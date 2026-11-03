# 01 · 架构地图

只产表，不找 bug。每行给出 `文件:行`，均已对 `9297a33` 核对。

## 表 A · 合约面

| 合约 | 行数 | 继承 | 外部依赖 | 持资产 | 可升级 | delegatecall / selfdestruct | 权限角色 | runtime |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `Stake.sol` | 877 | `IStake` | Phase / Vote / Submit / Launch / MemberNFT / Token / Pair / Factory / Router | **是**（Boost 代币 + LP） | 否 | 无 | `onlyMemberOwner(memberId)`；`settleFees` 任何人 | 14,585 |
| `Mint.sol` | 557 | `IMint` | Vote / Submit / Launch / MemberNFT / Phase / Token | 否 | 否 | 无 | `onlyMemberOwner`（mintGovReward\*）、`onlyProposalTarget`（mintProposalReward） | 10,021 |
| `MemberNFT.sol` | 379 | `ERC721Enumerable` + `IMemberNFT` | Token（首币） | 否（手续费瞬时过账） | 否 | 无 | `mint` 开放；`init` 开放且一次性 | 11,500 |
| `Launch.sol` | 350 | `ILaunch` | Factory / Token / MemberNFT / Distributor | 否 | 否 | 无 | `onlyMint`、`onlyMemberOwner`；`init` 开放且一次性 | 12,229 |
| `Submit.sol` | 339 | `ISubmit` | Phase / Stake / MemberNFT / ProposalTarget | 否 | 否 | 无 | `onlyMemberOwner` + 票权门槛 | 10,861 |
| `Vote.sol` | 293 | `IVote` | Phase / Stake / Submit / MemberNFT / ProposalTarget | 否 | 否 | 无 | `onlyMemberOwner` + 票权 > 0 | 6,476 |
| `Phase.sol` | 162 | `IPhase` | — | 否 | 否 | 无 | 无（`sync` 开放） | 4,000 |
| `LOVE20Token.sol` | 59 | `ERC20` + `ILOVE20Token` | — | 否 | 否 | 无 | `onlyMinter`（Mint）；`burn` 任何人可烧自己的 | 2,384 |

与计划表 A 的差异：无。计划未列的 `runtime` 列取自本次 `forge build --sizes`。

## 表 B · 资产与出口

| 资产 | 实际存放 | 谁能动 | 出口 / 记账 | 边界 |
| --- | --- | --- | --- | --- |
| 社区代币（Boost 押金） | `Stake` 合约余额 | 持有人 `withdraw` | `_push:508` → `Stake:244-247` 扣 `totalBoostShares` | 只退 `member.boostShares`，且先写账本再转账之外无其它扣减 |
| 社区代币（结算销毁） | `Stake` 瞬时持有 | 任何人 `settleFees` | `_burnLp:821` 收入 → `_swapParentTokenForToken:827` → `burn:831` | 烧的量恒等于本轮刚从 pair 收到的量，不触碰 Boost 押金（`STK-03`/测试 `test_settlementNeverTouchesBoostBacking`） |
| 父币 | `Stake` 瞬时持有 | 同一条结算链 | Router `swap:868` → 输出社区代币 → 烧 | 同上，净余额为零 |
| LP | `Stake` 合约 | `withdraw` / `settleFees` | `_burnLp:768`（`pair.burn` 直接付款给 `msg.sender`）或 `_push:756`（LP 转给持有人） | 合约 LP 余额恒等于 `lastFeeLp + lastWithdrawableLp`；外部转入的 LP 无人可认领（`Stake:725-726` 注释即此意） |
| 会员 NFT | 用户 | ERC721 转让 | 费用 `MemberNFT:85-86` → 转给自身再烧 | 不属于 `Stake` 的托管资产 |

**唯一托管资产的合约是 `Stake`**。其余合约的「资金类」问题只能降级成账本或可用性问题——本轮在 `Mint`/`Launch`/`Submit`/`Vote` 里也确实没有出现资产出口。

## 表 C · 外部调用与回调面

按「会不会动状态」分类。计划说 16 处；按调用点数是 22 处（差异在于把 `forceApprove`、`_safeMint` 的接收方钩子、`createPair` 各算一处）。

**会改外部状态的（11）**

