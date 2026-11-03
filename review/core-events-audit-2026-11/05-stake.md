# Stake 事件赋值与发射审查

- 实现：`core/src/Stake.sol`（911 行，`6fdd0f1`）
- 声明：`core/src/interfaces/IStake.sol`（`IStakeEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/04-stake.md`
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 7（core 内最多） |
| 发射点 | 7 个 emit 语句；一笔交易可发多条（`withdraw`：`FeeReclassified` → `FeesSettled` → `StakeWithdrawn`） |
| P0 / P1 / P2 / P3 | 0 / 0 / 2 / 1 |
| 修复状态 | ST-1 / ST-2 / ST-3 已全部关闭（见 §4） |
| 放行 | 可放行；ST-1 / ST-2 的断言缺口已补齐 |

本合约的事件设计在 core 中最完整：三个聚合量（流动性份额、加速份额、治理票）在**改变它们的每个事件**上都带后置总量；两个 LP 账本（`lastFeeLp` / `lastWithdrawableLp`）同样逐点携带。`StakeWithdrawn` 不带 `totalValidGovVotes` 是**正确**的省略——票权已在 `unstake` 清零，提取不改变它（`04-stake.md:261`）。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 同笔后续 |
| --- | --- | --- | --- | --- |
| `LiquidityStaked` | `tokenAddress`, `round`, `memberId` | `_creditLiquidity:617` | 份额与票权 `:606-611`、基线 `:613` | 无 |
| `BoostStaked` | 同上 | `stakeBoost:173` | 转入 `:153`、余额 `:156-157`、票权 `:159-164`、加速历史 `:166-167` | 无 |
| `Unstaked` | 同上 | `unstake:215` | `unlockRequestPhase:203`、票权扣减 `:204-205`、加速扣减 `:207-210` | 无 |
| `StakeWithdrawn` | 同上 | `withdraw:262` | 结算 `:249`/`:783`、LP 交付 `:253-256`、`delete:258` | 无 |
| `StakesMerged` | `tokenAddress`, `sourceMemberId`, `targetMemberId`（`round` 非 indexed） | `mergeStake:306` | 并入 `:300`、加速历史搬迁 `:302-304` | 无 |
| `FeesSettled` | `tokenAddress`, `round` | `_realizeFees:875` | 销毁与统计 `:853-869` | 无 |
| `FeeReclassified` | `tokenAddress`, `round` | `_applyReclassification:717` | 三个 LP 账本 `:712-714` | 可继续 `FeesSettled` / `LiquidityStaked` |

族归属：`core.stake`（根键 → round → memberId 链（0–2 个）→ 数值）。

## 2. 逐事件赋值链

### 2.1 `LiquidityStaked`

发射位置：`stakeLiquidity:110` → `_addLiquidity:131` → `_creditLiquidity:588`。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `tokenAmount` / `parentTokenAmount` | `added.tokenAmount` / `added.parentTokenAmount` `:621-622`，由 `_optimalAmounts:648-649` 按储备折算后的**实际入池量** | 不是调用方期望值；储备为零时等于期望值 `:737-739` |
| `promisedWaitingPhases` | `member.promisedWaitingPhases` `:623`，在 `:607` 写入后读 | 后置承诺期 |
| `govVotesAdded` | `(member.liquidityShares + liquiditySharesAdded) * promisedWaitingPhases - _govVotesOf(member)` `:603-604`，**写入前**用旧 `member.liquidityShares` 计算 | 本次新增票权；`promisedWaitingPhases` 恒为入参，不存在负增量（`stakeLiquidity:127` 已拒绝降低） |
| `govVotes` | `_govVotesOf(member)` `:625` = `liquidityShares × promisedWaitingPhases`（写入后） | 成员后置票权 |
| `liquiditySharesAdded` | `totalLiquidityShares == 0 \|\| withdrawableLpBefore == 0 ? lpMinted : totalLiquidityShares × lpMinted / withdrawableLpBefore` `:599-601` | 分母取**重分类之后**的 `lastWithdrawableLp`（`_addLiquidity:645-646`），顺序不可交换 |
| `liquidityShares` | `member.liquidityShares`（`:606` 累加后） | 成员后置份额 |
| `totalLiquidityShares` | `totals.totalLiquidityShares`（`:608` 累加后） | 社区后置总量 |
| `totalValidGovVotes` | `_totalValidGovVotesAt(tokenAddress, round)` `:615` = `Added − Removed` | 当轮后置票权总量 |
| `totalWithdrawableLp` | `totals.lastWithdrawableLp`（`:609` 累加后） | 含本次 LP 的可提取账本 |

