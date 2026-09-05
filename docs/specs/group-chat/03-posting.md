# 发言机制

本文档定义 Chat 的发言流程、校验规则和插件处理。

---

## 1. 参数和基础校验

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

发言入口接收 `groupId`、`senderId`、`content`、`mentionedSenderIds`、`mentionAll` 和 `quotedMessageId`。

**校验顺序**：
1. `groupId` 对应的 MemberNFT 存在
2. Chat 已激活且 `postingAllowed = true`
3. `senderId` 对应的 MemberNFT 存在，且 `msg.sender` 是其当前 owner
4. `content` 非空，字节长度不超过 `MAX_CONTENT_LENGTH`（默认 `4096` bytes）
5. `mentionedSenderIds` 数量不超过 `MAX_MENTIONED_SENDER_IDS`（默认 `32`），每个 MemberNFT 存在且不重复
6. `mentionAll = true` 时，`senderId` 必须是该群 `groupId`、有效 `delegateId` 或有效 `adminId`
7. `quotedMessageId = 0` 表示无引用，非零时必须指向当前 Chat 已存在的消息
8. 按规则槽位顺序执行资格、黑名单和插件检查

---

## 2. 消息写入和插件

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

消息追加后分配新的 `messageId`，更新按 sender、mention、mention-all 和 round 的轻量索引，并发出 `PostMessage`。

**插件失败处理**：
- `beforePostPlugin` 回滚时，整笔发言回滚
- `afterPostPlugin` 在消息和通知事件写入后调用；其失败不会回滚消息，而是捕获错误并发出 `FailAfterPostPlugin(groupId, messageId, pluginAddress, round, errorData)`

---

## 3. canPost（预检查）

`canPost(groupId, senderId)` 只执行无内容预检查并返回 `(allowed, reasonCode)`；不要求查询调用者本人持有该 NFT，也不检查正文、提及、引用或 `beforePostPlugin`。
