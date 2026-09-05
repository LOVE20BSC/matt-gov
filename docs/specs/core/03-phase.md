# Phase 与 Round

本文档定义 Phase 时间片系统及其与治理 Round 的关系。

---

## 1. 设计理念

### 1.1 全新设计

**重要**：BSC 版 Phase 是完全重新设计的动态时间片系统，与旧版静态 Phase 完全不同。旧版 Phase (`LOVE20TKM/core/src/Phase.sol`) 只是简单的区块计数器（不可变的 `originBlocks` 和 `phaseBlocks`），新版增加了观测点记录和动态校准能力。**不要参考旧版 Phase.sol 实现**。

### 1.2 设计原则

`Phase` 只维护连续的无语义时间片，不命名业务阶段，也不定义上层 Round。

- 底层时间基础设施：提供统一的时间分片
- 上层按需映射：Core 治理层、扩展层自行映射 Phase 到业务 Round

---

## 2. 初始化参数

部署构造参数：
- `originBlocks > 0`
- `phaseBlocks > 0`（初始 Phase 区块数）
- `targetDays > 0`（目标天数，用于动态校准）

### 2.1 Phase 编号

**Phase 编号从 1 开始**：第一个 Phase 编号为 1，`block.number = originBlocks` 时处于 Phase 1。Phase 0 不存在，`0` 是哨兵值表示未设置。由于 Phase 区块数会动态调整，每个 Phase 对应的区块范围由当时的 `phaseBlocks` 决定。

### 2.2 目标天数

- `targetDays` 用于计算目标秒数：`targetSeconds = targetDays × 86400`
- Phase 动态校准以此为目标，自动调整 `phaseBlocks` 使实际运行时间接近目标天数
- 例如 `targetDays = 7` 表示目标是每个 Phase 约 7 天

---

## 3. 核心能力

### 3.1 公开接口

- `currentPhase()`：当前区块对应的 Phase
- `phaseInfo(phaseNumber)`：阶段起始区块和阶段区块数
- `phaseAtBlock(blockNumber)`：指定区块的 Phase
- `syncObservationsCount()`、`syncObservation(observationId)`：同步观测数量和按 1-based ID 查询观测
- `sync()`：Submit 合约调用的校准入口

### 3.2 sync() 接口

```solidity
function sync() external returns (bool adjusted, uint256 newPhaseBlocks)
```

**权限**：只能由 Submit 合约调用

**返回值**：
- `adjusted`：本次调用是否调整了 Phase 长度（true = 调整了，false = 仅记录观测点未调整）
- `newPhaseBlocks`：调整后的 Phase 区块数（如果 `adjusted == false`，返回当前的 `phaseBlocks`）

**副作用**：
- 总是追加当前观测点（`block.number` 和 `block.timestamp`）
- 根据调整规则（第4节）决定是否调整未来 Phase 的长度
- 如果调整，触发 `PhaseAdjusted` 事件

---

## 4. Phase 同步时机

### 4.1 同步触发点

- ✅ 每轮首个推举：Submit 自动调用 `Phase.sync()`
- ❌ 投票时：不自动同步（依赖推举时的同步）
- ❌ 铸造时：不自动同步（已进入下一个 Phase）
- ❌ 外部调用：只有 Submit 合约可以调用

Submit 合约负责在每轮首个推举时调用 `sync()`，确保 Phase 动态校准及时生效。

### 4.2 设计理由

- 推举时同步确保下一轮的 Phase 参数更准确
- 避免每次投票都同步，节省 gas

### 4.3 极端情况

**如果某个 Round 没有推举**：
- Phase 不会自动同步（`sync()` 只能由 Submit 合约调用）
- 只能等待下一个 Round 的首个推举触发同步
- 未同步不影响协议运行，只影响下一个 Phase 的长度校准

**没有推举的 Round**：
- 仍然是有效的时间片（Phase N 对应治理 Round N）
- 由于没有 Proposal，该 Round 不产生投票和激励
- Phase 校准延迟到下一个有推举的 Round

---

## 5. 动态校准

### 5.1 基本规则

