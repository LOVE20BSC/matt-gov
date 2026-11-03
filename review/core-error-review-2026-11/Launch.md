# `core/Launch.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/08-launch.md`。
> 范围：`src/Launch.sol`（350 行）+ `src/interfaces/ILaunch.sol` 的 `ILaunchErrors`。
> 处置：本报告为 `6fdd0f1` 快照；修复与撤回见 [DISPOSITION.md](DISPOSITION.md)。

## 1. 结论

- 19 个错误声明 / 22 个发送点；覆盖完整，无未声明 revert、无裸 `require`。
- `launchToken` 的校验顺序与 08-launch:117 完全一致（鉴权→参数→存在性→账本→扣减→唯一性）；`mergeLaunchCount` 与 08-launch:82 一致。
- 2 条 Low：1 处载荷顺序违反 §4、1 处禁用命名；4 条 Info（`PairCreationFailed` 正常路径不可达、`init` 透传、入口级可达性、Callback 适用性）。
- `init` 的失败集合还包含 LOVE20Token 构造函数的 3 个 selector，`ILaunch` 未声明；见 E-LAU-04。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 19 |
| revert 站点 | 22 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 2 / 4 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `AlreadyInitialized` | `AlreadyInitialized()` | 1 | 保留 |
| `ZeroDistributorAddress` | `ZeroDistributorAddress()` | 1 | 保留 |
| `TokenNameEmpty` | `TokenNameEmpty()` | 1 | 保留（入口级不可达） |
| `TokenSymbolEmpty` | `TokenSymbolEmpty()` | 1 | 保留（入口级不可达） |
| `TokenNameTooLong` | `TokenNameTooLong(uint256,uint256)` | 1 | 保留（入口级不可达） |
| `TokenSymbolTooLong` | `TokenSymbolTooLong(uint256,uint256)` | 1 | 保留（条件可达） |
| `InvalidTokenSymbolLength` | `InvalidTokenSymbolLength(uint256,uint256)` | 1 | 保留 |
| `InvalidTokenSymbolCharacters` | `InvalidTokenSymbolCharacters()` | 1 | 保留 |
| `TokenSymbolAlreadyExists` | `TokenSymbolAlreadyExists(bytes32)` | 1 | 保留 |
| `PairCreationFailed` | `PairCreationFailed(address)` | 1 | 保留需文档化 |
| `ParentTokenNotRegistered` | `ParentTokenNotRegistered(address)` | 1 | 保留 |
| `TokenNotRegistered` | `TokenNotRegistered(address)` | 2 | 保留 |
| `DistributorNotContract` | `DistributorNotContract(address)` | 1 | 保留 |
| `InsufficientLaunchCount` | `InsufficientLaunchCount(uint256,uint256,uint256)` | 2 | 载荷顺序调整 |
| `ZeroCount` | `ZeroCount()` | 2 | 保留 |
| `SourceAndTargetMemberIdsMustBeDifferent` | `SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)` | 1 | 改名建议 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | 1 | 保留 |
| `NotMintContract` | `NotMintContract(address)` | 1 | 保留 |
| `LaunchCountLimitExceeded` | `LaunchCountLimitExceeded(address,uint256,uint256)` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:25`
- 签名：`AlreadyInitialized()`
- 载荷：无
- 核对：无载荷；`init` 自身状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:55` | `init` | `initialized` | `—` |

### `ZeroDistributorAddress` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:26`
- 签名：`ZeroDistributorAddress()`
- 载荷：无
- 核对：无载荷；`distributor` 可为 EOA，零地址非法——属非合约参数，`Zero<Field>` 正确。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:100` | `launchToken` | `distributor == address(0)` | `—` |

### `TokenNameEmpty` · 1 站点 · 保留（入口级不可达）

- 声明：`interfaces/ILaunch.sol:27`
- 签名：`TokenNameEmpty()`
- 载荷：无
- 赋值链：nameLength ← `bytes(name).length`（`Launch.sol:242-243`）。
- 核对：仅 `init` 可达；`launchToken` 的名称恒含 `@`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:243` | `_createToken` | `nameLength == 0` | `—` |

### `TokenSymbolEmpty` · 1 站点 · 保留（入口级不可达）

