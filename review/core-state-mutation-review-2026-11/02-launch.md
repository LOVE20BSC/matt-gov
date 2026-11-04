# Launch · 状态变量变更审查

> `core/src/Launch.sol`，350 行，`core@0466d67`。
> 本合约不持资产，但它是**代币登记、符号唯一性、发射次数**三本账的唯一写入者，也是 `MemberNFT` 的初始化者。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| 1-5 | `MINT_ADDRESS` / `MEMBER_NFT_ADDRESS` / `ROOT_PARENT_TOKEN_ADDRESS` / `FIRST_TOKEN_ADDRESS` / `PAIR_FACTORY_ADDRESS` | `address` | 依赖地址；`FIRST_TOKEN_ADDRESS` 是首币 | `init` `:58-61`、`:69` | 只写一次 |
| 6-10 | `TOKEN_SYMBOL_LENGTH` / `LAUNCH_COUNT_THRESHOLD_RATIO` / `MAX_LAUNCH_COUNT` / `LAUNCH_AMOUNT` / `MAX_SUPPLY` | `uint256` | 发射与供应参数 | `init` `:62-66` | 只写一次 |
| 11-13 | `MAX_TOKEN_SYMBOL_LENGTH` / `MAX_TOKEN_NAME_LENGTH` / `TEST_PREFIX_BYTES` | `constant` | 硬上限 | — | 编译期 |
| 14 | `initialized` | `bool` | 一次性开关 | `init` `:57` | 只写一次 |
| 15 | `_tokens` | `address[]` | 创建顺序的全量代币列表（含首币，索引 0） | `init:70`、`launchToken:133` | 只追加 |
| 16 | `_parentTokenByTokenAddress` | `mapping(address => address)` | 代币 → 父币；**非零即已登记** | `init:71`、`launchToken:134` | 只写一次/代币 |
| 17 | `_tokenAddressBySymbol` | `mapping(string => address)` | 最终符号 → 代币；全局唯一性来源 | `init:72`、`launchToken:135` | 只写一次/符号 |
| 18 | `_childTokens` | `mapping(address => address[])` | 父币 → 子币（创建序） | `init:73`、`launchToken:136` | 只追加 |
| 19 | `_remainingLaunchCount` | `mapping(address => mapping(uint256 => uint256))` | 成员**可用**次数 | `launchToken:112`、`mergeLaunchCount:174-175`、`_addLaunchCount:341` | 增/减 |
| 20 | `_issuedLaunchCount` | `mapping(address => uint256)` | 社区**累计已产生**次数 | `_addLaunchCount:340` | 只增 |

## 2. 逐变量变更逻辑

### 2.1 `init`：9 个入参落库 + 首币五处登记（`:54-85`）

| 顺序 | 语句 | 前置守卫 | 说明 |
| --- | --- | --- | --- |
| 1 | `initialized = true`（`:57`） | `if (initialized) revert AlreadyInitialized()`（`:55`） | **先置位再外部调用**，重入 `init` 会被挡 |
| 2 | 9 个参数赋值（`:58-66`） | 无校验（部署脚本负责） | 任一为错只能重部署 |
| 3 | `_createToken(ROOT, name, symbol, distributor)`（`:68`） | 名称/符号非空、长度上限（`:242-248`） | 内部两次外部调用：`new LOVE20Token`、`factory.getPair/createPair` |
| 4 | `FIRST_TOKEN_ADDRESS = firstToken`（`:69`） | `_createToken` 已返回 | — |
| 5 | `_tokens.push` / `_parentTokenByTokenAddress` / `_tokenAddressBySymbol` / `_childTokens[ROOT].push`（`:70-73`） | — | 四本账同时落账 |
| 6 | `IMemberNFT(...).init(firstToken)`（`:75`） | — | 外部调用；若 MemberNFT 已被抢跑，这里回滚 → **整个 `Launch.init` 作废** |
| 7 | `GenesisTokenCreated`（`:78-84`） | — | 首币不发 `TokenLaunched` |

`init` 的写入顺序有一个重要性质：**首币不经过 `_checkValidTokenSymbol`**（不走 `TOKEN_SYMBOL_LENGTH`），因此首币符号长度可以与其他子币不同；首币符号直接成为 `_tokenAddressBySymbol` 的第一个键，不做冲突校验（此时也不可能有冲突）。

### 2.2 `launchToken`：六本账 + 一次扣减（`:91-152`）

