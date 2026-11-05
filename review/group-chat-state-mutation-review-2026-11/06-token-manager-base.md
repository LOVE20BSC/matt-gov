# TokenManagerBase · 状态变量变更审查

> `group-chat/src/managers/TokenManagerBase.sol`，88 行，基线 `group-chat@e982df8`。
> 本合约没有可变状态；它只派生 token 类 Manager 的依赖快照，并提供 symbol 清洗与 Phase 读取。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `STAKE_ADDRESS` | `address immutable` | 从 Vote 派生的 Stake 地址 | 构造 `:29` |
| 2 | `LAUNCH_ADDRESS` | `address immutable` | 从 Stake 派生的 Launch 地址 | 构造 `:30` |
| 3 | `PHASE_ADDRESS` | `address immutable` | 从 Stake 派生的 Phase 地址 | 构造 `:31` |

没有 mapping、array、计数器或布尔状态；所有函数要么是 pure/view，要么写 memory。

## 2. 逐变量变更逻辑

### 2.1 三个 immutable

派生链：

```text
ManagerBase 构造：VOTE_ADDRESS = IActionTarget(ACTION_TARGET_ADDRESS).VOTE_ADDRESS()
TokenManagerBase 构造：STAKE_ADDRESS  = IVote(VOTE_ADDRESS).STAKE_ADDRESS()
                       LAUNCH_ADDRESS = IStake(STAKE_ADDRESS).LAUNCH_ADDRESS()
                       PHASE_ADDRESS  = IStake(STAKE_ADDRESS).PHASE_ADDRESS()
```

- 三个值只在构造期写一次，没有 setter；后续所有检查/查询都读取它们。
- 构造期没有代码/零地址校验；依赖绑定错误由部署脚本在广播前拦截（`06-manager.md`“构造期依赖代码、参数与地址关系校验移到部署脚本”）。
- 若依赖在部署后自毁或升级为不兼容实现，`_checkLOVE20Token` / `currentPhase` 会以外部调用失败回滚；这是部署信任边界，不是状态写入问题。

### 2.2 无状态函数

| 函数 | 位置 | 行为 |
| --- | --- | --- |
| `_checkLOVE20Token` | `:34-38` | `tokenAddress.code.length != 0` 且 `ILaunch.isLOVE20Token(tokenAddress)`；否则回 `TokenNotLOVE20` |
| `currentPhase` | `:40-42` | 直接 `IPhase(PHASE_ADDRESS).currentPhase()` |
| `_tokenNamePayload` | `:44-46` | `IERC20Metadata(tokenAddress).symbol()` 经 `_sanitizeNameSymbol` 清洗 |
| `_sanitizeNameSymbol` | `:48-87` | memory 过滤：保留 ASCII 字母数字与 U+4E00–U+9FFF 的 CJK；丢弃其他字节；返回新 `bytes` |

`_sanitizeNameSymbol` 的所有 `output` / `outputLength` / `i` 都是 memory 局部变量，不触碰 storage。过滤规则与规格 `06-manager.md` 的“ASCII 字母数字 + CJK（U+4E00–U+9FFF）”一致；`E4 80–B7` 被排除，`E4 B8–BF` 到 `E9 BF BF` 被保留。

## 3. 写入顺序与不可分割性

本合约没有 storage 写入，因此不存在“写入顺序”问题。所有外部调用都是 view：

- `code.length` 是 EXTCODESIZE；
- `ILaunch.isLOVE20Token` / `IPhase.currentPhase` / `IERC20Metadata.symbol` 都是 view（STATICCALL）。

这些调用不能被用于对本合约的状态重入（本合约也没有状态可改）。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `TMB-01` | Info | 三个 immutable 依赖没有构造期代码/零地址校验；绑定正确性完全依赖部署脚本 | E1 |
| `TMB-02` | Info | `_sanitizeNameSymbol` 只保留 ASCII 字母数字与 CJK 子集，其他 UTF-8（含空格、下划线、其他语言）全部丢弃；这是名称展示语义，不是身份来源 | E1 |
| `TMB-03` | Info | `currentPhase` 直接透传 Phase，没有本地缓存或快照；Phase 未启动时由调用方（GroupChat）先回 `RoundNotStarted` | E1 |

逐条说明：

- **`TMB-01`**：构造函数只做外部 getter 读取。若 `ACTION_TARGET_ADDRESS` 指到错误合约，派生出的 `VOTE_ADDRESS` / `STAKE_ADDRESS` / `LAUNCH_ADDRESS` / `PHASE_ADDRESS` 可能全部错误；部署脚本的 `21_check.sh` 负责复核。合约没有自己的防御，因为这类错误无法在链上安全自动修复。
- **`TMB-02`**：清洗函数是纯函数，只影响托管群名称的 payload。symbol 清洗后为空时，子类会退回只使用 actionId 或纯类型码 + 随机串；名称不是 token/action 的身份来源，身份由事件与映射读取。
- **`TMB-03`**：`currentPhase` 没有 try/catch；Phase 返回 0 时本函数返回 0（不会自己回滚），但调用它的 Manager 查询（`totalVoteWeight`）会把 0 交给 Stake；GroupChat 的 `currentRound` 在 Phase 0 时先回 `RoundNotStarted`，所以正常发言路径不会到达这里。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| symbol 含中文时是否会被错误截断 UTF-8 | 只复制完整的三字节 CJK 序列；ASCII 单字节；不会复制半个字符 |
| symbol 为空是否会让名称生成下溢 | 子类对空 payload 有分支；`_managedGroupNameStem` 只用类型码 + 随机串 |
| Phase 地址错误是否会让 Manager 状态写入一半 | Manager 的激活在 mint 后才调用 GroupChat；Phase 只影响查询，不影响映射写入的原子性 |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| TM1 | 三个依赖地址构造后不变 | ✅ | 全部 `immutable` |
| TM2 | 没有 storage 写入 | ✅ | 文件内无状态变量赋值 / push / delete |
| TM3 | 清洗后的 symbol 只含 ASCII 字母数字与合法 CJK 序列 | ✅ | `_sanitizeNameSymbol` 的字节级过滤 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 依赖地址错配 | 部署脚本覆盖，合约侧无防御测试 |
| 极端 symbol（长 UTF-8、混合语言） | 已有中文/长 symbol 测试；未覆盖其他 UTF-8 语言，但规则是“丢弃”，不需要逐语言测试 |

### 4.5 结论

未发现 Critical / High / Medium。本合约是可验证的无状态基类：三个 immutable 只在构造期写，其余全是 pure/view/memory。3 条 Info 均为部署信任、名称展示语义与 Phase 透传边界。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `TMB-01` | 登记：三个 immutable 不在构造期重复校验 | `06-manager.md`「托管群名称」（L48） |
| `TMB-02` | 登记：symbol 清洗规则，名称非身份（既有文本已覆盖） | `06-manager.md`「托管群名称」 |
| `TMB-03` | 登记：`currentPhase` 直接透传、不缓存 | `04-query.md`「群聊 Round」 |
