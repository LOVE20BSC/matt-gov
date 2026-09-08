# Group Chat 迁移差异

用户确认：群聊几乎原样迁移，功能、流程、查询和失败行为保持；业务身份统一为 MemberNFT，删除地址主体平行路径，NFT 代理仅作用于群聊。

## 来源

- `LOVE20TKM/group-chat@ce21ea8f29b3750421876ae649fa7d919fe42cff`：`LOVE20TKM/group-chat/src/GroupChat.sol`、`LOVE20TKM/group-chat/src/GroupAdmin.sol`、`LOVE20TKM/group-chat/src/GroupMember.sol`、`LOVE20TKM/group-chat/src/GroupBanList.sol`、`LOVE20TKM/group-chat/src/managers/`、`LOVE20TKM/group-chat/src/sources/`、`LOVE20TKM/group-chat/src/interfaces/`。
- `LOVE20TKM/group@2eb6d6c8d48bf6dd382efa5887124a2c3c722fd9`：`LOVE20TKM/group/src/GroupDelegate.sol`、`LOVE20TKM/group/src/interfaces/IGroupDelegate.sol`。
- 本轮核对的是干净本地源码。实际迁移仍须冻结部署证明；不得修改旧组织。

## 变更边界

| 组件 | 保留 | BSC 必要修改 |
| --- | --- | --- |
| GroupChat | 一 NFT 一 Chat、激活、四槽位、消息、提及、引用、索引、分页、插件失败处理 | 依赖改 MemberNFT；删除 postAsDefaultSender 和 GroupDefaults；预检查不再接收业务地址 |
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
- 旧 TokenMainManager 的持币阈值是严格大于 1 个最小单位；按“其他行为不变”保留。
- 旧行动黑名单读取当前 Vote Round 的行动票权，分母为全社区当前治理票；不固定在 Proposal 创建 Round。
- 旧 GroupDelegate 实现在 group 仓库；迁到 group-chat 并限制消费者，不是给全局 MemberNFT 添加授权。
- 旧群内委托还可以管理管理员、成员和人工黑名单，不能被精简为“只能改开关与槽位”。
- forceExit 只移除一个资格分支，不能推导为所有 Chat 资格立即失效。

## 验收

按 [群聊规格](group-chat/README.md) 回归保留功能；对删除项检查 ABI、状态、事件和消费者均无残留。对身份替换、委托隔离、Manager 付款/持有和黑名单当前轮权重作差异测试，证据记录在 [组织验收](../acceptance.md)。
