# 规则槽位

本文档定义 Chat 的四个外部规则槽位及其接口。

---

## 1. 规则槽位概述

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

每个 Chat 有四个外部规则槽位：
- `scopeSource`：发言资格
- `banSource`：黑名单拒绝
- `beforePostPlugin`：写消息前的业务校验
- `afterPostPlugin`：写消息后的通知或索引扩展

地址为 `0` 表示未挂载：`scopeSource = 0` 代表默认开放，`banSource = 0` 代表没有黑名单。

---

## 2. 调用顺序

核心身份和内容校验 → owner/delegate 的资格绕过判断 → `scopeSource(groupId, senderId)` → `banSource(groupId, senderId)` → `beforePostPlugin` → 写入消息 → 发出消息/提及事件 → `afterPostPlugin`

---

## 3. 资格绕过

当 `senderId == groupId`，或 `senderId` 是该群当前有效的 `delegateId` 时，可以跳过 `scopeSource` 和 `banSource`，但仍必须通过群存在、激活、发言开关、身份存在和 `msg.sender` 持有 `senderId` 等核心校验。

**mentionAll 权限**（详见第 4 节）：
- **允许 mentionAll**：owner（`senderId == groupId`）、有效 delegate、有效 admin
- **资格绕过**：仅 owner 和 delegate（admin 可以 mentionAll，但仍需通过 scopeSource 和 banSource 检查）
- **设计理由**：owner 和 delegate 代表群本身的管理身份，admin 是被授权的成员身份，仍需满足基本资格和黑名单规则

---

## 4. 标准接口

```solidity
interface IPostScopeSource {
    function canPost(uint256 groupId, uint256 senderId) external view returns (bool);
}

interface IPostBanSource {
    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool);
}

interface IBeforePostPlugin {
    function beforePost(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external;
}

interface IAfterPostPlugin {
    function afterPost(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId,
        uint256 messageId,
        uint256 blockNumber,
        uint256 timestamp
    ) external;
}
```
