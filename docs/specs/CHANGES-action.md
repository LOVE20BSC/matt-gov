# Action 迁移变更清单

本文档列出 BSC Action 相对于 LOVE20TKM 旧协议的所有变更。保留项直接引用旧代码位置，避免重复描述。

---

## 迁移原则

1. **身份统一**：所有参与主体统一使用 MemberNFT 的 `memberId`
2. **时间灵活**：使用 Core Phase 作为时间基础，各 Executor 按自身固定规格映射业务阶段
3. **职责分离**：ActionTarget 只做框架，业务逻辑由各 Executor 实现
4. **随 NFT 转移**：体验资产和行动加入状态归属于 `memberId`，随 MemberNFT 转移

---

## 组件迁移矩阵

| 组件 | 状态 | 旧位置 | 新位置 | 核心变化 |
|------|------|--------|--------|----------|
| ActionTarget | 重构 | `LOVE20TKM/extension/src/ExtensionCenter.sol` | `action/ActionTarget.sol` | 统一行动 Target，新增 forceExit |
| LP 行动 | 重构 | `LOVE20TKM/extension-lp/src/ExtensionLp.sol`、`LOVE20TKM/extension-lp/src/ExtensionLpFactoryV2.sol` | `action/LPAction.sol` | 只迁移 V2，支持部分撤出 |
| GroupAction | 修改 | `LOVE20TKM/extension-group/src/ExtensionGroupAction.sol`、`LOVE20TKM/extension-group/src/GroupJoin.sol`、`LOVE20TKM/extension-group/src/GroupVerify.sol` | `action/GroupAction.sol` | 保留群 ID/成员 ID 索引，统一为 MemberNFT，新增公共验证者 |
| GroupService | 修改 | `LOVE20TKM/extension-group/src/ExtensionGroupService.sol`、`LOVE20TKM/extension-group/src/GroupRecipients.sol` | `action/GroupService.sol` | 保留聚合和 owner 二次分配 |

行动阶段与 Round 是 Action 的共享概念，见 [阶段模型](action/02-phase-model.md)，不是独立组件或合约。

---

## 1. ActionTarget（重构）

### 来源
- 旧 `LOVE20TKM/extension/src/ExtensionCenter.sol`
- 旧 `LOVE20TKM/extension/src/interface/IExtensionCenter.sol`

### ✅ 保留逻辑
- **Proposal → Executor 映射**：参考 `LOVE20TKM/extension/src/ExtensionCenter.sol` 的映射逻辑
- **加入/退出状态**：参考 `addAccount` / `removeAccount` 逻辑

### 🔄 关键变化

#### 统一 Target 身份
- **旧**：每个行动类型可能有独立的 Target
- **新**：所有行动类型统一使用 `ActionTarget` 作为 Proposal Target

#### Executor 保留项
- **保留项位置**：创建 KV 的第 `0` 项固定为 `executor`
- **最小长度**：`kvList.length` 必须 >= 1，第 0 项必须是 executor，其余项可选
- **格式**：`key = keccak256("executor")`，`value = abi.encode(executorAddress)`
- **校验**：`executorAddress` 必须是非零且包含合约代码的地址

#### 查询接口
- **新增**：`proposalIdsByExecutor(tokenAddress, round, executor)`
- **新增**：`proposals(tokenAddress, round)` 返回 `proposalIds[]` 和 `executors[]`
- **设计**：先从 Vote 读取本轮有投票的 Proposal，再筛选，不维护独立反向索引

### ➕ 新增能力

#### forceExit（应急退出）
- **入口**：`forceExit(tokenAddress, actionId, memberId)`
- **权限**：当前 MemberNFT 持有人
- **行为**：直接清除 ActionTarget 的加入状态并触发事件
- **限制**：不调用 Executor、不转移资产、不承诺资产返还
- **前端**：默认隐藏，只作为最后兜底

### 📍 实现参考
```
旧代码：LOVE20TKM/extension/src/ExtensionCenter.sol（接口定义）
保留：Proposal 映射、加入/退出状态
新增：forceExit、统一查询接口
```

---

## 2. 阶段模型（全新设计）

### 替代对象
- 旧版协议中硬编码的 4 阶段映射（Vote、Join、Verify、Mint）

### 核心设计

