# BSC 规格文档说明

权威规范以 `core/`、`action/`、`group-chat/` 下的拆分文件为准；同级旧版整篇文件仅作迁移历史汇总，不据此实现或继续修改。

本目录包含 BSC 版协议的规格文档。

---

## 文档结构

### Core 规格（已拆分）

Core 规格已按合约拆分到 `core/` 目录：

- **[core/README.md](core/README.md)** - Core 规格导航索引
- **[core/00-protocol-model.md](core/00-protocol-model.md)** - 协议模型与初始化参数
- **[core/01-common-rules.md](core/01-common-rules.md)** - 参与主体与通用约束
- **[core/02-member-nft.md](core/02-member-nft.md)** - MemberNFT 规格
- **[core/03-phase.md](core/03-phase.md)** - Phase 与 Round
- **[core/04-stake.md](core/04-stake.md)** - Stake 规格
- **[core/05-submit-vote.md](core/05-submit-vote.md)** - Submit 与 Vote 规格
- **[core/06-mint.md](core/06-mint.md)** - Mint 规格
- **[core/07-launch.md](core/07-launch.md)** - Launch 与 TokenFactory 规格
- **[core/09-testing.md](core/09-testing.md)** - 事件、错误和验收

### Action 规格（已拆分）

Action 规格已按功能模块拆分到 `action/` 目录：

- **[action/README.md](action/README.md)** - Action 规格导航索引
- **[action/00-components.md](action/00-components.md)** - 组件和依赖关系
- **[action/01-action-target.md](action/01-action-target.md)** - ActionTarget 统一框架
- **[action/02-phase-model.md](action/02-phase-model.md)** - 行动阶段模型
- **[action/03-participation.md](action/03-participation.md)** - 共同参与模型
- **[action/04-lp-executor.md](action/04-lp-executor.md)** - LP 行动执行合约
- **[action/05-group-action-executor.md](action/05-group-action-executor.md)** - Group Action 执行合约
- **[action/06-service-executor.md](action/06-service-executor.md)** - 服务行动执行合约
- **[action/07-minting.md](action/07-minting.md)** - 铸造闭环、事件和错误
- **[action/08-testing.md](action/08-testing.md)** - 验收场景

### Group Chat 规格（已拆分）

Group Chat 规格已按功能模块拆分到 `group-chat/` 目录：

- **[group-chat/README.md](group-chat/README.md)** - Group Chat 规格导航索引
- **[group-chat/00-overview.md](group-chat/00-overview.md)** - 定位、边界、身份和对象
- **[group-chat/01-lifecycle.md](group-chat/01-lifecycle.md)** - 激活、管理操作和委托
- **[group-chat/02-rules.md](group-chat/02-rules.md)** - 规则槽位和标准接口
- **[group-chat/03-posting.md](group-chat/03-posting.md)** - 发言机制和插件处理
- **[group-chat/04-query.md](group-chat/04-query.md)** - Round 和查询接口
- **[group-chat/05-chat-types.md](group-chat/05-chat-types.md)** - 五类 Chat 类型和资格规则
- **[group-chat/06-manager.md](group-chat/06-manager.md)** - Manager 和群组 Chat
- **[group-chat/07-events-errors.md](group-chat/07-events-errors.md)** - 事件、错误和安全性
- **[group-chat/08-testing.md](group-chat/08-testing.md)** - 验收场景

### 变更清单

- **[CHANGES-core.md](CHANGES-core.md)** - Core 迁移变更清单
- **[CHANGES-action.md](CHANGES-action.md)** - Action 迁移变更清单
- **[CHANGES-group-chat.md](CHANGES-group-chat.md)** - Group Chat 迁移变更清单

### 其他文档

- **[overview.md](overview.md)** - 协议概览
- **[compatibility.md](compatibility.md)** - 兼容性说明

---

## 使用建议

### 首次了解协议

1. 阅读 **[overview.md](overview.md)** 了解协议整体设计
2. 阅读 **[core/README.md](core/README.md)** 了解 Core 治理层结构
3. 按需阅读各模块规格

### 实现时查阅

**Core 合约实现**：
1. 查看 **[CHANGES-core.md](CHANGES-core.md)** 了解变更
2. 按合约定位到 `core/` 下对应拆分文档
3. 参考文档中引用的旧代码位置

**Action 和 Group Chat 实现**：
1. 查看对应的 CHANGES 文档
2. 按功能模块定位到 `action/` 或 `group-chat/` 下对应拆分文档
3. 参考文档中引用的旧代码位置

### 验收时核对

1. 使用 CHANGES 文档的"验收边界"
2. 对照各模块的 testing.md 验收场景
   - Core: `core/09-testing.md`
   - Action: `action/08-testing.md`
   - Group Chat: `group-chat/08-testing.md`
3. 确保所有场景覆盖

---

## 文档统计

### Core（拆分前后对比）

- **拆分前**：1 个文件，1028 行
- **拆分后**：10 个文件（1 个索引 + 9 个模块），1425 行总计

### Action（拆分前后对比）

- **拆分前**：1 个文件，599 行
- **拆分后**：10 个文件（1 个索引 + 9 个模块），平均 60-110 行/文件

### Group Chat（拆分前后对比）

- **拆分前**：1 个文件，455 行
- **拆分后**：10 个文件（1 个索引 + 9 个模块），平均 25-100 行/文件

---

## 拆分理由

### 为什么拆分？

1. **单文件难以维护**：大文件包含多个合约或模块，修改单个部分需要滚动整个文件
2. **审核负担重**：人工审核时难以快速定位变更范围
3. **职责不清晰**：通用规则、合约规格、验收场景混在一起
4. **引用不便**：无法精确定位到某个合约或功能的某个小节

### 拆分原则

- 按合约或功能模块边界拆分
- 每个文件控制在 25-250 行之间
- 保持逻辑完整性，避免频繁跨文件引用
- 使用 README.md 作为导航索引

---

## 术语统一

在所有文档中：
- **Group Action** 而非"链群行动"
- **MemberNFT** 而非 Member NFT
- **Phase** 和 **Round** 有明确区分（Phase 是底层时间片，Round 是上层业务解释）

---

## 下一步

待代码库创建后：
1. 将拆分后的目录（`core/`、`action/`、`group-chat/`）复制到各代码库的 `docs/specs/`
2. 添加迁移记录：目标提交、迁移日期
