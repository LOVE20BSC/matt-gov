# 错误与回滚标准

本文件是 [`dev-standards.md`](dev-standards.md) §5.2.2 的细则，适用于 `core`、`action`、`group-chat`、`libs` 的全部自有 Solidity。身份错误同时适用 §5.2.1；调用者校验同时适用 §5.5。

## 一、本地所有权

- 每个合约/模块在自己的本地接口文件中声明 `I<Name>Errors`（通常是 `src/interfaces/I<Name>Errors.sol`，也可与主接口同文件）；实现文件不声明错误。
- 禁止从其他仓/其他模块导入错误定义；禁止中心 `Field` 枚举、中心错误表或“协议级 Error 文件”。
- 新增合约只新增 `I<Name>Errors.sol` + 实现 + 测试；不修改任何既有 `*Errors.sol`。协议固化后，新合约不能让老文件发生变化。
- 相同条件允许在不同模块本地重复声明（selector 相同）；目录按签名归组，不要求抽到共享文件。
- 标准错误由产生它的接口/合约拥有：`ILOVE20Token` 继承 `IERC20Errors`，`MemberNFT` 实现 ABI 自带 OZ ERC721 错误；`SafeERC20FailedOperation` 作为库错误通过 `SafeERC20` 使用进入调用方 ABI。
- 调用方接口默认不继承透传的标准错误；每个模块用一张“透传来源”表登记“可能透传 `ERC721NonexistentToken` / `ERC20InsufficientAllowance` 等”并链接来源 ABI，测试直接导入 OZ 或来源接口断言 selector。只有顶层集成面确需“单 ABI 自包含全部可预期失败”时，才白名单继承一组错误并逐项审查。

## 二、一条件一错误

- 一个 selector 只对应一个条件、一个主体、一个层次（鉴权/参数/存在/状态/资格/外部）。
- 禁止别名、重载、`deprecated` 双声明；旧错误直接删除。
- 不得用通用名承载多个条件（如 `InvalidAddress`、`InvalidTargetDataLength`、`InvalidParticipationAmount`、`InvalidExecutor`）。
- 需要区分条件时新增具名错误；错误名本身要能说明“什么失败了”。

## 三、命名

| 句式 | 示例 | 用途 |
|---|---|---|
| `<Subject><State>` | `GroupNotActive(groupId)`、`ProposalNotFound(proposalId)` | 身份/记录/生命周期 |
| `Zero<Field>` | `ZeroTokenAmount()`、`ZeroRecipientAddress()` | 非合约参数的零值（金额/计数/ID/recipient/target）；必填合约依赖用 `*NotContract` |
| `Invalid<Field>` | `InvalidFeeSettlementRatio(value)`、`InvalidTokenSymbolLength(length, expected)` | 值/格式/范围非法 |
| `<Subject>Exceeded` | `MaxSupplyExceeded(requested, remaining)`、`GroupCapacityExceeded(groupId, actual, limit)`、`LaunchCountLimitExceeded(tokenAddress, requested, remaining)` | 数值/额度/数量上限 |
| `Too<Size>` | `ContentTooLong(length, max)`、`TooManyRecipients(count, max)` | 长度/基数等尺寸语义 |
| `Not<Role>Owner/Operator` | `NotMemberOwner(memberId)`、`NotGroupOperator(groupId, operatorId)` | 角色鉴权 |
| `Already<State>` | `AlreadyJoined(token, action, member)`、`ChatAlreadyActivated(groupId)` | 重复状态/操作 |
| `*NotContract` | `SourceNotContract(address)`、`PluginNotContract(address)`、`DependencyNotContract(address)` | 依赖无代码（合约内字段级或模块级） |
| `*Unavailable` / `*Failed` | `BanVoteWeightSourceUnavailable(source)` | 外部依赖失败 |
| `*Rejected` | `ScopeRejected(source, groupId, senderId)` | 策略拒绝 |

约束：

