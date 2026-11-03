# 02 · 单元登记表

唯一进度真相。29 个单元全部到「已审」：无「未审」，无「审了一半」。每行给出该单元的判定要点与产出的 F-ID（没有 F-ID 表示该单元只产出「无缺陷」结论或不成立记录）。

轮次按计划 §2.3 的四轮模板走（R1 访问控制 / R2 外部调用与状态顺序 / R3 数学与边界 / R4 设计自洽）；读面单元（S4、V2）只走 R1 + 口径核对，T1 走 ABI 逐条 diff。

## Stake

| 单元 | 范围 | 行 | 判定 | 产出 |
| --- | --- | --- | --- | --- |
| S1 | `Stake:1-104` | 104 | 初始化无校验、依赖不可替换；`init` 无调用者限制按设计已接受（表 F）。`_pairFor:513-521` 首次缓存不校验 `token0/token1`，但 pair 只能来自 Factory，缓存后不再变 | DEP-01 |
| S2 | `Stake:106-181` | 76 | 入池定价与滑点：`_optimalAmounts:701` 单侧零储备跳过滑点仅在空池成立，空池时 `pair.mint` 用 `balance - reserve` 计额，捐赠不计入铸造量 → 无害。`stakeBoost:154-159` 用 1 wei 拉满乘数 | STK-01 |
| S3 | `Stake:183-311` | 129 | 解锁与交付：`withdraw` 外部调用先于 `delete`，但三条转账路径（社区代币 / LP / pair）全无钩子 → 不可达。`canWithdraw` 与 `withdraw` 的口径差不可达（见 STK-06 的反例搜索） | STK-03、STK-06 |
| S4 | `Stake:313-441` | 129 | 读面与写面同口径：`totalStake` 的 `totalLp` 与 `feeLp+withdrawableLp` 恒等（`_reclassify` 按差值定义 fee） | — |
| S5 | `Stake:443-522` | 80 | 代币准入与 Pair 绑定：`_checkToken` 走 `Launch.isLOVE20Token`，登记后不可撤销；`_pairFor` 缓存不可污染 | — |
| S6 | `Stake:524-653` | 130 | 份额稀释：`shares = S·lpMinted/W_before` 与 `lp = s·W/S` 互逆；`W/S ≤ 1` 恒成立 → 单笔存入的索取权恒等于其出资额 | STK-06 |
| S7 | `Stake:655-773` | 119 | 重分类不改本金：`_reclassify:684-691` 用 `sqrt(k)` 增量划走 W，绝对值守恒（证明见 STK-04）；`_canBurn:809` 与真 V2 的 `require(amount0>0&&amount1>0)` 整数等价，已测 | STK-04、STK-05 |
| S8 | `Stake:775-877` | 103 | 结算链：`settlementUnit` 由 `withdrawableLp` 定义（`:786`）而门槛比 `feeLp`（`:787`）；`amountOutMin` 同笔现算 → 单笔冲击上界 = 0.125% of reserves，往返 0.6% 费率不可套利。`burn:831` 只烧刚收到的量，Boost 押金不受影响（已测） | STK-03、STK-05 |

## Mint

| 单元 | 范围 | 行 | 判定 | 产出 |
| --- | --- | --- | --- | --- |
| M1 | `Mint:1-98` | 98 | 参数域 = 可用域：比例和 > 1e18 会让 `rewardAvailable:455` 下溢，三层防线闭合（表 E） | MNT-05 |
| M2 | `Mint:100-184` | 85 | 每轮只预留一次：guard 正确；但「哪一轮先被 prepare」无任何约束，池子大小取决于首次 mint 的时序 | MNT-01 |
| M3 | `Mint:186-262` + `:500-557` | 135 | 零额 / 重复 / 原子性：三项和为 0 时 revert 且不置位；批量 mint 任一元素失败整批回滚 | MNT-02 |
| M4 | `Mint:264-354` | 91 | 分配之和 ≤ 池：`eligibleVoteAmount` 与逐提案分配用同一集合与同一阈值 → **越预留不成立**（证明见 §M4 假设） | MNT-03 |
| M5 | `Mint:356-450` | 95 | 50/50 拆分与倍数封顶：`voteReward ≤ votePool`、`boostReward ≤ boostPool`，Σ ≤ `govReward` | — |
| M6 | `Mint:452-498` | 47 | 未铸额度不重复分配：`reservedAvailable = R − M − B` 使取消的额度回流 `available`，守恒正确；`issued >= max` 时提前 return 只丢累计credit，不丢次数 | MNT-04、MNT-05 |

