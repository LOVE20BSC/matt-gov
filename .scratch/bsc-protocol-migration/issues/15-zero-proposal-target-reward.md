# 提案目标为零地址时的提案激励

Type: grilling
Status: resolved
Blocked by: 14

## Question

当 `proposalTarget == address(0)` 时，提案激励是否沿用行动 `executor == address(0)` 的语义，在准备奖励时把该提案额度自动销毁；还是禁止零地址提案目标并要求所有提案填写可领取地址？需要同时确定 `proposalTargetMode` 的允许组合、事件和重复结算保护。

## Comments

核心奖励由 `Mint` 统一预留、铸造和销毁。零地址不能作为 ERC20 铸造接收者；若允许其进入普通领取路径，会把预留额度留在无法领取的状态。

建议：`Submit` 创建提案时直接拒绝 `proposalTarget == address(0)`。`proposalTarget` 的语义是提案激励领取地址，之前已经确定每个提案都要保留这个地址；它与行动层 `executor == address(0)` 不同，后者是行动业务明确支持的“该行动额度自动销毁”语义。这样核心不新增提案专属销毁状态、事件和分支；若未来需要治理提案主动销毁激励，另建显式的销毁目标类型。

## Answer

- `Submit` 创建提案时必须拒绝 `proposalTarget == address(0)`；Proposal 不使用零地址作为自动销毁哨兵。
- `proposalTarget` 始终是可领取提案激励的非零地址，允许是 EOA 或合约。
- `RewardOnly` 要求初始化 KV 为空且不触发回调；`Callback` 在 KV 非空时要求目标是合约并执行回调，KV 为空时不回调。
- Proposal 不新增零地址专属销毁状态、事件或重复结算分支。行动层 `executor == address(0)` 的行动额度自动销毁规则保持不变；未来若需要主动销毁提案激励，另建显式销毁目标类型。
