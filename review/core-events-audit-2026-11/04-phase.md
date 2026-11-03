# Phase 事件赋值与发射审查

- 实现：`core/src/Phase.sol`（158 行，`78ce1e6`）
- 声明：`core/src/interfaces/IPhase.sol`（`IPhaseEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/03-phase.md`
- 审查日期：2026-11-03（重基线 `78ce1e6`）

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点 | 1（每次有效同步恰一条） |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0 |
| 放行 | 通过：单条段长快照即可重建 `phase → 段长` 表，折叠与 `phaseInfo` 一致 |

一句话：每次有效同步只发一条 `PhaseSynchronized(phase, currentPhaseBlocks, nextPhaseBlocks)`。`currentPhaseBlocks` 是 Phase `phase` 的段长，`nextPhaseBlocks` 是 Phase `phase + 1` 起的段长；未调整时两者相等。`PhaseAdjusted` 已删除：`effectivePhase ≡ phase + 1`、旧段长 ≡ `currentPhaseBlocks`，同笔两条日志的顺序问题随之消失。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 触发条件 | 前置写入 |
| --- | --- | --- | --- | --- |
| `PhaseSynchronized` | `phase` | `sync:127` | 每次**有效**同步（`_lastSyncPhase != currentPhase`）；重复同步直接返回且不发事件 `:90-93` | `_lastSyncPhase:94`、观测三元组 `:107-110`；调整时另有 `_recordNextSegment:121` |

族归属：`core.phase`（对象 id → 段长快照）。

## 2. 逐事件赋值链

### 2.1 `PhaseSynchronized`

```solidity
event PhaseSynchronized(
    uint256 indexed phase,
    uint256 currentPhaseBlocks,
    uint256 nextPhaseBlocks
);
```

| 字段 | 赋值来源（源码行） | 取值口径 |
| --- | --- | --- |
| `phase` | `phase = currentPhase()` `:87` | 本次同步观测到的当前 Phase |
| `currentPhaseBlocks` | 局部 `phaseBlocks = _phaseBlocks(phase)` `:89` | 当前 Phase 的段长；与 `phaseInfo(phase).phaseBlocks`、`currentPhaseBlocks()` 一致 |
| `nextPhaseBlocks` | `newPhaseBlocks` `:120` / `:126` | 调整时为钳后 `observed`，已由 `_recordNextSegment` 写入 P+1 段；未调整时等于 `currentPhaseBlocks` |

关键代码路径：

```
:119  if (deviation > ADJUST_THRESHOLD) {
:120      newPhaseBlocks = observed == 0 ? 1 : observed;
:121      _recordNextSegment(phase, phaseBlocks, newPhaseBlocks);   // 只写 Segment(phase+1, start(phase+1), newPhaseBlocks)
:122      adjusted = true;
:126  if (!adjusted) newPhaseBlocks = phaseBlocks;
:127  emit PhaseSynchronized({
:128      phase: phase,
:129      currentPhaseBlocks: phaseBlocks,
:130      nextPhaseBlocks: newPhaseBlocks
:131  });
```

`_recordNextSegment:147-156` 只写 `_segmentByPhase[phase + 1]` 与 `_segmentByStartBlock[...]`，**不回写** `_segmentByPhase[phase]`；`_phaseBlocks(phase):134-138` 与 `phaseInfo(phase):56-63` 都取 `nearest(phase)`。因此：

- `currentPhaseBlocks` 恒等于 `phaseInfo(phase).phaseBlocks` 与 `currentPhaseBlocks()`；
- 调整时 `nextPhaseBlocks` 恒等于 `phaseInfo(phase + 1).phaseBlocks` 与本次返回值；
- 未调整时 `nextPhaseBlocks` 等于当前段长，也就是 P+1 在无新调整时的段长。

折叠规则：`schedule[phase] = currentPhaseBlocks`、`schedule[phase + 1] = nextPhaseBlocks`。`nextPhaseBlocks` 是终值：在 P 调整只写 P+1 段，之后在 P+1 调整只写 P+2，永不回写，因此重复折叠与乱序重组都幂等，不需要配对多条事件。相邻两次有效同步满足 `e2.currentPhaseBlocks == e1.nextPhaseBlocks`，中间跳过的空 Phase 不影响（`Phase.t.sol:202-228`）。首段 `(1, ORIGIN_BLOCKS, ORIGIN_PHASE_BLOCKS)` 由构造参数 `:45` 承担；`startBlock` 由 `origin + Σ 段长` 推出。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键/对象 id 首字段（§6.1） | 通过 | `phase` 首字段且 indexed |
| 族槽位（`core.phase`：对象 id → 数值） | 通过 | |
| indexed ≤ 3（§6.3） | 通过 | 1 个 |
| 快照完整性（§3.1） | 通过 | 单条日志同时携带 `phase` 与 `phase + 1` 的段长；未调整时两者相等，快照自身完整 |
| 状态写入后 emit（§3.4.3） | 通过 | `_lastSyncPhase:94`、观测 `:107-110`、段写入 `:121` 均在 `emit:127` 前 |
| 折叠完整性（§3.3） | 通过 | 见 §2 折叠规则与相邻同步不变式 |
| 累计值锚点（§3.1） | 不适用 | 无聚合量 |
| 失败不留日志（§3.5） | 通过 | `PhaseNotStarted` 在写入前 revert `:88`；重复同步 `:90-93` 直接返回，不追加观测、不发事件 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；`Phase.t.sol:70-77`、`:192-199` 断言签名、indexed 布局与载荷 |
| 测试断言（§8.1） | 通过 | 非调整 `:183-200`、调整 `:64-83`、相邻同步含空 Phase `:202-228`、钳制等长重写 `:230-254`、重复同步无事件 `:170`、未开始回滚 `:43` |

## 4. 发现

无未决问题。

### 4.1 语义边界（规格已登记，非缺陷）

- `nextPhaseBlocks == currentPhaseBlocks` 不区分「未调整」与「发生过一次同长度重写」：`currentPhaseBlocks == 1` 且估算为 0 时新长度钳到 1，会写入一段等长段。`adjusted` 只从 `sync()` 返回值读取，不进入事件（`Phase.t.sol:230-254` 固定该语义）。
- 该边界不影响折叠：两种情形投影出的下一段长都是 1。事件是段长快照，不是「是否调整」的 diff。
- `nextPhaseBlocks` 的终值性依赖 `_recordNextSegment` 只写 P+1；`Phase.t.sol:202-228` 用跳过空 Phase 的相邻同步固定该性质。

## 5. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_lastSyncPhase` | `:94` | `PhaseSynchronized.phase`（取其最大值即当前值） |
| `_observationBlocks` / `_observationTimestamps` / 索引 | `:107-110` | 不事件化：观测缓存可由日志的块号/时间戳重建；§6.9 已登记为派生缓存 |
| 分段表 `_segmentByPhase` / `_segmentByStartBlock` | 构造 `:45`、`:121`→`:147-156` | 首段由构造参数承担；后续段由 `currentPhaseBlocks` / `nextPhaseBlocks` 承载（`phase + 1` 由恒等式推导） |
| `newPhaseBlocks` 返回值 | `:120`、`:126` | 等于 `nextPhaseBlocks` |
