# Mint · 状态变量变更审查

> `core/src/Mint.sol`，557 行，`core@6fdd0f1`。
> Mint 不持资产，但它是**唯一能铸币的调用方**（`LOVE20Token.MINTER`），也是发射次数的唯一生产者。它的九个映射决定了「每轮切多少、谁拿多少、还剩多少」。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `_rewardReserved` | `mapping(address => uint256)` | 每 token **累计预留**（含之后铸/烧的） | `_prepareRewardIfNeeded:130` |
| 2 | `_rewardMinted` | `mapping(address => uint256)` | 每 token 累计已铸 | `mintProposalReward:208`、`_mintGovReward:526` |
| 3 | `_rewardBurned` | `mapping(address => uint256)` | 每 token 累计已取消的预留 | `_burnCancelledPool:165`、`_mintGovReward:528` |
| 4 | `_govReward` | `mapping(address => mapping(uint256 => uint256))` | 每轮治理池（准备时冻结） | `_prepareRewardIfNeeded:145` |
| 5 | `_proposalReward` | 同上 | 每轮 Proposal 池 | `:146` |
| 6 | `_eligibleProposalVoteAmountByRound` | 同上 | 每轮达标提案票数之和（分母） | `:147` |
| 7 | `_isRewardPrepared` | `mapping(address => mapping(uint256 => bool))` | 每轮是否已准备 | `:149` |
| 8 | `_proposalMinted` | `mapping(address => mapping(uint256 => mapping(uint256 => bool)))` | 每提案每次结算一次 | `mintProposalReward:207` |
| 9 | `_govMinted` | 同上 | 每成员每轮一次 | `_mintGovReward:523` |
| 10 | `_launchCredit` | `mapping(address => mapping(uint256 => uint256))` | 成员尚未换成发射次数的额度 | `_updateLaunchCredit:485`、`:495` |
| 11 | `initialized` + 5 地址 + 4 参数 | — | 接线与参数 | `init:85-97` |

`PHASE_ADDRESS` 不是 `init` 入参，而是从 `IVote(voteAddress).PHASE_ADDRESS()` 读来的（`:87`、`:93`）——这是本合约唯一「不通过参数传入的依赖」（`X-01`）。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:72-98`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:82-85` | 判重、`initialized = true` | 先置位 |
| 2 | `:87` | `phaseAddress = IVote(voteAddress).PHASE_ADDRESS()` | **外部调用**，在置位之后；重入 `init` 会被挡 |
| 3 | `:89-97` | 5 地址 + 4 参数 | 无校验；`PHASE_ADDRESS` 若为 0，`_isRoundEnded` 每次调用都会因对零地址 `staticcall` 解码失败而回滚 |

### 2.2 `_prepareRewardIfNeeded`（`:104-161`）：五个映射 + 两个累计账本

