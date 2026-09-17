# Stake

Stake 按 `tokenAddress + memberId` 维护流动性质押和加速质押，不发行 SL/ST 凭证。两类资产共享解锁生命周期；权限见 [通用规则](01-common-rules.md)。

## 状态

结构体和完整 ABI 见 [`IStake.sol`](../../../interfaces/core/IStake.sol)。

| 字段 | 含义 |
| --- | --- |
| `liquidityShares` / `boostShares` | 成员流动性份额 / 加速质押份额 |
| `promisedWaitingPhases` | 承诺解锁期，单位 Phase |
| `unlockRequestPhase` | 申请 Phase；0 表示未申请 |
| `totalLiquidityShares` / `totalBoostShares` | 社区份额总量 |
| `totalLp` | 合约记账的 LP 总量（等于 `lastWithdrawableLp + lastFeeLp`，不含他人主动转入的 LP） |
| `lastWithdrawableLp` | 上次结算后的可提取 LP 基准 |
| `lastFeeLp` | 上次结算后的协议手续费 LP 基准 |
| `lastSqrtKOfLp` | 上次结算的 sqrt(k) 基准 |
| `lastSettlePhase[tokenAddress]` | 上次**实际**结算的 Phase；等于当前 Phase 时本 Phase 不再结算，仅内部使用、不对外提供 getter |
| `cumulatedBoostShares[tokenAddress][round][memberId]` | 指定治理 Round 的累计加速份额 |
| `pairAddress[tokenAddress]` | 社区对应的 Uniswap V2 兼容 Pair 地址 |
| `totalBurnedToken[tokenAddress]` | 社区代币全局累计销毁量 |
| `totalParentTokenBurned[tokenAddress]` | 该社区手续费中父币的累计数量（换币前） |

## 流动性质押与手续费

`init` 只校验 `initialized` 状态并固定依赖地址和参数，不设调用者限制；成功后 `initialized` 置为 `true`，再次调用回滚 `AlreadyInitialized()`。固定 `phaseAddress`、`memberNFTAddress`、`voteAddress`、`routerAddress`、`pairFactoryAddress`、`PROMISED_WAITING_PHASES_MIN`、`PROMISED_WAITING_PHASES_MAX` 和 `MAX_WITHDRAWABLE_TO_FEE_RATIO`。所有成员写操作校验当前 NFT 持有人；`voteAddress` 用于融合时检查来源本轮投票。金额单位为代币最小单位，等待期为 Phase。

每个社区的唯一 Pair 由 [Launch](08-launch.md) 在发射该代币的同一笔交易内创建；`Stake` 在首次质押时通过 `pairFactoryAddress.getPair(tokenAddress, parentTokenAddress)` 读取并保存，为零地址时回滚 `InvalidTokenAddress()`。**`Stake` 的所有入口都只读取已登记的 Pair、不创建 Pair**，未登记即回滚。

调用者提供社区代币、父币的期望数量和允许的滑点。Stake 按当前 Pair 储备折算本次实际入池的最优数量——按储备比例一侧取期望值、另一侧按比例折算，只转入折算后的数量，再直接向 Pair 铸出 LP：

```text
parentTokenAmountOptimal = floor(tokenAmountDesired * reserveParent / reserveToken)
tokenAmountOptimal      = floor(parentTokenAmountDesired * reserveToken / reserveParent)
```

先算父币方向；该值不超过期望值时入池 `(期望代币量, 折算父币量)`，否则改算代币方向并入池 `(折算代币量, 期望父币量)`。折算使任一方向的入池量低于期望值时，偏离比例不得超过 `slippage`，否则回滚 `SlippageExceeded(slippage, deviation)`——第一个参数是调用方请求的容差、第二个是本次的实际偏离量，便于定位失败规模；`slippage` 按 `1e18` 精度表达允许的相对偏离，`0` 表示不允许任何偏离，不设除零以外的上界。Pair 任一侧储备为零时不做折算，直接采用期望数量。Pair 铸出的 LP 数量为零时回滚 `ZeroAmount("lpMinted")`。添加 LP 成功后按 LP 数量计份额；提取时移除 LP 并返还双币。

份额铸造公式（必须在手续费重分类之后计算）：

