# 生命周期与群聊内委托

## 激活与配置

保留 GroupChat 的 `activateChat` 和五个配置 setter。仅 groupId 当前 owner 可首次激活；NFT 必须存在，Chat 尚未激活，非零规则地址必须有代码。激活永久记录首次 owner/区块/时间，默认允许发言并加入可发现群列表。

激活后，owner 或有效 delegate 可更新发言开关和四个槽位；普通管理员无此权限。相同配置重复设置按旧实现无操作返回。typed Manager 未暴露配置转发，故不能由激活付款者重配，见 [Manager](06-manager.md)。

## NFT 委托

迁移旧 `LOVE20TKM/group/src/GroupDelegate.sol`，依赖 MemberNFT，但代码和授权消费者仅在 group-chat：

- `setDelegateId(groupId, delegateId)` 由群 NFT 当前 owner 调用。0 表示撤销；非零 delegateId 必须存在且不同于 groupId。
- 每群至多一个 delegateId。保存群与 delegate NFT 的 owner 快照；任一 owner 变化或白名单不允许则无效。转回快照 owner 且白名单允许时恢复，不删除历史记录。
- delegate NFT 当前持有人可批量清除自己收到的委托、开关委托方白名单和维护允许的 groupId 列表。
- 保留有效 delegate 查询、批量查询、被委托群/白名单枚举与分页、幂等行为及旧事件。

```solidity
function setDelegateId(uint256 groupId, uint256 delegateId) external;
function clearDelegatedGroupIds(uint256 delegateId, uint256[] calldata groupIds) external;
function setDelegatorWhitelistEnabled(uint256 delegateId, bool enabled) external;
function setAllowedDelegatorGroupIds(uint256 delegateId, uint256[] calldata groupIds, bool allowed) external;
function isDelegatorWhitelistEnabled(uint256 delegateId) external view returns (bool);
function canSetDelegateTo(uint256 groupId, uint256 delegateId) external view returns (bool);
function allowedDelegatorGroupIds(uint256 delegateId, uint256 offset, uint256 limit)
    external view returns (uint256[] memory groupIds, uint256 total);
function allowedDelegatorGroupIdsCount(uint256 delegateId) external view returns (uint256);
function delegateIdOf(uint256 groupId) external view returns (uint256);
function delegateIdsOf(uint256[] calldata groupIds) external view returns (uint256[] memory delegateIds);
function delegatedGroupIds(uint256 delegateId, uint256 offset, uint256 limit)
    external view returns (uint256[] memory groupIds, bool[] memory isEffective, uint256 total);
function delegatedGroupIdsCount(uint256 delegateId) external view returns (uint256);
```

## 权限范围

| 操作 | 允许身份 |
| --- | --- |
| 激活 Chat | 群 owner |
| 发言开关、四个槽位 | 群 owner 或有效 delegate |
| 授予/撤销管理员 | 群 owner 或有效 delegate |
| 成员名单、人工黑名单 | 群 owner、有效 delegate 或有效 admin |
| 发言 | 始终校验调用者持有显式 senderId；委托不能冒充群 NFT |
| Core 质押、投票、铸造、发射、Action 验证 | 此委托不产生任何权限 |

管理员保留群 NFT 和 admin NFT 双 owner 快照、转移失效/转回恢复及旧数量上限。删除 GroupDefaults 查找，改由操作显式提供 adminId。

“限制在群聊内”不等于“只剩开关和槽位”：旧群内的管理员、成员及人工黑名单管理能力继续保留。Core MemberNFT 的 ERC721 转移授权与此业务委托分开。

来源：旧 `LOVE20TKM/group/src/GroupDelegate.sol`、`LOVE20TKM/group-chat/src/GroupAdmin.sol`、`LOVE20TKM/group-chat/src/GroupMember.sol`、`LOVE20TKM/group-chat/src/GroupBanList.sol`，提交见 [入口](README.md#已核对来源)。验收见 [群聊验收](08-testing.md)。
