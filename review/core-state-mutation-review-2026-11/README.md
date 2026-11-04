# core/ 状态变量变更审查 · 2026-11

> 基线：`core@0466d67`（`git status --short` 仅 `?? test/audit/`，`src/` 干净）。本卷全部结论已在该提交上逐条复核。
> 范围：`core/src/` 8 个实现合约、**3,097 行**；`src/interfaces/` 10 个文件无状态，不单独立卷；`libs` 的三个存储库（`RoundHistoryUint256` / `OrderedHistoryIndex` / `Pagination`）的写入语义并入 `05-stake.md`、`04-phase.md`。
> 判据：只判**代码自身的状态一致性** —— 某变量的一次写入是否有守卫、是否与联动变量同笔、是否排在外部调用之前、谁能触发、失败时是否整笔回滚。规格文档仅用于核对口径，不作判据。
> 与 `core-review-plan-2026-11` 的关系：那份按「函数单元」审，基线 `9297a33`。此后 `1266696` 重写了 Stake 的 LP 账本与结算单位；本卷另在 `0466d67` 上复核了后续几次改动：`1411edb` 新增无许可准备入口、`fe72581` 新增 `lastSyncPhase()`、`78ce1e6` 收敛 Phase 事件、`5c0afc7` 把 `MINTER` / `PARENT_TOKEN_ADDRESS` 改为 `immutable`、`1adaef3` 把 `withdraw` 的 `delete` 前移、`0466d67` 补准备入口测试。因此本卷**不引用其结论**，全部从当前代码重推；重合项在 §4.2 只做复核标注，不重复论证。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。本卷未新增 PoC（`test/audit/` 下为上一轮产物，未改动）。

## 1. 方法与边界

1. **先枚举，再审逻辑**：用赋值 / `delete` / `++` / `.push` / `.pop` / 库写入（`.increase` / `.decrease` / `.record`）七类模式对 8 个文件做全量扫描，逐处归属到状态变量。扫描结果与人工逐行阅读逐条对齐，没有「只读函数列表」造成的漏项。
2. **每个变量四问**：谁能写（鉴权）→ 写之前校验了什么（守卫）→ 同一笔里还写了谁（联动）→ 写在前还是外部调用在前（顺序）。
3. **不把「有事件」当正确性证据**：事件只用于对账，不作为写入合法的依据。
4. **不可达路径单独标注**：静态存在但无入口可达的写入（如 `MemberNFT._update` 的 `to == 0` 分支）不计入风险，只计入覆盖说明。

### 1.1 存储库的写入语义（所有 `_valid*` / `_total*` 账本共用）

| 库 | 关键语义 | 对本卷的影响 |
| --- | --- | --- |
| `OrderedHistoryIndex.record(key)` | 仅当 `key > keys[last]` 时追加；`key == keys[last]` 走 `assert`（Panic 0x01）；`key < keys[last]` 也走 `assert` | 所有轮次账本的写入轮次必须**单调不减**；一旦某处回写历史轮，得到的是 Panic 不是业务错误 |
| `RoundHistoryUint256.value(round)` | 有精确记录取记录，否则取「不大于该轮」的最近记录 | 轮次账本是**累计量**，所以「取自历史」等于「该轮时点的累计值」；这是 `total = added − removed` 结构恒等式成立的前提 |
| `RoundHistoryUint256.increase/decrease` | `record(round, value(round) ± delta)`；`decrease` 下溢即回滚 | 成员账本的减量必须 ≤ 该轮时点存量，否则整笔回滚 |

## 2. 状态总表

| 合约 | 行数 | 自有存储变量 | 部署后可变的部分 | 写入函数（去重） |
| --- | --- | --- | --- | --- |
| `LOVE20Token` | 59 | 3（+ 继承 5） | `_balances` / `_allowances` / `_totalSupply` | `constructor`、`mint`、`burn`、ERC20 `transfer/approve/transferFrom` |
| `Launch` | 350 | 11 + 6 账本 | 6 个账本 + `FIRST_TOKEN_ADDRESS`（一次性） | `init`、`launchToken`、`mergeLaunchCount`、`addLaunchCount` |
| `MemberNFT` | 380 | 4 + 4 immutable + 4 账本（+ 继承 10） | 4 个账本 + `_nextTokenId` + `totalBurnedForMint` | `init`、`mint`、ERC721 转移/授权 |
| `Phase` | 160 | 5 immutable + 9 | 9 个观测/段账本 | `constructor`、`sync` |
| `Stake` | 911 | 10 + 12（含 6 个轮次库） | 全部成员/社区账本 | `init`、`settleFees`、`stakeLiquidity`、`stakeBoost`、`unstake`、`withdraw`、`mergeStake` |
| `Submit` | 339 | 5 + 5 | 5 个 Proposal/推举账本 | `init`、`submitNewProposal`、`submit` |
| `Vote` | 301 | 5 + 9 | 9 个投票/快照账本 | `init`、`vote` |
| `Mint` | 597 | 10 + 9 | 9 个额度/铸造账本 | `init`、`prepareRewardIfNeeded`、`mintProposalReward`、`mintGovReward(s)` |