#### ActionTarget 框架层
定义所有行动类型的必经流程：
1. **投票阶段**：社区对行动 Proposal 投票（治理层 Phase p）
2. **加入阶段**：获得票的行动开放加入（Phase p+1）
3. **铸币阶段**：行动完成后铸造激励（Phase p+x，x 由 Executor 决定）

#### 各 Executor 固定映射

**LP 行动执行合约**（3 阶段）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 铸币 Round = currentPhase() - 2

Phase 3 起，LP 行动进入稳态运行。

**GroupAction Executor**（4 阶段）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2
- 铸币 Round = currentPhase() - 3

Phase 4 起，GroupAction 进入稳态运行。

**GroupService Executor**（4 阶段，与被服务的 GroupAction 对齐）：
- 投票 Round = currentPhase()
- 加入 Round = currentPhase() - 1
- 验证 Round = currentPhase() - 2（复用同轮次 GroupAction 的验证结果，详见 `action/02-phase-model.md`）
- 铸币 Round = currentPhase() - 3

### 为什么改变
- LP 行动不需要验证，3 阶段更高效
- GroupAction 需要验证，保留 4 阶段
- 阶段数和映射由各 Executor 当前规格固定；变更必须同步更新本文件、Executor 规格和验收场景

---

## 3. LP 行动执行合约（重构）

### 来源
- 旧 `LOVE20TKM/extension-lp` 仓库的 V2 实现

### ✅ 保留逻辑

#### 时间权重公式
参考 `LOVE20TKM/extension-lp/src/ExtensionLp.sol` 的时间扣减逻辑：
```text
deduction_i = min(
    amount_i,
    amount_i × (joinBlock_i - joinPhaseStartBlock) / joinPhaseBlocks
)
effectiveAmount = joinedAmount - deduction
```

#### 治理票上限
参考旧版的 `govRatioMultiplier` 和 `govRatioCap` 计算：
```text
govRatio = validGovVotes(memberId) × 1e18 / totalGovVotes
govRatioCap = govRatio × govRatioMultiplier / 1e18
effectiveRatio = min(effectiveLpRatio, govRatioCap)
```

### 🔄 关键变化

#### 主体身份
- **旧**：钱包地址
- **新**：`memberId`

#### 阶段模型
- **旧**：固定 4 阶段（Vote、Join、Verify、Mint）
- **新**：3 阶段（投票、加入、铸币），无验证阶段

#### 激励铸造
- **旧**：`ExtensionLp` 一次性领取行动激励，再在扩展内按成员结算
- **新**：Executor 通过 ActionTarget 一次性取得整笔 Proposal 激励，再内部分配

### ❌ 删除能力
- **V1 实现**：不迁移，只迁移 V2

### 📍 实现参考
```
旧代码：LOVE20TKM/extension-lp/src/ExtensionLp.sol、LOVE20TKM/extension-lp/src/ExtensionLpFactoryV2.sol
保留：时间权重公式、治理票上限
修改：主体身份、阶段映射、激励铸造流程
删除：V1 实现
```

---

## 4. GroupAction Executor（修改）

### 来源
- 旧 `LOVE20TKM/extension-group/src/ExtensionGroupAction.sol`
- 旧 `LOVE20TKM/extension-group/src/GroupJoin.sol`
- 旧 `LOVE20TKM/extension-group/src/GroupVerify.sol`

### ✅ 保留逻辑

#### 17 组全局索引
**完全保留**：参考 `LOVE20TKM/extension-group/src/GroupJoin.sol` 的全局索引结构

- Group ID：`gGroupIds`、`gGroupIdsByMemberId`、`gGroupIdsByTokenAddress`、`gGroupIdsByTokenAddressByMemberId`、`gGroupIdsByTokenAddressByActionId`
- Token Address：`gTokenAddresses`、`gTokenAddressesByMemberId`、`gTokenAddressesByGroupId`、`gTokenAddressesByGroupIdByMemberId`
- Action ID：`gActionIdsByTokenAddress`、`gActionIdsByTokenAddressByMemberId`、`gActionIdsByTokenAddressByGroupId`、`gActionIdsByTokenAddressByGroupIdByMemberId`
- Member ID：`gMemberIds`、`gMemberIdsByGroupId`、`gMemberIdsByTokenAddress`、`gMemberIdsByTokenAddressByGroupId`

