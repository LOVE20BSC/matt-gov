# LOVE20BSC Action 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义社群行动 Proposal 类型。**保留旧逻辑的部分直接引用旧代码位置**，避免重复描述。详细变更清单见 [`CHANGES-action.md`](./CHANGES-action.md)。

---

## 1. 组件和依赖

`action` 由以下组件组成：

- `ActionTarget`：所有社群行动 Proposal 的统一 Target
- LP 行动执行合约
- 链群行动执行合约
- 链群服务行动执行合约

组件依赖 `core` 的 `MemberNFT`、`Stake`、`Submit`、`Vote`、`Mint` 和 `Phase` 接口。核心只传递 Proposal 上下文、治理票增量和不透明 KV；候选人、链群、LP、资产托管和服务分配由本代码库解释。

---

## 2. ActionTarget（统一框架）

### 2.1 Proposal 关联

#### 与 Core 治理的对接

行动 Proposal 通过 Core Submit 在治理 Round 创建：

**创建参数**：
- `tokenAddress`: 社区代币地址
- `target`: ActionTarget 合约地址（必须）
- `targetMode`: `Callback`（必须）
- `title`/`details`: 行动标题和详情
- `kvList[0]`: `(key=keccak256("executor"), value=abi.encode(executorAddress))`

**Core 调用流程**：
1. **创建时**：Core Submit 调用 `ActionTarget.onProposalCreated()`
   - ActionTarget 记录 `proposalId → executorAddress` 映射
   - ActionTarget 转发完整 KV 到 Executor 的 `onProposalCreated()`
   
2. **推举时**：Core Submit 调用 `ActionTarget.onProposalSubmitted()`
   - ActionTarget 转发到 Executor 的 `onProposalSubmitted()`
   
3. **投票时**：Core Vote 调用 `ActionTarget.onProposalVoted()`
   - ActionTarget 根据 proposalId 找到 executor
   - 调用 `executor.onProposalVoted(tokenAddress, proposalId, voterId, votes, ...)`
   - Executor 记录成员投票权重

**Executor 保留项**（关键设计）：
- 创建 KV 的第 `0` 项固定为：`key = keccak256("executor")`，`value = abi.encode(executorAddress)`
- `executorAddress` 必须是非零且包含合约代码的地址
- 第 `0` 项之外的 KV 可以为空，业务字段由 Executor 负责

**验证时机**：
ActionTarget 在 `onProposalCreated` 回调中验证：
- `kvList.length > 0`
- `kvList[0].key == keccak256("executor")`
- decode 后的 `executorAddress` 非零且包含合约代码
验证失败则回滚整个 Proposal 创建交易。

ActionTarget 以 `tokenAddress + proposalId` 为唯一键保存 Executor，把完整创建 KV 原样转发给 Executor。只有 ActionTarget 可以调用 Executor 的三个回调。

**回调接口**：
```solidity
onProposalCreated(address tokenAddress, uint256 proposalId,
    bytes32[] keys, bytes[] values)
onProposalSubmitted(address tokenAddress, uint256 proposalId,
    uint256 submitterId, bytes32[] keys, bytes[] values)
onProposalVoted(address tokenAddress, uint256 proposalId,
    uint256 voterId, uint256 votes, bytes32[] keys, bytes[] values)
```

### 2.2 参与登记

ActionTarget 维护通用的"MemberNFT 是否参与某个行动"登记，供前端"当前已参与行动"列表和外部参与资格判断使用。

**设计边界**：
- 只登记参与关系，不持有资产
- 资产和业务状态由 Executor 维护
- 链群行动是例外：链群归属由链群 Executor 维护

**接口**：
- `isParticipating(tokenAddress, actionId, memberId)`
- `actionIdsByMemberId(tokenAddress, memberId)`、对应的 `Count` 和 `AtIndex`
- `registerParticipation(tokenAddress, actionId, memberId)` — 仅关联 Executor 可调用
- `unregisterParticipation(tokenAddress, actionId, memberId)` — 仅关联 Executor 可调用

### 2.3 forceExit（应急兜底）

**入口**：`forceExit(tokenAddress, actionId, memberId)`

**设计意图**：Executor 失效时，当前 MemberNFT 持有人可以直接清除 ActionTarget 的通用登记。

**行为**：
- 清除 ActionTarget 登记并触发事件
- 不调用 Executor、不转移资产、不承诺资产返还
- 前端默认隐藏，只作为最后兜底

**用户体验提示**：
- `forceExit` 只清除 ActionTarget 的通用登记，不修改链群归属
- 用户调用后仍可能保留链群 Chat 资格（归属在 Executor）
- 要完全退出链群（包括 Chat），需通过 Executor 的正常退出流程
- 前端应明确提示这一差异，避免用户困惑

