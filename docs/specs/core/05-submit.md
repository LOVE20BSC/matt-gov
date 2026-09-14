# Submit

Submit 管理 Proposal 创建和当前治理 Round 的推举。Proposal 规则与权限见 [通用规则](01-common-rules.md)，Round 边界见 [Phase](03-phase.md#治理-round)。投票由 [Vote](06-vote.md) 独立管理。

## Proposal

Proposal 以 `tokenAddress + proposalId` 定位，ID 每社区单调分配、从 `1` 开始。`proposalId == 0` 无效，对未分配 ID 的访问回滚 `ProposalNotFound`。

Submit 不校验 `tokenAddress` 是否登记为 LOVE20 代币；推举门槛由 Stake 票数自然兜底。

| 数据 | 内容 |
| --- | --- |
| `ProposalHead` | `id`、`author`（memberId）、`createAtBlock` |
| `ProposalBody` | 非空 `title`、可空 `details` |
| `target` | 非零激励接收地址 |
| `targetMode` | `NoCallback` 或 `Callback` |
| `targetData` | 可选的不透明 Target Data 数组，可以为空 |

| target | NoCallback | Callback |
| --- | --- | --- |
| 非零 EOA | 合法，不回调 | 拒绝 |
| 非零合约 | 合法，不回调 | 创建、推举、投票都回调，空 Target Data 也回调 |
| 零地址 | 拒绝 | 拒绝 |

显式销毁可由专用 Target 合约接收后执行，不能用零 Target 隐式销毁。

结构体见 [`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)。

创建只保存 Proposal 并触发创建回调，不自动推举；调用者须持有 `memberId` 且满足 `canSubmit`。创建后内容和 Target 不变，重名标题不等于重复 Proposal。

`NoCallback` 忽略 `targetData`，不要求为空；`Callback` 允许 `targetData` 为空，并在回调时原样透传。Target Data 的业务编码由 Target 自行定义。

## 接口

完整 ABI 见 [`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)。它沿用旧 `LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol` 的 Proposal 创建、推举、枚举和查询职责；旧接口中的行动专属字段已按 BSC 规则移出，统一由 Proposal 与 Target/Target Data 表达，业务主体由地址改为 `memberId`。

## 推举

推举门槛沿用旧 Submit：从 Stake 读取当前成员 `validGovVotes(tokenAddress, memberId)` 与社区 `govVotesNum(tokenAddress)`；成员和社区票数均为正，且 `floor(validGovVotes * 1000 / govVotesNum) >= SUBMIT_MIN_PER_THOUSAND`。初始化门槛范围为 `1..1000`。

`canSubmit` 实现：先判 `govVotesNum(tokenAddress) == 0` 返回 `false`，再判 `validGovVotes(tokenAddress, memberId) == 0` 返回 `false`，最后计算千分比，避免除零 panic。

调用者必须持有 `memberId`。每个成员每社区每 Round 最多推举一个 Proposal，同一 Proposal 同轮只能被推举一次；创建不消耗推举次数。每社区每轮首个成功推举自动调用 `Phase.sync()`；`sync` 已同步时无操作返回、不会回滚，但若失败则按外部调用失败处理，整笔推举回滚。推举已有 Proposal 不重复触发创建回调。

## 校验顺序

`createProposal` 校验顺序：

1. **参数校验**：`title` 非空（`EmptyString("title")`）、`target` 非零（`InvalidAddress()`）、`targetMode` 合法（枚举范围内且 `Callback` 时 `target.code.length > 0`，否则 `InvalidTargetMode()`）
2. **存在性**：`memberId` 存在（`IMemberNFT.ownerOf` 不回滚）
3. **持有权**：`ownerOf(memberId) == msg.sender`（`NotMemberOwner(memberId)`）
4. **门槛**：`canSubmit(tokenAddress, memberId)`（`CannotSubmitAction()`）
5. 分配 `proposalId` 并写入
6. 发出 `ProposalCreated` 事件
7. `Callback` 时回调 `IProposalTarget.onProposalCreated`

`submit` 校验顺序：

1. **参数校验**：无显式参数校验
2. **存在性**：`proposalId` 存在（`ProposalNotFound(proposalId)`）、`memberId` 存在
3. **持有权**：`ownerOf(memberId) == msg.sender`（`NotMemberOwner(memberId)`）
4. **门槛**：`canSubmit(tokenAddress, memberId)`（`CannotSubmitAction()`）
5. **去重**：先判同一 Proposal 同轮是否已推举（`AlreadySubmitted()`）、再判同一成员同社区同轮是否已推举其他 Proposal（`OnlyOneSubmitPerRound()`）
6. 写入三处状态（推举列表、按 Proposal、按提交者）
7. 发出 `ProposalSubmitted` 事件
8. 本社区本轮首笔推举时调用 `Phase.sync()`
9. `Callback` 时回调 `IProposalTarget.onProposalSubmitted`

初始化校验：`phaseAddress`、`stakeAddress`、`memberNFTAddress` 非零（`InvalidAddress()`）；`submitMinPerThousand` 在 `1..1000` 范围（`ZeroAmount("submitMinPerThousand")` / `InvalidAmount()`）。

## 事件与错误

事件与错误定义见 [`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)。

`ProposalCreated` 由 `createProposal` 发出，包含 `author`（创建者 `memberId`）、`title`、`details`、`target`、`targetMode`；不含 `round`、不含 `targetData`。

`ProposalSubmitted` 由 `submit` 发出，包含 `round`（= `currentRound()`）、`submitterId`、`proposalId`。

`targetData` 无法从事件重建，需回读 `proposal()`。

错误：

| 错误 | 触发条件 |
| --- | --- |
| `AlreadyInitialized()` | 重复初始化 |
| `InvalidAddress()` | `init` 的任一地址为零；`createProposal` 的 `target` 为零 |
| `InvalidTargetMode()` | `targetMode` 枚举越界，或 `Callback` 且 `target.code.length == 0` |
| `NotMemberOwner(uint256 memberId)` | `ownerOf(memberId) != msg.sender` |
| `EmptyString(string parameter)` | `title` 为空 |
| `ZeroAmount(string parameter)` | `init` 的 `submitMinPerThousand == 0` |
| `InvalidAmount()` | `init` 的 `submitMinPerThousand > 1000` |
| `RoundNotStarted()` | `currentRound() == 0`（Phase 尚未开始；当前不强制校验，由业务决定是否允许 Phase 0 创建与推举） |
| `ProposalNotFound(uint256 proposalId)` | 不存在的 Proposal |
| `IndexOutOfBounds(uint256 index)` | 枚举越界 |
| `CannotSubmitAction()` | 门槛或资格不足 |
| `AlreadySubmitted()` | 同一 Proposal 同轮重复推举 |
| `OnlyOneSubmitPerRound()` | 同一成员同轮再次推举 |

沿用旧 Submit 的三个专用 selector：`CannotSubmitAction`、`AlreadySubmitted`、`OnlyOneSubmitPerRound`。

## Target 回调

回调接口见 [`IProposalTarget.sol`](../../../interfaces/core/IProposalTarget.sol)。

创建和推举分别触发对应回调。回调不要求 Target Data 非空；空 `targetData` 仍必须调用回调并传递空数组。创建回调仅接受 Submit；Executor 仅接受 ActionTarget 转发。回调前先写入对应 Proposal 或推举状态，失败则一并回滚。

验收见 [Core 验收](09-testing.md)。
