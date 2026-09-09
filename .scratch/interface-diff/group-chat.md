# group-chat 层接口对比

状态列取值同 [core.md](core.md)。跨层共性变化见 [README](README.md#跨层结构变化)。

## 本层最大的结构变化：删除地址主体平行路径 + 操作者显式化

group-chat 保留旧群聊全部业务行为，只作三类系统性改造：

1. **删除地址主体平行路径**。旧版为黑名单、封禁投票、`canPost`、插件回调等同时维护 `senderAddress`（地址）和 `senderId`（NFT）两套 API，外加合并两者的 `bySenders` 双参版本。新版只保留 `senderId` 一套。
2. **写操作显式传 operatorId**。旧版写操作由合约内部按 `msg.sender` 反查操作者 NFT（`adminIdOf`、`ownerOrDelegateIdOf`、`GroupDefaults`）；新版把 `uint256 operatorId` 提为显式参数，相应事件也补上 `operatorId` 字段。
3. **删除 GroupDefaults 依赖**。`GROUP_DEFAULTS_ADDRESS`、`postAsDefaultSender` 及相关错误一并删除。

`Message` 结构体和 `PostMessage` 事件中的 `senderAddress` 属于审计快照，不是业务身份，保留不变。

---

## 1. IGroupChat vs IGroupChat

旧：`LOVE20TKM/group-chat/src/interfaces/IGroupChat.sol`。

### 完全保留

`struct ChatInfo`（11 字段）、`struct Message`（11 字段）、`struct RoundSpan`（4 字段）字段不变。

以下 39 个函数签名完全不变（新接口共 45 个函数，其余 6 个见下节）：`GROUP_ADDRESS`、`GROUP_ADMIN_ADDRESS`、`GROUP_DELEGATE_ADDRESS`、`originBlocks`、`phaseBlocks`、`MAX_CONTENT_LENGTH`、`MAX_MENTIONED_SENDER_IDS`、`activateChat`、`post`、`chatInfo`、`chatInfos`、`postingAllowed`、`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`、`messagesCount`、`messages`、`message`、`messagesByRoundCount`、`messagesByRound`、`messagesBySenderCount`、`messagesBySender`、`messageIdsBySender`、`messagesByMentionCount`、`messagesByMention`、`messageIdsByMention`、`messagesByMentionAllCount`、`messagesByMentionAll`、`messageIdsByMentionAll`、`senderIdsCount`、`senderIds`、`groupIdsCount`、`groupIds`、`currentRound`、`roundsCount`、`rounds`、`roundInfo`、`roundInfos`。

`post(groupId, senderId, content, mentionedSenderIds[], mentionAll, quotedMessageId)` 与 `activateChat(groupId, scopeSource_, banSource_, beforePostPlugin_, afterPostPlugin_)` 是本层两个核心写操作，签名逐字保留。

### 改动与删除

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `setPostingAllowed(groupId, uint256 operatorId, bool postingAllowed_)` | `setPostingAllowed(groupId, bool postingAllowed_)` | 改参 |
| `setScopeSource(groupId, uint256 operatorId, address sourceAddress)` | `setScopeSource(groupId, address sourceAddress)` | 改参 |
| `setBanSource(groupId, uint256 operatorId, address sourceAddress)` | `setBanSource(groupId, address sourceAddress)` | 改参 |
| `setBeforePostPlugin(groupId, uint256 operatorId, address pluginAddress)` | `setBeforePostPlugin(groupId, address pluginAddress)` | 改参 |
| `setAfterPostPlugin(groupId, uint256 operatorId, address pluginAddress)` | `setAfterPostPlugin(groupId, address pluginAddress)` | 改参 |
| `canPost(groupId, senderId) returns (allowed, reasonCode)` | `canPost(groupId, senderId, address senderAddress) returns (allowed, reasonCode)` | 改参 |
| 无 | `postAsDefaultSender(groupId, content, mentionedSenderIds[], mentionAll, quotedMessageId)` | 删除 |
| 无 | `GROUP_DEFAULTS_ADDRESS()` | 删除 |

### 事件

10 个事件全部保留名称，5 个补 `operatorId`、1 个补 `ownerId`：

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `Activate(groupId, uint256 ownerId, address owner)` | `Activate(groupId, address owner)` | 改参 |
| `SetPostingAllowed(groupId, uint256 operatorId, address operator, bool)` | `SetPostingAllowed(groupId, address operator, bool)` | 改参 |
| `SetScopeSource(groupId, sourceAddress, uint256 operatorId, address operator, prevSourceAddress)` | `SetScopeSource(groupId, sourceAddress, address operator, prevSourceAddress)` | 改参 |
| `SetBanSource`、`SetBeforePostPlugin`、`SetAfterPostPlugin` | 同名 | 改参（同上补 `operatorId`） |
| `PostMessage`、`MentionSenderId`、`MentionAll`、`FailAfterPostPlugin` | 同名 | 保留 |

### 错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `SenderNotMemberOwner(uint256 senderId)` | `SenderAddressNotSenderIdOwner()` | 改名+改参 |
| `AlreadyInitialized()`、`InvalidAddress()` | 无 | 新增 |
| 无 | `DefaultGroupIdNotSet()`、`GroupDefaultsHasNoCode()`、`GroupDefaultsGroupMismatch()` | 删除（GroupDefaults 不迁移） |
| 无 | `GroupAdminHasNoCode()`、`GroupDelegateHasNoCode()`、`GroupDelegateGroupMismatch()` | 删除（后者仍存在于 `IGroupAdmin`） |
| 其余 23 项 | 同名 | 保留 |

保留的 23 项（新接口共 26 个错误 = 23 保留 + 1 改名 + 2 新增）：`GroupNotExist`、`ChatAlreadyActivated`、`ChatNotActivated`、`PostingNotAllowed`、`NotChatOwner`、`NotChatOwnerOrDelegateIdOwner`、`RoundNotStarted`、`Reentrant`、`PhaseBlocksZero`、`MaxContentLengthZero`、`SourceAddressHasNoCode`、`PluginAddressHasNoCode`、`ContentEmpty`、`ContentTooLong`、`TooManyMentionedSenderIds`、`DuplicateMentionedSenderId`、`InvalidQuotedMessageId`、`InvalidMessageId`、`MentionAllUnauthorized`、`ScopeRejected`、`BanRejected`、`ScopeSourceFailed`、`BanSourceFailed`。

---

## 2. IGroupAdmin vs IGroupAdmin

旧：`LOVE20TKM/group-chat/src/interfaces/IGroupAdmin.sol`。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `addAdmins(groupId, uint256 operatorId, uint256[] adminIds)` | `addAdmins(groupId, uint256[] adminIdList)` | 改参 |
| `removeAdmins(groupId, uint256 operatorId, uint256[] adminIds)` | `removeAdmins(groupId, uint256[] adminIdList)` | 改参 |
| `GROUP_ADDRESS()`、`GROUP_DELEGATE_ADDRESS()`、`MAX_ADMIN_IDS()` | 同名 | 保留 |
| `isAdminId(groupId, adminId)`、`adminIds(groupId) returns (ids[], isEffective[])` | 同名 | 保留 |
| 无 | `GROUP_DEFAULTS_ADDRESS()` | 删除 |
| 无 | `adminIdOf(groupId, address account)` | 删除（改由 `operatorId` 显式传入） |
| 无 | `ownerOrDelegateIdOf(groupId, address account)` | 删除（移到 `IGroupChatDelegate`） |
| 事件 `SetAdmin`、`SetAdminSnapshot` | 同名 | 保留 |
| 错误 7 项 | 同名 | 全部保留 |

保留的 7 个错误：`GroupAdminAddressHasNoCode`、`UnauthorizedGroupAdminManager`、`GroupNotExist`、`DuplicateAdminId`、`AdminIdsLimitExceeded`、`MaxAdminIdsZero`、`GroupDelegateGroupMismatch`。

`SetAdminSnapshot` 事件保留 `groupOwnerSnapshot`、`adminOwnerSnapshot` 两个地址字段，属于审计快照。

---

## 3. IGroupChatBanList vs IGroupBanList

旧：`LOVE20TKM/group-chat/src/interfaces/IGroupBanList.sol`。人工黑名单，删除全部地址路径。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `banBySenderIds(groupId, uint256 operatorId, uint256[] senderIds)` | `banBySenderIds(groupId, uint256[] senderIds)` | 改参 |
| `unbanBySenderIds(groupId, uint256 operatorId, uint256[] senderIds)` | `unbanBySenderIds(groupId, uint256[] senderIds)` | 改参 |
| `isSenderIdBannedBatch(groupId, uint256[] senderIds)` | 无 | 新增 |
| `GROUP_ADMIN_ADDRESS()`、`isSenderIdBanned`、`senderIdBanListCount`、`senderIdBanList`、`senderIdBanDetails` | 同名 | 保留 |
| 无 | `isAddressBanned`、`addressBanDetails`、`banBySenderAddresses`、`unbanBySenderAddresses`、`addressBanListCount`、`addressBanList` | 删除 6 项（地址路径） |
| 无 | `banBySenders(groupId, senderIds[], senderAddresses[])`、`unbanBySenders(...)`、`isBanned(groupId, senderId, senderAddress)` | 删除 3 项（双参路径） |
| 事件 `SetSenderIdBan` | 同名 | 保留 |
| 无 | 事件 `SetAddressBan` | 删除 |
| 错误 `TargetSenderIdZero`、`GroupBanListAddressHasNoCode`、`UnauthorizedGroupBanListManager` | 同名 | 保留 |
| 无 | 错误 `TargetAddressZero`、`SenderPairLengthMismatch` | 删除 |

接口名从 `IGroupBanList` 改为 `IGroupChatBanList`。

---

## 4. IGroupMember vs IGroupMember

旧：`LOVE20TKM/group-chat/src/interfaces/IGroupMember.sol`。改动最小的接口。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `addMemberIds(groupId, uint256 operatorId, uint256[] memberIds)` | `addMemberIds(groupId, uint256[] memberIds)` | 改参 |
| `removeMemberIds(groupId, uint256 operatorId, uint256[] memberIds)` | `removeMemberIds(groupId, uint256[] memberIds)` | 改参 |
| `GROUP_ADDRESS()`、`GROUP_ADMIN_ADDRESS()`、`isMemberId`、`isMemberIdBatch`、`memberIdsCount`、`memberIds` | 同名 | 保留 |
| 事件 `SetMemberId` | 同名 | 保留 |
| 错误 `TargetMemberIdZero`、`GroupMemberAddressHasNoCode`、`UnauthorizedGroupMemberManager`、`GroupNotExist` | 同名 | 全部保留 |

本接口的 `memberId` 指群成员名单中的 MemberNFT，与 `IGroupChat` 的 `senderId` 是同一身份空间。

---

## 5. IGroupChatDelegate vs IGroupDelegate

旧：`LOVE20TKM/group/src/interfaces/IGroupDelegate.sol`。**跨仓库迁移**：从 `group` 仓库移入 `group-chat`，并更名为 Group Chat Delegate，仅 group-chat 使用；Core、Action、Launch 不读取此委托作为授权。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `GROUP_ADDRESS()`、`setDelegateId`、`clearDelegatedGroupIds`、`setDelegatorWhitelistEnabled`、`setAllowedDelegatorGroupIds`、`isDelegatorWhitelistEnabled`、`canSetDelegateTo`、`allowedDelegatorGroupIds`、`allowedDelegatorGroupIdsCount`、`delegateIdOf`、`delegateIdsOf`、`delegatedGroupIds`、`delegatedGroupIdsCount`、`ownerOrDelegateIdOf` | 同名 | 全部保留（14 项签名不变） |
| 无 | `isOwnerOrDelegate(groupId, address account)` | 删除（`ownerOrDelegateIdOf` 返回 0 即可判断） |
| 事件 `SetDelegateId`、`ClearDelegatedGroupId`、`SetDelegatorWhitelistEnabled`、`SetAllowedDelegatorGroupId` | 同名 | 全部保留 |
| 错误 `GroupNotExist`、`SenderNotGroupOwner`、`SenderNotDelegateOwner`、`DelegatorGroupIdNotAllowed`、`DelegateIdCannotBeGroupId` | 同名 | 保留 |
| 无 | 错误 `InvalidAddress()` | 删除 |

本接口是全层唯一「函数签名零改动」的迁移：委托关系本来就是 NFT 到 NFT，不含地址主体。

---

## 6. IGroupChatRules vs sources + plugins 四文件

旧：`LOVE20TKM/group-chat/src/interfaces/sources/IPostScopeSource.sol`、`sources/IPostBanSource.sol`、`plugins/IBeforePostPlugin.sol`、`plugins/IAfterPostPlugin.sol`。四个单函数文件合并为一个文件内的四个接口，接口名和函数名不变，统一删除 `address senderAddress` 参数。

| 接口 | 新签名 | 旧签名 | 状态 |
| --- | --- | --- | --- |
| `IPostScopeSource` | `canPost(groupId, senderId)` | `canPost(groupId, senderId, address senderAddress)` | 改参 |
| `IPostBanSource` | `isBanned(groupId, senderId)` | `isBanned(groupId, senderId, address senderAddress)` | 改参 |
| `IBeforePostPlugin` | `beforePost(groupId, senderId, content, mentionedSenderIds[], mentionAll, quotedMessageId)` | `beforePost(groupId, senderId, address senderAddress, content, ...)` | 改参 |
| `IAfterPostPlugin` | `afterPost(groupId, senderId, content, mentionedSenderIds[], mentionAll, quotedMessageId, messageId, blockNumber, timestamp)` | `afterPost(groupId, senderId, address senderAddress, content, ..., messageId, blockNumber, timestamp)` | 改参 |

这四个接口是 group-chat 的扩展点契约，`IGroupChat.setScopeSource`/`setBanSource`/`setBeforePostPlugin`/`setAfterPostPlugin` 接受任意实现它们的地址。

---

## 7. IGovVotedBanSource vs IGovVotedBanSource

旧：`LOVE20TKM/group-chat/src/interfaces/sources/ban/IGovVotedBanSource.sol`。治理投票封禁，删除全部地址路径并把投票者显式化为 `voterId`。

旧接口 32 个函数是本层最大的删减对象，新接口 17 个。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `voteBySenderId(groupId, uint256 targetSenderId, uint256 voterId, bool supportBan)` | `voteBySenderId(groupId, uint256 senderId, bool supportBan)` | 改参（新增 `voterId`） |
| `clearVoteBySenderId(groupId, targetSenderId, uint256 voterId)` | `clearVoteBySenderId(groupId, senderId)` | 改参 |
| `refreshVoteBySenderId(groupId, targetSenderId, uint256 voterId)` | `refreshVoteBySenderId(groupId, senderId, address voter)` | 改参（`address` → `uint256`） |
| `voteWeightsBySenderIdsByVoter(groupId, senderIds[], uint256 voterId)` | `voteWeightsBySenderIdsByVoter(groupId, senderIds[], address voter)` | 改参 |
| `votersBySenderId(groupId, senderId, offset, limit) returns (uint256[] voters, ...)` | 同名 `returns (address[] voters, ...)` | 改参（返回类型变） |
| `GROUP_ADDRESS`、`PRECISION`、`MIN_SUPPORT_TO_OPPOSE_RATIO`、`BAN_THRESHOLD_RATIO` | 同名 | 保留 |
| `voteStatusBySenderId`、`voteStatusBySenderIds`、`isSenderIdBanned`、`isSenderIdBannedBatch`、`votedSenderIdsCount`、`votedSenderIds`、`votersBySenderIdCount`、`stateVersion` | 同名 | 保留 |
| 继承 `IPostBanSource.isBanned(groupId, senderId)` | 继承 `IPostBanSource.isBanned(groupId, senderId, senderAddress)` | 改参 |
| 无 | `voteBySenderAddress`、`clearVoteBySenderAddress`、`refreshVoteBySenderAddress`、`voteWeightsBySenderAddressesByVoter`、`voteStatusBySenderAddress`、`voteStatusBySenderAddresses`、`isAddressBanned`、`isAddressBannedBatch`、`votedSenderAddressesCount`、`votedSenderAddresses`、`votersBySenderAddressCount`、`votersBySenderAddress` | 删除 12 项（地址路径） |
| 无 | `voteBySender`、`clearVoteBySender`、`refreshVoteBySender` | 删除 3 项（双参路径） |

### 事件与错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `SetSenderIdBanVote(groupId, targetSenderId, uint256 voterId, supportBan, settledWeight, supportWeight, opposeWeight, stateVersion)` | 同名（`address voter`） | 改参 |
| `SetSenderIdBan`、`ChangeStateVersion` | 同名 | 保留 |
| 无 | 事件 `SetAddressBanVote`、`SetAddressBan` | 删除 |
| 错误 `SenderNotMemberOwner(uint256 senderId)` | 无 | 新增 |
| 错误 `GovVotedBanSourceAddressHasNoCode`、`BanVoteWeightSourceUnavailable`、`TargetSenderIdZero`、`VoteWeightZero`、`VoteUnchanged`、`VoteNotFound`、`BanThresholdTooHigh`、`MinSupportToOpposeRatioZero` | 同名 | 保留 8 项 |
| 无 | 错误 `TargetAddressZero` | 删除 |

---

## 8. IActionManager vs IBaseTokenActionScopeManager + IBaseManager

旧：`LOVE20TKM/group-chat/src/interfaces/managers/IBaseTokenActionScopeManager.sol`、`managers/IBaseManager.sol`。

旧继承链 `IBaseTokenActionScopeManager → IBaseManager → IPostScopeSource + IBanVoteWeightSource + IERC721Receiver` 扁平化为单一接口。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `canPost(groupId, senderId)` | `IPostScopeSource.canPost(groupId, senderId, address senderAddress)` | 改参 |
| `voteWeightOf(groupId, uint256 voterId)` | `IBanVoteWeightSource.voteWeightOf(groupId, address voter)` | 改参 |
| `totalVoteWeight(groupId)` | `IBanVoteWeightSource.totalVoteWeight(groupId)` | 保留 |
| `onERC721Received(operator, from, tokenId, data)` | `IERC721Receiver.onERC721Received(...)` | 保留（显式声明） |
| `GROUP_CHAT_ADDRESS`、`GROUP_ADDRESS`、`BAN_SOURCE_ADDRESS`、`BEFORE_POST_PLUGIN_ADDRESS`、`AFTER_POST_PLUGIN_ADDRESS` | `IBaseManager` 同名 | 保留 |
| `RECENT_ROUNDS`、`activate(token, actionId)`、`actionOfGroup`、`groupIdOfAction`、`groupIdsOfActions`、`actionsOfGroups`、`actionsByTokenCount`、`actionsByToken` | 同名 | 保留 8 项签名不变 |
| 无 | `IBaseManager.EXTENSION_CENTER_ADDRESS()` | 删除（ExtensionCenter 不迁移，改为直连 action 层） |
| 事件 `Activate(token, actionId, groupId, operator)` | 同名 | 保留 |
| 错误 10 项 | `IBaseManager` 同名 | 全部保留 |

保留的 10 个错误：`ManagerAddressHasNoCode`、`AlreadyManaged`、`RecentRoundsZero`、`ManagerGroupNameUnavailable`、`ManagerMintCostChanged`、`ManagerPaymentFailed`、`ManagerApprovalFailed`、`TokenNotLOVE20`、`UnexpectedManagerERC721Received`、`ActionIdNotExist`。

`canPost` 的实现依据从旧 `ExtensionCenter` 的参与登记改为 action 层的链群归属索引（`IGroupActionIndexes.gTokenAddressesByGroupIdByMemberIdCount(groupId, memberId) > 0`），这是实现变化而非 ABI 变化。

---

## 9. ITokenManager vs IBaseTokenScopeManager + IBaseManager

旧：`LOVE20TKM/group-chat/src/interfaces/managers/IBaseTokenScopeManager.sol`、`managers/IBaseManager.sol`。与 `IActionManager` 同构，作用域为整个代币社区而非单个行动。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `canPost(groupId, senderId)` | `IPostScopeSource.canPost(groupId, senderId, address senderAddress)` | 改参 |
| `voteWeightOf(groupId, uint256 voterId)` | `IBanVoteWeightSource.voteWeightOf(groupId, address voter)` | 改参 |
| `activate(address token) returns (uint256 groupId)`、`tokenOfGroup`、`groupIdOfToken`、`tokensCount`、`tokens` | 同名 | 保留 5 项签名不变 |
| `totalVoteWeight`、`onERC721Received`、5 个地址 getter | 同上 | 保留 |
| `RECENT_ROUNDS()` | `IBaseTokenScopeManager` 无（仅 ActionScope 版本有） | 新增 |
| 无 | `IBaseManager.EXTENSION_CENTER_ADDRESS()` | 删除 |
| 事件 `Activate(token, groupId, operator)` | 同名 | 保留 |
| 错误 9 项 | `IBaseManager` 同名 | 保留 |
| 无 | 错误 `ActionIdNotExist` | 删除（本接口无 actionId 维度，正确剥离） |

---

## 10. 旧 group-chat scope/ban 适配接口的去向

| 旧接口 | 去向 |
| --- | --- |
| `sources/ban/IBanVoteWeightSource.sol`（2 函数） | `voteWeightOf`、`totalVoteWeight` 合并进 `IActionManager`、`ITokenManager` |
| `sources/ban/IAdminBanSource.sol`（1 函数 / 1 错误） | **已补回** `group-chat/IAdminBanSource.sol`：声明 `GROUP_BAN_LIST_ADDRESS()`，错误 `AdminBanSourceAddressHasNoCode`；行为契约来自继承的 `IPostBanSource.isBanned`。1:1 无差异 |
| `sources/scope/IGroupMemberScope.sol`（1 函数 / 1 错误） | **已补回** `group-chat/IGroupMemberScope.sol`：声明 `GROUP_MEMBER_ADDRESS()`，错误 `GroupMemberScopeAddressHasNoCode`；行为契约来自继承的 `IPostScopeSource.canPost`。1:1 无差异 |
| `sources/scope/IGroupJoinScopeSource.sol`（2 函数 / 1 错误） | **已补回** `group-chat/IGroupJoinScopeSource.sol`：`GROUP_MEMBER_ADDRESS()` 原样保留；`GROUP_JOIN_ADDRESS()` 因旧 core `Join` 已取消，改名为 `GROUP_ACTION_EXECUTOR_ADDRESS()` 指向 action 层单例 `IGroupActionExecutor`；错误 `GroupJoinScopeSourceAddressHasNoCode` 保留。函数数 2 → 2（改名 1 项） |
| `interfaces/external/*.sol`（14 文件） | 外部依赖镜像（`IERC20Balance`、`IERC20Payment`、`IERC20Symbol`、`IERC721Receiver`、`IExtensionCenter`、`IGroupDefaults`、`IGroupDelegate`、`IGroupJoin`、`ILOVE20Group`、`ILOVE20Join`、`ILOVE20Launch`、`ILOVE20Stake`、`ILOVE20Submit`、`ILOVE20Vote`），新版直接引用 `core`、`action` 接口，不再复制 |

`IGroupDefaults`（旧 `group` 仓库）在本层同时作为 external 镜像存在，随 GroupDefaults 一并不迁移。
