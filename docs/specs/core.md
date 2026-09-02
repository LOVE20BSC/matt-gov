# LOVE20BSC Core 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义 BSC Core 的协议行为。**保留旧逻辑的部分直接引用旧代码位置**，避免重复描述。详细变更清单见 [`CHANGES-core.md`](./CHANGES-core.md)。

---

## 1. 协议模型

LOVE20 是社群铸币协议。每个 LOVE20 代币都有一个 `parentTokenAddress`。首个 LOVE20 代币的父币是公链原生代币的封装代币（BSC 为 WBNB）；该封装代币是协议树外的根父币，不是由 LOVE20 创建的代币。后续子币的父币是已登记的 LOVE20 代币。代币供应受 `maxSupply` 限制，协议按治理规则持续铸造激励；代币和治理状态全部在链上维护。

核心治理层包含：

- `MemberNFT`：统一参与身份（合并旧 LOVE20Group）
- `Stake`：治理质押、加速质押、LP 份额和手续费结算
- `Submit`：Proposal 创建和推举
- `Vote`：治理投票及 Proposal Target 回调
- `Mint`：轮次激励准备、治理激励和 Proposal 激励铸造
- `Phase`：无语义的动态时间片时间线（全新设计）
- `LOVE20Token`、`TokenFactory`：代币树和代币实例创建
- `Launch`：基础子币发射次数账本、次数融合、次数消耗和首批代币分发

核心不解释任何具体 Proposal 扩展的业务字段。扩展只通过 Proposal Target 的通用接口接入。

---

## 2. 参与主体与通用约束

- **所有业务主体都是 MemberNFT**，以 `memberId` 作为不可变身份主键。钱包地址只是当前控制者或交易调用者。
- `author`、`submitterId`、`voterId` 以及需要主体身份的其他参数均为 `memberId`。
- 减少或处分某个 MemberNFT 的资产、权益或业务状态时，必须验证 `MemberNFT.ownerOf(memberId) == msg.sender`；明确为单向融合目标的 MemberNFT 只增加状态，不要求由调用者持有。
- **MemberNFT 转移只改变当前控制者**，不改变身份、历史投票、快照、已结算激励或历史事件；当前未铸造权益由新控制者继续操作。

**MemberNFT 转移后的权益归属**：

历史状态不变：
- ✅ 已发生的质押、投票、发射历史记录不变
- ✅ 已记录的治理激励份额不变

当前权益转移：
- ✅ 尚未领取的治理激励：新持有人可铸造
- ✅ 尚未消耗的发射次数：新持有人可使用
- ✅ 进行中的解锁申请：倒计时继续，新持有人提取
- ✅ 当前质押状态：新持有人控制

示例：
- 旧持有人 Alice 在 Round 5 投票，获得 100 token 激励份额
- Alice 将 MemberNFT 转给 Bob
- Bob 可以调用 `mintGovReward(memberId, round=5)` 领取这 100 token
- Bob 还可以使用该 memberId 的剩余发射次数

- Phase、治理 Round 和 MemberNFT 的有效编号从 `1` 开始；Proposal ID 由 `Submit` 单调分配并保持稳定，不把某个具体起始值当作通用哨兵。
- 比例采用 `1e18` 精度；按比例分配的整数金额默认向下取整，发射阈值明确使用向上取整。
- 每个核心合约完成一次初始化后，依赖地址和初始化参数不可替换；不存在升级管理员或协议级后门。
- 外部调用使用重入保护和检查-更新-交互顺序，任何失败都不得留下半完成状态。

---

## 3. MemberNFT（合并新增）

### 3.1 定位

`MemberNFT` 是协议唯一的通用身份 NFT。质押、Proposal、投票、发射次数和所有扩展参与关系均使用 `memberId` 关联；同一 MemberNFT 可以在多个代币社区拥有互相独立的状态。

- 合约名：`MemberNFT`
- ERC721 名称：`LOVE20 Member NFT`
- 符号：`Member`
- `memberId` 从 `1` 开始单调递增且永不复用；`0` 始终表示未设置

### 3.2 名称校验

**实现基线**：参考 `LOVE20TKM/group/contracts/LOVE20Group.sol` 的名称校验逻辑。

**BSC 版变更**：
- 最大长度：`64 bytes` → `32 bytes`（避免与钱包地址混淆）
- 其他 UTF-8 校验规则、ASCII 大小写不敏感、禁止字符类型保持一致

Gas 成本在旧版实际部署中已验证可行，无需重新评估。

### 3.3 铸造费用

