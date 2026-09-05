# Manager 和群组 Chat

本文档定义 Manager 合约机制和群组 Chat 的特殊规则。

---

## 1. Manager

**参考实现**：`LOVE20TKM/group-chat/TokenMainManager` 等

协议提供四类 typed Manager：`TokenMainManager`、`TokenGovManager`、`TokenActionMainManager` 和 `TokenActionGovManager`。

**关键设计**：
- Manager 创建并持有一个 MemberNFT
- 把该 `memberId` 作为 `groupId` 激活到同一个 `GroupChat` 合约
- 一次性注入规则模块
- 不创建独立 Chat 合约，不复制 MemberNFT、不创建治理状态、不改变行动状态

**行动 Chat 与 Proposal 的关联**（黑名单权重查询）：
- 每个行动 Manager 在创建时关联一个 `actionId`（对应 Core 的 Proposal ID）
- 行动 Chat 的黑名单投票通过查询 Manager 获得 `actionId`，再查询该 Proposal 的投票权重
- Manager 必须提供 `getActionId(groupId) returns (uint256 actionId)` 接口供黑名单源查询
- 一个代币社区可能有多个行动 Proposal，每个行动 Manager 关联不同的 `actionId`

**Chat 类型区分机制**：
Manager 通过注入不同的 `scopeSource` 和 `banSource` 实现类型区分。

**参考旧代码命名**：`LOVE20TKM/group-chat/src/sources/`
- Scope 实现：`GroupMemberScope`、`GroupJoinScopeSource`
- Ban 实现：`AdminBanSource`、`GovVotedBanSource`

Manager 在创建 Chat 时应发出事件，标注 Chat 类型。

---

## 2. 群组 Chat

**参考实现**：`LOVE20TKM/group-chat/GroupChat`（群组配置）

群组 Chat 不使用 Manager，由群组 owner 持有的 MemberNFT 直接作为 `groupId` 激活和管理。

**两个标准 scopeSource**：

**GroupMemberScope**：
- 只读取管理员维护的 `groupId -> memberId` 成员名单

**GroupActionScope**（新增）：
- 部署时接收 GroupChat 的成员集合查询接口和 Group Action Executor 地址作为构造参数
- Executor 必须是协议部署的标准 Group Action Executor
- 成员名单命中时直接允许
- 否则检查 `gTokenAddressesByGroupIdByMemberIdCount(groupId, senderId) > 0`
  （查询该成员在该群组 Executor 服务的所有 Group Action 中参与的代币社区数量）
- 该查询覆盖该 Executor 服务的所有代币社区和所有 Group Action

**Group Action Executor 是归属唯一依据**：
- Group Chat 不复制归属状态，也不遍历 ActionTarget
- 成员通过 Executor 正常退出其在该群组的最后一个行动后资格立即失效
- `forceExit` 只清除 ActionTarget 的通用参与登记，不修改 Executor 的资产或群组归属

**群组 owner 在激活时传入所需的 `scopeSource`、`banSource` 和插件；激活后，群组 owner 或有效 Group Chat Delegate 可以更新这些规则槽位。这与 Manager Chat 不同：Manager Chat 的规则槽位在激活时一次性注入且通常不提供重新配置接口。**
