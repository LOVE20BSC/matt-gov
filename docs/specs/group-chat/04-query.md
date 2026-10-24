# Round 与查询

## 群聊 Round

构造时接收 Phase 地址，`currentRound = phase.currentPhase()`，从 1 开始，与治理 Round 一对一。不独立维护 `originBlock` 和 `phaseBlocks`，也不按行动阶段偏移。Phase 地址有代码且 `Phase.ORIGIN_PHASE_BLOCKS() != 0` 是部署期静态不变量，由部署脚本在广播前校验（dev-standards §5.7）。

消息创建时记录的 Round 永久固定；后续配置变化不回写消息。

## 查询清单

以下接口保留旧 `LOVE20TKM/group-chat/src/interfaces/IGroupChat.sol` 的参数、返回类型和查询行为，删除地址主体参数及默认身份接口。GroupChat 列表查询支持 `offset`、`limit`、`reverse`；成员、委托、黑名单各自的分页签名沿用旧接口，不强加统一参数。

完整查询与写入 ABI 见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)，包含 Group/管理模块地址与构造注入的 `PHASE_ADDRESS()`；Phase 地址只作部署校核，轮次只通过 `currentRound()` 暴露，不提供 `originBlocks` / `phaseBlocks` 推导入口。

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
- 群不存在时相应群查询回滚 `GroupNotExist(groupId)`；有效群内单条 messageId 为 0 或超出消息数时回滚 `MessageNotFound(groupId, messageId)`。
- 空 Round 的数量为 0、消息数组为空，roundInfo 返回 `RoundSpan(round, 0, 0, 0)`；rounds 列表只枚举有消息的 Round。
- BSC 动态 Phase 下，`Message.round` 在发言时按 `phase.currentPhase()` 固定保存；后续校准不能重算旧消息。
- `messages*` 分页返回含 `string` / `uint256[]` 的 `Message[]`，是对旧 ABI 的保留，属 `dev-standards §4.3(2)` 的模块级例外；新增查询不得沿用该形态。

来源：旧 `LOVE20TKM/group-chat/src/GroupChat.sol` 的 `_pageCount`、`_pageIndex`、`_roundSpanOrEmpty`、`message`。验收见 [群聊验收](08-testing.md)。
