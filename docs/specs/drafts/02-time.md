# 阶段与轮次

> 早期技术草稿，保留条款编号供追溯。现行开发规格见 [Core 阶段规则](../core/03-phase.md)和 [Action 轮次规则](../action/02-phase-model.md)。

<a id="TM-01"></a>

## TM-01 阶段编号

**级别**：必须

`block.number == ORIGIN_BLOCKS` 时为 Phase 1；不存在有效的 Phase 0。`block.number < ORIGIN_BLOCKS` 时，`currentPhase()` 与 `phaseAtBlock(block.number)` 返回 `0`。

`ORIGIN_BLOCKS` 为部署后冻结的值。

<a id="TM-02"></a>

## TM-02 阶段边界

**级别**：必须

`phaseInfo(phaseNumber)` 返回该阶段的起始区块与区块数。`phaseInfo(0)` 以 `PhaseNotStarted()` 回滚。查询未来阶段时，按当前已记录的阶段长度推算。校准的生效范围见 [TM-04](#TM-04)。

<a id="TM-03"></a>

## TM-03 同步的机会

**级别**：必须

任何地址都可调用 `Phase.sync()`。创世前调用以 `PhaseNotStarted()` 回滚。每个阶段首次成功同步时记录本阶段并追加一条观测（`block.number`、`block.timestamp`）。在同阶段重复调用直接返回 `(false, currentPhaseBlocks)`，保持已有状态。

判断本阶段是否已同步，读 `lastSyncPhase() == currentPhase()`。不能用 `PhaseSynchronized` 的事件条数推断，因为重复调用静默返回、不发事件。

<a id="TM-04"></a>

## TM-04 校准

**级别**：必须

只有 `deviation > ADJUST_THRESHOLD` 才调整；等于阈值时不调整。

```text
observed  = floor(elapsedBlocks * TARGET_SECONDS / elapsedSeconds)
deviation = floor(abs(observed - currentPhaseBlocks) * 1e18 / currentPhaseBlocks)
newPhaseBlocks = max(1, observed)
```

从最新记录往回找，选择第一个区块差大于 `currentPhaseBlocks` 的观测。区块差和时间差取该观测到本次同步的值。没有合格观测或时间差为零时，只记录观测。调整从下一阶段起生效，当前及过去阶段的编号和边界保持原值。

<a id="TM-05"></a>

## TM-05 同步事件的快照语义

**级别**：必须

每个阶段首次成功同步时发出一条 `PhaseSynchronized`。事件中的 `currentPhaseBlocks` 是当前阶段的长度，`nextPhaseBlocks` 是下一阶段的长度。两者相等时，下一阶段与当前阶段长度相同。

相邻两次有效同步中，后一条事件的 `currentPhaseBlocks` 等于前一条事件的 `nextPhaseBlocks`，即使期间有阶段没有发生同步。

<a id="TM-06"></a>

## TM-06 治理轮

**级别**：必须

`Submit.currentRound()` 与 `Vote.currentRound()` 等于 `Phase.currentPhase()`。推举和投票计入当前治理轮。

当 `currentPhase() > N` 时，治理第 `N` 轮结束，铸造该轮核心激励的时间门槛才满足。轮内可预留激励。

<a id="TM-07"></a>

## TM-07 四类流水线的阶段偏移

**级别**：必须

第 `N` 轮的各环节对应如下阶段号。

| 轮次类型 | 投票 | 加入 | 验证 | 铸造时间门槛 |
| --- | --- | --- | --- | --- |
| 治理轮 | `N` | — | — | 阶段 `N` 结束后 |
| LP 行动轮 | `N` | `N + 1` | — | 阶段 `N + 2` 起 |
| 链群行动轮 | `N` | `N + 1` | `N + 2` | 阶段 `N + 3` 起 |
| 链群服务轮 | `N` | `N + 1` | `N + 2`，复用链群行动的验证结果 | 阶段 `N + 3` 起 |

例如当前阶段为 10 时，链群行动正在为第 10 轮投票、第 9 轮加入、第 8 轮验证，第 7 轮已达到铸造的时间门槛。加入环节包含行动的加入和退出。

行动执行合约的 `currentVoteRound()`、`currentJoinRound()`、`currentMintRound()` 及链群行动和链群服务的 `currentVerifyRound()`，在对应环节尚未开始时以 `RoundNotStarted(1, 0)` 回滚。`1` 是该环节的首个轮次，`0` 表示尚未开始。按编号查询未来的加入轮次时，错误参数为 `RoundNotStarted(请求轮次, 当前加入轮次)`。

## 不承诺事项

- 阶段的实际自然时长和确切结束时间。
- 开放同步调用的发起者与具体执行区块。
- `PhaseSynchronized` 与同一交易中其他合约事件的相对顺序。
- 调用的 Gas 消耗。

## 验收

| 条款 | 测试 |
| --- | --- |
| TM-01 ~ TM-02 | `core/test/Phase.t.sol` |
| TM-03 ~ TM-05 | `core/test/Phase.t.sol` |
| TM-06 | `core/test/Submit.t.sol`、`core/test/Vote.t.sol`、`core/test/Mint.t.sol` |
| TM-07 | `action/test/LpExecutorEdgeCases.t.sol`、`action/test/GroupActionExecutor.t.sol`、`action/test/GroupServiceConstructor.t.sol` |
