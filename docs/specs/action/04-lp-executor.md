# LP 行动执行合约

本文档定义 LP 行动执行合约规格。

---

## 1. 保留逻辑（引用旧代码）

### 1.1 时间权重计算

**参考**：`LOVE20TKM/contracts/extension-lp/contracts/LpActionV2.sol` 的 `calculateTimeWeight` 函数

```text
deduction_i = min(
    amount_i,
    amount_i × (joinBlock_i - joinPhaseStartBlock) / joinPhaseBlocks
)
effectiveAmount = joinedAmount - deduction
effectiveLpRatio = effectiveAmount × 1e18 / totalEffectiveAmount
```

### 1.2 治理票上限

**参考**：`LOVE20TKM/contracts/extension-lp/contracts/LpActionV2.sol` 的 `govRatioMultiplier`

**变量定义**：
- `validGovVotes(memberId)` = 该 memberId 在该代币社区的当前有效治理票（铸币时从 Stake 合约实时查询）
- `totalGovVotes` = 该代币社区当前总有效治理票（铸币时从 Stake 合约实时查询）
- `effectiveLpRatio` = 经过时间权重扣减后的 LP 占比（见上述时间权重计算）
- `govRatioMultiplier` = 该 LP 行动 Proposal 创建时设置的治理票权重倍数（初始化参数）

**公式**：
```text
govRatio = validGovVotes(memberId) × 1e18 / totalGovVotes
govRatioCap = govRatio × govRatioMultiplier / 1e18
effectiveRatio = min(effectiveLpRatio, govRatioCap)
mintReward = proposalReward × effectiveRatio / 1e18
```

治理票用于计算激励上限，而非权重依据，因此使用实时值更公平：成员解锁质押后治理影响力降低，LP 激励上限也相应降低。

---

## 2. 关键变更

### 2.1 阶段模型

- **旧**：固定 4 阶段（Vote、Join、Verify、Mint）
- **新**：3 阶段（投票、加入、铸币），无验证阶段

### 2.2 激励铸造

- **旧**：逐人调用 Core Mint
- **新**：Executor 先经 ActionTarget 一次性铸造整个 Proposal 的 `proposalReward`，再按有效 LP 占比计算参与者激励

**铸造流程**：
1. Executor 通过 ActionTarget 调用 `mintProposalReward`
2. ActionTarget 调用 Core Mint
3. Core Mint 把全部 `proposalReward` 铸给 ActionTarget
4. ActionTarget 把全部金额转给 Executor
5. Executor 按参与者 `effectiveRatio` 分配

---

## 3. 删除能力

**V1 实现**：旧版本已废弃，仅迁移 V2（当前生产版本）。V1 与 V2 的核心差异：V1 不支持时间权重扣减和治理票上限约束，V2 引入这两项机制以提升公平性和防止末期涌入。