| 顺序 | 位置 | 语句 | 同函数内的前置守卫 |
| --- | --- | --- | --- |
| 1 | `:99` | `_checkValidTokenSymbol(tokenSymbol)` | 长度 `== TOKEN_SYMBOL_LENGTH`；字符集 `A-Z`（首位）/ `A-Z0-9`（非首位）/ CJK 基本区（`:267-307`） |
| 2 | `:100-101` | `distributor != 0`、`_checkDistributorMode` | `Callback` 时 `distributor.code.length != 0` |
| 3 | `:103-105` | 父币存在性 | `parent == ROOT` 或 `isLOVE20Token(parent)`，否则 `ParentTokenNotRegistered` |
| 4 | `:107-108` | 读 `_remainingLaunchCount[parent][memberId]` | `== 0` 回滚 `InsufficientLaunchCount(memberId, 0, 1)`（经 modifier 已确认调用者持有 `memberId`） |
| 5 | **`:112`** | `_remainingLaunchCount[parent][memberId] = available - 1` | **扣减发生在所有外部调用之前**（CEI 正确），并发 `LaunchCountConsumed`（`:114-118`） |
| 6 | `:121` | `ILOVE20Token(parent).symbol()` | **外部调用（`view` → `STATICCALL`）**；root 父币来自外部（WBNB），其余父币是本合约创建过的 `LOVE20Token`；不构成状态重入向量 |
| 7 | `:125-128` | 计算最终符号并查重 | `_tokenAddressBySymbol[final] != 0` → `TokenSymbolAlreadyExists` |
| 8 | `:132` | `_createToken(...)` | 内部：`new LOVE20Token`（`:250-252`）→ `getPair`（`view`）→ 若为 0 则 `createPair`（**非 view，唯一重入向量**，`:254-260`） |
| 9 | `:133-136` | `_tokens` / `_parentTokenByTokenAddress` / `_tokenAddressBySymbol` / `_childTokens` | **四本账在外部调用之后才落**；可信 factory 下无影响，恶意 factory 的重入窗口见 `LCH-05` |
| 10 | `:139-147` | `TokenLaunched` | — |
| 11 | `:149-151` | distributor 回调 | 状态已完整，重入安全 |

### 2.3 `mergeLaunchCount`：两侧同时写（`:154-185`）

```
源计数 s → s - count；目标计数 t → t + count
```
守卫：`onlyMemberOwner(source)`（modifier，首条）→ `source != target` → `count != 0` → `token` 已登记或为 root → 目标 `ownerOf` 存在（`:167`，只判存在）→ `s >= count`。

两个键不同（`:158-160` 已排除相等），所以读旧值再写不存在别名问题；`targetRemaining` 用的是写源之前的存储值，与源无关。

### 2.4 `addLaunchCount` → `_addLaunchCount`：只增（`:187-204`、`:334-349`）

| 位置 | 语句 | 守卫 |
| --- | --- | --- |
| `:191` | `count != 0` | — |
| `:192` | `isLOVE20Token(token)` | 排除 root（root 不经此入口） |
| `:194-197` | `count > MAX_LAUNCH_COUNT - issuedCount` 回滚 | **先比较再相加**，不做 `issued + count`，大 `count` 不会以溢出收场 |
| `:340` | `_issuedLaunchCount[token] = issued + count` | — |
| `:341` | `_remainingLaunchCount[token][memberId] += count` | — |
| `:342-348` | `LaunchCountAdded`（后置 `issuedCount` 与 `memberRemaining`） | — |
| `:201-203` | 若 `token == FIRST`，对 `ROOT` 重复一次 `_addLaunchCount` | 同一笔内，伴生 |

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| L1 | `_tokens[0] == FIRST_TOKEN_ADDRESS`，且每枚代币恰出现一次 | ✅ | `init` 先 push 首币；`launchToken` 每笔 push 一次新部署地址 |
| L2 | `isLOVE20Token(t)` ⟺ `_parentTokenByTokenAddress[t] != 0` | ✅ | 只有两处写入，且都同时写 `_tokens` |
| L3 | 对每个成功发射的代币 `t`，`_tokenAddressBySymbol[symbol(t)] == t` | ✅（生产依赖下） | 写入在 `:135`；`createPair` 只对恶意 factory 存在重入窗口（`LCH-05`，按信任假设判为不可达） |
| L4 | `_childTokens[p]` 恰为「父币为 `p` 的代币」按创建序 | ✅ | `init` 与 `launchToken` 各 push 一次；`p` 不存在的条目为空 |
| L5 | `Σ_m _remainingLaunchCount[t][m] == _issuedLaunchCount[t] − 已消耗[t]` | ✅ | 只有 `_addLaunchCount` 增、`launchToken` 减一、`merge` 在成员间搬移 |
| L6 | `_issuedLaunchCount[ROOT] == _issuedLaunchCount[FIRST]` | ✅ | `FIRST` 分支的伴生写入是唯一写 root 的路径（`:201-203`） |
| L7 | `_issuedLaunchCount[t] <= MAX_LAUNCH_COUNT` | ✅ | `addLaunchCount` 的差值比较（`:195`）；root 由 L6 传递 |
| L8 | `_remainingLaunchCount[t][m] <= _issuedLaunchCount[t]` | ✅ | 由 L5、L6 与「消耗不减 `issued`」推出 |

L6/L7 是「根级账本有界」的完整证明：root 维度的 `issued` 不是独立计数，而是 `FIRST` 的镜像，所以根级容量天然被同一个 `MAX_LAUNCH_COUNT` 约束。但**消耗**在两个维度各自发生，因此一个社区的实际上限是 `2 × MAX_LAUNCH_COUNT` 次发射（既有审查 `LCH-02` 的经济结论；本卷从账本口径复核，结论一致）。

