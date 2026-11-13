# ADR: Hub 双边入参、通用组 LP、DEX 费率参数化

## 状态

已接受 (2026-11-14)

修订 [ADR 2026-11-13 单币流动性质押](2026-11-13-periphery-hub-single-token-staking.md)：该 ADR 的仓库定位、鉴权结论与 core 侧改动继续有效，本 ADR 只改 `periphery` 的 `LOVE20Hub` 形状与 DEX 参数假设。

## 背景

### 触发问题

[ADR 2026-11-13](2026-11-13-periphery-hub-single-token-staking.md) 把 `UniswapV2Zap` 的 swap / 折算能力并入 `LOVE20Hub`，但只保留了**单币输入**这一种形态：`_swapPlan` 只接受一个输入量，另一侧恒为 0。原 Zap 的数学本来就是双边的一般解（`_calcAmountToSwap(reserveIn, reserveOut, amountIn, amountOutAlready)` 的 `imbalance = amountIn·reserveOut − reserveIn·amountOutAlready`），Hub 的 `_amountToSwap` 正是它令 `amountOutAlready = 0` 的特例。

需求是两条：**流动性质押**与**一键添加流动性**，两条都要在两个代币不平衡时仍能一笔完成。当前实现只覆盖了「单币」这一退化情形。

### 既有事实

- **Hub 从未部署过**：`periphery/broadcast/` 只有 `DeployHub.s.sol/31337`，`script/network/` 只有 `anvil31337_dev`；`anvil` / `interface-dev-dsh` / `compatibility` / `action` / `group-chat` / `dex` / `tools` / `libs` 全仓 grep `LOVE20Hub` 零命中。改签名无兼容成本。
- **`core` 的 ABI 不变**：`Stake.stakeLiquidity` 仍是 5 参，`ROUTER_ADDRESS` / `PAIR_FACTORY_ADDRESS` / `LAUNCH_ADDRESS` / `MEMBER_NFT_ADDRESS` 都是 `public` getter（`core/src/Stake.sol`）。本 ADR **不动 `core`**，因此不阻塞 `compatibility` / `anvil` / 前端。
- **`Launch` 建 token 时 `createPair` 但从不注资**（`core/src/Launch.sol` 的 `_ensurePair`），所以社区币的 pair 必然存在、储备必然为 0，直到第一笔流动性。当前 Hub 对空池直接 `PairEmpty` 回滚，**新币第一笔流动性走不了 Hub**，而 `Stake.stakeLiquidity` 在储备为 0 时能收双边首次注资——这是一个真实的能力缺口。
- **DEX 手续费率因部署而异，且已实测**（`compatibility/results/`）：
  - `anvil`（本地 `dex`）：`pair_feeToConfigured=0`、`router.feeModel=30bps`（`results/anvil/probe.evidence.txt`）
  - `bsc56_public`（Pancake 主网）：`pair_feeToConfigured=1`、`router.feeModel=25bps`、`pair_treasuryMint=2919716218400518`（`results/bsc56_public/probe.evidence.txt`）
  - `bsc97_dev`（Pancake 测试网）：`pair_feeToConfigured=1`、`router.feeModel=20bps`、`pair_treasuryMint=1824706796726387`（`results/bsc97_dev/probe.evidence.txt`）
- **Hub 现有 swap 尺寸闭式解只为 997/1000 推导**：`_amountToSwap` 的 `3_988_009 / 3_988_000 / 1_997 / 1_994` 在 25bps / 20bps 的池子上算错。而正式部署可能直接使用链上已有的 V2 兼容合约（如 PancakeSwap），不一定是 `dex` 部署的那一套。
- **`SWAP_OUTPUT_TOLERANCE_RATIO`（1%）给的是假保护**：`Hub._amountOut` 与 Router02 的 `UniswapV2Library.getAmountOut` 是逐项相同的整数公式，储备来源是同一个 pair，同一笔内储备不会在「读储备」与「swap」之间移动（`LOVE20Token` 与 WBNB 都是无钩子 ERC20，`safeTransferFrom` / `forceApprove` 不触发回调）。所以 `amountOutMin = 99% × amountOut` 恒被满足；夹子发生在交易之前，Hub 读到的已是被人推过的储备，按那组储备算出的 99% 自然还是过。
- **协议抽成公式因实现而异，且只能从 `Mint` 事件反推**（`view` 调用拿不到）：
  - Uniswap V2：`1/(5·rootK + rootKLast)`，即 `sqrt(k)` 增长的 1/6
  - Pancake 主网：`8/(17·rootK + 8·rootKLast)`，即增长的 32%（官方文档：`0.17%` 给 LP、`0.0225%` 给国库、`0.0575%` 给 CAKE 回购，协议合计 `0.08/0.25 = 32%`）
  - Pancake 测试网：`1/(3·rootK + rootKLast)`，即增长的 25%
