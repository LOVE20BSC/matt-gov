# Group Action 执行合约

本文档定义 Group Action 执行合约规格。

---

## 1. 保留逻辑（引用旧代码）

### 1.1 17 组全局索引

**完全保留**：`LOVE20TKM/action/GroupAction` 的索引结构

Group Action Executor 以当前有效的 `tokenAddress + actionId + groupId + memberId` 参与关系为事实来源。必须维护下列 17 组跨其所有代币社区和 Group Action 的可枚举全局索引：

- **Group ID**：`gGroupIds`、`gGroupIdsByMemberId`、`gGroupIdsByTokenAddress`、`gGroupIdsByTokenAddressByMemberId`、`gGroupIdsByTokenAddressByActionId`
- **Token Address**：`gTokenAddresses`、`gTokenAddressesByMemberId`、`gTokenAddressesByGroupId`、`gTokenAddressesByGroupIdByMemberId`
- **Action ID**：`gActionIdsByTokenAddress`、`gActionIdsByTokenAddressByMemberId`、`gActionIdsByTokenAddressByGroupId`、`gActionIdsByTokenAddressByGroupIdByMemberId`
- **Member ID**：`gMemberIds`、`gMemberIdsByGroupId`、`gMemberIdsByTokenAddress`、`gMemberIdsByTokenAddressByGroupId`

每组索引都提供同名全量数组查询、追加 `Count` 的数量查询和追加 `AtIndex` 的单项查询。

**设计理由**：Group Action Executor 需支持跨社区和跨行动的全局查询（如"某成员参与的所有群组"、"某群组在所有社区的行动"、"某代币社区的所有群组"），因此维护多维度的可枚举索引。索引在加入/退出时同步更新，查询时无需扫描历史事件。

### 1.2 按 Round 参与历史

**参考**：`LOVE20TKM/action/GroupAction` 的历史快照机制

Group Action Executor 通过加入阶段内逐笔发生的加入、追加、体验加入、部分撤回和全部退出交易，自然形成每轮参与快照。同一 Round 内的多笔交易持续更新该 Round 的最终值，不为同一 Round 重复创建版本。整轮无人交互时自然继承上一轮状态，不需要复制或同步交易。

**实现机制**：加入阶段内的每笔交易直接写入该 Round 的参与记录（`mapping(round => mapping(groupId => mapping(memberId => ParticipationData)))`）；查询时，若某 Round 无记录则回退查找上一轮记录，实现懒继承。退出时清除当前 Round 的记录，自然形成该 Round "未参与"的状态。

### 1.3 公共验证者机制

**参考**：`LOVE20TKM/action/GroupAction` 的候选申请、排名、分割线开放

候选申请只在投票阶段新增、撤销或修改。排名按累计候选票降序、`applicationId` 升序。分割线开放公式：
```text
openOffset = ceil(verifyPhaseBlocks × splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

**排名规则细节**：
- 排名依据：累计候选票（candidateVotes）降序为主序，applicationId 升序为次序
- 平票处理：candidateVotes 相同时，applicationId 较小的排名靠前（较早申请的优先）
- splits 数组长度为 `n-1`（n 为候选人数），`splits[0]` 对应第 2 名的开放时间占比
- 第 1 名在验证阶段开始时立即开放（openBlock = verifyPhaseStartBlock）
- 第 2 名及之后按 splits 数组计算开放时间，分段释放验证权限以激励候选竞争

### 1.4 激励计算

**参考**：`LOVE20TKM/action/GroupAction`

**变量定义**：
- `groupScore` = 该群组在该行动 Round 中的激励分配权重（所有成员的激励分配权重之和）
- `totalGroupScore` = 该行动 Round 中所有群组的激励分配权重总和
- `memberScore` = 该成员在该群组、该行动 Round 中的激励分配权重（该成员参与代币数量 × 原始验证得分）

**验证得分说明**：由公共验证者在验证阶段为每个成员评定（0-100），记录为 `originScore`；`memberScore = 参与代币数量 × originScore`。群组激励计算使用 originScore 结合参与代币数量，保持公平性。

**公式**：
```text
groupReward = proposalReward × groupScore / totalGroupScore
memberReward = groupReward × memberScore / groupScore
```

其中 `groupScore` 和 `memberScore` 基于验证阶段确认的参与数据计算。

---

## 2. 关键变更

### 2.1 主体身份

- **旧**：`groupId` 可以是地址或 MemberNFT
- **新**：`groupId` 必须是 `memberId`，群组 owner 就是该 MemberNFT

### 2.2 阶段模型

- **旧**：固定 4 阶段
- **新**：从 Core Phase 自行映射 4 阶段

### 2.3 激励铸造

- **旧**：逐人调用 Core Mint
- **新**：Executor 通过 ActionTarget 一次性铸造整个 Proposal 激励，再内部分配
