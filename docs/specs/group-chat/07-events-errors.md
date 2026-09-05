# 事件、错误和安全性

本文档定义 Group Chat 的事件、错误代码和安全性约束。

---

## 1. 事件

至少发出：
- `Activate`、`SetPostingAllowed`
- 四个规则槽位的设置事件
- `PostMessage`、`MentionSenderId`、`MentionAll`、`FailAfterPostPlugin`
- Group Chat Delegate 设置/撤销、成员集合变化、管理员变化
- Manager 创建/激活实例事件

配置变化事件包含 `groupId`、新旧合约地址、操作 `memberId` 和实际调用地址；消息事件包含 `groupId`、`senderId`、`senderAddress`、`round` 和 `messageId`。地址字段仅用于审计，不作为业务主体或地址维度索引。

---

## 2. 错误

至少拒绝：不存在的群或 sender、重复激活、非 owner/Delegate 管理、非 sender owner 发言、Chat 未激活、发言关闭、空正文、正文超长、提及数量超限或重复、无效引用、非管理员 `mentionAll`、规则地址无代码、scope/ban 拒绝和重入。

---

## 3. 安全性

- 消息只增不改，配置和消息写入使用重入保护
- 规则源、插件和 Manager 不能越权写入 Chat 核心存储
- 协议没有升级管理员和隐含后门
