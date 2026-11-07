> 历史卷标注：本文中关于根父币计数维度与 `2 × MAX_LAUNCH_COUNT` 的描述已被 `dac6d59` 取代；正文保持原样，不再作为当前实现依据。
# Launch 事件赋值与发射审查

- 实现：`core/src/Launch.sol`（350 行，`6fdd0f1`）
- 声明：`core/src/interfaces/ILaunch.sol`（`ILaunchEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/08-launch.md`
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 5 |
| 发射点 | 5 个 emit 语句（`LaunchCountAdded` 每笔可发 2 次） |
| P0 / P1 / P2 / P3 | 0 / 0 / 1 / 2 |
| 修复状态 | LA-1 / LA-2 / LA-3 已全部关闭（见 §4） |
| 放行 | 可放行；LA-1 的判别力缺口已补齐 |

本合约有两类事实：**登记类**（`GenesisTokenCreated` / `TokenLaunched`）与**次数账本类**（`LaunchCountAdded` / `LaunchCountMerged` / `LaunchCountConsumed`）。账本类事件的余额字段全部是后置值，登记类事件全部在登记写入之后发射，且 `TokenLaunched` 先于 distributor 回调。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `GenesisTokenCreated` | `tokenAddress`, `parentTokenAddress` | `init:78` | `_createToken:68`（子合约构造并发 `TokenMinted`）→ `FIRST_TOKEN_ADDRESS:69` → `_tokens/_parentTokenByTokenAddress/_tokenAddressBySymbol/_childTokens:70-73` → `MemberNFT.init:75` | 无 |
| `TokenLaunched` | `tokenAddress`, `parentTokenAddress`, `launcherMemberId` | `launchToken:139` | 扣减次数 `:112`（发 `LaunchCountConsumed`）→ 符号与名称 `:121-129` → `_createToken:132` → 四处登记 `:133-136` | `distributor.onTokenLaunched:150`（`Callback` 模式） |
| `LaunchCountConsumed` | `tokenAddress`, `memberId` | `launchToken:114` | `_remainingLaunchCount`:112 | 符号唯一性校验、创建子币、`TokenLaunched` |
| `LaunchCountAdded` | `tokenAddress`, `memberId` | `_addLaunchCount:342` | `_issuedLaunchCount:339-340`、`_remainingLaunchCount:341` | 首币时由 `addLaunchCount:201-203` 再记一次根父币维度 |
| `LaunchCountMerged` | `tokenAddress`, `sourceMemberId`, `targetMemberId` | `mergeLaunchCount:177` | 源、目标余额 `:174-175` | 无 |

族归属：`core.registry`（根键 → 父根键 → 对象 id → 角色 → 数值 → 枚举 → 文本）。

## 2. 逐事件赋值链

### 2.1 `GenesisTokenCreated`

```
event GenesisTokenCreated(
    address indexed tokenAddress,
    address indexed parentTokenAddress,
    address distributor,
    string name,
    string symbol
);
```

| 字段 | 赋值来源（源码行） | 取值口径 |
| --- | --- | --- |
| `tokenAddress` | `firstToken`，即 `_createToken` 的返回值 `:68` | 与 `FIRST_TOKEN_ADDRESS:69`、`_tokens[0]:70`、`_tokenAddressBySymbol[symbol]:72` 同一地址；测试断言与 `MemberNFT.LOVE20_TOKEN_ADDRESS()` 一致（`Launch.t.sol:277-302`） |
| `parentTokenAddress` | `params.rootParentTokenAddress` | 根父币；同时是 `_parentTokenByTokenAddress[firstToken]` 的键值 `:71` |
| `distributor` | `params.distributor` | 首批供应的接收者，与 `_createToken` 传给 `LOVE20Token` 构造函数的第 5 个参数同源 `:251` |
| `name` / `symbol` | `params.name` / `params.symbol` | 原值，不经 `Test` 前缀、不经 `tokenSymbol@parentSymbol` 拼接（与 `TokenLaunched` 的差异点） |

发射链：

