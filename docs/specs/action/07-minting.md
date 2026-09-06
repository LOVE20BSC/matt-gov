# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> ActionTarget -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口；ActionTarget 作为 Target 调用 Mint，取得指定 token、Round、Proposal 的完整激励并在同一交易全部转回 Executor，不留余额。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复结算。

服务轮次没有可分配源行动时，使用 Executor 的 `burnRewardIfNeeded(round)` 专用入口；该入口只能处理已结束轮次，Executor 直接调用服务代币 `burn(amount)`，且重复调用无操作。

Core 的预留、铸造和取消额度账本见 [Mint](../core/06-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

## 事件

```solidity
event ProposalLinked(address indexed tokenAddress, uint256 indexed proposalId, address indexed executor);
event ActionJoined(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
    uint256 round, uint256 amount, bool isExperience, uint256 providerMemberId);
event ActionWithdrawn(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
    uint256 round, uint256 amount, bool isExperience, uint256 providerMemberId);
event ActionExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
    uint256 round, bool isExperience, uint256 providerMemberId);
event ForceExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId);
event VerifierApplied(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
    uint256 round, uint256 applicationId);
event VerificationBatchSubmitted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed groupId,
    uint256 round, uint256 batchIndex, uint256[] scores);
event VerifierLocked(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
    uint256 memberId);
event ActionRewardMinted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
    uint256 totalAmount, bytes32 recipientType);
event ServiceRewardDistributed(address indexed serviceTokenAddress, uint256 indexed serviceProposalId,
    address indexed actionTokenAddress, uint256 memberId, uint256 verifierReward, uint256 ownerReward,
    uint256 ownerBurned, uint256 round);
event SecondaryDistributionConfigured(address indexed sourceTokenAddress, uint256 indexed sourceActionId,
    uint256 indexed groupId, uint256 round, uint256[] recipientIds, uint256[] ratios);
event RewardBurned(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
    uint256 amount, bytes32 reason);
```

事件按 BSC 业务主体使用 `memberId`；事件中的地址仅表示代币、合约或调用审计地址。

## 错误

| 已有错误示意 | 拒绝条件 |
| --- | --- |
| `InvalidExecutor()` | 零地址、EOA、无代码 Executor |
| `UnauthorizedCallback()` | 非 ActionTarget 调用 Executor 回调 |
| `NotMemberOwner(memberId)` | 调用者非该 NFT 当前持有人 |
| `ProposalNotVoted(tokenAddress, proposalId)` | Proposal 无票或未达门槛 |
| `InvalidRound(round)` | 不在对应操作的有效阶段 |
| `InsufficientExperienceQuota(providerMemberId, required, available)` | 体验额度不足 |
| `VerifierAlreadyLocked(tokenAddress, actionId, round)` | 锁定后更换验证者 |
| `BatchIndexMismatch(expected, actual)` | 验证批次跳跃、重复或乱序 |
| `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` | 重复成员结算 |
| `DistributionOverflow(configured, available)` | 配置比例总和超过 `1e18` 时拒绝；正好 `1e18` 合法 |

还须拒绝重复初始化、KV 长度不等、非法参与量、候选/分割线无效和申请已失效。待确认错误的类型和语义不能由实现者擅自补齐。

验收见 [Action 验收](08-testing.md)。
