# `action/LpRoundAxis.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/02-phase-model.md`。
> 范围：`src/LpRoundAxis.sol`（16 行）。本文件不声明错误、不 import 错误接口、不含 `revert`。

## 1. 结论

- **0 个错误声明 / 0 个发送点**：本库只做 `phase → round` 纯换算，未开始的表达方式是**返回 0 哨兵**，不是回滚。
- 这是 02-phase-model 明文规定的分层：「轴库只做纯换算，不 import 错误接口；未开始守卫由消费方承担」。因此「错误目录」在本文件为空，`RoundNotStarted(1, 0)` 的站点记在消费方（`02-ExecutorBase.md`、`06-GroupActionManager.md`）。
- 换算口径核对无误：`joinRound = phase < 2 ? 0 : phase - 1`、`mintRound = phase < 3 ? 0 : phase - 2`，与 02 的 LP 三阶段映射一致。

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

无。`round == 0` 的失败由消费方转成 `RoundNotStarted(1, 0)`：

| 消费方 | 站点 | 守卫 |
| --- | --- | --- |
| `ExecutorBase.currentJoinRound` | `ExecutorBase.sol:94` | `round == 0` |
| `ExecutorBase.currentMintRound` | `ExecutorBase.sol:102` | `round == 0` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-LRA-01 | Info | `src/LpRoundAxis.sol:7-15` | 「未开始返回 0」这一契约只存在于注释缺失的实现与规格正文里，函数签名是裸 `uint256`，调用方无法从类型上区分「未开始」与「Round 0」。当前两个消费方都做了守卫，但新增调用点时漏判会静默得到 0（例如把它当 `offset` 或 `round` 继续算）。 | error-standards §5（失败契约须可读出）；02-phase-model「轴库只做纯换算」 | 保持现状（分层是刻意的）；在 02-phase-model 的「实现分层」段补一句「两个轴库对未开始返回 0，调用方必须守卫，否则 0 会作为合法轮次流入账本」。 |

### 4.2 已核对项

- 无错误声明、无 `revert`、无 `require`、无 `assert`；不 import 任何 `*Errors` 接口，符合 02 的分层要求。
- `joinRound` 与 `GroupActionRoundAxis.joinRound` 逐字相同（`phase < 2 ? 0 : phase - 1`），两个 Executor 的加入轮同轴；`test/RoundAxis.t.sol:117` 的 `testJoinGuard` 固化了该边界。
- `mintRound` 比 `GroupActionRoundAxis.mintRound` 早一个 Phase（LP 三阶段 vs 链群四阶段），`test/RoundAxis.t.sol:109` 的 `testLpMintsOnePhaseEarlierThanGroup` 固化了该差异。
- `phase = 0` 时两个函数都返回 0，无下溢（`phase - 1` 与 `phase - 2` 只在 `phase >= 2/3` 时求值）。

### 4.3 透传错误面

无外部调用。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test --match-contract RoundAxisTest
```

> 扫描口径：本文件无 `revert <Error>(` 站点，故不进入错误目录；`RoundNotStarted` 的载荷由消费方构造。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-LRA-01 | Info | 已裁决（文档口径）：`LpRoundAxis.mintRound` 补哨兵注释；02 登记类型不可区分、消费方必须显式判 0。 |