## Launch

| 单元 | 范围 | 行 | 判定 | 产出 |
| --- | --- | --- | --- | --- |
| L1 | `Launch:1-89` | 89 | 首币与依赖绑定：`init:68-75` 顺序为 建币→登记→`MemberNFT.init`；抢跑后者让前者整笔回滚 | DEP-01 |
| L2 | `Launch:91-152` | 62 | 发射次数先扣后建：`:110-119` 先减再建币，失败整体回滚；回调在全部登记之后 | LCH-01 |
| L3 | `Launch:154-236` | 83 | 剩余 + 已消耗 = 已产生：两个账本口径不同（`_remainingLaunchCount` 可因 merge 转移，`_issued` 只增）；`MAX_LAUNCH_COUNT` 只约束被记账的那个代币 | LCH-02、LCH-03 |
| L4 | `Launch:238-350` | 113 | 符号唯一 + Pair 幂等：`_createToken:256-260` 复用已存在 Pair（H-01 分支），本次补测；UTF-8 三字节分支首字节区间 `0xE4≥0xB8 / 0xE5-0xE9` 与 CJK 基本区一致 | LCH-01、LCH-04 |

## MemberNFT

| 单元 | 范围 | 行 | 判定 | 产出 |
| --- | --- | --- | --- | --- |
| N1 | `MemberNFT:1-101` | 101 | 身份唯一性与手续费销毁：费用先转给自己再烧；`_nextTokenId` 与唯一性映射在 `_safeMint` 之前写入，接收方回调不能覆盖 | NFT-02 |
| N2 | `MemberNFT:103-213` | 111 | 持有人集合与余额一致：`_update` 在 `super._update` 之后按 `balanceOf` 增删，`_safeMint` 的回调发生在记账之后 → 不会错乱 | NFT-03 |
| N3 | `MemberNFT:215-379` | 165 | 归一化后唯一 + 码点白名单：归一化只折 ASCII A-Z；白名单是黑名单式补集，漏 U+180E 等不可见码点 | NFT-01 |

## Submit / Vote / Phase

| 单元 | 范围 | 行 | 判定 | 产出 |
| --- | --- | --- | --- | --- |
| B1 | `Submit:13-103` | 91 | 推举权 = 全局票权占比：分母是**活的** `totalValidGovVotes`，任何成员可自行放大 | STK-01 |
| B2 | `Submit:105-213` | 109 | 每轮每人一次：`_submitInfoBySubmitterId` 三重唯一性（提案 / 成员 / 轮容量）齐备 | — |
| B3 | `Submit:215-339` | 125 | 回调前状态已落盘：`:301-307` 早于 `:326`，回调内融合被 `StakeRightsUsed` 挡住（已测） | STK-01（同源） |
| V1 | `Vote:12-100` | 89 | 票上限实时 + 快照：`voteLimit` 每次调用重读，累计校验在 `:250-254` | — |
| V2 | `Vote:102-210` | 109 | 快照只读：`_voterBoostByMemberId` 仅在 `_vote` 内单调抬升 | — |
| V3 | `Vote:212-293` | 82 | 名册 / 累计 / 上限三者一致：`isFirstVoteByMember` 实为「对该提案首票」，去重成立；boost 快照依赖 Stake 轮内单调（已证） | VOT-01 |
| P1 | `Phase:1-162` | 162 | 轮长只影响未来：新段从 `phase+1` 起始，`currentPhase` 不跳变；`observed` 无上界 | PHS-01 |
| T1 | `LOVE20Token:1-59` + `interfaces/**` | 1069 | 供应上限与 minter 唯一：`MAX_SUPPLY` immutable、`mint` 只有 Mint；ABI 面与实现逐条一致 | TOK-01、TOK-02 |

---

## §2.4 预置假设的判决（14 组，全部给出成立/不成立）

