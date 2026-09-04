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
- 名称重复检查：使用名称哈希（`keccak256`）存储已使用的名称，不存储完整字符串

Gas 成本在旧版实际部署中已验证可行，无需重新评估。

### 3.3 铸造费用

**公式**（保留旧版）：
```text
baseCost = unmintedSupply / baseDivisor
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost × multiplier ^ (bytesThreshold - byteLength)
```

`baseDivisor`、`bytesThreshold` 和 `multiplier` 均在部署时确定且必须大于零。`unmintedSupply` = 协议首个 LOVE20 代币的 `maxSupply - totalSupply`（即首个代币的未铸造量）。铸造费用使用协议首个 LOVE20 代币支付；铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`。

**计算示例**（假设参数：`baseDivisor = 1000`, `bytesThreshold = 8`, `multiplier = 2`, `unmintedSupply = 10000`）：
- `baseCost = 10000 / 1000 = 10 token`
- 铸造 "Alice"（5 bytes）：`mintCost = 10 × 2^(8-5) = 10 × 8 = 80 token`
- 铸造 "Bob"（3 bytes）：`mintCost = 10 × 2^(8-3) = 10 × 32 = 320 token`
- 铸造 "LongName"（8 bytes）：`mintCost = 10 token`（达到阈值，无倍数）
- 铸造 "VeryLongName"（12 bytes）：`mintCost = 10 token`（超过阈值，无倍数）

**短名称稀缺性**：名称越短，费用呈指数增长，激励用户使用较长名称。

**参考实现**：`LOVE20TKM/group/contracts/LOVE20Group.sol` 78-95 行

**铸造接口**：
```solidity
function mint(string memory name) external payable returns (uint256 memberId)
```

- **参数**：
  - `name`：成员名称，必须通过名称校验（第3.2节）
- **返回值**：
  - `memberId`：新铸造的 MemberNFT ID
- **支付**：
  - 使用协议首个 LOVE20 代币支付 `mintCost`
  - 从 `msg.sender` 转入并立即销毁
- **失败条件**：
  - 名称校验失败（长度、字符、重复等）
  - 代币余额不足或授权不足
  - 费用计算溢出

### 3.4 转移语义

MemberNFT 的转移不复制、不拆分、不重置任何历史。依赖身份的合约必须实时读取 `ownerOf(memberId)`，不能缓存钱包地址作为长期权限。MemberNFT 转移后，新持有人可以铸造尚未领取的治理激励、使用尚未消耗的发射次数、提取解锁期结束的解锁资产，以及继续控制当前质押状态。

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
- `sync()`：Submit 合约调用的校准入口

**sync() 接口**：
```solidity
function sync() external returns (bool adjusted, uint256 newPhaseBlocks)
```

- **权限**：只能由 Submit 合约调用
- **返回值**：
  - `adjusted`：本次调用是否调整了 Phase 长度（true = 调整了，false = 仅记录观测点未调整）
  - `newPhaseBlocks`：调整后的 Phase 区块数（如果 `adjusted == false`，返回当前的 `phaseBlocks`）
- **副作用**：
  - 总是追加当前观测点（`block.number` 和 `block.timestamp`）
  - 根据调整规则（第4.4节）决定是否调整未来 Phase 的长度
  - 如果调整，触发 `PhaseAdjusted` 事件

**Phase 同步时机**：
- ✅ 每轮首个推举：Submit 自动调用 `Phase.sync()`
- ❌ 投票时：不自动同步（依赖推举时的同步）
- ❌ 铸造时：不自动同步（已进入下一个 Phase）
- ❌ 外部调用：只有 Submit 合约可以调用

**设计理由**：
- 推举时同步确保下一轮的 Phase 参数更准确
- 避免每次投票都同步，节省 gas

**极端情况**：
如果某个 Round 没有推举，Phase 不会自动同步。由于 `sync()` 只能由 Submit 合约调用，只能等待下一个 Round 的首个推举触发同步。未同步不影响协议运行，只影响下一个 Phase 的长度校准。

**没有推举的 Round**：
- 仍然是有效的时间片（Phase N 对应治理 Round N）
- 由于没有 Proposal，该 Round 不产生投票和激励
- Phase 校准延迟到下一个有推举的 Round

### 4.4 动态校准

每次 `sync()` 都先追加当前观测点，即使不调整参数。校准使用满足 `currentBlock - observation.blockNumber >= currentPhaseBlocks` 的最近一条历史观测（`currentPhaseBlocks` 指当前的 `phaseBlocks` 值）；若最近观测点不满足，继续往前追溯直到找到满足条件的观测点；若没有观测点满足条件，则使用最早的观测点。

**调整规则**：
- 根据观测数据计算目标天数对应的区块数：`observedPhaseBlocks = elapsedBlocks × targetSeconds / elapsedSeconds`
- 计算与当前 `phaseBlocks` 的偏差：`deviation = |observedPhaseBlocks - currentPhaseBlocks| / currentPhaseBlocks`
- **触发调整的偏差阈值**：`±10%`
  - 偏差在 `±10%` 内时不调整
  - 偏差超过 `±10%` 时触发调整
- **单次调整幅度上限**：`±20%`
  - 如果 `observedPhaseBlocks` 在 `currentPhaseBlocks × [0.8, 1.2]` 范围内，使用计算值
  - 如果 `observedPhaseBlocks < currentPhaseBlocks × 0.8`，限制为 `currentPhaseBlocks × 0.8`
  - 如果 `observedPhaseBlocks > currentPhaseBlocks × 1.2`，限制为 `currentPhaseBlocks × 1.2`
- 尚未生成的 Phase 使用 `newPhaseBlocks`

已经生成的 Phase 不回写。

**调整示例**（假设 `targetDays = 1`，`targetSeconds = 86400`，`currentPhaseBlocks = 28800`）：

**场景 1：不调整（在 ±10% 内）**
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1087200（经过 87200 秒）
- `observedPhaseBlocks = 29000 × 86400 / 87200 ≈ 28747`
- 偏差：`|28747 - 28800| / 28800 ≈ 0.18%` < 10%
- **不调整**，保持 `phaseBlocks = 28800`

**场景 2：向下调整（Phase 过慢）**
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1100000（经过 100000 秒）
- `observedPhaseBlocks = 29000 × 86400 / 100000 = 25056`
- 偏差：`|25056 - 28800| / 28800 ≈ 13%` > 10% 且 ≤ 20%
- **调整为 25056 区块/Phase**（加快节奏）

**场景 3：向上调整（Phase 过快）**
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1075000（经过 75000 秒）
- `observedPhaseBlocks = 29000 × 86400 / 75000 = 33408`
- 偏差：`|33408 - 28800| / 28800 ≈ 16%` > 10% 且 ≤ 20%
- **调整为 33408 区块/Phase**（放慢节奏）

**场景 4：极端调整（超过 20% 上限）**
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1150000（经过 150000 秒）
- `observedPhaseBlocks = 29000 × 86400 / 150000 = 16704`
- 偏差：`|16704 - 28800| / 28800 ≈ 42%` > 20%
- **按 20% 上限调整为 28800 × 0.8 = 23040 区块/Phase**（渐进式调整）

**关键**：根据观测数据计算目标天数对应的区块数，与当前 phaseBlocks 对比，超出阈值则调整。

### 4.5 与治理 Round 的关系

**术语定义**：
- **治理 Round**：Core Submit 和 Vote 把 Phase N 一对一解释为治理 Round N
- **当前治理 Round**：`Phase.currentPhase()` 返回的 Phase 编号，即当前治理 Round 编号

核心 `Submit` 和 `Vote` 提供无参数的 `currentRound()`。创建、推举和投票只写入当前治理 Round；当 `Phase.currentPhase() > N` 时，治理 Round N 的 Vote 时间片结束，`Vote` 对外返回该 Round 已结束，核心激励可以准备和铸造。

---

## 5. Stake（重构）

### 5.1 核心变更

- **去凭证化**：不再产生 SL/ST ERC20 代币，状态直接存储在 Stake 合约
- **按 memberId 归属**：质押状态按 `tokenAddress + memberId` 隔离
- **统一解锁**：流动性质押和加速质押必须同时申请、同时等待、同时提取

### 5.2 状态变量

**按代币和成员隔离的质押状态**：
```solidity
mapping(address tokenAddress => mapping(uint256 memberId => StakeData)) stakes;

