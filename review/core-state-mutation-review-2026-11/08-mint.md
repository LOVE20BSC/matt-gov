# Mint · 状态变量变更审查

> `core/src/Mint.sol`，597 行，`core@0466d67`。
> Mint 不持资产，但它是**唯一能铸币的调用方**（`LOVE20Token.MINTER`），也是发射次数的唯一生产者。它的九个映射决定了「每轮切多少、谁拿多少、还剩多少」。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `_totalRewardReserved` | `mapping(address => uint256)` | 每 token **累计预留**（含之后铸/烧的） | `_prepareRewardIfNeeded:134` |
| 2 | `_totalRewardMinted` | `mapping(address => uint256)` | 每 token 累计已铸 | `mintProposalReward:221`、`_mintGovReward:554` |
| 3 | `_totalRewardBurned` | `mapping(address => uint256)` | 每 token 累计已取消或溢出的预留 | `_burnCancelledPool:169`、`_mintGovReward:556` |
| 4 | `_govReward` | `mapping(address => mapping(uint256 => uint256))` | 每轮治理池（准备时冻结） | `_prepareRewardIfNeeded:149` |
| 5 | `_proposalReward` | 同上 | 每轮 Proposal 池 | `:150` |
| 6 | `_eligibleProposalVoteAmountByRound` | 同上 | 每轮达标提案票数之和（分母） | `:151` |
| 7 | `_isRewardPrepared` | `mapping(address => mapping(uint256 => bool))` | 每轮是否已准备 | `:152` |
| 8 | `_proposalMinted` | `mapping(address => mapping(uint256 => mapping(uint256 => bool)))` | 每提案每次结算一次 | `mintProposalReward:220` |
| 9 | `_govMinted` | 同上 | 每成员每轮一次 | `_mintGovReward:551` |
| 10 | `_launchCredit` | `mapping(address => mapping(uint256 => uint256))` | 成员尚未换成发射次数的额度 | `_updateLaunchCredit:507`、`:517` |
| 11 | `initialized` + 5 地址 + 4 参数 | — | 接线与参数 | `init:81-97` |

`PHASE_ADDRESS` 不是 `init` 入参，而是从 `IVote(voteAddress).PHASE_ADDRESS()` 读来的（`:87`、`:93`）——这是本合约唯一「不通过参数传入的依赖」（`X-01`）。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:72-98`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:82-85` | 判重、`initialized = true` | 先置位 |
| 2 | `:87` | `phaseAddress = IVote(voteAddress).PHASE_ADDRESS()` | **外部调用**，在置位之后；重入 `init` 会被挡 |
| 3 | `:89-97` | 5 地址 + 4 参数 | 无校验；`PHASE_ADDRESS` 若为 0，`_isRoundEnded` 每次调用都会因对零地址 `staticcall` 解码失败而回滚 |

### 2.2 `prepareRewardIfNeeded`（`:104-106`）与 `_prepareRewardIfNeeded`（`:108-165`）

`prepareRewardIfNeeded(address,uint256)` 是**无许可**的状态写入入口：任何地址都能在轮次结束后立即准备，把「什么时候准备」从依赖特定领取者的偶然行为变成可立即执行的确定性动作。它与 `mintProposalReward` / `mintGovReward(s)` **共用同一个 internal 实现**，池值口径完全一致，不产生第二套计算。

| 四问 | 答案 |
| --- | --- |
| **谁能写** | **任何人**。`external`、无修饰器，`msg.sender` 不参与任何判定 |
| **校验什么** | `_isRewardPrepared[token][round]` 短路（幂等，直接返回）→ `_isRoundEnded(round)`（`round != 0 && currentPhase() > round`），未结束回滚 `RoundNotEnded(round)` |
| **联动哪些账** | `_totalRewardReserved`（唯一增加点）、`_totalRewardBurned`（加速池/提案池整池取消时增加）、`_govReward`、`_proposalReward`、`_eligibleProposalVoteAmountByRound`、`_isRewardPrepared`（最后置位） |
| **顺序** | 本函数**没有外部写调用、没有回调**；只读 `Vote.totalVoteAmount` / `Vote.totalVoterBoost` / 提案列表。全部写入集中在 `:149-153`，唯一事件 `RewardPrepared`（`:156-164`）；幂等调用不发事件 |

