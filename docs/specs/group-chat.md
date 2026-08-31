# LOVE20BSC Group Chat 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义群聊实例、群聊身份、Group Chat Delegate、发言规则、消息索引、分页查询和可插拔的资格/黑名单模块。

## 1. 定位与边界

`group-chat` 是公开链上群聊业务。它只保存群聊配置、消息和查询索引，不保存治理质押、Proposal、行动资产或代币发射状态。

群聊业务包含生命周期、四类 typed Manager、规则槽位、插件、成员/管理员、Group Chat Delegate、消息索引和分页查询。成员、管理员、委托者、发言者、被提及者、黑名单目标和治理黑名单投票者统一使用 `MemberNFT/memberId`；不提供以钱包地址为业务键的平行状态或接口。

核心规则：

- `1 个 MemberNFT = 1 个 Chat`；`groupId` 是群聊身份 NFT 的 `memberId`；
- 发言身份是 `senderId`；地址只用于校验该 NFT 的当前控制者，不作为消息或成员主体；
- 消息只新增，不编辑、不删除；
- 成员资格、黑名单和发言插件通过规则槽位外置；
- **Group Chat Delegate** 只在本代码库内生效，不产生任何跨代码库权限。

不包含 P2P Chat、私聊、阅读权限、链下消息、治理投票、行动验证和代币经济。

## 2. 身份和对象

### 2.1 MemberNFT 身份

群、群管理员、群成员、委托者、发言者和被提及者都以 `memberId` 标识。任何需要代表身份写入状态的调用都必须验证 `MemberNFT.ownerOf(memberId) == msg.sender`。

群聊不把钱包地址作为长期业务主体，也不维护地址到默认 MemberNFT 的映射。MemberNFT 转移只改变当前控制者；群身份、历史消息、历史事件、成员列表和委托记录不被改写。

协议不部署默认 MemberNFT 映射，也不提供默认身份发言入口。需要 owner、delegate、admin 或 voter 身份的操作直接携带已有的 `groupId`、`delegateId`、`adminId`、`senderId` 或 `voterId`；合约校验 `MemberNFT.ownerOf(id) == msg.sender` 后再校验该 ID 的角色。黑名单、资格和治理黑名单投票均没有钱包地址版本。

### 2.2 ChatInfo

每个 `groupId` 的配置至少包含：

- `groupId`；
- 实时 `owner`；
- `activated`、`postingAllowed`；
- `scopeSource`、`banSource`；
- `beforePostPlugin`、`afterPostPlugin`；
- `firstActivatedOwner`、`firstActivatedBlockNumber`、`firstActivatedTimestamp`。

`groupId` 的当前控制者每次都从 `MemberNFT.ownerOf(groupId)` 实时读取，不缓存为权限依据。`owner` 和 `firstActivatedOwner` 是当前控制地址和历史审计地址，不是群聊业务主体。

### 2.3 Message

每条消息至少保存：`groupId`、`senderId`、`senderAddress`、`round`、`messageId`、`content`、`blockNumber`、`timestamp`、`mentionedSenderIds`、`mentionAll` 和 `quotedMessageId`。

`senderId` 可以与 `groupId` 不同，表示一个成员以自己的 MemberNFT 身份在另一个群发言。发言交易的 `msg.sender` 必须是 `senderId` 当前控制者；`senderAddress` 只保存当时的实际调用地址用于审计，不参与消息身份、索引、资格或黑名单判断。

`messageId` 在单个 Chat 内从 `1` 开始连续递增；数组下标 `messageIndex` 与 `messageId` 的关系是 `messageId = messageIndex + 1`。`0` 只表示无引用，不分配给消息。

## 3. 生命周期和管理权限

### 3.1 激活

只有 `groupId` 当前 MemberNFT owner 可以调用 `activateChat`。激活前必须验证群 NFT 存在、Chat 尚未激活，且所有非零规则地址都有合约代码。

首次激活写入 `firstActivatedOwner`、首个区块和时间戳，并永久保留。激活默认 `postingAllowed = true`，设置初始四个规则槽位，并把 `groupId` 加入可发现群列表。重复激活必须回滚。

### 3.2 管理操作

对于由普通 owner 激活的 Chat，激活后群 owner 或当前有效的 Group Chat Delegate 可以：

- 设置 `postingAllowed`；
- 更新 `scopeSource`、`banSource`、`beforePostPlugin` 和 `afterPostPlugin`。

