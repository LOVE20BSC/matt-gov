# Stake

`Stake` 是唯一托管资产的合约（877 行、14,585 字节）。本轮对它逐函数走完四轮，结论是：**没有可窃取路径**，但有 1 条治理层面的 High。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| STK-01 | **High** | 提交门槛乘的是活分母，1 wei 就能把它抬到别人票权之上，且永久 |
| STK-02 | Low | 份额对应的 LP 取整到 0 时，份额被删而资产留在池里，静默 |
| STK-03 | Info | `withdraw` 违反 CEI，但三条转账路径都无钩子 → 不可达 |
| STK-04 | Info | 「手续费 = 任何 sqrt(k) 增值」是政策而非缺陷；本金在几何价值上严格守恒 |
| STK-05 | Info | `W → 0` 时结算停摆，feeLp 滞留（有新存入即恢复） |
| STK-06 | — | 已排除：零基准分支与 `canWithdraw` 口径差都不可达 |

---

## STK-01 · 提交门槛可被 1 wei 捕获

| 字段 | 值 |
| --- | --- |
| 单元 | B1（`Submit:13-103`）+ S2（`Stake:106-181`） |
| 文件:行 | `Submit:79-81`、`Submit:84-86`、`Stake:154-159`、`Stake:593-597`、`Stake:123-125`、`Stake:143-145` |
| 函数/变量 | `Submit._submitPower`、`Submit._meetsSubmitPower`、`Stake.stakeBoost`、`Stake.promisedWaitingPhases` |
| 类别 | 治理可用性 / 门槛可操纵 |
| 严重度 | **High** |
| 攻击者画像 | 任何持币成员，无需特权，无需大额资金 |
| 前置条件 | ①`PROMISED_WAITING_PHASES_MAX > MIN`；②`SUBMIT_MIN_RATIO < 1e18`；③攻击者在攻击前已达到门槛；④愿意承诺最长锁定期 |
| 触发序列 | ①`token.approve(stake, 1)`；②`stakeBoost(token, 1, MAX, memberId)`；③自己的 `validGovVotes` 变为 `shares × MAX`；④`totalValidGovVotes` 同步抬升；⑤`requiredVotes = ceil(total × ratio)` 超过其他所有成员；⑥`canSubmit(others)` 从此恒 false |
| 影响 | 该社区的**提案通道**被单个成员垄断；其他成员永久失去提交权（投票权不受影响） |
| 设计依据 | 票权 = 份额 × 承诺等待期（`Stake:875`），veToken 式设计。缺陷不在乘数，而在**门槛的分母是实时值**：别人合格之后门槛还能被抬高 |
| 证据等级 | **E3** |
| 证据路径 | `test_submitGateCapturedWithOneWeiOfBoost`（`core/test/audit/AuditPoC.t.sol`） |
| 置信度 | 高（确定性复现，无竞态） |
| 状态 | 已确认待修 |

### 机制

`Submit._submitPower`（`Submit:73-82`）每次调用都重新读三个值：

```solidity
validVotes  = stake.validGovVotes(tokenAddress, round, memberId);   // :79
totalVotes  = stake.totalValidGovVotes(tokenAddress, round);        // :80
requiredVotes = ceil(totalVotes * SUBMIT_MIN_RATIO / 1e18);         // :81
```

`_meetsSubmitPower`（`:84-86`）的判据是 `validVotes >= requiredVotes`，即「你至少占当前总票权的 `ratio`」。问题在于分母 `totalVotes` 的每一项都由成员自己设定：`govVotes = liquidityShares × promisedWaitingPhases`（`Stake:875`），而 `promisedWaitingPhases` 是存钱时自己填的、只增不减的（`Stake:123-125`、`143-145`）。

`stakeBoost` 在 `Stake:154-159` 把**既有全部份额**的乘数从旧值直接拉到新值，只需要 `boostAmount > 0`——1 wei 就够：

```solidity
govVotesAdded = member.liquidityShares * (promisedWaitingPhases - member.promisedWaitingPhases);
```

于是攻击者用 1 wei 换来「自己的票权 × MAX」，同时把分母抬高同样的量。由于 `required = ratio × total`，只要 `ratio < 1`，攻击者始终合格；而其他成员原地不动，相对占比被稀释到 `ratio` 以下。

### 实测（4 人各 1e20 份额、MIN=1、MAX=100、ratio=5%）

| 时点 | 攻击者票权 | 总票权 | 门槛 | m1 | m2 | m3 | m4 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 攻击前 | 1.0e20 | 4.0e20 | 2.0e19 | ✓ | ✓ | ✓ | ✓ |
| 1 wei boost 后 | 1.0e22 | 1.03e22 | 5.15e20 | ✓ | ✗ | ✗ | ✗ |
| 下一轮 | 1.0e22 | 1.03e22 | 5.15e20 | ✓ | ✗ | ✗ | ✗ |

