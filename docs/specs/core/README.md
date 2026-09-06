# Core 规格

Core 定义治理、统一身份、时间线和基础子币发射。按编号阅读；标为“待确认”的规则尚不能作为实现定案。

| 文档 | 职责 |
| --- | --- |
| [00-protocol-model.md](00-protocol-model.md) | 协议模型、组件与初始化参数 |
| [01-common-rules.md](01-common-rules.md) | 主体、编号、精度和安全约束 |
| [02-member-nft.md](02-member-nft.md) | 身份、名称、铸造费用 |
| [03-phase.md](03-phase.md) | 时间片、同步观测和动态校准 |
| [04-stake.md](04-stake.md) | 质押、手续费、解锁与融合 |
| [05-submit-vote.md](05-submit-vote.md) | Proposal、推举、投票与回调 |
| [06-mint.md](06-mint.md) | 激励准备、铸造、销毁 |
| [07-launch.md](07-launch.md) | Launch.init 首币部署、发射次数与 TokenFactory |
| [08-testing.md](08-testing.md) | 事件、错误和验收 |

建议实现顺序：Phase/MemberNFT、Stake、Submit/Vote、Mint、Launch/TokenFactory。实现顺序不等于初始化调用顺序，初始化边界见 Launch。

[组织约束](../../../CONTEXT.md) · [迁移差异](../CHANGES-core.md)
