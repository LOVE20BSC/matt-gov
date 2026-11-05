# `group-chat/GroupChat.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），工作树干净；行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/01-lifecycle.md`、`02-rules.md`、`03-posting.md`、`04-query.md`、`07-events-errors.md`。
> 范围：`src/GroupChat.sol`（951 行）+ `src/interfaces/IGroupChat.sol` 的 `IGroupChatErrors`。
> 同目录汇总见 [README.md](README.md)。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 8 条（2 Low / 6 Info）。

## 1. 结论

- 22 个错误声明（`IGroupChatErrors`）/ 22 个 revert 站点，一错误一站点；实现文件零错误声明，无裸 `require`/`revert`。
- 唯一 `assert` 在 `_revertPostSourceReason` 的兜底分支（`:772`），属不可达不变量，符合 §8。
- 错误覆盖完整，无未声明 revert、无死声明；测试对 21 个错误有直接 `expectRevert` + 载荷断言，`Reentrant` 只在 after 插件失败的捕获 selector 中断言。
- 1 条 Low：`post` 的 `RoundNotStarted` 未进 03-posting 的校验顺序，`canPost` 也不覆盖该门，预检查与写入的失败集合不一致（已由 api-auth 卷 `GC-01` / state 卷 `GCH-01` 关闭）。
- 1 条 Low：`beforePostPlugin` 的 revert 原样冒泡，`post` ABI 可携带任意 revert data，规格未按 §7 声明。
- 其余为口径与文档项：`NotGroupOperator` 复合鉴权、`MentionAllUnauthorized` 命名、`Reentrant` 无直接 `expectRevert`、`activateChat` 重复取 owner、配置入口“状态先于依赖参数”的顺序未写理由（`E-GC-08`）、透传面未按模块列表登记。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 22 |
| revert 站点 | 22 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 2 / 6 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `Reentrant` | `Reentrant()` | `0xed3ba6a6` | 1 | 保留 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` | 1 | 保留 |
| `NotGroupOwner` | `NotGroupOwner(uint256)` | `0x54a55079` | 1 | 保留 |
| `NotGroupOperator` | `NotGroupOperator(uint256,uint256)` | `0x20e5d297` | 1 | 保留（复合鉴权，见 E-GC-05） |
| `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` | 1 | 保留 |
| `ChatAlreadyActivated` | `ChatAlreadyActivated(uint256)` | `0x7dd7c968` | 1 | 保留 |
| `ChatNotActivated` | `ChatNotActivated(uint256)` | `0xba67ced4` | 1 | 保留 |
| `PostingNotAllowed` | `PostingNotAllowed(uint256)` | `0x27dcd12b` | 1 | 保留 |
| `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | `0xea74f32b` | 1 | 保留（契约漏登记，见 E-GC-01） |
| `ContentEmpty` | `ContentEmpty()` | `0x85a5c617` | 1 | 保留 |
| `ContentTooLong` | `ContentTooLong(uint256,uint256)` | `0x9f588bb4` | 1 | 保留 |
| `TooManyMentionedSenderIds` | `TooManyMentionedSenderIds(uint256,uint256)` | `0x3f1035e9` | 1 | 保留 |
| `DuplicateMemberId` | `DuplicateMemberId(uint256)` | `0x1a494813` | 1 | 保留 |
| `MessageNotFound` | `MessageNotFound(uint256,uint256)` | `0xf90c4bc6` | 1 | 保留 |
| `QuotedMessageNotFound` | `QuotedMessageNotFound(uint256,uint256)` | `0xaeb2440f` | 1 | 保留 |
| `MentionAllUnauthorized` | `MentionAllUnauthorized(uint256,uint256)` | `0x340c79cd` | 1 | 保留（命名见 E-GC-04） |
| `ScopeRejected` | `ScopeRejected(uint256,uint256,address)` | `0x425c5f1a` | 1 | 保留 |
| `BanRejected` | `BanRejected(uint256,uint256,address)` | `0x8b4c2330` | 1 | 保留 |
| `ScopeSourceFailed` | `ScopeSourceFailed(uint256,address)` | `0x3b5866a6` | 1 | 保留 |
| `BanSourceFailed` | `BanSourceFailed(uint256,address)` | `0x0200c8c5` | 1 | 保留 |
| `SourceNotContract` | `SourceNotContract(address)` | `0x05dbf84e` | 1 | 保留 |
| `PluginNotContract` | `PluginNotContract(address)` | `0x54752274` | 1 | 保留 |

