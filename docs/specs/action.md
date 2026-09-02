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

组件依赖 `core` 的 `MemberNFT`、`Stake`、`Submit`、`Vote`、`Mint` 和 `Phase` 接口。核心只传递 Proposal 上下文和不透明 KV（Core 不解析业务字段，原样转发给 Target）；候选人、链群、LP、资产托管和服务分配由本代码库解释。

---

## 2. ActionTarget（统一框架）

**术语说明**：每个行动对应一个 Core Proposal。在 ActionTarget 和 Core 回调接口中使用 `proposalId`，在 Executor 业务逻辑和查询接口中使用 `actionId`。两者数值相同：`actionId = proposalId`。

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

**设计理由**：ActionTarget 是通用框架，不预设业务字段，仅通过 kvList[0] 约定获得 Executor 地址；其余 KV 由各 Executor 自行定义和解析。

**验证时机**：
ActionTarget 在 `onProposalCreated` 回调中验证：
- `kvList.length > 0`
- `kvList[0].key == keccak256("executor")`
- decode 后的 `executorAddress` 非零且包含合约代码
验证失败则回滚整个 Proposal 创建交易。

ActionTarget 以 `tokenAddress + proposalId` 为唯一键保存 Executor，把完整创建 KV 原样转发给 Executor。Executor 的三个回调只能通过 ActionTarget 转发，不接受外部直接调用。

**回调接口**：
```solidity
onProposalCreated(address tokenAddress, uint256 proposalId,
    bytes32[] keys, bytes[] values)
onProposalSubmitted(address tokenAddress, uint256 proposalId,
    uint256 submitterId, bytes32[] keys, bytes[] values)
onProposalVoted(address tokenAddress, uint256 proposalId,
    uint256 voterId, uint256 votes, bytes32[] keys, bytes[] values)
```

**回调接口参数说明**：key 使用 bytes32 便于链上索引和比较；value 使用 bytes 支持任意长度的 abi.encode 数据。

### 2.2 参与登记

ActionTarget 维护通用的"MemberNFT 是否参与某个行动"登记，供前端"当前已参与行动"列表和外部参与资格判断使用。

**设计边界**：
- ActionTarget 登记所有行动的参与关系（包括链群行动）
- 只登记参与关系，不持有资产
- 资产和业务状态由 Executor 维护
- 链群行动的额外业务逻辑（如链群归属）由链群 Executor 维护

**接口**：
- `isAccountJoined(tokenAddress, actionId, memberId)` — 沿用旧代码命名
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
- 用户调用后仍可能保留链群 Chat 资格（归属在链群 Executor）
- 要完全退出链群（包括 Chat），需通过链群 Executor 的正常退出流程
- 前端应明确提示这一差异，避免用户困惑

**对 Chat 资格的影响**：
- **代币社区/行动 Chat**：立即失去资格（资格检查通过 `ActionTarget.isAccountJoined()` 实现，forceExit 后立即失效）
- **链群 Chat**：不失去资格（资格检查通过链群 Executor 的 17 组归属索引实现，因此不受影响；详见 group-chat.md 第 7.1 节）

**限制**：
- ActionTarget 查询立即不再返回该参与记录
- Executor 的历史参与、资产和链群归属等业务状态均不更新
- 链群归属只在链群 Executor 的正常退出流程（成员完整退出链群在该社区的最后一个链群行动）中更新

### 2.4 查询

**按 Round 查询**（新增）：
1. `proposalIdsByExecutor(tokenAddress, round, executor)` 返回该 Executor 关联的 `proposalId[]`
2. `proposals(tokenAddress, round)` 返回本轮所有有投票且已关联 Executor 的 `proposalIds[]` 和一一对应的 `executors[]`

两类查询先从 `Vote` 读取本轮有投票的 Proposal，再按 Proposal ID 读取 ActionTarget 映射并筛选，不维护独立反向索引。"有投票"指 `Vote.votedCount(tokenAddress, proposalId) > 0`。