**公式**（保留旧版）：
```text
baseCost = unmintedSupply / baseDivisor
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost × multiplier ^ (bytesThreshold - byteLength)
```

`baseDivisor`、`bytesThreshold` 和 `multiplier` 均在部署时确定且必须大于零。`unmintedSupply` = 尚未铸造的 MemberNFT 总量。铸造费用使用协议首个 LOVE20 代币支付；铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`。

**参考实现**：`LOVE20TKM/group/contracts/LOVE20Group.sol` 78-95 行

### 3.4 转移语义

MemberNFT 的转移不复制、不拆分、不重置任何历史。依赖身份的合约必须实时读取 `ownerOf(memberId)`，不能缓存钱包地址作为长期权限。MemberNFT 转移后，新持有人可以铸造尚未领取的治理激励、使用尚未消耗的发射次数、提取等待期结束的解锁资产，以及继续控制当前质押状态。

供应量和按持有人查询使用标准 `ERC721Enumerable` 接口。

---

## 4. Phase 与 Round（全新设计）

### 4.1 设计理念

`Phase` 只维护连续的无语义时间片，**不命名 Vote、Join、Verify、Mint 等业务阶段**，也不定义上层 Round。

- 底层时间基础设施：提供统一的时间分片
- 上层按需映射：Core 治理层、Action 行动层自行映射 Phase 到业务 Round

### 4.2 初始化参数

部署构造参数：
- `startBlock > 0`
- `initialPhaseBlocks > 0`
- `targetDays > 0`

第一个 Phase 编号为 `1`。

### 4.3 核心能力

**公开接口**：
- `currentPhase()`：当前区块对应的 Phase
- `phaseInfo(phaseNumber)`：阶段起始区块和阶段区块数
- `phaseAtBlock(blockNumber)`：指定区块的 Phase
- `syncObservationsCount()`、`syncObservation(observationId)`：同步观测数量和按 1-based ID 查询观测
- `sync()`：任何地址可调用的校准入口

**Phase 同步时机**：
- ✅ 每轮首个推举：Submit 自动调用 `Phase.sync()`
- ❌ 投票时：不自动同步（依赖推举时的同步）
- ❌ 铸造时：不自动同步（已进入下一个 Phase）
- ✅ 外部调用：任何地址可主动调用 `Phase.sync()`

**设计理由**：
- 推举时同步确保下一轮的 Phase 参数更准确
- 避免每次投票都同步，节省 gas

**极端情况**：
如果某个 Round 没有推举，Phase 不会自动同步。任何地址可以主动调用 `sync()`，或等待下一个 Round 的首个推举触发同步。未同步不影响协议运行，只影响下一个 Phase 的长度校准。

### 4.4 动态校准

每次 `sync()` 都先追加当前观测点，即使不调整参数。校准使用满足 `currentBlock - observation.blockNumber >= currentPhaseBlocks` 的最近一条历史观测。

**调整规则**：
- 计算 `observedPhaseSeconds = elapsedSeconds × currentPhaseBlocks / elapsedBlocks`
- 该值在 `targetSeconds` 的 `±10%` 内时不调整
- 超出范围时，尚未生成 Phase 使用 `newPhaseBlocks = max(1, elapsedBlocks × targetSeconds / elapsedSeconds)`

已经生成的 Phase 不回写。

### 4.5 与治理 Round 的关系

核心 `Submit` 和 `Vote` 把 `Phase N` 一对一解释为治理 `Round N`，并提供无参数的 `currentRound()`。创建、推举和投票只写入当前治理 Round；当 `Phase.currentPhase() > N` 时，治理 Round N 的 Vote 时间片结束，`Vote` 对外返回该 Round 已结束，核心激励可以准备和铸造。

---

## 5. Stake（重构）

### 5.1 核心变更

- **去凭证化**：不再产生 SL/ST ERC20 代币，状态直接存储在 Stake 合约
- **按 memberId 归属**：质押状态按 `tokenAddress + memberId` 隔离
- **统一解锁**：流动性质押和加速质押必须同时申请、同时等待、同时提取

### 5.2 保留逻辑（引用旧代码）

**LP 份额计算**：参考 `LOVE20TKM/core/contracts/Stake.sol` 154-184 行
```text
sharesMinted = totalLpShares == 0
    ? lpMinted
    : totalLpShares × lpMinted / withdrawableLpBefore
