# 行动铸造、事件与错误

## 铸造链路

```text
executor -> ActionTarget -> Mint -> ActionTarget -> executor
```

只有关联 Executor 可发起 ActionTarget 的铸造入口；ActionTarget 作为 Target 调用 Mint，取得指定 token、Round、Proposal 的完整激励并在同一交易全部转回 Executor，不留余额。Executor 再按所属业务完成成员、验证者和 owner 分配。任一步失败回滚，不允许重复铸造。

流转由两条事件分别留痕，粒度与所在层一致：ActionTarget 在整笔转出时发出**行动级**的 `ActionRewardMinted(tokenAddress, actionId, round, amount)`，`amount` 即 `mintProposalReward` 的返回值，与同层查询 `mintedProposalReward` 同源；各 Executor 在成员或角色结算时发出**成员级**的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)`。本轮该行动只能铸造一次（去重键为 `tokenAddress + actionId + round`）；成员不参与这条链路也不需要了解它，成员级入口只存在于各 Executor。

服务轮次没有可分配源行动时，使用 Executor 的 `burnRewardIfNeeded(serviceTokenAddress, serviceProposalId, round)` 专用入口；该入口只能处理已结束轮次，Executor 直接调用服务代币 `burn(amount)`，且重复调用无操作，销毁由 `RewardBurned` 留痕。这是全链路唯一的**无成员归属**销毁路径，因此 `RewardBurned` 只声明在 `IGroupServiceExecutorEvents`；成员归属的销毁并入 `MemberRewardMinted.burnAmount`，不单独立事件。

Core 的预留、铸造和取消额度账本见 [Mint](../core/07-mint.md)，不能把 Executor 内部转账再次计作 Core 铸造。

事件和错误定义分别见 [`IActionTarget.sol`](../../../interfaces/action/IActionTarget.sol)、[`IActionExecutor.sol`](../../../interfaces/action/IActionExecutor.sol)、[`ILpExecutor.sol`](../../../interfaces/action/ILpExecutor.sol)、[`IGroupActionExecutor.sol`](../../../interfaces/action/IGroupActionExecutor.sol) 和 [`IGroupServiceExecutor.sol`](../../../interfaces/action/IGroupServiceExecutor.sol)。每个接口只声明自身合约实际拥有的事件和错误：三个 Executor 共用且签名一致的 1 个事件（`MemberRewardMinted`）与 7 个错误（`AlreadyInitialized`、`UnauthorizedCallback`、`InvalidRound`、`RoundNotStarted`、`NotMemberOwner`、`ProposalNotVoted`、`RewardAlreadyMinted`）声明在基座 `IActionExecutor` 的子接口中，由三个 Executor 继承；`ActionRewardMinted` 只由 ActionTarget 发出，声明在 `IActionTargetEvents`，各 Executor 不声明。只被两家使用的成员（如 `InvalidParticipationAmount`）留在各自子接口，不上提基座。

事件按 BSC 业务主体使用 `memberId`；事件中的地址仅表示代币、合约或调用审计地址。行动级事件（`ActionCreated`、`ActionRewardMinted`、`RewardBurned`）不含 `memberId`，它们的主体是行动或服务提案本身。

| 错误 | 拒绝条件 |
| --- | --- |
| `AlreadyInitialized()` | Executor 的 `init` 被重复调用 |
| `InvalidExecutor()` | 零地址、EOA、无代码 Executor |
| `UnauthorizedCallback()` | 非 ActionTarget 调用 Executor 回调 |
| `UnauthorizedExecutor(tokenAddress, actionId)` | 调用者不是该 `(tokenAddress, actionId)` 已注册绑定的 Executor（含未注册绑定时的任何调用者） |
| `NotMemberOwner(memberId)` | 调用者非该 NFT 当前持有人 |
| `ProposalNotVoted(tokenAddress, proposalId)` | Proposal 无票或未达门槛 |
| `InvalidRound(round)` | Round 已开始但不在对应操作的有效阶段 |
| `RoundNotStarted()` | 对应阶段的 Round 小于 1 |
| `InsufficientExperienceQuota(providerMemberId, required, available)` | 体验额度不足 |
| `VerifierAlreadyLocked(tokenAddress, actionId, round)` | 锁定后更换验证者 |
| `BatchIndexMismatch(expected, actual)` | 验证批次跳跃、重复或乱序 |
| `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` | 重复成员结算（Executor 层）；ActionTarget 层的行动级去重是 `AlreadyMinted(tokenAddress, actionId, round)` |
| `DistributionOverflow(configured, available)` | 配置比例总和超过 `1e18` 时拒绝；正好 `1e18` 合法 |

Target Data 的项数、每项位置与编码由各 Executor 在自己的规格中固定，并在对应回调内自行校验，错误也声明在各自的 `Errors` 子接口；ActionTarget 只解析创建回调的第 `0` 项 executor。`InvalidParticipationAmount` 拒绝零值或超出配置范围的参与量；`InvalidCandidate` 拒绝候选人或申请版本无效；`InvalidSplits` 拒绝分割线不严格递增或超出范围；`ApplicationNotActive` 拒绝使用已失效申请。以上错误均在对应外层交易中回滚。

验收见 [Action 验收](08-testing.md)。