| # | 假设 | 判决 | 依据 |
| --- | --- | --- | --- |
| 1a | S1 `init:83-94` 九参零校验 | **成立** | `Stake:83-94` 只判 `initialized`；`FEE` 无上界、6 个地址无 `code.length`。归 `DEP-01`/表 E，不单独登记 |
| 1b | S1 `_pairFor:513-521` 首次缓存不校验 `token0/token1` | **成立，但不构成风险** | pair 只能由 `PAIR_FACTORY_ADDRESS.getPair(token, PARENT_TOKEN_ADDRESS())` 给出；Factory 是部署常量，越权即信任边界之外。缓存后无写入点 |
| 1c | S1 `_hasUsedStakeRights:501` 二跳信任 `IVote.SUBMIT_ADDRESS()` | **成立，但不构成风险** | 两个地址都在 `init` 后不可变；跳错只会让「已用票权」判据失效，而该判据的唯一后果是允许提前解锁，攻击者无法改地址 |
| 2a | S2 `_optimalAmounts:701-703` 单侧储备为 0 时跳过滑点 | **成立** | 但该分支只在空池/单侧捐赠池出现；此时 `pair.mint` 用 `balance − reserve` 计额，捐赠不计入铸造量，存入者的 LP 仍与其出资成比例 |
| 2b | S2 `stakeBoost:155` 用 1 wei 把全部存量份额的乘数从 MIN 拉到 MAX | **成立** | 这是 `STK-01` 的杠杆来源。量化：乘数上限 `MAX`，成本 = 1 wei + 锁定期，非资金 |
| 3a | S3 `withdraw:239-249` 顺序为「出金 → 付 boost → `delete`」 | **成立** | `:239-240` 外部调用、`:249` delete。三条转账路径（LOVE20Token、V2 Pair、LP）都无钩子，`ROOT = router.WETH()` 亦无钩子 → 无可达重入路径。记为 `STK-03`（Info） |
| 3b | S3 `canWithdraw:416` 不比 `liquidityShares`，`withdraw:229` 比 | **成立，但不可达** | 反例搜索：`liquidityShares == 0 && unlockRequestPhase != 0` 需要先 `unstake`（要求 shares > 0）再让 shares 归零，而唯一能让 shares 归零的 `withdraw` 同时 `delete` 整个记录。故两者结论不会分叉 |
| 4 | S6 `_creditLiquidity:589-591` 零基准按 `lpMinted` 计份额，`withdrawableLp` 被打到 0 后老份额白吃新存入 | **不成立** | 需 `W == 0 && S > 0`。但 `W/S ≤ 1` 恒成立（首存 `W = S = lpMinted`，存入与提取都保持比值，重分类只减 W），且 `W = 0 ⇒ feeLp = W_old + ... ⇒ S = 0`（最后一笔提取把 W 与 S 同时清零）。见 `STK-06` |
| 5a | S7 `_canBurn:809` 与真 V2 的 `require(amount0>0 && amount1>0)` 严格等价 | **成立** | `lp·r ≥ TS ⇔ floor(lp·r/TS) ≥ 1`（整数）。测试 `test_zeroValueBurnFallsBackToLpTransfer` 构造了 `_canBurn == false` 的真实边界并跑通兜底 |
| 5b | S7 `_reclassify:684-690` 把任何第三方 donation 判成手续费 | **成立** | 测试 `test_donationIsReclassifiedAsFee`：捐赠 2e20 + `sync` 后 `feeLp > 0`、`withdrawableLp` 下降、`fee + withdrawable` 不变。但绝对价值只增不减（`STK-04` 的守恒证明） |
| 6a | S8 `settlementUnit` 由 `withdrawableLp` 定义（`:786`）而门槛拿 `feeLp` 比（`:787`） | **成立** | 口径不同是设计：`settlementUnit` 是「本次可处理量」，门槛是「是否够处理」。副作用是 `W → 0` 时 `unit → 0` 且 `_canBurn(0) == false` → 结算停摆（`STK-05`） |
| 6b | S8 `amountOutMin` 同笔现算（`:862-863`）对跨块夹子零保护 | **成立** | 同笔内 `getAmountsOut` 与 `swap` 之间储备不变 → 不会因滑点 revert；跨块则由上一块的操纵价成交。盈利不等式见 `05-paths/P-02.md`：单笔换币 ≤ 0.125% 储备，往返成本 0.6%，需结算是储备的 11% 以上才有利可图 → 实际不可套利 |
| 6c | S8 证明 `:831` 的 `burn` 吃不到 Boost 负债 | **成立** | `burn(totalTokenBurned)` 的实参恒等于本轮 `_burnLp` + `swap` 刚收到的量，净流入为 0。测试 `test_settlementNeverTouchesBoostBacking` 在结算后断言 `balanceOf(stake) ≥ Σ boostShares` |
| 7a | M1 `init:94-97` 无比例和上界 → 和 = 1e18+1 时 `rewardAvailable:455` 下溢 | **成立** | 算术成立；但 `DeployCore:155-160` + `21_check:517-518` 两层拦住。链上仍无 require → 表 E 记「三层闭合」，不登记 |
| 7b | M1 `_updateLaunchCredit:471-473` 提前 return 时不入账不发事件 | **成立，但无害** | `issuedCount >= maxCount` 时额度已发满，累计 credit 不再有意义；该笔额度在事件流里消失，但对应的发射权也已耗尽（`MNT-05`） |
| 8a | M2 三次独立外部读（`:116`、`:270-286`）在轮次已结束后是否必然一致 | **成立（一致）** | `Vote` 只写 `currentRound()`，`_isRoundEnded` 要求 `currentPhase > round` → 该轮数据冻结。唯一例外是有人拿同一 `round` 参数调 `mintProposalReward` 的 view，见 `MNT-03` |
| 8b | M2 `_burnCancelledPool:163-173` 只加 `_rewardBurned` 不减 `_rewardReserved` → 被取消额度回流 `rewardAvailable` | **成立** | 这是正确的守恒口径（`R − M − B`），不是缺陷；但事件名让索引器误以为供应减少（`MNT-04`） |
| 9 | M4 `_calculateEligibleProposalVoteAmount:270-298` 的求和必须恰等于本轮达标票之和 | **成立，且确实相等** | `votedProposalIds` 每个提案至多一行（`Vote:262-263` 只在「对该提案首票」时 push），逐条判据与 `:319` 完全同源 ⇒ Σ 达标票 == `eligibleVoteAmount` ⇒ `:340` 的各提案分配之和 ≤ `proposalReward`。**越预留不成立** |
| 10 | V3 加速快照「首投全量、后续只补增量、从不下降」依赖 Stake 轮内 `validBoostShares` 单调不减 | **成立** | 轮内减少只有两处：`unstake:202-205`（前置 `_hasUsedStakeRights` 挡住已投票者）与 `_mergeIntoTarget` 的 source 侧（同被 `:286-288` 挡住）。`stakeBoost`、`_creditLiquidity`、merge 的 target 侧只增。性质测试 `test_mergeZeroesSourceVotesForAllLaterRounds` 覆盖 source 清零后的历史回退 |
| 11 | P1 `sync:116-121` 只钳下界（`observed==0?1`）不钳上界 | **成立** | 测试 `test_phaseBlocksHasNoUpperClamp`：1001 块 / 1 秒的窗口把下一阶段长度写成 1,001,000，无任何上界（`PHS-01`） |
| 12 | L4 `_createToken:256-260` 复用预建 Pair 零覆盖 | **成立（覆盖缺口）** | 本次补 `test_launchReusesPrecreatedPair`：地址可预测、`createdPairCount` 不增、子币可正常质押。结论是无害（`LCH-01`） |
| 13a | N2 `calculateMintCost:110` 的 `unmintedSupply/BASE_DIVISOR` 可 floor 到 0 | **成立** | 供应接近上限时身份免费（`NFT-03`）；但身份本身不给票权，只解除 `member owner` 门槛 |
| 13b | N2 `:121` `MULTIPLIER**difference` 在阈值过大时溢出 | **成立** | 无任何一层检查 `MULTIPLIER^(BYTES_THRESHOLD−1) × baseCost < 2^256`，是表 E 里唯一「三层皆无」的行 |
| 14 | N3 `_isValidNameChars:230-363` 与 `_toLowerCase:365-378` 的组合断言「接受集合 = 白名单」 | **成立，但有洞** | 黑名单式补集漏掉 U+180E（蒙古文元音分隔符）、U+3164（谚文填充符）等不可见码点，二者都被 `_toLowerCase` 原样保留 → 视觉同形名共存（`NFT-01`，已测） |

**14 组全部有判决，7 个「成立但不构成缺陷」的条目都给了不可达/无害的理由，没有一条用「设计如此」收尾。**
