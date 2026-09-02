# LOVE20BSC Group Chat 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义群聊实例、群聊身份、Group Chat Delegate、发言规则、消息索引、分页查询和可插拔的资格/黑名单模块。**保留旧逻辑的部分直接引用旧代码位置**，避免重复描述。详细变更清单见 [`CHANGES-group-chat.md`](./CHANGES-group-chat.md)。

---

## 1. 定位与边界

`group-chat` 是公开链上群聊业务。它只保存群聊配置、消息和查询索引，不保存治理质押、Proposal、行动资产或代币发射状态。

**核心规则**：
- **1 个 MemberNFT = 1 个 Chat**：`groupId` 是群聊身份 NFT 的 `memberId`
- **发言身份是 `senderId`**：地址只用于校验该 NFT 的当前控制者，不作为消息或成员主体
- **消息只新增，不编辑、不删除**
- **成员资格、黑名单和发言插件通过规则槽位外置**
- **Group Chat Delegate 只在本代码库内生效**，不产生任何跨代码库权限

**不包含**：P2P Chat、私聊、阅读权限、链下消息、治理投票、行动验证和代币经济。

---

## 2. 身份和对象

### 2.1 MemberNFT 身份

群、群管理员、群成员、委托者、发言者和被提及者都以 `memberId` 标识。任何需要代表身份写入状态的调用都必须验证 `MemberNFT.ownerOf(memberId) == msg.sender`。

**关键约束**：
- 群聊不把钱包地址作为长期业务主体
- 不维护地址到默认 MemberNFT 的映射
- MemberNFT 转移只改变当前控制者；群身份、历史消息、历史事件、成员列表和委托记录不被改写

**不存在的接口**：
- 地址主体发言入口
- 地址到默认 MemberNFT 的映射
- 地址黑名单
- 地址黑名单投票

### 2.2 ChatInfo

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

每个 `groupId` 的配置至少包含：
- `groupId`
- 实时 `owner`
- `activated`、`postingAllowed`
- `scopeSource`、`banSource`
- `beforePostPlugin`、`afterPostPlugin`
- `firstActivatedOwner`、`firstActivatedBlockNumber`、`firstActivatedTimestamp`

`groupId` 的当前控制者每次都从 `MemberNFT.ownerOf(groupId)` 实时读取，不缓存为权限依据。

### 2.3 Message

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

每条消息至少保存：`groupId`、`senderId`、`senderAddress`、`round`、`messageId`、`content`、`blockNumber`、`timestamp`、`mentionedSenderIds`、`mentionAll` 和 `quotedMessageId`。

**关键设计**：
- `senderId` 可以与 `groupId` 不同，表示一个成员以自己的 MemberNFT 身份在另一个群发言
- 发言交易的 `msg.sender` 必须是 `senderId` 当前控制者
- `senderAddress` 只保存当时的实际调用地址用于审计，不参与消息身份、索引、资格或黑名单判断
- `messageId` 在单个 Chat 内从 `1` 开始连续递增

---

## 3. 生命周期和管理权限

### 3.1 激活

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

只有 `groupId` 当前 MemberNFT owner 可以调用 `activateChat`。激活前必须验证群 NFT 存在、Chat 尚未激活，且所有非零规则地址都有合约代码。

首次激活写入 `firstActivatedOwner`、首个区块和时间戳，并永久保留。激活默认 `postingAllowed = true`，设置初始四个规则槽位，并把 `groupId` 加入可发现群列表。

### 3.2 管理操作

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

激活后，群 owner 或当前有效的 Group Chat Delegate 可以：
- 设置 `postingAllowed`
- 更新 `scopeSource`、`banSource`、`beforePostPlugin` 和 `afterPostPlugin`

