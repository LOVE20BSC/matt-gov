# GroupServiceExecutor · 状态变量变更审查

> `action/src/GroupServiceExecutor.sol`，800 行，`action@0c1d1e2`。
> 职责：服务 Proposal 的宿主。**自身不持有参与状态**——服务行动的「谁加入了」完全存在 `ActionTarget`（`registerJoinState` / `clearJoinState`），本合约只持有「服务行动配置」与「按人结算记录 + 分母缓存」。
> 结算读的是**源行动代币**社区本轮全部 GroupAction 的激励，因此状态里有两种轮次口径：服务代币的轮（配置、结算键）与行动代币的轮（分母缓存键）。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `PRECISION` | `uint256 constant = 1e18` | 比例精度 | 编译期 |
| 2 | `DEFAULT_MAX_RECIPIENTS` | `uint256 constant = 10` | 二次分配上限 | 编译期 |
| 3 | `GROUP_ACTION_EXECUTOR_ADDRESS` | `address immutable` | 源行动宿主 | 构造器 `:71` |
| 4 | `LAUNCH_ADDRESS` | `address immutable` | 父币反查 | 构造器 `:72` |
| 5 | `MINT_ADDRESS` | `address immutable` | `isRewardPrepared` 的唯一用途 | 构造器 `:73` |
| 6 | `_layout.actionTokenAddressByActionId` | `mapping(address => mapping(uint256 => address))` | 服务行动 → 源行动代币 | `onProposalCreated:425` |
| 7 | `_layout.govRatioMultiplierByActionId` | 同上 `uint256` | owner 上限乘数 | `:426` |
| 8 | `_layout.publicVerifierRatioByActionId` | 同上 `uint256` | 公共验证者分成 | `:427` |
| 9 | `_layout.createdRoundByActionId` | 同上 `uint256` | 创建轮（0 = 未创建） | `:428` |
| 10 | `_layout.totalGroupActionRewardByRound` | `mapping(address => mapping(uint256 => uint256))` | 行动代币 + 轮 → 分母缓存 | `cacheDenominator:62` ← `:741` |
| 11 | `_layout.memberMinted` | `mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => bool))))` | 服务代币 + 行动 + 轮 + 成员 → 已结算 | `:744` |
| 12 | `_layout.verifierRewardByMemberId` | 同上 `uint256` | 验证者份额 | `:745` |
| 13 | `_layout.ownerBurnedByMemberId` | 同上 `uint256` | owner 超限销毁量 | `:746` |
| 14 | `_layout.ownerDistributedByMemberId` | 同上 `uint256` | 二次分配实际转出 | `:769` |
| 15 | `_layout.ownerRemainingByMemberId` | 同上 `uint256` | owner 自留 | `:770` |

`_layout` 的其余字段（`recipientIdsHistory` / `ratiosHistory` / `remarksHistory` / `actionIdsWithRecipients`）由 `GroupRecipients` 写，见 `09-group-recipients.md`。

## 2. 逐变量变更逻辑

### 2.1 `onProposalCreated`（`:393-437`）——四个配置槽

| 顺序 | 位置 | 语句 | 守卫 |
| --- | --- | --- | --- |
| 1 | `:397` | `onlyActionTarget` | `NotActionTarget` |
| 2 | `:398-406` | 项数恰为 4、每项 32 字节 | `TargetDataLengthMismatch(4, len)` / `InvalidTargetDataShape` |
| 3 | `:408-411` | 解出 `sourceTokenAddress` / `govRatioMultiplier` / `publicVerifierRatio` | — |
| 4 | `:412-414` | `sourceTokenAddress != 0` | `ZeroActionTokenAddress` |
| 5 | `:415-417` | `publicVerifierRatio <= 1e18` | `InvalidRatioForPublicVerifier` |
| 6 | `:418-423` | `sourceToken == token` 或 `Launch.parentToken(sourceToken) == token` | `ActionTokenParentMismatch` |
| 7 | `:425-428` | 写四个槽（含 `createdRound = currentPhase()`） | — |

`govRatioMultiplier` 无上界（`:426`），与 LpExecutor 同口径：任意大值等价于「上限关闭」，因为判定走交叉相乘（`:552`）。

