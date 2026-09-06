# Group Chat 范围与身份

Group Chat 是公开链上群聊，保存配置、消息和查询索引；不管理治理质押、Proposal、行动资产或发射状态。不包含 P2P、私聊、阅读权限、链下消息、治理投票、行动验证或代币经济。

## 迁移边界

保留旧 `src/GroupChat.sol`、`GroupAdmin.sol`、`GroupMember.sol`、`GroupBanList.sol`、Manager、scope/ban 及插件的业务行为。只有以下变化：

- GroupNFT 依赖统一为 Core MemberNFT；业务主体一律为 memberId。
- 删除 `postAsDefaultSender`、GroupDefaults 依赖、地址黑名单目标、地址投票者、地址/ID 双轨批量接口及其状态、索引、错误和事件。
- 非身份地址继续存在：ERC20/合约地址、付款地址、owner 快照、调用者审计字段、ERC721 接收回调参数不能误删。
- NFT 委托实现迁入 group-chat，仅本仓库消费者读取；Core、Action、Launch 不导入或使用该委托作为授权。
- 按已确认的 BSC 边界接入 Phase 和 ActionTarget/Executor；除此之外不增加、删减群聊功能。

## 身份

一个 MemberNFT 对应一个 Chat。群主体为 `groupId`，发言主体为 `senderId`；两者可以不同。成员、管理员、delegate、被提及者、黑名单目标和黑名单投票者均用 memberId。

代表身份写入时校验 `MemberNFT.ownerOf(memberId) == msg.sender`；sender/admin/voter 显式传入，不从地址默认身份推导。NFT 转移不改写历史消息或身份关系；委托和管理员的有效性仍按旧 owner 快照规则判断。

## 数据对象

保留旧 `src/interfaces/IGroupChat.sol` 的 ChatInfo、Message、RoundSpan 类型和字段：

| 对象 | 字段 |
| --- | --- |
| ChatInfo | groupId、owner、activated、postingAllowed、scopeSource、banSource、beforePostPlugin、afterPostPlugin、firstActivatedOwner、firstActivatedBlockNumber、firstActivatedTimestamp |
| Message | groupId、senderId、senderAddress、round、messageId、content、blockNumber、timestamp、mentionedSenderIds、mentionAll、quotedMessageId |
| RoundSpan | round、startMessageId、endMessageId、messageCount |

owner 实时读取；senderAddress 仅作审计，不作主体或资格分支。消息在每个 Chat 内从 1 连续编号，只追加不改删；Round 读取需使用 BSC 历史 Phase，见 [查询](04-query.md)。

源码基线见 [入口](README.md#已核对来源)，不是要求重新设计这些对象。
