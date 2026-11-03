# 06 · 工具交叉

## Slither

```
slither . --compile-force-framework foundry      # 259 results, 17 detectors, 0 High/Medium detector hits
```

原始输出：`evidence/slither-raw.txt`。slither 的 `--compile-force-framework foundry` 直接复用 `out/`，不需要它自己跑 solc，所以 0.8.37 的版本问题没有出现（退化方案未启用）。

加入 `lock`/`skim` 的夹具后复跑一次，结果与首轮一致：`analyzed (64 contracts with 100 detectors), 259 result(s) found`，无 High/Medium 检测器命中（`evidence/01-recheck.log` 末节）。

### 双向对账

**工具报了、我没报**（逐个解释为什么安全）

| 检测器 | 位置 | 判定 | 理由 |
| --- | --- | --- | --- |
| `reentrancy-eth` / `reentrancy-no-eth` | `Stake._realizeFees:812`、`_withdrawLiquidity:737`、`withdraw:223` | **误报（当前配置）** | 三条转账路径（社区代币、父币、LP）全部无钩子；`pair.burn` 在 pair 的 `lock` 内，嵌套 burn 必 revert。记为 `STK-03`（Info）而不是丢弃——顺序确实是反的，换父币即成立 |
| `divide-before-multiply` | `Mint:391/405/488`、`Stake:372-379` | **有意** | 全部是定点数按「先定份额、再折币量」的两步换算，合并成一步会改变取整方向。`Stake:374-376` 有注释说明；`Mint:339` 的分母是已冻结的总额 |
| `dangerous-strict-equalities` | `Phase:50/88/90/120` | **有意** | 全部是 0/哨兵比较：`phase == 0` 是「未开始」，`_lastSyncPhase == phase` 是「本阶段已同步」，`observed == 0` 是「钳到 1」 |
| `missing-zero-address-validation` | 7 个 `init` | **设计已接受** | 部署层负责（dev-standards §5.7），`init` 内的行已用 `// forge-lint: disable-next-item(missing-zero-check)` 标注。真正的风险是抢跑，见 `DEP-01` |
| `local-variable-shadowing` | `MemberNFT._checkName(string name)` 等 6 处 | **误报** | 形参名 `name` 与 `ERC721.name()` 同名，仅命名冲突，无作用域问题 |
| `incorrect-exponentiation` | OZ `Math.mulDiv` | **误报** | 库内用 `^` 做位运算，不是幂 |
| `incorrect-versions-of-solidity` / `different-pragma-directives` | `lib/openzeppelin-contracts/**` | **出范围** | 全部在 OZ 依赖里；`src/` 与 `libs/` 统一 `=0.8.37` |
| `state-variables-that-could-be-declared-immutable` | `LOVE20Token.MINTER` / `PARENT_TOKEN_ADDRESS` | **记录** | 构造函数后无写入点。改 `immutable` 只省 gas，见 `TOK-01` |
| `cyclomatic-complexity` | `MemberNFT._isValidNameChars`（20）、`Phase.sync`（13） | **指向正是本轮两个缺陷** | 复杂度最高的两个函数恰好是 `NFT-01`（黑名单漏码点）与 `PHS-01`（无上界）的所在地。这条不是缺陷，但它把注意力引对了地方 |
| `block-timestamp` | `Phase:113/114`、`Stake:869` | **有意** | `Phase` 的时间轴必须以时间戳为输入；Router 的 `deadline = block.timestamp` 是标准用法 |
| `assembly-usage` / `too-many-digits` / `unused-return` / `naming-conventions` | OZ + 本仓常量名（`MAX_*`/`*_ADDRESS`） | **约定** | 全大写常量是项目口径；`unused-return` 已在 `forge.toml` 的 `exclude_lints` 里 |

**我报了、工具没报**（全部是语义/经济类，超出 slither 规则集）

| F-ID | 为什么工具报不出 |
| --- | --- |
| STK-01 | 需要理解「分母是活的 + 乘数可自我放大」的组合，是经济语义不是模式 |
| MNT-01 | 需要理解「prepare 的时序决定池子大小」，是状态机的顺序性质 |
| NFT-01 | 需要 Unicode 语义（U+180E 是空白但不在黑名单） |
| DEP-01 | 需要部署脚本与广播顺序的上下文，超出单合约静态分析 |
| LCH-02 / LCH-03 | 记账口径与可转让性 |
| NFT-02 / NFT-03 | 读写面对称性、指数上界 |
| PHS-01 | 无上界钳制 |

