# Mint

Mint 准备并结算治理和 Proposal 激励，不读取行动验证结果。部署参数见 [参数表](00-protocol-model.md#部署参数)，通用权限见 [通用规则](01-common-rules.md)。

## 账本与数据来源

| 数据 | 作用域与含义 |
| --- | --- |
| `totalRewardReserved` | 每个 token 的累计预留总额，包含后来铸造或销毁的额度 |
| `totalRewardMinted` | 每个 token 的累计已铸造激励 |
| `totalRewardBurned` | 每个 token 的累计已取消预留额度；不铸造该部分代币 |
| `govReward` / `proposalReward` | 每个 token、Round 准备后冻结的完整治理池 / Proposal 池。**这是取消前的全额，不是可支付额**：加速池或 Proposal 池在准备阶段被取消时，对应额度已计入 `totalRewardBurned`，但这两个 getter 仍返回取消前的值；需要净可领取额的下游必须自行按 `totalVoterBoost == 0` / `eligibleProposalVoteAmount == 0` 扣减 |
| `totalVoteAmount` | Vote 的本轮 `totalVoteAmount(tokenAddress, round)` |
| `voterBoost` | 成员本轮在 Vote 的加速快照，`voterBoost(tokenAddress, round, memberId)` |
| `totalVoterBoost` | 本轮全局加速快照，`totalVoterBoost(tokenAddress, round)` |
| `eligibleProposalVoteAmount` | Mint 准备时按 Vote 冻结结果计算并缓存的本轮所有达标 Proposal 票数之和 |
| `launchCredit` | 每个 token、成员尚未转换为发射次数的治理激励额度，见[发射额度的生成](#发射额度的生成)。累加不单独发事件：`count == 0` 的累加与被 `MAX_LAUNCH_COUNT` 削平后留下的余额只能通过 `launchCredit()` 轮询，链下不要试图仅凭事件重建 |

Proposal 达标条件（链上查询通过 `isProposalIdWithReward(tokenAddress, round, proposalId)`）：

```text
proposalVoteAmount > 0
proposalVoteAmount * 1e18 >= totalVoteAmount * proposalRewardMinVoteRatio
```

`isProposalIdWithReward` 无论已准备或未准备，均读取 Vote 的 `voteAmountByProposalId(tokenAddress, round, proposalId)` 与 `totalVoteAmount(tokenAddress, round)` 实时判定。准备后若 `eligibleProposalVoteAmount == 0` 可快速返回 `false`（全轮无达标 Proposal 的缓存优化）。已铸造不影响返回值（仍返回 `true`）。本入口不做 Proposal 存在性校验；无效 `proposalId` 返回 `false`。

三个奖励比例参数统一 `1e18` 精度，例如门槛 `5e16` 表示 5%。`proposalRewardMinVoteRatio` 允许 `0..1e18`，上界由 DeployCore 广播前校验、21_check 复核；零门槛仍要求 Proposal 有正数票。账本始终满足：

```text
totalRewardReserved >= totalRewardMinted + totalRewardBurned
reservedAvailable = totalRewardReserved - totalRewardMinted - totalRewardBurned
available = MAX_SUPPLY - totalSupply - reservedAvailable
```

`reservedAvailable` 是尚未结算的额度，不能再次分配。三个累计账本与本轮池值不能混用。

`MAX_SUPPLY` 约束的是**任一时刻的在售供应**，不是累计发行量：`LOVE20Token.burn` 无许可，任何人销毁自己的余额都会抬高 `MAX_SUPPLY − totalSupply`，未来轮次据此重新预留；因此 `totalRewardMinted` 可以超过 `MAX_SUPPLY`，把两者直接比较的判断都是错的。

各项向下取整产生的余数是明确的永久保留量：继续计入 `reservedAvailable`，不进入后续轮次池，也不单独铸造或销毁；该保留量属于供应上限内的协议保留额度。

## 准备一次

完整 ABI 见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

准备由两种方式触发：调用无许可入口 `prepareRewardIfNeeded(tokenAddress, round)`，或首次调用治理 / Proposal 铸造入口时由 Mint 内部自动准备。两个路径复用同一实现，池子算法只有一份。`tokenAddress` 与 `round` 是唯一的定位参数，调用者不能指定收款地址、成员或金额，因此该入口符合 [通用规则](01-common-rules.md#无许可入口) 的无许可判据：它只把一个已经成立的轮次状态（轮次结束）推进为「池子已冻结」。此前定池只能由领取者触发；补上该入口后，任何地址都可以在第一个领取者之前中立地定池。池值仍按准备时点的 `rewardAvailable` 计算，首次准备的时点仍决定池子大小，但已不再只由领取权持有人掌握。同一 `(tokenAddress, round)` 幂等，重复调用直接返回；未结束的 Round 拒绝准备。

池值不只依赖「第 R 轮的准备时点」，还依赖**跨轮准备顺序**：`available` 扣除的是累计 `reservedAvailable`，而任意已结束轮次都可准备，所以先准备的轮次拿走 `ratio × available`、后准备的轮次只能在更小的基数上取同比例，第 R 轮与第 R+1 轮的相对份额由两次准备的先后决定。诚实路径上这不构成博弈——早准备让池子更大，对全轮次受益人都占优，任何人都能一次调用完成；只有在全员整整一个 Phase 都不准备的前提下顺序才被推迟，因此按「无许可入口 + 早准备占优」接受，不做跨轮强制排序。

1. 本轮已准备则直接返回，不更新状态，也不发事件。未准备时先判 `tokenAddress` 是否由 Launch 登记，未登记回滚 `TokenNotRegistered(tokenAddress)`（与 Stake 的写入口同口径，否则任何人可对任意地址写满四个轮次映射；该门禁早于 Round 结束判定，由 Mint 本地 `IMintErrors` 声明，selector 与 `ILaunch` 的同名错误一致）；再判 Round 已结束（`round != 0 && Phase.currentPhase() > round`，回滚 `RoundNotEnded(round)`；与 `Vote.isRoundEnded` 语义一致，`round == 0` 一律拒绝）。
2. 读取 Vote 的冻结结果。若 `totalVoteAmount == 0`，两池和 `eligibleProposalVoteAmount` 记为 0 并标记已准备，累计账本不变。
3. 否则遍历 Vote 本轮有票 Proposal，按冻结 `totalVoteAmount` 判断每个 Proposal 是否达到阈值，并把达标 Proposal 的票数总和写入 `_eligibleProposalVoteAmountByRound[tokenAddress][round]`。
4. 用准备前的 `available` 计算两池，并在本步骤唯一一次增加 `totalRewardReserved`。
5. 若 `totalVoterBoost == 0`，准备时直接取消加速池；若缓存的 `eligibleProposalVoteAmount == 0`，准备时直接取消完整 Proposal 池。两个条件可同时成立，此时按顺序发射两条 `RewardBurned` 事件（先加速池、后 Proposal 池）。
6. 保存轮次池值、达标票数和已准备状态，不逐个预写 Proposal 额度。后续 Proposal 结算只读取缓存，不再扫描 Vote 列表。

```text
govReward = floor(available * roundRewardGovRatio / 1e18)
proposalReward = floor(available * roundRewardProposalRatio / 1e18)
totalRewardReserved += govReward + proposalReward

if totalVoterBoost == 0:
    totalRewardBurned += govReward - floor(govReward / 2)  // 加速池
if eligibleProposalVoteAmount == 0:
    totalRewardBurned += proposalReward
```

这是每轮唯一增加 `totalRewardReserved` 的位置。后续治理结算按 `voteReward + boostReward` 增加 `totalRewardMinted`；Proposal 结算按实际铸造量增加 `totalRewardMinted`。准备阶段已经取消的额度不得再次销毁；任何失败均整体回滚。**Mint 侧不再有加速激励输出上限，也没有 `burnReward`**：加速池按理论份额全额铸造，超出部分既不截断也不销毁。

例（最小单位）：两池为 5 和 3，且 `totalVoterBoost = eligibleProposalVoteAmount = 0`。准备增加预留 8、销毁 6，留下投票激励 2；再次准备不变。

## Proposal 结算

入口为 `mintProposalReward(tokenAddress, round, proposalId, recipient)`：每个 token、Round、Proposal 只能结算一次，代币铸给被授权的 Target 指定的 `recipient`。**Mint 只支付，不销毁**。

只允许该 Proposal 已记录的 Target 调用，每个 token、Round、Proposal 只能结算一次；未结束、Proposal 不达标或该轮 `proposalReward` 为零时拒绝。若该 Round 尚未准备，入口先自动准备。

领取权只由「票数达标 + 是 target」两点决定，与提案是否被执行无关：`NoCallback` 的 target 可为 EOA，协议不校验它与提案主题相关，也不读取任何执行状态。投票者投的是内容，收款的是 target，两者之间没有链上约束。

校验顺序：

| 条件 | 回滚 |
| --- | --- |
| 读取 `(target, targetMode) = ISubmit(SUBMIT_ADDRESS).proposalTarget(tokenAddress, proposalId)`；`msg.sender != target` | `NotProposalTarget(msg.sender, target)` |
| `recipient == address(0)` | `ZeroRecipientAddress()` |
| `!IVote(VOTE_ADDRESS).isRoundEnded(round)` | `RoundNotEnded(round)` |
| 已结算（独立状态位） | `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)` |
| 票数低于门槛：`voteAmount < minVoteAmount`（门槛大于 0 时含本提案零票） | `ProposalBelowThreshold(tokenAddress, round, proposalId, voteAmount, minVoteAmount)` |
| 整轮池值为零：`proposalReward == 0`（整轮零票，或可用额度按比例取整为 0） | `ProposalPoolEmpty(tokenAddress, round)` |
| 门槛通过且池值非零，但按比例取整为 0 | `ProposalRewardRoundedToZero(tokenAddress, round, proposalId)` |

通过后写状态并铸造：

```text
实际结算量 = floor(proposalReward * proposalVoteAmount / eligibleProposalVoteAmount)
```

结算量为 0 时按「单提案 → 整轮 → 取整」逐层定位：

1. **单提案**：`voteAmount < minVoteAmount` 回 `ProposalBelowThreshold`，两个条件值都写进载荷，调用方据此区分“有票但不够”与“一票没拿到”。零票只在门槛大于 0、且本轮另有提案拿到票时才落到这一层；整轮零票时 `minVoteAmount` 也是 `0`，`0 < 0` 不成立，进入下一层。
2. **整轮**：`proposalReward == 0` 回 `ProposalPoolEmpty`——该轮没有任何可支付的 Proposal 激励，调用方对该轮全部 Proposal 一并无从结算、处置相同，因此“整轮零票”与“可用额度按比例取整为 0”共用同一个错误而不按来源拆分。判据只有池值一项：整轮零票时准备阶段直接跳过预留，池值必为 `0`；整轮有票但无提案达标时池值是非零值，而该轮任一提案都已被上一层拦下，走不到这里。
3. **取整**：门槛通过、池值非零，但 `floor(proposalReward * proposalVoteAmount / eligibleProposalVoteAmount) == 0` 时回 `ProposalRewardRoundedToZero`。`PROPOSAL_REWARD_MIN_VOTE_RATIO` 配成 `0` 时门槛关闭，零票提案也落到这一层——此时“取整为 0”与“没有票”在算术上是同一件事，不为它另设错误。

先具体后整轮：同一 Proposal 同时满足两组条件时报门槛，否则调用方会被轮级错误引去查整轮，而实际该提案本身就不够票。必须在除法前判零，否则会 panic。

代币铸给 `recipient`，`totalRewardMinted` 按实际铸造量累计，并以 `ProposalRewardMinted` 留痕；此后该 Proposal 一律回滚 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`。`recipient` 由被授权的 Target 指定，因此行动类 Target 可以直接让 Mint 铸给绑定的 Executor，不必先铸给自己再转一次；行动侧见 [行动铸造链路](../action/07-minting.md#铸造链路)。某个行动的激励无法分配时不在这里作废：全链路没有销毁路径，该笔激励永久停留在未结算状态、预留不释放（详见下段）。无合格 Proposal 的完整池已在准备时取消，不能再次销毁。

## 治理结算

只允许成员 NFT 当前持有人为本轮实际投过票的 `memberId` 结算；若该 Round 尚未准备，入口先自动准备。自动准备的第一步是登记门禁，因此未由 Launch 登记的 `tokenAddress` 先回 `TokenNotRegistered(tokenAddress)`，早于 `RoundNotEnded(round)`；已准备轮次不再重复该判定。

校验顺序：

| 条件 | 回滚 |
| --- | --- |
| `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `NotMemberOwner(uint256 memberId)` |
| `recipient == address(0)` | `ZeroRecipientAddress()` |
| `tokenAddress` 未由 Launch 登记（未准备轮次的自动准备门禁） | `TokenNotRegistered(address tokenAddress)` |
| `!IVote(VOTE_ADDRESS).isRoundEnded(round)` | `RoundNotEnded(round)` |
| 已铸造（独立状态位） | `MemberRewardAlreadyMinted(tokenAddress, round, memberId)` |
| `memberVoteAmount == 0` | `MemberHasNoVote(tokenAddress, round, memberId)` |
| `govReward == 0` | `MemberRewardPoolEmpty(tokenAddress, round)` |
| 两项和 == 0（已投票且池非零） | `MemberRewardRoundedToZero(tokenAddress, round, memberId)` |

通过后写状态、铸造、发射额度、发射事件。代币铸给 `recipient`（必须非零；鉴权不变，仍是 `ownerOf(memberId) == msg.sender`，由当前 NFT 持有人指定收款地址）。使用以下公式，金额除法向下取整：

```text
votePoolAmount = floor(govReward / 2)
boostPoolAmount = govReward - votePoolAmount
voteReward = floor(votePoolAmount * memberVoteAmount / totalVoteAmount)

if totalVoterBoost == 0:
    boostReward = 0
else:
    boostReward = floor(boostPoolAmount * voterBoost / totalVoterBoost)
```

`memberVoteAmount` 为本轮累计投出票数；`voterBoost` 和 `totalVoterBoost` 均取 Vote 的同轮冻结快照，记账时机见 [Vote](06-vote.md#投票和加速快照)。投票后仅追加质押、不再投票，不增加本轮加速权重；NFT 转移不重算快照。两池按固定 50/50 拆分，奇数余量归加速池。`totalVoterBoost == 0` 时整份加速池已在准备时取消，本次不得再计加速额。未投票者即使有加速质押也不能领取治理激励。

批量接口 `mintGovRewards` 先鉴权，再逐轮按上述顺序执行：每轮都先经过与 `mintGovReward` 相同的 `ZeroRecipientAddress`、自动准备门禁（`TokenNotRegistered` → `RoundNotEnded`）与结算校验；任一轮失败整笔回滚。空 `rounds` 数组在鉴权通过后允许（返回空数组，无副作用）。轮次数量由调用者自行决定，接口不设数量上限；数量过大导致交易失败及 gas 成本由调用者承担，这是写入批量长度上限规则的明确例外。

### 反资本约束的落点

取消输出上限后，`加速激励 ≤ 投票激励 × M` **不再是协议保证**，改由 [Stake 的质押入口](04-stake.md#加速激励质押上限)限量。两者的区别必须写清：

设某成员 `v_i` 票、社区总票 `V`、其加速份额 `b_i`、社区总加速份额 `B`，两池各半（`B_pool = V_pool = govReward / 2`），则

```text
V_i = V_pool × v_i / V
B_i = B_pool × b_i / B
B_i / V_i = (b_i / v_i) × (V / B)
```

入口上限为 `b_i ≤ C × (v_i / V) × M`，即 `b_i ≤ C × s_i × M`（`s_i = v_i / V`）。社区层面没有聚合上限，`B = Σ b_j` 只能由各单人上限求和约束：

```text
B ≤ Σ C × s_j × M = C × M
B_i / V_i = (b_i / v_i) × (V / B) = b_i / (s_i × B) ≤ C × M / B
```

另一个与上限无关的恒等约束来自 `B ≥ b_i`：

```text
B_i / V_i = (b_i / B) × (V / v_i) ≤ V / v_i = 1 / s_i
```

因此在入口限量下，回报比的实际上界是两者取小：

```text
B_i / V_i ≤ min(C × M / B, 1 / s_i)
```

当该成员打满自己的额度且是唯一加速者（`B = b_i = C × s_i × M`）时，两式相等，回报比为 `1 / s_i`。**反例**：`M = 5`、`s_i = 10%`、唯一加速者，`B_i / V_i = 10 > 5`。当所有成员都打满额度（`B = C × M`）时，`C × M / B = 1`：加速池按额度分配给所有人，回报比收敛到 `1`，而不是 `M`——`M` 是单人本金额度倍数，不是收益率倍数。

取消聚合上限后的边界必须写清：

1. **社区加速本金不再有 `C` 的硬上限。** 理论上限是 `Σ m_i = C × M`，但这是各人 allowance 之和，不是预分配额度；实际总量取决于多少人存入、存入多少。早期成员占满自己的额度不会挡住后来者，后来者始终按自己的票占比重算额度，不存在排队。
2. **反资本约束靠「本金与票权成正比」而不是「总量封顶」。** 单人最多锁定 `C × s_i × M`，其中 `C` 只由真实流动性本金与已铸造比例决定，`s_i` 只能由质押份额 × 承诺期获得。纯资本要提高绝对本金，必须先提高 `C`（更多真实流动性本金）或提高 `s_i`（更多票权），两者都不能靠瞬时买入绕过承诺期。
3. **规模与回报比不可兼得。** 回报比上限 `min(C × M / B, 1 / s_i)` 随 `s_i` 增大而下降：票占比越高，能拿到的相对倍数越低；`s_i = 100%` 时上界为 `1`。要高倍数，只能做小票占比下的少数加速者，此时绝对本金 `C × s_i × M` 也很小。这是取消聚合上限后仍然成立的唯一硬性质。
4. **参与填满程度决定实际回报。** `B` 越接近 `C × M`，`C × M / B` 越接近 `1`，全员参与的加速收益与投票收益趋同；`B` 越接近单个成员的本金，该成员的回报比越高。协议不承诺某个回报比，只保证本金上限与上述恒等上界。

协议保证的是：

```text
b_i ≤ C × (v_i / V) × M        单人本金上限（唯一入口约束）
C ∝ T × (totalSupply / MAX_SUPPLY)
B_i / V_i ≤ min(C × M / B, 1 / s_i)
```

每轮实际回报仍按冻结的 `voterBoost / totalVoterBoost` 分配，因此加速参与越集中，单人回报比越高；这是「用本金约束参与资格」而非「用回报比约束结果」的直接后果，白皮书与前端不得再宣称后者，也不得宣称存在社区总量上限。

例：两池各 500、成员投票占 10%、加速份额占 50%。结果 `voteReward = 50`、`boostReward = 250`，实际铸造 300；不再有 `burnReward`。

## 单轮与批量接口

单轮、批量、查询和激励参数接口均见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

`proposalRewardByProposalId` 和 `govRewardByMemberId` 两个查询函数无论轮次是否已准备均能返回金额：

- **已准备**：读取准备时冻结的 `govReward`、`proposalReward` 和 `eligibleProposalVoteAmount`，按缓存值计算。
- **未准备**：实时读取 `rewardAvailable` 计算轮次池，扫描 Vote 冻结结果计算 `eligibleProposalVoteAmount`，按当前状态计算。**警告**：未准备查询需要扫描本轮所有有票 Proposal（O(N) 复杂度，N 为 Proposal 数量）；调用方应优先读取已准备 Round，或在前端/链下环境使用，避免对未准备轮次批量查询。**未准备时返回的是按当前状态计算的投影值，实际金额以铸造入口自动准备时冻结的池值为准。**

两个查询函数均先校验存在性（`proposalRewardByProposalId` 调用 `Submit.proposalTarget`、`govRewardByMemberId` 调用 `MemberNFT.ownerOf`），后计算金额；不存在的 Proposal/成员回滚。未达标 Proposal 或未投票成员返回零金额；已铸造不影响金额，`minted` 返回 `true` 并仍返回原金额。

未准备查询返回的金额是按**当前状态计算的投影值**，实际结算金额以准备时冻结的池值为准。查询与结算之间若有新铸造消耗供应量上限，查询投影可能高于最终准备结果；若有准备其他轮次预留池值，查询投影可能低于最终结果。

`mintGovReward` 与 `mintProposalReward` 在结算量为 0 时拒绝，两侧都按“具体对象 → 整轮 → 取整为零”的顺序：治理侧「未投票 / 池为空 / 取整为零」分别回 `MemberHasNoVote`、`MemberRewardPoolEmpty`、`MemberRewardRoundedToZero`；Proposal 侧「低于门槛 / 池值为零 / 取整为零」分别回 `ProposalBelowThreshold`、`ProposalPoolEmpty`、`ProposalRewardRoundedToZero`。重复保护使用独立状态位，不能用金额是否大于零判断。

`mintProposalReward` 没有销毁分支：Mint 只支付，也**不判断**某笔激励该不该作废——那个判断属于各 Executor 的业务账本，而 Executor 侧没有任何销毁入口。无法分配的行动激励因此永久停留在未结算状态：`totalRewardReserved` 不释放，后续轮次的 `rewardAvailable` 相应被压低，代币永不铸出。`RewardBurned` 只记录 Mint 自己在准备阶段取消整池的会计行为；治理结算没有溢出分支，`BurnReason` 不再包含 `BoostOverflow`。

`isRewardPrepared` 查询本轮是否已准备；未准备时返回 `false`。

`rewardAvailable` 按 `MAX_SUPPLY - totalSupply - reservedAvailable` 计算当前可分配额度；`reservedAvailable` 返回 `totalRewardReserved - totalRewardMinted - totalRewardBurned`。

批量接口 `mintGovRewards` 先鉴权，再按输入顺序执行，结果数组与输入等长；任一 Round 的代币未登记、未结束、没有投票记录或已铸造，则整笔回滚。治理激励和发射额度/次数更新也必须原子完成。

### 透传来源

| 来源 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `ISubmit.proposalTarget` | `ProposalNotFound(address,uint256)` | `mintProposalReward` 的授权与存在性前置、`proposalRewardByProposalId` 的查询前置 |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner` 与 `govRewardByMemberId` 的查询前置 |
| `ILOVE20Token.mint` | `MaxSupplyExceeded(uint256,uint256)`、`ERC20InvalidReceiver(address)` | `recipient` 已在入口判零；供应上限由代币合约兜底 |
| `ILaunch.addLaunchCount` | `TokenNotRegistered(address)`、`LaunchCountLimitExceeded(address,uint256,uint256)` | 正常路径不可达：`_prepareRewardIfNeeded` 已先用 `ILaunch.isLOVE20Token` 判过登记，`count` 也已按剩余 `MAX_LAUNCH_COUNT` 削平；登记二者是为了让本入口的失败集合完整 |

## 发射额度的生成

Mint 保存 `launchCredit[tokenAddress][memberId]`：尚未转换成整数发射次数的治理激励额度，任意 token、memberId 可查询。只有正数实际铸造的治理激励参与累计；整数次数的保存、消耗与融合见 [Launch 的发射次数账本](08-launch.md#发射次数账本)。

每次治理激励实际铸造后，按以下顺序处理；只有正数实际铸造金额参与累计：

1. 先判断 `Launch.issuedLaunchCount(tokenAddress) >= Launch.MAX_LAUNCH_COUNT()`；成立则停止，不累计新额度，已有额度保留。
2. 否则用本次铸造前该社区代币的 `totalSupply` 计算 `threshold`；为 `0` 时停止，不累计、不转换，也不执行除法。当前账本不变式下该分支不可达（能进入此函数时必有 `mintAmount > 0`，从而 `MAX_SUPPLY - totalSupplyBeforeMint >= mintAmount > 0`），规格保留该检查作为防御。
3. 加入本次实际治理激励，计算完整次数并受剩余社区次数约束，扣除已转换额度；剩余额度保留到下次。
4. 正数新增次数由 Mint 调用 `Launch.addLaunchCount(tokenAddress, memberId, count)` 增加；Launch 只接受 Mint 调用，`count` 已由本函数按 `MAX_LAUNCH_COUNT - issuedLaunchCount` 削平，正常路径不会越限。次数增加与治理激励铸造整体回滚。次数只记入 `tokenAddress` 自己的维度，每次产生次数发一条 `LaunchCountAdded`；Mint 不额外调用，见 [Launch 的发射次数账本](08-launch.md#发射次数账本)。

```text
threshold = ceil((MAX_SUPPLY - totalSupplyBeforeMint) * Launch.LAUNCH_COUNT_THRESHOLD_RATIO() / 1e18)
count = min(floor(launchCredit / threshold), Launch.MAX_LAUNCH_COUNT() - issuedLaunchCount)
launchCredit -= count * threshold
```

`MAX_SUPPLY` 和 `totalSupplyBeforeMint` 都取自该社区代币；`LAUNCH_COUNT_THRESHOLD_RATIO` 使用 `1e18` 精度。`LAUNCH_COUNT_THRESHOLD_RATIO` 和 `MAX_LAUNCH_COUNT` 为非零/上界由 DeployCore 广播前校验、21_check 复核，Mint 不重复校验。

次数消耗或融合不释放累计上限；达到 `MAX_LAUNCH_COUNT` 后不再产生新次数或累计新额度，已有整数次数仍可使用。该上限按代币维度独立生效，首币与每个子币各自计算（见 [Launch 的发射次数账本](08-launch.md#发射次数账本)）。

例（最小单位）：当前阈值为 100、原额度为 80、本次铸造 50、剩余次数足够，则得到 1 次，余数 30。下次按新的铸造前供应量重新计算阈值，不沿用 100。

## 事件

- **`RewardPrepared(address indexed tokenAddress, uint256 indexed round, uint256 govReward, uint256 proposalReward, uint256 eligibleProposalVoteAmount, uint256 totalRewardReserved, uint256 totalRewardBurned)`**  
  准备完成后发射。`govReward` 与 `proposalReward` 为本轮冻结池值；`eligibleProposalVoteAmount` 为缓存的达标票数之和（`eligibleProposalVoteAmount == 0` 时该字段为 0）；`totalRewardReserved` 与 `totalRewardBurned` 为准备完成后的**累计值**（不是增量）。`totalVoteAmount == 0` 时两池与 `eligibleProposalVoteAmount` 均为 0，`totalRewardReserved` 与 `totalRewardBurned` 不变。

  `prepareRewardIfNeeded` 只在真正完成准备时发射本条（以及准备期取消池的 `RewardBurned`）；已准备时的重复调用是无操作，不发射任何事件。无操作不是业务事实，按 [事件规范](../../event-standards.md) §3.5 不引入「尝试 / 未变更」类事件，也不新增事件族。

- **`GovRewardMinted(address indexed tokenAddress, uint256 indexed round, uint256 indexed memberId, uint256 voteReward, uint256 boostReward, uint256 totalRewardMinted)`**  
  治理结算成功后发射。`memberId` 为被结算成员；两项金额按公式计算（`totalVoterBoost == 0` 时 `boostReward` 为 0），实际铸造量为 `voteReward + boostReward`，且 `totalRewardMinted` 为铸造后的社区累计已铸激励（后置值，等于此前全部 `GovRewardMinted` 的铸造量与 `ProposalRewardMinted.amount` 之和）。事件不再携带 `burnReward`：输出侧没有溢出，载荷中也没有任何“被销毁”的数字；`voteReward + boostReward == 0` 是拒绝条件，不会发事件。

- **`ProposalRewardMinted(address indexed tokenAddress, uint256 indexed round, uint256 indexed proposalId, address recipient, uint256 amount, uint256 totalRewardMinted)`**  
  Proposal 以 `burn = false` 结算成功后发射。`recipient` 为调用者指定的收款地址（行动类为绑定的 Executor）；`amount` 为实际铸造量；`totalRewardMinted` 为铸造后的社区累计已铸激励（后置值），与 `GovRewardMinted.totalRewardMinted` 是同一账本。

- **`RewardBurned(address indexed tokenAddress, uint256 indexed round, uint256 amount, uint256 totalRewardBurned, BurnReason reason)`**  
  准备期取消池时发射。一次准备可能发射 0～2 条；有多条时顺序为先加速池、后 Proposal 池。事件只在对应池金额大于 0 时发射；金额为 0 时账本仍 `+0`、不发事件。`totalRewardBurned` 为销毁后的社区累计已销毁额度（后置值，包含本条）。`reason` 为 `BurnReason` enum（按 `uint8` 编码，故 topic0 与旧的 `bytes32` 版本不同）：
  - `BoostPoolCancelled` - 准备期取消加速池（`totalVoterBoost == 0`）
  - `ProposalPoolCancelled` - 准备期取消 Proposal 池（`eligibleProposalVoteAmount == 0`）

  枚举只有这两项。删除末位 `BoostOverflow` 不改变前两项的序号与 `RewardBurned` 的 topic0；治理结算不再发 `RewardBurned`。

## 实现约束

事件与错误定义见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

- 两项激励比例之和 `<= 1e18`、`proposalRewardMinVoteRatio <= 1e18` 由 DeployCore 广播前校验；四个依赖有代码与 `PHASE_ADDRESS` 非零由 DeployCore 部署后校验；两者均由 21_check 独立复核；构造函数只保存入参。`MAX_GOV_BOOST_REWARD_MULTIPLIER` 已删除。
- `PHASE_ADDRESS` 是构造参数，由部署脚本从 `Phase` 地址直接传入，经同名 getter 暴露，供发布前检查脚本核对与 Vote 的 `PHASE_ADDRESS()` 一致；轮次结束判定直读 `PHASE_ADDRESS`（`round != 0 && IPhase(PHASE_ADDRESS).currentPhase() > round`），语义与 `Vote.isRoundEnded` 一致，不再经 Vote 二跳。
- Mint 的内部准备路径只在首次准备时扫描 Vote 本轮有票 Proposal；实现和验收至少覆盖约 300 个 Proposal 的准备交易。准备成功后，`_eligibleProposalVoteAmountByRound[tokenAddress][round]` 只读，不得再次读取 Vote 列表或改写。零额事件行为见[事件](#事件)节。
- 各项分配向下取整产生的极小舍入余数不单独维护，也不追加结算状态；累计账本只记录实际铸造和明确销毁的额度。
- 历史来源 `LOVE20TKM/core/src/LOVE20Mint.sol` 只作为行为参考，不替代本文件的账本规则。

验收见 [Core 验收](09-testing.md)。
