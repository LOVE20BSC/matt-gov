# Action 验收

行为以各模块为准，跨仓库证据见 [组织验收](../../acceptance.md)。本表是待实现的验收要求，不表示测试已运行。

| 模块 | 必测场景 | 预期 |
| --- | --- | --- |
| [ActionTarget](01-action-target.md) | 三类回调、executor 握手、映射、重复创建、非授权调用、加入轮校验、行动列表查询 | 只用关联 Executor，回调失败全回滚，当前投票轮不大于创建轮时注册回滚 `JoinNotOpen`，`votedActions` 与本轮投票一致，`actions`/`actionIdsByExecutor` 与创建绑定一致 |
| ActionTarget | forceExit 后正常退出 | forceExit 只清 Target 加入状态；随后 Executor 仍可返还资产、清理群归属，调用 `clearJoinState` 幂等成功 |
| ActionTarget | 分页顺序契约 | 按 `01-action-target.md` 顺序契约执行：加入态集合的 `offset` 不保证跨调用稳定，删除（swap-and-pop）后同一 `offset` 的返回内容可变化；`offset` 越界返回空数组与真实总数、`limit = 0` 只返回总数 |
| ActionTarget | Target Data 位置契约 | 创建与推举回调共用同一份 Target Data：第 `0` 项均为 executor 保留项、业务项从第 `1` 项起；投票回调为投票者提供的数据，非空时第 `0` 项为已绑定 Executor、其后为业务项；三类回调转发门禁——`targetData` 非空时第 `0` 项必须为已绑定 Executor 地址（否则回滚），投票回调空数据原样透传；项数、位置与编码由各 Executor 自定并自行拒绝 |
| ActionTarget | 激励铸造粒度与事件 | Executor 每轮经 `mintActionReward` 铸造整笔一次，`(tokenAddress, actionId, round)` 重复回滚 `AlreadyMinted`，成功时发出行动级 `ActionRewardMinted(tokenAddress, actionId, round, amount)` 且 `amount` 与 `actionReward` 返回值一致；成员不参与该链路，ActionTarget 不暴露成员领取入口 |
| ActionTarget | 铸造入口权限与查询 | 仅 `(tokenAddress, actionId)` 已注册绑定的 Executor 可调用铸造，其他地址与未注册绑定均回滚 `UnauthorizedExecutor`；`actionReward` 在未铸造/未关联时返回 `(0, false)` 不回滚，铸造后返回 `(amount, true)` |
| ActionTarget | 防御路径（桩测试） | 推举/投票回调面对未绑定 Proposal 回滚 `UnboundProposal`（真依赖不可达，另起 `*StubTest`）；`mintActionReward` 在代币 `transfer` 返 false 时回滚 `TransferFailed`（桩代币） |
| [Executor 基座](00-executor-interface.md) | 批量成员结算、销毁判据、参与量查询 | `mintMemberRewards` 平行数组按下标配对、长度不一致回滚 `BatchLengthMismatch`、任一元素失败整笔回滚、空数组无状态变化；`needBurnReward` 只对已结束轮次且无人有资格铸造的激励返回真；`joinedAmount`/`joinedAmountByMemberId` 返回截止加入轮结束的累计参与量（与各 Executor 参与账本一致，`round` 晚于当前加入轮返回 0），`joinedAmountTokenAddress` 为参与计价代币 |
| [ActionTarget](01-action-target.md) | 行动级销毁 | 任何人可触发 `burnRewardIfNeeded`：未绑定/已销毁/未铸造/额度为零/`needBurnReward` 为假均无操作，未结束轮次回滚 `InvalidRound`，重复调用无操作；经 Mint 的 `burnUnmintedProposalReward` 核销该行动本轮预留激励（标记该 Proposal 已结算、此后铸造回滚），无代币移动，`RewardBurned`/`burnInfo` 与 Mint 账本同源 |
| [LP](04-lp-executor.md) | 时间加权、治理上限、部分撤回与全额自动退出、完整退出 | 按 V2 聚合扣减结算，结算不超预算，零分母不 panic；轮次与错误映射按 04 表 |
| [阶段](02-phase-model.md) | LP 冷启动、GroupAction/GroupService 对齐 | 按确认后的三/四阶段映射，未开始回滚 RoundNotStarted |
| [GroupAction](05-group-action-executor.md) | 激活、配置更新、自有/体验参与 | 按角色权限更新各自账本 |
| GroupAction | Provider 部分/全部撤回、越权退出、NFT 转移 | 只返还该 Provider 体验代币；剩余自有或其他体验余额时不退出，总参与量归零才自动退出；权限与收款跟随对应 NFT |
| GroupAction | 17 组索引；跨社区、跨行动、最后关系退出 | 全量/Count/AtIndex 一致，逐层清理，不提前删除 |
| GroupAction | 逐笔 Round 历史、同轮多次变更、空轮继承 | 验证读取冻结历史，退出状态不复活 |
| GroupAction | 申请版本、平票、前 n + 1 开放 | 按确认后的容量、版本和排名规则开放 |
| GroupAction | 连续批次、NFT 转移续验、无候选/失联 | 无跳跃或重复，不换锁定身份；未完成行动层激励为零 |
| GroupAction | 完整验证后的成员和群激励 | 符合权重与舍入公式 |
| [GroupService](06-service-executor.md) | 全社区聚合、同币/直接父币、非直接关系 | 全部 GroupAction 激励作分母；源行动查询自行处理验证条件；非法代币关系拒绝 |
| GroupService | 验证者比例、owner 治理上限、100% 二次分配 | 验证者按工作量直接分配；owner 超额销毁；分配不超预算、不下溢 |

各模块“待确认”项仍需先确定预期；不得把旧用例运行成功当成新规格无冲突。