- **社区币 `MAX_SUPPLY = 1e28`**（`core/script/network/anvil31337_dev/core.params`），远小于 `uint112.max ≈ 5.19e33`，所以质押路径碰不到 `uint112` 上限检查；只有通用 LP 路径（任意 ERC20）有意义。

### 数学推导与验证

**swap 尺寸的一般闭式解**（`F/D` 为池子的实际费率，`S = F + D`）：

```text
x = ( √( r²·S² + 4FD·r·I/(rOut + b) ) − r·S ) / (2F),   I = a·rOut − r·b
```

`F/D = 997/1000` 时化简即现有 `_amountToSwap`。用 `sympy` 验证它是 `(a−x)(rOut−y) = (b+y)(rIn+x)` 的根，其中 `y = x·F·rOut/(rIn·D + x·F)`。

**改成 1e18 单比例**（`K18 = (F/D)·1e18`，`G = K18 + 1e18`）：

```text
x = ( √( r²·G² + 4·K18·1e18·r·I/(rOut + b) ) − r·G ) / (2·K18)
```

实测与整数形**逐 wei 相等**（`997/1000`、`9975/10000`、`9980/10000`、`9990/10000`、`9950/10000` 五组）。**注意**：把 `K18` 直接代进整数形（`4·K18·1e18` 换成 `4·K18`）会差 1 wei，必须按上式改写。

**溢出边界**：`r = uint112.max` 时 `r²·G² ≈ 1.08e104`，**超出 uint256**，必须用 `Math.mulDiv(rIn·rIn, G·G, 1e36)` 分步算；约掉 1e36 后 `inner ≈ 2.15e68`，uint256 上限 `1.16e77`，余量 5 个数量级。等价的整数形约束是 `F + D ≤ 65536`（推导：`R²·S² ≤ 2²⁵⁶` 且 `R = 2¹¹²−1` 给出 `S ≤ 65536`）。

**协议抽成的一般闭式解**：

```text
liquidity = supply · (rootK − rootKLast) · k / (a·rootK + k·rootKLast)
```

三种实现都是它的实例，且 `b ≡ k`（该族的一般形式就是「抽走增长的 `k/(a+k)`」）。用两组实测数据反解确认：主网只有 `(25bps, k=8/a=17)` 能命中 `2919716218400518`，测试网只有 `(20bps, k=1/a=3)` 能命中 `1824706796726387`，其余组合差 20%–48%。

**改用「手续费两个去向」表达**（`lp` = 留给 LP 的手续费、`proto` = 协议抽走的手续费，均以 1e18 为单位）：

```text
liquidity = supply · ΔrootK · proto / (lp·rootK + proto·rootKLast)
```

等价于 `k = proto, a = lp`，结果逐 wei 相同，但**三个已知 profile 的两个比例全部是 1e18 精确整数**，而 `k/(a+k)` 形式下 Uniswap 的 `1/6` 除不尽（截断 4 wei）。同时 `swapFeeRatio = 1e18 − (lp + proto)` 可完全由这两个值推出，构造函数因此只需 2 个费率参数。

| profile | `lp` | `proto` | 合计 | 抽成验算 |
| --- | --- | --- | --- | --- |
| 本地 `dex`（`feeTo=0`） | `3000000000000000` | `0` | 0.30% | `mint=0` |
| Uniswap V2 | `2500000000000000` | `500000000000000` | 0.30% | `mint=1824812122961676` |
| Pancake 主网 | `1700000000000000` | `800000000000000` | 0.25% | `mint=2919716218400518` |
| Pancake 测试网 | `1500000000000000` | `500000000000000` | 0.20% | `mint=1824706796726387` |

### 为什么费率必须是部署参数而不是运行时探测

运行时探测（先按 `997/1000` 算尺寸 → `getAmountsOut` 探一次 → 反解费率 → 重算）在数学上可行（实测 1 轮收敛、残差 2.6e-25），但有两个致命缺陷：