| 步 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:105-107` | 已准备 → 直接返回 | **幂等闸门**；返回值不是 bool，靠 `_isRewardPrepared` |
| 2 | `:110-113` | `!_isRoundEnded(round)` → `RoundNotEnded` | `round == 0` 也走这条（`_isRoundEnded` 对 0 返回 false） |
| 3 | `:116` | 读 `totalVoteAmount` | 外部只读 |
| 4 | `:122-124` | 若有票：算 `minVoteAmount` 与 `eligibleVoteAmount` | 遍历 Vote 的本轮提案列表（≤1000） |
| 5 | `:126-128` | `available = rewardAvailable(token)`；`gov = available×GOV`；`prop = available×PROP` | 都是 floor |
| 6 | `:130` | `_rewardReserved += gov + prop` | **全合约唯一增加点** |
| 7 | `:133-138` | `totalVoterBoost == 0` → `_burnCancelledPool(gov − gov/2, BoostPoolCancelled)` | 加速池整池取消 |
| 8 | `:140-142` | `eligibleVoteAmount == 0` → `_burnCancelledPool(prop, ProposalPoolCancelled)` | 提案池整池取消 |
| 9 | `:145-149` | 写四个轮次值 + `_isRewardPrepared = true` | 四个写入在最后，与第 6-8 步同笔 |
| 10 | `:152-160` | `RewardPrepared`（带后置 `rewardReserved`/`rewardBurned`） | — |

`totalVoteAmount == 0` 时跳过第 4-8 步，只写四个「零值 + 已准备」。这是「本轮无票 → 两池为 0」的显式记录，不是「未准备」；之后再调用会直接返回。

### 2.3 `_burnCancelledPool`（`:163-173`）

`amount == 0` 早退（不写、不发事件）；否则 `_rewardBurned += amount` 并发 `RewardBurned`。两个调用点（`:137`、`:141`）都在 `_rewardReserved +=` 之后，因此「先预留再取消」的顺序保证 `reservedAvailable` 不会出现负数。

### 2.4 `mintProposalReward`（`:186-222`）

| 顺序 | 位置 | 动作 | 守卫 |
| --- | --- | --- | --- |
| 1 | `:191` | `onlyProposalTarget(token, proposalId)` | `ISubmit.proposalTarget` 的 `target == msg.sender`；未分配 ID 由 Submit 回滚 |
| 2 | `:192-194` | `recipient != 0` | — |
| 3 | `:196` | `_prepareRewardIfNeeded` | 见 §2.2 |
| 4 | `:198-200` | `_proposalMinted` → `ProposalRewardAlreadyMinted` | 一次 |
| 5 | `:202-205` | 计算 `amount`；`== 0` → `ProposalRewardUnavailable` | **零额不写标记**，可重试 |
| 6 | `:207` | `_proposalMinted = true` | 先置位 |
| 7 | `:208` | `_rewardMinted += amount` | 与置位同笔 |
| 8 | `:210` | `token.mint(recipient, amount)` | 外部调用，在置位之后 |
| 9 | `:213-219` | `ProposalRewardMinted` | — |

### 2.5 `_mintGovReward`（`:500-556`）

| 顺序 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:506-508` | `recipient != 0` | — |
| 2 | `:510` | `_prepareRewardIfNeeded` | — |
| 3 | `:512-514` | `_govMinted` → `MemberRewardAlreadyMinted` | — |
| 4 | `:516` | `(vote, boost, burn) = _govRewardCalculation(...)` | 只读 |
| 5 | `:518-520` | 三项和为 0 → `MemberRewardUnavailable` | **零额不写标记** |
| 6 | `:523` | `_govMinted = true` | 先置位 |
| 7 | `:525-528` | `_rewardMinted += vote+boost`；`_rewardBurned += burn` | 两个累计账本同笔 |
| 8 | `:530-533` | `mintAmount > 0` → `token.mint` + `_updateLaunchCredit` | 外部调用 |
| 9 | `:535-543` | `burnReward > 0` → `RewardBurned(BoostOverflow)` | 纯销毁也走这里 |
| 10 | `:546-553` | `GovRewardMinted` | — |

「纯销毁」路径（`vote + boost == 0`、`burn > 0`）会写 `_govMinted` 与 `_rewardBurned`，但不铸币；这与「三项全 0 回滚、不写标记」是两条不同的规则，代码区分正确（`:518` vs `:535`）。

### 2.6 `_updateLaunchCredit`（`:462-498`）

