# 铸造闭环、事件和错误

本文档定义行动激励铸造流程、事件规范和错误代码。

---

## 1. 铸造闭环

行动激励闭环固定为：`executor -> ActionTarget -> Mint -> ActionTarget -> executor`

Executor 一次铸造一个 Proposal 在该 Round 的全部行动激励，再在内部完成参与者、公共验证者和 owner 分配。只有关联 Executor 可以发起；任何失败都回滚，ActionTarget 不保留余额。

---

## 2. 事件

至少发出：Proposal 关联、行动参与/撤回/退出、公共验证者申请和排名、验证批次/锁定/完成、行动激励铸造/销毁、服务分配和 `forceExit` 事件。

**核心事件定义**：
- `ProposalLinked(tokenAddress, proposalId, executor)`：Proposal 关联 Executor
- `ActionJoined(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)`：成员加入行动（自有或体验）
- `ActionWithdrawn(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)`：部分撤回
- `ActionExited(tokenAddress, actionId, memberId, round, isExperience, providerMemberId)`：全部退出
- `ForceExited(tokenAddress, actionId, memberId)`：应急退出（只清除 ActionTarget 登记）
- `VerifierApplied(tokenAddress, actionId, memberId, round, applicationId)`：公共验证者申请
- `VerificationBatchSubmitted(tokenAddress, actionId, groupId, round, batchIndex, scores[])`：验证批次提交
- `VerifierLocked(tokenAddress, actionId, round, memberId)`：验证者锁定
- `ActionRewardMinted(tokenAddress, actionId, round, totalAmount, recipientType)`：行动激励铸造（recipientType 区分成员/验证者/owner）
- `ServiceRewardDistributed(serviceTokenAddress, serviceProposalId, actionTokenAddress, memberId, verifierReward, ownerReward, round)`：服务激励分配
- `SecondaryDistributionConfigured(serviceTokenAddress, serviceProposalId, actionId, groupId, round, recipientIds[], ratios[])`：二次分配配置

---

## 3. 错误

至少拒绝：零地址或 EOA Executor、非 ActionTarget 回调、重复初始化、KV 长度不等、无效 Round、非 MemberNFT 控制者、未投票 Proposal、非法参与量、体验额度不足、非法候选或分割线、候选申请已失效、验证批次跳跃/重复、锁定后更换验证者、重复铸造，以及服务非法超额分配导致的下溢。

**核心错误代码**：
- `InvalidExecutor()`：零地址、EOA 或无代码地址
- `UnauthorizedCallback()`：非 ActionTarget 调用 Executor 回调
- `NotMemberOwner(memberId)`：调用者不是该 MemberNFT 的当前持有人
- `ProposalNotVoted(tokenAddress, proposalId)`：Proposal 未获得投票或未达到激励门槛
- `InvalidRound(round)`：Round 不在当前允许的操作范围内（如在非加入阶段尝试加入）
- `InsufficientExperienceQuota(providerMemberId, required, available)`：体验额度不足
- `VerifierAlreadyLocked(tokenAddress, actionId, round)`：验证者已锁定，不能更换
- `BatchIndexMismatch(expected, actual)`：验证批次索引不连续
- `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)`：该成员在该 Round 的激励已铸造
- `DistributionOverflow(configured, available)`：二次分配配置的总比例超过可用激励