Group Chat Delegate 不能激活未激活 Chat，不能替换群 owner，不能把权限转授给第三方，不能代替另一个 MemberNFT 发言。重复设置为当前值是 no-op，不产生重复事件。

由 typed Manager 激活的 Chat 仍由 Manager 在激活时一次性写入规则；Manager 持有对应的 `groupId`，因此外部用户不能通过 owner 权限重配。Manager 自身不提供激活后的停用、重配或修改资格参数入口。

### 3.3 Group Chat Delegate

Group Chat Delegate 沿用旧版 NFT 委托语义：每个 `groupId` 最多设置一个 `delegateId`，并保留被委托群列表、委托方白名单开关和白名单分页查询。只有群 owner 当前控制者可以设置或撤销 `delegateId`；delegate MemberNFT 当前控制者可以清理委托给自己的群，并管理自己是否只接受白名单群的委托。

委托权限只在指定 `groupId` 和指定管理操作中有效：

- 可以管理发言开关和四个规则槽位；
- 不可以调用 `post` 代替其他 `senderId`；
- 不可以获得治理票、质押权、发射次数、Action 验证权或任何群外权限；
- 委托保存群和 delegate MemberNFT 的 owner 快照；任一 NFT 当前 owner 与快照不一致时委托失效，转回快照 owner 时可以自动恢复；原始记录和历史查询不因转移删除；
- 撤销后立即拒绝新的管理调用，已完成的消息和事件不回写。

代码、事件和文档统一使用 `Group Chat Delegate`，不得把它当作跨仓库的通用 `delegate`。

## 4. 规则槽位

每个 Chat 有四个外部规则槽位：

- `scopeSource`：发言资格；
- `banSource`：黑名单拒绝；
- `beforePostPlugin`：写消息前的业务校验；
- `afterPostPlugin`：写消息后的通知或索引扩展。

地址为 `0` 表示未挂载：`scopeSource = 0` 代表默认开放，`banSource = 0` 代表没有黑名单，两个插件为 `0` 代表不调用。非零地址必须包含合约代码。

普通发言的调用顺序固定为：核心身份和内容校验 → owner/delegate 的资格绕过判断 → `scopeSource(groupId, senderId)` → `banSource(groupId, senderId)` → `beforePostPlugin` → 写入消息 → 发出消息/提及事件 → `afterPostPlugin`。

当 `senderId == groupId`，或 `senderId` 是该群当前有效的 `delegateId` 时，可以跳过 `scopeSource` 和 `banSource`，但仍必须通过群存在、激活、发言开关、身份存在和 `msg.sender` 持有 `senderId` 等核心校验。钱包同时持有 owner/delegate NFT 和另一个 MemberNFT，不会让另一个 `senderId` 继承绕过权限。规则源只能返回资格或拒绝，不能越权修改 Chat 核心状态。所有规则源、插件和黑名单接口只接收 `memberId` 业务身份，不提供以钱包地址为目标的平行接口。

标准规则源和插件 ABI 为：

```solidity
interface IPostScopeSource {
    function canPost(uint256 groupId, uint256 senderId) external view returns (bool);
}

interface IPostBanSource {
    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool);
}

interface IBeforePostPlugin {
    function beforePost(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external;
}

interface IAfterPostPlugin {
    function afterPost(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId,
        uint256 messageId,
        uint256 blockNumber,
        uint256 timestamp
    ) external;
}
```

`scopeSource`、`banSource` 或 `beforePostPlugin` 调用失败时发言整体回滚；`afterPostPlugin` 的失败语义见第 5.2 节。

## 5. 发言

### 5.1 `post` 参数和基础校验

发言入口接收 `groupId`、`senderId`、`content`、`mentionedSenderIds`、`mentionAll` 和 `quotedMessageId`。

校验顺序和要求：

1. `groupId` 对应的 MemberNFT 存在；
2. Chat 已激活且 `postingAllowed = true`；
3. `senderId` 对应的 MemberNFT 存在，且 `msg.sender` 是其当前 owner；
4. `content` 非空，字节长度不超过 `MAX_CONTENT_LENGTH`（默认 `4096` bytes，可在部署时设定）；
5. `mentionedSenderIds` 数量不超过 `MAX_MENTIONED_SENDER_IDS`（默认 `32`），每个 MemberNFT 存在且不重复，允许提及自己；
6. `mentionAll = true` 时，`senderId` 必须是该群 `groupId`、有效 `delegateId` 或有效 `adminId`；
7. `quotedMessageId = 0` 表示无引用，非零时必须指向当前 Chat 已存在的消息；
8. 按规则槽位顺序执行资格、黑名单和插件检查。