1. **冷启动时探不准**：反解精度依赖储备量，实测储备 `< 1e8` 时 1/1000 探测会给出错误费率（储备 `1e6` 时 1/1000 探测给出 30bps 而真值 25bps）。而社区币首笔流动性的场景恰恰是储备极小 —— 那时又不需要探测（首笔注资不 swap），但一旦缓存了错值就会一直错。
2. **协议抽成根本探不到**：它只能从真实 `Mint` 事件反推，任何 `view` 调用都拿不到。半自动的方案不成立。

所以两个费率都在部署时确定、构造期写入 `immutable`，并由部署脚本在广播前用 `getAmountsOut` 反解交叉校验（见「部署期校验」）。

## 决策

### 一、`LOVE20Hub` 的入参形状：双边

四条写入口全部改成**双边期望量**，任一侧为 0 表示该侧不给（单币输入是「一侧为 0」的特例）：

- `stakeLiquidityWithToken` / `stakeLiquidityWithNative`：`tokenAmountDesired` / `parentTokenAmountDesired`
- `addLiquidityWithToken` / `addLiquidityWithNative`：`amountADesired` / `amountBDesired`（native 分支用 `amountTokenDesired` / `amountNativeDesired`）

入参语义是**期望量**（用不完退余），与现有 `prepared − remaining` 的退款口径一致；精确量会让取整尘埃变成回滚。

函数名继续表示**资金入口形态**（`WithToken` = `transferFrom`、`WithNative` = `payable`），不表示单币/双币。

### 二、两条路径的代币对范围分家

- **流动性质押**：限定「已注册社区币 ↔ 它的 parent」。Hub 从 `ILaunch.isLOVE20Token` + `ILOVE20Token.PARENT_TOKEN_ADDRESS` + factory 取 pair。社区币 pair 由 `Launch._ensurePair` 保证存在，缺池是异常（`PairMissing`）。
- **一键组 LP**：**不限**任意 `tokenA` / `tokenB`。不读 `Launch` / `Stake` / `MemberNFT`，pair 由 factory 派生、缺池时交给 Router 的 `_addLiquidity` 内部 `createPair`。

这条分裂让组 LP 路径实际上不依赖 `core`，但它与质押路径共用同一份 swap / 折算 / 退款实现，且服务的是「社区币冷启动」这一场景，因此仍留在 `periphery`（见「对 `repositories.md` 的说明」）。

### 三、空池与缺池

- `pair == address(0)` 或 `reserve0 == reserve1 == 0`：要求两侧 desired 都 > 0，**不 swap**，直接加池（缺池时 Router 建池）；只有一侧 > 0 → `PairWithoutLiquidity(tokenA, tokenB)`。
- 有储备：按双边一般解配平后加池/质押。
- 质押分支：pair 必须存在（`PairMissing`），但储备可以为 0（首次注资走 `Stake.stakeLiquidity`，其 `_optimalAmounts` 在储备为 0 时原样返回）。

### 四、DEX 费率参数化

构造函数 3 个参数，全部 `immutable`：

```solidity
constructor(
    address stakeAddress,
    uint256 swapFeeForLpRatio,        // lp：留给 LP 的手续费，1e18 单位
    uint256 swapFeeForProtocolRatio   // proto：协议抽走的手续费，1e18 单位
)
```

构造期校验：`swapFeeForLpRatio > 0`、`swapFeeForLpRatio + swapFeeForProtocolRatio < 1e18`。

派生的两个量（内部计算用，不额外占参数）：

- `swapFeeRatio = 1e18 − (lp + proto)`，即 `F/D` 的 1e18 表达
- 抽成公式直接用 `lp` / `proto` 作为 `a` / `k` 的等价物

**部署期校验**（`DeployHub.s.sol` 的 `_validateConfig`，在 `startBroadcast()` 之前）：取一对已知有流动性的 pair，用 `getAmountsOut` 反解实际费率，与 `1e18 − (lp + proto)` 比对；不一致则中止并打印两组值。反解公式：

```text
F/D = y·rIn / (x·(rOut − y))      // x → y 是一次 getAmountsOut 探测
```

值本身来自 `hub.params`（人工维护、可审计、可复现），脚本的反解只做交叉校验 —— 不依赖部署时链上是否已有池子。

### 五、删除 `SWAP_OUTPUT_TOLERANCE_RATIO`

理由见「既有事实」。`swapExactTokensForTokens` 的 `amountOutMin` 传 `1`，唯一作用是「Router 不得返回 0」；价格保护完全交给调用者的终点 `tokenAmountMin` / `parentTokenAmountMin`（LP 侧 `amountAMin` / `amountBMin`）。

