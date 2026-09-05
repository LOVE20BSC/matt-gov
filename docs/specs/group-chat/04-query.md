# Round 和查询接口

本文档定义 Chat 的 Round 机制和查询接口。

---

## 1. 群聊 Round

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

群聊 Round 是消息索引使用的时间编号，通过 Phase 合约获取当前治理 Round。GroupChat 合约部署时接收 Phase 合约地址作为构造参数，通过 `Phase.currentPhase()` 获取当前 Round，编号从 `1` 开始。Phase 与治理 Round 一对一映射，因此群聊 Round 与治理 Round 同步。

**查询方式**：
```solidity
currentRound = phase.currentPhase()
```

**注意**：群聊使用 Phase 合约来获取治理 Round，而非独立维护 `originBlock` 和 `phaseBlocks` 参数。

消息记录创建时的 Round 永久固定，即使后续调整 Chat 配置也不回写历史消息。

---

## 2. 查询接口

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

公开查询至少包括：
- 单个或批量 `chatInfo`
- `postingAllowed`、四个规则槽位地址
- `messagesCount`、`message(groupId, messageId)`
- 全量消息分页 `messages`
- 按 Round 的 `messagesByRound`、`messagesByRoundCount`、`roundInfo`、`roundInfos`、`rounds`
- 按 sender 的 `messagesBySender`、`messagesBySenderCount`、`messageIdsBySender`
- 按 mention 的 `messagesByMention`、`messagesByMentionCount`、`messageIdsByMention`
- 按 mention-all 的 `messagesByMentionAll`、`messagesByMentionAllCount`、`messageIdsByMentionAll`
- Chat 内出现过的 `senderIds`
- 所有曾激活 Chat 的 `groupIds`

所有列表查询支持 `offset`、`limit` 和 `reverse`。
