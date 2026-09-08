# GroupAction Executor

GroupAction 使用 MemberNFT 身份，`groupId` 是群主体的 `memberId`，不是钱包地址。参与资产见 [共同模型](03-participation.md)，四阶段映射见 [阶段模型](02-phase-model.md)。

## 配置与参与接口

旧 `LOVE20TKM/extension-group/src/GroupManager.sol` / `LOVE20TKM/extension-group/src/GroupJoin.sol` 的 extension 地址改为 `tokenAddress + actionId`；不为每个 Proposal 部署 Executor。部署依赖通过 init 绑定，业务配置由 Proposal 创建回调写入。

```solidity
struct GroupConfig {
    string description;
    uint256 maxCapacity;
    uint256 minJoinAmount;
    uint256 maxJoinAmount;
    uint256 maxAccounts;
}
function init(address actionTargetAddress, address memberNFTAddress, address phaseAddress,
    address stakeAddress, address mintAddress, uint256[] calldata splits) external;
function activateGroup(address tokenAddress, uint256 actionId, uint256 groupId, GroupConfig calldata config) external;
function deactivateGroup(address tokenAddress, uint256 actionId, uint256 groupId) external;
function updateGroupInfo(address tokenAddress, uint256 actionId, uint256 groupId, GroupConfig calldata config) external;
function groupInfo(address tokenAddress, uint256 actionId, uint256 groupId)
    external view returns (GroupConfig memory config, bool active, uint256 activatedRound, uint256 deactivatedRound);
function join(address tokenAddress, uint256 actionId, uint256 groupId, uint256 memberId,
    uint256 amount, string[] calldata verificationInfos) external;
function withdraw(address tokenAddress, uint256 actionId, uint256 memberId, uint256 amount) external;
function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
function joinInfo(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256 joinedRound, uint256 amount, uint256 groupId);
function groupIds(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256[] memory);
function memberIdsByGroupId(address tokenAddress, uint256 actionId, uint256 round, uint256 groupId)
    external view returns (uint256[] memory);
function joinedAmountByMemberId(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256);
```

创建 KV 沿用旧行动参数：`joinTokenAddress(address)`、`activationStakeAmount(uint256)`、`maxJoinAmountRatio(uint256)`、`activationMinGovRatio(uint256)`，键取 `keccak256`、值取 `abi.encode`。验证信息键和说明沿用 LP 的可选 KV。配置和激活资格、质押退还及容量计算沿用旧 GroupManager；`maxCapacity = 0` 使用理论容量，`maxJoinAmount/maxAccounts = 0` 不另设群级上限，非零最大加入量不得低于最小加入量。

管理操作要求持有 groupId；自有参与操作要求持有 memberId。同一行动中成员只能归属一个 Group，追加不得改群；换群须先正常退出。`amount` 查询包含自有和体验参与总量。withdraw 只减少自有账本；自有余额归零且体验余额也为零时自动退出。Provider 只能用 trialWithdraw 撤回自己的体验代币；若使总参与量归零，合约自动退出成员。成员调用 exit 时同时结清自有和体验账本，分别返还成员和 Provider。无参与记录返回零元组，历史集合无记录返回空数组。

## 当前归属与索引

事实关系为 `tokenAddress + actionId + groupId + memberId`。跨本 Executor 的所有社区和行动维护 17 组可枚举索引：

| 维度 | 查询名 |
| --- | --- |
| Group ID | `gGroupIds`、`gGroupIdsByMemberId`、`gGroupIdsByTokenAddress`、`gGroupIdsByTokenAddressByMemberId`、`gGroupIdsByTokenAddressByActionId` |
| Token Address | `gTokenAddresses`、`gTokenAddressesByMemberId`、`gTokenAddressesByGroupId`、`gTokenAddressesByGroupIdByMemberId` |
| Action ID | `gActionIdsByTokenAddress`、`gActionIdsByTokenAddressByMemberId`、`gActionIdsByTokenAddressByGroupId`、`gActionIdsByTokenAddressByGroupIdByMemberId` |
| Member ID | `gMemberIds`、`gMemberIdsByGroupId`、`gMemberIdsByTokenAddress`、`gMemberIdsByTokenAddressByGroupId` |

每组提供全量数组、追加 `Count` 的数量查询和追加 `AtIndex` 的单项查询。加入/退出同步维护，不依赖扫描事件。仍有其他有效关系时不能提前移除上层索引；最后关系退出才逐层清理。ActionTarget.forceExit 不修改这些索引。

## Round 历史

加入阶段每笔加入、追加、体验加入、部分撤回及退出，都更新当轮参与记录。同一 Round 多次操作只保留该轮最终值，不新增多个版本；无人交互的 Round 继承最近历史，不逐轮复制或同步。

加入结束后不得回写目标 Round。验证直接读取该轮 Group 和成员历史，不需要前置准备交易；验证按历史成员顺序使用连续游标，不能重复、跳过或乱序。

原存储示意为 `mapping(round => mapping(groupId => mapping(memberId => ParticipationData)))`；外层仍须隔离 token 和 action。沿用旧 RoundHistory 语义：无记录表示继承最近历史，退出通过显式记录零值形成终止点，不能直接删除历史记录。

