# Phase 接口调用权限审查

> 对象 `core/src/Phase.sol`（162 行）
> 接口 `core/src/interfaces/IPhase.sol`（34 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/03-phase.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 11（写 1 / 读 10） |
| 带鉴权 modifier | **0** |
| 无许可写入口 | 1（`sync`） |
| 发现 | 2 条：Low 1 / Info 1，另有 2 条正面结论 |
| 接口对账 | 11 vs 11，**0 差异** |

一句话：**全仓唯一用 `constructor` 而不是 `init` 的合约，因此没有抢跑面；唯一的写入口 `sync` 无鉴权，但权限后果被「每 Phase 一次」的配额和「只按真实块/时间差计算」的公式约束在「影响采样方差」这一层，不能凭空制造方向。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 任何地址 | 无；仅 `_lastSyncPhase != currentPhase()` 的幂等闸 | `sync` |
| 无 | — | 10 个只读入口 |

本合约不读取 `msg.sender`，不持有任何资产，不调用任何外部合约。参数全部由构造器固定（`ORIGIN_BLOCKS`、`ORIGIN_PHASE_BLOCKS`、`TARGET_SECONDS`、`ADJUST_THRESHOLD`、`SYNC_OBSERVATION_LIMIT`），无 setter。

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 幂等闸 | 事件 |
| --- | --- | --- | --- | --- |
| `sync()` | 任何地址 | 无 | `_lastSyncPhase == phase` 时静默返回 `(false, phaseBlocks)` | `PhaseSynchronized`（每次有效同步）；调整时另发 `PhaseAdjusted` |

### 只读入口（10）

`ORIGIN_BLOCKS`、`ORIGIN_PHASE_BLOCKS`、`TARGET_SECONDS`、`ADJUST_THRESHOLD`、`SYNC_OBSERVATION_LIMIT`（immutable getter）；`currentPhaseBlocks`、`currentPhase`、`phaseInfo`、`phaseAtBlock`、`observations`。

读面边界（规格明示）：`phaseInfo(0)` 回滚 `PhaseNotStarted()`；`block.number < ORIGIN_BLOCKS` 时 `currentPhase()` 与 `phaseAtBlock()` 返回 0；`observations` 的 `offset >= totalCount` 返回空数组与真实总数，不回滚。

## 四、逐入口判定

### `sync` — 无鉴权，但配额与公式共同封住操纵空间

校验与写入顺序（`L86-136`）：

1. `currentPhase() == 0` → `PhaseNotStarted()`；
2. `_lastSyncPhase == phase` → 直接返回，不写状态、不发事件；
3. 写入 `_lastSyncPhase = phase`（**先占配额**）；
4. 向前找合格观测（最多 `SYNC_OBSERVATION_LIMIT` 条，找不到则二分）；
5. 追加本次观测（块号、时间戳、索引、id 映射）；
6. 满足条件才计算 `observed` / `deviation`，超过阈值才 `_recordNextSegment` 并调整。

三个权限相关结论：

- **先占配额再计算**：`_lastSyncPhase` 在观测计算之前写入（`L94`）。若后续计算 revert，整笔回滚，配额不消耗——与规格「失败回滚则不消耗」一致。这防止了「用一次 revert 的调用探测/占用配额」。
- **无外部调用**：`sync` 只读自身数组、写自身状态、发事件，不调用任何合约，所以不需要 `nonReentrant`，也不存在借回调重入的面。
- **无资产面**：调整的是未来 Phase 的块数，不涉及任何余额、份额或奖励。

### 抢跑的后果：只能改变采样时点，不能制造虚假比值

`observed = floor(elapsedBlocks * TARGET_SECONDS / elapsedSeconds)` 是同一段真实时间上的比值估计。抢跑者能决定的只有「在哪一块采样」，因此：

| 抢跑者能做的 | 抢跑者做不到的 |
| --- | --- |
| 在 Phase 早期采样，把观测点固定在边界附近 | 伪造 `elapsedBlocks` / `elapsedSeconds`（都来自 `block.number` / `block.timestamp`） |
| 在出块速度短暂异常的瞬间抢先调用，使本轮 `observed` 偏离 | 在同一 Phase 内多次采样取最有利值（配额已消耗，后续调用直接返回） |
| 消耗本轮机会，使本轮不再调整 | 回写已生成的 Phase 边界（`_recordNextSegment` 只写 `phase + 1` 起） |

因此单次抢跑的收益上限是「让某一次校准按异常时点的样本落地」，且只影响尚未生成的 Phase。

