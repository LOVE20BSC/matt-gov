# Submit

Submit 管理 Proposal 创建和当前治理 Round 的推举。Proposal 规则与权限见 [通用规则](01-common-rules.md)，Round 边界见 [Phase](03-phase.md#治理-round)。投票由 [Vote](06-vote.md) 独立管理。

## Proposal

Proposal 以 `tokenAddress + proposalId` 定位，ID 单调分配。

| 数据 | 内容 |
| --- | --- |
| `ProposalHead` | `id`、`author`（memberId）、`createAtBlock` |
| `ProposalBody` | 非空 `title`、可空 `details` |
| `target` | 非零激励接收地址 |
| `targetMode` | `NoCallback` 或 `Callback` |
| `keys` / `values` | 可选的不透明 KV；长度相等，可以同时为空 |

| target | NoCallback | Callback |
| --- | --- | --- |
| 非零 EOA | 合法，不回调 | 拒绝 |
| 非零合约 | 合法，不回调 | 创建、推举、投票都回调，空 KV 也回调 |
| 零地址 | 拒绝 | 拒绝 |

显式销毁可由专用 Target 合约接收后执行，不能用零 Target 隐式销毁。

结构体见 [`ILOVE20Submit.sol`](../../../interfaces/core/ILOVE20Submit.sol)。

创建只保存 Proposal 并触发创建回调，不自动推举；调用者须持有 `memberId` 且满足 `canSubmit`。创建后内容和 Target 不变，重名标题不等于重复 Proposal。

`NoCallback` 必须同时传入空 `keys` 和空 `values`；`Callback` 允许两者同时为空。任何不等长 KV 或 NoCallback 携带业务数据的调用都回滚。

## 接口

完整 ABI 见 [`ILOVE20Submit.sol`](../../../interfaces/core/ILOVE20Submit.sol)。它沿用旧 `LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol` 的 Proposal 创建、推举、枚举和查询职责；旧接口中的行动专属字段已按 BSC 规则移出，统一由 Proposal 与 Target/KV 表达，业务主体由地址改为 `memberId`。

## 推举

推举门槛沿用旧 Submit：从 Stake 读取当前成员 `validGovVotes(tokenAddress, memberId)` 与社区 `govVotesNum(tokenAddress)`；成员和社区票数均为正，且 `floor(validGovVotes * 1000 / govVotesNum) >= SUBMIT_MIN_PER_THOUSAND`。初始化门槛范围为 `1..1000`。

调用者必须持有 `memberId`。每个成员每社区每 Round 最多推举一个 Proposal，同一 Proposal 同轮只能被推举一次；创建不消耗推举次数。每轮首个成功推举自动调用 `Phase.sync`；推举已有 Proposal 不重复触发创建回调。

## 事件与错误

事件与错误定义见 [`ILOVE20Submit.sol`](../../../interfaces/core/ILOVE20Submit.sol)。

`ProposalNotFound` 用于不存在的 Proposal；`IndexOutOfBounds` 用于枚举越界。沿用旧 Submit 的三个专用 selector：门槛或资格不足回滚 `CannotSubmitAction`，同一 Proposal 同轮重复推举回滚 `AlreadySubmitted`，同一成员同轮再次推举回滚 `OnlyOneSubmitPerRound`。零 Target、非法模式、非成员持有人也必须回滚；其专用 selector 仍以接口文件为准。

## Target 回调

回调接口见 [`IProposalTarget.sol`](../../../interfaces/core/IProposalTarget.sol)。

创建和推举分别触发对应回调。回调不要求 KV 非空；空 `keys`/`values` 仍必须调用回调并传递空数组。创建回调仅接受 Submit；Executor 仅接受 ActionTarget 转发。回调前先写入对应 Proposal 或推举状态，失败则一并回滚。

验收见 [Core 验收](09-testing.md)。
