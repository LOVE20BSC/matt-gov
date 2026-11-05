# GroupChat · 状态变量变更审查

> `group-chat/src/GroupChat.sol`，951 行，基线 `group-chat@e982df8`（工作树干净）。
> 本合约是四个主合约中唯一带重入锁的合约；所有消息、索引和轮次状态都是 append-only，没有任何 `delete` / `pop`。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `MAX_CONTENT_LENGTH` | `uint256 constant = 4096` | 正文上限（协议常量） | 编译期 |
| 2 | `MAX_MENTIONED_SENDER_IDS` | `uint256 constant = 32` | 单条消息提及上限 | 编译期 |
| 3 | `GROUP_ADMIN_ADDRESS` | `address immutable` | GroupAdmin 依赖 | 构造 |
| 4 | `GROUP_ADDRESS` | `address immutable` | MemberNFT / 群身份来源 | 构造（从 `IGroupAdmin.GROUP_ADDRESS()` 派生） |
| 5 | `PHASE_ADDRESS` | `address immutable` | 轮次来源 | 构造 |
| 6 | `_chatConfig` | `mapping(uint256 => ChatConfig)` | 每群配置与首次激活快照 | `activateChat:123-133`、`setPostingAllowed:160`、`_setSource:553,562`、`_setPostPlugin:590,599` |
| 7 | `_messagesByGroupId` | `mapping(uint256 => MessageRecord[])` | 消息正文与元数据，ID = 下标 + 1 | `_storeMessage:860-871` |
| 8 | `_messageIndexesByGroupIdBySenderId` | `mapping(uint256 => mapping(uint256 => uint256[]))` | sender 维度的消息下标 | `_post:252` |
| 9 | `_messageIndexesByGroupIdByMentionedSenderId` | `mapping(uint256 => mapping(uint256 => uint256[]))` | 被提及者维度的消息下标 | `_storeMessage:876` |
| 10 | `_mentionAllMessageIndexesByGroupId` | `mapping(uint256 => uint256[])` | `mentionAll` 消息下标 | `_storeMessage:879` |
| 11 | `_senderIdsByGroupId` | `mapping(uint256 => uint256[])` | 发过言的 senderId，按首次发言顺序 | `_post:250` |
| 12 | `_roundStateByGroupIdByRound` | `mapping(uint256 => mapping(uint256 => RoundState))` | 每轮消息区间 | `_recordRound:613-619` |
| 13 | `_roundsByGroupId` | `mapping(uint256 => uint256[])` | 有消息的轮次，按首条消息顺序 | `_recordRound:615` |
| 14 | `_groupIds` | `uint256[]` | 已激活群列表，按激活顺序 | `activateChat:126` |
| 15 | `_reentrancyStatus` | `uint256` | 0 = 空闲，1 = 执行中 | `nonReentrant:85,87` |

`ChatConfig` 的 9 个字段只在 `activateChat` 一次性初始化，之后只有 `postingAllowed` 与四个地址槽位可改：

| 字段 | 首次写入 | 后续写入 |
| --- | --- | --- |
| `activated` | `:128` | 无 |
| `postingAllowed` | `:129` | `setPostingAllowed:160` |
| `firstActivatedOwner` | `:123` | 无 |
| `firstActivatedBlockNumber` | `:124` | 无 |
| `firstActivatedTimestamp` | `:125` | 无 |
| `scopeSource` | `:130` | `_setSource:553` |
| `banSource` | `:131` | `_setSource:562` |
| `beforePostPlugin` | `:132` | `_setPostPlugin:590` |
| `afterPostPlugin` | `:133` | `_setPostPlugin:599` |

## 2. 逐变量变更逻辑

### 2.1 `_chatConfig`

#### `activateChat`（`:104-145`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | 修饰器 `:110` | `nonReentrant` + `onlyChatOwner` | owner 必须是 `MemberNFT.ownerOf(groupId)`；不存在回 `GroupNotExist(groupId)` |
| 2 | `:113-116` | 读 `config`，`activated` 已为 true 则回 `ChatAlreadyActivated` | 一次性激活 |
| 3 | `:118-121` | 四个槽位分别做 `_checkSourceAddress` / `_checkPluginAddress` | 非零地址必须有代码；零地址放行 |
| 4 | `:123-126` | 写首次快照三字段 + `_groupIds.push(groupId)` | 无外部状态调用，整笔同回滚 |
| 5 | `:128-133` | `activated = true`、`postingAllowed = true`、四个槽位写入 | 同上 |
| 6 | `:135-144` | `GroupChatActivated` 事件 | 事件在全部写入之后 |

