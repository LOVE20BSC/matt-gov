# LOVE20BSC 仓库清单

组织级清单只记录仓库边界、主要依赖和当前状态；具体实现说明与测试命令放在对应仓库的 `README.md`。

| 仓库 | 定位 | 主要依赖 | 当前状态 |
| --- | --- | --- | --- |
| `matt-gov` | 组织治理、迁移决策和验收记录 | 无 | 活跃 |
| `core` | 核心治理、`MemberNFT`、`LOVE20Phase`、发射基础设施 | 无 | 规划中 |
| `launch` | 公平发射后的初始分配机制（含父币申购方案） | `core`、外部 PancakeSwap | 规划中 |
| `action` | `ActionTarget` 及社群行动类型内部业务 | `core` | 规划中 |
| `group-chat` | 群聊业务和 Chat 专属 delegate | `core` | 规划中 |
| `interface-test` | BSC 前端开发、集成和验收 | `core`、`launch`、`action`、`group-chat` | 规划中；日常修改入口 |
| `interface` | BSC 前端正式发布 | 验收后的 `interface-test` | 规划中；只接受人工同步 |
| `periphery` | 跨仓库调用与外围适配 | `core`、`launch`、`action` | 规划中 |
| `script` | 部署、地址和发布脚本 | 各可部署业务仓库 | 规划中 |
| `love20-anvil` | 本地区块链集成测试编排 | 各可部署业务仓库 | 规划中 |
| `docs` | 面向用户和开发者的协议文档 | 各业务仓库 | 规划中 |
| `batch-transfer` | 独立批量转账工具 | 无 | 规划中 |

`extension`、`extension-group`、`extension-lp` 的业务迁入 `action`；`burn`、未部署的 `chat` 和外部 `v2-periphery` 不在本组织清单中。
