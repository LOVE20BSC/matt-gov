# 服务行动执行合约

本文档定义服务行动执行合约规格。

---

## 1. 保留逻辑（引用旧代码）

### 1.1 服务范围和聚合

**参考**：`LOVE20TKM/action/GroupService`

一个服务 Proposal 面向整个 `actionTokenAddress` 社区的 Group Action 集合，不绑定单个源 `actionId`。该 Proposal 的 `tokenAddress` 记为 `serviceTokenAddress`。两者必须满足：
- `serviceTokenAddress == actionTokenAddress`，或
- `serviceTokenAddress` 是 `actionTokenAddress` 的直接父币

### 1.2 权重计算

**参考**：`LOVE20TKM/action/GroupService`

**变量定义**：
- `A[a]` = Group Action a 的总激励
- `r[a]` = Group Action a 的公共验证者比例（ratioForPublicVerifier）
- `T` = 所有相关 Group Action 的总激励之和
- `m` = memberId
- `groupReward(a, m)` = 群组 m 在 Group Action a 中获得的总激励（聚合该群组所有成员在该行动中的激励）

**公式**：
```text
verifierWeightNumerator(m) = Σ(A[a] × r[a])
    // 仅对 verifierId[a] == m 的行动累加

ownerWeightNumerator(m) = Σ(groupReward(a, m) × (1e18 - r[a]))

theoreticalVerifierReward(m) = serviceReward × verifierWeightNumerator(m) / (T × 1e18)
theoreticalOwnerReward(m) = serviceReward × ownerWeightNumerator(m) / (T × 1e18)
theoreticalOwnerRatio(m) = ownerWeightNumerator(m) / (T × 1e18)
```

**变量说明**：`verifierId[a]` = Group Action a 锁定的公共验证者 memberId。

### 1.3 二次分配

**参考**：`LOVE20TKM/action/GroupService`

群组 owner 当前持有人可以按 `actionTokenAddress + groupActionId + groupId + round` 配置二次分配的 `recipientIds[]` 和 `ratios[]`。

**配置键说明**：
- `actionTokenAddress`：Group Action 所属的代币社区地址（即被服务的社区）
- `groupActionId`：Group Action 的 actionId（在 actionTokenAddress 社区中）
- `groupId`：群组的 memberId（群组 owner 的 MemberNFT ID）
- `round`：轮次编号（该群组在该 Group Action 的哪个 Round 获得的激励）

**设计理由**：二次分配配置基于 Group Action 而非服务 Proposal，因此所有对该 Group Action 进行激励的服务行动都会按同一配置进行二次分配。这避免了为每个服务 Proposal 单独配置的复杂性。

**分配参数**：
- `recipientIds[]`：接收二次分配激励的 memberId 数组
- `ratios[]`：对应的分配比例数组（总和可以 ≤ 1e18，表示部分分配；> 1e18 时会缩放）

---

## 2. 关键变更

### 2.1 去 gas 补偿

- **旧**：服务激励包含 gas 补偿部分
- **新**：服务激励不包含 gas 补偿

### 2.2 100% 二次分配安全收敛

- **旧**：二次分配可能因舍入导致超额
- **新**：使用统一缩放比例，避免两次独立取整后超过实际预算

**改进计算**：

**变量定义**：
- `govRatioMultiplier(m)` = 该群组 m 的治理票占比倍数（Group Action Proposal 创建时设置）
- `theoreticalOwnerRatio(m)` = 该群组 owner 的理论激励占比（基于权重计算，见第 1.2 节）
- `actualOwnerReward(m)` = 该群组的实际 owner 激励（受治理票约束）

**公式**：
```text
// 计算群组 owner 的治理票占比上限
govRatio(m) = validGovVotes(m) × 1e18 / totalGovVotes
govRatioCap(m) = govRatio(m) × govRatioMultiplier(m) / 1e18

// owner 激励占比取理论值和上限的较小值
ownerRatioCap(m) = min(theoreticalOwnerRatio(m), govRatioCap(m))

// owner 激励 = 整个服务激励 × owner 占比上限
actualOwnerReward(m) = serviceReward × ownerRatioCap(m) / 1e18
```

**设计理由**：
- 公共验证者激励基于服务工作量，不需要单独约束，由权重自然分配
- 群组 owner 激励代表群组的组织能力，应受治理参与度约束，避免治理票极低的群组获得过高激励
- 以整个服务激励（包含验证者部分）作为分母，简化计算逻辑，避免逐个计算验证者激励的复杂性和高 gas 成本

公共验证者部分直接给实际锁定的验证者；群组 owner 部分按该 `groupId` 在各行动中的激励权重拆分，并按群组配置的接收主体和比例执行二次分配。

**二次分配公式**：
```solidity
// 计算每个接收者的理论份额
theoreticalRecipientReward[i] = recipientRatio[i] × actualOwnerReward / 1e18
theoreticalTotal = Σ(theoreticalRecipientReward[i])

// 统一缩放确保总和不超过可用激励
if (theoreticalTotal > actualOwnerReward) {
    scaleFactor = actualOwnerReward × 1e18 / theoreticalTotal
    actualRecipientReward[i] = theoreticalRecipientReward[i] × scaleFactor / 1e18
} else {
    actualRecipientReward[i] = theoreticalRecipientReward[i]
}
```

先计算每个接收者的理论份额，再统一缩放确保总和不超过 `actualOwnerReward`。验证者部分激励不参与二次分配，直接给实际锁定的公共验证者。
