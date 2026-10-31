# Group Chat 迁移差异

用户确认：群聊几乎原样迁移，功能、流程、查询和失败行为保持；业务身份统一为 MemberNFT，删除地址主体平行路径。群内 NFT 委托已整体移除（2026-10-31），见下节与 [ADR-005](../adr/005-remove-group-chat-delegation.md)。

## 移除群内 NFT 委托（2026-10-31）

用户确认：删除 `GroupChatDelegate`，群聊授权只认 NFT 当前持有人。这是对「原样迁移」的明确差异，现行行为以 [01-lifecycle.md](group-chat/01-lifecycle.md) 为准：

- **删除合约与接口**：`GroupChatDelegate.sol`、`IGroupChatDelegate.sol`；四个合约与接口删除 `GROUP_DELEGATE_ADDRESS` getter；`GroupChat` / `GroupAdmin` / `GroupMember` / `GroupChatBanList` 不再解析 owner/delegate。
- **构造链**：`GroupAdmin` 构造函数改为 `(groupAddress, maxAdminIds)`，不再从委托合约派生 `GROUP_ADDRESS`；部署脚本少部署一个合约（13 → 12），`11_deploy.sh` / `21_check.sh` / `31_verify.sh` 的键集合与校验项同步。
- **权限边界**：配置写入口（`setPostingAllowed` 与四个槽位）与管理员授予/撤销只接受群 owner；`operatorId` 参数保留用于事件，但必须等于 `groupId`，否则回 `NotGroupOperator(groupId, operatorId)`。成员名单与人工黑名单仍接受群 owner 或有效 admin。
- **发言**：scope/ban 豁免只保留 `senderId == groupId`；`mentionAll` 只保留群 owner 与有效 admin（`isAdminId` 分支原本已存在）。
- **`_isOperator` 内联**：`GroupMember` / `GroupChatBanList` 各自保留本地判定，先 `GroupNotExist(groupId)`，再 `ownerOf(operatorId) == msg.sender`，最后 `operatorId == groupId || isAdminId`；两个接口的 `I<Name>Errors` 补 `GroupNotExist(uint256 groupId)`。按 dev-standards §5.5，不再为去重新建共享库。
- **删除的 ABI**：`setDelegateId`、`clearDelegatedGroupIds`、`setDelegationAcceptanceEnabled`、`isDelegationAcceptanceEnabled`、`effectiveDelegateId`、`effectiveDelegateIdsByGroupIds`、`delegatedGroupIds`、`ownerOrDelegateId`；事件 `DelegateChanged`、`DelegationCleared`、`DelegationAcceptanceChanged`；错误 `DelegateIsSelfGroup`、`DelegateNotAcceptingNewDelegations`。事件族 `gc.delegation` 随之消失。
- **测试**：删除 `GroupChatDelegate.t.sol` 与 `MockGroupDelegate.sol`；原 delegate 用例改为 admin 或 owner 路径，新增「admin 不能改配置 / 不能任命管理员」的负向用例。门禁：**152 tests 全绿**（原 172，删除委托套件与其专属用例；后续追加 3 条缺失群/错误顺序用例）；`deploy_scripts_test.py` **13/13**。
- **上层替代**：需要代理时由使用者在应用层部署托管合约（NFT 转入、记录原持有人与代理人、保留取回权）；该方案委派整个身份，不在本仓库实现。

## 命名标准落地（2026-10-30）

[`naming-standards.md`](../naming-standards.md) 的机器规则在本仓清零（基线 0 条，172 个用例全绿）。本节是相对此前各小节记录的现行名称差异：

