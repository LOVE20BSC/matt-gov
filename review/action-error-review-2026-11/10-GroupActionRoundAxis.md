# `action/GroupActionRoundAxis.sol` 错误赋值与发送专项 Review

> 基线：`action@2014788`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/02-phase-model.md`。
> 范围：`src/GroupActionRoundAxis.sol`（21 行）。本文件不声明错误、不 import 错误接口、不含 `revert`。

## 1. 结论

- **0 个错误声明 / 0 个发送点**：与 `LpRoundAxis` 同构，未开始返回 0 哨兵，守卫在消费方。
- 三段换算核对无误：`joinRound = phase - 1`（`phase >= 2`）、`verifyRound = phase - 2`（`phase >= 3`）、`mintRound = phase - 3`（`phase >= 4`），与 02 的四阶段映射一致。
- 消费方共四处：`GroupActionManager.currentJoinRound`（`06:477-483`）、`GroupActionVerify.currentVerifyRound`（`08:521-527`）、`ExecutorBase` 的两个 getter（经 `09:691-697` 覆写）、`GroupServiceExecutor` 的 `currentVerifyRound` / `_joinRound` / `_mintRound`（`13:87-89`、`:694-700`）。四处都回 `RoundNotStarted(1, 0)`。
- 无 Medium / Low；1 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 0 |
| revert 站点 | 0 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 1 |

## 2. 错误清单

本文件无错误声明，也无 `revert` 站点。

## 3. 逐错误明细

无。三个函数各自的守卫站点：

| 函数 | 守卫站点 | 载荷 |
| --- | --- | --- |
| `joinRound` | `GroupActionManager.sol:480`（共享实现）、`ExecutorBase.sol:94`（`09` 覆写后经基座 getter） | `RoundNotStarted(1, 0)` |
| `verifyRound` | `GroupActionVerify.sol:524` | `RoundNotStarted(1, 0)` |
| `mintRound` | `ExecutorBase.sol:102`（`09` 覆写） | `RoundNotStarted(1, 0)` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GAA-01 | Info | `src/GroupActionRoundAxis.sol:7-20` | 同一个 `joinRound` 有两条守卫路径：`GroupActionManager.currentJoinRound`（库内 `internal`，被 `GroupActionJoin` 内联）与 `ExecutorBase.currentJoinRound`（ABI getter，被 `09` 覆写）。两者载荷相同（02 明文「两条路径回滚同一载荷」），但**判定点不同**：前者在业务入口内、后者只服务查询与 `GroupService` 的 `join`/`exit`。新增业务入口时容易只走其中一条。 | error-standards §5（同一条件同一表达）；02-phase-model「实现分层」 | 保持现状；建议在 02 的「实现分层」段列出「哪些入口走共享实现、哪些走基座 getter」的对照表（即本报告第 3 节）。 |

### 4.2 已核对项

- 无错误声明、无 `revert`、无 `require`、无 `assert`；不 import 任何 `*Errors` 接口。
- 三个函数的 `phase` 下界与 02 的表格逐条一致（`p-1` / `p-2` / `p-3`），`phase = 0` 时全部返回 0，无下溢。
- `GroupService` 复用本库的 `joinRound` / `mintRound`（`:694-700` 的覆写），因此服务与源行动的加入/铸造轮同轴；该同轴性有 `// Load-bearing:` 注释登记（`13:690-693`），是本轮 review 中唯一「两侧漂移会静默错位」的换算点。
- `test/RoundAxis.t.sol:75` 的 `testGroupActionAxis` 与 `:101` 的 `testGroupStepsStayOrdered` 固化了三段递增与边界。

### 4.3 透传错误面

无外部调用。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
forge test --match-contract RoundAxisTest
```

> 扫描口径：本文件无 `revert <Error>(` 站点；守卫站点按「谁 import 了 `IActionExecutorErrors`」归属到消费方文件。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GAA-01 | Info | 已裁决（文档口径）：02 登记两条 `joinRound` 守卫入口同源、载荷一致 `(1, 0)`。 |
