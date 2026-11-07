> 历史卷标注：本文中关于根父币计数维度与 `2 × MAX_LAUNCH_COUNT` 的描述已被 `dac6d59` 取代；正文保持原样，不再作为当前实现依据。

# LOVE20BSC `core/` 分层安全审查计划

> 判据：**设计合理性**。规格文档只当背景资料，不作判据 —— 代码与文档冲突时不判"漂移"，只判"这个机制值不值得攻击、失效时谁承担损失"。
> 产出边界：**含 PoC 测试、不含修复**（只读 `src/`，允许在 `test/` 新增复现）。
> 执行：同链串行、链间并行。所有结论落 `文件:行`，行号基准 = `9297a33`（工作树干净，已复核）。

## 0.0 审查范围：整仓 `src/`，不是 diff

| 维度 | 本次 |
| --- | --- |
| **审什么** | `core/src/` 全部 8 个文件 **4076 行**（7 个实现 + 6 个自有接口 + 3 个 V2 接口），逐函数、逐分支，切 29 个单元 |
| 最新提交的作用 | `9297a33` 只改 `Launch.sol`（加常量 `:28`、`:326` 用常量）与 `ILaunch.sol`（`:114` 加 getter）；其余 6 个合约自 `1dcdaff` 未动 → 行号稳定，可直接引用 |
| 部署脚本 | 只作"参数域 + 初始化绑定"的证据引用（表 E / 表 F），不审实现 |
| 共享库 | `lib/libs` 中 core 用到的 3 个（`RoundHistoryUint256` / `OrderedHistoryIndex` / `Pagination`，144 行），并入 LEDGER 上下文包 |
| 不作判据 | `matt-gov/docs/specs/core/**`。需要知道"当初想干什么"时读它，但结论必须由代码自身的机制推出 |
| 既有报告 | **不读、不引用**。`.scratch/` 下的历史审计产物不进上下文，也不作为缩小范围、跳过单元、降低级别的依据 |
| 不在范围 | `test/` 自身质量（只在 §0.4 补缺口）、`action/`、`group-chat/`、`dex/`、`compatibility/` |

不按 diff 审：本轮改动实质只有一个常量 + 一个 getter；而真正没验证过的风险全在**没改过**的代码里（Stake 的资金结论只在简化 Mock 上成立、H-01 修复分支零覆盖、Mint 的越预留路径从未算过）。

## 0. 基线（B0，未做完不许开审）

### 0.1 冻结

| 项 | 内容 |
| --- | --- |
| 基线提交 | `9297a33`，`git status --short` 为空 |
| 源码改动面 | 仅 `src/Launch.sol`（`:28` 常量 + `:326` 引用）与 `src/interfaces/ILaunch.sol`（`:114` getter） |
| 其余改动 | 部署脚本 6 个、`params.sh`、anvil profile、`DeployCore.t.sol`、`deploy_scripts_test.py`、`whitepaper` |
| 动作 | `git tag audit-base 9297a33`；把 `rev-parse HEAD`、`forge --version`(1.8.1)、`slither --version`、`git show --stat HEAD` 写进 `evidence/00-baseline.md` |

### 0.2 门禁基线（一条命令一条证据）

```sh
export PATH="$HOME/.foundry/bin:$PATH"
forge build --force --deny warnings
forge lint                      # 期望零输出
forge test --summary            # 基线用例数以实际输出为准
env -u PYTHONPATH python3 script/events/check-events.py
env -u PYTHONPATH python3 test/deploy_scripts_test.py
forge build --sizes
slither . --compile-force-framework foundry   # 只作"新增告警"对照
```

`env -u PYTHONPATH` 必须带：宿主机 Python shim 会拦 `shutil.copytree`，造成假红。Slither 若抗拒 solc 0.8.37，退化到 `--compile-force-framework foundry` 复用 `out/`；仍失败则只跑 `forge inspect` + 手工规则，并在报告写明覆盖率缺口。

### 0.3 证据等级（每条登记项必须标）

| 级 | 含义 | 可支撑的最高严重度 |
| --- | --- | --- |
| E3 | forge 测试复现（真 Core；DEX 需标真/假） | Critical / High |
| E2 | 精确算术推导 + 极值输入，未跑测试 | Medium |
| E1 | 静态可判定（缺校验、顺序、口径不一致）+ 行号 | Low / Info |
| E0 | 仅 slither / forge-lint 提示 | 只进线索池，不进登记表 |

**规则**：资金类结论只在 Mock 上验证 → 最高 E2。

### 0.4 现有测试的 7 处覆盖缺口（按代码独立核出，编号只为定位）

这些不是"已结论"，是**当前测试树里断言不到的地方**。每条都要在本次补齐；补齐前对应单元不得判"已审"。

