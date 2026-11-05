# GroupChat 事件赋值与发射审查

> 对象 `group-chat/src/GroupChat.sol`（951 行，`contract`）
> 声明 `group-chat/src/interfaces/IGroupChat.sol`（`IGroupChatEvents`，L64-143）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/00–08`、`group-chat/script/events/{event-families,events-baseline}.txt`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 9 |
| 发射点 | 10 |
| 业务状态写入面（不含瞬态锁） | 17 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 2 |
| 放行 | 可放行；2 项 P3 均为测试断言缺口，另有 2 条跨合约项（emitter 断言、`operatorId ≡ groupId` 登记）见 README |

GroupChat 是 group-chat 仓唯一同时承载「Chat 配置」「消息正文」「提及索引」「轮次索引」四类事实的合约。9 个事件没有一条被两个语义复用；配置事件只写 5 个可改槽位与 4 个一次激活字段，消息事件用父事件 `MessagePosted` + 子事件 `SenderMentioned` 表达一条消息及其提及，`AfterPostPluginFailed` 是唯一允许的捕获型失败事件。10 个发射点都在自身状态写入之后，失败整笔回滚；after 插件失败只产生 `AfterPostPluginFailed`，不回滚消息。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `GroupChatActivated` | `groupId`, `ownerId`, `owner` | `activateChat:135` | `_chatConfig` 9 字段 `:123-133`、`_groupIds.push:126` | 返回；托管群由 Manager 随后发 `TokenGroupActivated` |
| `PostingAllowedChanged` | `groupId`, `operatorId`, `operator` | `setPostingAllowed:161` | `config.postingAllowed:160` | 返回 |
| `ScopeSourceChanged` | `groupId`, `sourceAddress`, `operatorId` | `_setSource:554` | `config.scopeSource:553` | 返回 |
| `BanSourceChanged` | `groupId`, `sourceAddress`, `operatorId` | `_setSource:563` | `config.banSource:562` | 返回 |
| `BeforePostPluginChanged` | `groupId`, `pluginAddress`, `operatorId` | `_setPostPlugin:591` | `config.beforePostPlugin:590` | 返回 |
| `AfterPostPluginChanged` | `groupId`, `pluginAddress`, `operatorId` | `_setPostPlugin:600` | `config.afterPostPlugin:599` | 返回 |
| `MessagePosted` | `groupId`, `messageId`, `senderId` | `_emitMessagePosted:938`（由 `_post:256` 调用） | `_storeMessage:246-247`（`:860-880`）、sender 索引 `:249-252`、`_recordRound:254` | 逐条 `SenderMentioned`，再调 after 插件 |
| `SenderMentioned` | `groupId`, `messageId`, `mentionedSenderId` | `_post:258`（循环） | 提及索引已在 `_storeMessage:873-877` 写入 | after 插件 |
| `AfterPostPluginFailed` | `groupId`, `messageId`, `pluginAddress` | `_post:284`（catch） | 无状态写入；after 插件调用在 `:266-277` | 返回 |

族归属：`GroupChatActivated` / `PostingAllowedChanged` / 四个 `*Changed` → `gc.management`；`MessagePosted` / `SenderMentioned` → `gc.message`；`AfterPostPluginFailed` → `gc.plugin`。`script/events/check-events.py` 报 `event manifest OK: 18 events; families OK`（18 为 ABI 条目，含两个 Manager 共享事件的两份声明）。

## 三、逐事件赋值链

### 3.1 `GroupChatActivated`

```
event GroupChatActivated(
    uint256 indexed groupId,
    uint256 indexed ownerId,
    address indexed owner,
    bool postingAllowed,
    address scopeSource,
    address banSource,
    address beforePostPlugin,
    address afterPostPlugin
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:136` | 根键，也是 group 的 memberId |
| `ownerId` | 字面量 `groupId:137` | 协议恒等对：群 owner 的 actor id 恒为 `groupId`，已在 event-standards §8.1 登记 |
| `owner` | `owner = _groupOwnerOrRevert(groupId):111`，事件 `:138` | 首次激活时的 owner；`onlyChatOwner:110` 保证 `msg.sender == owner`；后续 NFT 转移不回写本事件 |
| `postingAllowed` | `config.postingAllowed:139`，写入 `:129` | 激活固定为 `true` |
| `scopeSource` | 入参 `:140`，写入 `:130` | 零地址表示关闭；非零地址已过 `_checkSourceAddress:118` |
| `banSource` | 入参 `:141`，写入 `:131` | 同上 |
| `beforePostPlugin` | 入参 `:142`，写入 `:132` | 非零地址已过 `_checkPluginAddress:120` |
| `afterPostPlugin` | 入参 `:143`，写入 `:133` | 同上 |

关键点：

- `firstActivatedOwner`、`firstActivatedBlockNumber`、`firstActivatedTimestamp` 三个 `ChatConfig` 快照字段不单独进事件：owner 由 `GroupChatActivated.owner` 给出，block/timestamp 由日志元数据给出；`activated = true` 由事件存在隐含，且 `ChatAlreadyActivated:114-116` 保证一次性。
- `_groupIds.push(groupId):126` 在 `activated = true:128` 之前，但两步之间没有外部调用；任何后续 revert 整笔回滚，外部观察不到「已加入列表但未激活」的中间态。
- 事件字段顺序符合 `gc.management`：根键 → 对象（仅根键）→ actor id → actor 地址 → 初始配置组。`ownerId` 与 `groupId` 是已登记恒等对。

### 3.2 `PostingAllowedChanged`

```
event PostingAllowedChanged(
    uint256 indexed groupId,
    uint256 indexed operatorId,
    address indexed operator,
    bool postingAllowed
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:162` | 根键 |
| `operatorId` | 入参 `:163` | `onlyGroupOwner:692` 强制 `operatorId == groupId`，见 `GL-EV-3` |
| `operator` | `msg.sender:164` | 群 owner；与 `owner` 实时解析 |
| `postingAllowed` | 入参 `:165`，写入 `:160` | 同值 `:155-157` 直接返回，不写不发；旧值可由 `!postingAllowed` 推出，故不携带 `prev*` |

### 3.3 `ScopeSourceChanged` / `BanSourceChanged`

```
event ScopeSourceChanged(
    uint256 indexed groupId,
    address indexed sourceAddress,
    uint256 indexed operatorId,
    address operator,
    address prevSourceAddress
);
```

`BanSourceChanged` 与上同形，仅字段名同为 `sourceAddress` / `prevSourceAddress`。

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:555` / `:564` | 根键 |
| `sourceAddress` | 入参 `sourceAddress:556` / `:565`，写入 `:553` / `:562` | 新地址；对象地址槽位 |
| `operatorId` | 入参 `:557` / `:566` | `onlyGroupOwner` 强制等于 `groupId` |
| `operator` | `msg.sender:558` / `:567` | 群 owner |
| `prevSourceAddress` | `config.scopeSource` / `config.banSource` 读取 `:546`，事件 `:559` / `:568` | 旧地址，写前读取；同地址 `:547-549` 返回，不写不发 |

### 3.4 `BeforePostPluginChanged` / `AfterPostPluginChanged`

```
event BeforePostPluginChanged(
    uint256 indexed groupId,
    address indexed pluginAddress,
    uint256 indexed operatorId,
    address operator,
    address prevPluginAddress
);
```

`AfterPostPluginChanged` 同形。

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:592` / `:601` | 根键 |
| `pluginAddress` | 入参 `pluginAddress:593` / `:602`，写入 `:590` / `:599` | 新地址；对象地址槽位 |
| `operatorId` | 入参 `:594` / `:603` | 等于 `groupId` |
| `operator` | `msg.sender:595` / `:604` | 群 owner |
| `prevPluginAddress` | `config.beforePostPlugin` / `config.afterPostPlugin` 读取 `:583`，事件 `:596` / `:605` | 旧地址；同地址 `:584-586` 返回 |

### 3.5 `MessagePosted`

```
event MessagePosted(
    uint256 indexed groupId,
    uint256 indexed messageId,
    uint256 indexed senderId,
    address sender,
    uint256 round,
    uint256 quotedMessageId,
    bool hasQuote,
    bool mentionAll,
    uint256 mentionedSenderCount,
    string content
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:939` | 根键 |
| `messageId` | `messageIndex + 1:940`；`messageIndex = _messagesByGroupId[groupId].length:860` | 每个 Chat 内从 1 连续编号；`_storeMessage:861` 先 push 后填充 |
| `senderId` | `storedMessage.senderId:941`，写入 `:864` | 显式传入；`onlySenderOwner:208` 校验 NFT 当前 owner |
| `sender` | `storedMessage.senderAddress:942`，写入 `:865` | `msg.sender`，只作审计；不被任何资格分支使用 |
| `round` | `storedMessage.round:943`，写入 `:869`；来源 `round = currentRound():238` | 区块级 Phase；同一交易内不会变化 |
| `quotedMessageId` | `storedMessage.quotedMessageId:944`，写入 `:871` | 0 表示无引用；非零已过 `_checkQuotedMessageId:236` |
| `hasQuote` | `storedMessage.quotedMessageId != 0:945` | 有意冗余，与 `quotedMessageId` 严格恒等；`07-events-errors.md` 已登记 |
| `mentionAll` | `storedMessage.mentionAll:946`，写入 `:870` | `true` 已过 `_checkMentionAllOperator:233-235` |
| `mentionedSenderCount` | `storedMessage.mentionedSenderIds.length:947`，写入 `:873-875` | 条数锚点；等于紧随其后的 `SenderMentioned` 条数，`07-events-errors.md` 已登记 |
| `content` | `storedMessage.content:948`，写入 `:866` | 已过非空 `:226-228` 和 `MAX_CONTENT_LENGTH:229-231` |

发射前写入顺序：`_storeMessage:246-247`（消息 + 提及索引 + mentionAll 索引）→ `_senderIdsByGroupId` 首发言判定 `:249-251` → sender 索引 `:252` → `_recordRound:254` → `MessagePosted:256`。`messageIndex` 在 `_storeMessage` 内返回，事件与子事件使用同一个 `messageIndex + 1`；`SenderMentioned` 循环使用同一份 `mentionedSenderIds`，与 `_storeMessage` 写入的条数同源。

`round` 在 `_checkPostSources:239` 与 before 插件 `:240-244` 之前读取；`Phase.currentPhase()` 只依赖 `block.number`，同一交易内不变（`core/src/Phase.sol:62`、`:86-132`），因此不是「事件早于状态」的缺陷。

### 3.6 `SenderMentioned`

```
event SenderMentioned(
    uint256 indexed groupId,
    uint256 indexed messageId,
    uint256 indexed mentionedSenderId
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:259` | 根键 |
| `messageId` | `messageIndex + 1:260` | 同一父消息 |
| `mentionedSenderId` | `mentionedSenderIds[i]:261` | 按入参顺序逐条；重复 ID 已在 `_checkMentionedSenderIds:840-848` 拒绝 |

`SenderMentioned` 在 `MessagePosted` 之后、after 插件之前发射；条数等于父事件 `mentionedSenderCount`，顺序等于入参顺序。其对应的 `_messageIndexesByGroupIdByMentionedSenderId` 写入发生在 `_storeMessage:876`，早于事件。

### 3.7 `AfterPostPluginFailed`

```
event AfterPostPluginFailed(
    uint256 indexed groupId,
    uint256 indexed messageId,
    uint256 round,
    address indexed pluginAddress,
    bytes32 errorHash,
    uint256 errorLength,
    bytes4 errorSelector
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:285` | 根键 |
| `messageId` | `messageIndex + 1:286` | 与 `MessagePosted` / `SenderMentioned` 同一 ID |
| `round` | `round:287`，来源 `:238`；同一交易内不变 | 消息所在轮 |
| `pluginAddress` | `config.afterPostPlugin:288` | 被调用的 after 插件；`nonReentrant` 阻止插件在回调中改配置 |
| `errorHash` | `keccak256(err):289` | 原始 revert 数据的哈希；不写无界 `bytes` |
| `errorLength` | `err.length:290` | 原始数据长度 |
| `errorSelector` | 前 4 字节，`err.length >= 4` 时由 `:278-283` 提取，否则保持 `bytes4(0)` | `errorLength < 4` 时 0 表示「没有 selector」，不是哨兵业务值 |

`AfterPostPluginFailed` 是捕获型失败事件：after 插件在消息、提及事件之后调用（`:265-277`），catch 内只读配置、不发任何状态写入；消息与提及事实保留。`errorHash` / `errorLength` / `errorSelector` 的取值与 `03-posting.md` 的约定一致。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `ChatConfig.activated` | `:128` | `GroupChatActivated`（事件存在即 true） | 一次性，`ChatAlreadyActivated` 挡住重复激活 |
| `ChatConfig.postingAllowed` | `:129`、`:160` | `GroupChatActivated.postingAllowed` / `PostingAllowedChanged` | 最后一次配置事件；同值不发 |
| `ChatConfig.firstActivatedOwner` | `:123` | `GroupChatActivated.owner` | 事件值为首次 owner；后续 NFT 转移不回写 |
| `ChatConfig.firstActivatedBlockNumber` | `:124` | 日志元数据 | 事件所在 block |
| `ChatConfig.firstActivatedTimestamp` | `:125` | 日志元数据 | 事件所在 timestamp |
| `ChatConfig.scopeSource` | `:130`、`:553` | `GroupChatActivated.scopeSource` / `ScopeSourceChanged` | 新值在对象槽，旧值 `prevSourceAddress` |
| `ChatConfig.banSource` | `:131`、`:562` | `GroupChatActivated.banSource` / `BanSourceChanged` | 同上 |
| `ChatConfig.beforePostPlugin` | `:132`、`:590` | `GroupChatActivated.beforePostPlugin` / `BeforePostPluginChanged` | 同上 |
| `ChatConfig.afterPostPlugin` | `:133`、`:599` | `GroupChatActivated.afterPostPlugin` / `AfterPostPluginChanged` | 同上 |
| `_groupIds` | `:126` | `GroupChatActivated` 顺序 | append-only；按事件序即激活序 |
| `_messagesByGroupId` | `:860-880` | `MessagePosted` + `SenderMentioned` | 正文/元数据由父事件，提及列表由子事件；block/timestamp 由日志元数据 |
| `_messageIndexesByGroupIdBySenderId` | `:252` | `MessagePosted` 顺序 | 按 senderId 过滤后的事件序 |
| `_messageIndexesByGroupIdByMentionedSenderId` | `:876` | `SenderMentioned` 顺序 | 按 mentionedSenderId 过滤后的事件序 |
| `_mentionAllMessageIndexesByGroupId` | `:879` | `MessagePosted.mentionAll` | 过滤 `mentionAll = true` 的消息 ID |
| `_senderIdsByGroupId` | `:250` | 首条 `MessagePosted` 的 senderId | 首次出现序，append-only |
| `_roundStateByGroupIdByRound` | `:613-619` | `MessagePosted.round` + `messageId` | 首/末消息 ID 可推出区间 |
| `_roundsByGroupId` | `:615` | 首条 `MessagePosted.round` | 首次出现序，append-only |
| `_reentrancyStatus` | `:85`、`:87` | 无 | 瞬态执行锁，不进入业务投影 |

17 个业务写入面全部有事件覆盖或可由事件 + 日志元数据确定性推导；`_reentrancyStatus` 是 §3.2 豁免的瞬态锁。消息、提及、sender、round 四类索引都在同一笔 `_post` 内、after 插件之前写入，不存在「写了、既不报、也无法推导」的字段。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 9 个事件均以 `groupId` 开头 |
| 族槽位（§6.1） | 通过 | `gc.management`：根键 → 对象 → actor id → actor 地址 → 新值组 → 旧值组；`gc.message`：根键 → messageId → senderId → sender → round → 引用 → 数值/布尔 → content；`gc.plugin`：根键 → messageId → round → pluginAddress → 错误指纹 |
| indexed ≤ 3 且按优先级（§6.3） | 通过 | 7 个事件 3 个 indexed；`MessagePosted` / `SenderMentioned` / `AfterPostPluginFailed` 均 3 个；`scope`/`ban`/插件事件按「对象地址 → actor id」布局，actor 地址入 payload |
| 状态写入后 emit（§3.4.3） | 通过 | 9 个静态发射点的前置写入见第二节；无「先发后写」 |
| 父子序 / 依赖序（§3.4.5-6） | 通过 | `MessagePosted` → `SenderMentioned` → `AfterPostPluginFailed`；`GroupChatActivated` 是配置父事件；托管群 `TokenGroupActivated` 在 `GroupChatActivated` 之后 |
| 批量逐条 emit（§3.4.1） | 通过 | 提及按入参逐条 `SenderMentioned`；配置 setter 单条 |
| 零事实不发事件（§3.5） | 通过 | `setPostingAllowed` 同值 `:155-157`、`_setSource` 同地址 `:547-549`、`_setPostPlugin` 同地址 `:584-586` 均零日志 |
| 失败不留日志（§3.5） | 通过 | 校验/revert 整笔回滚；after 插件失败是唯一捕获型失败，消息事件保留 |
| 动态字段上限（§6.8） | 通过 | `MessagePosted.content` ≤ `MAX_CONTENT_LENGTH = 4096`（`:229-231`）；提及 ≤ `MAX_MENTIONED_SENDER_IDS = 32`（`:837-839`）；`AfterPostPluginFailed` 无 `bytes` / 动态数组 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 报 `declaration style OK; emit style OK; emit keys OK` |
| §6.9 派生缓存 | 通过 | 四类消息索引、轮次区间、sender 排序、`_groupIds` 均可由事件流推导；`firstActivated*` 由事件 + 日志元数据推导 |
| 测试断言（§8.1） | 通过（本卷已闭合） | 所有事件至少一个用例；`GC-EV-1` / `GC-EV-2` / `GC-EV-3` 已补测试；本合约 9 个事件类的 emitter 断言已补齐（`GL-EV-1`） |

## 六、发现

### GC-EV-1（P3）`AfterPostPluginFailed` 的字段与边界断言不完整

- 证据：`testT072`（`test/GroupChatPlugins.t.sol:403-442`）只断言 `logs[1].topics[0]` 与 `logs[0]` 的字段；在全新 Chat 中 `messageId = 1`、`round = 1`，二者同值，交换字段的回归不会被发现；`pluginAddress` 是第三个 indexed topic，但 `topics[3]` 从未断言。`testT075`（`:469-491`）只断言 `topics[1]` / `topics[2]` 与 `errorSelector`，未断言 `round` / `pluginAddress`。`testT076`（`:493-510`）只断言 `topics[0]`。三条用例都没有覆盖 `err.length < 4` 的 `errorSelector = 0` 分支，也没有空 revert 数据。
- 问题：§8.1 要求每个事件至少断言发射条件、次数、字段顺序、indexed 布局与字段取值；`messageId` / `round` 取值不可区分，`pluginAddress` 未断言，`errorSelector` 的短数据分支未断言。§4.1 还要求断言 emitter，现有用例只断言 topic0（见 `GL-EV-1`）。
- 影响：若 `_post:284-292` 把 `messageId` 与 `round` 的赋值互换，或把 `pluginAddress` 写成 `address(0)` / 错误地址，现有测试仍会通过；若 `errorSelector` 对短错误数据改为 `bytes4(type(uint32).max)`，也没有测试失败。索引器看到的事件字段因此没有回归网。
- 建议：在 `testT072` 前先发一条 priming 消息，使 `messageId = 2`、`round = 1` 分离；断言 `topics[1..3]` 与 `data` 的全部字段；再补一个 revert 数据为空或 2 字节的 mock，断言 `errorHash = keccak256("")` 或对应哈希、`errorLength`、`errorSelector = 0`；同时按 `GL-EV-1` 加 emitter 断言。
- **处置（已落地）**：`testT072` 加 priming 并断言 `topics[1..3]` / `round` / emitter（`test/GroupChatPlugins.t.sol:409-484`）；`T075` / `T076` 补 `round` / `pluginAddress` / emitter；新增 `testT076B` 与 `MockAfterPostShortErrorPlugin`（2 字节错误，`errorLength=2`、`errorSelector=0`、`errorHash=keccak256(0x0000)`）。

### GC-EV-2（P3）`content` / `mentionedSenderCount` 的上限成功侧没有用例

- 证据：`testT043T044T045T046T047`（`test/GroupChatMessages.t.sol:93-101`）只构造 `MAX_CONTENT_LENGTH + 1` 并断言 `ContentTooLong`，没有恰好 4096 字节的成功消息，也没有断言 `MessagePosted.content` 在上限处的值。`testT086`（`:597-614`）构造 33 个提及，但前 32 个都是同一个 `senderId`，最后一个是 `otherGroupId`；`_checkMentionedSenderIds` 先判长度 `:837-839`，再判重复 `:840-848`，所以该用例只覆盖「33 条失败」，没有覆盖「32 条成功」，更没有断言 `MessagePosted.mentionedSenderCount = 32` 与 32 条 `SenderMentioned`。
- 问题：§8.10 要求边界成功值必须有测试（恰好等于上限时成功，上限 + 1 失败）。当前实现把上限判断写成 `>`（`:229`、`:837`），若误改为 `>=`，恰好 4096 / 32 会被拒绝，而现有 `max + 1` 失败用例仍然通过。
- 影响：正文上限和提及上限的事件侧没有成功边界证据；`MessagePosted.content` 与 `mentionedSenderCount` 是链上可观察字段，回归只能靠人工审查。
- 建议：补一条恰好 4096 字节正文的成功用例，断言 `MessagePosted.content` 完整；补一条 32 个**互不相同**的提及成功用例，断言 `mentionedSenderCount = 32` 且子事件 32 条；把 33 条失败用例改为 33 个互不相同的 ID，避免重复检查先于长度检查的干扰。
- **处置（已落地）**：`testT086` 改为 33 个互不相同 ID（`test/GroupChatMessages.t.sol:601-617`）；新增 `testT086B` 同时覆盖恰好 4096 字节正文成功与 32 条互不相同提及成功，断言 `mentionedSenderCount`、32 条 `SenderMentioned`、存储内容（`:618-655`）。

### GC-EV-3（P3）托管激活只断言 link 事件，`GroupChatActivated` 存在性无回归网

- 证据：`test/TypedManagers.t.sol` 的两个 `_assertTokenGroupActivated` helper 只取 `logs[logs.length - 1]` 断言 `TokenGroupActivated` / `TokenActionGroupActivated`；若 `GroupChat.activateChat` 完全不再发 `GroupChatActivated`，helper 仍会通过（它只要求最后一条正确）。
- 问题：§3.4.5 的父子序与 §8.1 的发射条件断言要求托管激活的父事件可观测；当前只有「最后一条」间接锁定，缺少存在性与下标断言。
- 影响：`GroupChatActivated` 在托管路径被误删或前移时，TypedManagers 测试不会失败；索引器会在没有群配置事件的情况下看到 link 事件。
- **处置（已落地，选择补测试而非登记）**：两个 helper 增加 `logs.length == 2`、`logs[0].emitter == address(chat)`、`logs[0].topics[0] == GROUP_CHAT_ACTIVATED_SIG`、`logs[0].topics[1] == groupId`（`test/TypedManagers.t.sol:592-613`、`:614-637`）。取舍：这是一条可静态断言的行为契约，补断言成本低于登记豁免，且能同时锁定顺序与存在性。

### 跨合约关联项

- `GL-EV-1`：本合约 9 个事件类（`GroupChatActivated`、`PostingAllowedChanged`、四个地址槽 `*Changed`、`MessagePosted`、`SenderMentioned`、`AfterPostPluginFailed`）原先均未断言 emitter；**本卷已全部补齐**。详见 README §五。
- `GL-EV-3`：`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged` 的 `operatorId` 在所有可达路径恒等于 `groupId`，属协议恒等，但未在 §8.1 恒等对清单登记；测试无法区分两者。详见 README §五。

### 正面结论（不计入发现）

- 9 个事件覆盖 17 个业务写入面，无「写了不报」的字段；`firstActivated*` 与四类消息索引均可由事件 + 日志元数据推导。
- 配置事件在写后发射，同值/同地址 no-op 零日志，测试 `testT014` / `testT070D` / `testT070E` 有零日志断言。
- `MessagePosted` 父事件先于 `SenderMentioned` 子事件，`mentionedSenderCount` 等于子事件条数；`testT048:134-161` 同时断言父事件字段、条数与逐条子事件。
- `MessagePosted.hasQuote` 与 `quotedMessageId != 0` 严格恒等，`mentionedSenderCount` 与子事件条数同源，二者已按 `07-events-errors.md` 登记，折叠规则明确。
- `AfterPostPluginFailed` 是唯一捕获型失败事件，命名 `<Object>Failed`，携带插件地址与错误指纹；after 插件失败不回滚消息，符合 `03-posting.md`。
- `MessagePosted.content` 有 4096 字节链上上限，`mentionedSenderIds` 有 32 条链上上限，事件不写无界数组；`AfterPostPluginFailed` 不写原始 `bytes`。
- `GroupChatActivated` 的 `ownerId` / `groupId` 恒等对已在 §8.1 登记；`MessagePosted` 的三个 indexed 槽为 `groupId` / `messageId` / `senderId`，`sender` 地址降为非 indexed，符合 §6.3 的 actor 优先级。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `GroupChatActivated` | `GroupChatPlugins.t.sol:275-302` | 3 个 topic + 5 个 data 字段 + emitter；托管路径见 `TypedManagers.t.sol` helper |
| `PostingAllowedChanged` | `GroupChatLifecycle.t.sol:154-180` | 3 个 topic + `postingAllowed`；同值零日志 `:161-165`；emitter |
| `ScopeSourceChanged` | `GroupChatPlugins.t.sol:167-219` | 3 个 topic + `operator` / `prevSourceAddress`；同地址零日志 `:191-195`；emitter |
| `BanSourceChanged` | `GroupChatPlugins.t.sol:221-273` | 同上；同地址零日志 `:245-249`；emitter |
| `BeforePostPluginChanged` | `GroupChatPlugins.t.sol:324-359` | 3 个 topic + `operator` / `prevPluginAddress`；emitter |
| `AfterPostPluginChanged` | `GroupChatPlugins.t.sol:324-359` | 同上；emitter |
| `MessagePosted` | `GroupChatMessages.t.sol:112-195`、`:507-552`、`:197-264`、`:618-655` | 3 个 topic + sender / round / quote / hasQuote / mentionAll / count / content；4096/32 上限成功；emitter |
| `SenderMentioned` | `GroupChatMessages.t.sol:156-161` | 3 个 topic、按入参顺序、条数等于父事件 count；emitter |
| `AfterPostPluginFailed` | `GroupChatPlugins.t.sol:409-484`、`:485-512`、`:513-560` | topic0 + `topics[1..3]`、round、errorHash/errorLength/errorSelector；2 字节短错误；emitter |

~~缺一条~~（`GC-EV-3`，本卷已补）：托管激活时 `GroupChatActivated` 与 `TokenGroupActivated` / `TokenActionGroupActivated` 的先后现由 `TypedManagers.t.sol` 两个 helper 显式断言 `logs.length == 2` 且 `logs[0]` 是 `GroupChatActivated`。

## 八、复现

```bash
cd group-chat

# 事件清单、族覆盖、声明与发射写法
python3 script/events/check-events.py
# → event manifest OK: 18 events; families OK; declaration style OK; emit style OK; emit keys OK

# 发射点总数
grep -rn "emit " src/ | wc -l          # → 18

# 本合约事件用例
forge test --match-contract GroupChatLifecycleTest
forge test --match-contract GroupChatMessagesTest
forge test --match-contract GroupChatPluginsTest

# 全量
forge test --summary
# → 151 passed, 0 failed
```