| 顺序 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:469-473` | `issuedCount >= maxCount` → 返回 | 额度发满后不再累计 credit（避免无界增长） |
| 2 | `:476-479` | `threshold = ceil((MAX_SUPPLY − totalSupplyBeforeMint) × RATIO)` | `totalSupplyBeforeMint = totalSupply() − mintedAmount`，即**本次铸造前**的未铸量 |
| 3 | `:480-482` | `threshold == 0` → 返回 | `RATIO == 0` 或未铸量为 0 时 credit 被丢弃（见 `MNT-05`） |
| 4 | `:485` | `_launchCredit += mintedAmount` | 只加 `vote+boost`，不含 `burnReward` |
| 5 | `:487-491` | `maxNewCount = maxCount − issued`；`count = credit / threshold`；`count > maxNewCount` 则截断 | 截断后余数留在 credit 里 |
| 6 | `:493-497` | `count > 0` → `credit −= count × threshold`；`launch.addLaunchCount(...)` | 外部调用（Launch 只写自己的账本） |

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| M1 | `_rewardReserved >= _rewardMinted + _rewardBurned` | ✅ 逐轮成立 | 见下方证明 |
| M2 | `reservedAvailable = R − M − B` 不会下溢 | ✅ | M1 |
| M3 | `_isRewardPrepared[t][r]` 一旦为 true，`_govReward[t][r]` / `_proposalReward[t][r]` / `_eligible…` 不再变 | ✅ | 四者在同一笔写入，之后唯一入口在第 1 步早退 |
| M4 | `_proposalMinted` / `_govMinted` 一旦为 true，对应额度不再铸 | ✅ | 写标记在 `token.mint` 之前 |
| M5 | 每轮 `minted + burned <= gov + prop` | ✅ | 见下方证明 |
| M6 | `_launchCredit[t][m]` 每次成功调用后 `< threshold`，或 `issued == MAX` | ✅ | `:495` 扣掉 `count × threshold`；只有当 `count` 被 `maxNewCount` 截断时才可能残留 ≥ threshold，此时 `issued` 已达上限 |
| M7 | `issuedLaunchCount[t] <= MAX_LAUNCH_COUNT` | ✅ | `count` 先被 `maxNewCount` 截断，Launch 侧再兜底（`Launch:195`） |

**M1/M5 的证明（按轮）**：

```text
准备：reserved += G + P

治理侧（每成员）：
  voteReward      = floor(votePool × m_i / T)          Σ_i voteReward <= votePool
  theoreticalBoost= floor(boostPool × b_i / B)         Σ_i theoreticalBoost <= boostPool
  boostReward     = min(theoreticalBoost, voteReward × MULT)
  burnReward      = theoreticalBoost − boostReward     >= 0
  => Σ_i (voteReward + boostReward) + Σ_i burnReward
     = Σ_i voteReward + Σ_i theoreticalBoost <= votePool + boostPool = G

提案侧（每提案）：
  amount_p = floor(P × v_p / E)，只对 v_p >= minVote 的提案
  Σ_p v_p = E  =>  Σ_p amount_p <= P