- 新错误禁用 `Only*`、`Must*`、`Cannot*`；`Invalid*` 只用于值本身非法，不用于零值、不存在、未授权或状态不符。
- 数值/额度/数量上限统一用 `<Subject>Exceeded`；禁止 `Exceeds...` 前缀、`Exceed<Verb>` 动词式名和 `*LimitReached`。
- 尺寸类条件统一用 `Too<Size>`（`TooLong`/`TooMany`/`TooHigh`/`TooSmall`/`TooShort`/`TooLarge`），不与上限错误混用；缺口统一用 `Insufficient*`。
- 合约内必填依赖（含 `init`）的条件是“有代码”，不是“非零”：只保留 `*NotContract(address)`，零地址由 `*NotContract(0)` 覆盖，不再并行声明 `Zero*Address`。字段级 `<Field>NotContract` 与同模块一个 `DependencyNotContract(address)` 均可；后者用地址定位失败依赖。可选依赖零值表示禁用，只在非零时校验代码。`Zero<Field>` 仅用于非合约参数。
- 错误名描述失败状态，不写“请执行 X”的规则句。
- 错误名英文；规格与目录中文；不使用超过四个词的介词短语。

## 四、载荷

- 主体键在前，条件值在后；例如 `UnstakeAlreadyRequested(tokenAddress, memberId)`、`MaxSupplyExceeded(requested, remaining)`。
- 上限：`actual + limit`；额度：`required + available`；外部：`source`；批量：失败元素键或索引。
- 只允许定长标量、地址、枚举、`bytes32`；禁止字符串与动态数组。
- 相邻字段单位必须一致；不一致时拆错误或把单位写进字段名。
- 不在鉴权前泄露激活、配置、资格等非公开状态；身份存在性本身公开，可按身份规则直接报。
- 没有行动价值时省略载荷；不要为了“信息完整”增加无法被调用方使用的字段。

## 五、失败契约

每个外部写入口在模块规格中有一张表：