## 3. 逐错误明细

> “实参赋值”列是 revert 时写入 payload 的表达式；“入口传播”列列出能触发该站点的外部入口。

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `Reentrant()` | `:83` | `nonReentrant` | `_reentrancyStatus != 0` | — | `activateChat`、5 个 setter、`post` |
| 2 | `NotMemberOwner(senderId)` | `:92` | `onlySenderOwner` | `IMemberNFT(GROUP_ADDRESS).ownerOf(senderId) != msg.sender` | `senderId ← 入参` | `post` |
| 3 | `NotGroupOwner(groupId)` | `:99` | `onlyChatOwner` | `msg.sender != _groupOwnerOrRevert(groupId)` | `groupId ← 入参` | `activateChat` |
| 4 | `ChatAlreadyActivated(groupId)` | `:115` | `activateChat` | `config.activated` | `groupId ← 入参` | `activateChat` |
| 5 | `PostingNotAllowed(groupId)` | `:223` | `_post` | `!config.postingAllowed` | `groupId ← 入参` | `post` |
| 6 | `ContentEmpty()` | `:227` | `_post` | `bytes(content).length == 0` | — | `post` |
| 7 | `ContentTooLong(length, maxLength)` | `:230` | `_post` | `bytes(content).length > MAX_CONTENT_LENGTH` | `length ← bytes(content).length`；`maxLength ← MAX_CONTENT_LENGTH = 4096` | `post` |
| 8 | `RoundNotStarted(requiredRound, currentRound)` | `:365` | `currentRound` | `round == 0` | `requiredRound ← 字面量 1`；`currentRound ← round`（`IPhase(PHASE_ADDRESS).currentPhase()`） | `post`（内部调用）；`currentRound()` 公开视图 |
| 9 | `MessageNotFound(groupId, messageId)` | `:373` | `message` | `messageId == 0 \|\| messageId > _messagesByGroupId[groupId].length` | `groupId ← 入参`；`messageId ← 入参` | `message` |
| 10 | `NotGroupOperator(groupId, operatorId)` | `:693` | `onlyGroupOwner` | `operatorId != groupId \|\| msg.sender != owner`；`owner ← _groupOwnerOrRevert(groupId)` | `groupId ← 入参`；`operatorId ← 入参` | `setPostingAllowed`、`setScopeSource`、`setBanSource`、`setBeforePostPlugin`、`setAfterPostPlugin` |
| 11 | `ChatNotActivated(groupId)` | `:701` | `_checkActivated` | `!_chatConfig[groupId].activated`（先前 `_groupOwnerOrRevert`） | `groupId ← 入参` | 5 个 setter、`post` |
| 12 | `MentionAllUnauthorized(groupId, senderId)` | `:712` | `_checkMentionAllOperator` | `senderId != groupId && !IGroupAdmin(GROUP_ADMIN_ADDRESS).isAdminId(groupId, senderId)` | `groupId ← 入参`；`senderId ← 入参` | `post`（`mentionAll = true`） |
| 13 | `ScopeRejected(groupId, senderId, source)` | `:761` | `_revertPostSourceReason` | `reason == ScopeRejected`（scope 返回 false） | `groupId`/`senderId ← 入参`；`source ← config.scopeSource` | `post` |
| 14 | `BanRejected(groupId, senderId, source)` | `:764` | `_revertPostSourceReason` | `reason == BanRejected`（ban 返回 true） | `groupId`/`senderId ← 入参`；`source ← config.banSource` | `post` |
| 15 | `ScopeSourceFailed(groupId, source)` | `:767` | `_revertPostSourceReason` | `reason == ScopeSourceFailed`（scope 调用 reverted / 无返回） | `groupId ← 入参`；`source ← config.scopeSource` | `post` |
| 16 | `BanSourceFailed(groupId, source)` | `:770` | `_revertPostSourceReason` | `reason == BanSourceFailed`（ban 调用 reverted / 无返回） | `groupId ← 入参`；`source ← config.banSource` | `post` |
| 17 | `GroupNotExist(groupId)` | `:817` | `_groupOwnerOrRevert` | `owner == address(0)`；`owner ← MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId)` | `groupId ← 入参` | 见 §3.2.3 |
| 18 | `SourceNotContract(dependency)` | `:823` | `_checkSourceAddress` | `sourceAddress != address(0) && sourceAddress.code.length == 0` | `dependency ← 入参 scopeSourceAddress / banSourceAddress` | `activateChat`（两处）、`setScopeSource`、`setBanSource` |
| 19 | `PluginNotContract(dependency)` | `:829` | `_checkPluginAddress` | `pluginAddress != address(0) && pluginAddress.code.length == 0` | `dependency ← 入参 beforePostPluginAddress / afterPostPluginAddress` | `activateChat`（两处）、`setBeforePostPlugin`、`setAfterPostPlugin` |
| 20 | `TooManyMentionedSenderIds(length, maxLength)` | `:838` | `_checkMentionedSenderIds` | `mentionedSenderIds.length > MAX_MENTIONED_SENDER_IDS` | `length ← mentionedSenderIds.length`；`maxLength ← MAX_MENTIONED_SENDER_IDS = 32` | `post` |
| 21 | `DuplicateMemberId(memberId)` | `:845` | `_checkMentionedSenderIds` | `mentionedSenderIds[j] == mentionedSenderId`（`j < i`） | `memberId ← mentionedSenderIds[i]` | `post` |
| 22 | `QuotedMessageNotFound(groupId, messageId)` | `:929` | `_checkQuotedMessageId` | `quotedMessageId > _messagesByGroupId[groupId].length` | `groupId ← 入参`；`messageId ← quotedMessageId` | `post` |