| 编号 | 缺口 | 现状 | 本次要补 |
| --- | --- | --- | --- |
| C-01 | 伪造代币消耗他人 Boost | `test/Stake.t.sol:1392 testUnregisteredTokenRevertsAllEntries` | 只断言 `TokenNotRegistered`。补"A 结算后 `IERC20(A).balanceOf(stake)` 只减 A 自己的量" |
| H-01 | 预建 Pair 阻断发射 | **无**。`test/Launch.t.sol:126-146 PairFactoryMock` 无预登记接口，但 `createPair` 接受任意地址 → **可测**：`vm.computeCreateAddress(launch, vm.getNonce(launch))` 算下一枚代币地址，先建 Pair 再 `launchToken`，断言复用且 `createdPairCount` 不增 | `testLaunchTokenReusesPrecreatedPair` |
| M-01 | 融合复用 / 提案无界 | `Stake.t.sol:957`、`Submit.t.sol:874` | 补"`onProposalCreated` 回调内融合"（`Submit:301-307` 写早于 `:326`） |
| F-01(旧) | 零 LP 提取回滚 | `Stake.t.sol:773`、`:811`，全在 `MockPair:98-205` 上 | 真 V2 复测 `_canBurn:809` 边界 |
| F-02(旧) | 每轮 1000 推举 | `test/stress/ProposalDoS.t.sol:76` | 真 V2 + 真 Core 复测 gas 预算 |
| F-04(旧) | init 绑定未验收 | `21_check.sh:250-265` 改为从链上读 `TEST_PREFIX_BYTES()` 与 `MAX_TOKEN_SYMBOL_LENGTH()` 再比较 | 只做回归确认 |
| F-09(旧) | 参数上界宽于验收 | `21_check.sh:456-525` 复核 5 组上界 + 两池和；`deploy_scripts_test.py:162-171` 钉住两处 `2.5e15` | 见 §1 表 E |

## 1. 第一层：地图（B1，只产表不找 bug）

产出 `01-architecture-map.md`，六张表。A/B/C 已预填，执行时只做核对。

### 表 A 合约面（预填）

| 合约 | 行数 | 继承 | 外部依赖 | 持资产 | 可升级 | delegatecall/selfdestruct | 权限角色 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `Stake.sol` | 877 | `IStake` | Phase/Vote/Submit/Launch/MemberNFT/Token/Pair/Factory/Router | **是**（代币+父币+LP） | 否 | 无 | `onlyMemberOwner` + 任何人 `settleFees` |
| `Mint.sol` | 557 | `IMint` | Vote/Submit/Launch/MemberNFT/Token/Phase | 否 | 否 | 无 | `onlyMemberOwner`、`onlyProposalTarget` |
| `MemberNFT.sol` | 379 | `ERC721Enumerable`+`IMemberNFT` | Token | 否（瞬时） | 否 | 无 | 无（`mint` 开放） |
| `Launch.sol` | 350 | `ILaunch` | Factory/Token/MemberNFT/Distributor | 否 | 否 | 无 | `onlyMint`、`onlyMemberOwner` |
| `Submit.sol` | 339 | `ISubmit` | Phase/Stake/MemberNFT/ProposalTarget | 否 | 否 | 无 | `onlyMemberOwner` |
| `Vote.sol` | 293 | `IVote` | Phase/Stake/Submit/MemberNFT/ProposalTarget | 否 | 否 | 无 | `onlyMemberOwner` |
| `Phase.sol` | 162 | `IPhase` | — | 否 | 否 | 无 | 无（`sync` 开放） |
| `LOVE20Token.sol` | 59 | `ERC20`+`ILOVE20Token` | — | 否 | 否 | 无 | `onlyMinter`；`burn` 开放 |

### 表 B 资产与出口

| 资产 | 存放 | 谁能动 | 出口 |
| --- | --- | --- | --- |
| 社区代币（Boost） | Stake | `withdraw`（持 NFT）、`_realizeFees` 销毁 | `_push:508`、`burn:831` |
| 父币 | Stake（瞬时） | `_realizeFees` 换币 | Router `swap:868` |
| LP | Stake | `withdraw` → `pair.burn` 或转给提取者 | `_burnLp:768`、`:756` |
| 社区代币存量 | 用户/Stake | `MemberNFT` 手续费 `safeTransferFrom+burn` | `MemberNFT:85-86` |

**唯一托管合约是 Stake** —— 其余合约的"资金类"问题一律降级为账本/可用性。

### 表 C 外部调用与回调（16 处非 view + 3 个回调面）

| 面 | 位置 | 被调方可信度 |
| --- | --- | --- |
| AMM | `pair.mint/burn/transfer`、`factory.getPair`、`router.getAmountsOut/swap` | 官方 V2 源码，可信 |
| 代币 | `LOVE20Token.mint/burn`、`SafeERC20` | 本仓自建，无回调 |
| 回调 1 | `Submit:326-338` → `IProposalTarget` | **第三方合约** |
| 回调 2 | `Vote:281-286` → `onProposalVoted` | 同上 |
| 回调 3 | `Launch:149-151` → `ILaunchDistributor` | **任意第三方** |
| 时间 | `Phase.sync()` 开放；`Submit:319-322` 每轮首推者触发 | 任何人 |

### 表 D 高风险路径清单 → 直接进第三层（§3 的 P-01..P-08）

### 表 E 参数域台账（链上 require / 广播前 / 广播后）

| 参数 | 链上 require | 广播前 `DeployCore` | 广播后 `21_check` | 缺失后果（设计层） |
| --- | --- | --- | --- | --- |
| `FEE_SETTLEMENT_RATIO` | 无（`Stake:83-94` 只防重复） | `:176` ≤2.5e15 | `:487` ≤2.5e15 | > 池费率 → 单笔结算成为可夹的价格冲击（D-03） |
| 两池比例和 | 无（`Mint:94-97`） | `:160-162` ≤1e18 | `:519` ≤1e18 | 和 >1e18 → `rewardAvailable:455` 下溢 → 全部铸造永久 revert |
| `SUBMIT_MIN_RATIO` | 无（`Submit:49-63`） | `:169` 非零 | `:485` ≤1e18 + 非零 | `=0` → `_meetsSubmitPower:85` 恒 false → 治理砖化 |
| `MAX_BOOST_MULTIPLIER` | 无 | `:163-166` ≤1000 | `:484` ≤1000 | 上界失真 → `:405` 的封顶失效 |
| `PROMISED_WAITING_PHASES_MIN/MAX` | 无 | `:171-175` | `:525` min≤max | `MIN=0` → 零票权仓位 + `_mergeIntoTarget:532` 的"空目标"判据失效 |
| `TOKEN_SYMBOL_LENGTH+4` | 无 | `:150-152` | `:250-265` 链上读值现算 | 超 32 → `_createToken:248` 必 revert → 该社区永远无法发射子币 |
| MemberNFT 四参数 | 无 | `:130-133` | 有 | `BYTES_THRESHOLD` 过大 → `calculateMintCost:121` 溢出 |
| Phase 五参数 | 无（`:33-46` 只存） | `:135-144` | 有 | `phaseBlocks=0` → `phaseAtBlock:70` 除零 |
| Router/Factory/WETH | 无（`Stake:77-78` 只存） | `:187-193` | 有 | 不一致 → `_pairFor:516` 取错 Pair |

