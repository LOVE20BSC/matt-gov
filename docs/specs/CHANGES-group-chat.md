# Group Chat 迁移差异

用户确认：群聊几乎原样迁移，功能、流程、查询和失败行为保持；业务身份统一为 MemberNFT，删除地址主体平行路径，NFT 代理仅作用于群聊。

## 错误模型 v3（2026-10-24）

Group Chat 已全部改为 **local-first** 错误模型：每个合约/模块拥有自己的 `I<Name>Errors`，不设中心枚举、不跨仓导入错误。

- 地址/依赖：`InvalidAddress` 拆为具体依赖错误；必填合约依赖以“有代码”为条件，零地址与非零 EOA 统一回 `*NotContract(address)`（零地址为 `*NotContract(0)`），payload 带失败地址。
- 状态：`ChatAlreadyActivated(groupId)`、`ChatNotActivated(groupId)`、`PostingNotAllowed(groupId)`；`RoundNotStarted(requiredRound,currentRound)` 与 Core/Action 同签名。
- 消息/提及/引用：`Name` 类错误按字段拆分；`MessageNotFound(groupId,messageId)`、`QuotedMessageNotFound(groupId,messageId)`、`MentionAllUnauthorized(groupId,senderId)`。
- 规则源：`ScopeRejected(source,groupId,senderId)`、`BanRejected(source,groupId,senderId)`、`ScopeSourceFailed(source)`、`BanSourceFailed(source)`。
- Delegate：`DelegatorGroupIdNotAllowed(groupId,delegateId)`；`setDelegateId` 先校验再幂等返回，不再吞掉非法请求。
- 批量与构造：GroupMember / GroupChatBanList 的数组内重复 ID 回 `DuplicateMemberId(memberId)`，与 GroupAdmin、提及、接收人一致；构造依赖零值与非零 EOA 统一回 `*NotContract(address)`，不再保留零值专项错误。
- `canPost`：返回封闭 `PostRejectionReason` 枚举，不再把错误 selector 当业务数据；缺失 sender 返回 `SenderNotExist`。
- Manager/GovVoted：Manager 必填依赖无代码（含零地址）统一回 `ManagerDependencyNotContract(dependency)`；`AlreadyManaged(groupId)`、`VoteUnchanged/VoteNotFound`、`BanVoteWeightSourceUnavailable(source)` 等带主体；GovVoted 写路径对缺失群回 `GroupNotExist(groupId)`、群存在但权重源无代码回 `BanVoteWeightSourceUnavailable(source)`；Manager 付款/授权走 OZ `SafeERC20FailedOperation(token)`；`FailAfterPostPlugin` 改为 `errorHash + errorLength + errorSelector`，不再写无界 `bytes`。
- `MemberOwner.ofOrZero`：只把 `ERC721NonexistentToken` 转成 0，其余 revert 原样冒泡。
- ABI：各接口默认不继承标准错误；`ownerOf` 的 `ERC721NonexistentToken` 按失败契约登记，来源 ABI 为 MemberNFT；`SafeERC20FailedOperation` 通过库进入 Manager ABI，token 的 ERC20 标准错误由 token ABI 拥有。
- Manager 构造：必填依赖无代码（含零地址）统一回 `ManagerDependencyNotContract(dependency)`。

Group Chat 门禁：**148 tests 全绿**；`build --deny warnings`、`lint`、`check_caller_auth.sh` 通过。本文档历史小节里的旧错误名均已被 v3 名称取代。

## 来源

- `LOVE20TKM/group-chat`：`LOVE20TKM/group-chat/src/GroupChat.sol`、`LOVE20TKM/group-chat/src/GroupAdmin.sol`、`LOVE20TKM/group-chat/src/GroupMember.sol`、`LOVE20TKM/group-chat/src/GroupBanList.sol`、`LOVE20TKM/group-chat/src/managers/`、`LOVE20TKM/group-chat/src/sources/`、`LOVE20TKM/group-chat/src/interfaces/`。
- `LOVE20TKM/group`：`LOVE20TKM/group/src/GroupDelegate.sol`、`LOVE20TKM/group/src/interfaces/IGroupDelegate.sol`。
- 本轮核对的是干净本地源码。实际迁移仍须冻结部署证明；不得修改旧组织。

## 变更边界