第三行是关键：`RoundHistoryUint256.value` 向后回退取最近一次记录，所以抬升对之后每一轮都生效，**不需要重复支付**。

### 为什么不是「本来就该这样」

「大户说话更算数」是设计意图，这点没问题；有问题的是**门槛在合格之后还能被移动**。两种情形必须区分：

- 若攻击者用**新增资金**抬票权，分母与自身份额同比例增长，其他成员的相对占比不变，门槛效应是「大户更有话语权」——可接受。
- 实际发生的是用 **1 wei + 一个自我承诺** 抬高乘数：分母涨了 25 倍，其他人一分钱没多、一票没多，却从「合格」变成「永久不合格」。

后者的成本与收益完全不对称（1 wei 对永久垄断），且不产生任何新增资金或新增风险承担。

### 破坏的不变量

> 任一成员在轮次开始时满足的提交资格，不应在轮次内（或之后）被其他成员单方面撤销。

`Submit` 没有对分母取快照，`Vote`/`Mint` 也没有——`Stake` 的 `_totalValidGovVotesAdded` 是单调累加的轮次历史，所以分母只会涨。这使得「资格」天然是**可撤回**的。

### 约束与失效边界

| 项 | 内容 |
| --- | --- |
| 参数约束 | `MAX = MIN` 时杠杆消失（`Stake:154` 的 `>` 不成立，`govVotesAdded = 0`）；`ratio = 1e18` 时门槛 = 全员票权，谁都过不去，机制整体失效 |
| 失效边界 | 攻击者必须曾经达到过门槛（≥ `ratio` 的票权）。若社区里已有一个更大份额的成员，攻击者抬到 MAX 后仍可能被对方压过——但对方同样可以再抬，结果是**锁定期军备竞赛**，最终所有成员被迫锁到 MAX 才能保留提交权 |
| 损失承担者 | 票权低于新门槛的全部成员。他们失去的是**提案权**，不是投票权，也不是资产 |

---

## STK-02 · 份额对应 LP 取整到 0 时静默没收

| 字段 | 值 |
| --- | --- |
| 单元 | S7（`Stake:655-773`） |
| 文件:行 | `Stake:744-746`、`Stake:748-758` |
| 函数/变量 | `_withdrawLiquidity` / `lpAmount` |
| 类别 | 取整 / 边界 |
| 严重度 | Low |
| 攻击者画像 | 无需攻击者；受害者是粉尘仓位持有人自己 |
| 前置条件 | `liquidityShares × withdrawableLp < totalLiquidityShares`，即该成员在池中的份额价值不足 1 LP |
| 触发序列 | ①小额质押拿到极少份额；②`unstake`；③等过等待期；④`withdraw`；⑤`lpAmount = 0` → 不转账、不 revert；⑥`totalLiquidityShares -= shares`，份额消失 |
| 影响 | 该成员的份额被删除，对应的 W 留在池中归剩余持有人；损失 ≤ 1 LP 当量 |
| 设计依据 | `_canBurn:804-810` 只为「burn 会 revert」设了兜底，没有为「lpAmount 本身为 0」设兜底 |
| 证据等级 | E3（相邻边界已测，0 值分支为 E1） |
| 证据路径 | `test_zeroValueBurnFallsBackToLpTransfer`（3 LP 的兜底路径）；0 值分支见 `Stake:748` 的 `if (lpAmount > 0)` |
| 置信度 | 高 |
| 状态 | 已确认待修 |

`Stake:748` 的 `if (lpAmount > 0)` 把「份额价值不足 1 LP」和「份额价值足够但 burn 会取整到 0」合并成了同一条静默路径：前者什么也不给，后者给 LP。两者的区别对持有人是实质性的（一个拿回资产，一个拿不回），但代码里没有区分，也不发事件。

`Unstaked`/`StakeWithdrawn` 都会记录 `liquidityShares` 与 `lpBurned`/`lpToMember`，所以链上事后可查；问题在于**当时不 revert**，前端无法阻止用户做这笔亏本操作。

---

## STK-03 · `withdraw` 违反 CEI，但当前不可达

