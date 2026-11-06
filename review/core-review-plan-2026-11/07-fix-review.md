# 07 · 修复复审

**本次不含修复**（计划 §4.3 的协议适用于修复阶段）。本轮 `src/` 一行未改，因此这里没有「修复后的完整函数」可审。

> **2026-11-06 更新**：`core@036b2ed` 新增了一次加速激励改版（入口本金上限 / 全额 boost 奖励）。本轮已只就 STK-01 补做修复复审，结果见下方「STK-01 修复复审」；其余 F-ID 仍未修复，也不在本轮范围。

留空的同时，把复审时要用的三问与四条前置写下来，避免下一轮重新定义：

## 复审协议（给下一个阶段用）

1. **不给 diff，给修复后的完整函数** + 原问题描述 + 触发序列。
2. 三问必答：
   - 是否完全消除原问题？
   - 是否引入新的状态不一致？
   - 是否改变边界（尤其 0 与 1 wei）？
3. 每个修复配一条**能被证伪的测试**：先在修复前失败（记 revert 选择器或断言差值），再在修复后通过。写不出来 → 审查结论本身可疑。
4. 复审前重跑：
   - `forge build --force --deny warnings && forge lint && forge test`
   - `env -u PYTHONPATH python3 script/events/check-events.py`
   - `env -u PYTHONPATH python3 test/deploy_scripts_test.py`
   - `forge test --match-path 'test/audit/*'`（本轮 11 个用例是回归基线，修 STK-01 / MNT-01 / NFT-01 时对应断言应当**由通过变失败**，再按新语义重写）

## 按 F-ID 的验收口径

| F-ID | 修好之后，本轮哪个断言应该变化 |
| --- | --- |
| STK-01 | `test_submitGateCapturedWithOneWeiOfBoost` 的「m2 失去提交权」应从 true 变 false（或门槛改为按轮快照） |
| MNT-01 | `test_rewardPoolDependsOnMintOrder` 的 `17/20` 比值应变成 `1/1`（池子与顺序无关） |
| NFT-01 | `test_invisibleCharacterBypassesNameUniqueness` 的第二次 `mint` 应 revert（`NameInvalidCharacters`） |
| STK-02 | 需要一个新用例：`lpAmount == 0` 时 revert 或补偿 |
| MNT-02 | 批量入口在有一轮无收益时应跳过而不是整批回滚 |
| MNT-03 | 视图与执行在同一轮给出同一数值 |
| NFT-02 | `isNameUsed("Alice")` 在 Test 部署下返回 true |
| NFT-03 | `calculateMintCost` 在供应尾部不为 0（或显式允许 0 并写进文档） |
| PHS-01 | `test_phaseBlocksHasNoUpperClamp` 的 `1,001,000` 应被钳到某个上界 |
| DEP-01 | 部署脚本在 `init` 失败时不产生可用地址（离线可测） |

LCH-02/03/04、STK-03/04/05、MNT-04/05、VOT-01、TOK-01/02 判为可接受或已关闭，不进入修复清单。

---

## STK-01 修复复审（2026-11-06）· `core@036b2ed`

> 只补 STK-01，其余 F-ID 本轮不动。
> 环境：`/tmp/core-stk01-review`（`rsync` 后 `git reset --hard 036b2ed`、`forge clean`、`forge build --force`），避免与 `core` 另一会话的测试改动互相干扰。
> 证据：[`evidence/07-stk01-fix-recheck.log`](evidence/07-stk01-fix-recheck.log)。

### 0. 先纠正一个前提

`036b2ed` 改的是**加速激励的反资本约束口径**（`Mint` 输出侧截断 → `Stake` 入口本金限量），不是 STK-01 的修复：

- 删的是 `MAX_GOV_BOOST_REWARD_MULTIPLIER`、`burnReward`、`BurnReason.BoostOverflow`（[CHANGES-core.md](../../docs/specs/CHANGES-core.md) §「加速激励改版」）；
- 加的是 `BoostCapExceeded` 与单人加速**本金**上限；
- 票权公式 `govVotes = liquidityShares × promisedWaitingPhases`（`Stake:986-987`）与 `Submit` 的活分母（`Submit:81-83`、`:86`）**一行未改**。