## 3. 写权限矩阵（谁能推动哪本账）

「触发者」是链上可达的最小权限，不含部署脚本。

| 账本 | 触发者 | 入口 | 说明 |
| --- | --- | --- | --- |
| `Stake._memberStake` | 该 `memberId` 的 NFT 持有人 | `stakeLiquidity` / `stakeBoost` / `unstake` / `withdraw` / `mergeStake`(源) | 目标侧由源持有人间接写 |
| `Stake._totalStake`（份额 / boost） | 同上 | 同上 | 与成员账本同笔增减 |
| `Stake._totalStake`（`lastFeeLp` / `lastWithdrawableLp` / `lastSqrtKOfLp`） | **任何人** | `settleFees`；`withdraw` 与 `stakeLiquidity` 顺带 | 重分类由 Pair 的 √k 决定，不由调用者决定 |
| `Stake._lastSettlePhase` | **任何人** | `settleFees`（达阈值时）/ `withdraw` | 每 token 每 Phase 至多一次 |
| `Stake._pairAddressByTokenAddress` | **任何人**（首次） | `settleFees` / `stakeLiquidity` / `withdraw` | 惰性缓存 |
| `Stake` 四个轮次账本 | 成员持有人 | 四个写点 + `mergeStake` | 轮次恒为 `currentPhase()` |
| `Launch._remainingLaunchCount` | 成员持有人 / `Mint` | `launchToken` / `mergeLaunchCount` / `addLaunchCount` | 两个维度（代币、根父币） |
| `Launch._issuedLaunchCount` | 仅 `Mint` | `addLaunchCount` | 只增 |
| `Launch._tokenAddressBySymbol` | 成员持有人 | `launchToken`（每个最终符号一次） | 全局唯一性来源 |
| `MemberNFT._tokenIdByNormalizedName` | 任何人（付费） | `mint` | 永不释放 |
| `MemberNFT._holders` / `_holderIndex` | NFT 持有人 | `transferFrom` / `safeTransferFrom` / `mint` | 余额 0↔1 时增删 |
| `Submit._proposals` / `_proposalIdsByAuthor` | 达 `canSubmit` 的成员持有人 | `submitNewProposal` | 永久追加 |
| `Submit._submits` / 两张反查 | 达 `canSubmit` 的成员持有人 | `submitNewProposal` / `submit` | 每 token 每轮 ≤1000 |
| `Vote` 九个账本 | 有票权的成员持有人 | `vote` | 轮次恒为 `currentPhase()` |
| `Mint._totalRewardReserved` / `_isRewardPrepared` | **任何人**（任意已结束轮） | `prepareRewardIfNeeded` / `mintGovReward(s)` / `mintProposalReward` | 幂等，只对已结束轮生效；准备入口与两个领取入口共用同一 internal 实现，池值按当时水位落账 |
| `Mint._govMinted` / `_launchCredit` | 成员持有人 | `mintGovReward(s)` | 一次一份 |
| `Mint._proposalMinted` | 提案 `target` | `mintProposalReward` | 一次一份 |
| `Phase._observation*` / `_segment*` | **任何人** | `sync` | 每 Phase 至多一次有效写入 |

## 4. 发现汇总

### 4.1 本卷新增

