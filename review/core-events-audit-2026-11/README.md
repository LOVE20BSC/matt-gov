# Core 事件赋值与发射专项审查（2026-11）

## 1. 范围与方法

| 项 | 内容 |
| --- | --- |
| 对象 | `core/src/` 全部 8 个生产合约 |
| 事件 | 23 个协议事件（另有 5 个 ERC-20 / ERC-721 标准事件，按 §5.4 不属规范正文） |
| 发射点 | 25 个 `emit` 语句 |
| 权威 | `matt-gov/docs/event-standards.md` v1.1（规则）、`docs/specs/core/*.md`（行为） |
| 基线 | `core@78ce1e6`、`matt-gov@8750937`（`78ce1e6` 仅改 Phase 事件、事件清单/族表与测试；其余合约实现自 `6fdd0f1` 未变，行号沿用。`core` 工作区干净，仅 `test/audit/` 未跟踪） |
| 日期 | 2026-11-03 |

每个事件按四层展开，逐层取证：

1. **声明层**：interface 中的字段顺序、indexed 布局、动态字段上限；
2. **赋值层**：每个字段由哪个存储/入参/局部量赋值，读到的是前值还是后值；
3. **时点层**：`emit` 与状态写入、外部调用、转账的相对位置；
4. **顺序层**：同笔多条事件之间、跨合约父子事实之间的依赖序与父子序。

判定依据五类：§6.1 槽位与根键、§3.4 顺序与依赖、§3.1 累计值锚点、§3.5 失败语义、§8.1 测试可判别性。

本目录只记录最终结论，不记录过程稿；历史留痕在 git 提交信息。

## 2. 分合约报告

| # | 合约 | 事件数 | 发射点 | P0 | P1 | P2 | P3 | 报告 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | `LOVE20Token` | 2 | 3 | 0 | 0 | 0 | 0 | [`01-love20token.md`](01-love20token.md) |
| 02 | `Launch` | 5 | 5 | 0 | 0 | 1 | 2 | [`02-launch.md`](02-launch.md) |
| 03 | `MemberNFT` | 1 | 1 | 0 | 0 | 1 | 0 | [`03-membernft.md`](03-membernft.md) |
| 04 | `Phase` | 1 | 1 | 0 | 0 | 0 | 0 | [`04-phase.md`](04-phase.md) |
| 05 | `Stake` | 7 | 7 | 0 | 0 | 2 | 1 | [`05-stake.md`](05-stake.md) |
| 06 | `Submit` | 2 | 2 | 0 | 0 | 0 | 1 | [`06-submit.md`](06-submit.md) |
| 07 | `Vote` | 1 | 1 | 0 | 0 | 2 | 0 | [`07-vote.md`](07-vote.md) |
| 08 | `Mint` | 4 | 5 | 0 | 0 | 2 | 1 | [`08-mint.md`](08-mint.md) |
| — | 合计 | 23 | 25 | 0 | 0 | 8 | 5 | |

机械门禁：`core/script/events/check-events.py` 输出 `event manifest OK: 28 events; families OK; declaration style OK; emit style OK; emit keys OK`（28 = 23 协议事件 + 5 标准事件）。族表 23 行，覆盖全部协议事件；根键首字段与 `round` 锚点全部合规；声明「一参数一行」与 `emit` kv 写法全部合规。

## 3. 问题清单

### P1（0）

无。Phase 的 PH-1 / PH-2 / PH-3 已由 `78ce1e6` 关闭（见 §4.2 与 [`04-phase.md`](04-phase.md)）。

### P2（8）

