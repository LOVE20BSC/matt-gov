# Submit Step 1 命名修复总结

**日期**：2026-09-15  
**任务**：修复查询函数命名，与旧代码保持一致

---

## ✅ 修复内容

### 命名对齐（保持旧代码一致性）

| 修改前 | 修改后 | 对应旧代码 | Selector |
|--------|--------|-----------|----------|
| `submitterOf(...)` | `submitInfo(...)` | `submitInfo` mapping getter | `0x8937c825` → `0x01759ece` |
| `submissionByMember(...)` | `submitInfoBySubmitter(...)` | `submitInfoBySubmitter` mapping getter | `0x9702bddd` → `0x55dea01d` |

**原因**：
- 旧代码使用 `submitInfo` 和 `submitInfoBySubmitter` 作为 public mapping 名称
- Solidity 自动生成同名 getter
- 新接口应保持相同命名，减少前端迁移成本

---

## 📝 更新的文件

1. **[ISubmit.sol](../../interfaces/core/ISubmit.sol)** - 接口定义
2. **[CHANGES-core.md](../../docs/specs/CHANGES-core.md)** - 变更清单
3. **[step1-interface-review-2026-09-15.md](../step1-interface-review-2026-09-15.md)** - 审查报告

---

## 🔍 编译验证

```bash
✓ Solc 0.8.37 编译通过
✓ 所有保留 selector 一致（8 个）
✓ 新增 selector 已生成（12 个：9 错误 + 3 getter）
✓ 命名修复后 selector 已更新
```

---

## 📊 最终 Selector 清单

### 保留（8 个）
```
stakeAddress()                          → 0x85107367
SUBMIT_MIN_PER_THOUSAND()               → 0xd6d15727
currentRound()                          → 0x8a19c8bc
isSubmitted(address,uint256,uint256)    → 0x2bed3c29
AlreadyInitialized()                    → 0x0dc149f0
CannotSubmitAction()                    → 0xaec0699e
AlreadySubmitted()                      → 0x9fbfc589
OnlyOneSubmitPerRound()                 → 0x9fb13b87
```

### 新增（12 个）
```
# 新增错误（9 个）
IndexOutOfBounds(uint256)               → 0x44945fcc
EmptyString(string)                     → 0x62a65aec
ZeroAmount(string)                      → 0x3b3e6350
InvalidAmount()                         → 0x2c5211c6
InvalidAddress()                        → 0xe6c4247b
InvalidTargetMode()                     → 0x2589e3a0
RoundNotStarted()                       → 0x8e9c6e1c
NotMemberOwner(uint256)                 → 0x33393244
ProposalNotFound(uint256)               → 0x428d06a9

# 新增查询（3 个 getter）
initialized()                           → 0x158ef93e
phaseAddress()                          → 0x07a40193
memberNFTAddress()                      → 0x1f0060b1

# 新增查询（4 个枚举/映射）
submitInfo(address,uint256,uint256)                   → 0x01759ece
submitInfoBySubmitter(address,uint256,uint256)        → 0x55dea01d
proposalsByAuthorCount(address,uint256)               → 0x9e33c8b9
proposalsByAuthorAtIndex(address,uint256,uint256)     → 0xed56f926
```

---

**Step 1 已完成所有修复，可以开始 Step 2（旧代码基线提交）**