```

**手续费结算**：参考 `LOVE20TKM/core/contracts/Stake.sol` 248-276 行（sqrt(k) 方法）
```text
currentSqrtKOfLp = sqrt(reserve0 × reserve1) × previousLp / pairTotalSupply
newFeeLp = previousLp - newWithdrawableLp（当 currentSqrtKOfLp > previousSqrtKOfLp）
```

**治理票公式**：
```text
govVotes = lpShares × promisedWaitingPhases
```

### 5.3 加速质押（修改）

**旧版**：加速质押不参与激励分配  
**新版**：加速质押参与治理激励的加速部分分配（见第 7.3 节）

加速质押不产生治理投票权，但参与投票激励。流动性质押产生治理投票权，并参与投票激励（对应旧版"验证激励"）分配。两类质押可以同时存在，共享解锁生命周期。

**投票记账**（新增）：使用投票时快照
- 首次投票记录当时加速质押
- 同一 Round 后续再次投票时，只补记当前数量超过已记录数量的差额
- 没有后续投票时，单独增加的加速质押不进入本轮

解锁申请对加速质押记录的影响见第 7.3 节。

### 5.4 统一解锁和提取

**流程**（新设计）：
1. 当前 MemberNFT 持有人发起统一解锁申请
2. 申请立即清零治理票，禁止追加质押和融合
3. 申请绑定 `memberId`、申请时 Phase 和等待期；MemberNFT 转移不重置倒计时
4. 连续经过 `promisedWaitingPhases` 个底层 Phase 后，当前持有人一次性提取 LP 对应的两种资产和加速质押代币
5. 等待期结束后，当前 MemberNFT 持有人（可能已不是申请时的持有人）有权提取全部资产

### 5.5 融合（新增）

**设计意图**：质押融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让这些资产可以通过 MemberNFT 作为载体进行场外交易。

**约束**：
- 源、目标 MemberNFT 必须不同且都已存在
- 调用者只需控制源 MemberNFT，不要求控制目标 MemberNFT
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 来源质押必须未投票且未解锁
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

**禁止融合的情况**：
- 任一方存在待处理解锁申请
- 当前投票 Round 中源或目标任一方已经发生非零投票
- 目标等待期小于源等待期

**禁止融合的设计理由**：

"当前投票 Round 中源或目标任一方已经发生非零投票"时禁止融合：

**理由**：
- 防止投票权重转移：用户通过融合改变已投票的权重分布
- 保护治理公平性：避免投票后再调整票权归属
- 简化实现：无需处理投票后的权重合并和激励重新计算

**用户影响**：
- 用户在本轮投票前可自由融合
- 投票后需等到下一轮才能融合

源的 LP Shares 和加速质押单向并入目标，不能修改或取走目标原有资产。

---

## 6. Proposal（保留结构，修改 Target 规则）

### 6.1 数据结构

Proposal 由 `tokenAddress + proposalId` 定位。

**结构**（保留）：
- `ProposalHead`：`id`、`author`、`createAtBlock`
- `ProposalBody`：`title`、`details`；`title` 非空，`details` 可为空
- `target`：激励铸造接收主体
- `targetMode`：`NoCallback` 或 `Callback`

### 6.2 Target 模式（修改）

**零地址禁止**（新规则）：
- **旧版**：允许零地址（激励自动销毁）
- **新版**：Target 必须是非零 EOA 或合约
- **理由**：避免遗忘填写导致激励永久丢失

| target | targetMode | 行为 |
| --- | --- | --- |
| 非零 EOA | `NoCallback` | 合法，只接收铸造激励 |
| 非零合约 | `NoCallback` | 合法，不触发回调 |
| 非零合约 | `Callback` | 合法，创建/推举/投票均回调，空 KV 也回调 |
| EOA | `Callback` | 拒绝 |
| 零地址 | 任何 | 拒绝 |

如需销毁激励，应创建专用销毁合约（铸造后立即销毁），使意图显式化。

### 6.3 创建和推举（保留逻辑）

**参考实现**：`LOVE20TKM/core/contracts/Submit.sol`

**保留**：
- 推举门槛计算（SUBMIT_MIN_RATIO）
- 同一 Round 推举去重
- 每轮首个推举触发 `Phase.sync()`

**变更**：主体身份 `address` → `memberId`

### 6.4 投票（保留逻辑）

**参考实现**：`LOVE20TKM/core/contracts/Vote.sol`

**保留**：
- 投票增量机制（同一 Round 可多次投票）
- Proposal Target 回调机制
- 批量投票原子性

**变更**：主体身份 `address` → `memberId`

---

## 7. Mint（修改）

### 7.1 轮次激励池（保留逻辑）

**参考实现**：`LOVE20TKM/core/contracts/Mint.sol`

**保留**：
```text
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
govReward = available × ROUND_REWARD_GOV_RATIO / 1e18
proposalReward = available × ROUND_REWARD_PROPOSAL_RATIO / 1e18
```

准备时一次性增加 `rewardReserved` 并冻结本轮池子。Proposal 激励门槛：
```text
proposalVotes > 0
proposalVotes × 1e18 >= totalVotes × PROPOSAL_REWARD_MIN_VOTE_RATIO
```

### 7.2 Proposal 激励铸造（保留逻辑）

**参考实现**：`LOVE20TKM/core/contracts/Mint.sol`

每个 Proposal 由其 `target` 单独铸造一次：
```text
实际数量 = proposalReward × proposalVotes / eligibleProposalVotes
```

行动类 Proposal 由关联 Executor 调用 `ActionTarget`，再由 `ActionTarget` 以自身身份调用 `mintProposalReward`；ActionTarget 在同一交易中把全部实际数量转给 Executor。

### 7.3 治理激励（重要修改）

**治理池拆分**（新设计）：
- **投票激励部分**（50%，`GOV_VOTE_SHARE = 0.5e18`）：按成员实际投票行为分配（对应旧版"验证激励"）
- **加速激励部分**（50%，`GOV_BOOST_SHARE = 0.5e18`）：按加速质押份额占总加速质押的比例分配

**计算公式**：
```solidity
// 常量定义
uint256 constant GOV_VOTE_SHARE = 0.5e18;    // 50%
uint256 constant GOV_BOOST_SHARE = 0.5e18;   // 50%