**限制**：
- ActionTarget 查询立即不再返回该参与记录
- Executor 的历史参与、资产和链群归属等业务状态均不回写
- 链群归属只在链群 Executor 的正常退出流程中更新

### 2.4 查询

**按 Round 查询**（新增）：
1. `proposalIdsByExecutor(tokenAddress, round, executor)` 返回该 Executor 关联的 `proposalId[]`
2. `proposals(tokenAddress, round)` 返回本轮所有有投票且已关联 Executor 的 `proposalIds[]` 和一一对应的 `executors[]`

两类查询先从 `Vote` 读取本轮有投票的 Proposal，再按 Proposal ID 读取 ActionTarget 映射并筛选，不维护独立反向索引。

---

## 3. 行动阶段模型（全新设计）

### 3.1 框架层通用阶段

ActionTarget 定义所有行动类型的必经流程：

1. **投票阶段**：社区对行动 Proposal 投票（治理层 Phase p）
2. **加入阶段**：获得票的行动开放加入（Phase p+1）
3. **铸币阶段**：行动完成后铸造激励（Phase p+x，x 由 Executor 决定）

### 3.2 执行合约阶段模型

各 Executor 从 `core.Phase.currentPhase()` 读取当前 Phase，并根据自己的阶段模型计算业务轮次。

**LP 行动执行合约**（3 阶段）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 铸币 Round = currentPhase() - 2

Phase 1、2 期间部分阶段尚未就绪，查询或操作对应 Round 时回滚 `RoundNotStarted`。Phase 3 起，LP 行动进入稳态运行。

**链群行动执行合约**（4 阶段）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

Phase 4 起，链群行动进入稳态运行。验证阶段在加入和铸币之间插入。

**链群服务行动执行合约**（4 阶段，与被服务的链群行动对齐）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

**链群服务验证复用机制**（关键设计）：

链群服务不单独执行验证，而是检查该服务 Proposal 关联的特定链群行动的验证结果。一个链群服务 Proposal 面向整个 `actionTokenAddress` 社区的所有链群行动，权重聚合来自所有相关链群行动，但验证状态检查针对每个链群行动独立进行。

```solidity
// 链群服务在铸币阶段查询关联链群行动的验证完成状态
// 铸币 Round p 对应验证 Round p
bool verified = linkGroupExecutor.isRoundVerified(actionTokenAddress, actionId, verifyRound);
```

**处理规则**：
- 关联的链群行动已完成验证 → 该链群行动的贡献计入服务激励权重计算
- 关联的链群行动未验证或验证失败 → 该链群行动跳过该轮次，不计入权重
- 链群服务不依赖链群行动的铸币完成，只检查验证完成

**设计理由**：
- 避免重复验证工作：链群行动已验证成员身份和贡献
- 权重数据来源一致：链群服务的权重计算基于链群行动的验证数据
- 阶段对齐：两者共享验证 Round，保持时间线一致性

### 3.3 冷启动期

**LP 行动**：
- Phase 1：只有投票(Round 1)
- Phase 2：投票(Round 2) + 加入(Round 1)
- Phase 3：投票(Round 3) + 加入(Round 2) + 铸币(Round 1) ← 第一批铸币

**链群行动和链群服务行动**：
- Phase 1：只有投票(Round 1)
- Phase 2：投票(Round 2) + 加入(Round 1)
- Phase 3：投票(Round 3) + 加入(Round 2) + 验证(Round 1)
- Phase 4：投票(Round 4) + 加入(Round 3) + 验证(Round 2) + 铸币(Round 1) ← 第一批铸币

第一批用户在 Phase 2 即可加入 LP 或链群行动。

---

## 4. 共同参与模型

- 行动参与主体统一为 MemberNFT 的 `memberId`；钱包地址只作为当前控制者
- 可复用行动状态至少按 `tokenAddress + actionId + round` 隔离
- **体验资产**按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账，归 Provider MemberNFT 所有
- 自有资产和体验资产可以同时存在；部分撤回只减少指定账本，不互相抵扣
- 加入阶段内的撤回直接更新该 Round 的参与权；加入阶段结束后，该 Round 的参与历史不再改变
- MemberNFT 转移不改变已发生的快照、投票、验证或已结算状态

---

## 5. LP 行动执行合约

### 5.1 保留逻辑（引用旧代码）

**时间权重计算**：参考 `LOVE20TKM/extension-lp/V2` 的时间扣减逻辑
```text
deduction_i = min(
    amount_i,
    amount_i × (joinBlock_i - joinPhaseStartBlock) / joinPhaseBlocks
)
effectiveAmount = joinedAmount - deduction
effectiveLpRatio = effectiveAmount × 1e18 / totalEffectiveAmount
```

