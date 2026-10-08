# Action 验收

行为以各模块为准，跨仓库证据见 [组织验收](../../acceptance.md)。本表是待实现的验收要求，不表示测试已运行。

| 模块 | 必测场景 | 预期 |
| --- | --- | --- |
| [ActionTarget](01-action-target.md) | 三类回调、executor 握手、映射、重复创建、非授权调用、加入轮校验、行动列表查询 | 只用关联 Executor，回调失败全回滚，当前投票轮不大于创建轮时注册回滚 `JoinNotOpen`，`votedActions` 与本轮投票一致，`actions`/`actionIdsByExecutor` 与创建绑定一致 |
| ActionTarget | `init` 只收 Mint、派生依赖与零值拒绝 | `voteAddress`/`submitAddress`/`memberNFTAddress`/`phaseAddress` 从 Mint 读取一次并缓存；`mintAddress` 或任一派生值为零回滚 `InvalidAddress` 且不锁定状态，修正后可重试 |
| ActionTarget | forceExit 后正常退出 | forceExit 只清 Target 加入状态；随后 Executor 仍可返还资产、清理群归属，调用 `clearJoinState` 幂等成功 |
| ActionTarget | 分页顺序契约 | 按 `01-action-target.md` 顺序契约执行：加入态集合的 `offset` 不保证跨调用稳定，删除（swap-and-pop）后同一 `offset` 的返回内容可变化；`offset` 越界返回空数组与真实总数、`limit = 0` 只返回总数 |
| ActionTarget | Target Data 位置契约 | 创建与推举回调共用同一份 Target Data：第 `0` 项均为 executor 保留项、业务项从第 `1` 项起；投票回调为投票者提供的数据，非空时第 `0` 项为已绑定 Executor、其后为业务项；三类回调转发门禁——`targetData` 非空时第 `0` 项必须为已绑定 Executor 地址（否则回滚），投票回调空数据原样透传；项数、位置与编码由各 Executor 自定并自行拒绝 |
| ActionTarget | 激励铸造粒度与事件 | Executor 每轮经 `mintActionReward` 铸造整笔一次，`(tokenAddress, actionId, round)` 重复回滚 `AlreadyMinted`，成功时发出行动级 `ActionRewardMinted(tokenAddress, actionId, round, amount)` 且 `amount` 与 `actionReward` 返回值一致；成员不参与该链路，ActionTarget 不暴露成员领取入口 |
| ActionTarget | 铸造入口权限与查询 | 仅 `(tokenAddress, actionId)` 已注册绑定的 Executor 可调用铸造，其他地址与未注册绑定均回滚 `UnauthorizedExecutor`；`actionReward` 未关联返回 `(0, false)`、已关联未铸造返回 `(理论可铸造数量, false)`（已销毁返回 `(0, false)`）、铸造后返回 `(amount, true)`，均不回滚 |
| ActionTarget | 防御路径（桩测试） | 推举/投票回调面对未绑定 Proposal 回滚 `UnboundProposal`（真依赖不可达，另起 `*StubTest`）；`mintActionReward` 在代币 `transfer` 返 false 时回滚 `TransferFailed`（桩代币） |
| [Executor 基座](00-executor-interface.md) | 批量成员结算、销毁判据、参与量查询 | `mintMemberRewards` 平行数组按下标配对、长度不一致回滚 `BatchLengthMismatch`、任一元素失败整笔回滚、空数组无状态变化；`needBurnReward` 只对已结束轮次且无人有资格铸造的激励返回真；`joinedAmount`/`joinedAmountByMemberId` 返回截止加入轮结束的累计参与量（与各 Executor 参与账本一致，`round` 晚于当前加入轮返回 0），`joinedAmountTokenAddress` 为参与计价代币 |
| [ActionTarget](01-action-target.md) | 行动级销毁 | 任何人可触发 `burnRewardIfNeeded`：未绑定/已销毁/未铸造/额度为零/`needBurnReward` 为假均无操作，未结束轮次回滚 `InvalidRound`，重复调用无操作；经 Mint 的 `burnUnmintedProposalReward` 核销该行动本轮预留激励（标记该 Proposal 已结算、此后铸造回滚），无代币移动，`RewardBurned`/`burnInfo` 与 Mint 账本同源 |
| [LP](04-lp-executor.md) | 时间加权、治理上限、部分撤回与全额自动退出、完整退出 | 按 V2 聚合扣减结算，结算不超预算，零分母不 panic；轮次与错误映射按 04 表 |
| [阶段](02-phase-model.md) | LP 冷启动、GroupAction/GroupService 对齐 | 按确认后的三/四阶段映射，未开始回滚 RoundNotStarted |
| [GroupAction](05-group-action-executor.md) | 激活、配置更新、自有/Provider 额度参与 | 按角色权限更新各自账本；`join` 的 `providerId` 决定来源，同一成员可混合多个来源并逐次追加；`updateGroupConfig` 回滚 `GroupNotActive`；同一成员在同一行动上至多激活一个链群，行动内以 `isGroupActive` 直查、不设按 owner 的行动维度列表/质押，社区级 `hasActiveGroups(tokenAddress, memberId)` 与 `totalStakedByMemberId(tokenAddress, memberId)` 保留；群集合/质押/快照查询（`activeGroupIds`、`staked`、`totalStaked`、`totalStakedByMemberId`、`tokenAddressesByGroupId`、`actionIds` 族、`descriptionByRound`、`hasActiveGroups`、`maxJoinAmount`）符合标准分页与零值口径 |
| GroupAction | Provider 部分/全部撤回、越权调用、NFT 转移 | 只有该 Provider 当前持有人可 `providerWithdraw` 且只返还其代币；成员不能撤回 Provider 额度或 Provider 已投入部分；剩余自有或其他 Provider 余额时不退出，总参与量归零才自动退出；权限与收款跟随对应 NFT |
| GroupAction | Provider 额度授予、部分使用、追加、收回、枚举 | 授予即把代币存入合约；`join` 只扣减额度、不转移代币；成员只使用部分额度时其余额度保留；重复 `join` 与重复授予是追加不回滚；`providerQuotaRemove` 只退还未使用额度；`providerQuota` 与 `providerAmountsByMemberId` 的分页结果分别与额度表、逐来源账本一致；批量授予/收回对每个成员各发一条 `ProviderQuotaAdded`/`ProviderQuotaRemoved`，金额与账本变动一致 |
| GroupAction | 部署体积与拆分边界 | Executor 与三个业务库（`GroupActionVerify`/`GroupActionJoin`/`GroupActionManager`）的 runtime 均不超过 24,576 字节——Executor 读 `forge build --sizes`，三个库从 `out/<库名>.sol/<库名>.json` 的 `deployedBytecode` 计长（`--sizes` 不列出未链接的库）；库调用只出现在函数级、不入循环，库间无 DELEGATECALL（判据：各业务库的 `linkReferences` 不含其他业务库）；分组与共享规则的归属见 [05](05-group-action-executor.md#部署体积与拆分)；链上被其他合约调用的接口（`isGroupMember`、`generatedActionRewardByGroupId`、`needBurnReward`、基座 Round 与参与量查询）实现在 Executor 本地而非转发库；地址与 ABI 不变 |
| GroupAction | 退出恢复 Provider 额度、不转出合约 | 成员 `exit` 后自有资产返还成员、Provider 来源回到可用额度且合约余额不变（除自有部分）；Provider 用 `providerQuotaRemove` 仍可取回；成员可用同一额度再次加入 |
| GroupAction | 验证的每成员写入次数 | 每个成员每轮至多产生一次新的冷写入（非满分写扣分、满分零写入）；组级累计量走轮级累加器；`originScore`/`finalScore` 仍返回 `(score, verified)` 且未验证与已验证零分可区分 |
| GroupAction | 位置化已验证推导的跨轮稳定性 | 目标轮计分后，后续轮集合变动（含成员退出引起的位移）不改变该轮解码；同轮加入→退出→再加入按该轮最终排列计分与解码；部分批次时余量保持未验证；集合定位失配（槽位与成员不符）按未验证返回、不误判已验证 |
| GroupAction | 代币量事件出口 | 代币量只由 `Joined`/`Withdrawn` 承载；单笔 `withdraw`/`providerWithdraw` 各发一条带 `providerId` 的 `Withdrawn`；`exit` 按来源逐条发出（自有来源为 0，每个有余额的 Provider 一条）后再发 `Exited`，`Withdrawn` 金额之和等于实际返还总额，`Exited` 带链群 `groupId`、不带金额 |
| GroupAction | `init` 派生依赖与零校验 | `memberNFTAddress`/`phaseAddress`/`voteAddress` 从 `stakeAddress` 读取一次并缓存，任一为零回滚 `InvalidAddress`；不接收 `mintAddress` |
| GroupAction | 创建数据与验证信息长度 | Target Data 项数超出约定回滚 `InvalidTargetDataLength`；schema 两数组不等长、成员值项数与 schema 不符回滚 `VerificationInfoLengthMismatch` |
| GroupAction | 参与索引分页与归属计数 | 五条 `g*` 分页查询的 `offset`/`limit`/`reverse`/`total` 符合标准分页契约；`isGroupMember` 与 `gTokenAddressesByGroupIdByMemberId` 同源一致，且都在最后一个关系退出后才归零；`forceExit` 不改动 |
| GroupAction | 按轮历史两读 | `groupIds`、`memberIdsByGroupId` 按目标轮历史返回，分页契约同 `g*`；`groupIds` 与验证游标衔接，加入阶段结束后该轮结果稳定，`offset` 连续翻页等价于验证游标 |
| GroupAction | 逐笔 Round 历史、同轮多次变更、空轮继承 | 验证读取冻结历史，退出状态不复活 |
| GroupAction | 申请版本、平票、前 n 开放 | 零票申请不入榜；替换或撤销把旧申请从排名移除且不补位；榜满严格超过末位才替换；`topVerifiers` 按票数降序回 `verifierIds[]`/`votes[]` 且与 `votesByVerifierIds`、`verifierApplications` 一致；`verifierApplication` 无申请回零值结构体，已取消申请不再出现在 `verifierApplications` |
| GroupAction | 描述字段长度上限 | 候选人申请说明与群描述 `GroupConfig.description` 超过 1024 字节均回滚 `DescriptionTooLong`；正好 1024 字节通过 |
| GroupAction | 开放区块与容量查询 | `SPLITS()` 回 init 传入的分割线且只读；用它与 `IPhase.phaseInfo(round + 2)` 算出的开放区块与合约判定一致，可开放人数为 `SPLITS().length + 1` |
| GroupAction | 连续批次、NFT 转移续验、无候选/失联 | 无跳跃或重复，不换锁定身份；未完成行动层激励为零 |
| GroupAction | 停用链群继续目标轮验证 | 加入轮结束后停用、恢复或新增链群都不改变该轮验证集合，目标轮验证仍可完成，不因当前激活状态阻断 |
| GroupAction | 未完成验证时的行动层查询 | `generatedActionRewardByGroupId` 与分配查询按轮次返回 0，部分批次已计入不产生正值，`totalFinalScore` 为零时不除零 |
| GroupAction | 完整验证后的成员和群激励 | 符合权重与舍入公式 |
| [GroupService](06-service-executor.md) | 全社区聚合、同币/直接父币、非直接关系 | 全部 GroupAction 激励作分母；源行动查询自行处理验证条件；非法代币关系拒绝 |
| GroupService | `init` 派生依赖与零校验 | `memberNFTAddress`/`phaseAddress`/`voteAddress` 从 `stakeAddress` 读取一次并缓存，任一为零回滚 `InvalidAddress`；不接收 `mintAddress` |
| GroupService | 验证者比例（按服务 Proposal 绑定）、owner 治理上限、100% 二次分配 | 验证者按工作量直接分配；owner 超额销毁；分配不超预算、不下溢；`ratioForPublicVerifier` 按 `serviceProposalId` 读取并与权重计算一致 |

各模块“待确认”项仍需先确定预期；不得把旧用例运行成功当成新规格无冲突。