所以「1 wei 拉满乘数」的做法没有被替代；被替代的是「加速回报最多 M 倍」的输出侧承诺，后者已在 `CHANGES-core.md:27` 明确写为「不再保证」。

### 1. 协议第 1 条：完整函数 + 原问题 + 触发序列

**形式通过 / 实质不通过。**

- 形式：`stakeBoost`（`Stake:145-193`）、`_checkBoostCap`（`Stake:529-541`）、`_boostStakeBaseAndMemberCap`（`Stake:506-526`）与 `_totalLiquidityTokenAmount` 台账都可读全量函数；PoC 的触发序列仍可逐步复现。
- 实质：修复后的 `stakeBoost` 只多了一道 `_checkBoostCap`（`Stake:163`，校验 `boostShares + amount ≤ m_i`），随后仍按 `liquidityShares × (P_new − P_old)` 补票（`Stake:170-174`）。实测 1 wei 是上限的 `5e-19`，这道检查对原触发序列没有约束力。

### 2. 协议第 2 条：三问

#### 2.1 是否完全消除原问题？**否（不通过）**

原 PoC `test_submitGateCapturedWithOneWeiOfBoost` 在修复前后都通过（基线 `9297a33`：11/11；HEAD `036b2ed`：11/11）。同一 fixture 下的实测：

| 时点 | m1 票权 | 总票权 | 门槛 | m1 加速度上限 | m2 票权 |
| --- | --- | --- | --- | --- | --- |
| 1 wei boost 前 | `9.9999e19` | `3.9999e20` | `1.9999e19` | `1.9999e18` | `1.0e20` |
| 1 wei boost 后 | `9.9999e21` | `1.0299e22` | `5.1499e20` | 同上 | `1.0e20` |

`1 wei` 相对上限约为 `5e-19`；票权正好 ×100，门槛 ×25.75，m2 的 `1.0e20` 低于新门槛 `5.15e20`，仍被排除。`promisedWaitingPhases` 只增不减、轮次历史向后回退取最近值，因此排除仍跨轮持续。

#### 2.2 是否引入新的状态不一致？**有限，逐项登记**

- **（a）入口本金上限与出口奖励份额不再由公式耦合。** 入口限制的是 `boostShares`（社区代币本金），出口按 `voterBoost / totalVoterBoost` 分加速池。`CHANGES-core.md:27` 已明确承认：不再保证「加速回报 ≤ 投票回报的 M 倍」，唯一加速且打满额度时回报比可达 `1 / 票占比`（例：`M=5`、票占比 10% → 10×）。这是**已登记的政策变化**，不是隐藏不一致；但 `M` 不再是收益率上限。
- **（b）同一 `BoostCapExceeded` selector 承载两套 payload 语义，且参数名在四处不一致。** `stakeBoost` 路径 `allowed = memberRemaining`（剩余额度，`Stake:537-539`；`04-stake.md:242` 写 `boostAmount, memberRemaining`）；`mergeStake` 路径 `allowed = targetCap`（目标绝对上限，`Stake:319-323`；`04-stake.md:280` 写 `targetBoostShares, targetCap`）；ABI 声明用 `requested, allowed`（`IStake.sol:72-77`），`09-testing.md:38` 又写 `requested, memberRemaining`。**语义与规格一致、selector 不变**，但四套参数名会让集成方把 merge 路径的 `allowed` 误读为剩余额度；`check_errors.py` 按一 selector 两站点通过。**登记一致，命名一致性残留（Low）。**
- **（c）本金台账按 LP 份额比例收缩，而不是按 token 本金。** `_totalLiquidityTokenAmount` 在提取时按 `liquidityShares / totalLiquidityShares` 缩减。不同成员在不同价格比例下存入时，LP 份额与 token 本金并非严格同比例，台账会缓慢漂移；漂移只影响上限基数 `C`，不影响资产与奖励结算。**只影响额度精度，不影响安全。**
- **（d）`core/test/integration/TEST_MATH_MODEL.md` 未同步。** 仍写 `MAX_GOV_BOOST_REWARD_MULTIPLIER = 2` 与 `maxBoostReward = voteReward × MULTIPLIER`（该文件 tracked，`036b2ed` 未改）。这是本次变更新引入的**文档不一致**（Low）；`docs/`、规格、whitepaper 已同步。
- **（e）ABI / 事件 / 存储变更均已登记。** `Mint.init` 8→7、`Stake.init` 9→11、`govRewardByMemberId` 4→3、`GovRewardMinted` 7→6 字段、`BurnReason.BoostOverflow` 删除；`RewardBurned` topic0 不变，`Mint` 释放末位槽、`Stake` 追加两槽。`CHANGES-core.md` 有对照表，`events` 检查 28 条通过。pre-mainnet 阶段可接受。