**治理票上限**：参考 `LOVE20TKM/extension-lp/V2` 的 `govRatioMultiplier`
```text
govRatio = validGovVotes(memberId) × 1e18 / totalGovVotes
govRatioCap = govRatio × govRatioMultiplier / 1e18
effectiveRatio = min(effectiveLpRatio, govRatioCap)
mintReward = proposalReward × effectiveRatio / 1e18
```

其中 `effectiveLpRatio` 是经过时间权重扣减后的 LP 占比（见上述时间权重计算）。

### 5.2 关键变更

#### 阶段模型
- **旧**：固定 4 阶段（Vote、Join、Verify、Mint）
- **新**：3 阶段（投票、加入、铸币），无验证阶段

#### 激励铸造
- **旧**：逐人调用 Core Mint
- **新**：Executor 先经 ActionTarget 一次性铸造整个 Proposal 的 `proposalReward`，再按有效 LP 占比计算参与者激励

**铸造流程**：
1. Executor 通过 ActionTarget 调用 `mintProposalReward`
2. ActionTarget 调用 Core Mint
3. Core Mint 把全部 `proposalReward` 铸给 ActionTarget
4. ActionTarget 把全部金额转给 Executor
5. Executor 按参与者 `effectiveRatio` 分配

### 5.3 删除能力

- **V1 实现**：不迁移，只迁移 V2

---

## 6. 链群行动执行合约

### 6.1 保留逻辑（引用旧代码）

**17 组全局索引**：完全保留 `LOVE20TKM/action/GroupAction` 的索引结构

链群 Executor 以当前有效的 `tokenAddress + actionId + groupId + memberId` 参与关系为事实来源。必须维护下列 17 组跨其所有代币社区和链群行动的可枚举全局索引：

- Group ID：`gGroupIds`、`gGroupIdsByMemberId`、`gGroupIdsByTokenAddress`、`gGroupIdsByTokenAddressByMemberId`、`gGroupIdsByTokenAddressByActionId`
- Token Address：`gTokenAddresses`、`gTokenAddressesByMemberId`、`gTokenAddressesByGroupId`、`gTokenAddressesByGroupIdByMemberId`
- Action ID：`gActionIdsByTokenAddress`、`gActionIdsByTokenAddressByMemberId`、`gActionIdsByTokenAddressByGroupId`、`gActionIdsByTokenAddressByGroupIdByMemberId`
- Member ID：`gMemberIds`、`gMemberIdsByGroupId`、`gMemberIdsByTokenAddress`、`gMemberIdsByTokenAddressByGroupId`

每组索引都提供同名全量数组查询、追加 `Count` 的数量查询和追加 `AtIndex` 的单项查询。

**按 Round 参与历史**：参考 `LOVE20TKM/action/GroupAction` 的历史快照机制

链群 Executor 通过加入阶段内逐笔发生的加入、追加、体验加入、部分撤回和全部退出交易，自然形成每轮参与快照。同一 Round 内的多笔交易持续更新该 Round 的最终值，不为同一 Round 重复创建版本。整轮无人交互时自然继承上一轮状态，不需要复制或同步交易。

**公共验证者机制**：参考 `LOVE20TKM/action/GroupAction` 的候选申请、排名、分割线开放

候选申请只在投票阶段新增、撤销或修改。排名按累计候选票降序、`applicationId` 升序。分割线开放公式：
```text
openOffset = ceil(verifyPhaseBlocks × splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

**激励计算**：参考 `LOVE20TKM/action/GroupAction`
```text
groupReward = proposalReward × groupScore / totalGroupScore
memberReward = groupReward × memberScore / groupScore
```

其中 `groupScore` 和 `memberScore` 基于验证阶段确认的参与数据计算。

### 6.2 关键变更

#### 主体身份
- **旧**：`groupId` 可以是地址或 MemberNFT
- **新**：`groupId` 必须是 `memberId`，链群 owner 就是该 MemberNFT

#### 阶段模型
- **旧**：固定 4 阶段
- **新**：从 Core Phase 自行映射 4 阶段

#### 激励铸造
- **旧**：逐人调用 Core Mint
- **新**：Executor 通过 ActionTarget 一次性铸造整个 Proposal 激励，再内部分配

---

## 7. 链群服务行动执行合约

### 7.1 保留逻辑（引用旧代码）

**服务范围和聚合**：参考 `LOVE20TKM/action/GroupService`

一个链群服务 Proposal 面向整个 `actionTokenAddress` 社区的链群行动集合，不绑定单个源 `actionId`。该 Proposal 的 `tokenAddress` 记为 `serviceTokenAddress`。两者必须满足：
- `serviceTokenAddress == actionTokenAddress`，或
- `serviceTokenAddress` 是 `actionTokenAddress` 的直接父币

**权重计算**：参考 `LOVE20TKM/action/GroupService`

变量定义：
- `A[a]` = 链群行动 a 的总激励
- `r[a]` = 链群行动 a 的公共验证者比例（ratioForPublicVerifier）
- `T` = 所有相关链群行动的总激励之和
- `m` = memberId
- `ownerActionReward(a, m)` = 链群 owner m 在链群行动 a 中获得的激励（聚合该链群所有成员在该行动中的激励）

```text
verifierWeightNumerator(m) = Σ(A[a] × r[a])
    // 仅对 verifierId[a] == m 的行动累加