**设计理由**：不维护独立反向索引，避免状态同步开销，查询时动态筛选即可满足需求。

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

**冷启动期操作边界**：
- Phase 1：可以创建 Proposal 和投票（投票 Round 1），加入和铸币操作回滚 `RoundNotStarted`
- Phase 2：可以创建、投票（Round 2）和加入（Round 1），铸币操作回滚 `RoundNotStarted`
- Phase 3 起：LP 行动进入稳态运行，所有阶段就绪

**易混淆点**：加入 Round 和铸币 Round 是根据当前 Phase 计算的**业务轮次编号**，不是 Phase 编号本身。例如在 Phase 5 时，加入 Round = 4（参与者正在为 Round 4 加入），铸币 Round = 3（正在为 Round 3 的参与者铸币）。Phase 2 时 `currentPhase() - 1 = 1`，加入操作检查 `加入 Round >= 1` 通过，不会回滚。

**链群行动执行合约**（4 阶段）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

Phase 4 起，链群行动进入稳态运行。验证阶段在加入和铸币之间插入。

**冷启动期操作边界**：
- Phase 1：可以创建 Proposal 和投票（投票 Round 1），加入、验证和铸币操作回滚 `RoundNotStarted`
- Phase 2：可以创建、投票（Round 2）和加入（Round 1），验证和铸币操作回滚 `RoundNotStarted`
- Phase 3：可以创建、投票（Round 3）、加入（Round 2）和验证（Round 1），铸币操作回滚 `RoundNotStarted`
- Phase 4 起：所有阶段就绪

**易混淆点**：验证 Round 和铸币 Round 同样是**业务轮次编号**，不是 Phase 编号。Phase 3 时验证 Round = 1（正在为 Round 1 验证），Phase 4 时铸币 Round = 1（正在为 Round 1 铸币）。Phase 2 时 `currentPhase() - 1 = 1`，Phase 3 时 `currentPhase() - 1 = 2`，加入操作检查均通过，不会回滚。

**链群服务行动执行合约**（4 阶段，与被服务的链群行动对齐）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

**易混淆点**：链群服务的验证 Round 和铸币 Round 同样是**业务轮次编号**。链群服务在业务 Round p 的铸币阶段（对应 Phase p+3）查询链群行动业务 Round p 的验证结果（该验证在 Phase p+2 完成）。业务 Round 编号相同（都是 p），但对应的 Phase 不同（p+3 vs p+2）。

**链群服务验证复用机制**（关键设计）：

链群服务不单独执行验证，而是检查该服务 Proposal 面向的所有链群行动各自的验证结果。一个链群服务 Proposal 面向整个 `actionTokenAddress` 社区的所有链群行动，权重聚合来自所有相关链群行动，但验证状态检查针对每个链群行动独立进行。

**链群行动列表获取**：
链群服务通过 ActionTarget 查询获得该社区的所有链群行动：
```solidity
proposalIds = ActionTarget.proposalIdsByExecutor(actionTokenAddress, mintRound, chainGroupExecutor)
```
该查询返回指定 Round 在指定 Executor 下的所有 proposalId（即 actionId）。链群服务的业务 Round p 对应投票 Phase p，查询时传入 `mintRound`（业务 Round p）作为投票 Round 参数，获得在该 Round 投票的链群行动列表。

链群服务在业务 Round p 的铸币阶段（对应 Phase p+3）查询链群行动业务 Round p 的验证结果（该验证在 Phase p+2 完成）。业务 Round 编号相同（都是 p），但对应的 Phase 不同（p+3 vs p+2）：

```solidity
bool verified = groupActionExecutor.isRoundVerified(actionTokenAddress, actionId, mintRound);
```

**处理规则**：
- 关联的链群行动已完成验证 → 该链群行动的激励计入服务激励权重计算
- 关联的链群行动未验证或验证失败 → 该链群行动跳过该轮次，不计入权重
- 链群服务不依赖链群行动的铸币完成，只检查验证完成

