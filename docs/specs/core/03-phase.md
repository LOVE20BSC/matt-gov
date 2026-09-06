# Phase 与 Round

Phase 维护连续的无语义时间片、同步观测和动态校准，不内置 Vote、Join、Verify、Mint 或业务 Round。不能把旧静态 Phase 直接作为本版实现。

## 参数与查询

`originBlocks`、初始 `phaseBlocks`、`targetDays` 为正数；`adjustThreshold` 使用 `1e18` 精度且大于零。`block.number == originBlocks` 时为 Phase 1；不存在有效 Phase 0。`targetSeconds = targetDays * 86400`，如 7 天。

| 接口示意 | 返回或作用 |
| --- | --- |
| `currentPhase()` | 当前区块的 Phase |
| `phaseInfo(phaseNumber)` | 阶段起始区块和区块数 |
| `phaseAtBlock(blockNumber)` | 指定区块的 Phase |
| `syncObservationsCount()` | 同步观测数量 |
| `syncObservation(observationId)` | 按从 1 开始的 ID 读取观测 |

公开查询接口：

```solidity
function currentPhase() external view returns (uint256 phase);
function phaseInfo(uint256 phaseNumber)
    external view returns (uint256 startBlock, uint256 phaseBlocks);
function phaseAtBlock(uint256 blockNumber) external view returns (uint256 phase);
function syncObservationsCount() external view returns (uint256 count);
function syncObservation(uint256 observationId)
    external view returns (uint256 blockNumber, uint256 blockTimestamp);
```

同步接口为：

```solidity
function sync() external returns (bool adjusted, uint256 newPhaseBlocks);
```

## 同步

任何地址可调用 `sync`，但同一 Phase 实例在每个治理投票 Round 最多执行一次有效同步。治理 Round 与 Phase 一对一，因此按调用前的 `currentPhase()` 全局限频，不按 token 或调用者分别计数。

维护 `lastSyncPhase`，初值为 0。若等于本次 Phase，直接返回 `(false, currentPhaseBlocks)`，不追加观测、不调整参数、不发事件；否则记录本 Phase 并追加 `block.number`、`block.timestamp`。首次同步或未达到调整条件仍消耗本轮同步机会，失败回滚则不消耗。

每轮首个成功推举仍自动调用 `sync`；如果已经有人同步，自动调用无操作返回，不能阻塞推举。没有推举时任何人仍可同步；投票和铸造本身不触发同步。无人调用也不停止 Phase 推进。

首次有效同步只记录观测；调整时发出 `PhaseAdjusted`。新参数不得改变当前或过去 Phase 的编号和边界，不能通过校准重获本轮同步机会。`adjusted = false` 时，`newPhaseBlocks` 返回当前值。

## 校准

1. 先从最近观测向前检查最多 10 条；仍未找到合格观测时，用二分查找最近的合格观测。
2. 对满足条件的记录计算以下公式，除法向下取整。
3. `deviation > adjustThreshold` 才调整，等于阈值时不调整。
4. 新长度至少为 1，只用于尚未生成的 Phase，已生成阶段不回写。

```text
observedPhaseBlocks = floor(elapsedBlocks * targetSeconds / elapsedSeconds)
deviation = floor(abs(observedPhaseBlocks - currentPhaseBlocks) * 1e18 / currentPhaseBlocks)
newPhaseBlocks = max(1, observedPhaseBlocks)
```

`deviation` 是比例表达式，不能先用整数除法截成零再与阈值比较。`elapsedBlocks` 和 `elapsedSeconds` 是选定观测到本次同步的区块差与秒差。

例如当前长度 100、阈值 20% 时，估算 110 保持 100，估算 130 调整为 130。

## 治理 Round

Submit 和 Vote 的 `currentRound()` 等于 `Phase.currentPhase()`。创建、推举、投票仅写当前治理 Round。当前 Phase 大于 N 时，Vote 对外确认 Round N 已结束，Mint 才能准备和铸造其激励。

## 校准边界

- 默认从最近观测向前检查最多 10 条；仍未找到合格观测时，用二分查找最近的合格观测。
- 没有合格观测、`elapsedBlocks == 0` 或 `elapsedSeconds == 0` 时只记录观测，不调整参数。
- 偏差阈值由初始化参数 `adjustThreshold` 提供，按 `1e18` 精度；超过阈值才调整。
- 新长度为 `max(1, floor(elapsedBlocks * targetSeconds / elapsedSeconds))`；已生成 Phase 不回写。

验收见 [Core 验收](08-testing.md)。
