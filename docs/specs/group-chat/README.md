# LOVE20BSC Group Chat 规格

状态：BSC 版实现前冻结的独立规格。

Group Chat 定义群聊实例、群聊身份、Group Chat Delegate、发言规则、消息索引、分页查询和可插拔的资格/黑名单模块。**保留旧逻辑的部分直接引用旧代码位置**，避免重复描述。详细变更清单见 [`../CHANGES-group-chat.md`](../CHANGES-group-chat.md)。

---

## 快速导航

| 文档 | 内容 | 预估行数 |
|------|------|----------|
| [00-overview.md](00-overview.md) | 定位、边界、身份和对象 | ~70 行 |
| [01-lifecycle.md](01-lifecycle.md) | 激活、管理操作和委托 | ~50 行 |
| [02-rules.md](02-rules.md) | 规则槽位和标准接口 | ~60 行 |
| [03-posting.md](03-posting.md) | 发言机制和插件处理 | ~40 行 |
| [04-query.md](04-query.md) | Round 和查询接口 | ~40 行 |
| [05-chat-types.md](05-chat-types.md) | 五类 Chat 类型和资格规则 | ~100 行 |
| [06-manager.md](06-manager.md) | Manager 和群组 Chat | ~60 行 |
| [07-events-errors.md](07-events-errors.md) | 事件、错误和安全性 | ~25 行 |
| [08-testing.md](08-testing.md) | 验收场景 | ~40 行 |

---

## 核心原则

- **1 个 MemberNFT = 1 个 Chat**：`groupId` 是群聊身份 NFT 的 `memberId`
- **发言身份是 `senderId`**：地址只用于校验该 NFT 的当前控制者
- **消息只新增，不编辑、不删除**
- **Group Chat Delegate 只在本代码库内生效**，不产生任何跨代码库权限

---

## 阅读建议

- **首次阅读**：按文档编号顺序（00 → 08）
- **实现查阅**：根据功能模块直接定位对应文档
- **验收核对**：重点查看 `08-testing.md` 的验收场景

---

## 术语说明

- **Group Chat**：群聊系统
- **groupId**：群聊身份 NFT 的 `memberId`
- **senderId**：发言者的 `memberId`
- **Group Chat Delegate**：群聊委托机制，权限限定在群聊管理范围内
- **Manager**：持有 MemberNFT 并管理特定类型 Chat 的合约（代币社区/治理/行动 Chat）
- **群组 Chat**：由群组 owner 直接管理的 Chat（非 Manager 类型）
