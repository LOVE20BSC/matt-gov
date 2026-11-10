# LP Executor

沿用旧 `LOVE20TKM/extension-lp/src/ExtensionLp.sol` 的聚合余额、时间扣减和历史查询，采用 V2 的 LP 准入规则；不部署旧业务工厂。BSC 新增部分撤回与全额撤回自动退出，不设退出等待；业务按 `tokenAddress + actionId` 隔离，参与主体为 MemberNFT。

## 配置与接口

部署依赖通过构造函数绑定，且只收 ActionTarget：Stake 经 `ActionTarget.VOTE_ADDRESS()` 的 `STAKE_ADDRESS()` 反查，MemberNFT、Phase 与 Pair Factory 再从 Stake 派生（`MEMBER_NFT_ADDRESS()`、`PHASE_ADDRESS()`、`PAIR_FACTORY_ADDRESS()`）。每个行动的配置由创建回调解析，不进入构造函数。

完整 ABI 见 [`ILpExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/ILpExecutor.sol)。

Target Data 是无键数组，按位置读取。第 `0` 项是 ActionTarget 保留的 executor，本 Executor 的项从第 `1` 项起固定为：`targetData[SLOT_LP_TOKEN] = abi.encode(address joinTokenAddress)`、`targetData[SLOT_GOV_RATIO_MULTIPLIER] = abi.encode(uint256 govRatioMultiplier)`、`targetData[SLOT_MIN_GOV_RATIO] = abi.encode(uint256 minGovRatio)`，项数必须为 `4`。项数、位置与校验均由本 Executor 负责，ActionTarget 只原样透传。创建回调成功时，本 Executor 在同一笔内发出 `LpActionCreated(tokenAddress, actionId, joinTokenAddress, govRatioMultiplier, minGovRatio)`，携带三项初始配置的全量；注册表事实由 ActionTarget 的 `ActionRegistered` 承担。LP 必须是已配置 Pair Factory 登记的交易对，V2 不要求交易对包含激励代币。两个治理比例使用 `1e18` 精度，`minGovRatio <= 1e18`。LP 无验证阶段，验证信息不迁移。

写操作要求调用者持有 memberId；加入/追加金额为正，首次加入满足 `minGovRatio`。LP 从调用者转入 Executor，撤回时转给当前持有人。首次加入时调用 `ActionTarget.registerJoinState`；全额撤回与 `exit` 都调用 `ActionTarget.clearJoinState`；失败全部回滚。激励接口见 [行动铸造](07-minting.md#铸造链路)。

**每次加入都重判行动归属**：`registerJoinState` 只在首次加入调用，后续 `join` 不再经过它，ActionTarget 的绑定校验因此不为再次加入兜底。若行动不是本 Executor 创建，非首次加入会跳过该回调，直接走到零地址 join token 的 `safeTransferFrom`，只靠 OpenZeppelin 的 `extcodesize` 检查偶然回滚。为此 `join` 在金额校验之后、`currentJoinRound()` 之前先判本 Executor 的创建记录：`createdRound == 0` 回滚 `ActionNotCreated(tokenAddress, actionId)`，首次与非首次加入一视同仁；该记录由创建回调一次写入且不删除，首次认定仍只读 `isJoined`，不自建副本。

**配置写入的唯一性由 ActionTarget 承担**：创建回调对同一 `(tokenAddress, actionId)` 只成功一次（重复回滚 `AlreadyCreated`），因此本 Executor 的 `joinTokenAddress`、比例等配置在每个行动上只写一次，不需要自己的「已配置」状态位。

校验与回滚：

构造函数没有重复初始化入口；ActionTarget、Stake 及从 Stake 派生的 MemberNFT、Phase、Pair Factory 有代码由 `DeployAction` 广播前校验；`21_check.sh` 回读 `STAKE_ADDRESS()`、`MEMBER_NFT_ADDRESS()`、`PHASE_ADDRESS()` 并与 core 地址文件复核，`PAIR_FACTORY_ADDRESS()` 与 Stake 的工厂地址一致。

| 条件 | 回滚错误 |
| --- | --- |
| `targetData` 项数少于 `TARGET_DATA_LENGTH`（`4`） | `InsufficientTargetDataItems(targetData.length, TARGET_DATA_LENGTH)` |
| `targetData` 项数多于 `TARGET_DATA_LENGTH`（`4`） | `TooManyTargetDataItems(targetData.length, TARGET_DATA_LENGTH)` |
| 第 `0`～`3` 项不是 32 字节 | `InvalidTargetDataShape(index, length)` |
| 投票回调 Target Data 超过保留的 executor 一项（无投票业务项） | `TooManyTargetDataItems(targetData.length, 1)` |
| `targetData[SLOT_LP_TOKEN]` 为零 | `ZeroJoinTokenAddress()` |
| `targetData[SLOT_LP_TOKEN]` 不是 `pairFactoryAddress` 登记的交易对 | `InvalidJoinTokenFactory(joinTokenAddress, pairFactoryAddress)` |
| `minGovRatio > 1e18` | `InvalidMinGovRatio(minGovRatio)` |
| 调用者不是 memberId 当前持有人（id 不存在时冒泡 `ERC721NonexistentToken`） | `NotMemberOwner(memberId)` |
| 加入金额为零，或撤回金额为零 | `ZeroParticipationAmount()` |
| 撤回金额大于当前余额 | `WithdrawAmountExceeded(amount, joined)` |
| 首次加入且 `govRatio < minGovRatio` | `InsufficientGovRatio(minGovRatio, govRatio)` |
| `exit` 时该成员没有加入记录 | `NotJoined(tokenAddress, actionId, memberId)` |
| 加入轮低于该行动创建轮 | `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)`（ActionTarget 抛出） |
| 行动未创建（`createdRound == 0`） | `ActionNotCreated(tokenAddress, actionId)`：`join` 在参数校验之后、轮次之前先判本 Executor 的创建记录；成员结算同判 |
| 结算轮次低于该行动创建轮（行动已创建） | `RoundBeforeActionCreated(round, createdRound)` |
| 结算轮次大于当前铸币轮（铸币阶段未开始时任何轮次都不在有效阶段） | `RoundAfterMintWindow(round, mintRound)` |
| 同一成员同一轮重复结算 | `RewardAlreadyMinted(tokenAddress, actionId, memberId, round)` |
| 非 ActionTarget 调用回调 | `NotActionTarget(caller)` |

加入轮的下界是该行动的创建轮（不小于 `1`），比按 Phase 推导的下界更严格：加入的下界由 ActionTarget 的 `JoinNotOpen` 承担，结算的下界由本 Executor 按创建轮校验。结算的第一段先判行动是否存在（`createdRound == 0` 回滚 `ActionNotCreated`），第二段才判轮次是否早于创建轮（`RoundBeforeActionCreated`），两段不合并。

## 时间权重

每笔加入按加入窗口所在 Phase（`Phase.phaseInfo(currentPhase())`）的起点和长度计算，并在加入时落账：

```text
deductionAdded = min(amount, floor(amount * elapsedJoinBlocks / joinPhaseBlocks))
effectiveAmount = joinedAmount - deduction
totalEffectiveAmount = joinedAmountByActionId - deductionByRound
effectiveLpRatio = floor(effectiveAmount * 1e18 / totalEffectiveAmount)
```

余额按 RoundHistory 继承，扣减只属于加入发生的 Round。跨轮持续参与时旧余额保留，新一轮扣减从 0 开始；追加只累加本次扣减。结算读取落账值，不用结算时的 Phase 参数重算。

## 部分撤回与退出

撤回只更新当前加入 Round，不能改已冻结历史；金额须满足 `0 < amount <= joinedAmount`，不设退出等待。

```text
deductionReduction = floor(deduction * amount / joinedAmount)
joinedAmount -= amount
joinedAmountByActionId -= amount
deduction -= deductionReduction
deductionByRound -= deductionReduction
```

所有右侧均使用撤回前值。减少成员扣减和总扣减的数量必须相同；全额撤回时公式自然取尽剩余扣减，不留余数。部分撤回保留原加入区块/金额数组作为记录，不逐笔缩放；数组之和不再代表当前余额。

全额撤回（`amount == joinedAmount`）与 `exit` 一样按退出处理：清空当前 Round 的上述数组与扣减、把该成员余额记录为零，调用 `ActionTarget.clearJoinState`，不删除过去 Round。事件按事实拆分：只要清仓路径执行（全额撤回或 `exit`），统一发两条——`LpWithdrawn(tokenAddress, actionId, memberId, round, amount)` 记录金额事实，`LpExited(tokenAddress, actionId, memberId, round)` 记录生命周期事实，`exit` 的 `LpWithdrawn.amount` 为本次返还金额；部分撤回只发 `LpWithdrawn`、不发 `LpExited`。加入态清理由 ActionTarget 的 `JoinStateCleared` 统一留痕。清仓顺序固定为：清自身状态 → 退款转账 → 发 `LpWithdrawn` → 回调 `ActionTarget.clearJoinState`（发 `JoinStateCleared(forced=false)`）→ 发 `LpExited`；`LpExited` 是无金额终态标记，必须最后发（见[事件规范 §4.4](../../event-standards.md#44-正常退出与注册表兜底清理)）。

**可用性依赖**：`clearJoinState` 内部读 `Phase.currentPhase()` 推导清理轮，因此全额撤回与 `exit` 这两个资金出口都依赖 Phase 可调用。Phase 故障时整笔回滚（原子性保证不会出现「钱已退、注册表未清」的半截状态），但成员暂时无法通过这两条路径取回资金；这是抵押/退出路径与注册表唯一所有者耦合的已知代价，登记而不改结构。

例（最小单位）：余额 7、扣减 3，撤回 2 后扣减减少 0，剩余余额 5、扣减 3；再 `exit` 取尽剩余扣减 3。

## 治理上限与分配

成员与社区治理票都在**铸造时按当前 Round** 读取：`Stake.validGovVotes(tokenAddress, currentPhase, memberId)` 与 `Stake.totalValidGovVotes(tokenAddress, currentPhase)`，其中 `currentPhase = IPhase.currentPhase()`。被结算的 `round`（`mintRound = currentPhase - 2`）不参与这张票权——旧版读的 `validGovVotes(tokenAddress, memberId)` / `globalGovVotes(tokenAddress)` 同样是当前值，口径不变。结果按被结算轮冻结在 `_mintedGovRatioByMemberId[tokenAddress][actionId][round][memberId]`：已铸造轮次的 `govRatio` 查询返回该记录，不再随质押变化；未铸造轮次（含尚未结算的过去轮）按当前 Round 现算，因此查询值与将来铸造时的取值同源。`MemberRewardMinted.round` 是本接口结算的业务轮（`currentPhase - 2`）；同一共享类在 GroupAction / Service 发射时是 `currentPhase - 3`，消费方按 emitter 选偏移（见[事件规范 §4.2](../../event-standards.md#42-共享事件类)）。

```text
theoreticalReward = floor(proposalReward * effectiveAmount / totalEffectiveAmount)
govRatio = floor(validGovVotes * 1e18 / totalValidGovVotes)
govRatioCap = floor(govRatio * govRatioMultiplier / 1e18)
mintReward = effectiveLpRatio <= govRatioCap
    ? theoreticalReward
    : floor(proposalReward * govRatioCap / 1e18)
