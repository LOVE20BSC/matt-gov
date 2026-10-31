# 生命周期与权限

## 激活与配置

保留 GroupChat 的 `activateChat` 和五个配置 setter。仅 groupId 当前 owner 可首次激活；NFT 必须存在，Chat 尚未激活，非零规则地址必须有代码。激活永久记录首次 owner/区块/时间，默认允许发言并加入可发现群列表。激活事件 `GroupChatActivated` 携带初始 5 项配置（`postingAllowed`、`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`），零地址表示该槽位关闭。

激活后，仅群 owner 可更新发言开关和四个槽位；普通管理员无此权限。配置写入口先完成鉴权（含群存在性），再校验已激活；非授权方不会拿到激活状态或配置差异。入口的 `operatorId` 必须等于 `groupId`，否则回 `NotGroupOperator(groupId, operatorId)`；该参数仅为事件字段保留。相同配置重复设置按旧实现无操作返回。每次变更发对应 `*Changed` 事件（`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged`），地址槽位保留旧值。typed Manager 未暴露配置转发，故不能由激活付款者重配，见 [Manager](06-manager.md)。

## NFT 委托（已移除）

旧 `LOVE20TKM/group/src/GroupDelegate.sol` 的群内 NFT 委托已整体删除，决策与取舍见 [ADR-005](../../adr/005-remove-group-chat-delegation.md)：

- 不再有 `GroupChatDelegate` 合约、`GROUP_DELEGATE_ADDRESS` getter，也不再有 `setDelegateId` / `delegatedGroupIds` 等入口与查询。
- 群聊不再解析「当前地址对应哪个 memberId」：身份只有 `MemberNFT.ownerOf(memberId) == msg.sender` 一条判据。
- 需要代理时由上层合约完成（把 MemberNFT 转入托管合约并指定代理人），它委派的是整个身份，不在本仓库实现。

## 权限范围

| 操作 | 允许身份 |
| --- | --- |
| 激活 Chat | 群 owner |
| 发言开关、四个槽位 | 群 owner（`operatorId` 必须等于 `groupId`） |
| 授予/撤销管理员 | 群 owner（`operatorId` 必须等于 `groupId`） |
| 成员名单、人工黑名单 | 群 owner 或有效 admin |
| 发言 | 始终校验调用者持有显式 senderId |
| scope/ban 豁免 | 群 owner |
| `mentionAll` | 群 owner 或有效 admin |
| Core 质押、投票、铸造、发射、Action 验证 | 群聊权限不产生任何授权 |

管理员保留群 NFT 和 admin NFT 双 owner 快照、转移失效/转回恢复及旧数量上限。删除 GroupDefaults 查找，改由操作显式提供 `operatorId`/`adminId`。

来源：旧 `LOVE20TKM/group-chat/src/GroupAdmin.sol`、`LOVE20TKM/group-chat/src/GroupMember.sol`、`LOVE20TKM/group-chat/src/GroupBanList.sol`，提交见 [入口](README.md#已核对来源)。验收见 [群聊验收](08-testing.md)。
