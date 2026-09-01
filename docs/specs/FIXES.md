# 规格文档问题修复清单

本文档列出规格文档一致性检查中发现的问题及修复方案。

## 修复状态

### ✅ 已完成修复

所有问题已修复完成：

**Critical (C1-C3)**：
- [x] C1: 统一治理激励公式（`core.md` + `CHANGES-core.md`）
- [x] C2: 补充 Action 与 Core 对接机制（`action.md`）
- [x] C3: 明确链群服务验证复用逻辑（`action.md`）

**Major (M1-M6)**：
- [x] M1: 加速质押解锁后的记账处理（`core.md`）
- [x] M2: forceExit 与链群 Chat 资格的 UX 提示（`action.md`）
- [x] M3: 治理激励批量铸造的前端过滤建议（`core.md`）
- [x] M4: Manager 创建的 Chat 类型区分（`group-chat.md`）
- [x] M5: 持币资格的精度歧义（`group-chat.md`）
- [x] M6: RECENT_ROUNDS 时间基准（`group-chat.md`）

**Minor (N1-N4)**：
- [x] N1: Phase 同步时机（`core.md`）
- [x] N2: 首个代币 Airdrop 部署顺序（`core.md`）
- [x] N3: MemberNFT 转移的权益定义（`core.md`）
- [x] N4: 质押融合的禁止条件设计理由（`core.md`）

---

## 🔴 严重问题（Critical）

### C1: 治理激励公式不一致 ✅

**问题**：`core.md` 和 `CHANGES-core.md` 中公式不一致，相差 10^18 倍。

**修复**：
统一为以下公式，并在两个文档中保持一致：

```solidity
// 常量定义
uint256 constant GOV_VERIFY_SHARE = 0.5e18;  // 50%
uint256 constant GOV_BOOST_SHARE = 0.5e18;   // 50%

// 计算公式
verifyReward = govPool * GOV_VERIFY_SHARE / 1e18 * memberVotes / totalVotes
theoreticalBoost = govPool * GOV_BOOST_SHARE / 1e18 * memberBoost / totalBoost
boostReward = min(theoreticalBoost, verifyReward * 2)
overflowReward = theoreticalBoost - boostReward
```

**影响文件**：
- `core.md` 第 7.3 节 ✅
- `CHANGES-core.md` 第 6 节 ✅

---

### C2: Action 与 Core 治理的对接机制 ✅

**问题**：行动 Proposal 如何在 Core 中创建和投票不清晰。

**修复**：在 `action.md` 第 2.1 节补充完整对接流程。

**影响文件**：
- `action.md` 第 2.1 节 ✅

---

### C3: 链群服务验证机制 ✅

**问题**："复用验证结果"的具体机制不清晰。

**修复**：在 `action.md` 第 3.2 节补充验证复用机制说明。

**影响文件**：
- `action.md` 第 3.2 节 ✅

---

## 🟡 重要问题（Major）

### M1: 加速质押解锁后的记账处理 ✅

**修复**：在 `core.md` 第 5.3 节补充解锁申请对加速质押记录的影响说明。

**影响文件**：
- `core.md` 第 5.3 节 ✅

---

### M2: forceExit 与链群 Chat 资格的 UX 提示 ✅

**修复**：在 `action.md` 第 2.3 节补充用户体验提示。

**影响文件**：
- `action.md` 第 2.3 节 ✅

---

### M3: 治理激励批量铸造的前端过滤建议 ✅

**修复**：在 `core.md` 第 7.3 节补充批量铸造最佳实践。

**影响文件**：
- `core.md` 第 7.3 节 ✅

---

### M4: Manager 创建的 Chat 类型区分 ✅

**修复**：在 `group-chat.md` 第 7.4 节补充 Chat 类型区分机制。

**影响文件**：
- `group-chat.md` 第 7.4 节 ✅

---

### M5: 持币资格的精度歧义 ✅

**修复**：在 `group-chat.md` 第 7.1 节将 `> 1` 改为 `> 0`。

**影响文件**：
- `group-chat.md` 第 7.1 节 ✅

---

### M6: RECENT_ROUNDS 时间基准 ✅

**修复**：在 `group-chat.md` 第 7.1 节补充 RECENT_ROUNDS 的时间基准说明。

**影响文件**：
- `group-chat.md` 第 7.1 节 ✅

---

## 🔵 次要问题（Minor）

### N1: Phase 同步时机 ✅

**修复**：在 `core.md` 第 4.3 节补充 Phase 同步时机说明。

**影响文件**：
- `core.md` 第 4.3 节 ✅

---

### N2: 首个代币 Airdrop 部署顺序 ✅

**修复**：在 `core.md` 第 9.2 节补充部署顺序和接口约定。

**影响文件**：
- `core.md` 第 9.2 节 ✅

---

### N3: MemberNFT 转移的权益定义 ✅

**修复**：在 `core.md` 第 2 节补充 MemberNFT 转移后的权益归属详细说明。

**影响文件**：
- `core.md` 第 2 节 ✅

---

### N4: 质押融合的禁止条件设计理由 ✅

**修复**：在 `core.md` 第 5.5 节补充禁止融合的设计理由。

**影响文件**：
- `core.md` 第 5.5 节 ✅

---

## 验收标准

- [x] `core.md` 和 `CHANGES-core.md` 中的治理激励公式完全一致
- [x] `action.md` 清晰描述了与 Core Submit/Vote 的对接流程
- [x] 所有"复用验证"、"时间基准"、"权益归属"等关键概念都有明确定义
- [x] 不再存在严重的自相矛盾或逻辑缺陷
