# LOVE20BSC Core 规格

状态：BSC 版实现前冻结的独立规格。

Core 治理层包含 9 个合约和通用规则。本文档定义 BSC Core 的协议行为。**保留旧逻辑的部分直接引用旧代码位置**，避免重复描述。详细变更清单见 [`../CHANGES-core.md`](../CHANGES-core.md)。

---

## 快速导航

| 文档 | 内容 | 预估行数 |
|------|------|----------|
| [00-protocol-model.md](00-protocol-model.md) | 协议模型、初始化参数 | ~150 行 |
| [01-common-rules.md](01-common-rules.md) | 参与主体、通用约束 | ~100 行 |
| [02-member-nft.md](02-member-nft.md) | MemberNFT 规格 | ~150 行 |
| [03-phase.md](03-phase.md) | Phase 与 Round | ~200 行 |
| [04-stake.md](04-stake.md) | Stake 规格 | ~250 行 |
| [05-submit-vote.md](05-submit-vote.md) | Submit + Vote（Proposal 流程）| ~150 行 |
| [06-mint.md](06-mint.md) | Mint 规格 | ~200 行 |
| [07-launch.md](07-launch.md) | Launch + TokenFactory | ~200 行 |
| [09-testing.md](09-testing.md) | 事件、错误、验收 | ~150 行 |

---

## 合约职责

**核心治理层包含**：

- `MemberNFT`：统一参与身份（合并旧 LOVE20Group）
- `Stake`：治理质押、加速质押、LP 份额和手续费结算
- `Submit`：Proposal 创建和推举（旧版 Action 重命名为 Proposal）
- `Vote`：治理投票及 Proposal Target 回调
- `Mint`：轮次激励准备、治理激励和 Proposal 激励铸造
- `Phase`：无语义的动态时间片时间线（全新设计）
- `LOVE20Token`、`TokenFactory`：代币树和代币实例创建
- `Launch`：基础子币发射次数账本、次数融合、次数消耗和首批代币分发

核心不解释任何具体 Proposal 扩展的业务字段。扩展只通过 Proposal Target 的通用接口接入。

---

## 实现顺序建议

1. **基础层**：Phase, MemberNFT
2. **质押层**：Stake
3. **治理层**：Submit, Vote
4. **铸造层**：Mint
5. **发射层**：Launch, TokenFactory（`Launch.init` 同时完成首个代币部署）

---

## 依赖关系

```
Phase (独立)
  ↓
MemberNFT → Stake → Submit → Vote → Mint → Launch
                      ↓                ↓
                    Phase        TokenFactory
```

---

## 阅读建议

- **首次阅读**：按文档编号顺序（00 → 07），最后阅读 `09-testing.md`
- **实现查阅**：根据合约名称直接定位对应文档
- **验收核对**：重点查看 `09-testing.md` 的验收场景