struct StakeData {
    uint256 lpShares;                    // LP 质押份额
    uint256 boostShares;                 // 加速质押份额（原 ST）
    uint256 promisedWaitingPhases;       // 承诺解锁期（Phase 数量）
    uint256 unlockRequestPhase;          // 解锁申请时的 Phase（0 = 未申请，≥1 = 已申请）
}
```

**按代币汇总的全局状态**：
```solidity
mapping(address tokenAddress => TokenStakeGlobals) globals;

struct TokenStakeGlobals {
    uint256 totalLpShares;               // 全局 LP 份额总量
    uint256 withdrawableLp;              // 上次结算后的可提取 LP 数量（基准值）
    uint256 feeLp;                       // 累积的手续费 LP 数量
    uint256 sqrtKOfLp;                   // 上次记录的 sqrt(k) 基准
    uint256 totalBoostShares;            // 全局加速质押份额总量
}
```

**状态变量说明**：
- `withdrawableLp`：每次质押/提取时更新的可提取 LP 基准，用于下次份额计算
- `feeLp`：累积的手续费 LP，不参与份额计算
- `sqrtKOfLp`：基于合约持有 LP 在 Pair 中占比计算的 sqrt(k) 值，用于判断手续费是否累积

### 5.3 保留逻辑（引用旧代码）

**流动性质押流程**：参考 `LOVE20TKM/core/src/LOVE20Stake.sol` 120-134 行

用户质押时提供双币（代币 + 父币），Stake 合约将双币转入并调用 Router 添加 LP，获得的 LP token 用于计算 LP 份额。提取时，Stake 合约移除 LP 并将双币返还用户。

**LP 份额计算**：参考 `LOVE20TKM/core/src/LOVE20SLToken.sol` 79-83 行
```text
sharesMinted = totalLpShares == 0
    ? lpMinted
    : totalLpShares × lpMinted / withdrawableLp
