# GroupActionExecutor · 状态变量变更审查

> `action/src/GroupActionExecutor.sol`，750 行（修复提交后 749 行），`action@0c1d1e2`。
> 职责：链群行动的宿主合约。**自身只声明 1 个存储变量**（`GroupActionStorage.Layout internal _layout`），全部业务状态在 `04-group-action-executor` 对应的三个业务库里经 `delegatecall` 写入。本卷审的是「哪个入口能改 Layout 的哪些字段」以及「唯一留在本合约的两处写入」（`_mintMemberReward`、构造函数）。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `_layout` | `GroupActionStorage.Layout` | 全部业务状态（58 个字段，见 `10-group-action-storage.md`） | 经三个业务库的 `delegatecall` |
| 2 | `VOTE_ADDRESS` | `address immutable` | Core `Vote`（`maxJoinAmount` 的票源） | 构造器 `:32` |
| 3-6 | `ACTION_TARGET_ADDRESS` / `STAKE_ADDRESS` / `MEMBER_NFT_ADDRESS` / `PHASE_ADDRESS` | `address immutable` | 继承自 `ExecutorBase` | `ExecutorBase:20-25` |
| — | `_status` | `uint256` | `ReentrancyGuard` | `nonReentrant` |

`_layout` 是**整个合约唯一可变的业务存储**。它的 58 个字段全部是 mapping（含 6 个 `Uint256Set.Storage` / `AddressSet.Storage` / `RoundHistory*` 结构体），没有数组型顶层字段——唯一的动态数组是 `SPLITS`（`:33`，构造器写一次，永不改）。

## 2. 逐变量变更逻辑

### 2.1 构造函数（`:31-34`）

| 位置 | 语句 | 说明 |
| --- | --- | --- |
| `:32` | `VOTE_ADDRESS = IStake(STAKE_ADDRESS).VOTE_ADDRESS()` | 第 5 个 immutable；比 `ExecutorBase` 多一层 |
| `:33` | `_layout.SPLITS = splits` | **唯一一处直接写 `_layout` 的构造函数语句**；此后 `SPLITS` 无写点 |

`SPLITS` 只由部署脚本保证「非空时每项 `0 < split < 1e18` 且严格递增」（`05-group-action-executor.md:7`），合约不校验。它直接决定 `_upsertRank` 的容量（`SPLITS.length + 1`）与 `_checkOpenVerifier` 的下标上界（`SPLITS[rank - 1]`），见 `06-group-action-verify.md` 的 §3 I7。

### 2.2 写入口 → Layout 字段矩阵

21 个写入口，按业务模块分组。每个入口的「鉴权」一列是最终生效的那一层（Executor 的 `nonReentrant` 另计）。

