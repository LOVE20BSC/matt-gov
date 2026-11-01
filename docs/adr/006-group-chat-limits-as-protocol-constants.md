# ADR-006: 消息上限改为协议常量

## 状态

已接受 (2026-11-02)

## 背景

旧公测 profile 把单条消息的正文长度与提及条数作为构造参数传入 `GroupChat`：

- `MAX_CONTENT_LENGTH`（默认 4096 字节）与 `MAX_MENTIONED_SENDER_IDS`（默认 32）由 `group-chat.params` 提供；
- 部署脚本校验两项非零，并在部署后断言链上取值等于配置值；
- 迁移规格曾明确「保留构造参数而非新增硬编码」（见 `group-chat/03-posting.md` 上一版）。

迁移到本仓库后，这两个上限的性质已经变化。消息正文随 `MessagePosted` 一起进日志（[03-posting](../specs/group-chat/03-posting.md)：事件携带 `content`，代价约 8 gas/byte，「用 gas 换可重建」），提及条数则线性决定同一条消息后面跟多少个 `SenderMentioned`。也就是说，**单条消息的日志体量与 gas 上界直接由这两个值决定**，而规格里给出的 +33k gas 最坏值正是以 4096 字节为前提算出来的。

可配置上限让这个前提失效：

1. **估算不再可证**。同一个字节码，换一份 `params` 就能把单条消息的日志推高数倍，而部署阶段没有任何成本信号或上限约束——`0 < x` 之外没有别的校验。
2. **对账是同义反复**。旧设计的部署期断言是「链上值 == 配置值」，配置本身可以是任意值，因此它只保证「部署与配置一致」，不保证「上限是协议接受的上限」。
3. **取值属于协议，不属于部署**。正文上限与提及上限决定的是索引器与消费者的资源边界（`SenderMentioned` 条数、`mentionedSenderCount` 恒等式），不是某条链或某个部署的运营参数。

## 决策

**`MAX_CONTENT_LENGTH = 4096`、`MAX_MENTIONED_SENDER_IDS = 32` 改为 `public constant`，`GroupChat` 构造函数收敛为 `(groupAdminAddress, phaseAddress)`。**

- 删除构造参数与 `DeployConfig` 中对应两项，`GROUP_CHAT_MAX_CONTENT_LENGTH` / `GROUP_CHAT_MAX_MENTIONED_SENDER_IDS` 从 `group-chat.params` 移除。
- `DeployGroupChat.s.sol` 不再有可校验对象：`_validateConfig` 的两条零值 `require` 与 `_validateDeployment` 的两条「链上值 == 配置值」`require` 一并删除。`21_check.sh` 改为只复核链上取值非零（零值只可能来自错误构建），`31_verify.sh` 的构造参数编码由四参改为 `(address,address)`。`11_deploy.sh` 只少掉两行 `unset`——它原本按 `GROUP_CHAT_*` 逐个清除继承值，现在由 `params_unset_all` 从参数文件的键集合派生。
- 精确取值由 `GroupChatLifecycle.t.sol` 的 `assertEq` 锁定，并由开源验证比对源码；两者都是链上不可改的事实。
- 错误载荷不变：`ContentTooLong(length, maxLength)` / `TooManyMentionedSenderIds(length, maxLength)` 仍回实际生效的上限，调用方无需读 getter 也能拿到边界。

## 后果

### 正面影响

1. **gas 估算重新可证**：`MessagePosted` 的最坏日志体量由字节码固定，规格里的 +33k gas 结论不再依赖部署配置。
2. **部署面收窄**：`group-chat.params` 少两个键，`DeployConfig` 少两个字段，`DeployGroupChat.s.sol` 少四条 `require`，`31_verify.sh` 少两个构造参数。
3. **不可被运营改小**：上限不再存在「某次部署把正文从 4096 降到 256、索引器按部署差异化配置」的分叉。

### 负面影响

1. **换 profile 需重新部署**：想调整正文或提及上限只能改源码并重新部署 `GroupChat`，不能靠 `params`。本仓库无生产部署，当前只影响 `anvil31337_dev`。
2. **破坏性 ABI 变更**：`GroupChat` 构造签名由 `(address,address,uint256,uint256)` 改为 `(address,address)`，`DeployGroupChat.DeployConfig` 少两个字段；同批更新的部署脚本、初始化夹具与验证步骤需一起改。
3. **21_check 的复核强度下降**：从「等于配置值」退到「非零」，链上取值是否正确由测试与源码验证承担。这是有意的取舍——配置值本身不再是有意义的期望值。

## 相关文档

- [群聊发帖](../specs/group-chat/03-posting.md)
- [群聊测试](../specs/group-chat/08-testing.md)
- [群聊迁移差异](../specs/CHANGES-group-chat.md)
- [事件规范](../event-standards.md)
