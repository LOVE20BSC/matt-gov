# Group Chat 事件、错误与安全

## 事件

覆盖激活、发言开关、四个规则槽位、发言（含提及与 mention-all 标志）、after 插件失败、成员/管理员变化和 Manager 创建/激活。

配置事件应包含 `groupId`、新旧地址、操作 `memberId` 和调用地址；消息事件应包含 `groupId`、`messageId`、`senderId`（三者 indexed）、`sender`、`round` 与正文/引用字段。地址只用于审计，不作业务主体。

事件定义见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)、[`IGroupAdmin.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupAdmin.sol)、[`IGroupMember.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupMember.sol)、[`IGroupChatBanList.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatBanList.sol)、[`IGovVotedBanSource.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/sources/ban/IGovVotedBanSource.sol)、[`IManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IManagerBase.sol)、[`ITokenScopeManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/ITokenScopeManagerBase.sol) 和 [`ITokenActionScopeManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/ITokenActionScopeManagerBase.sol)。

## 错误

错误采用 local-first 模型：每个合约/模块只在自己的 `I<Name>Errors` 接口声明错误，不设中央枚举或全局错误接口，不跨仓导入错误。一个错误只对应一个条件；payload 由主体键和条件值组成，定长，不含字符串或数组。运行期地址检查（source/plugin、token 等）用 `*NotContract(address dependency)` / `TokenNotLOVE20(address tokenAddress)` 并携带失败地址；构造期依赖代码、参数与地址关系的静态校验由部署脚本在广播前完成（dev-standards §5.7），错误表只列运行期错误。OZ 标准错误按继承使用；只有不可达分支才用 `assert(false)`，不用裸 `require` / `revert` / 字符串。

| 模块 | 错误 |
| --- | --- |
| GroupChat 槽位 | `SourceNotContract(address dependency)`、`PluginNotContract(address dependency)` |
| GroupChat 状态与鉴权 | `GroupNotExist(uint256 groupId)`、`ChatAlreadyActivated(uint256 groupId)`、`ChatNotActivated(uint256 groupId)`、`PostingNotAllowed(uint256 groupId)`、`RoundNotStarted(uint256 requiredRound, uint256 currentRound)`、`NotGroupOwner(uint256 groupId)`、`NotGroupOperator(uint256 groupId, uint256 operatorId)`、`NotMemberOwner(uint256 memberId)`、`Reentrant()` |
| GroupChat 内容与规则 | `ContentEmpty()`、`ContentTooLong(uint256 length, uint256 maxLength)`、`TooManyMentionedSenderIds(uint256 length, uint256 maxLength)`、`DuplicateMemberId(uint256 memberId)`、`MessageNotFound(uint256 groupId, uint256 messageId)`、`QuotedMessageNotFound(uint256 groupId, uint256 messageId)`、`MentionAllUnauthorized(uint256 groupId, uint256 senderId)`、`ScopeRejected(uint256 groupId, uint256 senderId, address source)`、`BanRejected(uint256 groupId, uint256 senderId, address source)`、`ScopeSourceFailed(uint256 groupId, address source)`、`BanSourceFailed(uint256 groupId, address source)` |
| GroupAdmin | `NotGroupOperator(uint256 groupId, uint256 operatorId)`、`GroupNotExist(uint256 groupId)`、`DuplicateMemberId(uint256 memberId)`、`AdminIdsLimitExceeded(uint256 groupId, uint256 count, uint256 maxCount)` |
| GroupMember / GroupChatBanList | `NotGroupOperator(uint256 groupId, uint256 operatorId)`、`GroupNotExist(uint256 groupId)`、`ZeroTargetSenderId()`、`DuplicateMemberId(uint256 memberId)` |
| 内置 Scope/Ban Source | `GroupNotExist(uint256 groupId)`、`BanVoteWeightSourceUnavailable(uint256 groupId, address source)`、`ZeroTargetSenderId()`、`ZeroVoteWeight(uint256 groupId, uint256 voterId)`、`VoteUnchanged(uint256 groupId, uint256 targetSenderId, uint256 voterId)`、`VoteNotFound(uint256 groupId, uint256 targetSenderId, uint256 voterId)`、`NotMemberOwner(uint256 memberId)` |
| Manager | `AlreadyManaged(uint256 groupId)`、`ManagerGroupNameUnavailable()`、`ManagerMintCostChanged(uint256 expected, uint256 actual)`、`TokenNotLOVE20(address tokenAddress)`、`UnexpectedManagerERC721Received(address operator, address from, uint256 tokenId)`、`ActionNotExist(address tokenAddress, uint256 actionId)`；付款/授权失败走 OZ 标准 `SafeERC20FailedOperation(address token)` |

Group Chat 各接口不继承标准错误：`ownerOf` 的 `ERC721NonexistentToken` 按失败契约透传登记，来源 ABI 为 MemberNFT；Manager 的 `SafeERC20FailedOperation` 通过库进入 ABI，token 的 ERC20 标准错误由 token ABI 拥有。

存在性按角色区分：缺失群回 `GroupNotExist(groupId)`；缺失成员角色 ID（sender、member、admin、mention、voter）回 `ERC721NonexistentToken(id)`，成员/管理员的 `0` 值按缺失处理，都不借用 `GroupNotExist`。人工黑名单/GovVoted 的目标 sender 只要求非零，不要求 NFT 存在，见 [Chat 类型](05-chat-types.md#黑名单)。

所有权与操作者按角色区分：成员 NFT 所有权统一回 `NotMemberOwner(memberId)`（发言传 `senderId`，GovVoted voter 传 `voterId`）。群 owner 非 owner 回 `NotGroupOwner(groupId)`；owner/admin 的复合群鉴权回 `NotGroupOperator(groupId, operatorId)`。

数组内重复成员 ID 回 `DuplicateMemberId(memberId)`。

旧 `NotChatOwner`、`SenderNotGroupOwner`、`NotChatOwnerOrDelegateIdOwner`、`UnauthorizedGroup*Manager`、`DuplicateMentionedSenderId`、`DuplicateAdminId`、`DelegateIdCannotBeGroupId`、`TargetMemberIdZero`、`SenderNotMemberOwner(uint256)`、`SenderNotDelegateOwner()`、`DelegateIsSelfGroup(uint256)`、`DelegateNotAcceptingNewDelegations(uint256)` 已从接口删除；不得重新引入。旧 `InvalidAddress`、`*AddressHasNoCode`、`InvalidMessageId`、`InvalidQuotedMessageId` 及其它无区分度的旧错误名同样删除，不保留兼容别名。

视图行为：`is*` 谓词对缺失成员或群返回 false/0。GroupChat 的群作用域记录/枚举查询缺失群回 `GroupNotExist(groupId)`；成员名单、黑名单等模块的枚举查询按各自规格返回空/0。`canPost` 返回 `IGroupChat.PostRejectionReason` 封闭枚举，缺失 sender 返回 `SenderNotExist`、缺失群返回 `GroupNotExist`，不再以错误 selector 作数据，见[发言](03-posting.md#预检查)；不得据此扩展其它入口。

错误定义见 [`IGroupChat.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChat.sol)、[`IGroupAdmin.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupAdmin.sol)、[`IGroupMember.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupMember.sol)、[`IGroupChatBanList.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatBanList.sol)、[`IGovVotedBanSource.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/sources/ban/IGovVotedBanSource.sol)、[`IManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IManagerBase.sol)、[`ITokenScopeManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/ITokenScopeManagerBase.sol) 和 [`ITokenActionScopeManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/ITokenActionScopeManagerBase.sol)。

## 安全

消息只增不改；配置和消息写入防重入；规则源、插件、Manager 不能越权修改核心状态；无升级管理员或隐含后门。

## 命名与迁移规则

事件名按 `<Object><PastParticiple>` 统一，不沿用旧 `LOVE20TKM` 的 `Activate` / `Set*` / `PostMessage` 族；身份主体统一为 memberId，调用地址仅作审计。错误按本页的 local-first 模型命名并补齐 payload，不保留旧错误名或兼容别名。删除默认身份和地址目标路径专属事件/错误，不新增一套平行行为。

当前事件集：

- 激活与配置：`GroupChatActivated`（首次激活即写入初始 5 项配置：`postingAllowed`、`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`）、`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged`。配置变更保留 `prev*` 旧值；仅布尔取反可推的旧值省略。
- 消息：`MessagePosted`（带 `content`、`quotedMessageId` 与 `hasQuote`、`mentionAll` 与 `mentionedSenderCount`；indexed 为 `groupId`、`messageId`、`senderId`，`sender` 入 payload）、`SenderMentioned`（每提及一条，紧跟同消息的 `MessagePosted`、按入参顺序）、`AfterPostPluginFailed`（捕获型失败）。不再单设 `MentionAll`：mention-all 已并入 `MessagePosted.mentionAll`。
- 管理与成员：`AdminChanged`（已合并旧 `SetAdminSnapshot`，同时带 `listed`、`prevListed` 与新旧 `groupOwnerSnapshot`/`adminOwnerSnapshot`）、`MemberStatusChanged`。
- 黑名单：`SenderBanChanged`（管理员封禁列表）、`SenderBanVoteCast`（投票，带累计 `supportWeight`/`opposeWeight`）、`GovSenderBanChanged`（治理投票结果）。不设版本字段或版本事件：每次已结算变更都由这两条事实事件携带。
- Manager 链路：`TokenGroupActivated`（`tokenAddress`/`groupId`/`operator` indexed）、`TokenActionGroupActivated`（`tokenAddress`/`actionId`/`groupId` indexed，`operator` 入 payload）。

`AfterPostPluginFailed` 记录捕获错误的 `keccak256`、字节长度与首 4 字节 selector（`errorHash`、`errorLength`、`errorSelector`），不写入无界 `bytes`。scope/ban 的返回 false 和外部调用失败继续分别报 `ScopeRejected` / `BanRejected` 与 `ScopeSourceFailed` / `BanSourceFailed`，不能误改为静默放行。

`MessagePosted` 的两个派生锚点是有意冗余，按事件规范 §8.1 登记：`hasQuote` 与 `quotedMessageId != 0` 严格恒等，保留布尔是为了让消费方不必把 `0` 读作「不存在」（§3.6 的显式布尔）；`mentionedSenderCount` 与 `mentionedSenderIds.length` 同源，并等于该消息后续 `SenderMentioned` 的条数，使单条消息的提及列表长度不依赖「下一条 `MessagePosted` 之前」的区间约定。折叠规则：`SenderMentioned` 紧跟同 `messageId` 的 `MessagePosted` 且按入参顺序，`mentionedSenderIds` 由该区间内的 `SenderMentioned.mentionedSenderId` 顺序拼出，条数必须等于 `mentionedSenderCount`。

验收见 [Group Chat 验收](08-testing.md)。
