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
| LOVE20Token / TokenFactory | 代币实例与代币树 |
| Launch | 首币部署、发射额度、次数融合及子币发射 |

Core 不解释具体 Proposal 的业务字段，扩展通过 Target 接入。

## 初始化参数

以下为当前已列明的参数，不是完整初始化 ABI。部署配置中的示例值不等于固定值。各合约一次性初始化入口使用 `init`；地址绑定与初始化安全见 [通用规则](01-common-rules.md)，首币流程见 [Launch](07-launch.md#初始化和首个代币)。

| 所属组件 | 参数 | 含义与单位 |
| --- | --- | --- |
| MemberNFT | `baseDivisor` | 首币未铸造量的费用除数，如 `1e8` |
| MemberNFT | `bytesThreshold` | 短名称字节阈值，如 `7` |
| MemberNFT | `multiplier` | 每缩短一字节的费用倍数，如 `10` |
| MemberNFT | `maxMemberNameLength` | 最大字节数，如 `32` |
| Phase 构造参数 | `originBlocks`、`phaseBlocks`、`targetDays`、`adjustThreshold` | 启动区块、初始区块数、目标天数、偏差阈值；前三者大于零，阈值使用 `1e18` 精度 |
| Stake | `promisedWaitingPhasesMin`、`promisedWaitingPhasesMax` | 承诺解锁期的最小、最大 Phase 数 |
| Submit | `phaseAddress`、`stakeAddress` | 时间和质押依赖 |
| Submit | `submitMinPerThousand` | 推举门槛，千分比，如 `10 = 1%` |
| Mint | `voteAddress`、`submitAddress`、`stakeAddress` | 投票、提案和质押依赖 |
| Mint | `proposalRewardMinVotePerThousand` | 提案激励门槛，千分比，如 `50 = 5%` |
| Mint | `roundRewardGovPerThousand`、`roundRewardProposalPerThousand` | 治理池、提案池占可用供应的千分比，如 `30`、`10` |
| Mint | `maxGovBoostRewardMultiplier` | 加速激励相对投票激励的倍数上限，如 `2` |
| Launch | `tokenFactoryAddress`、`mintAddress`、`memberNFTAddress` | 代币工厂、铸造和身份依赖 |
| Launch | `rootParentTokenAddress` | 根父币 WBNB |
| Launch | `distributor`、`name`、`symbol` | 首币分发目标、名称和符号；首币固定使用 `NoCallback`，`distributor` 非零 |
| Launch | `launchRatio` | 发射阈值比例，`1e18` 精度，如 `1e16 = 1%` |
| Launch | `maxLaunchCount` | 每社区累计次数上限，如 `100` |
| TokenFactory | `launchAddress`、`mintAddress`、`pairFactoryAddress` | 唯一创建调用方、代币 minter 和 Pair Factory |
| TokenFactory | `initialSupply`、`maxSupply` | 初始/最大供应量，工厂 init 固定；`initialSupply <= maxSupply` |
| TokenFactory.createToken | `distributor` | 本次创建的首批代币接收者；非零 |

MemberNFT 的首币地址在 `Launch.init` 创建首币后通过 `MemberNFT.init(tokenAddress)` 绑定，不在部署时传入。Launch 的首币分发地址、名称和符号，以及 TokenFactory 的初始化/创建参数统一见 [Launch](07-launch.md)，不另维护供应量副本。Router 是 Stake 加减流动性的外部依赖，不参与工厂的代币/Pair 创建。

## 实现约束

- Phase 使用构造参数创建；Core 其他合约先部署，再按依赖顺序调用一次 `init`，依赖后部署的地址通过后续 `init` 绑定。
- Vote 在投票阶段读取 Mint 配置的 `proposalRewardMinVotePerThousand`，并持续维护本轮达标 Proposal 票数总和；Mint 在准备时读取冻结结果。
- 参数有效范围和组合限制以各模块规格为准；表中示例值不是默认部署配置。