| 组件 | 保留 | BSC 必要修改 |
| --- | --- | --- |
| GroupChat | 一 NFT 一 Chat、激活、四槽位、消息、提及、引用、索引、分页、插件失败处理 | 依赖改 MemberNFT；删除 postAsDefaultSender 和 GroupDefaults；预检查不再接收业务地址；mentionAll 与 scope/ban 直通改按 `senderId` 判定（旧按调用者地址） |
| GroupAdmin | NFT 管理员、双 owner 快照、数量限制、转移失效/转回恢复 | 删除默认身份查找，操作显式给 adminId |
| GroupMember / GroupBanList | ID 集合、批量增删、枚举、权限和事件行为 | 删除地址黑名单及地址/ID 双轨路径 |
| GovVotedBanSource | 双阈值、settledWeight、改票/撤票/刷新、stateVersion、已结算名单 | voter 和 target 均用 memberId，删除地址目标及对应索引/事件 |
| typed Manager | 激活者付款、Manager 持有 NFT、单实例管理多个 Chat、不重配、不转出、命名和查询 | 新 Core 接口；资格由 memberId 查询，不重新设计付款或恢复机制 |
| GroupMemberScope / GroupJoinScopeSource | 名单或当前链群归属 | 将 GroupJoin 地址查询替换为链群 Executor 的 memberId 查询 |
| Group Chat Delegate | NFT 委托、白名单、反向枚举、双 owner 快照 | 实现归 group-chat，只供群聊管理；Core/Action/Launch 不使用 |
| 时间适配 | 消息 Round 永久稳定、按 Round 查询 | 已确认使用共享 Phase；历史消息不可用新的 phaseBlocks 重算 |

不得误删付款钱包、合约地址、owner 快照、调用地址审计或标准 ERC721 回调字段；它们不是业务身份。

## 纠正此前未经核验的表述

- 旧 GroupChat 已是一 NFT 一 Chat，Manager 已激活同一个 GroupChat，不是“可能独立创建 Chat”。
- 旧 TokenMainManager 的持币阈值是严格大于 1 个最小单位；2026-10-19 决策改为 **任一非零余额即满足**（`> 0`），规格 [05-chat-types.md](group-chat/05-chat-types.md) 与实现同步更新。
- 旧行动黑名单读取当前 Vote Round 的行动票权，分母为全社区当前治理票；不固定在 Proposal 创建 Round。
- 旧 GroupDelegate 实现在 group 仓库；迁到 group-chat 并限制消费者，不是给全局 MemberNFT 添加授权。
- 旧群内委托还可以管理管理员、成员和人工黑名单，不能被精简为“只能改开关与槽位”。
- forceExit 只移除一个资格分支，不能推导为所有 Chat 资格立即失效。

## ABI 对账（函数 / 事件 / 错误）

对账口径：自有声明（group-chat `src/interfaces/`），不含从标准依赖继承的成员。旧侧为 `LOVE20TKM` 群聊接口。

### GroupChat（`IGroupChat.sol`）

| 层 | 保留 | 改参 | 新增 | 删除 |
| --- | --- | --- | --- | --- |
| 函数 | `currentRound()`、三个地址 getter、两个上限 getter、`activateChat`、`post`、`chatInfo(s)`、五个槽位 getter、`messages*` / `message` / `messagesBy*` / `messageIds*` / `senderIds` / `groupIds` / `rounds` / `roundInfo(s)` | `canPost(uint256,uint256,address)` → `canPost(uint256,uint256)`；五个配置 setter 各增 `uint256 operatorId` | `PHASE_ADDRESS()` | `originBlocks()` / `phaseBlocks()`、`postAsDefaultSender(...)`、`GROUP_DEFAULTS_ADDRESS()` |
| 事件 | `PostMessage` / `MentionSenderId` / `MentionAll` / `FailAfterPostPlugin` | 五个配置事件各增 `uint256 indexed operatorId`；`Activate(uint256,address)` → `Activate(uint256,uint256,address)` | — | — |
| 错误 | `GroupNotExist` / `ChatAlreadyActivated` / `ChatNotActivated` / `PostingNotAllowed` / `RoundNotStarted` / `Reentrant` / `ZeroPhaseBlocks` / `ZeroMaxContentLength` / `SourceNotContract` / `PluginNotContract` / `ContentEmpty` / `ContentTooLong` / `TooManyMentionedSenderIds` / `QuotedMessageNotFound` / `MessageNotFound` / `GroupAdminNotContract` / `GroupDelegateNotContract` / `MentionAllUnauthorized` / `ScopeRejected` / `BanRejected` / `ScopeSourceFailed` / `BanSourceFailed` | `SenderAddressNotSenderIdOwner()` → `NotMemberOwner(uint256 memberId)`；`GroupNotExist()` → `GroupNotExist(uint256 groupId)`；`GroupDelegateGroupMismatch()` → `GroupAddressMismatch(address expected, address actual)` | `PhaseNotContract(address dependency)`、`ZeroMaxMentionedSenderIds()`、`NotGroupOwner(uint256 groupId)`、`NotGroupOperator(uint256 groupId, uint256 operatorId)`、`DuplicateMemberId(uint256 memberId)` | `DefaultGroupIdNotSet()` / `GroupDefaultsHasNoCode()` / `GroupDefaultsGroupMismatch()` |

