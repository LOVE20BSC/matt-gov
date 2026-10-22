# 发言

## 校验顺序

发言入口接收 `groupId`、`senderId`、`content`、`mentionedSenderIds`、`mentionAll`、`quotedMessageId`，按以下顺序检查：

1. senderId 的 NFT 存在，且调用者为当前 owner（鉴权 modifier；缺失回 `ERC721NonexistentToken(senderId)`，非 owner 回 `SenderNotMemberOwner(senderId)`）。
2. groupId 的 NFT 存在。
3. Chat 已激活且 `postingAllowed = true`。
4. content 非空，字节数不超过 `MAX_CONTENT_LENGTH`，默认 4096。
5. 提及数不超过 `MAX_MENTIONED_SENDER_IDS`，默认 32；每个 NFT 存在（缺失回 `ERC721NonexistentToken(mentionedSenderId)`）且不重复。
6. mentionAll 为 true 时，sender 必须为群本身、有效 delegate 或有效 admin。
7. quotedMessageId 为 0 表示无引用；非零必须指向本 Chat 已存在消息。
8. 执行 [规则槽位](02-rules.md#顺序与例外) 的 scope、ban 和插件逻辑。

鉴权先于群状态检查：非持有人只拿到鉴权错误，不能借错误差异探测群是否存在或是否激活。

## 消息与插件

分配新 messageId，追加消息并更新 sender、mention、mention-all、round 索引，发出 `PostMessage` 及提及事件。

| 失败位置 | 结果 |
| --- | --- |
| beforePostPlugin | 整笔发言回滚 |
| afterPostPlugin | 消息与通知事件保留；捕获错误并发出 `FailAfterPostPlugin(groupId, messageId, pluginAddress, round, errorData)` |

after 插件在消息及通知事件之后调用。上述是业务容错要求，不代表无限 Gas 或任意错误数据都天然可安全捕获。

## 预检查

删除旧预检查中的 senderAddress 参数，调用方不必持有 sender NFT；写入时仍必须校验真实 msg.sender。

预检查接口见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)。

保留旧 reasonCode 的错误 selector 语义：成功返回 `(true, bytes4(0))`；失败返回 GroupNotExist、ChatNotActivated、PostingNotAllowed、ScopeRejected、BanRejected、ScopeSourceFailed 或 BanSourceFailed 的 selector。无内容预检查不验证正文、提及、引用或 before 插件。预检查不验证 sender 所有权；缺失 senderId 仍返回 `GroupNotExist` reasonCode，实际 `post` 写入路径按成员错误回滚（缺失回 `ERC721NonexistentToken`，非 owner 回 `SenderNotMemberOwner`）。该例外只适用于 `canPost` 的 reasonCode；`post` 写入路径和其它入口仍按成员角色错误回滚，不得据此扩展 `GroupNotExist`。

正文 4096 bytes、提及 32 个是旧公测 profile 的部署值，保留构造参数而非新增硬编码。错误和插件捕获机制沿用已核对的旧 GroupChat，不另设计恢复流程。身份接口和事件按 [迁移边界](00-overview.md#迁移边界) 适配，验收见 [群聊验收](08-testing.md)。