结论：**没有一个 High/Medium 级检测器命中**，而本轮 4 条 High/Medium 全部落在语义层——这与「代码已经过多轮清洗、剩下的是设计问题」的判断一致。

## Gas

`test/audit/AuditPoC.t.sol`（`evidence/poc-tests.log`）：

| 测试 | gas | 备注 |
| --- | --- | --- |
| `test_submitGateCapturedWithOneWeiOfBoost` | 4,240,447 | 4 人质押 + 1 wei boost + 8 次 `canSubmit` |
| `test_mergeInsideProposalCreatedIsBlockedByWrittenState` | 3,706,628 | 含 `ProposalBot` 部署与一次真实推举 |
| `test_launchReusesPrecreatedPair` | 3,271,805 | 含 `preCreatePair` + 一次 `launchToken` + 首存 |
| `test_settlementNeverTouchesBoostBacking` | 2,743,594 | 含一次真实结算（burn + swap + burn） |
| `test_zeroValueBurnFallsBackToLpTransfer` | 2,077,174 | |
| `test_mergeZeroesSourceVotesForAllLaterRounds` | 2,040,603 | |
| `test_phaseBlocksHasNoUpperClamp` | 1,882,127 | 两次 `sync` |
| `test_rewardPoolDependsOnMintOrder` | 52,009,737 | 单测内跑了两整套 `setUp()`（4 次完整部署 + 2 轮治理），不是单次调用的成本 |
| `test_donationIsReclassifiedAsFee` | 1,161,935 | |
| `test_invisibleCharacterBypassesNameUniqueness` | 742,305 | |
| `test_batchMintGasPerRound` | 23,639,884 | 其中被测量的 `mintGovRewards` 批调用是 **3,800,897**（20 轮，**190,044/轮**）；测试自身 gas 主要来自 20 轮治理准备 |

上表是加入 `lock`/`skim` 后的复跑值（`evidence/01-recheck.log`），与首轮记录的差异 ≤ 8%（最大一处是 `test_launchReusesPrecreatedPair`：3,051,967 → 3,271,805），全部来自夹具新增的 `lock` 修饰符（每次 `mint/burn/swap/sync/skim` 多一次 `require` 与两次存储写）与 `_unlocked` 槽位。

### 批量 mint 的 gas 上界（计划 §4.1）

`mintGovRewards(token, rounds[], memberId, recipient)` 的循环维度是**轮次**，单轮成本 ≈ 190k gas（含 `_prepareRewardIfNeeded` 的 `totalVoteAmount` / `totalVoterBoost` 两次外部读与一次 `Launch.addLaunchCount`）。BSC 单块 gas 上限为数十 M 量级，按 30M 估算单批可容纳约 150 轮；真正的上界不在这里，而在 `_prepareRewardIfNeeded` 对**提案数**的线性遍历（1000 提案 6.9M gas，见下表），批内每一轮都要重付一次。

既有压力测试（基线，`forge test --match-path 'test/stress/*'`）：

| 测试 | gas |
| --- | --- |
| `testPrepare1000Proposals` | 6,937,608 |
| `testPrepare300Proposals` | 2,468,265 |
| `testPrepare10Proposals` | 624,827 |

单轮 prepare 的成本随「本轮被投票的提案数」线性增长：10 → 1000 约 6.3M 增量，约 6.3k gas/提案。BSC 的单块 gas 上限是数十 M 量级（随硬分叉变化），**一轮 prepare 在最坏情况下吃掉其中相当一块**；把它放进 `mintGovRewards` 的批循环（`MNT-02`）就会出问题。实际阈值应以部署时的链参数为准。

## ABI 对账

`out/<Contract>.sol/<Contract>.json` vs `out/<Interface>.sol/<Interface>.json`，按 `(type, name, inputs, outputs, stateMutability)` 归一化后双向差集（脚本见 `evidence/abi-diff.py`）。

| 合约 | 接口条目 | 实现条目 | 接口有·实现无 | 实现有·接口无 |
| --- | --- | --- | --- | --- |
| `Stake` | 57 | 58 | **0** | `SafeERC20FailedOperation` |
| `Mint` | 40 | 40 | **0** | **0** |
| `Launch` | 49 | 49 | **0** | **0** |
| `MemberNFT` | 40 | 52 | **0** | constructor + 10 个 `ERC721*` + `SafeERC20FailedOperation` |
| `Submit` | 39 | 39 | **0** | **0** |
| `Vote` | 32 | 32 | **0** | **0** |
| `Phase` | 14 | 15 | **0** | constructor |
| `LOVE20Token` | 30 | 31 | **0** | constructor |

