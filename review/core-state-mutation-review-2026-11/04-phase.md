# Phase · 状态变量变更审查

> `core/src/Phase.sol`，162 行，`core@6fdd0f1`。
> Phase 不发资产，但它是**全局时钟**：`currentPhase()` 被 Stake / Submit / Vote / Mint 四家当成 Round 唯一来源。这个合约的账本写错，四家的时间轴一起错。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| 1-5 | `ORIGIN_BLOCKS` / `ORIGIN_PHASE_BLOCKS` / `TARGET_SECONDS` / `ADJUST_THRESHOLD` / `SYNC_OBSERVATION_LIMIT` | `uint256 immutable` | 原点、初始段长、目标秒数、偏差阈值、回看条数 | 构造器 `:40-44` | 不可变 |
| 6 | `_lastSyncPhase` | `uint256` | 上次有效同步的 Phase（`0` = 从未） | `sync:94` | 只增 |
| 7 | `_observationBlocks` | `uint256[]` | 观测区块号（严格递增） | `sync:107` | 每 Phase ≤1 条 |
| 8 | `_observationTimestamps` | `uint256[]` | 对应时间戳 | `sync:108` | 与 #7 同长 |
| 9 | `_observationBlockIndex` | `OrderedHistoryIndex.Index` | 区块号有序索引（二分查找用） | `sync:109` | 与 #7 同长 |
| 10 | `_observationIdByBlock` | `mapping(uint256 => uint256)` | 区块号 → **1-based** 数组下标 | `sync:110` | 只写一次/区块 |
| 11 | `_segmentPhaseIndex` | `OrderedHistoryIndex.Index` | 段起始 Phase 的有序索引 | `_recordSegment:145` | 每次调整 +1 |
| 12 | `_segmentStartBlockIndex` | `OrderedHistoryIndex.Index` | 段起始区块的有序索引 | `_recordSegment:146` | 每次调整 +1 |
| 13 | `_segmentByPhase` | `mapping(uint256 => Segment)` | Phase →（phase, startBlock, phaseBlocks） | `_recordSegment:147` | 只写一次/段 |
| 14 | `_segmentByStartBlock` | `mapping(uint256 => Segment)` | startBlock → 同一 Segment | `_recordSegment:148` | 只写一次/段 |

`Segment` 同时写两份（`:147`、`:148`），是为了让 `phaseInfo`（按 Phase 查）与 `phaseAtBlock`（按区块查）都能走 `O(log n)` 的索引。两份内容必须逐字段一致。

## 2. 逐变量变更逻辑

### 2.1 `sync` 的写入序列（`:86-136`）

| 步 | 位置 | 动作 | 说明 |
| --- | --- | --- | --- |
| 1 | `:87-88` | 读 `currentPhase()`；`== 0` 回滚 `PhaseNotStarted` | 未到 `ORIGIN_BLOCKS` 时不可同步 |
| 2 | `:89` | 读 `_phaseBlocks(phase)` | 只读 |
| 3 | `:90-93` | `_lastSyncPhase == phase` → 直接返回 `(false, phaseBlocks)` | **不写任何状态、不发事件**；这是「每 Phase 一次」的唯一闸门 |
| 4 | `:94` | `_lastSyncPhase = phase` | **先落闸门再干活**：后续任何外部调用（本函数没有）都不可能再进第二遍 |
| 5 | `:96-101` | 从最新观测向前扫 `SYNC_OBSERVATION_LIMIT` 条，取第一条 `block.number - obs > phaseBlocks` 的 | 只读 |
| 6 | `:102-106` | 扫不到时用 `_observationBlockIndex.nearest(block.number - phaseBlocks - 1)`，再 `_observationIdByBlock[nearest] - 1` 换算成数组下标 | 只读；见 `PHS-02` 的 1-based 说明 |
| 7 | `:107-108` | `push` 区块号与时间戳 | 两条数组同笔、同序 |
| 8 | `:109` | `_observationBlockIndex.record(block.number)` | 索引 `keys` 追加 + `recorded[key] = true` |
| 9 | `:110` | `_observationIdByBlock[block.number] = _observationBlocks.length` | **1-based**：`levels[i]` 的 id 是 `i+1` |
| 10 | `:111-130` | 若有合格观测：算 `observed` / `deviation`；`deviation > ADJUST_THRESHOLD` 时 `newPhaseBlocks = max(1, observed)` 并 `_recordNextSegment(phase, phaseBlocks, newPhaseBlocks)` | 只在「严格大于」时调整 |
| 11 | `:132-135` | `PhaseSynchronized(phase, newPhaseBlocks)` | 每次有效同步都发 |

