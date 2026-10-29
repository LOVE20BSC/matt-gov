# Chat 类型与资格

保留旧四类 typed Manager 和 owner 管理型群聊；身份查询改用 memberId，不改变原资格组合和黑名单算法。

| 类型 | 资格 | 单个黑名单投票者权重 |
| --- | --- | --- |
| 代币社区 | 余额 > 0（任一最小单位），或有效治理票 > 0，或当前参与该社区行动 | 社区当前有效治理票 |
| 代币治理 | 社区当前有效治理票 > 0 | 同左 |
| 代币行动 | 最近 RECENT_ROUNDS 轮给该行动投票，或当前参与该行动 | 当前 Vote Round 给该 Proposal 的累计票数 |
| 代币行动治理 | 最近 RECENT_ROUNDS 轮给该行动投票 | 当前 Vote Round 给该 Proposal 的累计票数 |
| 群组 | 成员名单命中，或当前归属该群的 GroupAction | 人工黑名单，无治理加权 |

## 资格数据

- 持币判断为 `token.balanceOf(MemberNFT.ownerOf(senderId)) > 0`，任一最小单位即满足；身份解析改为 memberId，“删除地址主体”不删除 ERC20 余额读取。
- 治理票和 Proposal 投票直接按 memberId 查询；普通/扩展行动的参与来源统一适配为 ActionTarget，不保留旧 Join/ExtensionCenter 地址主体查询。
- `RECENT_ROUNDS > 0`；当前部署值 3。检查当前治理 Round 并逐轮向前，遇 BSC 最小有效 Round 1 停止；有一轮给该行动投票即满足资格。它是发言资格窗口，不是黑名单权重窗口。
- GroupMemberScope 只查名单；组合资格源先查名单，再查 `IGroupActionIndexes.isGroupMember(groupId, senderId)`。标准 GroupAction Executor 覆盖其所有社区和行动。

## 黑名单

`targetSenderId` 只要求非零，不要求 MemberNFT 存在（允许预黑名单）；`0` 回 `ZeroTargetSenderId()`。

`voteWeightOf(groupId, voterId)` 使用上表权重；两类 token Manager 和两类 action Manager 的 `totalVoteWeight(groupId)` 都取所属社区的当前总有效治理票，不取行动总票数或创建 Round。

权重源不是独立配置项，而是群 NFT 的当前持有者：`GovVotedBanSource` 以 `MemberNFT.ownerOf(groupId)` 解析权重合约，再调用其 `voteWeightOf` / `totalVoteWeight`。四类 Manager 在托管群 NFT 的同时实现 `IBanVoteWeightSource`，因此只有 Manager 托管的 Chat 具备治理加权封禁。群不存在回 `GroupNotExist(groupId)`；群存在但持有者是 EOA，或未实现该接口的合约钱包时，写票回 `BanVoteWeightSourceUnavailable(groupId, source)`（`source` 为解析出的失败权重源地址），只能用人工黑名单；`setBanSource` 只校验地址有代码，误配不会在配置期报错。

GovVotedBanSource 的接口见 [`IGovVotedBanSource.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/sources/ban/IGovVotedBanSource.sol)，其 voter 和 target 均使用 `memberId`。

支持/反对按 `groupId + targetSenderId + voterId` 保存。保留 GovVotedBanSource 的增量结算：改票先移除旧 settledWeight，再加入新权重；撤票移除旧权重；任何地址可刷新已存在的 voterId 票，权重归零时清除该票。写入/撤票需校验该 voterId 当前 owner；刷新不能改变支持/反对立场。

```text
totalVoteWeight > 0
supportWeight > opposeWeight * 10
supportWeight * 1e18 >= totalVoteWeight * 3e15
```

同时满足才进入黑名单，保留严格比较、0.3% 门槛及无变化/无投票记录的处理：重复投票（方向与权重都未变）回 `VoteUnchanged(groupId, targetSenderId, voterId)`，不做名单同步（source 不可用时先回 `BanVoteWeightSourceUnavailable`）。同票重投不结算权重漂移；该 target 上任何投票/撤票/刷新都会按实时分母重算名单，本票权重的唯一改口入口是 `refreshVoteBySenderId`。撤票或刷新找不到记录回 `VoteNotFound(groupId, targetSenderId, voterId)`，投票权重为 0 回 `ZeroVoteWeight(groupId, voterId)`。`minSupportToOpposeMultiplier > 0` 与 `banThresholdRatio <= 1e18`（0 合法）是部署期静态不变量，由部署脚本在广播前校验（dev-standards §5.7）。投票/撤票/刷新后同步目标名单；`isBanned` 读取已结算名单，不全量扫描重算。

不设版本字段：每次已结算变更都由 `SenderBanVoteCast` / `GovSenderBanChanged` 携带完整事实，链下缓存按事件失效即可。

`supportWeight` / `opposeWeight` / `isBanned` 都是**已结算**值，分母 `totalVoteWeight` 是**实时**值；跨轮或 Stake 变化不会自动刷新其他人的票，名单因此可能双向过期（该进未进、该出未出）。`refreshVoteBySenderId` 无鉴权、幂等、结果与调用者无关，任何地址都可提前结算。

投票身份按 voterId 该 MemberNFT 的**当前**持有人校验，不保存 owner 快照，与 admin/delegate 的双快照模型不同：NFT 转移后旧票仍按原 `settledWeight` 计数，新持有人可改票、撤票或刷新，旧持有人不再能操作该票。

查询视图对 source 无代码的处理：单条 `voteStatusBySenderId` 返回 `(false, 0, 0)`；批量 `voteStatusBySenderIds`、`isBanned`、`isSenderIdBannedBatch` 不检查 source，直接读已结算名单与权重。已结算值照常可读，权重查询才需要 source 合约存在。

## forceClearJoinState 与资格

采用组合资格源的群组，满足以下任一条件即可通过成员资格检查：在该群的成员名单中，或仍在该群下参加至少一个 GroupAction。仅名单型资格源只看成员名单。

- ActionTarget.forceClearJoinState 不修改 GroupAction 的群归属与 Executor 仓位，所以不会取消上述群组资格；但会取消代币社区/行动 Chat 中由该行动加入状态提供的资格。持币、治理票、近期投票等其他条件仍独立判断。
- GroupAction 实际退出（包括 Provider 额度撤回至总参与量为零）后，若成员已不在该群下参加任何行动，便不再满足行动归属条件；名单仍有效时，仍能通过成员资格检查。

例：成员同时在群成员名单中、也在该群下参加一个行动。退出该行动后，因为仍在名单中，成员资格仍成立。实际发言还须通过发言开关、黑名单等检查。

## 成员与管理员

成员/管理员和人工黑名单的旧批量增删、枚举、事件、owner 快照及幂等行为不变，只删除地址目标和默认身份查找。权限见 [生命周期](01-lifecycle.md#权限范围)。

成员、管理员和人工黑名单接口见 [`IGroupAdmin.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupAdmin.sol)、[`IGroupMember.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupMember.sol) 与 [`IGroupChatBanList.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/IGroupChatBanList.sol)。写操作显式传入操作者 `operatorId`。

核对来源：旧 `LOVE20TKM/group-chat/src/managers/TokenMainManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenActionScopeManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenScopeManager.sol`、`LOVE20TKM/group-chat/src/sources/ban/GovVotedBanSource.sol`、`LOVE20TKM/group-chat/src/sources/scope/GroupJoinScopeSource.sol`，提交见 [入口](README.md#已核对来源)。