1. `_createToken:238` 校验名称/符号长度 → `new LOVE20Token(...):250`（该构造函数内 `_mint` + `emit TokenMinted`）→ `getPair/createPair:256-260`；
2. 回到 `init`：`FIRST_TOKEN_ADDRESS` 与四个登记账本写入 `:69-73`；
3. `IMemberNFT(params.memberNFTAddress).init(firstToken):75`（外部调用，无事件）；
4. `emit GenesisTokenCreated:78`。

E1 适用：主对象（首币）的构造期 `TokenMinted` 先于创建事件 `GenesisTokenCreated`，创建事件中的 `tokenAddress` 等于部署地址。顺序由 `Launch.t.sol:1907` 断言。

### 2.2 `TokenLaunched`

```
event TokenLaunched(
    address indexed tokenAddress,
    address indexed parentTokenAddress,
    uint256 indexed launcherMemberId,
    address distributor,
    DistributorMode distributorMode,
    string name,
    string symbol
);
```

| 字段 | 赋值来源（源码行） | 取值口径 |
| --- | --- | --- |
| `tokenAddress` | `tokenAddress`，`_createToken` 返回值 `:132` | 新部署的子币；同时写入 `_tokens:133`、`_parentTokenByTokenAddress:134`、`_tokenAddressBySymbol:135`、`_childTokens:136` |
| `parentTokenAddress` | 入参 `parentTokenAddress` | 普通发射为父币；根级发射为 `ROOT_PARENT_TOKEN_ADDRESS`（由 `:103` 的存在性分支放行） |
| `launcherMemberId` | 入参 `memberId` | 本次消耗次数的成员；`onlyMemberOwner(memberId)` 已在 `:98` 校验持有权 |
| `distributor` | 入参 `distributor` | 与 `_createToken` 的构造参数同源 `:251`；`:100` 已拒绝零地址 |
| `distributorMode` | 入参 `distributorMode` | `:101` 已按模式校验 distributor 有代码 |
| `name` | `tokenName = subTokenSymbol + "@" + parentTokenSymbol` `:129` | 与 `LOVE20Token` 构造参数同源 `:251`；根级发射的 `parentTokenSymbol` 取 `FIRST_TOKEN_ADDRESS` 的符号 `:122-124` |
| `symbol` | `subTokenSymbol` `:125` | 施加 `Test` 前缀后的**最终**符号，与构造函数同源；唯一性按该值校验 `:126` |

发射链（`launchToken`）：

1. 鉴权 `:98` → 参数 `:99-101` → 父币存在性 `:103-105` → 账本余量 `:107-108`；
2. 扣减并 `emit LaunchCountConsumed:114`（先更新后外部调用，满足检查—更新—交互）；
3. 读取父币符号、拼 `Test` 前缀、算名称、校验最终符号唯一 `:121-129`；
4. `_createToken:132`：子币构造（内发 `TokenMinted`）+ 建池；
5. 四处登记 `:133-136`；
6. `emit TokenLaunched:139`；
7. `Callback` 模式回调 distributor `:150`（回调失败整笔回滚）。

依赖序：`TokenMinted`（子币）→ `TokenLaunched`；`LaunchCountConsumed` 先于 `TokenLaunched`（§6.1 `08-launch.md` 事件表明确要求）。

### 2.3 `LaunchCountConsumed`

```
event LaunchCountConsumed(address indexed tokenAddress, uint256 indexed memberId, uint256 remaining);
```

| 字段 | 赋值来源 | 说明 |
| --- | --- | --- |
| `tokenAddress` | `parentTokenAddress` | 消耗的是**父币维度**的次数（根级发射即根父币维度） |
| `memberId` | 入参 `memberId` | |
| `remaining` | `remainingCount = availableCount - 1` `:111` | 后置余额；`availableCount` 读自 `:107` |

`issuedLaunchCount` 不变，故不携带；一次发射固定消耗 1，消耗量由事件名承载，不单列恒为 1 的 `count`（`08-launch.md` 事件表）。

### 2.4 `LaunchCountAdded`