顺序：`_addLiquidity` 内先 `_applyReclassification:645`（可能发 `FeeReclassified`），再入池、铸 LP `:657`；回到 `_creditLiquidity` 写账本后才 emit。因此 `FeeReclassified` 必然先于 `LiquidityStaked`（`StakeDonation.t.sol:748` 断言）。

### 2.2 `BoostStaked`

发射位置：`stakeBoost:173`。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `boostAmount` | 入参 `boostAmount` `:177` | 本次转入量，同时就是份额增量（1:1） |
| `promisedWaitingPhases` | 入参 `:178` | 后置承诺期（`member.promisedWaitingPhases` 在 `:161` 已同步） |
| `govVotesAdded` | 仅当新承诺期大于旧值时：`member.liquidityShares × (新 − 旧)` `:160`；否则为 0（默认值） | 用**旧**承诺期差乘当前份额 |
| `govVotes` | `_govVotesOf(member)` `:180`（写入后） | 成员后置票权 |
| `boostShares` | `member.boostShares`（`:156` 累加后） | 成员后置**余额**（申请解锁后仍保留，提取才清零） |
| `totalBoostShares` | `totals.totalBoostShares`（`:157` 累加后） | 社区余额合计 |
| `totalValidBoostShares` | `_totalValidBoostSharesAt(tokenAddress, round)` `:169` | 当轮有效合计（申请解锁即减） |
| `totalValidGovVotes` | `_totalValidGovVotesAt(tokenAddress, round)` `:170` | 当轮后置票权总量 |

顺序：`_pull:153`（外部转入）→ 账本写入 → emit。检查—更新—交互顺序与 `04-stake.md` 实现约束一致（校验完成后才发起资产调用）。

### 2.3 `Unstaked`

发射位置：`unstake:215`。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `promisedWaitingPhases` | `member.promisedWaitingPhases` `:219` | 不清零 |
| `govVotes` | 局部 `govVotes = _govVotesOf(member)` `:200`，**先缓存**再在 `:203` 写 `unlockRequestPhase` | 被清零的票权；同时也是 `Removed` 的增量 |
| `liquidityShares` | `member.liquidityShares` `:221` | 成员**仍保留**的份额（提取才清零） |
| `boostShares` | `member.boostShares` `:222` | 仍保留的余额；当轮有效值已归零，由事件名承载 |
| `totalValidBoostShares` | `_totalValidBoostSharesAt` `:212`（`:207-210` 扣减后） | 当轮有效合计 |
| `totalValidGovVotes` | `_totalValidGovVotesAt` `:213`（`:204-205` 扣减后） | 当轮后置总量 |

`round` 同时是本次写入的 `unlockRequestPhase`，不另设字段（`04-stake.md:253`）。`totalLiquidityShares` / `totalBoostShares` 不变，不携带。

### 2.4 `StakeWithdrawn`

发射位置：`withdraw:262`。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `promisedWaitingPhases` | 局部缓存 `:237`（`delete` 之前） | 删除前快照 |
| `liquidityShares` | 局部缓存 `:238` | 删除前快照 |
| `tokenAmountForLiquidity` / `parentTokenAmountForLiquidity` | `_withdrawLiquidity:244-249` → `_burnLp:804` 的 `pair.burn` 返回，按 `token0` 归一 `:810-813` | 不可烧分支下两者均为 0 |
| `boostShares` | 局部缓存 `:239`，`:254` 已转出 | 归还的加速代币量 |
| `withdrawableLpBurned` | `lpAmount`（可烧分支）`:792` | 与 `withdrawableLpToMember` 互斥 |
| `withdrawableLpToMember` | `lpAmount`（不可烧分支）`:796` | 两者之和 = `floor(liquidityShares × lastWithdrawableLp / totalLiquidityShares)` |
| `totalLiquidityShares` | `totals.totalLiquidityShares`（`:787` 扣减后） | 后置总量 |
| `totalBoostShares` | `totals.totalBoostShares`（`:255` 扣减后） | 后置余额合计 |
| `totalWithdrawableLp` | `totals.lastWithdrawableLp`（`:786` 扣减后，`_updateSqrtKBaseline` 不改它） | 后置账本 |

