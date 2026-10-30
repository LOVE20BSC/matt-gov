# 生命周期与群聊内委托

## 激活与配置

保留 GroupChat 的 `activateChat` 和五个配置 setter。仅 groupId 当前 owner 可首次激活；NFT 必须存在，Chat 尚未激活，非零规则地址必须有代码。激活永久记录首次 owner/区块/时间，默认允许发言并加入可发现群列表。激活事件 `GroupChatActivated` 携带初始 5 项配置（`postingAllowed`、`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`），零地址表示该槽位关闭。

激活后，owner 或有效 delegate 可更新发言开关和四个槽位；普通管理员无此权限。配置写入口先完成鉴权（含群存在性），再校验已激活；非授权方不会拿到激活状态或配置差异。相同配置重复设置按旧实现无操作返回。每次变更发对应 `*Changed` 事件（`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged`），地址槽位保留旧值。typed Manager 未暴露配置转发，故不能由激活付款者重配，见 [Manager](06-manager.md)。

## NFT 委托

迁移旧 `LOVE20TKM/group/src/GroupDelegate.sol`，依赖 MemberNFT，但代码和授权消费者仅在 group-chat：

- `setDelegateId(groupId, delegateId)` 由群 NFT 当前 owner 调用。0 表示撤销；非零 delegateId 必须存在（缺失回 `ERC721NonexistentToken(delegateId)`）且不同于 groupId（相等回 `DelegateIsSelfGroup(groupId)`）。目标 memberId 的委托接受开关必须为开，否则回 `DelegateNotAcceptingNewDelegations(delegateId)`。
- 校验顺序：先检查 `delegateId == groupId`、delegate NFT 存在性，再检查接受开关，最后判断是否与现有状态相同。无效请求不会因为与现有记录相同而被静默吞掉；只有通过校验的重复设置才按幂等无操作返回。
- 委托接受开关按目标 memberId 保存，默认关闭，只有 delegate NFT 当前持有人可开关。开关随 memberId 而非持有人：delegate NFT 转移后设置不变，新持有人继承当前值并可自行开关。开关只约束新指定，不改变已有委托的有效性：关闭后既有委托继续生效，直到被撤销或因 owner 快照失配而失效；撤销（`delegateId = 0`）永远允许。群或 delegate NFT 转移后委托失效，重新设回属于新指定，需要开关为开。
- 每群至多一个 delegateId。保存群与 delegate NFT 的 owner 快照；任一 owner 变化则无效。转回快照 owner 时恢复，不删除历史记录。有效性变化本身不产生协议事件：群 owner 或 delegate NFT 转移由 core ERC721 `Transfer` 折叠。
- `DelegateChanged` 的旧值组（`prevDelegateId`、`prevOwnerSnapshot`、`prevDelegateOwnerSnapshot`）一律取**原始存储**，不取「当前有效值」：委托因 owner 转移失效后再清空时，`prevDelegateId` 仍是被清掉的原始 delegateId，与同组两个非零快照自洽，消费方可据此重建 `delegatedGroupIds` 的移除。新值组在 `delegateId = 0` 时两个快照都写零。
- delegate NFT 当前持有人可批量清除自己收到的委托、开关委托接受；缺失 delegateId 的写入口回 `ERC721NonexistentToken(delegateId)`，非 owner 回 `NotMemberOwner(delegateId)`。delegate NFT 缺失时，查询与有效性判断按无有效 delegate 处理，不回滚：`isDelegationAcceptanceEnabled` 返回 false，`delegatedGroupIds` 返回空且 totalCount=0。
- 保留有效 delegate 查询、批量查询与被委托群枚举分页；事件按本规范命名：`DelegateChanged`、`DelegationCleared`、`DelegationAcceptanceChanged`。`DelegateChanged` 是群主对 `delegateId` 的赋值变更（`0` 表示撤销），`DelegationCleared` 是 delegate 持有人批量清除自己收到的群链接：前者以群为主体，后者以 delegate 为主体。

委托接口见 [`IGroupChatDelegate.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatDelegate.sol)，包括有效 delegate 查询和分页枚举。

## 权限范围

| 操作 | 允许身份 |
| --- | --- |
| 激活 Chat | 群 owner |
| 发言开关、四个槽位 | 群 owner 或有效 delegate |
| 授予/撤销管理员 | 群 owner 或有效 delegate |
| 成员名单、人工黑名单 | 群 owner、有效 delegate 或有效 admin |
| 发言 | 始终校验调用者持有显式 senderId；委托不能冒充群 NFT |
| Core 质押、投票、铸造、发射、Action 验证 | 此委托不产生任何权限 |

管理员保留群 NFT 和 admin NFT 双 owner 快照、转移失效/转回恢复及旧数量上限。删除 GroupDefaults 查找，改由操作显式提供 `operatorId`/`adminId`。

“限制在群聊内”不等于“只剩开关和槽位”：旧群内的管理员、成员及人工黑名单管理能力继续保留。Core MemberNFT 的 ERC721 转移授权与此业务委托分开。

来源：旧 `LOVE20TKM/group/src/GroupDelegate.sol`、`LOVE20TKM/group-chat/src/GroupAdmin.sol`、`LOVE20TKM/group-chat/src/GroupMember.sol`、`LOVE20TKM/group-chat/src/GroupBanList.sol`，提交见 [入口](README.md#已核对来源)。验收见 [群聊验收](08-testing.md)。
