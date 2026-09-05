# LOVE20BSC Action 规格

状态：BSC 版实现前冻结的独立规格。

Action 扩展层定义社群行动 Proposal 类型。**保留旧逻辑的部分直接引用旧代码位置**，避免重复描述。详细变更清单见 [`../CHANGES-action.md`](../CHANGES-action.md)。

---

## 快速导航

| 文档 | 内容 | 预估行数 |
|------|------|----------|
| [00-components.md](00-components.md) | 组件和依赖 | ~20 行 |
| [01-action-target.md](01-action-target.md) | ActionTarget 统一框架 | ~140 行 |
| [02-phase-model.md](02-phase-model.md) | 行动阶段模型 | ~130 行 |
| [03-participation.md](03-participation.md) | 共同参与模型 | ~20 行 |
| [04-lp-executor.md](04-lp-executor.md) | LP 行动执行合约 | ~60 行 |
| [05-group-action-executor.md](05-group-action-executor.md) | Group Action 执行合约 | ~80 行 |
| [06-service-executor.md](06-service-executor.md) | 服务行动执行合约 | ~110 行 |
| [07-minting.md](07-minting.md) | 铸造闭环、事件和错误 | ~50 行 |
| [08-testing.md](08-testing.md) | 验收场景 | ~30 行 |
| [06-service-executor.md](06-service-executor.md) | 服务行动执行合约 | ~110 行 |
| [07-minting.md](07-minting.md) | 铸造闭环、事件和错误 | ~50 行 |
| [08-testing.md](08-testing.md) | 验收场景 | ~30 行 |

---

## 合约职责

**Action 扩展层包含**：

- `ActionTarget`：所有社群行动 Proposal 的统一 Target
- LP 行动执行合约
- Group Action 执行合约
- 服务行动执行合约

组件依赖 `core` 的 `MemberNFT`、`Stake`、`Submit`、`Vote`、`Mint` 和 `Phase` 接口。核心只传递 Proposal 上下文和不透明 KV（Core 不解析业务字段，原样转发给 Target）；候选人、群组、LP、资产托管和服务分配由本代码库解释。

---

## 实现顺序建议

1. **框架层**：ActionTarget（统一框架和阶段模型）
2. **LP 行动**：LP Executor（3 阶段模型）
3. **Group Action**：Group Action Executor（4 阶段模型）
4. **服务行动**：Service Executor（基于 Group Action 验证结果）

---

## 依赖关系

```
Core (Phase, Vote, Mint)
  ↓
ActionTarget (统一框架)
  ↓
├─ LP Executor (3 阶段)
├─ Group Action Executor (4 阶段)
└─ Service Executor (复用 Group Action 验证)
```

---

## 阅读建议

- **首次阅读**：按文档编号顺序（00 → 08）
- **实现查阅**：根据合约名称直接定位对应文档
- **验收核对**：重点查看 `08-testing.md` 的验收场景

---

## 术语说明

- **行动（Action）**：对应一个 Core Proposal，由 ActionTarget 管理
- **proposalId**：Core 层使用的 Proposal 唯一标识
- **actionId**：Executor 业务逻辑中使用的行动标识，数值上 `actionId = proposalId`
- **Group Action**：链群行动（统一术语）
