# LpExecutor · 状态变量变更审查

> `action/src/LpExecutor.sol`，533 行，`action@0c1d1e2`。
> 职责：LP 类行动。三阶段（投票 `p` / 加入 `p-1` / 铸币 `p-2`），没有验证阶段。状态是「按轮聚合余额 + 按轮时间扣减」两套账：余额走 `RoundHistoryUint256`（懒继承），扣减走普通 mapping（只属于发生加入的那一轮）。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `PRECISION` | `uint256 constant = 1e18` | 比例精度 | 编译期 |
| 2 | `PAIR_FACTORY_ADDRESS` | `address immutable` | LP 准入的工厂 | 构造器 `:28` |
| 3 | `_joinTokenAddressByActionId` | `mapping(address => mapping(uint256 => address))` | 行动 → LP 代币 | `onProposalCreated:118` |
| 4 | `_govRatioMultiplierByActionId` | `mapping(address => mapping(uint256 => uint256))` | 治理上限乘数（0 = 关闭） | `:119` |
| 5 | `_minGovRatioByActionId` | `mapping(address => mapping(uint256 => uint256))` | 首次加入门槛 | `:120` |
| 6 | `_createdRoundByActionId` | `mapping(address => mapping(uint256 => uint256))` | 创建轮（0 = 未创建哨兵） | `:121` |
| 7 | `_deductionByMemberId` | `mapping(... => uint256)` | 行动 → 轮 → 成员 → 该轮累计扣减 | `join:170`（`+=`）、`withdraw:216`（`=`）、`_clearJoinState:274`（`delete`） |
| 8 | `_deductionByRound` | `mapping(... => uint256)` | 行动 → 轮 → 全员扣减合计 | `join:171`（`+=`）、`withdraw:217`（`-=`）、`_clearJoinState:273`（`-=`） |
| 9 | `_joinBlocksByMemberId` | `mapping(... => uint256[])` | 行动 → 轮 → 成员 → 每笔加入的区块 | `join:172`（push）、`_clearJoinState:275`（`delete`） |
| 10 | `_joinAmountsByMemberId` | `mapping(... => uint256[])` | 同上，金额 | `join:173`（push）、`_clearJoinState:276`（`delete`） |
| 11 | `_mintedGovRatioByMemberId` | `mapping(... => uint256)` | 铸造时冻结的治理票占比 | `_mintMemberReward:514` |
| 12 | `_joinedAmountByMemberId` | `mapping(... => RoundHistoryUint256.History)` | 成员余额（按轮） | `join:174`（increase）、`withdraw:218`（record）、`_clearJoinState:277`（record 0） |
| 13 | `_joinedAmountByActionId` | `mapping(... => RoundHistoryUint256.History)` | 行动总余额（按轮） | `join:175`（increase）、`withdraw:219`（decrease）、`_clearJoinState:278`（decrease） |
| 14 | `_memberMinted` | `mapping(... => bool)` | 行动 → 轮 → 成员 → 已结算 | `_mintMemberReward:511` |
| 15 | `_mintedRewardByMemberId` | `mapping(... => uint256)` | 已铸数量 | `:512` |
| 16 | `_burnedRewardByMemberId` | `mapping(... => uint256)` | 已销毁数量 | `:513` |

14 本账 + 1 常量 + 1 immutable。三组结构：**配置**（3-6，写一次）、**参与**（7-13，加入/撤回时写）、**结算**（11、14-16，铸币时写）。

## 2. 逐变量变更逻辑

### 2.1 `onProposalCreated`（`:89-130`）——四个配置槽一次性写定

| 顺序 | 位置 | 语句 | 守卫 |
| --- | --- | --- | --- |
| 1 | `:93` | `onlyActionTarget` | `NotActionTarget` |
| 2 | `:94-102` | 项数恰为 4、每项 32 字节 | `TargetDataLengthMismatch` / `InvalidTargetDataShape` |
| 3 | `:108-110` | `lpTokenAddress != 0` | `ZeroJoinTokenAddress` |
| 4 | `:111-113` | `_isRegisteredPair(lp, factory)` | `InvalidJoinTokenFactory` |
| 5 | `:114-116` | `minGovRatio <= 1e18` | `InvalidMinGovRatio` |
| 6 | `:118-121` | 写 4 个槽（含 `createdRound = currentPhase()`） | — |