| ID | 合约 | 一句话 | 位置 |
| --- | --- | --- | --- |
| LA-1 | Launch | `LaunchCountAdded.issuedCount` 与 `memberRemaining` 在夹具中恒等，互换实参测不出 | `Launch.t.sol:1275`、`:1324` |
| MN-1 | MemberNFT | `totalBurnedForMint` 未在 `MemberMinted` 携带后置总量（与 `Stake.totalBurnedToken` 口径不一致） | `MemberNFT.sol:28,83,92` |
| ST-1 | Stake | `LiquidityStaked` 5 个字段未断言，`tokenAmount`/`parentTokenAmount` 在夹具中恒等 | `Stake.t.sol:2102-2113` |
| ST-2 | Stake | `FeesSettled.parentTokenBurned` 从未做取值断言 | `Stake.t.sol:2142` |
| VT-1 | Vote | `VoteCast` 缺成员本轮累计与全局累计票数锚点 | `Vote.sol:256-258,271` |
| VT-2 | Vote | `voterBoost` 与 `totalVoterBoost` 在夹具中恒等，不可判别 | `Vote.t.sol:1353-1375` |
| MI-1 | Mint | `RewardBurned` 不携带累计 `rewardBurned` | `Mint.sol:165,528` |
| MI-2 | Mint | `GovRewardMinted` / `ProposalRewardMinted` 不携带累计 `rewardMinted` | `Mint.sol:208,526` |

### P3（5）

| ID | 合约 | 一句话 | 位置 |
| --- | --- | --- | --- |
| LA-2 | Launch | 首币伴生两条 `LaunchCountAdded` 的发射顺序未断言 | `Launch.sol:199-203` |
| LA-3 | Launch | `GenesisTokenCreated` 前夹了一次无事件的 `MemberNFT.init` 外部调用，E1「登记后立即 emit」不严格 | `Launch.sol:75-78` |
| ST-3 | Stake | `BoostStaked` / `Unstaked` 未断言 `topics[1]`（`tokenAddress`） | `Stake.t.sol:2196`、`:2263` |
| SB-1 | Submit | 首笔推举的 `ProposalSubmitted → Phase.sync` 跨合约顺序未断言 | `Submit.t.sol:409` |
| MI-3 | Mint | 两个 `Minted` 事件的期望值取自被测算函数本身（自证循环） | `MintEvents.t.sol:201,238` |

## 4. 横向结论

### 4.1 事件契约层：两件事做对了，一件事有系统性缺口

**做对的两件：**

- **`Stake` 的聚合量策略是 core 的样板**：三个聚合量（流动性份额、加速份额、治理票）与两个 LP 账本在**每个改变点**都带后置值，且明确说明「`StakeWithdrawn` 不带 `totalValidGovVotes` 是因为票权已在 `unstake` 清零」。这是 §3.1 的正面实现。
- **`Launch` / `Submit` / `Vote` 的「增量 + 后置余额」双字段结构**：账本类事实用增量折叠、用后置值对账，消费者不必反推公式。

**系统性缺口：累计账本没有逐点锚点。** 全仓 8 个「只由单事件类改变」的聚合量中，5 个缺失或部分缺失后置总量：

| 聚合量 | 合约 | 改变点 | 后置总量 |
| --- | --- | --- | --- |
| `totalBurnedForMint` | MemberNFT | `MemberMinted` | 缺（MN-1） |
| `_totalVoteAmountByRound` | Vote | `VoteCast` | 缺（VT-1） |
| `_voteAmountByMemberId` | Vote | `VoteCast` | 缺（VT-1） |
| `_rewardMinted` | Mint | `GovRewardMinted` / `ProposalRewardMinted` | 缺（MI-2） |
| `_rewardBurned` | Mint | `RewardBurned` ×2 | 部分：仅在 `RewardPrepared` 出现（MI-1） |
| `_rewardReserved` | Mint | `RewardPrepared` | 有 |
| `_issuedLaunchCount` | Launch | `LaunchCountAdded` | 有 |
| `totalSupply` | LOVE20Token | 标准 `Transfer` | 有（标准事件） |

这不是「能不能折叠」的问题——五个量都能折叠，且多数有折叠测试；缺的是 §3.1 要求的「单条事件即可对账的锚点」。跨仓对照：`action` 的 `ApplicationVoteRecorded` 带 `voteAmountTotal`、`OriginScoresSubmitted` 带 `totalFinalScore`，core 的 `VoteCast` / `MemberMinted` 没有对应字段，属**仓间口径漂移**。

### 4.2 语义层：Phase 已修正，23 个事件均与链上 view 一致

