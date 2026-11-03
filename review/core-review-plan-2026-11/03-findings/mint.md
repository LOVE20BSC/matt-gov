# Mint

557 行、10,021 字节。`Mint` 不持资产，所有问题都是账本与分配。本轮最重要的结论是**两条否定**：越预留不成立、结算不会吃掉 Boost；以及一条肯定：奖池大小取决于 mint 时序。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| MNT-01 | **Medium** | 每轮奖池在「该轮第一次 mint」时按当时 `rewardAvailable()` 定，先 prepare 后一轮可压缩前一轮 |
| MNT-02 | Low | 批量 mint 全有全无，且每轮 prepare 可能遍历 1000 个提案 |
| MNT-03 | Low | 未 prepare 时 view 用实时 `available` 反推池子，与执行结果可以不一致 |
| MNT-04 | Info | `RewardBurned` 不减少供应；只重分类不销毁的路径没有事件 |
| MNT-05 | Info | `_updateLaunchCredit` 在额度发满时静默丢弃累计 credit |

---

## MNT-01 · 奖池大小由首个 mint 的时序决定

| 字段 | 值 |
| --- | --- |
| 单元 | M2（`Mint:100-184`） |
| 文件:行 | `Mint:104-130`、`Mint:145-149` |
| 函数/变量 | `_prepareRewardIfNeeded` / `_rewardReserved` / `rewardAvailable` |
| 类别 | 经济分配 / 时序 |
| 严重度 | **Medium** |
| 攻击者画像 | 该轮任一投票人（`voteReward > 0`，`mintGovReward` 的 `onlyMemberOwner`）；或该轮任一达标提案的 target（`mintProposalReward`） |
| 前置条件 | 至少两轮已结束且都未 prepare |
| 触发序列 | ①轮 N 与轮 N+1 都已结束，且攻击者在 N+1 有非零收益；②先对 N+1 调 `mintGovReward`（`_prepareRewardIfNeeded` 在 `:196` 先跑，mint 成功则 prepare 不被回滚）；③N+1 按当时的 `available` 预留 20%（gov 10% + proposal 10%）；④再对 N 调 mint；⑤N 只能拿到剩余配额的 10% |
| 影响 | 轮次之间的配额可被重排；实测把前一轮压到后一轮的 17/20。对「自己在 A 轮占比高、B 轮占比低」的成员，重排是纯获利 |
| 设计依据 | `_prepareRewardIfNeeded` 用「当前剩余可用量 × 固定比例」定义单轮池，而不是在轮次结束时锁定该轮额度 |
| 证据等级 | **E3** |
| 证据路径 | `test_rewardPoolDependsOnMintOrder` |
| 置信度 | 高（确定性，两种顺序各跑一遍） |
| 状态 | 已确认待修 |

### 实测

两轮各 1e19 票、gov/proposal 各 10%、无人 boost：

| 顺序 | `govReward(轮 1)` |
| --- | --- |
| 先 mint 轮 1，再 mint 轮 2（自然序） | `99,900,000,000,000,000,399,600,000` |
| 先 mint 轮 2，再 mint 轮 1 | `84,915,000,000,000,000,339,660,000` |

比值恰为 `17/20`：轮 2 先预留了 20%，其中 5% 的 boost 池因 `totalVoterBoost == 0` 被 `_burnCancelledPool` 退回 `available`（`Mint:135-138` + `:455`），所以净扣 15%。

### 为什么是缺陷而不是「先到先得」

`_prepareRewardIfNeeded` 的语义是「把这一轮的奖励额度定下来」。任何读代码的人都会预期它在该轮结束时就已经是确定值。实际是：

- 轮次结束后额度**仍然是浮动的**，浮动区间取决于之后有多少轮被提前预留；
- 没有任何顺序约束（没有 `round` 单调检查，`_isRewardPrepared` 只按轮去重）；
- 谁先 mint 谁决定，而 mint 是**按成员**的：任何在某一轮有票的人都能触发该轮的 prepare。

所以「同一轮对不同人给出不同池子」不是可能的，而是必然的——只要有人先动了后面的轮次。

### 破坏的不变量

> 轮 N 的奖励池在轮 N 结束时应当是确定的，且与之后任何人的 mint 顺序无关。

### 约束与失效边界

