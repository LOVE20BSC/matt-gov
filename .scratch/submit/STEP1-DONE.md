# Submit Step 1 完成总结

**日期**：2026-09-15  
**状态**：✅ 完成（待 Solc 0.8.37 编译验证）

---

## 完成事项

### ✅ 1. 接口命名修复（已完成并验证）
- `submitterOf` → `submitInfo`
- `submissionByMember` → `submitInfoBySubmitter`
- 对齐旧代码 mapping getter 命名

### ✅ 2. 删除 minStake 字段（已完成）
- 从 `ProposalBody` 删除
- 从 `ProposalParams` 删除
- 删除 `createProposal` 中的 `minStake > 0` 校验
- `ProposalCreated` 事件不含 `minStake`

**原因**：BSC 删除统一 Join 模块，旧代码中 `minStake` 用于首次加入门槛的逻辑已移至 Action 层各 Executor 独立配置

### ✅ 3. 枚举改用分页（已完成）
- 删除 4 个旧函数：`proposalsCount`、`proposalsAtIndex`、`proposalsByAuthorCount`、`proposalsByAuthorAtIndex`
- 新增 2 个分页函数：
  - `proposals(address, uint256 offset, uint256 limit)` 返回 `(uint256[] proposalIds, uint256 totalCount)`
  - `proposalsByAuthor(address, uint256 author, uint256 offset, uint256 limit)` 返回 `(uint256[] proposalIds, uint256 totalCount)`

**原因**：与 Phase 的 `syncObservations` 分页模式保持一致，单次调用获取数据 + 总数，Gas 效率更高

### ✅ 4. 文档同步（已完成）
- [ISubmit.sol](../../interfaces/core/ISubmit.sol) - 接口定义
- [05-submit.md](../../docs/specs/core/05-submit.md) - 规格文档
- [CHANGES-core.md](../../docs/specs/CHANGES-core.md) - 变更清单
- [step1-interface-review-2026-09-15.md](step1-interface-review-2026-09-15.md) - 审查报告

---

## Selector 清单

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

### 新增错误（9 个）
```
IndexOutOfBounds(uint256)               → 0x44945fcc
EmptyString(string)                     → 0x62a65aec
ZeroAmount(string)                      → 0x3b3e6350
InvalidAmount()                         → 0x2c5211c6
InvalidAddress()                        → 0xe6c4247b
InvalidTargetMode()                     → 0x2589e3a0
RoundNotStarted()                       → 0x8e9c6e1c
NotMemberOwner(uint256)                 → 0x33393244
ProposalNotFound(uint256)               → 0x428d06a9
```

### 新增 Getter（3 个）
```
initialized()                           → 0x158ef93e
phaseAddress()                          → 0x07a40193
memberNFTAddress()                      → 0x1f0060b1
```

### 新增映射查询（2 个）
```
submitInfo(address,uint256,uint256)                   → 0x01759ece
submitInfoBySubmitter(address,uint256,uint256)        → 0x55dea01d
```

### 新增分页查询（2 个，待编译）
```
proposals(address,uint256,uint256)                        → 待编译
proposalsByAuthor(address,uint256,uint256,uint256)        → 待编译
```

### 删除（4 个旧枚举）
```
proposalsCount(address)                    → 已删除
proposalsAtIndex(address,uint256)          → 已删除
proposalsByAuthorCount(address,uint256)    → 已删除
proposalsByAuthorAtIndex(address,uint256,uint256) → 已删除
```

---

## ⚠️ 待完成

需要使用 Solc 0.8.37 编译 [ISubmit.sol](../../interfaces/core/ISubmit.sol) 以生成新的分页函数 selector。

---

## 📂 相关文档

- [命名修复总结](.completed/step1-naming-fix-2026-09-15.md)
- [minStake 和分页改造完成](.completed/step1-minStake-pagination-fix-2026-09-15.md)
- [接口审查报告](step1-interface-review-2026-09-15.md)

---

**Step 1 接口定稿完成，可开始 Step 2（旧代码基线提交）**
