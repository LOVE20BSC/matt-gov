# 行动阶段模型

本文档定义行动的阶段模型（全新设计）。

---

## 1. 框架层通用阶段

ActionTarget 定义所有行动类型的必经流程：

1. **投票阶段**：社区对行动 Proposal 投票（治理层 Phase p）
2. **加入阶段**：获得票的行动开放加入（Phase p+1）
3. **铸币阶段**：行动完成后铸造激励（Phase p+x，x 由 Executor 决定）

---

## 2. 执行合约阶段模型

各 Executor 从 `core.Phase.currentPhase()` 读取当前 Phase，并根据自己的阶段模型计算各阶段的轮次编号。

### 2.1 LP 行动执行合约（3 阶段）

- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 铸币 Round = currentPhase() - 2

**阶段映射说明**：
- 上述公式定义了**如何从当前 Phase 计算各阶段的轮次编号**
- 例如：Phase 5 时，加入 Round = 4，铸币 Round = 3
- 各阶段的 Round 编号不是 Phase 编号本身

**操作允许条件**：
- 只有当对应阶段的 Round ≥ 1 时，该操作才允许执行
- 如果该阶段的 Round < 1，操作回滚 `RoundNotStarted`

**冷启动期示例**：
- **Phase 1**：
  - 投票 Round = 1 ✅ 允许投票
  - 加入 Round = 0 ❌ 回滚 `RoundNotStarted`
  - 铸币 Round = -1 ❌ 回滚 `RoundNotStarted`
- **Phase 2**：
  - 投票 Round = 2 ✅ 允许投票
  - 加入 Round = 1 ✅ 允许加入（Round 1 ≥ 1）
  - 铸币 Round = 0 ❌ 回滚 `RoundNotStarted`
- **Phase 3 起**：LP 行动进入稳态运行，所有阶段就绪

### 2.2 Group Action 执行合约（4 阶段）

- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

**阶段映射说明**：
- 上述公式定义了**如何从当前 Phase 计算各阶段的轮次编号**
- 例如：Phase 5 时，加入 Round = 4，验证 Round = 3，铸币 Round = 2
- 验证阶段在加入和铸币之间插入

**操作允许条件**：
- 只有当对应阶段的 Round ≥ 1 时，该操作才允许执行
- 如果该阶段的 Round < 1，操作回滚 `RoundNotStarted`

**冷启动期示例**：
- **Phase 1**：
  - 投票 Round = 1 ✅ 允许投票
  - 加入 Round = 0 ❌ 回滚 `RoundNotStarted`
  - 验证 Round = -1 ❌ 回滚 `RoundNotStarted`
  - 铸币 Round = -2 ❌ 回滚 `RoundNotStarted`
- **Phase 2**：
  - 投票 Round = 2 ✅ 允许投票
  - 加入 Round = 1 ✅ 允许加入（Round 1 ≥ 1）
  - 验证 Round = 0 ❌ 回滚 `RoundNotStarted`
  - 铸币 Round = -1 ❌ 回滚 `RoundNotStarted`
- **Phase 3**：
  - 投票 Round = 3 ✅ 允许投票
  - 加入 Round = 2 ✅ 允许加入（Round 2 ≥ 1）
  - 验证 Round = 1 ✅ 允许验证（Round 1 ≥ 1）
  - 铸币 Round = 0 ❌ 回滚 `RoundNotStarted`
- **Phase 4 起**：所有阶段就绪

### 2.3 服务行动执行合约（4 阶段，与被服务的 Group Action 对齐）

- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

**易混淆点**：服务的验证 Round 和铸币 Round 同样是**各阶段的轮次编号**。服务在铸币阶段的 Round p（对应 Phase p+3）查询 Group Action 验证阶段的 Round p（该验证在 Phase p+2 完成）。两个阶段的 Round 编号相同（都是 p），但对应的 Phase 不同（p+3 vs p+2）。

### 2.4 服务验证复用机制（关键设计）

服务不单独执行验证，而是检查该服务 Proposal 面向的所有 Group Action 各自的验证结果。一个服务 Proposal 面向整个 `actionTokenAddress` 社区的所有 Group Action，权重聚合来自所有相关 Group Action，但验证状态检查针对每个 Group Action 独立进行。

**Group Action 列表获取**：

服务通过 ActionTarget 查询获得该社区的所有 Group Action：
```solidity
proposalIds = ActionTarget.proposalIdsByExecutor(actionTokenAddress, mintRound, groupExecutor)
```

该查询返回指定 Round 在指定 Executor 下的所有 proposalId（即 actionId）。服务铸币阶段的 Round p 对应投票 Phase p，查询时传入 `mintRound`（铸币阶段的 Round p）作为投票 Round 参数，获得在该 Round 投票的 Group Action 列表。

服务在铸币阶段的 Round p（对应 Phase p+3）查询 Group Action 验证阶段的 Round p（该验证在 Phase p+2 完成）。两个阶段的 Round 编号相同（都是 p），但对应的 Phase 不同（p+3 vs p+2）：

```solidity
bool verified = groupActionExecutor.isRoundVerified(actionTokenAddress, actionId, mintRound);
```

**处理规则**：
- 关联的 Group Action 已完成验证 → 该 Group Action 的激励计入服务激励权重计算
- 关联的 Group Action 未验证或验证失败 → 该 Group Action 跳过该轮次，不计入权重
- 服务不依赖 Group Action 的铸币完成，只检查验证完成

**设计理由**：
- 避免重复验证工作：Group Action 已验证成员的参与身份和行动得分
- 权重数据来源一致：服务的权重计算基于 Group Action 的验证数据
- 阶段对齐：两者共享验证 Round，保持时间线一致性

---

## 3. 冷启动期

**LP 行动**：
- Phase 1：只有投票(Round 1)
- Phase 2：投票(Round 2) + 加入(Round 1)
- Phase 3：投票(Round 3) + 加入(Round 2) + 铸币(Round 1) ← 第一批铸币

**Group Action 和服务行动**：
- Phase 1：只有投票(Round 1)
- Phase 2：投票(Round 2) + 加入(Round 1)
- Phase 3：投票(Round 3) + 加入(Round 2) + 验证(Round 1)
- Phase 4：投票(Round 4) + 加入(Round 3) + 验证(Round 2) + 铸币(Round 1) ← 第一批铸币

第一批用户在 Phase 2 即可加入 LP 或 Group Action。