`govRatioMultiplier` **不设上界**（`:119` 直接写）：任意大值等价于「上限关闭」（见 §2.6 的交叉相乘判定）。`_isRegisteredPair`（`:450-478`）是三重校验：`code.length`、`token0()/token1()` 可调、`factory.getPair(token0, token1) == lp`。这是本合约唯一比 GroupAction 严格的准入点（后者只判 `joinTokenAddress != 0`）。

### 2.2 `join`（`:144-190`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:149` | `nonReentrant onlyMemberOwner(memberId)` | 双门禁 |
| 2 | `:150-152` | `amount == 0` | `ZeroParticipationAmount` |
| 3 | `:154` | `joinRound = currentJoinRound()` | `phase < 2` 时 `RoundNotStarted(1,0)` |
| 4 | `:156` | `isFirstJoin = !IActionTarget.isJoined(...)` | **外部只读**，判据在 ActionTarget |
| 5 | `:157-163` | 首次加入：`_calculateGovRatio(token, currentPhase, memberId) >= minGovRatio` | `InsufficientGovRatio` |
| 6 | `:165-166` | `(startBlock, blocks) = phaseInfo(joinRound + 1)`；`deductionAdded = amount * (block.number - startBlock) / blocks` | `joinRound + 1 == currentPhase` |
| 7 | `:167-169` | `deductionAdded > amount` 时钳到 `amount` | 唯一钳位点 |
| 8 | `:170-171` | 两个扣减槽 `+=` | — |
| 9 | `:172-173` | 两个数组 push（区块、金额） | 只增 |
| 10 | `:174-175` | 两个余额槽 `increase(joinRound, amount)` | RoundHistory |
| 11 | `:177-179` | 首次加入 → `ActionTarget.registerJoinState` | 外部写 |
| 12 | `:181` | `safeTransferFrom(msg.sender, this, amount)` | 在全部状态写之后（CEI ✅） |

第 6 步的 `phaseStartBlock` 来自 `phaseInfo(currentPhase)`，对**当前** Phase 是精确记录值（不是外推），因此 `block.number >= startBlock` 恒成立，`block.number - startBlock` 不会下溢。

### 2.3 `withdraw`（`:193-235`）——两条分支

| 分支 | 位置 | 写入 | 说明 |
| --- | --- | --- | --- |
| 公共前置 | `:203-207` | 读 `memberJoinedAmount = _joinedAmountByMemberId.value(joinRound)` | `amount > 余额` → `WithdrawAmountExceeded` |
| 部分撤回 | `:213-219` | `deductionReduction = floor(memberDeduction * amount / memberJoinedAmount)`；成员扣减 `-= reduction`；`_deductionByRound -= reduction`；余额 `record(round, 余额 - amount)`；总余额 `decrease` | `memberDeduction` 取**当前轮**的扣减 |
| 全额撤回 | `:210-211` | `_clearJoinState(...)` | 见 2.4 |
| 退款 | `:222` | `safeTransfer(msg.sender, amount)` | — |
| 自动退出 | `:226-234` | 若 `余额 - amount == 0` 且 Provider 余额 == 0 → `_clearJoinState` + `ActionTarget.clearJoinState` + `LpExited` | 与全额撤回同一路径 |

**部分撤回的比例分摊只作用于「当前轮」的扣减**。如果成员在第 4 轮加入（扣减 40）、第 5 轮部分撤回，`_deductionByMemberId[5]` 为 0，因此 `reduction = 0`，第 4 轮的扣减与余额**都不动**——第 4 轮的历史权重保持不变。这与规格 `04-lp-executor.md:56`「撤回只更新当前加入 Round，不能改已冻结历史」一致。

### 2.4 `_clearJoinState`（`:266-279`）

| 顺序 | 位置 | 语句 |
| --- | --- | --- |
| 1 | `:273` | `_deductionByRound[round] -= _deductionByMemberId[round][memberId]` |
| 2 | `:274-276` | `delete` 三个槽（成员扣减、两个数组） |
| 3 | `:277` | `_joinedAmountByMemberId.record(round, 0)` |
| 4 | `:278` | `_joinedAmountByActionId.decrease(round, memberJoinedAmount)` |

