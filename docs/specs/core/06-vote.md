# Vote

Vote 管理当前治理 Round 的 Proposal 投票和加速快照。Proposal 的创建与推举由 [Submit](05-submit.md) 管理，Round 边界见 [Phase](03-phase.md#治理-round)。

## 投票和加速快照

- 票数累加到 `_voteAmountByMemberId[tokenAddress][round][memberId]`。同轮可多次投票，累计值不得超过本次从 `Stake.validGovVotes` 读取的 `maxVoteAmount`。
- Vote 按 `tokenAddress + round + memberId` 保存已计入的加速快照，同时维护其总和 `_totalVoterBoostByRound[tokenAddress][round]`。首次投票计入成员快照，再次投票仅补记当前质押高于已记值的正增量，不重复计入整份快照；未增加时不更新。
- 质押增加但没有后续投票，不更新 Vote 快照。Round 结束后成员快照与总量冻结；Mint 的 `voterBoost` 和 `totalVoterBoost` 都从 Vote 读取，不能用 Stake 的最新余额替换其中一项。
- Vote 只保存每个 Proposal 的冻结票数和本轮有票 Proposal 列表，不维护达标 Proposal 总票数；Mint 在准备时按冻结结果计算该总数并缓存，不依赖行动验证结果。
- 批量投票或 Target 回调失败时，对应外层交易整体回滚。

## 读取来源

| 本合约需要的值 | 来源 |
| --- | --- |
| 当前 Round | `IPhase(PHASE_ADDRESS).currentPhase()` |
| 成员身份 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId)` |
| 本轮票上限 | `IStake(STAKE_ADDRESS).validGovVotes(tokenAddress, currentRound, memberId)` |
| 加速快照 | `IStake(STAKE_ADDRESS).validBoostShares(tokenAddress, round, memberId)` |
| 推举状态 | `ISubmit(SUBMIT_ADDRESS).isSubmitted(tokenAddress, round, proposalId)` |
| 回调目标与模式 | `ISubmit(SUBMIT_ADDRESS).proposalTarget(tokenAddress, proposalId)` |

票上限每笔投票只读一次，不随批量长度重复读取；快照与推举状态逐笔读取。快照只在当前 Round 读取，未来 Round 由 Stake 回滚 `RoundNotStarted(requestedRound, currentRound)`，而 Vote 本身只在当前 Round 投票。

## 校验顺序

`vote` 的校验与写入顺序，任一步回滚整笔：

1. **持有权**：`IMemberNFT.ownerOf(memberId) == msg.sender`（`NotMemberOwner(memberId)`）；`memberId` 不存在时由 `ownerOf` 抛出 `ERC721NonexistentToken(memberId)`
2. **形状**：`proposalIds` 非空（`ProposalIdsEmpty()`）；`voteAmounts` 与 `proposalIds` 等长（`ProposalVoteAmountsLengthMismatch(proposalIdsLength, voteAmountsLength)`）；`targetData` 传入时必须与 `proposalIds` 等长（`TargetDataLengthMismatch(proposalIdsLength, targetDataLength)`），传空外层数组表示每笔回调都使用空 Target Data
3. **资格**：取当前 Round 与票上限，即 `maxVoteAmount(tokenAddress, memberId)`（`canVote` 同源）；票上限为零回 `NoVotingPower(tokenAddress, memberId)`。该读数供整批复用，不重复读取
4. 逐 Proposal 处理（复用第 3 步的 Round 与票上限）：
   1. **票数**：本次增量为正（`ZeroVoteAmount(tokenAddress, round, proposalId)`）
   2. **存在性与回调目标**：读 `Submit.proposalTarget(tokenAddress, proposalId)`；未分配 ID 由 Submit 透传 `ProposalNotFound(tokenAddress, proposalId)`。返回的 `target` / `targetMode` 复用到本笔回调，不再二次读取
   3. **推举状态**：本轮已推举（`ProposalNotSubmitted(tokenAddress, round, proposalId)`）
   4. 记录加速快照：首投记全量，后续只补正增量
   5. **额度**：先算加上本笔后的成员累计票数，超过票上限回滚（`VoteLimitExceeded(tokenAddress, round, memberId, cumulativeVoteAmount, maxVoteAmount)`，`cumulativeVoteAmount` 为加上本笔后的成员累计票数）
   6. 累加票数，维护本轮有票 Proposal 与投票者集合
   7. 发出 `VoteCast` 事件（含本次 `voteAmount`、该成员本轮后置累计 `voteAmountTotal`、该轮后置总量 `totalVoteAmount`，以及成员加速快照 `voterBoost` 与全局 `totalVoterBoost`）
   8. `Callback` 且 `target` 非零时回调 `IProposalTarget.onProposalVoted`，失败回滚整笔

额度按整批累计判定：同一批里先投的票数计入后投的判定基准，超过上限的那笔回滚整批。

上述回滚都发生在 `voteAmounts` 循环内，载荷携带逐笔上下文的错误因此能定位到具体 Proposal 或累计值，而不是只报一个批次级错误。

`init` 只防重复初始化（`AlreadyInitialized()`）并保存入参；`PHASE_ADDRESS`、`STAKE_ADDRESS`、`SUBMIT_ADDRESS`、`MEMBER_NFT_ADDRESS` 有代码由 DeployCore 部署后校验、21_check 独立复核。

## 接口

完整 ABI 见 [`IVote.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IVote.sol)。它沿用旧 `LOVE20TKM/core/src/interfaces/ILOVE20Vote.sol` 的投票记录、增量机制和批量查询；BSC 将所有业务主体改为 `memberId`，并增加逐 Proposal 的不透明 Target Data 回调。