#### 2.3 是否改变边界（尤其 0 与 1 wei）？

| 输入 | 修复前 | HEAD `036b2ed` | 判定 |
| --- | --- | --- | --- |
| `boostAmount = 0` | `ZeroBoostAmount` | `ZeroBoostAmount` | 未变 |
| `boostAmount = 1`，`m_i ≥ 1` | 通过，乘数拉满 | 通过，乘数拉满（实测 `m_i ≈ 2e18`） | 未变 |
| `boostAmount = 1`，`m_i = 0` | 通过 | `BoostCapExceeded(token, id, 1, 0)` | 新增边界（仅小本金/上限收缩后出现） |
| `boostAmount = m_i + 1` | 不存在该错误 | `BoostCapExceeded(token, id, cap+1, cap)` | 新增，`allowed` = 剩余额度 |
| merge 后超过目标上限 | 不存在该错误 | `BoostCapExceeded(token, target, mergedTotal, targetCap)` | 新增，`allowed` = 绝对上限 |

结论：0 wei 与 1 wei 的**原有语义未变**；新增的是「上限触发」这一类错误，其触发条件与 payload 与 `04-stake.md:242` / `:280` 一致。

### 3. 协议第 3 条：可证伪测试

**不通过。**

- 修复未新增任何能让 STK-01 旧断言失效的测试；`test_submitGateCapturedWithOneWeiOfBoost` 在修复前后都通过（见 §2.1）。
- `036b2ed` 在 `test/Stake.t.sol` 新增了上限用例（`testBoostStakeCapMatchesFormula`、`testBoostStakeRevertsAboveMemberCap`、`testSupplyBurnShrinksCapAndGrandfathersExistingBoost`、`testMergeWithBoostSucceedsWithinTargetCap` 等），它们证伪的是「入口本金上限」本身，不是提交门槛。
- 按协议「先在修复前失败，再在修复后通过」的方向，STK-01 缺少一条反向断言；修复没有让任何旧断言由通过变失败。

### 4. 协议第 4 条：门禁

**通过。**

| 命令 | 结果 |
| --- | --- |
| `forge clean && forge build --force --deny warnings` | rc=0（仅 foundry 预处理器的 OZ 重复声明告警，solc 编译成功） |
| `forge lint` | rc=0 |
| `forge test` | 530 passed / 0 failed（HEAD 527 + 本复审新增 3 条只读测量用例） |
| `env -u PYTHONPATH python3 script/events/check-events.py` | 28 events OK，rc=0 |
| `env -u PYTHONPATH python3 test/deploy_scripts_test.py` | 41 passed，rc=0 |
| `forge test --match-path 'test/audit/*'`（11 条回归基线） | 11 passed / 0 failed |

### 5. 按 F-ID 的实测对照（只判 STK-01）

| F-ID | 协议期望 | HEAD 实测 | 判定 |
| --- | --- | --- | --- |
| STK-01 | 「m2 失去提交权」true → false | 仍为 true；m2 票权 `1.0e20` < 新门槛 `5.15e20` | **验收不通过** |
| MNT-01 / NFT-01 / STK-02 | 各自断言变化 | 原 PoC 仍通过 | 不在 `036b2ed` 范围，本轮未动 |

### 6. 复审结论

`036b2ed` 是一次**加速奖励经济口径改版**，不是 STK-01 的修复；STK-01 的机制与 PoC 在 HEAD 完整保留。签字判定有两种自洽路径，取决于项目是否继续沿用 `core-state-mutation-review-2026-11`（`core@0466d67`）的「机制设计」裁决：

- 沿用该裁决 → **降级接受**（High → 可接受），但不得把 `036b2ed` 记为 STK-01 的修复证据；
- 要求关闭 1 wei 通道 → **需整改**，`036b2ed` 不能作为关闭依据。

具体签字表见 [`09-signoff.md`](09-signoff.md)。