| # | 位置 | 调用 | 被调方可信度 | 备注 |
| --- | --- | --- | --- | --- |
| 1 | `Stake:505` | `safeTransferFrom(token, user, this)` | 社区代币 = 本仓 `LOVE20Token`（无钩子） | Boost 入账 |
| 2 | `Stake:510` | `safeTransfer(token, to, boost)` | 同上 | Boost 退款 |
| 3 | `Stake:646-649` | `safeTransferFrom` ×2 + `transfer` ×2 → pair | 同上 | 入池 |
| 4 | `Stake:651` | `pair.mint(this)` | V2 Pair | LP 铸造，`pair` 内 `lock` |
| 5 | `Stake:752 / 756 / 820` | LP `transfer` | V2 Pair（LP 本身是普通 ERC20） | 送 LP 去烧 / 直接给持有人 |
| 6 | `Stake:768` | `pair.burn(to)` | V2 Pair | **向 `to` 付款**，`to` 可为 `msg.sender` 或 `this` |
| 7 | `Stake:831` | `token.burn(n)` | 本仓 `LOVE20Token` | 烧自身余额 |
| 8 | `Stake:866 / 868` | `forceApprove` + `swapExactTokensForTokens` | V2 Router | 结算换币 |
| 9 | `Mint:210 / 531` | `token.mint(to, amount)` | 本仓 `LOVE20Token`，`onlyMinter` | 唯一铸币入口 |
| 10 | `Mint:496` | `launch.addLaunchCount` | 本仓 `Launch`，`onlyMint` | 额度入账 |
| 11 | `Launch:75 / 258 / 251` | `MemberNFT.init`、`factory.createPair`、`new LOVE20Token` | 本仓 / V2 Factory | 部署序列的组成部分 |
| 12 | `MemberNFT:85-86` | `transferFrom` + `burn` | 本仓 `LOVE20Token` | 身份费 |
| 13 | `Submit:321` | `IPhase.sync()` | 本仓 `Phase` | 每轮首个推举者触发 |

**回调面（3 个入口，4 个钩子）**

| 面 | 位置 | 传入的身份信息 | 谁决定被调方 |
| --- | --- | --- | --- |
| 回调 1 · 提案生命周期 | `Submit:329`（`onProposalCreated`）、`Submit:336`（`onProposalSubmitted`） | `tokenAddress, proposalId, memberId, targetData` —— **不含 `msg.sender`** | 提案创建者（`ProposalBody.target`，`Submit:236` 要求有代码） |
| 回调 2 · 投票 | `Vote:286`（`onProposalVoted`） | `tokenAddress, round, proposalId, memberId, voteAmount, targetData` | 同上 |
| 回调 3 · 发射 | `Launch:150`（`onTokenLaunched`） | `tokenAddress, parentTokenAddress, memberId, distributorData` | 发射者（`launchToken` 的 `distributor` 参数，`Launch:316` 要求有代码） |
| 回调 4 · ERC721 接收 | `MemberNFT:89`（`_safeMint` → `onERC721Received`） | `operator, from, tokenId, data` | 接收方地址 |

**只读依赖（不改状态，共 20 余处，按用途归并）**

| 用途 | 位置 |
| --- | --- |
| 轮次 | `Stake:444`、`Mint:101`、`Submit:45`、`Vote:103`、`Vote:110` |
| 票权 | `Stake:500-501`、`Submit:79-80`、`Vote:235`、`Vote:291`、`Mint:116/133/290/311/312/369/374/393/398/441` |
| 身份 | `Stake:102`、`Mint:226/424`、`Submit:99`、`Vote:63`、`Launch:37/167/264` |
| 代币登记 | `Stake:476`、`Launch:87/103/163/192` |
| 供需 | `Mint:453-455`、`MemberNFT:108`、`Launch:194` |
| 池子 | `Stake:662-664`、`Stake:516-517`、`Stake:862` |

## 表 D · 高风险路径清单

→ 直接进第三层，每条一页。

| # | 起点 | 核心问题 | 页 |
| --- | --- | --- | --- |
| P-01 | `stakeLiquidity` → `_addLiquidity` → `pair.mint` → `_creditLiquidity` → `_reclassify` | 首存/通胀：捐赠后存入，受害者多付多少？谁赚？ | `05-paths/P-01.md` |
| P-02 | `_settleFees` → `_realizeFees` → `_swap` → Router | `amountOutMin` 同笔现算；单次结算的价格冲击上限 | `05-paths/P-02.md` |
| P-03 | `submitNewProposal` → `_submitByProposalId` → `onProposalCreated` → `mergeStake` / `vote` | 回调内能否融合、能否绕过「已用票权」 | `05-paths/P-03.md` |
| P-04 | `unstake` → `withdraw` → `_withdrawLiquidity` → `_settleFees` → `_push` | 已解锁未提取窗口里谁能动这笔钱 | `05-paths/P-04.md` |
| P-05 | `Phase.sync` → `Submit` 首推 → `Vote` / `Mint` / `Stake` 的轮次读 | 时间轴被放大的影响面 | `05-paths/P-05.md` |
| P-06 | `_prepareRewardIfNeeded` → `_mintGovReward` → `_updateLaunchCredit` → `Launch.addLaunchCount` | 四个账本是否守恒 | `05-paths/P-06.md` |
| P-07 | 三个回调面 | 回调可见的中间态 × 可达写入口矩阵 | `05-paths/P-07.md` |
| P-08 | 7 个 `init` → `rewardAvailable` / `_meetsSubmitPower` | 哪些参数组合让入口永久不可用，哪层拦 | `05-paths/P-08.md` |

## 表 E · 参数域台账

四层防线：**链上 require**（合约自己判）→ **广播前**（`DeployCore._validateConfig`，模拟阶段）→ **广播后**（`21_check.sh`，链上读回）→ **字面量一致性**（`deploy_scripts_test.py` 钉住两份常量）。判级口径：四层闭合即不登记为漏洞，只有「某组合能让已正确部署的实例失效」才升级。

