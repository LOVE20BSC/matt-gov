# Action 验收

行为以各模块为准，跨仓库证据见 [组织验收](../../acceptance.md)。本表是待实现的验收要求，不表示测试已运行。

| 模块 | 必测场景 | 预期 |
| --- | --- | --- |
| [ActionTarget](01-action-target.md) | 三类回调、executor 握手、映射、重复创建、非授权调用、加入轮校验、行动列表查询 | 只用关联 Executor，回调失败全回滚，当前投票轮不大于创建轮时注册回滚 `JoinNotOpen`，`votedActions` 与本轮投票一致，`actions`/`actionIdsByExecutor` 与创建绑定一致 |
| ActionTarget | `init` 只收 Mint、派生依赖与零值拒绝 | `voteAddress`/`submitAddress`/`memberNFTAddress`/`phaseAddress` 从 Mint 读取一次并缓存；`mintAddress` 或任一派生值为零回滚 `InvalidAddress` 且不锁定状态，修正后可重试 |
| ActionTarget | forceExit 后正常退出 | forceExit 只清 Target 加入状态；随后 Executor 仍可返还资产、清理群归属，调用 `clearJoinState` 幂等成功 |
| ActionTarget | 分页顺序契约 | 按 `01-action-target.md` 顺序契约执行：加入态集合的 `offset` 不保证跨调用稳定，删除（swap-and-pop）后同一 `offset` 的返回内容可变化；`offset` 越界返回空数组与真实总数、`limit = 0` 只返回总数 |
| ActionTarget | Target Data 位置契约 | 创建与推举回调共用同一份 Target Data：第 `0` 项均为 executor 保留项、业务项从第 `1` 项起；投票回调为投票者提供的数据，非空时第 `0` 项为已绑定 Executor、其后为业务项；三类回调转发门禁——`targetData` 非空时第 `0` 项必须为已绑定 Executor 地址（否则回滚），投票回调空数据原样透传；项数、位置与编码由各 Executor 自定并自行拒绝 |
| ActionTarget | 激励铸造粒度与事件 | Executor 每轮经 `mintActionReward` 铸造整笔一次，`(tokenAddress, actionId, round)` 重复由 Mint 回滚 `AlreadyMinted()`（ActionTarget 不另存铸造状态位），成功时发出行动级 `ActionRewardMinted(tokenAddress, actionId, round, amount)` 且 `amount` 与 `actionReward` 返回值一致；Mint 收到的 `recipient` 即该行动的绑定 Executor，铸造路径上不发生任何代币转账；成员不参与该链路，ActionTarget 不暴露成员领取入口 |
| ActionTarget | 铸造入口权限与查询 | 仅 `(tokenAddress, actionId)` 已注册绑定的 Executor 可调用铸造，其他地址与未注册绑定均回滚 `UnauthorizedExecutor`；`actionReward` 未关联返回 `(0, false)`、已关联未铸造返回 `(理论可铸造数量, false)`、铸造后返回 `(amount, true)`，均不回滚 |
| ActionTarget | 防御路径（桩测试） | 推举/投票回调面对未绑定 Proposal 回滚 `UnboundProposal`（真依赖不可达，另起 `*StubTest`）；`onProposalCreated` 遇到握手会回滚的 Executor 归一为 `InvalidExecutor`（桩合约） |
| [Executor 基座](00-executor-interface.md) | 批量成员结算、参与量查询 | `mintMemberRewards` 平行数组按下标配对、长度不一致回滚 `BatchLengthMismatch`、任一元素失败整笔回滚、空数组无状态变化；零额结算（`mintAmount` 与 `burnAmount` 均为 0）回滚 `NoRewardAvailable` 且不置位已结算，后续可重试；`joinedAmount`/`joinedAmountByMemberId` 返回截止加入轮结束的累计参与量（与各 Executor 参与账本一致，`round` 晚于当前加入轮返回 0），`joinedAmountTokenAddress` 为参与计价代币 |
| [LP](04-lp-executor.md) | 时间加权、治理上限、部分撤回与全额自动退出、完整退出 | 按 V2 聚合扣减结算，结算不超预算，零分母不 panic；零额结算回滚 `NoRewardAvailable`（纯销毁 `mintAmount = 0`、`burnAmount > 0` 仍结算且 `minted` 为 true）；轮次与错误映射按 04 表 |
| [阶段](02-phase-model.md) | LP 冷启动、GroupAction/GroupService 对齐 | 按确认后的三/四阶段映射，未开始回滚 RoundNotStarted；成员结算对未创建的行动回滚 ActionNotCreated（三个 Executor 一致，批量里任一元素未创建即整批回滚），`round` 早于创建轮仍回 RoundNotStarted；对应 `testMintRejectsAnUncreatedAction`、`testMintMemberRewardRejectsRoundsOutOfRange`、`testBatchSettlementPairsArraysAndRollsBack` |
| [GroupAction](05-group-action-executor.md) | 激活、配置更新、自有/Provider 额度参与 | 按角色权限更新各自账本；`join` 的 `providerId` 决定来源，同一成员可混合多个来源并逐次追加；`updateGroupConfig` 回滚 `GroupNotActive`；同一成员在同一行动上至多激活一个链群，行动内以 `isGroupActive` 直查、不设按 owner 的行动维度列表/质押，社区级 `hasActiveGroups(tokenAddress, memberId)` 与 `totalStakedByMemberId(tokenAddress, memberId)` 保留；群集合/质押/快照查询（`activeGroupIds`、`staked`、`totalStaked`、`totalStakedByMemberId`、`tokenAddressesByGroupId`、`actionIds` 族、`descriptionByRound`、`hasActiveGroups`、`maxJoinAmount`）符合标准分页与零值口径 |
| GroupAction | Provider 部分/全部撤回、越权调用、NFT 转移 | 只有该 Provider 当前持有人可 `providerWithdraw` 且只返还其代币；成员不能撤回 Provider 额度或 Provider 已投入部分；剩余自有或其他 Provider 余额时不退出，总参与量归零才自动退出；权限与收款跟随对应 NFT |
| GroupAction | Provider 额度授予、部分使用、追加、收回、枚举 | 授予即把代币存入合约；`join` 只扣减额度、不转移代币；成员只使用部分额度时其余额度保留；重复 `join` 与重复授予是追加不回滚；`providerQuotaRemove` 只退还未使用额度；`providerQuota` 与 `providerAmountsByMemberId` 的分页结果分别与额度表、逐来源账本一致；批量授予/收回对每个成员各发一条 `ProviderQuotaAdded`/`ProviderQuotaRemoved`，金额与账本变动一致 |
| GroupAction | 部署体积与拆分边界 | Executor 与三个业务库（`GroupActionVerify`/`GroupActionJoin`/`GroupActionManager`）的 runtime 均不超过 24,576 字节——Executor 读 `forge build --sizes`，三个库从 `out/<库名>.sol/<库名>.json` 的 `deployedBytecode` 计长（`--sizes` 不列出未链接的库）；库调用只出现在函数级、不入循环，库间无 DELEGATECALL（判据：各业务库的 `linkReferences` 不含其他业务库）；分组与共享规则的归属见 [05](05-group-action-executor.md#部署体积与拆分)；链上被其他合约调用的接口（`isGroupMember`、`generatedActionReward`、`generatedActionRewardByGroupId`、基座 Round 与参与量查询）实现在 Executor 本地而非转发库；地址与 ABI 不变 |
| GroupAction | 退出恢复 Provider 额度、不转出合约 | 成员 `exit` 后自有资产返还成员、Provider 来源回到可用额度且合约余额不变（除自有部分）；Provider 用 `providerQuotaRemove` 仍可取回；成员可用同一额度再次加入 |
| GroupAction | 验证的每成员写入次数 | 每个成员每轮至多产生一次新的冷写入（非满分写扣分、满分零写入）；组级累计量走轮级累加器；`originScore`/`finalScore` 仍返回 `(score, verified)` 且未验证与已验证零分可区分 |
| GroupAction | 位置化已验证推导的跨轮稳定性 | 目标轮计分后，后续轮集合变动（含成员退出引起的位移）不改变该轮解码；同轮加入→退出→再加入按该轮最终排列计分与解码；部分批次时余量保持未验证；集合定位失配（槽位与成员不符）按未验证返回、不误判已验证 |
| GroupAction | 整轮验证计数 | 只有该轮全部群的游标追平成员数后 `roundVerified` 才为真；`verifiedGroupCount` 与该轮群数一致；空轮保持 false（结算先看 `totalFinalScore`）；已完成群的重复提交回滚 `AlreadyVerified` |
| GroupAction | 代币量事件出口 | 参与代币量只由 `Joined`/`Withdrawn` 承载；单笔 `withdraw`/`providerWithdraw` 各发一条带 `providerId` 的 `Withdrawn`；`exit` 按来源逐条发出（自有来源为 0，每个有余额的 Provider 一条）后再发 `Exited`，`Withdrawn` 金额之和等于实际返还总额，`Exited` 带链群 `groupId`、不带金额 |
| GroupAction | `init` 派生依赖与零校验 | `memberNFTAddress`/`phaseAddress`/`voteAddress` 从 `stakeAddress` 读取一次并缓存，任一为零回滚 `InvalidAddress`；不接收 `mintAddress` |
| GroupAction | 创建数据与验证信息长度 | Target Data 项数不为 `6`（无验证信息）或 `7`（含验证信息）回滚 `InvalidTargetDataLength`；schema 两数组不等长、成员值项数与 schema 不符回滚 `VerificationInfoLengthMismatch` |
| GroupAction | 参与索引分页与归属计数 | 五条 `g*` 分页查询的 `offset`/`limit`/`reverse`/`total` 符合标准分页契约；`isGroupMember` 与 `gTokenAddressesByGroupIdByMemberId` 同源一致，且都在最后一个关系退出后才归零；`forceExit` 不改动 |
| GroupAction | 按轮历史两读 | `groupIds`、`memberIdsByGroupId` 按目标轮历史返回，分页契约同 `g*`；`groupIds` 与验证游标衔接，加入阶段结束后该轮结果稳定，`offset` 连续翻页等价于验证游标 |
| GroupAction | 逐笔 Round 历史、同轮多次变更、空轮继承 | 验证读取冻结历史，退出状态不复活 |
| GroupAction | 申请版本、平票、前 n 开放 | 零票申请不入榜；替换或撤销把旧申请从排名移除且不补位；榜满严格超过末位才替换；`topVerifiers` 按票数降序回 `verifierIds[]`/`votes[]` 且与 `votesByVerifierIds`、`verifierApplications` 一致；`verifierApplication` 无申请回零值结构体，已取消申请不再出现在 `verifierApplications` |
| GroupAction | 申请常设与按轮历史 | 第 3 轮提交的申请在第 4、5 轮查询时返回同一 `applicationId`；第 3 轮申请、第 5 轮修改后，查第 4 轮仍返回**第 3 轮的申请与说明**（`RoundHistory` 懒继承），查第 5、6 轮返回新申请；申请创建轮之前的轮次一律零值；撤销在该轮写入零值终止点、不回写更早轮次；跨轮复用整条流水线时不重新申请也能投票、锁定与验证；投票轮之后替换或撤销申请不影响该轮已当选验证者的锁定与验证（候选身份按该轮历史解析，不读当前申请）；对应 `testVerifierApplicationHistorySurvivesALaterModification`、`testVerifierApplicationStandsAcrossRounds`、`testCrossRoundReuseRunsTheWholePipeline`、`testReplacingAfterTheVoteRoundKeepsTheVerificationRight`、`testCancellingAfterTheVoteRoundKeepsTheVerificationRight` |
| GroupAction | 跨轮复用：后续轮重新推举、投票、加入、验证、结算 | 票数与排名按轮隔离（`votesByApplicationId` 以 `round` 为键，不存在跨轮累计值），创建轮的票不抬高后续轮排名；候选没有当前申请时投票回滚 `ApplicationNotActive`；同一行动在第 N 轮与第 M 轮各自完成「投票→加入→验证→结算」且互不影响，`generatedActionReward` 按轮返回该轮金额；`votesByVerifierIds` 只返回指定轮的票 |
| GroupAction | 验证者押金（申请划转、修改不重复划转、撤销全额退还） | `verifierStakeAmount = 0` 时申请与撤销都不转账；首次申请按配置额划转，修改申请（含换轮修改）不退款也不再划转且不发新的押金事件；撤销把押金全额退还给 memberId 当前持有人（退款跟随 NFT 转移后的新持有人）；无治理票、说明超长（1025 字节回滚、正好 1024 字节通过并划转）与未创建行动的申请、无当前申请的撤销都不产生划转；多成员各自独立，一人撤销不影响他人押金；同一社区不同行动各自配置与独立，一个行动撤销不影响另一个行动的押金与配置；`verifierStake` 与「持有当前申请」一致（持有返回配置额，撤销后为 0）；创建轮结束后撤销仍然有效并退款；已在本轮排名内或已锁定的验证者撤销后照常退款，且不影响该轮的锁定与后续批次提交；余额或授权不足时整笔回滚、不留下申请；押金不进 `staked`/`totalStaked`/`totalStakedByMemberId`，不改变 `hasActiveGroups`；`VerifierStakeDeposited`/`VerifierStakeRefunded` 的金额与代币划转一致，申请与撤销事件的 `round` 是操作发生的轮次（撤销事件不再是创建轮）；对应 `testVerifierStakeLifecycle`、`testVerifierApplicationReplacementKeepsTheBond`、`testLockedVerifierKeepsVerifyingAfterCancelling`、`testVerifierApplicationCancelEventCarriesTheCancelRound` |
| GroupAction | 描述字段长度上限 | 候选人申请说明与群描述 `GroupConfig.description` 超过 1024 字节均回滚 `DescriptionTooLong`；正好 1024 字节通过 |
| GroupAction | 开放区块与容量查询 | `SPLITS()` 回 init 传入的分割线且只读；用它与 `IPhase.phaseInfo(round + 2)` 算出的开放区块与合约判定一致，可开放人数为 `SPLITS().length + 1` |
| GroupAction | 连续批次、NFT 转移续验、无候选/失联 | 无跳跃或重复，不换锁定身份；未完成行动层激励为零 |
| GroupAction | 停用链群继续目标轮验证 | 加入轮结束后停用、恢复或新增链群都不改变该轮验证集合，目标轮验证仍可完成，不因当前激活状态阻断 |
| GroupAction | 未完成验证时的行动层查询 | `generatedActionReward` 与 `generatedActionRewardByGroupId` 按轮次返回 0，部分批次已计入不产生正值，`totalFinalScore` 为零时不除零 |
| GroupAction | 完整验证后的成员和群激励 | 符合权重与舍入公式 |
| [GroupService](06-service-executor.md) | 全社区聚合、同币/直接父币、非直接关系 | 分母按 `votedActions` 枚举并过滤 `executor == groupActionExecutorAddress`、逐行动求和；源行动查询自行处理验证条件；非法代币关系回滚 `InvalidParentToken`；`ratioForPublicVerifier > 1e18` 回滚 `InvalidRatio` |
| GroupService | `init` 派生依赖与零校验 | `memberNFTAddress`/`phaseAddress`/`launchAddress` 从 `stakeAddress` 读取一次并缓存，`mintAddress` 从 `ActionTarget.mintAddress()` 读取一次并缓存，任一为零回滚 `InvalidAddress`；`mintAddress` 不作为 `init` 参数；不派生 `voteAddress` |
| GroupService | 加入资格两类分支与 join/exit 边界 | owner 分支 = 成员自身作为链群在社区存在激活行动（`hasActiveGroups`）；候选分支 = 被加入的那一轮的社区行动集内存在有效验证者申请（资格按 `currentJoinRound()` 判定，申请在其创建轮之前不算，对应 `testJoinReadsTheApplicationAtTheJoinedRound`）；晚加入从加入轮起生效、不回填更早轮次；均不满足回滚 `NoActiveGroups`；重复 `join` 回滚 `AlreadyJoined`、未加入 `exit` 回滚 `NotJoined`；`joinInfo` 转发 `isJoinedByRound`，退出不追回已发生轮 |
| GroupService | 分母实时计算、缓存与零分母结算 | 分母与权重同源；分母对每个入榜行动读一次 `A[a]`（O(votedActions)），权重另读群切片、成员为锁定验证者时再读一次 `A[a]`，群切片按分数现算；**行动代币**那一轮被 Mint 准备后分母才缓存，父币服务 / 子币行动时子币那轮未准备，分母必须保持实时；`D == 0` 时任何角色结算都回滚 `NoRewardAvailable`，整笔激励停留在未结算状态、预留不释放 |
| GroupService | 验证者比例（按服务 Proposal 绑定）、owner 治理上限、100% 二次分配 | 验证者按工作量直接分配；owner 超额销毁；分配不超预算、不下溢；`RATIO_FOR_PUBLIC_VERIFIER` 按 `serviceActionId` 读取并与权重计算一致；上限判定按 `cap >= ceilDiv(W, D)` 形式比较（等价于交叉相乘，但不做会溢出的乘法），未触发时无取整粉尘销毁 |
| GroupService | 公式全精度与旧版回归 | 中间量不提前截断（`Math.mulDiv`）；旧版最小复现（`S=3, T=3, G=2, g=2`）不再下溢；owner 权重按群切片 floor、`Σ ownerWeight <= D`，未覆盖份额不重分配；`Σ 转账 + 销毁 ≤ serviceReward` 恒成立；100% 配置合法且 owner 无下溢；恒有 `ownerReward == ownerDistributed + ownerRemaining` |
| GroupService | 事件可还原资产变化 | `DistributeRecipient` 逐笔记录接收者金额与来源行动；`ServiceRewardDistributed` 含 owner 份额的已分配/自留拆分（`ownerDistributed`/`ownerRemaining`）；它与 `MemberRewardMinted` 和服务代币的 `TokenBurn` 一起可完整还原结算的全部资产变化 |
| GroupService | 二次分配配置枚举与试算 | `actionIdsWithRecipients` 按轮分页枚举已配置源行动（懒继承、显式清空移除、越界返回空 + 真实总数）；`getDistribution` 对任意金额按同规则试算（逐项 floor、余数归 owner、100% 不下溢）；`rewardByRecipient` 单接收者投影（`recipientId == groupId` 回 owner 自留额、非接收者回 0） |

各模块“待确认”项仍需先确定预期；不得把旧用例运行成功当成新规格无冲突。
