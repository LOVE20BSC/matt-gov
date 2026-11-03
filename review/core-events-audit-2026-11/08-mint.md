# Mint 事件赋值与发射审查

- 实现：`core/src/Mint.sol`（557 行，`6fdd0f1`）
- 声明：`core/src/interfaces/IMint.sol`（`IMintEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/07-mint.md`
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 4 |
| 发射点 | 5（`RewardBurned` 2 处：准备期取消池、治理结算溢出） |
| P0 / P1 / P2 / P3 | 0 / 0 / 2 / 1 |
| 放行 | 事件契约可放行；2 项 P2 为累计锚点缺口 |

三个累计账本中，`rewardReserved` 只在准备时改变并携带后置值；`rewardMinted` 与 `rewardBurned` 各有多个改变点，但**只有 `RewardPrepared` 携带**，`RewardBurned` 与两个 `Minted` 事件都不携带。这是本合约唯一的系统性缺口。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 同笔顺序 |
| --- | --- | --- | --- | --- |
| `RewardPrepared` | `tokenAddress`, `round` | `_prepareRewardIfNeeded:152` | `_rewardReserved:130`、可选 `RewardBurned`×0–2 `:135-142`、四个轮次字段 `:145-149` | 最后发；`RewardBurned` 必须在前（§8.7） |
| `RewardBurned`（取消池） | `tokenAddress`, `round` | `_burnCancelledPool:167` | `_rewardBurned[token] += amount` `:165` | 先加速池、后 Proposal 池（`07-mint.md:50`） |
| `RewardBurned`（溢出） | 同上 | `_mintGovReward:537` | `_rewardBurned += burnReward` `:528` | 先于 `GovRewardMinted` |
| `GovRewardMinted` | `tokenAddress`, `round`, `memberId` | `_mintGovReward:546` | 状态位 `:523`、`_rewardMinted:526`、销毁 `:528`、铸造 `:531`、发射额度 `:532` | 最后发 |
| `ProposalRewardMinted` | `tokenAddress`, `round`, `proposalId` | `mintProposalReward:213` | 状态位 `:207`、`_rewardMinted:208`、铸造 `:210` | 最后发 |

族归属：`core.round`（根键 → round → 对象 id → 角色 → 数值 → 枚举）。

## 2. 逐事件赋值链

### 2.1 `RewardPrepared`

