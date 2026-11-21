# GroupService Executor

服务 Proposal 的代币为 `serviceTokenAddress`，面向整个 `actionTokenAddress` 社区的 GroupAction，不绑定单个源 actionId。两者必须相同，或服务代币是行动代币的直接父币；其他关系在创建时拒绝。服务 Proposal 绑定本 Executor，其 Proposal ID 在 Action 层统一以 `serviceActionId` 称呼（Action ID 别名）。

阶段和源行动查询见 [服务验证复用](02-phase-model.md#服务验证复用)。GroupService 直接读取来源社区的当轮总激励与验证者权重。这两个量由 GroupAction 在完成各行动最后一批评分时累加。服务 Proposal 的预算来自 Core 的单项提案激励。

状态集中在 `GroupServiceStorage.Layout`；字段的插入、删除或重排都会移动后续槽位。本仓无生产部署，Layout 变更后必须整体重新部署；若已有部署，只能尾部追加。

## 权重

| 符号 | 含义 |
| --- | --- |
| `A[a]` | 源 GroupAction a 的行动分配总额，即 `generatedActionReward` 返回的 proposalReward；按链群切片 floor 后其和不超过 `A[a]` |
| `r` / `publicVerifierRatio` | 服务 Proposal 绑定的公共验证者比例，`1e18` 精度，取值严格位于 `(0, 1e18)`；各源行动统一取该值（不再由验证者在申请时自报） |
| `totalGroupActionReward` | `actionTokenAddress` 社区本轮全部 GroupAction 的 `A[a]` 之和，即本服务轮次的分母 |
| `publicVerifierId[a]` | 行动 a 在目标轮锁定的公共验证者 verifierId |
| `m` | 结算主体 memberId；作为链群 owner 时也是 groupId |
| `groupReward(a, m)` | Group m 在行动 a 的激励切片，按链群得分占比从 `A[a]` 向下取整 |
| `serviceReward` | 本服务 Proposal 的整笔激励 |

```text
A[a] = generatedActionReward(actionTokenAddress, a, round)                 // 该行动自身的行动激励
D    = Σ_a A[a]                                                          // 验证完成时累计

verifierWeightNumerator(m) = Σ_{a: lockedVerifierId(actionTokenAddress, a, round) == m} A[a]
ownerWeightNumerator(m)    = Σ_{a: A[a] > 0} groupReward(a, m)

theoreticalVerifierReward(m) = mulDiv(serviceReward, r * verifierWeightNumerator(m), D * 1e18)
theoreticalOwnerReward(m)    = mulDiv(serviceReward, (1e18 - r) * ownerWeightNumerator(m), D * 1e18)
```

每个 GroupAction 在所有参与链群完成评分、且总分与来源激励均为正时，将 `A[a]` 计入来源社区的轮次总额和该轮当选验证者的权重。投票已在验证前结束，Core 的奖池自首票预留，单项激励在该轮关闭后固定。`totalGroupActionReward` 直接读取 `totalGeneratedActionReward`。验证者权重读取 `totalGeneratedActionRewardByVerifierId`，服务行动在结算时应用自己的 `publicVerifierRatio`。

Owner 结算和预览从 GroupAction 的 `totalGeneratedActionRewardByGroupId` 读取权重。链群在目标轮没有参与记录时，权重为零。有参与记录时，GroupAction 遍历 `actionIdsWithGeneratedActionReward` 对应的产出行动集合，用登记的 `A[a]` 和链群历史得分计算每项的 `floor(A[a] × finalScore(a, m) ÷ totalFinalScore(a))`。链群无正分时切片为零。取消激活或后续轮次的退出不影响已结束轮次的切片。所有 Owner 权重之和至多为 `D`。逐项舍入和未加入角色的份额留在服务合约。

验证窗口关闭后，任何地址都可调用 GroupAction 的 `prepareGeneratedActionRewardByGroupId`，从链上已提交的游标开始累计最多 `limit` 个行动的切片。`groupRewardPreparation` 返回已处理数与总数。链群权重按来源社区、轮次、链群保存，预览和领取均使用已累计权重加尚未处理的切片。准备完成后，领取直接读取累计权重。同一来源社区与轮次的各服务行动共用累计结果。

游标与权重在同一笔交易提交。每次推进后，GroupAction 发出 `GroupRewardPreparationAdvanced`，记录本页首项、下一页起点、总项数、本页新增权重和累计权重。切片为零的行动仍占一个游标位置。零长度页和完成后的重复调用不推进。

父币服务使用父币 Proposal 预算，并以子币的总额和权重计算分配比例。来源权重在验证窗口结束后固定。结算时的治理上限仍可因当前治理票变化而调整。

完整 ABI 见 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)（继承 [`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol) 的二次分配配置面）。

内层创建配置传 `abi.encode(GroupServiceCreationParams(...))`，含 `actionTokenAddress`、`govRatioMultiplier` 和 `publicVerifierRatio`，共 96 字节。创建回调先校验调用者是 ActionTarget。长度不符回滚 `InvalidCreationDataLength`，地址字高 96 位非零回滚 `InvalidCreationDataEncoding`。解码后依序校验代币地址、公共验证者比例和代币关系。`actionTokenAddress` 为零回滚 `ZeroActionTokenAddress`。公共验证者比例须严格位于 (0, 100%)，否则回滚 `InvalidRatioForPublicVerifier`。代币关系不符回滚 `ActionTokenParentMismatch`。三项配置按 `serviceTokenAddress + serviceActionId` 读取，创建时由 `ServiceActionCreated` 完整记录。投票传 `0x`，非空回滚 `UnexpectedVoteData`。

`constructor(groupActionExecutorAddress)` 只收 GroupAction Executor：ActionTarget 从 `IGroupActionExecutor.ACTION_TARGET_ADDRESS()` 反查，Stake 再从 `ActionTarget.VOTE_ADDRESS()` 的 `STAKE_ADDRESS()` 反查；`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`LAUNCH_ADDRESS`、`MINT_ADDRESS`（从 Stake/ActionTarget 读取一次并缓存）有代码由 `DeployAction` 广播前校验；`21_check.sh` 复核 `STAKE_ADDRESS()`、`MEMBER_NFT_ADDRESS()`、`PHASE_ADDRESS()`、`LAUNCH_ADDRESS()`、`MINT_ADDRESS()`、ActionTarget 与 `GROUP_ACTION_EXECUTOR_ADDRESS()`；构造函数没有重复初始化入口。`GROUP_ACTION_EXECUTOR_ADDRESS()` 暴露绑定，供 21_check 核对 `GroupServiceExecutor -> GroupActionExecutor` 关系。

**加入与退出**。`join` 校验当前 NFT 持有人。Owner 通过 `hasActiveGroups` 检查在来源社区是否拥有激活链群。验证者通过 `hasVerifierApplicationByRound` 查询被加入轮的申请快照，来源社区任一 GroupAction 的申请均可满足，包括零票行动。申请自提交轮起延续，停止接票仍计入资格，撤回从下一轮失效。两个条件均不满足时回滚 `NotQualified`。服务加入状态由 `ActionTarget.isJoinedByRound` 查询，退出从当前加入轮起更新。加入与退出分别发 `ServiceJoined` 和 `ServiceExited`。

**加入窗口**。服务 Proposal 创建后每轮都可加入。`currentJoinRound()` 给出申请资格和服务加入快照所属的轮次。同轮退出使该轮加入状态失效。`join` 对尚未创建的行动回滚 `ActionNotCreated`，对重复加入回滚 `AlreadyJoined`。创建时的 Phase 由 ActionTarget 的 `JoinNotOpen` 门禁覆盖。未加入时调用 `exit` 回滚 `NotJoined`。

`joinedAmountByActionId` 和 `joinedAmountByMemberId` 代理来源社区的按轮激活质押查询。`joinTokenAddress` 返回服务行动绑定的来源代币，与 `actionTokenAddress` 指向同一值。

[组织验收](../../acceptance.md#groupservice-结算) 按加入状态、轮级分母、成员权重的顺序判断。成员当轮未加入时回滚 `ZeroRewardWeight`。已加入且分母为零时回滚 `MemberRewardPoolEmpty`。分母为正且两种权重均为零时回滚 `ZeroRewardWeight`。服务 Proposal 激励为零时回滚 `MemberRewardPoolEmpty`。有权重和预算但结算额取整为零时回滚 `MemberRewardRoundedToZero`。预览在这些情况下返回零金额。

### 客户端领取与续跑

1. 从服务行动取得来源代币与 GroupAction Executor 地址，用来源代币、目标结算轮和 Owner 的链群 ID 读取准备进度。领取和准备可分别估算 gas，预算应使用目标网络的单笔交易限制并为交易本身留出余量。
2. 单笔领取估算在预算内时可直接提交。尾段较长或多笔领取共用来源权重时，可先分批准备。估算每页的 `limit`，等待上一页确认后重新读取链上游标。遇到回滚或客户端重启时，先核对交易回执和最新游标，再提交下一页。
3. 游标达到总数后重新估算领取。批量领取超出预算时，将对应的行动与轮次成对拆批，必要时逐笔领取。领取失败后从链上确认 `claimed` 和准备进度再重试。验收包含未准备、部分准备和全部准备的 gas 对照。见 [Action 验收](08-testing.md)。

## 治理上限

只约束链群 owner，公共验证者按实际验证工作量直接获得权重激励，不受该上限影响。owner 超出上限的部分销毁，不转给其他 owner 或验证者：

```text
W(m)   = (1e18 - r) * ownerWeightNumerator(m)                            // 不提前取整
govRatio(m) = totalGovVotes == 0 ? 0 : mulDiv(govVotes(actionTokenAddress, currentPhase, m), 1e18, totalGovVotes)
cap(m)      = multiplier == 0 ? 上限关闭 : mulDiv(govRatio(m), multiplier, 1e18)

actualOwnerReward(m) = (multiplier == 0 || cap(m) >= ceilDiv(W(m), D))
    ? theoreticalOwnerReward(m)
    : mulDiv(serviceReward, cap(m), 1e18)
ownerOverflow(m) = theoreticalOwnerReward(m) - actualOwnerReward(m)
```

上限判定等价于交叉相乘 `cap(m) * D >= W(m)`，即 `cap(m) >= ceilDiv(W(m), D)`；实现对 ratio 不先取整，但按后一形式比较：除法形式不会溢出，任意 `govRatioMultiplier`（含极大值）都不会让结算回滚并锁死该行动。上限未触发时 `actualOwnerReward == theoreticalOwnerReward`，不产生取整粉尘销毁；触发时按 `cap(m)` 全额向下取整。

其中 `theoreticalOwnerReward(m)` 使用上节权重公式；治理权按**铸造时的当前 Round** 读取 `Stake.govVotes(actionTokenAddress, currentPhase, m)` 和 `Stake.totalGovVotes(actionTokenAddress, currentPhase)`，`currentPhase = IPhase.currentPhase()`，不是被结算的 `round`。上限启用且社区总治理权为零时只销毁 owner 理论激励；乘数为零直接关闭上限。已结算的查询返回记录结果，不重新套用后续票权。

`govRatioMultiplier` 与 `publicVerifierRatio` 来自服务 Proposal 的创建配置。Owner 超额按人记入 `ownerBurned`，由 Executor 调用服务代币的 `burn(amount)`。这是已铸代币的余额销毁。未达标服务 Proposal 的预留额度可通过 Core 的 `burnProposalReward` 释放。

成员级结清每次结算发出两条事件：基座的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` 记公共口径，本接口的 `ServiceRewardsDistributed(...)` 追加角色细分。两者必须满足 `MemberRewardMinted.mintAmount == verifierReward + ownerReward` 且 `.burnAmount == ownerBurned`，因此基座的「可铸造」在本接口是**聚合值**（服务轮次的可铸造量不是标量，公共验证者与 owner 两部分独立计算），逐个角色的金额仍读 `serviceRewardByMemberId`。`ServiceRewardsDistributed` 与 `serviceRewardByMemberId` 同时给出 owner 份额的拆分：`ownerDistributed` 为实际转给二次分配接收者的总额（逐笔见 `RecipientPaid`），`ownerRemaining` 为留在 owner 手中的部分（含无配置行动的整份切片与逐项取整余数），恒有 `ownerReward == ownerDistributed + ownerRemaining`。

## 二次分配

groupId 的当前 NFT 持有人按 `sourceTokenAddress + sourceActionId + groupId + round` 配置 `recipientIds[]`、`ratios[]`；查询指定 `round` 没有配置时，回退到不晚于该轮的最近配置，不使用未来轮次；不存在更早配置时视为未配置。所有对同一源行动提供激励的服务 Proposal 复用该配置。接收者为 memberId，比例使用 `1e18` 精度。owner 部分先按各源行动权重拆分，再应用对应配置：`slice(a, m) = mulDiv(actualOwnerReward(m), groupReward(a, m), ownerWeightNumerator(m))`（该 owner 权重为零时无此路径）；公共验证者部分直接给锁定验证者，不参与二次分配。

二次分配配置接口见 [`IGroupRecipients.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupRecipients.sol)（含配置枚举 `actionIdsWithRecipients` 与任意金额试算 `distribution`）；结算结果查询 `rewardDistribution` 与单接收者投影 `rewardByRecipientId` 见 [`IGroupServiceExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupServiceExecutor.sol)（后者返回指定接收者的分配额，`recipientId` 等于 `groupId` 时返回 owner 自留额，非接收者返回 0）。

setRecipients 沿用旧 GroupRecipients：只写当前验证 Round，不允许指定已结束轮次；同轮更新覆盖该轮配置。源行动未由本 Executor 创建时回滚 `UnknownSourceAction(sourceTokenAddress, sourceActionId)`；三数组等长回滚 `RecipientArrayLengthMismatch(recipientIdsLength, ratiosLength, remarksLength)`、最多 8 项回滚 `TooManyRecipients(count, MAX_RECIPIENTS_PER_ACTION)`（协议级编译期常量）、逐项比例为正回滚 `ZeroRecipientRatio(recipientId)`、接收 NFT 有效（无效由 `IMemberNFT.ownerOf` 回滚）、不得重复回滚 `DuplicateMemberId(memberId)`、不得等于 groupId 回滚 `RecipientIsGroupId(groupId, recipientId)`；缺失链群回 `GroupNotExist(groupId)`，非 groupId 当前持有人调用回滚 `NotGroupOwner(groupId)`，且鉴权先于轮次校验。**校验次序（实现口径）**：链群存在性与调用者（`onlyGroupOwner`：`GroupNotExist` → `NotGroupOwner`）→ 轮次（`currentVerifyRound()` 作为实参先求值）→ 参数（`_checkRecipients`：三数组等长 / 条数 / 比例 / 重复 / 自身 / 接收 NFT 有效）→ 源行动存在性（`UnknownSourceAction`）→ 上限资格（非空配置、该 action 不在累计集合、集合已达 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP` 时回滚 `RecipientActionsLimitExceeded(address sourceTokenAddress, uint256 groupId, uint256 actual, uint256 limit)`，`actual` 为判定时集合内的源行动数、`limit` 为该上限常量）。`E-GR-02` 的处置范围是**库内顺序**：参数先于源行动存在性；外层修饰器的链群存在性与调用者顺序未变，也没有被重排。全部传空表示显式清空，该轮及后续回退到空配置，不能重新找到清空前配置。没有配置时 owner 保留全部该项预算。转账对象是**结算时**接收 NFT 的当前持有人，不是配置时的持有人：配置只固定名单与比例，所有权在结算那一刻判定；NFT 转让后新持有人取得该轮分配（`forceClearJoinState` 同口径：处分权随当前持有人）。配置变更发 `RecipientsChanged`，按新表→旧表携带 `recipientIds`/`ratios`/`remarks` 与 `prevRecipientIds`/`prevRatios`/`prevRemarks`；`remarks` 每条不超过 `256` 字节，条数不超过 `MAX_RECIPIENTS_PER_ACTION`；单条超出回滚 `RemarkTooLong(index, length, maxLength)`。

配置按 `sourceTokenAddress + groupId` 维护按轮枚举：本轮非空写入登记源行动、显式清空移除，`actionIdsWithRecipients(sourceTokenAddress, groupId, round, offset, limit, reverse)` 分页返回该轮有效的已配置源行动与真实总数（懒继承到不晚于该轮的最近记录；同轮配置更新会重写该轮快照）。该集合是**累计集合**而非本轮集合：跨轮继承的项仍占位并计入上限，单个 `(sourceTokenAddress, groupId)` 最多登记 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP`（16）个源行动；配满后须先对其中一个已登记行动显式清空（传空表）才能为新行动让位。该集合用 swap-and-pop 删除：同一 `offset` 的返回内容不保证跨调用稳定，`reverse` 也不等于「新到旧」；调用方不得跨调用缓存 `offset`，也不得按「先拉首页再增量补页」拼接。`distribution(sourceTokenAddress, sourceActionId, groupId, round, groupReward)` 对任意金额按同规则试算（逐项向下取整、余数归 owner，100% 不下溢）。

配置比例总和不得超过 `1e18`，超过回滚 `DistributionOverflow(configured, limit)`；正好 100% 合法。判据逐项前置：单项大于 `1e18` 时 `configured` 为该单项值，累计超过 `1e18` 时为「已累计 + 本项」，两种情况都不进入 `uint256` 溢出（不产生 `Panic`）。金额逐步向下取整：

```text
amount[i] = mulDiv(slice(a, m), ratios[i], 1e18)
```

各项取整后的总支出不得超过对应预算，`slice` 层与 owner 总量层的舍入余数都归 owner；100% 分配不得下溢。旧版两处双重 floor 曾使「单链群理论激励之和」超过可铸造量，100% 分配时 `mintReward - distributed` 下溢、整笔铸造回滚；本版全部中间量不提前截断，**`Σ 转账 + 销毁 ≤ serviceReward` 为承重不变量**，回归用例见 [Action 验收](08-testing.md)。

逐笔转账由 `RecipientPaid(serviceTokenAddress, serviceActionId, round, groupId, sourceTokenAddress, sourceActionId, recipientId, amount)` 留痕（每个收款人一条；`serviceTokenAddress`、`serviceActionId`、`groupId` 为 indexed，即第 1、2、4 个字段，`round` 不 indexed，字段顺序以 `IGroupServiceExecutor.sol` 为准）；事件流连同 `MemberRewardMinted` 与服务代币的 `TokenBurned` 可完整还原结算的全部资产变化。

结算内的事件顺序固定为：写成员账本 → `TokenBurned`（若有销毁）→ 逐笔 `RecipientPaid` → 两笔 `safeTransfer`（owner 余量与验证者份额）→ `MemberRewardMinted` → `ServiceRewardsDistributed`。两条汇总事件都排在明细之后：`ServiceRewardsDistributed` 的 `ownerDistributed` / `ownerRemaining` 依赖分配循环结果，属[事件规范 §3.4 E5](../../event-standards.md#34-批量与顺序)的依赖序逆序；`MemberRewardMinted` 声明的是「已结算」，只有在 burn 与转账完成后才成立，属 §3.4 E6 的结算聚合例外，与 E5 构成同一结算尾部的两条相邻汇总。测试必须断言 `MemberRewardMinted` 晚于最后一条 `RecipientPaid`、且早于 `ServiceRewardsDistributed`。

## 入口与鉴权主体

按 dev-standards §5.5 列出映射；本合约的链群 owner 判定留在自身（没有对应业务库），成员判定走基座：

| 入口 | 鉴权主体 | 定义位置 | 调用方附加 |
| --- | --- | --- | --- |
| `join`、`exit` | `memberId` 当前持有人 | `ExecutorBase.onlyMemberOwner` | 均 `nonReentrant` |
| `setRecipients` | `groupId` 当前持有人 | 本合约 `onlyGroupOwner`（`GroupRecipients` 库不判调用者） | 无锁（只读依赖） |
| `onProposalCreated` / `onProposalSubmitted` / `onProposalVoted` | ActionTarget | `ExecutorBase.onlyActionTarget` | 库内不重复判定 |
| `mintMemberReward`、`mintMemberRewards` | `memberId` 当前持有人 | `ExecutorBase.onlyMemberOwner` | 结算入口 |
| `distribution` / `rewardDistribution` 等查询 | 无（只读） | — | — |

`GroupRecipients` 是被 `delegatecall` 的库：它只提供 `distribute` 与配置写入的内部实现，鉴权由调用方（本合约）先行完成——库单独被调用不具备鉴权能力（同 `05-group-action-executor.md` 的库内回调口径）。

## 实现约束

- `DistributionOverflow(configured, limit)` 在配置比例总和超过 `limit`（协议上限 `1e18`）时触发；正好 `1e18` 合法。单项超过 `1e18` 直接以该项为 `configured` 触发，不先累加，因此超大比例不会先冒 `Panic(0x11)`。
- **协议常量默认不进 ABI**（与 `05-group-action-executor.md` 的编译期常量段一致）；`PRECISION`、`MAX_RECIPIENTS_PER_ACTION` 与 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP` 例外地以 `public constant` 暴露，只为链下对齐取整精度与配置上限，登记为口径偏差，不改变语义。
- **`setRecipients` 不设锁**：它只调用只读外部依赖（`IMemberNFT.ownerOf`、ActionTarget / 本合约自身存储），不动钱；若将来加入外呼或资金路径，必须同批加 `nonReentrant`（与 05 的无锁配置入口同口径）。
- **轮次契约由调用方保证**：`setRecipients` 的 `round` 必须是当前验证轮，由调用方在提取时确认；库与合约都不把 `round` 与 `currentPhase()` 比较，只把它写成按轮快照。链下按已配置轮读取，不要用未来轮。
- 二次分配配置键为 `sourceTokenAddress + sourceActionId + groupId + round`；分配事件另带服务 Proposal 上下文。
- 二次分配配置面单独声明接口 `IGroupRecipients.sol`（沿用旧文件名，由 `IGroupServiceExecutor` 继承），实现落在独立业务库 `GroupRecipients`：与单体 Executor 合并会超过 24,576 字节部署上限。
- ownerBurned 按 `serviceTokenAddress + serviceActionId + round + memberId` 保存实际销毁量，`ownerDistributed`/`ownerRemaining` 按同一键记录（恒有 `ownerReward = ownerDistributed + ownerRemaining`），不影响源行动激励的读取；铸造与销毁失败时标记、转账和代币 burn 全部回滚。
- 来源为旧 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol`、`LOVE20TKM/extension-group/src/GroupRecipients.sol` 与 `LOVE20TKM/extension/src/ExtensionBaseReward.sol`。公共验证者份额及全社区分母以本文件 BSC 规则为准。

铸造见 [统一链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。

## 状态口径

- 结算金额依赖结算时点的治理权读取结果，不是 `(actionToken, round, memberId)` 的纯函数；同一键在不同区块可能算出不同数量，索引方不得把首次观察值当唯一真值。
- 分母和验证者权重随评分完成增长。进入服务铸造窗口后直接读取对应来源社区的最终总量，零表示该轮没有正数来源激励。
- 服务代币必须实现 `burn(uint256)`；合约不校验，上限绑定时才暴露，由部署期代币选择保证。
- `RecipientsChanged` 的 `prev*` 是懒继承解析后的**有效值**，不是本轮原值；配置懒继承意味着「配一次永久生效」，集合无法区分「本轮配过」与「继承来的」。
- `distribute` 只随收款人维度增长：action 维度由单个 `(sourceTokenAddress, groupId)` 的 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP`（16）封顶，上界为 `MAX_RECIPIENT_ACTIONS_PER_TOKEN_GROUP × MAX_RECIPIENTS_PER_ACTION` = 128 次收款人级外呼（每次 `ownerOf` + `safeTransfer` + 一条 `RecipientPaid`），另加至多 16 次行动切片读取；成本由份额承担，与社区行动总数无关。`setRecipients` 不校验链群激活状态，任意链群 owner 可在停用链群上配比例。
- Owner 权重计算的遍历范围最多为来源社区当轮的 1,000 个提案。跨轮累积的参与行动数量不影响遍历长度。领取前可以分笔准备权重，为二次分配预留 gas。

## 错误卷补记（2026-11，X-06 / X-09）

- `E-GR-03`：没有「比例之和为零」的独立错误——空表是显式清空（合法），非空表每项比例必须 `> 0` 故和 `≥ 1`，`Σ ratio == 0` 只能由空表达成，语义自洽。
- `E-GSE-05`：`onlyGroupOwner` 用裸名引用本地 `IGroupServiceExecutorErrors`，`GroupActionManager` 用限定名引用 `IGroupActionManagerErrors`；两处同名同签名，协议级「一名一签名」不受影响。