| 字段 | 值 |
| --- | --- |
| 单元 | S3（`Stake:183-311`） |
| 文件:行 | `Stake:239-240`（外部调用）、`Stake:244-245`（第二次外部调用）、`Stake:249`（`delete`） |
| 函数/变量 | `withdraw` → `_withdrawLiquidity` → `pair.burn(to=msg.sender)`、`_push` |
| 类别 | 状态顺序 / 重入 |
| 严重度 | Info |
| 攻击者画像 | 若存在回调，任何持有人 |
| 前置条件 | 社区代币、父币或 LP 三者之一具备转账钩子 |
| 触发序列 | ①`withdraw`；②`pair.burn` 把两种代币转给 `msg.sender`；③父币若有钩子 → 回调；④重入 `withdraw`（记录尚未 `delete`）；⑤重复 `_push(boostShares)` 与 `totalBoostShares -=`；⑥`totalBoostShares` 下溢 revert 或双倍退款成功 |
| 影响 | 若可达：Boost 押金双付 + LP 重复提取 |
| 设计依据 | 计划 §附 A 已指出 `withdraw` 与 `Vote`/`Submit` 相反，是「先调用后落盘」 |
| 证据等级 | E1 |
| 证据路径 | 静态：`Stake:239-249`；不可达论证见下 |
| 置信度 | 高（不可达）；若父币替换为带钩子代币则升为 High |
| 状态 | 已关闭（附条件） |

**为什么现在不可达**：`withdraw` 的三条转账路径分别是

1. `pair.burn(to)` → V2 `_safeTransfer(token0/token1, to)`，被转的是社区代币与父币；
2. `_push(tokenAddress, msg.sender, boostShares)` → 社区代币；
3. `_push(pair, msg.sender, lpAmount)` / `_push(pair, pair, lpAmount)` → LP 本身。

社区代币是本仓 `LOVE20Token`（`ERC20` 直系，无 `_update` 钩子、无 ERC777）；父币只有两种来源——`DeployCore:85` 取 `router.WETH()`（WETH 无钩子）或 `Launch` 创建的 `LOVE20Token`（同上）；LP 是 V2 Pair 的普通 ERC20。三条路径都不产生外部回调，因此 `delete:249` 之前没有任何机会插入代码。

另外，即使父币带钩子，重入也只能 revert：外层已经在 `pair.burn` 内部（pair 有 `lock`），内层任何 `pair.burn` 都会撞上 `UniswapV2: LOCKED`；而内层若走不到 pair（`lpAmount == 0` 或 `feeLp < settlementUnit`），外层此刻还没有做过任何转 boost 的动作，双付仍然不成立。

**结论**：这不是「靠运气安全」，而是「靠代币实现安全」。`Stake` 的 CEI 顺序不构成当前风险，但它是唯一托管资产的函数，一旦父币换成带钩子的资产就会立刻变成可利用——所以记为 Info 而不是「无问题」。

---

## STK-04 · 「手续费 = 任何 sqrt(k) 增值」是政策，本金不受损

| 字段 | 值 |
| --- | --- |
| 单元 | S7（`Stake:655-773`） |
| 文件:行 | `Stake:684-691`、`Stake:782-784`、`Stake:835` |
| 函数/变量 | `_reclassify`、`_settleFees` |
| 类别 | 设计自洽 / 经济 |
| 严重度 | Info |
| 攻击者画像 | 任何人（`settleFees` 无权限） |
| 前置条件 | 池子的 `sqrt(k)` 相对上次基线上升 |
| 触发序列 | ①向 pair 转入代币（或任何 swap）；②`pair.sync()`（或让下一次 mint/burn 捎带）；③`settleFees(token)`；④`_reclassify` 把增值部分从 `lastWithdrawableLp` 移到 `lastFeeLp`；⑤`_realizeFees` 烧掉 0.25% 的 W 当量 |
| 影响 | 可提取基数 W 的**名义**数量下降；但每单位 W 的价值同比例上升，持有人本金在几何价值上不变 |
| 设计依据 | 用 `sqrt(k)` 而不是 `getReserves` 余额差来度量手续费（`Stake:655-669` 只读 `getReserves()`，不读余额） |
| 证据等级 | E3 + 推导 |
| 证据路径 | `test_donationIsReclassifiedAsFee`；守恒证明见下 |
| 置信度 | 高 |
| 状态 | 已关闭（判定为政策） |

### 守恒证明

记 `W = lastWithdrawableLp`、`F = lastFeeLp`、`TS` = pair 总供应、`r` = 储备、`k = r_t·r_p`。基线

```
b = sqrt(k) · (F + W) / TS
```

重分类后（`Stake:689-690`）：

```
W' = W · b0 / b1 ,   F' = F + W − W' ,   b1 > b0
```

定义「几何价值」`V(w, k, TS) = w · sqrt(k) / TS`（LP 的可赎回价值在均衡池里正比于此）。则

```
V(W', k1, TS) = W · (b0/b1) · sqrt(k1)/TS = W · sqrt(k0)/TS = V(W, k0, TS)
```

