# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口 `mintActionReward`；ActionTarget 作为 Target 调用 Mint 时把该 Executor 作为 `recipient` 传入，Mint 直接把指定 token、Round、Proposal 的完整激励铸给 Executor——激励不落在 ActionTarget，没有「先铸给自己、再转一次」的转发，也没有中转余额需要清理。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复铸造。铸造去重由 Mint 持有：ActionTarget 不保存行动级铸造状态位，重复调用由 Mint 回滚 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`（Mint 是 init 固定的可信依赖、`LOVE20Token.mint` 无回调，外呼不可重入）。

流转由两条事件分别留痕，粒度与所在层一致：ActionTarget 在整笔转出时发出**行动级**的 `ActionRewardMinted(tokenAddress, actionId, round, amount)`，`amount` 即 `mintActionReward` 的返回值，与同层查询 `actionReward` 同源；各 Executor 在成员或角色结算时发出**成员级**的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)`。本轮该行动只能铸造一次（去重键 `tokenAddress + actionId + round`，由 Mint 的状态位判定）；成员不参与这条链路也不需要了解它，成员级入口只存在于各 Executor。成员结算量为零（`mintAmount` 与 `burnAmount` 均为 0）时回滚 `MemberActionRewardUnavailable(tokenAddress, actionId, memberId, round)`，不置位已结算状态、不发事件，与 Core 铸造的零额拒绝同口径；有销毁量即允许结算。

成员级结算支持批量：`mintMemberRewards(tokenAddress, actionIds[], rounds[], memberId)` 以平行数组按下标配对，逐元素执行与 `mintMemberReward` 相同的结算，返回按下标对齐的 `(mintAmounts[], burnAmounts[])`。两数组长度不一致回滚 `BatchLengthMismatch(actionIdsLength, roundsLength)`；任一元素失败整笔回滚（下标对齐、不补空）；空数组在鉴权通过后返回空结果、不改状态；不设长度上限——成本由调用方自付，区块 gas 为自然上界（与 core `mintGovRewards` 同型）。批量入口同样先鉴权，权限与单条入口一致，由各 Executor 规格固定。

行动级整笔激励无法分配（判据由各 Executor 规格固定，如无可分配源行动、全部验证失败）时，**全链路没有销毁路径**：Mint 只支付、ActionTarget 只路由，两者都不判断「该不该作废」，各 Executor 也不提供销毁入口。该轮激励因此永久停留在未结算状态——`ActionTarget.actionReward` 一直返回 `(理论数量, false)`，Mint 的 `rewardReserved` 不释放，后续轮次的 `rewardAvailable` 相应被压低，代币永不铸出。这是有意的取舍：不可分配意味着「本轮没有任何有效分配路径」，属于罕见情形；少发比「误判并销毁本该发给成员的激励」安全，而销毁入口本身是一条 permissionless 的状态变更路径。成员归属的销毁并入 `MemberRewardMinted.burnAmount`，与此无关。

Core 的预留、铸造和取消额度账本见 [Mint](../core/07-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

事件和错误定义分别见 [`IActionTarget.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionTarget.sol)、[`IActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionExecutor.sol)、[`ILpExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/ILpExecutor.sol)、[`IGroupActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionExecutor.sol) 与按业务模块拆分的 [`IGroupActionVerify.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionVerify.sol)、[`IGroupActionJoin.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionJoin.sol)、[`IGroupActionManager.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionManager.sol)、[`IGroupActionIndexes.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionIndexes.sol)、[`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol) 和 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)。错误按**局部优先**声明：每个合约/模块拥有自己的 `I<Name>Errors`，不设中心枚举或跨仓库错误接口，错误名自带字段（如 `ZeroJoinTokenAddress`）；模块只在拒绝条件与载荷完全相同时复用另一个本地 `Errors` 接口（如三个 Executor 的 `NotActionTarget(caller)`、`NotMemberOwner(memberId)` 与结算族错误）。每个接口只声明自身合约实际拥有的事件和错误：三个 Executor 共用且签名一致的 1 个事件（`MemberRewardMinted`）与 9 个错误（`NotActionTarget`、`ActionNotCreated`、`NotMemberOwner`、`RewardAlreadyMinted`、`MemberActionRewardUnavailable`、`BatchLengthMismatch`、`RoundNotStarted`、`RoundBeforeActionCreated`、`RoundAfterMintWindow`）声明在基座 `IActionExecutor` 的子接口中，由三个 Executor 继承；`ActionRewardMinted` 只由 ActionTarget 发出，声明在 `IActionTargetEvents`，各 Executor 不声明。执行器专属错误留在各自 `Errors` 子接口（如链群加入代币 `ZeroJoinTokenAddress`、Target Data 形状、比例、分割线、群管理与验证错误），不上提基座；`ActionNotCreated` 被三个 Executor 与链群管理、验证者申请共用，按同签名共用规则声明在基座。Executor 与 ActionTarget 的接口默认不继承标准错误：`ownerOf`/转账的 `ERC721NonexistentToken`、ERC20 标准错误按透传登记，来源 ABI 为 MemberNFT/LOVE20Token；`SafeERC20FailedOperation` 通过 `SafeERC20` 进入执行器 ABI。只有顶层集成面确需自包含 ABI 时才白名单继承。