| 入口 | 鉴权 | 写入的 Layout 字段 |
| --- | --- | --- |
| `onProposalCreated:104` | `onlyActionTarget` | `joinTokenAddressByActionId`、`activationStakeAmountByActionId`、`maxJoinAmountRatioByActionId`、`activationMinGovRatioByActionId`、`verifierStakeAmountByActionId`、`verificationKeysByActionId`、`verificationDescriptionsByActionId`、`createdRoundByActionId`（8 个，全写一次） |
| `onProposalVoted:112` | `onlyActionTarget` | `voteAmountByApplicationId`、`voterIdsByApplicationId`、`voteAmountByApplicationIdByVoterId`、`rankedApplicationIds` |
| `join:128` | 库 `onlyMemberOwner(memberId)` | `joinedRoundHistoryByMemberId`、`groupHistoryByMemberId`、`memberIdsByGroupId`、`groupIdsByRound`、`membershipCountByGroupIdByMemberId`、`membershipCountByTokenAddress`、`joinedTokenAddressesByGroupIdByMemberId`、`joinedGroupIds`、`joinedGroupIdsByMemberId`、`joinedMemberIds`、`joinedMemberIdsByGroupId`、`verificationValueHistory`、`ownAmountHistoryByMemberId`（或 `providerAmountHistoryByMemberId` + `providerIdsByMemberId` + `providerAmountByMemberIdByProviderId`）、`joinedAmountByGroupId`、`joinedAmountByActionId` |
| `withdraw:143` | 库 `onlyMemberOwner(memberId)` | `ownAmountHistoryByMemberId`、`joinedAmountByGroupId`、`joinedAmountByActionId`；归零时另走 `_finalizeExit` 的 8 个字段 |
| `exit:162` | 库 `onlyMemberOwner(memberId)` | 同上 + `providerAmountHistoryByMemberId`、`providerIdsByMemberId`、`providerAmountByMemberIdByProviderId`（逐个 Provider 归零） |
| `addProviderQuota:208` | 库 `onlyMemberOwner(providerId)` | `quotaAmountByGroupIdByProviderIdByMemberId`、`quotaMemberIdsByGroupIdByProviderId` |
| `removeProviderQuota:222` | 库 `onlyMemberOwner(providerId)` | 同上 + 已投入部分的 `providerAmount*` / `joinedAmount*`；归零时走 `_finalizeExit` |
| `withdrawProviderQuota:148` | 库 `onlyMemberOwner(providerId)` | `quotaAmountByGroupIdByProviderIdByMemberId`、`quotaMemberIdsByGroupIdByProviderId`（只动可用额度，不动参与量） |
| `submitOriginScores:320` | 库 `onlyMemberOwner(verifierId)` | `lockedVerifierId`、`originScoreDeductionByMemberId`、`finalScoreByGroupId`、`totalFinalScore`、`verifiedMemberCountByGroupId`、`verifiedGroupCountByRound`、`roundVerified` |
| `submitVerifierApplication:380` | 库 `onlyMemberOwner(verifierId)` | `applicationIdCount`、`currentApplicationId`、`activeApplicationIds`、`applicationIdHistory`、`applicationVerifierId`、`applicationDescription`（+ 替换时移除旧申请） |
| `cancelVerifierApplication:392` | 库 `onlyMemberOwner(verifierId)` | `activeApplicationIds`、`rankedApplicationIds`、`currentApplicationId`、`applicationIdHistory` |
| `activateGroup:505` | 库 `onlyGroupOwner(groupId)` | `groupState`、`descriptionHistoryByGroupId`、`activeGroupIdsByActionId`、`stakedByActionId`、`totalStaked`、`stakedByMemberId`、`tokenAddressesByGroupId`、`actionIdsByGroupId`、`activeActionIds` |
| `deactivateGroup:515` | 库 `onlyGroupOwner(groupId)` | 同上（反向）+ `groupState.active/deactivatedRound` |
| `setGroupConfig:520` | 库 `onlyGroupOwner(groupId)` | `groupState.config`、`descriptionHistoryByGroupId` |
| `mintMemberReward:51`（基类） | `nonReentrant onlyMemberOwner(memberId)` | `memberMinted`、`memberMintedReward`（修复提交后不再写 `memberBurnedReward`，见 M-GAE-01） |
| `mintMemberRewards:60`（基类） | 同上 | 同上（循环） |

19 个读入口不写状态；`joinInfo`/`joinedAmount*` 等只读 Layout 或转发到 `ActionTarget`。