### 3.2 关键路径说明

#### 3.2.1 鉴权族：`Reentrant` / `NotMemberOwner` / `NotGroupOwner` / `NotGroupOperator`

- modifier 顺序：写入口统一 `nonReentrant` 在前，因此重入失败先于鉴权失败；这不泄露身份或群状态。
- `post`：`onlySenderOwner` 直接调用 `IMemberNFT.ownerOf(senderId)`。senderId 缺失时由 MemberNFT 透传 `ERC721NonexistentToken(senderId)`，非 owner 时回 `NotMemberOwner(senderId)`，与 03-posting:7、07-events-errors:27 一致。
- `activateChat`：`onlyChatOwner` 先经 `_groupOwnerOrRevert`（缺失群 → `GroupNotExist`），再比较 `msg.sender`；不是 owner 回 `NotGroupOwner(groupId)`。`activateChat` 函数体 `:111` 再次调用 `_groupOwnerOrRevert` 取得 `owner` 快照，属重复外部读取（E-GC-06）。
- 5 个配置 setter：`onlyGroupOwner(groupId, operatorId)` 同时校验 `operatorId == groupId` 与 `msg.sender == owner`，任一不满足回 `NotGroupOperator(groupId, operatorId)`。运营上 `operatorId != groupId` 与“非 owner”共用 selector，但 payload 两个键都能自证（E-GC-05）。

#### 3.2.2 `RoundNotStarted(1, 0)`

- `currentRound()` 读 `IPhase.currentPhase()`；core `Phase.currentPhase()` 在 origin 之前返回 0（不 revert），因此这里以 `requiredRound = 1` 回滚。
- `post` 在引用校验之后、规则槽位之前调用 `currentRound()`（`:238`），是 03-posting 八步顺序里唯一没有登记的一步（E-GC-01）。
- `canPost` 不调用 `currentRound()`，`PostRejectionReason` 也没有对应成员；Phase 未开始时预检查会返回 `(true, None)` 而 `post` 回滚。

#### 3.2.3 `GroupNotExist` 的入口传播

`_groupOwnerOrRevert` 被四类路径复用，均回同一个 `GroupNotExist(groupId)`：

| 路径 | 覆盖入口 |
| --- | --- |
| `onlyChatOwner` | `activateChat` |
| `_checkActivated` | 5 个 setter、`post` |
| `_checkExistingGroup` | `isPostingAllowed`、`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`、`message`、`messages`、`messagesByRound`、`messagesBySenderId`、`messageIdsBySenderId`、`messagesByMentionedSenderId`、`messageIdsByMentionedSenderId`、`mentionAllMessages`、`mentionAllMessageIds`、`senderIds`、`rounds`、`roundInfo`、`roundInfosByRounds` |
| `_chatInfo` | `chatInfo`、`chatInfosByGroupIds`（任一缺失整笔回滚，04-query:36） |