事件按 BSC 业务主体使用 `memberId`；事件中的地址仅表示代币、合约或调用审计地址。行动级事件（`ActionRegistered`、`ActionRewardMinted`、`GroupActionCreated`、`ServiceActionCreated`、`LpActionCreated`）不含 `memberId`，它们的主体是行动或服务提案本身。

| 错误 | 拒绝条件 |
| --- | --- |
| `AlreadyInitialized()` | ActionTarget 的 `init` 被重复调用 |
| `ZeroJoinTokenAddress()` / `ZeroActionTokenAddress()` | 创建回调的参与计价代币或服务行动代币为零 |
| `NotSubmit(address caller)` / `NotVote(address caller)` | ActionTarget 三类回调的调用者不是 Submit / Vote |
| `NotActionTarget(address caller)` | Executor 三类回调的调用者不是 ActionTarget |
| `UnboundProposal(tokenAddress, proposalId)` | ActionTarget 的推举/投票回调对应的 `(tokenAddress, proposalId)` 无绑定（结构上不可达，防御 Core 侧缺陷） |
| `UnauthorizedExecutor(tokenAddress, actionId)` | 调用者不是该 `(tokenAddress, actionId)` 已注册绑定的 Executor（含未注册绑定时的任何调用者） |
| `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)` | 注册加入时当前投票轮不大于该行动创建轮（投票轮未走完，加入未开放） |
| `NotMemberOwner(memberId)` | 调用者非该 NFT 当前持有人 |
| `ProposalNotVoted(tokenAddress, proposalId)` | Proposal 无票或未达门槛 |
| `TargetDataLengthMismatch(uint256 expected, uint256 actual)` / `InvalidTargetDataShape(uint256 index, uint256 length)` | 创建/推举/投票转发的第 `0` 项缺失或不是 32 字节 |
| `ExecutorNotContract(address executor)` | 第 `0` 项解码为零地址或 EOA |
| `ExecutorTargetMismatch(address expected, address actual)` | 创建握手：`executor.ACTION_TARGET_ADDRESS()` 不是本 ActionTarget |
| `ExecutorHandshakeFailed(address executor)` | 创建握手的 `ACTION_TARGET_ADDRESS()` 调用回滚 |
| `TargetDataExecutorMismatch(address expected, address actual)` | 推举/投票转发的第 `0` 项不是已绑定 Executor |
| `AlreadyCreated(tokenAddress, actionId)` | 同一 `(tokenAddress, actionId)` 的重复创建回调 |
| `TargetDataLengthMismatch(uint256 expected, uint256 actual)` | Target Data 项数与约定不符（GroupAction 少于 6 报 `expected = 6`，多于 7 报 `expected = 7`；LP/GroupService 固定 4；投票回调最多 1/2） |
| `InvalidTargetDataShape(uint256 index, uint256 length)` | 第 `index` 项不是 `abi.encode` 的 32 字节形态 |
| `VerificationInfoLengthMismatch(uint256 expected, uint256 actual)` | 验证信息 schema 两数组不等长，或成员值项数与 schema 不符 |
| `DescriptionTooLong(uint256 length, uint256 maxLength)` | 群描述或验证者申请说明超过 1024 字节 |
| `InvalidMaxJoinAmountRatio(uint256 value)` / `InvalidActivationMinGovRatio(uint256 value)` / `InvalidRatioForPublicVerifier(uint256 value)` | 创建回调的比例超出 `1e18`（按字段分别报错） |
| `InvalidMinGovRatio(uint256 value)` / `InvalidJoinTokenFactory(address joinToken, address factory)` | LP 最小治理比例超过 `1e18` / 参与代币不是该工厂登记的交易对 |
| `InvalidMinJoinAmount(uint256 minAmount)` / `InvalidMaxJoinAmount(uint256 minAmount, uint256 maxAmount)` | 群最小加入量为零 / 非零最大加入量低于最小加入量 |
| `GroupAlreadyActivated(uint256 groupId)` / `GroupNotActive(uint256 groupId)` / `GroupNotExist(uint256 groupId)` | 重复激活 / 在未激活链群上操作 / 群身份不存在 |
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
| `ScoreCountExceeded(uint256 startIndex, uint256 count, uint256 memberCount)` | 验证批次越过该群成员总数 |
| `StartIndexMismatch(uint256 expected, uint256 actual)` | 验证批次跳跃、重复或乱序；`expected` 为该群当前已验证数量，`actual` 为调用者传入的 `startIndex` |
| `ZeroVerifyVotes(address tokenAddress, uint256 verifierId)` | 验证者没有有效治理票 |
| `NoActiveApplication(uint256 verifierId)` | 没有当前申请或申请已失效 |
| `VerifierNotRanked(uint256 verifierId, uint256 round)` / `VerifierNotOpen(uint256 verifierId, uint256 round)` | 未进入当轮排名 / 分割窗口未开 |
| `GroupVerificationAlreadyComplete(uint256 groupId, uint256 round)` | 已完成验证的群重复提交 |
| `VerifierAlreadyLocked(address tokenAddress, uint256 actionId, uint256 round)` | 锁定后更换验证者 |
| `UnknownSourceAction(address sourceTokenAddress, uint256 sourceActionId)` | 二次分配配置的源行动不是本 Executor 创建 |
| `RecipientArrayLengthMismatch(uint256 recipientIdsLength, uint256 ratiosLength, uint256 remarksLength)` | 二次分配三数组不等长 |
| `TooManyRecipients(uint256 count, uint256 maxCount)` / `ZeroRecipientRatio(uint256 recipientId)` / `DuplicateMemberId(uint256 memberId)` / `RecipientIsGroupId(uint256 groupId, uint256 recipientId)` | 接收人配置不合法 |
| `DistributionOverflow(uint256 configured, uint256 available)` | 配置比例总和超过 `1e18` 时拒绝；正好 `1e18` 合法 |
| `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` | 重复成员结算（Executor 层；行动级的重复铸造由 Mint 回滚 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`） |
| `MemberActionRewardUnavailable(tokenAddress, actionId, memberId, round)` | 成员结算无产出：`mintAmount` 与 `burnAmount` 均为 0（无有效参与、目标轮未完成验证或零分、行动激励为零）；有销毁量即允许结算，不置位已结算、不发事件 |
| `ActionNotCreated(tokenAddress, actionId)` | 行动尚未创建（`createdRound == 0`）：群激活、验证者申请与三个 Executor 的成员结算（含批量）都拒绝 |
| `RoundNotStarted(uint256 requiredRound, uint256 currentRound)` | 对应阶段的 Round 小于 1：`requiredRound` 恒为 1，`currentRound` 为推导出的 0 |
| `RoundBeforeActionCreated(uint256 round, uint256 createdRound)` | 成员结算的 `round` 早于行动创建轮（行动已存在），三个 Executor 一致 |
| `RoundAfterMintWindow(uint256 round, uint256 mintRound)` | 成员结算的 `round` 超过当前铸币轮（含铸币阶段未开始时的 `mintRound = 0`） |
| `NotQualified(address actionTokenAddress, uint256 round, uint256 memberId)` | 服务加入者既非社区激活群 owner，也没有该轮有效验证者申请 |
| `ActionTokenParentMismatch(address actionTokenAddress, address serviceTokenAddress, address actualParentTokenAddress)` | 服务代币不是行动代币，且行动代币的实际父币不是服务代币；载荷同时给出行动代币、服务代币与实际父币 |

Target Data 的项数、每项位置与编码由各 Executor 在自己的规格中固定，并在对应回调内自行校验，错误也声明在各自的 `Errors` 子接口；ActionTarget 只解析创建回调的第 `0` 项 executor。错误名自带字段，不复用「一个 `InvalidAddress` 覆盖多个字段」的写法：零地址按字段分别报 `Zero<Field>Address()`，比例按字段分别报 `Invalid<Field>(value)`，参与量按条件分别报 `ZeroParticipationAmount`/`BelowMinJoinAmount`/`WithdrawAmountExceeded`；结算轮次按轴分别报 `RoundBeforeActionCreated` 与 `RoundAfterMintWindow`，阶段未开始统一报 `RoundNotStarted(requiredRound, currentRound)`。以上错误均在对应外层交易中回滚。

验收见 [Action 验收](08-testing.md)。
