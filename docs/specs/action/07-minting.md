# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> ActionTarget -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口；ActionTarget 作为 Target 调用 Mint，取得指定 token、Round、Proposal 的完整激励并在同一交易全部转回 Executor，不留余额。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复结算。

服务轮次没有可分配源行动时，使用 Executor 的 `burnRewardIfNeeded(round)` 专用入口；该入口只能处理已结束轮次，且重复调用无操作。

Core 的预留、铸造和取消额度账本见 [Mint](../core/06-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

## 事件

下列为已有事件名称与参数示意，尚未给出完整类型和 indexed 定义：

| 事件 | 触发语义 |
| --- | --- |
| `ProposalLinked(tokenAddress, proposalId, executor)` | 关联 Executor |
| `ActionJoined(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)` | 自有或体验加入 |
| `ActionWithdrawn(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)` | 部分撤回 |
| `ActionExited(tokenAddress, actionId, memberId, round, isExperience, providerMemberId)` | 全部退出 |
| `ForceExited(tokenAddress, actionId, memberId)` | 仅清除通用登记 |
| `VerifierApplied(tokenAddress, actionId, memberId, round, applicationId)` | 候选申请 |
| `VerificationBatchSubmitted(tokenAddress, actionId, groupId, round, batchIndex, scores[])` | 验证批次 |
| `VerifierLocked(tokenAddress, actionId, round, memberId)` | 验证者锁定 |
| `ActionRewardMinted(tokenAddress, actionId, round, totalAmount, recipientType)` | 成员/验证者/owner 激励 |
| `ServiceRewardDistributed(serviceTokenAddress, serviceProposalId, actionTokenAddress, memberId, verifierReward, ownerReward, round)` | 服务分配 |
| `SecondaryDistributionConfigured(sourceTokenAddress, sourceActionId, groupId, round, recipientIds[], ratios[])` | 二次分配配置；缺少当前轮次时沿用最近历史配置 |

事件还须覆盖候选排名、验证完成和激励销毁；对应签名尚未确定。

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
