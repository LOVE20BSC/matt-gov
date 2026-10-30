# Stake

Stake 按 `tokenAddress + memberId` 维护流动性质押和加速质押，不发行 SL/ST 凭证。两类资产共享解锁生命周期；权限见 [通用规则](01-common-rules.md)。

## 状态

结构体和完整 ABI 见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。

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
| `validGovVotes[tokenAddress][round][memberId]` | 成员在指定治理 Round 的**有效**治理票：`stakeLiquidity` 与提升等待期的 `stakeBoost` 加，申请解锁清零，融合按源→目标搬移；未开始的 Round 回滚 `RoundNotStarted` |
| `validBoostShares[tokenAddress][round][memberId]` | 成员在指定治理 Round 的**有效**加速份额：`stakeBoost` 加、申请解锁清零、融合按源→目标搬移；未开始的 Round 回滚 `RoundNotStarted` |
| `totalValidGovVotesAdded[tokenAddress][round]` / `Removed` | 截至该 Round 的**累计**有效治理票增量 / 减量。两者的差就是社区有效治理票总量 |
| `totalValidBoostSharesAdded[tokenAddress][round]` / `Removed` | 截至该 Round 的**累计**有效加速份额增量 / 减量。两者的差就是社区有效加速份额总量 |
| `pairAddress[tokenAddress]` | 社区对应的 Uniswap V2 兼容 Pair 地址 |
| `totalBurnedToken[tokenAddress]` | 社区代币全局累计销毁量 |
| `totalParentTokenBurned[tokenAddress]` | 该社区手续费中父币的累计数量（换币前） |

## 流动性质押与手续费

`init` 只校验 `initialized` 状态并固定依赖地址和参数，不设调用者限制；成功后 `initialized` 置为 `true`，再次调用回滚 `AlreadyInitialized()`。固定 `PHASE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`VOTE_ADDRESS`、`LAUNCH_ADDRESS`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS`、`PROMISED_WAITING_PHASES_MIN`、`PROMISED_WAITING_PHASES_MAX` 和 `FEE_SETTLEMENT_RATIO`。所有成员写操作校验当前 NFT 持有人；`VOTE_ADDRESS` 提供本轮投票记录并暴露其已绑定的 Submit，`LAUNCH_ADDRESS` 用于确认代币由 Launch 登记。金额单位为代币最小单位，等待期为 Phase。

每个社区的唯一 Pair 由 [Launch](08-launch.md) 在发射该代币的同一笔交易内创建或复用；`Stake` 在首次质押时通过 `PAIR_FACTORY_ADDRESS.getPair(tokenAddress, parentTokenAddress)` 读取并保存，为零地址时回滚 `PairMissing(tokenAddress)`。**`Stake` 的所有入口都只接受 Launch 已登记的代币，只读取已登记的 Pair，不创建 Pair**，未登记回滚 `TokenNotRegistered(tokenAddress)`，无 Pair 回滚 `PairMissing(tokenAddress)`。

调用者提供社区代币、父币的期望数量和允许的滑点。Stake 按当前 Pair 储备折算本次实际入池的最优数量——按储备比例一侧取期望值、另一侧按比例折算，只转入折算后的数量，再直接向 Pair 铸出 LP：

```text
parentTokenAmountOptimal = floor(tokenAmountDesired * reserveParent / reserveToken)
tokenAmountOptimal      = floor(parentTokenAmountDesired * reserveToken / reserveParent)
```