顺序：`_withdrawLiquidity` 内先 `_settleFees:783`（可能发 `FeeReclassified` → `FeesSettled`），再折算、销毁/转出、`delete:258`，最后 emit。`FeesSettled` 必然先于 `StakeWithdrawn`（`Stake.t.sol:2340` 断言）。

`totalValidGovVotes` 不携带：票权已在 `unstake` 清零（`04-stake.md:261`），此处重复属于复述未变化字段。

### 2.5 `StakesMerged`

发射位置：`mergeStake:306`。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `liquiditySharesMerged` / `boostSharesMerged` | `merged.liquidityShares` / `.boostShares`（源侧，`:550-551`，取自 `_mergeIntoTarget` 前的源余额） | 迁出量 |
| `targetGovVotes` | `_govVotesOf(target)` `:572`（并入后） | 目标后置票权 |
| `targetLiquidityShares` / `targetBoostShares` | `target.*` `:573-574`（并入后） | 目标后置余额 |
| `targetPromisedWaitingPhases` | `target.promisedWaitingPhases` `:575`；空目标继承源 `:558-560` | 目标后置承诺期 |
| `prevSourceGovVotes` | `_govVotesOf(source)` `:553`（并入前） | 源**旧值**；融合后源被清空，`prevSourceGovVotes = liquiditySharesMerged × prevSourcePromisedWaitingPhases`（恒等对，已登记） |
| `prevSourcePromisedWaitingPhases` | `source.promisedWaitingPhases` `:552` | 源旧值 |
| `totalValidGovVotes` | `_totalValidGovVotesAt` `:576` | 社区后置票权总量 |

账本写入 `:563-570` 在 `_mergeIntoTarget` 内完成（源减、目标加，社区 `Added/Removed` 同步），加速份额搬迁 `_moveBoostHistory:581-586` 只动成员账本、不动社区净额（净额为零），因此在 `:302-304` 之后 emit。

### 2.6 `FeesSettled`

发射位置：`_realizeFees:875`（入口 `settleFees:100`、`withdraw` 的结算段）。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `feeLpBurned` | 入参 `processedFeeLp` = `settlementUnit = mulDiv(pairTotalSupply, FEE_SETTLEMENT_RATIO, 1e18)` `:823` | 单笔恰一个阈值单位 |
| `tokenBurned` | `totalTokenBurned = tokenBurned + (parentBurned > 0 ? _swapParentTokenForToken(...) : 0)` `:858-861` | 含父币换得的部分 |
| `parentTokenBurned` | `_burnLp` 返回的父币侧 `:854` | 换币**前**数量 |
| `totalBurnedToken` | `_totalBurnedToken[tokenAddress]`（`:866` 累加后） | 社区累计 |
| `totalParentTokenBurned` | `_totalParentTokenBurned[tokenAddress]`（`:856` 累加后） | 社区累计 |
| `totalFeeLp` | `totals.lastFeeLp`（`:868` 扣减后） | 后置费用账本 |

顺序：`_applyReclassification`（可能发 `FeeReclassified`）`→ pair.burn / swap / 子币 burn（发 `TokenBurned`）→ 账本 → emit`。

### 2.7 `FeeReclassified`

发射位置：`_applyReclassification:717`；仅在 `sqrtKOfLp > previousSqrtKOfLp` 时发射（`:716`）。

