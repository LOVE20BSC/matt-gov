# Launch 与 TokenFactory

Launch 负责基础发射与次数账本；TokenFactory 负责创建 LOVE20Token。首币启动不另设合约或外部入口，也不创建独立 `launch` 仓库。

## 初始化和首个代币

首币参数与依赖在同一次 `Launch.init` 中传入；供应量在工厂初始化固定，不在 Launch 再保存一份：

由 `init` 固定的 Launch 配置状态变量使用大写 `public` 命名并直接提供同名 getter：`LAUNCH_RATIO`、`MAX_LAUNCH_COUNT` 和 `TOKEN_SYMBOL_LENGTH`。

完整 ABI 见 [`ILaunch.sol`](../../../interfaces/core/ILaunch.sol)。

初始化分两笔交易，顺序固定：

1. 先部署全部合约取得地址，`TokenFactory.init(launchAddress, mintAddress, launchAmount, maxSupply)` 固定工厂的创建调用方、minter 和供应量参数。
2. 再提交 `Launch.init(...)`。同一笔交易内完成：写入依赖和发射参数、调用 `TokenFactory.createToken(rootParentToken, name, symbol, distributor)` 创建首币、登记首币，并同步调用 `MemberNFT.init(tokenAddress)` 完成其初始化；MemberNFT 不保存 Launch 地址。

两个 `init` 都不保存或校验部署者地址，各自只允许成功一次；成功后 `initialized()` 为 `true`，Launch 与 TokenFactory、MemberNFT 一致地公开该状态供检查脚本核对。检查脚本随后读取 `initialized()`、依赖地址和参数核对结果；参数错误则该部署版本不对外发布。