`Phase` 在 `78ce1e6` 收敛为单事件段长快照：`PhaseSynchronized(phase, currentPhaseBlocks, nextPhaseBlocks)`，删除 `PhaseAdjusted`。`currentPhaseBlocks` 恒等于 `phaseInfo(phase)` 的段长；`nextPhaseBlocks` 是 P+1 起的段长，调整时等于 `phaseInfo(phase + 1)` 的段长并与 `sync()` 返回值一致，未调整时等于当前段长。折叠规则 `schedule[phase] = currentPhaseBlocks`、`schedule[phase + 1] = nextPhaseBlocks` 幂等，且相邻两次有效同步满足 `e2.currentPhaseBlocks == e1.nextPhaseBlocks`（中间空 Phase 不影响）。`effectivePhase ≡ phase + 1`、旧段长 ≡ `currentPhaseBlocks` 均由恒等式推导，不再占字段；单条日志使同笔顺序问题消失。

规格显式登记了两条边界：`nextPhaseBlocks == currentPhaseBlocks` 不区分「未调整」与「同长度重写」（`currentPhaseBlocks == 1` 且估算为 0 时钳到 1），`adjusted` 只从返回值读取；两者折叠出的段长相同，不影响 §3.3。其余 22 个事件的字段语义与链上 view 一致（原审查结论不变）。

### 4.3 测试层：断言覆盖不均衡

| 维度 | 状况 |
| --- | --- |
| 事件存在性 / 条数 / 反向断言 | 覆盖充分（含「不产生 X 事件」的反向断言） |
| indexed 布局与取值 | 大多覆盖；`BoostStaked` / `Unstaked` 漏 `topics[1]`（ST-3） |
| 单字段取值 | 大多覆盖；`LiquidityStaked` 5 字段、`FeesSettled.parentTokenBurned` 缺失（ST-1/2） |
| 同类型双字段可判别 | **最弱**：`issuedCount` vs `memberRemaining`（LA-1）、`tokenAmount` vs `parentTokenAmount`（ST-1）、`voterBoost` vs `totalVoterBoost`（VT-2）三处夹具恒等 |
| 顺序 / 依赖序 | 关键依赖序有测试（`RewardBurned → RewardPrepared`、`FeeReclassified → FeesSettled → StakeWithdrawn`、`LaunchCountAdded → GovRewardMinted`）；伴生顺序与跨合约顺序缺失（LA-2、SB-1） |
| 分支覆盖 | `Phase` 已覆盖：非调整、调整、相邻同步（含跳过空 Phase）、钳制等长重写四条分支均有载荷断言（`Phase.t.sol:64-83`、`:183-254`） |

「同类型双字段取同值」是本次审查最可复制的发现：三处都不是实现错误，却都能让实参互换的实现通过全套测试。建议在 core 测试规范中加一条硬约束：**同一事件内两个同类型字段，夹具必须让取值不同**（§8.1 已有此要求，缺的是执行）。

## 5. 复现

```sh
cd core && export PATH="$HOME/.foundry/bin:$PATH"
env -u PYTHONPATH python3 script/events/check-events.py     # 事件清单/族/写法/键名
env -u PYTHONPATH python3 -m pytest test/deploy_scripts_test.py -q   # 部署脚本（与事件无关，随门禁跑）
```

行号以 `core@78ce1e6` 为准（除 Phase 外，各合约实现自 `6fdd0f1` 未变，原行号仍有效）；本目录所有引用均为 `file:line` 形式，可直接跳转核对。

## 6. 放行条件

已满足：PH-1 由 `78ce1e6` 将 Phase 收敛为单事件段长快照，`matt-gov@8750937` 已同步 `03-phase.md` 同步节与 `09-testing.md` 验收；PH-2 / PH-3（调整轮载荷测试、同笔顺序）随同落地。

仍待处理：

1. MN-1 / VT-1 / MI-1 / MI-2 四个累计锚点问题：修复或在 `event-standards.md` §3.1 的豁免清单登记理由（二者择一，但不能一个仓带、一个仓不带）。
2. ST-1 / ST-2 / VT-2 / LA-1 四处夹具恒等：改夹具让同类型字段分离——这是唯一能防「实参互换」的手段。
3. LA-2 / SB-1 / ST-3 顺序与根键断言补齐。

P1 已清零；剩余 P2 属 ABI 变更的最后窗口，P3 为断言补齐。