### 2.2 `join` / `exit`（`:113-137` / `:372-390`）——**不写本合约状态**

| 入口 | 状态写入 |
| --- | --- |
| `join` | 只调 `ActionTarget.registerJoinState`（外部写）+ `ServiceJoined` |
| `exit` | 只调 `ActionTarget.clearJoinState`（外部写）+ `ServiceExited` |

这是本合约最重要的结构决定：**服务的加入态是 `ActionTarget` 的账本，本合约没有副本**。因此 `isJoinedByRound(serviceToken, serviceActionId, round, memberId)` 直接回答「该成员在该轮是否已加入」，不需要在本合约做按轮快照。

### 2.3 `_mintMemberReward`（`:702-799`）——五个结算槽 + 一个缓存槽

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:708-715` | `_checkMintWindow(..., createdRound, memberMinted)` | 四段守卫 |
| 2 | `:717` | `settlement = _settlement(...)` | 见 2.4 |
| 3 | `:718-719` | `mintAmount = verifier + owner`；`burnAmount = ownerBurned` | — |
| 4 | `:720-722` | 双零 → revert | 按 `cause`：`ZeroRewardWeight` / `MemberRewardPoolEmpty` / `MemberRewardRoundedToZero` |
| 5 | `:724-733` | `!actionMinted` → `mintActionReward` 取整笔，再 `_applyFormulas` 重算 | 外部调用 |
| 6 | `:737-742` | 缓存分母（条件见 2.5） | — |
| 7 | `:744-746` | 写 `memberMinted` / `verifierReward` / `ownerBurned` | 三槽同段 |
| 8 | `:748-751` | `burnAmount != 0` → `ILOVE20Token(tokenAddress).burn(burnAmount)` | 烧本合约余额 |
| 9 | `:753-767` | `ownerReward != 0` → `GroupRecipients.distribute(...)` | 多次转账 |
| 10 | `:768-770` | `remaining = ownerReward − distributed`；写 `ownerDistributed` / `ownerRemaining` | — |
| 11 | `:772-777` | 转 `remaining` 与 `verifierReward` 给 `msg.sender` | — |
| 12 | `:779-798` | `MemberRewardMinted` + `ServiceRewardsDistributed` | — |

第 7 步在 `burn` 与 `distribute` 之前，因此「已标记」先于「已付款」。第 10 步的 `ownerDistributed` / `ownerRemaining` 只能在 `distribute` 之后写（要拿实际转出额），因此这一段是唯一「外部调用夹在两次状态写之间」的地方——由 `nonReentrant` 与第 7 步的 `memberMinted` 双重保护。

### 2.4 `_settlement`（`:482-513`）——六段早退

| 顺序 | 位置 | 判据 | 早退后的状态 |
| --- | --- | --- | --- |
| 1 | `:488` | 写 `actionTokenAddress`（memory 结构体，非存储） | — |
| 2 | `:489-491` | `!ActionTarget.isJoinedByRound(serviceToken, actionId, round, member)` | 全零 |
| 3 | `:493-497` | `verifierWeight == 0 && ownerWeight == 0` | 全零 |
| 4 | `:499-504` | `denominator == 0` | 全零 |
| 5 | `:506-510` | `serviceReward == 0` | 全零 |
| 6 | `:512` | `_applyFormulas` | 填 `verifierReward` / `ownerReward` / `ownerBurned` |

第 2 段是关键：**结算资格由「服务行动的加入快照」决定，不由源行动的参与决定**。成员必须用服务代币的 `serviceActionId` 加入过（且在该轮或更早、未退出），才有资格分。

### 2.5 分母缓存（`:626-629`、`:737-742`、`GroupServiceStorage:56-68`）

| 项 | 值 |
| --- | --- |
| 键 | `actionTokenAddress + round`（**不是**服务代币） |
| 值 | `_totalGroupActionReward(scope)` = Σ `generatedActionReward(actionToken, a, round)` |
| 写入条件 | `cached == 0` **且** `IMint.isRewardPrepared(actionToken, round)` |
| 永不重写 | 命中即返回（`:220-223`、`:627-628`） |

键必须是行动代币的轮，因为服务代币是父币时 `mintActionReward` 只准备父币那一轮，子币那一轮的 `A[a]` 仍会随 `rewardAvailable()` 移动（`GroupServiceStorage:65-68` 的 `Load-bearing` 注释）。

### 2.6 `_applyFormulas`（`:515-558`）——上限的两条分支

| 分支 | 条件 | `ownerReward` | `ownerBurned` |
| --- | --- | --- | --- |
| 关闭上限 | `govRatioMultiplier == 0` | `theoreticalOwnerReward` | 0 |
| 上限不绑定 | `cap >= ceilDiv(ownerRatioWeight, denominator)` | `theoreticalOwnerReward` | 0 |
| 上限绑定 | 否则 | `floor(serviceReward * cap / 1e18)` | `theoretical − actual` |

`cap` 由 `validGovVotes(actionToken, currentPhase, memberId)` 与 `totalValidGovVotes(actionToken, currentPhase)` 现读（`:536-545`），**不是被结算轮**。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| S1 | `memberMinted == true` ⟹ 四个金额槽都已写 | ✅ | `:744-746` 与 `:769-770` 之间有 `distribute`，但任一步失败整笔回滚，因此不存在「已标记、金额缺失」 |
| S2 | `ownerReward == ownerDistributed + ownerRemaining` | ✅ | `:768` 直接定义 |
| S3 | `verifierReward + ownerReward + ownerBurned <= serviceReward` | ✅ | `verifierWeight <= D`、`ownerWeight <= D`，两项占比之和 ≤ 1；上限绑定分支下 `actual + burned = theoretical` |
| S4 | 同一 (服务代币, 行动, 轮, 成员) 至多结算一次 | ✅ | `memberMinted` 先于转账写，且 `_checkMintWindow` 先判 |
| S5 | 分母缓存一旦写入不再变化 | ✅ | 唯一的 `cacheDenominator` 调用点前置 `cached == 0` |
| S6 | 缓存的键与值的轮次口径一致 | ✅ | 键用 `settlement.actionTokenAddress`（`:738`），值由 `_roundActions(actionToken, round)` 算出 |
| S7 | 结算只依赖已冻结的验证结果 | ✅ | `finalScoreByGroupId` / `totalFinalScore` 在验证结束后不再写（`GroupActionVerify` 的唯一写点是 `_scoreBatch`，轮次固定 `phase − 2`） |
| S8 | `mintActionReward` 的收款方是本合约 | ✅ | `ActionTarget:275` 的 `bound` 就是绑定的 Executor |

## 4. 发现

### M-GSE-01 · 结算金额依赖「领取时点的治理票」，因此 `(服务代币, 行动, 轮, 成员)` 不能唯一确定结果

| 字段 | 值 |
| --- | --- |
| 位置 | `:536-545`（现读 `currentPhase`）、`:744`（`memberMinted` 冻结） |
| 级别 | Info |
| 证据 | E2 |

`_applyFormulas` 的 `cap` 用 `IPhase.currentPhase()` 的治理票算，而结算键是 `(服务代币, 行动, round, 成员)`。因此同一个键在不同时点调用 `_settlement` 会得到不同的 `ownerReward` / `ownerBurned`，只有第一次真正落地的那个值被 `memberMinted` 冻结。

后果：

1. **结算不可重放**。链下无法用 `(token, action, round, member)` 预计算最终金额，必须先读 `memberMinted` 判断是否已结算；未结算时的返回值只是「此刻的值」。
2. **成员可以选择领取时机**。`ownerReward` 随 `validGovVotes(member)` 上升而上升、随 `totalValidGovVotes` 下降而上升；`ownerBurned` 是反向。成员可以等到自己的治理票占比最高时再领，从而把「本应销毁」的部分拿回来。
3. **`ownerBurned` 的销毁量因此也是时点相关的**，链下统计「累计销毁」必须读 `ownerBurnedByMemberId`，不能重算。

规格 `06:77` 明确「治理票按铸造时的当前 Round 读取，不是被结算的 round」，所以这是**规格授权的设计**。本卷列为发现的原因是：规格只写了「读当前轮」，没有写「因此结算金额不是键的函数」这一可观测后果——而这直接影响链下账务与「上限是否真的约束了 owner」这个经济结论。

### M-GSE-02 · 缓存值在 `mintActionReward` **之前**算出，写入却在**之后**；等值依赖「准备后 `A[a]` 冻结」

| 字段 | 值 |
| --- | --- |
| 位置 | `:717`（`_settlement` 算分母）→ `:726`（可能准备该轮）→ `:737-742`（写缓存） |
| 级别 | Info |
| 证据 | E2 |

`settlement.denominator` 在第 2 步用实时账本算出；如果 `!actionMinted`，第 5 步的 `mintActionReward` 会在同一笔内把行动代币那一轮「准备」掉（冻结 `P` 与 `E`），此后 `A[a]` 不再变化。写入条件是 `isRewardPrepared`，也就是**只有在准备之后才写缓存**。

等值推导：`generatedActionReward` 在未准备时返回 `actionReward` 的**理论值** `floor(P · v_a / E)`，用的是当时的 `rewardAvailable()`；准备动作在同一笔、同一 `rewardAvailable()` 下算出并冻结同一个值。因此「准备前算出的分母」== 「准备后冻结的分母」，缓存不会失真。

但这条链有三个隐含前提，代码只用 `GroupServiceStorage:65-68` 的注释登记了「键的选择」：

1. `generatedActionReward` 在未准备时返回理论值（而不是 0）——依赖 `Mint.proposalRewardByProposalId` 的语义；
2. 准备动作不改变 `rewardAvailable()` 的取值（只预留，不增发）；
3. 同一 `(actionToken, round)` 只准备一次。

任一前提变化，缓存就会写进一个「准备前的旧值」，而它此后永不重写（S5），该轮所有后续结算都用这个旧分母。这是本合约最需要一条 `// Load-bearing:` 的位置。

