# LpRoundAxis · 状态变量变更审查

> `action/src/LpRoundAxis.sol`，**修复后 11 行**（基线 16 行，join 已移出），`action@0c1d1e2`。
> 职责：LP 行动的 `phase → round` 类型专属换算，仅 `mintRound`；`joinRound` 已删除，加入轮统一由 `ActionRoundAxis` 定义、`ExecutorBase._joinRound()` 单一实现。LP 是三阶段，**没有验证轮**，因此本文件比 `GroupActionRoundAxis` 少一个函数——这个「少」本身是规格要求。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

无。文件内没有状态变量、常量、struct 或 mapping。

| 函数 | 签名 | 返回 | 说明 |
| --- | --- | --- | --- |
| `mintRound` | `(address phaseAddress) → uint256` | `phase < 3 ? 0 : phase − 2` | 铸币轮 |

唯一函数是 `internal view`，编译期内联。

## 2. 逐变量变更逻辑

无状态写入。唯一外部读是 `IPhase(phaseAddress).currentPhase()`。

| 函数 | 阈值 | 与 GroupAction 的差异 |
| --- | --- | --- |
| `mintRound` | `phase < 3` | GroupAction 是 `phase < 4`（多一个验证阶段） |

LP 的铸币轮比 GroupAction 早一轮，因为 LP 没有验证阶段：`phase N` 的 LP 行动在 `phase N+2` 就能铸币，而 GroupAction 要等到 `phase N+3`。加入轮不再属于类型轴：两个 Executor 都经 `ExecutorBase._joinRound()` → `ActionRoundAxis`。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| Y1 | `ActionRoundAxis.joinRound(p) == mintRound(p) + 1`（两者都非 0 时） | ✅ | join 与 mint 的偏移同源 |
| Y2 | `ActionRoundAxis` 是 join 的唯一实现，`LpRoundAxis` 不含 join | ✅ | `LpExecutor` 经 `ExecutorBase._joinRound()` 取加入轮（`SUP-02` 已收敛） |
| Y3 | 没有 `verifyRound` | ✅ | 文件只剩 `mintRound`；LP 无验证阶段（`02-phase-model.md:6`） |
| Y4 | 函数不回滚 | ✅ | 无 require |

## 4. 发现

### M-AXS-03 · LP 的 `mintRound` 比 GroupAction 早一轮，但两个 Executor 共用同一个 `_checkMintWindow`

| 字段 | 值 |
| --- | --- |
| 位置 | `:12-15`、`GroupActionRoundAxis:17-20`、`ExecutorBase:107-128` |
| 级别 | Info |
| 证据 | E1 |

`_checkMintWindow` 是基类共享的，它只接收 `mintRound`（由子类的 `_mintRound()` 提供），因此两个 Executor 的窗口边界不同但判定逻辑相同：

| Executor | 最早可铸币的轮 | 对应 Phase |
| --- | --- | --- |
| `LpExecutor` | `phase − 2` | `phase = round + 2` |
| `GroupActionExecutor` / `GroupServiceExecutor` | `phase − 3` | `phase = round + 3` |

差异本身是设计（`02-phase-model.md:10-14` 的表）。本卷记录的是**状态后果**：同一个 `round` 在两个 Executor 上的「可结算时点」差一个 Phase，而 `ActionTarget._createdRoundByActionId`、`joinedAmountByActionId` 等跨 Executor 共享的状态是同一份。链下按 `round` 聚合「本轮可结算的行动」时必须按 Executor 分开算窗口，不能用一个全局 `mintRound`。

`LpExecutor.memberReward`（`:387-390`）与 `GroupActionExecutor.memberReward`（`:652-656`）都用自己的 `_mintRound()`，因此视图侧是正确的；错的只可能是链下的聚合口径。

### M-AXS-04 · 两个轴库的 `joinRound` 逐字节相同，但分别被两个不同的 Executor 依赖，改一处不会触发编译错误