即**可提取部分的几何价值严格不变**，全部 k 增长都记进了 `F'`，而 `F` 的去向是销毁。所以：

- 捐赠者不能通过「捐赠 + sync」把别人的钱变到自己口袋——他自己的捐赠反而大部分进了待销毁账户；
- 被捐赠的社区持有人本金不受损，受益的是「销毁节奏」；
- `settleFees` 任何人可调 → 销毁的**时点**由第三方决定，销毁的**总量**由 k 决定，与调用者无关。

### 剩下的问题只有可观测性

`_settleFees:782-784` 每次都会把 `lastFeeLp/lastWithdrawableLp/lastSqrtKOfLp` 写回，但只在真正 `_realizeFees` 时才发 `FeesSettled`。**只重分类不销毁**的那一次调用没有任何事件，链下无法从日志重建 W 与 F 的拆分。这一点与 `MNT-04` 是同一类问题，记在那里。

---

## STK-05 · `W → 0` 时结算停摆，feeLp 滞留

| 字段 | 值 |
| --- | --- |
| 单元 | S8（`Stake:775-877`） |
| 文件:行 | `Stake:786-796`、`Stake:804-810` |
| 函数/变量 | `_settleFees` / `settlementUnit` / `_canBurn` |
| 类别 | 可用性 / 账本 |
| 严重度 | Info |
| 攻击者画像 | 无需攻击者；最后一户退出即触发 |
| 前置条件 | 所有持有人提取完毕（`totalLiquidityShares == 0`）而 `lastFeeLp > 0` |
| 触发序列 | ①最后一户 `withdraw`；②`_settleFees` 先跑一次（可能处理一部分）；③`W = 0`；④此后 `settlementUnit = 0`，`_canBurn(0)` 恒 false；⑤剩余 feeLp 永久停在合约里 |
| 影响 | 待销毁的 LP 停在 `Stake`，无人可提取；有新成员存入后自动恢复可结算 |
| 设计依据 | `settlementUnit` 以 W 为分母（`Stake:786`），W = 0 时退化为 0 |
| 证据等级 | E2 |
| 证据路径 | 推导：`Stake:786` + `Stake:809`（`0 * r >= TS` 恒 false，因 `TS > 0`） |
| 置信度 | 高 |
| 状态 | 已关闭 |

这不是资金损失（`feeLp` 本来就属于「该烧掉」的部分），但会让「手续费会被销毁」这句话在社区死掉之后不成立：最后一户退出后，剩余 fee 永远不烧。若协议把「销毁量」当作对外指标，这里会出现一个静默的平台期。

---

## STK-06 · 已排除（零基准分支与 `canWithdraw` 口径差）

两条曾在计划里被标为「重点看」的路径，反例搜索后都不成立。记录在此以免下一轮重复投入。

### 6a · `_creditLiquidity:589-591` 的 `withdrawableLpBefore == 0` 分支

假设：老份额在 W 被打到 0 后仍存在，新存入按 1:1 计份额，于是老份额白吃新存入。

不成立。需要 `W == 0 && S > 0` 同时成立，而：

1. **`W/S` 单调不增（除取整尘埃）**：首存 `W = S = lpMinted`；存入保持比值（`W' / S' = (W+L)/(S(W+L)/W) = W/S`）；提取按 `floor(s·W/S)` 扣减，只会让 W 少减一点，即 `W/S` 至多上升 `1/S` 每笔。重分类只减 W。
2. **`W == 0` 意味着 S == 0**：重分类把 W 压到 0 需要 `W·b0 < b1`，即 `sqrt(k)` 增长超过 `W` 倍；而最后一笔提取（`s == S`）时 `lpAmount = W` 恰好把两者同时清零。

因此该分支只在 `S == 0` 时进入，此时不存在「老份额」。分支的实际作用是防除零。

### 6b · `canWithdraw:416` 与 `withdraw:229` 的口径差

假设：`canWithdraw` 不检查 `liquidityShares != 0`，会对「已解锁但份额为零」的成员返回 true，而 `withdraw` 会 revert，前端因此误判。

不成立。要让 `liquidityShares == 0` 且 `unlockRequestPhase != 0`，必须：

- `unstake` 设置 `unlockRequestPhase`，但它要求 `_checkStakedLiquidity`（`Stake:188`）→ 当时 shares > 0；
- 之后唯一能把 shares 归零的路径是 `withdraw`，而它同时 `delete _memberStake`（`Stake:249`）→ `unlockRequestPhase` 也归零。

没有中间态能让两者分叉。唯一的差别是 `canWithdraw` 不判 `member.unlockRequestPhase` 以外的失效条件（`_checkToken`），但 token 登记不可撤销。