- 声明：`interfaces/ILaunch.sol:28`
- 签名：`TokenSymbolEmpty()`
- 载荷：无
- 赋值链：symbolLength ← `bytes(symbol).length`（`Launch.sol:246-247`）。
- 核对：仅 `init` 可达；`launchToken` 已先判长度。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:247` | `_createToken` | `symbolLength == 0` | `—` |

### `TokenNameTooLong` · 1 站点 · 保留（入口级不可达）

- 声明：`interfaces/ILaunch.sol:29`
- 签名：`TokenNameTooLong(uint256,uint256)`
- 载荷：`uint256 length, uint256 maxLength`
- 赋值链：nameLength ← `bytes(name).length`（`Launch.sol:242-244`）。
- 核对：仅 `init` 可达；`launchToken` 的名称最长 32+1+32=65 < 96。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:244` | `_createToken` | `nameLength > MAX_TOKEN_NAME_LENGTH` | `nameLength, MAX_TOKEN_NAME_LENGTH` |

### `TokenSymbolTooLong` · 1 站点 · 保留（条件可达）

- 声明：`interfaces/ILaunch.sol:33`
- 签名：`TokenSymbolTooLong(uint256,uint256)`
- 载荷：`uint256 length, uint256 maxLength`
- 赋值链：symbolLength ← `bytes(symbol).length`（`Launch.sol:246-248`），此处 symbol 可能已加 `Test` 前缀。
- 核对：仅当 `Test` 前缀把最终符号推过 32 时可达；部署门禁已卡 `TOKEN_SYMBOL_LENGTH + 4 <= 32`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:248` | `_createToken` | `symbolLength > MAX_TOKEN_SYMBOL_LENGTH` | `symbolLength, MAX_TOKEN_SYMBOL_LENGTH` |

### `InvalidTokenSymbolLength` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:37`
- 签名：`InvalidTokenSymbolLength(uint256,uint256)`
- 载荷：`uint256 length, uint256 expected`
- 赋值链：length ← `bytes(tokenSymbol).length`（`Launch.sol:268-271`）。
- 核对：载荷 `(length, expected)`，与 §4 `length → maxLength` 同类。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:271` | `_checkValidTokenSymbol` | `length != TOKEN_SYMBOL_LENGTH` | `length, TOKEN_SYMBOL_LENGTH` |

### `InvalidTokenSymbolCharacters` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:41`
- 签名：`InvalidTokenSymbolCharacters()`
- 载荷：无
- 核对：无载荷；非法对象是整个符号，逐字节白名单无法用定长载荷表达。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:272` | `_checkValidTokenSymbol` | `!_isValidTokenSymbolBytes(symbolBytes)` | `—` |

### `TokenSymbolAlreadyExists` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:42`
- 签名：`TokenSymbolAlreadyExists(bytes32)`
- 载荷：`bytes32 symbolHash`
- 赋值链：symbolHash ← `keccak256(bytes(subTokenSymbol))`，subTokenSymbol 已加 `Test` 前缀（`Launch.sol:125-127`）。
- 核对：载荷 `bytes32 symbolHash`，定长；调用方知道自己传入的符号。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:127` | `launchToken` | `_tokenAddressBySymbol[subTokenSymbol] != address(0)` | `keccak256(bytes(subTokenSymbol))` |

### `PairCreationFailed` · 1 站点 · 保留需文档化

- 声明：`interfaces/ILaunch.sol:43`
- 签名：`PairCreationFailed(address)`
- 载荷：`address parentTokenAddress`
- 赋值链：pair ← `factory.createPair(tokenAddress, parentTokenAddress)`（`Launch.sol:258-259`）。
- 核对：载荷只有 parent；参考工厂正常路径不返回 0（create2 冲突除外），见 E-LAU-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:259` | `_createToken` | `pair == address(0)` | `parentTokenAddress` |

### `ParentTokenNotRegistered` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:44`
- 签名：`ParentTokenNotRegistered(address)`
- 载荷：`address parentTokenAddress`
- 核对：载荷 `(parentTokenAddress)`；根父币在检查前已放行。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:104` | `launchToken` | `parentTokenAddress != ROOT_PARENT_TOKEN_ADDRESS && !isLOVE20Token(parentTokenAddress)` | `parentTokenAddress` |

### `TokenNotRegistered` · 2 站点 · 保留

- 声明：`interfaces/ILaunch.sol:45`
- 签名：`TokenNotRegistered(address)`
- 载荷：`address tokenAddress`
- 核对：载荷 `(tokenAddress)`；`mergeLaunchCount` 与 `addLaunchCount` 两处。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:164` | `mergeLaunchCount` | `tokenAddress != ROOT_PARENT_TOKEN_ADDRESS && !isLOVE20Token(tokenAddress)` | `tokenAddress` |
| 2 | `Launch.sol:192` | `addLaunchCount` | `!isLOVE20Token(tokenAddress)` | `tokenAddress` |

