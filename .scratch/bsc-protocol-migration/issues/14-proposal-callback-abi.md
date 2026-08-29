# 提案回调 ABI 与初始化原子性

Type: grilling
Status: resolved
Blocked by: 13

## Question

固定 `Submit` 初始化回调和 `Vote` 投票回调的最小通用 ABI、KV 数组校验、`proposalTargetMode` 与目标地址的组合规则，以及初始化回调失败时提案创建是否回滚。

## Comments

旧版 `LOVE20Submit` 和 `LOVE20Vote` 没有扩展回调；新 ABI 不能把 `voter`、`memberId`、`votes` 等只属于某类行动的字段放入通用接口。

当前可以确定的规则：

- 通用回调只传递 `tokenAddress`、`proposalId` 和不透明 KV，不放入 `proposer`、`proposalDetails`、当前轮次，也不放入 `voter`、`memberId`、`votes` 等行动专属字段。目标合约通过已配置的 `Submit`/`Vote` 按 `tokenAddress + proposalId` 查询需要的提案信息，并自行限制调用者为 `Submit` 或 `Vote`。
- `RewardOnly` 不回调且 KV 必须为空；`Callback` 只有在 KV 非空时才回调，目标无合约代码或 KV 长度不一致时回滚。
- 初始化回调或任意批量投票回调失败，外层交易整体回滚；回调不返回业务值，只以成功或 revert 表示结果。

## Answer

- 通用 KV 定为 `bytes32[] keys` 与 `bytes[] values`；两数组长度必须相等。`values` 由目标合约按自身 ABI 解码，核心不解析。
- 初始化回调定为 `onProposalInitialized(address tokenAddress, uint256 proposalId, bytes32[] keys, bytes[] values)`。
- 投票回调定为 `onProposalVote(address tokenAddress, uint256 proposalId, bytes32[] keys, bytes[] values)`；批量投票为每个提案提供独立 KV。
- `proposer`、`proposalDetails` 和治理轮次不作为通用回调参数。目标合约按 `tokenAddress + proposalId` 查询提案元数据或当前状态；行动专属的 `voter`、`memberId`、`votes` 等信息只通过业务约定的 KV 传递。
- `RewardOnly` 的 KV 必须为空且不回调；`Callback` 仅在 KV 非空时回调，目标无合约代码或数组长度不一致时回滚。
- 初始化回调或任意批量投票回调失败，外层 `Submit`/`Vote` 整笔交易回滚；回调无业务返回值，只以成功或 revert 表示结果。
