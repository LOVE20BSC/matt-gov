# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口 `mintActionReward`；ActionTarget 作为 Target 调用 Mint 时把该 Executor 作为 `recipient` 传入，Mint 直接把指定 token、Round、Proposal 的完整激励铸给 Executor——激励不落在 ActionTarget，没有「先铸给自己、再转一次」的转发，也没有中转余额需要清理。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复铸造。铸造去重由 Mint 持有：ActionTarget 不保存行动级铸造状态位，重复调用由 Mint 回滚 `AlreadyMinted()`（Mint 是 init 固定的可信依赖、`LOVE20Token.mint` 无回调，外呼不可重入）。

流转由两条事件分别留痕，粒度与所在层一致：ActionTarget 在整笔转出时发出**行动级**的 `ActionRewardMinted(tokenAddress, actionId, round, amount)`，`amount` 即 `mintActionReward` 的返回值，与同层查询 `actionReward` 同源；各 Executor 在成员或角色结算时发出**成员级**的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)`。本轮该行动只能铸造一次（去重键 `tokenAddress + actionId + round`，由 Mint 的状态位判定）；成员不参与这条链路也不需要了解它，成员级入口只存在于各 Executor。成员结算量为零（`mintAmount` 与 `burnAmount` 均为 0）时回滚 `NoRewardAvailable`，不置位已结算状态、不发事件，与 Core 铸造的零额拒绝同口径；有销毁量即允许结算。

成员级结算支持批量：`mintMemberRewards(tokenAddress, actionIds[], memberId, rounds[])` 以平行数组按下标配对，逐元素执行与 `mintMemberReward` 相同的结算，返回按下标对齐的 `(mintAmounts[], burnAmounts[])`。两数组长度不一致回滚 `BatchLengthMismatch(actionIdsLength, roundsLength)`；任一元素失败整笔回滚（下标对齐、不补空）；空数组在鉴权通过后返回空结果、不改状态；不设长度上限——成本由调用方自付，区块 gas 为自然上界（与 core `mintGovRewards` 同型）。批量入口同样先鉴权，权限与单条入口一致，由各 Executor 规格固定。

行动级整笔激励无法分配（判据由各 Executor 规格固定，如无可分配源行动、全部验证失败）时，**全链路没有销毁路径**：Mint 只支付、ActionTarget 只路由，两者都不判断「该不该作废」，各 Executor 也不提供销毁入口。该轮激励因此永久停留在未结算状态——`ActionTarget.actionReward` 一直返回 `(理论数量, false)`，Mint 的 `rewardReserved` 不释放，后续轮次的 `rewardAvailable` 相应被压低，代币永不铸出。这是有意的取舍：不可分配意味着「本轮没有任何有效分配路径」，属于罕见情形；少发比「误判并销毁本该发给成员的激励」安全，而销毁入口本身是一条 permissionless 的状态变更路径。成员归属的销毁并入 `MemberRewardMinted.burnAmount`，与此无关。

Core 的预留、铸造和取消额度账本见 [Mint](../core/07-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

事件和错误定义分别见 [`IActionTarget.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionTarget.sol)、[`IActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionExecutor.sol)、[`ILpExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/ILpExecutor.sol)、[`IGroupActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionExecutor.sol) 与按业务模块拆分的 [`IGroupActionVerify.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionVerify.sol)、[`IGroupActionJoin.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionJoin.sol)、[`IGroupActionManager.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionManager.sol)、[`IGroupActionIndexes.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionIndexes.sol)、[`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol) 和 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)。每个接口只声明自身合约实际拥有的事件和错误：三个 Executor 共用且签名一致的 1 个事件（`MemberRewardMinted`）与 10 个错误（`AlreadyInitialized`、`UnauthorizedCallback`、`InvalidRound`、`RoundNotStarted`、`ActionNotCreated`、`NotMemberOwner`、`ProposalNotVoted`、`RewardAlreadyMinted`、`NoRewardAvailable`、`BatchLengthMismatch`）声明在基座 `IActionExecutor` 的子接口中，由三个 Executor 继承；`ActionRewardMinted` 只由 ActionTarget 发出，声明在 `IActionTargetEvents`，各 Executor 不声明。跨模块共用的错误（如 `InvalidParticipationAmount` 只由加入与额度使用，留在 `IGroupActionJoinErrors`；创建回调与投票回调用到的 `InvalidTargetDataLength` 留在 Executor 自身的错误子接口），不上提基座；`ActionNotCreated` 被三个 Executor 与链群管理、验证者申请共用，按同签名共用规则声明在基座。