| # | 层 | 条件 | 错误 | 载荷 | 测试 |
|---|---|---|---|---|---|
| 1 | 鉴权 | 调用者不是 member owner | `NotMemberOwner(memberId)` | memberId | `test...` |
| 2 | 参数 | amount == 0 | `ZeroTokenAmount()` | 无 | `test...` |
| 3 | 存在 | token 未注册 | `TokenNotRegistered(tokenAddress)` | tokenAddress | `test...` |
| 4 | 状态 | 已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, memberId)` | tokenAddress, memberId | `test...` |
| 5 | 资格/上限 | 新总额超过上限 | `GroupCapacityExceeded(groupId, actual, limit)` | groupId, actual, limit | `test...` |
| 6 | 外部 | 转账失败 | `SafeERC20FailedOperation(token)` | token | `test...` |

顺序固定为：**鉴权 → 参数 → 存在性 → 状态/资格 → 账本/交互 → 不变量**；先命中先回滚，同一入口内不重排。

- 身份解析属于鉴权：函数主体就是鉴权键时，先解析主体；不存在回 `*NotExist`/标准 ERC721 错误，存在但非持有人回 `Not<Role>Owner`。这不是泄露，身份存在性公开。
- 模块规格可定义不同顺序，但必须写明理由并落入拒绝表；未写明的按上序执行。
- 依赖校验：必填合约依赖统一用 `*NotContract(address)`；零地址不单独成错误，部署脚本需要区分“漏配”时按 payload `0` 处理，不增加链上 selector。
- 标准错误透传不进本模块 Errors：每个模块用一张“透传来源”表登记 selector 与来源接口/合约 ABI，不要求每个入口重复；测试直接断言来源 selector，不要求本模块 ABI 自带。

## 六、写语义

| 类型 | 语义 | 规则 |
|---|---|---|
| Set | 设置值/集合增删 | 与当前相同 → 校验后幂等 no-op；不产生事件 |
| Transition | 投票、领取、铸造、撤回、加入、退出 | 必须改变状态，或回 `Already<State>`；同一模块内一致 |

- 批量入口一律原子：形状错误先回滚，元素错误按顺序首个失败回滚；错误必须能定位失败元素。
- 不提供 silent skip 模式；需要 liveness 时用单元素入口或独立清理函数。
- no-op 不得先于参数/身份/资格校验；不得用 no-op 吞掉非法请求。
- 批量删除不存在的元素默认 no-op；若模块选择严格模式，逐项回 `*NotFound`，必须在规格写明。

## 七、外部调用

| 边界 | 处理 |
|---|---|
| 协议固定依赖（MemberNFT/Phase/Mint/Vote/Submit/ActionTarget/Stake） | 预期缺失按读一致处理；非预期失败 rethrow，不映射成领域错误 |
| 用户配置/绑定依赖（Executor、scope/ban 源、插件） | 校验地址与代码；拒绝回 `*Rejected`；故障回 `*Failed`/`*Unavailable(source)` |
| 调用方任意输入（LP/join token、distributor） | 形态校验；失败归 `Invalid*`/`*NotContract`；原始错误只进有界事件 |

- 转译预期 selector 时必须写 `catch (bytes memory err)`（如 `ERC721NonexistentToken`）；只转译预期 selector，其余原样 rethrow。宽泛 `catch {}` 只允许用于明确不可信输入（无法安全限定 selector 的场景），并在规格登记。
- 不可信回调的 selector 不得与协议错误混淆；需要冒泡时，规格声明“可能携带任意 revert data”。
- 事件中的外部错误数据必须有界：使用 `bytes32 errorHash` + `uint256 errorLength`，或固定长度前缀；不得原样写入无界 `bytes`。

## 八、ABI 与版本

- 错误签名是公开 ABI；新增错误是兼容变更，改签名/删除是破坏性变更；不保留旧签名、别名或 deprecated 声明。
- 不保留 deprecated 声明、别名或不可达错误；不可达的不变量用 `assert`（Panic），不进错误目录。
- 错误 selector 不得作为业务返回值；预检查返回本地封闭枚举 `Reason`，不复用错误 selector。
- 错误目录由 `script/check_errors.py` 扫描 `src/interfaces` + 实现生成；提交生成物，不在源码中维护中心表。脚本要求 Foundry `cast` 在 PATH 中；缺失时直接失败，不写入未解析的 selector。
- 同一脚本的 `--check` 模式检查：裸 `require`/`revert`、未声明错误、同名不同签名、跨仓错误导入、死声明、目录漂移；失败即门禁失败，不设 allowlist。

## 九、测试

| 测试类 | 要求 |
|---|---|
| 失败契约 | 每个可达错误一条 selector + 载荷断言 |
| 优先级 | 每个多条件入口至少 auth-vs-input、input-vs-state；批量加 shape-vs-element |
| 批量 | 形状错误、首元素、后元素、整批回滚 |
| 外部 | 预期缺失、非预期 revert 原样冒泡、回调伪造、事件数据上限 |
| no-op | Set 幂等、Transition 已状态、集合增删重复/缺失 |
| 快照 | 错误目录 selector 不变；变更即失败 |
| mock 保真 | mock 使用真实错误接口，不得同名不同签名 |

## 十、审查清单

- [ ] 错误声明在本模块的 `I<Name>Errors`（独立文件或与主接口同文件）；实现文件无错误声明；未从其他仓导入错误。
- [ ] 新合约只新增文件，未修改既有 `*Errors.sol`。
- [ ] 一条件一错误；无别名/重载/通用多义名。
- [ ] 载荷含主体键/实际值与上限；批量错误能定位元素；无字符串/动态数组。
- [ ] 无裸 `require`/`revert`；`assert` 仅不可达不变量。
- [ ] 写入口有拒绝表；鉴权最先；无 no-op 先于校验。
- [ ] 外部边界分类明确；catch 只转译预期 selector；事件错误数据有界。
- [ ] 标准错误由产生者拥有；调用方未重复继承透传错误，失败契约登记来源与白名单例外；无死声明；目录与检查器通过。
- [ ] 合约内必填依赖（含 `init`）只声明 `*NotContract(address)`，没有并行的 `Zero*Address`；`Zero<Field>` 只用于非合约参数。
- [ ] 每个可达错误有 selector + 载荷测试；mock 与真实接口一致。
