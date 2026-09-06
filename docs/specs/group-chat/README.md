# Group Chat 规格

**迁移原则：保留旧群聊功能和业务行为，只删除地址主体平行路径、适配 MemberNFT/Core/Action 接口，并将 NFT 委托限制在 group-chat 内。** 不把已有支付、管理、分页或失效处理重新列为待设计。

## 已核对来源

- 旧 group-chat：`ce21ea8f29b3750421876ae649fa7d919fe42cff`。
- 旧 group 的 NFT 委托：`2eb6d6c8d48bf6dd382efa5887124a2c3c722fd9`，`src/GroupDelegate.sol` 与对应接口。
- 这些是本地干净工作区的源码基线，不等同于链上部署证明。迁移前仍须核对实际部署来源。

| 文档 | 职责 |
| --- | --- |
| [00-overview.md](00-overview.md) | 迁移范围、身份和数据对象 |
| [01-lifecycle.md](01-lifecycle.md) | 激活、管理和群聊内 NFT 委托 |
| [02-rules.md](02-rules.md) | 规则槽位与身份接口 |
| [03-posting.md](03-posting.md) | 发言校验和插件失败 |
| [04-query.md](04-query.md) | Round、消息与分页 |
| [05-chat-types.md](05-chat-types.md) | 五类资格、黑名单和成员管理 |
| [06-manager.md](06-manager.md) | Manager 付款、持有和管理边界 |
| [07-events-errors.md](07-events-errors.md) | 事件、错误与安全 |
| [08-testing.md](08-testing.md) | 迁移等价性与删除项验收 |

旧 ABI 的身份参数按本目录映射，其他功能和行为保留；需要的是接口对齐与回归，不是新增恢复机制或重设计业务。已确认的 BSC 时间和行动依赖适配不撤销，差异见 [迁移清单](../CHANGES-group-chat.md)。

[组织约束](../../../CONTEXT.md)
