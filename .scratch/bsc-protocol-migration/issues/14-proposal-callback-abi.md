# 提案回调 ABI 与操作原子性

Type: grilling
Status: resolved
Blocked by: 13

## Question

固定 Proposal 创建、提案推举和提案投票三类回调的最小通用 ABI、KV 数组校验、`targetMode` 与目标地址的组合规则，以及任一回调失败时对应外层操作是否回滚。

## Comments

旧版 `LOVE20Submit` 和 `LOVE20Vote` 没有扩展回调；BSC 版回调只保留通用上下文和不透明 KV，推举回调标准传递 `submitterId`，投票回调标准传递 `voterId` 与增量治理票数。行动专属候选人 Member ID 仍通过 KV 传递。

## Answer

- 通用 KV 为 `bytes32[] keys` 与 `bytes[] values`，两数组长度必须相等。字段含义和编码由目标合约自行定义，`Submit`、`Vote` 和 `ActionTarget` 只负责透传。
- 创建回调：`onProposalCreated(address tokenAddress, uint256 proposalId, bytes32[] keys, bytes[] values)`。
- 推举回调：`onProposalSubmitted(address tokenAddress, uint256 proposalId, uint256 submitterId, bytes32[] keys, bytes[] values)`（对应核心 `Submit` 的推举操作）。`submitterId` 是本次将 Proposal 纳入治理轮次的 MemberNFT；推举 KV 可为空，由目标合约自行解释。
- 投票回调：`onProposalVoted(address tokenAddress, uint256 proposalId, uint256 voterId, uint256 votes, bytes32[] keys, bytes[] values)`。`voterId` 是本次投票人对应的 MemberNFT，`votes` 只表示本次调用新增的治理票数；批量投票为每个 Proposal 提供独立 KV 和标准投票上下文。
- `author`、`details` 和治理轮次不作为通用回调参数。Proposal 本体使用 `ProposalHead` / `ProposalBody` 保存元数据，目标合约按 `tokenAddress + proposalId` 查询需要的信息；候选人的 Member ID 等行动专属字段通过业务 KV 传递。
- `author`、`submitterId` 和 `voterId` 的值均为 MemberNFT 的 `memberId`，不使用钱包地址作为业务主体。
- Proposal 创建时 `title` 必须非空，`details` 可为空；目标合约可在创建回调中增加业务校验并通过回滚拒绝。
- `RewardOnly` 的 KV 必须为空且不回调；`Callback` 只要目标是合约就始终回调，KV 为空时也传递空数组。目标无合约代码或 KV 长度不一致时回滚；EOA 不得使用 `Callback`。
- 创建回调、推举回调或任意批量投票回调失败，对应外层创建、推举或投票整笔交易回滚；回调无业务返回值，只以成功或 revert 表示结果。
- 创建与推举在同一笔交易中执行时，固定先调用 `onProposalCreated`，再调用 `onProposalSubmitted`；任一回调失败都回滚整笔交易。