任何一步失败都不得写入消息。Delegate 不能因为拥有管理权限而冒充不属于自己的 `senderId`。

### 5.2 消息写入和插件

消息追加后分配新的 `messageId`，更新按 sender、mention、mention-all 和 round 的轻量索引，并发出 `PostMessage`。提及事件必须在 `PostMessage` 之后发出。

`beforePostPlugin` 回滚时，整笔发言回滚。`afterPostPlugin` 在消息和通知事件写入后调用；其失败不会回滚消息，而是捕获错误并发出 `FailAfterPostPlugin(groupId, messageId, pluginAddress, round, errorData)`。这样消息仍然可查询，插件失败也能被监控。

### 5.3 `canPost`

`canPost(groupId, senderId)` 只执行无内容预检查并返回 `(allowed, reasonCode)`；它从 `MemberNFT.ownerOf(senderId)` 读取当前控制者供需要地址资产的资格源使用，不要求查询调用者本人持有该 NFT，也不检查正文、提及、引用或 `beforePostPlugin`。实际 `post` 仍必须校验 `msg.sender`。原因码至少包括：

- `0x00000000`：允许；
- Chat 未激活；
- 发言已关闭；
- 群或发言身份不存在；
- `scopeSource` 拒绝或调用失败；
- `banSource` 拒绝或调用失败。

## 6. 群聊 Round 和查询

群聊 Round 是消息索引使用的本地时间编号，不等同治理 Round 或 ActionRound。它由部署时的 `originBlock` 和 `phaseBlocks > 0` 计算，编号从 `1` 开始；`block.number < originBlock` 时查询当前 Round 回滚。

当前 Round 计算为 `1 + (block.number - originBlock) / phaseBlocks`。消息记录创建时的 Round 永久固定，即使后续调整 Chat 配置也不回写历史消息。

公开查询至少包括：

- 单个或批量 `chatInfo`；
- `postingAllowed`、四个规则槽位地址；
- `messagesCount`、`message(groupId, messageId)`；
- 全量消息分页 `messages`；
- 按 Round 的 `messagesByRound`、`messagesByRoundCount`、`roundInfo`、`roundInfos`、`rounds`；
- 按 sender 的 `messagesBySender`、`messagesBySenderCount`、`messageIdsBySender`；
- 按 mention 的 `messagesByMention`、`messagesByMentionCount`、`messageIdsByMention`；
- 按 mention-all 的 `messagesByMentionAll`、`messagesByMentionAllCount`、`messageIdsByMentionAll`；
- Chat 内出现过的 `senderIds`；
- 所有曾激活 Chat 的 `groupIds`。

`RoundSpan` 至少包含 `round`、`startMessageId`、`endMessageId` 和 `messageCount`。没有消息的 Round 返回对应 Round 和三个零值区间。

所有列表查询支持 `offset`、`limit` 和 `reverse`：`reverse = false` 为旧到新，`reverse = true` 为新到旧；`offset` 以返回方向为基准；`limit = 0` 或越界返回空数组。单条 `message` 的 `messageId` 必须在 `1..messagesCount(groupId)` 内。

## 7. 群聊类型和资格规则

`GroupChat` 不把群聊类型写死在核心状态，类型由 Manager、scope source、ban source 和插件组合实现。当前支持以下业务形态：

| 类型 | 发言资格 | 黑名单 |
| --- | --- | --- |
| 代币社区 Chat | 持有社区代币余额大于 `1`、拥有有效治理票或参与过该社区行动之一 | 治理票加权黑名单 |
| 代币治理 Chat | 拥有该代币有效治理票 | 治理票加权黑名单 |
| 代币行动 Chat | 最近若干 Round 给行动投票，或通过核心/行动合约参与过该行动 | 行动投票权重黑名单 |
| 代币行动治理 Chat | 最近若干 Round 给行动投票 | 行动投票权重黑名单 |
| 链群服务 Chat | 被群管理员列入成员，或满足指定链群行动参与条件 | 管理员黑名单 |

