# LP Executor

沿用旧 `LOVE20TKM/extension-lp/src/ExtensionLp.sol` 的聚合余额、时间扣减和历史查询，采用 V2 的 LP 准入规则；不部署旧业务工厂。BSC 新增部分撤回与全额撤回自动退出，不设退出等待；业务按 `tokenAddress + actionId` 隔离，参与主体为 MemberNFT。

## 配置与接口

部署依赖通过一次性 `init` 绑定；每个行动的配置由创建回调解析，不能放进共享合约的全局 init。

完整 ABI 见 [`ILpExecutor.sol`](../../../interfaces/action/ILpExecutor.sol)。

Target Data 是无键数组，按位置读取。第 `0` 项是 ActionTarget 保留的 executor，本 Executor 的项从第 `1` 项起固定为：`targetData[1] = abi.encode(address joinTokenAddress)`、`targetData[2] = abi.encode(uint256 govRatioMultiplier)`、`targetData[3] = abi.encode(uint256 minGovRatio)`，项数必须为 `4`。项数、位置与校验均由本 Executor 负责，ActionTarget 只原样透传。LP 必须是已配置 Pair Factory 登记的交易对，V2 不要求交易对包含激励代币。两个治理比例使用 `1e18` 精度，`minGovRatio <= 1e18`。LP 无验证阶段，验证信息不迁移。

写操作要求调用者持有 memberId；加入/追加金额为正，首次加入满足 `minGovRatio`。LP 从调用者转入 Executor，撤回时转给当前持有人。首次加入时调用 `ActionTarget.registerJoinState`；全额撤回与 `exit` 都调用 `ActionTarget.clearJoinState`；失败全部回滚。激励接口见 [行动铸造](07-minting.md#铸造链路)。

校验与回滚：

| 条件 | 回滚错误 |
| --- | --- |
| `init` 任一依赖地址为零 | `InvalidAddress()` |
| `targetData` 项数不是 `4` | `InvalidTargetDataLength()` |
| 投票回调 Target Data 超过保留的 executor 一项（无投票业务项） | `InvalidTargetDataLength()` |
| `targetData[1]` 为零 | `InvalidJoinTokenAddress()` |
| `targetData[1]` 不是 `pairFactoryAddress` 登记的交易对 | `InvalidJoinTokenFactory()` |
| `minGovRatio > 1e18` | `InvalidMinGovRatio()` |
| 调用者不是 memberId 当前持有人 | `NotMemberOwner(memberId)` |
| 加入金额为零，或撤回金额为零、大于当前余额 | `InvalidParticipationAmount()` |
| 首次加入且 `govRatio < minGovRatio` | `InsufficientGovRatio()` |
| `exit` 时该成员没有加入记录 | `NotJoined()` |
| 加入轮低于该行动创建轮 | `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)`（ActionTarget 抛出） |
| 结算轮次低于该行动创建轮 | `RoundNotStarted()` |
| 结算轮次大于当前铸币轮（铸币阶段未开始时任何轮次都不在有效阶段） | `InvalidRound(round)` |
| 同一成员同一轮重复结算 | `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` |
| 非 ActionTarget 调用回调 | `UnauthorizedCallback()` |

行动轮次的下界是该行动的创建轮（不小于 `1`），比按 Phase 推导的下界更严格：加入的下界由 ActionTarget 的 `JoinNotOpen` 承担，结算的下界由本 Executor 按创建轮校验。

## 时间权重

每笔加入按加入窗口所在 Phase（`Phase.phaseInfo(currentPhase())`）的起点和长度计算，并在加入时落账：

```text
deductionAdded = min(amount, floor(amount * elapsedJoinBlocks / joinPhaseBlocks))
effectiveAmount = joinedAmount - deduction
totalEffectiveAmount = totalJoinedAmount - totalDeduction
effectiveLpRatio = floor(effectiveAmount * 1e18 / totalEffectiveAmount)
```

余额按 RoundHistory 继承，扣减只属于加入发生的 Round。跨轮持续参与时旧余额保留，新一轮扣减从 0 开始；追加只累加本次扣减。结算读取落账值，不用结算时的 Phase 参数重算。

## 部分撤回与退出

撤回只更新当前加入 Round，不能改已冻结历史；金额须满足 `0 < amount <= joinedAmount`，不设退出等待。

```text
deductionReduction = floor(deduction * amount / joinedAmount)
joinedAmount -= amount
totalJoinedAmount -= amount
deduction -= deductionReduction
totalDeduction -= deductionReduction
```

所有右侧均使用撤回前值。减少成员扣减和总扣减的数量必须相同；全额撤回时公式自然取尽剩余扣减，不留余数。部分撤回保留原加入区块/金额数组作为记录，不逐笔缩放；数组之和不再代表当前余额。

全额撤回（`amount == joinedAmount`）与 `exit` 一样按退出处理：清空当前 Round 的上述数组与扣减、把该成员余额记录为零，调用 `ActionTarget.clearJoinState`，不删除过去 Round。事件按入口区分：撤回发 `Withdrawn`，`exit` 发 `Exited`；加入态清理由 ActionTarget 的 `JoinStateCleared` 统一留痕。

例（最小单位）：余额 7、扣减 3，撤回 2 后扣减减少 0，剩余余额 5、扣减 3；再 `exit` 取尽剩余扣减 3。

## 治理上限与分配

成员与社区治理票均在铸造时读取 `Stake.validGovVotes(tokenAddress, memberId)` 和 `Stake.globalGovVotes(tokenAddress)`。已铸造轮次的 `govRatio` 返回当时记录，不受后续质押变化影响。

```text
theoreticalReward = floor(proposalReward * effectiveLpRatio / 1e18)
govRatio = floor(validGovVotes * 1e18 / totalGovVotes)
govRatioCap = floor(govRatio * govRatioMultiplier / 1e18)
mintReward = floor(proposalReward * min(effectiveLpRatio, govRatioCap) / 1e18)
burnReward = theoreticalReward - mintReward
```

先处理零值：无有效参与量时成员激励为零；乘数为 0 时关闭上限并返回理论激励；上限启用且总治理票为 0 时该成员理论激励全部销毁。未参与的轮次查询返回零。销毁调用 Token.burn，不修改 Core 的取消预留账本。销毁量带成员归属，因此并入该成员 `MemberRewardMinted.burnAmount`，不单独立事件；纯销毁情形下 `mintAmount = 0` 而 `burnAmount > 0`，`minted` 仍为 true。

成员结算按 [统一铸造链路](07-minting.md#铸造链路) 进行：整笔预期数量读 `ActionTarget.actionReward`（未铸造时返回理论可铸造数量），大于零且未铸造时经 `ActionTarget.mintActionReward` 取得该整笔激励再内部分配；该轮有效参与总量（`totalJoinedAmount - totalDeduction`）为零或预期数量为零时，成员结算返回零值并记为已结算，不拉取整笔激励。`needBurnReward` 仅在轮次已到铸币轮且有效参与总量为零时返回真，由 `ActionTarget.burnRewardIfNeeded` 核销预留。未到铸币轮的轮次结算回滚（见上表），查询返回零值。

来源：旧 `LOVE20TKM/extension-lp/src/ExtensionLp.sol`、`LOVE20TKM/extension-lp/src/ExtensionLpFactoryV2.sol` 和 `LOVE20TKM/extension/src/ExtensionBaseRewardTokenJoin.sol`。部分撤回、全额撤回自动退出与取消退出等待是 BSC 新增/变更，不声称旧 V2 已具备。验收见 [Action 验收](08-testing.md)。