**这是对 [ADR 2026-11-13](2026-11-13-periphery-hub-single-token-staking.md) §三.3 与 `periphery/README.md` 中「1% 内部输出界把 swap 段夹子变成回滚」这条论证的推翻** —— 该论证不成立，原文保留但加指针指向本 ADR。

### 六、报价面

四个报价函数按双边重命名并统一形状：

- `quoteLp(tokenA, tokenB, amountADesired, amountBDesired)`
- `quoteLpWithNative(tokenAddress, amountTokenDesired, amountNativeDesired)`
- `quoteStakeLiquidity(tokenAddress, tokenAmountDesired, parentTokenAmountDesired, memberId, promisedWaitingPhases)`
- `quoteStakeLiquidityWithNative(tokenAddress, tokenAmountDesired, memberId, promisedWaitingPhases)`

全部补 `hasLiquidity`（前端要区分首次注资）；组 LP 报价**也**返回 `suggestedAmountAMin` / `suggestedAmountBMin`（取 `usable*`），与质押报价的 `suggestedTokenAmountMin` / `suggestedParentAmountMin` 对齐；保留 `prepared*`（被 swap 掉的一侧 `prepared = desired − amountToSwap`，不等于用户转账量，`_settle` 与 `suggested*Min` 都以它为基准）；**不补** `reserve*After`（报价与成交之间池子会变，给的是过期值，且能自行推导）。

### 七、事件拆两族

| 族 | 根键 | 事件 |
| --- | --- | --- |
| `periphery.hub` | `tokenAddress` | `HubLiquidityStakedWithToken` / `HubLiquidityStakedWithNative` |
| `periphery.pair`（新） | `pairAddress` | `HubLiquidityAddedWithToken` / `HubLiquidityAddedWithNative` |

- 事件名**保留 `Hub` 前缀**：发射者即域，前缀是冗余，但它是可读性约定（一眼看出层级），不承担唯一性职责（见「八」）。
- 组 LP 事件的字段改 `preparedAmountA` / `preparedAmountB` / `remainingAmountA` / `remainingAmountB`（LP 路径没有「parent」角色）；质押事件字段不变。
- `pairAddress` 在 `getPair == 0` 时于 `addLiquidity` 返回后回读（`factory.getPair(tokenA, tokenB)`），多一次外部调用（约 5k gas），只发生在「该 pair 的史上第一笔 LP」这一笔上。**不**用 CREATE2 预算（pair init code hash 在 `dex` 与 Pancake 不同，作为构造参数填错时静默出错）。
- 两个族在 `check-events.py` 的 `FAMILIES` 表里分别登记根键，机器守住「质押事件必须以 `tokenAddress` 开头、组 LP 事件必须以 `pairAddress` 开头」。**不**用「一族多根键」（那会把机器约束降级成人眼约定）。

### 八、`event-standards.md` §5.1 的规范修订

§5.1 现写「全协议事件名与 schema 必须全局唯一；同名不同 payload 一律拆名」。**对一个去中心化协议这条是错的**：任何人都能部署自己的合约、发射自己的 `LiquidityStaked`，链下不能假设「看到某个 topic0 就知道是哪个合约的」。

真正的唯一性只可能来自 `(emitting contract address, topic0)` 这个二元组，topic0 单独不构成身份。因此：

- 「必须全局唯一」降级为「**同一仓库内**应尽量唯一；跨合约 / 跨仓库唯一性是**建议**」；
- 链下解析必须按发射合约地址区分同名事件，不得把「事件名全局唯一」当作必然；
- `Hub` 前缀作为可读性约定保留。

### 九、错误集合

- **删**：`InvalidInputTokenAddress`、`ZeroInputTokenAddress`、`ZeroInputTokenAmount`、`PairEmpty`（空池合法）
- **增**：`ZeroAmount`（两侧 desired 全 0）、`IdenticalTokens`（`tokenA == tokenB`）、`WrappedNativeAsToken`（native 分支 `token == WBNB`）、`PairWithoutLiquidity(tokenA, tokenB)`、`InsufficientAmountA(uint256, uint256)`、`InsufficientAmountB(uint256, uint256)`（LP 侧，与 `amountA` / `amountB` 字段同名）
- **保留**：`PairMissing(tokenAddress)`（只服务质押分支）、`DeadlineExpired`、`AmountExceeded`、`ZeroSwapOutput`、`ZeroRecipientAddress`、`ZeroTokenAddress`、`ZeroNativeTokenAmount`、`NativeInputUnsupported`、`NativeTokenSenderRejected`、`NativeRefundFailed`、`InvalidPromisedWaitingPhases`、`TokenNotRegistered`、`InsufficientTokenAmount` / `InsufficientParentTokenAmount`（只服务质押分支）