旧接口的三对 `*Count`/`AtIndex` 枚举（共 6 个函数）改为三个分页入口：`votedProposalIds`（本轮有票 Proposal）、`votedProposalIdsByMemberId`（成员本轮投过的 Proposal，票数随 id 一起返回）、`voterIdsByProposalId`（Proposal 的投票者）。按指定 id 批量取票数走 `voteAmountsByMemberIdByProposalIds`。

`isRoundEnded(0)` 返回 `false`。投票调用者须持有 `memberId`，Proposal 必须已在当前轮推举。`proposalIds` 与 `voteAmounts` 必须非空且等长；`targetData` 可以传空外层数组，表示每笔回调均使用空 Target Data，若传入则必须与 `proposalIds` 等长；每笔票数必须为正。Proposal 为 `NoCallback` 时忽略对应 Target Data，不做额外校验；Proposal 为 `Callback` 时按输入顺序原样透传。批量没有协议固定长度上限，调用方可按区块 Gas 分批提交；测试记录首次失败规模。Core 不解析 Target Data 的业务内容。

## 事件与错误

事件与错误定义见 [`IVote.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IVote.sol)。

`VoteCast` 的载荷分三组：本次增量 `voteAmount`；票数后置锚点 `voteAmountTotal`（该成员本轮累计，等于 `voteAmountByMemberId`）与 `totalVoteAmount`（该轮总量，等于 `totalVoteAmount`）；加速快照 `voterBoost`（成员本轮已记值）与 `totalVoterBoost`（本轮合计）。两个票数锚点让单条日志即可对账，无需重放整轮投票。

| 错误 | 触发条件 |
| --- | --- |
| `AlreadyInitialized()` | 重复初始化 |
| `NotMemberOwner(uint256 memberId)` | `ownerOf(memberId) != msg.sender`；`memberId` 不存在时由 MemberNFT 回滚 `ERC721NonexistentToken` |
| `NoVotingPower(address tokenAddress, uint256 memberId)` | 本轮票上限为零 |
| `ProposalIdsEmpty()` | `proposalIds` 为空 |
| `ProposalVoteAmountsLengthMismatch(uint256 proposalIdsLength, uint256 voteAmountsLength)` | `voteAmounts` 与 `proposalIds` 不等长 |
| `TargetDataLengthMismatch(uint256 proposalIdsLength, uint256 targetDataLength)` | 传入的 `targetData` 外层数组与 `proposalIds` 不等长 |
| `ProposalNotSubmitted(address tokenAddress, uint256 round, uint256 proposalId)` | 该 Proposal 已分配但本轮未推举 |
| `ZeroVoteAmount(address tokenAddress, uint256 round, uint256 proposalId)` | 该笔票数为零 |
| `VoteLimitExceeded(address tokenAddress, uint256 round, uint256 memberId, uint256 cumulativeVoteAmount, uint256 maxVoteAmount)` | 成员本轮累计票数超过票上限；`cumulativeVoteAmount` 为加上该笔后的累计值 |

未提交 Proposal、票数超额、零票、批次长度不合法或回调失败时，整笔投票回滚。

### 透传来源

| 来源 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `ISubmit.proposalTarget` | `ProposalNotFound(address,uint256)` | 每笔投票的存在性读取；Vote 不重复声明 |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner`；`memberId` 不存在时先于 `NotMemberOwner` |
| `IProposalTarget.onProposalVoted` | 任意 revert data | 第三方回调；失败整笔回滚 |
| `IStake.validGovVotes`、`validBoostShares` | 依赖自身错误 | 传当前轮，正常路径不触发；异常读取按 [`error-standards.md`](../../error-standards.md) 的「七、外部调用」冒泡 |

## Target 回调

回调接口见 [`IProposalTarget.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IProposalTarget.sol)。

`voteAmount` 为本次增量，不是累计票数；Target Data 为不透明 `bytes[]`，由 Target 解释。空 Target Data 仍必须触发回调。投票回调仅接受 Vote，Executor 仅接受 ActionTarget 转发；回调前先写入投票状态，失败则一并回滚。

回调可重入 `vote`：重入时重新读取 `Stake.validGovVotes` 作为票上限，成员累计票数仍受该上限约束，因此回调不能突破本轮票权；若回调期间成员自己在 Stake 增加了质押，重入可按新上限继续投，等价于同一交易内先加杠杆再投票。

Mint 的 `voterBoost` / `totalVoterBoost` 直接取 Vote 的同名冻结快照。验收见 [Core 验收](09-testing.md)。