构造签名 `(groupAdmin, originBlocks, phaseBlocks, maxContentLength, maxMentionedSenderIds)` → `(groupAdmin, phaseAddress, maxContentLength, maxMentionedSenderIds)`；`currentRound()` 签名保留，语义改为直接映射 Phase（Phase 前回滚 `RoundNotStarted`，从 1 起）；`Message.round` 由发言时的 Phase 轮次固定（[04-query.md](group-chat/04-query.md)）。缺失成员角色 ID（sender/member/admin/delegate/mention/voter）回 `ERC721NonexistentToken(id)`；非 owner 的发言/delegate 写入口回 `NotMemberOwner(senderId)` / `NotMemberOwner(delegateId)`；GovVoted 的 voter 非 owner 回 `NotMemberOwner(voterId)`；群 owner 非 owner 回 `NotGroupOwner(groupId)`，owner/delegate/admin 复合鉴权回 `NotGroupOperator(groupId, operatorId)`；数组内重复成员回 `DuplicateMemberId(memberId)`；delegate 查询缺失 delegate 返回 false/0/空，不回滚；缺失群回 `GroupNotExist(groupId)`。旧 `NotChatOwner` / `NotChatOwnerOrDelegateIdOwner` / `DuplicateMentionedSenderId` / `SenderNotMemberOwner` / `SenderNotDelegateOwner` 已删除。

### GroupAdmin / GroupMember

| 接口 | 改参 | 新增 | 删除 |
| --- | --- | --- | --- |
| `IGroupAdmin` | `addAdmins` / `removeAdmins` 各增 `uint256 operatorId`；构造删 `groupDefaults` 参 | — | `GROUP_DEFAULTS_ADDRESS()`、`adminIdOf(uint256,address)`、`ownerOrDelegateIdOf(uint256,address)`、错误 `GroupDelegateGroupMismatch()`（新名 `GroupAddressMismatch(address expected, address actual)`，由 `IGroupChat` 承载） |
| `IGroupMember` | `addMemberIds` / `removeMemberIds` 各增 `uint256 operatorId` | — | — |

错误：缺失成员/管理员（含 `0`）回 `ERC721NonexistentToken`；缺失群回 `GroupNotExist(groupId)`；群操作者鉴权回 `NotGroupOperator(groupId, operatorId)`；重复管理员回 `DuplicateMemberId(memberId)`。`TargetMemberIdZero`、`UnauthorizedGroup*Manager`、`DuplicateAdminId` 已删除。

### GroupChatBanList（原 `IGroupBanList`）

- **改名**：合约 `GroupBanList` → `GroupChatBanList`；接口同名改名；错误 `GroupBanListAddressHasNoCode` 保留原名（selector 不变）
- **改参**：`banBySenderIds` / `unbanBySenderIds` 各增 `uint256 operatorId`
- **新增**：`isSenderIdBannedBatch(uint256,uint256[])`；错误 `NotGroupOperator(uint256,uint256)`
- **删除**：地址名单一整套（`banBySenderAddresses` / `unbanBySenderAddresses` / `banBySenders` / `unbanBySenders` / `isAddressBanned` / `addressBanDetails` / `addressBanList(Count)` / `isBanned(uint256,uint256,address)`）、错误 `TargetAddressZero` / `SenderPairLengthMismatch`、事件 `SetAddressBan`

### GroupChatDelegate（原 `IGroupDelegate`）

