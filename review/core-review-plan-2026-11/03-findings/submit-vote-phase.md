# Submit / Vote / Phase

三份合约分别是 339 / 293 / 162 行。本轮在这三个模块里只登记 2 条，另外把 `Submit` 的两条「已验证安全」写清楚——因为计划把它们当成重点怀疑对象。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| PHS-01 | Low | `sync` 把 `observed` 原样写成下一阶段长度，无上界；且采样点由调用者选 |
| VOT-01 | Info | 加速快照「只增不减」成立，但依赖 Stake 的两道锁，属跨合约假设 |

`Submit` 侧唯一的问题（提交门槛）已在 `stake.md` 的 `STK-01` 登记，根因在 `Stake` 的乘数，不在 `Submit` 的比较式。

---

## PHS-01 · `sync` 无上界，且采样点由调用者决定

| 字段 | 值 |
| --- | --- |
| 单元 | P1（`Phase:1-162`） |
| 文件:行 | `Phase:86-136`、`Phase:116-121`、`Phase:151-160` |
| 函数/变量 | `sync` / `observed` / `_recordNextSegment` |
| 类别 | 时间轴 / 边界 |
| 严重度 | Low |
| 攻击者画像 | 任何人（`sync` 无权限）；实际首个调用者通常是当轮首个提交者（`Submit:319-322`） |
| 前置条件 | 存在一个 `elapsedSeconds ≪ elapsedBlocks × 正常出块间隔` 的观测窗口 |
| 触发序列 | ①阶段 N 的首次 `sync` 记下 `(block, timestamp)`；②等到 `block − obs > phaseBlocks` 再调 `sync`；③`observed = elapsedBlocks × TARGET / elapsedSeconds`；④偏差超阈值 → `newPhaseBlocks = observed`（仅 `observed == 0` 时钳到 1）；⑤新段从 `phase+1` 起生效，无上界、无平滑 |
| 影响 | 阶段长度可被写成任意值（测试里 1001 倍）；此后所有依赖 phase 的时序（等待期、轮次、结算节奏）一起变形 |
| 设计依据 | 只钳下界（`observed == 0 ? 1`），不钳上界；`ADJUST_THRESHOLD` 只决定「是否调整」，不决定「调多少」 |
| 证据等级 | **E3**（机制）+ E1（触发条件） |
| 证据路径 | `test_phaseBlocksHasNoUpperClamp` |
| 置信度 | 高（机制确定）；触发需要时间戳异常 |
| 状态 | 已确认待修 |

### 机制

```solidity
uint256 observed = Math.mulDiv(elapsedBlocks, TARGET_SECONDS, elapsedSeconds);   // :116
uint256 difference = observed > phaseBlocks ? observed - phaseBlocks : phaseBlocks - observed;
uint256 deviation  = Math.mulDiv(difference, 1e18, phaseBlocks);                 // :118
if (deviation > ADJUST_THRESHOLD) {
    newPhaseBlocks = observed == 0 ? 1 : observed;                               // :120
    _recordNextSegment(phase, phaseBlocks, newPhaseBlocks);                      // :121
}
```

`observed` 是「达到 `TARGET_SECONDS` 需要多少块」，语义上就是出块速率。它没有任何上界，也没有「单次最多调整 N 倍」的限制。测试构造 1001 块 / 1 秒的窗口，`newPhaseBlocks = 1,001,000`，`phaseInfo(4).phaseBlocks` 读回同一个数字。

### 两个必须分开说的问题

**(a) 采样点由调用者选。** 每个阶段只有第一次 `sync` 会记录观测（`:90-93` 的 `_lastSyncPhase` 门），而这个调用可以由任何人发起。`Submit:319-322` 让「当轮首个提交者」顺手触发一次。于是观测点不是阶段边界，而是「当轮第一笔提交发生的时刻」。这不会让结果偏向任何一方（`elapsedBlocks` 与 `elapsedSeconds` 同源），但会让采样窗口抖动：提交越稀疏，窗口越长。

**(b) 这个阶段没有提交就没有观测。** `Phase` 自己不定期推进，`Vote`/`Mint`/`Stake` 都不调 `sync`。一个没有提案的社区不会产生观测，也就永远不会调整阶段长度——而 `Phase` 是全局的，所以「活跃社区的时间轴会被不活跃社区拖住」。

### 为什么只判 Low

要拿到「1 秒 / 1001 块」，需要 BSC 的区块时间戳在这个窗口内被压缩到 1 秒。这不是普通用户能做的事（时间戳由验证者写入），也不是靠交易排序能构造的（同一块内所有交易共享同一个时间戳）。所以：

- **机制层面**是缺陷：`observed` 没有上界，一次写入永久生效（新段无回退路径，只能靠下一次偏差再调）；
- **触发层面**需要一个异常窗口，普通攻击者拿不到。

如果 `TARGET_SECONDS` 被配成很小的值（例如 1），日常出块速率就会连续触发大幅调整，那时这条会升级为可用性问题——属于部署参数（`P-08`）。

### 不变量层面

设计承诺「轮长调整只影响未来」，这一点是**兑现的**：`_recordNextSegment` 把新段的起点算在 `phase+1` 的边界上（`:155-159`），`phaseAtBlock` 用 `nearest(startBlock)` 查找，所以 `currentPhase` 在同一笔交易内不会跳变，`Submit` 的「首个提交触发 sync」不会让自己那一笔跨轮。