```text
sharesMinted = totalLiquidityShares == 0 or lastWithdrawableLp == 0
    ? lpMinted
    : floor(totalLiquidityShares * lpMinted / lastWithdrawableLp)
```

`lastWithdrawableLp == 0` 表示既有份额的可提取基准已被全部重分类为手续费，此时新存入按自身的 `lpMinted` 计份额；该零基准分支沿用旧 `LOVE20SLToken`，避免除零回滚。

手续费重分类公式（必须在份额铸造之前执行）：

```text
currentSqrtKOfLp = floor(sqrt(reserve0 * reserve1) * totalLp / pairTotalSupply)
newWithdrawableLp = floor(lastWithdrawableLp * lastSqrtKOfLp / currentSqrtKOfLp)
newFeeLp = totalLp - newWithdrawableLp
```

`totalLp` 是合约记账的 LP 总量（`lastWithdrawableLp + lastFeeLp`），`pairTotalSupply` 是 Pair 的 LP 总供应。两者必须同一口径：基线 `lastSqrtKOfLp` 与重分类都用记账量计算，任何人主动转入的 LP 既不影响基准也不进入可提取量，避免重分类两侧基数不一致。仅当 `currentSqrtKOfLp > lastSqrtKOfLp` 时重分类手续费；`pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 或基准未增长时跳过结算，不能先除零再判断。结算更新 `lastWithdrawableLp`、`lastFeeLp` 和 `lastSqrtKOfLp`；`totalLp` 不单独写，它在每次基准更新（份额铸造、提取、结算）时由 `lastWithdrawableLp + lastFeeLp` 重算，这是它唯一的写入方式。

**流动性质押的执行顺序**：先重分类手续费（更新 `lastWithdrawableLp`），再按新的 `lastWithdrawableLp` 计算份额。两个公式都以 `lastWithdrawableLp` 为输入，顺序错误会导致份额和手续费计算错误。

手续费增量归协议，不归旧质押者。重分类后可提取 LP 下降；相同新存入 LP 对应更多份额。无池价变化的比例模型中，这是剥离手续费，不是损失本金；整数舍入仍须按公式计算。

例（整数模型）：原可提取 LP 为 120，旧/新 sqrt(k) 基准为 100/120，重分类后可提取 LP 为 100、手续费 LP 为 20。原总份额为 120 时，新存入 100 LP 得到 120 份额。

## 手续费结算与销毁

任何人可调用 `settleFees(tokenAddress)` 单独结算手续费；提取本金前也自动结算。重分类每次都执行，因为它决定后续定价所用的 `withdrawableLp`；真正取回双币并销毁的结算则受两条约束：

**一、每个社区每个 Phase 最多结算一次。** 单笔上限只约束一次调用，同一笔交易内重复调用即可把额度刷完，所以必须有这条按 Phase 的限频才能让上限真正成立。

**二、单笔结算量就是一个阈值单位。**

```text
settlementUnit = floor(withdrawableLp / MAX_WITHDRAWABLE_TO_FEE_RATIO)
触发条件        feeLp >= settlementUnit
单笔处理量      processedFeeLp = settlementUnit
```

阈值同时定义「何时开始烧」和「一次烧多少」：达到一个单位就结算一个单位，剩余 `feeLp - settlementUnit` 留待下个 Phase。这样不需要第二个参数。

结算把 `processedFeeLp / pairTotalSupply` 的流动性按比例取出，再把其中父币那半卖出，价格移动比例恰为 `processedFeeLp / pairTotalSupply`，即 `(withdrawableLp / pairTotalSupply) / MAX_WITHDRAWABLE_TO_FEE_RATIO`——不超过 `1 / MAX_WITHDRAWABLE_TO_FEE_RATIO`（Stake 持满整个 Pair 时取到上界）。**因此该参数同时是夹子敞口的尺度，取值必须满足**：

```text
MAX_WITHDRAWABLE_TO_FEE_RATIO >= 1 / 池费率
```

夹子需要在一次往返中盖过两倍池费才有利润，上式让单笔价格移动不超过一个池费率，留出两倍余量。目标池费率 0.25% 时要求该值不小于 `400`；旧代码使用的 `1000` 满足（覆盖率 0.1%，余量 2.5 倍）。取值低于该下界会静默放大夹子敞口，部署前须按目标 DEX 的实际池费率核对。

单笔量过小、无法让 Pair 两侧都产出非零数量时（`pair.burn` 会回滚 `INSUFFICIENT_LIQUIDITY_BURNED`），本次不结算也不消耗本 Phase 的额度。

达到门槛且本 Phase 未结算时，从 Pair 取回 `processedFeeLp` 对应双币：

1. 社区代币直接销毁
2. 父币按固定路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁
3. 最小输出量按同笔交易的当前 Pair 储备现算，不接受调用方传入。它的作用是拒绝调用方指定路径与最小量、并保证同笔内一致，**不是** MEV 防护——报价是在同笔内、在当时的储备上读出的，跨交易夹子不受其影响，跨交易面由上面两条约束处理
4. 更新 `totalBurnedToken` 和 `totalParentTokenBurned`（换币前父币数量）
5. 未处理的 `feeLp - processedFeeLp` 保留为待结算手续费，下个 Phase 继续

低于阈值时保留待结算；Pair、Router、销毁或统计更新任一步失败，整笔回滚。每次只处理一个代币社区。

无质押的有效成员返回零状态；`canWithdraw` 对任意 `tokenAddress` 都返回布尔值、不回滚，未申请或未到期时为 false。历史查询读取不晚于目标 Round 的最近记录，含明确归零记录；尚未开始的未来轮按[时点值口径](00-protocol-model.md#实现约束)回滚 `InvalidPhase(round)`（承接旧 `RoundHasNotStartedYet` 的语义），不把最近记录当作未来轮的值。Vote 从上述历史查询取加速份额，并自行维护投票快照。

## 治理票与加速质押

```text
govVotes = liquidityShares * promisedWaitingPhases
```

Vote 每次投票通过 `Stake.validGovVotes(tokenAddress, memberId)` 读取当前有效票，不冻结治理票上限；追加质押、改变承诺等待期和申请解锁会影响票权。加速质押本身不产生票权。

`cumulatedBoostShares` 在新 Round 首次操作时承接最近历史值，增减加速份额时更新本轮；无操作轮次读取最近记录，申请解锁后禁止追加，原说明要求累计值不再更新。申请解锁时即按旧行为把成员累计份额与全局累计同步扣减，提取时不再重复扣减；`totalBoostShares` 表示当前成员份额合计，在提取、份额真正离开合约时才减少。这是 Stake 的质押历史，不是 Mint 的结算快照；Mint 只读取 [Vote 保存的投票快照](06-vote.md#投票和加速快照)。

例：Round 4 记录 50，Round 5 追加 30 后为 80；后续无变动轮次读取 80，不逐轮复制。

## 解锁与提取

1. 当前 NFT 持有人申请统一解锁，记录申请 Phase 和承诺等待期，立即清零治理票，禁止追加及融合。
2. 满足 `currentPhase > unlockRequestPhase + promisedWaitingPhases` 后，当前持有人一次提取 LP 对应双币和加速代币；不能分别解锁、分别提取。等待期按「申请 Phase 之后再等满 `promisedWaitingPhases` 个完整 Phase」计量，与旧 `LOVE20Stake.withdraw` 同口径：申请轮加 `promisedWaitingPhases` 的那一个 Phase 仍然太早，例如在 Phase 100 申请、承诺 `1` 时，Phase 102 起才可提取。
3. NFT 转移不重置等待期，不限制解锁中的 NFT 转移。查询应返回申请 Phase、承诺等待期和是否可提取，任何人可按社区和成员查询。

## 融合

用于同一社区质押的单向转移，可支持 NFT 场外交易：

- 源和目标不同且已存在；调用者必须持有源，不要求持有目标。
- 任一方待解锁时拒绝；源在当前治理 Round 已有非零投票时拒绝，目标已投票不阻止融合。
- 空目标（`promisedWaitingPhases = 0`）继承源等待期；非空目标等待期短于源则拒绝，否则保持目标等待期。
- 源全部流动性份额和加速份额并入目标，源当前质押清零。目标原资产不得减少，历史投票和激励不回写。
- 目标本轮已投票仍可接收：融合只增加目标的流动性份额，按 `liquidityShares × promisedWaitingPhases` 重算后表现为治理票增量，与该成员自己追加质押产生的增量等价，可继续用这部分增量投票。
- 源本轮已投票则禁止融合：源的票权已经计入本轮投票，融合会让同一份质押资产在本轮产生两次投票。
- 融合后按目标份额正常提取双币和加速代币；解锁中的成员需完成提取后才可再次融合。

## 拒绝条件与错误

各入口按「参数 → 存在性 → 持有 → 账本」的顺序校验，先命中的条件先回滚，同一入口内不重排。事件与错误定义见 [`IStake.sol`](../../../interfaces/core/IStake.sol)。

`tokenAddress` 的有效性统一按两条判定：`ILOVE20Token(tokenAddress).parentTokenAddress()` 返回零地址，即不是已登记 LOVE20 代币；需要 Pair 的入口再判 `pairAddress[tokenAddress]` 为零地址。两者都回滚 `InvalidTokenAddress()`。

### `init`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 已初始化 | `AlreadyInitialized()` |
| 2 | `phaseAddress`、`memberNFTAddress`、`voteAddress`、`routerAddress`、`pairFactoryAddress` 任一为零地址 | `InvalidAddress()` |
| 3 | `promisedWaitingPhasesMin` 为零 | `ZeroAmount("promisedWaitingPhasesMin")` |
| 4 | `maxWithdrawableToFeeRatio` 为零 | `ZeroAmount("maxWithdrawableToFeeRatio")` |
| 5 | `promisedWaitingPhasesMin` 大于 `promisedWaitingPhasesMax` | `InvalidAmount()` |

### `stakeLiquidity`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `tokenAmount` 或 `parentTokenAmount` 为零 | `StakeAmountMustBeSet()` |
| 2 | `promisedWaitingPhases` 不在 `[PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX]` 范围 | `PromisedWaitingPhasesOutOfRange()` |
| 3 | `tokenAddress` 无效，或首次质押时 Pair 为零地址 | `InvalidTokenAddress()` |
| 4 | 当前 Phase 为 `0` | `NotAllowedToStakeAtRoundZero()` |
| 5 | `memberId` 为 `0` | `InvalidMemberId()` |
| 6 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 7 | 已申请解锁 | `UnstakeAlreadyRequested()` |
| 8 | `promisedWaitingPhases` 小于已有值 | `PromisedWaitingPhasesMustBeGreaterOrEqualThanBefore()` |
| 9 | 折算使入池量低于期望量，且偏离比例超过 `slippage` | `SlippageExceeded(slippage, deviation)` |
| 10 | Pair 铸出的 LP 数量为零 | `ZeroAmount("lpMinted")` |

第 3 行在首次质押时读取 Factory 登记的 Pair 并保存；该入口不创建 Pair，未登记即回滚。

### `stakeBoost`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `boostAmount` 为零 | `StakeAmountMustBeSet()` |
| 2 | `promisedWaitingPhases` 不在 `[PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX]` 范围 | `PromisedWaitingPhasesOutOfRange()` |
| 3 | `tokenAddress` 无效 | `InvalidTokenAddress()` |
| 4 | `memberId` 为 `0` | `InvalidMemberId()` |
| 5 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 6 | 已申请解锁 | `UnstakeAlreadyRequested()` |
| 7 | 无流动性质押 | `NoStakedLiquidity()` |
| 8 | `promisedWaitingPhases` 小于已有值 | `PromisedWaitingPhasesMustBeGreaterOrEqualThanBefore()` |

### `unstake`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `tokenAddress` 无效 | `InvalidTokenAddress()` |
| 2 | `memberId` 为 `0` | `InvalidMemberId()` |
| 3 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 4 | 已申请解锁 | `UnstakeAlreadyRequested()` |
| 5 | 无流动性质押 | `NoStakedLiquidity()` |

### `withdraw`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `tokenAddress` 无效，或 Pair 为零地址 | `InvalidTokenAddress()` |
| 2 | `memberId` 为 `0` | `InvalidMemberId()` |
| 3 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 4 | 未申请解锁 | `UnstakeNotRequested()` |
| 5 | 无流动性质押 | `NoStakedLiquidity()` |
| 6 | 当前 Phase 不大于 `unlockRequestPhase + promisedWaitingPhases` | `NotEnoughWaitingPhases()` |

### `mergeStake`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 源与目标相同 | `SourceAndTargetMustBeDifferent()` |
| 2 | `tokenAddress` 无效 | `InvalidTokenAddress()` |
| 3 | 源或目标 `memberId` 为 `0` | `InvalidMemberId()` |
| 4 | 调用者不持有源 `memberId` 的 NFT | `NotMemberOwner(sourceMemberId)` |
| 5 | 源或目标已申请解锁 | `UnstakeAlreadyRequested()` |
| 6 | 源无流动性质押 | `NoStakedLiquidity()` |
| 7 | 源在当前治理 Round 已有非零投票 | `SourceHasVotedInCurrentRound()` |
| 8 | 目标非空且其 `promisedWaitingPhases` 短于源 | `TargetPromisedWaitingPhasesTooShort()` |

### `settleFees`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `tokenAddress` 无效，或 Pair 为零地址 | `InvalidTokenAddress()` |

任何人可调用；未达到一个阈值单位、本 Phase 已结算、或单笔量小到无法在 Pair 两侧都产出非零数量时无操作返回，不回滚。

## 实现约束

事件与错误定义见 [`IStake.sol`](../../../interfaces/core/IStake.sol)。

- 当前质押余额为 `0` 就表示没有质押；只有 RoundHistory 的历史查询需要区分”本轮没有记录”和”本轮明确归零”，直接沿用旧 RoundHistory 的显式记录语义，不新增额外布尔状态。
- 流动性写操作先按条件表顺序完成参数与权限校验——校验自身允许读取 Factory、代币合约与 MemberNFT 的只读接口——**再发起会改变资产或记账的外部调用**（转入代币、向 Pair 铸出或退出 LP、经 Router 换币），并以这些调用实际返回的数量记账；不设重入锁，一致性由这一顺序保证（与 [通用规则](01-common-rules.md#初始化与安全)的检查—更新—交互顺序的差别在此）。读取 Pair 状态，在任何除法前处理 `pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 和基准未增长；需要 Router、Pair 或 ERC20 调用时，以外部调用成功返回的实际数量计算并更新 `lastWithdrawableLp`、`lastFeeLp`、`lastSqrtKOfLp`、成员份额和社区总份额。任一步失败全部回滚。BSC 不使用 SL/ST 凭证，所有份额和可提取 LP 直接存入 Stake。
- 手续费结算失败（Pair 取回、Router 兑换、销毁或统计更新任一失败）时整笔结算回滚；提取本金前自动结算手续费，手续费结算失败则提取也回滚。
- 空目标沿用本文件的等待期继承例外；`MemberStake` 和 `GlobalStake` 结构体仅用于内部存储，不作为查询返回格式。
- `InvalidMemberId()` 只覆盖 `memberId == 0`；`memberId` 非零但不存在的，由 `MemberNFT.ownerOf` 抛出 OpenZeppelin 的 `ERC721NonexistentToken`，与 `Launch` 的既有实现一致，不另作归一化。
- 治理票为 `liquidityShares × promisedWaitingPhases`；`unlockRequestPhase != 0` 时 `validGovVotes` 返回 `0`，`globalGovVotes` 与全体成员 `validGovVotes` 之和保持一致，追加质押、提升等待期、申请解锁、融合、提取都要同步增减。
- `stakeData()` 和 `globalStakeData()` 返回的 `tokenAmountForLiquidity` / `parentTokenAmountForLiquidity` 以及 `withdrawableLp` / `feeLp` 都是查询时根据当前 Pair 状态现算的值，不是直接读取存储的历史基准。
- 分页查询 `globalBoostUpdatedRounds` 和 `boostUpdatedRounds` 使用 `(offset, limit, reverse)` 参数顺序并返回 `(rounds, totalCount)`，与 `IPhase`、`IMemberNFT`、`ILaunch` 的分页接口一致。

历史来源：`LOVE20TKM/core/src/LOVE20Stake.sol` 和 `LOVE20TKM/core/src/LOVE20SLToken.sol`；提交已固定，当前 BSC 行为以本文件为准。验收见 [Core 验收](09-testing.md)。