```
event LaunchCountAdded(
    address indexed tokenAddress,
    uint256 indexed memberId,
    uint256 count,
    uint256 issuedCount,
    uint256 memberRemaining
);
```

| 字段 | 赋值来源 | 说明 |
| --- | --- | --- |
| `tokenAddress` | `_addLaunchCount` 的 `tokenAddress` 参数 | 首币时该函数被调用两次：`addLaunchCount:199` 传首币，`:201-203` 传根父币 |
| `memberId` | 入参 | 两次调用同值 |
| `count` | 入参 `count` | 本次新增次数；两次调用同值（1:1 伴生） |
| `issuedCount` | 局部 `issuedCount = _issuedLaunchCount[token] + count` `:339`，先写回 `:340` | 该账本维度的后置累计值；`addLaunchCount:195` 已保证不超过 `MAX_LAUNCH_COUNT` |
| `memberRemaining` | 读 `_remainingLaunchCount[token][memberId]` `:347`，在 `+=` `:341` 之后读 | 该成员在该维度的后置余额 |

两个不变量：

- `issuedCount == 折叠(Σcount)`（`Launch.t.sol:1311` 断言）。
- 首币与根父币两维度的 `issuedCount` 恒等（`08-launch.md` 根级伴生不变式）。

### 2.5 `LaunchCountMerged`

```
event LaunchCountMerged(
    address indexed tokenAddress,
    uint256 indexed sourceMemberId,
    uint256 indexed targetMemberId,
    uint256 count,
    uint256 sourceRemaining,
    uint256 targetRemaining
);
```

| 字段 | 赋值来源 | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 | 已登记代币或根父币（`:163-165` 放行两种） |
| `sourceMemberId` / `targetMemberId` | 入参 | `:158-160` 已拒绝同值；`_ownerOf(targetMemberId):167` 只校验存在性，不要求调用者持有目标 |
| `count` | 入参 | `:161` 已拒绝 0 |
| `sourceRemaining` | `sourceCount - count` `:172`，写回 `:174` | 后置余额 |
| `targetRemaining` | 旧值 + `count` `:173`，写回 `:175` | 后置余额 |