- **改名**：合约与接口 `GroupDelegate` → `GroupChatDelegate`；`InvalidAddress()` 等错误与四个事件保留
- **删除**：`isOwnerOrDelegate(uint256,address)`；等价判断由 `ownerOrDelegateIdOf(...) != 0` 表达，`delegateIdOf` / `delegateIdsOf` 已覆盖「有效 delegate 查询」
- **错误**：写入口缺失 delegateId 回 `ERC721NonexistentToken`；非 owner 回 `NotMemberOwner(delegateId)`；查询缺失 delegate 返回 false/0/空，不回滚；群 owner 非 owner 回 `NotGroupOwner(groupId)`；`delegateId == groupId` 回 `DelegateIsSelfGroup(groupId)`；`GroupNotExist(groupId)` 只用于群角色。旧 `SenderNotGroupOwner` / `DelegateIdCannotBeGroupId` / `SenderNotDelegateOwner` 已删除

### Manager 三接口

- **改参**：四个 Manager 构造 `extensionCenter_` → `actionTarget_`；`banSource_` 由激活参数提前为构造参数
- **删除**：`IBaseManager.EXTENSION_CENTER_ADDRESS()`
- **移动**：`ActionIdNotExist()` 由 `IBaseManager` 移至 `IBaseTokenActionScopeManager`（selector 不变）
- **可见性**：`tokenOfGroup` / `groupIdOfToken` / `actionOfGroup` / `groupIdOfAction` 由 `public` 存储改为 `internal` + 显式 getter（selector 不变）
- **入参名**：批量入参在接口与实现统一为 `_` 后缀，与 `postingAllowed_` 同例，规避与同名 getter 的声明遮蔽（solc 8760）：`addAdmins` / `removeAdmins` 的 `adminIds_`、`addMemberIds` / `removeMemberIds` / `isMemberIdBatch` 的 `memberIds_`、`chatInfos` 的 `groupIds_`、`roundInfos` 的 `rounds_`
- **新增**：错误 `ManagerGroupNameSpaceTooSmall()`；MemberNFT `MAX_NAME_LENGTH < 17`（1 字节分隔符 + 12 位十六进制后缀 + 4 字节 Test 前缀）时 Manager 构造回滚

### 资格与黑名单源

| 接口 | 变更 |
| --- | --- |
| `IPostScopeSource` | `canPost(uint256,uint256,address)` → `canPost(uint256,uint256)` |
| `IPostBanSource` | `isBanned(uint256,uint256,address)` → `isBanned(uint256,uint256)` |
| `IBanVoteWeightSource` | `voteWeightOf(uint256,address)` → `voteWeightOf(uint256,uint256)` |
| `IGroupJoinScopeSource` | `GROUP_JOIN_ADDRESS()` → `GROUP_ACTION_EXECUTOR_ADDRESS()`；成员判定改 `IGroupActionIndexes.isGroupMember(groupId, senderId)` |
| `IAdminBanSource` / `IGroupMemberScope` | 不变 |
| `IGovVotedBanSource` | `voteBySenderId(uint256,uint256,bool)` → `(uint256,uint256,uint256,bool)`（显式 `voterId`），`clear` / `refresh` 同理；新增错误 `NotMemberOwner(uint256)`（写入/撤票校验 voter 当前持有人），旧 `SenderNotMemberOwner(uint256)` 已删除；删除地址投票一整套（`voteBySenderAddress` / `voteBySender` 及其 clear/refresh、`voteWeightsBySenderAddressesByVoter` / `voteStatusBySenderAddress(es)` / `isAddressBanned(es)` / `votedSenderAddresses*` / `votersBySenderAddress*`、事件 `SetAddressBanVote` / `SetAddressBan`、错误 `TargetAddressZero`）与单条 `isSenderIdBanned` |

### 插件与来源（`plugins/`）

`IBeforePostPlugin.beforePost` / `IAfterPostPlugin.afterPost` **保留** `address senderAddress` 参数，`GroupChat._post` 继续传 `msg.sender`；地址在此仅作审计字段（[00-overview.md](group-chat/00-overview.md)）。

### 部署脚本

`script/` 按 [dev-standards §6](../../dev-standards.md) 重组为 `11_deploy.sh` / `21_check.sh` / `31_verify.sh` + `one_click_deploy.sh`；
`DeployGroupChat.s.sol` 移入 `script/deploy/` 并改用 forge-std `Script`；依赖地址拆为 `addresses.core.params` / `addresses.action.params`；
部署范围新增 `GroupChatDelegate`（旧流程由仓外文件提供地址），one-click 覆盖本库全部 13 个合约。

## 验收

按 [群聊规格](group-chat/README.md) 回归保留功能；对删除项检查 ABI、状态、事件和消费者均无残留。对身份替换、委托隔离、Manager 付款/持有和黑名单当前轮权重作差异测试，证据记录在 [组织验收](../acceptance.md)。