注意第 4 步与第 7 步的顺序：`_lastSyncPhase` 在观测入账之前写。若第 5-10 步之间发生回滚，整笔撤销，闸门也回滚——「失败不消耗本 Phase 的同步机会」由此成立。

### 2.2 `_recordSegment` / `_recordNextSegment`（`:144-160`）

```solidity
// _recordSegment：四个写入必须同笔
_segmentPhaseIndex.record(segment.phase);
_segmentStartBlockIndex.record(segment.startBlock);
_segmentByPhase[segment.phase] = segment;
_segmentByStartBlock[segment.startBlock] = segment;

// _recordNextSegment：从最新段外推
(found, key) = _segmentPhaseIndex.latest();
previous = _segmentByPhase[key];
_recordSegment(Segment(phase + 1,
    previous.startBlock + (phase - previous.phase + 1) * phaseBlocks,
    newPhaseBlocks));
```

`startBlock` 的算法是「从最新段的起点，按当前段长走到 `phase + 1` 的起点」。它成立的前提是**段与段之间无空隙**，即最新段的 `phase <= phase`（当前 Phase）。这个前提由「每 Phase 至多一次调整、每次只写 `phase + 1`」保证：

| 时刻 | 最新段的 phase | 本次写入 | `phase - previous.phase + 1` |
| --- | --- | --- | --- |
| 构造后 | 1 | 在 phase 1 调整 → 写 2 | 1 |
| phase 2 | 2（上一轮写的） | 写 3 | 1 |
| phase 3（phase 2 没同步） | 2（上一轮写的） | 写 4 | 2 |

三行都得到正确的下一段起点。若未来把「每 Phase 一次」放开成多次，`phase - previous.phase + 1` 会退化为 0 或负数，`startBlock` 会与已有段重合——`_segmentByStartBlock` 被覆盖，`phaseAtBlock` 对历史区块的换算随之改变。这是 `PHS-02` 的核心：**这段正确性依赖一个不在本函数里的时序前提**。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| P1 | `_observationBlocks` 严格递增，`_observationTimestamps.length == _observationBlocks.length` | ✅ | 同笔 push；`_lastSyncPhase` 保证每 Phase ≤1 条，而 Phase 随区块单调 |
| P2 | `_observationIdByBlock[_observationBlocks[i]] == i + 1` | ✅ | `:110` 用 push 之后的长度赋值 |
| P3 | `_segmentPhaseIndex.keys` 严格递增，最后一项 ≤ `currentPhase() + 1` | ✅ | `_recordNextSegment` 只写 `phase + 1`，且每 Phase 一次 |
| P4 | 任意相邻段 `(p, s, L)`、`(q, s', L')` 满足 `s' == s + (q - p) * L` | ✅（在 P3 下） | 见 §2.2 的三行表 |
| P5 | `_segmentByPhase[p]` 与 `_segmentByStartBlock[s]` 字段完全一致 | ✅ | 同一个 `Segment` 内存值写两处（`:147-148`） |
| P6 | `phaseAtBlock(b)` 对 `b` 单调不减；`b < ORIGIN_BLOCKS` 返回 0 | ✅ | `nearest` 返回不大于 `b` 的最大段起点，段内整除 |
| P7 | `currentPhase() >= 1` ⟺ `block.number >= ORIGIN_BLOCKS` | ✅ | `phaseAtBlock:66` 的早退 + 构造时 `_recordSegment(Segment(1, origin, L))` |

P3/P4 是**结构性**的：`_segmentByStartBlock` 用 `startBlock` 当键，一旦两段同起点，后写覆盖前写，`phaseAtBlock` 会拿错段长去换算一个历史区间。当前不会发生，但没有任何运行时检查（`record` 只对 Phase 键做 `assert`，不对 startBlock 做唯一性检查）。

## 4. 发现

### PHS-02 · 三条承重不变量只由 `assert` 与时序共同保证

| 字段 | 值 |
| --- | --- |
| 位置 | `:100-110`（观测选择与 1-based 换算）、`:144-160`（段写入） |
| 级别 | Info |
| 证据 | E1 |

三处「看起来是防御、实际是 Panic」的写法：