**`AmountExceeded` 的语义修正**：现有注释声称它挡得住 pair 溢出，这是错的。pair 的真实溢出条件是 `reserve + amountIn ≤ uint112.max`（`UniswapV2Pair._update` 里 `balance <= uint112.max`），而 Hub 检查的是「单个量 ≤ `uint112.max`」：

- 储备接近上限时，通过检查的量仍会溢出（`reserve = max/2`、`desired = max` 时 `reserve + usable > max`）；
- 反过来，`desired > uint112.max` 但 `reserve + usable ≤ max` 的合法交易存在（实测 48 组反例），所以**不能**收紧成 `reserve + desired ≤ max`（`desired` 是「最多愿意放多少」，真正入池的是折算后的 `usable`）；
- 也不能改判 `reserve + usable ≤ max`：那要把 Router 的折算公式在 Hub 里再写一遍，违反「同一规则两处实现」。

所以它保留为**荒谬输入护栏**，注释与 README 写明「这不是溢出保护，溢出由 pair 回滚」。

### 十、不恢复 Zap 的 `liquidityMin`

终点 `tokenAmountMin` / `parentTokenAmountMin`（LP 侧 `amountAMin` / `amountBMin`）已经界定「至少多少真的进了池子/质押」；LP 与份额是 core / pair 的内部记账，不对外暴露。再要求用户填一个自己算不出来的 LP 数只会增加摩擦，而报价返回 `suggested*Min` 已经消除了「不知道该填多少」的问题。

## 对 `repositories.md` 的说明

`repositories.md` 的边界判据是编译期事实（`periphery` 的合约 `import @core/`，`tools` 的不 import）。本 ADR 之后 Hub 里的组 LP 路径**不需要 core**（不读 `Launch` / `Stake` / `MemberNFT`），却因为与质押路径同居一个合约而挂上了 `@core/` 依赖。

不拆开：拆分会把 Zap 复活成第二个合约 + 第二套部署（正是 [ADR 2026-11-13](2026-11-13-periphery-hub-single-token-staking.md) 否决的方案）。改为在 `repositories.md` 的 Hub 条目补一条例外说明：**Hub 的通用组 LP 入口服务于社区币冷启动，不追求通用性；判据针对「合约是否依赖协议合约」，Hub 整体依赖，故整体归 `periphery`**。

## 被否决的方案

| 方案 | 否决理由 |
| --- | --- |
| 保留单币入口、另加双边入口（8 写 + 8 报价） | 单币就是「一侧为 0」，两套等于把同一份数学维护两遍；且无已部署调用方，改签名零成本 |
| 入参用精确量（用不完回滚） | 取整 / 折算的 wei 级尘埃变成回滚，与现有退款路径冲突 |
| 不支持空池首次注资 | `Launch` 建 token 时就 `createPair` 但不注资，新币第一笔流动性将无法走 Hub，而 core 的 `Stake` 能收 —— 能力面倒退 |
| 组 LP 恢复 Zap 的任意 `tokenA`/`tokenB` 且脱离 Hub 回 `tools` | 违背「完全放入 LOVE20Hub」的需求，且要把 Zap 复活成第二个合约 |
| 运行时探测费率（每次调用反解） | 冷启动储备小反解不准、协议抽成公式 `view` 拿不到；半自动方案不成立 |
| 首次使用时探测并缓存 | 唯一需要它的场景（冷启动）恰恰探不准，缓存下来的就是错值且此后一直错 |
| 固定 997/1000 + Uniswap `1/6`，不支持 Pancake | 正式部署可能直接用链上已有的 V2 兼容合约（如 PancakeSwap），闭式解与抽成公式都会算错 |
| 抽成参数传三个（`k`/`a`/`b`） | `b ≡ k` 是恒等式，多传一个等于交给部署者填错；真要 `b ≠ k` 的 fork 是「改一行合约」的代码变更 |
| 抽成参数用一个枚举 profile | 把「数值」变成「分支」，新增 fork 要改代码；链上只看到 `1`，审计时看不出实际抽成比例 |
| 费率参数用 `F`/`D` 两个整数 | 1e18 单比例已经精确（三个 profile 全部整除），两个整数多一个可填错的维度 |
| 抽成比例用 `k/(a+k)` | Uniswap 的 `1/6` 除不尽（截断 4 wei）；而「手续费两个去向」（`lp`/`proto`）三个 profile 全部是 1e18 精确整数 |
| 保留 `SWAP_OUTPUT_TOLERANCE_RATIO` | 恒被满足，给的是假保护；挡不住夹子，真正起作用的是终点 Min |
| 事件用「一族多根键」 | 检查器只能守住「首字段是这两个之一」，一条质押事件写错成 `pairAddress` 也能通过 |
| 事件去掉 `Hub` 前缀 | 前缀是冗余但无害的可读性约定；去掉会与 core 的 `LiquidityStaked` 只差后缀，层级反而更难辨认 |
| 事件用 CREATE2 预算 `pairAddress` | pair init code hash 在 `dex` 与 Pancake 不同，作为构造参数填错时静默发错地址（违反「失败方向必须响亮」） |
| 恢复 Zap 的 `liquidityMin` | 终点 Min 已界定实际入池量；LP 是内部记账，要求用户填算不出来的数只增加摩擦 |
| 报价补 `reserve*After` | 报价与成交之间池子会变，给的是过期值，且能从 swap 前后自行推导 |