### M-GSE-03 · 零分母轮次永不写缓存，每次尝试都重新枚举全部入榜行动

| 字段 | 值 |
| --- | --- |
| 位置 | `:501-504`（`denominator == 0` 早退）、`:737-742`（写缓存的前置） |
| 级别 | Info |
| 证据 | E1 |

`_settlement` 在 `denominator == 0` 时早退，`_mintMemberReward` 随后因双零回滚 `MemberRewardPoolEmpty`（`cause == 2`，轮级），**不写任何状态**（规格 `06:58` 明说「零分母的失败结算不写任何状态」）。

于是该轮在账本产出激励之前，每次结算尝试都要付一次 `_roundActions` + 逐行动 `generatedActionReward` 的完整枚举成本，然后回滚。`_votedActions` 用 `votedActions(..., 0, type(uint256).max, ...)`（`:653`）取全量，成本与「该轮入榜行动数」成正比。

这是「失败不写状态」的必然代价（不能把 0 写进缓存，因为 0 是「未缓存」的哨兵）。若要让失败也可缓存，需要把缓存改成 `(bool cached, uint256 value)` 或用一个 `type(uint256).max` 哨兵。

### M-GSE-04 · 服务代币必须支持 `burn(uint256)`，合约不校验；`ownerBurned != 0` 时依赖它