事件按 BSC 业务主体使用 `memberId`；事件中的地址仅表示代币、合约或调用审计地址。行动级事件（`ActionCreated`、`ActionRewardMinted`）不含 `memberId`，它们的主体是行动或服务提案本身。

| 错误 | 拒绝条件 |
| --- | --- |
| `AlreadyInitialized()` | Executor 或 ActionTarget 的 `init` 被重复调用 |
| `InvalidAddress()` | ActionTarget 的 `init` 依赖地址为零 |
| `UnauthorizedCallback()` | 非授权调用者触发回调：ActionTarget 的三类回调仅 Submit/Vote 可调，Executor 的三类回调仅 ActionTarget 可调 |
| `UnboundProposal(tokenAddress, proposalId)` | ActionTarget 的推举/投票回调对应的 `(tokenAddress, proposalId)` 无绑定（结构上不可达，防御 Core 侧缺陷） |
| `UnauthorizedExecutor(tokenAddress, actionId)` | 调用者不是该 `(tokenAddress, actionId)` 已注册绑定的 Executor（含未注册绑定时的任何调用者） |
| `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)` | 注册加入时当前投票轮不大于该行动创建轮（投票轮未走完，加入未开放） |
| `NotMemberOwner(memberId)` | 调用者非该 NFT 当前持有人 |
| `ProposalNotVoted(tokenAddress, proposalId)` | Proposal 无票或未达门槛 |
| `InvalidExecutor()` | 零地址、EOA、无代码 Executor |
| `AlreadyCreated(tokenAddress, actionId)` | 同一 `(tokenAddress, actionId)` 的重复创建回调 |
| `InvalidRound(round)` | Round 已开始但不在对应操作的有效阶段（成员结算中即 `round` 超过当前铸币轮） |
| `ActionNotCreated(tokenAddress, actionId)` | 行动尚未创建（`createdRound == 0`）：群激活、验证者申请与三个 Executor 的成员结算（含批量）都拒绝；成员结算里这是唯一归它的条件，`round` 早于创建轮另见 `RoundNotStarted()` |
| `RoundNotStarted()` | 对应阶段的 Round 小于 1；成员结算中 `round` 早于行动创建轮（行动已存在）同样报此错误——三个 Executor 保持一致，不改用 `InvalidRound(round)`。行动不存在（`createdRound == 0`）不归这条，走 `ActionNotCreated` |
| `InsufficientProviderQuota(providerId, required, available)` | Provider 额度不足 |
| `GroupNotActive()` | 在未激活链群上执行群管理操作（停用、更新配置） |
| `VerifierAlreadyLocked(tokenAddress, actionId, round)` | 锁定后更换验证者 |
| `StartIndexMismatch(expected, actual)` | 验证批次跳跃、重复或乱序；`expected` 为该群当前已验证数量，`actual` 为调用者传入的 `startIndex` |
| `VerificationBatchTooLarge()` | 验证批次项数超过协议级上界 100（对应常量 `MAX_VERIFICATION_BATCH`） |
| `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` | 重复成员结算（Executor 层；行动级的重复铸造由 Mint 回滚 `AlreadyMinted()`） |
| `NoRewardAvailable()` | 成员结算无产出：`mintAmount` 与 `burnAmount` 均为 0（无有效参与、目标轮未完成验证或零分、行动激励为零）；有销毁量即允许结算，不置位已结算、不发事件 |
| `DistributionOverflow(configured, available)` | 配置比例总和超过 `1e18` 时拒绝；正好 `1e18` 合法 |

Target Data 的项数、每项位置与编码由各 Executor 在自己的规格中固定，并在对应回调内自行校验，错误也声明在各自的 `Errors` 子接口；ActionTarget 只解析创建回调的第 `0` 项 executor。`InvalidParticipationAmount` 拒绝零值或超出配置范围的参与量；`InvalidCandidate` 拒绝候选身份无效、未进入排名或分割窗口未开；`InvalidSplits` 拒绝分割线不严格递增或超出范围；`InvalidRatio` 拒绝创建回调中比例（`maxJoinAmountRatio`、`activationMinGovRatio`、`ratioForPublicVerifier`）超出 `1e18`；`ApplicationNotActive` 拒绝没有当前申请或申请已失效；`InvalidTargetDataLength` 拒绝 Target Data 项数超出约定；`VerificationInfoLengthMismatch` 拒绝验证信息 schema 两数组不等长或成员值项数与 schema 不符；`GroupNotActive` 拒绝在未激活链群上执行群管理操作，加入类操作改由 `CannotJoinInactiveGroup` 拒绝。以上错误均在对应外层交易中回滚。

验收见 [Action 验收](08-testing.md)。
