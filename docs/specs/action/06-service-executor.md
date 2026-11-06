# GroupService Executor

服务 Proposal 的代币为 `serviceTokenAddress`，面向整个 `actionTokenAddress` 社区的 GroupAction，不绑定单个源 actionId。两者必须相同，或服务代币是行动代币的直接父币；其他关系在创建时拒绝。服务 Proposal 绑定本 Executor，其 Proposal ID 在 Action 层统一以 `serviceActionId` 称呼（Action ID 别名）。

阶段和源行动查询见 [服务验证复用](02-phase-model.md#服务验证复用)。分母统计 `actionTokenAddress` 社区本轮全部 GroupAction 的行动层激励：按 `votedActionIdsByExecutors(actionTokenAddress, round, [GROUP_ACTION_EXECUTOR_ADDRESS()])` 枚举本轮属于本执行器的有票行动（**上界 = 该代币本轮有推举资格的成员数**：每个成员每轮最多推举一个提案，出处 core [提交](../core/05-submit.md)；不是社区行动总数，见 [ActionTarget](01-action-target.md)），逐个行动求和。行动层查询自带验证与激励条件，未完成验证或无公共验证者的行动整轮返回 0，GroupService 不重复筛选。服务 Proposal 本轮没有可铸造激励时，由 Mint 的内部 Round 准备逻辑决定为零，Executor 不重复判断原因，owner 和公共验证者激励均为零。

状态集中在 `GroupServiceStorage.Layout`；字段的插入、删除或重排都会移动后续槽位。本仓无生产部署，Layout 变更后必须整体重新部署；若已有部署，只能尾部追加。

## 权重

| 符号 | 含义 |
| --- | --- |
| `A[a]` | 源 GroupAction a 的行动层分配总额，即 `generatedActionReward` 返回的 proposalReward；按群切片 floor 后其和不超过 `A[a]` |
| `r` / `publicVerifierRatio` | 服务 Proposal 绑定的公共验证者比例，`1e18` 精度；各源行动统一取该值（不再由验证者在申请时自报） |
| `totalGroupActionReward` | `actionTokenAddress` 社区本轮全部 GroupAction 的 `A[a]` 之和，即本服务轮次的分母 |
| `publicVerifierId[a]` | 行动 a 在目标轮锁定的公共验证者 verifierId |
| `m` | 结算主体 memberId；作为群 owner 时也是 groupId |
| `groupReward(a, m)` | Group m 在行动 a 的成员激励总和；与 `A[a]`、`D` 同源，同一时刻从同一份账本读出 |
| `serviceReward` | 本服务 Proposal 的整笔激励 |

```text
A[a] = generatedActionReward(actionTokenAddress, a, round)                 // 该行动自身的行动层激励
D    = Σ_a A[a]                                                          // 未准备时实时重算；行动代币轮次准备后读缓存

verifierWeightNumerator(m) = Σ_{a: lockedVerifierId(actionTokenAddress, a, round) == m} A[a]
ownerWeightNumerator(m)    = Σ_a groupReward(a, m)

theoreticalVerifierReward(m) = mulDiv(serviceReward, r * verifierWeightNumerator(m), D * 1e18)
theoreticalOwnerReward(m)    = mulDiv(serviceReward, (1e18 - r) * ownerWeightNumerator(m), D * 1e18)
```

`generatedActionRewardByGroupId` 对未完成验证或无参与的行动返回 0，`lockedVerifierId` 只在该行动的目标轮存在锁定验证者时非零；行动可跨轮复用，但**每个行动只在被推举并投票的那一轮产出参与与激励**，`votedActionIdsByExecutors(round)` 入榜的正是该轮被投票且绑定本执行器的行动，因此分母天然只统计当轮的参与。理论金额使用同一组不提前截断的分子与分母（`Math.mulDiv`）。

分母 `D` 与每个行动的 `A[a]` 默认按实时账本读取。分母对每个入榜行动读一次 `A[a]`（`generatedActionReward`，未完成验证或无参与返回 0），即 O(votedActionIdsByExecutors)，而 `votedActionIdsByExecutors` 有每轮提案上界，**链上没有与链群数成正比的成本**；群切片 `groupReward(a, g)` 不落存储，按 `mulDiv(A[a], finalScore(a, g), totalFinalScore(a))` 现算；权重侧另按群切片读取，成员为锁定验证者时再读一次 `A[a]`。

owner 权重按群切片 floor 后汇总，因此 `Σ_m ownerWeightNumerator(m) ≤ D`：每个行动的分母最多比该行动的群切片之和多「群数 − 1」个 wei。owner 侧按 `ownerWeight / D` 分成，这部分未被权重覆盖的服务激励不重分配、留在服务合约，与未加入角色的份额、零分母未结算激励同口径；公共验证者权重直接按 `A[a]` 汇总，不受此取整影响。这是分母取行动总额、而非逐群切片之和的直接代价，换来分母的 O(votedActionIdsByExecutors)。

**分母缓存**：行动代币那一轮被 Mint 准备、且该轮已进入结算窗口（验证已结束）之后，该轮的 `_proposalReward`、`_eligibleProposalVoteAmountByRound` 与票数都已定稿，每个 `A[a]` 不再变化——此时把 `D` 存下来，后续结算与查询直接读缓存，省掉一次行动枚举；缓存命中后不再重写，也不再读 `isRewardPrepared`。判据必须是**行动代币**的 `isRewardPrepared(actionTokenAddress, round)`，不是服务代币的：服务 Proposal 挂在父币上时，结算里的 `mintActionReward` 只准备父币那一轮，子币那一轮仍开着，`A[a]` 还会随 `rewardAvailable()` 移动；此时缓存会把冻结的分母和活的权重配在一起，第二个人超额领取（`testRegression_RealSourceBurnCannotOverpayServiceBudget` 就是这个反例）。未准备时一律实时算、不写缓存。`MINT_ADDRESS` 在构造函数内从 `ActionTarget.MINT_ADDRESS()` 读取一次并缓存，只用于这一个查询。

**分摊之所以稳定，靠的是「权重与分母同源」，不是「分子与分母同源」。** 权重侧 `ownerWeightNumerator(m)` 与 `verifierWeightNumerator(m)` 都由 `A[a]` 派生（群切片是 `A[a]` 按 `finalScore / totalFinalScore` 的比例，验证者权重直接是 `A[a]` 之和），分母 `D = Σ A[a]` 也是同一份账本，因此两者对池子大小同比例变化，`w(m)/D` 与池子无关。同一轮里所有行动都按 `P · v_a / E` 分摊同一个池 `P` 与同一个达标票数 `E`，所以别的轮次准备或铸造、社区代币被销毁导致 `rewardAvailable()` 移动时，`w` 与 `D` 一起动、比例不动，同一轮的两位成员即使在不同交易里结算，分摊比例也一样——差异只剩逐项取整的几位 wei。

这条论证**不要求分子与分母同币同源**：服务代币是行动代币的父币时，分子来自父币池、分母来自子币池，二者本就不会一起动；但分子一经准备即冻结、权重与分母同源，分摊仍然稳定。反过来，历史上「分子读实时、分母读快照」会超额支付，错的正是权重与分母不同源，而不在是否快照——所以只钉分母、不钉权重是不够的，真要快照就必须两侧一起钉（即已删除的旧「冻结账本」那套）。

现算切片的前提是轮次已过验证：`finalScoreByGroupId` 与 `totalFinalScore` 只在 `_scoreBatch` 里增长，验证结束、进入铸造窗口后都不再变化。若将来出现「验证之后还能改分数」的路径，同一轮的 owner 权重会在两次结算之间静默变化——这是承重不变式。

完整 ABI 见 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)（继承 [`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol) 的二次分配配置面）。

创建 Target Data 从第 `1` 项起（第 `0` 项是 ActionTarget 保留的 executor）固定为 `targetData[SLOT_SOURCE_TOKEN] = abi.encode(address actionTokenAddress)`、`targetData[SLOT_GOV_RATIO_MULTIPLIER] = abi.encode(uint256 govRatioMultiplier)` 和 `targetData[SLOT_PUBLIC_VERIFIER_RATIO] = abi.encode(uint256 publicVerifierRatio)`，项数恰为 `TARGET_DATA_LENGTH`（`4`）；项数少于 `TARGET_DATA_LENGTH` 回滚 `InsufficientTargetDataItems(targetData.length, TARGET_DATA_LENGTH)`、多于 `TARGET_DATA_LENGTH` 回滚 `TooManyTargetDataItems(targetData.length, TARGET_DATA_LENGTH)`，第 `0`～`3` 项不是 32 字节回滚 `InvalidTargetDataShape(index, length)`，`actionTokenAddress` 为零回滚 `ZeroActionTokenAddress()`，`publicVerifierRatio > 1e18` 回滚 `InvalidRatioForPublicVerifier(value)`（否则 `1e18 - r` 下溢），代币关系不满足回滚 `ActionTokenParentMismatch(actionTokenAddress, serviceTokenAddress, actualParentTokenAddress)`（载荷为行动代币、服务代币与行动代币的实际父币；未登记父币时实际父币为零地址）。`actionTokenAddress`、`govRatioMultiplier`、`publicVerifierRatio` 均按 `serviceTokenAddress + serviceActionId` 读取。创建回调成功的同一笔内由本 Executor 发出 `ServiceActionCreated`，携带 `actionTokenAddress`、`govRatioMultiplier`、`publicVerifierRatio` 三项初始配置全量；注册表事实由 ActionTarget 的 `ActionRegistered` 承担。投票回调没有业务项，`targetData.length > 1` 回滚 `TooManyTargetDataItems(targetData.length, 1)`。

`constructor(groupActionExecutorAddress)` 只收 GroupAction Executor：ActionTarget 从 `IGroupActionExecutor.ACTION_TARGET_ADDRESS()` 反查，Stake 再从 `ActionTarget.VOTE_ADDRESS()` 的 `STAKE_ADDRESS()` 反查；`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`LAUNCH_ADDRESS`、`MINT_ADDRESS`（从 Stake/ActionTarget 读取一次并缓存）有代码由 `DeployAction` 广播前校验；`21_check.sh` 复核 `STAKE_ADDRESS()`、`MEMBER_NFT_ADDRESS()`、`PHASE_ADDRESS()`、`LAUNCH_ADDRESS()`、`MINT_ADDRESS()`、ActionTarget 与 `GROUP_ACTION_EXECUTOR_ADDRESS()`；构造函数没有重复初始化入口。`GROUP_ACTION_EXECUTOR_ADDRESS()` 暴露绑定，供 21_check 核对 `GroupServiceExecutor -> GroupActionExecutor` 关系。

**加入与退出**：`join(serviceTokenAddress, serviceActionId, memberId)` 校验当前 NFT 持有人，资格为两类之一——该成员（自身作为链群主体）在 `actionTokenAddress` 社区存在激活行动，以 GroupAction Executor 的 `hasActiveGroups(actionTokenAddress, memberId)` 一次判定；或在该轮社区行动集（与分母枚举同源）中存在有效公共验证者竞选申请，逐个读 `verifierApplication(actionTokenAddress, actionId, round, verifierId)` 的 `applicationId != 0`（申请自其提交轮起常设，必须按**被加入轮**判断它当时是否已生效；无申请返回零值结构体、不回滚）。满足其一即可，不要求该轮已选出公共验证者；均不满足回滚 `NotQualified(actionTokenAddress, round, memberId)`。**第二条路径的成本是 O(votedActionIds)**，上界与分母枚举相同（本轮有推举资格的成员数）；它不随社区行动总数增长。重复 `join` 回滚 `AlreadyJoined(serviceTokenAddress, serviceActionId, memberId)`，未加入 `exit` 回滚 `NotJoined(serviceTokenAddress, serviceActionId, memberId)`。服务资格按轮快照由 ActionTarget 持有：查某成员在某轮是否已加入，直接读 `ActionTarget.isJoinedByRound(tokenAddress, actionId, round, memberId)`（地址经基座 `ACTION_TARGET_ADDRESS()` 取），执行器不设转发入口、不自建副本；退出只写当时轮快照，不追回已发生轮。加入与退出分别发 `ServiceJoined` / `ServiceExited`（均只带服务根键、`serviceActionId`、`memberId` 与 `round`，不带金额）。共同准备/铸造/销毁 ABI 见 [行动铸造](07-minting.md#铸造链路)。

**加入窗口**：服务 Proposal 是持续存在的，创建之后**每一轮都可以加入**，不限于创建轮——`createdRound` 只是下界。快照自加入轮起持续有效直到 `exit`，因此某轮结算只包含「在该轮或更早加入、且尚未退出」的成员；晚加入的人拿不到更早轮次的分成，但也无需重复加入。**同轮退出使该轮结算不再包含该成员**——退出把当前轮快照覆写为零，退出后再结算该轮时其份额留在合约（与未加入角色同口径）；已结算的轮次不追回。资格判定用**被加入的那一轮**的社区行动集（`currentJoinRound()`），不是创建轮的行动集。下界由 ActionTarget 的 `registerJoinState` 兜住：当前轮 `<= createdRound` 时回滚 `JoinNotOpen`，Executor 不重复判断。**例外：未创建行动**——未创建时 `createdRound` 为 `0`，`currentRound <= createdRound` 不成立，`JoinNotOpen` 不会触发，`registerJoinState` 反而会给未注册行动写加入状态并把 `actionId` 塞进成员索引；因此 `join` 在轮次之后、`AlreadyJoined` 之前先判 `createdRoundByActionId != 0`，否则回滚 `ActionNotCreated(serviceTokenAddress, serviceActionId)`。不要以为未创建行动会回滚 `JoinNotOpen`。

基座 `joinedAmountByActionId` 族代理社区激活质押：`joinedAmountByActionId(serviceTokenAddress, serviceActionId, round)` 返回 `totalStaked(actionTokenAddress)`（`round > currentJoinRound()` 返回 0），`joinedAmountByMemberId(serviceTokenAddress, serviceActionId, round, memberId)` 返回 `stakedByMemberId(actionTokenAddress, memberId)`，基座 `joinTokenAddress(serviceTokenAddress, serviceActionId)` 返回该服务行动绑定的行动代币（领域别名 `actionTokenAddress(serviceTokenAddress, serviceActionId)` 同键同值）；社区激活质押为当前值，没有按轮历史。`totalGroupActionReward` 的参数在源码与 ABI JSON 中名为 `sourceTokenAddress`：它与同名 getter `actionTokenAddress()` 冲突，按命名标准 §3.4 改参数名；getter、事件字段与结构体字段仍是 `actionTokenAddress`，指同一值。

[组织验收](../../acceptance.md#groupservice-结算) 还要求：只有本轮加入服务 Proposal 的群 owner/验证者 MemberNFT 可按人结算，未加入角色份额不重分配。每个角色先检查自己的分子，为零只跳过该角色，不影响同一 memberId 的另一角色；两个分子都为零时不读取分母，视图返回全零，结算入口按零额规则三分回滚（内部由 `GroupServiceStorage.SettlementCause` 的 `NoEligibleWeight` / `PoolEmpty` / `RoundedToZero` 驱动）：成员级回滚 `ZeroRewardWeight(tokenAddress, actionId, memberId)`（该成员本轮未按轮加入，或加入后验证者/owner 两个权重都为零）、轮级回滚 `MemberRewardPoolEmpty(tokenAddress, round)`（轮次未完成验证、轮级分母为零或服务激励为零）、取整回滚 `MemberRewardRoundedToZero(tokenAddress, round, memberId)`（分子非零但取整为零）（见 [统一链路](07-minting.md#铸造链路)）。`ZeroRewardWeight` 有意合并「未按轮加入」与「权重为零」两种子成因：既有 `NotJoined` 用于 `exit`，表达的是**当前**加入状态且载荷不带 `round`，复用到结算会与「该轮未加入」混淆，因此不拆。`totalGroupActionReward == 0` 时该轮没有分配路径（判据与 GroupAction 同型：轮次不等于 `createdRound` 或超过 `currentMintRound()` 时不适用，否则看 `D == 0`），任何角色结算都回滚 `MemberRewardPoolEmpty(tokenAddress, round)`，整笔服务激励停留在未结算状态、预留不释放。结算只在分母非零且**行动代币**轮次已准备时写分母缓存；零分母的失败结算不写任何状态，因此该轮在账本产出激励之前一直不可结算。

## 治理上限

只约束群 owner，公共验证者按实际验证工作量直接获得权重激励，不受该上限影响。owner 超出上限的部分销毁，不转给其他 owner 或验证者：

```text
W(m)   = (1e18 - r) * ownerWeightNumerator(m)                            // 不提前取整
govRatio(m) = totalValidGovVotes == 0 ? 0 : mulDiv(validGovVotes(actionTokenAddress, currentPhase, m), 1e18, totalValidGovVotes)
cap(m)      = multiplier == 0 ? 上限关闭 : mulDiv(govRatio(m), multiplier, 1e18)

actualOwnerReward(m) = (multiplier == 0 || cap(m) >= ceilDiv(W(m), D))
    ? theoreticalOwnerReward(m)
    : mulDiv(serviceReward, cap(m), 1e18)
ownerOverflow(m) = theoreticalOwnerReward(m) - actualOwnerReward(m)
```

上限判定等价于交叉相乘 `cap(m) * D >= W(m)`，即 `cap(m) >= ceilDiv(W(m), D)`；实现对 ratio 不先取整，但按后一形式比较：除法形式不会溢出，任意 `govRatioMultiplier`（含极大值）都不会让结算回滚并锁死该行动。上限未触发时 `actualOwnerReward == theoreticalOwnerReward`，不产生取整粉尘销毁；触发时按 `cap(m)` 全额向下取整。

其中 `theoreticalOwnerReward(m)` 使用上节权重公式；治理票按**铸造时的当前 Round** 读取 `Stake.validGovVotes(actionTokenAddress, currentPhase, m)` 和 `Stake.totalValidGovVotes(actionTokenAddress, currentPhase)`，`currentPhase = IPhase.currentPhase()`，不是被结算的 `round`。上限启用且总治理票为零时只销毁 owner 理论激励；乘数为零直接关闭上限。已结算的查询返回记录结果，不重新套用后续票权。

`govRatioMultiplier` 与 `publicVerifierRatio` 来自服务 Proposal 创建回调的 `targetData[SLOT_GOV_RATIO_MULTIPLIER]`、`targetData[SLOT_PUBLIC_VERIFIER_RATIO]`；owner 超额按每个 owner 单独记入 `ownerBurned`。服务代币已经由 Mint 直接铸给 Executor 后，销毁直接调用该代币的 `burn(amount)`；不重复修改 Core Mint 的 `totalRewardBurned`。服务 Proposal 本轮没有激励时由 Mint 的内部 Round 准备逻辑处理，Executor 不重复判断。

成员级结清每次结算发出两条事件：基座的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` 记公共口径，本接口的 `ServiceRewardsDistributed(...)` 追加角色细分。两者必须满足 `MemberRewardMinted.mintAmount == verifierReward + ownerReward` 且 `.burnAmount == ownerBurned`，因此基座的「可铸造」在本接口是**聚合值**（服务轮次的可铸造量不是标量，公共验证者与 owner 两部分独立计算），逐个角色的金额仍读 `serviceRewardByMemberId`。`ServiceRewardsDistributed` 与 `serviceRewardByMemberId` 同时给出 owner 份额的拆分：`ownerDistributed` 为实际转给二次分配接收者的总额（逐笔见 `RecipientPaid`），`ownerRemaining` 为留在 owner 手中的部分（含无配置行动的整份切片与逐项取整余数），恒有 `ownerReward == ownerDistributed + ownerRemaining`。

## 二次分配

groupId 的当前 NFT 持有人按 `sourceTokenAddress + sourceActionId + groupId + round` 配置 `recipientIds[]`、`ratios[]`；查询指定 `round` 没有配置时，回退到不晚于该轮的最近配置，不使用未来轮次；不存在更早配置时视为未配置。所有对同一源行动提供激励的服务 Proposal 复用该配置。接收者为 memberId，比例使用 `1e18` 精度。owner 部分先按各源行动权重拆分，再应用对应配置：`slice(a, m) = mulDiv(actualOwnerReward(m), groupReward(a, m), ownerWeightNumerator(m))`（该 owner 权重为零时无此路径）；公共验证者部分直接给锁定验证者，不参与二次分配。

二次分配配置接口见 [`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol)（含配置枚举 `actionIdsWithRecipients` 与任意金额试算 `distribution`）；结算结果查询 `rewardDistribution` 与单接收者投影 `rewardByRecipientId` 见 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)（后者返回指定接收者的分配额，`recipientId` 等于 `groupId` 时返回 owner 自留额，非接收者返回 0）。

setRecipients 沿用旧 GroupRecipients：只写当前验证 Round，不允许指定已结束轮次；同轮更新覆盖该轮配置。源行动未由本 Executor 创建时回滚 `UnknownSourceAction(sourceTokenAddress, sourceActionId)`；三数组等长回滚 `RecipientArrayLengthMismatch(recipientIdsLength, ratiosLength, remarksLength)`、最多 8 项回滚 `TooManyRecipients(count, MAX_RECIPIENTS_PER_ACTION)`（协议级编译期常量）、逐项比例为正回滚 `ZeroRecipientRatio(recipientId)`、接收 NFT 有效（无效由 `IMemberNFT.ownerOf` 回滚）、不得重复回滚 `DuplicateMemberId(memberId)`、不得等于 groupId 回滚 `RecipientIsGroupId(groupId, recipientId)`；缺失群回 `GroupNotExist(groupId)`，非 groupId 当前持有人调用回滚 `NotGroupOwner(groupId)`，且鉴权先于轮次校验。**校验次序（实现口径）**：群存在性与调用者（`onlyGroupOwner`：`GroupNotExist` → `NotGroupOwner`）→ 轮次（`currentVerifyRound()` 作为实参先求值）→ 参数（`_checkRecipients`：三数组等长 / 条数 / 比例 / 重复 / 自身 / 接收 NFT 有效）→ 源行动存在性（`UnknownSourceAction`）→ 上限资格（非空配置、该 action 不在累计集合、集合已达 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP` 时回滚 `RecipientActionsLimitExceeded(address sourceTokenAddress, uint256 groupId, uint256 actual, uint256 limit)`，`actual` 为判定时集合内的源行动数、`limit` 为该上限常量）。`E-GR-02` 的处置范围是**库内顺序**：参数先于源行动存在性；外层修饰器的群存在性与调用者顺序未变，也没有被重排。全部传空表示显式清空，该轮及后续回退到空配置，不能重新找到清空前配置。没有配置时 owner 保留全部该项预算。付款对象是**结算时**接收 NFT 的当前持有人，不是配置时的持有人：配置只固定名单与比例，所有权在结算那一刻判定；NFT 转让后新持有人取得该轮分配（`forceClearJoinState` 同口径：处分权随当前持有人）。配置变更发 `RecipientsChanged`，按新表→旧表携带 `recipientIds`/`ratios`/`remarks` 与 `prevRecipientIds`/`prevRatios`/`prevRemarks`；`remarks` 每条不超过 `256` 字节，条数不超过 `MAX_RECIPIENTS_PER_ACTION`；单条超出回滚 `RemarkTooLong(index, length, maxLength)`。

配置按 `sourceTokenAddress + groupId` 维护按轮枚举：本轮非空写入登记源行动、显式清空移除，`actionIdsWithRecipients(sourceTokenAddress, groupId, round, offset, limit, reverse)` 分页返回该轮有效的已配置源行动与真实总数（懒继承到不晚于该轮的最近记录；同轮配置更新会重写该轮快照）。该集合是**累计集合**而非本轮集合：跨轮继承的项仍占位并计入上限，单个 `(sourceTokenAddress, groupId)` 最多登记 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP`（16）个源行动；配满后须先对其中一个已登记行动显式清空（传空表）才能为新行动让位。该集合用 swap-and-pop 删除：同一 `offset` 的返回内容不保证跨调用稳定，`reverse` 也不等于「新到旧」；调用方不得跨调用缓存 `offset`，也不得按「先拉首页再增量补页」拼接。`distribution(sourceTokenAddress, sourceActionId, groupId, round, groupReward)` 对任意金额按同规则试算（逐项向下取整、余数归 owner，100% 不下溢）。

配置比例总和不得超过 `1e18`，超过回滚 `DistributionOverflow(configured, limit)`；正好 100% 合法。金额逐步向下取整：

```text
amount[i] = mulDiv(slice(a, m), ratios[i], 1e18)
```

各项取整后的总支出不得超过对应预算，`slice` 层与 owner 总量层的舍入余数都归 owner；100% 分配不得下溢。旧版两处双重 floor 曾使「单链群理论激励之和」超过可铸造量，100% 分配时 `mintReward - distributed` 下溢、整笔铸造回滚；本版全部中间量不提前截断，**`Σ 转账 + 销毁 ≤ serviceReward` 为承重不变量**，回归用例见 [Action 验收](08-testing.md)。

逐笔付款由 `RecipientPaid(serviceTokenAddress, round, serviceActionId, groupId, sourceTokenAddress, sourceActionId, recipientId, amount)` 留痕（每个收款人一条）；事件流连同 `MemberRewardMinted` 与服务代币的 `TokenBurned` 可完整还原结算的全部资产变化。

结算内的事件顺序固定为：写成员账本 → `TokenBurned`（若有销毁）→ 逐笔 `RecipientPaid` → 两笔 `safeTransfer`（owner 余量与验证者份额）→ `MemberRewardMinted` → `ServiceRewardsDistributed`。两条汇总事件都排在明细之后：`ServiceRewardsDistributed` 的 `ownerDistributed` / `ownerRemaining` 依赖分配循环结果，属[事件规范 §3.4 E5](../../event-standards.md#34-批量与顺序)的依赖序逆序；`MemberRewardMinted` 声明的是「已结算」，只有在 burn 与转账完成后才成立，属 §3.4 E6 的结算聚合例外，与 E5 构成同一结算尾部的两条相邻汇总。测试必须断言 `MemberRewardMinted` 晚于最后一条 `RecipientPaid`、且早于 `ServiceRewardsDistributed`。

## 入口与鉴权主体

按 dev-standards §5.5 列出映射；本合约的群 owner 判定留在自身（没有对应业务库），成员判定走基座：

| 入口 | 鉴权主体 | 定义位置 | 调用方附加 |
| --- | --- | --- | --- |
| `join`、`exit` | `memberId` 当前持有人 | `ExecutorBase.onlyMemberOwner` | 均 `nonReentrant` |
| `setRecipients` | `groupId` 当前持有人 | 本合约 `onlyGroupOwner`（`GroupRecipients` 库不判调用者） | 无锁（只读依赖） |
| `onProposalCreated` / `onProposalSubmitted` / `onProposalVoted` | ActionTarget | `ExecutorBase.onlyActionTarget` | 库内不重复判定 |
| `mintMemberReward`、`mintMemberRewards` | `memberId` 当前持有人 | `ExecutorBase.onlyMemberOwner` | 结算入口 |
| `distribution` / `rewardDistribution` 等查询 | 无（只读） | — | — |

`GroupRecipients` 是被 `delegatecall` 的库：它只提供 `distribute` 与配置写入的内部实现，鉴权由调用方（本合约）先行完成——库单独被调用不具备鉴权能力（同 `05-group-action-executor.md` 的库内回调口径）。

## 实现约束

- `DistributionOverflow(configured, limit)` 在配置比例总和超过 `limit`（协议上限 `1e18`）时触发；正好 `1e18` 合法。
- **协议常量默认不进 ABI**（与 `05-group-action-executor.md` 的编译期常量段一致）；`PRECISION`、`MAX_RECIPIENTS_PER_ACTION` 与 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP` 例外地以 `public constant` 暴露，只为链下对齐取整精度与配置上限，登记为口径偏差，不改变语义。
- **`setRecipients` 不设锁**：它只调用只读外部依赖（`IMemberNFT.ownerOf`、ActionTarget / 本合约自身存储），不动钱；若将来加入外呼或资金路径，必须同批加 `nonReentrant`（与 05 的无锁配置入口同口径）。
- **轮次契约由调用方保证**：`setRecipients` 的 `round` 必须是当前验证轮，由调用方在提取时确认；库与合约都不把 `round` 与 `currentPhase()` 比较，只把它写成按轮快照。链下按已配置轮读取，不要用未来轮。
- 二次分配配置键为 `sourceTokenAddress + sourceActionId + groupId + round`；分配事件另带服务 Proposal 上下文。
- 二次分配配置面单独声明接口 `IGroupRecipients.sol`（沿用旧文件名，由 `IGroupServiceExecutor` 继承），实现落在独立业务库 `GroupRecipients`：与单体 Executor 合并会超过 24,576 字节部署上限。
- ownerBurned 按 `serviceTokenAddress + serviceActionId + round + memberId` 保存实际销毁量，`ownerDistributed`/`ownerRemaining` 按同一键记录（恒有 `ownerReward = ownerDistributed + ownerRemaining`），不影响源行动激励的读取；铸造与销毁失败时标记、转账和代币 burn 全部回滚。
- 来源为旧 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol`、`LOVE20TKM/extension-group/src/GroupRecipients.sol` 与 `LOVE20TKM/extension/src/ExtensionBaseReward.sol`。公共验证者份额及全社区分母以本文件 BSC 规则为准。

铸造见 [统一链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。

## 状态口径

- 结算金额依赖领取时点的治理票读面，不是 `(actionToken, round, memberId)` 的纯函数；同一键在不同区块可能算出不同数量，索引方不得把首次观察值当唯一真值。
- 分母缓存的时序前提：`_mintMemberReward` 在 `mintActionReward` 之前算出分母、之后写入 `cacheDenominator`；等值成立依赖「准备后 `A[a]` 冻结」与「同一 `(actionToken, round)` 只准备一次」。该前提由本规格承载（按 `dev-standards §5.3`，不在源码加注释）：读 `generatedActionReward` 前必须先调用一次 `mintMemberReward` 触发写入。
- 零分母不写缓存（`0` 兼作「未缓存」），因此该轮每次尝试都重新枚举全部入榜行动；与 `GroupServiceStorage` 的哨兵二义同源。
- 服务代币必须实现 `burn(uint256)`；合约不校验，上限绑定时才暴露，由部署期代币选择保证。
- `joinedAmountByActionId` / `joinedAmountByMemberId` 的 `round` 只作上界，返回值始终是当前累计，与 `LpExecutor`/`GroupActionExecutor` 的按轮历史不同。
- `RecipientsChanged` 的 `prev*` 是懒继承解析后的**有效值**，不是本轮原值；配置懒继承意味着「配一次永久生效」，集合无法区分「本轮配过」与「继承来的」。
- `distribute` 只随收款人维度增长：action 维度由单个 `(sourceTokenAddress, groupId)` 的 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP`（16）封顶，上界为 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP × MAX_RECIPIENTS_PER_ACTION` = 128 次收款人级外呼（每次 `ownerOf` + `safeTransfer` + 一条 `RecipientPaid`），另加至多 16 次行动切片读取；成本由份额承担，与社区行动总数无关。`setRecipients` 不校验群激活状态，任意群主可在停用群上配比例。
- **已知边界（首次 mint）**：单笔 `mintMemberReward` 的投票行动扫描上界是 `SUBMIT_ROUND_LIMIT`（1000 项），叠加首笔结算的分母写入后，即使收款人配置已收窄到 `16 × 8`，最坏路径仍可能触及区块预算（按 24M 估算约 103%–127%，两个锚点均超）。根因是 1000 项扫描与分母缓存写入，**不是收款人配置**：后者已由 `128` 次外呼封顶。该边界作为已知取舍登记，不在配置层再加限制（再加会改变分母的共识语义）。
- `cacheDenominator` 自身无幂等守卫，唯一性由唯一调用方（`_mintMemberReward`）保证；`joinTokenAddress` / `actionTokenAddress` / `sourceTokenByServiceActionId` 三名同概念，链下不得按 getter 名做统一适配。

## 错误卷补记（2026-11，X-06 / X-09）

- `E-GR-03`：没有「比例之和为零」的独立错误——空表是显式清空（合法），非空表每项比例必须 `> 0` 故和 `≥ 1`，`Σ ratio == 0` 只能由空表达成，语义自洽。
- `E-GSS-01`：`cachedDenominator` 的写入口只有 `_mintMemberReward`，`cacheDenominator` 自身无幂等守卫，唯一性由唯一调用方保证；链下不得把它当作可任意刷新的缓存。
- `E-GSE-05`：`onlyGroupOwner` 用裸名引用本地 `IGroupServiceExecutorErrors`，`GroupActionManager` 用限定名引用 `IGroupActionManagerErrors`；两处同名同签名，协议级「一名一签名」不受影响。