先算父币方向；该值不超过期望值时入池 `(期望代币量, 折算父币量)`，否则改算代币方向并入池 `(折算代币量, 期望父币量)`。折算使任一方向的入池量低于期望值时，偏离量不得超过 `floor(期望量 * slippage / 1e18)`，否则回滚 `SlippageExceeded(actualDeviation, maxDeviation)`——两个参数同为代币最小单位，第一个是本次的实际偏离量、第二个是按容差算出的允许偏离量；`slippage` 按 `1e18` 精度表达允许的相对偏离，`0` 表示不允许任何偏离，不设除零以外的上界。Pair 任一侧储备为零时不做折算，直接采用期望数量。Pair 铸出的 LP 数量为零时回滚 `ZeroLiquidityMinted()`。添加 LP 成功后按 LP 数量计份额；提取时移除 LP 并返还双币。

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
settlementUnit = floor(withdrawableLp * FEE_SETTLEMENT_RATIO / 1e18)
触发条件        feeLp >= settlementUnit
单笔处理量      processedFeeLp = settlementUnit
```

`FEE_SETTLEMENT_RATIO` 是单笔结算占可提取 LP 的比例，以 `1e18` 表示 100%（配置值 `3e15` 即 0.3%）；部署时要求 `0 < FEE_SETTLEMENT_RATIO <= 1e18` 且不大于目标池费率（当前 `3e15`）。

阈值同时定义「何时开始烧」和「一次烧多少」：达到一个单位就结算一个单位，剩余 `feeLp - settlementUnit` 留待下个 Phase。这样不需要第二个参数。

结算把 `processedFeeLp / pairTotalSupply` 的流动性按比例取出，再把其中父币那半卖出，价格移动比例恰为 `processedFeeLp / pairTotalSupply`，即 `(withdrawableLp * FEE_SETTLEMENT_RATIO) / (pairTotalSupply * 1e18)`——不超过 `FEE_SETTLEMENT_RATIO / 1e18`（Stake 持满整个 Pair 时趋近该上界；因结算要求 `feeLp > 0`，实际严格小于）。**因此该参数同时是夹子敞口的尺度，取值必须满足**：

```text
FEE_SETTLEMENT_RATIO <= 池费率
```

夹子需要在一次往返中盖过两倍池费才有利润，上式让单笔价格移动不超过一个池费率，往返成本为两个池费。目标池费率 0.30% 时要求该值不大于 `3e15`；配置使用的 `3e15`（0.3%）即取该上界。取值高于该上界会静默放大夹子敞口，部署前须按目标 DEX 的实际池费率核对。

单笔量过小、无法让 Pair 两侧都产出非零数量时（`pair.burn` 会回滚 `INSUFFICIENT_LIQUIDITY_BURNED`），本次不结算也不消耗本 Phase 的额度。

达到门槛且本 Phase 未结算时，从 Pair 取回 `processedFeeLp` 对应双币：

1. 社区代币直接销毁
2. 父币按固定路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁
3. 最小输出量按同笔交易的当前 Pair 储备现算，不接受调用方传入。它的作用是拒绝调用方指定路径与最小量、并保证同笔内一致，**不是** MEV 防护——报价是在同笔内、在当时的储备上读出的，跨交易夹子不受其影响，跨交易面由上面两条约束处理
4. 更新 `totalBurnedToken` 和 `totalParentTokenBurned`（换币前父币数量）
5. 未处理的 `feeLp - processedFeeLp` 保留为待结算手续费，下个 Phase 继续

低于阈值时保留待结算；Pair、Router、销毁或统计更新任一步失败，整笔回滚。每次只处理一个代币社区。

无质押的有效成员返回零状态；`canWithdraw` 对任意 `tokenAddress` 都返回布尔值、不回滚，未申请或未到期时为 false。历史查询读取不晚于目标 Round 的最近记录，含明确归零记录；尚未开始的未来轮按[时点值口径](00-protocol-model.md#实现约束)回滚 `RoundNotStarted(requiredRound, currentRound)`，不把最近记录当作未来轮的值。Vote 用同一入口按当前 Round 读取治理票上限与加速份额，并自行维护投票快照。

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

## 解锁与提取

1. 当前 NFT 持有人申请统一解锁，记录申请 Phase 和承诺等待期，立即清零治理票，禁止追加及融合。**本 Round 已推举或已投票的成员不得申请解锁**：解锁只清零当前票权，撤不回已经计入本轮的票，放行等于让同一份质押资产在本轮既投票又退出。该限制与融合对源成员的「本轮已使用质押权」检查同口径，只作用于当前治理 Round，上一 Round 用过质押权的成员在新一轮可以解锁。
2. 满足 `currentPhase > unlockRequestPhase + promisedWaitingPhases` 后，当前持有人一次提取 LP 对应双币和加速代币；不能分别解锁、分别提取。等待期按「申请 Phase 之后再等满 `promisedWaitingPhases` 个完整 Phase」计量，与旧 `LOVE20Stake.withdraw` 同口径：申请轮加 `promisedWaitingPhases` 的那一个 Phase 仍然太早，例如在 Phase 100 申请、承诺 `1` 时，Phase 102 起才可提取。
3. NFT 转移不重置等待期，不限制解锁中的 NFT 转移。查询应返回申请 Phase、承诺等待期和是否可提取，任何人可按社区和成员查询。

提取先按原规则结算手续费，再以 `floor(liquidityShares * lastWithdrawableLp / totalLiquidityShares)` 折算 LP。结果为零时跳过 LP 转账与 Pair 销毁，仍归还全部加速代币、扣减成员及社区份额并清理头寸；`StakeWithdrawn` 的双币数量为零。退出者放弃不足一个 LP 最小单位的尾差，零额提取不扣减可提取 LP 总账，余量由剩余份额承接。LP 非零时，只有两侧产出都非零（`lpAmount * reserve_i >= pairTotalSupply`，`i` 取两币）才转入 Pair 并销毁；否则 `pair.burn` 会因一侧取整为零而回滚，而 `withdraw` 是原子的、加速代币返还排在其后，整笔头寸（本金与 boost）将永久锁死。因此「非零但不可烧」时 LP 原样转给提取者：不转入 Pair、不销毁，`StakeWithdrawn` 的双币数量为零，份额与可提取 LP 总账照常扣减，LP 转出同时由 `StakeWithdrawn.lpBurned`/`lpToMember` 记录，Pair 代币的 Transfer 仍可作标准审计；提取人持 LP 自行退出 Pair，这是协议唯一的直接 LP 出口，仅在销毁会回滚时启用。LP 转出不改变 `pairTotalSupply`，手续费分类与基线照常重算，不受影响。手续费结算或后续资产交付失败仍整笔回滚。

## 融合

用于同一社区质押的单向转移，可支持 NFT 场外交易：

- 源和目标不同且已存在；调用者必须持有源，不要求持有目标。
- 任一方待解锁时拒绝；源在当前治理 Round 已使用过质押权时拒绝，目标已使用过质押权不阻止融合。
- 空目标（`promisedWaitingPhases = 0`）继承源等待期；非空目标等待期短于源则拒绝，否则保持目标等待期。
- 源全部流动性份额和加速份额并入目标，源当前质押清零。目标原资产不得减少，历史投票和激励不回写。
- 目标本轮已投票仍可接收：融合只增加目标的流动性份额，按 `liquidityShares × promisedWaitingPhases` 重算后表现为治理票增量，与该成员自己追加质押产生的增量等价，可继续用这部分增量投票。
- 源本轮已推举或已投票则禁止融合：推举或投票都视为使用质押权，融合会让同一份质押资产在本轮转移后再次使用。
- 当前 Round 结束后限制清零；上一 Round 使用过质押权的来源，在下一 Round 可以再次融合。Submit 会先完成推举状态写入，再执行创建回调，回调不能绕过该限制。
- 融合后按目标份额正常提取双币和加速代币；解锁中的成员需完成提取后才可再次融合。

## 拒绝条件与错误

各入口按「鉴权 → 参数 → 存在性 → 业务 → 账本」的顺序校验，先命中的条件先回滚，同一入口内不重排。鉴权行同时覆盖 `memberId` 不存在：`memberId == 0` 或 NFT 不存在时由 `MemberNFT.ownerOf` 抛出 `ERC721NonexistentToken`，不进入 `NotMemberOwner`。`ERC721NonexistentToken` 与 token 的 ERC20 标准错误按透传登记，来源 ABI 为 MemberNFT 与 LOVE20Token；`SafeERC20FailedOperation` 通过 `SafeERC20` 进入 Stake ABI。Stake 自有错误定义见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。

`tokenAddress` 的有效性统一由 `ILaunch(LAUNCH_ADDRESS).isLOVE20Token(tokenAddress)` 判定；未由 Launch 登记的地址即使实现了 `PARENT_TOKEN_ADDRESS()` 也无效，回滚 `TokenNotRegistered(tokenAddress)`。需要 Pair 的入口再判 `pairAddress[tokenAddress]` 为零地址，回滚 `PairMissing(tokenAddress)`。

### `init`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 已初始化 | `AlreadyInitialized()` |

Factory 与 `Router.factory()` 一致、`promisedWaitingPhasesMin > 0`、`0 < feeSettlementRatio <= 目标池费率（当前 3e15）`、`min <= max` 由 DeployCore 广播前校验；六个依赖地址有代码由 DeployCore 部署后校验；两者均由 21_check 独立复核；`init` 只防重复初始化并保存入参。

### `stakeLiquidity`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 2 | `tokenAmount` 为零 | `ZeroTokenAmount()` |
| 3 | `parentTokenAmount` 为零 | `ZeroParentTokenAmount()` |
| 4 | `promisedWaitingPhases` 不在 `[PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX]` 范围 | `InvalidPromisedWaitingPhases(promisedWaitingPhases, PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX)` |
| 5 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 6 | 首次质押时 Pair 为零地址 | `PairMissing(tokenAddress)` |
| 7 | 当前 Phase 为 `0` | `NotAllowedToStakeAtRoundZero()` |
| 8 | 已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, memberId)` |
| 9 | `promisedWaitingPhases` 小于已有值 | `PromisedWaitingPhasesDecreased(promisedWaitingPhases, member.promisedWaitingPhases)` |
| 10 | 折算使入池量低于期望量，且偏离超过 `slippage` | `SlippageExceeded(actualDeviation, maxDeviation)` |
| 11 | Pair 铸出的 LP 数量为零 | `ZeroLiquidityMinted()` |

