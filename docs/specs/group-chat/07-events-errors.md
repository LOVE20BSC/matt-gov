# Group Chat 事件、错误与安全

## 事件

覆盖激活、发言开关、四个规则槽位、发言、提及、mention-all、after 插件失败、Delegate 设置/撤销、成员/管理员变化和 Manager 创建/激活。

配置事件应包含 `groupId`、新旧地址、操作 `memberId` 和调用地址；消息事件应包含 `groupId`、`senderId`、`senderAddress`、`round` 和 `messageId`。地址只用于审计，不作业务主体。

```solidity
event Activate(uint256 indexed groupId, uint256 indexed ownerId, address indexed owner);
event SetPostingAllowed(uint256 indexed groupId, uint256 indexed operatorId, address indexed operator, bool postingAllowed);
event SetScopeSource(uint256 indexed groupId, address indexed sourceAddress, uint256 operatorId, address operator, address prevSourceAddress);
event SetBanSource(uint256 indexed groupId, address indexed sourceAddress, uint256 operatorId, address operator, address prevSourceAddress);
event SetBeforePostPlugin(uint256 indexed groupId, address indexed pluginAddress, uint256 operatorId, address operator, address prevPluginAddress);
event SetAfterPostPlugin(uint256 indexed groupId, address indexed pluginAddress, uint256 operatorId, address operator, address prevPluginAddress);
event PostMessage(uint256 indexed groupId, uint256 indexed senderId, address indexed senderAddress, uint256 round, uint256 messageId);
event MentionSenderId(uint256 indexed groupId, uint256 indexed mentionedSenderId, uint256 messageId);
event MentionAll(uint256 indexed groupId, uint256 messageId);
event FailAfterPostPlugin(uint256 indexed groupId, uint256 indexed messageId, address indexed pluginAddress, uint256 round, bytes errorData);
event SetDelegateId(uint256 indexed groupId, address indexed owner, uint256 indexed delegateId, uint256 prevDelegateId);
event ClearDelegatedGroupId(uint256 indexed groupId, uint256 indexed delegateId, address indexed delegateOwner);
event SetDelegatorWhitelistEnabled(uint256 indexed delegateId, address indexed delegateOwner, bool enabled);
event SetAllowedDelegatorGroupId(uint256 indexed delegateId, uint256 indexed groupId, address indexed delegateOwner, bool allowed);
event SetAdmin(uint256 indexed groupId, address indexed operator, uint256 indexed adminId, uint256 operatorId, bool listed);
event SetMemberId(uint256 indexed groupId, address indexed operator, uint256 indexed memberId, uint256 operatorId, bool listed);
event SetSenderIdBan(uint256 indexed groupId, address indexed operatorAddress, uint256 indexed targetSenderId, uint256 operatorId, bool listed);
```

## 错误

```solidity
error AlreadyInitialized();
```

拒绝不存在的群或 sender、重复激活、越权管理、非 sender owner 发言、未激活、关闭发言、空或超长正文、提及超限/重复、无效引用、非法 mentionAll、无代码规则地址、scope/ban 拒绝和重入。

```solidity
error GroupNotExist();
error ChatAlreadyActivated();
error ChatNotActivated();
error PostingNotAllowed();
error NotChatOwner();
error NotChatOwnerOrDelegateIdOwner();
error SenderAddressNotSenderIdOwner();
error RoundNotStarted();
error Reentrant();
error PhaseBlocksZero();
error MaxContentLengthZero();
error SourceAddressHasNoCode();
error PluginAddressHasNoCode();
error ContentEmpty();
error ContentTooLong(uint256 length, uint256 maxLength);
error TooManyMentionedSenderIds(uint256 length, uint256 maxLength);
error DuplicateMentionedSenderId();
error InvalidQuotedMessageId();
error InvalidMessageId();
error MentionAllUnauthorized();
error ScopeRejected();
error BanRejected();
error ScopeSourceFailed();
error BanSourceFailed();
error InvalidAddress();
error SenderNotGroupOwner();
error SenderNotDelegateOwner();
error DelegatorGroupIdNotAllowed();
error DelegateIdCannotBeGroupId();
error DuplicateAdminId();
error AdminIdsLimitExceeded();
error TargetMemberIdZero();
error TargetSenderIdZero();
error SenderPairLengthMismatch();
error ManagerAddressHasNoCode();
error AlreadyManaged();
error RecentRoundsZero();
error ManagerGroupNameUnavailable();
error ManagerMintCostChanged();
error ManagerPaymentFailed();
error ManagerApprovalFailed();
error TokenNotLOVE20();
error UnexpectedManagerERC721Received();
error ActionIdNotExist();
```

## 安全

消息只增不改；配置和消息写入防重入；规则源、插件、Manager 不能越权修改核心状态；无升级管理员或隐含后门。

## 迁移规则

保留旧 `LOVE20TKM/group-chat/src/interfaces/` 中非地址主体功能的事件、错误名/参数和 indexed 字段；只对身份替换所影响的 operator/voter 参数改为 memberId，调用地址可继续作审计。删除默认身份和地址目标路径专属事件/错误，不新增一套平行行为。

保留 Activate、SetPostingAllowed、SetScopeSource、SetBanSource、SetBeforePostPlugin、SetAfterPostPlugin、PostMessage、MentionSenderId、MentionAll 和 FailAfterPostPlugin；后者 errorData 仍为捕获到的 bytes。scope/ban 的返回 false 和外部调用失败继续分别报 Rejected 与 SourceFailed，不能误改为静默放行。

验收见 [Group Chat 验收](08-testing.md)。