只清**当前加入轮**：更早轮的 `_deductionByMemberId`、`_deductionByRound`、两个数组全部保留。因此「第 4 轮加入、第 5 轮退出」的成员，第 4 轮的 `deduction(4)` 与 `joinedAmountByMemberId(4)` 仍可读，第 4 轮激励照常计算——这是「退出不追回已发生轮」的实现。

### 2.5 `_mintMemberReward`（`:480-532`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:486-493` | `_checkMintWindow(createdRound, _memberMinted[...])` | 四段守卫 |
| 2 | `:495` | `totalEffectiveAmount = 总余额 - 总扣减` | 为 0 则跳过计算 |
| 3 | `:497-504` | 读 `actionReward`；未铸则 `mintActionReward`（把整笔铸给本合约）；再算 `_calculateReward` | 外部调用 |
| 4 | `:507-509` | `mintAmount == 0 && burnAmount == 0` → revert | `MemberActionRewardUnavailable` |
| 5 | `:511-515` | 写 `_memberMinted` / `_mintedReward` / `_burnedReward` / `_mintedGovRatio` | 四槽同笔 |
| 6 | `:517-519` | `burnAmount != 0` → `ILOVE20Token.burn` | 烧本合约余额 |
| 7 | `:520-522` | `mintAmount != 0` → `safeTransfer(msg.sender, mintAmount)` | — |
| 8 | `:524-531` | `MemberRewardMinted` | — |

第 5 步在两次外部调用（`burn`、`transfer`）**之前**，因此重入即使绕过 `nonReentrant` 也会撞上 `RewardAlreadyMinted`。

### 2.6 `_calculateReward`（`:297-330`）——上限判定的三条分支

| 分支 | 条件 | 结果 |
| --- | --- | --- |
| 关闭上限 | `govRatioMultiplier == 0` | `(theoreticalReward, 0)` |
| 无治理票 | `totalValidGovVotes == 0` | `(0, theoreticalReward)` 全额销毁 |
| 有上限 | 否则 | `cappedRatio = min(effectiveLpRatio, govRatioCap)`；`mint = cappedRatio == effectiveLpRatio ? theoreticalReward : floor(P * cappedRatio / 1e18)`；`burn = theoretical - mint` |

`cappedRatio == effectiveLpRatio` 的短路（`:327-328`）是承重写法：从截断后的 ratio 反算会少 1 个单位，把「零销毁」变成「销毁 1」。`burnAmount = theoreticalReward - mintAmount` 不会下溢，因为 `floor(P * cappedRatio / 1e18) <= floor(P * effectiveLpRatio / 1e18) <= floor(P * effectiveAmount / totalEffectiveAmount)`（E2）。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| L1 | `_deductionByMemberId[round][m] <= _joinedAmountByMemberId.value(round)` | ✅ | 每笔加入的 `deductionAdded <= amount`（`:167` 钳位），部分撤回按比例减少两侧，全额撤回两侧同清 |
| L2 | `_deductionByRound[round] == Σ_m _deductionByMemberId[round][m]` | ✅ | 六个写点成对：join 两侧同加、withdraw 两侧同减、clear 两侧同减（`_clearJoinState:273` 取的就是该成员的全额） |
| L3 | `_joinedAmountByActionId.value(round) == Σ_m _joinedAmountByMemberId.value(round, m)` | ✅ | 所有写点成对（`:174/175`、`:218/219`、`:277/278`） |
| L4 | `_totalEffectiveAmount(round) = 总余额 − 总扣减 >= 0` | ✅ | 由 L1 + L2 推出 |
| L5 | `burnAmount = theoreticalReward − mintAmount >= 0` | ✅ | 见 §2.6 的 E2 推导 |
| L6 | 同一成员同一轮至多结算一次 | ✅ | `_memberMinted` 先于转账写入，且 `_checkMintWindow` 先判 |
| L7 | `_mintedGovRatioByMemberId` 与 `_calculateReward` 用的 ratio 同源 | ✅ | 两处都调 `_calculateGovRatio(token, currentPhase, memberId)`，同一笔同一块 |
| L8 | 所有 RoundHistory 写入轮单调不减 | ✅ | 唯一写入轮是 `currentJoinRound()` = `phase - 1`，单调不减；同轮覆写被 `OrderedHistoryIndex.record` 的等值分支允许 |
| L9 | `Σ mint + Σ burn <= proposalReward` | ✅ | 每个成员 `mint + burn = theoretical = floor(P·eff_i/E)`，Σ ≤ P（向下取整） |

