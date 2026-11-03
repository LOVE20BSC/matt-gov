# Stake · 状态变量变更审查

> `core/src/Stake.sol`，911 行，`core@6fdd0f1`。
> 全仓唯一托管资产的合约：代币、父币、LP、加速代币都在这里。它同时是「治理票 / 加速份额」两本轮次账本的唯一写入者，而 Vote、Submit、Mint 三家都读它。
> **基线说明**：`1266696 feat(stake)!: close the LP ledger and settle on pair supply` 重写了本合约的 LP 账本与结算单位（`settlementUnit` 从 `withdrawableLp × ratio` 改为 `pairTotalSupply × ratio`），因此上一卷（`9297a33`）的 Stake 结论不能直接沿用；本文全部从当前代码重推。
> **编号说明**：本文引用的 `STK-01` / `STK-02` … `STK-05` 均指 `core-review-plan-2026-11` 的编号（该卷按函数单元审）；本卷新增项从 `STK-07` 起，`STK-06` 在该卷是「已排除」记录，不复用。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `initialized` | `bool` | 一次性开关 | `init:88` |
| 2-7 | `PHASE_ADDRESS` / `MEMBER_NFT_ADDRESS` / `VOTE_ADDRESS` / `LAUNCH_ADDRESS` / `ROUTER_ADDRESS` / `PAIR_FACTORY_ADDRESS` | `address` | 依赖 | `init:89-94` |
| 8-10 | `PROMISED_WAITING_PHASES_MIN/MAX` / `FEE_SETTLEMENT_RATIO` | `uint256` | 参数 | `init:95-97` |
| 11 | `_pairAddressByTokenAddress` | `mapping(address => address)` | 代币 → Pair 的**惰性缓存** | `_pairFor:530` |
| 12 | `_totalStake` | `mapping(address => TotalStake)` | 社区账本（5 字段） | 见 §2.3 |
| 13 | `_memberStake` | `mapping(address => mapping(uint256 => MemberStake))` | 成员账本（4 字段） | 见 §2.2 |
| 14-15 | `_totalBurnedToken` / `_totalParentTokenBurned` | `mapping(address => uint256)` | 累计销毁量 | `_realizeFees:856`、`:866` |
| 16-19 | `_totalValidGovVotesAdded/Removed`、`_totalValidBoostSharesAdded/Removed` | `mapping(address => RoundHistoryUint256.History)` | 社区**累计**增量/减量 | 见 §2.4 |
| 20-21 | `_validGovVotesByMember` / `_validBoostSharesByMember` | `mapping(address => mapping(uint256 => History))` | 成员按轮存量 | 见 §2.4 |
| 22 | `_lastSettlePhase` | `mapping(address => uint256)` | 上次**实际**结算的 Phase | `_realizeFees:851` |