第 6 行在首次质押时读取 Factory 登记的 Pair 并保存；该入口不创建 Pair，未登记即回滚。

### `stakeBoost`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 调用者不持有指定 `memberId` 的 NFT | `NotMemberOwner(memberId)` |
| 2 | `boostAmount` 为零 | `ZeroBoostAmount()` |
| 3 | `promisedWaitingPhases` 不在 `[PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX]` 范围 | `InvalidPromisedWaitingPhases(promisedWaitingPhases, PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX)` |
| 4 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 5 | 已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, memberId)` |
| 6 | 无流动性质押 | `NoStakedLiquidity(tokenAddress, memberId)` |
| 7 | `promisedWaitingPhases` 小于已有值 | `PromisedWaitingPhasesDecreased(promisedWaitingPhases, member.promisedWaitingPhases)` |

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
| 6 | 当前 Phase 不大于 `unlockRequestPhase + promisedWaitingPhases` | `InsufficientWaitingPhases(currentRound, unlockRequestPhase + promisedWaitingPhases)` |

### `mergeStake`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 调用者不持有源 `memberId` 的 NFT | `NotMemberOwner(sourceMemberId)` |
| 2 | 源与目标相同 | `SourceAndTargetMemberIdsMustBeDifferent(sourceMemberId, targetMemberId)` |
| 3 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 4 | 目标 `memberId` 不存在（含 `0`） | MemberNFT 的标准错误（`ownerOf` 回滚 `ERC721NonexistentToken`） |
| 5 | 源已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, sourceMemberId)` |
| 6 | 目标已申请解锁 | `UnstakeAlreadyRequested(tokenAddress, targetMemberId)` |
| 7 | 源无流动性质押 | `NoStakedLiquidity(tokenAddress, sourceMemberId)` |
| 8 | 源在当前治理 Round 已使用过质押权（已推举或已投票） | `StakeRightsUsed(tokenAddress, round, sourceMemberId)` |
| 9 | 目标非空且其 `promisedWaitingPhases` 短于源 | `TargetPromisedWaitingPhasesTooShort(target.promisedWaitingPhases, source.promisedWaitingPhases)` |

