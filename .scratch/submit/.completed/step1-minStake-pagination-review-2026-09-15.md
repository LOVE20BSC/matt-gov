# Submit Step 1 - minStake 和分页问题

**日期**：2026-09-15  
**发现者**：用户审查

---

## 问题 1: minStake 字段无意义

### 当前状态
```solidity
struct ProposalBody {
    string title;
    string details;
    uint256 minStake;  // ❌ 应删除
}
```

### 问题分析
- **旧代码用途**：在 `LOVE20Join` 中限制首次加入的最小金额
  ```solidity
  // LOVE20TKM/core/src/LOVE20Join.sol:220
  if (joinedAmount == 0) {
      if (additionalAmount < actionInfo.body.minStake) {
          revert JoinAmountLessThanMinStake();
      }
  }
  ```
- **BSC 新架构**：
  - **Join 模块已删除**：不在 Core 层迁移
  - **Action 层替代**：LP Executor 和 GroupAction Executor 各自定义准入规则
    - LP Executor：使用 `minGovRatio` 控制首次加入门槛（`action/04-lp-executor.md`）
    - GroupAction Executor：使用 `activationMinGovRatio` 控制激活门槛（`action/05-group-action-executor.md`）
  - **不再需要统一字段**：各 Executor 通过 Proposal KV 传递自己的配置参数
- **现状**：Submit 接口中保留了 `minStake` 但无消费者，规格文档也要求校验它 > 0

### 审查结论：✅ 应删除

**理由**：
1. **无消费者**：Core Submit 不使用、Action Executor 各自独立配置
2. **架构更清晰**：准入规则下沉到具体 Executor，Core 层不预设业务字段
3. **符合设计原则**：Proposal 通过 Target + Target Data 传递不透明配置，不在 ProposalBody 硬编码具体业务参数

### 删除清单
从以下位置删除 `minStake`：
1. `ProposalBody` 结构体
2. `ProposalParams` 结构体
3. `createProposal` 校验逻辑（删除 `ZeroAmount("minStake")` 的触发条件，保留错误声明供其他模块使用）
4. 规格文档 `05-submit.md` 中的相关说明
5. 事件 `ProposalCreated` 不再包含 `minStake` 字段

---

## 问题 2: 枚举接口应改用分页

### 当前状态
```solidity
// ❌ 旧模式：count + atIndex
function proposalsCount(address tokenAddress) external view returns (uint256);
function proposalsAtIndex(address tokenAddress, uint256 index) external view returns (uint256 proposalId);

function proposalsByAuthorCount(address tokenAddress, uint256 author) external view returns (uint256);
function proposalsByAuthorAtIndex(address tokenAddress, uint256 author, uint256 index) external view returns (uint256 proposalId);
```

### 问题分析
- **Phase 已采用分页**：`syncObservations(offset, limit, reverse)` 返回数组 + `totalCount`
- **旧模式缺点**：
  - 需要两次调用（先 count，再循环 atIndex）
  - 大量 Proposal 时 Gas 效率低
  - 前端需要多次 RPC 调用

### 审查结论：✅ 应改用分页

**理由**：
1. **Phase 已确立模式**：`syncObservations(offset, limit, reverse)` 返回 `(arrays, totalCount)`
2. **前端效率**：单次调用获取数据 + 总数，避免先 count 再循环 atIndex 的多次 RPC
3. **Gas 优化**：批量返回数组比逐个 atIndex 调用更高效
4. **一致性**：与 Phase 接口风格统一，降低学习成本

### 改造方案

**删除 4 个旧函数**：
```solidity
// ❌ 删除
function proposalsCount(address tokenAddress) external view returns (uint256);
function proposalsAtIndex(address tokenAddress, uint256 index) external view returns (uint256 proposalId);

function proposalsByAuthorCount(address tokenAddress, uint256 author) external view returns (uint256);
function proposalsByAuthorAtIndex(address tokenAddress, uint256 author, uint256 index) external view returns (uint256 proposalId);
```

**新增 2 个分页函数**：
```solidity
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
- 更符合现代 Web3 前端需求

---

## 影响评估

### minStake 删除
- ✅ 无向后兼容问题（新合约，旧代码也未真正依赖此字段被 Submit 校验）
- ✅ 简化参数校验逻辑
- ✅ 架构更清晰：Core 层不预设业务字段，由 Executor 自行配置
- ⚠️ 需同步更新规格文档、接口定义和事件签名
- ⚠️ 事件 selector 会变化（`ProposalCreated` 删除 `minStake` 字段）

### 分页改造
- ✅ 更符合现代 Web3 前端需求
- ✅ 与 Phase 接口风格统一
- ✅ Gas 效率提升（批量读取 vs 多次单点查询）
- ⚠️ 删除 4 个函数、新增 2 个函数，selector 完全变化
- ⚠️ 前端需要调整调用方式（但更简单）
- ⚠️ 保留的 selector 数量从 8 个减少到 4 个（删除 4 个枚举相关）

---

## 审查结论

### ✅ 推荐执行两项改造

**理由**：
1. **minStake 删除是正确的架构决策**：
   - BSC 已删除统一 Join 模块
   - 各 Executor 通过 KV 独立配置准入规则
   - Core 层保留无意义字段会造成混淆

2. **分页改造符合最佳实践**：
   - Phase 已确立分页模式为协议标准
   - 单次调用 vs 多次调用的效率差异显著
   - 前端实现更简洁，用户体验更好

3. **现在改造成本最低**：
   - 新合约未部署，无历史包袱
   - 无需考虑向后兼容
   - Step 1 就是接口确认阶段，最适合调整

---

## 待办事项

### minStake 删除
- [ ] 删除 `ProposalBody.minStake` 字段
- [ ] 删除 `ProposalParams.minStake` 字段
- [ ] 删除 `createProposal` 中的 `minStake > 0` 校验（保留 `ZeroAmount` 错误声明，其他地方可能用）
- [ ] 更新 `ProposalCreated` 事件：删除 `minStake` 字段
- [ ] 更新规格文档 `05-submit.md`：删除 minStake 相关校验说明和事件字段
- [ ] 更新 `CHANGES-core.md`：记录此变更

### 分页改造
- [ ] 删除 `proposalsCount(address)` 函数
- [ ] 删除 `proposalsAtIndex(address, uint256)` 函数
- [ ] 删除 `proposalsByAuthorCount(address, uint256)` 函数
- [ ] 删除 `proposalsByAuthorAtIndex(address, uint256, uint256)` 函数
- [ ] 新增 `proposals(address, uint256, uint256)` 分页函数
- [ ] 新增 `proposalsByAuthor(address, uint256, uint256, uint256)` 分页函数
- [ ] 更新规格文档 `05-submit.md`：说明分页模式
- [ ] 更新 `CHANGES-core.md`：记录枚举接口改造

### 通用
- [ ] 重新编译验证
- [ ] 更新所有 selector 清单
- [ ] 更新 `.scratch/submit/step1-interface-review-2026-09-15.md`：记录这两项变更
- [ ] 确认 Step 1 完成，准备进入 Step 2

---

**预计 selector 变化**：
- 保留：4 个（stakeAddress, SUBMIT_MIN_PER_THOUSAND, currentRound, isSubmitted）
- 删除：4 个（4 个旧枚举函数）
- 新增：2 个（2 个新分页函数）
- 事件变化：`ProposalCreated` selector 会改变（字段删除）
