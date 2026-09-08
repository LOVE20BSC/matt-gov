# Round 与查询

## 群聊 Round

构造时接收 Phase 地址，`currentRound = phase.currentPhase()`，从 1 开始，与治理 Round 一对一。不独立维护 `originBlock` 和 `phaseBlocks`，也不按行动阶段偏移。

消息创建时记录的 Round 永久固定；后续配置变化不回写消息。

## 查询清单

以下接口保留旧 `LOVE20TKM/group-chat/src/interfaces/IGroupChat.sol` 的参数、返回类型和查询行为，删除地址主体参数及默认身份接口。GroupChat 列表查询支持 `offset`、`limit`、`reverse`；成员、委托、黑名单各自的分页签名沿用旧接口，不强加统一参数。

```solidity
function MAX_CONTENT_LENGTH() external view returns (uint256);
function MAX_MENTIONED_SENDER_IDS() external view returns (uint256);
function activateChat(uint256 groupId, address scopeSource_, address banSource_, address beforePostPlugin_, address afterPostPlugin_) external;
function setPostingAllowed(uint256 groupId, bool postingAllowed_) external;
function setScopeSource(uint256 groupId, address sourceAddress) external;
function setBanSource(uint256 groupId, address sourceAddress) external;
function setBeforePostPlugin(uint256 groupId, address pluginAddress) external;
function setAfterPostPlugin(uint256 groupId, address pluginAddress) external;
function post(uint256 groupId, uint256 senderId, string calldata content, uint256[] calldata mentionedSenderIds, bool mentionAll, uint256 quotedMessageId) external;
function chatInfo(uint256 groupId) external view returns (ChatInfo memory);
function chatInfos(uint256[] calldata groupIds) external view returns (ChatInfo[] memory);
function postingAllowed(uint256 groupId) external view returns (bool);
function scopeSource(uint256 groupId) external view returns (address);
function banSource(uint256 groupId) external view returns (address);
function beforePostPlugin(uint256 groupId) external view returns (address);
function afterPostPlugin(uint256 groupId) external view returns (address);
function canPost(uint256 groupId, uint256 senderId) external view returns (bool allowed, bytes4 reasonCode);
function messagesCount(uint256 groupId) external view returns (uint256);
function messages(uint256 groupId, uint256 offset, uint256 limit, bool reverse) external view returns (Message[] memory);
function message(uint256 groupId, uint256 messageId) external view returns (Message memory);
function messagesByRoundCount(uint256 groupId, uint256 round) external view returns (uint256);
function messagesByRound(uint256 groupId, uint256 round, uint256 offset, uint256 limit, bool reverse) external view returns (Message[] memory);
function messagesBySenderCount(uint256 groupId, uint256 senderId) external view returns (uint256);
function messagesBySender(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse) external view returns (Message[] memory);
function messageIdsBySender(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory);
function messagesByMentionCount(uint256 groupId, uint256 mentionedSenderId) external view returns (uint256);
function messagesByMention(uint256 groupId, uint256 mentionedSenderId, uint256 offset, uint256 limit, bool reverse) external view returns (Message[] memory);
function messageIdsByMention(uint256 groupId, uint256 mentionedSenderId, uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory);
function messagesByMentionAllCount(uint256 groupId) external view returns (uint256);
function messagesByMentionAll(uint256 groupId, uint256 offset, uint256 limit, bool reverse) external view returns (Message[] memory);
function messageIdsByMentionAll(uint256 groupId, uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory);
function senderIdsCount(uint256 groupId) external view returns (uint256);
function senderIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory);
function groupIdsCount() external view returns (uint256);
function groupIds(uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory);
function currentRound() external view returns (uint256);
function roundsCount(uint256 groupId) external view returns (uint256);
function rounds(uint256 groupId, uint256 offset, uint256 limit, bool reverse) external view returns (RoundSpan[] memory);
function roundInfo(uint256 groupId, uint256 round) external view returns (RoundSpan memory);
```

| 范围 | 查询 |
| --- | --- |
| Chat 配置 | `chatInfo`、`chatInfos`、`postingAllowed`、四个规则地址 |
| 消息 | `messagesCount`、`message(groupId, messageId)`、分页 `messages` |
| Round | `messagesByRound`、`messagesByRoundCount`、`roundInfo`、`rounds` |
| sender | `messagesBySender`、`messagesBySenderCount`、`messageIdsBySender` |
| mention | `messagesByMention`、`messagesByMentionCount`、`messageIdsByMention` |
| mention-all | `messagesByMentionAll`、`messagesByMentionAllCount`、`messageIdsByMentionAll` |
| 发现 | `senderIds`、`senderIdsCount`、`groupIds`、`groupIdsCount`、`roundsCount` |

## 边界

- `limit == 0` 或 `offset >= total` 返回空数组；否则返回 `min(limit, total - offset)` 项。
- 正向索引为 `offset + i`，反向为 `total - 1 - offset - i`，ID 保持原值不重新编号。
- 群不存在时相应群查询回滚 GroupNotExist；有效群内单条 messageId 为 0 或超出消息数时回滚 InvalidMessageId。
- 空 Round 的数量为 0、消息数组为空，roundInfo 返回 `RoundSpan(round, 0, 0, 0)`；rounds 列表只枚举有消息的 Round。
- BSC 动态 Phase 下，`Message.round` 在发言时按 `phase.currentPhase()` 固定保存；后续校准不能重算旧消息。

来源：旧 `LOVE20TKM/group-chat/src/GroupChat.sol` 的 `_pageCount`、`_pageIndex`、`_roundSpanOrEmpty`、`message`。验收见 [群聊验收](08-testing.md)。