// 激励计算
voteReward = govReward * GOV_VOTE_SHARE / 1e18 * memberVotes / totalVotes

theoreticalBoost = govReward * GOV_BOOST_SHARE / 1e18 * memberBoost / totalBoost
boostReward = min(theoreticalBoost, voteReward * 2)  // 基于投票激励的2倍上限
burnReward = theoreticalBoost - boostReward  // 溢出部分销毁
```

**关键特性**：
- 50%/50% 划分和 2 倍上限是固定协议常量，不是部署参数
- `memberBoost` = 该 memberId 在投票时记录的加速质押份额（boostShares），见第 5.3 节加速质押投票记账机制
- `totalBoost` = 本轮所有投票者的加速质押份额总和
- 若 `totalBoost == 0`，在准备该 Round 激励时（`prepareRoundReward`），整个加速池立即计入 `rewardBurned`

**批量铸造**（新增）：
- `mintGovRewards(tokenAddress, memberId, rounds[])`
- 按输入顺序逐轮执行，返回与 `rounds` 等长的三类激励结果数组
- 任一 Round 失败则整笔交易回滚

**单轮铸造失败条件**：
- Round 尚未结束（当前 Phase 尚未推进到该 Round 之后）
- Round 激励池未准备（未调用 `prepareRoundReward`）
- 该 memberId 在该 Round 没有投票记录
- 该 Round 该 memberId 的激励已铸造

**接口**：
```solidity
mintGovReward(tokenAddress, memberId, round) 
    returns (voteReward, boostReward, burnReward)

mintGovRewards(tokenAddress, memberId, rounds[]) 
    returns (voteReward[], boostReward[], burnReward[])
