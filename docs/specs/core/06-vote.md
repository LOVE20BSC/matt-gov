# Vote

Vote 管理当前治理 Round 的 Proposal 投票和加速快照。Proposal 的创建与推举由 [Submit](05-submit.md) 管理，Round 边界见 [Phase](03-phase.md#治理-round)。

## 投票和加速快照

- 票数累加到 `votesNumByMemberId[tokenAddress][round][memberId]`。同轮可多次投票，累计值不得超过本次从 `Stake.validGovVotes` 读取的 `maxVotesNum`。
- Vote 按 `tokenAddress + round + memberId` 保存已计入的加速快照，同时维护其总和 `stakedAmountOfVoters[tokenAddress][round]`。首次投票计入成员快照，再次投票仅补记当前质押高于已记值的正增量，不重复计入整份快照；未增加时不更新。
- 质押增加但没有后续投票，不更新 Vote 快照。Round 结束后成员快照与总量冻结；Mint 的 `memberBoost` 和 `totalBoost` 都从 Vote 读取，不能用 Stake 的最新余额替换其中一项。
- Vote 只保存每个 Proposal 的冻结票数和本轮有票 Proposal 列表，不维护达标 Proposal 总票数；Mint 在准备时按冻结结果计算该总数并缓存，不依赖行动验证结果。
- 批量投票或 Target 回调失败时，对应外层交易整体回滚。

## 读取来源

| 本合约需要的值 | 来源 |
| --- | --- |
| 当前 Round | `IPhase(phaseAddress).currentPhase()` |
| 成员身份 | `IMemberNFT(memberNFTAddress).ownerOf(memberId)` |
| 本轮票上限 | `IStake(stakeAddress).validGovVotes(tokenAddress, memberId)` |
| 加速快照 | `IStake(stakeAddress).cumulatedBoostShares(tokenAddress, round, memberId)` |
| 推举状态 | `ISubmit(submitAddress).isSubmitted(tokenAddress, round, proposalId)` |
| 回调目标与模式 | `ISubmit(submitAddress).proposalTarget(tokenAddress, proposalId)` |

票上限每笔投票只读一次，不随批量长度重复读取；快照与推举状态逐笔读取。快照只在当前 Round 读取，未来 Round 由 Stake 回滚 `InvalidPhase(round)`，而 Vote 本身只在当前 Round 投票。

## 校验顺序

`vote` 的校验与写入顺序，任一步回滚整笔：

1. **持有权**：`IMemberNFT.ownerOf(memberId) == msg.sender`（`NotMemberOwner(memberId)`）；`memberId` 不存在时由 `ownerOf` 抛出 MemberNFT 的错误
2. **资格**：`canVote(tokenAddress, memberId)`，即票上限大于零（`CannotVote()`）
3. **长度**：`proposalIds` 非空且与 `votes` 等长（`InvalidTargetDataLength()`）；`targetData` 传入时必须与 `proposalIds` 等长，传空外层数组表示每笔回调都使用空 Target Data
4. 取当前 Round 与票上限，随后逐 Proposal 处理：
   1. **推举状态**：本轮已推举（`ProposalNotSubmitted()`）
   2. **票数**：本次增量为正（`VotesMustBeGreaterThanZero()`）
   3. 记录加速快照：首投记全量，后续只补正增量
   4. 累加票数，维护本轮有票 Proposal 与投票者集合
   5. **额度**：成员本轮累计票数不超过票上限（`NotEnoughVotesLeft()`）
   6. 发出 `Voted` 事件
   7. `Callback` 且 `target` 非零时回调 `IProposalTarget.onProposalVoted`，失败回滚整笔

额度按整批累计判定：同一批里先投的票数计入后投的判定基准，超过上限的那笔回滚整批。

`init` 校验顺序：先看初始化状态（`AlreadyInitialized()`），再逐个校验 `phaseAddress`、`stakeAddress`、`submitAddress`、`memberNFTAddress` 非零（`InvalidAddress()`）。

## 接口

完整 ABI 见 [`IVote.sol`](../../../interfaces/core/IVote.sol)。它沿用旧 `LOVE20TKM/core/src/interfaces/ILOVE20Vote.sol` 的投票记录、增量机制和批量查询；BSC 将所有业务主体改为 `memberId`，并增加逐 Proposal 的不透明 Target Data 回调。

旧接口的三对 `*Count`/`AtIndex` 枚举（共 6 个函数）改为三个分页入口：`votedProposalIds`（本轮有票 Proposal）、`votedProposalIdsByMemberId`（成员本轮投过的 Proposal）、`voterIdsByProposalId`（Proposal 的投票者）。成员本轮所投 Proposal 的票数按页随 id 一起返回（`votesNumsByMemberId`），按指定 id 批量取票数走 `votesNumsByMemberIdByProposalIds`。

`isRoundEnded(0)` 返回 `false`。投票调用者须持有 `memberId`，Proposal 必须已在当前轮推举。`proposalIds` 与 `votes` 必须非空且等长；`targetData` 可以传空外层数组，表示每笔回调均使用空 Target Data，若传入则必须与 `proposalIds` 等长；每笔票数必须为正。Proposal 为 `NoCallback` 时忽略对应 Target Data，不做额外校验；Proposal 为 `Callback` 时按输入顺序原样透传。批量没有协议固定长度上限，调用方可按区块 Gas 分批提交；测试记录首次失败规模。Core 不解析 Target Data 的业务内容。

## 事件与错误

事件与错误定义见 [`IVote.sol`](../../../interfaces/core/IVote.sol)。

错误沿用旧 Vote 的语义；`ProposalNotSubmitted` 对应旧 `ActionNotSubmitted` 的 Proposal 命名调整。未提交 Proposal、票数超额、零票、`targetData` 外层长度不合法或回调失败时，整笔投票回滚；长度错误使用 `InvalidTargetDataLength()`。

## Target 回调

回调接口见 [`IProposalTarget.sol`](../../../interfaces/core/IProposalTarget.sol)。

`votes` 为本次增量，不是累计票数；Target Data 为不透明 `bytes[]`，由 Target 解释。空 Target Data 仍必须触发回调。投票回调仅接受 Vote，Executor 仅接受 ActionTarget 转发；回调前先写入投票状态，失败则一并回滚。

Mint 的 `memberBoost` 对应 `stakedAmountOfVotersByMemberId`，`totalBoost` 对应 `stakedAmountOfVoters`。验收见 [Core 验收](09-testing.md)。