### `DistributorNotContract` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:46`
- 签名：`DistributorNotContract(address)`
- 载荷：`address distributor`
- 核对：载荷 `(distributor)`；只在 `Callback` 模式校验，`NoCallback` 允许 EOA。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:316` | `_checkDistributorMode` | `distributor.code.length == 0` | `distributor` |

### `InsufficientLaunchCount` · 2 站点 · 载荷顺序调整

- 声明：`interfaces/ILaunch.sol:47`
- 签名：`InsufficientLaunchCount(uint256,uint256,uint256)`
- 载荷：`uint256 memberId, uint256 available, uint256 required`
- 赋值链：availableCount ← `_remainingLaunchCount[parentTokenAddress][memberId]`（`Launch.sol:107`）；sourceCount ← 同名映射（`:169`）；`launchToken` 的 required 是字面量 `1`。
- 核对：`(memberId, available, required)` 与 §4 的 `required + available` 相反，见 E-LAU-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:108` | `launchToken` | `availableCount == 0` | `memberId, availableCount, 1` |
| 2 | `Launch.sol:170` | `mergeLaunchCount` | `sourceCount < count` | `sourceMemberId, sourceCount, count` |

### `ZeroCount` · 2 站点 · 保留

- 声明：`interfaces/ILaunch.sol:52`
- 签名：`ZeroCount()`
- 载荷：无
- 核对：无载荷；`mergeLaunchCount` 与 `addLaunchCount` 两处。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:161` | `mergeLaunchCount` | `count == 0` | `—` |
| 2 | `Launch.sol:191` | `addLaunchCount` | `count == 0` | `—` |

### `SourceAndTargetMemberIdsMustBeDifferent` · 1 站点 · 改名建议

- 声明：`interfaces/ILaunch.sol:53`
- 签名：`SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)`
- 载荷：`uint256 sourceMemberId, uint256 targetMemberId`
- 核对：同 E-STK-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:159` | `mergeLaunchCount` | `sourceMemberId == targetMemberId` | `sourceMemberId, targetMemberId` |

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:57`
- 签名：`NotMemberOwner(uint256)`
- 载荷：`uint256 memberId`
- 核对：单键；NFT 不存在时先抛 OZ 错误。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:37` | `onlyMemberOwner` | `_ownerOf(memberId) != msg.sender` | `memberId` |