关键点：

- `_groupIds.push` 在 `activated = true` 之前，但两者之间没有外部调用；任何后续失败都会整笔回滚，因此外部观察不到“已加入列表但未激活”的中间态。
- `firstActivatedOwner` 是**首次激活时**的 owner；群 NFT 后续转移不会改写这三个快照字段，`chatInfo` 同时返回当前 `owner` 与历史快照，语义不混淆。
- `postingAllowed` 首次写入固定为 `true`，本合约没有“以暂停态激活”的入参；若 owner 需要暂停，只能激活后再调 `setPostingAllowed(false)`（见 `GCH-04`）。

#### 配置 setter（`:147-199`、`:536-608`）

| 函数 | 位置 | 守卫 | 写前校验 | 写后事件 | 幂等 |
| --- | --- | --- | --- | --- | --- |
| `setPostingAllowed` | `:147-167` | `nonReentrant` + `onlyGroupOwner` | `_checkActivated(groupId)` | `PostingAllowedChanged` | 同值直接 `return`，不写不发 |
| `setScopeSource` / `setBanSource` | `:169-183` → `_setSource:536-571` | 同上 | `_checkActivated` + `_checkSourceAddress` | `ScopeSourceChanged` / `BanSourceChanged` | 同地址直接 `return` |
| `setBeforePostPlugin` / `setAfterPostPlugin` | `:185-199` → `_setPostPlugin:573-608` | 同上 | `_checkActivated` + `_checkPluginAddress` | `BeforePostPluginChanged` / `AfterPostPluginChanged` | 同地址直接 `return` |

`onlyGroupOwner`（`:687-696`）要求 `operatorId == groupId` 且 `msg.sender == owner`；`operatorId` 只作为事件字段，不能把管理员提升为配置操作者。

### 2.2 `_messagesByGroupId`

`_storeMessage`（`:851-881`）是唯一写入点：

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:860` | `messageIndex = length` | ID 由长度现算，结构上连续无空洞 |
| 2 | `:861` | `push()` | 先追加空记录 |
| 3 | `:864-871` | 写 `senderId` / `senderAddress` / `content` / `blockNumber` / `timestamp` / `round` / `mentionAll` / `quotedMessageId` | `senderAddress = msg.sender`，即调用时的 NFT owner |
| 4 | `:873-877` | 每条提及写 `storedMessage.mentionedSenderIds.push` 与提及索引 | 提及列表已在 `:232` 校验（≤32、去重、NFT 存在） |
| 5 | `:878-880` | `mentionAll` 时写 mention-all 索引 | `:233-235` 已校验 owner / 有效 admin |

`_storeMessage` 本身不做业务校验，所有校验在 `_post:220-239` 完成；`_post` 由 `post` 的 `nonReentrant` + `onlySenderOwner` 保护，写入之后才调用 `afterPostPlugin`。

### 2.3 `_messageIndexesByGroupIdBySenderId`

`_post`（`:249-252`）：

```solidity
if (_messageIndexesByGroupIdBySenderId[groupId][senderId].length == 0) {
    _senderIdsByGroupId[groupId].push(senderId);
}
_messageIndexesByGroupIdBySenderId[groupId][senderId].push(messageIndex);
```

- “首次发言”判定依赖该 sender 的索引数组长度为 0；`_storeMessage` 不写这个数组，所以判定不会被本笔刚写入的消息污染。
- `_senderIdsByGroupId` 与 sender 索引数组在同一段代码内，前者只在首次 push；消息从不删除，所以不存在“索引清空后重复 push senderId”的路径。

### 2.4 `_messageIndexesByGroupIdByMentionedSenderId`

唯一写入点 `_storeMessage:876`，在消息记录 push 之后按入参顺序逐条写入。每条提及同时写入消息内的 `mentionedSenderIds` 数组和反向索引，二者在同一循环、同一笔交易内完成，不会出现“消息有提及但反查索引缺失”。

### 2.5 `_mentionAllMessageIndexesByGroupId`

唯一写入点 `_storeMessage:879`，条件为 `mentionAll == true`。`mentionAll` 的鉴权在 `:233-235`，且 `_emitMessagePosted` 的 `mentionAll` 字段直接读存储，二者同源。

### 2.6 `_senderIdsByGroupId`

唯一写入点 `_post:250`，条件是该 sender 的索引数组为空。append-only，首次发言顺序。`senderIds` 查询页（`:479-488`）只读该数组，不改写。

### 2.7 `_roundStateByGroupIdByRound`

`_recordRound`（`:610-620`）：

| 分支 | 位置 | 写入 | 说明 |
| --- | --- | --- | --- |
| 该轮首条消息 | `:612-616` | `startIndexPlusOne = messageIndex + 1`、`endIndex = messageIndex`、`_roundsByGroupId.push(round)` | 用 `startIndexPlusOne == 0` 兼作“本轮尚无消息” |
| 该轮后续消息 | `:619` | `endIndex = messageIndex` | 只扩右端 |

成立前提：`currentRound()` 单调不减（`Phase.currentPhase()` 只依赖 `block.number`，`Phase.sync` 只记录未来段，见 §4.3），因此同一轮的消&#24687;一定连续，后一轮不会回写到前一轮。

### 2.8 `_roundsByGroupId`

唯一写入点 `_recordRound:615`，只在该轮首条消息时 push。`startIndexPlusOne` 的非零判定同时保证同轮不会重复 push。

### 2.9 `_groupIds`

唯一写入点 `activateChat:126`。`activated` 的 one-shot 检查保证同一 groupId 不会重复 push；群聊没有停用/删除入口，列表只增不减。

### 2.10 `_reentrancyStatus`

`nonReentrant`（`:81-88`）在进入时写 1、退出时写 0。`activateChat`、`setPostingAllowed`、四个槽位 setter、`post` 共 7 个外部可变入口全部使用该修饰器；`post` 内部的 `beforePostPlugin` / `afterPostPlugin` 回调因此不能重入任何 GroupChat 写入口（`testT075_afterPostReenterIsBannedByNonReentrant` 覆盖）。回滚交易会连状态一起撤销，不存在残留 1 的路径。

## 3. 写入顺序与不可分割性

### 3.1 `post` / `_post`（`:201-295`）

```text
nonReentrant + onlySenderOwner
  -> 激活 / postingAllowed / 正文 / 提及 / mentionAll / 引用
  -> currentRound
  -> scopeSource -> banSource
  -> beforePostPlugin（外部调用，失败整笔回滚）
  -> _storeMessage（消息 + mention 索引 + mentionAll 索引）
  -> sender 索引 / _senderIdsByGroupId
  -> _recordRound
  -> MessagePosted / SenderMentioned 事件
  -> afterPostPlugin（try/catch，失败只发事件）