| 项 | 内容 |
| --- | --- |
| 参数约束 | `GOV_RATIO + PROPOSAL_RATIO` 越小，单次预留越少，重排的绝对影响越小，但相对比例（`1/(1−ratio)`）不变 |
| 失效边界 | 只有「多轮同时未 prepare」时才有重排空间；如果每轮结束都有人及时 mint，窗口为零 |
| 损失承担者 | 被后置 prepare 的那一轮的投票者与提案 target。他们在该轮的实际收益下降，且无法通过自己的行为挽回（只能抢在别人前面） |

---

## MNT-02 · 批量 mint 的全有全无与 gas 上界

| 字段 | 值 |
| --- | --- |
| 单元 | M3（`Mint:186-262` + `:500-557`） |
| 文件:行 | `Mint:241-262`、`Mint:288-299`、`Mint:518-520` |
| 函数/变量 | `mintGovRewards` / `_calculateEligibleProposalVoteAmount` |
| 类别 | 可用性 |
| 严重度 | Low |
| 攻击者画像 | 无需攻击者；加害者是自己的调用参数 |
| 前置条件 | ①批量里有一轮 `voteReward + boostReward + burnReward == 0`；或②多轮各自有大量提案 |
| 触发序列 | ①`mintGovRewards(token, [r1..rN], id, to)`；②第 k 轮三项和为 0 → `MemberRewardUnavailable`（`:518-520`）；③整批回滚，前 k−1 轮已成功的 mint 一并撤销 |
| 影响 | 批量入口对「有一轮无收益」的成员不可用；每轮 `prepare` 的循环成本随提案数线性增长（1000 提案实测 6.9M gas，见 `test/stress/ProposalDoS.t.sol`） |
| 设计依据 | 批量入口没有「跳过空轮」的语义，也没有分段上限 |
| 证据等级 | E2 |
| 证据路径 | `testPrepare1000Proposals`（基线 6,937,608 gas）；`Mint:256-259` 的循环无 try/catch |
| 置信度 | 高 |
| 状态 | 已确认待修 |

批量入口的单轮函数（`mintGovReward`）完全可用，所以这是「工具不好用」而不是「功能不可用」。真正需要记住的是 gas 量级：一轮 prepare 在最坏情况下要遍历本轮所有被投票过的提案（上限 `SUBMIT_ROUND_LIMIT = 1000`，`Submit:16`），每项一次外部调用。批量跨 5 轮就可能撞上 BSC 的单块上限。

---

## MNT-03 · 未 prepare 时 view 反推池子

| 字段 | 值 |
| --- | --- |
| 单元 | M4（`Mint:264-354`） |
| 文件:行 | `Mint:326-333`、`Mint:380-385`、`Mint:345-354`、`Mint:413-427` |
| 函数/变量 | `_proposalRewardCalculation`、`_govRewardCalculation`、`proposalRewardByProposalId`、`govRewardByMemberId` |
| 类别 | 读面/写面不一致 |
| 严重度 | Low |
| 攻击者画像 | 无需攻击者；误导 UI 与第三方集成 |
| 前置条件 | 目标轮尚未 prepare |
| 触发序列 | ①轮 N 已结束但无人 mint；②调 `proposalRewardByProposalId(token, N, id)`；③返回值按「此刻 prepare 会得到的池子」算；④若之后有人先 prepare 了 N+1，实际可 mint 量更小 |
| 影响 | view 给出的是条件值，调用方无从得知；集成方会把它当成确定值报价 |
| 设计依据 | view 不复用 `_prepareRewardIfNeeded`（它要写状态），于是复制了一份「不写状态」的分支 |
| 证据等级 | E1 |
| 证据路径 | `Mint:329-333` 与 `:196`（执行路径必然先 prepare） |
| 置信度 | 高 |
| 状态 | 已确认待修 |

两份分支（`isRewardPrepared ? 存储值 : 实时 available`）在**数学上**是一致的，只在「何时 prepare」这一点上分叉；而这恰好是 MNT-01 的变量。所以 MNT-03 是 MNT-01 的读面投影：把 MNT-01 修掉（轮次结束时锁定额度）之后，这个分支自然消失。

---

## MNT-04 · `RewardBurned` 不减少供应