| ID | 级别 | 合约 | 一句话 | 证据 |
| --- | --- | --- | --- | --- |
| `LCH-06` | Info | Launch | 首币路径绕开 `_checkValidTokenSymbol`，`_tokenAddressBySymbol` 的第一个键不受字符集约束（规格已定为有意） | E1 |
| `MNT-06` | Info | Mint | 预留额度无到期、无回收：未领取的池子永久占用 `rewardAvailable`（仍可随时领取），取整余数按规格永久保留 | E2 |
| `MNT-07` | Info | Mint | 三个参数越界会让激励系统永久不可用且无 setter；三者都已在 `DeployCore` 广播前校验，合约侧零守卫（记录这条单点依赖） | E2 |
| `NFT-04` | Info | MemberNFT | 合约没有任何 burn 入口，`_update` 的 `to == 0` 分支不可达；名称与 `tokenId` 永久占用 | E1 |
| `NFT-05` | Info | MemberNFT | 黑名单漏掉 U+115F / U+1160 / U+3164 / U+FFA0 / U+2800 等「渲染为空白」的码点，可铸造视觉空名 | E1/E2 |
| `LCH-05` | Info | Launch | 符号唯一性落账晚于 `createPair`；仅恶意/可升级 factory 的重入成立，按部署期信任假设判不可达 | E1 |
| `STK-07` | Info | Stake | `pair.burn(to)` 烧的是 **Pair 自身持有的全部 LP**，不是本次的 `lpAmount` / `settlementUnit`；有 LP 被转入 Pair 时，事件里的「烧了多少」与账本减量不一致 | E1 |
| `STK-08` | Info | Stake | `pairAddress` 惰性缓存：首次质押/结算前对外返回 `0`，与「已登记代币必有 Pair」冲突 | E1 |
| `STK-09` | Info | Stake | `_lastSettlePhase` 用 `0` 兼作「从未结算」，与 Round 0 同值；当前只因「Round 0 不可能有手续费 LP」而安全 | E1 |
| `SUB-01` | Info | Submit | `_createProposal` 先写两本账并发事件，再判本轮名额与 1000 上限；可观测等价（全部回滚），但与规格步骤表顺序不一致；`SUBMIT_ROUND_LIMIT` 无 getter | E1 |
| `SUB-02` | Info | Submit | `_submits` 按轮分数组、跨轮只增不减，链上没有「全部推举」的读路径 | E1 |
| `VOT-02` | Info | Vote | 承载 Mint 分母的 `_voterBoostByMemberId` 注释写「首投快照」，代码与规格都是「只补正增量」；`isFirstVoteByMember` 的名字也不是「本轮首次」 | E1 |
| `VOT-03` | Info | Vote | 批次长度无协议上限，单笔 gas 上界由调用者自选 | E1 |
| `PHS-02` | Info | Phase | 段表与观测表的三条不变量只由 `assert` 与「每 Phase 一次」的时序共同保证；时序前提一变，失败形态是 Panic | E1 |
| `PHS-03` | Info | Phase | `phaseInfo` 对未来 Phase 返回外推值，与已记录值不可区分 | E1 |
| `X-01` | Info | Stake / Mint | 两处地址不是 `init` 入参而是从 `Vote` 读：`Stake` 用 `Vote.SUBMIT_ADDRESS()` 判「本轮已推举」，`Mint` 用 `Vote.PHASE_ADDRESS()` 判轮次；接线错配时没有链上断言会失败 | E1 |
| `TOK-03` | Info | LOVE20Token | `mint(to, 0)` / `burn(0)` 不设零额守卫，会发零额事件 | E1 |

分布：新增 **17 条**，**Info 17**，无 Critical / High / Medium / Low（另有 2 条在复核期间修复，见 §4.1.1）。

### 4.1.1 复核期间已修复

| ID | 原级别 | 修复提交 | 状态 | 一句话结论与证据 |
| --- | --- | --- | --- | --- |
| `TOK-04` | Info | `5c0afc7`：`MINTER` / `PARENT_TOKEN_ADDRESS` 改为 `immutable`（`LOVE20Token.sol:9-10`） | 已修复（5c0afc7） | 构造后不再写的值现由编译器保证不可变，`mint` 的 `MINTER` 读取走立即数；`MAX_SUPPLY` 与二者口径一致。E1 |
| `STK-03` | Info | `1adaef3`：`withdraw` 的 `delete _memberStake` 前移到 `_withdrawLiquidity` 之前（`Stake.sol:244`） | 已修复（1adaef3） | 先清成员账、再动资产（`_withdrawLiquidity:251`、`_push:256`），CEI 恢复，`S12` 的附条件风险随之关闭。E1 |

### 4.2 复核确认（既有审查已登记，在 `0466d67` 仍成立）

只列与状态写入直接相关、且本卷逐行复核后仍成立的项；括号内为上一卷 ID。

