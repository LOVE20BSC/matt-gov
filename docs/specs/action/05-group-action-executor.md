# 链群行动 Executor

链群使用 MemberNFT 身份，`groupId` 是链群主体的 `memberId`，不是钱包地址。参与资产见 [共同模型](03-participation.md)，四阶段映射见 [阶段模型](02-phase-model.md)。

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

加入结束后不得回写目标 Round。验证直接读取该轮链群和成员历史，不需要前置准备交易；验证按历史成员顺序使用连续游标，不能重复、跳过或乱序。

原存储示意为 `mapping(round => mapping(groupId => mapping(memberId => ParticipationData)))`；外层仍须隔离 token 和 action。沿用旧 RoundHistory 语义：无记录表示继承最近历史，退出通过显式记录零值形成终止点，不能直接删除历史记录。

## 候选与验证

候选只在投票阶段新增、撤销或修改；排序按 `candidateVotes` 降序、`applicationId` 升序，平票时较早申请优先。

第 1 名在验证阶段起点开放，后续排名按下式开放：

```text
openOffset = ceil(verifyPhaseBlocks * splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

`splits[0]` 对应第 2 名。`block.number >= openBlock` 才开放，不能因取整提前。

首个有效验证批次永久锁定验证者 MemberNFT；NFT 转移后新持有人续验，不能由未经授权候选接管。需完成目标 Round 的全部链群验证；无候选或锁定者失联、未完成时，行动层激励为零，底层 Proposal 激励仍可独立铸造或销毁。相关验收见 [组织验收](../../acceptance.md#公共验证者与-round-历史)。

## 行动激励

公共验证者对所有链群成员使用同一规则记录 `originScore`（0–100）并计算 `finalScore`。行动激励直接按所有链群成员的最终得分统一加权：

```text
memberScore = 参与代币数量 * finalScore
totalFinalScore = sum(memberScore across all groups)
memberReward = floor(proposalReward * memberScore / totalFinalScore)
```

所有链群使用同一原始得分和最终得分规则；按目标 Round 已确认参与数据汇总全行动的 `totalFinalScore` 后直接分配。`totalVotes` 或 `totalFinalScore` 为零时不除零，行动层激励为零；链群 owner 的聚合份额由其成员最终激励之和得到，不在链群内再次按比例分配。

Executor 先按 [统一铸造链路](07-minting.md#铸造链路) 取得整笔激励，再内部分配。

## 实现约束

- 退出零值与无记录继续使用旧 RoundHistory 的显式记录语义；不得通过清空 mapping 伪造退出。
- `candidateCount = n` 时 `splits.length == max(n - 1, 0)`；排名在验证阶段开始时冻结，申请只能在投票阶段修改。
- 激活、配置更新、候选申请及验证批次 ABI 以实现接口补齐；原 `LOVE20TKM/action/GroupAction` 仅作为行为参考。

验收见 [Action 验收](08-testing.md)。
