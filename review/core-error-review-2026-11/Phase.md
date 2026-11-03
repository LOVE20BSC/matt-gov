# `core/Phase.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/03-phase.md`。
> 范围：`src/Phase.sol`（162 行）+ `src/interfaces/IPhase.sol` 的 `IPhaseErrors`。

## 1. 结论

- 1 个错误声明 / 3 个发送点；无裸 `require`，不可达不变量用 `assert`（符合 §8）。
- `PhaseNotStarted` 的三个站点条件一致（phase/phaseNumber 为 0）。
- 2 条 Info 均为“未开始”契约不一致：`phaseAtBlock` 返回 0 哨兵而非回滚；`phaseInfo` 可外推未来 Phase。
- 构造器不校验参数，除零/越界由 DeployCore 广播前与 21_check 兜底。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 1 |
| revert 站点 | 3 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 2 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `PhaseNotStarted` | `PhaseNotStarted()` | 3 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `PhaseNotStarted` · 3 站点 · 保留

- 声明：`interfaces/IPhase.sol:5`
- 签名：`PhaseNotStarted()`
- 载荷：无
- 赋值链：phase ← `currentPhase()`；phaseNumber ← 入参（`Phase.sol:49-57`、`:87`）。
- 核对：无载荷；三处都是“phase == 0 / phaseNumber == 0”。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Phase.sol:50` | `currentPhaseBlocks` | `phase == 0` | `—` |
| 2 | `Phase.sol:57` | `phaseInfo` | `phaseNumber == 0` | `—` |
| 3 | `Phase.sol:88` | `sync` | `phase == 0` | `—` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-PHS-01 | Info | `src/Phase.sol:65-71` | `phaseAtBlock(blockNumber < ORIGIN_BLOCKS)` 返回 0 作为“未开始”哨兵，而 `currentPhaseBlocks`、`phaseInfo(0)`、`sync` 在 phase 0 回 `PhaseNotStarted`。同一个状态有两种失败契约；03-phase:22 只写“未开始的 Phase 回 PhaseNotStarted”，未写 `phaseAtBlock` 例外。`currentPhase()` 依赖该哨兵，不能简单改成回滚。 | error-standards §2/§5；`03-phase.md:22` | 在 03-phase 补一句“`phaseAtBlock` 对 origin 之前的区块返回 0，不回滚；`currentPhase` 继承该哨兵”。 |
| E-PHS-02 | Info | `src/Phase.sol:56-63` | `phaseInfo(phaseNumber)` 对任意 `phaseNumber > 0` 都按最近 segment 外推，包括未来 Phase；规格只写“阶段起始区块和区块数”，没有写“可查询未来”。同名族的 `currentPhaseBlocks` 只服务当前 Phase。 | error-standards §5（读面契约）；`03-phase.md:14` | 在 03-phase 写明 `phaseInfo` 可外推未来 Phase、不校验是否已开始；若要严格，改为 `phaseNumber > currentPhase()` 回 `PhaseNotStarted`（会改行为）。 |

### 4.2 已核对项

- 声明在 `IPhaseErrors`；实现零声明；无裸 `require`/`revert`。
- 3 个站点条件一致；`sync` 同 Phase 返回 `(false, currentPhaseBlocks)`，不追加观测、不发事件（03-phase:30）。
- `assert(found)` ×3（`:59`、`:140`、`:153`）是不可达不变量，符合 §8“不可达用 Panic，不进错误目录”。
- `check_error_tests.py`：0 untested；`test/Phase.t.sol` 断言 `PhaseNotStarted` 的三个入口。

### 4.3 透传错误面

无外部调用。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/Phase.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/IPhase.sol`。
