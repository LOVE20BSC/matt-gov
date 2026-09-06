# BSC 规格入口

当前规范是以下拆分规格和兼容性规格。阅读顺序：范围与依赖、相关模块、验收；不以历史票据代替当前规则。

| 范围 | 入口 | 验收 |
| --- | --- | --- |
| Core 治理与发射 | [core](core/README.md) | [Core 验收](core/08-testing.md) |
| Action 行动扩展 | [action](action/README.md) | [Action 验收](action/08-testing.md) |
| Group Chat 群聊 | [group-chat](group-chat/README.md) | [群聊验收](group-chat/08-testing.md) |
| 外部依赖 | [compatibility](compatibility.md) | 同文件 |

## 使用边界

- [概览](overview.md) 仅解释职责和流程；具体规则以模块规格为准。
- [CONTEXT](../../CONTEXT.md) 定义共享术语，[组织验收](../acceptance.md) 定义跨仓库门槛。模块内“待确认”项表示已有冲突或缺口，不能视为冻结结论。
- [撰写指南](../spec-writing-guide.md) 约束表达，[文档结构](../specification-structure.md) 规定迁移位置，[审查指南](../review-guide.md) 规定核查方法。
- `core/`、`action/`、`group-chat/` 迁移时原样移入各仓库 `docs/specs/`，不保留重复正文。

历史差异见 [CHANGES-core](CHANGES-core.md)、[CHANGES-action](CHANGES-action.md)、[CHANGES-group-chat](CHANGES-group-chat.md)；更早讨论见 [迁移地图](../../.scratch/bsc-protocol-migration/map.md)。历史来源尚未逐条核验，不能凭“沿用旧版”视为规格完整。
