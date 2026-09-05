# 组件和依赖

本文档定义 Action 扩展层的组件结构和依赖关系。

---

## 组件列表

`action` 由以下组件组成：

- `ActionTarget`：所有社群行动 Proposal 的统一 Target
- LP 行动执行合约
- Group Action 执行合约
- 服务行动执行合约

---

## 依赖关系

### Core 依赖

组件依赖 `core` 的以下接口：

- `MemberNFT`：成员身份查询
- `Stake`：质押状态查询
- `Submit`：Proposal 创建
- `Vote`：投票和回调
- `Mint`：激励铸造
- `Phase`：当前 Phase 查询

### 职责边界

- **Core**：只传递 Proposal 上下文和不透明 KV，不解析业务字段，原样转发给 Target
- **Action**：解释候选人、群组、LP、资产托管和服务分配等业务逻辑