**设计理由**：
- 避免重复验证工作：链群行动已验证成员的参与身份和行动得分
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

**术语定义**：
- **自有资产**：MemberNFT 以自己的代币参与行动，资产归自己所有
- **体验资产**：MemberNFT 使用 Provider MemberNFT 提供的代币体验行动，资产归 Provider 所有，按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账
- **Provider MemberNFT**：提供体验额度的 MemberNFT，资产所有者；体验成员退出或 Provider 代为退出时，体验资产返还 Provider

**核心规则**：
- 行动参与主体统一为 MemberNFT 的 `memberId`；钱包地址只作为当前控制者
- 可复用行动状态至少按 `tokenAddress + actionId + round` 隔离
- 自有资产和体验资产可以同时存在；部分撤回只减少指定账本，不互相抵扣
- 加入阶段内的撤回直接更新该 Round 的参与权；加入阶段结束后，该 Round 的参与历史不再更新
- **体验资产撤回规则**（新协议变更）：Provider 可部分或全部撤回体验资产；若撤回后参与者的总代币参与量变为 0，则触发参与者退出行动；若不为 0，则仅撤回体验资产，参与者不退出行动
- MemberNFT 转移不改变已发生的快照、投票、验证或已结算状态

---

## 5. LP 行动执行合约

### 5.1 保留逻辑（引用旧代码）

**时间权重计算**：参考 `LOVE20TKM/contracts/extension-lp/contracts/LpActionV2.sol` 的 `calculateTimeWeight` 函数
```text
deduction_i = min(
    amount_i,
    amount_i × (joinBlock_i - joinPhaseStartBlock) / joinPhaseBlocks
)
effectiveAmount = joinedAmount - deduction
effectiveLpRatio = effectiveAmount × 1e18 / totalEffectiveAmount
```

**治理票上限**：参考 `LOVE20TKM/contracts/extension-lp/contracts/LpActionV2.sol` 的 `govRatioMultiplier`

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

- **V1 实现**：旧版本已废弃，仅迁移 V2（当前生产版本）。V1 与 V2 的核心差异：V1 不支持时间权重扣减和治理票上限约束，V2 引入这两项机制以提升公平性和防止末期涌入

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

**设计理由**：链群 Executor 需支持跨社区和跨行动的全局查询（如"某成员参与的所有链群"、"某链群在所有社区的行动"、"某代币社区的所有链群"），因此维护多维度的可枚举索引。索引在加入/退出时同步更新，查询时无需扫描历史事件。

**按 Round 参与历史**：参考 `LOVE20TKM/action/GroupAction` 的历史快照机制

链群 Executor 通过加入阶段内逐笔发生的加入、追加、体验加入、部分撤回和全部退出交易，自然形成每轮参与快照。同一 Round 内的多笔交易持续更新该 Round 的最终值，不为同一 Round 重复创建版本。整轮无人交互时自然继承上一轮状态，不需要复制或同步交易。

**实现机制**：加入阶段内的每笔交易直接写入该 Round 的参与记录（mapping(round => mapping(groupId => mapping(memberId => ParticipationData)))）；查询时，若某 Round 无记录则回退查找上一轮记录，实现懒继承。退出时清除当前 Round 的记录，自然形成该 Round "未参与"的状态。

**公共验证者机制**：参考 `LOVE20TKM/action/GroupAction` 的候选申请、排名、分割线开放

