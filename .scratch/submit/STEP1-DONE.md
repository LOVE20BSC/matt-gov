# Submit Step 1 完成总结

**日期**：2026-09-15  
**状态**：✅ 完成（已通过 Solc 0.8.37 编译验证）

---

## 完成事项

### ✅ 1. 结构体按旧分层重组（已完成）
- 新增 `ProposalInfo { ProposalHead head, ProposalBody body }`，对应旧 `ActionInfo`
- `ProposalBody` 改为**创建者提供的全部字段**：`title`、`details`、`target`、`targetMode`、`targetData`；`submitNewProposal` 的入参与 `ProposalInfo` 的组成共用这一个结构，不另立 `Params`
- `ActionSubmitInfo` → `SubmitInfo { submitterId, proposalId }`（`submitter` 由地址改为 `submitterId`）
- `ProposalCreated` 事件**不含 `targetData`**：`TokenLaunched` 与 `VoteCast` 同样有透传数据入参而事件不发，三个合约口径一致

### ✅ 2. 删除 minStake 字段（已完成）
- 从 `ProposalBody` 删除
- 删除 `submitNewProposal` 中的 `minStake > 0` 校验
- `ProposalCreated` 事件不含 `minStake`

**原因**：BSC 删除统一 Join 模块，旧代码中 `minStake` 用于首次加入门槛的逻辑已移至 Action 层各 Executor 独立配置

### ✅ 3. 读取面改为三类（已完成）
- 按 id 批量取详情：`proposalInfosByIds(tokenAddress, proposalIds[])` 回 `ProposalInfo[]`，与入参下标一一对应，未分配 ID 回滚 `ProposalNotFound`
- 分页：`proposalIds`、`proposalIdsByAuthor`、`submitInfos`，统一 `(offset, limit, reverse)` 并按页返回真实总数
  - `proposalIds`/`proposalIdsByAuthor` **只回 `proposalId` 不回本体**；`submitInfos` 回完整 `SubmitInfo` 记录（`submitterId` + `proposalId`）
- 不设单条详情入口：读一条传单元素数组，不再有只差一个字母、返回值却是两种东西的近名对
- 单键查询三条：`isSubmitted`（旧接口同名同参保留，回 `bool`）与两条方向单键 `proposalIdBySubmitter` / `submitterIdByProposalId`——旧 `submitInfo`/`submitInfoBySubmitter` 各改名而来，返回值都由 `ActionSubmitInfo` 收为单个标量，`0` 表示本轮未推举
- 删除 6 个 `Count`/`AtIndex` 函数与越界错误 `IndexOutOfBounds`

**为什么 `proposalIds` 分页不回本体、而 `submitInfos` 分页回记录**：判据是页内每一项是否定长。`ProposalBody` 的 `title`/`details`/`targetData` 都不设长度上限，页内成员由别人决定，一页里落进一条大 `targetData` 就能把整页顶到调用方 gas 上限之上且无法跳过；`SubmitInfo` 全为 `uint256`，任意一页的体量都与 `limit` 成正比。旧 `actionsAtIndex`/`actionSubmitsAtIndex` 直接在枚举里回结构体，这条路被撤掉。

**命名记号**：数组返回值在名字里体现载荷——`Ids` 只回轻量标识、`Infos` 回记录本体，裸集合名不用于返回数组的函数；筛选条件进名字（默认全量不标记、`By<key>` 按键、`ByIds` 显式 ID 数组）；是否分页不进名字，由入参 `(offset, limit, reverse)` 决定。仓库现有 28 个分页函数全部以参数表意、名字不带分页记号。

### ✅ 4. 写入口沿用旧语义（已完成）
- `submitNewProposal` 一笔内完成「创建 + 立即推举」，与旧 `submitNewAction` 的 `_createAction` + `_submitByActionId` 一致
- 事件顺序固定：先 `ProposalCreated` 后 `ProposalSubmitted`；回调同序，先 `onProposalCreated` 后 `onProposalSubmitted`
- 创建即占用该成员本轮的推举名额，两个入口共用「每人每轮一个」「每提案每轮一次」；`submit` 只推举已有 Proposal，可跨轮

**唯一的批量入口不设长度上限**：只读、无状态写，体量由调用方自己选，超限只是调用方自己的 out-of-gas，减小批量即可重试。

### ✅ 5. 文档同步（已完成）
- [ISubmit.sol](../../interfaces/core/ISubmit.sol) - 接口定义
- [05-submit.md](../../docs/specs/core/05-submit.md) - 规格文档
- [CHANGES-core.md](../../docs/specs/CHANGES-core.md) - 变更清单
- [CONTEXT.md](../../CONTEXT.md) - Proposal 记录命名
- [review-guide.md](../../docs/review-guide.md) - 批量边界一条补豁免条件
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

### 新增错误（7 个）
```
EmptyString(string)                     → 0x62a65aec
ZeroAmount(string)                      → 0x3b3e6350
InvalidAmount()                         → 0x2c5211c6
InvalidAddress()                        → 0xe6c4247b
InvalidTargetMode()                     → 0x2589e3a0
RoundNotStarted()                       → 0x8e9c6e1c
NotMemberOwner(uint256)                 → 0x33393244
```

### 改名错误（1 个）
```
ProposalNotFound(uint256)               → 0x428d06a9   （旧 ActionIdNotExist()）
```

### 新增 Getter 与 init（4 个）
```
initialized()                           → 0x158ef93e
phaseAddress()                          → 0x1bd70981
memberNFTAddress()                      → 0xceecabf5
init(address,address,address,uint256)   → 0x46639dba
```

### 改参与改名（3 个）
```
canSubmit(address,uint256)                                              → 0x74abd30d
submitNewProposal(address,uint256,(string,string,address,uint8,bytes[])) → 0xa59abdc8
submit(address,uint256,uint256)                                         → 0xb57c0be4
```

### 查询（6 个）
```
proposalInfosByIds(address,uint256[])                      → 0x58f1444e
proposalIds(address,uint256,uint256,bool)                  → 0xbc7a7809
proposalIdsByAuthor(address,uint256,uint256,uint256,bool)  → 0xc252fb35
submitInfos(address,uint256,uint256,uint256,bool)          → 0x4d8331da
proposalIdBySubmitter(address,uint256,uint256)             → 0x376a6055
submitterIdByProposalId(address,uint256,uint256)           → 0xb14e8f00
```

### 事件（2 个）
```
ProposalCreated(address,uint256,uint256,string,string,address,uint8)  → 0xfb8b1d44
ProposalSubmitted(address,uint256,uint256,uint256)                    → 0x81d08274
```

### 删除（7 个）
```
proposalsCount(address)                            → 已删除
proposalsAtIndex(address,uint256)                  → 已删除
proposalsByAuthorCount(address,uint256)            → 已删除
proposalsByAuthorAtIndex(address,uint256,uint256)  → 已删除
submissionsCount(address,uint256)                  → 已删除
submissionAtIndex(address,uint256,uint256)         → 已删除
IndexOutOfBounds(uint256)                          → 已删除
```

---

## 📂 相关文档

- [命名修复总结](.completed/step1-naming-fix-2026-09-15.md)
- [minStake 和分页改造完成](.completed/step1-minStake-pagination-fix-2026-09-15.md)
- [接口审查报告](step1-interface-review-2026-09-15.md)

---

**Step 1 接口定稿完成，可开始 Step 2（旧代码基线提交）**
