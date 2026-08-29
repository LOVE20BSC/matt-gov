# 提案回调 ABI 与初始化原子性

Type: grilling
Status: claimed
Blocked by: 13

## Question

固定 `Submit` 初始化回调和 `Vote` 投票回调的最小通用 ABI、KV 数组校验、`proposalTargetMode` 与目标地址的组合规则，以及初始化回调失败时提案创建是否回滚。

## Comments

旧版 `LOVE20Submit` 和 `LOVE20Vote` 没有扩展回调；新 ABI 不能把 `voter`、`memberId`、`votes` 等只属于某类行动的字段放入通用接口。
