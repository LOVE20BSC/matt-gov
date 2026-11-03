# 登记项索引

22 条登记项 + 1 条已排除记录。每条都在对应模块页里有完整的登记表、机制、触发序列、约束与损失承担者。

## 按严重度

| F-ID | 严重度 | 模块 | 一句话 | 证据 | 状态 |
| --- | --- | --- | --- | --- | --- |
| STK-01 | **High** | Stake / Submit | 提交门槛乘活分母，1 wei 把 `promisedWaitingPhases` 拉满即可永久排除他人提交 | E3 | 已确认待修 |
| MNT-01 | **Medium** | Mint | 每轮奖池在首次 mint 时按当时 `available` 定，先 prepare 后一轮可压缩前一轮 | E3 | 已确认待修 |
| NFT-01 | **Medium** | MemberNFT | 唯一性只折 ASCII 大小写，U+180E 等不可见码点被接受 → 视觉同形名共存 | E3 | 已确认待修 |
| DEP-01 | **Medium** | 部署 | 7 个 `init` 无调用者限制 + 逐笔广播 → 抢跑产生 8 个不可删除的孤儿合约 | E1 | 已确认待修 |
| STK-02 | Low | Stake | 份额对应的 LP 取整到 0 时静默删份额、不给资产 | E3/E1 | 已确认待修 |
| MNT-02 | Low | Mint | 批量 mint 全有全无；单轮 prepare 可遍历 1000 提案 | E2 | 已确认待修 |
| MNT-03 | Low | Mint | 未 prepare 时 view 用实时 `available` 反推池子，可与执行结果不一致 | E1 | 已确认待修 |
| LCH-02 | Low | Launch | 一份额度买两次发射；根级账本不受 `MAX_LAUNCH_COUNT` 约束 | E1 | 已关闭（可接受） |
| NFT-02 | Low | MemberNFT | `isNameUsed`/`memberId` 不套 `Test` 前缀 | E1 | 已确认待修 |
| NFT-03 | Low | MemberNFT | 供应尾部身份免费；`MULTIPLIER**difference` 溢出上界无人查 | E1/E2 | 已确认待修 |
| PHS-01 | Low | Phase | `sync` 把 `observed` 原样写成下一阶段长度，无上界；采样点由调用者选 | E3/E1 | 已确认待修 |
| STK-03 | Info | Stake | `withdraw` 违反 CEI，但三条转账路径全无钩子 → 不可达 | E1 | 已关闭（附条件） |
| STK-04 | Info | Stake | 「手续费 = 任何 sqrt(k) 增值」是政策；本金几何价值严格守恒 | E3 | 已关闭 |
| STK-05 | Info | Stake | `W → 0` 时结算停摆，feeLp 滞留；有新存入即恢复 | E2 | 已关闭 |
| MNT-04 | Info | Mint | `RewardBurned` 不减少供应；只重分类不销毁的路径无事件 | E1 | 已关闭 |
| MNT-05 | Info | Mint | 额度发满后静默丢弃累计 credit | E1 | 已关闭 |
| LCH-01 | Info | Launch | 预建 Pair 被幂等复用，无害（H-01 分支已补测） | E3 | 已关闭 |
| LCH-03 | Info | Launch | `mergeLaunchCount` 让发射额度可转让 | E1 | 已关闭 |
| LCH-04 | Info | Launch | `Test` 前缀让符号每代 +4 字节，深度卡在 6 代 | E1 | 已关闭 |
| VOT-01 | Info | Vote | 加速快照单调性依赖 Stake 的两道锁，属跨合约假设 | E1/E3 | 已关闭 |
| TOK-01 | Info | Token | `burn` 开放；两个变量可 immutable；全仓无 rescue | E1 | 已关闭 |
| TOK-02 | Info | 接口 | 8 组接口/实现 ABI 双向 diff，接口声明全部实现 | E1 | 已关闭 |
| — | — | Stake | **STK-06 已排除**：零基准分支与 `canWithdraw` 口径差都不可达 | E2 | 不成立 |

分布：High 1 / Medium 3 / Low 7 / Info 11。

## 按模块

| 模块 | 页 | 条目 |
| --- | --- | --- |
| `Stake.sol` | [stake.md](stake.md) | STK-01 .. STK-06 |
| `Mint.sol` | [mint.md](mint.md) | MNT-01 .. MNT-05 + M4 不成立证明 |
| `Launch.sol` + 部署 | [launch.md](launch.md) | LCH-01 .. LCH-04、DEP-01 |
| `MemberNFT.sol` | [membernft.md](membernft.md) | NFT-01 .. NFT-03 |
| `Submit.sol` / `Vote.sol` / `Phase.sol` | [submit-vote-phase.md](submit-vote-phase.md) | PHS-01、VOT-01 + 两条已验证结论 |
| `LOVE20Token.sol` / 接口 | [token-interfaces.md](token-interfaces.md) | TOK-01、TOK-02 |

## 与 PoC 的映射

| 测试 | 断言的对象 | F-ID |
| --- | --- | --- |
| `test_submitGateCapturedWithOneWeiOfBoost` | 门槛抬升后他人 `canSubmit` 为 false，且下一轮仍为 false | STK-01 |
| `test_rewardPoolDependsOnMintOrder` | 两种 prepare 顺序下 `govReward(轮1)` 的比值恰为 17/20 | MNT-01 |
| `test_invisibleCharacterBypassesNameUniqueness` | `admin` 与 `admin`+U+180E 同名共存；`ADMIN` 被正确判重 | NFT-01 |
| `test_launchReusesPrecreatedPair` | 地址可预测、`createdPairCount` 不增、复用后可质押 | LCH-01 |
| `test_zeroValueBurnFallsBackToLpTransfer` | `_canBurn == false` 时改发 LP，不 revert | STK-02 |
| `test_donationIsReclassifiedAsFee` | 捐赠 + `sync` 后 fee 上升、W 下降、总额不变 | STK-04 |
| `test_settlementNeverTouchesBoostBacking` | 结算后 `balanceOf(stake) ≥ Σ boostShares` | STK-03 / STK-04 |
| `test_mergeInsideProposalCreatedIsBlockedByWrittenState` | 回调内 merge 的 revert data == `StakeRightsUsed(token, round, botId)`；下一轮同一次 merge 成功 | STK-01 同源 / B3 |
| `test_mergeZeroesSourceVotesForAllLaterRounds` | merge 后 source 在本轮票权为 0、target 增加 | VOT-01 |
| `test_phaseBlocksHasNoUpperClamp` | `phaseInfo(4).phaseBlocks == 1,001,000`；`phaseInfo(3)` 不变 | PHS-01 |

## 状态口径

| 状态 | 含义 | 本轮条数 |
| --- | --- | --- |
| 已确认待修 | 判定为缺陷，且给出约束与损失承担者 | 10 |
| 已关闭（可接受） | 判定不是缺陷，理由写在正文（含约束/边界/承担者） | 2 |
| 已关闭（附条件） | 当前安全但依赖外部条件，条件一变即成缺陷 | 1 |
| 已关闭 | 已验证无害或纯记录 | 9 |
| 不成立 | 假设被反例搜索否证 | 1 |
