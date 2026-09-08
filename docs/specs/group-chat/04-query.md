# Round 与查询

## 群聊 Round

构造时接收 Phase 地址，`currentRound = phase.currentPhase()`，从 1 开始，与治理 Round 一对一。不独立维护 `originBlock` 和 `phaseBlocks`，也不按行动阶段偏移。

消息创建时记录的 Round 永久固定；后续配置变化不回写消息。

## 查询清单

以下接口保留旧 `LOVE20TKM/group-chat/src/interfaces/IGroupChat.sol` 的参数、返回类型和查询行为。GroupChat 列表查询支持 `offset`、`limit`、`reverse`；成员、委托、黑名单各自的分页签名沿用旧接口，不强加统一参数。

| 范围 | 查询 |
| --- | --- |
| Chat 配置 | `chatInfo`、`chatInfos`、`postingAllowed`、四个规则地址 |
| 消息 | `messagesCount`、`message(groupId, messageId)`、分页 `messages` |
| Round | `messagesByRound`、`messagesByRoundCount`、`roundInfo`、`roundInfos`、`rounds` |
| sender | `messagesBySender`、`messagesBySenderCount`、`messageIdsBySender` |
| mention | `messagesByMention`、`messagesByMentionCount`、`messageIdsByMention` |
| mention-all | `messagesByMentionAll`、`messagesByMentionAllCount`、`messageIdsByMentionAll` |
| 发现 | `senderIds`、`senderIdsCount`、`groupIds`、`groupIdsCount`、`roundsCount` |

## 边界

- `limit == 0` 或 `offset >= total` 返回空数组；否则返回 `min(limit, total - offset)` 项。
- 正向索引为 `offset + i`，反向为 `total - 1 - offset - i`，ID 保持原值不重新编号。
- 群不存在时相应群查询回滚 GroupNotExist；有效群内单条 messageId 为 0 或超出消息数时回滚 InvalidMessageId。
- 空 Round 的数量为 0、消息数组为空，roundInfo 返回 `RoundSpan(round, 0, 0, 0)`；rounds 列表只枚举有消息的 Round。
- BSC 动态 Phase 下，Message.round 按发言时 Phase 固定保存或经不回写的历史 Phase 查询；不能用当前 phaseBlocks 重算旧消息。

来源：旧 `LOVE20TKM/group-chat/src/GroupChat.sol` 的 `_pageCount`、`_pageIndex`、`_roundSpanOrEmpty`、`message`。验收见 [群聊验收](08-testing.md)。
