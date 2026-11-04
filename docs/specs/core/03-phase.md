# Phase 与 Round

Phase 维护连续的无语义时间片、同步观测和动态校准，不内置 Vote、Join、Verify、Mint 或业务 Round。不能把旧静态 Phase 直接作为本版实现。

## 参数与查询

`ORIGIN_BLOCKS`、`ORIGIN_PHASE_BLOCKS`、`TARGET_SECONDS` 为正数；`ADJUST_THRESHOLD` 使用 `1e18` 精度且在 `(0, 1e18]` 内，`SYNC_OBSERVATION_LIMIT` 为正数。`block.number == ORIGIN_BLOCKS` 时为 Phase 1；不存在有效 Phase 0。`TARGET_SECONDS` 是每个 Phase 的目标自然时长，单位秒，7 天为 `604800`。

构造参数为 `ORIGIN_BLOCKS`、`ORIGIN_PHASE_BLOCKS`、`TARGET_SECONDS`、`ADJUST_THRESHOLD` 和 `SYNC_OBSERVATION_LIMIT`；完整运行时 ABI 见 [`IPhase.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IPhase.sol)。`SYNC_OBSERVATION_LIMIT` 为正数，用于初始化每轮同步前的快速回溯条数。

| 接口 | 返回或作用 |
| --- | --- |
| `currentPhase()` | 当前区块的 Phase |
| `lastSyncPhase()` | 最近一次有效同步记录的 Phase，初值 0 |
| `phaseInfo(phaseNumber)` | 阶段起始区块和区块数 |
| `phaseAtBlock(blockNumber)` | 指定区块的 Phase |
| `observations(offset, limit, reverse)` | 分页读取同步观测：返回区块号数组、时间戳数组和观测总数 |

`observations` 的 `offset` 大于或等于观测总数时返回空数组与真实总数，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时按从新到旧返回。

## 接口、事件与错误

完整 ABI 见 [`IPhase.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IPhase.sol)。

`Phase` 本身不提供 `init`。未开始的 Phase 回 `PhaseNotStarted()`；构造参数非零与 `ADJUST_THRESHOLD <= 1e18` 由 DeployCore 在广播前校验，`21_check` 部署后复核，构造器只保存参数；内部索引不变量用 `assert`（Panic）。完整 selector 以接口文件为准。

## 同步

任何地址可调用 `sync`，但同一 Phase 实例在每个治理投票 Round 最多执行一次有效同步。治理 Round 与 Phase 一对一，因此按调用前的 `currentPhase()` 全局限频，不按 token 或调用者分别计数。

维护 `lastSyncPhase`，初值为 0。若等于本次 Phase，直接返回 `(false, currentPhaseBlocks)`，不追加观测、不调整参数、不发事件；否则记录本 Phase 并追加 `block.number`、`block.timestamp`。首次同步或未达到调整条件仍消耗本轮同步机会，失败回滚则不消耗。

**机会一旦消耗，本 Phase 内不再有任何调用能触发校准。** 这是无许可入口的治理含义：抢跑者能决定的只是采样时点，既不能在同一 Phase 内多次采样取最有利值，也不能伪造 `elapsedBlocks` / `elapsedSeconds`——两者都来自链上真实值，`observed` 是同一段真实时间上的比值估计，采样时点只改变方差、不改变期望方向。

每轮首个成功推举仍自动调用 `sync`；如果已经有人同步，自动调用无操作返回，不能阻塞推举。没有推举时任何人仍可同步；投票和铸造本身不触发同步。无人调用也不停止 Phase 推进。

首次有效同步只追加观测。每次有效同步发出且只发一条 `PhaseSynchronized(phase, currentPhaseBlocks, nextPhaseBlocks)`，它是本次同步时点的**段长快照**：`currentPhaseBlocks` 是 Phase `phase` 的段长，`nextPhaseBlocks` 是 Phase `phase + 1` 起的段长；块高与时间由日志元数据承担，不进入载荷。快照携带整组段长，未调整时两者相等——`AdminChanged` 携带整组新快照（哪怕只改一项）是同一先例，快照的完整性优先于「不重复未变化字段」（§3.1）。