| 字段 | 值 |
| --- | --- |
| 位置 | `:748-751` |
| 级别 | Info |
| 证据 | E1 |

`burnAmount != 0` 时直接 `ILOVE20Token(tokenAddress).burn(burnAmount)`。服务代币由 `Launch` 发行（都是 `LOVE20Token` 克隆），因此正常路径都有 `burn`。但 `onProposalCreated` 只校验「与源行动代币相同或是其直接父币」（`:418-423`），不校验代币接口。

若服务代币没有 `burn`，则**只有在治理上限绑定时**才回滚（`ownerBurned > 0`），表现为「大部分成员能结算，某些成员永远不能」。这是「按人结算」的一个非对称失败点：同一轮里治理票占比低的成员全部卡住，占比高的正常。

规格 `06:79` 写了「销毁直接调用该代币的 `burn(amount)`」，没写「因此服务代币必须有 `burn`」。

### M-GSE-05 · `joinedAmountBy*` 的 `round` 参数不参与计算，与同名的 GroupAction / LP 版本语义不同

| 字段 | 值 |
| --- | --- |
| 位置 | `:182-207` |
| 级别 | Info |
| 证据 | E1 |

```solidity
function joinedAmountByActionId(address token, uint256 actionId, uint256 round) external view returns (uint256) {
    if (round > _joinRound()) return 0;
    return IGroupActionExecutor(...).totalStaked(actionTokenAddress[token][actionId]);
}
```

