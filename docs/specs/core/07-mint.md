# Mint

Mint 准备并结算治理和 Proposal 激励，不读取行动验证结果。部署参数见 [参数表](00-protocol-model.md#部署参数)，通用权限见 [通用规则](01-common-rules.md)。

## 账本与数据来源

| 数据 | 作用域与含义 |
| --- | --- |
| `totalRewardReserved` | 每个 token 的累计预留总额，包含后来铸造或销毁的额度 |
| `totalRewardMinted` | 每个 token 的累计已铸造激励 |
| `totalRewardBurned` | 每个 token 的累计已取消预留额度；不铸造该部分代币 |
| `govReward` / `proposalReward` | 每个 token、Round 首票预留时冻结的完整治理池 / Proposal 池。两项 getter 始终返回原始池值，供单项激励计算 |
| `totalVoteAmount` | Vote 的本轮 `totalVoteAmount(tokenAddress, round)` |
| `voterBoost` | 成员本轮在 Vote 的加速快照，`voterBoost(tokenAddress, round, memberId)` |
| `totalVoterBoost` | 本轮全局加速快照，`totalVoterBoost(tokenAddress, round)` |
| `launchCredit` | 每个 token、成员尚未转换为发射次数的治理激励额度，见[发射额度的生成](#发射额度的生成)。累加不单独发事件：`count == 0` 的累加与被 `MAX_LAUNCH_COUNT` 削平后留下的余额只能通过 `launchCredit()` 轮询，链下不要试图仅凭事件重建 |

Proposal 达标条件（链上查询通过 `isProposalIdWithReward(tokenAddress, round, proposalId)`）：

```text
proposalVoteAmount > 0
proposalVoteAmount * 1e18 >= totalVoteAmount * proposalRewardMinVoteRatio
```

`isProposalIdWithReward` 读取 Vote 的单项票权和当轮总票权判定。已铸造的达标 Proposal 仍返回 `true`。未知 `proposalId` 的票权为零，查询返回 `false`。

三个激励比例参数统一 `1e18` 精度，例如门槛 `5e16` 表示 5%。`proposalRewardMinVoteRatio` 允许 `0..1e18`，上界由 DeployCore 广播前校验、21_check 复核；零门槛仍要求 Proposal 有正数票。账本始终满足：

```text
totalRewardReserved >= totalRewardMinted + totalRewardBurned
reservedAvailable = totalRewardReserved - totalRewardMinted - totalRewardBurned
available = MAX_SUPPLY - totalSupply - reservedAvailable
```

`reservedAvailable` 是尚未结算的额度，不能再次分配。三个累计账本与本轮池值不能混用。

`MAX_SUPPLY` 约束的是**任一时刻可铸出总量的上限**，不是累计发行量：`LOVE20Token.burn` 无许可，任何人销毁自己的余额都会抬高 `MAX_SUPPLY − totalSupply`，未来轮次据此重新预留；因此 `totalRewardMinted` 可以超过 `MAX_SUPPLY`，把两者直接比较的判断都是错的。

各项向下取整的余数通常继续计入 `reservedAvailable`。若一轮所有有票 Proposal 均未达标，最后一次逐项销毁释放整个 Proposal 池的取整余数。

## 准备一次

完整 ABI 见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

Vote 在每个社区每轮首笔正数投票时调用 `reserveRoundReward`，按当时的可用额度计算并冻结两池。零票轮次的两池均为零。跨轮准备和结算顺序与已预留的池值无关。

任何人可在轮末调用 `prepareRewardIfNeeded`。治理铸造、Proposal 铸造和逐项销毁也会自动准备。首次准备先验证社区代币已登记，再验证 `round != 0 && Phase.currentPhase() > round`。准备读取已预留池值，在治理池为正且 `totalVoterBoost == 0` 时释放加速池，随后记录已准备状态。重复准备直接返回。

```text
govReward = floor(available * roundRewardGovRatio / 1e18)
proposalReward = floor(available * roundRewardProposalRatio / 1e18)
totalRewardReserved += govReward + proposalReward

if totalVoterBoost == 0:
    totalRewardBurned += govReward - floor(govReward / 2)  // 加速池
```

首票预留是每轮唯一增加 `totalRewardReserved` 的位置。治理结算按 `voteReward + boostReward` 增加 `totalRewardMinted`，Proposal 结算按实际铸造量增加 `totalRewardMinted`。

## Proposal 结算

`mintProposalReward` 将某个 Proposal 的激励一次性铸给其 Target 指定的 `recipient`。

只允许该 Proposal 已记录的 Target 调用，每个 token、Round、Proposal 只能结算一次；未结束、Proposal 不达标或该轮 `proposalReward` 为零时拒绝。若该 Round 尚未准备，入口先自动准备。

铸造权只由「票数达标 + 是 target」两点决定，与提案是否被执行无关：`NoCallback` 的 target 可为 EOA，协议不校验它与提案主题相关，也不读取任何执行状态。投票者投的是内容，收款的是 target，两者之间没有链上约束。

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
实际结算量 = floor(proposalReward * proposalVoteAmount / totalVoteAmount)
```

结算量为 0 时按「单提案 → 整轮 → 取整」逐层定位：

1. **单提案**：`voteAmount < minVoteAmount` 回 `ProposalBelowThreshold`，两个条件值都写进载荷，调用方据此区分“有票但不够”与“一票没拿到”。零票只在门槛大于 0、且本轮另有提案拿到票时才落到这一层；整轮零票时 `minVoteAmount` 也是 `0`，`0 < 0` 不成立，进入下一层。
2. **整轮**。`proposalReward == 0` 回 `ProposalPoolEmpty`。整轮零票时未发生首票预留。预留份额向下取整为零也触发此错误。
3. **取整**：门槛通过、池值非零，但 `floor(proposalReward * proposalVoteAmount / totalVoteAmount) == 0` 时回 `ProposalRewardRoundedToZero`。零门槛且池为正时，零票提案也落到这一层。

先具体后整轮：同一 Proposal 同时满足两组条件时报门槛，否则调用方会被轮级错误引去查整轮，而实际该提案本身就不够票。必须在除法前判零，否则会 panic。

代币铸给 `recipient`，`totalRewardMinted` 按实际铸造量累计，并以 `ProposalRewardMinted` 留痕。此后再次铸造回滚 `ProposalRewardAlreadyMinted`。行动类 Target 可以指定绑定的 Executor 收款，详见 [行动铸造链路](../action/07-minting.md#铸造链路)。

### 逐项销毁

轮末任何人可调用 `burnProposalReward` 处理一个有票但未过线的 Proposal。每个 `(tokenAddress, round, proposalId)` 最多处理一次。零票和达标 Proposal 跳过逐项销毁。未准备的轮次会先完成准备。

每笔增加 `totalRewardBurned` 的额度按同一个原始池值和分母计算，即 `floor(proposalReward * proposalVoteAmount / totalVoteAmount)`。协议同时记录已处理票权，份额取整为零也计入票权。累计处理票权等于当轮总票权时，最后一笔释放原始池值扣除已释放份额后的尾差。若有达标 Proposal，逐项释放未达标份额，取整尾差仍计入预留。释放额度立即回到可用供应，代币供应量保持原值。

达标行动的激励仍由 Executor 按各自验证和分配规则结算。达标后无法分配的额度继续保留。

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

`memberVoteAmount` 为本轮累计投出票数；`voterBoost` 和 `totalVoterBoost` 均取 Vote 的同轮冻结快照，记账时机见 [Vote](06-vote.md#投票和加速快照)。投票后仅追加质押、不再投票，不增加本轮加速权重；NFT 转移不重算快照。两池按固定 50/50 拆分，奇数余量归加速池。`totalVoterBoost == 0` 时整份加速池已在准备时取消，本次不得再计加速额。未投票者即使有加速质押也不能铸造治理激励。

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

- **已预留**时读取首票冻结的池值，结合 Vote 的票权或加速份额计算。轮内票权仍可变化，轮末冻结。
- **尚未预留**时若需要池值，查询用当前 `rewardAvailable` 计算投影。正常投票流程在首票的同一笔交易内写入预留。

两个查询函数均先校验存在性（`proposalRewardByProposalId` 调用 `Submit.proposalTarget`、`govRewardByMemberId` 调用 `MemberNFT.ownerOf`），后计算金额；不存在的 Proposal/成员回滚。未达标 Proposal 或未投票成员返回零金额；已铸造不影响金额，`minted` 返回 `true` 并仍返回原金额。

`mintGovReward` 与 `mintProposalReward` 在结算量为 0 时拒绝，两侧都按“具体对象 → 整轮 → 取整为零”的顺序：治理侧「未投票 / 池为空 / 取整为零」分别回 `MemberHasNoVote`、`MemberRewardPoolEmpty`、`MemberRewardRoundedToZero`；Proposal 侧「低于门槛 / 池值为零 / 取整为零」分别回 `ProposalBelowThreshold`、`ProposalPoolEmpty`、`ProposalRewardRoundedToZero`。重复保护使用独立状态位，不能用金额是否大于零判断。

`isRewardPrepared` 查询本轮是否已准备；未准备时返回 `false`。

`rewardAvailable` 按 `MAX_SUPPLY - totalSupply - reservedAvailable` 计算当前可分配额度；`reservedAvailable` 返回 `totalRewardReserved - totalRewardMinted - totalRewardBurned`。

批量接口 `mintGovRewards` 先鉴权，再按输入顺序执行，结果数组与输入等长；任一 Round 的代币未登记、未结束、没有投票记录或已铸造，则整笔回滚。治理激励和发射额度/次数更新也必须原子完成。

### 透传来源

| 来源 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `ISubmit.proposalTarget` | `ProposalNotFound(address,uint256)` | `mintProposalReward` 的授权与存在性前置、`proposalRewardByProposalId` 的查询前置 |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner` 与 `govRewardByMemberId` 的查询前置 |
| `ILOVE20Token.mint` | `MaxSupplyExceeded(uint256,uint256)`、`ERC20InvalidReceiver(address)` | `recipient` 已在入口判零；最大铸币上限由代币合约兜底 |
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

- `RoundRewardReserved` 在首票预留时发射，记录两池原始额度。
- `RewardPrepared` 在首次准备后发射，记录两池原始额度与预留、销毁累计值。若同笔释放加速池，`RewardBurned` 在前。
- `GovRewardMinted` 与 `ProposalRewardMinted` 记录各自的实际铸造量及同一个 `totalRewardMinted` 后置值。
- `ProposalRewardBurned` 在每项首次处理后发射，记录提案 ID、释放额度和 `totalRewardBurned` 后置值。份额为零时仍发射，供索引方识别已处理 Proposal。
- `RewardBurned` 记录正数的加速池释放（`BoostPoolCancelled`），以及全轮未过线时最后一笔逐项销毁释放的正数尾差（`ProposalPoolCancelled`）。两类销毁事件的 `amount` 之和对应 `totalRewardBurned`。

## 实现约束

事件与错误定义见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

- 两项激励比例之和 `<= 1e18`、`proposalRewardMinVoteRatio <= 1e18` 由 DeployCore 广播前校验；四个依赖有代码与 `PHASE_ADDRESS` 非零由 DeployCore 部署后校验；两者均由 21_check 独立复核；构造函数只保存入参。`MAX_GOV_BOOST_REWARD_MULTIPLIER` 已删除。
- `PHASE_ADDRESS` 是构造参数，由部署脚本从 `Phase` 地址直接传入，经同名 getter 暴露，供发布前检查脚本核对与 Vote 的 `PHASE_ADDRESS()` 一致；轮次结束判定直读 `PHASE_ADDRESS`（`round != 0 && IPhase(PHASE_ADDRESS).currentPhase() > round`），语义与 `Vote.isRoundEnded` 一致，不再经 Vote 二跳。
- 准备、单项预览、单项铸造和逐项销毁的开销与本轮 Proposal 数量无关。单个 Proposal 的份额计算读取 Vote 的轮次总票权和该 Proposal 的票权。
- 历史来源 `LOVE20TKM/core/src/LOVE20Mint.sol` 只作为行为参考，不替代本文件的账本规则。

验收见 [Core 验收](09-testing.md)。
