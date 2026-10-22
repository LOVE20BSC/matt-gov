# Group Chat 事件、错误与安全

## 事件

覆盖激活、发言开关、四个规则槽位、发言、提及、mention-all、after 插件失败、Delegate 设置/撤销、成员/管理员变化和 Manager 创建/激活。

配置事件应包含 `groupId`、新旧地址、操作 `memberId` 和调用地址；消息事件应包含 `groupId`、`senderId`、`senderAddress`、`round` 和 `messageId`。地址只用于审计，不作业务主体。

事件定义见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)、[`IGroupChatDelegate.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatDelegate.sol)、[`IGroupAdmin.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupAdmin.sol)、[`IGroupMember.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupMember.sol)、[`IGroupChatBanList.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatBanList.sol)、[`IGovVotedBanSource.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/sources/ban/IGovVotedBanSource.sol)、[`IBaseManager.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IBaseManager.sol)、[`IBaseTokenScopeManager.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IBaseTokenScopeManager.sol) 和 [`IBaseTokenActionScopeManager.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IBaseTokenActionScopeManager.sol)。

## 错误

拒绝不存在的群或成员、重复激活、越权管理、非 owner 发言、未激活、关闭发言、空或超长正文、提及超限/重复、无效引用、非法 mentionAll、无代码规则地址、scope/ban 拒绝和重入。

存在性按角色区分：缺失群回 `GroupNotExist()`；缺失成员角色 ID（sender、member、admin、delegate、mention、voter）回 `ERC721NonexistentToken(id)`，成员/管理员的 `0` 值按缺失处理，都不借用 `GroupNotExist()`。`delegateId = 0` 在 `setDelegateId` / `canSetDelegateTo` 中表示撤销或无委托，按[生命周期](01-lifecycle.md)处理，不按缺失回滚。人工黑名单/GovVoted 的目标 sender 只要求非零，不要求 NFT 存在，见 [Chat 类型](05-chat-types.md#黑名单)。所有权按角色区分：sender 发言非 owner 回 `SenderNotMemberOwner(senderId)`，delegate 写入口非 owner 回 `SenderNotDelegateOwner()`；GovVoted 的 voter 非 owner 回 `NotMemberOwner(voterId)`（接口新增，旧 `SenderNotMemberOwner` 保留但不再用于 voter，见 [CHANGES](../CHANGES-group-chat.md)）。delegate 查询缺失 ID 时按[生命周期](01-lifecycle.md)返回无 delegate，不回滚。

视图行为：`is*`/`can*` 谓词对缺失成员或 delegate 返回 false/0，delegate 枚举查询返回空且 total=0。GroupChat 与 GroupChatDelegate 的群作用域记录/枚举查询缺失群回 `GroupNotExist()`；成员名单、黑名单等模块的枚举查询按各自规格返回空/0。`canPost` 的 reasonCode 是旧 ABI 的封闭枚举例外，缺失 sender 仍返回 `GroupNotExist.selector`，见[发言](03-posting.md#预检查)；不得据此扩展其它入口。

错误定义见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)、[`IGroupChatDelegate.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatDelegate.sol)、[`IGroupAdmin.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupAdmin.sol)、[`IGroupMember.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupMember.sol)、[`IGroupChatBanList.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatBanList.sol)、[`IGovVotedBanSource.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/sources/ban/IGovVotedBanSource.sol)、[`IBaseManager.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IBaseManager.sol)、[`IBaseTokenScopeManager.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IBaseTokenScopeManager.sol) 和 [`IBaseTokenActionScopeManager.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IBaseTokenActionScopeManager.sol)。

## 安全

消息只增不改；配置和消息写入防重入；规则源、插件、Manager 不能越权修改核心状态；无升级管理员或隐含后门。

## 迁移规则

保留旧 `LOVE20TKM/group-chat/src/interfaces/` 中非地址主体功能的事件、错误名/参数和 indexed 字段；只对身份替换所影响的 operator/voter 参数改为 memberId，调用地址可继续作审计。删除默认身份和地址目标路径专属事件/错误，不新增一套平行行为。

保留 Activate、SetPostingAllowed、SetScopeSource、SetBanSource、SetBeforePostPlugin、SetAfterPostPlugin、PostMessage、MentionSenderId、MentionAll 和 FailAfterPostPlugin；后者 errorData 仍为捕获到的 bytes。scope/ban 的返回 false 和外部调用失败继续分别报 Rejected 与 SourceFailed，不能误改为静默放行。

验收见 [Group Chat 验收](08-testing.md)。
