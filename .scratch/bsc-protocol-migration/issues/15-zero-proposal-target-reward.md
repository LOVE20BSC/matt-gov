# 提案目标为零地址时的提案激励

Type: grilling
Status: resolved
Blocked by: 14

## Question

当 `target == address(0)` 时，是自动销毁提案激励，还是禁止零地址并要求所有 Proposal 填写激励铸造接收主体？同时确定 `targetMode` 的允许组合、事件和重复结算保护。

## Comments

核心激励由 `Mint` 统一预留、铸造和销毁。零地址不能作为 ERC20 铸造接收者；若允许其进入普通铸造路径，会把预留额度留在无法铸造的状态。

最终规则：`Submit` 创建提案时直接拒绝 `target == address(0)`。Proposal Target 的语义是提案激励铸造接收主体，每个 Proposal 都必须提供；核心不新增提案专属销毁状态、事件和分支。行动层的 `executor` 也必须是非零合约地址，不存在零地址自动销毁例外；若未来需要治理提案主动销毁激励，另建显式的销毁目标类型。

## Answer

- `Submit` 创建提案时必须拒绝 `target == address(0)`；Proposal 不使用零地址作为自动销毁哨兵。
- `target` 始终是接收协议铸造提案激励的非零地址，允许是 EOA 或合约；由合约目标自行规定实际触发者，行动类目标只接受关联 `executor` 发起铸造。
- `RewardOnly` 要求创建 KV 为空且不触发回调；`Callback` 要求目标是合约并始终执行回调，KV 为空时也传递空数组。
- 四种组合边界固定为：非零 EOA + `RewardOnly` 合法；非零合约 + `RewardOnly` 合法但不回调；非零合约 + `Callback` 合法且始终回调；任意 EOA + `Callback` 直接拒绝。行动类 Proposal 额外要求 `target = ActionTarget`、`targetMode = Callback`，创建 KV 必须包含第 `0` 项 `executor` 保留项；仅有 executor 项、没有其他初始化 KV 时也允许通过，其他业务字段由行动执行合约判断。
- Proposal 不新增零地址专属销毁状态、事件或重复结算分支；行动 `executor` 同样拒绝零地址，不存在自动销毁行动激励的路径。未来若需要主动销毁提案激励，另建显式销毁目标类型。