`issuedLaunchCount` 不变（融合不释放累计上限），事件不携带。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 5 个事件均以 `tokenAddress` 开头 |
| 父链槽位（根键 → 父根键） | 通过 | `GenesisTokenCreated` / `TokenLaunched` 第二字段为 `parentTokenAddress` |
| 配置变更带旧值+新值（§5.1、§6.7） | 不适用 | 本合约无可变配置；`init` 参数属一次性部署参数（§3.2） |
| 创世与发起拆分（§5.3、§3.6） | 通过 | `GenesisTokenCreated` 无 launcher 字段，不用 `launcherMemberId = 0` 作哨兵 |
| 账本事件带后置余额 | 通过 | 三个账本事件均携带后置值 |
| 累计值锚点（§3.1） | 通过 | `LaunchCountAdded.issuedCount` |
| 状态写入后 emit（§3.4.3） | 通过 | 见 §1 表 |
| 依赖序（§3.4.5） | 通过 | `TokenMinted` → `TokenLaunched`；`LaunchCountConsumed` → `TokenLaunched` |
| E1（§3.4.7） | 基本符合，见 LA-3 | 创建事件前有一次无事件的 `MemberNFT.init` 外部调用 |
| 失败不留日志（§3.5） | 通过 | 符号重复、`PairCreationFailed`、回调失败均整笔回滚 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py`：29 events、families OK、style OK |
| 测试断言（§8.1） | 部分，见 LA-1 / LA-2 | |

## 4. 发现

### [P2] LA-1 `LaunchCountAdded` 的 `issuedCount` 与 `memberRemaining` 在夹具中恒等，未做可判别断言

- 状态：已修复。夹具先给第二成员发 2 次，测得事件为 `issuedCount=6`、`memberRemaining=4`，并逐条断言二者不等。
- 证据：`Launch.t.sol:1275-1281`（`count=4, issuedCount=4, memberRemaining=4`）；`Launch.t.sol:1324-1327`（`count=3, issuedCount=7`，`memberRemaining` 未断言，实际也是 7）。
- 问题：`issuedCount`（账本累计）与 `memberRemaining`（成员余额）是同一事件内的两个同类型 `uint256`，两个夹具里取值始终相同，把两个实参互换后测试仍然通过——按 §8.1 属「没断言」。二者在语义上可以不同（多成员共用同一账本，或先消耗后新增）。
- 影响：若实现误把 `memberRemaining` 赋成 `issuedCount`（或反之），现有测试无法发现；消费方以 `memberRemaining` 折叠成员余额时会拿到错误值。
- 建议：在 `testAddLaunchCountUpdatesBothLedgersAndEmits` 中给第二个成员发放次数（或先 `launchToken` 消耗 1 次）后再断言，使 `issuedCount != memberRemaining`。

### [P3] LA-2 首币伴生的两条 `LaunchCountAdded` 发射顺序未被断言

- 状态：已修复。测试断言首币维度日志下标小于根父币维度，`08-launch.md` 事件表同步登记该顺序。
- 证据：`Launch.t.sol:1293` 只断言条数为 2；`LaunchCountAdded` 的两条分别由 `addLaunchCount:199`（首币）与 `:202`（根父币）产生。
- 问题：§3.4.4 要求批量/多条事件的发射顺序确定并由测试断言；当前顺序（首币 → 根父币）只体现在源码，没有契约级断言。
- 影响：实现若调换两次 `_addLaunchCount` 的顺序，测试仍全绿，但依赖「首币维度先出现」的折叠逻辑会静默错位。
- 建议：断言第一条 `topics[1] == FIRST_TOKEN_ADDRESS`、第二条 `topics[1] == ROOT_PARENT_TOKEN_ADDRESS`。

### [P3] LA-3 创建事件与登记之间夹有一次无事件的外部调用

- 状态：已修复（文档 + 断言）。`08-launch.md` 把 `init` 固定为「登记 → `MemberNFT.init` → 创建事件」三步，测试断言 `GenesisTokenCreated` 是 `init` 的最后一条日志。
- 证据：`Launch.sol:75` `IMemberNFT(...).init(firstToken)` 位于登记写入 `:70-73` 与 `emit GenesisTokenCreated:78` 之间。
- 问题：E1 的措辞是「创建事件在登记完成后立即 emit」；此处登记完成后先调用外部合约再 emit。当前 `MemberNFT.init` 不发事件、不回调 Launch，因此没有可观察的交错；但顺序契约比规范描述松。
- 影响：若 `MemberNFT.init` 未来引入回调或事件，`GenesisTokenCreated` 之前会出现其他合约的日志，破坏「创建事件紧随登记」的折叠假设。
- 建议：二选一——把 `MemberNFT.init` 前移到登记写入之前（`_createToken` 之后立即调用），或在 `08-launch.md` 明确「登记 → 绑定 MemberNFT → 创建事件」是固定三步，并在测试中断言 `GenesisTokenCreated` 是 `init` 的最后一个日志。

## 5. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_tokens` / `_childTokens` | `:70`、`:133`、`:73`、`:136` | `GenesisTokenCreated` / `TokenLaunched`（含顺序与父币） |
| `_parentTokenByTokenAddress` | `:71`、`:134` | 同上（`isLOVE20Token` 的判定源） |
| `_tokenAddressBySymbol` | `:72`、`:135` | 同上（符号唯一性可从事件流重建） |
| `_remainingLaunchCount` | `:112`、`:174-175`、`:341` | `LaunchCountConsumed` / `Merged` / `Added` |
| `_issuedLaunchCount` | `:340` | `LaunchCountAdded.issuedCount` |
| `initialized` / 配置 / `FIRST_TOKEN_ADDRESS` | `:57-69` | 一次性部署参数，§3.2 豁免；`FIRST_TOKEN_ADDRESS` 由 `GenesisTokenCreated.tokenAddress` 隐含 |