```
event RewardPrepared(
    address indexed tokenAddress,
    uint256 indexed round,
    uint256 govReward,
    uint256 proposalReward,
    uint256 eligibleProposalVoteAmount,
    uint256 rewardReserved,
    uint256 rewardBurned
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `round` | 入参 `:153-154` | 根键 + 纪元键 |
| `govReward` | `govRewardAmount = mulDiv(available, ROUND_REWARD_GOV_RATIO, 1e18)` `:127`；`totalVoteAmount == 0` 时为 0（`:118` 初始化） | 本轮冻结的治理池 |
| `proposalReward` | `proposalRewardAmount = mulDiv(available, ROUND_REWARD_PROPOSAL_RATIO, 1e18)` `:128`；同上为 0 | 本轮冻结的 Proposal 池 |
| `eligibleProposalVoteAmount` | `_calculateEligibleProposalVoteAmount(token, round, minVoteAmount)` `:124`，只累计「`voteAmount >= minVoteAmount`」的 Proposal 票数 `:288-298`；无票时为 0 | 缓存值，写于 `:147`；此后只读 |
| `rewardReserved` | `_rewardReserved[tokenAddress]`，在 `:130` 累加 `gov + proposal` 之后读 `:158` | **累计后置值**（不是增量） |
| `rewardBurned` | `_rewardBurned[tokenAddress]`，在两处 `_burnCancelledPool` `:137`/`:141` 之后读 `:159` | **累计后置值**；包含本次取消的两个池 |

`available = MAX_SUPPLY − totalSupply − reservedAvailable`（`:126` → `:452-456`），按准备前的供应量计算；`_rewardReserved` 全合约只在此处增加一次 `:130`，与 `07-mint.md:64` 一致。

发射链与顺序：

1. `_isRewardPrepared` 早退 `:105-107`（不重复发事件）；
2. `_isRoundEnded` 校验 `:110-113`；
3. 扫描 Vote 冻结结果、计算两池与达标票数 `:116-124`；
4. `_rewardReserved += gov + proposal` `:130`；
5. `totalVoterBoost == 0` → 取消加速池 `:135-138`（发第 1 条 `RewardBurned`）；
6. `eligibleVoteAmount == 0` → 取消完整 Proposal 池 `:140-142`（发第 2 条）；
7. 写 `_govReward` / `_proposalReward` / `_eligibleProposalVoteAmountByRound` / `_isRewardPrepared` `:145-149`；
8. `emit RewardPrepared` `:152`。

`totalVoteAmount == 0` 时两池为 0、`rewardReserved`/`rewardBurned` 不变，仍然 emit（`isRewardPrepared` 是真实状态迁移），由 `Mint.t.sol:testZeroVotePreparationMustEmitEvent` 断言。

### 2.2 `RewardBurned`

```
event RewardBurned(address indexed tokenAddress, uint256 indexed round, uint256 amount, BurnReason reason);
```

| 发射点 | `amount` 来源 | `reason` | 时点 |
| --- | --- | --- | --- |
| 取消加速池 `:137` | `boostPoolAmount = govRewardAmount − govRewardAmount / 2` `:136` | `BoostPoolCancelled` | `_rewardReserved` 已累加；`_rewardBurned` 在 `:165` 累加后 emit |
| 取消 Proposal 池 `:141` | `proposalRewardAmount` `:141` | `ProposalPoolCancelled` | 同上 |
| 治理溢出 `:537` | `burnReward = theoreticalBoost − boostReward`（`_govRewardCalculation:407`） | `BoostOverflow` | `_rewardBurned` 在 `:528` 累加后 emit；先于 `GovRewardMinted` |

`_burnCancelledPool:163-173` 的守卫：`amount == 0` 直接返回，不写账本、不发事件（`MintCoverage.t.sol:testPrepareSkipsZeroAmountBurnEvents` 断言）。这与治理溢出口径一致（`burnReward > 0` 才发）。

`BoostOverflow` 的 `amount` 与同笔 `GovRewardMinted.burnReward` 同值，属 §3.1 允许的**有意冗余**（前者记全局销毁账本、不带 `memberId`；后者给成员归属），已在 `07-mint.md:184` 登记。

### 2.3 `GovRewardMinted`

```
event GovRewardMinted(
    address indexed tokenAddress,
    uint256 indexed round,
    uint256 indexed memberId,
    uint256 voteReward,
    uint256 boostReward,
    uint256 burnReward
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `voteReward` | `votePoolAmount × memberVoteAmount / totalVoteAmount`，`votePoolAmount = govReward / 2` `:387-391` | 向下取整 |
| `boostReward` | `min(theoreticalBoost, voteReward × MAX_GOV_BOOST_REWARD_MULTIPLIER)` `:403-406`；`totalVoterBoost == 0` 时为 0 | |
| `burnReward` | `theoreticalBoost − boostReward` `:407`；`totalVoterBoost == 0` 时为 0 | 与 `RewardBurned(BoostOverflow).amount` 同值 |

三项来自 `_govRewardCalculation:516`，在写状态**之前**计算；实际铸造量为 `voteReward + boostReward` `:525`。

`voteReward + boostReward == 0 && burnReward > 0` 是可达状态（`govReward` 极小时 `votePoolAmount == 0`，加速上限随之为 0），此时仍发 `RewardBurned` 与 `GovRewardMinted`——「本次一枚未铸、额度全部销毁」只能由该载荷表达（`07-mint.md:184`）。

发射链：状态位 `:523` → `_rewardMinted += mintAmount` `:526` → `_rewardBurned += burnReward` `:528` → `ILOVE20Token.mint`（子事件 `TokenMinted`）`:531` → `_updateLaunchCredit`（子事件 `LaunchCountAdded`，可 0–2 条）`:532` → `emit RewardBurned`（若 `burnReward > 0`）`:537` → `emit GovRewardMinted` `:546`。

依赖序满足 §8.7 的 `TokenMinted`/`LaunchCountAdded` → `GovRewardMinted`，由 `MintEvents.t.sol:testEvent_LaunchCountAddedPrecedesGovRewardMinted` 断言。

### 2.4 `ProposalRewardMinted`

```
event ProposalRewardMinted(
    address indexed tokenAddress,
    uint256 indexed round,
    uint256 indexed proposalId,
    address recipient,
    uint256 amount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `recipient` | 入参 `recipient` `:217` | `:192` 已拒绝零地址；只允许 Proposal 记录的 Target 调用（modifier `:175-184`） |
| `amount` | `_proposalRewardCalculation:202` = `proposalReward × proposalVoteAmount / eligibleVoteAmount` `:340` | `:203-205` 已拒绝 0 |

发射链：`_prepareRewardIfNeeded:196` → 重复保护 `:198-200` → 计算 `:202` → 状态位 `:207` → `_rewardMinted += amount` `:208` → `mint`（`TokenMinted`）`:210` → `emit` `:213`。Mint 只支付、不销毁，所以没有配套 `RewardBurned`（`07-mint.md:147`）。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 四个事件均以 `tokenAddress` 开头 |
| 族槽位（根键 → round → 对象 id → 角色 → 数值 → 枚举） | 通过 | `RewardBurned.reason` 在末尾 |
| indexed ≤ 3（§6.3） | 通过 | 2 / 2 / 3 / 3 |
| 依赖序 `RewardBurned → RewardPrepared`（§8.7） | 通过 | `MintEvents.t.sol:testEvent_RewardBurnedPrecedesRewardPrepared` |
| 依赖序 `LaunchCountAdded → GovRewardMinted`（§8.7） | 通过 | `MintEvents.t.sol:testEvent_LaunchCountAddedPrecedesGovRewardMinted` |
| **累计值锚点（§3.1）** | **不通过** | 见 MI-1 / MI-2 |
| 零额不发事件 | 通过 | `_burnCancelledPool:164`；`MintCoverage.t.sol` 三条用例 |
| 状态写入后 emit（§3.4.3） | 通过 | 见 §1 表 |
| 失败不留日志（§3.5） | 通过 | 已铸造、零额、未结束、非 Target 均 revert |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 部分，见 MI-3 | |

## 4. 发现

### [P2] MI-1 `RewardBurned` 不携带累计 `rewardBurned`

- 证据：`Mint.sol:165` 与 `:528` 两处累加 `_rewardBurned`，两处 emit 都只有 `amount` 与 `reason`；后置总量只在 `RewardPrepared.rewardBurned:159` 出现。
- 问题：§3.1 第 3 条——聚合量被多个事件改变时每个改变点都应携带后置总量；「只在一部分改变点携带属于族内漂移」。当前 `rewardBurned` 的锚点只存在于准备事件，而准备事件恰恰**不是**每次销毁都发生（治理溢出的销毁发生在 `mintGovReward`，不再发 `RewardPrepared`）。
- 影响：`rewardBurned()` 的链下对账必须全量折叠两条 `RewardBurned` 路径；单条 `RewardBurned(BoostOverflow)` 无法就地确认累计值，`reservedAvailable` 的链下校验要跨多笔交易拼装。
- 建议：`RewardBurned` 追加 `rewardBurned`（后置累计），置于 `amount` 之后、`reason` 之前；同步 `07-mint.md` 事件节、ABI 基线与测试。

### [P2] MI-2 `GovRewardMinted` / `ProposalRewardMinted` 不携带累计 `rewardMinted`

- 证据：`_rewardMinted` 在 `:208`（Proposal 结算）与 `:526`（治理结算）累加；两个事件的载荷都没有该值，`rewardMinted` 也没有任何事件携带。
- 问题：`rewardMinted` 是被两个事件类共同改变的聚合量，按 §3.1 每个改变点都该有后置总量；当前完全没有锚点，只能靠 `Σ(voteReward+boostReward) + Σ(amount)` 全量折叠。
- 影响：`rewardReserved >= rewardMinted + rewardBurned` 这条不变量（`07-mint.md:31`）无法用单条事件增量校验；审计时必须在链下重放全部历史。
- 建议：两个 `Minted` 事件各追加 `rewardMinted`（后置累计）。若担心 `MemberRewardMinted` 等共享类已有同名字段的语义冲突，注意这里是 Mint 域的 `rewardMinted`，与行动域的 `mintAmount` 不同层，不构成共享类。

### [P3] MI-3 两个 `Minted` 事件的期望值取自被测算函数本身

- 证据：`MintEvents.t.sol:201` 用 `mint.govRewardByMemberId(...)` 的返回值作为 `GovRewardMinted` 的期望；`MintEvents.t.sol:238` 用 `mint.proposalRewardByProposalId(...)` 作为 `ProposalRewardMinted` 的期望。
- 问题：这两个查询入口与铸造入口共用 `_govRewardCalculation` / `_proposalRewardCalculation`，属自证循环：公式错了两边一起错，`expectEmit` 仍然通过。
- 影响：`voteReward` / `boostReward` / `burnReward` 的**算术**没有被事件测试独立钉住（算术正确性另由 `Mint.t.sol` / `MintIntegration.t.sol` 的余额断言覆盖，故不列为 P2）。
- 建议：在事件用例里用独立算式（`govReward/2 × memberVote / totalVote` 等）算期望值，而不是回调查询接口。

## 5. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_rewardReserved` | `:130`（唯一） | `RewardPrepared.rewardReserved`（后置） |
| `_rewardMinted` | `:208`、`:526` | 仅靠折叠，无锚点（MI-2） |
| `_rewardBurned` | `:165`、`:528` | `RewardPrepared.rewardBurned` 仅在准备时；`RewardBurned` 无累计（MI-1） |
| `_govReward` / `_proposalReward` / `_eligibleProposalVoteAmountByRound` / `_isRewardPrepared` | `:145-149` | `RewardPrepared`（四字段一一对应） |
| `_proposalMinted` / `_govMinted` | `:207`、`:523` | `ProposalRewardMinted` / `GovRewardMinted`（单次性由事件存在性折叠） |
| `_launchCredit` | `:485`、`:495` | 派生缓存（§6.9「Launch credit」）：由治理铸造量与 `threshold` 推导；转换结果由 `Launch.LaunchCountAdded` 承载 |