---

## VOT-01 · 加速快照的单调性依赖 Stake 的两道锁

| 字段 | 值 |
| --- | --- |
| 单元 | V3（`Vote:212-293`） |
| 文件:行 | `Vote:232-245`、`Stake:191-193`、`Stake:286-288` |
| 函数/变量 | `_voterBoostByMemberId` / `_totalVoterBoostByRound` / `_hasUsedStakeRights` |
| 类别 | 跨合约假设 |
| 严重度 | Info |
| 攻击者画像 | 无（假设成立即无风险） |
| 前置条件 | Stake 在轮内禁止「已用票权者」减少 `validBoostShares` |
| 触发序列 | ①轮 R 首次投票 → `actualVoterBoost` 记入快照与总数；②之后 `stakeBoost` → 下一次投票补增量（`:240-244`）；③若 `actualVoterBoost < current`，快照**不下降**（`else if` 分支不存在） |
| 影响 | 快照只增不减，`Mint` 的 boost 分配因此不会因轮内减仓而失真 |
| 设计依据 | 用「单调快照 + 增量补齐」替代「每票重算」，省 gas 且防止轮末操纵 |
| 证据等级 | E1 + E3（性质） |
| 证据路径 | `test_mergeZeroesSourceVotesForAllLaterRounds`；证明见下 |
| 置信度 | 高 |
| 状态 | 已关闭 |

### 证明

轮内能让 `validBoostShares` 下降的只有两处：

1. `Stake.unstake:202-205` —— 前置 `_hasUsedStakeRights`（`Stake:191`）要求该成员本轮**没有**投票、**没有**提交，所以投票过的人无法解锁；
2. `Stake._mergeIntoTarget` 的 source 侧（`Stake:553-556` 通过 `_moveBoostHistory` 减 source）—— 前置同样在 `Stake:286-288`。

其余写入（`stakeBoost:161`、`_creditLiquidity:601`、merge 的 target 侧 `_moveBoostHistory:575`）都只增。因此「已投过票的成员」在本轮内的 `validBoostShares` 单调不减，`Vote:240` 的 `actualVoterBoost > currentVoterBoost` 判据足以补齐所有增量，`_totalVoterBoostByRound` 不会与 `Σ _voterBoostByMemberId` 分叉。

反向验证：把 `Stake:191` 或 `Stake:286` 去掉，`unstake` 就能在投票后把 `validBoostShares` 清零，此时 `Vote` 的快照仍然保留旧值——票权与加速权重不再对应，`Mint` 会按虚高的 boost 分配。所以 `Vote` 的正确性**是 Stake 借出去的**，这条依赖必须写进跨仓接口说明。

### 名册去重（顺带确认）

`Vote:248-267` 的两个 flag 容易被误读：

- `isFirstVoteByMember` 实为「**对该提案**的首票」（按 `[round][memberId][proposalId]` 取）；
- `isFirstVoteOnProposal` 是「对该提案的全局首票」。

`_votedProposalIds` 只在两者同时为真时 push，所以每个提案至多一行；`_voterIdsByProposalId` 只在「对该提案首票」时 push，所以每个投票人至多一行。`Mint` 的 `eligibleVoteAmount` 求和依赖前者，若允许重复 push 会重复计入——现状不会。命名有误导，属于可读性而非缺陷。

---

## `Submit` 的两条已验证结论

计划把这两条列为 S1/B3 的重点，结论都是「安全」，但安全的原因值得写下来。

### 1. 回调前状态已落盘

`_submitByProposalId`（`Submit:277-324`）的写入顺序：

```
:301  _submits[round].push(submitInfo)
:302-304  _submitInfoByProposalId[round][proposalId] = submitInfo
:305-307  _submitInfoBySubmitterId[round][memberId] = submitInfo
:312  emit ProposalSubmitted
:321  IPhase.sync()        ← 首个提交者才走
```

`_callProposalCreated`（`:326-331`）在 `submitNewProposal:116` 才被调用，此时三张表都写完。所以回调里做任何依赖「本轮是否已提交」的判断，看到的都是已提交状态。`Stake._hasUsedStakeRights`（`Stake:501`）正是读 `proposalIdBySubmitterId`，因此回调内 `mergeStake` 必然撞 `StakeRightsUsed`——测试 `test_mergeInsideProposalCreatedIsBlockedByWrittenState` 断言了完整的 revert data（含 `token/round/memberId` 三个参数），并在下一轮用同一个成员成功执行同一次 merge 作为对照，证明 revert 的原因是轮次记录而不是别的。

### 2. 每轮每人一次，三重唯一性齐备

| 维度 | 判据 | 错误 |
| --- | --- | --- |
| 同一提案 | `isSubmitted(round, proposalId)` | `ProposalAlreadySubmitted` |
| 同一成员 | `_submitInfoBySubmitterId[round][memberId].submitterId != 0` | `MemberAlreadySubmitted` |
| 每轮容量 | `_submits[round].length >= 1000` | `SubmitRoundFull` |

三者都在写之前检查，且 `memberId` 的归属由 modifier 保证。没有找到绕过路径。
