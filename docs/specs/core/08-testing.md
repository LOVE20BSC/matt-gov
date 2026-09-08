# Core 事件、错误与验收

本文件规定验收范围，行为以对应模块为准；证据与发布要求见 [组织验收](../../acceptance.md)。这是待实现的场景清单，不是已通过的测试报告。

## 事件

```solidity
event PhaseSynchronized(uint256 indexed phase, uint256 blockNumber, uint256 timestamp,
    bool adjusted, uint256 phaseBlocks);
event PhaseAdjusted(uint256 indexed effectivePhase, uint256 oldPhaseBlocks, uint256 newPhaseBlocks);
event ProposalCreated(address indexed tokenAddress, uint256 indexed proposalId, uint256 indexed author,
    string title, string details, address target, uint8 targetMode);
event ProposalSubmitted(address indexed tokenAddress, uint256 indexed round, uint256 indexed proposalId,
    uint256 submitterId);
event VoteCast(address indexed tokenAddress, uint256 indexed round, uint256 indexed proposalId,
    uint256 voterId, uint256 votes);
event RewardPrepared(address indexed tokenAddress, uint256 indexed round, uint256 govReward,
    uint256 proposalReward, uint256 eligibleProposalVotes, uint256 rewardReserved, uint256 rewardBurned);
event GovernanceRewardMinted(address indexed tokenAddress, uint256 indexed round, uint256 indexed memberId,
    uint256 voteReward, uint256 boostReward, uint256 burnReward);
event ProposalRewardMinted(address indexed tokenAddress, uint256 indexed round, uint256 indexed proposalId,
    address target, uint256 amount);
event RewardBurned(address indexed tokenAddress, uint256 indexed round, uint256 amount, bytes32 reason);
event LaunchCountAdded(address indexed tokenAddress, uint256 indexed memberId, uint256 count);
event LaunchCountMerged(address indexed tokenAddress, uint256 indexed sourceMemberId,
    uint256 indexed targetMemberId, uint256 count);
event LaunchCountConsumed(address indexed tokenAddress, uint256 indexed memberId, uint256 count);
event TokenCreated(address indexed tokenAddress, address indexed parentTokenAddress,
    string name, string symbol, address distributor);
```

事件使用 `tokenAddress`、`memberId`、`proposalId`、`round` 主键；地址字段仅表示代币、Target、Distributor 或调用审计地址。

## 拒绝条件

```solidity
error AlreadyInitialized();
```

必须拒绝无效成员或非来源控制者、零 Target/Distributor、非法模式、KV 长度不等、重复 Proposal/推举、投票超额、Round 未结束或未准备、重复铸造/销毁、待解锁时追加或融合、解锁期不足、跨社区次数操作、次数不足或超上限。重复准备属于幂等返回，不等同于重复结算。

批量治理激励中任一 Round 无效，以及 Pair、Router、Target 外部调用失败时，整笔交易回滚。

## 验收矩阵

| 模块 | 场景 | 预期 |
| --- | --- | --- |
| [MemberNFT](02-member-nft.md) | NFT 转移、名称 32 bytes 边界、短名费用 | 新持有人控制未结算权益，历史不变；名称与费用符合模块规则 |
| MemberNFT | 持有人枚举：自转账、转出全部、再转入 | 自转账不移除，余额归零后移除，索引按 swap-and-pop 重排 |
| [Phase](03-phase.md) | 空阶段、首个推举同步、偏差在/超过 `adjustThreshold` | 时间继续推进，按初始化阈值校准，不改历史 |
| Phase | 任意地址先同步、同轮跨社区重复、下轮再同步 | 每个投票轮只记录一次；重复无操作、不阻塞 Submit；下轮重新允许 |
| [Stake](04-stake.md) | 两类资产统一解锁；向非自有目标融合 | 只增目标状态；同一等待期后提取两类资产 |
| Stake | LP 份额、手续费销毁统计、PancakeSwap、加速历史继承 | 份额/资产/历史与模块公式一致，不因无记录而错误复活 |
| [Proposal](05-submit-vote.md) | 零 Target、三类回调失败 | 拒绝并整体回滚 |
| [Mint](06-mint.md) | Round 准备、单 Proposal 结算、重复准备 | 每轮仅预留一次，单项不能重复结算 |
| Mint | 约 300 个 Proposal 的准备、缓存读取 | 准备阶段一次扫描并缓存达标 Proposal 总票数；后续单项结算不再扫描 Vote 列表，重复准备不改缓存 |
| Mint | 两种零总量、三段治理结果、批量多轮 | 预留不重加，销毁不重复，任一失败整体回滚 |
| Vote / Mint | 投票时快照为 50，随后追加 30；再次投票或不投票；NFT 转移 | 不投票仍按 50，再投票按 80、总量仅加 30；结算和转移不重算 |
| [Launch](07-launch.md) | 向上取整、跨多个阈值、社区上限 | 余数保留，新增次数不超上限，仅 Mint 可 addLaunchCount |
| Launch | 向非自有 NFT 部分融合、次数消耗 | 源扣目标增，不转移额度，已消耗次数不能再次使用 |
| Launch.init | 首币、Airdrop、任一步失败或重复初始化 | 首次原子完成，失败全回滚，成功后不能重做 |

存在“待确认”的场景必须先确定预期，不得用当前实现结果反推规格。
