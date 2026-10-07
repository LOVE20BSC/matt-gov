# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> ActionTarget -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口 `mintActionReward`；ActionTarget 作为 Target 调用 Mint，取得指定 token、Round、Proposal 的完整激励并在同一交易全部转回 Executor，不留余额。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复铸造。去重状态位在 Mint 外呼之后写入：Mint 是 init 固定的可信依赖、`LOVE20Token.mint` 无回调，外呼不可重入，先铸后记安全。

流转由两条事件分别留痕，粒度与所在层一致：ActionTarget 在整笔转出时发出**行动级**的 `ActionRewardMinted(tokenAddress, actionId, round, amount)`，`amount` 即 `mintActionReward` 的返回值，与同层查询 `actionReward` 同源；各 Executor 在成员或角色结算时发出**成员级**的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)`。本轮该行动只能铸造一次（去重键为 `tokenAddress + actionId + round`）；成员不参与这条链路也不需要了解它，成员级入口只存在于各 Executor。

成员级结算支持批量：`mintMemberRewards(tokenAddress, actionIds[], memberId, rounds[])` 以平行数组按下标配对，逐元素执行与 `mintMemberReward` 相同的结算，返回按下标对齐的 `(mintAmounts[], burnAmounts[])`。两数组长度不一致回滚 `BatchLengthMismatch(actionIdsLength, roundsLength)`；任一元素失败整笔回滚（下标对齐、不补空）；空数组返回空结果、不改状态；不设长度上限——成本由调用方自付，区块 gas 为自然上界（与 core `mintGovRewards` 同型）。调用权限与单条入口一致，由各 Executor 规格固定。

行动级整笔激励无法分配（判据由各 Executor 规格固定，如无可分配源行动、全部验证失败）时，销毁链路为「Executor 判据 → ActionTarget 调 Mint 核销预留」：此类行动的 Executor 不触发 `mintActionReward`，激励停留在 Mint 的预留账本；任意地址触发 `ActionTarget.burnRewardIfNeeded(tokenAddress, actionId, round)`（permissionless，通常由 Executor 自身发起，未绑定行动无操作）后，ActionTarget 依次校验已结束轮次（否则回滚 `InvalidRound(round)`）与该轮未铸造且激励非零（读取 Mint 的 `proposalRewardByProposalId`，已铸造或零额无操作），再经 `IActionExecutor.needBurnReward(tokenAddress, actionId, round)` 取得业务判据，为真则调用 Mint 的 `burnUnmintedProposalReward(tokenAddress, round, proposalId)` 核销该行动本轮预留激励——标记该 Proposal 已结算（此后铸造回滚）、`rewardBurned` 累计、Mint 以 `RewardBurned(tokenAddress, round, amount, proposalRewardUnallocatable)` 留痕；ActionTarget 以同层 `RewardBurned(tokenAddress, actionId, round, amount)` 与 `burnInfo(tokenAddress, actionId, round)`（未销毁与未关联返回 `(0, false)` 不回滚）供查询。这是全链路唯一**无成员归属**的销毁路径；成员归属的销毁并入 `MemberRewardMinted.burnAmount`，不单独立事件。

Core 的预留、铸造和取消额度账本见 [Mint](../core/07-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

事件和错误定义分别见 [`IActionTarget.sol`](../../../interfaces/action/IActionTarget.sol)、[`IActionExecutor.sol`](../../../interfaces/action/IActionExecutor.sol)、[`ILpExecutor.sol`](../../../interfaces/action/ILpExecutor.sol)、[`IGroupActionExecutor.sol`](../../../interfaces/action/IGroupActionExecutor.sol) 与按业务模块拆分的 [`IGroupActionVerify.sol`](../../../interfaces/action/IGroupActionVerify.sol)、[`IGroupActionJoin.sol`](../../../interfaces/action/IGroupActionJoin.sol)、[`IGroupActionManager.sol`](../../../interfaces/action/IGroupActionManager.sol)、[`IGroupActionIndexes.sol`](../../../interfaces/action/IGroupActionIndexes.sol) 和 [`IGroupServiceExecutor.sol`](../../../interfaces/action/IGroupServiceExecutor.sol)。每个接口只声明自身合约实际拥有的事件和错误：三个 Executor 共用且签名一致的 1 个事件（`MemberRewardMinted`）与 8 个错误（`AlreadyInitialized`、`UnauthorizedCallback`、`InvalidRound`、`RoundNotStarted`、`NotMemberOwner`、`ProposalNotVoted`、`RewardAlreadyMinted`、`BatchLengthMismatch`）声明在基座 `IActionExecutor` 的子接口中，由三个 Executor 继承；`ActionRewardMinted` 与 `RewardBurned` 只由 ActionTarget 发出，声明在 `IActionTargetEvents`，各 Executor 不声明。跨模块共用的错误（如 `InvalidParticipationAmount` 只由加入与额度使用，留在 `IGroupActionJoinErrors`；创建回调与投票回调用到的 `InvalidTargetDataLength` 留在 Executor 自身的错误子接口），不上提基座。

事件按 BSC 业务主体使用 `memberId`；事件中的地址仅表示代币、合约或调用审计地址。行动级事件（`ActionCreated`、`ActionRewardMinted`、`RewardBurned`）不含 `memberId`，它们的主体是行动或服务提案本身。

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
| `AlreadyMinted(tokenAddress, actionId, round)` | 同一行动同一轮重复铸造（ActionTarget 行动级去重，独立状态位判定） |
| `TransferFailed(tokenAddress, to, amount)` | ActionTarget 向 Executor 转出整笔激励失败 |
| `InvalidRound(round)` | Round 已开始但不在对应操作的有效阶段 |
| `RoundNotStarted()` | 对应阶段的 Round 小于 1 |
| `InsufficientProviderQuota(providerId, required, available)` | Provider 额度不足 |
| `GroupNotActive()` | 在未激活链群上执行群管理操作（停用、更新配置） |
| `VerifierAlreadyLocked(tokenAddress, actionId, round)` | 锁定后更换验证者 |
| `StartIndexMismatch(expected, actual)` | 验证批次跳跃、重复或乱序；`expected` 为该群当前已验证数量，`actual` 为调用者传入的 `startIndex` |
| `VerificationBatchTooLarge()` | 验证批次项数超过协议级上界 100（对应常量 `MAX_VERIFICATION_BATCH`） |
| `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` | 重复成员结算（Executor 层；ActionTarget 层见 `AlreadyMinted` 行） |
| `DistributionOverflow(configured, available)` | 配置比例总和超过 `1e18` 时拒绝；正好 `1e18` 合法 |

Target Data 的项数、每项位置与编码由各 Executor 在自己的规格中固定，并在对应回调内自行校验，错误也声明在各自的 `Errors` 子接口；ActionTarget 只解析创建回调的第 `0` 项 executor。`InvalidParticipationAmount` 拒绝零值或超出配置范围的参与量；`InvalidCandidate` 拒绝候选人或申请版本无效；`InvalidSplits` 拒绝分割线不严格递增或超出范围；`InvalidRatio` 拒绝创建回调中 `maxJoinAmountRatio` 或 `activationMinGovRatio` 超出 `1e18`；`ApplicationNotActive` 拒绝使用已失效申请；`InvalidTargetDataLength` 拒绝 Target Data 项数超出约定；`VerificationInfoLengthMismatch` 拒绝验证信息 schema 两数组不等长或成员值项数与 schema 不符；`GroupNotActive` 拒绝在未激活链群上执行群管理操作，加入类操作改由 `CannotJoinInactiveGroup` 拒绝。以上错误均在对应外层交易中回滚。

验收见 [Action 验收](08-testing.md)。
