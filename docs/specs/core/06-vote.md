# Vote

Vote 管理当前治理 Round 的 Proposal 投票和加速快照。Proposal 的创建与推举由 [Submit](05-submit.md) 管理，Round 边界见 [Phase](03-phase.md#治理-round)。

## 投票和加速快照

- 票数累加到 `votesNumByAccount[tokenAddress][round][memberId]`。同轮可多次投票，累计值不得超过本次从 `Stake.validGovVotes` 读取的 `maxVotesNum`。
- Vote 按 `tokenAddress + round + memberId` 保存已计入的加速快照，同时维护其总和 `stakedAmountOfVoters[tokenAddress][round]`。首次投票计入成员快照，再次投票仅补记当前质押高于已记值的正增量，不重复计入整份快照；未增加时不更新。
- 质押增加但没有后续投票，不更新 Vote 快照。Round 结束后成员快照与总量冻结；Mint 的 `memberBoost` 和 `totalBoost` 都从 Vote 读取，不能用 Stake 的最新余额替换其中一项。
- Vote 只保存每个 Proposal 的冻结票数和本轮有票 Proposal 列表，不维护达标 Proposal 总票数；Mint 在准备时按冻结结果计算该总数并缓存，不依赖行动验证结果。
- 批量投票或 Target 回调失败时，对应外层交易整体回滚。

## 接口

完整 ABI 见 [`ILOVE20Vote.sol`](../../../interfaces/core/ILOVE20Vote.sol)。它沿用旧 `LOVE20TKM/core/src/interfaces/ILOVE20Vote.sol` 的投票记录、增量机制、枚举和批量查询；BSC 将所有业务主体改为 `memberId`，并增加逐 Proposal 的不透明 KV 回调。

`isRoundEnded(0)` 返回 `false`。投票调用者须持有 `memberId`，Proposal 必须已在当前轮推举。`proposalIds` 与 `votes` 必须非空且等长；`keys` 与 `values` 可以同时传空外层数组，表示每笔回调均使用空 KV，若传入则必须与 `proposalIds` 等长且每笔内层数组等长；每笔票数必须为正。按输入顺序累加并回调，重复 Proposal ID 按多笔增量处理。批量没有协议固定长度上限，调用方可按区块 Gas 分批提交；测试记录首次失败规模。Core 不解析 KV 的业务内容。

## 事件与错误

事件与错误定义见 [`ILOVE20Vote.sol`](../../../interfaces/core/ILOVE20Vote.sol)。

错误沿用旧 Vote 的语义；`ProposalNotSubmitted` 对应旧 `ActionNotSubmitted` 的 Proposal 命名调整。未提交 Proposal、票数超额、零票、数组长度不合法或回调失败时，整笔投票回滚。

## Target 回调

回调接口见 [`IProposalTarget.sol`](../../../interfaces/core/IProposalTarget.sol)。

`votes` 为本次增量，不是累计票数；`bytes32` 键用于比较，`bytes` 值承载 ABI 编码。空 KV 仍必须触发回调。投票回调仅接受 Vote，Executor 仅接受 ActionTarget 转发；回调前先写入投票状态，失败则一并回滚。

Mint 的 `memberBoost` 对应 `stakedAmountOfVotersByMemberId`，`totalBoost` 对应 `stakedAmountOfVoters`。验收见 [Core 验收](09-testing.md)。
