# Vote · 状态变量变更审查

> `core/src/Vote.sol`，301 行，`core@0466d67`。
> Vote 保存「本轮每人投了多少、每个提案收了多少、谁投过谁」以及**加速快照**；Mint 的治理奖励分母直接取自这里，所以这九个映射是资金公式的输入。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1-5 | `initialized` / `STAKE_ADDRESS` / `SUBMIT_ADDRESS` / `PHASE_ADDRESS` / `MEMBER_NFT_ADDRESS` | `bool` + 4 `address` | 一次性开关与依赖 | `init:55-59` |
| 6 | `_totalVoteAmountByRound` | `mapping(address => mapping(uint256 => uint256))` | 每轮总票数 | `_vote:256` |
| 7 | `_voteAmountByProposalId` | `…[round][proposalId]` | 提案得票 | `_vote:257` |
| 8 | `_voteAmountByMemberId` | `…[round][memberId]` | 成员累计投票 | `_vote:258` |
| 9 | `_voteAmountByMemberIdByProposalId` | 四层映射 | 成员对提案的累计 | `_vote:259` |
| 10 | `_votedProposalIds` | `…[round] → uint256[]` | 本轮**有票**的提案（去重、按首次得票序） | `_vote:263` |
| 11 | `_votedProposalIdsByMemberId` | `…[round][memberId] → uint256[]` | 成员本轮投过的提案（去重） | `_vote:265` |
| 12 | `_voterIdsByProposalId` | `…[round][proposalId] → uint256[]` | 提案的投票者（去重） | `_vote:266` |
| 13 | `_voterBoostByMemberId` | `…[round][memberId] → uint256` | **加速快照**：本轮已计入的成员加速份额 | `_vote:238`、`:242` |
| 14 | `_totalVoterBoostByRound` | `…[round] → uint256` | 本轮加速快照总和 | `_vote:239`、`:243` |

`PHASE_ADDRESS` 只用于 `currentRound()`；`round` 在整笔交易内只读一次（`:85`），因此同一批的九个映射写到同一轮。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:46-60`）

`initialized = true` 写在四个地址之前（`:55`），中间无外部调用。四个地址**无零地址/代码校验**；任何一个指错，后果是：

| 错配 | 后果 |
| --- | --- |
| `MEMBER_NFT_ADDRESS` | `onlyMemberOwner` 直接打向攻击者合约 → 任何人可代表任意 `memberId` 投票 |
| `SUBMIT_ADDRESS` | `isSubmitted` / `proposalTarget` 读到错误命题 → 要么全部回滚，要么按攻击者的白名单投票 |
| `STAKE_ADDRESS` | 票权上限与加速快照全部来自错误账本 |
| `PHASE_ADDRESS` | 轮次错位，跨轮重复投票 |

`init` 无调用者限制且只能成功一次。与 `MemberNFT.init` 不同，这里的抢跑不会让部署整体回滚（`Launch.init` 不调用 `Vote.init`），而是**部署脚本的 `Vote.init` 静默失败**（若脚本不检查返回值/回执状态）或整笔回滚（若检查）。无论哪种，正确接线都是部署期一次性假设。

### 2.2 `_vote` 的写入序列（`:212-276`）

| 步 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:221-224` | `voteAmount == 0` → `ZeroVoteAmount` | **零票在一切外部读取与快照写入之前被拒**，不会留下「投了 0 票但进名册」的记录 |
| 2 | `:226` | `ISubmit.proposalTarget(token, proposalId)` | 外部只读；先取 target 与回调模式，供第 11 步使用 |
| 3 | `:227-230` | `ISubmit.isSubmitted(token, round, proposalId)` | 外部只读；本轮未推举 → `ProposalNotSubmitted` |
| 4 | `:233-235` | 读 `_voterBoostByMemberId[t][r][m]` 与 `Stake.validBoostShares(t,r,m)` | 外部只读 |
| 5 | `:237-244` | 若快照为 0：写 `= actual`、`total += actual`；若 `actual > 快照`：写 `= actual`、`total += (actual − 快照)` | **只补正增量，不下调** |
| 6 | `:248-249` | `isFirstVoteByMember = member×proposal == 0`；`isFirstVoteOnProposal = proposal == 0` | 两个「首次」都基于**写前**的值 |
| 7 | `:250-254` | `memberVoteAfter = 成员累计 + voteAmount`；`> voteLimit` → `VoteLimitExceeded` | `voteLimit` 由 `vote()` 在循环外读一次（`:86`） |
| 8 | `:256-259` | 四个金额累加 | 总、提案、成员、成员×提案 |
| 9 | `:261-267` | 三张名册按条件 push | 见 §3 的 V3-V5 |
| 10 | `:270` | `_emitVoteCast`（`VoteCast` 含 `voteAmount`、`voterBoost`、`totalVoterBoost`） | 读的是写后值 |
| 11 | `:272-275` | `TargetMode.Callback && target != 0` → `onProposalVoted` | 状态已写完，重入安全 |

