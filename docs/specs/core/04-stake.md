# Stake

Stake 按 `tokenAddress + memberId` 维护流动性质押和加速质押，不发行 SL/ST 凭证。两类资产共享解锁生命周期。**减项收紧、增项开放**：解锁、提取、融合源侧要求调用者是持有人；`stakeLiquidity`、`stakeBoost` 与融合目标侧只要求 `memberId` 存在，任何人可代为增加（见[通用规则](01-common-rules.md#无许可增项)）。

## 状态

结构体和完整 ABI 见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。

| 字段 | 含义 |
| --- | --- |
| `liquidityShares` / `boostShares` | 成员流动性份额 / 加速质押份额 |
| `promisedWaitingPhases` | 承诺解锁期，单位 Phase |
| `unlockRequestPhase` | 申请 Phase；0 表示未申请 |
| `firstGovVoteRound`（成员级） | 当前仓位的**首次获取治理票的 Round**：`liquidityShares` 由 0 变为非 0 的那一轮写入，追加质押与提高等待期都不改写；`withdraw` 清空整个成员记录时一并归零，再次质押从新的那一轮重新记。0 表示当前没有仓位。加速质押不写该字段（它本身不产生票权） |
| `firstGovVoteRound`（社区级） | 该社区**首次获取治理票的 Round**：社区第一笔流动性质押所在轮写入，**此后永不变更、永不重置**——全体成员提取完毕后仍保留原值。`mergeStake` 不改写它 |
| `totalLiquidityShares` / `totalBoostShares` | 社区份额总量 |
| `lastWithdrawableLp` | 上次结算后的可提取 LP 基准 |
| `lastFeeLp` | 上次结算后的协议增值 LP 基准 |
| `lastSqrtKOfLp` | 上次结算的 sqrt(k) 基准 |
| `lastSettlePhase[tokenAddress]` | 上次**实际**结算的 Phase；等于当前 Phase 时本 Phase 不再结算，仅内部使用、不对外提供 getter |
| `validGovVotes[tokenAddress][round][memberId]` | 成员在指定治理 Round 的**有效**治理票：`stakeLiquidity` 与提升等待期的 `stakeBoost` 加，申请解锁清零，融合按源→目标搬移；未开始的 Round 回滚 `RoundNotStarted` |
| `validBoostShares[tokenAddress][round][memberId]` | 成员在指定治理 Round 的**有效**加速份额：`stakeBoost` 加、申请解锁清零、融合按源→目标搬移；未开始的 Round 回滚 `RoundNotStarted` |
| `totalValidGovVotesAdded[tokenAddress][round]` / `Removed` | 截至该 Round 的**累计**有效治理票增量 / 减量。两者的差就是社区有效治理票总量 |
| `totalValidBoostSharesAdded[tokenAddress][round]` / `Removed` | 截至该 Round 的**累计**有效加速份额增量 / 减量。两者的差就是社区有效加速份额总量 |
| `pairAddress[tokenAddress]` | 社区对应的 Uniswap V2 兼容 Pair 地址 |
| `totalBurnedToken[tokenAddress]` | 社区代币全局累计销毁量 |
| `totalParentTokenBurned[tokenAddress]` | 该社区手续费中父币的累计数量（换币前） |
| `totalLiquidityTokenAmount[tokenAddress]` | 流动性质押中的**社区代币本金**台账：入池时按实际转入量增加，提取时按份额占比减少。只读该台账、不读 Pair 现货储备，因此不受捐赠与闪电贷影响；内部映射，对外由 `liquidityTokenAmount(tokenAddress)` 暴露 |
| `BOOST_STAKE_SUPPLY_FACTOR` | 单人加速质押上限基数 `C` 的部署因子 `F`（`uint256 public`，默认 2，建议 1–10，仅建议不作校验） |
| `BOOST_STAKE_MULTIPLIER` | 单人加速质押上限的部署倍数 `M`（`uint256 public`，默认 5，建议 1–20，仅建议不作校验） |
| `LIQUIDITY_TOKEN_EQUIVALENCE_FACTOR` | 恒定 `2`：Uniswap V2 双边等值折算因子（`uint256 public constant`） |

`totalLp` 不是存储字段：`totalStake()` 与 `_updateSqrtKBaseline` 都在使用时由 `lastWithdrawableLp + lastFeeLp` 派生，值等于合约记账的 LP 总量（不含他人主动转入的 LP）。

## 流动性质押与手续费

构造函数固定 `PHASE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`VOTE_ADDRESS`、`LAUNCH_ADDRESS`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS`、`PROMISED_WAITING_PHASES_MIN`、`PROMISED_WAITING_PHASES_MAX`、`FEE_SETTLEMENT_RATIO`、`BOOST_STAKE_SUPPLY_FACTOR` 和 `BOOST_STAKE_MULTIPLIER`，不设调用者限制，只保存入参、不读取同批部署合约；`VOTE_ADDRESS` 在前序部署中尚未存在时由脚本按 nonce 预测，并在 `Vote` 部署后核对 `Stake.VOTE_ADDRESS()`。

每个社区的唯一 Pair 由 [Launch](08-launch.md) 在发射该代币的同一笔交易内创建或复用；`Stake` 在首次质押时通过 `PAIR_FACTORY_ADDRESS.getPair(tokenAddress, parentTokenAddress)` 读取并保存，为零地址时回滚 `PairMissing(tokenAddress)`。**`Stake` 的所有入口都只接受 Launch 已登记的代币，只读取已登记的 Pair，不创建 Pair**，未登记回滚 `TokenNotRegistered(tokenAddress)`，无 Pair 回滚 `PairMissing(tokenAddress)`。

调用者提供社区代币与父币的期望数量。`stakeLiquidity` 不承担价格保护，只按 Pair 储备把收到的两种币**尽可能**放进流动性质押——按储备比例一侧取期望值、另一侧按比例折算，只转入折算后的数量，再直接向 Pair 铸出 LP；**折算后放不下的部分不转账、留在调用者手里**（它们从未进入 Stake，无需退款）：

```text
parentTokenAmountOptimal = floor(tokenAmountDesired * reserveParent / reserveToken)
tokenAmountOptimal      = floor(parentTokenAmountDesired * reserveToken / reserveParent)
```

先算父币方向；该值不超过期望值时入池 `(期望代币量, 折算父币量)`，否则改算代币方向并入池 `(折算代币量, 期望父币量)`。折算保留一侧全额、削减另一侧，因此只可能一侧有剩余，或比例一致时两侧都无剩余。折算只是**纯比例计算**，不含任何容差、上限或回滚：比例失衡不 revert，只是静默少押、剩余留在自己钱包——资产无损，但少了偏离提醒。价格保护完全交给调用方自己指定的最小量（`periphery` 的 `LOVE20Hub` 用 `tokenAmountMin` / `parentTokenAmountMin` 在调用前做全链路终点口径的事后校验，不在 core 内复刻）。Pair 任一侧储备为零时不做折算，直接采用期望数量。Pair 铸出的 LP 数量为零时回滚 `ZeroLiquidityMinted()`；该分支保留给“返回 0 而不是回滚”的 V2 兼容 Pair，参考实现会先以 `INSUFFICIENT_LIQUIDITY_MINTED` 回滚。添加 LP 成功后按 LP 数量计份额，并按实际转入的社区代币数量增加本金台账 `totalLiquidityTokenAmount[tokenAddress]`；提取时移除 LP 并返还双币，同时按 `floor(liquidityShares × T / totalLiquidityShares)` 扣减该台账。

`stakeLiquidity` 与 `stakeBoost` **不要求调用者持有该 `memberId` 的 NFT**，只调用 `ownerOf(memberId)` 校验存在（见[通用规则 · 无许可增项](01-common-rules.md#无许可增项)）。任一地址都可以为任意已存在的 `memberId` 增加质押，`_pull` 从 `msg.sender` 拉币。**已写入的等待期不可被第三方改写**：调用者不是该 NFT 持有人时，只要该成员记录的 `promisedWaitingPhases` 已非零，传入值就必须等于现有值，否则按下面的顺序回滚；未写过（`== 0`）的记录允许调用者自由指定（含 `MAX`）。判据是等待期本身，与 `mergeStake` 判空的 `targetHadPosition`（按份额）是两个不同的判据，各自服务于自己的规则。

份额铸造公式（必须在手续费重分类之后计算）：

```text
sharesMinted = totalLiquidityShares == 0 or lastWithdrawableLp == 0
    ? lpMinted
    : floor(totalLiquidityShares * lpMinted / lastWithdrawableLp)
```

`lastWithdrawableLp == 0` 表示既有份额的可提取基准已被全部重分类为手续费，此时新存入按自身的 `lpMinted` 计份额；该零基准分支沿用旧 `LOVE20SLToken`，避免除零回滚。此时既有份额并未清零，它们对新存入的 LP 仍占 `S0 / (S0 + L1)` 的份额（`S0` 为存量份额、`L1` 为新存入的 LP），即新存入者会被这批「零基准份额」分走一部分；进入该分支要求 √K 相对基线增长到把全部可提取 LP 都归入手续费：`currentSqrtK > lastWithdrawableLp × lastSqrtKOfLp`，即需要把池子的 √K 放大 `W` 倍（`W` 为可提取 LP 量级）。在池价不变的比例模型下这要一笔约 `(W − 1)` 倍池价值的捐赠，成本远高于可瓜分的额度，因此作为已知边界保留而不加固。

手续费重分类公式（必须在份额铸造之前执行）：

```text
currentSqrtKOfLp = floor(sqrt(reserve0 * reserve1) * totalLp / pairTotalSupply)
newWithdrawableLp = floor(lastWithdrawableLp * lastSqrtKOfLp / currentSqrtKOfLp)
newFeeLp = totalLp - newWithdrawableLp
```

`totalLp` 是合约记账的 LP 总量（`lastWithdrawableLp + lastFeeLp`），`pairTotalSupply` 是 Pair 的 LP 总供应。两者必须同一口径：基线 `lastSqrtKOfLp` 与重分类都用记账量计算，任何人主动转入的 LP 既不影响基准也不进入可提取量，避免重分类两侧基数不一致。仅当 `currentSqrtKOfLp > lastSqrtKOfLp` 时重分类手续费；`pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 或基准未增长时跳过结算，不能先除零再判断。结算更新 `lastWithdrawableLp`、`lastFeeLp` 和 `lastSqrtKOfLp`；`totalLp` 不落存储，`totalStake()` 与 `_updateSqrtKBaseline` 都在使用时由 `lastWithdrawableLp + lastFeeLp` 派生。

**流动性质押的执行顺序**：先重分类手续费（更新 `lastWithdrawableLp`），再按新的 `lastWithdrawableLp` 计算份额。两个公式都以 `lastWithdrawableLp` 为输入，顺序错误会导致份额和手续费计算错误。

手续费是质押 LP 的全部 √K 增值，不区分 swap 手续费与外部捐赠；增量归协议，不归旧质押者。只有质押 LP 的增值被剥离，未质押 LP 保留自己的份额；剥离没有上限，任何地址都能触发。直接转账进池只有在被 `sync`/`mint`/`burn` 折入储备后才计入；折入前可被任何人 `skim` 取回。重分类后可提取 LP 下降；相同新存入 LP 对应更多份额。无池价变化的比例模型中，这是剥离增值，不是损失本金；整数舍入仍须按公式计算。

例（整数模型）：原可提取 LP 为 120，旧/新 sqrt(k) 基准为 100/120，重分类后可提取 LP 为 100、手续费 LP 为 20。原总份额为 120 时，新存入 100 LP 得到 120 份额。

## 手续费结算与销毁

任何人可调用 `settleFees(tokenAddress)` 单独结算手续费；提取本金前也自动结算。重分类每次都执行，因为它决定后续定价所用的 `withdrawableLp`；真正取回双币并销毁的结算则受两条约束：

**一、每个社区每个 Phase 最多结算一次。** 单笔上限只约束一次调用，同一笔交易内重复调用即可把额度刷完，所以必须有这条按 Phase 的限频才能让上限真正成立。

**二、单笔结算量就是一个阈值单位。**

```text
settlementUnit = floor(pairTotalSupply * FEE_SETTLEMENT_RATIO / 1e18)
触发条件        feeLp >= settlementUnit
单笔处理量      processedFeeLp = settlementUnit
```

`FEE_SETTLEMENT_RATIO` 是单笔结算占 Pair 的 LP 总供应的比例，以 `1e18` 表示 100%（配置值 `25e14`，即 0.25%）；部署时要求 `0 < FEE_SETTLEMENT_RATIO <= MAX_FEE_SETTLEMENT_RATIO`（源码常量 `2.5e15`，本身已小于 `1e18`）。

阈值同时定义「何时开始烧」和「一次烧多少」：手续费 LP 达到一个单位才结算一个单位，剩余 `feeLp - settlementUnit` 留待下个 Phase。这样不需要第二个参数。可提取 LP 归零不影响单位本身：只要 `pairTotalSupply × FEE_SETTLEMENT_RATIO / 1e18 > 0`，单位仍为正；再满足社区质押 LP 占全池比例大于结算比例且手续费 LP 不少于一个结算单位时，任何人仍可按同一比例释放。手续费 LP 不足一个结算单位时，手续费 LP 留在合约（仍是池中 LP），不会实际销毁；精确边界是 `feeLp >= floor(S × r / 1e18)`，份额低于比例但落在取整边界上的例外见下。

手续费 LP 恒不超过社区记账 LP：`lastFeeLp <= lastFeeLp + lastWithdrawableLp = L`，而 `settlementUnit` 按 `pairTotalSupply = S` 计价。设重分类前 `s = L / S`、`r = FEE_SETTLEMENT_RATIO`，实际销毁的精确必要条件是 `feeLp >= floor(S × r / 1e18)`。当 `s < r` 时 `L < rS`；若 `rS` 非整数，`L` 仍可能等于 `floor(rS)`。因此「`s < r` 就永不销毁」只在取整边界之外成立：边界外 `L < settlementUnit`，手续费账本的上限不到一个单位，`settleFees` 只重分类、不实际销毁，手续费 LP 留在合约（仍是池中 LP），直到社区质押增长；边界内 `L == settlementUnit`，手续费账本的上限恰好是一个单位，重分类把全部记账 LP 转为手续费时（如 `L = 1` 时的任意增长）仍会结算。份额达标后，首次销毁所需的 √K 增长 `g` 满足 `g / (1 + g) >= r / s`，即 `g >= (r / s) / (1 - r / s)`；例如 `r = 0.25%`、`s = 1%` 时约需 33% 的 √K 增长。`s = r` 时分母为零：有限增长下需 `s > r`，`s = r` 只有把可提取 LP 全部重分类为手续费的极限才够一个单位。

结算把 `processedFeeLp / pairTotalSupply` 的流动性按比例取出，再把其中父币那半卖出。`processedFeeLp = pairTotalSupply × FEE_SETTLEMENT_RATIO / 1e18`，所以单笔销毁占 Pair LP 总供应的比例恰为配置值；卖出量占父币储备的比例与它相同，成交价相对结算前偏离恰为配置值，池子的现货价移动约为其两倍。**因此该参数同时是夹子敞口的尺度，取值必须满足**：

```text
FEE_SETTLEMENT_RATIO <= 池费率
```

夹子往返成本为两倍池费；只要 `FEE_SETTLEMENT_RATIO <= 池费率`，成交价偏离低于一个池费，现货价移动（约为两倍比例）也不超过两倍池费，往返无利可图。部署期上界 `2.5e15`（0.25%，低于池费率；该值是源码常量，参数文件里因指数写法只收整数尾数而写成 `25e14`）。取值高于该上界会静默放大夹子敞口，由部署脚本在广播前拒绝。

单笔量过小时 `pair.burn` 会回滚 `INSUFFICIENT_LIQUIDITY_BURNED`，本次不结算也不消耗本 Phase 的额度；取出后的父币→代币兑换不在 `_canBurn` 的早退覆盖范围内（零输出回滚 `INSUFFICIENT_OUTPUT_AMOUNT`，会把 `settleFees` 与依赖它的 `withdraw` 一起带走），该窗口只由社区代币储备决定（约 400–402 wei，任何人转入两个 wei 并 `sync()` 即可脱离）。不为它引入池费率假设做销毁前预演——那会换来「假设失配则永久静默停止销毁」的新失败模式，代价大于收益。`feeLp < settlementUnit` 时同样跳过，不足一个结算单位的手续费 LP 继续留在合约；`settlementUnit` 向下取整为零时无法释放。

达到门槛且本 Phase 未结算时，从 Pair 取回 `processedFeeLp` 对应双币：

1. 社区代币直接销毁
2. 父币按固定路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁
3. 最小输出量按同笔交易的当前 Pair 储备现算，不接受调用方传入；截止时间取 `block.timestamp`。二者的作用是拒绝调用方指定路径、最小量与截止时间，并保证兑换与报价在同一笔内一致，**不是** MEV 防护——报价是在同笔内、在当时的储备上读出的，跨交易夹子不受其影响；跨交易面只由上面两条约束与「`FEE_SETTLEMENT_RATIO <= 池费率`」共同处理。这条语义是明确的取舍：结算方是协议自身，没有可参照的独立报价源，任何由调用方传入的最小量都会被夹子反向利用
4. 更新 `totalBurnedToken` 和 `totalParentTokenBurned`（换币前父币数量）
5. 未处理的 `feeLp - processedFeeLp` 保留为待结算手续费，下个 Phase 继续

低于阈值时保留待结算；Pair、Router、销毁或统计更新任一步失败，整笔回滚。每次只处理一个代币社区。

无质押的有效成员返回零状态；`canWithdraw` 对任意 `tokenAddress` 都返回布尔值、不回滚，未申请或未到期时为 false。历史查询读取不晚于目标 Round 的最近记录，含明确归零记录；尚未开始的未来轮按[时点值口径](00-protocol-model.md#实现约束)回滚 `RoundNotStarted(requestedRound, currentRound)`，不把最近记录当作未来轮的值。Vote 用同一入口按当前 Round 读取治理票上限与加速份额，并自行维护投票快照。

## 治理票与加速质押

```text
govVotes = liquidityShares * promisedWaitingPhases
```

Vote 每次投票通过 `Stake.validGovVotes(tokenAddress, currentRound, memberId)` 读取当前有效票，不冻结治理票上限；追加质押、改变承诺等待期和申请解锁会影响票权。加速质押本身不产生票权。

`validBoostShares` 在新 Round 首次操作时承接最近历史值，增减加速份额时更新本轮；无操作轮次读取最近记录，申请解锁后禁止追加，原说明要求累计值不再更新。它是**当轮有效值**而非余额：申请解锁即归零，而 `boostShares` 余额要到提取才清零——这两个量只在「已申请解锁、尚未提取」的窗口里不相等。申请解锁时即按旧行为把成员累计份额与全局累计同步扣减，提取时不再重复扣减；`totalBoostShares` 表示当前成员份额合计，在提取、份额真正离开合约时才减少。这是 Stake 的质押历史，不是 Mint 的结算快照；Mint 只读取 [Vote 保存的投票快照](06-vote.md#投票和加速快照)。

例：Round 4 记录 50，Round 5 追加 30 后为 80；后续无变动轮次读取 80，不逐轮复制。

治理票与加速份额走**同一套轮次账本**，两种口径都能按 Round 查：

```text
totalValidGovVotes(R)   = totalValidGovVotesAdded(R)   - totalValidGovVotesRemoved(R)
totalValidBoostShares(R) = totalValidBoostSharesAdded(R) - totalValidBoostSharesRemoved(R)
```

- 成员口径 `validGovVotes(tokenAddress, round, memberId)` / `validBoostShares(tokenAddress, round, memberId)` 是**时点存量**：用 `RoundHistoryUint256` 做懒继承，每个 Round 只记录发生变更的那一次，未变更的轮次读最近记录，不必逐轮复制。
- 社区口径拆成两个**累计**账本而不是直接存一个总量：`total = added - removed` 因此是结构性的恒等式，不靠维护、也不会漂移。`Added` / `Removed` 各自单调不减，差值恒等于该轮全体成员有效值之和。
- 每轮流量由累计值差分得到：`Added(R) - Added(R-1)`。`Removed` 同理。
- 事件里的 `totalValidGovVotes` / `totalValidBoostShares` 就是这个差值，与查询结果逐条相等。

## 加速激励质押上限

加速质押在入口处限量，Mint 侧不再设输出上限。上限只由「流动性质押本金」和「代币已铸造比例」决定，不随轮次爬升，也没有起始倍数或爬升轮数。

```text
C(token) = floor(T × totalSupply / MAX_SUPPLY) × 2 × F
m_i      = floor(C × v_i / V) × M
```

- `T = totalLiquidityTokenAmount[token]`：流动性质押中的社区代币本金，不是 LP 份额，也不是 `tokenAmountForLiquidity` 的现货折算。
- 第一个 `2` 是命名常量 `LIQUIDITY_TOKEN_EQUIVALENCE_FACTOR`：Uniswap V2 池内双币价值对等，一份社区代币本金对应池内两侧各一份价值，用它把本金折算成社区代币口径。
- `totalSupply / MAX_SUPPLY` 是已铸造比例；两个值都从 `ILOVE20Token(token)` 读取。
- `F = BOOST_STAKE_SUPPLY_FACTOR`：部署参数，不是字面量。
- `v_i = validGovVotes(token, round, memberId)`，`V = totalValidGovVotes(token, round)`，`round` 为入口当轮。
- `M = BOOST_STAKE_MULTIPLIER`：部署参数，固定配置，不随轮次变化。
- 所有除法向下取整；上限只会因取整而收紧，不会放宽。

**`C` 只是单人上限的基数，不是社区聚合上限。** 入口只校验单人 allowance：

```text
stakeBoost 通过条件：member.boostShares + amount <= m_i
```

社区层面不设总量校验。取消聚合上限的原因是它会造成先到先得：早期质押者占满额度后，后期成员即使票权更高也押不进去，而票权占比本身已经随时间与质押规模变化，聚合上限会把这种变化固化成排队顺序。取消后，各成员的额度之和最大为 `Σ m_i = C × M`，但这是上限之和，不是协议承诺或预分配的总量；实际总量只由成员各自存入多少决定。

`totalBoostShares` 保留为**查询与事件口径**，不再是约束：它继续在 `stakeBoost` 时累加、在 `withdraw` 时扣减，出现在 `BoostStaked` / `StakeWithdrawn` 事件和 `totalStake` 返回值中，供前端与审计读取社区加速本金总额。入口校验不再读取该字段，也不再存在以它为比较对象的错误。

**单调性与收缩。** `totalSupply` 会因手续费结算销毁而下降，`T` 会因成员提取本金而下降，因此 `C` 与 `m_i` 都可能变小，已质押的加速余额可能事后超过新上限。处理方式是**入口校验 + 祖父条款**：不强制减仓、不自动销毁已质押代币，已有头寸保持不变；上限收缩后新的 `stakeBoost` 因 `member.boostShares + amount > m_i` 回滚，直到成员提取、票权占比回升或已铸造比例回升。可观测口径：此时 `boostStakeCap` 返回 `memberUsed > memberCap`，且任何新存入的 `BoostCapExceeded` 载荷 `allowed = 0`。`MAX_SUPPLY` 由代币构造参数固定为 `immutable`，不会变化。

**公平性残留。** 单人上限按入口当轮的票权占比计算。后加入者投票会稀释 `v_i / V`，早期成员的 `m_i` 随之下调，但其已存头寸按祖父条款保留，形成「旧头寸超过新额度」的残留；反过来，若某成员在轮内先追加质押、提高票权再存入，其额度按提高后的占比重算。残留的大小取决于占比变化幅度：占比减半则旧头寸可达新额度的两倍，且这部分超额头寸在提取前持续参与加速分配。协议不强行清算这部分，因为清算需要卖出或扣押成员已存入的代币，属于入口校验之外的新机制。

**查询入口。** `boostStakeCap(tokenAddress, memberId)` 返回 `(memberCap, memberUsed)`，其中 `memberCap = m_i`、`memberUsed` 为该成员已存加速本金，均按当前轮计算；上限基数 `C` 只在合约内部计算，不对外返回（其输入 `T` 仍可由 `liquidityTokenAmount(tokenAddress)` 读取）。成员可在 `stakeBoost` 前读到自己的可用额度；但额度会随本轮新增投票、`totalSupply` 销毁和他人提取而变化，查询只是当时快照。

**量纲与可操纵性。** `T` 取 `_totalLiquidityTokenAmount` 本金台账，入池时增加实际转入的社区代币数量，提取时按扣减前的 `totalLiquidityShares` 扣除 `floor(liquidityShares × T / totalLiquidityShares)`，再扣减份额总量，与可提取 LP 的份额口径一致。选择本金而非 `tokenAmountForLiquidity`（`withdrawableLp × reserveToken / pairTotalSupply`）的原因：后者读 Pair 现货储备，可被捐赠 + `sync`、闪电贷或价格波动移动；本金台账只由协议自己的入池/提取写入，不受外部转账影响。代价是本金按入池时数量记账，不随池价重估。

**释放时点。** `unstake` 只把有效加速份额清零，不减少 `totalBoostShares`；`withdraw` 真正归还代币时才减少。由于聚合字段不再参与校验，这一差异只影响查询口径，不影响任何人的可用额度。`mergeStake` 保持聚合总量不变。仅当源带加速余额且目标合并前非空（有流动性质押或有加速余额）时，才在融合完成后按目标的新票占比重算 `m_target` 并校验目标余额；目标为空仓时豁免，因为那只是同一份加速换了持有身份，不构成新存入，合并后该仓位随即处于祖父状态。该检查是防御性的：命中意味着合并后的合计超过按新票占比算出的额度，至少一方在合并前已超限。

## 解锁与提取

1. 当前 NFT 持有人申请统一解锁，记录申请 Phase 和承诺等待期，立即清零治理票，禁止追加及融合。**本 Round 已推举或已投票的成员不得申请解锁**：解锁只清零当前票权，撤不回已经计入本轮的票，放行等于让同一份质押资产在本轮既投票又退出。该限制与融合对源成员的「本轮已使用质押权」检查同口径，只作用于当前治理 Round，上一 Round 用过质押权的成员在新一轮可以解锁。
2. 满足 `currentPhase > unlockRequestPhase + promisedWaitingPhases` 后，当前持有人一次提取 LP 对应双币和加速代币；不能分别解锁、分别提取。等待期按「申请 Phase 之后再等满 `promisedWaitingPhases` 个完整 Phase」计量，与旧 `LOVE20Stake.withdraw` 同口径：申请轮加 `promisedWaitingPhases` 的那一个 Phase 仍然太早，例如在 Phase 100 申请、承诺 `1` 时，Phase 102 起才可提取。
3. NFT 转移不重置等待期，不限制解锁中的 NFT 转移。查询应返回申请 Phase、承诺等待期和是否可提取，任何人可按社区和成员查询。

提取先按原规则结算手续费，再以 `floor(liquidityShares * lastWithdrawableLp / totalLiquidityShares)` 折算 LP。结果为零时跳过 LP 转账与 Pair 销毁，仍归还全部加速代币、扣减成员及社区份额并清理头寸；`StakeWithdrawn` 的双币数量为零。退出者放弃不足一个 LP 最小单位的尾差，零额提取不扣减可提取 LP 总账，余量由剩余份额承接。LP 非零时，只有两侧产出都非零（`lpAmount * reserve_i >= pairTotalSupply`，`i` 取两币）才转入 Pair 并销毁；否则 `pair.burn` 会因一侧取整为零而回滚，而 `withdraw` 是原子的、加速代币返还排在其后，整笔头寸（本金与 boost）将永久锁死。因此「非零但不可烧」时 LP 原样转给提取者：不转入 Pair、不销毁，`StakeWithdrawn` 的双币数量为零，份额与可提取 LP 总账照常扣减，LP 转出同时由 `StakeWithdrawn.withdrawableLpBurned`/`withdrawableLpToMember` 记录，Pair 代币的 Transfer 仍可作标准审计；提取人持 LP 自行退出 Pair，这是协议唯一的直接 LP 出口，仅在销毁会回滚时启用。LP 转出不改变 `pairTotalSupply`，手续费分类与基线照常重算，不受影响。手续费结算或后续资产交付失败仍整笔回滚。

## 融合

用于同一社区质押的单向转移，可支持 NFT 场外交易：

- 源和目标不同且已存在；调用者必须持有源，不要求持有目标。
- 任一方待解锁时拒绝；源在当前治理 Round 已使用过质押权时拒绝，目标已使用过质押权不阻止融合。
- 空目标（`liquidityShares == 0 && boostShares == 0`，与 `stakeLiquidity` / `stakeBoost` 判「已有仓位」的 `targetHadPosition` 同一判据；注意不是 `promisedWaitingPhases == 0`）继承源等待期；非空目标等待期短于源则拒绝，否则保持目标等待期。
- 源全部流动性份额和加速份额并入目标，源当前质押清零。目标原资产不得减少，历史投票和激励不回写。
- 目标本轮已投票仍可接收：融合只增加目标的流动性份额，按 `liquidityShares × promisedWaitingPhases` 重算后表现为治理票增量，与该成员自己追加质押产生的增量等价，可继续用这部分增量投票。
- 源本轮已推举或已投票则禁止融合：推举或投票都视为使用质押权，融合会让同一份质押资产在本轮转移后再次使用。
- 当前 Round 结束后限制清零；上一 Round 使用过质押权的来源，在下一 Round 可以再次融合。Submit 会先完成推举状态写入，再执行创建回调，回调不能绕过该限制。
- 融合后按目标份额正常提取双币和加速代币；解锁中的成员需完成提取后才可再次融合。
- **首次获取治理票的 Round**：目标在融合前没有流动性质押（空仓或只有加速余额）时，目标记本次融合所在 Round；目标已有流动性质押时保留其原有更早的 Round。源被清空，其成员级标记随记录一并归零。社区级标记不受融合影响。

## 拒绝条件与错误

各入口按「鉴权 → 参数 → 存在性 → 业务 → 账本」的顺序校验，先命中的条件先回滚，同一入口内不重排。**鉴权分两类**：处分类入口（`unstake`、`withdraw`、`mergeStake` 源侧）校验 `ownerOf(memberId) == msg.sender`，不持有回滚 `NotMemberOwner(memberId)`；单向增加类入口（`stakeLiquidity`、`stakeBoost`，以及 `mergeStake` 的目标侧）只调 `ownerOf` 校验存在，**不会产生 `NotMemberOwner`**。两类都覆盖 `memberId` 不存在：`memberId == 0` 或 NFT 不存在时由 `MemberNFT.ownerOf` 抛出 `ERC721NonexistentToken`，不进入 `NotMemberOwner`。`ERC721NonexistentToken` 与 token 的 ERC20 标准错误按透传登记，来源 ABI 为 MemberNFT 与 LOVE20Token；`SafeERC20FailedOperation` 通过 `SafeERC20` 进入 Stake ABI。Stake 自有错误定义见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。

`tokenAddress` 的有效性统一由 `ILaunch(LAUNCH_ADDRESS).isLOVE20Token(tokenAddress)` 判定；未由 Launch 登记的地址即使实现了 `PARENT_TOKEN_ADDRESS()` 也无效，回滚 `TokenNotRegistered(tokenAddress)`。需要 Pair 的入口再判 `pairAddress[tokenAddress]` 为零地址，回滚 `PairMissing(tokenAddress)`。

### 构造函数

构造函数不做任何静态校验，只保存入参，因此没有回滚条件。Factory 与 `Router.factory()` 一致、`promisedWaitingPhasesMin > 0`、`0 < feeSettlementRatio <= MAX_FEE_SETTLEMENT_RATIO（2.5e15）`、`min <= max`、`boostStakeSupplyFactor > 0`（建议 1–10，非校验条件）、`boostStakeMultiplier > 0`（建议 1–20，非校验条件）由 DeployCore 广播前校验；六个依赖地址有代码、`LIQUIDITY_TOKEN_EQUIVALENCE_FACTOR == 2` 由 DeployCore 部署后校验；两者均由 21_check 独立复核。

### `stakeLiquidity`

**鉴权：只校验 `memberId` 存在，不要求调用者持有该 NFT**（[无许可增项](01-common-rules.md#无许可增项)）。本入口没有调用者限制，因此不存在鉴权行；`ownerOf(memberId)` 的判定落在「存在性」层。

| 顺序 | 层 | 条件 | 回滚错误 |
| --- | --- | --- | --- |
| 1 | 参数 | `tokenAmount` 为零 | `ZeroTokenAmount()` |
| 2 | 参数 | `parentTokenAmount` 为零 | `ZeroParentTokenAmount()` |
| 3 | 参数 | `promisedWaitingPhases` 不在 `[PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX]` 范围 | `InvalidPromisedWaitingPhases(promisedWaitingPhases, PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX)` |
| 4 | 存在性 | `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚 `ERC721NonexistentToken`） |
| 5 | 存在性 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 6 | 存在性 | 首次质押时 Pair 为零地址 | `PairMissing(tokenAddress)` |
| 7 | 业务 | 当前 Phase 为 `0` | `StakeNotStarted()` |
| 8 | 业务 | 已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, memberId)` |
| 9 | 业务 | 调用者非持有人，`member.promisedWaitingPhases != 0`（该记录被写过），且入参不等于已有值（上调下调都算） | `PromisedWaitingPhasesRewritten(tokenAddress, memberId, promisedWaitingPhases, member.promisedWaitingPhases)` |
| 10 | 业务 | `promisedWaitingPhases` 小于已有值（对所有人生效，含持有人） | `PromisedWaitingPhasesDecreased(promisedWaitingPhases, member.promisedWaitingPhases)` |
| 11 | 业务 | Pair 铸出的 LP 数量为零 | `ZeroLiquidityMinted()` |

第 4 行取代原表第 1 行的 `NotMemberOwner`：判据由「持有该 NFT」放宽为「该 `memberId` 存在」，位置随之从 modifier 层（最前）落到存在性层（参数之后），符合 [开发规范 §5.5](../../dev-standards.md#55-调用者校验)「鉴权 → 参数 → 存在性 → 业务 → 账本」。**这带来一处刻意的错误优先级变化**：不存在的 `memberId` + 非法参数，现在先回滚参数错误、再回滚 `ERC721NonexistentToken`，而旧表是鉴权错误优先。理由是本入口已无鉴权面，没有「非授权方不能探测内部状态」这条约束要守；`memberId` 本身由 ERC721Enumerable 公开可枚举，不构成信息泄漏。

第 6 行在首次质押时读取 Factory 登记的 Pair 并保存；该入口不创建 Pair，未登记即回滚。

第 9、10 行按**先权限、后方向**的顺序判定：先问「这个调用者有没有资格改」（第 9 行，非持有人且记录已写过时一律不许改，上调下调都算），再问「这次改动是不是在调小」（第 10 行）。顺序不可交换：`Rewritten` 必须在 `Decreased` 之前，否则非持有人下调会被报成「变小」而不是「没权限」，诊断信息错位；而 `Decreased` 必须对所有调用者生效（含持有人），否则持有人下调会让 `govVotesAdded` 的减项大于被减项、触发算术下溢。两者条件、主体与可诊断性都不同，按[错误标准 §二](../../error-standards.md)「一条件一错误」不共用一个 selector。**「未写过」的判据是 `member.promisedWaitingPhases == 0` 本身，不是份额余额**：该字段为 `0` 表示这条成员记录从未写入过等待期，非持有人可以自由指定到 `MAX`；一旦非零，非持有人即不得再改写（上调、下调都算，下调优先命中第 9 行）。`PROMISED_WAITING_PHASES_MIN > 0` 由 `DeployCore` 在广播前校验，因此「写入即非零」成立，`0` 不会是一个合法的已写入值。

**「空仓位」的判据是份额而非等待期**：`liquidityShares == 0 && boostShares == 0`，**不是** `promisedWaitingPhases == 0`。两者在当前实现里等价，因为成员记录只在 `withdraw`（整个 `delete`）与 `mergeStake` 的源侧（同样 `delete`）被清空，而 `_creditLiquidity` 写入等待期时必然同时写入至少一份份额：份额公式 `floor(totalLiquidityShares × lpMinted / lastWithdrawableLp)` 的下界由不变量 `lastWithdrawableLp <= totalLiquidityShares` 保证，该不变量又由「两者在 `_creditLiquidity` 同步增长、重分类只降低 `lastWithdrawableLp`」归纳成立，因此 `liquiditySharesAdded >= lpMinted > 0`（`lpMinted == 0` 已回滚 `ZeroLiquidityMinted()`）。按份额判定是**承重**的：若哪天份额增量可以取整为零，一笔 dust 质押就会把等待期写到一条空记录上，钉死真实持有人首次质押的等待期。该等价性由 `StakeInvariant.t.sol` 的 `invariant_EmptyPositionHasNoWaitingPeriod` 与 `invariant_WithdrawableLpNeverExceedsShareTotal` 守护。

**这条约束对任何中间合约同样成立，包括 `periphery` 的 `LOVE20Hub`**：Hub 代用户调 `stakeLiquidity` 时 `msg.sender` 是 Hub 自己，永远不等于 NFT 持有人，因此经 Hub 对**已写入等待期**的成员二次质押只能**精确沿用**当前值，无法借 Hub 提升；要提升等待期，须由持有人**直接调用** `Stake.stakeLiquidity`。Hub 侧据此不提供提升入口，前端应先读 `memberStake(tokenAddress, memberId).promisedWaitingPhases` 原样回填。未写过的记录不受此限，经 Hub 可自由指定（含 `MAX`）。

本入口**没有**滑点类拒绝条件：`slippage` 参数、`SLIPPAGE_PRECISION` 常量、`_checkSlippage` 守卫与 `SlippageExceeded` 错误已删除，折算出的剩余不转账、留在调用者手里，不构成回滚。第 10 行是本次新增：它由原第 9 行的复合条件拆出，见上。

### `stakeBoost`

**鉴权：只校验 `memberId` 存在，不要求调用者持有该 NFT**（同 `stakeLiquidity`，见[无许可增项](01-common-rules.md#无许可增项)）。

| 顺序 | 层 | 条件 | 回滚错误 |
| --- | --- | --- | --- |
| 1 | 参数 | `boostAmount` 为零 | `ZeroBoostAmount()` |
| 2 | 参数 | `promisedWaitingPhases` 不在 `[PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX]` 范围 | `InvalidPromisedWaitingPhases(promisedWaitingPhases, PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX)` |
| 3 | 存在性 | `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚 `ERC721NonexistentToken`） |
| 4 | 存在性 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 5 | 业务 | 当前 Phase 为 `0` | `StakeNotStarted()` |
| 6 | 业务 | 已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, memberId)` |
| 7 | 业务 | 无流动性质押 | `NoStakedLiquidity(tokenAddress, memberId)` |
| 8 | 业务 | 调用者非持有人，`member.promisedWaitingPhases != 0`，且入参不等于已有值（上调下调都算） | `PromisedWaitingPhasesRewritten(tokenAddress, memberId, promisedWaitingPhases, member.promisedWaitingPhases)` |
| 9 | 业务 | `promisedWaitingPhases` 小于已有值（对所有人生效，含持有人） | `PromisedWaitingPhasesDecreased(promisedWaitingPhases, member.promisedWaitingPhases)` |
| 10 | 业务 | 追加后超过该成员的单人上限 `m_i` | `BoostCapExceeded(tokenAddress, memberId, boostAmount, memberRemaining)` |

第 3 行取代原表第 1 行的 `NotMemberOwner`，位置从 modifier 层落到存在性层，与 `stakeLiquidity` 同口径。

第 8、9 行与 `stakeLiquidity` 同口径（同样先权限后方向）：非持有人在该记录已写过等待期时只能沿用现有值（改任何别的值命中第 8 行）。`stakeBoost` 的前提是已有流动性质押（第 7 行），因此「非持有人 + 未写过等待期」这一组合在本入口不可达——非持有人调 `stakeBoost` 时该记录必然已写过等待期，只能沿用。

第 10 行在同一轮按当前 `T`、`totalSupply / MAX_SUPPLY`、`v_i / V` 现算；`allowed` 是当前剩余额度，已超限的祖父头寸对应 `0`。社区层面没有聚合校验，也没有对应的回滚错误。

### `unstake`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 2 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 3 | 已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, memberId)` |
| 4 | 无流动性质押 | `NoStakedLiquidity(tokenAddress, memberId)` |
| 5 | 本 Round 已推举或已投票 | `StakeRightsUsed(tokenAddress, round, memberId)` |