`canPost` 是唯一不 revert 的群查询：缺失群返回枚举 `PostRejectionReason.GroupNotExist`（03-posting:51）。

#### 3.2.4 scope/ban 四错误

- `_postSourceRejection` 以 `PostRejectionReason` 返回结果，`_checkPostSources` 仅在 `reason != None` 时调用 `_revertPostSourceReason`；`_canPost` 复用同一判定但不 revert。
- 四个 revert 的 `source` 实参在 `_revertPostSourceReason` 内重新读取 `config.scopeSource` / `config.banSource`。`post` 为 `nonReentrant`，配置 setter 也是 `nonReentrant`，外部源无法在判定与 revert 之间改写槽位，赋值稳定。
- scope 先于 ban；scope 拒绝后不再检查 ban（`_postSourceRejection` 早返回），与 02-rules:12-16 的顺序一致。
- `senderId == groupId` 时直接返回 `None`，跳过 scope/ban，与 02-rules:18 一致。
- 兜底 `assert(false)`（`:772`）不可达；若枚举新增成员而忘记分支，会以 Panic 0x01 暴露，符合 §8。

#### 3.2.5 `SourceNotContract` / `PluginNotContract`

- 只校验“非零且无代码”；零地址表示槽位关闭（01-lifecycle:5、02-rules:3-8）。
- `activateChat` 在一次调用里对两个 source 和两个 plugin 各调用一次；同一错误最多出现 4 次但只回第一个失败地址。
- 只校验代码，不校验接口实现；误配在发言期表现为 `ScopeSourceFailed` / `BanSourceFailed`（05-chat-types:26 已写明“setBanSource 只校验地址有代码”）。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-GC-01 | Low | `src/GroupChat.sol:238`、`:362-367`、`:775-808` | `post` 在引用校验后调用 `currentRound()`，Phase 未开始（`currentPhase() == 0`）时回 `RoundNotStarted(1, 0)`；03-posting 的 8 步校验顺序没有这一步，`canPost` 也不检查轮次且 `PostRejectionReason` 无对应成员。结果是预检查返回 `(true, None)`、写入却回滚，失败集合在预检查与写入之间不一致。 | §5（每个写入口写明校验顺序与错误集合）；§8（预检查返回封闭枚举） | **已由 api-auth 卷 `GC-01` / state 卷 `GCH-01` 关闭**：03-posting:14 补第 8 步，03-posting:52 写明 `canPost` 不覆盖轮次门 |
| E-GC-02 | Low | `src/GroupChat.sol:240-244` | `beforePostPlugin` 直接调用，插件 revert 原样冒泡；`post` 的 ABI 因此可能携带任意 revert data，且该 selector 可能与 `IGroupChatErrors` 混淆。规格只写“整笔发言回滚”，未按 §7 声明“可能携带任意 revert data”。 | §7（不可信回调冒泡时规格声明任意 revert data） | 已登记：03-posting:28「before 插件 revert 原样冒泡，可能不携带自定义 selector」 |
| E-GC-03 | Info | `src/GroupChat.sol:83` | `Reentrant` 没有直接 `expectRevert` 用例；唯一断言在 `testT075` 的 `AfterPostPluginFailed.errorSelector` 中（`test/GroupChatPlugins.t.sol:490`）。守卫行为被证明，但不是独立的失败契约用例。 | §9（每个可达错误一条 selector + 载荷断言） | 已知边界，不处理：捕获 selector 已间接断言；07-events-errors 已登记该口径 |
| E-GC-04 | Info | `src/interfaces/IGroupChat.sol:40-43` | `MentionAllUnauthorized` 不在 §3 的句式表内：§3 要求角色鉴权用 `Not<Role>Owner/Operator`；这里承载“sender 既不是群本身也不是有效 admin”的复合角色。名字可读且已进 ABI，但属存量偏差。 | §3（句式表与禁用前缀） | 已登记：07-events-errors 错误表旁注「沿用既有语义，不改名」 |
| E-GC-05 | Info | `src/GroupChat.sol:687-696` | `NotGroupOperator` 同 selector 覆盖两个条件：`operatorId != groupId` 与 `msg.sender != owner`。payload 含两个键，调用方可自证；01-lifecycle:7 与 07-events-errors:29 已明示这是复合群鉴权。 | §2（一条件一错误）；§4（主体键） | 已知边界，不处理：07-events-errors 已明示复合鉴权，不拆 ABI |
| E-GC-06 | Info | `src/GroupChat.sol:97-102`、`:110-111` | `activateChat` 的 modifier 已调用 `_groupOwnerOrRevert`，函数体 `:111` 再次调用取 `owner`，同一次激活多一次 `ownerOf` 外部调用。错误语义不受影响。 | 无（Gas / 一致性） | 已知边界，不处理：01-lifecycle:5 已登记重复解析 owner 的口径 |
| E-GC-07 | Info | 全模块 | 透传面只在 07-events-errors:25 用一段全局声明登记 `ERC721NonexistentToken`（来源 MemberNFT）与 `SafeERC20FailedOperation`，没有按 §1 给每个模块一张“透传来源”表；`post` 的 before 插件任意数据、Phase 依赖也未进表。 | §1（每个模块一张透传来源表） | 已登记：07-events-errors「按模块登记透传面」段 |
| E-GC-08 | Info | `src/GroupChat.sol:114-121`、配置 setter | 配置入口先校验 `activated` 再校验依赖地址代码；§5 默认顺序为「鉴权 → 参数 → 存在性 → 状态/资格」，规格只写顺序未写理由。 | §5（自定义顺序须写明理由） | 已登记：01-lifecycle:5「有意顺序与理由」 |