1. `OrderedHistoryIndex.record` 对 `key < last` 或 `key == last` 走 `assert`（`libs/OrderedHistoryIndex.sol:10-18`）。Phase 的两处 `record`（观测区块号、段起始 Phase/区块）都假定严格递增，一旦不成立，失败形态是 `Panic(0x01)` 而不是带载荷的业务错误。
2. `_observationIdByBlock[nearest] - 1`（`:105`）假定「凡进入索引的区块号都写过映射」。这条成立只因为 `:107-110` 三步同笔且顺序固定；若未来把映射写移到 `record` 之前或之后单独失败，减法会下溢。
3. `_recordNextSegment`（`:151-159`）假定最新段的 `phase <= 当前 phase`。该前提由 `_lastSyncPhase` 的「每 Phase 一次」提供，不在函数内。

**建议**：把这三条写成注释或 `require`（`require(previous.phase <= phase)` 只需一次比较），并在测试里加一条「同一 Phase 连续两次 `sync()` 第二次不写任何状态」的断言（当前行为正确，但没有测试钉住）。

### PHS-03 · `phaseInfo` 对未来 Phase 返回外推值，与已记录值不可区分

| 字段 | 值 |
| --- | --- |
| 位置 | `:56-63` |
| 级别 | Info |
| 证据 | E1 |

`phaseInfo(n)` 用 `_segmentPhaseIndex.nearest(n)` 取「不大于 `n`」的最近段，再按段长外推。对已生成的 Phase 这是精确值；对 `n > currentPhase()` 这是**预测值**，下一次 `sync` 调整后就会变。两个区间返回同一种结构、没有 `recorded` 标志，调用方无法区分。链下如果拿 `phaseInfo` 去做「下一轮开始时间」的硬编码，会与链上实际边界不一致。建议在规格里注明「`n > currentPhase()` 时为预测值」，或增加一个返回 `bool recorded` 的重载（会改 ABI，非必要）。

### PHS-01 复核：无上下限，但采样点不是自由旋钮

既有审查把 `PHS-01` 记为「`observed` 原样写成下一段长度，无上界；采样点由调用者选」。本卷复核后确认前半句，**修正后半句的强度**：

```text
observed = floor(elapsedBlocks * TARGET_SECONDS / elapsedSeconds)
```

`observed` 是**速率量**：`elapsedBlocks / elapsedSeconds` 是所选区间内的平均出块速率，乘以目标秒数就是「按这个速率，一个目标周期会出多少块」。调用者能选的只是区间**终点**（何时调用 `sync`）；起点由「最新一条早于 `phaseBlocks` 的观测」规则确定（`:96-101`）。因此：

- 出块速率恒定时，无论何时调用，`observed` 只取决于该速率与 `TARGET_SECONDS`（与采样点无关），采样点没有杠杆；
- 只有速率本身在区间内不均（出块突发、链停摆后恢复、测试链按需出块）时，选终点才能「截取」一个有利的平均值；
- 一旦截取成功，`_recordNextSegment` 把它固化成整段，直到下一次调整。

所以 `PHS-01` 的真实风险是「**无步长限幅**」而不是「采样点可任意操纵」。建议的修法不变：把 `newPhaseBlocks` 夹在 `[phaseBlocks/2, phaseBlocks*2]`（或类似的显式上下界）内，再配合已有的 `ADJUST_THRESHOLD`。这不会消除速率跟踪，只会消除单次异常观测的持久化。

## 5. 已核对为正确的点

- `_lastSyncPhase` 在函数体早期写、且在任何可能回滚的计算之前；失败不消耗同步机会。
- 观测扫描的下标边界正确：`for (i = count; i > from; ) { --i; ... }` 覆盖 `count-1 .. from`，不会越界。
- `selected` 一定小于 `count`（循环内或 `nearest` 换算得到），因此 `push` 不会影响 `_observationBlocks[selected]` 的读取。
- `elapsedBlocks > 0 && elapsedSeconds > 0` 双守卫，排除了同块、同秒的除零。
- `_previewReclassification` 式的「先判零再除」在本合约同样成立：`phaseAtBlock` 在 `nearest` 未命中时早退，`phaseInfo` 由 `phaseNumber == 0` 早退。
- 构造器只写 `_segmentByPhase/StartBlock` 一次（`Segment(1, origin, L)`），没有「空索引」窗口。

## 6. 覆盖缺口

- 未构造「同一 Phase 二次 sync」「跨多个 Phase 不 sync 后一次补上」的测试；P3/P4 由归纳法推导。
- 构造参数（`ORIGIN_PHASE_BLOCKS > 0`、`ADJUST_THRESHOLD <= 1e18`）由部署脚本校验，合约侧无守卫；`ORIGIN_PHASE_BLOCKS == 0` 会让 `phaseAtBlock` 在第一次除法时 Panic，属于「参数错即全协议停摆」的单点。
