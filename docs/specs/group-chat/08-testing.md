# 验收场景

本文档定义 Group Chat 系统的验收测试场景。

---

## 1. 核心机制

至少覆盖：
- 1 个 MemberNFT = 1 个 Chat
- 群 NFT 转移后的 owner 连续性和历史不回写
- 激活一次性、默认开放发言、规则槽位更新和无代码地址拒绝

---

## 2. Group Chat Delegate

至少覆盖：
- 设置、撤销、作用域、权限限制和不能冒充 sender

---

## 3. 身份约束

至少覆盖：
- 不存在默认 MemberNFT 映射
- 不存在地址主体发言入口
- 不存在地址黑名单
- 不存在地址黑名单投票或其他地址主体接口

---

## 4. 发言机制

至少覆盖：
- 普通发言、owner/Delegate 资格绕过、scope/ban 拒绝
- before 插件回滚、after 插件失败但消息保留
- 正文、提及、mention-all、引用和 1-based 消息 ID 边界

---

## 5. 查询

至少覆盖：
- 按 Round/sender/mention/mention-all 查询
- 空 Round、反向分页和越界返回

---

## 6. 群管理

至少覆盖：
- 成员/管理员批量操作、当前 owner 实时授权和 MemberNFT 不存在回滚

---

## 7. 类型和资格

至少覆盖：
- 四类 typed Manager 的资格、黑名单和不可重配边界
- 群组 owner 管理型 Chat 的标准资格源与可重配边界
- 群组归属跨社区和跨行动查询
- 所有业务状态只按 `memberId` 记录