**判级口径**：四层防线（链上无 → 广播前拒 → 广播后复核 → 字面量一致性测试）已闭合，所以这些**不是**漏洞。只有"某组合能让一个**已正确部署**的实例失效"才升 Medium；否则 Info，归入部署清单。真正值得单独看的是 D-10：这些参数为什么不能在链上自证。

### 表 F 部署序列（本计划独立定级）

7 个 `init` 全部无调用者限制，`DeployCore.s.sol` 逐个 `new X()` → 逐个 `init`（`:209-273`），`11_deploy.sh` 用 `--slow` → 这是一条**逐笔确认的公开交易序列**。抢跑任一 `init` 即永久 `AlreadyInitialized`，无 setter；`_validateDeployment` 在 `vm.stopBroadcast()` 之后才跑（`DeployCore:90` vs `:92`），发现时合约已在链上、删不掉。

- 参数侧：`Stake.init:83-94` 对 `FEE_SETTLEMENT_RATIO`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS` 一个 require 都没有；`Mint.init:82-97` 对 4 个地址 + 4 个比例零校验；`Launch.init:55-66` 让 5 个经济常量原样落库。所以抢跑产物不是"明显错误的副本"，而是**语法合法、语义任意**的配置。
- 顺序事实：`Launch.init:231` 内部调 `MemberNFT.init:75`，抢跑后者会让前者整笔回滚（含首币部署）。
- **本计划按设计判据独立定级**：确定性损失是"任何人可随时打断部署 + 8 个不可删除的孤儿合约 + 接线与经济常量由首个调用者决定"；资金损失是条件性的（要部署方无视脚本非零退出继续公布）。不引用任何既有裁决。

## 2. 第二层：逐文件（B2–B4）

### 2.1 单元切分（29 单元 = 28 个源码单元 ≤165 行 + 1 个接口面）

| # | 范围 | 行数 | 风险 | 轮数 | 上下文包 | 该单元的设计命题 |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | `Stake:1-104` | 104 | 极高 | 4 | LEDGER/TIME/DEPLOY | 初始化不可逆 + 依赖可替换性 |
| S2 | `Stake:106-181` | 76 | 高 | 4 | LEDGER/AMM | 入池定价与滑点保护 |
| S3 | `Stake:183-311` | 129 | 极高 | 4 | LEDGER/FEED/AMM | 解锁期与资产交付原子性 |
| S4 | `Stake:313-441` | 129 | 中 | 2 | LEDGER/TIME | 读面与写面同口径 |
| S5 | `Stake:443-522` | 80 | 高 | 4 | LEDGER/TIME | 代币准入与 Pair 绑定 |
| S6 | `Stake:524-653` | 130 | 极高 | 4 | AMM/LEDGER | 份额稀释与手续费归属 |
| S7 | `Stake:655-773` | 119 | 极高 | 4 | AMM | 重分类不改本金 |
| S8 | `Stake:775-877` | 103 | 极高 | 4 | AMM/TIME/DEPLOY | 销毁量与价格冲击上限 |
| M1 | `Mint:1-98` | 98 | 高 | 4 | FEED/DEPLOY | 参数域 = 可用域 |
| M2 | `Mint:100-184` | 85 | 高 | 4 | FEED | 每轮只预留一次 |
| M3 | `Mint:186-262` + `:500-557` | 135 | 高 | 4 | FEED | 零额 / 重复 / 原子性 |
| M4 | `Mint:264-354` | 91 | 高 | 4 | FEED | 分配之和 ≤ 池 |
| M5 | `Mint:356-450` | 95 | 中高 | 3 | FEED/DEPLOY | 50/50 拆分与倍数封顶 |
| M6 | `Mint:452-498` | 47 | 高 | 3 | FEED | 未铸额度不重复分配 |
| L1 | `Launch:1-89` | 89 | 高 | 4 | DEPLOY/IDENT | 首币与依赖绑定 |
| L2 | `Launch:91-152` | 62 | 高 | 4 | IDENT | 发射次数先扣后建 |
| L3 | `Launch:154-236` | 83 | 高 | 4 | IDENT | 剩余 + 已消耗 = 已产生 |
| L4 | `Launch:238-350` | 113 | 中高 | 4 | DEPLOY | 符号唯一 + Pair 幂等 |
| N1 | `MemberNFT:1-101` | 101 | 高 | 4 | IDENT | 身份唯一性与手续费销毁 |
| N2 | `MemberNFT:103-213` | 111 | 中高 | 3 | — | 持有人集合与余额一致 |
| N3 | `MemberNFT:215-379` | 165 | 中 | 3 | — | 归一化后唯一 + 码点白名单 |
| B1 | `Submit:13-103` | 91 | 高 | 4 | LEDGER/FEED | 推举权 = 全局票权占比 |
| B2 | `Submit:105-213` | 109 | 中高 | 3 | FEED | 每轮每人一次 |
| B3 | `Submit:215-339` | 125 | 高 | 4 | — | 回调前状态已落盘 |
| V1 | `Vote:12-100` | 89 | 高 | 4 | LEDGER | 票上限实时 + 快照 |
| V2 | `Vote:102-210` | 109 | 中 | 2 | LEDGER/FEED | 快照只读 |
| V3 | `Vote:212-293` | 82 | 高 | 4 | LEDGER/FEED | 名册 / 累计 / 上限三者一致 |
| P1 | `Phase:1-162` | 162 | 高 | 4 | TIME | 轮长只影响未来 |
| T1 | `LOVE20Token:1-59` + `interfaces/**` | 1069 | 中 | 2 | DEPLOY | 供应上限与 minter 唯一 |

共 **105 轮**（S30 + M22 + L16 + N10 + B11 + V10 + P 4 + T 2）。T1 用 ABI 逐条 diff，不做四轮。

**切分依据**（不是对半切）：
- `Stake` 切点落在"账本写点结束"：`524`（记账）/`655`（纯数学）/`775`（结算链）。`_creditLiquidity:578` 与 `_reclassify:671` 分属 S6/S7 —— "先重分类再算份额"的顺序约束（`:638` 调 `_reclassify` 后 `:589` 才算份额）必须由 S6 末尾与 S7 开头各写一段交界断言。
- `Mint` 的 M3 是双区间：入口 `186-262` 与其唯一实现 `500-557` 必须同会话，否则"入口校验顺序 vs 私有实现顺序"各审一半。
- `Launch` 的 L4 含 UTF-8 循环（`275-307`）：`i+=3` 越界判断与首字节区间必须一次看完。
- 读面（S4/V2）只给 2 轮：访问控制 + 与写面同口径；读面不写状态，数学轮并入。

### 2.2 上下文包（只带声明的那几个，禁整仓塞）

| 包 | 内容 | 行数 |
| --- | --- | --- |
| LEDGER | `IStake.sol:3-19`、`RoundHistoryUint256.sol`、`OrderedHistoryIndex.sol` | ~103 |
| AMM | 三个 Uniswap 接口 + `test/Stake.t.sol:77-219`（**标注为简化 Mock**）+ `dex` 的 `UniswapV2Pair.mint/burn` 原文 | ~190 |
| TIME | `IPhase.sol` + `Phase.sol:48-71` | ~60 |
| IDENT | `IMemberNFT.sol` + `MemberNFT.sol:198-213` | ~90 |
| FEED | `IVote.sol:121-150`、`ISubmit.sol:199-213` | ~35 |
| DEPLOY | `DeployCore.s.sol:127-194`、`21_check.sh:240-270,450-530` | ~200 |

### 2.3 四轮模板（每轮只做一件事，禁跨轮）

固定登记表 schema（所有轮共用）：

```text
| F-ID | 单元 | 文件:行 | 函数/变量 | 类别 | 严重度 | 攻击者画像 | 前置条件 | 触发序列(≤6步) | 影响 | 设计依据 | 证据等级 | 证据路径 | 置信度 | 状态 |
```

`F-ID` = `<单元>-<序号>`；状态 ∈ `待确认/已确认待修/已驳回/已修复待复审/已关闭`。

**R1 访问控制与身份**（追加 3 列：谁能调 / 应谁能调 / 越权可达资产）
禁：把 `init` 无调用者限制当漏洞（设计已接受，见 §1 表 F）；重复 §0.4 的 7 条；无行号条目；"建议加强权限"。
必做：每个 external/public 函数都给结论；无权限的函数写"靠什么安全"。

**R2 外部调用与状态顺序**（追加 4 列：调用目标:selector / 调用前已写(行号) / 调用后才写(行号) / 回调可达写入口）
禁：不证可达就"加 nonReentrant"（本仓以"先写状态、再回调"替代锁，典型 `Vote:256-268` 写完后才在 `:281-286` 回调、`Submit:301-307` 写完后才在 `:326` 回调）；把 view 调用当风险；忽略"被调方为 EOA"分支。

**R3 数学、边界与精度**（追加 5 列：代码式(行号) / 设计承诺的算法 / 舍入方向 / 极值输入 / 结论）
禁："可能有溢出"而不给输入量级；把 checked arithmetic 当已安全（下溢 revert 本身就是 DoS）；混用 1e18 比例与整数分母不标精度。
必做：每式给输入定义域（变量真实上界 + 来源行号）+ 尾差归属（谁拿走、是否可累积）。

**R4 设计自洽与经济激励**（追加 6 列：设计承诺 / 实际机制 / 偏离点 / 可被利用的激励 / 损失承担者 / 判定）
判定只有三档：`兑现` / `可接受（附约束条件）` / `缺陷`。**不许出现"设计如此"** —— 写"可接受"必须给出约束条件、失效边界、谁承担损失三者。
禁：拿文档当理由；把"符合文档"当"正确"；对经济问题只给"建议加监控"。

### 2.4 高价值单元预置假设（每条必须给成立/不成立）

**S1** `init:83-94` 九参零校验（`FEE` 无上界、地址无 `code.length`）；`_pairFor:513-521` 首次缓存不校验 Pair 的 `token0/token1` 与服务对象一致；`_hasUsedStakeRights:501` 二跳信任 `IVote.SUBMIT_ADDRESS()`。

**S2** `_optimalAmounts:701-703` 储备单侧为 0 时**完全跳过 slippage**；`stakeBoost:155` 用 1 wei boost 把**全部存量份额**的乘数从 MIN 期拉到 MAX 期 → 量化"低成本治理夺权"的成本。

**S3** `withdraw:239-249` 顺序为"出金 → 付 boost → `delete`"，`delete` 在外部调用之后；`canWithdraw:416` 不比 `liquidityShares`，`withdraw:229` 比 → 两者对"解锁后份额为零"的成员可能给出相反结论。

**S6** `_creditLiquidity:589-591` 零基准按 `lpMinted` 计份额，与 `_withdrawLiquidity:744` 的 `shares/totalShares` 分配不自洽：`withdrawableLp` 被打到 0 后老份额白吃新存入 → 给算术序列与最大白吃比例。

**S7** `_canBurn:809` 的 `lp*reserve >= supply` 与真 V2 的 `require(amount0>0&&amount1>0)` 是否严格等价（floor>0 ⇔ 乘积≥）→ 反例搜索；`_reclassify:684-690` 把任何第三方 donation 判成手续费。

**S8** `settlementUnit` 由 `withdrawableLp` 定义（`:786`）而门槛拿 `feeLp` 比（`:787`）；`amountOutMin` 同笔现算（`:862-863`）对跨块夹子零保护，安全性完全依赖 `FEE_SETTLEMENT_RATIO ≤ 池费率`；证明 `:831` 的 `burn` 吃不到 Boost 负债。

**M1** `init:94-97` 无比例和上界 → 和 `=1e18+1` 时 `rewardAvailable:455` 下溢 → 所有铸造入口永久 revert；`_updateLaunchCredit:471-473` 提前 return 时不入账不发事件 → 该笔额度在事件流里消失。

**M2** 三次独立外部读（`:116`、`:270-286`）在轮次已结束后是否必然一致（Vote 只写当前轮）；`_burnCancelledPool:163-173` 只加 `_rewardBurned` 不减 `_rewardReserved` → 被取消额度经 `:455` 回流 `rewardAvailable`，下一轮可再预留。

**M4** 最高优先项：`_calculateEligibleProposalVoteAmount:270-298` 的求和必须**恰等于**本轮所有达标票之和，否则 `:340` 的各提案分配之和 > 池 → 越预留铸造 → `reservedAvailable` 下溢。依赖 `Vote:248-267` 双 flag 的真值表（`isFirstVoteByMember` 实为"对该提案首票"）。

**V3** 加速快照"首投全量、后续只补增量、从不下降"（`:232-245`）依赖 Stake 轮内 `validBoostShares` 单调不减（`Stake:191` 禁已投票者解锁、`Stake:286` 禁已使用者融合）→ 给证明与破坏条件。

**P1** `sync:116-121` 只钳下界（`observed==0?1`）**不钳上界**，观测点由本轮首个调用者选定（`:90-104`），`Submit:319-322` 让首推者也能触发 → 量化"拉长下一轮"所需条件。

**L4** `_createToken:256-260` 复用预建 Pair（H-01 修复）零覆盖 —— 可测，但无测试。

**N2** `calculateMintCost:110` 的 `unmintedSupply/BASE_DIVISOR` 可 floor 到 0 → 供应接近上限时零成本铸身份；`:121` `MULTIPLIER**difference` 在阈值过大时溢出 → mint 永久失败。

**N3** `_isValidNameChars:230-363` 与 `_toLowerCase:365-378` 的组合：全码点扫描（0x00–0x10FFFF）断言"接受集合 = 设计白名单"，重点 `U+0080–U+009F` 是否只在 2 字节分支（`:282-289`）被拦。

### 2.5 设计层命题（D-01..D-10，每个子系统问一次，不依赖文档）

| # | 命题 | 机制（行号） | 若成立意味着 |
| --- | --- | --- | --- |
| D-01 | 票权杠杆无上限 | `govVotes = liquidityShares × promisedWaitingPhases`（`Stake:875`）；`stakeBoost:154-159` 只需 1 wei 就把乘数从 MIN 拉到 MAX | 若 MIN=1、MAX=1000，1 wei 换 1000× 票权 → 治理可被低成本收购。是否有意？上限在哪？ |
| D-02 | 手续费归属 = 任何 LP 增值 | `_reclassify:684-690` 用 `sqrt(k)` 增量判手续费，而 `_reserves:655-669` 只读 `getReserves()`，不读余额 | 捐赠、他人交易费、价格操纵造成的 k 变化全被判成协议收入；改标量不进任何人口袋而是被烧掉。重分类无单次上限、逐轮可重复 |
| D-03 | 结算吞吐有硬上限 | 每社区每 Phase 一次 + 单笔 0.25%（`:786-793`），单价按 `withdrawableLp` 计价 | 若 `feeLp` 增速 > 0.25%/Phase，积压单调增长；`lastWithdrawableLp` 被压到 0 后 `settlementUnit == 0`，`_canBurn` 恒假 → 出口取决于他人新质押 |
| D-04 | 协议存在直接 LP 出口 | `_canBurn` 失败时 LP 直接给提取者（`:750-757`） | 同一份额对不同人价值不同；拿到 LP 可立即自行 burn，等价于"拿不到双币但能提前退出"。是兜底还是绕过等待期？ |
| D-05 | 发射次数双账本 | `addLaunchCount:201-203` 同时给 FIRST 与 ROOT 记账，但 `MAX_LAUNCH_COUNT` 只校验 FIRST（`:194-197`） | ROOT 的剩余次数可无限增长？根级与社区级是否应共享上限？两个账本哪个是权威？ |
| D-06 | "销毁"名不副实 | `_burnCancelledPool:163-173` 只加 `_rewardBurned`，代币从未存在；`_settleFees:782-784` 改写总量却不发事件 | 事件 `RewardBurned` 会被索引器读成"销毁了代币"；改标时序在事件流里完全不可重建 |
| D-07 | 身份定价反向 | `calculateMintCost:110-121`：成本 ∝ 未铸供应，越接近上限越便宜 | 早期参与者最贵、晚期免费。是"抑制早期囤积"还是"必然通胀到免费"？ |
| D-08 | 时间轴可被放大 | `sync:116-121` 只保 `newPhaseBlocks ≥ 1`，观测窗由首个调用者选（`:90-104`） | 轮长被放大 100× 后，Stake 等待期、Mint 的"轮已结束"、Vote 的轮次推进同时变形。首推者与出块者的影响力边界在哪？ |
| D-09 | 回调身份靠目标自证 | core 不传 `msg.sender` 给 `onProposal*`/`onTokenLaunched`；`Mint:179-183` 反向用 `Submit.proposalTarget` 校验调用者 | 恶意 target 可让别人的提交/投票整笔失败；高 gas 目标可让票权记录不可用；回调内是否可达"半写"状态 |
| D-10 | 参数域完全在链外 | 7 个 `init` 只防重复（`Stake:83-94`、`Mint:82-98`、`Submit:55-58`、`Vote:52-55`、`Launch:55-57`、`MemberNFT:55-57`） | 一旦部署脚本被绕过，哪些参数让协议**永久**不可用且无自愈？是否值得一条链上 `require`？ |

10 条全部按同一判据独立判定，不设"已被认定"或"勿再上报"的豁免。

每条判定三档：`兑现` / `可接受（约束条件 + 失效边界 + 损失承担者）` / `缺陷`。

## 3. 第三层：跨文件（B5–B6，一次只走一条）

每条只带 2–5 个文件，固定三问：**状态修改顺序有无可利用窗口 / 攻击者能在哪个时点插入什么 / 结论落在哪个不变量**。

| # | 路径 | 要问的核心 | 结论形态 |
| --- | --- | --- | --- |
| P-01 | `Launch._createToken:250-260` → `Stake.stakeLiquidity:106` → `_addLiquidity:626` → 真 V2 `mint` → `_creditLiquidity:578` → `_reclassify:671` | 首存通胀：极小金额入场 → 直接 `transfer` 给 Pair 抬储备 → 受害者按 `_optimalAmounts` 存入，三种量各变多少？捐赠被判成 `feeLp` 后攻击者净收益？受害者能否被 `ZeroLiquidityMinted:652` 永久挡住 | 获利不等式 / DoS 门槛 / 自我抵消条件 |
| P-02 | `_settleFees:775` → `_realizeFees:812` → `_swap:853` → Router | `amountOutMin` 同笔现算；前块推价 → 结算按被推高价成交。单次冲击 = `processedFeeLp/pairTotalSupply` 是否恒 ≤ `FEE_SETTLEMENT_RATIO/1e18`？0.3% 池费、往返 0.6%，`2.5e15` 真不可套利？误配 `1e18` 的损失上界 | 一条盈亏不等式 + 两档参数数值表 |
| P-03 | `Submit.submitNewProposal:105` → `_submitByProposalId:277` → `_callProposalCreated:326` → `Stake.mergeStake:269` → `_hasUsedStakeRights:495` → `Vote.vote:69` | 同轮"推举 + 投票 + 融合给未推举目标再推举"能否成立？`onProposalCreated` 期间推举状态已写（`:301-307` 早于 `:326`），融合是否必然 revert？"目标已投票仍可接收"是否成为票权放大器（`Vote:77` 每入口只读一次上限） | 交易序列逐步标 revert 点 + 错误选择器 |
| P-04 | `unstake:183` → `withdraw:223` → `_withdrawLiquidity:737` → `_settleFees:775` → `_push:508` | "已解锁未提取"窗口里 `boostShares` 仍在合约、`totalBoostShares` 未减（`:202-205` vs `:244-247`）而 `validBoostShares=0` → 谁能动这笔钱？`:821/:831` 的 burn 会不会吃到该负债？"提取→再质押→再解锁"能否复用同一份资产 | 不变式：`balanceOf(stake,token) ≥ Σ有效 boostShares + 在途提取` |
| P-05 | `Phase.sync:86` → `Submit:319` → `Vote:76` → `Mint._isRoundEnded:100` → `Stake:790/231` | `sync` 只改未来 `phaseBlocks`，同 tx 内 round 不跳变；但轮长可被放大 → 等待期从"天"变"年"、`Mint` 的"已结束"被无限推迟。首推者成本 / 放大倍率 / 受影响入口 | 时间轴表（block / phase / phaseBlocks / 各模块读到的 round） |
| P-06 | `_prepareRewardIfNeeded:126` → `_mintGovReward:500` → `_updateLaunchCredit:463` → `Launch.addLaunchCount:187` → `_addLaunchCount:334` → `LOVE20Token.mint:42` | 四个量（reserved/minted/burned、launchCredit、issued、remaining）在"mint 被 `MAX_SUPPLY` 截断""`issued>=max` 提前 return""根级伴生 1:1（`:201-203`）"下是否守恒？`threshold` 用 mint 前供应而 `launchCredit` 跨轮累加 → 额度被吞？ | 四账本守恒式 + 事件折叠 == view 的对账表 |
| P-07 | `Submit:326-338` → `Vote:281-287` → `Launch:149-151` | 回调可见中间态；回调内可重入哪些写入口；回调内 `stakeBoost` 能否抬高嵌套 `vote` 的上限；gas 炸弹面 | 3×N 矩阵：回调 × 可达写入口 × 中间态 |
| P-08 | 7 个 `init` → `rewardAvailable:452` → `_meetsSubmitPower:84` → `DeployCore:127-194`／`21_check:450-530` | 哪些参数组合让入口**永久**不可用且链上无自愈：比例和 >1e18、`SUBMIT_MIN_RATIO=0`、`FEE=1e18`、`MIN_WAITING=0`、阈值过大、符号长度+4>32。每种回答：链上 / 广播前 / 广播后哪层拦、绕过后果 | 参数 × 失效入口 × 拦截点三列表；"三层皆无"的行才是登记项 |

## 4. 第四层：工具交叉与修复复审（B7）

### 4.1 工具矩阵

| 工具 | 用途 | 判据 |
| --- | --- | --- |
| Slither | 新增告警对照基线，不当结论 | 双向对账：AI 报工具没报 → 重点查误报；工具报 AI 没提 → 让 AI 解释为何安全 |
| `forge test` | 回归 + PoC 载体 | 基线不退 |
| `forge inspect ... storageLayout` | 无代理，仍核对声明顺序与 0 哨兵位置 | 全部协议合约 |
| `forge build --sizes` | 记体积基线（当前 `Stake` 14.6 KB / `Launch` 12.2 KB / `Mint` 10.0 KB，距 24 KB 上限尚有余量） | 改动前后对比 |
| `forge test --gas-report` | 1000 提案准备、批量 mint 的 gas 上界 | 对照 BSC 区块 gas |
| `check-events.py` | 事件族/字段/顺序 | 零输出 |
| ABI diff | `out/*.json` vs `src/interfaces` | 按 `(type,name,inputs,outputs,stateMutability)` 排序 diff |

### 4.2 必建真 V2 集成夹具（PoC 的地基）

新增 `test/integration/StakeRealDex.t.sol`：真 `UniswapV2Factory/Pair/Router`（复用 `dex/` 源码，`feeTo=0`）+ 真 Launch/Stake/MemberNFT/Phase。6 场景：首存、捐赠重分类、单次结算、双币取整、零 LP、预建 Pair。必须含 `sync`/`skim`/`MINIMUM_LIQUIDITY=1000`/0.3% 费率——少任何一个，重分类与 `_canBurn` 的结论都不成立。

理由（本计划最重要的工程判断）：`test/Stake.t.sol:98-205` 的 `MockPair` **没有 `MINIMUM_LIQUIDITY=1000`、没有 0.3% 费率**（`MockRouter:78-94` 1:1）、`burn` 用 `_balances[this]`、`getReserves` 用 `uint112(...)` 静默截断。凡"资金/份额/结算"结论只在 Mock 上验证，最高 E2，不能进 Critical/High。

### 4.3 修复复审协议（修复阶段适用，本次不含实施）

1. 不给 diff，给**修复后的完整函数** + 原问题描述 + 触发序列。
2. 三问必答：是否完全消除原问题 / 是否引入新的状态不一致 / 是否改变边界（尤其 0 与 1 wei）。
3. 每个修复配一条**能被证伪的测试**：先让它在修复前失败（记 revert 选择器），再在修复后通过。写不出来 → 审查结论本身可疑。
4. 复审前重跑 §0.4 的回归断言 + Slither high。

## 5. 人工确认点（不可省）

| 门 | 要求 |
| --- | --- |
| Critical / High | 人工沿调用栈走一遍：前置检查是否真可满足、攻击者资金从哪来、利润能否提出。AI 的"看起来合理"在这里淘汰 |
| 任何 E2 结论 | 要么补成 E3，要么降级 |
| 任何"设计取舍" | 必须给约束条件 + 失效边界 + 损失承担者，三者缺一即判为缺陷 |
| 任何跨仓结论（action 侧回调行为） | 只作为"core 的假设"，标注由谁验证 |

## 6. 产物（`matt-gov/review/core-review-2026-11/`）

```text
core-review-plan-2026-11.md   本计划（已落盘，就在本文件）
00-baseline.md                9297a33 + 门禁输出 + slither 原始告警
01-architecture-map.md        表 A–F
02-registry.md                29 单元 × 4 状态跟踪（唯一进度真相）
03-findings.md                合并后的登记表（唯一结论出口）
04-design-notes.md            D-01..D-10 逐条判定（设计层结论）
05-paths/P-01..P-08.md        每条路径一页
06-tool-crosscheck.md         工具对账 + gas 表 + ABI/storage diff
07-fix-review.md              修复复审（本次留空）
08-final-report.md            汇总：严重度分布、已接受风险、部署清单、回归缺口
evidence/                     测试日志、gas 报告、PoC 命令
```

`src/` 侧一行不改；所有过程产物留在这一个目录，报告只写结论，不写修改史。

## 7. 执行排期

| 批 | 内容 | 并行 | 产出 | 退出判据 |
| --- | --- | --- | --- | --- |
| B0 | 冻结 + 门禁 + 真 V2 夹具 | — | `00-baseline.md`、`StakeRealDex.t.sol` | 快照可复现；6 场景跑通 |
| B1 | 地图 | — | `01-architecture-map.md` | 每行有 `文件:行`；表 E 无空格 |
| B2 | S1→S2 ｜ M1→M2 ｜ B1→B2 ｜ V1 | 4 链 | 9 单元 | 契约/参数/门槛三链闭环 |
| B3 | S3→S5 ｜ M4→M3 ｜ V3 ｜ L1→L2 | 4 链 | 9 单元 | M4 双 flag 真值表出结论 |
| B4 | S6→S7→S8 ｜ M5→M6 ｜ L3→L4 ｜ N1→N2→N3 ｜ P1 ｜ S4 ｜ T1 | 4 链 | 11 单元 | Stake 记账/数学/结算三段交界断言齐 |
| B5 | P-01 ｜ P-02 ｜ P-03+P-07 ｜ P-04+P-05 ｜ P-06 ｜ P-08 | 3 链 | 8 路径 | 每条给"可利用/不可利用/需人裁决" |
| B6 | D-01..D-10 判定 + 工具对账 | — | `04`、`06` | 每条 D 有三档判定与理由 |
| B7 | 人工确认 + 定稿 | — | `08` | Critical/High 全 E3 且人工签字 |

耗时参考：单单元 4 轮 ≈ 40–60 min；29 单元 ≈ 20–26 h；8 路径 ≈ 4–6 h；设计判定 + 工具 ≈ 4 h。4 链并行 → **2 个工作日**；单人串行 → 4–5 天。

## 8. 退出标准

1. 29 单元全部到"已审"或"已关闭"，无"未审"。
2. §2.4 的 14 组预置假设每条都有成立/不成立结论。
3. D-01..D-10 每条都有三档判定，且"可接受"项都带约束条件与损失承担者。
4. 8 条路径每条有明确结论，无"待进一步观察"。
5. 所有 Critical/High 为 E3 且有人工确认记录；E2 结论已降级。
6. §0.4 的回归缺口全部补齐或标注"不可补 + 原因"。
7. 表 E 每行都有"链上/广播前/广播后"三态结论。
8. 门禁全绿（build / lint / test / events / deploy-scripts）。

## 9. 三个最易失效点

| 风险 | 事实 | 对策 |
| --- | --- | --- |
| **Mock 保真度** | Stake 侧全部资产测试跑在无 `MINIMUM_LIQUIDITY`、无费率的 `MockPair` 上；H-01 分支零覆盖 | §4.2 真 V2 夹具；Critical/High 必须来自它 |
| **"设计如此"成为挡箭牌** | 不再拿文档当判据后，任何反常机制都能被解释成有意为之 | R4 强制三件套：约束条件 / 失效边界 / 损失承担者。缺一即缺陷；三者齐也只能到"可接受"，不能到"兑现" |
| **回归幻觉** | 旧 findings 的 PoC 在 `compatibility/`，不在 core；core 里只有形式化断言 | B0 后先补 §0.4 的断言（只加 `test/`，不改 `src/`）；`src/` 有任何 diff 时这些断言与 Slither high 同列门禁 |

## 附 A：本次复核结论（2026-11-02，基线 `9297a33`）

| 项 | 结论 |
| --- | --- |
| 工作树 | 干净（`git status --short` 空） |
| `src/` 改动面 | 仅 `Launch.sol`（`:28` 常量、`:326` 引用）与 `ILaunch.sol`（`:114` getter）；其余 6 合约自 `1dcdaff` 未动 → 本计划全部行号引用有效 |
| F-04 | **已关闭**：`21_check.sh:250-265` 从链上读 `TEST_PREFIX_BYTES()` 与 `MAX_TOKEN_SYMBOL_LENGTH()` 再比较，不再复制字面量 |
| F-09 | **基本关闭**：`21_check.sh:456-525` 复核 `LAUNCH_RATIO≤1e18`、`FEE≤2.5e15`、`BOOST≤1000`、`SUBMIT≤1e18` 且非零、两池和≤1e18；`deploy_scripts_test.py:162-171` 把两处 `2.5e15` 钉在一起。链上仍无 require（见 §1 表 E） |
| 事实纠正 1 | 体积不是 24 KB 量级：`Stake` 14.6 KB / `Launch` 12.2 KB / `Mint` 10.0 KB（读 `out/*.json` 的 `deployedBytecode`） |
| 事实纠正 2 | "先写状态、再回调"的典型是 `Vote:256-268 → :281-286` 与 `Submit:301-307 → :326`；`Stake.withdraw` 相反（`:239-240` 外部调用在前、`delete:249` 在后），这正是 S3 要重点看的地方，不能当正面例子 |
| 仍然开放 | H-01 分支零覆盖；C-01 只断言错误码；`MockPair:98-205` 缺 `MINIMUM_LIQUIDITY` 与费率；M4 越预留路径未验算；D-01..D-10 全部待判 |

## 附 B：落盘状态

本文件已在 `matt-gov/review/core-review-plan-2026-11.md`，不再需要复制。开审时从这里开始，第一步是 B0（冻结 + 门禁 + 真 V2 夹具），产物写进同目录的 `core-review-2026-11/`。

在你说"开始"之前，不跑 `forge`、不改 `src/`、不写任何 `01-` 之后的产物。

## 附：明确不做

1. 不以 `matt-gov/docs/specs/**` 作判据；需要"当初意图"时只作背景，不写进结论。
2. 不重跑 `compatibility/` 的 DEX 兼容性探针。
3. 不审 `script/deploy/*` 实现，只作参数域与绑定证据。
4. 不引用任何既有报告或裁决；部署序列、重分类、结算等区域一律按本计划的判据独立重审。
5. 不审 `action/`、`group-chat/`、`dex/`。
6. 不做修复实施、不提交任何改动。
