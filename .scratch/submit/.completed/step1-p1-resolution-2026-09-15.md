# Submit 迁移 Step 1 P1 问题解决报告

**日期**: 2026-09-15  
**状态**: ✅ 已解决并验证  
**前置**: [review-2026-09-15-submit-step1-spec-review.md](../review-2026-09-15-submit-step1-spec-review.md)

---

## 一、P1 问题解决清单

### P1-1: 六类必须拒绝条件缺 selector ✅

**解决方案**: 新增 9 个精准错误声明，覆盖所有拒绝条件

| 错误名 | 触发条件 | Selector |
|--------|----------|----------|
| `EmptyString(string field)` | 标题或描述为空 | `0x62a65aec` |
| `ZeroAmount(string field)` | 质押或 Target 金额为 0 | `0x3b3e6350` |
| `InvalidAmount()` | 金额超出范围 | `0x2c5211c6` |
| `InvalidAddress()` | Target 地址为零或 EOA/合约无效 | `0xe6c4247b` |
| `InvalidTargetMode()` | targetMode 枚举值非法 | `0x2589e3a0` |
| `RoundNotStarted()` | `currentRound()` 返回 0 | `0x8e9c6e1c` |
| `NotMemberOwner(uint256 memberId)` | 调用者不是该 memberId 的所有者 | `0x33393244` |
| `ProposalNotFound(uint256 proposalId)` | 指定 proposalId 不存在 | `0x428d06a9` |
| `IndexOutOfBounds(uint256 index)` | 查询索引超出范围 | `0x44945fcc` |

**变更位置**: [ISubmit.sol:25-37](../../interfaces/core/ISubmit.sol)

---

### P1-2: `MAX_VERIFICATION_KEY_LENGTH()` 无消费者 ✅

**解决方案**: 已从接口中删除

**确认**: 编译后 ABI 中不再存在该函数

---

### P1-3: 缺 `ISubmitErrors` 子接口 ✅

**解决方案**: 新增 `ISubmitErrors` 子接口，包含所有错误声明

**变更位置**: [ISubmit.sol:25-37](../../interfaces/core/ISubmit.sol)

**继承关系**:
```solidity
interface ISubmit is ISubmitErrors, ISubmitEvents
```

---

### P1-4: 校验顺序未定稿 ✅

**解决方案**: 在规格文档中明确两阶段校验顺序

#### `createProposal` 校验顺序

1. **结构校验**（与业务状态无关，可提前失败）
   - `head.title` 非空 → `EmptyString("title")`
   - `body.description` 非空 → `EmptyString("description")`
   - `head.stakeAmount > 0` → `ZeroAmount("stakeAmount")`
   - `body.targetAmount > 0` → `ZeroAmount("targetAmount")`
   - `body.targetAddress != address(0)` → `InvalidAddress()`
   - `targetMode` 枚举值有效 → `InvalidTargetMode()`

2. **状态与权限校验**（依赖外部合约和存储）
   - `currentRound() > 0` → `RoundNotStarted()`
   - `MemberNFT.ownerOf(submitterId) == msg.sender` → `NotMemberOwner(submitterId)`
   - `Stake.canStake(submitterId, tokenAddress, head.stakeAmount)` → `InvalidAmount()`

#### `submit` 校验顺序

1. **结构与存在性**
   - `currentRound() > 0` → `RoundNotStarted()`
   - `proposal(tokenAddress, proposalId)` 存在 → `ProposalNotFound(proposalId)`

2. **权限与状态**
   - `MemberNFT.ownerOf(submitterId) == msg.sender` → `NotMemberOwner(submitterId)`
   - `!isSubmitted(tokenAddress, submitterId, round)` → `AlreadySubmitted()`
   - `canSubmit(tokenAddress, submitterId)` → `CannotSubmitAction()` 或 `OnlyOneSubmitPerRound()`

**变更位置**: [05-submit.md:141-179](../05-submit.md)

---

## 二、P2 问题解决清单

### P2-1: 缺 `initialized()` getter ✅

**解决方案**: 新增 `initialized() external view returns (bool)`

**Selector**: `0x158ef93e`

---

### P2-2: 缺 `phaseAddress()` getter ✅

**解决方案**: 新增 `phaseAddress() external view returns (address)`

**Selector**: `0x1bd70981`

---

### P2-3: 缺 `memberNFTAddress()` getter ✅

**解决方案**: 新增 `memberNFTAddress() external view returns (address)`

**Selector**: `0xceecabf5`

---

## 三、编译验证

### 测试环境
```
Solc: 0.8.37
EVM: osaka
```

### 验证结果
```
✅ 编译成功
✅ 所有保留 selector 一致
✅ 新增 9 个错误 selector 已生成
✅ 删除 MAX_VERIFICATION_KEY_LENGTH()
✅ 新增 3 个 getter selector 已生成
```

### 保留 selector 验证

| 函数/错误 | Selector | 状态 |
|-----------|----------|------|
| `stakeAddress()` | `0x85107367` | ✅ |
| `SUBMIT_MIN_PER_THOUSAND()` | `0xd6d15727` | ✅ |
| `currentRound()` | `0x8a19c8bc` | ✅ |
| `isSubmitted(address,uint256,uint256)` | `0x2bed3c29` | ✅ |
| `AlreadyInitialized()` | `0x0dc149f0` | ✅ |
| `CannotSubmitAction()` | `0xaec0699e` | ✅ |
| `AlreadySubmitted()` | `0x9fbfc589` | ✅ |
| `OnlyOneSubmitPerRound()` | `0x9fb13b87` | ✅ |

---

## 四、文档更新

1. ✅ 更新 [ISubmit.sol](../../interfaces/core/ISubmit.sol)
2. ✅ 更新 [05-submit.md](../05-submit.md) - 补充校验顺序和新增错误说明
3. ✅ 更新 [CHANGES-core.md](../CHANGES-core.md) - 记录接口变更

---

## 五、接口审查通过（2026-09-15 补充）

### 修复的遗漏问题
1. `IndexOutOfBounds` 参数名 `length` → `index`（与旧代码一致）
2. `submissionAtIndex` 返回值补充 `submitterId`
3. 新增 4 个查询接口（对应旧代码 mapping getter）：
   - `submitterOf()` - 查询 Proposal 推举者
   - `submissionByMember()` - 查询成员是否已推举
   - `proposalsByAuthorCount()` / `proposalsByAuthorAtIndex()` - 枚举作者 Proposal
4. `ProposalParams` 补充 `minStake` 字段

### Selector 验证
- 保留 selector：8 个（全部一致）
- 新增 selector：13 个（9 错误 + 4 查询函数）
- 编译：Solc 0.8.37 通过

### 审查结论
**✅ 通过** - 接口符合"尽可能保留旧接口"原则，可进入 Step 2

详见：[step1-interface-review-2026-09-15.md](../step1-interface-review-2026-09-15.md)

---

**Step 1 已完成审查，可以开始 Step 2（旧代码基线提交）**

---

## 五、下一步准备

所有 P1 阻塞问题已解决，P2 问题同步修复，满足进入 Step 2 的条件：

- ✅ 接口定稿并编译通过
- ✅ 规格文档补充完整（校验顺序、错误说明）
- ✅ selector 验证通过
- ✅ 差异文档已更新

**可以开始 Step 2**: 旧代码基线提交