burnReward = theoreticalReward - mintReward
```

`cap` 不生效时直接取 `theoreticalReward`；若改用截断后的 `effectiveLpRatio` 重算，可能少 1 个单位，把本应零销毁的结算变成 1 单位销毁。

乘数为 0 时关闭上限并返回理论激励；上限启用且总治理票为 0 时该成员理论激励全部销毁。未参与的轮次查询返回零。结算量为零（`mintAmount` 与 `burnAmount` 均为 0）时按成因三分：有效参与总量或行动激励为零（轮级）回滚 `MemberRewardPoolEmpty(tokenAddress, round)`；成员自身有效额为 0 回滚 `ZeroEffectiveJoinAmount(tokenAddress, actionId, memberId)`；分子非零但取整为零回滚 `MemberRewardRoundedToZero(tokenAddress, round, memberId)`。三者都不置位已结算、不发事件，不拉取整笔激励，可待行动激励就绪后重试；有销毁量即允许结算。销毁调用 Token.burn，不修改 Core 的取消预留账本。销毁量带成员归属，因此并入该成员 `MemberRewardMinted.burnAmount`，不单独立事件；纯销毁情形下 `mintAmount = 0` 而 `burnAmount > 0`，`minted` 仍为 true。

成员结算按 [统一铸造链路](07-minting.md#铸造链路) 进行：整笔预期数量读 `ActionTarget.actionReward`（未铸造时返回理论可铸造数量），大于零且未铸造时经 `ActionTarget.mintActionReward` 取得该整笔激励再内部分配；该轮有效参与总量（`joinedAmountByActionId - deductionByRound`）为零或预期数量为零时，成员结算无产出，回滚 `MemberRewardPoolEmpty(tokenAddress, round)`；成员自身有效额为 0 时回滚 `ZeroEffectiveJoinAmount(tokenAddress, actionId, memberId)`；分子非零但逐项取整为零时回滚 `MemberRewardRoundedToZero(tokenAddress, round, memberId)`（均不拉取整笔激励、不记已结算）。轮次已到铸币轮而有效参与总量仍为零时，该轮没有任何有效分配路径：结算一律回滚 `MemberRewardPoolEmpty(tokenAddress, round)`，整笔激励停留在未结算状态，预留不释放（没有销毁入口）。未到铸币轮的轮次结算回滚（见上表），查询返回零值。

来源：旧 `LOVE20TKM/extension-lp/src/ExtensionLp.sol`、`LOVE20TKM/extension-lp/src/ExtensionLpFactoryV2.sol` 和 `LOVE20TKM/extension/src/ExtensionBaseRewardTokenJoin.sol`。部分撤回、全额撤回自动退出与取消退出等待是 BSC 新增/变更，不声称旧 V2 已具备。验收见 [Action 验收](08-testing.md)。

## 状态口径

- `joinBlocksByMemberId` / `joinAmountsByMemberId` 是**加入流水**，不是余额分解：部分撤回不缩放、全额撤回不删除，数组之和不再等于当前余额，`deduction()` 的累计扣减可以超过单轮加入量。
- `deduction()` 的三个返回值不足以自校验（缺 `phaseStartBlock` / `phaseBlocks`），链下不得用它反推加入流水；需要逐笔核对时只能读两个日志数组。
- `memberReward` 把「行动未创建 / 轮次早于创建 / 超过铸币窗口 / 无有效参与」四种情形压成同一个 `(0, 0, false)`；需要区分原因时只能试算 `mintMemberReward` 的 revert。
- `totalEffectiveAmount == 0` 与「激励为零」都归 `MemberRewardPoolEmpty`，两者都不可通过重试解决；前者在铸币阶段到达后每次尝试都会重新枚举，成本可重复支付。
- 成员结算**有**销毁面：治理上限生效时 `burnAmount = theoreticalReward − mintAmount`，数量写入 `_burnedRewardByMemberId[tokenAddress][actionId][round][memberId]`，并在同一笔内调用行动代币的 `Token.burn`；`govRatioMultiplier = 0`（上限关闭）或 `cap` 未绑定该成员时为 `0`。纯销毁（`mintAmount = 0`、`burnAmount > 0`）仍置位已结算，`memberReward` 回该 `burnAmount`。没有销毁面的是 `GroupActionExecutor`（见 [销毁面](07-minting.md#销毁面)）。

## 错误卷补记（2026-11，X-09）

- `E-LP-02`：`govRatioMultiplier` 没有上界校验，安全性依赖 `Math.mulDiv` 不溢出：任意乘数只会放大分母、压低 `govRatio`，不会放大成员份额；链下不得假定乘数已被限制在某个范围。
- `E-LP-03`：`registerJoinState`（可回 `JoinNotOpen`）排在全部账本写入之后，整笔回滚保证无残留；这是「账本先写、状态后写」的自定义顺序，按此登记。
- `E-LP-04`：同一「无余额」状态在 `withdraw(amount > 0)` 报 `WithdrawAmountExceeded(amount, 0)`、在 `exit` 报 `NotJoined(...)`；两个入口语义不同（显式撤回 / 整体退出），保留双错误。
