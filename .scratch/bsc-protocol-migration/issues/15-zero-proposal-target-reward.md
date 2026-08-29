# 提案目标为零地址时的提案激励

Type: grilling
Status: open
Blocked by: 14

## Question

当 `proposalTarget == address(0)` 时，提案激励是否沿用行动 `executor == address(0)` 的语义，在准备奖励时把该提案额度自动销毁；还是禁止零地址提案目标并要求所有提案填写可领取地址？需要同时确定 `proposalTargetMode` 的允许组合、事件和重复结算保护。