### `NotMintContract` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:58`
- 签名：`NotMintContract(address)`
- 载荷：`address caller`
- 核对：载荷 `(caller)`；`addLaunchCount` 唯一入口。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:32` | `onlyMint` | `msg.sender != MINT_ADDRESS` | `msg.sender` |

### `LaunchCountLimitExceeded` · 1 站点 · 保留

- 声明：`interfaces/ILaunch.sol:59`
- 签名：`LaunchCountLimitExceeded(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 requested, uint256 remaining`
- 赋值链：remaining ← `MAX_LAUNCH_COUNT − issuedCount`（`Launch.sol:194-196`）。
- 核对：载荷 `(tokenAddress, requested, remaining)`，符合 §4 上限 actual+limit。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Launch.sol:196` | `addLaunchCount` | `count > MAX_LAUNCH_COUNT - issuedCount` | `tokenAddress, count, MAX_LAUNCH_COUNT - issuedCount` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-LAU-01 | Low | `src/Launch.sol:107-108`、`:169-170` | `InsufficientLaunchCount(memberId, available, required)` 把 available 放在 required 前，§4 规定额度类载荷顺序为 `required + available`；`launchToken` 还直接传字面量 `1`，没有命名局部量，读起来像“可用量为 1”。 | error-standards §4；`ILaunch.sol:47-51` | 下一 breaking 窗口改为 `(memberId, required, available)`；`launchToken` 用 `uint256 requiredCount = 1;` 传参，避免魔法数。 |
| E-LAU-02 | Info | `src/Launch.sol:254-260` | `PairCreationFailed(parentTokenAddress)` 在参考工厂的正常路径下不可达：失败即字符串回滚（`PAIR_EXISTS`/`IDENTICAL_ADDRESSES`/`ZERO_ADDRESS`），成功返回 pair。只有 create2 目标地址已存在代码时才会返回 0（工厂不检查返回值，随后对零地址 `initialize` 也成功）；该地址只能由工厂自身在同一 salt 下创建，外部无法构造。唯一能稳定触发的是 `ZeroReturningPairFactory` 测试桩。载荷也只有 parent，没有本次新建的 `tokenAddress`。 | error-standards §8（正常路径不可达）、§4（主体键）；`dex/lib/v2-core/contracts/UniswapV2Factory.sol:23-36`；`test/Launch.t.sol:377-387` | 保留则改载荷为 `(tokenAddress, parentTokenAddress)`，并在 08-launch 写明“仅 create2 冲突/非 canonical 工厂可达”；或删声明与桩测试。 |
| E-LAU-03 | Low | `src/interfaces/ILaunch.sol:53-56` | `SourceAndTargetMemberIdsMustBeDifferent` 的 `Must` 句式违反 §3；与 Stake 同签名、各自声明（声明本身允许），但两个 ABI 都暴露禁用名。 | error-standards §3；站点 `Launch.sol:159` | 与 E-STK-02 同窗口一起改。 |
| E-LAU-04 | Info | `src/Launch.sol:250-252` | `init` 走 `new LOVE20Token(...)`，失败集合包含 `ZeroInitialSupply()`、`InvalidInitialSupply(uint256,uint256)`、`DependencyNotContract(address)`；`ILaunchErrors` 未声明这三个 selector，08-launch 的 init 表也只列了 `AlreadyInitialized`/`TokenNameEmpty`/`TokenSymbolEmpty`/`PairCreationFailed`。 | error-standards §5（写入口错误集合）；`08-launch.md:25-33` | 在 init 表补一行“以下错误透传自 LOVE20Token 构造函数”，链接 ILOVE20Token ABI；正文已提“零供应、上限、零 distributor”，补 selector 即可。 |
| E-LAU-05 | Info | `src/Launch.sol:243-248` | 四个“创建期”错误在 `launchToken` 入口不可达或条件可达：`TokenNameEmpty`/`TokenSymbolEmpty`/`TokenNameTooLong` 只在 `init` 可达；`TokenSymbolTooLong` 只在 `Test` 前缀把长度推过 32 时可达。若按 §8 机械判“死声明”，会误删只在 genesis 生效的合法错误。 | error-standards §8；`08-launch.md:105` 已说明前缀与 32 上限 | 在 08-launch 错误表加“可达入口”列（init / launchToken / 两者），把入口级不可达写成事实，而不是留给读者推断。 |
| E-LAU-06 | Info | `src/Launch.sol:309-317` | `DistributorNotContract` 只在 `Callback` 模式校验；`NoCallback` + EOA 合法。`ZeroDistributorAddress` 对 EOA 不适用，但 distributor 不是强制合约依赖，用 `Zero<Field>` 而非 `*NotContract` 是正确的。 | error-standards §3/§5；`08-launch.md:111` | 无需改代码；建议在 08-launch 的错误表把“Callback/NoCallback 的适用性”写进条件列。 |

### 4.2 已核对项

- 声明全部在 `ILaunchErrors`；`init` 的已初始化判定先于首币创建（`test/Launch.t.sol:359-371` 断言 `AlreadyInitialized` 优先于空名称）。
- `launchToken` 22 个站点中的 9 个按 08-launch:117 顺序排列；扣减在唯一性之前，失败整笔回滚，`LaunchCountConsumed` 不落地。
- `mergeLaunchCount` 只校验调用者持有源 NFT，目标存在性由 `ownerOf` 保证（08-launch:82）；`addLaunchCount` 只接受 Mint。
- `_addLaunchCount` 同时给首币与根父币记账（`:334-348`），与 08-launch:69-76 的 1:1 伴生一致。
- `check_error_tests.py`：0 untested；`InsufficientLaunchCount` 两处载荷都有断言（`test/Launch.t.sol:934`、`:1206`）。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner`、`mergeLaunchCount` 的目标存在性；08-launch:89 已登记。 |
| `ILaunchDistributor.onTokenLaunched` | 任意 revert data | 外部回调；08-launch:111 声明“失败整笔回滚”。 |
| `ILOVE20Token.symbol()` | 空 revert（对 EOA/零地址） | 父币/首币符号读取；依赖已由部署检查绑定。 |
| `IMemberNFT.init` | `AlreadyInitialized()` | 与 Launch 同 selector，无法区分来源；部署序列问题。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/Launch.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/ILaunch.sol`。
