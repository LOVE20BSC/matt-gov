# Submit Step 1 - minStake 和分页改造完成

**日期**：2026-09-15  
**任务**：删除 minStake 字段，枚举改用分页

---

## ✅ 改造内容

### 1. 删除 minStake 字段

#### ProposalBody 结构体
```solidity
// ❌ 删除前
struct ProposalBody {
    string title;
    string details;
    uint256 minStake;
}

// ✅ 删除后
struct ProposalBody {
    string title;
    string details;
}
```

#### ProposalParams 结构体
```solidity
// ❌ 删除前
struct ProposalParams {
    string title;
    string details;
    uint256 minStake;
    address target;
    TargetMode targetMode;
    bytes[] targetData;
}

// ✅ 删除后
struct ProposalParams {
    string title;
    string details;
    address target;
    TargetMode targetMode;
    bytes[] targetData;
}
```

#### 删除校验逻辑
- 删除 `createProposal` 中的 `minStake > 0` 校验
- `ZeroAmount("minStake")` 错误不再用于此处（保留错误声明，`init` 仍用于 `submitMinPerThousand == 0`）

#### 事件不含 minStake
- `ProposalCreated` 不再包含 `minStake` 字段

**原因**：BSC 架构删除统一 Join 模块，旧代码中 `minStake` 用于 `LOVE20Join` 首次加入门槛的逻辑已移至 Action 层各 Executor 独立配置（LP 用 `minGovRatio`，GroupAction 用 `activationMinGovRatio`）

---

### 2. 枚举改用分页

#### 删除 4 个旧函数
```solidity
// ❌ 旧模式（已删除）
function proposalsCount(address tokenAddress) external view returns (uint256);
function proposalsAtIndex(address tokenAddress, uint256 index) external view returns (uint256 proposalId);
function proposalsByAuthorCount(address tokenAddress, uint256 author) external view returns (uint256);
function proposalsByAuthorAtIndex(address tokenAddress, uint256 author, uint256 index) external view returns (uint256 proposalId);
```

#### 新增 2 个分页函数
```solidity
// ✅ 新模式（分页）
/// @notice 分页查询社区的所有 Proposal
/// @param tokenAddress 社区代币地址
/// @param offset 起始偏移（0-based）
/// @param limit 最多返回数量
/// @return proposalIds Proposal ID 数组
/// @return totalCount 社区 Proposal 总数
function proposals(
    address tokenAddress,
    uint256 offset,
    uint256 limit
) external view returns (uint256[] memory proposalIds, uint256 totalCount);

/// @notice 分页查询作者创建的 Proposal
/// @param tokenAddress 社区代币地址
/// @param author 作者 memberId
/// @param offset 起始偏移（0-based）
/// @param limit 最多返回数量
/// @return proposalIds Proposal ID 数组
/// @return totalCount 该作者的 Proposal 总数
function proposalsByAuthor(
    address tokenAddress,
    uint256 author,
    uint256 offset,
    uint256 limit
) external view returns (uint256[] memory proposalIds, uint256 totalCount);
```

**优势**：
- 单次调用获取数据 + 总数
- 支持前端分页展示
- 与 Phase.syncObservations 保持一致
- Gas 效率更高

---

## 📝 更新的文件

### 接口
1. **[ISubmit.sol](../../interfaces/core/ISubmit.sol)**
   - 删除 `ProposalBody.minStake`
   - 删除 `ProposalParams.minStake`
   - 删除 4 个枚举函数
   - 新增 2 个分页函数

### 规格文档
2. **[05-submit.md](../../docs/specs/core/05-submit.md)**
   - 删除 ProposalBody 表格中的 minStake 行
   - 删除 `proposalsAtIndex(tokenAddress, i)` 说明
   - 删除 `createProposal` 校验中的 `minStake > 0` 检查
   - 删除 `ProposalCreated` 事件中的 `minStake` 字段
   - 更新错误触发条件：`ZeroAmount` 不再用于 `minStake == 0`

3. **[CHANGES-core.md](../../docs/specs/CHANGES-core.md)**
   - 新增 minStake 删除说明
   - 新增枚举改分页说明
   - 更新错误触发条件表格
   - 更新实现参考清单

---

## 🔍 Selector 影响

### 保留（8 个）
```
stakeAddress()                          → 0x85107367 ✓
SUBMIT_MIN_PER_THOUSAND()               → 0xd6d15727 ✓
currentRound()                          → 0x8a19c8bc ✓
isSubmitted(address,uint256,uint256)    → 0x2bed3c29 ✓
AlreadyInitialized()                    → 0x0dc149f0 ✓
CannotSubmitAction()                    → 0xaec0699e ✓
AlreadySubmitted()                      → 0x9fbfc589 ✓
OnlyOneSubmitPerRound()                 → 0x9fb13b87 ✓
```

### 删除（4 个旧枚举）
```
proposalsCount(address)                    → 已删除
proposalsAtIndex(address,uint256)          → 已删除
proposalsByAuthorCount(address,uint256)    → 已删除
proposalsByAuthorAtIndex(address,uint256,uint256) → 已删除
```

### 新增（2 个分页）
```
proposals(address,uint256,uint256)                        → 待编译
proposalsByAuthor(address,uint256,uint256,uint256)        → 待编译
```

### 已有新增（11 个）
```
# 错误（9 个）
IndexOutOfBounds(uint256)               → 0x44945fcc
EmptyString(string)                     → 0x62a65aec
ZeroAmount(string)                      → 0x3b3e6350
InvalidAmount()                         → 0x2c5211c6
InvalidAddress()                        → 0xe6c4247b
InvalidTargetMode()                     → 0x2589e3a0
RoundNotStarted()                       → 0x8e9c6e1c
NotMemberOwner(uint256)                 → 0x33393244
ProposalNotFound(uint256)               → 0x428d06a9

# Getter（3 个）
initialized()                           → 0x158ef93e
phaseAddress()                          → 0x07a40193
memberNFTAddress()                      → 0x1f0060b1

# 查询（2 个映射 getter）
submitInfo(address,uint256,uint256)                   → 0x01759ece
submitInfoBySubmitter(address,uint256,uint256)        → 0x55dea01d
```

---

## ⚠️ 待编译验证

需要使用 Solc 0.8.37 编译生成新的 selector：
- `proposals(address,uint256,uint256)`
- `proposalsByAuthor(address,uint256,uint256,uint256)`

---

## 📊 最终状态

- ✅ minStake 完全移除
- ✅ 4 个枚举函数删除
- ✅ 2 个分页函数新增
- ✅ 规格文档同步
- ✅ CHANGES-core.md 同步
- ⚠️ 需要 Solc 0.8.37 编译验证新 selector

---

**Step 1 改造完成，待编译验证后可开始 Step 2（旧代码基线提交）**