### `settleFees`

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | `tokenAddress` 未由 Launch 登记 | `TokenNotRegistered(tokenAddress)` |
| 2 | Pair 为零地址 | `PairMissing(tokenAddress)` |

任何人可调用；未达到一个阈值单位、本 Phase 已结算、或单笔量小到无法在 Pair 两侧都产出非零数量时无操作返回，不回滚。

## 事件

事件签名见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。三个聚合量——流动性份额、加速份额、治理票——在**改变它们的每个事件**上都携带后置总量，与增量字段并存：增量用于折叠，总量用于对账。`totalLiquidityShares` / `totalBoostShares` 必须等于 `totalStake` 的同名字段；`totalValidGovVotes` / `totalValidBoostShares` 必须等于 `totalValidGovVotes(tokenAddress, round)` / `totalValidBoostShares(tokenAddress, round)`，也就是同轮 `Added` 与 `Removed` 之差。

| 事件 | 触发入口 | 字段 |
| --- | --- | --- |
| `LiquidityStaked(tokenAddress, round, memberId, tokenAmountDesired, parentTokenAmountDesired, tokenAmount, parentTokenAmount, promisedWaitingPhases, govVotesAdded, govVotes, liquiditySharesAdded, liquidityShares, totalLiquidityShares, totalValidGovVotes)` | `stakeLiquidity` | `tokenAmountDesired`/`parentTokenAmountDesired` 为调用方期望量，`tokenAmount`/`parentTokenAmount` 为折算后实际入池量；`govVotesAdded` = `(旧份额 + 新份额) × promisedWaitingPhases - 旧票权`；`govVotes` 为成员后置票权；`liquiditySharesAdded`/`liquidityShares` 为本次新增份额与成员后置份额；两个 `total*` 为社区后置总量 |
| `BoostStaked(tokenAddress, round, memberId, boostAmount, promisedWaitingPhases, govVotesAdded, govVotes, boostShares, totalBoostShares, totalValidBoostShares, totalValidGovVotes)` | `stakeBoost` | `boostAmount` 为本次转入的加速代币数量，同时也是本次份额增量（1:1，不再重复成 `boostSharesAdded`）；`govVotesAdded` 仅在等待期提升时为正；`boostShares` 为成员后置**余额**；`totalBoostShares` 为社区余额合计；`totalValidBoostShares` 为 `round` 当轮有效加速份额合计；`totalValidGovVotes` 为社区后置票权总量 |
| `Unstaked(tokenAddress, round, memberId, promisedWaitingPhases, govVotes, liquidityShares, boostShares, totalValidBoostShares, totalValidGovVotes)` | `unstake` | `round` 同时是本次写入的 `unlockRequestPhase`；`govVotes` 为被清零的票权（社区总量同步减该值）；`liquidityShares`/`boostShares` 为成员仍保留的余额；`totalValidBoostShares` 为扣减后当轮有效加速份额合计；`totalValidGovVotes` 为扣减后社区票权总量 |
| `StakeWithdrawn(tokenAddress, round, memberId, promisedWaitingPhases, liquidityShares, tokenAmountForLiquidity, parentTokenAmountForLiquidity, boostShares, lpBurned, lpToMember, totalLiquidityShares, totalBoostShares)` | `withdraw` | `tokenAmountForLiquidity`/`parentTokenAmountForLiquidity` 为销毁 LP 取回的双币数量；`boostShares` 为归还的加速代币；`lpBurned` 与 `lpToMember` **互斥**，二者之和等于本次折算出的 LP `floor(liquidityShares × lastWithdrawableLp / totalLiquidityShares)`——`liquidityShares` 是份额，与 LP 不同量纲，不能直接与这两个字段相加；`lpToMember` 是「非零但不可烧」时原样交给成员的那一支 |
| `FeesSettled(tokenAddress, round, feeLp, tokenBurned, parentTokenBurned, totalBurnedToken, totalParentTokenBurned)` | `settleFees`、`withdraw` 的结算段 | `feeLp` 为本次处理的费用 LP；`tokenBurned` 为社区代币销毁量（含父币换得的部分），`parentTokenBurned` 为换币前的父币数量；后两个 `total*` 为社区累计销毁量 |
| `StakesMerged(tokenAddress, round, sourceMemberId, targetMemberId, liquiditySharesMerged, boostSharesMerged, targetGovVotes, targetLiquidityShares, targetBoostShares, targetPromisedWaitingPhases, prevSourceGovVotes, prevSourcePromisedWaitingPhases, totalValidGovVotes)` | `mergeStake` | `*Merged` 为源侧迁出的份额；`target*` 为目标的后置状态；`prevSource*` 为**融合前**源成员的状态——融合后源被清空、等同于从未质押，因此这两个字段是旧值而非现状，`prevSourceGovVotes` = `liquiditySharesMerged × prevSourcePromisedWaitingPhases`；`totalValidGovVotes` 为社区后置票权总量 |