## 4. 发现

### M-LP-01 · 两个加入日志数组只增不减、不随撤回缩放，`deduction()` 会随自增操作无界增长

| 字段 | 值 |
| --- | --- |
| 位置 | `:50-53`、`:172-173`、`:266-279`、`:332-341` |
| 级别 | Info |
| 证据 | E1 |

`_joinBlocksByMemberId` / `_joinAmountsByMemberId` 在每次 `join` 追加一项（`:172-173`），只在**当前轮**全额退出时 `delete`（`:275-276`）。部分撤回明确不缩放（规格 `04:66`「不逐笔缩放」），更早轮的数组永不清理。

后果有三层：

1. **数组之和不再等于余额**。部分撤回后 `Σ _joinAmountsByMemberId = 原余额 > 当前余额`，任何按数组求和的链下核算都会高估。
2. **无上限**。同一成员在同一轮反复 `join`，每笔增加 2 个数组元素（2 次冷写 + 1 次长度更新）。调用者自付，不构成对他人的攻击面。
3. **`deduction()` 的返回体积随上述增长**（`:339-340` 直接回整个数组）。这是唯一读这两个数组的入口，没有分页。

这两个槽的唯一用途是「可复现的时间权重推导」（事件审查 `LPE-EV-1`/`LPE-EV-2` 已指出折叠它们需要重实现库语义）。既然链上没有消费者，`deduction()` 是给链下审计用的；建议在规格里写明「数组是加入流水，不是余额分解」。

### M-LP-02 · 读面把四种「不能结算」压成同一个 `(0, 0, false)`，写面却有四个不同的错误

| 字段 | 值 |
| --- | --- |
| 位置 | `:374-391`（`memberReward`）、`:486-493`（`_checkMintWindow`） |
| 级别 | Info |
| 证据 | E1 |

`memberReward` 对以下四种情形全部返回 `(0, 0, false)`：行动未创建（`createdRound == 0`）、`round < createdRound`、`round > _mintRound()`、轮次有效但无可分配量。而 `mintMemberReward` 分别回滚 `ActionNotCreated` / `RoundBeforeActionCreated` / `RoundAfterMintWindow` / `MemberActionRewardUnavailable`。

链下无法用视图回答「为什么这笔领不了」，只能靠试算 revert。这本身是可接受的取舍（视图不抛错），但 `createdRound == 0` 与「轮次超窗」的返回完全相同，而前者是永久不可结算、后者只是时机未到——两者的运维处置完全相反。

### M-LP-03 · `_totalEffectiveAmount == 0` 与「激励为零」共用 `MemberActionRewardUnavailable`

| 字段 | 值 |
| --- | --- |
| 位置 | `:495-509` |
| 级别 | Info |
| 证据 | E1 |

当 `totalEffectiveAmount == 0`（该轮无人有效参与，或全员扣减等于余额）时，`mintAmount`/`burnAmount` 保持 0，`:507` 回滚 `MemberActionRewardUnavailable`。此时行动激励可能充足、轮次也在窗口内，唯一的问题是分母为零。

规格 `04:90` 已把这个情形与「激励为零」合并为同一个错误（「该轮有效参与总量为零或预期数量为零时，成员结算无产出」），所以这是**规格授权的合并**，不是实现偏离。记录的原因：该错误名会让运维误判为「激励未就绪」，而实际是「这一轮没有有效参与」，两者都不可能通过重试解决。

### M-LP-04 · `_joinBlocksByMemberId` 的区块数与 `deductionAdded` 不是一一对应，`deduction()` 的返回值无法自校验

| 字段 | 值 |
| --- | --- |
| 位置 | `:165-173`、`:332-341` |
| 级别 | Info |
| 证据 | E2 |