候选申请只在投票阶段新增、撤销或修改。排名按累计候选票降序、`applicationId` 升序。分割线开放公式：
```text
openOffset = ceil(verifyPhaseBlocks × splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

**排名规则细节**：
- 排名依据：累计候选票（candidateVotes）降序为主序，applicationId 升序为次序
- 平票处理：candidateVotes 相同时，applicationId 较小的排名靠前（较早申请的优先）
- splits 数组长度为 `n-1`（n 为候选人数），`splits[0]` 对应第 2 名的开放时间占比
- 第 1 名在验证阶段开始时立即开放（openBlock = verifyPhaseStartBlock）
- 第 2 名及之后按 splits 数组计算开放时间，分段释放验证权限以激励候选竞争

**激励计算**：参考 `LOVE20TKM/action/GroupAction`

**变量定义**：
- `groupScore` = 该链群在该行动 Round 中的激励分配权重（所有成员的激励分配权重之和）
- `totalGroupScore` = 该行动 Round 中所有链群的激励分配权重总和
- `memberScore` = 该成员在该链群、该行动 Round 中的激励分配权重（该成员参与代币数量 × 原始验证得分）

**验证得分说明**：由公共验证者在验证阶段为每个成员评定（0-100），记录为 `originScore`；`memberScore = 参与代币数量 × originScore`。链群激励计算使用 originScore 结合参与代币数量，保持公平性。

**公式**：
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
- `groupReward(a, m)` = 链群 m 在链群行动 a 中获得的总激励（聚合该链群所有成员在该行动中的激励）

```text
verifierWeightNumerator(m) = Σ(A[a] × r[a])
    // 仅对 verifierId[a] == m 的行动累加

ownerWeightNumerator(m) = Σ(groupReward(a, m) × (1e18 - r[a]))

theoreticalVerifierReward(m) = serviceReward × verifierWeightNumerator(m) / (T × 1e18)
theoreticalOwnerReward(m) = serviceReward × ownerWeightNumerator(m) / (T × 1e18)
theoreticalOwnerRatio(m) = ownerWeightNumerator(m) / (T × 1e18)
```

**变量说明**：`verifierId[a]` = 链群行动 a 锁定的公共验证者 memberId。

**二次分配**：参考 `LOVE20TKM/action/GroupService`

链群 owner 当前持有人可以按 `actionTokenAddress + groupActionId + groupId + round` 配置二次分配的 `recipientIds[]` 和 `ratios[]`。

**配置键说明**：
- `actionTokenAddress`：链群行动所属的代币社区地址（即被服务的社区）
- `groupActionId`：链群行动的 actionId（在 actionTokenAddress 社区中）
- `groupId`：链群的 memberId（链群 owner 的 MemberNFT ID）
- `round`：业务 Round 编号（该链群在该链群行动的哪个 Round 获得的激励）

**设计理由**：二次分配配置基于链群行动而非链群服务 Proposal，因此所有对该链群行动进行激励的链群服务行动都会按同一配置进行二次分配。这避免了为每个服务 Proposal 单独配置的复杂性。

**分配参数**：
- `recipientIds[]`：接收二次分配激励的 memberId 数组
- `ratios[]`：对应的分配比例数组（总和可以 ≤ 1e18，表示部分分配；> 1e18 时会缩放）

### 7.2 关键变更

#### 去 gas 补偿
- **旧**：服务激励包含 gas 补偿部分
- **新**：服务激励不包含 gas 补偿

#### 100% 二次分配安全收敛
- **旧**：二次分配可能因舍入导致超额
- **新**：使用统一缩放比例，避免两次独立取整后超过实际预算

**改进计算**：

**变量定义**：
- `govRatioMultiplier(m)` = 该链群 m 的治理票占比倍数（链群行动 Proposal 创建时设置）
- `theoreticalOwnerRatio(m)` = 该链群 owner 的理论激励占比（基于权重计算，见第 7.1 节）
- `actualOwnerReward(m)` = 该链群的实际 owner 激励（受治理票约束）

**公式**：
```text
// 计算链群 owner 的治理票占比上限
govRatio(m) = validGovVotes(m) × 1e18 / totalGovVotes
govRatioCap(m) = govRatio(m) × govRatioMultiplier(m) / 1e18

// owner 激励占比取理论值和上限的较小值
ownerRatioCap(m) = min(theoreticalOwnerRatio(m), govRatioCap(m))

