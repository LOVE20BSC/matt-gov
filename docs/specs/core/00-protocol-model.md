# 协议模型与部署参数

## 协议模型

每个 LOVE20 代币有一个 `parentTokenAddress`。首个代币的父币为 WETH，WETH 是协议树外根父币（由 Router.WETH() 读取）；普通发射的父币必须是已登记的 LOVE20 代币。发射次数记入被发射社区自己的代币维度。供应受 `MAX_SUPPLY` 限制，代币和治理状态在链上维护。

| 组件 | 职责 |
| --- | --- |
| MemberNFT | 统一业务身份 |
| Stake | 流动性质押、加速质押、份额和手续费 |
| Submit / Vote | Proposal 创建、推举、投票和 Target 回调 |
| Mint | 轮次激励准备、治理激励及 Proposal 激励结算 |
| Phase | 无业务语义的时间片 |
| LOVE20Token | 代币实例与代币树 |
| Launch | 首币部署、LOVE20Token 创建、发射额度、次数融合及子币发射 |

Core 不解释具体 Proposal 的业务字段，扩展通过 Target 接入。

## 部署参数

以下为部署参数总览；各模块文件给出完整构造函数 ABI。部署配置中的示例值不等于固定值。所有合约都通过构造函数一次性注入依赖和参数，不再保留 `init`；地址绑定与部署安全见 [通用规则](01-common-rules.md#部署与安全)，首币流程见 [Launch](08-launch.md#部署与首个代币)。

可直接用于实现的 ABI 唯一来源是 core 仓库的 [`src/interfaces/`](https://github.com/LOVE20BSC/core/tree/main/src/interfaces)。

| 所属组件 | 参数 | 含义与单位 |
| --- | --- | --- |
| MemberNFT 构造参数 | `baseDivisor` | 首币未铸造量的费用除数；状态变量和公开 getter 为 `BASE_DIVISOR`，如 `1e8` |
| MemberNFT 构造参数 | `bytesThreshold` | 短名称字节阈值；状态变量和公开 getter 为 `BYTES_THRESHOLD`，如 `7` |
| MemberNFT 构造参数 | `multiplier` | 每缩短一字节的费用倍数；状态变量和公开 getter 为 `MULTIPLIER`，如 `10` |
| MemberNFT 构造参数 | `maxNameLength` | 最大字节数；状态变量和公开 getter 为 `MAX_NAME_LENGTH`，如 `32` |
| Phase 构造参数 | `ORIGIN_BLOCKS`、`ORIGIN_PHASE_BLOCKS`、`TARGET_SECONDS`、`ADJUST_THRESHOLD`、`SYNC_OBSERVATION_LIMIT` | 启动区块、初始区块数、每个 Phase 的目标自然时长（秒，7 天为 `604800`）、偏差阈值、单次同步回溯上限；五项均须大于零，偏差阈值使用 `1e18` 精度且不超过 `1e18` |
| Stake | `PHASE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`VOTE_ADDRESS`、`LAUNCH_ADDRESS`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS` | 时间、身份、当前轮投票/推举检查、Launch 代币登记、路由和 Pair Factory 依赖；Stake 通过 Vote 已绑定的 Submit 读取推举记录；在 Stake 侧 Pair Factory 只用于读取 Launch 已创建或复用的 Pair |
| Stake | `promisedWaitingPhasesMin`、`promisedWaitingPhasesMax` | 承诺解锁期的最小、最大 Phase 数 |
| Stake | `feeSettlementRatio` | 单笔手续费结算占 Pair 的 LP 总供应的比例，`1e18` 表示 100%（如 `25e14` 为 0.25%）；同时是结算阈值与单笔处理量；须不大于部署期上界（0.25%），见 [Stake](04-stake.md#手续费结算与销毁) |
| Submit | `PHASE_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS` | 时间、质押和身份依赖 |
| Submit | `submitMinRatio` | 推举门槛，`1e18` 表示 100%，如 `1e16 = 1%` |
| Vote | `PHASE_ADDRESS`、`STAKE_ADDRESS`、`SUBMIT_ADDRESS`、`MEMBER_NFT_ADDRESS` | 时间、票权、提案和身份依赖 |
| Mint | `PHASE_ADDRESS`、`VOTE_ADDRESS`、`SUBMIT_ADDRESS`、`LAUNCH_ADDRESS`、`MEMBER_NFT_ADDRESS` | 时间、投票、提案、发射和身份依赖；BSC 版本已移除原 `STAKE_ADDRESS`（加速数据源改为 Vote 快照）；`PHASE_ADDRESS` 由部署脚本直接传入，不再从 Vote 派生 |
| Mint | `proposalRewardMinVoteRatio` | 提案激励门槛；状态变量和公开 getter 为 `PROPOSAL_REWARD_MIN_VOTE_RATIO`，`1e18` 表示 100%，如 `5e16 = 5%` |
| Mint | `roundRewardGovRatio`、`roundRewardProposalRatio` | 治理池、提案池占可用供应的比例；状态变量和公开 getter 为 `ROUND_REWARD_GOV_RATIO`、`ROUND_REWARD_PROPOSAL_RATIO`，`1e18` 表示 100%，如 `1e17 = 10%` |
| Stake | `boostStakeSupplyFactor` | 单人加速质押上限基数 `C` 的已铸造比例因子 `F`；状态变量和公开 getter 为 `BOOST_STAKE_SUPPLY_FACTOR`，默认 `2`，建议 `1..10`（仅建议，不作校验条件） |
| Stake | `boostStakeMultiplier` | 单人加速质押上限的倍数 `M`；状态变量和公开 getter 为 `BOOST_STAKE_MULTIPLIER`，默认 `5`，建议 `1..20`（仅建议，不作校验条件），不随轮次变化 |
| Launch | `MINT_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PAIR_FACTORY_ADDRESS` | 铸造、身份与建池依赖；每个代币在创建时即创建或复用 Pair |
| Launch | `ROOT_PARENT_TOKEN_ADDRESS` | 根父币（Router.WETH() 读取）；首币的父币与建池报价资产，不再承担计数维度，也不是可发射父币 |
| Launch | `distributor`、`name`、`symbol` | 首币分发目标、名称和符号；首币固定使用 `NoCallback`，`distributor` 非零 |
| Launch | `launchCountThresholdRatio` | 发射次数阈值比例；状态变量和公开 getter 为 `LAUNCH_COUNT_THRESHOLD_RATIO`，`1e18` 精度，如 `1e17 = 10%` |
| Launch | `maxLaunchCount` | 每社区累计次数上限；状态变量和公开 getter 为 `MAX_LAUNCH_COUNT`，如 `100` |
| Launch | `tokenSymbolLength` | 子币符号固定 UTF-8 字节长度，汉字占 3 字节；状态变量和公开 getter 为 `TOKEN_SYMBOL_LENGTH`，长度与字符集校验见 [Launch](08-launch.md#普通发射) |
| Launch | `launchAmount`、`maxSupply` | 首批/最大供应量，构造函数固定；状态变量和公开 getter 为 `LAUNCH_AMOUNT`、`MAX_SUPPLY`；`0 < launchAmount <= maxSupply` |

上表的 Launch 行按含义分组，不表示传参顺序；`Launch` 构造函数只接受一个 `LaunchInitParams`，实参顺序即结构体字段顺序（依赖地址 → 分发目标 → 经济与符号参数 → 供应量 → 首币元数据），参数表中的名字与字段名一致。结构体定义见 [`ILaunch.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ILaunch.sol)。

`MemberNFT` 的首币地址在其构造函数中传入，部署脚本从已部署的 `Launch.FIRST_TOKEN_ADDRESS()` 读取真实地址；公开 getter 保持旧名 `LOVE20_TOKEN_ADDRESS()`。MemberNFT 不保存 Launch 地址。Launch 在构造函数内创建首币并把地址记录为 `FIRST_TOKEN_ADDRESS`（派生状态、非入参，经同名 getter 公开）；首币身份只由该地址判定。Launch 的首币分发地址、名称、符号和供应量配置统一见 [Launch](08-launch.md)。Pair Factory 由 Launch 与 Stake 共用：Launch 在创建代币时创建或复用 Pair，Stake 只在首次质押时读取该 Pair；Router 只属 Stake，用于父币手续费换币。

## 实现约束

- 全部 Core 合约都通过构造函数创建；部署顺序固定为 `Phase → Launch → MemberNFT → Stake → Submit → Vote → Mint`。依赖后部署合约的地址由脚本按部署者 nonce 预测（`MemberNFT`、`Vote`、`Mint` 三处前向引用），并在对应合约部署后立即核对。
- 构造函数不设调用者限制、不保存部署者地址；只保存传入地址和配置，不调用同批部署合约的任何 getter（`Launch` 的第三方 `factory.getPair`/`createPair` 是唯一例外）；不做静态零值校验，相关参数由 `DeployCore`/`21_check.sh` 校验；部署成功与否由发布前检查脚本核对实际绑定结果判定，见 [通用规则](01-common-rules.md#部署与安全)。
- Mint 在准备时读取 Vote 的冻结结果，按 `proposalRewardMinVoteRatio` 一次性计算并缓存本轮达标 Proposal 总票数；后续 Proposal 激励结算以该缓存为分母，不再重算达标集合。单提案票数与门槛仍按该轮账本现读——该轮必须已结束，二者此后不再变化，现读值等于结算时点值。
- 参数有效范围和组合限制以各模块规格为准；表中示例值不是默认部署配置。
- **以 Round 为键的历史查询按载荷分两种口径**，分界是「取该轮的时点值」还是「取该轮的记录集合」，不按模块划分：
  - 取时点值（单值历史，如 Stake 的 `validGovVotes`、`validBoostShares` 及其社区口径 `totalValidGovVotes`、`totalValidBoostShares`）：传入尚未开始的未来 Round 回滚 `RoundNotStarted(requestedRound, currentRound)`，不得把最近一条记录当作未来轮的值返回。
  - 取该轮记录集合（如 Submit 的 `submitInfos`）：未来 Round 与无记录的已开始 Round 一致，返回空集合与 `0`，不回滚。
  - 两种口径都只针对历史查询；写入口校验未来轮不属于本节，按各模块条件表执行。
  - **消费方一律读当前 Round**：协议内部的写路径与结算路径按 `IPhase.currentPhase()` 读这些时点账本——Submit 的推举门槛、Vote 的票上限与加速快照、LpExecutor 与 GroupServiceExecutor 的治理上限、GroupActionManager 的激活门槛、GroupActionVerify 的申请资格，以及 group-chat 四个 Manager 的 `voteWeight` / `totalVoteWeight`，都是「读当前」。参数里的 `round` 服务历史查询、事件对账与索引器重建，不改变结算口径；需要冻结结果的（如 LP 的 `_govRatioAtMint`）在写入时存下当前值，事后查询返回该记录。