第 5 步排在第 7 步之前：超限回滚时快照一并撤销，不存在「票没投进去、快照却涨了」的中间态。

### 2.3 三张名册的 push 条件（`:261-267`）

```solidity
if (isFirstVoteByMember) {                 // 该成员对该提案是首次
    if (isFirstVoteOnProposal) {           // 该提案本轮首次得票
        _votedProposalIds[t][r].push(proposalId);
    }
    _votedProposalIdsByMemberId[t][r][m].push(proposalId);
    _voterIdsByProposalId[t][r][p].push(memberId);
}
```

三层条件容易误读，逐一证明其正确性：

| 断言 | 证明 |
| --- | --- |
| `_votedProposalIds` 中每个提案恰出现一次 | 某提案的**第一票**必然满足 `proposal == 0` **且** `member×proposal == 0`（该成员此前对该提案的贡献也是 0），所以第一次 push 一定发生；此后 `proposal > 0`，不再进入 |
| `_votedProposalIdsByMemberId` 每个提案恰一次 | 第一次投票时 `member×proposal == 0`，push；此后该值 > 0 |
| `_voterIdsByProposalId` 每个成员恰一次 | 同上，按提案维度 |

即：**`isFirstVoteByMember` 的真实语义是「该成员对该提案首次」，不是「该成员本轮首次」**。名字误导，逻辑正确（`VOT-02`）。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| V1 | `total == Σ_p 提案票 == Σ_m 成员票 == Σ_m Σ_p 成员×提案` | ✅ | 四个金额在同一笔里按同一个 `voteAmount` 增加（`:256-259`） |
| V2 | `提案票(p) == Σ_m 成员×提案(m,p)` | ✅ | 同上 |
| V3 | `_votedProposalIds` 无重复、无遗漏 | ✅ | §2.3 |
| V4 | `_votedProposalIdsByMemberId[m]` 无重复、无遗漏 | ✅ | §2.3 |
| V5 | `_voterIdsByProposalId[p]` 无重复、无遗漏 | ✅ | §2.3 |
| V6 | `totalVoterBoost == Σ_m 快照(m)` | ✅ | 快照与总和在同一分支里成对增加（`:238-239`、`:242-243`） |
| V7 | 快照对 `(t,r,m)` **单调不减** | ✅ | 只在「快照为 0」或「实际更高」时写 |
| V8 | 成员本轮累计 `<= voteLimit` | ✅ | 第 6 步逐笔判定，写前比较 |
| V9 | 名册里的成员/提案一定先有 `> 0` 的票 | ✅ | push 与金额累加同笔，且零票在第 2 步被拒 |

