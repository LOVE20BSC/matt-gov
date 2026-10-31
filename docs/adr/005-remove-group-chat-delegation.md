# ADR-005: 移除群聊内 NFT 委托

## 状态

已接受 (2026-10-31)

## 背景

`GroupChatDelegate` 从旧 `LOVE20TKM/group/src/GroupDelegate.sol` 迁入，实现「按群、按 memberId 的运营权委派」：

- 键为 `groupId`，值为 `{delegateId, ownerSnapshot, delegateOwnerSnapshot}`；
- 群主把某个群的运营权委派给另一个 memberId，NFT 仍留在原钱包；
- 两个 owner 快照任一失配即自动失效；
- 被委派人需先开启接受开关（默认关闭）；
- 授予的能力：改群聊配置、授予/撤销管理员、增删成员、拉黑/解黑；发言时额外获得 `mentionAll` 与 scope/ban 豁免。

它带来三类成本：

1. **鉴权路径分叉**：所有授权入口都要先调 `ownerOrDelegateId` / `effectiveDelegateId`，每次操作多 1–2 次跨合约 `ownerOf`，且 `operatorId` 的含义随调用者变化（owner 时为 `groupId`，委派时为 `delegateId`）。
2. **能力重叠**：成员与黑名单管理已由 `GroupAdmin` 的管理员承担（同样是「按群 + memberId + 双 owner 快照自动失效」），委托只在「改配置、任命管理员、发言豁免」三处提供额外能力。
3. **语义不对称**：delegate 发言可绕过 scope/ban，admin 却不能；同样的「运营者」概念在不同入口有不同边界。

产品侧的判断是：参与主体本来就是 memberId，`ownerOf(memberId) == msg.sender` 足以表达身份。若将来需要「代持并代理行使」，应由上层合约完成（把 NFT 转入托管合约并指定代理人），不应内建在群聊授权里。

## 决策

**删除 `GroupChatDelegate` 及其全部消费者，群聊授权只认 NFT 当前持有人。**

- 删除 `GroupChatDelegate.sol`、`IGroupChatDelegate.sol`，以及四个合约与接口中的 `GROUP_DELEGATE_ADDRESS`。
- `GroupAdmin` 构造函数改为直接接收 `groupAddress`，不再从委托合约派生。
- 配置写入口（`setPostingAllowed` 与四个槽位）与管理员授予/撤销：**仅群 owner**。`operatorId` 参数保留用于事件，但必须等于 `groupId`，否则回 `NotGroupOperator(groupId, operatorId)`。
- 成员名单与人工黑名单：群 owner 或有效 admin（维持原状）。
- 发言：仍校验 `senderId` 的 NFT 所有权；scope/ban 豁免与 `mentionAll` 只保留群 owner，`mentionAll` 另外保留有效 admin。
- `GroupMember` / `GroupChatBanList` 的 `_isOperator` 内联回各自合约：先判群存在（`GroupNotExist`），再判 `ownerOf(operatorId) == msg.sender`，最后判 `operatorId == groupId || isAdminId`。

**上层方案（不在本仓库实现）**：需要代理时，由使用者把 MemberNFT 转入一个不可升级的托管合约，合约记录原持有人与代理人，代理期间由合约以自身地址调用协议；原持有人保留取回权。该方案委派的是整个身份而非单个群，且 `msg.sender` 变为托管合约地址，事件与退款路径随之改变——这是独立的产品取舍，不属群聊授权。

## 后果

### 正面影响

1. **鉴权收敛为单一不变式**：`actor 地址 ↔ memberId` 只有 `MemberNFT.ownerOf(memberId) == msg.sender` 一条路径，不再有「地址解析成哪个 memberId」的分支。
2. **每次操作少 1–2 次外部调用**：发帖不再解析 `effectiveDelegateId`，配置 setter 不再解析 `ownerOrDelegateId`。
3. **删除 313 行合约与接口**、四个 `GROUP_DELEGATE_ADDRESS` getter、一个部署步骤与对应的校验脚本项。
4. **消除能力不对称**：admin 与 owner 的边界由权限表一次性说明，不再有「delegate 能绕 scope/ban、admin 不能」的例外。

### 负面影响

1. **失去按群委派配置权**：多人协作运营一个群时，配置修改必须由群 NFT 持有人执行。需要多人操作时，只能转移群 NFT 或等待上层托管方案。
2. **失去委托接受开关与反向枚举**：`isDelegationAcceptanceEnabled`、`delegatedGroupIds` 等查询不存在。
3. **ABI 破坏性变更**：删除 `setDelegateId`、`clearDelegatedGroupIds`、`setDelegationAcceptanceEnabled`、`isDelegationAcceptanceEnabled`、`effectiveDelegateId`、`effectiveDelegateIdsByGroupIds`、`delegatedGroupIds`、`ownerOrDelegateId` 与三个事件；四个合约删除 `GROUP_DELEGATE_ADDRESS`；`GroupAdmin` 构造签名由 `(address,uint256)` 改语义为 `(groupAddress,uint256)`。本仓库无生产部署，只影响同批更新的调用方与索引。
4. **`operatorId` 变为冗余参数**：配置与管理入口仍保留该参数以维持事件字段，但必须等于 `groupId`。后续如需彻底清理，可与事件字段一起在下一个 major 变更中移除。

## 相关文档

- [群聊生命周期](../specs/group-chat/01-lifecycle.md)
- [群聊规则](../specs/group-chat/02-rules.md)
- [群聊事件与错误](../specs/group-chat/07-events-errors.md)
- [群聊迁移差异](../specs/CHANGES-group-chat.md)