- 谓词：`postingAllowed(groupId)` → `isPostingAllowed(groupId)`；`ChatInfo.postingAllowed`、`ChatConfig.postingAllowed`、`GroupChatActivated.postingAllowed`、`PostingAllowedChanged.postingAllowed` 是字段不是函数，保持原名。
- 批量读：`chatInfos` → `chatInfosByGroupIds(uint256[] requestedGroupIds)`；`roundInfos` 的载荷是轮次而非 id，改 `roundInfosByRounds(uint256 groupId, uint256[] requestedRounds)`，不套 `Ids`。
- 委托读：`delegateIdOf` → `effectiveDelegateId`、`delegateIdsOf` → `effectiveDelegateIdsByGroupIds`（名字写明只返回快照仍有效的委托；批量读按 naming-standards §六 带 `By<Key>Ids`）、`ownerOrDelegateIdOf(groupId, account)` → `ownerOrDelegateId(groupId, operatorAddress)`。
- 权重读：`voteWeightOf` → `voteWeight`（`IBanVoteWeightSource` 与四类 Manager 同步）。
- 冻结值：`GroupChatBanList._groupAddress` / `_groupDelegateAddress`、`GroupMember._groupDelegateAddress` 改全大写 immutable `GROUP_ADDRESS` / `GROUP_DELEGATE_ADDRESS`；`ManagedAction.token` → `tokenAddress`。
- 状态：四处 `_states` 改 `_adminState` / `_chatState` / `_memberState` / `_chatState`；`GroupChat` 重入锁 `_entered` → `_reentrancyStatus`、局部 `message_` → `storedMessage`。
- 入参：接口入参不再用 `_` 后缀。与同名 getter 撞的批量入参改写为 `adminIdList` / `memberIdList`（写方向；方向已由 `add*` / `remove*` 给出，且与内部双向辅助 `_setMemberIds(…, memberIdList, listed)` 同名）、`checkedMemberIds`（`isMemberIdBatch`）、`requestedGroupIds`（`chatInfosByGroupIds`）、`requestedRounds`（`roundInfosByRounds`）；`adminIds(groupId)` 的返回名 `ids` → `adminIdList`（`ids` 是裸复数泛名，ABI JSON 里读不出是哪类 id，按 §十一「返回值不用裸 `ids`/`list`/`items`」改；`List` 后缀在这里取「数组」义，与 §7.5 分页禁 `List` 不冲突）。`activateChat` 的四个槽位入参改 `scopeSourceAddress` / `banSourceAddress` / `beforePostPluginAddress` / `afterPostPluginAddress`（§十一 四处同源在此处让位于同名声明禁入，见 naming-standards §3 硬约束 4 的读取 getter 例外）。下文 §Manager 三接口的「入参名」条记录的是本次被取代的旧做法。
- 实体地址后缀（naming-standards §十）：构造函数入参与对应 getter 对齐为 `groupAdminAddress` / `groupDelegateAddress` / `groupChatAddress` / `banSourceAddress` / `beforePostPluginAddress` / `afterPostPluginAddress` / `actionTargetAddress` / `groupBanListAddress` / `groupMemberAddress` / `groupActionExecutorAddress`；Manager 的 `address token` 入参与局部变量改 `tokenAddress`，`actionByGroupId` 的返回名同步。四个配置槽位在 `activateChat` 与单槽 setter（`setScopeSource` / `setBanSource` / `setBeforePostPlugin` / `setAfterPostPlugin`）里统一为 `scopeSourceAddress` / `banSourceAddress` / `beforePostPluginAddress` / `afterPostPluginAddress`，字段与事件保留角色名（§3 硬约束 4 例外二、§十一 登记例外）。部署参数文件的键名（`*_ADDRESS`）不受影响。
- 黑名单写票：`voteBySenderId` / `clearVoteBySenderId` / `refreshVoteBySenderId` → `voteByTargetSenderId` / `clearVoteByTargetSenderId` / `refreshVoteByTargetSenderId`，**入参保持 `targetSenderId`**——它与事件字段 `SenderBanVoteCast.targetSenderId`（由 event-standards §6.1 的 `gc.ban-vote` 槽位冻结）及内部 `TargetState` 键同名，按 naming-standards §3 硬约束 4 的例外让函数名让位，保住 §十一 的四处同源。
- mention 查询族（§7.3 收紧 `By<Key>` 后）：`messagesByMention` / `messageIdsByMention` → `messagesByMentionedSenderId` / `messageIdsByMentionedSenderId`（Key 取入参 `mentionedSenderId` 的词干）；`messagesByMentionAll` / `messageIdsByMentionAll` → `mentionAllMessages` / `mentionAllMessageIds`（mention-all 是固定条件、没有对应入参，按 §7.3 不用 `By`）。`messagesBySenderId*` / `voteWeightsBySenderIdsByVoterId` 不动：`Sender` / `Voter` 分别是 `senderId` / `voterId` 去 `Id` 后的词干。这两族的 Count 入口已删除，总数由分页返回。
- 集合查询：18 个分页入口统一为 `(offset, limit, reverse) → (列表, totalCount)`，返回值全部具名。删除全部 15 个 `*Count`（`messagesCount`、`messagesByRoundCount`、`messagesBySenderCount`、`messagesByMentionCount`、`messagesByMentionAllCount`、`senderIdsCount`、`groupIdsCount`、`roundsCount`、`memberIdsCount`、`delegatedGroupIdsCount`、`senderIdBanListCount`、`votedSenderIdsCount`、`votersBySenderIdCount`、`tokensCount`、`actionsByTokenCount`）：旧 ABI 的「分页 + 独立计数」是同一集合两条读取路径，`delegatedGroupIds` 更是在已返回 `totalCount` 之后又留了一个 Count。`limit = 0` 是取总数的唯一入口。`memberIds` / `senderIdBanList` / `delegatedGroupIds` / `votedSenderIds` / `votersBySenderId` 补 `reverse`；它们基于 swap-and-pop 的 `Uint256Set`，`reverse` 只承诺逆序遍历当前存储顺序，`offset` 不跨调用稳定。五个 `reverse` 都有反向分页用例（`senderIdBanList` / `votedSenderIds` / `votersBySenderId` 见 `testT123B` / `testT135B` / `testT135C`，`memberIds` / `delegatedGroupIds` 见 `testT133B_adminCanAddAndRemoveMemberIds` / `testT153_delegationPaginationBoundaries`），夹具先删首个元素让尾元素填位，使「当前存储顺序」与「插入序」可判别。
- 存储态与映射（naming-standards §8.3 / §8.6）：`StoredMessage` → `MessageRecord`（写入后不改写，`State` 会被读成可变状态，按 §8.6 新增的 `Record` 判据改名）；`_chatConfigs` / `_messagesByChat` / `_senderMessageIndexes` / `_mentionMessageIndexes` / `_mentionAllMessageIndexes` / `_senderIdsByChat` / `_roundStates` / `_roundListByChat` → `_chatConfig` / `_messagesByGroupId` / `_messageIndexesByGroupIdBySenderId` / `_messageIndexesByGroupIdByMentionedSenderId` / `_mentionAllMessageIndexesByGroupId` / `_senderIdsByGroupId` / `_roundStateByGroupIdByRound` / `_roundsByGroupId`；`GroupChatDelegate` 的 `_delegateStates` / `_delegationAcceptanceEnabled` → `_delegateState` / `_delegationAcceptanceEnabledByDelegateId`。
- 冻结值可见性：`GroupChatBanList.GROUP_ADDRESS` / `GROUP_DELEGATE_ADDRESS`、`GroupMember.GROUP_DELEGATE_ADDRESS` 由 `internal` 改 `public` 并进接口，`21_check.sh` 补三条绑定校验——与 GroupChat / GroupAdmin / GroupMember 既有 getter 对齐，部署后可直接核对这些合约指向的 MemberNFT 与 delegate。
- Manager 查询去中缀 `Of`（§7.7，N20 只匹配结尾 `Of`，这批靠人工）：`tokenOfGroup` / `groupIdOfToken` / `actionOfGroup` / `groupIdOfAction` / `groupIdsOfActions` / `actionsOfGroups` → `tokenAddressByGroupId` / `groupIdByTokenAddress` / `actionByGroupId` / `groupIdByActionId` / `groupIdsByActionIds` / `actionsByGroupIds`；`actionsByToken` 的 `Token` 在入参改 `tokenAddress` 后不再同名，按 §7.3 的作用域键规则改为 `actions`，其 Count 入口删除、总数由分页返回；成对映射同步按 §8.3 改 `_tokenAddressByGroupId` / `_groupIdByTokenAddress` / `_managedActionByGroupId` / `_groupIdByActionId`；`_actionIdsByToken` → `_actionIdsByTokenAddress`（同批其余键都补了 `Address`，只剩它用裸 `Token`）。