`nextPhaseBlocks` 是终值：在 Phase P 调整只写 P+1 段，之后在 P+1 再调整只写 P+2，永不回写 P+1，因此 `next(P)` 一旦发出不会被后续日志推翻。折叠规则是 `schedule[phase] = currentPhaseBlocks`、`schedule[phase + 1] = nextPhaseBlocks`，重放与乱序重组都幂等，不需要配对多条事件。`effectivePhase` 不是载荷字段，它恒等于 `phase + 1`，由消费方推导。

相邻两次有效同步满足 `e2.currentPhaseBlocks == e1.nextPhaseBlocks`；中间跳过的空 Phase 不影响该式，因为生效段始终是 `p1 + 1`。`nextPhaseBlocks == currentPhaseBlocks` 只表示段长不变，不承诺区分「未调整」与「发生过一次同长度重写」：`currentPhaseBlocks == 1` 且估算为 0 时新长度被钳到 1，会写一段等长段，投影上与旧外推一致。`adjusted` 返回值只供调用方判断本次是否写入了新段，不进入事件。

新参数不得改变当前或过去 Phase 的编号和边界，不能通过校准重获本轮同步机会。`adjusted = false` 时，`newPhaseBlocks` 返回当前值。

`lastSyncPhase()` 返回最近一次有效同步记录的 Phase，初值为 0。判断「本 Phase 是否已同步」应读该 getter：`lastSyncPhase() == currentPhase()` 表示本 Phase 已消耗同步机会；未同步过或最近一次同步在更早 Phase 时两者不相等。本 Phase 已被同步后的重复调用静默返回、不发事件，因此**不能用 `PhaseSynchronized` 的事件计数推断同步状态**。

## 校准

1. 先从最近观测向前检查最多 `SYNC_OBSERVATION_LIMIT` 条；仍未找到合格观测时，通过 `OrderedHistoryIndex` 二分查找最近的合格观测。
2. 对满足条件的记录计算以下公式，除法向下取整。
3. `deviation > ADJUST_THRESHOLD` 才调整，等于阈值时不调整。
4. 新长度至少为 1，只写入 `phase + 1` 起的段，已生成阶段不回写。

```text
observed = floor(elapsedBlocks * TARGET_SECONDS / elapsedSeconds)
deviation = floor(abs(observed - currentPhaseBlocks) * 1e18 / currentPhaseBlocks)
newPhaseBlocks = max(1, observed)
```

`deviation` 是比例表达式，不能先用整数除法截成零再与阈值比较。`elapsedBlocks` 和 `elapsedSeconds` 是选定观测到本次同步的区块差与秒差。

合格观测定义为：从最新观测向前，选择第一个满足 `block.number - observation.blockNumber > currentPhaseBlocks` 的观测；严格大于，等于时继续向前查找。二分查找也以该条件为判定，不存在合格观测时不调整。

例如当前长度 100、阈值 20% 时，估算 110 保持 100，估算 130 调整为 130。

## 治理 Round

Submit 和 Vote 的 `currentRound()` 等于 `Phase.currentPhase()`。创建、推举、投票仅写当前治理 Round。当前 Phase 大于 N 时，Vote 对外确认 Round N 已结束，Mint 才能准备和铸造其激励。

## 校准边界

- 默认从最近观测向前检查最多 `SYNC_OBSERVATION_LIMIT` 条；仍未找到合格观测时，通过 `OrderedHistoryIndex` 二分查找最近的合格观测。
- 没有合格观测、`elapsedBlocks == 0` 或 `elapsedSeconds == 0` 时只记录观测，不调整参数。
- 偏差阈值由初始化参数 `ADJUST_THRESHOLD` 提供，按 `1e18` 精度；超过阈值才调整。
- 新长度为 `max(1, floor(elapsedBlocks * TARGET_SECONDS / elapsedSeconds))`；已生成 Phase 不回写。
- `block.number < ORIGIN_BLOCKS` 时 `currentPhase()` 和 `phaseAtBlock(block.number)` 返回 `0`；`phaseInfo(0)` 无效。

验收见 [Core 验收](09-testing.md)。
