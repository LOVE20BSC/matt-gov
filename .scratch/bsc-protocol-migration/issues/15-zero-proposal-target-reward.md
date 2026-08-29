# 提案目标为零地址时的提案激励

Type: grilling
Status: claimed
Blocked by: 14

## Question

当 `proposalTarget == address(0)` 时，提案激励是否沿用行动 `executor == address(0)` 的语义，在准备奖励时把该提案额度自动销毁；还是禁止零地址提案目标并要求所有提案填写可领取地址？需要同时确定 `proposalTargetMode` 的允许组合、事件和重复结算保护。

## Comments

核心奖励由 `Mint` 统一预留、铸造和销毁。零地址不能作为 ERC20 铸造接收者；若允许其进入普通领取路径，会把预留额度留在无法领取的状态。

建议：`Submit` 创建提案时直接拒绝 `proposalTarget == address(0)`。`proposalTarget` 的语义是提案激励领取地址，之前已经确定每个提案都要保留这个地址；它与行动层 `executor == address(0)` 不同，后者是行动业务明确支持的“该行动额度自动销毁”语义。这样核心不新增提案专属销毁状态、事件和分支；若未来需要治理提案主动销毁激励，另建显式的销毁目标类型。

待确认：是否按上述建议禁止零地址提案目标。
