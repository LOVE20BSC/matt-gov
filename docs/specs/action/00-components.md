# Action 组件与依赖

## 组件

| 组件 | 职责 |
| --- | --- |
| ActionTarget | 行动类型的统一 Proposal Target，负责映射、回调和加入状态 |
| LP Executor | LP 时间权重和内部激励分配 |
| GroupAction Executor | 链群归属、参与历史、验证者申请与验证 |
| GroupService Executor | 聚合 GroupAction 激励并分配服务激励 |

## Core 依赖

| 依赖 | 用途 |
| --- | --- |
| MemberNFT | 身份与当前控制者 |
| Stake | 质押与治理权查询 |
| Submit | Proposal 创建、推举及回调 |
| Vote | 轮次投票与回调 |
| Mint | Proposal 激励铸造 |
| Phase | 当前阶段和业务轮次映射 |

`GroupActionStorage` / `GroupServiceStorage` 是纯声明的布局库：只定义 `Layout`、常量与槽位切分，不承载业务逻辑、不参与链接部署；边界与例外见 [GroupAction Executor 的部署体积与拆分](05-group-action-executor.md#部署体积与拆分)。

Core 向 Target 传递提案上下文和本次回调的数据。ActionTarget 查找并调用 Executor，验证者申请、链群、LP、托管和服务分配由各 Executor 处理。主体与术语见 [组织上下文](../../../CONTEXT.md)。

加入态与「成员 → 行动」跨类型索引的唯一所有者是 ActionTarget，Executor 不得自建「是否加入」副本。与行动类型无关的参与判定走 ActionTarget，某一行动类型的专属关系（如链群归属）走该 Executor。
