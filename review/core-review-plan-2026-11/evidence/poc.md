# PoC 索引与夹具保真度

## 怎么跑

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
forge test --match-path 'test/audit/*' -vv
```

11 个用例，全部 E3。源码两份：

| 位置 | 作用 |
| --- | --- |
| `core/test/audit/RealV2.sol` | UniswapV2 忠实子集：`MINIMUM_LIQUIDITY = 1000`、0.3% 费率、k 校验、`sync`、`skim`、`lock`、`burn` 按余额比例付款 |
| `core/test/audit/AuditPoC.t.sol` | 10 个复现/性质断言 + 1 个 gas 上界用例 + `ProposalBot`（作为 Callback target 的合约成员） |
| `evidence/*.sol` | 上面两份的快照（与仓内逐字节一致，便于归档） |

## 映射

| 测试 | 断言的核心事实 | F-ID |
| --- | --- | --- |
| `test_submitGateCapturedWithOneWeiOfBoost` | 1 wei boost 后 `totalValidGovVotes` 涨 >20 倍；攻击者保留提交权，其余 3 人全部失去；下一轮仍失去 | STK-01 |
| `test_rewardPoolDependsOnMintOrder` | 先 prepare 轮 2 时 `govReward(轮1)` 恰为自然序的 `17/20` | MNT-01 |
| `test_invisibleCharacterBypassesNameUniqueness` | `admin` 与 `admin`+U+180E 共存（`memberId` 各自解析）；`ADMIN` 被 `NameAlreadyExists` 拒绝 | NFT-01 |
| `test_launchReusesPrecreatedPair` | `child == computeCreateAddress(launch, nonce)`；`createdPairCount` 不增；复用后可质押 | LCH-01 |
| `test_mergeInsideProposalCreatedIsBlockedByWrittenState` | 回调内 merge 的 revert data == `StakeRightsUsed(token, round, botId)`；下一轮同一次 merge 成功 | STK-01 同源 / B3 |
| `test_settlementNeverTouchesBoostBacking` | 结算后 `totalBoostShares` 不变、`balanceOf(stake) ≥ 1e18` | STK-03 / STK-04 |
| `test_zeroValueBurnFallsBackToLpTransfer` | `_canBurn == false` 时持有人拿到 3 LP、社区代币余额不变 | STK-02 / D-04 |
| `test_donationIsReclassifiedAsFee` | 捐赠 + `sync` 后 `feeLp > 0`、`withdrawableLp` 下降、两者之和不变 | STK-04 / D-02 |
| `test_mergeZeroesSourceVotesForAllLaterRounds` | merge 后 source 本轮票权为 0、target 增加 | VOT-01 |
| `test_phaseBlocksHasNoUpperClamp` | `phaseInfo(4).phaseBlocks == 1,001,000`；`phaseInfo(3)` 仍为 1000 | PHS-01 |
| `test_batchMintGasPerRound` | 20 轮 `mintGovRewards` 批调用 = 3,800,897 gas（190,044/轮），每轮 < 200k 断言成立 | §4.1 gas 上界（不指向缺陷） |

## 夹具保真度

计划 §9 把「Mock 保真度」列为三个最易失效点之首。本轮的处理方式是：**凡是涉及份额、重分类、结算、`_canBurn` 的断言，一律跑在 `RealV2.sol` 上**，而不是仓库既有的 `test/Stake.t.sol:MockPair`。

`RealV2.sol` 与真 V2 的逐项对照：

| 语义 | 真 V2 | `RealV2.sol` | 是否一致 |
| --- | --- | --- | --- |
| 首次铸造烧掉 `MINIMUM_LIQUIDITY` | `_mint(address(0), MINIMUM_LIQUIDITY)` | 同 | ✅ |
| 后续铸造按 `min(amount0·TS/r0, amount1·TS/r1)` | 同 | 同 | ✅ |
| `burn` 用 `balanceOf(this)` 而非传入量 | 同 | 同 | ✅ |
| `burn` 要求 `amount0 > 0 && amount1 > 0` | 同 | 同（`V2: INSUFFICIENT_LIQUIDITY_BURNED`） | ✅ |
| `swap` 的 k 校验含 0.3% 费率 | `(b0·1000 − in0·3)(b1·1000 − in1·3) ≥ r0·r1·1000²` | 同 | ✅ |
| `swap` 的 `amountIn` 以 `_reserve` 为基准（不是余额） | 同 | 同（第一版写错，已修正并记录） | ✅ |
| `sync` 把余额写进储备 | 同 | 同 | ✅ |
| 储备用 `uint112` 存储（超限 revert） | 同 | 同 | ✅ |
| `feeTo` / `mintFee` | 存在（`feeTo = 0` 时不走） | 省略（等价于 `feeTo = 0`） | ✅ |
| `lock` 修饰符 | 有（`mint`/`burn`/`swap`/`sync`/`skim`） | 同 | ✅ |
| `skim` | 有 | 同 | ✅ |
| `permit` / 闪电贷 | 有 | 省略 | 不影响本轮断言 |
| Router 的 `swapExactTokensForTokens` | 含 `getAmountsOut` + `pair.swap` | 同（去掉 path 长度校验） | ✅ |

仓库既有的 `test/Stake.t.sol:MockPair`（`98-205`）**没有** `MINIMUM_LIQUIDITY`、**没有** 0.3% 费率、`burn` 用 `_balances[this]`、`getReserves` 用 `uint112(...)` 静默截断、`MockRouter` 1:1 兑换。凡是建在它上面的资金类结论最高只能到 E2——这也是本轮不去复用它、而新写 `RealV2.sol` 的原因。

## 已知的测试局限

1. **时间戳**：`RealV2Pair` 只存 `blockTimestampLast`，不参与任何计算（真 V2 的 TWAP 预言机部分未实现）。本轮不涉及 TWAP。
2. **`test_rewardPoolDependsOnMintOrder` 的 52M gas**：该用例内部跑了两次完整 `setUp()`（4 次部署 + 2 轮治理），不是单次调用的成本。
3. **BSC 特有的 gas 表**没有校准：所有 gas 数字是 forge 本地 EVM 的结果，用作量级参考而非绝对值。
4. **`lock` 已补齐**（2026-11-01 复跑）：`STK-03` 的不可达性仍由「代币无钩子」论证，不依赖 pair 的 `lock`；`lock` 的作用是让夹具与真 V2 在嵌套调用上的行为一致，便于后续复用时不被误导。