### 4.2 已核对项

- 声明全部在 `IGroupChatErrors`；实现零声明；无跨仓错误导入；无裸 `require`/`revert`。
- 22 个站点全部命中本模块声明；每个声明至少一个站点；无死声明。
- 校验顺序：鉴权 → 群存在/激活 → 发言开关 → 正文 → 提及 → mentionAll → 引用 → 轮次 → 规则槽位 → before → 写消息 → 事件 → after；除轮次外与 03-posting:5-16 逐条一致。
- `post` 的鉴权先于群状态：非持有人只拿到 `NotMemberOwner` / `ERC721NonexistentToken`，不能探测群是否存在（03-posting:16）。
- `canPost` 使用封闭枚举，不用错误 selector 作返回值；缺失群/缺失 sender 分别返回 `GroupNotExist` / `SenderNotExist`（§8、03-posting:51）。
- `MessageNotFound` 覆盖 `messageId == 0` 与越界两值，04-query:38 已明示；属“记录不存在”的单条件。
- `DuplicateMemberId` 在提及数组中按首个重复元素回滚；数组上限 32，O(n²) 有界。
- 配置 setter 幂等：相同值直接返回，不发事件（01-lifecycle:7、§6）。
- `afterPostPlugin` 失败被捕获，事件只写 `errorHash` / `errorLength` / `errorSelector`（07-events-errors:55），无无界 `bytes`。
- 测试：`forge test` 151 passed / 0 failed；`check_error_tests.py` group-chat 34/34 有引用；`check_errors.py --check` 0 violations；`check_caller_auth.py --check` 0 violations。

### 4.3 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `MemberNFT.ownerOf` | `ERC721NonexistentToken(memberId)` | `post`（senderId、mentionedSenderIds）、`onlySenderOwner` | 07-events-errors:25、03-posting:7/11 |
| `IBeforePostPlugin.beforePost` | 任意 revert data（原样冒泡） | `post` | 03-posting:28（E-GC-02） |
| `IAfterPostPlugin.afterPost` | 任意 revert data（被捕获为 `AfterPostPluginFailed`） | `post` | 03-posting:25-27 |
| `IPhase.currentPhase` | 无（返回 0） | `post`、`currentRound` | 04-query:5 |
| `IGroupAdmin.isAdminId` | 无自身错误；依赖无代码时为空 revert（部署门禁） | `post`（mentionAll） | 07-events-errors:25（按模块透传表） |
| `MemberOwner.ownerOrZero` | 无（映射为地址 0） | `_groupOwnerOrRevert` | MemberOwner 库注释 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
env -u PYTHONPATH python3 ../matt-gov/script/check_caller_auth.py --check
forge test
```

> 扫描口径：`src/GroupChat.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 前最近的 `if`（无 `if` 的循环兜底单独注明）。声明行号取 `src/interfaces/IGroupChat.sol`。
