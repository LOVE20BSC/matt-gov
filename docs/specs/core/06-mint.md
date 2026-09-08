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

Proposal 达标条件：

```text
proposalVotes > 0
proposalVotes * 1000 >= totalVotes * proposalRewardMinVotePerThousand
```

`PerThousand` 参数使用千分比，例如门槛 50 表示 5%。账本始终满足：

```text
rewardReserved >= rewardMinted + rewardBurned
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
```

`reservedAvailable` 是尚未结算的额度，不能再次分配。三个累计账本与本轮池值不能混用。

各项向下取整产生的余数是明确的永久保留量：继续计入 `reservedAvailable`，不进入后续轮次池，也不单独铸造或销毁；该保留量属于供应上限内的协议保留额度。

## 准备一次

```solidity
function init(
    address voteAddress,
    address submitAddress,
    address stakeAddress,
    address launchAddress,
    address memberNFTAddress,
    uint256 proposalRewardMinVotePerThousand,
    uint256 roundRewardGovPerThousand,
    uint256 roundRewardProposalPerThousand,
    uint256 maxGovBoostRewardMultiplier
) external;

function prepareRewardIfNeeded(address tokenAddress, uint256 round) external;
```

`prepareRewardIfNeeded` 任何地址可调用。

1. 本轮已准备则直接返回，不更新状态；未结束的 Round 拒绝准备。
2. 读取 Vote 的冻结结果。若 `totalVotes == 0`，两池和 `eligibleProposalVotes` 记为 0 并标记已准备，累计账本不变。
3. 否则遍历 Vote 本轮有票 Proposal，按冻结 `totalVotes` 判断每个 Proposal 是否达到阈值，并把达标 Proposal 的票数总和写入 `eligibleProposalVotes[tokenAddress][round]`。
4. 用准备前的 `available` 计算两池，并在本步骤唯一一次增加 `rewardReserved`。
5. 若 `totalBoost == 0`，准备时直接取消加速池；若缓存的 `eligibleProposalVotes == 0`，准备时直接取消完整 Proposal 池。
6. 保存轮次池值、达标票数和已准备状态，不逐个预写 Proposal 额度。后续 Proposal 结算只读取缓存，不再扫描 Vote 列表。

```text
govReward = floor(available * roundRewardGovPerThousand / 1000)
proposalReward = floor(available * roundRewardProposalPerThousand / 1000)
rewardReserved += govReward + proposalReward

if totalBoost == 0:
    rewardBurned += govReward - floor(govReward / 2)  // 加速池
if eligibleProposalVotes == 0:
    rewardBurned += proposalReward
```

这是每轮唯一增加 `rewardReserved` 的位置。后续治理结算按 `voteReward + boostReward` 增加 `rewardMinted`，按加速上限溢出的 `burnReward` 增加 `rewardBurned`；Proposal 结算按实际铸造量增加 `rewardMinted`。准备阶段已经取消的额度不得再次销毁，同一额度不得重复铸造或销毁；任何失败均整体回滚。

例（最小单位）：两池为 5 和 3，且 `totalBoost = eligibleProposalVotes = 0`。准备增加预留 8、销毁 6，留下投票激励 2；再次准备不变。

## Proposal 结算

```solidity
function mintProposalReward(
    address tokenAddress,
    uint256 round,
    uint256 proposalId
) external returns (uint256 amount);
```

只允许该 Proposal 已记录的 Target 调用，每个 token、Round、Proposal 只能铸造一次；未准备、未结束、Proposal 不达标或 `eligibleProposalVotes == 0` 时拒绝。

```text
实际铸造量 = floor(proposalReward * proposalVotes / eligibleProposalVotes)
```