所有条件都以 `memberId` 和当前 MemberNFT 控制权判断。持币资格严格按 `token.balanceOf(MemberNFT.ownerOf(senderId)) > 1` 判断，其中 `1` 表示一个代币最小单位；该余额仅作为实时资格，不保存地址主体状态。治理票、Proposal 投票和行动参与直接按 `memberId` 查询。具体 Manager 可以在激活时一次性配置四个规则槽位；typed Manager 激活后不提供人工更新入口，普通 owner 管理型 Chat 则按第 3.2 节更新。

### 7.1 群成员和管理员

群聊可以维护 `groupId -> memberId` 成员集合，并提供批量新增、移除、存在性判断和分页查询。只有群 owner、有效 Group Chat Delegate 或有效群管理员可以修改成员集合；加入集合的目标 MemberNFT 必须存在且不能为 `0`。

管理员集合同样使用 MemberNFT。群 owner 或有效 Delegate 可以批量新增/移除管理员，受部署时的最大数量限制。沿用旧版 owner 快照：添加管理员时保存群和管理员 MemberNFT 的 owner；任一当前 owner 与快照不一致时该管理员暂时失效，恢复为快照 owner 时可以自动恢复；历史管理员记录不因转移删除。管理员执行操作时显式提供 `adminId`，不再通过钱包地址的默认 NFT 映射推导。

管理员可以执行明确授权的群管理操作（例如黑名单维护和 `mentionAll`），不能修改核心代币、治理或行动状态。

管理员黑名单只维护 `groupId -> senderId`。治理投票黑名单按 `groupId + targetSenderId + voterId` 记录支持/反对票，并从 `voterId` 对应的治理状态读取权重；不存在地址黑名单目标、地址投票者或地址维度汇总。

### 7.2 Manager

沿用旧版四类 typed Manager：`TokenMainManager`、`TokenGovManager`、`TokenActionMainManager` 和 `TokenActionGovManager`。Manager 创建并持有一个 MemberNFT，把该 `memberId` 作为 `groupId` 激活到同一个 `GroupChat` 合约，并一次性注入规则模块；它不创建独立 Chat 合约，不复制 MemberNFT、不创建治理状态、不改变行动状态。

链群服务 Chat 不使用 Manager，由链群 owner 持有的 MemberNFT 直接作为 `groupId` 激活和管理。`group-chat` 不新增 GroupChat 工厂。

## 8. 事件、错误和安全性

至少发出：

- `Activate`、`SetPostingAllowed`；
- 四个规则槽位的设置事件；
- `PostMessage`、`MentionSenderId`、`MentionAll`、`FailAfterPostPlugin`；
- Group Chat Delegate 设置/撤销、成员集合变化、管理员变化；
- Manager 创建/激活实例事件。

配置变化事件包含 `groupId`、新旧合约地址、操作 `memberId` 和实际调用地址；消息事件包含 `groupId`、`senderId`、`senderAddress`、`round` 和 `messageId`。地址字段仅用于审计，不作为业务主体或地址维度索引。事件是索引信号，正文和完整配置以 view 为准。

至少拒绝：不存在的群或 sender、重复激活、非 owner/Delegate 管理、非 sender owner 发言、Chat 未激活、发言关闭、空正文、正文超长、提及数量超限或重复、无效引用、非管理员 `mentionAll`、规则地址无代码、scope/ban 拒绝和重入。

消息只增不改，配置和消息写入使用重入保护。规则源、插件和 Manager 不能越权写入 Chat 核心存储。协议没有升级管理员和隐含后门。

## 9. 验收场景

至少覆盖：

- `1 个 MemberNFT = 1 个 Chat`、群 NFT 转移后的 owner 连续性和历史不回写；
- 激活一次性、默认开放发言、规则槽位更新和无代码地址拒绝；
- Group Chat Delegate 的设置、撤销、作用域、权限限制和不能冒充 sender；
- 不存在默认 MemberNFT 映射、默认身份发言入口、地址黑名单、地址黑名单投票或其他地址主体接口；
- 普通发言、owner/Delegate 资格绕过、scope/ban 拒绝、before 插件回滚、after 插件失败但消息保留；
- 正文、提及、mention-all、引用和 1-based 消息 ID 边界；
- 按 Round/sender/mention/mention-all 查询、空 Round、反向分页和越界返回；
- 成员/管理员批量操作、当前 owner 实时授权和 MemberNFT 不存在回滚；
- 四类 typed Manager 和链群服务 owner 管理型 Chat 的资格、黑名单与不可重配边界，以及所有业务状态只按 `memberId` 记录。