每次 `sync()` 都先追加当前观测点，即使不调整参数。校准使用满足 `currentBlock - observation.blockNumber >= currentPhaseBlocks` 的最近一条历史观测（`currentPhaseBlocks` 指当前的 `phaseBlocks` 值）；若最近观测点不满足，继续往前追溯直到找到满足条件的观测点；若没有观测点满足条件，则使用最早的观测点。

### 5.2 首次 sync() 处理

- 第一次调用 `sync()` 时，还没有历史观测点，只记录当前观测点（`block.number` 和 `block.timestamp`），不执行调整
- 后续 `sync()` 调用才能基于历史观测点进行阈值判断和调整

### 5.3 调整规则

**只在有符合条件的历史观测点时才执行**：

1. 根据观测数据计算目标天数对应的区块数：
   ```
   observedPhaseBlocks = elapsedBlocks × targetSeconds / elapsedSeconds
   ```

2. 计算与当前 `phaseBlocks` 的偏差：
   ```
   deviation = |observedPhaseBlocks - currentPhaseBlocks| / currentPhaseBlocks
   ```

3. **触发调整的偏差阈值**：`±10%`
   - 偏差在 `±10%` 内时不调整
   - 偏差超过 `±10%` 时触发调整

4. **单次调整幅度上限**：`±20%`
   - 如果 `observedPhaseBlocks` 在 `currentPhaseBlocks × [0.8, 1.2]` 范围内，使用计算值
   - 如果 `observedPhaseBlocks < currentPhaseBlocks × 0.8`，限制为 `currentPhaseBlocks × 0.8`
   - 如果 `observedPhaseBlocks > currentPhaseBlocks × 1.2`，限制为 `currentPhaseBlocks × 1.2`

5. 尚未生成的 Phase 使用 `newPhaseBlocks`

已经生成的 Phase 不回写。

### 5.4 调整示例

**假设**：`targetDays = 1`，`targetSeconds = 86400`，`currentPhaseBlocks = 28800`

#### 场景 1：不调整（在 ±10% 内）
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1087200（经过 87200 秒）
- `observedPhaseBlocks = 29000 × 86400 / 87200 ≈ 28747`
- 偏差：`|28747 - 28800| / 28800 ≈ 0.18%` < 10%
- **不调整**，保持 `phaseBlocks = 28800`

#### 场景 2：向下调整（Phase 过慢）
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1100000（经过 100000 秒）
- `observedPhaseBlocks = 29000 × 86400 / 100000 = 25056`
- 偏差：`|25056 - 28800| / 28800 ≈ 13%` > 10% 且 ≤ 20%
- **调整为 25056 区块/Phase**（加快节奏）

#### 场景 3：向上调整（Phase 过快）
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1075000（经过 75000 秒）
- `observedPhaseBlocks = 29000 × 86400 / 75000 = 33408`
- 偏差：`|33408 - 28800| / 28800 ≈ 16%` > 10% 且 ≤ 20%
- **调整为 33408 区块/Phase**（放慢节奏）

#### 场景 4：极端调整（超过 20% 上限）
- 上次观测：区块 1000，时间戳 1000000
- 当前观测：区块 30000（经过 29000 区块），时间戳 1150000（经过 150000 秒）
- `observedPhaseBlocks = 29000 × 86400 / 150000 = 16704`
- 偏差：`|16704 - 28800| / 28800 ≈ 42%` > 20%
- **按 20% 上限调整为 28800 × 0.8 = 23040 区块/Phase**（渐进式调整）

**关键**：根据观测数据计算目标天数对应的区块数，与当前 phaseBlocks 对比，超出阈值则调整。

---

## 6. 与治理 Round 的关系

### 6.1 术语定义

- **治理 Round**：Core Submit 和 Vote 把 Phase N 一对一解释为治理 Round N
- **当前治理 Round**：`Phase.currentPhase()` 返回的 Phase 编号，即当前治理 Round 编号

### 6.2 治理流程

核心 `Submit` 和 `Vote` 提供无参数的 `currentRound()`。创建、推举和投票只写入当前治理 Round；当 `Phase.currentPhase() > N` 时，治理 Round N 的 Vote 时间片结束，`Vote` 对外返回该 Round 已结束，核心激励可以准备和铸造。
