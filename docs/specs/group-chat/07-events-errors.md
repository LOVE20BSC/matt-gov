# Group Chat 事件、错误与安全

## 事件

覆盖激活、发言开关、四个规则槽位、发言、提及、mention-all、after 插件失败、Delegate 设置/撤销、成员/管理员变化和 Manager 创建/激活。

配置事件应包含 `groupId`、新旧地址、操作 `memberId` 和调用地址；消息事件应包含 `groupId`、`senderId`、`senderAddress`、`round` 和 `messageId`。地址只用于审计，不作业务主体。

事件定义见 [`IGroupChat.sol`](../../../interfaces/group-chat/IGroupChat.sol)、[`IGroupChatDelegate.sol`](../../../interfaces/group-chat/IGroupChatDelegate.sol)、[`IGroupAdmin.sol`](../../../interfaces/group-chat/IGroupAdmin.sol)、[`IGroupMember.sol`](../../../interfaces/group-chat/IGroupMember.sol)、[`IGroupChatBanList.sol`](../../../interfaces/group-chat/IGroupChatBanList.sol)、[`IGovVotedBanSource.sol`](../../../interfaces/group-chat/IGovVotedBanSource.sol)、[`ITokenManager.sol`](../../../interfaces/group-chat/ITokenManager.sol) 和 [`IActionManager.sol`](../../../interfaces/group-chat/IActionManager.sol)。

## 错误

拒绝不存在的群或 sender、重复激活、越权管理、非 sender owner 发言、未激活、关闭发言、空或超长正文、提及超限/重复、无效引用、非法 mentionAll、无代码规则地址、scope/ban 拒绝和重入。

错误定义见 [`IGroupChat.sol`](../../../interfaces/group-chat/IGroupChat.sol)、[`IGroupChatDelegate.sol`](../../../interfaces/group-chat/IGroupChatDelegate.sol)、[`IGroupAdmin.sol`](../../../interfaces/group-chat/IGroupAdmin.sol)、[`IGroupMember.sol`](../../../interfaces/group-chat/IGroupMember.sol)、[`IGroupChatBanList.sol`](../../../interfaces/group-chat/IGroupChatBanList.sol)、[`IGovVotedBanSource.sol`](../../../interfaces/group-chat/IGovVotedBanSource.sol)、[`ITokenManager.sol`](../../../interfaces/group-chat/ITokenManager.sol) 和 [`IActionManager.sol`](../../../interfaces/group-chat/IActionManager.sol)。

## 安全

消息只增不改；配置和消息写入防重入；规则源、插件、Manager 不能越权修改核心状态；无升级管理员或隐含后门。

## 迁移规则

保留旧 `LOVE20TKM/group-chat/src/interfaces/` 中非地址主体功能的事件、错误名/参数和 indexed 字段；只对身份替换所影响的 operator/voter 参数改为 memberId，调用地址可继续作审计。删除默认身份和地址目标路径专属事件/错误，不新增一套平行行为。

保留 Activate、SetPostingAllowed、SetScopeSource、SetBanSource、SetBeforePostPlugin、SetAfterPostPlugin、PostMessage、MentionSenderId、MentionAll 和 FailAfterPostPlugin；后者 errorData 仍为捕获到的 bytes。scope/ban 的返回 false 和外部调用失败继续分别报 Rejected 与 SourceFailed，不能误改为静默放行。

验收见 [Group Chat 验收](08-testing.md)。