## Scope 谓词改名（2026-10-31）

`IPostScopeSource.canPost(uint256,uint256)` → `isSenderAllowed(uint256,uint256)`，两个内置 scope source 与四个 Manager 同步。`IGroupChat.canPost(uint256,uint256)` 保留 `(bool allowed, PostRejectionReason reason)`。

- **原因**：两族原本同 selector、不同返回形态。`GroupChat` 通过 `IPostScopeSource` 定向调用只读首字，按布尔 ABI 调用 `IGroupChat` 则会把 `PostRejectionReason` 丢掉；反向按二元组 ABI 调用 scope source 会因返回数据不足回滚。改名后 `canPost` 只剩高层预检查一种形态。
- **语义**：scope source 只回答“该 sender 是否允许发言”，不返回拒绝原因；拒绝原因仍由 `GroupChat` 汇总为 `PostRejectionReason`。
- 规格见 [规则槽位](group-chat/02-rules.md#标准接口) 与 [发言](group-chat/03-posting.md#预检查)。

## 委托接受开关（2026-10-29）

用户确认：删除按群白名单，改为按目标 memberId 的**委托接受开关**。本节是相对“原样迁移”的明确差异，现行行为以 [01-lifecycle.md](group-chat/01-lifecycle.md) 为准：

- 删除 `setAllowedDelegatorGroupIds` / `allowedDelegatorGroupIds` / `allowedDelegatorGroupIdsCount`、事件 `DelegatorGroupPermissionChanged`、错误 `DelegatorGroupIdNotAllowed`，以及查询 `canSetDelegateTo`。
- `setDelegatorWhitelistEnabled` / `isDelegatorWhitelistEnabled` / `DelegatorWhitelistChanged` 改为 `setDelegationAcceptanceEnabled` / `isDelegationAcceptanceEnabled` / `DelegationAcceptanceChanged`；新增错误 `DelegateNotAcceptingNewDelegations(uint256 delegateId)`。
- 开关按 delegateId 保存，默认关闭；关闭时禁止一切非零 `setDelegateId`（含同 id 重设、群或 delegate NFT 转移后的重新设回），`setDelegateId(groupId, 0)` 永远允许。
- 开关是 delegateId 的属性，不随 delegate NFT 转移变化：新持有人继承当前值并可自行开关，旧持有人不再能开关；委托失效只由 owner 快照失配决定。
- 开关只约束新指定，不参与有效性判断：关闭后既有委托继续生效（`effectiveDelegateId`、`ownerOrDelegateId`、`delegatedGroupIds.isEffective` 均不变），撤销或 owner 快照失配才失效。
- 校验顺序：自指 → delegate NFT 存在性 → 接受开关 → 幂等；无效请求不被幂等静默吞掉。
- 事件族 `gc.delegation` 只保留 `DelegationAcceptanceChanged`；`event-standards.md`、[07-events-errors.md](group-chat/07-events-errors.md)、[08-testing.md](group-chat/08-testing.md) 已同步。Group Chat 门禁：**168 tests 全绿**，事件基线与错误注册表已重生成。

## 事件与基类改名（2026-10-27）

事件规范 v1.1 与基类后缀规则（`dev-standards.md` §5.2）重命名了本文其他小节记录的迁移时点名称；正文保留当时名称，现行名称以 [规格](README.md) 与 `group-chat/src/interfaces/` 为准：

- 事件：`Activate` → `GroupChatActivated`；`SetPostingAllowed` / `SetScopeSource` / `SetBanSource` / `SetBeforePostPlugin` / `SetAfterPostPlugin` → `*Changed`；`PostMessage` → `MessagePosted`；`MentionSenderId` → `SenderMentioned`；`MentionAll` 并入 `MessagePosted.mentionAll`；`FailAfterPostPlugin` → `AfterPostPluginFailed`；`SetAdmin` / `SetAdminSnapshot` → `AdminChanged`；`SetMemberId` → `MemberStatusChanged`；`SetSenderIdBan` → `SenderBanChanged`；`SetSenderIdBanVote` → `SenderBanVoteCast`；`SetDelegateId` → `DelegateChanged`；`ClearDelegatedGroupId` → `DelegationCleared`；`SetDelegatorWhitelistEnabled` → `DelegatorWhitelistChanged`；`SetAllowedDelegatorGroupId` → `DelegatorGroupPermissionChanged`；`ChangeStateVersion` 与 `stateVersion` 字段/getter 一并删除（变更由 `SenderBanVoteCast`/`GovSenderBanChanged` 携带）；`forceExit` → `forceClearJoinState`。
- 基类：`BaseManager` → `ManagerBase`、`BaseTokenManager` → `TokenManagerBase`、`BaseTokenScopeManager` → `TokenScopeManagerBase`、`BaseTokenActionScopeManager` → `TokenActionScopeManagerBase`，接口同理（`IBaseManager` → `IManagerBase` 等）。

## 托管群命名 v2 与校验分层（2026-10-25）

- 四个托管 Manager 的群名改为 `type[_payload]_random`：类型码由各 Manager 的 `_typeCode()` 提供（`tm`/`tg`/`am`/`ag`），payload 为清洗后的 symbol 或 `symbol_actionId`；放不下时整段丢弃并用随机串填满，含 payload 时随机后缀固定 4 位 hex。
- MemberNFT `MAX_NAME_LENGTH` 下限为 `bytes(TYPE_CODE()).length + 9`（当前四类 2 字节类型码即 11）。类型码由各 Manager 自己定义、不设集中清单，`IBaseManager` 暴露 `TYPE_CODE()`；部署脚本广播前按「当前最长类型码 2 字节 + 9」预检 11（`testT181` 锁定该假设与四个 Manager 的实际 `TYPE_CODE()` 一致），`21_check.sh` 部署后按各 Manager 的 `TYPE_CODE()` 独立复核；四类类型码非空且互异由 `testT180` 锁定。
- 构造期依赖代码、参数范围与地址关系校验移到部署脚本；`ManagerDependencyNotContract`、`ManagerGroupNameSpaceTooSmall`、`ZeroRecentRounds` 及构造 `*NotContract` 错误删除。下文历史小节保留当时记录。
- 当前门禁：`forge test`、`build --deny warnings`、`lint`、`check_caller_auth.sh`、部署脚本回归、`check_errors.py --check` 全绿。

## 错误模型 v3（2026-10-24）

> 本节记录 2026-10-24 的 v3 状态；2026-10-25 起构造期静态校验移到部署脚本，构造错误已删除，见上节。

Group Chat 已全部改为 **local-first** 错误模型：每个合约/模块拥有自己的 `I<Name>Errors`，不设中心枚举、不跨仓导入错误。

- 地址/依赖：`InvalidAddress` 拆为具体依赖错误；必填合约依赖以“有代码”为条件，零地址与非零 EOA 统一回 `*NotContract(address)`（零地址为 `*NotContract(0)`），payload 带失败地址。
- 状态：`ChatAlreadyActivated(groupId)`、`ChatNotActivated(groupId)`、`PostingNotAllowed(groupId)`；`RoundNotStarted(requiredRound,currentRound)` 与 Core/Action 同签名。
- 消息/提及/引用：`Name` 类错误按字段拆分；`MessageNotFound(groupId,messageId)`、`QuotedMessageNotFound(groupId,messageId)`、`MentionAllUnauthorized(groupId,senderId)`。
- 规则源：`ScopeRejected(groupId,senderId,source)`、`BanRejected(groupId,senderId,source)`、`ScopeSourceFailed(groupId,source)`、`BanSourceFailed(groupId,source)`（主体键在前，条件值 `source` 在后）。
- Delegate：`DelegateNotAcceptingNewDelegations(delegateId)`；`setDelegateId` 先校验再幂等返回，不再吞掉非法请求。
- 批量与构造：GroupMember / GroupChatBanList 的数组内重复 ID 回 `DuplicateMemberId(memberId)`，与 GroupAdmin、提及、接收人一致；构造依赖零值与非零 EOA 统一回 `*NotContract(address)`，不再保留零值专项错误。
- `canPost`：返回封闭 `PostRejectionReason` 枚举，不再把错误 selector 当业务数据；缺失 sender 返回 `SenderNotExist`。
- Manager/GovVoted：Manager 必填依赖无代码（含零地址）统一回 `ManagerDependencyNotContract(dependency)`；`AlreadyManaged(groupId)`、`VoteUnchanged/VoteNotFound`、`BanVoteWeightSourceUnavailable(groupId,source)` 等带主体；GovVoted 写路径对缺失群回 `GroupNotExist(groupId)`、群存在但权重源无代码回 `BanVoteWeightSourceUnavailable(groupId,source)`；Manager 付款/授权走 OZ `SafeERC20FailedOperation(token)`；`FailAfterPostPlugin` 改为 `errorHash + errorLength + errorSelector`，不再写无界 `bytes`。
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
| GovVotedBanSource | 双阈值、settledWeight、改票/撤票/刷新、已结算名单 | voter 和 target 均用 memberId，删除地址目标、stateVersion 及对应索引/事件 |
| typed Manager | 激活者付款、Manager 持有 NFT、单实例管理多个 Chat、不重配、不转出、命名和查询 | 新 Core 接口；资格由 memberId 查询，不重新设计付款或恢复机制 |
| GroupMemberScope / GroupJoinScopeSource | 名单或当前链群归属 | 将 GroupJoin 地址查询替换为链群 Executor 的 memberId 查询 |
| Group Chat Delegate | NFT 委托、接受开关、反向枚举、双 owner 快照 | 实现归 group-chat，只供群聊管理；删除按群白名单，改为默认关闭的接受开关；Core/Action/Launch 不使用 |
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
| 函数 | `currentRound()`、三个地址 getter、两个上限 getter、`activateChat`、`post`、`chatInfo` / `chatInfosByGroupIds`、五个槽位 getter、`messages*` / `message` / `messagesBy*` / `messageIds*` / `senderIds` / `groupIds` / `rounds` / `roundInfo` / `roundInfosByRounds` | `canPost(uint256,uint256,address)` → `canPost(uint256,uint256)`；五个配置 setter 各增 `uint256 operatorId` | `PHASE_ADDRESS()` | `originBlocks()` / `phaseBlocks()`、`postAsDefaultSender(...)`、`GROUP_DEFAULTS_ADDRESS()` |
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

- **改名**：合约与接口 `GroupDelegate` → `GroupChatDelegate`；`InvalidAddress()` 等错误保留
- **2026-10-29 起**：删除按群白名单与 `canSetDelegateTo`；白名单读写/枚举、`DelegatorGroupPermissionChanged`、`DelegatorGroupIdNotAllowed` 不再存在；`setDelegatorWhitelistEnabled` / `isDelegatorWhitelistEnabled` / `DelegatorWhitelistChanged` 改为 `setDelegationAcceptanceEnabled` / `isDelegationAcceptanceEnabled` / `DelegationAcceptanceChanged`，新增 `DelegateNotAcceptingNewDelegations(uint256)`；开关默认关闭，只约束新指定
- **删除**：`isOwnerOrDelegate(uint256,address)`；等价判断由 `ownerOrDelegateId(...) != 0` 表达，`effectiveDelegateId` / `effectiveDelegateIdsByGroupIds` 已覆盖「有效 delegate 查询」
- **错误**：写入口缺失 delegateId 回 `ERC721NonexistentToken`；非 owner 回 `NotMemberOwner(delegateId)`；查询缺失 delegate 返回 false/0/空，不回滚；群 owner 非 owner 回 `NotGroupOwner(groupId)`；`delegateId == groupId` 回 `DelegateIsSelfGroup(groupId)`；`GroupNotExist(groupId)` 只用于群角色。旧 `SenderNotGroupOwner` / `DelegateIdCannotBeGroupId` / `SenderNotDelegateOwner` 已删除

### Manager 三接口

- **改参**：四个 Manager 构造 `extensionCenter_` → `actionTarget_`；`banSource_` 由激活参数提前为构造参数
- **删除**：`IBaseManager.EXTENSION_CENTER_ADDRESS()`
- **移动**：`ActionIdNotExist()` 由 `IBaseManager` 移至 `IBaseTokenActionScopeManager`（selector 不变）
- **可见性**：`tokenOfGroup` / `groupIdOfToken` / `actionOfGroup` / `groupIdOfAction` 由 `public` 存储改为 `internal` + 显式 getter（selector 不变）
- **入参名**（**2026-10-30 起被命名标准取代**）：当时批量入参在接口与实现统一为 `_` 后缀以规避同名 getter 的声明遮蔽（solc 8760）；现行做法见本页 §命名标准落地
- **新增**：错误 `ManagerGroupNameSpaceTooSmall()`；MemberNFT `MAX_NAME_LENGTH < 17`（1 字节分隔符 + 12 位十六进制后缀 + 4 字节 Test 前缀）时 Manager 构造回滚（已被 2026-10-25 命名 v2 取代，见上）

### 资格与黑名单源

| 接口 | 变更 |
| --- | --- |
| `IPostScopeSource` | `canPost(uint256,uint256,address)` → `canPost(uint256,uint256)` |
| `IPostBanSource` | `isBanned(uint256,uint256,address)` → `isBanned(uint256,uint256)` |
| `IBanVoteWeightSource` | `voteWeightOf(uint256,address)` → `voteWeight(uint256,uint256)`（2026-10-30 去 `Of` 后缀） |
| `IGroupJoinScopeSource` | `GROUP_JOIN_ADDRESS()` → `GROUP_ACTION_EXECUTOR_ADDRESS()`；成员判定改 `IGroupActionIndexes.isGroupMember(groupId, senderId)` |
| `IAdminBanSource` / `IGroupMemberScope` | 不变 |
| `IGovVotedBanSource` | `voteBySenderId(uint256,uint256,bool)` → `(uint256,uint256,uint256,bool)`（显式 `voterId`），`clear` / `refresh` 同理；新增错误 `NotMemberOwner(uint256)`（写入/撤票校验 voter 当前持有人），旧 `SenderNotMemberOwner(uint256)` 已删除；删除地址投票一整套（`voteBySenderAddress` / `voteBySender` 及其 clear/refresh、`voteWeightsBySenderAddressesByVoter` / `voteStatusBySenderAddress(es)` / `isAddressBanned(es)` / `votedSenderAddresses*` / `votersBySenderAddress*`、事件 `SetAddressBanVote` / `SetAddressBan`、错误 `TargetAddressZero`）与单条 `isSenderIdBanned` |

### 插件与来源（`plugins/`）

`IBeforePostPlugin.beforePost` / `IAfterPostPlugin.afterPost` **保留** `address senderAddress` 参数，`GroupChat._post` 继续传 `msg.sender`；地址在此仅作审计字段（[00-overview.md](group-chat/00-overview.md)）。

### 部署脚本

`script/` 按 [dev-standards §6](../../dev-standards.md) 重组为 `11_deploy.sh` / `21_check.sh` / `31_verify.sh` + `one_click_deploy.sh`；
`DeployGroupChat.s.sol` 移入 `script/deploy/` 并改用 forge-std `Script`；依赖地址拆为 `addresses.core.params` / `addresses.action.params`；
部署范围新增 `GroupChatDelegate`（旧流程由仓外文件提供地址），one-click 覆盖本库全部 13 个合约。**2026-10-31 已移除委托，现行部署为 12 个合约，见文首「移除群内 NFT 委托」。**

## 验收

按 [群聊规格](group-chat/README.md) 回归保留功能；对删除项检查 ABI、状态、事件和消费者均无残留。对身份替换、委托隔离、Manager 付款/持有和黑名单当前轮权重作差异测试，证据记录在 [组织验收](../acceptance.md)。