代币铸给 Target；行动类 Target 的后续转发见 [行动铸造链路](../action/07-minting.md#铸造链路)。无合格 Proposal 的完整池已在准备时取消，不能再次销毁。

## 治理结算

只允许成员 NFT 当前持有人为本轮实际投过票的 `memberId` 结算。使用以下公式，金额除法向下取整：

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

`memberVotes` 为本轮累计投出票数；`memberBoost` 和 `totalBoost` 均取 Vote 的同轮冻结快照，记账时机见 [Vote](05-submit-vote.md#投票和加速快照)。投票后仅追加质押、不再投票，不增加本轮加速权重；NFT 转移不重算快照。两池按固定 50/50 拆分，奇数余量归加速池。`totalBoost == 0` 时整份加速池已在准备时取消，本次不得再计 `burnReward`。未投票者即使有加速质押也不能领取治理激励。

例：两池各 500、成员投票占 10%、加速份额占 50%、倍数上限为 2。结果为 `voteReward = 50`、`boostReward = 100`、`burnReward = 150`；实际铸造 150。

## 单轮与批量接口

```solidity
function mintGovReward(
    address tokenAddress,
    uint256 memberId,
    uint256 round
) external returns (
    uint256 voteReward,
    uint256 boostReward,
    uint256 burnReward
);

function mintGovRewards(
    address tokenAddress,
    uint256 memberId,
    uint256[] calldata rounds
) external returns (
    uint256[] memory voteRewards,
    uint256[] memory boostRewards,
    uint256[] memory burnRewards
);

function rewardReserved(address tokenAddress) external view returns (uint256);
function rewardMinted(address tokenAddress) external view returns (uint256);
function rewardBurned(address tokenAddress) external view returns (uint256);
function isRewardPrepared(address tokenAddress, uint256 round)
    external view returns (bool);
function govReward(address tokenAddress, uint256 round)
    external view returns (uint256);
function proposalReward(address tokenAddress, uint256 round)
    external view returns (uint256);
function eligibleProposalVotes(address tokenAddress, uint256 round)
    external view returns (uint256);
function proposalRewardInfo(address tokenAddress, uint256 round, uint256 proposalId)
    external view returns (uint256 amount, bool prepared, bool minted);
function govRewardByAccount(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256 voteReward, uint256 boostReward, uint256 burnReward, bool minted);
function isProposalIdWithReward(address tokenAddress, uint256 round, uint256 proposalId)
    external view returns (bool);
function rewardAvailable(address tokenAddress) external view returns (uint256);
function reservedAvailable(address tokenAddress) external view returns (uint256);
function launchCredit(address tokenAddress, uint256 memberId) external view returns (uint256);
function proposalRewardMinVotePerThousand() external view returns (uint256);
```

`proposalRewardInfo` 未准备时返回 `(0, false, false)`，不能把它缓存为最终零激励；准备后按冻结池、Proposal 票数和已缓存的 `eligibleProposalVotes` 计算 amount，已铸造也返回原金额。未达标返回 0。治理查询未准备或未投票时返回零金额；不存在的 Proposal/成员回滚。铸造金额为 0 时按旧逻辑拒绝 `NoRewardAvailable`，重复保护使用独立状态位，不能用金额是否大于零判断。

批量按输入顺序执行，结果数组与输入等长；任一 Round 未结束、未准备、没有投票记录或已铸造，则整笔回滚。治理激励和发射额度/次数更新也必须原子完成。

## 发射额度

Mint 保存 `launchCredit[tokenAddress][memberId]`。只有实际铸造的治理激励可累计；上限、零阈值、计算顺序和余数规则只在 [Launch](07-launch.md#发射次数) 定义。产生正数次数时调用仅授权 Mint 的 `Launch.addLaunchCount`。

## 实现约束

- 初始化时拒绝两项激励比例之和超过 `1000`。
- 各项分配向下取整产生的极小舍入余数不单独维护，也不追加结算状态；累计账本只记录实际铸造和明确销毁的额度。
- 历史来源 `LOVE20TKM/core/src/LOVE20Mint.sol` 只作为行为参考，不替代本文件的账本规则。

验收见 [Core 验收](08-testing.md)。