### `withdraw`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 2 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 3 | Pair 为零地址 | `PairMissing(tokenAddress)` |
| 4 | 未申请解锁 | `UnstakeNotRequested(tokenAddress, memberId)` |
| 5 | 无流动性质押 | `NoStakedLiquidity(tokenAddress, memberId)` |
| 6 | 当前 Phase 不大于 `unlockRequestPhase + promisedWaitingPhases` | `UnlockRoundNotReached(currentRound, unlockRequestPhase + promisedWaitingPhases)` |

### `mergeStake`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 调用者不持有源 `memberId` 的 NFT | `NotMemberOwner(sourceMemberId)` |
| 2 | 源与目标相同 | `SourceEqualsTarget(sourceMemberId)` |
| 3 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 4 | 目标 `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚 `ERC721NonexistentToken`） |
| 5 | 源已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, sourceMemberId)` |
| 6 | 目标已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, targetMemberId)` |
| 7 | 源无流动性质押 | `NoStakedLiquidity(tokenAddress, sourceMemberId)` |
| 8 | 源在当前治理 Round 已使用过质押权（已推举或已投票） | `StakeRightsUsed(tokenAddress, round, sourceMemberId)` |
| 9 | 目标非空且其 `promisedWaitingPhases` 短于源 | `TargetPromisedWaitingPhasesTooShort(target.promisedWaitingPhases, source.promisedWaitingPhases)` |
| 10 | 目标合并前非空且融合后加速余额超过目标新票占比下的 `m_target`（仅源带有加速余额时校验） | `BoostCapExceeded(tokenAddress, targetMemberId, targetBoostShares, targetCap)` |

第 10 行是防御性检查。**目标合并前为空仓（既无流动性质押、也无加速余额）时豁免**：此时融合只是同一份加速换了个持有身份，不构成新存入、也不新增加速，因此即使合并后超过额度也允许；该仓位随即处于祖父状态，后续不能再新增。目标只要已有仓位——包括“有 LP 但无加速”——融合都会改变票权结构或带来加速增量，源带加速时照常按合并后的新票占比重算 `memberCap` 并校验。由于融合不改变聚合总量，且目标额度按合并后的合计票占比重算，这一校验只在至少一方合并前已超限时命中。

### `settleFees`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 2 | Pair 为零地址 | `PairMissing(tokenAddress)` |

任何人可调用；未达到一个阈值单位、本 Phase 已结算、或单笔量小到无法在 Pair 两侧都产出非零数量时无操作返回，不回滚。

## 事件

事件签名见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。三个聚合量——流动性份额、加速份额、治理票——在**改变它们的每个事件**上都携带后置总量，与增量字段并存：增量用于折叠，总量用于对账。`totalLiquidityShares` / `totalBoostShares` 必须等于 `totalStake` 的同名字段；`totalValidGovVotes` / `totalValidBoostShares` 必须等于 `totalValidGovVotes(tokenAddress, round)` / `totalValidBoostShares(tokenAddress, round)`，也就是同轮 `Added` 与 `Removed` 之差。`lastFeeLp` 与 `lastWithdrawableLp` 同样在**每个改变它们的事件**上携带后置总量，两个账本可从事件逐笔折叠，不需要反推份额公式或读取 Pair 日志。

| 事件 | 触发入口 | 字段 |
| --- | --- | --- |
| `LiquidityStaked(tokenAddress, round, memberId, caller, memberOwner, tokenAmount, parentTokenAmount, promisedWaitingPhases, prevPromisedWaitingPhases, govVotesAdded, liquiditySharesAdded, liquidityShares, totalLiquidityShares, totalValidGovVotes, totalWithdrawableLp)` | `stakeLiquidity` | `caller` 是直接调用者 `msg.sender`（单笔交易涉及多层合约调用时日志只带发日志的合约地址、`tx.from` 只有顶层 EOA，中间调用者需 `debug_traceTransaction` 才能还原）；`memberOwner` 是 `ownerOf(memberId)` 在本次写入时点的快照；三者（`caller` / `memberOwner` / `tx.from`）比对即可判「本人直接质押 / 本人经 Hub / 第三方代付」。`tokenAmount`/`parentTokenAmount` 为折算后实际入池量（折算剩余从不进入 Stake，故不出现）；`promisedWaitingPhases` 为写入后的新值，`prevPromisedWaitingPhases` 为写入前的旧值（首次质押为 `0`）；`govVotesAdded` = `(旧份额 + 新份额) × promisedWaitingPhases - 旧票权`；`liquiditySharesAdded`/`liquidityShares` 为本次新增份额与成员后置份额；`totalLiquidityShares`/`totalValidGovVotes` 为社区后置总量；`totalWithdrawableLp` 为加入本次 LP 后的后置可提取 LP 账本。**成员后置票权不单独成字段**：它恒等于本 payload 内的 `liquidityShares × promisedWaitingPhases`（`Stake._govVotesOf` 的实现），属[事件规范 §6.9](../../event-standards.md#69-派生缓存) 的派生缓存，携带即冗余；`BoostStaked` 不同——它的 payload 里没有 `liquidityShares`，`govVotes` 不可推导，因此保留。该字段的删除同时受非 `via_ir` 的代码生成上限约束：3 个 indexed 加 13 个 payload 参数（共 16 个）在仓库锁定的 solc 0.8.37 + `optimizer_runs = 200` 下必然 `Stack too deep`，15 个才可通过；[开发规范 §3.1](../../dev-standards.md#31-工具链) 明令不使用 `via_ir`、遇此错误优先重构，因此该字段不能保留。 |
| `BoostStaked(tokenAddress, round, memberId, caller, memberOwner, boostAmount, promisedWaitingPhases, prevPromisedWaitingPhases, govVotesAdded, govVotes, boostShares, totalBoostShares, totalValidBoostShares, totalValidGovVotes)` | `stakeBoost` | `caller` / `memberOwner` / `prevPromisedWaitingPhases` 与 `LiquidityStaked` 同义同口径。`boostAmount` 为本次转入的加速代币数量，同时也是本次份额增量（1:1，不再重复成 `boostSharesAdded`）；`govVotesAdded` 仅在等待期提升时为正；`boostShares` 为成员后置**余额**；`totalBoostShares` 为社区余额合计；`totalValidBoostShares` 为 `round` 当轮有效加速份额合计；`totalValidGovVotes` 为社区后置票权总量 |
| `Unstaked(tokenAddress, round, memberId, promisedWaitingPhases, govVotes, liquidityShares, boostShares, totalValidBoostShares, totalValidGovVotes)` | `unstake` | `round` 同时是本次写入的 `unlockRequestPhase`；`govVotes` 为被清零的票权（社区总量同步减该值）；`liquidityShares`/`boostShares` 为成员仍保留的余额；`totalValidBoostShares` 为扣减后当轮有效加速份额合计；`totalValidGovVotes` 为扣减后社区票权总量 |
| `StakeWithdrawn(tokenAddress, round, memberId, promisedWaitingPhases, liquidityShares, tokenAmountForLiquidity, parentTokenAmountForLiquidity, boostShares, withdrawableLpBurned, withdrawableLpToMember, totalLiquidityShares, totalBoostShares, totalWithdrawableLp)` | `withdraw` | `tokenAmountForLiquidity`/`parentTokenAmountForLiquidity` 为销毁 LP 取回的双币数量；`boostShares` 为归还的加速代币；`withdrawableLpBurned` 与 `withdrawableLpToMember` **互斥**，二者之和等于本次折算出的 LP `floor(liquidityShares × lastWithdrawableLp / totalLiquidityShares)`——`liquidityShares` 是份额，与 LP 不同量纲，不能直接与这两个字段相加；`withdrawableLpBurned` 是可提取 LP 账本中真正烧成双币返还成员的部分，`withdrawableLpToMember` 是「非零但不可烧」时原样交给成员的那一支；`totalWithdrawableLp` 为扣减后的后置账本 |
| `FeesSettled(tokenAddress, round, feeLpBurned, tokenBurned, parentTokenBurned, totalBurnedToken, totalParentTokenBurned, totalFeeLp)` | `settleFees`、`withdraw` 的结算段 | `feeLpBurned` 为本次销毁的费用 LP；`tokenBurned` 为社区代币销毁量（含父币换得的部分），`parentTokenBurned` 为换币前的父币数量；`totalBurnedToken`/`totalParentTokenBurned` 为社区累计销毁量；`totalFeeLp` 为扣减后的后置费用账本 |
| `FeeReclassified(tokenAddress, round, feeLpAdded, withdrawableLpRemoved, totalFeeLp, totalWithdrawableLp, sqrtKOfLp, pairTotalSupply)` | `settleFees`、`withdraw` 的结算段、`stakeLiquidity` 的重分类段 | `feeLpAdded` 为本次转入手续费账本的 LP，`withdrawableLpRemoved` 为可提取 LP 的等量减少（`totalLp` 守恒，二者恒等，见恒等对登记）；`totalFeeLp`/`totalWithdrawableLp` 为后置总账；`sqrtKOfLp` 为重分类后的基线（同一交易内若随后增减流动性或销毁，会再次刷新）；`pairTotalSupply` 为重分类时的 LP 总供应。仅在 √K 增长时发射；`sqrtKOfLp` 是重分类时点快照，不作为折叠来源，`lastSqrtKOfLp` 仍由 Pair `Sync` + `totalLp` 派生 |
| `StakesMerged(tokenAddress, round, sourceMemberId, targetMemberId, liquiditySharesMerged, boostSharesMerged, targetGovVotes, targetLiquidityShares, targetBoostShares, targetPromisedWaitingPhases, prevSourceGovVotes, prevSourcePromisedWaitingPhases, totalValidGovVotes)` | `mergeStake` | `*Merged` 为源侧迁出的份额；`target*` 为目标的后置状态；`prevSource*` 为**融合前**源成员的状态——融合后源被清空、等同于从未质押，因此这两个字段是旧值而非现状，`prevSourceGovVotes` = `liquiditySharesMerged × prevSourcePromisedWaitingPhases`；`totalValidGovVotes` 为社区后置票权总量 |

事件里成员级**没有**单独的有效加速份额字段（查询侧有 `validBoostShares`）：`BoostStaked`、`StakesMerged`、`StakeWithdrawn` 三个时点上 `boostShares` 本身就是有效值（未申请解锁的成员，余额与当轮有效份额相等），而 `Unstaked` 之后有效值恒为 `0`，由事件名承载——另设字段只会是恒等对或常量。全局侧则相反：`totalBoostShares`（余额合计，提取才减）与 `totalValidBoostShares`（当轮有效合计，申请解锁即减）会在「已申请解锁、尚未提取」的成员上分叉，两者必须并存；加速质押的业务趋势以 `totalValidBoostShares` 为准，而不是滞后的 `totalBoostShares`；成员级同理，趋势看 `validBoostShares(tokenAddress, round, memberId)`，而不是 `boostShares`。两个 `valid*` 值都能直接查询，事件里的总量与查询结果必须逐条相等。

`StakeWithdrawn` 不携带 `totalValidGovVotes`：票权在 `unstake` 已清零，提取不再改变它，重复携带属于复述未变化字段。

**只有 `LiquidityStaked` / `BoostStaked` 带 `prevPromisedWaitingPhases`**：Stake 的全部入口里只有 `stakeLiquidity` 与 `stakeBoost` 会改变 `promisedWaitingPhases`；`unstake` 只写入 `unlockRequestPhase` 并读取等待期、`withdraw` 随记录删除一起读取、`mergeStake` 的源记录被 `delete`、目标等待期在空仓时取源值、非空时保持不变。`StakesMerged` 因而不补目标前置值：目标为空仓时该前置值恒为 `0`，非空仓时恒等于 `targetPromisedWaitingPhases`，两种情形都可由新值恒等推导，属[事件规范 §6.7](../../event-standards.md#67-旧值与新值)「旧值由新值恒等可推时可以省略」。

`caller` / `memberOwner` 只在 `LiquidityStaked` / `BoostStaked` 上：这两个入口现在允许任何人调用，链下必须能区分「本人直接质押 / 本人经 Hub / 第三方代付」；`unstake` / `withdraw` / `mergeStake` 的源侧仍然要求 `ownerOf(msg.sender)`，归属由鉴权与 `memberId` 唯一确定，不需要快照。

`withdrawableLpBurned` 与 `feeLpBurned` 都调用 `pair.burn`，但分属两个账本：前者是可提取 LP 账本中被烧成双币返还成员的部分，后者是手续费账本中被销毁的部分（父币先换成社区代币再销毁）；`StakeWithdrawn` 不报告手续费 LP，手续费 LP 只在同一笔交易更早的 `FeesSettled` 中。

## 实现约束

事件与错误定义见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。

- 当前质押余额为 `0` 就表示没有质押；只有 RoundHistory 的历史查询需要区分”本轮没有记录”和”本轮明确归零”，直接沿用旧 RoundHistory 的显式记录语义，不新增额外布尔状态。
- 流动性写操作先按条件表顺序完成鉴权、参数与存在性校验——校验自身允许读取 Factory、代币合约与 MemberNFT 的只读接口——**再发起会改变资产或记账的外部调用**（转入代币、向 Pair 铸出或退出 LP、经 Router 换币），并以这些调用实际返回的数量记账；不设重入锁，一致性由这一顺序保证（与 [通用规则](01-common-rules.md#部署与安全)的检查—更新—交互顺序的差别在此）。读取 Pair 状态，在任何除法前处理 `pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 和基准未增长；需要 Router、Pair 或 ERC20 调用时，以外部调用成功返回的实际数量计算并更新 `lastWithdrawableLp`、`lastFeeLp`、`lastSqrtKOfLp`、成员份额和社区总份额。任一步失败全部回滚。BSC 不使用 SL/ST 凭证，所有份额和可提取 LP 直接存入 Stake。
- 「不设重入锁」的前提是**所有外部调用的接收方都不触发回调**：`tokenAddress` 只能是 Launch 创建的标准 `LOVE20Token`，Pair 是标准 UniswapV2Pair，Router 是部署期固定的可信合约，三者的转账与 `mint`/`burn`/`swap` 都不回调发起方。`withdraw` 在发起任何外部调用之前先 `delete` 成员记录（等待期、流动性份额、加速份额已先读入内存），因此即使存在回调也无法二次提取同一份份额。若将来引入带接收回调的代币标准或替换 Pair 实现，必须先恢复重入锁或补齐完整 CEI。
- 手续费结算失败（Pair 取回、Router 兑换、销毁或统计更新任一失败）时整笔结算回滚；提取本金前自动结算手续费，手续费结算失败则提取也回滚。
- 空目标沿用本文件的等待期继承例外；`MemberStake` 和 `TotalStake` 结构体仅用于内部存储，不作为查询返回格式。
- `memberId == 0` 与不存在的 `memberId` 同走 `MemberNFT.ownerOf`，由 OpenZeppelin 抛出 `ERC721NonexistentToken`；Stake 不声明 `InvalidMemberId()`，与 `Launch` 的既有实现一致。
- 鉴权 modifier 只有 `onlyMemberOwner` 一个，用在 `unstake`、`withdraw`、`mergeStake` 的源侧；`stakeLiquidity`、`stakeBoost` 与 `mergeStake` 的目标侧不走 modifier，改为在函数体内按 `// forge-lint: disable-next-item(unused-return)` + `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId);` 只验存在。**不得为放宽鉴权而给 modifier 加布尔开关**——两个鉴权面的判据不同（`!= msg.sender` 回滚 vs 只验存在），混进一个 modifier 会让「谁可以调」在阅读时不可见（[开发规范 §5.5](../../dev-standards.md#55-调用者校验)）。
- **等待期约束在写点判定，不在 modifier 里**：判据同时依赖 `msg.sender` 与成员仓位的读写，属于业务校验而非调用者校验。统一实现为「该 `memberId` 的 NFT 持有人不是 `msg.sender`，且成员仓位非空（`liquidityShares != 0 || boostShares != 0`）时，入参 `promisedWaitingPhases` 必须等于 `member.promisedWaitingPhases`」，命中即回滚 `PromisedWaitingPhasesRewritten`；下调仍回滚 `PromisedWaitingPhasesDecreased`，两者是两行拒绝条件。
- 治理票的**原始乘积**为 `liquidityShares × promisedWaitingPhases`，只用于在写点计算增量；对外可查的是轮次账本 `validGovVotes(round, memberId)`，申请解锁当轮记 `0`。`stakeLiquidity`、`stakeBoost` 提升等待期、`unstake`、`mergeStake` 四处写点必须同时更新成员账本与社区的 `Added` / `Removed`，使 `totalValidGovVotes(round)` 恒等于该轮全体成员 `validGovVotes` 之和。加速份额同构，但**只在社区净额变化时**写社区账本：`mergeStake` 的加速搬迁只在成员之间移动，净额为零，不写 `Added` / `Removed`（各记一笔等额会把 `total` 抬成两倍）。
- `memberStake()` 和 `totalStake()` 返回的 `tokenAmountForLiquidity` / `parentTokenAmountForLiquidity` 以及 `withdrawableLp` / `feeLp` 都是查询时根据当前 Pair 状态现算的值，不是直接读取存储的历史基准。加速上限不读这些现算值，只读本金台账 `_totalLiquidityTokenAmount`。
- `memberStake(tokenAddress, memberId)` 返回 `(liquidityShares, boostShares, promisedWaitingPhases, unlockRequestPhase, tokenAmountForLiquidity, parentTokenAmountForLiquidity, firstGovVoteRound)`，`totalStake(tokenAddress)` 返回 `(totalLiquidityShares, totalLp, withdrawableLp, feeLp, totalBoostShares, tokenAmountForLiquidity, parentTokenAmountForLiquidity, firstGovVoteRound)`。两个 `firstGovVoteRound` 的口径见[状态](#状态)表：成员级随 `withdraw` 归零、社区级永不重置。两者都**不**由 `stakeBoost` 写入——加速质押本身不产生治理票，也不改变流动性质押份额。
- 加速份额不提供「哪些 Round 发生过变更」的链上枚举：该轮次集合完全可由 `BoostStaked`/`Unstaked`/`StakesMerged` 的 `round` 折叠得到，属派生缓存（事件规范 §6.9），不再单独开分页查询。

历史来源：`LOVE20TKM/core/src/LOVE20Stake.sol` 和 `LOVE20TKM/core/src/LOVE20SLToken.sol`；提交已固定，当前 BSC 行为以本文件为准。验收见 [Core 验收](09-testing.md)。