## 4. 发现

### LCH-05 · 符号唯一性对恶意 factory 的重入假设（不可达，Info）

| 字段 | 值 |
| --- | --- |
| 位置 | `Launch:126`（查重）、`Launch:132`（`_createToken` → `factory.createPair`）、`Launch:135`（符号落账） |
| 类别 | 写入顺序 / 部署期信任假设 |
| 级别 | **Info** |
| 前置条件 | `PAIR_FACTORY_ADDRESS` 是恶意或可升级、且会在 `createPair` 中回调的合约（部署期参数） |
| 证据 | E1 |

**机制**：唯一性判据是 `_tokenAddressBySymbol[final] != 0`（`:126`），而该键要到 `:135` 才写入。`:132` 的 `_createToken` 里会在 `getPair` 返回 0 时调用非 view 的 `factory.createPair`（`:258`）。若 factory 在 `createPair` 里再次进入 `launchToken`（同一 `parent`、同一 `tokenSymbol`、且该成员还有余量），第二次调用看到的仍是空键，于是：

1. 两枚代币用同一个最终符号被创建（`L3` 在恶意 factory 下不成立）；
2. `_tokens` 与 `_childTokens` 各多一条（`L1`/`L4` 仍成立，但集合里出现同符号两项）；
3. `_tokenAddressBySymbol[final]` 只保留后写入的那一枚，前一枚**再也无法通过符号查到**；
4. 两笔各扣一次次数（`L5` 不受影响）。

**为什么是 Info 而不是 Low**：

- `:121` 的 `ILOVE20Token(parent).symbol()` 继承自 `IERC20Metadata`，是 `view`，编译成 `STATICCALL`；回调里做 `launchToken` 这种状态写入会直接 revert。root 父币（WBNB）和已登记的 `LOVE20Token` 都不构成这个向量。
- `factory.getPair` 也是 `view`（STATICCALL），只有 `createPair` 是非 view。也就是说，唯一的重入向量是**恶意或可升级的 factory**。
- factory 是部署期可信依赖。生产部署用 UniswapV2Factory，不会回调；如果 factory 本身不可信，它能做的远不止重入造同符号币（例如返回假 pair、跳过 `createPair`、给出错误的 Pair 地址），同符号只是其中一个表征，不构成独立风险。

**建议**：按当前信任模型**不需要改代码**。如果未来换成可升级/可回调的 factory，再考虑把最终符号的预留写提到 `_createToken` 之前（`:126` 查重通过后写 `_tokenAddressBySymbol[final] = address(this)` 作哨兵，`_createToken` 返回后再覆盖真实地址），作为可选硬化，2-3 行，不改变 ABI。

### LCH-06 · 首币路径不受符号长度与字符集校验

| 字段 | 值 |
| --- | --- |
| 位置 | `Launch:68`（`init` 直接 `_createToken`）、`:238-248`（只判非空与 32 字节上限） |
| 级别 | Info |
| 证据 | E1 |

首币绕开 `_checkValidTokenSymbol`（`:267`），只受 `MAX_TOKEN_SYMBOL_LENGTH = 32` 约束。这是**有意**的（规格 `08-launch.md:31`：首币符号长度可与子币不同），但它意味着 `_tokenAddressBySymbol` 的第一个键可能包含任意 UTF-8（含小写、空格以外的不可见字符）。子币符号唯一性是对「最终符号」比较，所以一个奇怪的首币符号不会破坏唯一性，只会让 `tokenAddressBySymbol` 的键空间不受字符集约束。记录，不建议改。

## 5. 已核对为正确的点

- `initialized` 在 `init` 的**第一笔写入**，且早于 `new LOVE20Token`、`createPair`、`MemberNFT.init` 三次外部调用；`init` 重入必然命中 `AlreadyInitialized`。
- 发射计数在外部调用之前扣减（`:112`），`launchToken` 的任何后续失败都整笔回滚，不会「扣了次数没发币」。
- 上限判定用 `count > MAX - issued` 而不是 `issued + count > MAX`，极端 `count` 不会以算术溢出收场（与规格 `08-launch.md:65` 一致）。
- `mergeLaunchCount` 先判目标存在（`:167`）再读源余量，`memberId == 0` 与不存在走同一个 `ownerOf` 回滚。
- 根级伴生写入与首币写入同笔（`:199-203`），没有「首币加了、root 没加」的中间态。
- `_addLaunchCount` 的两条事件都带后置值（`issuedCount`、`memberRemaining`），账本可从事件逐笔折叠。

## 6. 覆盖缺口

- 未构造恶意 factory 的 PoC；`LCH-05` 已按部署期信任假设判为不可达，不再升级。
- 未审 `LOVE20Token` 构造函数在 `_createToken` 内的 gas 与 `distributor` 为合约时的行为（ERC20 无回调，风险为零）。

行号基准 `0466d67`。