| 字段 | 值 |
| --- | --- |
| 位置 | 修复前：`LpRoundAxis:7-10`、`GroupActionRoundAxis:7-10`；修复后：两库均无 join，`ActionRoundAxis:9` 唯一 |
| 级别 | Info |
| 证据 | E1 |

修复前两个函数体完全一致（`phase < 2 ? 0 : phase - 1`）。`SUP-02`（api-auth）已登记这个重复，本卷补的是**状态后果**：

- `LpExecutor._joinRound()` 与 `GroupActionExecutor._joinRound()` 修复前都调各自的轴库；修复后 override 删除，`ExecutorBase._joinRound():134` 是唯一实现；
- 两者都用 `_joinRound()` 做读面上界（`joinedAmountByActionId:394`、`GroupActionExecutor:618`）；
- `ActionTarget.registerJoinState` 曾用**第三份**副本（见 `12-group-action-round-axis.md` 的 M-AXS-01）。

因此修复前「加入轮」这个概念在全仓有 3 个表达式（2 个轴库 + `ActionTarget`）+ 各 Executor 的 override 转发，改一处不会让任何编译单元失败，只会让某条链的轮次错位一格。

修复方向：把 `phase − 1` 收进一个不依赖业务类型的共享库，让「加入轮」只有一个定义。

**处置（已修复，最终形态）**：`joinRound` 只在 `ActionRoundAxis:9` 定义一次。`ExecutorBase._joinRound():134` 去掉 `virtual`、改为单一实现；三个 Executor（含 `LpExecutor`）的 override 全部删除；`ActionTarget._joinRound()` 与 `GroupActionManager:378/485` 直接调 `ActionRoundAxis`。`LpRoundAxis.joinRound` 与 `GroupActionRoundAxis.joinRound` 已删除，两个类型轴库只保留 `mintRound`（16 → 11 行 / 21 → 16 行）。**剩余重复只有 `mintRound`**（LP `phase − 2` / Group `phase − 3`），这是业务类型差异、本就不应合并，作为登记事实而非缺陷保留。`check_caller_auth.py` 与 `forge lint` 不覆盖跨文件重复的问题不再适用于 `joinRound`（它已无重复）。

## 5. 已核对为正确的点

- 没有虚构 `verifyRound`，符合「LP 不提供虚构的验证接口」（`02-phase-model.md:6`）。
- `phase < 3` 的阈值保证减法不下溢（join 的 `phase < 2` 阈值在 `ActionRoundAxis` 里同样保证）。
- 返回 0 的哨兵在三个 Executor 中同语义；加入轮统一由 `ActionRoundAxis` 的 `phase < 2` 阈值给出，`_joinRound()` 在冷启动期行为一致。
- 唯一函数是 `internal`，不进 ABI、不产生部署地址。
- `LpExecutor` 的三个 Round getter（`currentVoteRound` / `currentJoinRound` / `currentMintRound`）全部走 `ExecutorBase`，没有在本合约里另写一套换算。

## 6. 覆盖缺口

- 未验证 LP 在 `phase == 2` 时「加入轮 1、铸币轮 0」的组合下 `memberReward` 的返回值（按 `_mintRound() == 0` 且 `round >= createdRound >= 1` 应返回 `(0,0,false)`，未跑用例）。
- 未审 LP 的三阶段与 GroupAction 的四阶段在同一 `Phase` 下的交错（例如同一轮里 LP 已可铸币而 GroupAction 还在验证），该交错是设计，但未做端到端时间线验证。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-AXS-03` | 规格补写 | [`02-phase-model.md`](../../docs/specs/action/02-phase-model.md) 的「轴库与哨兵」：同一 `round` 在各 Executor 的可结算时点差一个 Phase，链下必须按 Executor 分窗口 |
| `M-AXS-04` | 已修复（`joinRound` 最终收敛） | `joinRound` 只在 `ActionRoundAxis:9` 定义；`ExecutorBase._joinRound():134` 单一实现（非 virtual），三个 Executor override 与两个类型轴库的 join 全部删除；剩余重复只有按类型本就不同的 `mintRound`，登记为事实（见本条处置） |