`deduction()` 同时返回 `amount`（累计扣减）、`joinBlocks[]`、`joinAmounts[]`。要验证 `amount`，消费方必须对每对 `(block, amount_i)` 重算 `min(amount_i, floor(amount_i * (block_i - phaseStart) / phaseBlocks))` 并求和——而 `phaseStart` / `phaseBlocks` 不在返回值里，必须另行读 `Phase.phaseInfo(joinRound + 1)`。

即：`deduction()` 的三个返回值**不足以自校验**，缺两个外部量。这在事件审查 `LPE-EV-1` 里已从事件侧登记过（`LpJoined` 缺 Phase 段参数），本卷从状态侧确认同一缺口：存储里没有保存 `phaseStartBlock`/`phaseBlocks`，因此扣减量在 Phase 参数被 `sync` 改写后**无法用当前参数重算**（只能靠历史段表）。规格 `04:52` 的「结算读取落账值，不用结算时的 Phase 参数重算」正是为此。

## 5. 已核对为正确的点

- `join` 的全部状态写都在 `safeTransferFrom` 之前（`:170-181` vs `:181`），CEI 成立。
- 部分撤回的比例分摊不会让 `_deductionByRound` 下溢：`memberDeduction <= memberJoinedAmount`（L1），故 `reduction = floor(memberDeduction * amount / memberJoinedAmount) <= amount`，且 `_deductionByRound >= memberDeduction >= reduction`。
- 全额撤回与 `exit` 走同一个 `_clearJoinState`，扣减与余额两侧同清，不会留下「余额 0、扣减非 0」的脏状态。
- `withdraw` 的自动退出判据（`:226`）在退款之后读 Provider 余额，而 `_decreaseOwnAmount` 不触碰 Provider 账本，因此判据不会读到被自己刚改过的值。
- `_mintMemberReward` 的四个结算槽（`_memberMinted` / `_mintedReward` / `_burnedReward` / `_mintedGovRatio`）在同一段内写完，没有「已标记但金额未写」的窗口。
- `_calculateReward` 的短路写法保证「上限不生效时 `mintAmount == theoreticalReward` 精确相等」，不会因为从截断 ratio 反算而凭空产生 1 单位销毁。
- `govRatioMultiplier` 无上界不会导致结算回滚：判定用 `effectiveLpRatio < govRatioCap` 的比较，乘数极大时 cap 极大，走「无上限」分支。
- `join` 的 `phaseInfo(joinRound + 1)` 取的是**当前** Phase 的精确段（不是外推），因此 `block.number - startBlock` 恒非负。
- `PRECISION` 是 `private constant`，与 `GroupActionStorage.PRECISION`、`GroupServiceStorage.PRECISION` 三处独立定义但同为 `1e18`；没有发现某处用了别的值。

## 6. 覆盖缺口

- 未复现「Phase 段长被 `sync` 改写后，历史轮的 `deduction` 是否仍与当时的段参数一致」；按 `Phase` 的段表设计（`_segmentByPhase` 按段起点记录）应当一致，但本卷未逐条验算。
- 未测 `_isRegisteredPair` 对一个「`token0()`/`token1()` 会重入」的恶意 pair 的行为；该函数只在创建回调里调用一次，且失败即整笔回滚。
- 未审 `mintMemberRewards` 批量结算的 gas 上界（见 `02-executor-base.md` 的 `M-EB-03`）。
- 未审 `_calculateReward` 在 `totalValidGovVotes` 于同一笔内变化的可能（`Stake` 的读面在同块内是稳定的，但未逐行复核 `Stake` 是否会在结算路径中被写）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-LP-01` | 规格补写 | [`04-lp-executor.md`](../../docs/specs/action/04-lp-executor.md) 的「状态口径」：两个加入数组是流水不是余额分解，撤回不缩放，累计扣减可无界增长 |
| `M-LP-02` | 规格补写 | 同上：四种不可结算情形在读面压成 `(0, 0, false)`，需要原因只能试算写入口的 revert |
| `M-LP-03` | 口径登记 | 零分母与「激励为零」共用 `MemberActionRewardUnavailable` 已由 04 规格授权，源码不改 |
| `M-LP-04` | 规格补写 | 同上：`deduction()` 不自校验（缺 `phaseStartBlock` / `phaseBlocks`），链下不得用它反推加入流水 |