### 2.3 `_mintMemberReward`（`:700-749`）——本合约唯一的本地写入

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:706-713` | `_checkMintWindow(..., createdRound, memberMinted)` | 四段守卫 |
| 2 | `:715-716` | `totalFinal != 0 && isRoundVerified(round)` | 两个条件都满足才继续 |
| 3 | `:717-718` | `memberFinalScore = finalScore(round, memberId)` | 位置化前缀推导 |
| 4 | `:719-724` | 读 `actionReward`；`!actionMinted && proposalReward != 0` → `mintActionReward` | 铸给本合约 |
| 5 | `:725` | `mintAmount = floor(proposalReward * memberFinalScore / totalFinal)` | — |
| 6 | `:729-731` | `mintAmount == 0 && burnAmount == 0` → revert | 见 M-GAE-01 |
| 7 | `:733-734` | 写两个结算槽（修复提交后删除了第三个写入） | — |
| 8 | `:736-738` | `safeTransfer(msg.sender, mintAmount)` | 从本合约余额转 |
| 9 | `:740-747` | `MemberRewardMinted` | — |

`burnAmount` 在整个函数里**没有任何赋值**，因此第 6 步实际等价于 `mintAmount == 0`。修复提交把 `memberBurnedReward` 的写入（原 `:735`）整行删除：该槽从 Layout 消失，`memberReward` 的 `burnAmount` 直接返回字面量 `0`。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| G1 | `_layout` 的每个字段只有一个业务库负责写 | ✅ | 见 §2.2 矩阵：配置面只由 Manager 写、参与面只由 Join 写、验证面只由 Verify 写、结算面只由本合约写 |
| G2 | `Σ mintAmount <= 该轮已铸给本合约的数量` | ✅ | 每个成员 `floor(P·s_i/T)`，Σ ≤ P（向下取整） |
| G3 | 同一成员同一轮至多一次 | ✅ | `memberMinted` 先于转账写入 |
| G4 | `_layout.createdRoundByActionId[t][a] == ActionTarget._createdRoundByActionId[t][a]` | ⚠️ 两份独立副本 | 同一笔内各写一次 `currentPhase()`，无交叉断言（见 M-GAE-02） |
| G5 | `memberBurnedReward` 恒为 0 | 已删除（A-12） | 槽位与唯一写入点在修复提交中删除，`memberReward` 固定返回 `0` |
| G6 | `generatedActionRewardByGroupId` 不会除零 | ✅ | `_isRoundRewardable` 要求 `totalFinalScore != 0`（`:677`），且 `groupFinalScore == 0` 早退（`:85-87`） |
| G7 | 结算不依赖「群当前是否激活」 | ✅ | `_memberFinalScore` 只读按轮分数，不读 `groupState.active` |

## 4. 发现

### M-GAE-01 · `memberBurnedReward` 是死槽，`burnAmount` 恒为 0，`MemberRewardMinted.burnAmount` 因此永远为 0

| 字段 | 值 |
| --- | --- |
| 位置 | `:700-749`（无任何 `burnAmount =` 赋值）、`GroupActionStorage:168`（槽位）、`:747`（事件字段） |
| 级别 | Info |
| 证据 | E1 |

`_mintMemberReward` 声明 `returns (uint256 mintAmount, uint256 burnAmount)`，但函数体内**没有一处给 `burnAmount` 赋值**，它恒为 0。连带三个后果：

1. `GroupActionStorage.memberBurnedReward`（第 58 个字段，源码 `:168`）永远读到 0，占用一个 4 层嵌套 mapping 的槽位定义；
2. `MemberRewardMinted.burnAmount` 在 GroupAction 路径上恒为 0，与 `GroupServiceExecutor` 的同名事件字段（治理上限触发时可非零）语义不一致——同一个事件名在三个发射者上承载不同含义（`LpExecutor` 同样无销毁路径，也恒为 0）；
3. `if (mintAmount == 0 && burnAmount == 0)` 的第二个合取项是死条件。

这与 ADR-004「行动激励无销毁机制」一致：GroupAction 侧确实没有任何销毁路径。既然 ADR 已把「无销毁」定为设计，建议把 `memberBurnedReward` 从 Layout 里删掉（Layout 变更需整体重部署，本仓无生产部署，成本为零），或至少在规格里写明「GroupAction 的 `burnAmount` 恒为 0」——否则集成方会按 LpExecutor 的形状去解析它。

**处置（已裁决：删除槽位）**：A-12 采纳「删除死槽」。修复提交同时做三件事：`GroupActionStorage` 删除 `memberBurnedReward`；`GroupActionExecutor` 删除唯一写入点（原 `:735`）；`memberReward` 的 `burnAmount` 改为固定 `0`、签名不变。修复后 Layout 57 字段，`GroupActionExecutor` 750 → 749 行（`:735` 之后上移 1 行），`GroupActionStorage` 190 → 188 行；`voterIdsByApplicationId`、`voteAmountByApplicationIdByVoterId` 各前移一个槽位（详见 `10-group-action-storage.md`）。

### M-GAE-02 · 同一个「创建轮」在 ActionTarget 与三个 Executor 的 Layout 里各存一份，无交叉断言

| 字段 | 值 |
| --- | --- |
| 位置 | `ActionTarget:453`（`_createdRoundByActionId`）、`GroupActionManager:123`、`LpExecutor:121`、`GroupServiceExecutor:428` |
| 级别 | Info |
| 证据 | E1 |

四个合约各自保存 `tokenAddress + actionId → 创建轮`，四处都在同一笔里写同一个 `IPhase.currentPhase()`。它们被用于不同的判定：

| 副本 | 用途 |
| --- | --- |
| `ActionTarget` | `registerJoinState` 的加入下界（`JoinNotOpen`） |
| GroupAction Layout | `activateGroup` / `submitVerifierApplication` 的「行动存在」哨兵 + 结算下界 |
| LpExecutor | 结算四段守卫的第一、二段 |
| GroupServiceExecutor | `_isSettleableRound` 的下界 |

正常路径下四者恒等（同块、同 `currentPhase()`、同笔写入）。但没有任何断言把「ActionTarget 的创建轮」与「Executor 的创建轮」绑在一起：如果将来新增一个不写 `createdRound` 的 Executor，或者某个 Executor 的创建回调在 `currentPhase()` 之外另取轮次，**加入窗口与结算窗口就会错位一格**，而两处都不会报错——只会在边界轮次上静默多算或少算一轮。

这是「同一事实存多份」的典型代价。规格 `01-action-target.md` 只说注册表事实由 `ActionRegistered` 承担，没有说明「创建轮」有四个副本。

### M-GAE-03 · 1 wei 级份额永久不可领取，且与「未验证」在视图上不可区分

| 字段 | 值 |
| --- | --- |
| 位置 | `:725`、`:729-731`、`:636-670`（`memberReward` 视图） |
| 级别 | Info |
| 证据 | E2 |

`mintAmount = floor(proposalReward * memberFinalScore / totalFinal)`。当 `memberFinalScore > 0` 但 `proposalReward * memberFinalScore < totalFinal` 时，`mintAmount == 0` → `:729` 回滚 `MemberActionRewardUnavailable`，且**不写 `memberMinted`**。

后果：该成员的份额（< 1 wei）永久留在合约里，每次重试都回滚同一个错误，`memberReward` 视图返回 `(0, 0, false)`——与「目标轮未完成验证」的返回值完全相同。链下无法区分「再等等」与「永远领不到」。

规模上限：每个成员至多损失 1 wei，全轮合计不超过成员数。不是资金安全问题，但它让「可领取」这个判断在边界上失真。

### M-GAE-04 · 首次结算后整笔激励进入合约余额，未领取部分没有回收路径

| 字段 | 值 |
| --- | --- |
| 位置 | `:719-724`（`mintActionReward` 铸给 `bound = 本合约`）、`:737-739`（逐成员转出） |
| 级别 | Info |
| 证据 | E1 |

`mintActionReward` 一次把该轮整笔 `proposalReward` 铸给本合约（`ActionTarget:275` 的 `bound` 就是本合约），之后每个成员各自领自己那份。未被领取的部分永久留在合约余额里：

- 未验证或分数为 0 的成员（`memberFinalScore == 0` 时 `_memberFinalScore` 返回 0，`mintAmount = 0` → 回滚，不标记）；
- M-GAE-03 的 1 wei 残渣；
- 从未调用 `mintMemberReward` 的成员。

合约没有 sweep / rescue / burn 入口（`G-04` 已确认全仓无管理员角色）。这与 ADR-004 的「不可分配的行动激励永久未结算」是同一现象在「已铸但未分配」一侧的镜像，但 ADR-004 只覆盖了「未铸」那一半。建议在 ADR 里补一句「已铸未领取的部分同样不可回收」。

## 5. 已核对为正确的点

- 三个业务库的写入口在 Executor 侧全部是薄壳（`:104-527`），没有一处本地状态写，因此「谁写了 Layout 的哪个字段」可以完全由库的源码回答——这是拆库方案最容易被破坏的性质，本合约保住了。
- 12 个动钱入口全部带 `nonReentrant`（`GAE-07` 已登记，本卷复核：`:128`、`:143`、`:148`、`:162`、`:208`、`:222`、`:380`、`:392`、`:505`、`:515` + 基类两个）。
- `_mintMemberReward` 的三个结算槽在同一段内写完（`:733-735`），且早于两次外部调用（`:738`），不存在「已标记未付款」的中间态。
- `_isRoundRewardable`（`:672-679`）同时要求 `totalFinalScore != 0` 与 `isRoundVerified`，因此 `generatedActionReward*` 不会在「部分批次已计分但未验完」时返回正值——这正是规格 `05:94` 的「不返回部分结果」。
- `generatedActionRewardByGroupId` 在 `groupFinalScore == 0` 时早退（`:85`），避免 `mulDiv(0, x, T)` 与「该群无参与」混淆。
- `SPLITS` 只有构造器一个写点，`SPLITS()` 只读；没有 setter。
- `VOTE_ADDRESS` 从 `Stake.VOTE_ADDRESS()` 派生而非入参，与 `ExecutorBase` 的派生链同源，不会分叉。

## 6. 覆盖缺口

- 58 个 Layout 字段的**写入语义**分派到 `05`（Join）、`06`（Verify）、`07`（Manager）、`10`（Layout 总表）三卷，本卷只做「入口 → 字段」的映射，不重复论证。
- 未复核 `delegatecall` 到三个业务库时的存储槽冲突：三个库共享同一个 `Layout storage`，字段由编译器按 struct 布局分配，理论上无重叠；本卷按 `GroupActionStorage.Layout` 的声明顺序认定，未做 `forge inspect storage-layout` 实测。
- 未审 21 个入口的事件发射（见 `action-events-audit-2026-11` 的 `02-group-action-executor.md`）。
- 未审 19 个读入口的分页边界（见 `action-api-auth-2026-11` 的 `04-group-action-executor.md`）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GAE-01` | 已裁决：删除槽位（A-12）+ 已修复 | Layout 删字段、删唯一写入、`memberReward` 的 `burnAmount` 固定 `0`；见本条与 `10-group-action-storage.md` |
| `M-GAE-02` | 规格补写 | [`05-group-action-executor.md`](../../docs/specs/action/05-group-action-executor.md) 的「状态口径」：创建轮在四处各存一份，由 `onProposalCreated` 一次写入，运行期无交叉断言 |
| `M-GAE-03` | 设计保留 | 1 wei 级残渣无回收路径，在卷头 §5.3 与 §7 登记，不改源码 |
| `M-GAE-04` | 设计保留 | 已铸未领取部分无 sweep（ADR-004 只覆盖未铸未结算），在 §5.3 登记，不改源码 |
