# 提案回调 ABI 与初始化原子性

Type: grilling
Status: claimed
Blocked by: 13

## Question

固定 `Submit` 初始化回调和 `Vote` 投票回调的最小通用 ABI、KV 数组校验、`proposalTargetMode` 与目标地址的组合规则，以及初始化回调失败时提案创建是否回滚。

## Comments

旧版 `LOVE20Submit` 和 `LOVE20Vote` 没有扩展回调；新 ABI 不能把 `voter`、`memberId`、`votes` 等只属于某类行动的字段放入通用接口。

当前可以确定的规则：

- 通用回调只传递 `tokenAddress`、`proposalId`、当前治理轮次和不透明 KV，不放入 `voter`、`memberId`、`votes` 等行动专属字段；目标合约自行限制调用者为 `Submit` 或 `Vote`。
- `RewardOnly` 不回调且 KV 必须为空；`Callback` 只有在 KV 非空时才回调，目标无合约代码或 KV 长度不一致时回滚。
- 初始化回调或任意批量投票回调失败，外层交易整体回滚；回调不返回业务值，只以成功或 revert 表示结果。

待用户确认的 ABI 细节：旧扩展现有字段是 `string[]`，通用 KV 继续使用 `string[] keys` / `string[] values`，还是改为 `bytes32[] keys` / `bytes[] values`；以及 `proposer`、`proposalDetails` 是否作为初始化回调的显式参数，还是由 `Target` 按 `proposalId` 查询。