| 字段 | 赋值来源（源码行） | 时点说明 |
| --- | --- | --- |
| `feeLpAdded` | `feeLp − previousFeeLp` `:720` | 转入手续费账本的 LP |
| `withdrawableLpRemoved` | `previousWithdrawableLp − withdrawableLp` `:721` | 与 `feeLpAdded` 恒等（`totalLp` 守恒，属已登记恒等对） |
| `totalFeeLp` | `totals.lastFeeLp`（`:712` 写入后） | 后置 |
| `totalWithdrawableLp` | `totals.lastWithdrawableLp`（`:713` 写入后） | 后置 |
| `sqrtKOfLp` | 局部 `sqrtKOfLp`（`:714` 写入后） | 重分类时点快照；§6.9 唯一允许的派生缓存例外，同一交易内后续 `_updateSqrtKBaseline` 会再刷新，**不得作为最终值折叠** |
| `pairTotalSupply` | `snapshot.pairTotalSupply` `:725` | Pair ERC-20 `totalSupply()` 的外部标准值，不是派生缓存 |

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 全部以 `tokenAddress` 开头 |
| 族槽位（根键 → round → memberId 链 → 数值） | 通过 | `StakesMerged` 的 `round` 非 indexed 但仍在第二槽位 |
| indexed ≤ 3（§6.3） | 通过 | 五个事件 3 个（`LiquidityStaked`/`BoostStaked`/`Unstaked`/`StakeWithdrawn`/`StakesMerged`）；`FeesSettled` / `FeeReclassified` 2 个 |
| 三聚合量逐点携带后置总量（§3.1） | 通过 | `totalLiquidityShares`（`:628`、`:273`）、`totalBoostShares`（`:182`、`:274`）、`totalValidGovVotes`（`:629`、`:184`、`:224`、`:319`）、`totalValidBoostShares`（`:183`、`:223`） |
| LP 账本逐点携带（§3.1） | 通过 | `lastWithdrawableLp`：`:630`、`:723`、`:275`；`lastFeeLp`：`:722`、`:883` |
| 依赖序（§3.4.5） | 通过 | `FeeReclassified → LiquidityStaked`（`StakeDonation.t.sol:748`）、`FeeReclassified → FeesSettled → StakeWithdrawn`（`:774`、`Stake.t.sol:2340`） |
| 状态写入后 emit（§3.4.3） | 通过 | 见 §1 表 |
| 失败不留日志（§3.5） | 通过 | 滑点、零 LP、等待期不足均 revert；`settleFees` 低于阈值是「无操作返回」而非软失败事件 |
| 恒等对登记（§8.1） | 通过 | `feeLpAdded ≡ withdrawableLpRemoved`、`prevSourceGovVotes ≡ liquiditySharesMerged × prevSourcePromisedWaitingPhases` |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 部分，见 ST-1 / ST-2 / ST-3 | |

## 4. 发现

### [P2] ST-1 `LiquidityStaked` 有 5 个字段未被断言，且两对同类型字段在夹具中不可判别

- 状态：已修复。夹具改 2:1 储备（入池 2000e18 / 1000e18），`LiquidityStaked` 10 个字段全部精确断言并显式断言两笔入池量不等；`BoostStaked` 的 `govVotesAdded` / `govVotes` 改为精确值。
- 证据：`Stake.t.sol:2102-2113` 的 `abi.decode` 只取 `promisedWaitingPhases`、`liquidityShares`、`totalLiquidityShares`、`totalValidGovVotes`、`totalWithdrawableLp`；`tokenAmount`、`parentTokenAmount`、`govVotesAdded`、`govVotes`、`liquiditySharesAdded` 全部被跳过。夹具为 1:1 入池（`1000e18/1000e18`），`tokenAmount == parentTokenAmount`。
- 问题：§8.1 要求「同一事件内两个同类型字段必须由取值可区分的夹具断言」。`tokenAmount` 与 `parentTokenAmount` 是相邻的两个 `uint256`，互换实参后测试仍通过；`govVotesAdded` 与 `govVotes` 同样只被跳过。`BoostStaked` 的票权字段也只做了 `govVotes > govVotesAdded` 的范围断言（`Stake.t.sol:2211`），没有精确值。
- 影响：把 `tokenAmount` 与 `parentTokenAmount` 对调、或把 `govVotes` 赋成 `govVotesAdded`，`LiquidityStaked` 的载荷会错，但全套测试仍绿。链下按事件重建「本次入池双币数量」会直接读到错值。
- 建议：夹具改成非 1:1（例如 `2000e18` 子币 + `1500e18` 父币，让 `_optimalAmounts` 折算后两侧不等），并补齐 5 个字段的精确断言；`BoostStaked` 的 `govVotesAdded` / `govVotes` 改为断言具体数值（现有夹具已能算出）。