ownerWeightNumerator(m) = Σ(ownerActionReward(a, m) × (1e18 - r[a]))

theoreticalVerifierReward(m) = serviceReward × verifierWeightNumerator(m) / (T × 1e18)
theoreticalOwnerReward(m) = serviceReward × ownerWeightNumerator(m) / (T × 1e18)
```

**二次分配**：参考 `LOVE20TKM/action/GroupService`

链群 owner 当前持有人可以按 `serviceProposalId + actionId + groupId + round` 配置二次分配的 `recipientIds[]` 和 `ratios[]`。

### 7.2 关键变更

#### 去 gas 补偿
- **旧**：服务激励包含 gas 补偿部分
- **新**：服务激励不包含 gas 补偿

#### 100% 二次分配安全收敛
- **旧**：二次分配可能因舍入导致超额
- **新**：使用统一缩放比例，避免两次独立取整后超过实际预算

**改进计算**：
```text
theoreticalReward(m) = theoreticalVerifierReward(m) + theoreticalOwnerReward(m)

actualReward(m) = min(
    theoreticalReward(m),
    serviceReward × capRatio(m) / 1e18
)

// 统一缩放比例拆分（避免超额）
actualVerifierReward = actualReward × theoreticalVerifierReward / theoreticalReward
actualOwnerReward = actualReward - actualVerifierReward
```

公共验证者部分直接给实际锁定的验证者；链群 owner 部分按该 `groupId` 在各行动中的激励权重拆分，并按链群配置的接收主体和比例执行二次分配。二次分配时，先计算每个接收者的理论份额，再统一缩放确保总和不超过 `actualOwnerReward`。

---

## 8. 铸造闭环、事件和错误

### 8.1 铸造闭环

行动激励闭环固定为：`executor -> ActionTarget -> Mint -> ActionTarget -> executor`

Executor 一次铸造一个 Proposal 在该 Round 的全部行动激励，再在内部完成参与者、公共验证者和 owner 分配。只有关联 Executor 可以发起；任何失败都回滚，ActionTarget 不保留余额。

### 8.2 事件

至少发出：Proposal 关联、行动参与/撤回/退出、公共验证者申请和排名、验证批次/锁定/完成、行动激励铸造/销毁、服务分配和 `forceExit` 事件。

### 8.3 错误

至少拒绝：零地址或 EOA Executor、非 ActionTarget 回调、重复初始化、KV 长度不等、无效 Round、非 MemberNFT 控制者、未投票 Proposal、非法参与量、体验额度不足、非法候选或分割线、候选申请已失效、验证批次跳跃/重复、锁定后更换验证者、重复铸造，以及服务非法超额分配导致的下溢。

---

## 9. 验收场景

至少覆盖：

**ActionTarget**：
- 三类 Proposal 回调和原子回滚
- Proposal → Executor 映射
- 按 Round 查询（proposalIdsByExecutor、proposals）
- forceExit（只清除登记，不调用 Executor，不返还资产）

**LP 行动**：
- 时间加权、治理票上限和部分撤回
- 3 阶段映射（Phase 3 起进入稳态）

**链群行动**：
- 激活、配置更新、成员/体验参与
- 17 组链群全局索引的全量/Count/AtIndex 一致性
- 跨社区和跨行动关系
- 逐层清理、最后一次正常退出和 forceExit 状态边界
- 候选申请版本切换、排名平票、前 `n + 1` 开放
- 逐笔交易形成 Round 历史、同轮多次变更、空轮继承
- 验证批次连续性、NFT 转移续验
- 无候选/失联导致行动层激励为零
- 完整验证后的成员和链群激励

**链群服务**：
- 跨整个社区聚合、同币/父币服务
- 公共验证者比例、100% 二次分配和全精度舍入边界
