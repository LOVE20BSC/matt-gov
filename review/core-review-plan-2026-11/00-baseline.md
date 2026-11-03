# 00 · 基线

## 冻结

| 项 | 值 |
| --- | --- |
| 提交 | `9297a330269ba74b1fca97a595322f8c449eed5b` |
| 工作树 | `git status --short` 为空（审查开始、结束时各确认一次） |
| forge | 1.8.1（`982849d3`） |
| solc | 0.8.37，`evm_version = osaka`，optimizer 200 runs |
| 源码面 | `src/` 8 文件 4036 行；`src/interfaces/` 10 文件；`libs` 3 文件 144 行 |
| 审查期间 `src/` 改动 | **无** |

比计划 §0.1 少一步：未打 `git tag audit-base`。理由是该 tag 会写进仓的 refs（等于对仓库做一次写操作），而提交哈希本身已经唯一确定基线；本文件与 `evidence/00-gates.log` 记录同一哈希即可复现。

行号基准即 `9297a33`。审查过程中 `src/` 未变，故所有 `文件:行` 可直接对应此提交。

## 门禁（一条命令一条证据，原始输出见 `evidence/00-gates.log`）

| 命令 | 结果 |
| --- | --- |
| `forge build --force --deny warnings` | 通过 |
| `forge lint` | 零输出 |
| `forge test --summary` | **484 passed / 0 failed**（基线 473 + 本次新增 11 个 PoC；复跑记录 `evidence/01-recheck.log`） |
| `env -u PYTHONPATH python3 script/events/check-events.py` | `event manifest OK: 28 events; families OK; declaration style OK; emit style OK; emit keys OK` |
| `env -u PYTHONPATH python3 test/deploy_scripts_test.py` | `Passed 41 isolated deployment checks` |
| `forge build --sizes` | 见下表 |
| `slither . --compile-force-framework foundry` | 259 条结果，17 个检测器，**无 High/Medium 检测器命中**；对账见 `06-tool-crosscheck.md` |

`env -u PYTHONPATH` 是必需的：宿主机 Python shim 的 `sitecustomize` 会拦 `shutil.copytree`，让 `deploy_scripts_test.py` 报假的 `PermissionError`。

### 体积基线（runtime，字节）

| 合约 | runtime | 距 24,576 上限余量 |
| --- | --- | --- |
| `Stake` | 14,585 | 9,991 |
| `Launch` | 12,229 | 12,347 |
| `MemberNFT` | 11,500 | 13,076 |
| `Submit` | 10,861 | 13,715 |
| `Mint` | 10,021 | 14,555 |
| `Vote` | 6,476 | 18,100 |
| `Phase` | 4,000 | 20,576 |
| `LOVE20Token` | 2,384 | 22,192 |

计划 §附 A 的「Stake 14.6 KB / Launch 12.2 KB / Mint 10.0 KB」复核一致。

## 证据等级

| 级 | 含义 | 可支撑的最高严重度 |
| --- | --- | --- |
| E3 | forge 测试复现（真 Core；DEX 侧标注真/假） | High |
| E2 | 精确算术推导 + 极值输入，未跑测试 | Medium |
| E1 | 静态可判定（缺校验、顺序、口径不一致）+ 行号 | Low |
| E0 | 仅工具提示 | 只进线索池 |

本轮的 DEX 侧一律是 **`RealV2.sol`：忠实子集**（含 `MINIMUM_LIQUIDITY = 1000`、0.3% 费率、k 校验、`sync`、`skim`、`lock`、`burn` 按余额比例付款）。它不是 `dex/` 仓的原文（原文 `dex/lib/v2-core` 钉在 `=0.5.16`，与 core 的 `=0.8.37` 不能同次编译），但凡涉及份额、重分类、结算、`_canBurn` 的结论都跑在它上面，且这些结论只依赖上述语义。涉及「余额 vs 储备」差异的地方（捐赠未 `sync`）在正文里单独标注。

## 严重度口径

计划没有定义尺度，本轮的判据如下（先定尺度再判级，避免事后找理由）：

| 级 | 判据 |
| --- | --- |
| **High** | 未授权者以可忽略的成本、确定性地让一个**核心机制**（资金出口或治理通道）对他人**永久**失效 |
| **Medium** | 经济分配被扭曲，或机制在特定参数/时序下退化；有明确的受损方与获利方 |
| **Low** | 边界行为、读写面不一致、依赖特定部署参数才成立 |
| **Info** | 加固建议、可观测性缺口、命名/事件语义、已验证无害的可疑点 |

「设计要求如此」不作为降级理由。任何判为「可接受」的条目必须在 `04-design-notes.md` 里同时给出**约束条件、失效边界、损失承担者**三者，缺一即改判缺陷。

## 本次新增的测试资产

| 文件 | 作用 |
| --- | --- |
| `core/test/audit/RealV2.sol` | UniswapV2 忠实子集（Pair/Factory/Router），供份额与结算类断言使用 |
| `core/test/audit/AuditPoC.t.sol` | 11 个用例：10 条复现/性质断言 + 1 条批量 mint gas 上界；全套真 Core（Launch/MemberNFT/Phase/Stake/Submit/Vote/Mint） |

运行：

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core && forge test --match-path 'test/audit/*' -vv
```

用例与 `03-findings/` 的 F-ID 对应关系见 `evidence/poc.md`。新增的 `test_batchMintGasPerRound` 不指向某条缺陷，只用于 §4.1 的 gas 上界（结果见 `06-tool-crosscheck.md`）。