**普通 owner Chat vs Manager Chat 的管理差异**：
- **普通 owner Chat**（如链群 Chat）：owner 持有 MemberNFT，可随时更新四个规则槽位
- **Manager Chat**（代币社区/治理/行动 Chat）：Manager 合约持有 MemberNFT，规则槽位在激活时一次性注入，Manager 通常不提供重新配置接口

### 3.3 Group Chat Delegate（限定范围）

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`（委托语义）

Group Chat Delegate 使用 NFT 委托语义：每个 `groupId` 最多设置一个 `delegateId`，并保留被委托群列表、委托方白名单开关和白名单分页查询。

**委托权限限定**（重要变更）：

**可以做**：
- 管理发言开关和四个规则槽位

**不可以做**：
- 不可以调用 `post` 代替其他 `senderId`
- 不可以获得治理票、质押权、发射次数、Action 验证权或任何群外权限

**委托失效**：
- 委托保存群和 delegate MemberNFT 的 owner 快照
- 任一 NFT 当前 owner 与快照不一致时委托失效
- 转回快照 owner 时可以自动恢复
- 原始记录和历史查询不因转移删除

---

## 4. 规则槽位

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

每个 Chat 有四个外部规则槽位：
- `scopeSource`：发言资格
- `banSource`：黑名单拒绝
- `beforePostPlugin`：写消息前的业务校验
- `afterPostPlugin`：写消息后的通知或索引扩展

地址为 `0` 表示未挂载：`scopeSource = 0` 代表默认开放，`banSource = 0` 代表没有黑名单。

**调用顺序**：
核心身份和内容校验 → owner/delegate 的资格绕过判断 → `scopeSource(groupId, senderId)` → `banSource(groupId, senderId)` → `beforePostPlugin` → 写入消息 → 发出消息/提及事件 → `afterPostPlugin`

**资格绕过**：
当 `senderId == groupId`，或 `senderId` 是该群当前有效的 `delegateId` 时，可以跳过 `scopeSource` 和 `banSource`，但仍必须通过群存在、激活、发言开关、身份存在和 `msg.sender` 持有 `senderId` 等核心校验。

**mentionAll 权限**（详见第 5.1 节）：
- **允许 mentionAll**：owner（`senderId == groupId`）、有效 delegate、有效 admin
- **资格绕过**：仅 owner 和 delegate（admin 可以 mentionAll，但仍需通过 scopeSource 和 banSource 检查）

**标准接口**：
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

---

## 5. 发言

### 5.1 参数和基础校验

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

发言入口接收 `groupId`、`senderId`、`content`、`mentionedSenderIds`、`mentionAll` 和 `quotedMessageId`。

**校验顺序**：
1. `groupId` 对应的 MemberNFT 存在
2. Chat 已激活且 `postingAllowed = true`
3. `senderId` 对应的 MemberNFT 存在，且 `msg.sender` 是其当前 owner
4. `content` 非空，字节长度不超过 `MAX_CONTENT_LENGTH`（默认 `4096` bytes）
5. `mentionedSenderIds` 数量不超过 `MAX_MENTIONED_SENDER_IDS`（默认 `32`），每个 MemberNFT 存在且不重复
6. `mentionAll = true` 时，`senderId` 必须是该群 `groupId`、有效 `delegateId` 或有效 `adminId`
7. `quotedMessageId = 0` 表示无引用，非零时必须指向当前 Chat 已存在的消息
8. 按规则槽位顺序执行资格、黑名单和插件检查

### 5.2 消息写入和插件

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

消息追加后分配新的 `messageId`，更新按 sender、mention、mention-all 和 round 的轻量索引，并发出 `PostMessage`。

**插件失败处理**：
- `beforePostPlugin` 回滚时，整笔发言回滚
- `afterPostPlugin` 在消息和通知事件写入后调用；其失败不会回滚消息，而是捕获错误并发出 `FailAfterPostPlugin(groupId, messageId, pluginAddress, round, errorData)`

### 5.3 canPost（预检查）

`canPost(groupId, senderId)` 只执行无内容预检查并返回 `(allowed, reasonCode)`；不要求查询调用者本人持有该 NFT，也不检查正文、提及、引用或 `beforePostPlugin`。

---

## 6. 群聊 Round 和查询

### 6.1 群聊 Round

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

群聊 Round 是消息索引使用的本地时间编号，不等同治理 Round。GroupChat 合约部署时接收 Phase 合约地址作为构造参数，通过 `Phase.currentPhase()` 获取当前 Round，编号从 `1` 开始。

**查询方式**：
```solidity
currentRound = phase.currentPhase()
```

**注意**：群聊使用 Phase 合约来推算 Round，而非独立维护 `originBlock` 和 `phaseBlocks` 参数。

消息记录创建时的 Round 永久固定，即使后续调整 Chat 配置也不回写历史消息。

### 6.2 查询接口

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

公开查询至少包括：
- 单个或批量 `chatInfo`
- `postingAllowed`、四个规则槽位地址
- `messagesCount`、`message(groupId, messageId)`
- 全量消息分页 `messages`
- 按 Round 的 `messagesByRound`、`messagesByRoundCount`、`roundInfo`、`roundInfos`、`rounds`
- 按 sender 的 `messagesBySender`、`messagesBySenderCount`、`messageIdsBySender`
- 按 mention 的 `messagesByMention`、`messagesByMentionCount`、`messageIdsByMention`
- 按 mention-all 的 `messagesByMentionAll`、`messagesByMentionAllCount`、`messageIdsByMentionAll`
- Chat 内出现过的 `senderIds`
- 所有曾激活 Chat 的 `groupIds`

所有列表查询支持 `offset`、`limit` 和 `reverse`。

---

## 7. 群聊类型和资格规则

### 7.1 五类 Chat 类型

**参考实现**：`LOVE20TKM/group-chat/Managers`、`ScopeSource`

`GroupChat` 不把群聊类型写死在核心状态，类型由 Manager、scope source、ban source 和插件组合实现。

| 类型 | 发言资格 | 黑名单 |
| --- | --- | --- |
| 代币社区 Chat | 持有社区代币余额大于 `0`、拥有有效治理票或当前已登记参与该社区至少一个行动 | 治理票加权黑名单 |
| 代币治理 Chat | 拥有该代币有效治理票 | 治理票加权黑名单 |
| 代币行动 Chat | 最近 `RECENT_ROUNDS` 轮给行动投过票，或当前已在 ActionTarget 登记参与该行动 | 行动投票权重黑名单 |
| 代币行动治理 Chat | 最近 `RECENT_ROUNDS` 轮给行动投过票 | 行动投票权重黑名单 |
| 链群 Chat | 被群管理员列入成员，或当前参与至少一个归属该链群的链群行动 | 管理员黑名单 |

**关键实现细节**：

**持币资格**：
```text
token.balanceOf(MemberNFT.ownerOf(senderId)) > 0
```
持有任意非零余额即可。

**治理票、投票和参与**：
- 治理票、Proposal 投票和行动参与直接按 `memberId` 查询
- `RECENT_ROUNDS` 在各 ScopeSource 部署时通过构造参数设置，所有 ScopeSource 应使用统一值
- 推荐值：3（检查最近 3 个治理 Round）

**RECENT_ROUNDS 的时间基准**：
当前 Core 治理 Round（即 `Phase.currentPhase()` 返回值，Phase 与治理 Round 一对一映射）向前数 `RECENT_ROUNDS` 轮。

示例（假设 RECENT_ROUNDS = 3）：
- 当前 Phase = 10（即治理 Round 10）
- 检查 memberId 在治理 Round 10, 9, 8 是否投过票
- 任一 Round 有投票记录即符合资格

注意：
- 使用 Core 治理 Round 作为基准，而非行动的执行 Round
- 这确保了跨行动的资格判断一致性

**ActionTarget 参与登记与链群 Chat 资格差异**：

forceExit 对 Chat 资格的影响：
- **代币社区/行动 Chat**：立即失去资格（依赖 ActionTarget 登记，forceExit 清除登记）
- **链群 Chat**：不失去资格（依赖链群 Executor 归属，forceExit 不修改归属；归属只在链群 Executor 的正常退出流程中更新）

### 7.2 群成员和管理员

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

群聊可以维护 `groupId -> memberId` 成员集合，并提供批量新增、移除、存在性判断和分页查询。只有群 owner、有效 Group Chat Delegate 或有效群管理员可以修改成员集合。

管理员集合同样使用 MemberNFT。管理员执行操作时显式提供 `adminId`，不通过钱包地址的默认 NFT 映射推导。

### 7.3 治理投票黑名单

**参考实现**：`LOVE20TKM/group-chat/GovBanSource`

治理投票黑名单按 `groupId + targetSenderId + voterId` 记录支持/反对票，并从 `voterId` 对应的治理状态读取权重。

**权重查询**（按 Chat 类型区分）：

**代币社区 Chat、代币治理 Chat**：
- `voteWeightOf(groupId, voterId)` = 该代币社区中 `voterId` 当前有效治理票
- `totalVoteWeight(groupId)` = 该代币社区当前总有效治理票

**代币行动 Chat、代币行动治理 Chat**：
- `voteWeightOf(groupId, voterId)` = 该行动 Proposal 创建的治理 Round 中 `voterId` 的累计投票数
- `totalVoteWeight(groupId)` = 该行动 Proposal 创建的治理 Round 中的总投票数

注意：行动 Chat 的权重基准是行动 Proposal 的投票数，而非代币社区的治理票总数。行动 Proposal 只在创建的治理 Round 接受投票，后续 Round 的黑名单投票使用该历史投票数据作为权重基准。

**进入黑名单条件**（固定常量）：
```text
supportWeight > opposeWeight × 10
supportWeight × 1e18 >= totalVoteWeight × 3e15
```

**黑名单投票时间窗口**：
- 代币社区/治理 Chat：任何时候都可以投票（使用当前治理票作为权重）
- 代币行动/行动治理 Chat：任何时候都可以投票，但权重固定使用行动 Proposal 创建 Round 的历史投票数据

每次投票、反对、撤票或刷新后同步该目标的黑名单状态。

### 7.4 Manager

**参考实现**：`LOVE20TKM/group-chat/TokenMainManager` 等

协议提供四类 typed Manager：`TokenMainManager`、`TokenGovManager`、`TokenActionMainManager` 和 `TokenActionGovManager`。

**关键设计**：
- Manager 创建并持有一个 MemberNFT
- 把该 `memberId` 作为 `groupId` 激活到同一个 `GroupChat` 合约
- 一次性注入规则模块
- 不创建独立 Chat 合约，不复制 MemberNFT、不创建治理状态、不改变行动状态

**行动 Chat 与 Proposal 的关联**（黑名单权重查询）：
- 每个行动 Manager 在创建时关联一个 `actionId`（对应 Core 的 Proposal ID）
- 行动 Chat 的黑名单投票通过查询 Manager 获得 `actionId`，再查询该 Proposal 的投票权重
- Manager 必须提供 `getActionId(groupId) returns (uint256 actionId)` 接口供黑名单源查询
- 一个代币社区可能有多个行动 Proposal，每个行动 Manager 关联不同的 `actionId`

**Chat 类型区分机制**：
Manager 通过注入不同的 `scopeSource` 和 `banSource` 实现类型区分。

**参考旧代码命名**：`LOVE20TKM/group-chat/src/sources/`
- Scope 实现：`GroupMemberScope`、`GroupJoinScopeSource`
- Ban 实现：`AdminBanSource`、`GovVotedBanSource`

Manager 在创建 Chat 时应发出事件，标注 Chat 类型。

### 7.5 链群 Chat

**参考实现**：`LOVE20TKM/group-chat/GroupChat`（链群配置）

链群 Chat 不使用 Manager，由链群 owner 持有的 MemberNFT 直接作为 `groupId` 激活和管理。

**两个标准 scopeSource**：

**GroupMemberScope**：
- 只读取管理员维护的 `groupId -> memberId` 成员名单

**GroupActionScope**（新增）：
- 部署时接收 GroupChat 的成员集合查询接口和链群行动 Executor 地址作为构造参数
- Executor 必须是协议部署的标准链群行动 Executor
- 成员名单命中时直接允许
- 否则检查 `gTokenAddressesByGroupIdByMemberIdCount(groupId, senderId) > 0`
- 该查询覆盖该 Executor 服务的所有代币社区和所有链群行动

**链群行动 Executor 是归属唯一依据**：
- Group Chat 不复制归属状态，也不遍历 ActionTarget
- 成员通过 Executor 正常退出其在该链群的最后一个行动后资格立即失效
- `forceExit` 只清除 ActionTarget 的通用参与登记，不修改 Executor 的资产或链群归属

**链群 owner 在激活时传入所需的 `scopeSource`、`banSource` 和插件；激活后，链群 owner 或有效 Group Chat Delegate 可以更新这些规则槽位。这与 Manager Chat 不同：Manager Chat 的规则槽位在激活时一次性注入且通常不提供重新配置接口。**

---

## 8. 事件、错误和安全性

### 8.1 事件

至少发出：
- `Activate`、`SetPostingAllowed`
- 四个规则槽位的设置事件
- `PostMessage`、`MentionSenderId`、`MentionAll`、`FailAfterPostPlugin`
- Group Chat Delegate 设置/撤销、成员集合变化、管理员变化
- Manager 创建/激活实例事件

配置变化事件包含 `groupId`、新旧合约地址、操作 `memberId` 和实际调用地址；消息事件包含 `groupId`、`senderId`、`senderAddress`、`round` 和 `messageId`。地址字段仅用于审计，不作为业务主体或地址维度索引。

### 8.2 错误

至少拒绝：不存在的群或 sender、重复激活、非 owner/Delegate 管理、非 sender owner 发言、Chat 未激活、发言关闭、空正文、正文超长、提及数量超限或重复、无效引用、非管理员 `mentionAll`、规则地址无代码、scope/ban 拒绝和重入。

### 8.3 安全性

- 消息只增不改，配置和消息写入使用重入保护
- 规则源、插件和 Manager 不能越权写入 Chat 核心存储
- 协议没有升级管理员和隐含后门

---

## 9. 验收场景

至少覆盖：

**核心机制**：
- 1 个 MemberNFT = 1 个 Chat
- 群 NFT 转移后的 owner 连续性和历史不回写
- 激活一次性、默认开放发言、规则槽位更新和无代码地址拒绝

**Group Chat Delegate**：
- 设置、撤销、作用域、权限限制和不能冒充 sender

**身份约束**：
- 不存在默认 MemberNFT 映射
- 不存在地址主体发言入口
- 不存在地址黑名单
- 不存在地址黑名单投票或其他地址主体接口

**发言机制**：
- 普通发言、owner/Delegate 资格绕过、scope/ban 拒绝
- before 插件回滚、after 插件失败但消息保留
- 正文、提及、mention-all、引用和 1-based 消息 ID 边界

**查询**：
- 按 Round/sender/mention/mention-all 查询
- 空 Round、反向分页和越界返回

**群管理**：
- 成员/管理员批量操作、当前 owner 实时授权和 MemberNFT 不存在回滚

**类型和资格**：
- 四类 typed Manager 的资格、黑名单和不可重配边界
- 链群 owner 管理型 Chat 的标准资格源与可重配边界
- 链群归属跨社区和跨行动查询
- 所有业务状态只按 `memberId` 记录