`TotalStake` = `{totalLiquidityShares, lastWithdrawableLp, lastFeeLp, lastSqrtKOfLp, totalBoostShares}`；`MemberStake` = `{liquidityShares, boostShares, promisedWaitingPhases, unlockRequestPhase}`。`totalLp` 不落存储，由 `lastFeeLp + lastWithdrawableLp` 派生（`:409`、`:769`）。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:76-98`）

一次写入 1 个 bool + 6 个地址 + 3 个参数，**只有 `initialized` 守卫，没有任何参数校验**。`VOTE_ADDRESS` / `LAUNCH_ADDRESS` 被后续读写路径直接信任；`PAIR_FACTORY_ADDRESS` 与 `ROUTER_ADDRESS` 未校验「同一个 factory」（规格 `04-stake.md:169` 把它放在部署脚本）。失败形态：错一个地址 → 某条路径永久回滚，且无 setter 可修。

### 2.2 `_memberStake`：五个写点

| 写点 | 位置 | 语句 | 同函数内的前置守卫 | 联动写入 |
| --- | --- | --- | --- | --- |
| `stakeLiquidity` | `:606-607` | `liquidityShares += added`；`promisedWaitingPhases = P` | `onlyMemberOwner` → `tokenAmount != 0` → `parentAmount != 0` → `P ∈ [min,max]` → `token 已登记` → `pair 存在` → `round != 0` → 未申请解锁 → `P >= 旧P` → 滑点 → `lpMinted > 0` | `totalLiquidityShares +=`、`lastWithdrawableLp += lpMinted`、票账本两处 `increase` |
| `stakeBoost` | `:156`、`:161` | `boostShares += boostAmount`；`promisedWaitingPhases = P`（仅提升时） | `onlyMemberOwner` → `boostAmount != 0` → `P ∈ [min,max]` → `token` → 未申请解锁 → **有流动性质押** → `P >= 旧P` | `totalBoostShares +=`；提升时补票 `L × (P−旧P)`；boost 账本两处 `increase` |
| `unstake` | `:203` | `unlockRequestPhase = round` | `onlyMemberOwner` → `token` → 未申请解锁 → 有流动性 → **本轮未推举/未投票**（`:196-198`） | 票账本 `decrease(L×P)` + 社区 `Removed +=`；boost 账本 `decrease(B)` + 社区 `Removed +=`。**份额与 boost 余额都不清零** |
| `withdraw` | `:258` | `delete _memberStake[token][memberId]` | `onlyMemberOwner` → `token` → `pair` → `unlockRequestPhase != 0` → 有流动性 → `round > unlock + P` | 先 `_withdrawLiquidity`（扣 W 与总份额）→ 归还 boost 并 `totalBoostShares -=`（`:253-256`）→ 再 delete |
| `mergeStake` | `:556-559`、`:578` | 目标 `+= L`、`+= B`、空目标继承 P；源整体 `delete` | `onlyMemberOwner(source)` → `source != target` → `token` → 目标存在 → 双方均未申请解锁 → 源有流动性 → 源本轮未用质押权 → 非空目标 `P_target >= P_source` | 源票 `decrease(Ls×Ps)`、目标票 `increase(Ls×Pt)`；boost 在成员间搬移（`:584-585`） |

三个关键点：

1. **`unstake` 只写 `unlockRequestPhase`，不碰份额与 P**。因此「已申请解锁、未提取」的成员仍然满足 `_govVotesOf(member) = L × P`，但这个值不再被任何路径二次扣减：`stakeLiquidity` / `stakeBoost` / `mergeStake(源)` 都被 `_checkNoUnstakeRequest` 挡住，`withdraw` 不读它。这是「票已清零、份额仍在」的窗口能被安全表达的原因。
2. **`mergeStake` 的票是「按目标 P 重算」而不是「搬移源票」**：目标增量 `Ls × Pt`，源减量 `Ls × Ps`。`Pt > Ps` 时社区票总量会增加 `Ls × (Pt − Ps)`，这是「承诺更长的等待期换更多票」的直接后果，不是凭空增发（目标的 P 在合并前就存在）。
3. **`withdraw` 的 `delete` 排在两次外部交互之后**（`_push` 归还 boost、`_burnLp` 给双币）。既有审查 `STK-03` 已登记为 CEI 偏离，结论「三条转账路径都无钩子 → 不可达」；本卷复核该结论仍成立，理由见 §3 的 S12。

### 2.3 `_totalStake`：五个字段

| 字段 | 增加 | 减少 | 整体重写 |
| --- | --- | --- | --- |
| `totalLiquidityShares` | `_creditLiquidity:608` | `_withdrawLiquidity:787` | — |
| `lastWithdrawableLp` | `_creditLiquidity:609`（`+= lpMinted`） | `_withdrawLiquidity:786`（`-= lpAmount`） | `_applyReclassification:713`（重分类后的新值） |
| `lastFeeLp` | `_applyReclassification:712` | `_realizeFees:868`（`-= processedFeeLp`） | 同上 |
| `lastSqrtKOfLp` | `_applyReclassification:714`、`_updateSqrtKBaseline:770` | `_updateSqrtKBaseline:766`（置 0） | — |
| `totalBoostShares` | `stakeBoost:157` | `withdraw:255` | — |

`mergeStake` 对五个字段**全部不动**：源的 L/B 加进目标、源的成员记录被删，社区总量守恒。

`_applyReclassification`（`:700-728`）是唯一会「整体重写」三字段的地方：

```solidity
(feeLp, withdrawableLp, sqrtKOfLp) = _previewReclassification(totals, snapshot);
totals.lastFeeLp = feeLp; totals.lastWithdrawableLp = withdrawableLp; totals.lastSqrtKOfLp = sqrtKOfLp;
if (sqrtKOfLp > previousSqrtKOfLp) emit FeeReclassified(...);
```

`_previewReclassification` 在四种情况下原样返回旧三元组（总额为 0、基线为 0、`pairTotalSupply == 0`、√k 未增长，`:684-693`），因此「写回」在无事件时是 no-op，三字段不会漂移。

### 2.4 四个轮次账本 + 两个成员账本：五个写点

| 写点 | 成员票 `_validGovVotesByMember` | 社区票 `Added` | 社区票 `Removed` | 成员 boost | 社区 boost `Added` | 社区 boost `Removed` |
| --- | --- | --- | --- | --- | --- | --- |
| `_creditLiquidity` | `increase(Δ)` | `increase(Δ)` | — | — | — | — |
| `stakeBoost`（提升 P 时） | `increase(L×ΔP)` | `increase(L×ΔP)` | — | `increase(b)` | `increase(b)` | — |
| `stakeBoost`（P 不变） | — | — | — | `increase(b)` | `increase(b)` | — |
| `unstake` | `decrease(L×P)` | — | `increase(L×P)` | `decrease(B)` | — | `increase(B)` |
| `mergeStake` 源 | `decrease(Ls×Ps)` | — | `increase(Ls×Ps)` | `decrease(Bs)` | — | — |
| `mergeStake` 目标 | `increase(Ls×Pt)` | `increase(Ls×Pt)` | — | `increase(Bs)` | — | — |

两条结构恒等式由此成立：

```
totalValidGovVotes(R)   = Added.gov(R)   − Removed.gov(R)    = Σ_m validGovVotes(R, m)
totalValidBoostShares(R)= Added.boost(R) − Removed.boost(R)  = Σ_m validBoostShares(R, m)
```

**为什么 merge 的 boost 不写社区账本**：源减 `Bs`、目标加 `Bs`，社区净额为零；写两笔等额会把 `total = Added − Removed` 抬成两倍。代码 `_moveBoostHistory`（`:581-586`）只动成员账本，与规格 `04-stake.md:274` 一致。这是最容易写错的一处，写法正确。

### 2.5 `_pairAddressByTokenAddress`（`:523-532`）

```solidity
pair = _pairAddressByTokenAddress[token];
if (pair == 0) {
    pair = factory.getPair(token, ILOVE20Token(token).PARENT_TOKEN_ADDRESS());
    if (pair == 0) revert PairMissing(token);
    _pairAddressByTokenAddress[token] = pair;   // 写
}
```

只写一次，写点在一个**非 view** 函数里。`settleFees`、`stakeLiquidity`、`withdraw` 都会顺带触发。`pairAddress()` 是 view，只读缓存，因此首次交互前对外返回 0（`STK-08`）。

### 2.6 `_lastSettlePhase`（`:851`）

唯一写入在 `_realizeFees`，且排在 `_push`/`pair.burn` **之前**：先占住本 Phase 的额度，再执行外部动作。任一步失败整笔回滚，额度不会被白白消耗。

`_settleFees` 的三条早退（加上 `_realizeFees` 内部的一条）保证它只在「真的会烧」时被写：

| 早退 | 位置 | 效果 |
| --- | --- | --- |
| `feeLp < settlementUnit` | `:824-826` | 不写 |
| `_lastSettlePhase == round` | `:827-829` | 不写 |
| `!_canBurn(settlementUnit)` | `:830-832` | 不写 |
| `processedFeeLp == 0`（在 `_realizeFees` 内） | `:846-848` | 不写（`settlementUnit == 0` 且 `pairTotalSupply == 0` 时可达） |

### 2.7 `_totalBurnedToken` / `_totalParentTokenBurned`（`:856`、`:866`）

只在 `_realizeFees` 增加，来源是 `pair.burn` 的**实际返回值**。这两个数与 `lastFeeLp` 的减量不是同一口径：前者是「双币」，后者是「LP」，且父币那半会被换成代币再烧（`:860`）。对账时必须分账本，不能用 `tokenBurned` 反推 `feeLp`。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| S1 | `Σ_m _memberStake[t][m].liquidityShares == _totalStake[t].totalLiquidityShares` | ✅ | 五个写点全部成对增删；merge 源删目标增 |
| S2 | `Σ_m boostShares == totalBoostShares` | ✅ | `stakeBoost` 成对加，`withdraw` 成对减，merge 内部搬移 |
| S3 | `totalValidGovVotes(R) == Σ_m validGovVotes(R,m)` | ✅ | §2.4 的五个写点左表与中两列逐行同额 |
| S4 | `totalValidBoostShares(R) == Σ_m validBoostShares(R,m)` | ✅ | 同上；merge 净额为零 |
| S5 | `validBoostShares(R,m) <= boostShares(m)` | ✅ | 未解锁时相等；`unstake` 把前者清零、后者保留 |
| S6 | `lastFeeLp + lastWithdrawableLp == 合约持有的记账 LP` | ✅（协议内流程） | 加 LP 只经 `pair.mint` 入账，出 LP 只经 `_push(pair, …)` + `burn` / 转给成员；重分类不动 LP。**外部转入 Stake 的 LP 不入账**（`:761-762` 注释），等式对外部捐赠不成立，且不影响任何人可提取量 |
| S7 | 重分类守恒：`ΔlastFeeLp == −ΔlastWithdrawableLp` | ✅ 精确 | `feeLp = lastFeeLp + lastWithdrawableLp − withdrawableLp`（`:696`），两 delta 代数相等，无舍入残差 |
| S8 | `lpAmount <= lastWithdrawableLp` 且 `Σ 已提取 + 剩余 == W` | ✅ | `lpAmount = shares × W / T`，`shares <= T`；减量与份额同一笔 |
| S9 | `round > unlockRequestPhase + promisedWaitingPhases` 才可提取 | ✅ | `:240-242` 与 `canWithdraw:426` 同口径 |
| S10 | 已申请解锁的成员不再影响任何 `Added` | ✅ | 三个入口的 `_checkNoUnstakeRequest` 先于任何账本写入 |
| S11 | 每 token 每 Phase 至多一次实际结算 | ✅ | `_lastSettlePhase` 在外部调用前写 |
| S12 | `withdraw` 的「先付款后删除」不可被重入利用 | ⚠️ 附条件 | `_push` 走 `LOVE20Token`（无钩子）；`pair.burn` 只做转账（无回调）；boost 代币同为主币。三个依赖任一变成可回调资产，`delete` 之前的窗口即可重入 |

S3/S4 的证明是**逐写点**的：每次写成员账本，必然在同一笔里写社区账本的对应侧，且增量表达式相同。这比「事后校验总额」更强：不存在中间态。

## 4. 发现

### STK-07 · `pair.burn` 烧的是 Pair 的全部 LP 余额，不是本次额度

| 字段 | 值 |
| --- | --- |
| 位置 | `:793`（`_push(pair, pair, lpAmount)`）、`:797`（`_push(pair, member, lpAmount)`）、`:853-854`、`:809`（`pairContract.burn(to)`） |
| 级别 | Info |
| 证据 | E1 |

Uniswap V2 的 `burn(to)` 按 `balanceOf[address(this)]`（Pair 自身持有的 LP）决定烧多少，而不是按调用方传入的数量。本合约的用法是「先把 `lpAmount`/`processedFeeLp` 转给 Pair，再调 `burn`」，只有在 `pair.balanceOf(pair) == 0` 时二者才相等。

有人把 LP 直接转给 Pair 时（任何人都能做，也可能是误转）：

| 路径 | 实际烧掉 | 账本减量 | 多出来的部分流向 |
| --- | --- | --- | --- |
| `withdraw` 可烧分支 | `D + lpAmount` | `lpAmount` | 提取者（`_burnLp` 的 `to = msg.sender`） |
| `_realizeFees` | `D + processedFeeLp` | `processedFeeLp` | 被烧（代币直接烧，父币换币后烧） |

事件字段 `withdrawableLpBurned` / `feeLpBurned` 只报本次额度，`tokenBurned` / `totalBurnedToken` 报的是**含 D 的实际产出**，两组数不可互推。

**为什么不升级为风险**：转到 Pair 的 LP 本来就是「任何人调 `pair.burn(自己)` 都能拿走」的公开余额，协议没有额外损失；多出来的部分要么给提取者（本来也拿得到），要么被烧（对通缩有利）。所以只算账本口径问题。若要严格，可改为「转给 Pair 后只烧 `lpAmount`」不可行（`burn` 无参数），替代方案是先读 `pair.balanceOf(pair)` 并在差额不为 0 时跳过或记录。

### STK-08 · `pairAddress` 的惰性缓存让「已登记必有 Pair」在读取面不成立

| 字段 | 值 |
| --- | --- |
| 位置 | `:323-325`（getter）、`:523-532`（写缓存） |
| 级别 | Info |
| 证据 | E1 |

`pairAddress(token)` 返回 `_pairAddressByTokenAddress[token]`，该映射只在首次 `stakeLiquidity` / `settleFees` / `withdraw` 时写入。因此一枚刚发射、还没人质押的代币，`pairAddress` 返回 `0`，而 `Launch` 在发射时**已经**创建了 Pair。`memberStake` / `totalStake` 也直接读这个映射，未命中时提前返回零值（`:379`、`:412-413`），不会回退去问 factory。

对链下：不能把 `pairAddress == 0` 当作「没有 Pair」；对链上：没有影响（真实入口都走 `_pairFor`）。建议把 getter 改成「缓存未命中时读 factory」的 view（会多一次外部调用），或在规格里注明该 getter 是缓存视图。

### STK-09 · `_lastSettlePhase` 用 0 兼作「从未结算」

| 字段 | 值 |
| --- | --- |
| 位置 | `:73`（声明）、`:827`（比较）、`:851`（写） |
| 级别 | Info |
| 证据 | E1 |

`_lastSettlePhase[token]` 的初值 0 同时表示「没有结算过」和「Phase 0 结算过」。当前安全，因为 Phase 0 不可能有手续费 LP（`stakeLiquidity` 在 `round == 0` 直接回滚 `NotAllowedToStakeAtRoundZero`，`:123`、`:472-475`），所以 `feeLp` 恒为 0，`_settleFees` 会在 `:824` 或 `:827` 早退。但这是一个靠外部条件成立的安全边界：若未来允许 Round 0 质押，`_lastSettlePhase == 0` 会让第一次结算被误判为「本 Phase 已结算」而跳过。建议改用 `round + 1` 编码，或加一个 `bool settled`。

### X-01 · 两处地址从别的合约读，接线错配时静默读错

| 字段 | 值 |
| --- | --- |
| 位置 | `Stake:505-512`（`_hasUsedStakeRights`）、`Mint:87`/`:93`（`PHASE_ADDRESS` 派生）、`Mint:90`（`SUBMIT_ADDRESS` 独立入参） |
| 级别 | Info |
| 证据 | E1 |

| 读取点 | 实际来源 | 错配后果 |
| --- | --- | --- |
| `Stake._hasUsedStakeRights` 的第二判 | `ISubmit(IVote(VOTE_ADDRESS).SUBMIT_ADDRESS()).proposalIdBySubmitterId(...)` | 若 `Vote.SUBMIT_ADDRESS` 与前端/其他组件使用的 Submit 不是同一份，则「本轮已推举」判在错误的那本账上：成员可以在另一份 Submit 上推举后直接 `unstake`，同一份质押在本轮既推举又退出 |
| `Mint.PHASE_ADDRESS` | `IVote(VOTE_ADDRESS).PHASE_ADDRESS()` | 若 Vote 的 Phase 与 Stake/Submit 使用的不是同一份，`_isRoundEnded` 按错误的时钟判轮结束 → 要么提前可领（读到更快的时钟），要么永远不可领（读到更慢的时钟） |
| `Mint.SUBMIT_ADDRESS` | `init` 入参，**与 Vote 的入参相互独立** | 两者不同时，`onlyProposalTarget` 去另一份 Submit 里找提案 → 本轮有票但提案不在那份里 → 提案奖励永久不可领（`ProposalNotFound` 回滚） |

`Stake` 通过 `Vote` 间接拿 Submit 是**有意的**（少一个接线点，单一事实源）；代价是把全部正确性压在 `Vote.init` 的那一个参数上，而链上没有任何交叉断言。`Mint` 则同时持有自己的 `SUBMIT_ADDRESS`，与 `Vote` 的可以分叉。

**建议**：在 `21_check.sh` 增加三条只读比对（不改合约）：
1. `Vote.SUBMIT_ADDRESS()` == 部署清单里的 Submit；
2. `Mint.SUBMIT_ADDRESS()` == `Vote.SUBMIT_ADDRESS()`；
3. `Mint.PHASE_ADDRESS()` == `Phase` 地址 == `Vote.PHASE_ADDRESS()`。

### STK-01 复核（High，仍未修复）

既有审查的核心结论在本基线仍成立，且**没有**被 `1266696` 的账本重写削弱：

- `stakeBoost:159-164`：`govVotesAdded = liquidityShares × (P_new − P_old)`，`boostAmount` 只需 `> 0`（1 wei 即可），`P` 可一次拉到 `PROMISED_WAITING_PHASES_MAX`；
- `Submit:79-86`：门槛每次重算 `ceil(totalValidGovVotes × SUBMIT_MIN_RATIO / 1e18)`，分母是**活的**；
- 因此任何已达门槛的成员可以把分母抬到自己之外所有人都够不到的位置，且 `P` 只增不减（`PromisedWaitingPhasesDecreased`），效果**跨轮永久**。

状态视角的修法：`promisedWaitingPhases` 的提升目前立即写进当前轮的 `_validGovVotesByMember`。轮次账本本身支持「按轮记录」，所以可以改成「提升只写下一轮」，让本轮的票权分母在本轮内冻结。这会改变 `Submit` 的读数语义，需要与规格一起改。

### STK-02 / STK-03 / STK-04 / STK-05 复核

| ID | 状态 | 本卷复核点 |
| --- | --- | --- |
| `STK-02` | 仍成立 | `:785-799`：`lpAmount == 0` 时 `lastWithdrawableLp -= 0`、`totalLiquidityShares -= shares`、成员被删，份额对应的 LP 留在池中无人可提 |
| `STK-03` | 附条件成立 | `delete`（`:258`）晚于 `_push`（`:254`）与 `pair.burn`（`:794`）；三条资产路径目前都无回调 |
| `STK-04` | 仍成立（政策） | 「√k 的任何增长都归手续费」由 `_previewReclassification:688-697` 定义，与捐赠/交换无关 |
| `STK-05` | 仍成立 | `W → 0` 时 `feeLp < settlementUnit` 恒成立，结算停摆；有新存入（`W > 0`）后恢复 |

## 5. 已核对为正确的点

- `_creditLiquidity` 的票增量恒非负：`(L+Δ)×P_new − L×P_old >= 0`，因为 `P_new >= P_old` 且 `Δ >= 0`；`RoundHistoryUint256.increase` 不会下溢。
- `unstake` 的 `decrease(L×P)` 之前，成员在本轮必有记录（`stakeLiquidity` 或 `stakeBoost` 已在同一轮或更早轮写入），不会出现「从未有记录却减量」的下溢。
- `_mergeIntoTarget` 先 `delete` 源（`:578`），随后 `mergeStake` 才搬 boost 历史（`:302-304`）；`merged.boostShares` 是删除前抓的局部值，顺序安全。
- `_withdrawLiquidity` 先 `_settleFees` 再算 `lpAmount`，提取者拿到的是**结算后**的 W，不会把「本 Phase 该烧的费」算进自己的份额。
- `_updateSqrtKBaseline` 在每次 LP 增减后都重算，且用 `lastFeeLp + lastWithdrawableLp`（记账量）而不是 `pair.totalSupply()`，使基线不受外部转入影响。
- `_canBurn` 用 `lp × reserve >= pairTotalSupply` 的整数形式判断「两侧都非零」，比 `lp × reserve / totalSupply > 0` 少一次除法且无精度损失。
- `_optimalAmounts` 两个方向都做滑点检查，且检查的是「实际偏离 vs 允许偏离」，不是「比例」。

## 6. 覆盖缺口

- 未在真 V2 Pair 上复测 `STK-07`（LP 被转入 Pair 后的实际燃烧量）；需要 fork 或部署真 Pair。
- 未构造「已申请解锁、未提取」窗口下的 `mergeStake` / `stakeBoost` 负例；结论来自 `_checkNoUnstakeRequest` 的调用点穷举（`:126`、`:146`、`:192`、`:291-292`）。
- `S12` 的可达性依赖三个资产合约都不回调；未审 `LOVE20Token` 之外的 boost 代币（`stakeBoost` 的 `tokenAddress` 就是社区代币本身，不是任意 ERC20）。
