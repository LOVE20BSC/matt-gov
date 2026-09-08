# Action 验收

行为以各模块为准，跨仓库证据见 [组织验收](../../acceptance.md)。本表是待实现的验收要求，不表示测试已运行。

| 模块 | 必测场景 | 预期 |
| --- | --- | --- |
| [ActionTarget](01-action-target.md) | 三类回调、映射、重复创建、非授权调用、Round 查询 | 只用关联 Executor，回调失败全回滚，列表与本轮投票一致 |
| ActionTarget | forceExit 后正常退出 | forceExit 只清 Target 加入状态；随后 Executor 仍可返还资产、清理群归属，调用 ActionTarget.exit 幂等成功 |
| [LP](04-lp-executor.md) | 时间加权、治理上限、部分撤回、完整退出 | 按 V2 聚合扣减结算，结算不超预算，零分母不 panic |
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