| 步 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:109-111` | 已准备 → 直接返回 | **幂等闸门**；靠 `_isRewardPrepared` 而不是返回值 |
| 2 | `:114-117` | `!_isRoundEnded(round)` → `RoundNotEnded` | `round == 0` 也走这条（`_isRoundEnded` 对 0 返回 false） |
| 3 | `:120` | 读 `totalVoteAmount` | 外部只读 |
| 4 | `:127-128` | 算 `minVoteAmount` 与 `eligibleVoteAmount` | 遍历 Vote 的本轮提案列表（≤1000） |
| 5 | `:130-132` | `available = rewardAvailable(token)`；`gov = available×GOV`；`prop = available×PROP` | 都是 floor；`available` 是准备时的**实时水位** |
| 6 | `:134` | `_totalRewardReserved += gov + prop` | **全合约唯一增加点** |
| 7 | `:137-142` | `totalVoterBoost == 0` → `_burnCancelledPool(gov − gov/2, BoostPoolCancelled)` | 加速池整池取消 |
| 8 | `:144-146` | `eligibleVoteAmount == 0` → `_burnCancelledPool(prop, ProposalPoolCancelled)` | 提案池整池取消 |
| 9 | `:149-152` | 写四个轮次值 + `_isRewardPrepared = true` | 四个写入在最后，与第 6-8 步同笔 |
| 10 | `:156-164` | `RewardPrepared`（带后置 `totalRewardReserved` / `totalRewardBurned`） | — |

`totalVoteAmount == 0` 时跳过第 4-8 步，只写四个「零值 + 已准备」。这是「本轮无票 → 两池为 0」的显式记录，不是「未准备」；之后再调用会直接返回。

### 2.3 `_burnCancelledPool`（`:167-178`）

`amount == 0` 早退（不写、不发事件）；否则 `_totalRewardBurned += amount`（`:169`）并发 `RewardBurned`。两个调用点（`:141`、`:145`）都在 `_totalRewardReserved +=` 之后，因此「先预留再取消」的顺序保证 `reservedAvailable` 不会出现负数。

### 2.4 `mintProposalReward`（`:191-236`）

| 顺序 | 位置 | 动作 | 守卫 |
| --- | --- | --- | --- |
| 1 | `:196` | `onlyProposalTarget(token, proposalId)` | `ISubmit.proposalTarget` 的 `target == msg.sender`；未分配 ID 由 Submit 回滚 |
| 2 | `:197-199` | `recipient != 0` | — |
| 3 | `:201` | `_prepareRewardIfNeeded` | 见 §2.2 |
| 4 | `:203-205` | `_proposalMinted` → `ProposalRewardAlreadyMinted` | 一次 |
| 5 | `:207-218` | 计算 `amount`；`== 0` 按三种原因回滚（低于门槛 / 池空 / 取整为零） | **零额不写标记**，可重试 |
| 6 | `:220-221` | `_proposalMinted = true`；`_totalRewardMinted += amount` | 先置位、同笔累计 |
| 7 | `:223` | `token.mint(recipient, amount)` | 外部调用，在置位之后 |
| 8 | `:226-233` | `ProposalRewardMinted` | — |

### 2.5 `_mintGovReward`（`:522-577`）

| 顺序 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:528-530` | `recipient != 0` | — |
| 2 | `:532` | `_prepareRewardIfNeeded` | — |
| 3 | `:534-536` | `_govMinted` → `MemberRewardAlreadyMinted` | — |
| 4 | `:538` | `(vote, boost, burn) = _govRewardCalculation(...)` | 只读；未准备时按实时水位估（`:393-398`） |
| 5 | `:540-548` | 三项和为 0 按三种原因回滚（未投票 / 池空 / 取整为零） | **零额不写标记** |
| 6 | `:551` | `_govMinted = true` | 先置位 |
| 7 | `:553-556` | `_totalRewardMinted += vote+boost`；`_totalRewardBurned += burn` | 两个累计账本同笔 |
| 8 | `:558-561` | `mintAmount > 0` → `token.mint` + `_updateLaunchCredit` | 外部调用 |
| 9 | `:563-572` | `burnReward > 0` → `RewardBurned(BoostOverflow)` | 纯销毁也走这里 |
| 10 | `:574` | `_emitGovRewardMinted` | — |

「纯销毁」路径（`vote + boost == 0`、`burn > 0`）会写 `_govMinted` 与 `_totalRewardBurned`，但 `_totalRewardMinted` 不动；对账时不能用「minted 增量」判断「本轮已有成员结算」。

### 2.6 `_updateLaunchCredit`（`:485-520`）

