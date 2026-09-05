# 生命周期和管理权限

本文档定义 Chat 的激活、管理操作和委托机制。

---

## 1. 激活

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

只有 `groupId` 当前 MemberNFT owner 可以调用 `activateChat`。激活前必须验证群 NFT 存在、Chat 尚未激活，且所有非零规则地址都有合约代码。

首次激活写入 `firstActivatedOwner`、首个区块和时间戳，并永久保留。激活默认 `postingAllowed = true`，设置初始四个规则槽位，并把 `groupId` 加入可发现群列表。

---

## 2. 管理操作

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

激活后，群 owner 或当前有效的 Group Chat Delegate 可以：
- 设置 `postingAllowed`
- 更新 `scopeSource`、`banSource`、`beforePostPlugin` 和 `afterPostPlugin`

**普通 owner Chat vs Manager Chat 的管理差异**：
- **普通 owner Chat**（如群组 Chat）：owner 持有 MemberNFT，可随时更新四个规则槽位
- **Manager Chat**（代币社区/治理/行动 Chat）：Manager 合约持有 MemberNFT，规则槽位在激活时一次性注入，Manager 通常不提供重新配置接口

---

## 3. Group Chat Delegate（限定范围）

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`（委托语义）

Group Chat Delegate 使用 NFT 委托语义：每个 `groupId` 最多设置一个 `delegateId`，并保留被委托群列表、委托方白名单开关和白名单分页查询。

**委托权限限定**（重要变更）：

**可以做**：
- 管理发言开关和四个规则槽位

**不可以做**：
- 不可以调用 `post` 代替其他 `senderId`
- 不可以获得治理票、质押权、发射次数、Action 验证权或任何群外权限

**委托失效**：
- 委托保存群和 delegate MemberNFT 的 owner 快照
- 任一 NFT 当前 owner 与快照不一致时委托失效
- 转回快照 owner 时可以自动恢复
- 原始记录和历史查询不因转移删除