| 字段 | 值 |
| --- | --- |
| 单元 | M2 / M6 |
| 文件:行 | `Mint:163-173`、`Mint:526-543`、`Mint:458-460` |
| 函数/变量 | `_burnCancelledPool`、`_rewardBurned`、`reservedAvailable` |
| 类别 | 事件语义 / 可观测性 |
| 严重度 | Info |
| 攻击者画像 | 无（数据消费者） |
| 前置条件 | 任一轮 `totalVoterBoost == 0` 或 `eligibleVoteAmount == 0` |
| 触发序列 | ①轮 N prepare 时 boost 池无人认领；②`_rewardBurned += boostPool` 并发 `RewardBurned`；③代币从未被铸造，`totalSupply` 不变；④同一笔额度经 `reservedAvailable` 回流 `rewardAvailable`，下一轮可再次预留 |
| 影响 | 把 `RewardBurned` 当「供应减少」聚合的索引器会算错，误差 = Σ 被取消额度 |
| 设计依据 | `reservedAvailable = R − M − B` 的三项口径本身是自洽的：`B` 增即「该额度不再可铸」 |
| 证据等级 | E1 |
| 证据路径 | `Mint:459`、`Mint:165`、`Mint:455` |
| 置信度 | 高 |
| 状态 | 已关闭（记录） |

`RewardBurned` 的真实含义是「本轮的这部分额度作废」，不是「烧掉了代币」。同一件事在 `Mint:528`（`BoostOverflow`）里又是另一种含义——那一笔确实是从待铸额度里划掉、永不铸造，但同样没有链上销毁动作。两种 reason 共享同一个事件名，语义却分别是「配额作废」与「配额转销毁」，靠 `reason` 字段区分，容易误读。

---

## MNT-05 · 额度发满后静默丢弃累计 credit

| 字段 | 值 |
| --- | --- |
| 单元 | M6（`Mint:452-498`） |
| 文件:行 | `Mint:469-473`、`Mint:480-482`、`Mint:485` |
| 函数/变量 | `_updateLaunchCredit` / `_launchCredit` |
| 类别 | 账本边界 |
| 严重度 | Info |
| 攻击者画像 | 无 |
| 前置条件 | `issuedLaunchCount(token) >= MAX_LAUNCH_COUNT` |
| 触发序列 | ①该代币的发射额度已发满；②之后每次 `mintGovReward` 仍会铸币，但 `_updateLaunchCredit` 在 `:471` 直接 return；③`_launchCredit[memberId]` 不再累加 |
| 影响 | 无实际损失：额度已满，credit 无法再兑换成发射次数；但成员的历史累计值会停在旧数，与「他后来还铸了很多」不符 |
| 设计依据 | 早退是为了省 gas，逻辑上等价 |
| 证据等级 | E1 |
| 证据路径 | `Mint:469-473` |
| 置信度 | 高 |
| 状态 | 已关闭 |

`MAX_LAUNCH_COUNT` 是 `Launch` 的不可变配置，不存在「以后提高上限」的路径，所以这段 credit 永远没有兑现机会，丢弃它不构成损失。

---

## 已验证 · M4 越预留不成立

计划把这条列为「最高优先项」。结论是**不成立**，理由是一次集合恒等，不需要读测试。

`_calculateEligibleProposalVoteAmount`（`Mint:264-302`）的求和域是

```
P = { p | p ∈ votedProposalIds(round) , voteAmount(p) > 0 , voteAmount(p) >= minVoteAmount }
eligibleVoteAmount = Σ_{p∈P} voteAmount(p)
```

`_proposalRewardCalculation`（`Mint:304-343`）对单个提案的分配是

```
amount(p) = proposalRewardAmount · voteAmount(p) / eligibleVoteAmount ,  仅当 p 满足同一判据
```

两者用的是**同一个集合**、**同一个阈值**、**同一份已冻结的 vote 数据**，所以

```
Σ_{p∈P} amount(p) = proposalRewardAmount · (Σ_{p∈P} voteAmount(p)) / eligibleVoteAmount = proposalRewardAmount
```

逐项 floor 只会让它更小，不会更大。因此 `:340` 的分母不可能小于分子之和，`reservedAvailable` 不会因提案奖励下溢。

集合恒等依赖一个前提：`votedProposalIds` 里每个提案至多出现一次。这在 `Vote:261-267` 得到保证——只有「该成员对该提案的首票」与「该提案的首票」同时成立时才 push 提案 ID，而提案首票必然也是该成员对该提案的首票。第二轮投票时 `isFirstVoteOnProposal` 已为 false。

`_minProposalVoteAmount` 用 `Ceil`（`Mint:449`），两边同源，不会一边算 5 一边算 6。

治理奖励侧同理：`Σ memberVote = totalVoteAmount`（`Vote:256-258` 每次投票同时累加两边），`voteReward ≤ votePool`、`boostReward ≤ boostPool`、`burnReward = theoretical − boostReward`，逐成员三项和 ≤ `govReward`，故 `Σ(mint + burn) ≤ govReward`。
