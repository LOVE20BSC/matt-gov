# Launch

Launch 负责首币部署、LOVE20Token 创建、基础发射与次数账本。Token 创建逻辑与 Launch 合并，不再部署独立的 `TokenFactory` 合约。

## 初始化和首个代币

首币参数、依赖和供应量配置在同一次 `Launch.init(LaunchInitParams)` 中传入并固定：

由 `init` 固定的 Launch 配置状态变量使用大写 `public` 命名并直接提供同名 getter：`LAUNCH_RATIO`、`MAX_LAUNCH_COUNT`、`TOKEN_SYMBOL_LENGTH`、`LAUNCH_AMOUNT` 和 `MAX_SUPPLY`。

完整 ABI 见 [`ILaunch.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILaunch.sol)。

初始化为一笔交易：

1. 部署全部合约取得地址，提交 `Launch.init(LaunchInitParams)`。同一笔交易内完成：写入依赖（含 Pair Factory）、发射参数和供应量配置，创建首币、**创建或复用首币的 Pair**、登记首币，并同步调用 `MemberNFT.init(tokenAddress)` 完成其初始化；MemberNFT 不保存 Launch 地址。

`Launch.init` 不保存或校验部署者地址，只允许成功一次；成功后 `initialized()` 为 `true`。该初始化仍存在被抢先绑定的窗口：被抢跑的版本不得发布，必须重新部署并核对受影响的依赖，不把“部署后立即初始化”当作防抢跑保证。部署是否成功由发布前检查脚本判定——逐项核对 `initialized()`、依赖地址、首币名称与符号、首币分发地址、发射参数和供应量配置，任何不一致即重新部署。

首币不消耗成员发射次数，不带分发数据，固定采用 `NoCallback`。`Launch.init` 任一步失败回滚全部效果；成功后不得重初始化、替换依赖或改写首币；`init` 把首币地址记录为 `firstTokenAddress` 并通过同名 getter 公开，首币身份不得再由「父币是根父币」推断——根级发射创建的同级币与首币有相同的父币（见[根级次数与伴生规则](#根级次数与伴生规则)）。**Launch 拥有 Pair 生命周期**：每创建一个代币（首币与子币相同），都在同一笔交易内查询 `pairFactoryAddress.getPair(tokenAddress, parentTokenAddress)`；不存在时调用 `createPair`，已存在时复用该 Pair，因此预先存在的正确 Pair 不会阻断发射；`Stake` 只在首次质押时读取并保存该地址，不创建 Pair。Launch 不重复铸造首批供应。部署参数的含义见 [参数表](00-protocol-model.md#初始化参数)。

`Launch.init` 的校验与回滚：

| 条件 | 回滚错误 |
| --- | --- |
| 重复初始化 | `AlreadyInitialized()` |
| 任一地址参数（含首币 `distributor`）为零 | `InvalidAddress()` |
| `launchRatio == 0`、`maxLaunchCount == 0` 或 `tokenSymbolLength == 0` | `ZeroAmount("launchRatio")` / `ZeroAmount("maxLaunchCount")` / `ZeroAmount("tokenSymbolLength")` |
| `launchRatio > 1e18` | `InvalidAmount()`；恰好 `1e18` 合法 |
| `launchAmount == 0` | `ZeroAmount("launchAmount")` |
| `launchAmount > maxSupply` | `InvalidAmount()` |
| 首币名称或符号为空 | `EmptyString("name")` / `EmptyString("symbol")`，属于 `init` 参数校验 |
| 首币建池返回零地址 | `InvalidAddress()` |

`launchAmount` 必须大于零，`maxSupply` 必须不小于 `launchAmount`，即 `0 < launchAmount <= maxSupply`；两者相等是合法配置。零供应代币不可创建：LOVE20Token 构造函数独立拒绝零 `initialSupply`，绕过 `init` 直接部署同样回滚 `InvalidSupply()`。

首币符号不套用 `TOKEN_SYMBOL_LENGTH` 校验：旧实现的第一个代币走 `tokensCount() == 0` 分支，跳过符号校验与测试网 `Test` 前缀（名称仍按 `tokenSymbol + "@" + parentTokenSymbol` 拼接）；BSC 版由 `init` 参数直接给定首币名称和符号，因此首币符号长度可以与配置的子币符号长度不同。

首币 `distributor` 为 Burn 活动结束后由旧 `LOVE20TKM/burn` 来源单独部署的 Airdrop；Burn 业务不迁移。旧仓库只读，来源提交、来源区块、Merkle Root、部署地址及公开源码证据见 [仓库清单](../../repositories.md)。不能把部署外部 Airdrop 误写为改造旧仓库。

## 代币登记与查询

`isLOVE20Token(tokenAddress)` 是登记状态的唯一判定入口：`init` 登记首币，`launchToken` 登记新创建的子币。对首币与所有由 Launch 创建的子币返回 `true`；对其余任何地址（WBNB、EOA、其它合约，以及未初始化时的全部地址）返回 `false`，不校验也不回滚。登记只写一次，不提供删除或改写入口。根父币（BSC 上为 WBNB）不在登记范围内，但承载根级次数，并作为根级同级币的父币维度参与 `childTokens` 查询：`isLOVE20Token(rootParentTokenAddress)` 始终为 `false`（见[根级次数与伴生规则](#根级次数与伴生规则)）。

登记状态记录为「代币地址 → 父币地址」，由 Launch 自己维护：非零即已登记，首币的父币地址是 `rootParentTokenAddress`。`parentTokenOf(tokenAddress)` 是读取入口，`isLOVE20Token` 也用它判定，不读取代币合约的 `parentTokenAddress()`：无关合约同样能实现这个 getter，而 EOA 与非合约地址调用它会回滚，与上面的返回约定冲突。

Launch 维护四个查询账本，都由上述两个入口写入：

| 账本 | 作用 |
| --- | --- |
| 创建顺序的已发射代币列表 | `tokens(offset, limit, reverse)` 分页读取；包含首币 |
| 代币地址到父币地址 | `parentTokenOf(tokenAddress)` 单点读取；未登记地址返回零地址 |
| `parentTokenAddress` 到子币列表 | `childTokens(parentTokenAddress, offset, limit, reverse)` 分页读取；`childTokens(rootParentTokenAddress)` 返回首币 |
| 符号到代币地址 | `tokenAddressBySymbol(symbol)` 单点读取；首币与子币都登记，因此子币符号全局唯一 |

分页语义与 `Phase.syncObservations` 一致：`offset` 大于或等于总数时返回空数组与真实 `totalCount`，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时按从新到旧返回。未登记过的父币地址返回空数组与 `0`。分页查询都不限制写入条数，链上不提供全量遍历，只按页读取。

子币符号必须全局唯一：`launchToken` 用施加 `Test` 前缀后的最终符号查询 `tokenAddressBySymbol`，已存在则回滚 `TokenSymbolExists()`；首币符号在 `init` 登记时不需要冲突校验。

## 发射次数账本

Launch 只保存“成员可用整数次数”和“社区累计已产生次数”；次数如何从治理激励产生见 [Mint 的发射额度](07-mint.md#发射额度的生成)。`tokenAddress` 维度除已登记代币外还包括根父币：根父币维度的次数称根级次数，只能由首币次数的伴生规则写入（见[根级次数与伴生规则](#根级次数与伴生规则)）。

| 账本 | 所属与作用域 |
| --- | --- |
| `launchCount[tokenAddress][memberId]` | Launch 保存成员可用整数次数 |
| `issuedLaunchCount[tokenAddress]` | Launch 保存社区累计已产生次数；消耗与融合都不减少 |
| `MAX_LAUNCH_COUNT` | 每社区累计次数上限；根级累计由伴生不变式约束在同一上限内 |

- `launchCount` 与 `issuedLaunchCount` 对任意 `tokenAddress`、`memberId` 可查询；未登记的 token 返回 `0`，不校验也不回滚（根父币未登记但承载根级次数，返回真实账本值）。
- `addLaunchCount` 只允许 Mint 调用，其他调用者回滚 `UnauthorizedCaller()`。校验顺序固定为参数 → 存在性 → 账本：`count` 必须大于 `0`，否则回滚 `CountMustBeGreaterThanZero()`；`tokenAddress` 必须是已登记 LOVE20 代币，否则回滚 `InvalidTokenAddress()`——根父币不经过本入口，其次数只由首币伴生在同一调用内追加；必须满足 `issuedLaunchCount + count <= MAX_LAUNCH_COUNT`，否则回滚 `LaunchCountLimitReached()`（Mint 已按剩余额度截断，此处是兜底）。上限判断不得依赖加法结果：任何使累计次数超过上限的 `count`（含极端大值）都必须回滚 `LaunchCountLimitReached()`，不能以算术溢出回滚收场。
- 只增加 `launchCount` 与 `issuedLaunchCount`，与治理激励铸造整体回滚；次数被消耗或融合都不释放累计上限。
- 只有 `init` 校验初始化状态：`addLaunchCount`、`mergeLaunchCount` 和 `launchToken` 不重复校验 `initialized`（未成功初始化的版本不会发布，见 [通用规则](01-common-rules.md#初始化与安全)），它们的失败由各自的权限、参数与存在性校验决定。

## 根级次数与伴生规则

根父币（BSC 上为 WBNB）维度的次数称为根级次数：它用于发射与首币平级、父币同为根父币的同级代币。根级次数只作用于首币：首币每次通过 `addLaunchCount` 产生整数次数时，Launch 在同一调用内把同一 `count` 1:1 记入 `launchCount[rootParentTokenAddress][memberId]` 与 `issuedLaunchCount[rootParentTokenAddress]`，并追加一条 `LaunchCountAdded`（`tokenAddress` 为根父币）；其他代币产生次数时不伴生，其他代币也不能产生根级次数。

- 伴生与首币次数增加发生在同一笔交易：`addLaunchCount` 由 Mint 调用并与治理激励铸造整体回滚，根级伴生同样整体回滚。
- 根父币维度不由 `addLaunchCount` 的外部入口写入：Mint 直接以根父币为 `tokenAddress` 调用会按存在性校验回滚 `InvalidTokenAddress()`。
- 不变式：`issuedLaunchCount[rootParentTokenAddress] == issuedLaunchCount[firstTokenAddress]`，且两者都不超过 `MAX_LAUNCH_COUNT`。根级发行因此自动有界，不引入独立的根级上限参数。
- 首币由 `init` 创建、不产生发射次数，根级累计从 `0` 开始；次数消耗与融合都不触发伴生，也不改变 `issuedLaunchCount`。

## 次数融合

源、目标必须不同且存在，`count > 0`，源次数足够。只校验调用者持有源 NFT，不要求持有目标。成功后原子扣减源次数、增加目标次数；不转移 `launchCredit`，不改变其他质押、投票、发射历史或事件，也不减少目标既有状态。此操作可用于 NFT 场外交易。融合对已登记代币与根父币两个维度同规则：根级次数同样可融合。

校验顺序固定为参数 → 存在性 → 持有 → 账本：先校验参数（源与目标不同、`count > 0`），再校验存在性（`tokenAddress` 已登记或为根父币、源与目标 `memberId` 都存在），然后校验调用者持有源 MemberNFT，最后校验源可用次数。

| 条件 | 回滚错误 |
| --- | --- |
| `sourceMemberId == targetMemberId` | `SourceAndTargetMustBeDifferent()` |
| `count == 0` | `CountMustBeGreaterThanZero()` |
| `tokenAddress` 不是已登记 LOVE20 代币且不是根父币 | `InvalidTokenAddress()` |
| 源或目标 `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚） |
| 调用者不持有源 MemberNFT | `NotMemberOwner(sourceMemberId)` |
| 源可用次数小于 `count` | `NotEnoughLaunchCount()` |

不存在的 `memberId` 由 MemberNFT 的标准错误经 `ownerOf` 回滚，Launch 不为其新增自有错误；`memberId` 不从 `0` 开始，`0` 永远无效。

## 普通发射

当前成员 NFT 持有人可发射社区子币，消耗其一次 `launchCount`。发射流程按「检查 → 更新 → 交互」执行：先按参数 → 存在性 → 持有 → 账本的顺序完成检查，扣减一次次数，再创建子币、登记、分发首批供应并调用 distributor；以“先更新账本、再外部调用”满足防重入，不引入额外重入锁。外部调用失败时子币创建、登记和次数消耗全部回滚。

发射、次数和代币查询接口均见 [`ILaunch.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILaunch.sol)。

`memberId` 必须由调用者当前持有；不用地址默认 NFT 映射。发射只检查账本余量和 NFT 当前所有权，不要求推举资格：旧 `remainingLaunchCount` 中的 `Submit.canSubmit` 门槛已取消，`submitAddress` 依赖同步删除。名称沿用旧 Launch 的 `tokenSymbol + "@" + parentTokenSymbol` 生成方式。

`tokenSymbol` 按 UTF-8 字节校验：字节长度必须等于部署配置的 `TOKEN_SYMBOL_LENGTH`；首字符必须为 ASCII `A-Z` 或汉字；其余字符必须为 ASCII `A-Z`、`0-9` 或汉字。汉字限定为 CJK 统一表意文字基本区 `U+4E00`–`U+9FFF` 的三字节编码；中英数字可混排，纯汉字符号要求配置长度为 3 的倍数（如配置 6 对应两个汉字）。长度口径与旧实现一致（UTF-8 字节数），字符集在旧实现的 ASCII 基础上扩展出汉字。其余任何字节序列——其他多字节字符、不完整的 UTF-8、超出基本区的码点——都回滚 `InvalidTokenSymbol()`。

测试网前缀沿用旧实现：先按配置长度校验 `tokenSymbol`，再读取前缀判定符号——父币为根父币的根级发射取 `firstTokenAddress` 的符号，其余发射取 `parentTokenAddress` 的符号；判定符号前 4 字节等于 `Test` 时给符号加上 `Test` 前缀，然后生成名称。该前缀施加在校验之后，因此测试网子币的实际符号可以超出配置长度；首币不施加该前缀。根级发射改用首币符号判定，因为根父币符号跨网络共用，不能标记测试网。

普通发射的社区必须与 `parentTokenAddress` 一致，父币必须是已登记 LOVE20 代币或根父币，`distributor` 非零。父币为根父币的发射称为根级发射：消耗根级次数，创建与首币平级、父币同为根父币的同级币；除父币与次数维度外，创建、登记、子币列表、Pair、分发与回调与普通发射完全一致。分发支持 `NoCallback` 和 `Callback` 两种模式。普通发射携带一个 `bytes[] distributorData` 数组；可以为空，不设长度上限，元素内容与编码由 distributor 自行约定：Launch 只原样透传，不遍历、不解析。

分发回调接口见 [`ILaunchDistributor.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILaunchDistributor.sol)。

`NoCallback` 不调用回调，且忽略 `distributorData`（不校验是否为空）；`Callback` 要求 `distributor` 为合约并调用 `onTokenLaunched`，原样透传 `distributorData`，回调失败则整笔发射回滚。首币使用旧 Burn `Airdrop`，固定采用 `NoCallback`；普通发射才可选择 `Callback`。

回调仅由 Launch 调用，发生于代币创建、首批供应到账、代币登记与次数扣减之后；`launcherMemberId` 取本次 `memberId`。distributor 校验调用方并防止同一 token 重复处理；Launch 不开放额外的补触发回调入口。两种模式均允许非零合约接收，EOA 仅允许 NoCallback。

distributor 自行实现领取与查询逻辑，`claim(tokenAddress)` 只是建议接口，不是协议必需 ABI。发射者负责选择分发目标，承担其失败和 Gas 耗尽风险。

校验顺序固定为参数 → 存在性 → 持有 → 账本 → 扣减 → 最终符号唯一性：先校验参数（`tokenSymbol`、`distributor` 与分发模式），再校验存在性（`parentTokenAddress` 已登记或为根父币、`memberId` 存在），然后校验调用者持有 `memberId`，再校验账本余量并扣减次数，最后按施加 `Test` 前缀后的最终符号校验唯一性。唯一性校验必须排在父币存在性校验之后：最终符号要先读取父币（根级发射为首币）符号才能得到。

`distributorData` 不参与校验：除了分发模式本身，Launch 不对它设任何条件，`NoCallback` 下直接忽略。

| 条件 | 回滚错误 |
| --- | --- |
| `tokenSymbol` 不合法 | `InvalidTokenSymbol()` |
| `distributor == address(0)` | `InvalidAddress()` |
| `Callback` 但 `distributor` 不是合约 | `InvalidDistributorMode()` |
| `parentTokenAddress` 不是已登记 LOVE20 代币且不是根父币（含零地址） | `InvalidParentToken()` |
| `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚） |
| 调用者不持有 `memberId` | `NotMemberOwner(memberId)` |
| `launchCount[parentTokenAddress][memberId] == 0` | `NotEnoughLaunchCount()` |
| 施加 `Test` 前缀后的最终符号已登记 | `TokenSymbolExists()` |
| 子币建池返回零地址 | `InvalidAddress()` |

名称只按 `tokenSymbol + "@" + parentTokenSymbol` 生成，不另存名称账本；根级发射的 `parentTokenSymbol` 取根父币的实际符号（BSC 上为 WBNB，不写死）。

## 事件

事件契约如下；`TokenLaunched` 的 `tokenAddress`、`parentTokenAddress` 和 `launcherMemberId` 带 `indexed`，其余字段用于链下重建。

| 事件 | 触发入口 | 字段取值 |
| --- | --- | --- |
| `TokenLaunched(tokenAddress, parentTokenAddress, launcherMemberId, distributor, name, symbol)` | `init` 创建首币；`launchToken` 每次成功发射 | `tokenAddress` 为新创建的代币地址；`parentTokenAddress` 首币与根级发射为 `rootParentTokenAddress`、其余发射为本次 `parentTokenAddress`；`launcherMemberId` 首币为 `0`（没有发起成员），普通发射为本次 `memberId`；`distributor` 为首批供应接收者；`name` 和 `symbol` 与最终部署的 LOVE20Token 完全一致，子币为加 `Test` 前缀后的最终值，首币为 `init` 参数原值。发出时机在代币创建、首批供应到账、代币登记与次数扣减之后 |
| `LaunchCountAdded(tokenAddress, memberId, count)` | `addLaunchCount`（首币次数附带根级伴生） | `tokenAddress` 为次数账本维度：社区代币，或首币伴生时的根父币；`count` 为本次新增次数 |
| `LaunchCountMerged(tokenAddress, sourceMemberId, targetMemberId, count)` | `mergeLaunchCount` | `count` 为本次融合转移的次数 |

次数消耗不单独发事件：`launchToken` 每次成功都发 `TokenLaunched`，且每次发射恰消耗一次次数，因此消耗历史可由 `TokenLaunched` 重建，余量可用 `launchCount` 直接查询；再发一个消耗事件只会重复同一笔交易的同一事实。

- 首币由 `init` 发出 `TokenLaunched`（`launcherMemberId = 0`）；`init`、`launchToken`、`addLaunchCount`、`mergeLaunchCount` 之外的入口不产生上述事件。
- `TokenLaunched` 同时记录创建和发射所需的代币元数据；不再另发旧 `ILOVE20TokenFactory` 的 `TokenCreate`。
- 链上查询覆盖全部已发射代币、某社区的子币列表和符号到地址（见 [代币登记与查询](#代币登记与查询)）；按成员聚合的发射历史仍由 `TokenLaunched` 的 `launcherMemberId` 链下索引。

## LOVE20Token 创建

`Launch` 直接保存 `LAUNCH_AMOUNT`、`MAX_SUPPLY`，并在内部创建 LOVE20Token。创建时把 `mintAddress` 作为 `minter` 写入 LOVE20Token，把首批供应直接铸给 `distributor`，并在同一笔内向 `pairFactoryAddress` 为该代币建池；不创建 SL/ST。父币是否已登记或为根父币、发射次数和分发回调由 Launch 检查。

## 实现约束

Launch 的事件和错误定义见 [`ILaunch.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILaunch.sol)；LOVE20Token 的公开 ABI 见 [`ILOVE20Token.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILOVE20Token.sol)。

LOVE20Token 使用构造函数接收 `name`、`symbol`、`initialSupply`、`maxSupply`、`distributor`、`minter` 和 `parentTokenAddress`；构造函数不属于 Solidity `interface` ABI。其运行时函数、事件和错误以 [`ILOVE20Token.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILOVE20Token.sol) 为准。

