# 行动阶段与 Round

所有行动有投票、加入、铸币流程；加入阶段包括加入、退出及资产/参与状态变化。各 Executor 从 `Phase.currentPhase()` 计算业务 Round，不把当前 Phase 号直接当作所有阶段的 Round。

## 阶段映射

令 `p = currentPhase()`，下表保留当前 Action 规格的映射：

| Executor | 投票 Round | 加入 Round | 验证 Round | 铸币 Round |
| --- | --- | --- | --- | --- |
| LP（三阶段） | p | p - 1 | 无独立验证阶段 | p - 2 |
| GroupAction（四阶段） | p | p - 1 | p - 2 | p - 3 |
| GroupService（四阶段） | p | p - 1 | p - 2，复用行动结果 | p - 3 |

计算结果小于 1 时，阶段尚未开始，查询和操作回滚 `RoundNotStarted(1, 0)`（`requiredRound` 为 1，`currentRound` 为推导出的 0），不得返回 0。结果有效只表示阶段已开始，实际参与或铸币条件仍由 Executor 校验。获得票的 Proposal 在全局 Phase 增加一后开放加入；此时加入 Round 为当前全局 Phase 减一。

投票、加入、铸币 Round 见 [`IActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionExecutor.sol)。GroupAction 和 GroupService 额外提供 `currentVerifyRound()`；LP 不提供虚构的验证接口。加入类写操作只写当前加入 Round，验证只接受当前验证 Round，历史领取允许 `1 <= round <= currentMintRound()`。

实现分层：`GroupActionRoundAxis`（join/verify/mint）与 `LpRoundAxis`（join/mint）只做 `phase → round` 纯换算，入参是 Phase 地址、不 import 错误接口。未开始守卫由消费方承担：Executor 基座的 `currentVoteRound`/`currentJoinRound`/`currentMintRound` 是 ABI 查询入口；业务模块内部用到时，`GroupActionManager.currentJoinRound` 与 `GroupActionVerify.currentVerifyRound` 是共享实现，其他模块以 `internal` 内联复用。两条路径回滚同一载荷 `RoundNotStarted(1, 0)`。

**轴库分层**：加入轮（`phase < 2 ? 0 : phase − 1`）只在中立库 `ActionRoundAxis` 定义一次。`GroupActionRoundAxis` 与 `LpRoundAxis` 的 `joinRound` 都委托它，`ActionTarget` 也直接调用它，不存在内联副本或第三份同式。类型轴只保留各自类型专属的偏移：`GroupActionRoundAxis` 的 `verifyRound`（`phase − 2`）与 `mintRound`（`phase − 3`）、`LpRoundAxis` 的 `mintRound`（`phase − 2`）；这些偏移按业务类型本就不同，不合并。底座共用合约不依赖带业务类型名字的库。

冷启动示例：

| 当前 Phase | 已开始的最早业务 |
| --- | --- |
| 1 | Round 1 投票 |
| 2 | Round 1 加入；Round 2 投票 |
| 3 | Round 1 LP 铸币及 GroupAction 验证；Round 2 加入 |
| 4 | Round 1 GroupAction/GroupService 铸币；其他轮次继续流水运行 |

例：Phase 5 的加入 Round 为 4；LP 铸币 Round 为 3，链群/服务铸币 Round 为 2。

## 服务验证复用

服务 Proposal 面向整个 `actionTokenAddress` 社区的 GroupAction，不只绑定一个行动。服务在 Phase `N + 3` 结算 Round N，逐项读取 GroupAction 在 Phase `N + 2` 的同一 Round N 激励。

每个 GroupAction 的激励查询已包含源行动的验证和激励条件，GroupService 不重复筛选。行动层激励查询按轮次读取，目标轮未完成验证时返回 0，不返回部分结果；服务与链群行动阶段划分相同，Round N 的验证在 Phase `N + 2`、结算在 Phase `N + 3`，服务读取的轮次此时已经完成验证，正常不会命中该分支。不要求 GroupAction 先完成铸币，也不在 GroupService 内执行验证。聚合与分配公式见 [服务 Executor](06-service-executor.md)。

实现与组织上下文一致：LP 为三阶段，GroupAction 和 GroupService 为四阶段。

## 轴库与哨兵

- 加入轮由 `ActionRoundAxis.joinRound` 唯一定义（`phase < 2` 时为 `0`）；`ExecutorBase._joinRound()` 是它的单一实现点（非 `virtual`，三个 Executor 不再 override），`ActionTarget._joinRound()` 与 `GroupActionManager` 两处直接调用也走同一函数。`GroupActionRoundAxis` / `LpRoundAxis` **不含** `joinRound`。铸币轮由三个类型轴派生（GroupAction `phase < 4`、GroupService `phase < 4`、LP `phase < 3` 时为 `0`）。`0` 是「阶段未开始」的唯一哨兵，真实轮次从 `1` 起。
- 哨兵有两种消费方式：守卫式（调用方先判 `== 0` 并报 `RoundNotStarted(1, 0)`）与透传式（原样返回 0 交给下游比较）。铸币面已统一为守卫式；加入面仍为透传式，但 `round == 0` 在加入入口不可达。
- 同一 `round` 在各 Executor 的可结算时点相差一个 Phase（LP 三阶段、GroupAction/GroupService 四阶段），链下必须按 Executor 分窗口取数，不能按统一 `mintRound` 聚合。
- `ActionTarget` 的加入轮同样走 `ActionRoundAxis.joinRound`（经自身 `_joinRound()`），`registerJoinState` 不再内联 `currentPhase() - 1`；与 `ExecutorBase` 的单一实现同一来源。

## 错误卷补记（2026-11，X-09）

- `E-LRA-01`：三条轴函数签名为裸 `uint256`，「未开始」只能靠 `0` 约定表达，类型上不可区分；所有消费方必须显式判 `== 0`，新增调用点漏判会静默得到 0。`LpRoundAxis.joinRound`（实为 `mintRound`，LP 无加入轴）已补注释说明该哨兵。
- `E-GAA-01`：`joinRound` 的守卫有两条入口（库 `GroupActionManager.currentJoinRound` 与 `ExecutorBase._joinRound`），两处都读同一 `ActionRoundAxis`，载荷一致 `(1, 0)`，不存在分叉。
