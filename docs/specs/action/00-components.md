# Action 组件与依赖

## 组件

| 组件 | 职责 |
| --- | --- |
| ActionTarget | 行动类型的统一 Proposal Target，负责映射、回调和参与登记 |
| LP Executor | LP 时间权重和内部激励分配 |
| 链群行动 Executor | 链群归属、参与历史、候选与验证 |
| 链群服务 Executor | 聚合已验证行动并分配服务激励 |

## Core 依赖

| 依赖 | 用途 |
| --- | --- |
| MemberNFT | 身份与当前控制者 |
| Stake | 质押与治理票查询 |
| Submit | Proposal 创建、推举及回调 |
| Vote | 轮次投票与回调 |
| Mint | Proposal 激励铸造 |
| Phase | 当前时间片和业务轮次映射 |

Core 只传递 Proposal 上下文与不透明 KV，不解释候选、链群、LP、托管或服务分配。上述业务由对应 Executor 处理；ActionTarget 不持有参与资产。主体与术语见 [组织上下文](../../../CONTEXT.md)。
