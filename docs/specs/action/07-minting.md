# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口 `mintActionReward`；ActionTarget 作为 Target 调用 Mint 时把该 Executor 作为 `recipient` 传入，Mint 直接把指定 token、Round、Proposal 的完整激励铸给 Executor——激励不落在 ActionTarget，没有「先铸给自己、再转一次」的转发，也没有中转余额需要清理。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复铸造。铸造去重由 Mint 持有：ActionTarget 不保存行动级铸造状态位，重复调用由 Mint 回滚 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`（Mint 是 init 固定的可信依赖、`LOVE20Token.mint` 无回调，外呼不可重入）。**可结算窗口不在本入口**：`mintActionReward` 不判 `round` 与当前阶段的关系，窗口随行动类型不同（LP `phase−2`，Group/Service `phase−3`），由调用方 Executor 负责；新增 Executor 必须实现等价约束（边界同 core 卷 `MNT-01`）。

流转由两条事件分别留痕，粒度与所在层一致：ActionTarget 在整笔转出时发出**行动级**的 `ActionRewardMinted(tokenAddress, actionId, round, amount)`，`amount` 即 `mintActionReward` 的返回值，与同层查询 `actionReward` 同源；各 Executor 在成员或角色结算时发出**成员级**的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)`。本轮该行动只能铸造一次（去重键 `tokenAddress + actionId + round`，由 Mint 的状态位判定）；成员不参与这条链路也不需要了解它，成员级入口只存在于各 Executor。成员结算量为零（`mintAmount` 与 `burnAmount` 均为 0）时按成因三分为 `MemberHasNoVote(tokenAddress, round, memberId)`（成员侧无有效参与 / 无最终得分）、`MemberRewardPoolEmpty(tokenAddress, round)`（轮级分母或行动激励为零）与 `MemberRewardRoundedToZero(tokenAddress, round, memberId)`（逐项取整为零），不置位已结算状态、不发事件，与 Core 铸造的零额拒绝同口径；有销毁量即允许结算。三个错误名与载荷与 core `IMintErrors` 完全一致（协议级「一名一签名」约束，执行器不再重复携带 `actionId`）。

**事件例外（推举转发）**：`ActionTarget.onProposalSubmitted` 与各 Executor 的同名回调是纯转发，不新增 action 层的领域事件——推举事实由 Core 的 `ProposalSubmitted` 记录，action 层再发一条只会制造两份同义事实。这是本族「写入口必有事件」的唯一例外，登记在此以免被当成遗漏。

成员级结算支持批量：`mintMemberRewards(tokenAddress, actionIds[], rounds[], memberId)` 以平行数组按下标配对，逐元素执行与 `mintMemberReward` 相同的结算，返回按下标对齐的 `(mintAmounts[], burnAmounts[])`。两数组长度不一致回滚 `BatchLengthMismatch(actionIdsLength, roundsLength)`；任一元素失败整笔回滚（下标对齐、不补空）；空数组在鉴权通过后返回空结果、不改状态；不设长度上限——成本由调用方自付，区块 gas 为自然上界（与 core `mintGovRewards` 同型）。批量入口同样先鉴权，权限与单条入口一致，由各 Executor 规格固定。

行动级整笔激励无法分配（判据由各 Executor 规格固定，如无可分配源行动、全部验证失败）时，**全链路没有销毁路径**：Mint 只支付、ActionTarget 只路由，两者都不判断「该不该作废」，各 Executor 也不提供销毁入口。该轮激励因此永久停留在未结算状态——`ActionTarget.actionReward` 一直返回 `(理论数量, false)`，Mint 的 `totalRewardReserved` 不释放，后续轮次的 `rewardAvailable` 相应被压低，代币永不铸出。这是有意的取舍：不可分配意味着「本轮没有任何有效分配路径」，属于罕见情形；少发比「误判并销毁本该发给成员的激励」安全，而销毁入口本身是一条 permissionless 的状态变更路径。成员归属的销毁并入 `MemberRewardMinted.burnAmount`，与此无关。

Core 的预留、铸造和取消额度账本见 [Mint](../core/07-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

事件和错误定义分别见 [`IActionTarget.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionTarget.sol)、[`IActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionExecutor.sol)、[`ILpExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/ILpExecutor.sol)、[`IGroupActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionExecutor.sol) 与按业务模块拆分的 [`IGroupActionVerify.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionVerify.sol)、[`IGroupActionJoin.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionJoin.sol)、[`IGroupActionManager.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionManager.sol)、[`IGroupActionIndexes.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionIndexes.sol)、[`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol) 和 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)。错误按**局部优先**声明：每个合约/模块拥有自己的 `I<Name>Errors`，不设中心枚举或跨仓库错误接口，错误名自带字段（如 `ZeroJoinTokenAddress`）；模块只在拒绝条件与载荷完全相同时复用另一个本地 `Errors` 接口（如三个 Executor 的 `NotActionTarget(caller)`、`NotMemberOwner(memberId)` 与结算族错误）。每个接口只声明自身合约实际拥有的事件和错误：三个 Executor 共用且签名一致的 1 个事件（`MemberRewardMinted`）与 11 个错误（`NotActionTarget`、`ActionNotCreated`、`NotMemberOwner`、`RewardAlreadyMinted`、`MemberHasNoVote`、`MemberRewardPoolEmpty`、`MemberRewardRoundedToZero`、`BatchLengthMismatch`、`RoundNotStarted`、`RoundBeforeActionCreated`、`RoundAfterMintWindow`）声明在基座 `IActionExecutor` 的子接口中，由三个 Executor 继承；`ActionRewardMinted` 只由 ActionTarget 发出，声明在 `IActionTargetEvents`，各 Executor 不声明。执行器专属错误留在各自 `Errors` 子接口（如链群加入代币 `ZeroJoinTokenAddress`、Target Data 形状、比例、分割线、群管理与验证错误），不上提基座；`ActionNotCreated` 被三个 Executor 与链群管理、验证者申请共用，按同签名共用规则声明在基座。Executor 与 ActionTarget 的接口默认不继承标准错误：`ownerOf`/转账的 `ERC721NonexistentToken`、ERC20 标准错误按透传登记，来源 ABI 为 MemberNFT/LOVE20Token；`SafeERC20FailedOperation` 通过 `SafeERC20` 进入执行器 ABI。只有顶层集成面确需自包含 ABI 时才白名单继承。