| 级别 | 项 | 状态写入视角的复核点 |
| --- | --- | --- |
| Medium | 名称唯一性只折 ASCII 大小写（`NFT-01`） | `MemberNFT:222`（校验调用）、`:366-379`（`_toLowerCase`）未变 |
| Medium | 7 个 `init` 无调用者限制（`DEP-01`） | 本卷在 `03-membernft.md`、`07-vote.md` 各补一条**具体的**抢跑后果：`MemberNFT.init` 被抢跑会让 `Launch.init` 整笔回滚（部署作废）；`Vote.init` 被抢跑会让 `onlyMemberOwner` 指向攻击者的 NFT |
| Low | `sync` 把 `observed` 原样写成下一段长度，无上下限（`PHS-01`） | `Phase:118-121` 未变；本卷补充「采样点本身不是自由旋钮」的推导（见 `04-phase.md` §4.3） |
| Low | 份额对应 LP 取整为 0 时静默删份额（`STK-02`） | `Stake:785-799` 的 `lpAmount == 0` 分支未变 |
| Low | 根级维度与代币维度共用一次额度，社区实际发射容量是 `2 × MAX_LAUNCH_COUNT`（`LCH-02`） | `Launch:201-203` 的伴生写入未变，本卷给出账本口径证明（`02-launch.md` §3 L5-L8） |
| Info | 「手续费 = 任何 √k 增值」是政策（`STK-04`）；`W → 0` 结算停摆（`STK-05`） | 两条均未变化 |

### 4.3 机制设计项（兑现，不计入缺陷分布）

#### `STK-01` · 提升承诺等待期放大票权 + 门槛乘活分母 = **兑现（机制设计）**

这是定价机制，不是缺陷：**相同资产下，共识高者选择更长的解锁期，换取更高票权与治理激励**。拉满是**自愿选择**而非必经路径，低共识者可以选择更短的解锁期，因此 `MAX/MIN` 的倍差始终保留区分度。

- 代码与规格口径一致：`Stake:159-164` 按 `liquidityShares × (P_new − P_old)` 补票；`Submit:79-86` 每次重读 `totalValidGovVotes`；规格 `05-submit.md:96`、`04-stake.md:118` 明确要求活分母与活票权。
- 参数演算（生产示例 `MIN=1`、`MAX=100`、`SUBMIT_MIN_RATIO=0.3%`）：等份额且所有人都在 `MIN` 时，某成员把 P 拉到 `MAX` 后的过渡态排除区间约为 `235 ≤ N ≤ 33,234`（再大该成员自己也过不了）；份额不均时，51% 份额可把门槛抬到约 15.4% 份额，所有更小的成员出局。
- **失效边界**：上述「排除区」只在过渡态成立——当事人 1 wei 即可自补，故该假设不成立。1 wei 只是入场券，真实成本是接受 `MAX` 个 Phase 的锁定期；对手也可以同样拉满反制，`P` 只增不减使效果跨轮持续，但不是不可逆的垄断。
- 已申请解锁的成员**不在分母内**：`unstake` 在 `Stake:205-209` 把该成员的 `validGovVotes` 减到 0、把 `boostShares` 移出有效账本，因此不存在「已申请解锁者被稀释或排除」的问题。

#### `MNT-01` · 奖池由首个触发者定 = **机制设计，非缺陷**

`prepareRewardIfNeeded` 提供的是「**任何地址都能在轮次结束后立即准备**」的确定性，不是对某个攻击的缓解；正常运转下每轮都有人铸币，准备动作本就发生在轮次一开始，因此不存在「谁先动手谁压低池子」的对抗性窗口。

- 池值口径：`Mint:130-134` 的 `available × ratio` 是准备时的实时快照，`_totalRewardReserved` 只有这一处增加；三个入口（`prepareRewardIfNeeded` / `mintProposalReward` / `mintGovReward(s)`）共用同一 internal 实现，口径一致。
- 边界备注 (a)：若某轮确实无人铸造、直到多轮之后才有人领取或准备，池值按**当时水位**落账。这是可观察的时序属性，不是缺陷。
- 边界备注 (b)：若将来引入「轮内 `rewardAvailable` 会增长」的新资金来源路径，此条需重新评估。

### 4.4 本卷判定为「不是缺陷」的疑点

