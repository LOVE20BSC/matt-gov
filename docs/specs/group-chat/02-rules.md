# 规则槽位

| 槽位 | 职责 | 零地址语义 |
| --- | --- | --- |
| `scopeSource` | 发言资格 | 默认开放 |
| `banSource` | 黑名单拒绝 | 无黑名单 |
| `beforePostPlugin` | 写入前校验 | 未挂载 |
| `afterPostPlugin` | 写入后通知或索引扩展 | 未挂载 |

## 顺序与例外

```text
核心身份和内容校验 -> owner/delegate 资格绕过判断
-> scopeSource -> banSource -> beforePostPlugin
-> 写入消息 -> 消息/提及事件 -> afterPostPlugin
```

只有 `senderId == groupId` 或 senderId 等于当前有效 delegateId 可跳过 scope/ban；群存在、激活、发言开关、sender 存在及调用者持有 sender 的校验仍必须执行。

owner、有效 delegate、有效 admin 可 `mentionAll`；admin 不因此绕过 scope/ban。插件失败处理见 [发言](03-posting.md#消息与插件)。

## 标准接口

规则槽位接口见 [`IGroupChatRules.sol`](../../../interfaces/group-chat/IGroupChatRules.sol)。