### [P2] ST-2 `FeesSettled.parentTokenBurned` 从未做取值断言

- 状态：已修复。夹具改用非对称储备（150000e18 / 100000e18），断言 `parentTokenBurned` 等于按储备与 LP 供应量独立算出的父币侧数额，并断言与 `tokenBurned` 不等——父币侧与换币前子币侧因此也可区分。
- 证据：`Stake.t.sol:2142-2143` 的 `abi.decode` 用空位跳过 `parentTokenBurned`（第 3 个字段），只断言 `feeLpBurned == settlementUnit`、`tokenBurned > 0`、两个累计值与 `totalFeeLp`；`StakeDonation.t.sol` 只断言事件存在。
- 问题：`tokenBurned` 与 `parentTokenBurned` 是同一事件内两个相邻 `uint256`，前者只断 `> 0`、后者完全未断，等于该维度没有取值约束。`parentTokenBurned` 还是 `totalParentTokenBurned` 的唯一来源，二者一起失去锚点。
- 影响：把 `parentTokenBurned` 误赋成 `tokenBurned`（或反之）不会被发现；父币销毁账本与「换币前数量」的语义会静默错位。
- 建议：在 `testSettleFeesEmitsCorrectEvent` 中断言 `parentTokenBurned == 结算前从 Pair 取回的父币量`，并显式断言 `tokenBurned != parentTokenBurned`（当前夹具下两者本就不等，直接可用）。

### [P3] ST-3 `BoostStaked` / `Unstaked` 的测试未断言 `topics[1]`（`tokenAddress`）

- 状态：已修复。两处都补 `topics[1] == childToken` 断言。
- 证据：`Stake.t.sol:2196-2198`（只查 `topics[2]`、`topics[3]`）、`Stake.t.sol:2263-2265`（同）。
- 问题：§8.1 要求断言 indexed 布局的**取值**；根键 `tokenAddress` 是 topic1，未被校验。`LiquidityStaked` / `StakesMerged` / `StakeWithdrawn` 的用例都断言了 topic1，只有这两处漏。
- 影响：根键写错（例如写成 Pair 地址或父币）时这两个事件的测试仍通过。
- 建议：补 `require(logs[i].topics[1] == bytes32(uint256(uint160(address(childToken)))), "event token")`。

## 5. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| 成员份额 / 承诺期 / 解锁申请 | `:156`、`:161`、`:203`、`:606-607`、`:258`（delete） | `BoostStaked` / `Unstaked` / `LiquidityStaked` / `StakeWithdrawn` |
| 社区份额总量 | `:157`、`:255`、`:608`、`:787` | 同上（各改变点均带后置总量） |
| 有效票权 / 有效加速（成员 + 社区 Added/Removed） | `:162-167`、`:204-210`、`:564-570`、`:584-585` | `LiquidityStaked` / `BoostStaked` / `Unstaked` / `StakesMerged`（`totalValid*`） |
| `lastWithdrawableLp` / `lastFeeLp` | `:609`、`:712-713`、`:786`、`:868` | `LiquidityStaked` / `FeeReclassified` / `StakeWithdrawn` / `FeesSettled` |
| `lastSqrtKOfLp` | `:714`、`:766`、`:770`、`:801`、`:869` | 派生缓存（§6.9）：由 Pair `Sync` + `totalLp` 推导；仅 `FeeReclassified.sqrtKOfLp` 作为时点快照携带 |
| `_totalBurnedToken` / `_totalParentTokenBurned` | `:856`、`:866` | `FeesSettled` 两个累计字段 |
| `_pairAddressByTokenAddress` | `:530` | 派生缓存：`factory.getPair(token, parentToken)` 可重建（§6.9「pair 地址」） |
| `_lastSettlePhase` | `:851` | 由 `FeesSettled.round` 的每 token 最大值重建 |