「实现有·接口无」的条目全部是构造函数与 OZ 继承错误，不需要出现在接口里。**接口声明的每一条都能在实现里找到**，下游按接口编码不会落空。

## storageLayout

`forge inspect <C> storageLayout`，无代理，仍核对声明顺序与 0 哨兵位置。

| 合约 | 关键点 | 结论 |
| --- | --- | --- |
| `Stake` | `initialized` 在 slot 0 offset 0，与 `PHASE_ADDRESS` 同槽（1 + 20 = 21 ≤ 32 字节） | 无跨槽读取；`initialized` 只写一次 |
| `Stake` | `_pairAddressByTokenAddress` 的 0 = 「未缓存」 | `_pairFor:515` 用 0 判缓存，一致 |
| `Stake` | `_memberStake[..].unlockRequestPhase` 的 0 = 「未申请」 | 轮次从 1 开始（`_checkActiveRound:462-465` 拒绝 0），0 不会与真实轮次冲突 |
| `Stake` | `_lastSettlePhase` 的 0 = 「从未结算」 | 与 phase 0 冲突，但正是想要的语义：phase 0 不结算（`Stake:791` 直接 return） |
| `Launch` | `_parentTokenByTokenAddress[token] == 0` = 「不是 Launch 创建」 | `isLOVE20Token` 即此判据；ROOT 本身不在表里，所以 `isLOVE20Token(ROOT) == false`，与 `launchToken:103` 的显式放行一致 |
| `Launch` | `_tokenAddressBySymbol[symbol] == 0` = 「未占用」 | 0 不是合法地址，无冲突 |
| `MemberNFT` | `_nextTokenId` 从 1 起 | `_tokenIdByNormalizedName[...] == 0` 可安全作「未使用」 |
| `MemberNFT` | `_holderIndex[holder] == 0` 既是「下标 0」也是「不在集合」 | 唯一一处置信歧义。安全性由调用图保证：`_removeHolder` 只在 `balanceOf(from) == 0` 且该地址确实持有过 token 时进入（`_update:206-208`），而余额为 0 的地址不会再成为 `from`。已核对，无二次删除路径 |
| `Phase` | `_segmentByPhase` / `_segmentByStartBlock` 双索引同一 `Segment` | 写入只经 `_recordSegment:144-149`，两处同步；`startBlock` 严格递增（`_recordNextSegment:155-159`），不会互相覆盖 |
| `Mint` | `initialized` 与 `VOTE_ADDRESS` 同槽（slot 10，offset 0/1） | 1 + 20 = 21 ≤ 32 字节，无跨槽读写；`initialized` 只写一次 |
| `Mint` | `_isRewardPrepared[token][round] == false` = 「未 prepare」 | 池子为 0 是合法值，所以不能用 `_govReward == 0` 判「未准备」；代码确实只用 bool（`Mint:105`） |
| `Mint` | `_launchCredit[token][memberId] == 0` = 「无额度」 | 额度只增不减（`MergeLaunchCount` 走 transfer），0 可安全作空值 |
| `Submit` | `initialized` 与 `PHASE_ADDRESS` 同槽（slot 0） | 同上，无跨槽读写 |
| `Submit` | `_proposals[token]` 的 0 下标 = 提案 ID 1 | ID 由 `_createProposal:246` 的 `length + 1` 给出，从 1 起；`_submitInfoByProposalId` 不会与「不存在」混淆 |
| `Vote` | `initialized` 与 `STAKE_ADDRESS` 同槽（slot 0） | 同上 |
| `Vote` | `_voterBoostByMemberId[...] == 0` = 「未快照」 | `Vote:235` 用「快照为 0 则取当前值」的语义，0 是哨兵；票权为 0 的成员本就不能投票，无歧义 |
| `LOVE20Token` | `MINTER` / `PARENT_TOKEN_ADDRESS` 在 slot 5/6，均为地址 | 构造后无写入点，可改 `immutable`（`TOK-01`）；根币的 `PARENT_TOKEN_ADDRESS == address(0)` 是合法空值 |

`forge build --sizes` 的余量见 `00-baseline.md`：最大的 `Stake` 距 24,576 上限还有 9,991 字节，本轮无新增合约代码，故改动前后一致。