// owner 激励 = 整个服务激励 × owner 占比上限
actualOwnerReward(m) = serviceReward × ownerRatioCap(m) / 1e18
```

**设计理由**：
- 公共验证者激励基于服务工作量，不需要单独约束，由权重自然分配
- 链群 owner 激励代表链群的组织能力，应受治理参与度约束，避免治理票极低的链群获得过高激励
- 以整个服务激励（包含验证者部分）作为分母，简化计算逻辑，避免逐个计算验证者激励的复杂性和高 gas 成本

公共验证者部分直接给实际锁定的验证者；链群 owner 部分按该 `groupId` 在各行动中的激励权重拆分，并按链群配置的接收主体和比例执行二次分配。

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

---

## 8. 铸造闭环、事件和错误

### 8.1 铸造闭环

行动激励闭环固定为：`executor -> ActionTarget -> Mint -> ActionTarget -> executor`

Executor 一次铸造一个 Proposal 在该 Round 的全部行动激励，再在内部完成参与者、公共验证者和 owner 分配。只有关联 Executor 可以发起；任何失败都回滚，ActionTarget 不保留余额。

### 8.2 事件

至少发出：Proposal 关联、行动参与/撤回/退出、公共验证者申请和排名、验证批次/锁定/完成、行动激励铸造/销毁、服务分配和 `forceExit` 事件。

**核心事件定义**：
- `ProposalLinked(tokenAddress, proposalId, executor)`：Proposal 关联 Executor
- `ActionJoined(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)`：成员加入行动（自有或体验）
- `ActionWithdrawn(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)`：部分撤回
- `ActionExited(tokenAddress, actionId, memberId, round, isExperience, providerMemberId)`：全部退出
- `ForceExited(tokenAddress, actionId, memberId)`：应急退出（只清除 ActionTarget 登记）
- `VerifierApplied(tokenAddress, actionId, memberId, round, applicationId)`：公共验证者申请
- `VerificationBatchSubmitted(tokenAddress, actionId, groupId, round, batchIndex, scores[])`：验证批次提交
- `VerifierLocked(tokenAddress, actionId, round, memberId)`：验证者锁定
- `ActionRewardMinted(tokenAddress, actionId, round, totalAmount, recipientType)`：行动激励铸造（recipientType 区分成员/验证者/owner）
- `ServiceRewardDistributed(serviceTokenAddress, serviceProposalId, actionTokenAddress, memberId, verifierReward, ownerReward, round)`：服务激励分配
- `SecondaryDistributionConfigured(serviceTokenAddress, serviceProposalId, actionId, groupId, round, recipientIds[], ratios[])`：二次分配配置

### 8.3 错误

至少拒绝：零地址或 EOA Executor、非 ActionTarget 回调、重复初始化、KV 长度不等、无效 Round、非 MemberNFT 控制者、未投票 Proposal、非法参与量、体验额度不足、非法候选或分割线、候选申请已失效、验证批次跳跃/重复、锁定后更换验证者、重复铸造，以及服务非法超额分配导致的下溢。

**核心错误代码**：
- `InvalidExecutor()`：零地址、EOA 或无代码地址
- `UnauthorizedCallback()`：非 ActionTarget 调用 Executor 回调
- `NotMemberOwner(memberId)`：调用者不是该 MemberNFT 的当前持有人
- `ProposalNotVoted(tokenAddress, proposalId)`：Proposal 未获得投票或未达到激励门槛
- `InvalidRound(round)`：Round 不在当前允许的操作范围内（如在非加入阶段尝试加入）
- `InsufficientExperienceQuota(providerMemberId, required, available)`：体验额度不足
- `VerifierAlreadyLocked(tokenAddress, actionId, round)`：验证者已锁定，不能更换
- `BatchIndexMismatch(expected, actual)`：验证批次索引不连续
- `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)`：该成员在该 Round 的激励已铸造
- `DistributionOverflow(configured, available)`：二次分配配置的总比例超过可用激励

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