```

---

## 8. 基础子币发射（修改）

### 8.1 发射次数（按 memberId 记录）

**旧版**：`launchCount[tokenAddress][address]`  
**新版**：`launchCount[tokenAddress][memberId]`

**保留逻辑**（参考 `LOVE20TKM/core/contracts/Launch.sol`）：
- 阈值向上取整：`threshold = ceil((maxSupply - totalSupplyBeforeMint) × launchRatio / 1e18)`
- 累计和余额结转：`launchCredit` 保留整数除法余额

**新增约束**：
- 每个社区最多产生 `maxLaunchCount` 次发射（部署时传入）
- 达到上限后，该社区不再产生新的发射次数，但已有的整数次数仍可融合转移和消耗

### 8.2 发射（保留流程）

**参考实现**：`LOVE20TKM/core/contracts/Launch.sol`

任何当前持有目标 MemberNFT 的钱包或合约都可以触发该社区子币发射，但必须消耗该成员的一次 `launchCount`。

分发合约由发射调用者决定，不同分发合约可实现各自的领取逻辑。分发合约接口没有通用定义，各自按需实现；建议至少提供 `claim(tokenAddress)` 接口和领取状态查询接口。

### 8.3 发射次数融合（新增）

**接口**：`mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)`

**设计意图**：发射次数融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让发射次数可以通过 MemberNFT 作为载体进行场外交易。

**约束**：
- 源、目标必须是不同且已存在的 MemberNFT
- `count > 0`，调用者只需控制源 MemberNFT
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 发射次数转移不携带 `launchCredit`，只转移整数次数
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

成功后源次数减少、目标次数增加；目标原有次数及其他状态不减少，其他质押、投票、历史发射和事件不改变。

---

## 9. 首个代币部署（新增依赖）

### 9.1 启动路径

首个代币在部署 Core 合约时内部原子完成创建，不需要部署后再调用。`Launch` 仍是 `TokenFactory` 的唯一调用者。

**启动交易必须原子完成**：
1. Core 合约部署
2. 内部创建首个代币
3. 协议代币登记
4. 核心 `minter` 设置
5. 首批代币铸造并发送到 Airdrop 合约
6. 首个代币/WBNB Pair 的创建或确认

任一步失败则整个启动回滚。启动成功后该路径永久关闭，不能创建第二个首个代币或改写其父币和分发结果。

### 9.2 Airdrop 依赖

BSC 首个代币的初始分发来源：

1. 在 BSC 上部署 `LOVE20TKM/burn` 仓库的 `Airdrop.sol` 合约
2. Airdrop 合约记录旧协议（Thinkium）参与者通过销毁活动获得的份额
3. Core 合约部署时，首个代币铸造后直接发送到 Airdrop 合约
4. 参与者按份额从 Airdrop 合约领取

**Airdrop 合约特性**：
- 支持任意 ERC20 代币的分发，不绑定特定代币
- 份额按代币独立记录：某代币领取后该份额即消耗，即使该代币后续余额增加也不能重复领取
- 未领取份额对应的代币余额归属于剩余未领取者

**来源可追溯性**：正式部署必须在文档中公开指向：
- `LOVE20TKM/burn` 仓库的 `Airdrop.sol`
- `DeployAirdrop.s.sol` 部署脚本
- `airdrop-design.md` 设计文档

这使任何人都可以验证首个代币分发的合法性和公平性。

注：`LOVE20TKM` 只读约束是指在实现 BSC 迁移期间不修改旧仓库代码；部署 Airdrop 到 BSC 可以手动操作，不属于迁移工作流的一部分。

---

## 10. 事件、错误和验收

### 10.1 事件

事件至少覆盖：MemberNFT 铸造/转移、质押/解锁/提取/融合、Phase 生成/同步、Proposal 创建/推举/投票、激励准备/铸造/销毁、发射额度和次数增加/融合/消耗、子币创建/分发、Pair 手续费结算和销毁。

事件主键使用 `tokenAddress`、`memberId`、`proposalId`、`round`。

### 10.2 错误

以下情况必须回滚：无效成员或来源控制者、零地址 Target/Distributor、非法模式、KV 长度不等、Proposal 或推举重复、投票超额、Round 未结束或未准备、重复铸造/销毁、批量治理激励中存在任一无效 Round、待解锁时追加或融合、等待期不足、跨社区次数操作、发射次数不足或超社区上限、外部 Pair/Router 调用失败和任何 Target 回调失败。

### 10.3 验收场景

至少覆盖：

**MemberNFT**：
- NFT 转移后的权限连续性（历史不回写，当前未铸造权益由新持有人继续操作）
- 名称长度 32 bytes 边界
- 铸造费用短名称稀缺性

**Phase**：
- 空阶段和动态校准
- ±10% 内不调整，超出范围时计算新 phaseBlocks
- 首个推举自动 sync()

**Stake**：
- 统一解锁（流动性质押和加速质押同时申请、同时等待、同时提取）
- 向非调用者持有目标 NFT 的融合（只增加，不减少目标状态）
- LP 份额与手续费销毁统计
- PancakeSwap 兼容性
- 加速质押投票快照和补差

**Proposal**：
- 零地址 Target 拒绝
- Callback 原子性

**Mint**：
- Round 级准备与 Proposal 单项铸造
- 治理激励三段结果（voteReward, boostReward, burnReward）
- 投票增量补差
- 批量多轮铸造原子性

**Launch**：
- 发射阈值向上取整
- 多阈值跨越
- 社区 maxLaunchCount 上限
- 向非调用者持有目标 NFT 部分融合

**首个代币**：
- 一次性启动路径原子性
- Airdrop 依赖和分发验证
