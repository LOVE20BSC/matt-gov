# Group Chat 概览

本文档定义 Group Chat 系统的定位、边界和核心规则。

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