每组索引都提供 `全量数组`、`Count`、`AtIndex` 查询。

#### 按 Round 参与历史
**保留逻辑**：参考 `LOVE20TKM/extension-group/src/GroupJoin.sol` 的历史快照机制

GroupAction Executor 通过加入阶段内逐笔发生的加入、追加、体验加入、部分撤回和全部退出交易，自然形成每轮参与快照。同一 Round 内的多笔交易持续更新该 Round 的最终值，不为同一 Round 重复创建版本；退出写入显式零值，供后续 RoundHistory 识别终止点。

#### 公共验证者机制
**BSC 新增**：旧 `LOVE20TKM/extension-group/src/GroupVerify.sol` 只作为连续批次和原始分校验的参考；候选申请、排名和分割线开放不沿用旧机制。

- 候选申请只在投票阶段新增、撤销或修改
- 排名按累计候选票降序、`applicationId` 升序
- 分割线开放：`openBlock = verifyPhaseStartBlock + ceil(verifyPhaseBlocks × splits[rank - 2] / 1e18)`

#### 激励计算
**BSC 调整**：所有成员按同一原始得分规则计算，全行动共用分母，不在 Group 内二次按比例分配：
```text
finalScore(memberId) = participationAmount(memberId) × originScore(memberId)
totalFinalScore = sum(finalScore across all GroupAction groups)
memberReward(memberId) = floor(proposalReward × finalScore(memberId) / totalFinalScore)
```

### 🔄 关键变化

#### 主体身份
- **旧**：`groupId` 已是 Group NFT ID；成员参与和服务领取仍使用地址
- **新**：群和成员都使用 `memberId`；`groupId` 即群主体的 MemberNFT，群 owner 是该 NFT 当前持有人

#### 阶段模型
- **旧**：固定 4 阶段
- **新**：GroupAction 按自身阶段规格固定映射 4 阶段（投票、加入、验证、铸币）；其他 Executor 采用各自规格的阶段划分

#### 激励铸造
- **旧**：`ExtensionGroupAction` 一次性领取行动激励，再在扩展内按成员结算
- **新**：Executor 通过 ActionTarget 一次性取得整笔 Proposal 激励，再内部分配

### 📍 实现参考
```
旧代码：LOVE20TKM/extension-group/src/ExtensionGroupAction.sol、LOVE20TKM/extension-group/src/GroupVerify.sol
保留：17 组索引、Round 历史、连续验证和原始分校验
修改：统一 MemberNFT、公共验证者、阶段映射、激励分配
```

---

## 5. GroupService Executor（修改）

### 来源
- 旧 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol`
- 旧 `LOVE20TKM/extension-group/src/GroupRecipients.sol`

### ✅ 保留逻辑

#### 服务范围和聚合
**保留逻辑**：参考 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol` 的聚合计算

一个 GroupService Proposal 面向整个 `actionTokenAddress` 社区的 GroupAction 集合。服务 Executor 在铸币阶段通过 ActionTarget 一次性取得 `serviceReward`，随后以该社区本轮全部 GroupAction 激励作为分母；源行动激励查询已包含其自身可结算条件，Service 不重复筛选。

#### 权重计算
**保留公式**：
```text
verifierWeightNumerator(m) = Σ(A[a] × r[a])
    // 仅累加 publicVerifierId[a] == m 的行动

ownerWeightNumerator(m) = Σ(groupReward(a, m) × (1e18 - r[a]))

theoreticalVerifierReward(m) = serviceReward × verifierWeightNumerator(m) / (totalGroupActionReward × 1e18)
theoreticalOwnerReward(m) = serviceReward × ownerWeightNumerator(m) / (totalGroupActionReward × 1e18)
```

`totalGroupActionReward` 统计 `actionTokenAddress` 社区本轮全部 GroupAction 激励，首次按 `actionTokenAddress + round` 计算并缓存。各角色分子为零时直接返回，不执行除法；分母为零时由 `burnRewardIfNeeded(round)` 销毁整笔服务激励。

#### 二次分配
**保留逻辑**：groupId 当前持有人可以按 `sourceTokenAddress + sourceActionId + groupId + round` 配置 `recipientIds[]` 和 `ratios[]`；查询轮次没有配置时沿用不晚于该轮的最近配置。

