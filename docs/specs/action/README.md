# Action 规格

Action 实现社群行动 Proposal 类型，包括 LP、GroupAction 和 GroupService。按编号阅读；标为“待确认”的规则尚不能作为实现定案。

| 文档 | 职责 |
| --- | --- |
| [00-components.md](00-components.md) | 组件、依赖和职责边界 |
| [01-action-target.md](01-action-target.md) | 回调转发、加入/退出和 forceExit |
| [02-phase-model.md](02-phase-model.md) | 阶段、Round 和服务验证复用 |
| [03-participation.md](03-participation.md) | 自有资产、体验资产和撤回 |
| [04-lp-executor.md](04-lp-executor.md) | LP 时间权重和激励上限 |
| [05-group-action-executor.md](05-group-action-executor.md) | GroupAction 索引、历史、候选和验证 |
| [06-service-executor.md](06-service-executor.md) | 服务聚合与二次分配 |
| [07-minting.md](07-minting.md) | 铸造链路、事件和错误 |
| [08-testing.md](08-testing.md) | 验收 |

建议实现顺序：ActionTarget、LP、GroupAction、GroupService。Core 使用 `proposalId`，Executor 使用 `actionId` 业务别名，二者数值相同。

[组织约束](../../../CONTEXT.md) · [迁移差异](../CHANGES-action.md)