事件按 BSC 业务主体使用 `memberId`；事件中的地址仅表示代币、合约或调用审计地址。行动级事件（`ActionRegistered`、`ActionRewardMinted`、`GroupActionCreated`、`ServiceActionCreated`、`LpActionCreated`）不含 `memberId`，它们的主体是行动或服务提案本身。

| 错误 | 拒绝条件 |
| --- | --- |
| `AlreadyInitialized()` | ActionTarget 的 `init` 被重复调用 |
| `ZeroJoinTokenAddress()` / `ZeroActionTokenAddress()` | 创建回调的参与计价代币或服务行动代币为零 |
| `NotSubmit(address caller)` / `NotVote(address caller)` | ActionTarget 三类回调的调用者不是 Submit / Vote |
| `NotActionTarget(address caller)` | Executor 三类回调的调用者不是 ActionTarget |
| `UnboundProposal(tokenAddress, proposalId)` | ActionTarget 的推举/投票回调对应的 `(tokenAddress, proposalId)` 无绑定（结构上不可达，防御 Core 侧缺陷） |
| `UnauthorizedExecutor(tokenAddress, actionId)` | 调用者不是该 `(tokenAddress, actionId)` 已注册绑定的 Executor（含未注册绑定时的任何调用者）。**同一 selector 同时表示「行动未绑定」与「调用者不匹配」**；链下要区分须反查 `executorByActionId`（零地址 = 未绑定），载荷本身没有区分位 |
| `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)` | 注册加入时当前投票轮不大于该行动创建轮（投票轮未走完，加入未开放） |
| `NotMemberOwner(memberId)` | 调用者非该 NFT 当前持有人 |
| `ProposalNotVoted(tokenAddress, proposalId)` | Proposal 无票或未达门槛 |
| `InsufficientTargetDataItems(uint256 count, uint256 minCount)` / `InvalidTargetDataShape(uint256 index, uint256 length)` | 创建/推举/投票转发的第 `0` 项缺失或不是 32 字节 |
| `ExecutorNotContract(address executor)` | 第 `0` 项解码为零地址或 EOA |
| `ExecutorTargetMismatch(address expected, address actual)` | 创建握手：`executor.ACTION_TARGET_ADDRESS()` 不是本 ActionTarget |
| `ExecutorHandshakeFailed(address executor)` | 创建握手的 `ACTION_TARGET_ADDRESS()` 调用回滚 |
| `TargetDataExecutorMismatch(address expected, address actual)` | 推举/投票转发的第 `0` 项不是已绑定 Executor |
| `AlreadyCreated(tokenAddress, actionId)` | 同一 `(tokenAddress, actionId)` 的重复创建回调 |
| `InsufficientTargetDataItems(uint256 count, uint256 minCount)` | Target Data 项数少于约定（GroupAction 创建少于 6、LP/GroupService 创建少于 4、创建回调第 `0` 项缺失；`count` 为实际项数，`minCount` 为下界） |
| `TooManyTargetDataItems(uint256 count, uint256 maxCount)` | Target Data 项数多于约定（GroupAction 创建多于 7、LP/GroupService 创建多于 4、投票回调多于 1/2；`count` 为实际项数，`maxCount` 为上界） |
| `InvalidTargetDataShape(uint256 index, uint256 length)` | 第 `index` 项不是 `abi.encode` 的 32 字节形态 |
| `VerificationInfoLengthMismatch(uint256 expected, uint256 actual)` | 验证信息 schema 两数组不等长，或成员值项数与 schema 不符 |
| `DescriptionTooLong(uint256 length, uint256 maxLength)` | 群描述或验证者申请说明超过 1024 字节 |
| `InvalidMaxJoinAmountRatio(uint256 value)` / `InvalidActivationMinGovRatio(uint256 value)` / `InvalidRatioForPublicVerifier(uint256 value)` | 创建回调的比例超出 `1e18`（按字段分别报错） |
| `InvalidMinGovRatio(uint256 value)` / `InvalidJoinTokenFactory(address joinToken, address factory)` | LP 最小治理比例超过 `1e18` / 参与代币不是该工厂登记的交易对 |
| `ZeroMinJoinAmount()` / `InvalidMaxJoinAmount(uint256 minAmount, uint256 maxAmount)` | 群最小加入量为零 / 非零最大加入量低于最小加入量 |
| `GroupAlreadyActivated(uint256 groupId)` / `GroupNotActive(uint256 groupId)` / `GroupNotExist(uint256 groupId)` / `ZeroGroupId()` | 重复激活 / 在未激活链群上操作 / 群身份不存在 / 群参数缺省（`groupId == 0`，与「群身份不存在」分开） |
| `DeactivationLockedInActivatedRound(uint256 groupId, uint256 round)` | 在链群激活的同一加入轮停用 |
| `InsufficientActivationMinGovRatio(uint256 groupId, uint256 required, uint256 actual)` | 群 owner 的治理票占比低于激活下限 |
| `NoGovVotes(address tokenAddress)` | 激励代币没有全局治理票，无法计算激活下限 |
| `ZeroParticipationAmount()` | 加入、撤回或 Provider 撤回金额为零 |
| `BelowMinJoinAmount(uint256 actual, uint256 minAmount)` | 首次加入量低于群最小加入量 |
| `WithdrawAmountExceeded(uint256 amount, uint256 joined)` | 撤回超过自有余额 |
| `GroupMaxJoinAmountExceeded(uint256 memberId, uint256 actual, uint256 limit)` / `ActionMaxJoinAmountExceeded(uint256 memberId, uint256 actual, uint256 limit)` | 加入后的成员总量超过群上限 / 行动上限 |
| `GroupCapacityExceeded(uint256 groupId, uint256 actual, uint256 limit)` | 加入后的群总量超过 `maxCapacity` |
| `GroupAccountsFull(uint256 groupId, uint256 count, uint256 maxCount)` | 首次加入时群成员数已达 `maxAccounts` |
| `AlreadyInOtherGroup(uint256 memberId, uint256 existingGroupId, uint256 requestedGroupId)` | 同一行动内成员已归属其他链群 |
| `NotJoined(address tokenAddress, uint256 actionId, uint256 memberId)` / `AlreadyJoined(address tokenAddress, uint256 actionId, uint256 memberId)` | 未加入时退出 / 重复加入服务 Proposal |
| `QuotaArrayLengthMismatch(uint256 memberIdsLength, uint256 amountsLength)` / `QuotaMemberIsProvider(uint256 providerId)` / `ZeroQuotaAmount(uint256 memberId)` / `QuotaNotGranted(uint256 groupId, uint256 providerId, uint256 memberId)` | Provider 额度批量参数不合法 |
| `InsufficientProviderQuota(uint256 providerId, uint256 required, uint256 available)` | Provider 额度不足 |
| `OriginScoresEmpty()` / `VerificationBatchTooLarge(uint256 count, uint256 maxCount)` / `ScoreLimitExceeded(uint256 index, uint256 score, uint256 maxScore)` | 验证批次为空 / 超过 100 项 / 原始分超过 100 |
| `ScoreCountExceeded(uint256 startIndex, uint256 count, uint256 maxCount)` | 验证批次越过该群成员总数；`maxCount` 为该群该轮成员总数（限定名口径，不再是裸的实际值字段名） |
| `StartIndexMismatch(uint256 expected, uint256 actual)` | 验证批次跳跃、重复或乱序；`expected` 为该群当前已验证数量，`actual` 为调用者传入的 `startIndex` |
| `ZeroVerifyVotes(address tokenAddress, uint256 verifierId)` | 验证者没有有效治理票 |
| `NoActiveApplication(uint256 verifierId)` | 没有当前申请或申请已失效 |
| `VerifierNotRanked(uint256 verifierId, uint256 round)` / `VerifierNotOpen(uint256 verifierId, uint256 round)` | 未进入当轮排名 / 分割窗口未开 |
| `GroupVerificationAlreadyComplete(uint256 groupId, uint256 round)` | 已完成验证的群重复提交 |
| `RoundVerifierLocked(address tokenAddress, uint256 actionId, uint256 round, uint256 lockedVerifierId)` | 该轮已被其他验证者锁定（名称描述「轮次已锁定」而非「该验证者已锁定」，载荷带当前锁定者） |
| `UnknownSourceAction(address sourceTokenAddress, uint256 sourceActionId)` | 二次分配配置的源行动不是本 Executor 创建 |
| `RecipientArrayLengthMismatch(uint256 recipientIdsLength, uint256 ratiosLength, uint256 remarksLength)` | 二次分配三数组不等长 |
| `TooManyRecipients(uint256 count, uint256 maxCount)` / `ZeroRecipientRatio(uint256 recipientId)` / `DuplicateMemberId(uint256 memberId)` / `RecipientIsGroupId(uint256 groupId, uint256 recipientId)` | 接收人配置不合法 |
| `DistributionOverflow(uint256 configured, uint256 limit)` | 配置比例总和超过上限 `1e18` 时拒绝；正好 `1e18` 合法 |
| `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` | 重复成员结算（Executor 层；行动级的重复铸造由 Mint 回滚 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`） |
| `MemberHasNoVote(address tokenAddress, uint256 round, uint256 memberId)` | 成员结算无产出且成因在成员侧：该成员本轮无有效参与量 / 无最终得分（载荷与 core `IMintErrors` 一致，不含 `actionId`——执行器本身已按行动隔离） |
| `MemberRewardPoolEmpty(address tokenAddress, uint256 round)` | 成员结算无产出且成因在轮级：有效参与总量 / 最终得分总量 / 行动激励为零，本轮没有分配路径 |
| `MemberRewardRoundedToZero(address tokenAddress, uint256 round, uint256 memberId)` | 成员结算无产出且成因是逐项取整：分子非零但结果向下取整为零 |
| `ActionNotCreated(tokenAddress, actionId)` | 行动尚未创建（`createdRound == 0`）：群激活、验证者申请与三个 Executor 的成员结算（含批量）都拒绝 |
| `RoundNotStarted(uint256 requiredRound, uint256 currentRound)` | 对应阶段的 Round 小于 1：`requiredRound` 恒为 1，`currentRound` 为推导出的 0（`currentVoteRound` 写作 `(1, phase)`，因 `phase < 1` 时 phase 恒为 0，载荷与 `(1, 0)` 等价） |
| `RoundBeforeActionCreated(uint256 round, uint256 createdRound)` | 成员结算的 `round` 早于行动创建轮（行动已存在），三个 Executor 一致 |
| `RoundAfterMintWindow(uint256 round, uint256 mintRound)` | 成员结算的 `round` 超过当前铸币轮（仅当铸币阶段已开始且 `mintRound != 0`） |
| `NotQualified(address actionTokenAddress, uint256 round, uint256 memberId)` | 服务加入者既非社区激活群 owner，也没有该轮有效验证者申请 |
| `ActionTokenParentMismatch(address actionTokenAddress, address serviceTokenAddress, address actualParentTokenAddress)` | 服务代币不是行动代币，且行动代币的实际父币不是服务代币；载荷同时给出行动代币、服务代币与实际父币 |

Target Data 的项数、每项位置与编码由各 Executor 在自己的规格中固定，并在对应回调内自行校验，错误也声明在各自的 `Errors` 子接口；ActionTarget 只解析创建回调的第 `0` 项 executor。错误名自带字段，不复用「一个 `InvalidAddress` 覆盖多个字段」的写法：零地址按字段分别报 `Zero<Field>Address()`，比例按字段分别报 `Invalid<Field>(value)`，参与量按条件分别报 `ZeroParticipationAmount`/`BelowMinJoinAmount`/`WithdrawAmountExceeded`；参数为零与非零非法分开（如 `ZeroMinJoinAmount()` / `InvalidMaxJoinAmount(...)`、`ZeroGroupId()` / `GroupNotExist(...)`）；Target Data 项数的下界与上界分开（`InsufficientTargetDataItems` / `TooManyTargetDataItems`）；结算轮次按轴分别报 `RoundBeforeActionCreated` 与 `RoundAfterMintWindow`（后者只用于「铸币阶段已开始但已过窗」）；阶段未开始（`mintRound == 0`）时统一报 `RoundNotStarted(requiredRound, currentRound)`，读面 `currentMintRound()` 与写面同口径。以上错误均在对应外层交易中回滚。

验收见 [Action 验收](08-testing.md)。

## 销毁面

三个 Executor 共用 `MemberRewardMinted` 事件，但只有 `GroupServiceExecutor` 有真实销毁：治理上限触发时 `burnAmount = ownerBurned`，并把数量写入 `ownerBurnedByMemberId`。`GroupActionExecutor` 与 `LpExecutor` 没有销毁路径，`burnAmount` 恒为 `0`；`GroupActionStorage` 不再有对应状态槽（`memberBurnedReward` 已删除），因此 GroupAction 的 `memberReward` 直接返回字面量 `0`，不读任何存储。共享 schema 不因此改变，索引方按字段取 0 处理即可。