### 🔄 关键变化

#### 治理票上限
- **旧、新**：服务没有 gas 补偿
- **新**：仅 owner 激励受治理票占比上限；公共验证者激励不受上限约束
- owner 超额由 Executor 直接调用服务代币 `burn`，按 owner 单独记录

#### owner 二次分配
- **旧、新**：配置比例总和超过 `1e18` 时拒绝，正好 `1e18` 合法；逐项向下取整，舍入余数归 owner
- **新**：只分配 owner 激励；公共验证者激励直接给锁定的公共验证者

#### 同币或父币服务
- **旧、新**：支持 `serviceTokenAddress == actionTokenAddress`，或 `serviceTokenAddress` 是 `actionTokenAddress` 的直接父币

### 📍 实现参考
```
旧代码：LOVE20TKM/extension-group/src/ExtensionGroupService.sol、LOVE20TKM/extension-group/src/GroupRecipients.sol
保留：服务范围、权重计算、二次分配
修改：公共验证者直接分配、仅 owner 受治理上限和二次分配
```

---

## 6. 体验资产（修改）

### ✅ 保留逻辑
- 体验资产按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账
- 成员正常退出时，体验代币返还 Provider 当前持有人
- 自有资产和体验资产可以同时存在

### 🔄 关键变化

#### 部分撤回边界
- **旧**：只支持全部退出
- **新**：LP 和 GroupAction 均支持自有资产部分撤回；按各自聚合账本更新当前 Round，LP 的 `deduction` 按撤回比例向下取整，全额撤回沿用 V2 的 `exit` 清理。Provider 只能撤回体验代币；若该成员总参与量归零，合约自动触发该成员退出

#### forceExit 不处理资产
- **新增**：`forceExit` 只清除 ActionTarget 加入状态，不返还体验资产
- **边界**：后续正常退出或撤回应继续由 Executor 处理；其调用 ActionTarget.exit 时必须幂等成功

### 📍 实现参考
```
旧代码：LOVE20TKM/extension-group/src/GroupJoin.sol（体验资产逻辑）
保留：独立记账、归属 Provider
修改：撤回边界、forceExit 边界
```

---

## 删除组件

| 组件 | 原位置 | 删除原因 |
|------|--------|----------|
| LP V1 | LOVE20TKM/extension-lp（V1 历史实现，未迁移） | 只迁移 V2 |
| 地址主体接口 | 所有 Executor | 统一使用 memberId |

---

## 实现检查清单

实现时必须确认：

- [ ] 所有参与主体使用 `memberId`，不使用 `address` 作为长期键
- [ ] ActionTarget 是所有行动类型的统一 Target
- [ ] 创建 KV 的第 `0` 项固定为 `executor`
- [ ] LP 行动使用 3 阶段映射
- [ ] GroupAction 和 GroupService 使用 4 阶段映射
- [ ] 保留 GroupAction 的 17 组全局索引
- [ ] 按 Round 参与历史自然形成，不重复创建版本
- [ ] forceExit 只清除加入状态，不调用 Executor
- [ ] GroupService 仅 owner 激励受治理上限和二次分配
- [ ] 100% 二次分配不下溢，超比例配置被拒绝

---

## 验收边界

核心验收场景见 `action/08-testing.md` 和组织级 `docs/acceptance.md`。关键变更的专项验收：

1. **ActionTarget 映射**：Proposal → Executor 映射正确，查询接口返回本轮有投票的行动
2. **forceExit**：只清除 ActionTarget 加入状态，不调用 Executor，不返还资产
3. **LP 3 阶段**：Phase 3 起进入稳态，加入后下一 Phase 即可铸币
4. **GroupAction 4 阶段**：Phase 4 起进入稳态，验证在加入和铸币之间插入
5. **17 组全局索引**：跨社区和跨行动查询正确，全量/Count/AtIndex 一致性
6. **Round 历史**：同轮多次变更持续更新该 Round 最终值，空轮继承上一轮
7. **公共验证者**：排名平票、分割线开放、NFT 转移续验
8. **服务聚合**：跨整个社区聚合，同币/父币服务，100% 二次分配安全收敛
