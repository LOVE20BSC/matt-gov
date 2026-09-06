# Launch 与 TokenFactory

Launch 负责基础发射与次数账本；TokenFactory 负责创建 LOVE20Token。首币启动不另设合约或外部入口，也不创建独立 `launch` 仓库。

## 初始化和首个代币

首币参数与依赖在同一次初始化中传入；供应量在工厂初始化固定，不在 Launch 再保存一份：

```solidity
enum DistributorMode { NoCallback, Callback }

function init(
    address tokenFactory,
    address mint,
    address memberNFT,
    address rootParentToken,
    address distributor,
    DistributorMode distributorMode,
    uint256 launchRatio,
    uint256 maxLaunchCount,
    string calldata name,
    string calldata symbol
) external;
```

先部署全部合约取得地址，并完成 `TokenFactory.init`，再由部署授权者调用一次 `Launch.init`。本次交易写入依赖和参数，调用 `TokenFactory.createToken(rootParentToken, name, symbol, distributor)`；工厂完成首币、Pair 和父币/minter 绑定，Launch 登记首币并调用 `MemberNFT.init(tokenAddress)`。Launch 不再次创建 Pair，也不重复铸造首批供应。

首币不消耗成员发射次数。任一步失败回滚全部初始化效果；成功后不得重初始化、替换依赖或改写首币。部署参数的含义见 [参数表](00-protocol-model.md#初始化参数)。

首币 `distributor` 为 Burn 活动结束后由旧 `LOVE20TKM/burn` 来源单独部署的 Airdrop；Burn 业务不迁移。旧仓库只读，来源提交、来源区块、Merkle Root、部署地址及公开源码证据见 [仓库清单](../../repositories.md)。不能把部署外部 Airdrop 误写为改造旧仓库。

## 发射次数

| 账本 | 所属与作用域 |
| --- | --- |
| `launchCredit[tokenAddress][memberId]` | Mint 保存尚未转换的治理激励额度 |
| `launchCount[tokenAddress][memberId]` | Core 保存成员可用整数次数 |
| `issuedLaunchCount[tokenAddress]` | 社区累计已产生次数；融合或消耗不减少 |
| `maxLaunchCount` | 每社区累计次数上限 |

每次治理激励实际铸造后，按以下顺序处理；只有正数实际铸造金额参与累计：

1. 先判断 `issuedLaunchCount >= maxLaunchCount`；成立则停止，不累计新额度，已有额度保留。
2. 否则用本次铸造前的供应量计算 `threshold`；为 0 时停止，不累计、不转换，也不执行除法。
3. 加入本次实际治理激励，计算完整次数并受剩余社区次数约束，扣除已转换额度；剩余额度保留到下次。
4. 正数新增次数由 Mint 调用 `Launch.addLaunchCount(tokenAddress, memberId, count)` 增加，其他调用者拒绝。与治理激励铸造整体回滚。

```text
threshold = ceil((maxSupply - totalSupplyBeforeMint) * launchRatio / 1e18)
count = min(floor(launchCredit / threshold), maxLaunchCount - issuedLaunchCount)
launchCredit -= count * threshold
```

`launchRatio` 使用 `1e18` 精度。次数消耗或融合不释放累计上限；达到上限后不再生成新次数或累计新额度，已有整数次数仍可使用。任意 token、memberId 的 `launchCredit` 需可查询。

例（最小单位）：当前阈值为 100、原额度为 80、本次铸造 50、剩余次数足够，则得到 1 次，余数 30。下次按新的铸造前供应量重新计算阈值，不沿用 100。

## 次数融合

```solidity
function mergeLaunchCount(
    address tokenAddress,
    uint256 sourceMemberId,
    uint256 targetMemberId,
    uint256 count
) external;
```

源、目标必须不同且存在，`count > 0`，源次数足够。只校验调用者持有源 NFT，不要求持有目标。成功后原子扣减源次数、增加目标次数；不转移 `launchCredit`，不改变其他质押、投票、发射历史或事件，也不减少目标既有状态。此操作可用于 NFT 场外交易。

## 普通发射

当前成员 NFT 持有人可发射社区子币，消耗其一次 `launchCount`。发射流程按检查、更新、交互执行并防重入：先验证成员次数和代币参数，扣减次数，再创建子币、分发首批供应并调用 distributor。外部失败时子币创建和次数消耗全部回滚。

```solidity
function launchToken(
    string calldata tokenSymbol,
    address parentTokenAddress,
    address distributor,
    DistributorMode distributorMode
) external returns (address tokenAddress);
```

普通发射的社区必须与 `parentTokenAddress` 一致，`distributor` 非零。部署时保留符号不得本地发射或复用。分发支持 `NoCallback` 和 `Callback` 两种模式，不使用 Proposal KV：

```solidity
interface ILaunchDistributor {
    function onTokenLaunched(
        address tokenAddress,
        address parentTokenAddress,
        uint256 launcherMemberId
    ) external;
}
```

`NoCallback` 不调用回调；`Callback` 要求 `distributor` 为合约并调用 `onTokenLaunched`，回调失败则整笔发射回滚。首币使用旧 Burn `Airdrop`，固定采用 `NoCallback`；普通发射才可选择 `Callback`。

distributor 自行实现领取与查询逻辑，`claim(tokenAddress)` 只是建议接口，不是协议必需 ABI。发射者负责选择分发目标，承担其失败和 Gas 耗尽风险。

## TokenFactory

保留旧工厂“初始化配置 + 创建代币/Pair”的职责。来源为 [LOVE20TokenFactory.sol](https://github.com/LOVE20TKM/core/blob/0e3efcc13a7b9e202033f62e4858795bf43b557e/src/LOVE20TokenFactory.sol)；BSC 新增 `distributor`，删除 SL/ST 创建及相关依赖。LOVE20Token 的完整参数在构造函数中一次传入，不再提供 `init`。

```solidity
function init(
    address pairFactoryAddress,
    address launchAddress,
    address mintAddress,
    uint256 initialSupply,
    uint256 maxSupply
) external;
```

工厂由部署授权者初始化一次，固定 Pair Factory、Launch、Mint、首批供应量和最大供应量；要求依赖有效、`initialSupply <= maxSupply`。不调用 Launch 业务，因此可在首币存在前初始化。Stake 通过符合 Uniswap V2 接口的 Pair Factory 查询 Pair，不要求 TokenFactory 维护 `pairOf` 映射。

```solidity
function createToken(
    address parentTokenAddress,
    string calldata name,
    string calldata symbol,
    address distributor
) external returns (address tokenAddress);
```

仅已初始化工厂允许 Launch 调用。父币或 distributor 为零、名称或符号为空时拒绝。创建时原子执行：

1. 创建 LOVE20Token，使用工厂固定的供应参数，将 `initialSupply` 直接铸给 distributor，不先交给 Launch。
2. 通过 Pair Factory 创建该代币与 parentTokenAddress 的 Pair。
3. LOVE20Token 构造函数直接写入父币和 Mint 权限；不创建 SL/ST，质押账本仍在 Stake。
4. 发出代币创建事件并返回 tokenAddress；任一步失败全部回滚。

父币社区是否合法、发射次数和分发回调由 Launch 检查。首币使用 WBNB，普通子币使用已登记 LOVE20 父币。

## 实现约束

- LOVE20Token 不提供 `init`；构造函数直接接收 `name`、`symbol`、`initialSupply`、`maxSupply`、`distributor`、`minter` 和 `parentTokenAddress`。
- `MemberNFT.init(firstToken)` 由 Launch 调用；Launch 地址在 MemberNFT 部署时预先绑定，避免初始化循环依赖。

验收见 [Core 验收](08-testing.md)。旧来源 `LOVE20TKM/core/src/LOVE20Launch.sol` 已核对，仅作为保留行为参考。
