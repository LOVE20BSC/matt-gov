# LOVE20BSC 规格文档结构

本文件规定文档归属和迁移方式；具体写法见 [撰写指南](spec-writing-guide.md)，审查方法见 [审查指南](review-guide.md)。

## 单一来源

| 文档 | 职责 |
| --- | --- |
| 当前模块规格 | 本模块的行为、接口、公式、事件、错误和验收 |
| [CONTEXT](../CONTEXT.md) | 跨仓库术语与领域关系 |
| [仓库清单](repositories.md) | 仓库边界和依赖 |
| [组织验收](acceptance.md) | 跨仓库场景、发布门槛和证据 |
| `CHANGES-*`、`.scratch/` | 迁移差异与决策历史，不是当前实现规范 |

当前规格与组织约束必须一致。发现冲突应标注并确认，不能由实现者自行选择；理解 BSC 行为不应依赖阅读旧仓库代码。

## 存放与迁移

| 仓库 | 创建前 | 创建后 |
| --- | --- | --- |
| core | `matt-gov/docs/specs/core/` | `core/docs/specs/` |
| action | `matt-gov/docs/specs/action/` | `action/docs/specs/` |
| group-chat | `matt-gov/docs/specs/group-chat/` | `group-chat/docs/specs/` |
| compatibility | `matt-gov/docs/specs/compatibility.md` | `compatibility/SPEC.md` |

前三组保留拆分文件、编号和目录内 `README.md`，不合并为单一 `SPEC.md`。`compatibility` 目前只有一份测试规格，迁移时仍保持单文件。

迁移步骤：

1. 将对应目录或文件移入目标仓库，保持内部结构；调整跨仓库链接并验证可达。
2. 在本仓库记录迁移日期、目标路径和目标提交；删除已迁移正文，只保留记录，历史由 Git 保存。
3. 目标仓库根 `README.md` 链接到规格入口。此后只在目标仓库修改规格。

## 范围

- `core`：治理、MemberNFT、Phase、基础子币发射；首个代币由 `Launch.init` 创建，见 [Launch](specs/core/07-launch.md)。
- `action`：ActionTarget、LP、GroupAction 和 GroupService；共享边界不要求各 Executor 具有相同业务接口。
- `group-chat`：群聊和仅限群聊内部的 Group Chat Delegate。
- `compatibility`：外部 WBNB/PancakeSwap 接口与行为验证；无生产合约，不是业务运行时依赖。
- `launch` 仓库本阶段不创建；外围、部署、集成、前端、批量转账和用户文档仓库使用自身 README、部署或测试说明。

## 变更与验收

代码行为与对应规格在同一提交中更新。跨仓库接口变更同时更新所有受影响规格，在 `repositories.md` 记录影响，并在 PR 中列出各仓库提交；相关集成测试通过后方可验收。

迁移前在上表的本仓库位置维护规格；迁移后在目标位置维护。历史票据可保留旧名称，但不得与当前规范并列为实现依据。