首币不消耗成员发射次数，也不接收或处理 Launch KV 数组，固定采用 `NoCallback`。`Launch.init` 任一步失败回滚全部效果；成功后不得重初始化、替换依赖或改写首币。Pair 在首次 LP 质押时由 `Stake` 按需查询或创建，Launch 不创建 Pair，也不重复铸造首批供应。部署参数的含义见 [参数表](00-protocol-model.md#初始化参数)。

`Launch.init` 的校验与回滚：

| 条件 | 回滚错误 |
| --- | --- |
| 任一地址参数（含首币 `distributor`）为零 | `InvalidAddress()` |
| `launchRatio == 0`、`maxLaunchCount == 0` 或 `tokenSymbolLength == 0` | `ZeroAmount("launchRatio")` / `ZeroAmount("maxLaunchCount")` / `ZeroAmount("tokenSymbolLength")` |
| 首币名称或符号为空 | `EmptyString("name")` / `EmptyString("symbol")`，由 `TokenFactory.createToken` 回滚 |
| 重复初始化 | `AlreadyInitialized()` |

首币符号不套用 `TOKEN_SYMBOL_LENGTH` 校验：旧实现的第一个代币走 `tokensCount() == 0` 分支，跳过符号校验与名称拼接；BSC 版由 `init` 参数直接给定首币名称和符号，因此首币符号长度可以与配置的子币符号长度不同。

首币 `distributor` 为 Burn 活动结束后由旧 `LOVE20TKM/burn` 来源单独部署的 Airdrop；Burn 业务不迁移。旧仓库只读，来源提交、来源区块、Merkle Root、部署地址及公开源码证据见 [仓库清单](../../repositories.md)。不能把部署外部 Airdrop 误写为改造旧仓库。

## 发射次数账本

Launch 只保存“成员可用整数次数”和“社区累计已产生次数”；次数如何从治理激励产生见 [Mint 的发射额度](07-mint.md#发射额度的生成)。

| 账本 | 所属与作用域 |
| --- | --- |
| `launchCount[tokenAddress][memberId]` | Launch 保存成员可用整数次数 |
| `issuedLaunchCount[tokenAddress]` | Launch 保存社区累计已产生次数；消耗与融合都不减少 |
| `MAX_LAUNCH_COUNT` | 每社区累计次数上限 |

- `launchCount` 与 `issuedLaunchCount` 对任意 `tokenAddress`、`memberId` 可查询；未登记的 token 返回 `0`，不校验也不回滚。
- `addLaunchCount(tokenAddress, memberId, count)` 只允许 Mint 调用，其他调用者回滚 `UnauthorizedCaller()`。
- `tokenAddress` 必须是已登记 LOVE20 代币，否则回滚 `InvalidTokenAddress()`；`count` 必须大于 `0`，否则回滚 `CountMustBeGreaterThanZero()`。
- 必须满足 `issuedLaunchCount + count <= MAX_LAUNCH_COUNT`，否则回滚 `LaunchCountLimitReached()`（Mint 已按剩余额度截断，此处是兜底）。
- 只增加 `launchCount` 与 `issuedLaunchCount`，与治理激励铸造整体回滚；次数被消耗或融合都不释放累计上限。
- 未初始化时 `addLaunchCount`、`mergeLaunchCount`、`launchToken` 三个写入口回滚 `UnauthorizedCaller()`。

## 次数融合

源、目标必须不同且存在，`count > 0`，源次数足够。只校验调用者持有源 NFT，不要求持有目标。成功后原子扣减源次数、增加目标次数；不转移 `launchCredit`，不改变其他质押、投票、发射历史或事件，也不减少目标既有状态。此操作可用于 NFT 场外交易。

| 条件 | 回滚错误 |
| --- | --- |
| `tokenAddress` 不是已登记 LOVE20 代币 | `InvalidTokenAddress()` |
| `sourceMemberId == targetMemberId` | `SourceAndTargetMustBeDifferent()` |
| `count == 0` | `CountMustBeGreaterThanZero()` |
| 调用者不持有源 MemberNFT | `NotMemberOwner(sourceMemberId)` |
| 源可用次数小于 `count` | `NotEnoughLaunchCount()` |
| 未初始化 | `UnauthorizedCaller()` |

目标 `memberId` 不存在（含 `0`）时由 MemberNFT 的标准错误经 `ownerOf` 回滚，Launch 不为其新增自有错误；`memberId` 不从 `0` 开始，`0` 永远无效。

## 普通发射

当前成员 NFT 持有人可发射社区子币，消耗其一次 `launchCount`。发射流程按检查、更新、交互执行并防重入：先验证成员次数和代币参数，扣减次数，再创建子币、分发首批供应并调用 distributor。外部失败时子币创建和次数消耗全部回滚。

发射、次数和代币查询接口均见 [`ILaunch.sol`](../../../interfaces/core/ILaunch.sol)。

`memberId` 必须由调用者当前持有；不用地址默认 NFT 映射。发射只检查账本余量和 NFT 当前所有权，不要求推举资格：旧 `remainingLaunchCount` 中的 `Submit.canSubmit` 门槛已取消，`submitAddress` 依赖同步删除。名称沿用旧 Launch 的 `tokenSymbol + "@" + parentSymbol` 生成方式。

`tokenSymbol` 的合法性沿用旧实现：长度必须等于部署配置的符号长度；首字符必须为 ASCII `A-Z`；其余字符必须为 ASCII `A-Z` 或 `0-9`。不满足时回滚 `InvalidTokenSymbol()`。

测试网前缀沿用旧实现：先按配置长度校验 `tokenSymbol`，再读取 `parentTokenAddress` 的符号，其前 4 字节等于 `Test` 时给符号加上 `Test` 前缀，然后生成名称。该前缀施加在校验之后，因此测试网子币的实际符号可以超出配置长度；首币不施加该前缀。

普通发射的社区必须与 `parentTokenAddress` 一致，父币必须是已登记 LOVE20 代币，`distributor` 非零。分发支持 `NoCallback` 和 `Callback` 两种模式。Launch 回调使用本次发射的 `keys`/`values` 数组；两数组可以同时为空，非空时必须等长：

分发回调接口见 [`ILaunchDistributor.sol`](../../../interfaces/core/ILaunchDistributor.sol)。

`NoCallback` 不调用回调且要求两数组为空；`Callback` 要求 `distributor` 为合约并调用 `onTokenLaunched`，原样透传 Launch KV，回调失败则整笔发射回滚。首币使用旧 Burn `Airdrop`，固定采用 `NoCallback`；普通发射才可选择 `Callback`。

回调仅由 Launch 调用，发生于代币创建、首批供应到账、代币登记与次数扣减之后；`launcherMemberId` 取本次 `memberId`。distributor 校验调用方并防止同一 token 重复处理；Launch 不开放额外的补触发回调入口。两种模式均允许非零合约接收，EOA 仅允许 NoCallback。

distributor 自行实现领取与查询逻辑，`claim(tokenAddress)` 只是建议接口，不是协议必需 ABI。发射者负责选择分发目标，承担其失败和 Gas 耗尽风险。

| 条件 | 回滚错误 |
| --- | --- |
| 未初始化 | `UnauthorizedCaller()` |
| 调用者不持有 `memberId` | `NotMemberOwner(memberId)` |
| `launchCount[parentTokenAddress][memberId] == 0` | `NotEnoughLaunchCount()` |
| `tokenSymbol` 不合法 | `InvalidTokenSymbol()` |
| `parentTokenAddress` 不是已登记 LOVE20 代币（含零地址） | `InvalidParentToken()` |
| `distributor == address(0)` | `InvalidAddress()` |
| 两数组非等长，或 `NoCallback` 下两数组非空 | `InvalidKVLength()` |
| `Callback` 但 `distributor` 不是合约 | `InvalidDistributorMode()` |
| `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚） |

子币符号不要求全局唯一：Launch 不保存 `tokenAddressBySymbol` 账本，名称只按 `tokenSymbol + "@" + parentSymbol` 生成。

## TokenFactory

保留旧工厂“初始化配置 + 创建代币”的职责。来源为 `LOVE20TKM/core/src/LOVE20TokenFactory.sol`（提交见[旧代码基线](../../repositories.md#旧代码基线)）；BSC 新增 `distributor`，删除 Pair、SL/ST 创建及相关依赖，Pair 生命周期移入 `Stake`。LOVE20Token 的完整参数在构造函数中一次传入，不再提供 `init`。

初始化接口见 [`ITokenFactory.sol`](../../../interfaces/core/ITokenFactory.sol)。

工厂初始化一次，固定 Launch、Mint、首批供应量和最大供应量；`init` 可由任意地址提交，不保存部署者地址，也不授予部署者特权，发布前由检查脚本核验参数。零地址使用 `ZeroAddress(parameter)`，空名称或符号使用 `EmptyString(parameter)`，供应量关系错误使用 `InvalidAmount()`。对应常量 getter 保留旧命名 `LAUNCH_AMOUNT()`、`MAX_SUPPLY()`，初始化参数 `launchAmount <= maxSupply`。Stake 自行依赖符合 Uniswap V2 接口的 Pair Factory，并在首次 LP 质押时查询或创建 Pair。

创建接口见 [`ITokenFactory.sol`](../../../interfaces/core/ITokenFactory.sol)。

仅已初始化工厂允许 Launch 调用。父币或 distributor 为零、名称或符号为空时拒绝。创建时原子执行：

1. 创建 LOVE20Token，使用工厂固定的供应参数，将 `initialSupply` 直接铸给 distributor，不先交给 Launch。
2. LOVE20Token 构造函数直接写入父币和 Mint 权限；不创建 Pair 或 SL/ST，质押账本仍在 Stake。
3. 发出代币创建事件并返回 tokenAddress；任一步失败全部回滚。

父币是否已登记 LOVE20 代币、发射次数和分发回调由 Launch 检查。首币使用 WBNB，普通子币使用已登记 LOVE20 父币。

## 实现约束

TokenFactory 的事件和错误定义见 [`ITokenFactory.sol`](../../../interfaces/core/ITokenFactory.sol)；LOVE20Token 的公开 ABI 见 [`ILOVE20Token.sol`](../../../interfaces/core/ILOVE20Token.sol)。

LOVE20Token 使用构造函数接收 `name`、`symbol`、`initialSupply`、`maxSupply`、`distributor`、`minter` 和 `parentTokenAddress`；构造函数不属于 Solidity `interface` ABI。其运行时函数、事件和错误以 [`ILOVE20Token.sol`](../../../interfaces/core/ILOVE20Token.sol) 为准。

- LOVE20Token 不提供 `init`；构造函数直接接收 `name`、`symbol`、`initialSupply`、`maxSupply`、`distributor`、`minter` 和 `parentTokenAddress`。
- `MemberNFT.init(firstToken)` 由 `Launch.init` 在创建首币时同步调用完成；MemberNFT 不保存 Launch 地址，费用代币地址是唯一外部地址依赖。

旧来源 `LOVE20TKM/core/src/LOVE20Launch.sol`（提交见[旧代码基线](../../repositories.md#旧代码基线)）已逐项核对。BSC 版**保留**的旧行为只有四项：`isLOVE20Token` 的登记判定、`tokenSymbol` 的长度与字符集校验、`tokenSymbol + "@" + parentSymbol` 名称拼法与测试网 `Test` 前缀、`launchToken` 的“检查—创建—登记”外部调用骨架。其余整块删除：公平发射募资与认购领取（`contribute`/`withdraw`/`claim`/`claimInfo`）、`LaunchInfo`、`CLAIM_DELAY_BLOCKS`、代币枚举接口和 `tokenAddressBySymbol` 账本。次数阈值换算、额度余数结转、社区上限和次数融合都不在旧实现中，属新设计，见 [Mint 的发射额度](07-mint.md#发射额度的生成)。

验收见 [Core 验收](09-testing.md)。