```

**手续费结算**：参考 `LOVE20TKM/core/src/LOVE20SLToken.sol` 256-289 行（sqrt(k) 方法）

**计算流程**：
1. 计算当前 sqrtK：`currentSqrtKOfLp = sqrt(reserve0 × reserve1) × totalLp / pairTotalSupply`
2. 如果 `currentSqrtKOfLp > previousSqrtKOfLp`（手续费累积）：
   - `newWithdrawableLp = previousWithdrawableLp × previousSqrtKOfLp / currentSqrtKOfLp`
   - `newFeeLp = totalLp - newWithdrawableLp`
3. 如果 `currentSqrtKOfLp ≤ previousSqrtKOfLp`（未累积手续费或异常情况），跳过手续费结算
4. 更新 `withdrawableLp`、`feeLp` 和 `sqrtKOfLp`

**边界保护**：
- `currentSqrtKOfLp = 0` 或 `pairTotalSupply = 0` 时跳过手续费结算（异常情况）
- `currentSqrtKOfLp ≤ previousSqrtKOfLp` 时跳过手续费结算（未累积或 LP 被移除导致的下降）

**手续费结算效果**：
- 手续费累积 → `withdrawableLp` 下降 → 每份额对应的可提取 LP 减少
- 新质押者用相同 LP 获得更多份额（通货膨胀机制）
- 已质押者的份额占比被稀释
- LP 交易产生的手续费增量不归旧质押者，归协议所有
- 旧质押者取回的双币数量与质押时提供的双币数量相同（无池价格变化时）

**手续费结算示例**：

**说明**：以下示例使用简化数值和向下取整，实际实现遵循 Solidity 整数除法规则。

**初始状态**：
- A 质押 100 LP → 获得 100 份额
- `withdrawableLp = 100`, `sqrtKOfLp = sqrt(k1)`, `totalLpShares = 100`

**Pair 累积手续费**：
- Reserve 增长，`sqrt(k2) = 1.05 × sqrt(k1)`（增长 5%）
- 合约仍持有 100 LP，但 LP 价值增加了（包含手续费增量）

**B 质押 100 LP**：
1. 手续费结算：
   - `newWithdrawableLp = 100 × sqrt(k1) / sqrt(k2) = 100 / 1.05 ≈ 95.24`
   - `newFeeLp = 100 - 95.24 = 4.76`
   - 更新：`withdrawableLp = 95.24`, `feeLp = 4.76`, `sqrtKOfLp = sqrt(k2)`

2. B 铸造份额：
   - `sharesMinted = 100 × 100 / 95.24 ≈ 105`
   - B 获得 **105 份额**（比 A 多 5%）
   - 更新：`withdrawableLp = 95.24 + 100 = 195.24`, `totalLpShares = 205`

3. 最终状态：
   - 总 LP：200（包含手续费增量），可提取 LP：195.24，协议 feeLp：4.76
   - A 占 100/205 ≈ 48.78%，可提 195.24 × 100 / 205 ≈ 95.24 LP（对应质押时的双币数量）
   - B 占 105/205 ≈ 51.22%，可提 195.24 × 105 / 205 ≈ 100 LP（对应质押时的双币数量）
   - 协议累积 `feeLp = 4.76`（对应手续费增量）

**关键**：通货膨胀机制确保新旧质押者都能取回质押时提供的双币数量（无池价格变化时），手续费增量归协议所有。

**治理票公式**：
```text
govVotes = lpShares × promisedWaitingPhases
```

**治理票计算时机**：
- 治理票**实时计算**，不快照
- 投票时，Vote 合约调用 Stake 合约读取当前的 `lpShares` 和 `promisedWaitingPhases` 计算治理票
- 每次质押追加、解锁申请都会改变治理票（通过改变 `lpShares` 或 `promisedWaitingPhases`）

### 5.4 加速质押（保留旧版机制）

加速质押在旧版和新版都参与治理激励的加速部分分配（见第 7.3 节）。

加速质押不产生治理投票权，但参与投票激励。流动性质押产生治理投票权，并参与投票激励（对应旧版"验证激励"）分配。两类质押可以同时存在，共享解锁生命周期。

**投票记账**（保留旧版逻辑）：参考 `LOVE20TKM/core/src/LOVE20Stake.sol` 的 `_cumulatedTokenAmountByAccount` 机制

旧版按 round 维护每个 account 的累计加速质押代币数量（`_cumulatedTokenAmountByAccount[tokenAddress][round][account]`），新版改为按 memberId 维护累计加速质押份额（`cumulatedBoostShares[tokenAddress][round][memberId]`）。记录时机和逻辑保持一致：
- 进入新 round 时，复制上一轮的累计值作为本轮起点
- 加速质押增减时，直接更新当前 round 的累计值
- 投票时读取当前 round 的累计值参与激励计算
- 没有加速质押变动时，累计值自然继承上一轮
- 解锁申请后不能再追加质押，累计值不再更新

**累计值读取逻辑**（保留旧版）：
- 读取指定 Round 的累计值时，如果该 Round 未记录（mapping 默认值为 0），则查找该 Round **之前最近的有记录的 Round**，返回那个 Round 的累计值
- 这确保了解锁申请后，后续所有 Round 都能读取到**解锁申请时的累计值**
- 参考实现：`LOVE20TKM/core/src/LOVE20Stake.sol` 335-359 行的 `cumulatedTokenAmountByAccount` 函数

**累计值继承示例**（无手续费场景）：
- **Round 4**：成员 A 提供 100 代币 + 100 WBNB 添加 LP（无手续费时获得 100 LP 份额），同时加速质押 50 代币
  - Round 4 累计加速质押 = 50 代币
- **Round 5 开始**：A 追加提供 50 代币 + 50 WBNB 添加 LP（无手续费时获得 50 LP 份额），同时加速质押 30 代币，承诺解锁期保持或增加
  - 首次操作时，复制 Round 4 累计值：50 代币
  - 追加后更新 Round 5 累计值：80 代币
- **Round 5 投票**：读取 Round 5 累计加速质押（80 代币）参与激励计算
- **Round 6 开始**：A 无操作，Round 6 累计值自然继承 Round 5 的 80 代币
- **Round 7**：A 申请解锁，解锁申请后不能再追加质押，Round 7 的累计值保持为 80 代币
- **Round 8**：A 仍在解锁期内，无法追加质押
  - 读取 Round 8 累计值：未记录，查找最近的有记录 Round（Round 5），返回 80 代币
- **Round 9**：读取 Round 9 累计值，同样返回 80 代币（继承机制）


### 5.5 统一解锁和提取

**流程**（新设计）：
1. 当前 MemberNFT 持有人发起统一解锁申请
2. 申请立即清零治理票，禁止追加质押和融合
3. 申请绑定 `memberId`、申请时 Phase 和解锁期；MemberNFT 转移不重置倒计时
4. 经过 `promisedWaitingPhases` 个底层 Phase 后，当前持有人一次性提取 LP 对应的两种资产和加速质押代币
5. 解锁期结束后，当前 MemberNFT 持有人（可能已不是申请时的持有人）有权提取全部资产

**解锁状态查询**：
- Stake 合约提供查询接口，返回解锁申请状态（申请时 Phase、承诺解锁期、是否可提取）
- MemberNFT 持有人或潜在买家可以查询任意 `memberId` 在任意代币的解锁状态
- MemberNFT 转移是 ERC721 标准行为，Stake 合约不限制解锁中的 NFT 转移

### 5.6 融合（新增）

**设计意图**：质押融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让这些资产可以通过 MemberNFT 作为载体进行场外交易。

**约束**：
- 源、目标 MemberNFT 必须不同且都已存在
- 调用者只需控制源 MemberNFT，不要求控制目标 MemberNFT
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 来源质押必须未投票且未解锁
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

**禁止融合的情况**：
- 任一方存在待处理解锁申请（`unlockRequestPhase != 0`）
- 当前治理 Round 中源 MemberNFT 已经发生非零投票
- 目标质押的承诺解锁期（`promisedWaitingPhases`）小于源质押的承诺解锁期

**承诺解锁期约束说明**：
- 如果目标没有质押（`promisedWaitingPhases = 0`），融合后目标使用源的承诺解锁期
- 如果目标有质押但解锁期更短，拒绝融合（防止通过融合缩短承诺解锁期，绕过锁定约束）
- 如果目标解锁期 ≥ 源解锁期，允许融合（不会降低承诺）

**禁止融合的设计理由**：

**1. 源已投票禁止融合 → 防止重复计票**

**问题场景**：
- 源 NFT 有 100 LP 份额，投票 100 票给 Proposal A
- 源融合到目标 NFT
- 目标 NFT 现在有源的 100 LP 份额，再投票又投出 100 票
- **结果**：同一份质押资产产生了两次投票（源的历史投票 + 目标的新投票），重复计票

**2. 解锁申请中禁止融合 → 防止治理权复活**

**问题场景**：
- 源 NFT 有 100 LP 份额，申请解锁（治理票立即清零）
- 源融合到目标 NFT
- 目标 NFT 获得源的 100 LP 份额，重新产生治理票
- **结果**：已解锁（治理票为 0）的质押通过融合"复活"了治理权，绕过解锁限制

**3. 为什么目标已投票不影响融合**

目标已投票后接收融合不会重复计票：
- 目标的历史投票基于融合前的份额（如 50 LP → 50 票）
- 源的份额转入（如 100 LP）后，目标总份额变为 150 LP
- 如果目标后续再投票，按投票增量机制：增量 = 150 - 50 = 100 票
- 增量正好对应源转入的份额，**不重复计票**

**用户影响**：
- 源 MemberNFT 在本轮投票前可自由融合
- 源 MemberNFT 投票后需等到下一轮才能融合
- 目标 MemberNFT 是否投票不影响融合
- 任一方有解锁申请时，必须等待解锁期结束并完成提取后才能融合

**融合接口**：
```solidity
function mergeStake(
    address tokenAddress,
    uint256 sourceMemberId,
    uint256 targetMemberId
) external
```

- **参数**：
  - `tokenAddress`：要融合的代币地址
  - `sourceMemberId`：来源 MemberNFT ID（调用者必须是其持有人）
  - `targetMemberId`：目标 MemberNFT ID（必须存在，但调用者不需要持有）
- **效果**：
  - 将 `sourceMemberId` 在该代币的全部质押状态转移到 `targetMemberId`
  - LP 质押份额、加速质押份额、承诺解锁期合并到目标
  - 源质押清零
- **失败条件**：
  - 调用者不是 `sourceMemberId` 的持有人
  - `targetMemberId` 不存在
  - 任一方存在待处理解锁申请（`unlockRequestPhase != 0`）
  - 当前治理 Round 中源 MemberNFT 已投票
  - 目标的 `promisedWaitingPhases` 小于源的 `promisedWaitingPhases`

**融合后的状态等价性**：
- 融合后的质押状态与原始质押流程等价
- 提取时，Stake 合约按目标 MemberNFT 的份额比例移除 LP，正常返还双币
- 加速质押代币也正常返还

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

**变更**：主体身份 `address` → `memberId`

### 6.4 投票（保留逻辑）

**参考实现**：`LOVE20TKM/core/contracts/Vote.sol`

**保留**：
- 投票增量机制（同一 Round 可多次投票）
- Proposal Target 回调机制
- 批量投票原子性

**投票增量机制说明**：
- 本轮首次投票时，记录 LP 份额快照和加速质押份额快照
- 后续再次投票时，增量 = 当前份额 - 首次快照份额
- 两个快照独立维护，详见第 5.4 节

**变更**：主体身份 `address` → `memberId`

---

## 7. Mint（修改）

### 7.1 轮次激励池（修改）

**参考实现**：`LOVE20TKM/core/contracts/Mint.sol`

**保留**：
```text
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
govReward = available × ROUND_REWARD_GOV_RATIO / 1e18
proposalReward = available × ROUND_REWARD_PROPOSAL_RATIO / 1e18
```

Proposal 激励门槛：
```text
proposalVotes > 0
proposalVotes × 1e18 >= totalVotes × PROPOSAL_REWARD_MIN_VOTE_RATIO
```

**轮次激励池准备逻辑**（新增优化）：
- `prepareRewardIfNeeded(tokenAddress, round)` 可由任何地址调用（保持旧版函数命名）
- 通常在 Round 结束后首次铸造前调用
- 首次铸造时如果未准备则回滚，提示调用者先准备激励池
- 准备时检查 `totalVotes`（Vote 合约的 `votesNum[tokenAddress][round]`）：
  - **如果 `totalVotes = 0`**：不预留激励，`govReward[tokenAddress][round] = 0`，`proposalReward[tokenAddress][round] = 0`，`rewardReserved` 不增加
  - **如果 `totalVotes > 0`**：
    - 按公式计算 `govReward` 和 `proposalReward`
    - 检查 `stakedAmountOfVoters[tokenAddress][round]`（该 Round 所有投票者的加速质押代币累计总量，由 Vote 合约维护）：
      - 如果为 0，将加速激励部分（`govReward / 2`）立即计入 `rewardBurned`，治理激励池实际只预留 `govReward / 2`
      - 如果大于 0，正常预留完整 `govReward`
    - 累加到 `rewardReserved`
- 准备操作是幂等的：重复调用已准备的 Round 直接返回，不重复预留

### 7.2 Proposal 激励铸造（保留逻辑）

**参考实现**：`LOVE20TKM/core/contracts/Mint.sol`

每个 Proposal 由其 `target` 单独铸造一次：
```text
实际数量 = proposalReward × proposalVotes / eligibleProposalVotes
```

行动类 Proposal 由关联 Executor 调用 `ActionTarget`，再由 `ActionTarget` 以自身身份调用 `mintProposalReward`；ActionTarget 在同一交易中把全部实际数量转给 Executor。

### 7.3 治理激励（术语调整）

**治理池拆分**（保持旧版机制）：
- **投票激励部分**（50%）：按成员实际投票行为分配（对应旧版"验证激励"）
- **加速激励部分**（50%）：按加速质押份额占总加速质押的比例分配

**计算公式**：
```solidity
// 固定 50/50 拆分
votePoolAmount = govReward / 2
boostPoolAmount = govReward - votePoolAmount  // 避免舍入损失

