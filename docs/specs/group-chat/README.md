# Group Chat 规格

**迁移原则：保留旧群聊功能和业务行为，只删除地址主体平行路径与群内 NFT 委托、适配 MemberNFT/Core/Action 接口。** 不把已有支付、管理、分页或失效处理重新列为待设计。

## 已核对来源

- 旧 `LOVE20TKM/group-chat`。
- 旧 `LOVE20TKM/group/src/GroupDelegate.sol` 仅用于确认被删除的委托行为，不再迁移。
- 这些是本地干净工作区的源码基线，不等同于链上部署证明。迁移前仍须核对实际部署来源。

| 文档 | 职责 |
| --- | --- |
| [00-overview.md](00-overview.md) | 迁移范围、身份和数据对象 |
| [01-lifecycle.md](01-lifecycle.md) | 激活、管理和权限边界 |
| [02-rules.md](02-rules.md) | 规则槽位与身份接口 |
| [03-posting.md](03-posting.md) | 发言校验和插件失败 |
| [04-query.md](04-query.md) | Round、消息与分页 |
| [05-chat-types.md](05-chat-types.md) | 五类资格、黑名单和成员管理 |
| [06-manager.md](06-manager.md) | Manager 付款、持有和管理边界 |
| [07-events-errors.md](07-events-errors.md) | 事件、错误与安全 |
| [08-testing.md](08-testing.md) | 迁移等价性与删除项验收 |

旧 ABI 的身份参数按本目录映射；托管群命名按 [Manager](06-manager.md) 的 v2 模板，构造期静态校验按 dev-standards §5.7 下沉到部署脚本；其余功能和行为保留。需要的是接口对齐与回归，不是新增恢复机制或重设计业务。已确认的 BSC 时间和行动依赖适配不撤销，差异见 [迁移清单](../CHANGES-group-chat.md)。

[组织约束](../../../CONTEXT.md)

接口以 [`group-chat/src/interfaces/`](https://github.com/LOVE20BSC/group-chat/tree/main/src/interfaces) 为准，是 Group Chat ABI 的唯一来源；本仓库不再保留副本。