## 候选与验证

候选只在投票阶段新增、撤销或修改；排序按 `candidateVotes` 降序、`applicationId` 升序，平票时较早申请优先。

```solidity
struct VerifierApplication {
    uint256 applicationId;
    uint256 memberId;
    string description;
    uint256 ratioForPublicVerifier;
    uint256 votes;
    bool active;
}
function applyForVerifier(address tokenAddress, uint256 actionId, uint256 memberId,
    string calldata description, uint256 ratioForPublicVerifier) external returns (uint256 applicationId);
function cancelVerifierApplication(address tokenAddress, uint256 actionId, uint256 memberId) external;
function currentApplicationId(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256);
function verifierApplication(address tokenAddress, uint256 actionId, uint256 round, uint256 applicationId)
    external view returns (VerifierApplication memory);
function verifierApplicationsCount(address tokenAddress, uint256 actionId, uint256 round)
    external view returns (uint256);
function verifierApplicationAtIndex(address tokenAddress, uint256 actionId, uint256 round, uint256 index)
    external view returns (VerifierApplication memory);
function rankedApplicationIds(address tokenAddress, uint256 actionId, uint256 round)
    external view returns (uint256[] memory);
function submitOriginScores(address tokenAddress, uint256 actionId, uint256 round,
    uint256 verifierMemberId, uint256 groupId, uint256 startIndex, uint256[] calldata originScores) external;
function verifiedMemberCount(address tokenAddress, uint256 actionId, uint256 round, uint256 groupId)
    external view returns (uint256);
function lockedVerifierId(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256);
function isRoundVerified(address tokenAddress, uint256 actionId, uint256 round) external view returns (bool);
function originScore(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256 score, bool verified);
function finalScore(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256);
function totalFinalScore(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256);
function generatedActionRewardByGroupId(address tokenAddress, uint256 actionId, uint256 round, uint256 groupId)
    external view returns (uint256);
```

申请者须持有 memberId 且有该社区有效治理票；比例范围 `0..1e18`。apply 新建或替换当前申请：旧 ID 失效但保留票数，新 ID 单调递增且从零计票。取消只移除当前关联和榜内项，不扫描榜外补位。不存在申请查询回滚；无当前申请 ID 返回 0。

投票 KV 使用 `keccak256("candidateMemberId")` / `abi.encode(uint256)`，对应当前有效 applicationId；每次回调将全部治理票增量记给该候选。候选字段为空时不增加候选票，有字段但申请已失效则回滚。排名增量维护，只保存可开放的前 n 名；榜满时榜外候选必须票数严格超过末位才替换，不因修改旧申请自动转移票数。

`submitOriginScores` 仅接受当前验证 Round；调用者持有 verifierMemberId，批次数组非空，每项不超过 100，`startIndex` 等于该群已验证数量且不能超出历史成员数。全部校验成功才锁定和计分；同一成员记录只消费一次。未验证的分数查询返回 `(0, false)`，与已验证零分区分。

第 1 名在验证阶段起点开放，后续排名按下式开放：

```text
openOffset = ceil(verifyPhaseBlocks * splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

`splits[0]` 对应第 2 名。`block.number >= openBlock` 才开放，不能因取整提前。

首个有效验证批次永久锁定验证者 MemberNFT；NFT 转移后新持有人续验，不能由未经授权候选接管。需完成目标 Round 的全部 Group 验证；无候选或锁定者失联、未完成时，行动层激励为零，底层 Proposal 激励仍可独立铸造或销毁。相关验收见 [组织验收](../../acceptance.md#公共验证者与-round-历史)。

## 行动激励

公共验证者按同一规则记录原始分和最终分。每条冻结成员记录只计入一次，不允许对同一份参与量重复评分。

```text
finalScore(memberId) = participationAmount(memberId) * originScore(memberId)
totalFinalScore = sum(finalScore across all groups)
memberReward(memberId) = floor(proposalReward * finalScore(memberId) / totalFinalScore)
```

所有 Group 使用同一原始得分和最终得分规则；按目标 Round 已确认参与数据汇总全行动的 `totalFinalScore` 后直接分配。`totalFinalScore` 为零时不除零，行动层激励为零；群 owner 的聚合份额由其成员最终激励之和得到，不在 Group 内再次按比例分配。

Executor 先按 [统一铸造链路](07-minting.md#铸造链路) 取得整笔激励，再内部分配。

## 实现约束

- 退出零值与无记录继续使用旧 RoundHistory 的显式记录语义；不得通过清空 mapping 伪造退出。
- `candidateCount = n` 表示最大可开放排名数，不是本轮总申请人数；`n = splits.length + 1`。分割线严格递增且在 `(0, 1e18)` 内，空数组只开放第 1 名。投票结束后排名自然冻结，不增加冻结交易。
- 候选竞选是 BSC 新逻辑；旧 `LOVE20TKM/extension-group/src/GroupVerify.sol` 的 `submitOriginScores` 仅作为连续批次和原始分校验的参考，不是候选机制来源。

验收见 [Action 验收](08-testing.md)。
