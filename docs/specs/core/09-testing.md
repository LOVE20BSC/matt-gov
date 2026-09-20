# Core 验收

本文件规定验收范围，行为以对应模块为准；证据与发布要求见 [组织验收](../../acceptance.md)。这是待实现的场景清单，不是已通过的测试报告。

事件和错误定义分别位于 [`IMemberNFT.sol`](../../../interfaces/core/IMemberNFT.sol)、[`IPhase.sol`](../../../interfaces/core/IPhase.sol)、[`IStake.sol`](../../../interfaces/core/IStake.sol)、[`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)、[`IVote.sol`](../../../interfaces/core/IVote.sol)、[`IMint.sol`](../../../interfaces/core/IMint.sol)、[`ILaunch.sol`](../../../interfaces/core/ILaunch.sol) 和 [`ILOVE20Token.sol`](../../../interfaces/core/ILOVE20Token.sol)。

必须拒绝无效成员或非来源控制者、零 Target/Distributor、非法模式、Target Data 长度不等、重复 Proposal/推举、投票超额、Round 未结束或未准备、重复铸造/销毁、待解锁时追加或融合、解锁期不足、跨社区次数操作、次数不足或超上限。未冻结专用 selector 的拒绝条件不能冒充已确定 ABI。

批量治理激励中任一 Round 无效，以及 Pair、Router、Target、distributor 回调等外部调用失败时，整笔交易回滚。

## 验收矩阵

| 模块 | 场景 | 预期 |
| --- | --- | --- |
| [MemberNFT](02-member-nft.md) | NFT 转移、名称 32 bytes 边界、短名费用 | 新持有人控制未结算权益，历史不变；名称与费用符合模块规则 |
| MemberNFT | 持有人枚举分页：自转账、转出全部、再转入、`offset` 越界 | 自转账不移除，余额归零后移除，位置按 swap-and-pop 重排；`holders` 按页返回且越界返回空数组与真实总数 |
| [Phase](03-phase.md) | 空阶段、首个推举同步、偏差在/超过 `ADJUST_THRESHOLD` | 时间继续推进，按初始化阈值校准，不改历史 |
| Phase | 任意地址先同步、同轮跨社区重复、下轮再同步 | 每个投票轮只记录一次；重复无操作、不阻塞 Submit；下轮重新允许 |
| [Stake](04-stake.md) | 两类资产统一解锁；向非自有目标融合 | 只增目标状态；同一等待期后提取两类资产 |
| Stake | LP 份额、手续费销毁统计、Uniswap V2 兼容 DEX、加速历史继承 | 份额/资产/历史与模块公式一致，不因无记录而错误复活 |
| Stake | 入池最优量折算与滑点：储备任一侧为零、比例一致、偏离未超/超过 `slippage`、LP 铸出为零 | 储备为零时按期望量入池；比例一致时不折算；偏离未超阈值时只转入折算量并计入相应份额；超过阈值回滚 `SlippageExceeded(slippage, deviation)`；LP 为零回滚 `ZeroAmount("lpMinted")` |
| Stake | Pair 读取：首次质押读取并登记、再次质押不再访问 Factory、未登记 Pair 的社区调用各入口 | 首次质押读 Factory 的 `getPair` 并保存；已登记后不再访问 Factory；未登记 Pair 时所有入口回滚 `InvalidTokenAddress()`，`Stake` 从不创建 Pair |
| Stake | 加速历史查询的轮次边界：已结束轮、无记录轮、明确归零轮、未来轮 | 前三者按最近不晚于目标轮的记录返回（含显式归零）；未来轮回滚 `InvalidPhase(round)`，不把当前记录当作未来轮的值 |
| Stake | 结算的夹子防护：阈值单位触发、同 Phase 重复调用、剩余手续费、单笔量小到无法产出 | 单笔处理量恰为一个阈值单位（价格移动不超过 `1 / MAX_WITHDRAWABLE_TO_FEE_RATIO`）；同一 Phase 第二次调用无操作返回；`FeesSettled` 只报实际处理量；剩余留待下个 Phase 且不重复扣减 `withdrawableLp`；单笔量过小时不结算也不消耗本 Phase 额度 |
| Stake | 等待期到期边界：`unlockRequestPhase + promisedWaitingPhases` 的前一个、恰好、后一个 Phase | 前一个与恰好等于该 Phase 都回滚 `NotEnoughWaitingPhases()`；其后一个 Phase 起允许提取；`canWithdraw` 与 `withdraw` 在同一 Phase 上给出相同结论 |
| Stake | 加速历史的解锁归属：申请解锁、等待期内查询、提取、解锁中再追加 | 申请解锁当轮即扣减成员与全局累计；等待期与提取都不重复扣减；`totalBoostShares` 到提取才减少；解锁中追加回滚 `UnstakeAlreadyRequested()` |
| Stake | `init` 参数校验与重复初始化：五个依赖地址任一为零、`promisedWaitingPhasesMin` 为零、`maxWithdrawableToFeeRatio` 为零、`promisedWaitingPhasesMin > promisedWaitingPhasesMax`、已初始化 | 依赖地址任一为零 → `InvalidAddress()`；`promisedWaitingPhasesMin` 为零 → `ZeroAmount("promisedWaitingPhasesMin")`；`maxWithdrawableToFeeRatio` 为零 → `ZeroAmount("maxWithdrawableToFeeRatio")`；`min > max` → `InvalidAmount()`；已初始化 → `AlreadyInitialized()`（初始化状态先于参数校验，同时命中回滚前者）；成功后五个依赖 getter 与三个参数 getter 等于入参，再次调用回滚 |
| [Proposal](05-submit.md) / [Vote](06-vote.md) | 零 Target、三类回调失败 | 拒绝并整体回滚 |
| Proposal | `proposalIds`/`proposalIdsByAuthor`/`submitInfos` 分页：`offset` 越界、`limit` 超剩余、`reverse`、只取总数 | 三个查询都按 `(offset, limit, reverse)` 按页返回并给出真实总数，越界返回空数组且不回滚，`reverse` 时从新到旧；`proposalIds`/`proposalIdsByAuthor` 只回 `proposalId`；`limit = 0` 只回总数 |
| Proposal | `proposalInfosByIds(proposalIds[])` 批量：未分配 ID、批量缺项、批量大小 | 回 `ProposalInfo` 数组，与入参下标一一对应，无长度上限；任一 ID 未分配回滚 `ProposalNotFound`，不静默补空 |
| Proposal | `submitInfos` 记录内容与轮次边界：同轮多笔推举、无推举的 Round、未开始的 Round | 每条记录同时含 `submitterId` 与 `proposalId`；无推举或未开始的 Round 返回空数组与 `0` 而不回滚 |
| Proposal | 两条方向单键：`proposalIdBySubmitter` 与 `submitterIdByProposalId` 互为逆、回 `0` 的三种情形 | 已推举时两条互为逆映射；未分配过的 `proposalId`、已分配但本轮未推举、本轮未推举的成员都回 `0` 而不回滚 |
| Proposal | `submitNewProposal` 创建后立即推举：事件顺序、回调顺序、本轮名额、`Phase.sync` | 同一笔内先 `ProposalCreated` 后 `ProposalSubmitted`，先 `onProposalCreated` 后 `onProposalSubmitted`；写满三处推举状态并占用本 Round 名额；本轮首笔推举触发 `sync` |
| Proposal | 两个入口的名额与去重交叉：先 `submitNewProposal` 再 `submit`、同轮重复创建、跨轮推举已有 Proposal | 同一成员同轮第二次推举回滚 `OnlyOneSubmitPerRound`；同一 Proposal 同轮第二次回滚 `AlreadySubmitted`；跨轮推举已有 Proposal 成功且不触发创建回调 |
| [Mint](07-mint.md) | Round 准备、单 Proposal 结算、重复准备 | 每轮仅预留一次，单项不能重复结算；对应 `MintTest.testZeroVotePreparationMustEmitEvent`、`testZeroProposalRewardMustRevert` |
| Mint | 约 300 个 Proposal 的准备、缓存读取 | 准备阶段一次扫描并缓存达标 Proposal 总票数；后续单项结算不再扫描 Vote 列表，重复准备不改缓存；对应 `MintTest.testPrepareScansProposalsOnceAndCachesResult` |
| Mint | 两种零总量、三段治理结果、批量多轮 | 预留不重加，销毁不重复，任一失败整体回滚；对应 `testBatchMustPreserveMemberOwner`、`testBatchFailureRollsBackRewardsAndLaunchCounts`、`testGovernanceQueryMatchesMintAndBoostBurn` |
| Vote / Mint | 投票时快照为 50，随后追加 30；再次投票或不投票；NFT 转移 | 不投票仍按 50，再投票按 80、总量仅加 30；结算和转移不重算；Vote 快照由 `VoteTest` 覆盖，Mint 结算由 `MintTest.testGovernanceQueryMatchesMintAndBoostBurn` 覆盖 |
| [Mint](07-mint.md) | 向上取整、跨多个阈值、社区上限 | 余数保留，新增次数不超上限，仅 Mint 可 `addLaunchCount`；对应 `testLaunchCreditMustUseActualPreMintSupply`、`testLaunchThresholdMustRoundUp`、`testLaunchCapRetainsUnconvertedCredit` |
| [Launch](08-launch.md) | 向非自有 NFT 部分融合、次数消耗、账本上限、非 Mint 调用 `addLaunchCount` | 源扣目标增，不转移额度，已消耗次数不能再次使用；只有 `init` 校验初始化状态，三个写入口不重复校验 |
| Launch.init | 首币、Airdrop、参数校验、任一步失败或重复初始化 | `Launch.init(LaunchInitParams)` 一次完成配置、首币创建和 MemberNFT 初始化，失败全回滚，成功后不能重做；首币发含名称和符号的 `TokenLaunched`（`launcherMemberId = 0`） |
| Launch | 代币列表与子币列表分页、`offset` 越界、符号重复、按代币地址取父币 | `tokens`/`childTokens` 按页返回且包含首币，越界返回空数组与真实总数；施加 `Test` 前缀后的符号重复回滚 `TokenSymbolExists()`；`parentTokenOf` 与 `isLOVE20Token` 对首币、子币与未登记地址的结果一致 |
| Launch | 发射即建池：`init` 首币、`launchToken` 子币、Factory 返回零地址 | `init` 与每次 `launchToken` 都在同一笔内对新建代币调用 `createPair(tokenAddress, parentTokenAddress)`；返回零地址回滚 `InvalidAddress()`；`Stake` 首次质押时读到的正是该 Pair |

存在“待确认”的场景必须先确定预期，不得用当前实现结果反推规格。