事件里成员级**没有**单独的有效加速份额字段（查询侧有 `validBoostShares`）：`BoostStaked`、`StakesMerged`、`StakeWithdrawn` 三个时点上 `boostShares` 本身就是有效值（未申请解锁的成员，余额与当轮有效份额相等），而 `Unstaked` 之后有效值恒为 `0`，由事件名承载——另设字段只会是恒等对或常量。全局侧则相反：`totalBoostShares`（余额合计，提取才减）与 `totalValidBoostShares`（当轮有效合计，申请解锁即减）会在「已申请解锁、尚未提取」的成员上分叉，两者必须并存；加速质押的业务趋势以 `totalValidBoostShares` 为准，而不是滞后的 `totalBoostShares`；成员级同理，趋势看 `validBoostShares(tokenAddress, round, memberId)`，而不是 `boostShares`。两个 `valid*` 值都能直接查询，事件里的总量与查询结果必须逐条相等。

`StakeWithdrawn` 不携带 `totalValidGovVotes`：票权在 `unstake` 已清零，提取不再改变它，重复携带属于复述未变化字段。

## 实现约束

事件与错误定义见 [`IStake.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IStake.sol)。

- 当前质押余额为 `0` 就表示没有质押；只有 RoundHistory 的历史查询需要区分”本轮没有记录”和”本轮明确归零”，直接沿用旧 RoundHistory 的显式记录语义，不新增额外布尔状态。
- 流动性写操作先按条件表顺序完成鉴权、参数与存在性校验——校验自身允许读取 Factory、代币合约与 MemberNFT 的只读接口——**再发起会改变资产或记账的外部调用**（转入代币、向 Pair 铸出或退出 LP、经 Router 换币），并以这些调用实际返回的数量记账；不设重入锁，一致性由这一顺序保证（与 [通用规则](01-common-rules.md#初始化与安全)的检查—更新—交互顺序的差别在此）。读取 Pair 状态，在任何除法前处理 `pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 和基准未增长；需要 Router、Pair 或 ERC20 调用时，以外部调用成功返回的实际数量计算并更新 `lastWithdrawableLp`、`lastFeeLp`、`lastSqrtKOfLp`、成员份额和社区总份额。任一步失败全部回滚。BSC 不使用 SL/ST 凭证，所有份额和可提取 LP 直接存入 Stake。
- 手续费结算失败（Pair 取回、Router 兑换、销毁或统计更新任一失败）时整笔结算回滚；提取本金前自动结算手续费，手续费结算失败则提取也回滚。
- 空目标沿用本文件的等待期继承例外；`MemberStake` 和 `TotalStake` 结构体仅用于内部存储，不作为查询返回格式。
- `memberId == 0` 与不存在的 `memberId` 同走 `MemberNFT.ownerOf`，由 OpenZeppelin 抛出 `ERC721NonexistentToken`；Stake 不声明 `InvalidMemberId()`，与 `Launch` 的既有实现一致。
- 治理票的**原始乘积**为 `liquidityShares × promisedWaitingPhases`，只用于在写点计算增量；对外可查的是轮次账本 `validGovVotes(round, memberId)`，申请解锁当轮记 `0`。`stakeLiquidity`、`stakeBoost` 提升等待期、`unstake`、`mergeStake` 四处写点必须同时更新成员账本与社区的 `Added` / `Removed`，使 `totalValidGovVotes(round)` 恒等于该轮全体成员 `validGovVotes` 之和。加速份额同构，但**只在社区净额变化时**写社区账本：`mergeStake` 的加速搬迁只在成员之间移动，净额为零，不写 `Added` / `Removed`（各记一笔等额会把 `total` 抬成两倍）。
- `memberStake()` 和 `totalStake()` 返回的 `tokenAmountForLiquidity` / `parentTokenAmountForLiquidity` 以及 `withdrawableLp` / `feeLp` 都是查询时根据当前 Pair 状态现算的值，不是直接读取存储的历史基准。
- 加速份额不提供「哪些 Round 发生过变更」的链上枚举：该轮次集合完全可由 `BoostStaked`/`Unstaked`/`StakesMerged` 的 `round` 折叠得到，属派生缓存（事件规范 §6.9），不再单独开分页查询。

历史来源：`LOVE20TKM/core/src/LOVE20Stake.sol` 和 `LOVE20TKM/core/src/LOVE20SLToken.sol`；提交已固定，当前 BSC 行为以本文件为准。验收见 [Core 验收](09-testing.md)。
