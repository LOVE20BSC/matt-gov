# Round 与查询

## 群聊 Round

构造时接收 Phase 地址，`currentRound = phase.currentPhase()`，从 1 开始，与治理 Round 一对一。不独立维护 `originBlock` 和 `phaseBlocks`，也不按行动阶段偏移。Phase 地址有代码且 `Phase.ORIGIN_PHASE_BLOCKS() != 0` 是部署期静态不变量，由部署脚本在广播前校验（dev-standards §5.7）。

消息创建时记录的 Round 永久固定；后续配置变化不回写消息。

## 查询清单

以下接口保留旧 `LOVE20TKM/group-chat/src/interfaces/IGroupChat.sol` 的查询行为，删除地址主体参数及默认身份接口。集合查询统一按 `(offset, limit, reverse)` 分页并同时返回集合真实总数；不设计数入口，只取总数时传 `limit = 0`。

完整查询与写入 ABI 见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)，包含 Group/管理模块地址与构造注入的 `PHASE_ADDRESS()`；Phase 地址只作部署校核，轮次只通过 `currentRound()` 暴露，不提供 `originBlocks` / `phaseBlocks` 推导入口。

| 范围 | 查询 |
| --- | --- |
| Chat 配置 | `chatInfo`、`chatInfosByGroupIds`、`isPostingAllowed`、四个规则地址 |
| 消息 | `message(groupId, messageId)`、分页 `messages` |
| Round | `messagesByRound`、`roundInfo`、`roundInfosByRounds`、`rounds` |
| sender | `messagesBySenderId`、`messageIdsBySenderId` |
| mention | `messagesByMentionedSenderId`、`messageIdsByMentionedSenderId` |
| mention-all | `mentionAllMessages`、`mentionAllMessageIds` |
| 发现 | `senderIds`、`groupIds` |

## 分页

GroupChat 的 11 个集合查询都是 `(作用域键 → offset → limit → reverse) → (列表, totalCount)`，语义同 `IPhase.observations`：

- `offset` 大于或等于总数时返回空数组与真实 `totalCount`，不校验也不回滚。
- `limit` 为 0 时返回空数组与真实 `totalCount`，这是取基数的唯一入口。
- `limit` 大于剩余条数时按剩余条数返回。
- `reverse` 为 `true` 时逆序遍历当前存储顺序。消息、sender、mention、mention-all、Round 五个集合只追加不删除，`reverse` 即插入逆序。

## 边界

- `chatInfosByGroupIds(requestedGroupIds)` 按入参下标对齐返回，任一 groupId 不存在即整笔回滚 `GroupNotExist(groupId)`，不跳过、不补空（`dev-standards §4.3(7)`）。
- 正向索引为 `offset + i`，反向为 `totalCount - 1 - offset - i`，ID 保持原值不重新编号。
- 群不存在时相应群查询回滚 `GroupNotExist(groupId)`；有效群内单条 messageId 为 0 或超出消息数时回滚 `MessageNotFound(groupId, messageId)`。
- 空 Round 的总数为 0、消息数组为空，roundInfo 返回 `RoundSpan(round, 0, 0, 0)`；rounds 列表只枚举有消息的 Round。
- BSC 动态 Phase 下，`Message.round` 在发言时按 `phase.currentPhase()` 固定保存；后续校准不能重算旧消息。
- `messages*` 分页返回含 `string` / `uint256[]` 的 `Message[]`，是对旧 ABI 的保留，属 `dev-standards §4.3(2)` 的模块级例外；新增查询不得沿用该形态。

来源：旧 `LOVE20TKM/group-chat/src/GroupChat.sol` 的 `_pageCount`、`_pageIndex`、`_roundSpanOrEmpty`、`message`。验收见 [群聊验收](08-testing.md)。
