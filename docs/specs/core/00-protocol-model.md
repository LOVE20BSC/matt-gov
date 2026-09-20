# 协议模型与初始化参数

## 协议模型

每个 LOVE20 代币有一个 `parentTokenAddress`。首个代币的父币为 WBNB，WBNB 是协议树外根父币；后续父币必须是已登记的 LOVE20 代币。供应受 `maxSupply` 限制，代币和治理状态在链上维护。

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

## 初始化参数

以下为初始化参数总览；各模块文件给出完整构造函数和 `init` ABI。部署配置中的示例值不等于固定值。除 Phase/LOVE20Token 使用构造函数、MemberNFT 费用参数在构造函数固定外，各合约一次性初始化入口使用 `init`；地址绑定与初始化安全见 [通用规则](01-common-rules.md)，首币流程见 [Launch](08-launch.md#初始化和首个代币)。

可直接用于实现的 ABI 唯一来源是 [`interfaces/core/`](../../../interfaces/core/)。

| 所属组件 | 参数 | 含义与单位 |
| --- | --- | --- |
| MemberNFT 构造参数 | `baseDivisor` | 首币未铸造量的费用除数；状态变量和公开 getter 为 `BASE_DIVISOR`，如 `1e8` |
| MemberNFT 构造参数 | `bytesThreshold` | 短名称字节阈值；状态变量和公开 getter 为 `BYTES_THRESHOLD`，如 `7` |
| MemberNFT 构造参数 | `multiplier` | 每缩短一字节的费用倍数；状态变量和公开 getter 为 `MULTIPLIER`，如 `10` |
| MemberNFT 构造参数 | `maxNameLength` | 最大字节数；状态变量和公开 getter 为 `MAX_NAME_LENGTH`，如 `32` |
| Phase 构造参数 | `ORIGIN_BLOCKS`、`ORIGIN_PHASE_BLOCKS`、`TARGET_SECONDS`、`ADJUST_THRESHOLD`、`SYNC_OBSERVATION_LIMIT` | 启动区块、初始区块数、每个 Phase 的目标自然时长（秒，7 天为 `604800`）、偏差阈值、单次同步回溯上限；五项均须大于零，偏差阈值使用 `1e18` 精度 |
| Stake | `phaseAddress`、`memberNFTAddress`、`voteAddress`、`routerAddress`、`pairFactoryAddress` | 时间、身份、融合投票检查、路由和 Pair Factory 依赖；在 Stake 侧 Pair Factory 只用于读取 Launch 已创建的 Pair |
| Stake | `promisedWaitingPhasesMin`、`promisedWaitingPhasesMax` | 承诺解锁期的最小、最大 Phase 数 |
| Stake | `maxWithdrawableToFeeRatio` | 手续费结算阈值，同时是单笔结算量的分母；须不小于目标 DEX 池费率的倒数，见 [Stake](04-stake.md#手续费结算与销毁) |
| Submit | `phaseAddress`、`stakeAddress`、`memberNFTAddress` | 时间、质押和身份依赖 |
| Submit | `submitMinPerThousand` | 推举门槛，千分比，如 `10 = 1%` |
| Vote | `phaseAddress`、`stakeAddress`、`submitAddress`、`memberNFTAddress`、`mintAddress` | 时间、票权、提案、身份和激励门槛依赖 |
| Mint | `voteAddress`、`submitAddress`、`stakeAddress`、`launchAddress`、`memberNFTAddress` | 投票、提案、发射和铸造权限依赖；`stakeAddress` 为旧接口保留成员、当前无消费者（加速数据来源已改为 Vote 快照） |
| Mint | `proposalRewardMinVotePerThousand` | 提案激励门槛；状态变量和公开 getter 为 `PROPOSAL_REWARD_MIN_VOTE_PER_THOUSAND`，千分比，如 `50 = 5%` |
| Mint | `roundRewardGovPerThousand`、`roundRewardProposalPerThousand` | 治理池、提案池占可用供应的千分比；状态变量和公开 getter 为 `ROUND_REWARD_GOV_PER_THOUSAND`、`ROUND_REWARD_PROPOSAL_PER_THOUSAND`，如 `30`、`10` |
| Mint | `maxGovBoostRewardMultiplier` | 加速激励相对投票激励的倍数上限；状态变量和公开 getter 为 `MAX_GOV_BOOST_REWARD_MULTIPLIER`，如 `2` |
| Launch | `mintAddress`、`memberNFTAddress`、`pairFactoryAddress` | 铸造、身份与建池依赖；每个代币在创建时即建 Pair |
| Launch | `rootParentTokenAddress` | 根父币 WBNB |
| Launch | `distributor`、`name`、`symbol` | 首币分发目标、名称和符号；首币固定使用 `NoCallback`，`distributor` 非零 |
| Launch | `launchRatio` | 发射阈值比例；状态变量和公开 getter 为 `LAUNCH_RATIO`，`1e18` 精度，如 `1e16 = 1%` |
| Launch | `maxLaunchCount` | 每社区累计次数上限；状态变量和公开 getter 为 `MAX_LAUNCH_COUNT`，如 `100` |
| Launch | `tokenSymbolLength` | 子币符号固定字节长度；状态变量和公开 getter 为 `TOKEN_SYMBOL_LENGTH`，沿用旧 Launch 校验 |
| Launch | `launchAmount`、`maxSupply` | 首批/最大供应量，`Launch.init` 固定；状态变量和公开 getter 为 `LAUNCH_AMOUNT`、`MAX_SUPPLY`；`0 < launchAmount <= maxSupply` |

上表的 Launch 行按含义分组，不表示传参顺序；`Launch.init` 只接受一个 `LaunchInitParams`，实参顺序即结构体字段顺序（依赖地址 → 分发目标 → 经济与符号参数 → 供应量 → 首币元数据），参数表中的名字与字段名一致。结构体定义见 [`ILaunch.sol`](../../../interfaces/core/ILaunch.sol)。

MemberNFT 的首币地址由 `Launch.init` 在创建首币时同步调用 `MemberNFT.init(tokenAddress)` 绑定，不在部署时传入；公开 getter 保持旧名 `LOVE20_TOKEN_ADDRESS()`。MemberNFT 不保存 Launch 地址。Launch 的首币分发地址、名称、符号和供应量配置统一见 [Launch](08-launch.md)。Pair Factory 由 Launch 与 Stake 共用：Launch 在创建代币时建池，Stake 只在首次质押时读取该 Pair；Router 只属 Stake，用于父币手续费换币。

## 实现约束

- Phase 使用构造参数创建；Core 其他合约先部署，再按依赖顺序调用一次 `init`，依赖后部署的地址通过后续 `init` 绑定。
- 各合约的 `init` 不设调用者限制、不保存部署者地址；只有 `init` 校验初始化状态，其他写入口不重复校验；部署成功与否由发布前检查脚本核对实际绑定结果判定，见 [通用规则](01-common-rules.md#初始化与安全)。
- Mint 在准备时读取 Vote 的冻结结果，按 `proposalRewardMinVotePerThousand` 一次性计算并缓存本轮达标 Proposal 总票数；后续 Proposal 激励结算只读取该缓存。
- 参数有效范围和组合限制以各模块规格为准；表中示例值不是默认部署配置。
- **以 Round 为键的历史查询按载荷分两种口径**，分界是「取该轮的时点值」还是「取该轮的记录集合」，不按模块划分：
  - 取时点值（单值历史，如 Stake 的 `cumulatedBoostShares`）：传入尚未开始的未来 Round 回滚 `InvalidPhase(round)`，与旧代码的 `RoundHasNotStartedYet` 同义，不得把最近一条记录当作未来轮的值返回。
  - 取该轮记录集合（如 Submit 的 `submitInfos`）：未来 Round 与无记录的已开始 Round 一致，返回空集合与 `0`，不回滚。
  - 两种口径都只针对历史查询；写入口校验未来轮不属于本节，按各模块条件表执行。