V7 的安全性依赖 Stake：成员投票后本轮不能再 `unstake`（`Stake._hasUsedStakeRights` 读 `voteAmountByMemberId != 0`），所以「投票 → 撤质押 → 快照仍高」不可达。这是既有审查 `VOT-01` 的结论，本卷复核成立。

## 4. 发现

### VOT-02 · 承载 Mint 分母的快照带着一句错注释

| 字段 | 值 |
| --- | --- |
| 位置 | `:40-41`（注释与声明）、`:237-244`（实现） |
| 级别 | Info |
| 证据 | E1 |

```solidity
// tokenAddress => round => memberId => boostShares at first vote in round
mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _voterBoostByMemberId;
```

注释说「本轮首次投票时的 boost」，但实现（以及规格 `06-vote.md:8`）是「首次计入全量，之后只补当前质押高于已记值的正增量」。也就是说它是**本轮已计入的最大快照**，不是首投快照。差别在两种场景下会体现：

| 场景 | 首投快照语义 | 当前实现 |
| --- | --- | --- |
| 首投时 boost=10，之后 `stakeBoost` 到 20 并再投一票 | 仍记 10 | 记 20，总和无重复地 +10 |
| 首投时 boost=0，之后 stakeBoost 到 20 再投 | 记 0（永远不涨） | 记 20 |

Mint 的 `boostReward = boostPool × voterBoost / totalVoterBoost`（`Mint:411-419`）用的就是这个值。注释错不会改变链上结果，但会让审计者/索引器按错误语义去反推 `totalVoterBoost`。建议改为「本轮已计入的加速份额（只增）」。

同一处还有命名问题：`:248` 的 `isFirstVoteByMember` 实际是「该成员对该提案首次」，`isFirstVoteOnProposal` 才是「该提案首次」。三张名册的去重逻辑全靠这两个布尔，名字读错就会把 `push` 条件改错。建议重命名为 `isFirstVoteByMemberOnProposal`。

### VOT-03 · 批次长度无协议上限

| 字段 | 值 |
| --- | --- |
| 位置 | `:69-100`（`vote` 的入参）、`:93-99`（循环） |
| 级别 | Info |
| 证据 | E1 |

`proposalIds.length` 没有任何上限，每个元素会做 3 次外部只读调用（`isSubmitted` / `validBoostShares` / `proposalTarget`），外加最多 1 次 Target 回调。调用者可以自选批次大小，超限只是自己的 out-of-gas 回滚（可减小重试），不会把成本转嫁给别人；规格 `06-vote.md:54` 明确「没有协议固定长度上限」。记录在这里是为了说明：**这条路径的 gas 上界由调用者控制，因此任何「按票数计费/补贴」的外部机制都不能假设单笔有个固定上限**。

## 5. 已核对为正确的点

- `voteLimit` 在循环外读一次（`:86`），循环内不重复读；同一批的累计判定基准固定，不会因为中途 `stakeBoost` 而放宽。
- 零票在写任何状态之前被拒（`:221-224`），因此名册里不会出现「投了 0 票」的成员。
- 超限判定在四个累加之前（`:250-254`），失败整笔撤销。
- `TargetMode.NoCallback` 或 `target == 0` 时不回调（`:272`）；`NoCallback` 下 `targetData` 被忽略，与规格一致。
- 回调发生在所有写入与事件之后，回调内再投票只会命中「非首次」分支，不会重复进名册。
- `isRoundEnded(0)` 返回 false（`:106-108`），与规格一致。
- 所有查询入口都不回滚：未知 `token`/`round` 返回 0 或空数组。

## 6. 覆盖缺口

- 未验证「同一成员先投 A 再投 B，B 的首次得票由该成员产生」时三张名册的最终内容；证明见 §2.3，未落测试。
- 未复核 `totalVoterBoost` 在成员 boost 减少（`unstake` 后重新质押到更低 P）场景下的行为；该场景被 `_hasUsedStakeRights` 挡住，属跨合约假设。

行号基准 `0466d67`。
