# core/ 分层安全审查 · 2026-11

> 基线 `9297a33`（core 仓工作树在审查开始时为空）。范围：`core/src/` 全部 8 个实现文件 **4036 行** + 10 个自有接口 + 3 个 `libs` 库。
> 判据：**设计合理性**。规格文档只当背景，不作判据。
> 产出边界：含 PoC，不含修复（`src/` 一行未改；新增仅 `core/test/audit/`）。

## 一页结论

| 项 | 数值 |
| --- | --- |
| 单元 | 29 个全部到「已审」 |
| 登记项 | 22 条（High 1 / Medium 3 / Low 7 / Info 11）；另有 1 条已排除记录 STK-06 |
| 设计命题 | D-01..D-10 全部三档判定：兑现 2 / 可接受 7 / 缺陷 1 |
| 路径 | P-01..P-08 全部给出明确判定，无「待观察」 |
| 预置假设 | §2.4 的 14 组全部给出成立/不成立 |
| PoC | 11 个（10 条复现/性质断言 + 1 条 gas 上界），全部 E3，随 `core/test/audit/` 落地 |
| 门禁 | build / lint / test **484 passed** / events 28 / deploy-scripts 41 全绿 |

**最需要看的四条**

1. **STK-01（High）**：提交门槛 `SUBMIT_MIN_RATIO` 乘的是一个**活的、成员可自行放大的**分母。任何达到门槛的成员花 **1 wei** 把 `promisedWaitingPhases` 拉到上限，就能把门槛抬到其他所有人票权之上，并**永久**（该值只增不减）把他人排除在提案通道外。无资金损失，损失的是治理提案权。
2. **MNT-01（Medium）**：每轮奖池大小不是轮次结束时定的，而是**该轮第一个 mint 时**按当时的 `rewardAvailable()` 定的。抢先 mint 后一轮，可把前一轮的池子压到 17/20（实测）。
3. **NFT-01（Medium）**：身份名唯一性只做 ASCII 小写折叠。U+180E 这类不可见码点被接受，两个视觉完全相同的名字可以共存。
4. **DEP-01（Medium）**：7 个 `init` 无调用者限制，而部署是 `--slow` 逐笔广播、校验在 `stopBroadcast()` 之后。抢跑即产生 8 个不可删除的孤儿合约，接线与常量由首个调用者决定。

**没有找到的东西，也要说清楚**：`Stake` 是唯一托管资产的合约，逐函数走完后没有找到可窃取路径。份额定价恒等式 `shares = S·lpMinted/W` 与提取 `lp = s·W/S` 互为逆运算，W/S ≤ 1 恒成立（证明见 `03-findings/stake.md` 的 STK-06 已排除项）；结算、销毁、boost 退款三条出口都被账本或余额约束住。Mint 的「越预留」假设（M4）经代数验证**不成立**：`eligibleVoteAmount` 与逐提案分配用的是同一集合，Σ ≤ 池。

## 怎么读

按「想回答什么问题」挑，不必顺序读：

| 你想知道 | 打开 |
| --- | --- |
| 结论、严重度分布、部署清单、还剩什么风险 | `08-final-report.md` |
| 某条到底是不是真问题、怎么复现 | `03-findings/`（按模块拆 6 页 + 1 页索引） |
| 这个机制值不值得这么设计 | `04-design-notes.md`（D-01..D-10） |
| 跨合约的攻击序列能走通吗 | `05-paths/P-0x.md` |
| 29 个单元审到哪了、每条假设的判决 | `02-registry.md` |
| 合约面、资产出口、外部调用、参数域、部署顺序 | `01-architecture-map.md` |
| 门禁怎么跑的、slither 报了什么 | `00-baseline.md`、`06-tool-crosscheck.md` |
| 要人工复核 High/Medium，怎么走 | `09-signoff.md`（逐跳表 + 可证伪检查 + 签字栏） |
| PoC 源码与日志 | `evidence/`（源码另存于 `core/test/audit/`） |

## 目录

```text
README.md                     本页
00-baseline.md                冻结、门禁、证据等级、严重度口径
01-architecture-map.md        表 A–F（合约面/资产出口/外部调用/参数域/部署序列）
02-registry.md                29 单元进度 + 14 组预置假设判决（唯一进度真相）
03-findings/
  README.md                   22 条登记项索引（按严重度 / 按模块）
  stake.md                    STK-01..05 + STK-06 已排除记录
  mint.md                     MNT-01..05
  launch.md                   LCH-01..04 + DEP-01
  membernft.md                NFT-01..03
  submit-vote-phase.md        PHS-01 / VOT-01 + Submit 两条已验证结论
  token-interfaces.md         TOK-01..02
04-design-notes.md            D-01..D-10 三档判定
05-paths/P-01..P-08.md        8 条跨文件路径，每条一页
06-tool-crosscheck.md         slither / gas / ABI / storage 对账
07-fix-review.md              本次不含修复，留空
08-final-report.md            汇总与部署清单
09-signoff.md                 人工复核工作表（High/Medium 逐跳 + 签字栏）
evidence/                     门禁日志、slither 原文、PoC 日志与源码副本
```

## 与计划的两处偏离

| 项 | 计划 | 实际 | 原因 |
| --- | --- | --- | --- |
| 产物目录 | `core-review-2026-11/`（§6） | `core-review-plan-2026-11/` | 按「与计划文档同名」落盘；内容与 §6 的清单一一对应 |
| 真 V2 夹具 | 新增 `test/integration/StakeRealDex.t.sol` | 新增 `test/audit/RealV2.sol`（忠实子集）+ `test/audit/AuditPoC.t.sol` | `dex/lib/v2-core` 钉在 `=0.5.16`、Router 是 `=0.6.6`，与 core 的 `=0.8.37` 不能同次编译，所以按同一语义重写子集；计划要的 6 个场景（首存/捐赠重分类/单次结算/双币取整/零 LP/预建 Pair）都在 `AuditPoC.t.sol` 里跑通。子集含 `MINIMUM_LIQUIDITY`、0.3% 费率、k 校验、`sync`、`skim`、`lock` |