## 五、发现

### PHS-01（Low）无许可 + 单次配额 = 可由抢跑者决定「本轮是否校准、按哪个时点校准」

- 证据：`sync` 无鉴权（`L86`）；`_lastSyncPhase = phase` 在 `L94`，先于观测选择与计算；`_lastSyncPhase == phase` 时静默返回（`L90-93`）。
- 影响：任何人只要在某 Phase 的第一时间调用 `sync`，本轮就再也不能校准；若这次调用恰好落在出块速度短暂偏离的窗口，`observed` 会按该窗口的样本落地，`phaseBlocks` 被调大或调小后对后续所有 Phase 生效。规格 `03-phase.md` 明确「首次同步或未达到调整条件仍消耗本轮同步机会，失败回滚则不消耗」，所以这是**已声明的设计**，不是实现偏差。
- 为何仍是 Low 而非 Info：`phaseBlocks` 是全局时间轴参数，一次不利校准的影响面是全协议的所有轮次边界；而阻止它只需要一次普通交易（无质押、无身份、无成本门槛）。这与 `settleFees`（只能按时结算，不能加速）不同——后者没有「配额被浪费」的副作用。
- 建议（择一，均不改 ABI）：
  1. 在 `03-phase.md` 的「校准边界」里显式写出这条后果（当前只写了「消耗机会」，没写「消耗后本轮不可能再校准」的治理含义）；
  2. 若要收紧，可把「配额」改到「找到合格观测之后」再占用——代价是允许同一 Phase 内多次尝试，需同时评估 `_observationBlocks` 的增长速率。
- 注意：本报告不主张改代码。第 2 条与规格「首次同步也消耗机会」冲突，改则必须同步改规格。

### PHS-02（Info）`sync` 静默返回时不发事件，链下无法观测「有人尝试过」

- 证据：`L90-93` 直接 `return (false, phaseBlocks)`，不 emit。
- 规格：`03-phase.md`「若等于本次 Phase，直接返回，不追加观测、不调整参数、不发事件」——已声明。
- 判定：不是缺陷。但链下若以「`PhaseSynchronized` 事件数」统计活跃度，会把「本 Phase 已被同步」误读为「无人同步」。建议在规格里补一句「以 `_lastSyncPhase` 的状态变化而非事件计数判断同步状态」，或提供一个只读 getter（当前 `_lastSyncPhase` 是 private，无 getter——这是**读面缺口**：任何人都无法直接读「本 Phase 是否已同步」，只能从 `observations` 的最后一条推断）。

### PHS-03（正面结论）没有 `init`，因此没有抢跑面

- 证据：参数全部由构造器写入（`L33-46`），`_recordSegment(Segment(1, originBlocks, originPhaseBlocks))` 也在构造器内完成。
- 判定：全仓 8 个合约里唯一不需要 `init` 的两个之一（另一个是 `LOVE20Token`），不存在「谁先调谁定参数」的窗口。这部分权限面天然闭合。

### PHS-04（正面结论）`assert` 兜住内部索引不变量

- 证据：`_phaseBlocks` 与 `phaseInfo` 用 `assert(found)`（`L59`、`L139`）；`_recordNextSegment` 用 `assert(found)`（`L153`）。
- 判定：索引不变量破坏时是 Panic 而不是静默返回错误值。读面因此在任何状态下都返回确定的段，不会把「找不到」误报成 Phase 0。规格 `03-phase.md` 已声明「内部索引不变量用 `assert`（Panic）」。

## 六、核对证据

```text
$ forge inspect Phase abi --json              # 11 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

本合约无鉴权分支，无 `NotMemberOwner` 类负例。`test/Phase.t.sol` 覆盖：`phaseInfo(0)` 回滚、`phaseAtBlock` 在 `ORIGIN_BLOCKS` 之前返回 0、同 Phase 重复 `sync` 返回 `(false, …)` 且不追加观测、调整阈值边界（等于阈值不调整）、`SYNC_OBSERVATION_LIMIT` 回溯与二分回退。

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 下游 | `Submit.currentRound`、`Vote.currentRound`、`Stake._currentRound`、`Mint._isRoundEnded` | 全部以 `currentPhase()` 为轮次唯一来源 |
| 下游 | `Submit._submitByProposalId` | 每轮首个推举自动调 `sync()`（`Submit.sol:321`）；已有同步时无操作 |
| 上游 | 无 | 本合约不读任何外部合约 |