```

- 所有 GroupChat 状态写入都在 `afterPostPlugin` **之前**；after 插件失败不会回滚消息，符合规格 `03-posting.md`。
- `beforePostPlugin` 在状态写入前，失败整笔回滚；期间即使插件尝试重入，`_reentrancyStatus == 1` 会回 `Reentrant`，被外层 `try` 捕获为插件失败（after）或直接回滚（before）。
- 消息、提及索引、sender 索引、轮次状态、事件顺序严格按上表；任一步 revert 都撤销前面所有写入。

### 3.2 配置写入顺序

`activateChat` 与四个 setter 都是“鉴权 → 存在性/激活状态 → 地址代码校验 → 写状态 → 发事件”，写状态之前没有外部状态变更调用；`_checkSourceAddress` / `_checkPluginAddress` 只读 `code.length`，不会产生回调。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `GCH-01` | Low | `canPost` 不检查 `RoundNotStarted`：Phase 启动前返回 `(true, None)`，实际 `post` 回 `RoundNotStarted` | E1 |
| `GCH-02` | Info | 四个槽位只校验 `code.length`，不校验接口实现；误配 scope/ban/before 插件会让全部发言失败，owner 可通过 setter 修复 | E1 |
| `GCH-03` | Info | source 的 `try/catch` 只捕获调用 revert；带 fallback 的合约返回空/畸形数据时，ABI 解码失败在调用方抛出，不进入 `catch`，表现为原始 revert 而非 `ScopeSourceFailed` / `BanSourceFailed` | E1 |
| `GCH-04` | Info | `activateChat` 固定把 `postingAllowed` 初始化为 `true`，没有“以暂停态激活”的入参；需要暂停只能第二笔交易设置 | E1 |
| `GCH-05` | Info | `chatInfosByGroupIds` / `roundInfosByRounds` 是整批 all-or-nothing；分页 `limit` 无协议上限，调用者自担 gas | E1 |
| `GCH-06` | Info | `_setSource` / `_setPostPlugin` 的同地址 no-op 仍先做代码校验；若该地址已无代码，重复设置同一地址会回 `SourceNotContract` / `PluginNotContract`，需改为设置零地址或新地址 | E1 |

逐条说明：

- **`GCH-01`**：`canPost`（`:775-808`）检查群存在、激活、发言开关、sender 存在、scope/ban，但不调用 `currentRound()`；`post` 在 `:238` 调用 `currentRound()`，Phase 未启动时回 `RoundNotStarted(1,0)`。`canPost` 是明确的部分预检查（不校验正文/提及/引用/插件），所以这是“预检查可乐观”的边界，不是状态写入缺陷。
  同 `GC-01`（Low），处置见 `review/group-chat-api-auth-2026-11/01-group-chat.md` 与 `matt-gov/docs/specs/group-chat/03-posting.md`。
- **`GCH-02`**：`:118-121` 与 `_setSource` / `_setPostPlugin` 只保证地址有代码。`scopeSource` / `banSource` 误配时 `post` 在 source 阶段失败（fail-closed）；`beforePostPlugin` 误配时每笔发言直接回滚；`afterPostPlugin` 误配只产生 `AfterPostPluginFailed`，消息仍保留。owner 可随时改回，故不构成不可恢复状态。
- **`GCH-03`**：Solidity 的 `try/catch` 捕获外部调用 revert；返回数据解码失败发生在当前合约，不进入 `catch`。因此一个“有代码、fallback 返回空/非 ABI 数据”的 source 会让 `post` 和 `canPost` 以原始 ABI 错误回滚，而不是文档里的 `ScopeSourceFailed` / `BanSourceFailed`。source 由 owner 配置，影响限于错误语义。
- **`GCH-04`**：若 owner 希望“开放 scope + 暂停发言”，先 `activateChat`（postingAllowed=true）再 `setPostingAllowed(false)` 之间存在一个区块窗口；用临时 scope/ban 可以规避，但协议没有原子入参。
- **`GCH-05`**：`chatInfosByGroupIds`（`:301-309`）在任一 groupId 缺失时整批回滚；`messages` / `rounds` 等分页的 `limit` 不设上限，返回内存大小由调用者选择。两者都是查询语义，不影响写入。
- **`GCH-06`**：`_setSource` 在 `:543` 先 `_checkSourceAddress`，再在 `:547` 判断同地址；`_setPostPlugin` 同理。正常的“同一地址重复设置”在地址仍有代码时确实 no-op；只有地址已失去代码时才变成 revert。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| `_post` 在 `beforePostPlugin` 之前就取 `round`，插件若推进 Phase 是否会让消息落错轮 | `Phase.currentPhase()` 只依赖 `block.number`；`Phase.sync` 只写 `phase + 1` 的未来段（`Phase.sol:86-132,147-156`），同一交易内当前轮不会变化 |
| `beforePostPlugin` 能否在写入前重入并改 GroupChat 状态 | 7 个可变入口全部 `nonReentrant`；重入会被 `Reentrant` 拒绝，before 路径整笔回滚 |
| `afterPostPlugin` 失败是否回滚消息 | 不会；规格明确要求保留消息并只发 `AfterPostPluginFailed`，测试 `testT072` 覆盖 |
| `_senderIdsByGroupId` 的“首次发言”判定在 `_storeMessage` 之后是否会被污染 | `_storeMessage` 不写 sender 索引数组，判定读取的仍是本笔之前的长度 |
| 单条消息时 `RoundState.endIndex < startIndex` 是否会让 `messageCount` 下溢 | 首条消息写入 `startIndexPlusOne = index + 1`、`endIndex = index`；`endIndex - (startIndexPlusOne - 1) + 1 = 1`，无下溢 |
| `activateChat` 先 push `_groupIds` 再写 `activated` 是否可观察到半完成 | 两步之间没有外部调用；任何 revert 整笔回滚 |
| `messagesByRound` 是否可能读到非连续区间 | 轮次单调，消息 append-only，同轮消息必然连续（见 §2.7） |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| C1 | `_groupIds` 恰好是 `activated == true` 的 groupId 集合，无重复、按激活顺序 | ✅ | `activated` one-shot + `:126` 同笔 push |
| C2 | 消息 ID 恰为 `1.._messagesByGroupId[g].length`，无空洞 | ✅ | `messageIndex = length`，只 push |
| C3 | `_senderIdsByGroupId[g]` 恰好是发过至少一条消息的 sender，按首次发言顺序 | ✅ | `:249-252` 首次判定 + append-only |
| C4 | `_messageIndexesByGroupIdBySenderId` / `...ByMentionedSenderId` / `_mentionAll...` 的每个下标都指向存在的消息，且与消息内容一致 | ✅ | 三个索引都在 `_storeMessage` / `_post` 同一笔写入，消息从不删除 |
| C5 | `_roundsByGroupId[g]` 恰好是有消息的轮次，按首条消息顺序，无重复 | ✅ | `startIndexPlusOne == 0` 判定 + append-only |
| C6 | 每个 `RoundState` 的区间恰为该轮消息的连续下标，`messageCount = endIndex - startIndex + 1` | ✅ | `_recordRound` 只扩右端；轮次单调（§4.2） |
| C7 | `activated == true` 的群，`firstActivated*` / 四个槽位均已初始化；未激活群不暴露这些值 | ✅ | `activateChat` 一次性写入；查询按 `activated` 分支 |
| C8 | 所有配置写入只接受群 owner 且 `operatorId == groupId`；所有发言写入只接受 sender NFT 当前 owner | ✅ | `onlyGroupOwner` / `onlySenderOwner` |
| C9 | 任一时刻最多一个 GroupChat 可变入口在执行 | ✅ | `_reentrancyStatus` 覆盖 7 个入口 |
| C10 | 消息、提及、sender、round 四类索引与消息正文在同一笔交易内一致 | ✅ | `_post` 单函数内顺序写入，无外部状态变更插在中间 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| Phase 启动前的 `canPost` | 现有 `testT001` 只验证 `currentRound()` 回 `RoundNotStarted`；未锁定 `canPost` 在 Phase 0 的返回 |
| source 返回畸形数据 | 现有测试只覆盖 source revert / 返回 false，没有 fallback 返回空数据的错误路径 |
| 群 NFT 转移后的配置继承 | 测试覆盖 owner 转移后的 admin 失效，未覆盖 GroupChat 配置槽位随 NFT 转移的语义（代码上由 `onlyGroupOwner` 自然继承） |
| after 插件畸形返回 | after 插件无返回值，不存在解码路径；未测试 |

### 4.5 结论

未发现 Critical / High / Medium。`_chatConfig` 的每次写入都有 owner + `operatorId == groupId` 鉴权，`activated` one-shot；消息与四类索引、轮次状态在同一笔交易内写入，append-only，不存在删除/回填路径；`post` 的状态写入全部在外部 after 回调之前，before 回调之前无状态写入，且全入口有重入锁。`GCH-01` 为 Low（`canPost` 预检查可乐观）；其余 5 条 Info 均为配置信任、错误语义或查询边界，不改变账本一致性。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `GCH-01` | 同 api-auth 卷 `GC-01`，Low，A（文档已落地）；原处置行保留 | `docs/specs/group-chat/03-posting.md` |
| `GCH-02` | 由 api-auth 卷 `GC-02` 关闭，文档已落地 | `docs/specs/group-chat/01-lifecycle.md`、`06-manager.md` |
| `GCH-03` | A（文档）：声明不可解码返回以原始 ABI 解码错误冒泡 | `02-rules.md`「顺序与例外」、`07-events-errors.md`「命名与迁移规则」（L55） |
| `GCH-04` | 登记：无「以暂停态激活」入参 | `01-lifecycle.md`「激活与配置」 |
| `GCH-05` | 登记：`limit` 与批量入参无协议上限 | `04-query.md`「边界」 |
| `GCH-06` | 登记：no-op 判断在代码校验之后 | `01-lifecycle.md`「激活与配置」 |

### 4.7 卷级汇总（2026-11-05）

- 原 40 条：`Low` 1（`GCH-01`，保留原处置行）、`Info` 39（自测）。
- 处置分布：api-auth 已覆盖并关闭 2 条（`GCH-01`、`GCH-02`）；文档登记 35 条（其中既有文本已覆盖 8 条）；裁决 3 条（`GCH-03` A、`GAD-01` A、`TAM-01` B）。计数与原表一致，无新增/降级。
- 补充审查：`04-group-chat-ban-list.md` §5 新增 `GVB-01..06`，6 项核对不计入原 40 条；其中 5 项成立、`GVB-02` 仅实时口径不成立（规格已声明的结算过期）。
- 代码变更：仅 `TAM-01`（`TokenActionScopeManagerBase._checkExistingAction` + `testT113C`）；ABI/storageLayout 未变。