| 疑点 | 结论 |
| --- | --- |
| `Vote._vote` 把加速快照写在票数上限判定**之前** | 同一笔交易内，超限整笔回滚，快照随同撤销；顺序不产生中间态 |
| `Submit.submitNewProposal` 在名额校验前就写了 `_proposals` | 任何后续回滚都撤销该写入；`proposalId` 由 `length + 1` 现算，不会留空洞 |
| `Phase.sync` 的观测点可由调用者挑选 | `observed = elapsedBlocks × TARGET / elapsedSeconds` 是**速率**量，调用者只能选区间终点，起点由规则决定；要拉偏必须让真实出块速率本身偏离目标（`04-phase.md` §4.3） |

## 5. 处置与后续

本卷新增项全部为 Info，没有需要改代码的 Critical / High / Medium / Low；另有 2 条已在复核期间修复。

1. **已修复，无需后续**：`TOK-04`（`5c0afc7`）、`STK-03`（`1adaef3`）。
2. **机制设计，不改代码**：`STK-01` 是「更长解锁期换更高票权」的定价机制，`MNT-01` 是「任何地址可立即准备」的确定性；二者都不需要修实现。若要调整博弈，只动规格/参数旋钮（`MAX/MIN`、`SUBMIT_MIN_RATIO`），不是修 bug。
3. **不可达，可选硬化**：`LCH-05` 按当前信任模型不需要改代码；若未来换成可升级/可回调 factory，再考虑哨兵预留。
4. **文档性修正（零风险）**：`VOT-02` 的注释与布尔命名、`SUB-01` 的 `SUBMIT_ROUND_LIMIT` getter、`STK-08` 的 `pairAddress` 语义说明。三项都不改经济逻辑，只降低误读成本。

## 6. 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 无 PoC | 本卷是静态审查。17 条新增中 14 条 E1、2 条 E2、1 条 E1/E2；`LCH-05` 已按部署期信任假设判为不可达，不构造恶意 factory PoC |
| 门禁 | 已在 `core@0466d67` 上跑过，五项全绿，结果见下表 |
| 未审继承实现 | `ERC20` / `ERC721` / `ERC721Enumerable` 的行为按 OpenZeppelin 5.6.1 的公开语义认定，未逐行复核 |
| 未审跨仓 | `action/`、`group-chat/` 对 core 账本的二次写入不在本卷范围 |

### 6.1 门禁结果（`core@0466d67`）

| 命令 | 结果 |
| --- | --- |
| `forge build --force --deny warnings` | ✅ 退出码 0。仅有 solar 预处理器的一条 `WARN`（OZ `draft-IERC6093.sol` 的重复声明诊断），不是 solc warning，且此前各轮同样存在；编译产物正常 |
| `forge lint` | ✅ 退出码 0，无输出 |
| `forge test --summary` | ✅ 21 个套件 **513 passed / 0 failed / 0 skipped**（`MintTest` 27 条，含本卷新增的两条准备入口测试） |
| `env -u PYTHONPATH python3 script/events/check-events.py` | ✅ `event manifest OK: 28 events; families OK; declaration style OK; emit style OK; emit keys OK`，退出码 0 |
| `env -u PYTHONPATH python3 test/deploy_scripts_test.py` | ✅ `Passed 41 isolated deployment checks (no network calls or broadcasts).`，退出码 0 |

## 7. 文档索引

| 文件 | 合约 | 存储变量 | 对应发现 |
| --- | --- | --- | --- |
| [`01-love20token.md`](01-love20token.md) | `LOVE20Token` | 3（+ 继承 5） | `TOK-03`；`TOK-04`（复核期间已修复） |
| [`02-launch.md`](02-launch.md) | `Launch` | 11 + 6 账本 | `LCH-05`、`LCH-06` |
| [`03-membernft.md`](03-membernft.md) | `MemberNFT` | 4 + 4 immutable + 4 账本（+ 继承 10） | `NFT-04`、`NFT-05` |
| [`04-phase.md`](04-phase.md) | `Phase` | 5 immutable + 9 | `PHS-02`、`PHS-03` |
| [`05-stake.md`](05-stake.md) | `Stake` | 10 + 12 | `STK-07`、`STK-08`、`STK-09`、`X-01`；`STK-03`（复核期间已修复）、`STK-01`（机制） |
| [`06-submit.md`](06-submit.md) | `Submit` | 5 + 5 | `SUB-01`、`SUB-02` |
| [`07-vote.md`](07-vote.md) | `Vote` | 5 + 9 | `VOT-02`、`VOT-03` |
| [`08-mint.md`](08-mint.md) | `Mint` | 10 + 9 | `MNT-06`、`MNT-07`；`MNT-01`（机制） |

行号基准 `0466d67`。