| 顺序 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:493-495` | `issuedCount >= maxCount` 早退 | 额度已满，不记 credit |
| 2 | `:498-501` | `totalSupplyBeforeMint = totalSupply − mintedAmount`；`threshold = ceil((MAX_SUPPLY − before) × ratio)` | 用**铸前**总量，避免把自己的这次 mint 计入 |
| 3 | `:502-504` | `threshold == 0` 早退 | 未铸造量为 0 时不发额度 |
| 4 | `:507` | `_launchCredit[token][member] += mintedAmount` | 先记账 |
| 5 | `:509-513` | `count = credit / threshold`，并按 `maxCount − issuedCount` 截断 | 不能越过代币上限 |
| 6 | `:515-519` | `count > 0` → credit 扣减、`launch.addLaunchCount` | 外部调用在扣减之后 |

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| M1 | `_totalRewardReserved[t] == Σ_round(_govReward + _proposalReward)` | ✅ | `:134` 是唯一增加点，且与 `:149-150` 的四个轮次写入同笔 |
| M2 | `_totalRewardReserved >= _totalRewardMinted + _totalRewardBurned` | ✅ | 每次 mint / burn 的额度都来自已预留；差值 = 未领取 + 取整余数 |
| M3 | `rewardAvailable + reservedAvailable == MAX_SUPPLY − totalSupply` | ✅ 定义式 | `rewardAvailable = MAX_SUPPLY − totalSupply − reservedAvailable`（`:474-478`）；`reservedAvailable = reserved − minted − burned`（`:480-482`） |
| M4 | 每 token 每轮至多一次实际准备 | ✅ | `_isRewardPrepared` 在 `:152` 置位；置位前没有任何外部写调用 |
| M5 | 同一提案/成员至多结算一次 | ✅ | `_proposalMinted:220` / `_govMinted:551` 在 `token.mint` 之前置位 |
| M6 | `_launchCredit` 不会让 `issuedLaunchCount` 越过 `MAX_LAUNCH_COUNT` | ✅ | `:509-513` 的截断 + `Launch._addLaunchCount` 自身的上限 |
| M7 | 准备的池值不随后续水位变化 | ✅ | 四个轮次值只在 `:149-152` 写；`_govRewardCalculation` 的实时估算（`:393-398`）只对**未准备**轮生效 |

## 4. 发现

### MNT-06 · 预留额度无到期、无回收

| 字段 | 值 |
| --- | --- |
| 位置 | `:134`（预留）、`:474-478`（`rewardAvailable`） |
| 级别 | Info |
| 证据 | E2 |

`_totalRewardReserved` 只增不减；已预留但无人领取的池子永久占用 `rewardAvailable`，直到有人领取。没有「过期回收」入口，取整余数按规格永久留在池中。效果是**可铸上限被永久锁定一部分**，不涉及任何人的余额；规格 `07-mint.md:99` 已明确接受。

### MNT-07 · 三个参数越界会让激励系统永久不可用

| 字段 | 值 |
| --- | --- |
| 位置 | `:94-97`（`init` 写入）、`:131-132`（使用） |
| 级别 | Info |
| 证据 | E2 |

`ROUND_REWARD_GOV_RATIO + ROUND_REWARD_PROPOSAL_RATIO != 1e18` 时，每轮只切一部分或切超（`Math.mulDiv` 各自 floor，切超会让 `reservedAvailable` 超过剩余额度并让 `rewardAvailable` 下溢）；`MAX_GOV_BOOST_REWARD_MULTIPLIER == 0` 时 boost 全被烧；`PROPOSAL_REWARD_MIN_VOTE_RATIO` 越界会让提案池恒空或恒全额。合约侧零守卫、无 setter。`DeployCore` 在广播前校验，因此这是**记录单点依赖**，不是要改合约。

### MNT-01 · 奖池由首个触发者定 = 机制设计，非缺陷

`prepareRewardIfNeeded` 提供的是「**任何地址都能在轮次结束后立即准备**」的确定性，不是对某个攻击的缓解；正常运转下每轮都有人铸币，准备动作本就发生在轮次一开始，因此不存在「谁先动手谁压低池子」的对抗性窗口。

- 池值口径：`:130-134` 的 `available × ratio` 是准备时的实时快照，`_totalRewardReserved` 只有这一处增加；三个入口（`prepareRewardIfNeeded` / `mintProposalReward` / `mintGovReward(s)`）共用同一 internal 实现，口径一致。
- 边界备注 (a)：若某轮确实无人铸造、直到多轮之后才有人领取或准备，池值按**当时水位**落账。这是可观察的时序属性，不是缺陷。
- 边界备注 (b)：若将来引入「轮内 `rewardAvailable` 会增长」的新资金来源路径，此条需重新评估。

## 5. 已核对为正确的点

- `_prepareRewardIfNeeded` 的四个轮次写入与 `_totalRewardReserved` 同笔，且都在 `_isRewardPrepared` 置位之前；不存在「已准备但池子未落账」的中间态。
- 两个领取入口的「标记置位 → 累计 → `token.mint`」顺序一致，外部调用都在标记之后，重入无法二次领取。
- `_burnCancelledPool` 的 `amount == 0` 早退避免了零额 `RewardBurned`，与 `TOK-03`（代币层无零额守卫）互补。
- `_updateLaunchCredit` 用「铸前总量」算阈值，且先扣 credit 再调 `Launch`，外部调用失败时整笔回滚。
- `mintGovRewards` 循环逐个调用 `_mintGovReward`，单个成员失败会整笔回滚；批量入口没有「部分成功」语义。

## 6. 覆盖缺口

- 未构造 `ROUND_REWARD_GOV_RATIO + ROUND_REWARD_PROPOSAL_RATIO > 1e18` 的越界负例（合约无守卫，部署脚本才是防线）。
- `totalVoteAmount != 0` 且提案数接近 1000 的 gas 上界未实测。
- `MNT-06` 的「永久占用」只做账本推导，未做多年期模拟。

行号基准 `0466d67`。