// 投票激励
voteReward = (votePoolAmount * memberVotes) / totalVotes  // 向下取整

// 加速激励（有 2 倍上限）
theoreticalBoost = (boostPoolAmount * memberBoost) / totalBoost  // 向下取整
boostReward = min(theoreticalBoost, voteReward * 2)  // 基于投票激励的2倍上限
burnReward = theoreticalBoost - boostReward  // 溢出部分销毁
```

**关键特性**：
- 50/50 拆分是协议固定设计，使用整数除法简化计算
- `boostPoolAmount = govReward - votePoolAmount` 确保两池总和精确等于 `govReward`
- 2 倍上限是固定协议常量，不是部署参数
- `memberBoost` = 该 memberId 在投票时记录的加速质押份额（boostShares），计算和记账机制见第 5.4 节
- `totalBoost` = 本轮所有投票者的加速质押份额总和
- 若 `totalBoost == 0`，在该 Round 的首次治理激励铸造时，判断并将整个加速池一次性计入 `rewardBurned`
- 由于加速质押只在投票时记录（见第 5.4 节），如果某个 memberId 没有投票，则不会产生加速质押记录，因此不存在 `voteReward = 0` 但有 `boostReward` 的情况

**2 倍上限示例**（假设 `govReward = 1000 token`，`totalVotes = 100`，`totalBoost = 200`）：

**场景 1：未达上限**
- 成员 A：投票 10 票，加速质押 10 份额
- `voteReward = 500 × 10 / 100 = 50 token`
- `theoreticalBoost = 500 × 10 / 200 = 25 token`
- `boostReward = min(25, 50 × 2) = 25 token`（未达上限）
- `burnReward = 0`
- **A 总激励：75 token**

**场景 2：达到上限**
- 成员 B：投票 10 票，加速质押 100 份额
- `voteReward = 500 × 10 / 100 = 50 token`
- `theoreticalBoost = 500 × 100 / 200 = 250 token`
- `boostReward = min(250, 50 × 2) = 100 token`（达到上限）
- `burnReward = 250 - 100 = 150 token`（销毁）
- **B 总激励：150 token**（投票 50 + 加速 100）

**场景 3：无加速质押**
- 成员 C：投票 10 票，加速质押 0 份额
- `voteReward = 500 × 10 / 100 = 50 token`
- `theoreticalBoost = 0`
- `boostReward = 0`
- `burnReward = 0`
- **C 总激励：50 token**（仅投票激励）

**上限设计理由**：防止极端加速质押占用过多激励，确保投票行为仍是核心贡献。

**批量铸造**（新增）：
- `mintGovRewards(tokenAddress, memberId, rounds[])`
- 按输入顺序逐轮执行，返回与 `rounds` 等长的三类激励结果数组
- 任一 Round 失败则整笔交易回滚

**单轮铸造失败条件**：
- Round 尚未结束（`Phase.currentPhase() <= round`）
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

**launchCredit 说明**：
- 发射阈值计算使用向上取整：`threshold = ceil((maxSupply - totalSupply) × launchRatio / 1e18)`
- 每次超过阈值时，计算整数发射次数：`count = floor(delta / threshold)`
- 余额 `delta % threshold` 累计到 `launchCredit[tokenAddress][memberId]`
- 后续继续累计，`launchCredit` 达到新的阈值时继续产生发射次数
- **融合时只转移整数次数，不转移 `launchCredit`**（源的 launchCredit 保留，用户应在融合前等待 launchCredit 转化为整数次数）

**launchCredit 累计示例**（假设 `maxSupply = 10000 token`，`launchRatio = 0.01 = 1e16`，`totalSupply` 初始为 0）：

**Round 1**：
- 成员 A 铸造 80 token 治理激励
- `threshold = ceil(10000 × 0.01) = 100 token`
- `delta = 80`，未达阈值
- `launchCredit[A] = 80`，`launchCount[A] = 0`

**Round 2**：
- 成员 A 铸造 50 token 治理激励
- `threshold = ceil((10000 - 80) × 0.01) = ceil(99.2) = 100 token`
- `delta = 50 + launchCredit[A] = 50 + 80 = 130`
- `count = floor(130 / 100) = 1`
- `launchCredit[A] = 130 % 100 = 30`，`launchCount[A] = 1`

**Round 3**：
- 成员 A 铸造 90 token 治理激励
- `threshold = ceil((10000 - 130) × 0.01) = ceil(98.7) ≈ 99 token`
- `delta = 90 + launchCredit[A] = 90 + 30 = 120`
- `count = floor(120 / 99) = 1`
- `launchCredit[A] = 120 % 99 = 21`，`launchCount[A] = 2`

**Round 4**：
- 成员 A 铸造 200 token 治理激励
- `threshold = ceil((10000 - 220) × 0.01) = ceil(97.8) = 98 token`
- `delta = 200 + launchCredit[A] = 200 + 21 = 221`
- `count = floor(221 / 98) = 2`（一次性跨越两个阈值）
- `launchCredit[A] = 221 % 98 = 25`，`launchCount[A] = 4`

**关键**：launchCredit 避免余额丢失，确保所有激励最终转化为发射次数。

**新增约束**：
- 每个社区最多产生 `maxLaunchCount` 次发射（部署时传入）
- 达到上限后，该社区不再产生新的发射次数，但已有的整数次数仍可融合转移和消耗

### 8.2 发射（保留流程）

**参考实现**：`LOVE20TKM/core/contracts/Launch.sol`

任何当前持有目标 MemberNFT 的钱包或合约都可以触发该社区子币发射，但必须消耗该成员的一次 `launchCount`。

分发合约由发射调用者决定，不同分发合约可实现各自的领取逻辑。分发合约接口没有通用定义，各自按需实现；建议至少提供 `claim(tokenAddress)` 接口和领取状态查询接口。

**发射安全性**：
- 使用重入保护（`nonReentrant`）
- 遵循检查-更新-交互顺序：
  1. 检查：验证 `launchCount[tokenAddress][memberId] > 0`、代币参数有效性等
  2. 更新：扣除 `launchCount[tokenAddress][memberId] -= 1`
  3. 交互：创建子币、铸造首批代币、调用 distributor
- 整个发射流程原子性：如果分发合约调用失败（`revert`），整个交易回滚，子币创建不成功，发射次数不消耗
- 发射者需自行验证 distributor 合约的可靠性，承担 gas 耗尽等风险

### 8.3 发射次数融合（新增）

**接口**：
```solidity
function mergeLaunchCount(
    address tokenAddress,
    uint256 sourceMemberId,
    uint256 targetMemberId,
    uint256 count
) external
```

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
6. 首个代币/WBNB Pair 的创建或确认（如果 Pair 已存在则使用已存在的 Pair，否则通过 Factory 创建新 Pair）

任一步失败则整个启动回滚。启动成功后该路径永久关闭，不能创建第二个首个代币或改写其父币和分发结果。

**MemberNFT 铸造时序**：
- MemberNFT 合约在启动时部署，但不自动铸造任何 NFT
- 用户需要从 Airdrop 合约领取首个 LOVE20 代币后，才能调用 `MemberNFT.mint()` 支付铸造费用来铸造 MemberNFT
- 铸造费用基于首个代币的未铸造量计算（见第3.3节）

### 9.2 Airdrop 依赖

**部署主体和时序**：
- Airdrop 合约由 **`LOVE20TKM/burn` 代码库** 负责，在 **Burn 活动结束后** 单独部署到 BSC
- Burn 业务合约**不迁移**到 LOVE20BSC 组织
- Airdrop 合约地址作为 BSC 新协议首个代币的 `distributor` 外部依赖
- `LOVE20TKM/burn` 仓库保持只读，只作为 Airdrop 合约的来源和部署依据

BSC 首个代币的初始分发来源：

1. Airdrop 合约记录旧协议（Thinkium）参与者通过销毁活动获得的份额
2. Core 合约部署时，首个代币铸造后直接发送到已部署的 Airdrop 合约地址
3. 参与者按份额从 Airdrop 合约领取

**Airdrop 合约特性**：
- 支持任意 ERC20 代币的分发，不绑定特定代币
- 份额按代币独立记录：某代币领取后该份额即消耗，即使该代币后续余额增加也不能重复领取
- 未领取份额对应的代币余额归属于剩余未领取者

**来源可追溯性**：部署记录必须公开指向 `LOVE20TKM/burn` 的：
- [`Airdrop.sol`](https://github.com/LOVE20TKM/burn/blob/main/src/Airdrop.sol) — 合约源码
- [`DeployAirdrop.s.sol`](https://github.com/LOVE20TKM/burn/blob/main/script/DeployAirdrop.s.sol) — 部署脚本
- [`airdrop-design.md`](https://github.com/LOVE20TKM/burn/blob/main/docs/airdrop-design.md) — 设计文档
- 实际使用的 Burn 提交哈希、来源区块、Merkle Root 和已部署的 Airdrop 地址

这使任何人都可以验证首个代币分发的合法性和公平性。

---

## 10. 事件、错误和验收

### 10.1 事件

事件至少覆盖：MemberNFT 铸造/转移、质押/解锁/提取/融合、Phase 生成/同步、Proposal 创建/推举/投票、激励准备/铸造/销毁、发射额度和次数增加/融合/消耗、子币创建/分发、Pair 手续费结算和销毁。

事件主键使用 `tokenAddress`、`memberId`、`proposalId`、`round`。

### 10.2 错误

以下情况必须回滚：无效成员或来源控制者、零地址 Target/Distributor、非法模式、KV 长度不等、Proposal 或推举重复、投票超额、Round 未结束或未准备、重复铸造/销毁、批量治理激励中存在任一无效 Round、待解锁时追加或融合、解锁期不足、跨社区次数操作、发射次数不足或超社区上限、外部 Pair/Router 调用失败和任何 Target 回调失败。

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