- LOVE20Token 不提供 `init`；构造函数直接接收 `name`、`symbol`、`initialSupply`、`maxSupply`、`distributor`、`minter` 和 `parentTokenAddress`。
- `MemberNFT.init(firstToken)` 由 `Launch.init` 在创建首币时同步调用完成；MemberNFT 不保存 Launch 地址，费用代币地址是唯一外部地址依赖。
- `mintAddress` 在 `init` 后不可变更，并作为此后每个 LOVE20Token 的 `minter`。升级 Mint 需要连同 `Launch` 一起重部署，已发射代币的 `minter` 不会随之改写。

旧来源 `LOVE20TKM/core/src/LOVE20Launch.sol`（提交见[旧代码基线](../../repositories.md#旧代码基线)）已逐项核对。BSC 版**保留**的旧行为：`isLOVE20Token` 的登记判定、`tokenSymbol` 的字节长度口径（字符集在本版扩展出汉字，见[普通发射](#普通发射)）、`tokenSymbol + "@" + parentTokenSymbol` 名称拼法与测试网 `Test` 前缀、`launchToken` 的“检查—创建—登记”外部调用骨架、代币列表与某社区子币列表的链上枚举（旧 `tokensCount`/`tokensAtIndex`、`childTokensCount`/`childTokensAtIndex` 改为分页查询）、符号到地址账本（旧 `tokenAddressBySymbol` 与 `TokenSymbolExists` 唯一性校验），以及代币地址到父币地址（旧 `LaunchInfo.parentTokenAddress`）。其余整块删除：公平发射募资与认购领取（`contribute`/`withdraw`/`claim`/`claimInfo`）、`LaunchInfo` 的其余 10 个字段、`CLAIM_DELAY_BLOCKS`，以及按发射者或募资状态划分的其余枚举（`childTokensByLauncher*`、`launching*`、`launched*`、`participatedTokens*`）。次数阈值换算、额度余数结转、社区上限、次数融合和根级次数伴生都不在旧实现中，属新设计，见 [Mint 的发射额度](07-mint.md#发射额度的生成) 与[根级次数与伴生规则](#根级次数与伴生规则)。

验收见 [Core 验收](09-testing.md)。
