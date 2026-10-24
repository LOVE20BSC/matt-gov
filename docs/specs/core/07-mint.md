# Mint

Mint 准备并结算治理和 Proposal 激励，不读取行动验证结果。初始化参数见 [参数表](00-protocol-model.md#初始化参数)，通用权限见 [通用规则](01-common-rules.md)。

## 账本与数据来源

| 数据 | 作用域与含义 |
| --- | --- |
| `rewardReserved` | 每个 token 的累计预留总额，包含后来铸造或销毁的额度 |
| `rewardMinted` | 每个 token 的累计已铸造激励 |
| `rewardBurned` | 每个 token 的累计已取消预留额度；不铸造该部分代币 |
| `govReward` / `proposalReward` | 每个 token、Round 准备后冻结的完整治理池 / Proposal 池 |
| `totalVotes` | Vote 的本轮 `votesNum[tokenAddress][round]` |
| `memberBoost` | Vote 的 `stakedAmountOfVotersByMemberId(tokenAddress, round, memberId)` |
| `totalBoost` | Vote 的 `stakedAmountOfVoters[tokenAddress][round]` |
| `eligibleProposalVotes` | Mint 准备时按 Vote 冻结结果计算并缓存的本轮所有达标 Proposal 票数之和 |
| `launchCredit` | 每个 token、成员尚未转换为发射次数的治理激励额度，见[发射额度的生成](#发射额度的生成) |

Proposal 达标条件（链上查询通过 `isProposalIdWithReward(tokenAddress, round, proposalId)`）：

```text
proposalVotes > 0
proposalVotes * 1e18 >= totalVotes * proposalRewardMinVoteRatio
```

`isProposalIdWithReward` 无论已准备或未准备，均读取 Vote 的 `votesNumByProposalId(tokenAddress, round, proposalId)` 与 `votesNum(tokenAddress, round)` 实时判定。准备后若 `eligibleProposalVotes == 0` 可快速返回 `false`（全轮无达标 Proposal 的缓存优化）。已铸造不影响返回值（仍返回 `true`）。本入口不做 Proposal 存在性校验；无效 `proposalId` 返回 `false`。

三个奖励比例参数统一 `1e18` 精度，例如门槛 `5e16` 表示 5%。`init` 允许 `proposalRewardMinVoteRatio` 为 `0..1e18`，超过 `1e18` 回滚 `InvalidProposalRewardMinVoteRatio(proposalRewardMinVoteRatio)`；零门槛仍要求 Proposal 有正数票。账本始终满足：

```text
rewardReserved >= rewardMinted + rewardBurned
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
```

`reservedAvailable` 是尚未结算的额度，不能再次分配。三个累计账本与本轮池值不能混用。

各项向下取整产生的余数是明确的永久保留量：继续计入 `reservedAvailable`，不进入后续轮次池，也不单独铸造或销毁；该保留量属于供应上限内的协议保留额度。

## 准备一次

完整 ABI 见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

首次调用治理或 Proposal 铸造入口时，Mint 在内部准备该 Round；准备逻辑不再作为公开 ABI 暴露。

1. 本轮已准备则直接返回，不更新状态；未结束的 Round 拒绝准备（通过 `IVote(voteAddress).isRoundEnded(round)` 判定，`isRoundEnded(0) == false`）。
2. 读取 Vote 的冻结结果。若 `totalVotes == 0`，两池和 `eligibleProposalVotes` 记为 0 并标记已准备，累计账本不变。
3. 否则遍历 Vote 本轮有票 Proposal，按冻结 `totalVotes` 判断每个 Proposal 是否达到阈值，并把达标 Proposal 的票数总和写入 `eligibleProposalVotes[tokenAddress][round]`。
4. 用准备前的 `available` 计算两池，并在本步骤唯一一次增加 `rewardReserved`。
5. 若 `totalBoost == 0`，准备时直接取消加速池；若缓存的 `eligibleProposalVotes == 0`，准备时直接取消完整 Proposal 池。两个条件可同时成立，此时按顺序发射两条 `RewardBurned` 事件（先加速池、后 Proposal 池）。
6. 保存轮次池值、达标票数和已准备状态，不逐个预写 Proposal 额度。后续 Proposal 结算只读取缓存，不再扫描 Vote 列表。

```text
govReward = floor(available * roundRewardGovRatio / 1e18)
proposalReward = floor(available * roundRewardProposalRatio / 1e18)
rewardReserved += govReward + proposalReward

if totalBoost == 0:
    rewardBurned += govReward - floor(govReward / 2)  // 加速池
if eligibleProposalVotes == 0:
    rewardBurned += proposalReward
```

这是每轮唯一增加 `rewardReserved` 的位置。后续治理结算按 `voteReward + boostReward` 增加 `rewardMinted`，按加速上限溢出的 `burnReward` 增加 `rewardBurned`；Proposal 结算按实际铸造量增加 `rewardMinted`。准备阶段已经取消的额度不得再次销毁，同一额度不得重复铸造或销毁；任何失败均整体回滚。

例（最小单位）：两池为 5 和 3，且 `totalBoost = eligibleProposalVotes = 0`。准备增加预留 8、销毁 6，留下投票激励 2；再次准备不变。

## Proposal 结算

入口为 `mintProposalReward(tokenAddress, round, proposalId, recipient)`：每个 token、Round、Proposal 只能结算一次，代币铸给被授权的 Target 指定的 `recipient`。**Mint 只支付，不销毁**。

只允许该 Proposal 已记录的 Target 调用，每个 token、Round、Proposal 只能结算一次；未结束、Proposal 不达标或 `eligibleProposalVotes == 0` 时拒绝。若该 Round 尚未准备，入口先自动准备。

校验顺序：

| 条件 | 回滚 |
| --- | --- |
| 读取 `(target, targetMode) = ISubmit(submitAddress).proposalTarget(tokenAddress, proposalId)`；`msg.sender != target` | `NotProposalTarget(msg.sender, target)` |
| `recipient == address(0)` | `ZeroRecipientAddress()` |
| `!IVote(voteAddress).isRoundEnded(round)` | `RoundNotEnded(round)` |
| 已结算（独立状态位） | `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)` |
| `eligibleProposalVotes[tokenAddress][round] == 0` | `ProposalRewardUnavailable(tokenAddress, round, proposalId)` |
| Proposal 不达标 | `ProposalRewardUnavailable(tokenAddress, round, proposalId)` |

通过后写状态并铸造：

```text
实际结算量 = floor(proposalReward * proposalVotes / eligibleProposalVotes)
```

`eligibleProposalVotes == 0` 在准备阶段已取消完整 Proposal 池（见上），该 Round 任何 Proposal 都不能结算；必须在除法前判零，否则会 panic。

代币铸给 `recipient`，`rewardMinted` 按实际铸造量累计，并以 `ProposalRewardMinted` 留痕；此后该 Proposal 一律回滚 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`。`recipient` 由被授权的 Target 指定，因此行动类 Target 可以直接让 Mint 铸给绑定的 Executor，不必先铸给自己再转一次；行动侧见 [行动铸造链路](../action/07-minting.md#铸造链路)。某个行动的激励无法分配时不在这里作废：全链路没有销毁路径，该笔激励永久停留在未结算状态、预留不释放（详见下段）。无合格 Proposal 的完整池已在准备时取消，不能再次销毁。

## 治理结算

只允许成员 NFT 当前持有人为本轮实际投过票的 `memberId` 结算；若该 Round 尚未准备，入口先自动准备。

校验顺序：

| 条件 | 回滚 |
| --- | --- |
| `IMemberNFT(memberNFTAddress).ownerOf(memberId) != msg.sender` | `NotMemberOwner(uint256 memberId)` |
| `recipient == address(0)` | `ZeroRecipientAddress()` |
| `!IVote(voteAddress).isRoundEnded(round)` | `RoundNotEnded(round)` |
| 已铸造（独立状态位） | `MemberRewardAlreadyMinted(tokenAddress, round, memberId)` |
| `memberVotes == 0` | `MemberRewardUnavailable(tokenAddress, round, memberId)` |
| `voteReward + boostReward + burnReward == 0` | `MemberRewardUnavailable(tokenAddress, round, memberId)` |

通过后写状态、铸造、销毁（若有溢出）、发射额度、发射事件。代币铸给 `recipient`（必须非零；鉴权不变，仍是 `ownerOf(memberId) == msg.sender`，由当前 NFT 持有人指定收款地址）。使用以下公式，金额除法向下取整：

```text
votePoolAmount = floor(govReward / 2)
boostPoolAmount = govReward - votePoolAmount
voteReward = floor(votePoolAmount * memberVotes / totalVotes)

if totalBoost == 0:
    boostReward = 0
    burnReward = 0
else:
    theoreticalBoost = floor(boostPoolAmount * memberBoost / totalBoost)
    boostReward = min(theoreticalBoost, voteReward * maxGovBoostRewardMultiplier)
    burnReward = theoreticalBoost - boostReward
```

`memberVotes` 为本轮累计投出票数；`memberBoost` 和 `totalBoost` 均取 Vote 的同轮冻结快照，记账时机见 [Vote](06-vote.md#投票和加速快照)。投票后仅追加质押、不再投票，不增加本轮加速权重；NFT 转移不重算快照。两池按固定 50/50 拆分，奇数余量归加速池。`totalBoost == 0` 时整份加速池已在准备时取消，本次不得再计 `burnReward`。未投票者即使有加速质押也不能领取治理激励。

批量接口 `mintGovRewards` 先鉴权，再逐轮按上述顺序执行，任一轮失败整笔回滚。空 `rounds` 数组在鉴权通过后允许（返回空数组，无副作用）。轮次数量由调用者自行决定，接口不设数量上限；数量过大导致交易失败及 gas 成本由调用者承担，这是写入批量长度上限规则的明确例外。

例：两池各 500、成员投票占 10%、加速份额占 50%、倍数上限为 2。结果为 `voteReward = 50`、`boostReward = 100`、`burnReward = 150`；实际铸造 150。

## 单轮与批量接口

单轮、批量、查询和激励参数接口均见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

`proposalRewardByProposalId` 和 `govRewardByMemberId` 两个查询函数无论轮次是否已准备均能返回金额：

- **已准备**：读取准备时冻结的 `govReward`、`proposalReward` 和 `eligibleProposalVotes`，按缓存值计算。
- **未准备**：实时读取 `rewardAvailable` 计算轮次池，扫描 Vote 冻结结果计算 `eligibleProposalVotes`，按当前状态计算。**警告**：未准备查询需要扫描本轮所有有票 Proposal（O(N) 复杂度，N 为 Proposal 数量）；调用方应优先读取已准备 Round，或在前端/链下环境使用，避免对未准备轮次批量查询。**未准备时返回的是按当前状态计算的投影值，实际金额以铸造入口自动准备时冻结的池值为准。**

两个查询函数均先校验存在性（`proposalRewardByProposalId` 调用 `Submit.proposalTarget`、`govRewardByMemberId` 调用 `MemberNFT.ownerOf`），后计算金额；不存在的 Proposal/成员回滚。未达标 Proposal 或未投票成员返回零金额；已铸造不影响金额，`minted` 返回 `true` 并仍返回原金额。

未准备查询返回的金额是按**当前状态计算的投影值**，实际结算金额以准备时冻结的池值为准。查询与结算之间若有新铸造消耗供应量上限，查询投影可能高于最终准备结果；若有准备其他轮次预留池值，查询投影可能低于最终结果。

`mintGovReward` 与 `mintProposalReward` 在结算量为 0 时拒绝，分别回滚 `MemberRewardUnavailable(tokenAddress, round, memberId)` 与 `ProposalRewardUnavailable(tokenAddress, round, proposalId)`，重复保护使用独立状态位，不能用金额是否大于零判断。

`mintProposalReward` 没有销毁分支：Mint 只支付，也**不判断**某笔激励该不该作废——那个判断属于各 Executor 的业务账本，而 Executor 侧没有任何销毁入口。无法分配的行动激励因此永久停留在未结算状态：`rewardReserved` 不释放，后续轮次的 `rewardAvailable` 相应被压低，代币永不铸出。`RewardBurned` 只记录 Mint 自己会计意义上的取消（准备期整池取消与治理溢出）。

`isRewardPrepared` 查询本轮是否已准备；未准备时返回 `false`。

`rewardAvailable` 按 `maxSupply - totalSupply - reservedAvailable` 计算当前可分配额度；`reservedAvailable` 返回 `rewardReserved - rewardMinted - rewardBurned`。

批量接口 `mintGovRewards` 先鉴权，再按输入顺序执行，结果数组与输入等长；任一 Round 未结束、没有投票记录或已铸造，则整笔回滚。治理激励和发射额度/次数更新也必须原子完成。

## 发射额度的生成

Mint 保存 `launchCredit[tokenAddress][memberId]`：尚未转换成整数发射次数的治理激励额度，任意 token、memberId 可查询。只有正数实际铸造的治理激励参与累计；整数次数的保存、消耗与融合见 [Launch 的发射次数账本](08-launch.md#发射次数账本)。

每次治理激励实际铸造后，按以下顺序处理；只有正数实际铸造金额参与累计：

1. 先判断 `Launch.issuedLaunchCount(tokenAddress) >= Launch.MAX_LAUNCH_COUNT()`；成立则停止，不累计新额度，已有额度保留。
2. 否则用本次铸造前该社区代币的 `totalSupply` 计算 `threshold`；为 `0` 时停止，不累计、不转换，也不执行除法。当前账本不变式下该分支不可达（能进入此函数时必有 `mintAmount > 0`，从而 `maxSupply - totalSupplyBeforeMint >= mintAmount > 0`），规格保留该检查作为防御。
3. 加入本次实际治理激励，计算完整次数并受剩余社区次数约束，扣除已转换额度；剩余额度保留到下次。
4. 正数新增次数由 Mint 调用 `Launch.addLaunchCount(tokenAddress, memberId, count)` 增加；Launch 只接受 Mint 调用并在越限时回滚。次数增加与治理激励铸造整体回滚。当 `tokenAddress` 是首币时，Launch 在同一调用内把同一 `count` 1:1 记入根父币维度（根级次数）并发第二条 `LaunchCountAdded`；伴生由 Launch 完成，Mint 不额外调用、不感知，也不为根级次数维护 `launchCredit`，见 [Launch 的根级次数与伴生规则](08-launch.md#根级次数与伴生规则)。

```text
threshold = ceil((maxSupply - totalSupplyBeforeMint) * Launch.LAUNCH_RATIO() / 1e18)
count = min(floor(launchCredit / threshold), Launch.MAX_LAUNCH_COUNT() - issuedLaunchCount)
launchCredit -= count * threshold
```

`maxSupply` 和 `totalSupplyBeforeMint` 都取自该社区代币；`LAUNCH_RATIO` 使用 `1e18` 精度。`LAUNCH_RATIO` 和 `MAX_LAUNCH_COUNT` 由 `Launch.init` 校验为非零（`ZeroLaunchRatio` / `ZeroMaxLaunchCount`），Mint 不重复校验。

次数消耗或融合不释放累计上限；达到 `MAX_LAUNCH_COUNT` 后不再产生新次数或累计新额度，已有整数次数仍可使用。首币达到上限时根级伴生同步停止（不变式：根级累计恒等于首币累计，见 [Launch 的根级次数与伴生规则](08-launch.md#根级次数与伴生规则)）。

例（最小单位）：当前阈值为 100、原额度为 80、本次铸造 50、剩余次数足够，则得到 1 次，余数 30。下次按新的铸造前供应量重新计算阈值，不沿用 100。

## 事件

- **`RewardPrepared(address indexed tokenAddress, uint256 indexed round, uint256 govReward, uint256 proposalReward, uint256 eligibleProposalVotes, uint256 rewardReserved, uint256 rewardBurned)`**  
  准备完成后发射。`govReward` 与 `proposalReward` 为本轮冻结池值；`eligibleProposalVotes` 为缓存的达标票数之和（`eligibleProposalVotes == 0` 时该字段为 0）；`rewardReserved` 与 `rewardBurned` 为准备完成后的**累计值**（不是增量）。`totalVotes == 0` 时两池与 `eligibleProposalVotes` 均为 0，`rewardReserved` 与 `rewardBurned` 不变。

- **`GovernanceRewardMinted(address indexed tokenAddress, uint256 indexed round, uint256 indexed memberId, uint256 voteReward, uint256 boostReward, uint256 burnReward)`**  
  治理结算成功后发射。`memberId` 为被结算成员；三项金额按公式计算（`totalBoost == 0` 时 `boostReward` 与 `burnReward` 均为 0）。

- **`ProposalRewardMinted(address indexed tokenAddress, uint256 indexed round, uint256 indexed proposalId, address recipient, uint256 amount)`**  
  Proposal 以 `burn = false` 结算成功后发射。`recipient` 为调用者指定的收款地址（行动类为绑定的 Executor）；`amount` 为实际铸造量。

- **`RewardBurned(address indexed tokenAddress, uint256 indexed round, uint256 amount, BurnReason reason)`**  
  准备期取消池或治理结算溢出时发射。一次准备可能发射 0～2 条；有多条时顺序为先加速池、后 Proposal 池。准备期的 `RewardBurned` 事件只在对应池金额大于 0 时发射（与治理结算溢出口径一致）；金额为 0 时账本仍 `+0`、不发事件。`reason` 为 `BurnReason` enum（按 `uint8` 编码，故 topic0 与旧的 `bytes32` 版本不同）：
  - `BoostPoolCancelled` - 准备期取消加速池（`totalBoost == 0`）
  - `ProposalPoolCancelled` - 准备期取消 Proposal 池（`eligibleProposalVotes == 0`）
  - `BoostOverflow` - 治理结算时加速上限溢出（`burnReward > 0`）

## 实现约束

事件与错误定义见 [`IMint.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMint.sol)。

- 初始化时四个依赖与从 `voteAddress` 派生的 `phaseAddress` 均要求有代码（零地址同条件，`DependencyNotContract(address)`），且两项激励比例之和不得超过 `1e18`（`InvalidRoundRewardRatios(roundRewardGovRatio, roundRewardProposalRatio)`）；校验顺序按 [通用规则](01-common-rules.md#初始化与安全)，先初始化状态、后参数校验。`maxGovBoostRewardMultiplier` 须满足 `0 < x ≤ 1000`（`InvalidMaxGovBoostRewardMultiplier(maxGovBoostRewardMultiplier)`），这是整数倍数上限，与比例刻度无关；`proposalRewardMinVoteRatio` 须在 `0..1e18` 范围，超出上界回滚 `InvalidProposalRewardMinVoteRatio(proposalRewardMinVoteRatio)`。
- `phaseAddress` 在 `init` 时从 Vote 读取一次并缓存，经同名 getter 暴露，供发布前检查脚本核对与 Vote 一致；`voteAddress` 须先完成 init，否则其 `phaseAddress` 为零或无代码、`init` 回滚 `DependencyNotContract(phaseAddress)`。轮次结束判定直读缓存的 Phase（`round != 0 && IPhase(phaseAddress).currentPhase() > round`），语义与 `Vote.isRoundEnded` 一致，不再经 Vote 二跳。
- Mint 的内部准备路径只在首次准备时扫描 Vote 本轮有票 Proposal；实现和验收至少覆盖约 300 个 Proposal 的准备交易。准备成功后，`eligibleProposalVotes[tokenAddress][round]` 只读，不得再次读取 Vote 列表或改写。零额事件行为见[事件](#事件)节。
- 各项分配向下取整产生的极小舍入余数不单独维护，也不追加结算状态；累计账本只记录实际铸造和明确销毁的额度。
- 历史来源 `LOVE20TKM/core/src/LOVE20Mint.sol` 只作为行为参考，不替代本文件的账本规则。

验收见 [Core 验收](09-testing.md)。