`round` 只做一次上界早退，返回值是**当前**的 `totalStaked`。三个 Executor 的同名读面因此有三种语义：

| Executor | `joinedAmountByActionId(t, a, r)` |
| --- | --- |
| `LpExecutor` | `_joinedAmountByActionId[t][a].value(r)`（真正的按轮历史） |
| `GroupActionExecutor` | `joinedAmountByActionId[t][a].value(r)`（真正的按轮历史） |
| `GroupServiceExecutor` | 当前 `totalStaked`，`r` 只用于上界 |

规格 `06:56` 已明说「社区激活质押为当前值，没有按轮历史」，所以是设计。但**同一个 ABI 形状在三个合约里回答三种问题**，链下按接口名统一处理会得到错的历史。建议在 `IGroupServiceExecutor` 的对应注释里显式写「`round` 仅作上界，返回值不是该轮快照」——接口不写 NatSpec（`§4.1`），所以只能落在规格。

## 5. 已核对为正确的点

- `join` / `exit` 不写本合约任何状态，服务行动的加入态只有 `ActionTarget` 一份（避免了「两份快照」的所有同步问题）。
- 结算的五个金额槽在 `distribute` 之前写三个、之后写两个，且 `memberMinted` 最早——重入无法二次结算（S1/S4）。
- `verifierReward + ownerReward + ownerBurned <= serviceReward`（S3），因此本合约的代币余额在每次结算后不会减少到不足以支付剩余成员。
- 缓存键用 `settlement.actionTokenAddress` 而不是 `tokenAddress`（`:738`），与 `_roundActions` 的入参同源（S6），不存在「父币轮缓存了子币分母」。
- `_isSettleableRound`（`:681-688`）同时要求 `createdRound != 0`、`round >= createdRound`、`round <= _mintRound()`，与服务行动的加入下界（`ActionTarget.JoinNotOpen`）方向一致。
- `_ownerRewardAndWeight` 在已结算时用 `ownerDistributed + ownerRemaining` 反推 `ownerReward`（`:576-577`），与 S2 一致，不会因为重算 `_settlement` 而漂移。
- `_votedGroupActions` 用两次遍历（先计数、再填充）避免动态数组扩容，返回的数组长度精确。
- `GroupRecipients.ownerSlice` 的 `groupReward == 0` 早退（`09:294-296`）避免 `mulDiv(ownerReward, 0, ownerWeight)` 产生 0 切片却被计入 `distributed`。

## 6. 覆盖缺口

- 未复现「服务代币 == 行动代币」时缓存写入的完整路径（M-GSE-02 的三个前提只做了静态推导，未跑 `testRegression_RealSourceBurnCannotOverpayServiceBudget` 对照）。
- 未审 `_settlement` 被 `memberReward` / `serviceRewardByMemberId` / `rewardByRecipientId` 三个视图各调用一次时的重复枚举成本（每次 O(votedActions) 次外部静态调用）。
- 未审 `GroupRecipients.distribute` 的无界循环（见 `09-group-recipients.md` 的 M-GRC-03）。
- 未复核 `ILaunch.parentToken` 在未登记时的返回值（按 `06:48` 应为零地址 → `ActionTokenParentMismatch`）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GSE-01` | 规格补写 | [`06-service-executor.md`](../../docs/specs/action/06-service-executor.md) 的「状态口径」：结算金额依赖领取时点的治理票读面，不是 `(actionToken, round, memberId)` 的纯函数 |
| `M-GSE-02` | 规格补写（不加源码注释） | 同上：写明「必须先 `mintMemberReward` 触发缓存写入，再读 `generatedActionReward`」的时序前提；按 `dev-standards §5.3`，该前提由规格承载，不在 `src/` 加注释 |
| `M-GSE-03` | 规格补写 | 同上：零分母不写缓存，每次重算；与 `M-GSS-01` 同源 |
| `M-GSE-04` | 规格补写 | 同上：服务代币必须实现 `burn(uint256)`，由部署期代币选择保证 |
| `M-GSE-05` | 规格补写 | 同上：`joinedAmountByActionId` 的 `round` 只作上界，返回值始终是当前轮累计 |