## 按仓库拆分的工作项

| # | 仓库 | 写范围 | 内容 | 依赖 |
| --- | --- | --- | --- | --- |
| A | `matt-gov` | `docs/adr/`、`docs/event-standards.md`、`docs/repositories.md`、`registry/errors.*` | 本 ADR；§5.1 唯一性降级、§6.1 新增 `periphery.pair` 族与 `periphery.hub` 行改写；`repositories.md` 的 Hub 例外说明；错误登记刷新 | 无（先做） |
| B | `periphery` | `src/`、`test/`、`script/` | 接口与实现重写（双边入参、两条路径分家、空池/缺池、费率参数化、删 1% 容差、事件拆族、错误增删）；mock 参数化；5 个测试文件改写 + 新增用例；部署脚本与 `hub.params`；事件表与 `check-events.py`；README | A（ABI 定稿） |

**跨仓顺序**：A → B。`periphery` 的测试与 `check-events.py` 都以 A 定稿的 ABI 为输入。

## 后果

### 正面

1. 一键添加流动性与流动性质押都支持**两个代币不平衡**的入参，单币是「一侧为 0」的特例，数学只存在一份。
2. 新币冷启动（空池 / 缺池）可以走 Hub，与 `Stake` 的能力面对齐。
3. Hub 可部署到任意 Uniswap V2 兼容 DEX（本地 `dex`、Pancake 主网/测试网、将来的 fork），费率由部署参数决定，数学与抽成公式都精确。
4. 删除一段恒被满足的「保护」，`_amountOut` 不再自己算输出（改用 Router 返回值），报价与写入可逐 wei 对齐。
5. 事件按事实拆族，机器守住两个根键；§5.1 的唯一性条款被修正为符合去中心化协议实际。

### 负面 / 成本

1. **破坏性 ABI 变更**（无已部署调用方，但前端与索引方需要按新形状接）：4 个写入口与 4 个报价的签名与 struct 字段全变、4 个事件 topic0 全变、错误集合增删。
2. `LOVE20Hub.sol` 从 690 行增至约 780 行，`ILOVE20Hub.sol` 从 209 行增至约 260 行；测试与 mock 全部要改（约 1,900 行）。
3. 部署多 2 个参数与 1 项广播前校验；`hub.params` 需要按网络维护费率。
4. `event-standards.md` §5.1 与 §6.1 两处规范改动，影响面超出本仓。
5. `repositories.md` 的边界判据出现一条文字例外。

## 相关文档

- [ADR 2026-11-13 单币流动性质押](2026-11-13-periphery-hub-single-token-staking.md)（本 ADR 修订其 §三 的 Hub 形状）
- [repositories.md](../repositories.md) · [event-standards.md](../event-standards.md) · [error-standards.md](../error-standards.md) · [naming-standards.md](../naming-standards.md) · [dev-standards.md](../dev-standards.md)
- [04-stake.md](../specs/core/04-stake.md) · [00-protocol-model.md](../specs/core/00-protocol-model.md)
- 实测证据：`compatibility/results/{anvil,bsc56_public,bsc97_dev}/probe.evidence.txt`