| 参数 | 链上 require | 广播前 `DeployCore` | 广播后 `21_check` | 缺失后果 | 判定 |
| --- | --- | --- | --- | --- | --- |
| `FEE_SETTLEMENT_RATIO` | 无（`Stake:83-94` 只防重复初始化） | `:173-177` 非零且 ≤ `MAX_FEE_SETTLEMENT_RATIO = 2.5e15` | `:487` ≤ `2500000000000000` | > 池费率 → 单笔结算成为可夹的价格冲击 | 三层闭合 |
| `ROUND_REWARD_GOV_RATIO + PROPOSAL_RATIO` | 无（`Mint:82-98`） | `:155-160` 各 ≤ 1e18，且 proposal ≤ 1e18 − gov | `:517-518` 和 ≤ 1e18 | 和 > 1e18 → `rewardAvailable:455` 下溢 → 全部铸造永久 revert | 三层闭合 |
| `SUBMIT_MIN_RATIO` | 无（`Submit:55-58`） | `:166` 非零且 ≤ 1e18 | `:476` 非零、`:485` ≤ 1e18 | = 0 → `_meetsSubmitPower:85` 恒 false → 提案砖化 | 三层闭合 |
| `MAX_GOV_BOOST_REWARD_MULTIPLIER` | 无（`Mint:82-98`） | `:161-164` 非零且 ≤ 1000 | `:484` ≤ 1000 | 上界失真 → `Mint:405` 的封顶失效 | 三层闭合 |
| `PROMISED_WAITING_PHASES_MIN/MAX` | 无（`Stake:83-94`） | `:168-172` MIN 非零、MIN ≤ MAX | `:477` 非零、`:525` MIN ≤ MAX | MIN = 0 → 零票权仓位；`_mergeIntoTarget:532` 的「空目标」判据失效 | 三层闭合 |
| `TOKEN_SYMBOL_LENGTH + TEST_PREFIX_BYTES` | 无（`Launch:54-66`） | `:148-151` 非零且 +4 ≤ `MAX_TOKEN_SYMBOL_LENGTH = 32` | `:250-265` **从链上读** `MAX_TOKEN_SYMBOL_LENGTH()` 与 `TEST_PREFIX_BYTES()` 后现算 | 超 32 → `_createToken:248` 必 revert → 该社区永远无法发射子币 | 三层闭合（`:262` 不再复制字面量） |
| MemberNFT 四参数 | 无（`MemberNFT:41-51` 构造函数） | `:129-132` 各自非零 | 有 | `BYTES_THRESHOLD` 过大 → `calculateMintCost:121` 的 `MULTIPLIER**difference` 溢出 → 短名永远铸造失败 | **广播前只查非零，未查溢出上界**（见 `NFT-03`） |
| Phase 五参数 | 无（`Phase:33-46` 只存） | `:134-141` 各自非零、`ADJUST_THRESHOLD ≤ 1e18` | 有 | `originPhaseBlocks = 0` → `phaseAtBlock:70` 除零；`ADJUST_THRESHOLD = 0` → 每次 `sync` 都调整 | 三层闭合 |
| Router / Factory / WETH | 无（`Stake:77-78` 只存） | `:184-192` 都有代码、`router.factory == FACTORY`、`router.WETH()` 有代码 | 有 | 不一致 → `_pairFor:516` 取错 Pair | 三层闭合 |

唯一「三层皆无」的一行是 MemberNFT 的指数溢出上界，登记为 `NFT-03`（Low）。其余见 `P-08`。

## 表 F · 部署序列

事实（逐条对代码核对）：

| # | 事实 | 位置 |
| --- | --- | --- |
| 1 | 7 个 `init` 全部只判 `initialized`，**无调用者限制** | `Stake:83`、`Mint:82`、`Submit:55`、`Vote:52`、`Launch:55`、`MemberNFT:55`、`Phase` 用构造函数（无 `init`） |
| 2 | `DeployCore` 逐个 `new` → 逐个 `init`，全程在一个 `startBroadcast/stopBroadcast` 里 | `DeployCore:195-283` |
| 3 | `11_deploy.sh` 用 `--slow` → 每笔都要等确认 | `script/deploy/11_deploy.sh` |
| 4 | `_validateDeployment` 在 `vm.stopBroadcast()` **之后**才跑 | `DeployCore:89` vs `:91` |
| 5 | `Launch.init:75` 内部调 `MemberNFT.init` | `Launch:75` |
| 6 | 抢跑任一 `init` → 该合约永久 `AlreadyInitialized`，无 setter | 各 `init` 首行 |
| 7 | 参数侧几乎零校验：`Stake.init` 对 `FEE`/`ROUTER`/`FACTORY` 一个 `require` 都没有 | `Stake:83-94` |

**独立定级（不引用任何既有裁决）**：确定性损失是「任何人可随时打断部署 + 8 个不可删除的孤儿合约 + 接线与经济常量由首个调用者决定」；资金损失是条件性的（要部署方无视脚本非零退出继续公布）。见 `03-findings/launch.md` 的 `DEP-01`（Medium）。