```

因此任意轮次的「已铸 + 已烧」不超过该轮预留；`_rewardReserved` 只增，两个消耗账本只增，M1 对全部轮次求和成立。

**M5 的边界**：`totalVoterBoost == 0` 时加速池在**准备阶段**整池烧掉（`:136`），此时逐成员 `boostReward = burnReward = 0`（`Mint:394-396`），两条路径不重叠也不遗漏。

## 4. 发现

### MNT-06 · 预留额度无到期、无回收；舍入余数是永久保留

| 字段 | 值 |
| --- | --- |
| 位置 | `:130`（唯一增加）、`:145-149`（冻结） |
| 级别 | Info |
| 证据 | E2 |

三个口径需要分清：

| 类别 | 是否回流 `rewardAvailable` | 说明 |
| --- | --- | --- |
| 准备阶段取消的池（`totalVoterBoost == 0` / `eligibleVoteAmount == 0`） | ✅ 回流 | `_rewardBurned` 增加 → `reservedAvailable` 减少 → `available` 增加 |
| 已铸额度 | ➖ 净零 | `_rewardMinted` 增加使 `reservedAvailable` 减少，同时 `totalSupply` 增加同样的量，两项相抵，`available` 不变 |
| **未领取的额度** | ❌ 不回流 | 仍留在 `reservedAvailable`，可**无限期**领取（`mintGovReward` 无截止时间） |
| **逐项取整的余数** | ❌ 不回流 | 规格 `07-mint.md:38` 明确定为「永久保留量」 |

因此 `rewardAvailable` 随轮次单调下降，最终趋近 0；这是「每轮切分」的政策结果，不是泄漏。真正需要关注的是可观测性：`reservedAvailable` 把「已预留未领取」「取整余数」「取消后已回流」三种状态混在一个数里，链下若要用它判断「还有多少可分配」，必须自己按轮重算 `_govReward + _proposalReward − _rewardMinted − _rewardBurned`。建议在文档里明确这条对账路径（不建议为此加存储字段）。

### MNT-07 · 参数域只由部署脚本守（已闭合，记录单点依赖）

| 字段 | 值 |
| --- | --- |
| 位置 | `:94-97`（写入）、`:127-128`（使用）、`:405`（倍数） |
| 级别 | Info |
| 证据 | E2 |

三个参数一旦越界，后果从「治理奖励不可领」到「整池静默归零」不等，且都没有 setter 可修。三者都已在 `DeployCore` 广播前校验：

| 参数 | 越界后果 | 部署期校验 |
| --- | --- | --- |
| `ROUND_REWARD_GOV_RATIO + ROUND_REWARD_PROPOSAL_RATIO > 1e18` | `gov + prop > available` → `reservedAvailable` 超过 `MAX_SUPPLY − totalSupply` → `rewardAvailable` 下溢回滚 → 之后所有有票轮次的准备都失败 | ✅ `DeployCore.s.sol:160-163`（`prop <= 1e18 - gov`） |
| `PROPOSAL_REWARD_MIN_VOTE_RATIO > 1e18` | `minVote > totalVote` → 所有提案都不达标 → 提案池每轮整池取消（静默归零，不回滚） | ✅ `DeployCore.s.sol:158` |
| `MAX_GOV_BOOST_REWARD_MULTIPLIER` 过大 | `voteReward × MULT` 溢出 → `_govRewardCalculation` 回滚 → 治理奖励不可领 | ✅ `DeployCore.s.sol:164-167`（`!= 0 && <= 1000`，最大 1e31，远离 2^256） |

所以这不是一个待修项，而是一条**单点依赖**：三个参数的正确性全部押在 `DeployCore` 的四个 `require` 上，合约侧零校验。任何绕开 `DeployCore` 的部署路径（自写脚本、fork、测试夹具）都会失去这层保护，而错误不可修。若要消除单点，可把「和 ≤ 1e18」与「倍数 ≤ 1000」搬进 `Mint.init`；代价是与仓库「参数域在广播前校验、`init` 只存」的约定冲突。

## 5. 已核对为正确的点

- `_rewardReserved` 只在 `_prepareRewardIfNeeded` 增加一次，且在任何 `_rewardBurned`/`_rewardMinted` 写入之前；不存在「先取消后预留」的负数窗口。
- `_isRewardPrepared` 在四个轮次值写完之后才置位；即使外部调用（本函数只有只读 staticcall）出现重入，也没有「已准备但池值为 0」的中间态。
- `mintProposalReward` / `_mintGovReward` 都是「先置标记、再铸币」，重入同一 `(token, round, id)` 会在标记处回滚。
- 零额结算（`amount == 0` / 三项和为 0）**不写标记**，可以改天重试；这与「一次一份」的语义不冲突。
- `_govRewardCalculation` 的 `boostReward = min(theoretical, voteReward × MULT)` 与 `burnReward = theoretical − boostReward` 恒非负，`boostReward + burnReward == theoretical`，不会出现「既铸又烧同一份」。
- `_updateLaunchCredit` 的 `totalSupplyBeforeMint` 用「当前总量 − 本次铸造量」还原，等价于在 mint 之前读总量；不会把本次铸造算进未铸量。
- 批量 `mintGovRewards` 任一轮失败整批回滚（`MNT-02` 已登记为设计），不会出现「前几轮已铸、后面失败」的半成品。

## 6. 覆盖缺口

- 未构造 `MAX_GOV_BOOST_REWARD_MULTIPLIER` 溢出边界的测试；`MNT-07` 为 E2。
- 未验证「同一轮先 `mintProposalReward` 再 `mintGovReward`」与反序的 `_rewardReserved` 一致性；两者都走同一个幂等准备，结论由 §2.2 的早退保证。
