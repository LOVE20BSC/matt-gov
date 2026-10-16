# GroupService Executor

服务 Proposal 的代币为 `serviceTokenAddress`，面向整个 `actionTokenAddress` 社区的 GroupAction，不绑定单个源 actionId。两者必须相同，或服务代币是行动代币的直接父币；其他关系在创建时拒绝。服务 Proposal 绑定本 Executor，其 Proposal ID 在 Action 层统一以 `serviceActionId` 称呼（Action ID 别名）。

阶段和源行动查询见 [服务验证复用](02-phase-model.md#服务验证复用)。分母统计 `actionTokenAddress` 社区本轮全部 GroupAction 的行动层激励：按 `votedActions(actionTokenAddress, round)` 枚举本轮有票行动（规模上界由每轮提案上界保证，见 [ActionTarget](01-action-target.md)），过滤 `executor == groupActionExecutorAddress` 后逐个行动求和。行动层查询自带验证与激励条件，未完成验证或无公共验证者的行动整轮返回 0，GroupService 不重复筛选。服务 Proposal 本轮没有可铸造激励时，由 Mint 的内部 Round 准备逻辑决定为零，Executor 不重复判断原因，owner 和公共验证者激励均为零。

## 权重

| 符号 | 含义 |
| --- | --- |
| `A[a]` | 源 GroupAction a 的行动层分配总额，等于其全部链群成员激励之和 |
| `r` / `RATIO_FOR_PUBLIC_VERIFIER` | 服务 Proposal 绑定的公共验证者比例，`1e18` 精度；各源行动统一取该值（不再由候选在申请时自报） |
| `totalGroupActionReward` | `actionTokenAddress` 社区本轮全部 GroupAction 的 `A[a]` 之和，首次成功结算时冻结为本服务轮次分母 |
| `publicVerifierId[a]` | 行动 a 在目标轮锁定的公共验证者 memberId |
| `m` | 结算主体 memberId；作为群 owner 时也是 groupId |
| `groupReward(a, m)` | Group m 在行动 a 的成员激励总和；与 `A[a]`、`D` 同源，来自同一本冻结账 |
| `serviceReward` | 本服务 Proposal 的整笔激励 |

```text
A[a] = Σ_{g ∈ groupIds(actionTokenAddress, a, round)} generatedActionRewardByGroupId(actionTokenAddress, a, round, g)
D    = Σ_a A[a]                                                          // 首次成功结算时按 actionTokenAddress + round 冻结

verifierWeightNumerator(m) = Σ_{a: lockedVerifierId(actionTokenAddress, a, round) == m} A[a]
ownerWeightNumerator(m)    = Σ_a groupReward(a, m)

theoreticalVerifierReward(m) = mulDiv(serviceReward, r * verifierWeightNumerator(m), D * 1e18)
theoreticalOwnerReward(m)    = mulDiv(serviceReward, (1e18 - r) * ownerWeightNumerator(m), D * 1e18)
```

`generatedActionRewardByGroupId` 对未完成验证或无参与的行动返回 0，`lockedVerifierId` 只在该行动的目标轮存在锁定验证者时非零；每个行动只在其创建轮产出参与与激励，`votedActions` 入榜的行动即该轮创建的行动，跨轮行动天然不计入。理论金额使用同一组不提前截断的分子与分母（`Math.mulDiv`）。

首次成功结算某服务轮次时，按 `actionTokenAddress + round` 冻结整本奖励账：分母 `D`、每个行动的 `A[a]`、以及每个群在行动内的切片 `groupReward(a, g)`。查询不能写状态，未冻结时按实时账本只计算返回，后续结算一律读取冻结值，包括被冻结为零的项——零值同样不再回读实时账本。分子与分母因此始终同源：owner 权重按 `groupReward` 冻结值汇总，验证者权重按 `A[a]` 冻结值汇总，冻结后账本再变动也不会把同一笔服务激励二次分配。冻结在结算读取之前写入，零额回滚时随交易一并撤销；销毁路径不写状态；`needBurnReward` 每次按需计算。冻结账本与分母缓存是内部状态，不属于对外 ABI。

完整 ABI 见 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)（继承 [`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol) 的二次分配配置面）。

创建 Target Data 从第 `1` 项起（第 `0` 项是 ActionTarget 保留的 executor）固定为 `targetData[1] = abi.encode(address actionTokenAddress)`、`targetData[2] = abi.encode(uint256 govRatioMultiplier)` 和 `targetData[3] = abi.encode(uint256 ratioForPublicVerifier)`，项数恰为 `4`；超出回滚 `InvalidTargetDataLength`，`ratioForPublicVerifier > 1e18` 回滚 `InvalidRatio`（否则 `1e18 - r` 下溢），代币关系不满足回滚 `InvalidParentToken`。`ACTION_TOKEN_ADDRESS`、`GOV_RATIO_MULTIPLIER`、`RATIO_FOR_PUBLIC_VERIFIER` 均按 `serviceTokenAddress + serviceActionId` 读取。投票回调没有业务项，`targetData.length > 1` 回滚 `InvalidTargetDataLength`。

`init(actionTargetAddress, stakeAddress, groupActionExecutorAddress)` 只收 ActionTarget、Stake 和 GroupAction Executor：`memberNFTAddress`、`phaseAddress`、`launchAddress` 在 init 内从 `stakeAddress` 的 getter 读取一次并缓存，任一为零回滚 `InvalidAddress`；激励经 `ActionTarget` 读取，不注入 Mint。

**加入与退出**：`join(serviceTokenAddress, serviceActionId, memberId)` 校验当前 NFT 持有人，资格为两类之一——该成员（自身作为链群主体）在 `actionTokenAddress` 社区存在激活行动，以 GroupAction Executor 的 `hasActiveGroups(actionTokenAddress, memberId)` 一次判定；或在该服务轮的社区行动集（与分母枚举同源）中存在有效公共验证者竞选申请，逐个读 `verifierApplication(actionTokenAddress, actionId, memberId)` 的 `applicationId != 0`（无申请返回零值结构体、不回滚）。满足其一即可，不要求该轮已选出公共验证者；均不满足回滚 `NoActiveGroups`。重复 `join` 回滚 `AlreadyJoined`，未加入 `exit` 回滚 `NotJoined`。服务资格按轮快照由 ActionTarget 持有：`joinInfo(serviceTokenAddress, serviceActionId, round, memberId)` 转发 `isJoinedByRound`、返回该轮快照是否已加入，Executor 不自建副本；退出只写当时轮快照，不追回已发生轮。共同准备/铸造/销毁 ABI 见 [行动铸造](07-minting.md#铸造链路)。

基座 `joinedAmount` 族代理社区激活质押：`joinedAmount(serviceTokenAddress, serviceActionId, round)` 返回 `totalStaked(actionTokenAddress)`（`round > currentJoinRound()` 返回 0），`joinedAmountByMemberId(serviceTokenAddress, serviceActionId, round, memberId)` 返回 `totalStakedByMemberId(actionTokenAddress, memberId)`，`joinedAmountTokenAddress(serviceTokenAddress, serviceActionId)` 返回 `ACTION_TOKEN_ADDRESS(serviceTokenAddress, serviceActionId)`；社区激活质押为当前值，没有按轮历史。

[组织验收](../../acceptance.md#groupservice-结算) 还要求：只有本轮加入服务 Proposal 的群 owner/候选 MemberNFT 可按人结算，未加入角色份额不重分配。每个角色先检查自己的分子，为零只跳过该角色，不影响同一 memberId 的另一角色；两个分子都为零时不读取分母，视图返回全零，结算入口按零额规则回滚 `NoRewardAvailable`（见 [统一链路](07-minting.md#铸造链路)）。`totalGroupActionReward == 0` 时，任何地址可在轮次结束后调用 `burnRewardIfNeeded(serviceTokenAddress, serviceActionId, round)` 销毁整笔服务激励（`needBurnReward` 与 GroupAction 同型：轮次不等于 `createdRound` 或超过 `currentMintRound()` 时返回 false，否则返回 `D == 0`），销毁由 `IActionTargetEvents.RewardBurned(tokenAddress, actionId, round, amount)` 留痕。

## 治理上限

只约束群 owner，公共验证者按实际验证工作量直接获得权重激励，不受该上限影响。owner 超出上限的部分销毁，不转给其他 owner 或验证者：

```text
W(m)   = (1e18 - r) * ownerWeightNumerator(m)                            // 不提前取整
govRatio(m) = globalGovVotes == 0 ? 0 : mulDiv(validGovVotes(actionTokenAddress, m), 1e18, globalGovVotes)
cap(m)      = multiplier == 0 ? 上限关闭 : mulDiv(govRatio(m), multiplier, 1e18)

actualOwnerReward(m) = (multiplier == 0 || cap(m) >= ceilDiv(W(m), D))
    ? theoreticalOwnerReward(m)
    : mulDiv(serviceReward, cap(m), 1e18)
ownerOverflow(m) = theoreticalOwnerReward(m) - actualOwnerReward(m)
```

上限判定等价于交叉相乘 `cap(m) * D >= W(m)`，即 `cap(m) >= ceilDiv(W(m), D)`；实现对 ratio 不先取整，但按后一形式比较：除法形式不会溢出，任意 `govRatioMultiplier`（含极大值）都不会让结算回滚并锁死该行动。上限未触发时 `actualOwnerReward == theoreticalOwnerReward`，不产生取整粉尘销毁；触发时按 `cap(m)` 全额向下取整。

其中 `theoreticalOwnerReward(m)` 使用上节权重公式；治理票读取 `Stake.validGovVotes(actionTokenAddress, m)` 和 `Stake.globalGovVotes(actionTokenAddress)`。上限启用且总治理票为零时只销毁 owner 理论激励；乘数为零直接关闭上限。结算使用服务铸造时 `actionTokenAddress` 社区最新的有效治理票；已结算的查询返回记录结果，不重新套用后续票权。

`GOV_RATIO_MULTIPLIER` 与 `RATIO_FOR_PUBLIC_VERIFIER` 来自服务 Proposal 创建回调的 `targetData[2]`、`targetData[3]`；owner 超额按每个 owner 单独记入 `ownerBurned`。服务代币已经由 Mint 铸造并转入 Executor 后，销毁直接调用该代币的 `burn(amount)`；不重复修改 Core Mint 的 `rewardBurned`。服务 Proposal 本轮没有激励时由 Mint 的内部 Round 准备逻辑处理，Executor 不重复判断。

成员级结清每次结算发出两条事件：基座的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` 记公共口径，本接口的 `ServiceRewardDistributed(...)` 追加角色细分。两者必须满足 `MemberRewardMinted.mintAmount == verifierReward + ownerReward` 且 `.burnAmount == ownerBurned`，因此基座的「可铸造」在本接口是**聚合值**（服务轮次的可铸造量不是标量，公共验证者与 owner 两部分独立计算），逐个角色的金额仍读 `serviceRewardByMember`。`ServiceRewardDistributed` 与 `serviceRewardByMember` 同时给出 owner 份额的拆分：`ownerDistributed` 为实际转给二次分配接收者的总额（逐笔见 `DistributeRecipient`），`ownerRemaining` 为留在 owner 手中的部分（含无配置行动的整份切片与逐项取整余数），恒有 `ownerReward == ownerDistributed + ownerRemaining`。

## 二次分配

groupId 的当前 NFT 持有人按 `sourceTokenAddress + sourceActionId + groupId + round` 配置 `recipientIds[]`、`ratios[]`；查询指定 `round` 没有配置时，回退到不晚于该轮的最近配置，不使用未来轮次；不存在更早配置时视为未配置。所有对同一源行动提供激励的服务 Proposal 复用该配置。接收者为 memberId，比例使用 `1e18` 精度。owner 部分先按各源行动权重拆分，再应用对应配置：`slice(a, m) = mulDiv(actualOwnerReward(m), groupReward(a, m), ownerWeightNumerator(m))`（该 owner 权重为零时无此路径）；公共验证者部分直接给锁定验证者，不参与二次分配。

二次分配配置接口见 [`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol)（含配置枚举 `actionIdsWithRecipients` 与任意金额试算 `getDistribution`）；结算结果查询 `rewardDistribution` 与单接收者投影 `rewardByRecipient` 见 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)（后者返回指定接收者的分配额，`recipientId` 等于 `groupId` 时返回 owner 自留额，非接收者返回 0）。

setRecipients 沿用旧 GroupRecipients：只写当前验证 Round，不允许指定已结束轮次；同轮更新覆盖该轮配置。三数组等长回滚 `ArrayLengthMismatch`、最多 10 项回滚 `TooManyRecipients`（协议级编译期常量）、逐项比例为正回滚 `ZeroRatio`、接收 NFT 有效（无效由 `IMemberNFT.ownerOf` 回滚）、不得重复回滚 `DuplicateMemberId(memberId)`、不得等于 groupId 回滚 `RecipientCannotBeSelf`；非 groupId 当前持有人调用回滚 `NotMemberOwner(groupId)`。全部传空表示显式清空，该轮及后续回退到空配置，不能重新找到清空前配置。没有配置时 owner 保留全部该项预算。付款使用结算时接收 NFT 当前持有人。

配置按 `sourceTokenAddress + groupId` 维护按轮枚举：本轮非空写入登记源行动、显式清空移除，`actionIdsWithRecipients(sourceTokenAddress, groupId, round, offset, limit, reverse)` 分页返回该轮有效的已配置源行动与真实总数（懒继承到不晚于该轮的最近记录；同轮配置更新会重写该轮快照）。该集合用 swap-and-pop 删除：同一 `offset` 的返回内容不保证跨调用稳定，`reverse` 也不等于「新到旧」；调用方不得跨调用缓存 `offset`，也不得按「先拉首页再增量补页」拼接。`getDistribution(sourceTokenAddress, sourceActionId, groupId, groupReward, round)` 对任意金额按同规则试算（逐项向下取整、余数归 owner，100% 不下溢）。

配置比例总和不得超过 `1e18`，超过回滚 `DistributionOverflow(configured, available)`；正好 100% 合法。金额逐步向下取整：

```text
amount[i] = mulDiv(slice(a, m), ratios[i], 1e18)
```

各项取整后的总支出不得超过对应预算，`slice` 层与 owner 总量层的舍入余数都归 owner；100% 分配不得下溢。旧版两处双重 floor 曾使「单链群理论激励之和」超过可铸造量，100% 分配时 `mintReward - distributed` 下溢、整笔铸造回滚；本版全部中间量不提前截断，**`Σ 转账 + 销毁 ≤ serviceReward` 为承重不变量**，回归用例见 [Action 验收](08-testing.md)。

逐笔付款由 `DistributeRecipient(serviceTokenAddress, round, serviceActionId, groupId, sourceActionId, recipientId, amount)` 留痕；事件流连同 `MemberRewardMinted`、`RewardBurned` 可完整还原结算的全部资产变化。

## 实现约束

- `DistributionOverflow` 在配置比例总和超过 `1e18` 时触发；正好 `1e18` 合法。
- 二次分配配置键为 `sourceTokenAddress + sourceActionId + groupId + round`；分配事件另带服务 Proposal 上下文。
- 二次分配配置面单独声明接口 `IGroupRecipients.sol`（沿用旧文件名，由 `IGroupServiceExecutor` 继承），实现落在独立业务库 `GroupRecipients`：与单体 Executor 合并会超过 24,576 字节部署上限。
- ownerBurned 按 `serviceTokenAddress + serviceActionId + round + memberId` 保存实际销毁量，`ownerDistributed`/`ownerRemaining` 按同一键记录（恒有 `ownerReward = ownerDistributed + ownerRemaining`），不影响源行动缓存；铸造与销毁失败时标记、转账和代币 burn 全部回滚。
- 来源为旧 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol`、`LOVE20TKM/extension-group/src/GroupRecipients.sol` 与 `LOVE20TKM/extension/src/ExtensionBaseReward.sol`。公共验证者份额及全社区分母以本文件 BSC 规则为准。

铸造见 [统一链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
