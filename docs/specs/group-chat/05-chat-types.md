# Chat 类型与资格

保留旧四类 typed Manager 和 owner 管理型群聊；身份查询改用 memberId，不改变原资格组合和黑名单算法。

| 类型 | 资格 | 单个黑名单投票者权重 |
| --- | --- | --- |
| 代币社区 | 余额 > 1 个最小单位，或有效治理票 > 0，或当前参与该社区行动 | 社区当前有效治理票 |
| 代币治理 | 社区当前有效治理票 > 0 | 同左 |
| 代币行动 | 最近 RECENT_ROUNDS 轮给该行动投票，或当前参与该行动 | 当前 Vote Round 给该 Proposal 的累计票数 |
| 代币行动治理 | 最近 RECENT_ROUNDS 轮给该行动投票 | 当前 Vote Round 给该 Proposal 的累计票数 |
| 群组 | 成员名单命中，或当前归属该群的 GroupAction | 人工黑名单，无治理加权 |

## 资格数据

- 持币判断为 `token.balanceOf(MemberNFT.ownerOf(senderId)) > 1`，不是 > 0。它保留旧 TokenMainManager 的阈值，只改变身份解析方式；“删除地址主体”不删除 ERC20 余额读取。
- 治理票和 Proposal 投票直接按 memberId 查询；普通/扩展行动的参与来源统一适配为 ActionTarget，不保留旧 Join/ExtensionCenter 地址主体查询。
- `RECENT_ROUNDS > 0`；保留旧部署值 3。检查当前治理 Round 并逐轮向前，遇 BSC 最小有效 Round 1 停止；有一轮给该行动投票即满足资格。它是发言资格窗口，不是黑名单权重窗口。
- GroupMemberScope 只查名单；组合资格源先查名单，再查 `gTokenAddressesByGroupIdByMemberIdCount(groupId, senderId) > 0`。标准 GroupAction Executor 覆盖其所有社区和行动。

## 黑名单

`voteWeightOf(groupId, voterId)` 使用上表权重；两类 token Manager 和两类 action Manager 的 `totalVoteWeight(groupId)` 都取所属社区的当前总有效治理票，不取行动总票数或创建 Round。

支持/反对按 `groupId + targetSenderId + voterId` 保存。保留 GovVotedBanSource 的增量结算：改票先移除旧 settledWeight，再加入新权重；撤票移除旧权重；任何地址可刷新已存在的 voterId 票，权重归零时清除该票。写入/撤票需校验该 voterId 当前 owner；刷新不能改变支持/反对立场。

```text
totalVoteWeight > 0
supportWeight > opposeWeight * 10
supportWeight * 1e18 >= totalVoteWeight * 3e15
```

同时满足才进入黑名单，保留严格比较、0.3% 门槛、stateVersion、无变化和无投票记录的旧处理。投票/撤票/刷新后同步目标名单；`isBanned` 读取已结算名单，不全量扫描重算。跨轮或 Stake 变化不会自动刷新其他人的票。

## forceExit 与资格

采用组合资格源的群组，满足以下任一条件即可通过成员资格检查：在该群的成员名单中，或仍在该群下参加至少一个 GroupAction。仅名单型资格源只看成员名单。

- ActionTarget.forceExit 不修改 GroupAction 的群归属，所以不会取消上述群组资格；但会取消代币社区/行动 Chat 中由该行动加入状态提供的资格。持币、治理票、近期投票等其他条件仍独立判断。
- GroupAction 实际退出（包括体验撤回至总参与量为零）后，若成员已不在该群下参加任何行动，便不再满足行动归属条件；名单仍有效时，仍能通过成员资格检查。

例：成员同时在群成员名单中、也在该群下参加一个行动。退出该行动后，因为仍在名单中，成员资格仍成立。实际发言还须通过发言开关、黑名单等检查。

## 成员与管理员

成员/管理员和人工黑名单的旧批量增删、枚举、事件、owner 快照及幂等行为不变，只删除地址目标和默认身份查找。权限见 [生命周期](01-lifecycle.md#权限范围)。

```solidity
function addAdmins(uint256 groupId, uint256[] calldata adminIds) external;
function removeAdmins(uint256 groupId, uint256[] calldata adminIds) external;
function adminIdOf(uint256 groupId, address account) external view returns (uint256);
function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool);
function adminIds(uint256 groupId) external view returns (uint256[] memory ids, bool[] memory isEffective);
function addMemberIds(uint256 groupId, uint256[] calldata memberIds) external;
function removeMemberIds(uint256 groupId, uint256[] calldata memberIds) external;
function isMemberId(uint256 groupId, uint256 memberId) external view returns (bool);
function isMemberIdBatch(uint256 groupId, uint256[] calldata memberIds) external view returns (bool[] memory listed);
function memberIdsCount(uint256 groupId) external view returns (uint256);
function memberIds(uint256 groupId, uint256 offset, uint256 limit) external view returns (uint256[] memory);
function banBySenderIds(uint256 groupId, uint256[] calldata senderIds) external;
function unbanBySenderIds(uint256 groupId, uint256[] calldata senderIds) external;
function senderIdBanListCount(uint256 groupId) external view returns (uint256);
function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit)
    external view returns (uint256[] memory senderIds, address[] memory operatorAddresses, uint256[] memory operatorIds);
function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool);
```

核对来源：旧 `LOVE20TKM/group-chat/src/managers/TokenMainManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenActionScopeManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenScopeManager.sol`、`LOVE20TKM/group-chat/src/sources/ban/GovVotedBanSource.sol`、`LOVE20TKM/group-chat/src/sources/scope/GroupJoinScopeSource.sol`，提交见 [入口](README.md#已核对来源)。
