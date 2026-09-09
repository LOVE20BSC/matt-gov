# action 层接口对比

状态列取值同 [core.md](core.md)。跨层共性变化见 [README](README.md#跨层结构变化)。

## 本层最大的结构变化：实例模型 → 单例多社区模型

旧 `extension` 体系为每个 `tokenAddress + actionId` 部署一个 extension 实例，由工厂创建并在 `ExtensionCenter` 注册。因此旧接口分两类：

- **实例自身接口**（`ILp`、`IGroupAction`、`ITokenJoin`、`IReward`、`IJoin`、`IExtension`）：不带 `tokenAddress`/`actionId` 参数，作用域即该实例，如 `deduction(round, account)`。
- **共享单例接口**（`IGroupJoin`、`IGroupManager`、`IGroupVerify`、`IGroupRecipients`）：首参传 `address extension` 定位实例，如 `join(extension, groupId, amount, verificationInfos)`。

新 action 层每类 Executor 是一个单例合约，服务所有代币社区与行动。因此：

- 旧实例接口的函数统一补齐 `address tokenAddress, uint256 actionId` 前缀参数。
- 旧共享接口的 `address extension` 首参替换为 `address tokenAddress, uint256 actionId`。
- 全部工厂接口删除：`IExtensionFactory`、`ILpFactory`、`IGroupActionFactory`、`IGroupServiceFactory`、`IExtensionGroupActionFactory`、`IExtensionGroupServiceFactory`。
- `FACTORY_ADDRESS()`、`initialize(address factory_)`、`initializeIfNeeded()`、`initialized()`、`TOKEN_ADDRESS()`、`actionId()` 一律删除，改为各 Executor 的 `init(...)` 一次性依赖注入。

以下各节不再对每个函数重复标注这一层参数变化的理由。

## 继承关系与完整 ABI 规模

新 action 层有 4 个接口带继承，其**完整 ABI = 自身声明 + 继承成员**。下表给出总数，各节表格只列自身声明的部分。

| 接口 | 自身声明 | 继承自 | 完整 ABI |
| --- | --- | --- | --- |
| `IActionTarget` | 12 | `IProposalTarget`（3） | 15 |
| `ILpExecutor` | 16 | `IProposalTarget`（3） | 19 |
| `IGroupActionExecutor` | 42 | `IGroupActionIndexes`（51）+ `IProposalTarget`（3） | 96 |
| `IGroupServiceExecutor` | 15 | `IProposalTarget`（3） | 18 |

旧侧对应情况：旧 `IAdminBanSource`/`IGroupMemberScope`/`IGroupJoinScopeSource`/`IGovVotedBanSource` 均通过 `is IPostBanSource`/`is IPostScopeSource` 继承行为契约（见 [group-chat.md](group-chat.md)）；旧 `IExtensionGroupActionFactory is IGroupActionFactory, IExtensionFactory`，随工厂体系一并删除。

---

## 1. IActionTarget vs IExtensionCenter + IExtension

旧：`LOVE20TKM/extension/src/interface/IExtensionCenter.sol`、`IExtension.sol`。

新 `IActionTarget` 继承 `IProposalTarget`，承担「提案与执行合约关联 + 通用加入/退出登记 + 激励中转」。旧 `ExtensionCenter` 的注册中心、委托和验证信息职责不迁移。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `isAccountJoined(tokenAddress, actionId, uint256 memberId)` | `IExtensionCenter.isAccountJoined(tokenAddress, actionId, address account)` | 改参 |
| `join(tokenAddress, actionId, uint256 memberId)` | `IExtensionCenter.addAccount(tokenAddress, actionId, address account, verificationInfos[])` | 改名+改参（`verificationInfos` 移入各 Executor 的 `join`） |
| `exit(tokenAddress, actionId, uint256 memberId)` | `IExtensionCenter.removeAccount(tokenAddress, actionId, address account) returns (bool)` | 改名+改参（去返回值） |
| `actionIdsByMemberId(tokenAddress, memberId) returns (uint256[])` | `IExtensionCenter.actionIdsByAccount(tokenAddress, address account, address[] factories) returns (actionIds[], extensions[], factories_[])` | 改名+改参（去 factories 参数与两个返回数组） |
| `actionIdsByMemberIdCount`、`actionIdsByMemberIdAtIndex` | 无 | 新增 |
| `executor(tokenAddress, uint256 proposalId)` | `IExtensionCenter.extension(tokenAddress, actionId)` | 改名 |
| `forceExit(tokenAddress, actionId, memberId)` | 无 | 新增（应急登记清理） |
| `mintProposalReward(tokenAddress, round, proposalId) returns (uint256 amount)` | 无 | 新增（激励中转） |
| `proposalIdsByExecutor(tokenAddress, round, address executor_)` | 无 | 新增 |
| `proposals(tokenAddress, round) returns (proposalIds[], executors[])` | 无 | 新增 |
| `init(memberNFTAddress, submitAddress, voteAddress, mintAddress)` | 无 | 新增 |
| 继承 `IProposalTarget` 三回调 | 无 | 新增 |
| 无 | `IExtensionCenter.registerActionIfNeeded(tokenAddress, actionId)` | 删除（改由 `onProposalCreated` 回调建立关联） |
| 无 | `IExtensionCenter.factory(tokenAddress, actionId)` | 删除 |
| 无 | `IExtensionCenter.setExtensionDelegate`、`extensionDelegate`、`extensionTokenActionPair` | 删除 |
| 无 | `IExtensionCenter.isAccountJoinedByRound(...)` | 删除 |
| 无 | `IExtensionCenter.accounts`、`accountsCount`、`accountsAtIndex`、`accountsByRound`、`accountsByRoundCount`、`accountsByRoundAtIndex` | 删除（成员枚举下移各 Executor） |
| 无 | `IExtensionCenter.updateVerificationInfo`、`verificationInfo`、`verificationInfoByRound` | 删除（KV 化） |
| 无 | `IExtensionCenter.uniswapV2FactoryAddress`、`launchAddress`、`stakeAddress`、`submitAddress`、`voteAddress`、`joinAddress`、`verifyAddress`、`mintAddress`、`randomAddress` | 删除 9 个 getter（新 `init` 只注入 4 个依赖） |
| 无 | `IExtension.joinedAmount()`、`joinedAmountByAccount(account)`、`joinedAmountTokenAddress()` | 删除（金额查询下移各 Executor） |

旧 `IExtension` 另有 4 个错误全部删除：`InvalidTokenAddress`、`ActionIdNotFound`、`MultipleActionIdsFound`、`RoundNotFinished`；1 个事件 `Initialize` 删除（改为 `init` 一次性注入，无事件）。`FACTORY_ADDRESS`、`TOKEN_ADDRESS`、`actionId`、`initializeIfNeeded`、`initialized` 5 个成员按本层开头的实例模型规则删除。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ProposalLinked(tokenAddress, proposalId, address executor)` | `IExtensionCenter.RegisterAction(tokenAddress, actionId, extension, factory)` | 改名+改参 |
| `ActionJoined(tokenAddress, actionId, memberId, round, amount, isExperience, providerMemberId)` | `IExtensionCenter.AddAccount(tokenAddress, round, actionId, address account, accountCount)` | 改名+改参 |
| `ActionExited(tokenAddress, actionId, memberId, round, isExperience, providerMemberId)` | `IExtensionCenter.RemoveAccount(tokenAddress, round, actionId, address account, accountCount)` | 改名+改参 |
| `ActionWithdrawn(...)`、`ForceExited(tokenAddress, actionId, memberId)` | 无 | 新增 |
| 无 | `IExtensionCenter.SetExtensionDelegate`、`UpdateVerificationInfo`；`IExtension.Initialize` | 删除 |

### 错误

新 9 个：`AlreadyInitialized`、`InvalidKVLength`、`InvalidExecutor`、`UnauthorizedCallback`、`NotMemberOwner(memberId)`、`ProposalNotVoted(tokenAddress, proposalId)`、`InvalidRound(round)`、`RewardAlreadyMinted(tokenAddress, actionId, memberId, round)`、`IndexOutOfBounds(length)`。

旧 `IExtensionCenter` 13 个错误全部删除，其中三项有语义继承：`InvalidExtensionAddress`/`InvalidExtensionFactory` → `InvalidExecutor`、`ActionNotVotedInCurrentRound` → `ProposalNotVoted`、`OnlyExtensionOrDelegate`/`OnlyAccountOrExtensionOrDelegate` → `UnauthorizedCallback`。`AccountAlreadyJoined`、`VerificationInfoLengthMismatch`、`RoundExceedsJoinRound`、`ExtensionCreatorMismatch`、`ExtensionTokenAddressMismatch`、`ExtensionActionIdMismatch`、`ActionAlreadyRegisteredToOtherAction`、`InvalidAccountAddress` 无对应声明。

---

## 2. ILpExecutor vs ILp + ITokenJoin + IReward

旧：`LOVE20TKM/extension-lp/src/interface/ILp.sol`、`LOVE20TKM/extension/src/interface/ITokenJoin.sol`、`IReward.sol`。仅迁移 V2 LP 业务，V1 实现与旧 LP 工厂不迁移。

三阶段轮次（投票、加入、铸币）。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `GOV_RATIO_MULTIPLIER()`、`MIN_GOV_RATIO()` | `ILp` 同名 | 保留 |
| `deduction(tokenAddress, actionId, round, memberId) returns (amount, joinBlocks[], joinAmounts[])` | `ILp.deduction(round, address account) returns (deduction, joinBlocks[], joinAmounts[])` | 改参 |
| `totalDeduction(tokenAddress, actionId, round)` | `ILp.totalDeduction(round)` | 改参 |
| `govRatio(tokenAddress, actionId, round, memberId) returns (ratio, claimed)` | `ILp.govRatio(round, address account) returns (ratio, claimed)` | 改参 |
| `join(tokenAddress, actionId, memberId, amount, verificationInfos[])` | `ITokenJoin.join(uint256 amount, string[] verificationInfos)` | 改参 |
| `exit(tokenAddress, actionId, memberId)` | `ITokenJoin.exit()` | 改参 |
| `withdraw(tokenAddress, actionId, memberId, amount)` | 无（旧只有全额 `exit`） | 新增（部分撤回） |
| `joinedAmountByRound(tokenAddress, actionId, round)` | `ITokenJoin.joinedAmountByRound(round)` | 改参 |
| `joinedAmountByMemberIdByRound(tokenAddress, actionId, memberId, round)` | `ITokenJoin.joinedAmountByAccountByRound(address account, round)` | 改名+改参 |
| `joinedAmount(tokenAddress, actionId)` | `IExtension.joinedAmount()` | 改参 |
| `joinedAmountByMemberId(tokenAddress, actionId, memberId)` | `IExtension.joinedAmountByAccount(address account)` | 改名+改参 |
| `currentVoteRound()`、`currentJoinRound()`、`currentMintRound()` | 无 | 新增（阶段映射显式化） |
| `init(actionTargetAddress, memberNFTAddress, phaseAddress, stakeAddress, mintAddress, pairFactoryAddress)` | 无 | 新增 |
| 继承 `IProposalTarget` | 无 | 新增 |
| 无 | `ITokenJoin.JOIN_TOKEN_ADDRESS()` | 删除（LP 场景由 `pairFactoryAddress` 推导） |
| 无 | `ITokenJoin.WAITING_BLOCKS()` | 删除 |
| 无 | `ITokenJoin.joinInfo(account) returns (joinedRound, amount, lastJoinedBlock, exitableBlock)` | 删除（LP 无退出等待期） |
| 无 | `IReward.reward(round)`、`rewardByAccount`、`claimReward`、`claimRewards`、`burnInfo` | 删除（领取模型 → 铸造分发模型） |
| 无 | `IReward.burnRewardIfNeeded(round)` | 删除（`IGroupServiceExecutor` 仍保留同名函数） |

### 事件与错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ActionJoined`、`ActionWithdrawn`、`ActionExited` | `ITokenJoin.Join(tokenAddress, round, actionId, address account, amount)`、`Exit(...)` | 改名+改参（统一为含 `memberId`/`isExperience`/`providerMemberId` 的三事件） |
| `ActionRewardMinted(tokenAddress, actionId, round, totalAmount, bytes32 recipientType)` | `IReward.ClaimReward(tokenAddress, round, actionId, address account, mintAmount, burnAmount)` | 改名+改参 |
| `RewardBurned(tokenAddress, actionId, round, amount, bytes32 reason)` | `IReward.BurnReward(tokenAddress, round, actionId, amount)` | 改名+改参 |
| 错误 `InsufficientGovRatio()` | `ILp.InsufficientGovRatio()` | 保留 |
| 错误 `AlreadyInitialized`、`InvalidKVLength`、`UnauthorizedCallback`、`InvalidParticipationAmount`、`InvalidRound`、`NotMemberOwner`、`ProposalNotVoted`、`RewardAlreadyMinted` | 无 | 新增 |
| 无 | `ITokenJoin.InvalidJoinTokenAddress`、`JoinAmountZero`、`NotJoined`、`NotEnoughWaitingBlocks`；`IReward.AlreadyClaimed` | 删除（`JoinAmountZero` 语义并入 `InvalidParticipationAmount`） |

---

## 3. IGroupActionExecutor vs IGroupAction + IGroupManager + IGroupJoin + IGroupVerify

旧：`LOVE20TKM/extension-group/src/interface/IGroupAction.sol`、`IGroupManager.sol`、`IGroupJoin.sol`、`IGroupVerify.sol`。四个旧接口合并为一个 Executor。

**继承**：`IGroupActionExecutor is IGroupActionIndexes, IProposalTarget`。因此其完整 ABI = 自身声明的 42 个函数 + 继承的 51 个 `g*` 索引函数（见第 4 节）+ 3 个 `IProposalTarget` 回调，共 96 个。下文表格只列自身声明的部分，`g*` 索引按第 4 节的组名收敛。

四阶段轮次（投票、加入、验证、铸币）。

### 结构体

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `GroupConfig { description, maxCapacity, minJoinAmount, maxJoinAmount, maxAccounts }` | `IGroupManager.GroupInfo { groupId, description, maxCapacity, minJoinAmount, maxJoinAmount, maxAccounts, isActive, activatedRound, deactivatedRound }` | 改名+改参（配置与状态拆分） |
| `VerifierApplication { applicationId, memberId, description, ratioForPublicVerifier, votes, active }` | 无 | 新增 |

状态字段（`isActive`、`activatedRound`、`deactivatedRound`）从结构体移到 `groupInfo()` 的返回值。

### 链群配置

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `activateGroup(tokenAddress, actionId, groupId, GroupConfig)` | `IGroupManager.activateGroup(extension, groupId, description, maxCapacity, minJoinAmount, maxJoinAmount, maxAccounts_)` | 改参（展开参数 → 结构体） |
| `deactivateGroup(tokenAddress, actionId, groupId)` | `IGroupManager.deactivateGroup(extension, groupId)` | 改参 |
| `updateGroupInfo(tokenAddress, actionId, groupId, GroupConfig)` | `IGroupManager.updateGroupInfo(extension, groupId, newDescription, newMaxCapacity, newMinJoinAmount, newMaxJoinAmount, newMaxAccounts)` | 改参 |
| `groupInfo(tokenAddress, actionId, groupId) returns (config, active, activatedRound, deactivatedRound)` | `IGroupManager.groupInfo(extension, groupId) returns (GroupInfo)` | 改参 |
| `JOIN_TOKEN_ADDRESS()`、`ACTIVATION_STAKE_AMOUNT()`、`MAX_JOIN_AMOUNT_RATIO()`、`ACTIVATION_MIN_GOV_RATIO()` | `IGroupAction` 同名 | 保留 |
| 无 | `IGroupManager.descriptionByRound`、`activeGroupIdsByOwner`、`activeGroupIds`(+`Count`/`AtIndex`)、`isGroupActive`、`maxJoinAmount`、`stakedByOwner`、`staked`、`totalStaked`、`totalStakedByOwner`、`hasActiveGroups`、`PRECISION` | 删除 11 项 |
| 无 | `IGroupManager.tokenAddressesByGroupId`(+`Count`/`AtIndex`)、`actionIdsByGroupId`(+`Count`/`AtIndex`)、`actionIds`(+`Count`/`AtIndex`) | 删除（能力由 `IGroupActionIndexes` 的 `g*` 索引覆盖） |

### 参与与体验资产

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `join(tokenAddress, actionId, groupId, memberId, amount, verificationInfos[])` | `IGroupJoin.join(extension, groupId, amount, verificationInfos[])` | 改参 |
| `exit(tokenAddress, actionId, memberId)` | `IGroupJoin.exit(extension)` | 改参 |
| `withdraw(tokenAddress, actionId, memberId, amount)` | 无 | 新增（部分撤回） |
| `joinInfo(tokenAddress, actionId, round, memberId) returns (joinedRound, amount, groupId)` | `IGroupJoin.joinInfo(extension, round, address account) returns (joinedRound, amount, groupId, address provider)` | 改参（去 `provider` 返回） |
| `memberIdsByGroupId(tokenAddress, actionId, round, groupId)` | `IGroupJoin.accountsByGroupId(extension, round, groupId)` | 改名+改参 |
| `joinedAmountByMemberId(tokenAddress, actionId, round, memberId)` | `IGroupJoin.joinedAmountByAccount(extension, round, address account)` | 改名+改参 |
| `groupIds(tokenAddress, actionId, round)` | `IGroupVerify.groupIds(extension, round)` | 改参 |
| `trialJoin(tokenAddress, actionId, groupId, memberId, providerMemberId, verificationInfos[])` | `IGroupJoin.trialJoin(extension, groupId, address provider, verificationInfos[])` | 改参 |
| `trialWithdraw(tokenAddress, actionId, memberId, providerMemberId, amount)` | `IGroupJoin.trialExit(extension, address account)` | 改名+改参（全额退出 → 按额撤回） |
| `trialAccountsWaitingAdd(tokenAddress, actionId, groupId, providerMemberId, uint256[] memberIds, uint256[] amounts)` | `IGroupJoin.trialAccountsWaitingAdd(extension, groupId, address[] trialAccounts, uint256[] trialAmounts)` | 改参 |
| `trialAccountsWaitingRemove(tokenAddress, actionId, groupId, providerMemberId, uint256[] memberIds)` | `IGroupJoin.trialAccountsWaitingRemove(extension, groupId, address[] trialAccounts)` | 改参 |
| `trialAccountsWaiting(tokenAddress, actionId, groupId, providerMemberId) returns (memberIds[], amounts[], blockNumbers[])` | `IGroupJoin.trialAccountsWaiting(extension, groupId, address provider) returns (accounts[], trialAmounts[], blockNumbers[])` | 改参 |
| `trialAmount(tokenAddress, actionId, round, memberId, providerMemberId)` | 无 | 新增 |
| 无 | `IGroupJoin.trialAccountsWaitingRemoveAll`、`trialAccountsWaitingCount`、`trialAccountsWaitingAtIndex`、`trialAccountsJoined`(+`Count`/`AtIndex`) | 删除 6 项 |
| 无 | `IGroupJoin.groupIdByAccount` | 删除（`joinInfo` 返回 `groupId`） |
| 无 | `IGroupJoin.totalJoinedAmountByGroupId`、`joinedAmount`、`totalJoinedAmountByGroupOwner` | 删除，见 [待确认 4](README.md#待确认) |
| 无 | `IGroupJoin.accountsByGroupIdCount`、`accountsByGroupIdAtIndex`、`accountIndexByGroupId` | 删除 |

### 验证与验证者竞选

新增公开验证者竞选机制（票据 [03-public-verifier-election](../bsc-protocol-migration/issues/03-public-verifier-election.md)），旧版按链群 owner 指派/委托验证。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `submitOriginScores(tokenAddress, actionId, round, verifierMemberId, groupId, startIndex, originScores[])` | `IGroupVerify.submitOriginScores(extension, groupId, startIndex, originScores[])` | 改参（新增 `round`、`verifierMemberId`） |
| `originScore(tokenAddress, actionId, round, memberId) returns (score, verified)` | `IGroupVerify.originScoreByAccount(extension, round, address account) returns (uint256)` | 改名+改参（新增 `verified` 返回） |
| `finalScore(tokenAddress, actionId, round, memberId)` | `IGroupVerify.accountScore(extension, round, address account)` | 改名+改参 |
| `totalFinalScore(tokenAddress, actionId, round)` | `IGroupVerify.totalGroupScore(extension, round)` | 改名+改参 |
| `verifiedMemberCount(tokenAddress, actionId, round, groupId)` | `IGroupVerify.verifiedAccountCount(extension, round, groupId)` | 改名+改参 |
| `isRoundVerified(tokenAddress, actionId, round)` | `IGroupVerify.isVerified(extension, round, groupId)` | 改名+改参（粒度 groupId → round） |
| `lockedVerifierId(tokenAddress, actionId, round)` | `IGroupVerify.verifiers(extension, round)`(+`Count`/`AtIndex`) | 改名+改参（多验证者列表 → 单一锁定验证者） |
| `applyForVerifier(tokenAddress, actionId, memberId, description, ratioForPublicVerifier) returns (applicationId)` | 无 | 新增 |
| `cancelVerifierApplication(tokenAddress, actionId, memberId)` | 无 | 新增 |
| `currentApplicationId`、`verifierApplication`、`verifierApplicationsCount`、`verifierApplicationAtIndex`、`rankedApplicationIds` | 无 | 新增 5 项 |
| `generatedActionRewardByGroupId(tokenAddress, actionId, round, groupId)` | `IGroupAction.generatedActionRewardByGroupId(round, groupId)` | 改参 |
| `generatedActionRewardByVerifier(uint256 verifierMemberId, round)` | `IGroupAction.generatedActionRewardByVerifier(address verifier, round)` | 改参 |
| `init(actionTargetAddress, memberNFTAddress, phaseAddress, stakeAddress, mintAddress, uint256[] splits)` | `IGroupManager.initialize(factory_)`、`IGroupJoin.initialize(factory_)`、`IGroupVerify.initialize(factory_)` | 改名+改参（三处初始化合并为一处） |
| 无 | `IGroupVerify.setGroupDelegate`、`delegateByGroupId`、`canVerify`、`verifierByGroupId`、`submitterByGroupId` | 删除（验证者由竞选锁定，不再按链群委托） |
| 无 | `IGroupVerify.distrustVote`、`distrustVotesByGroupOwner`、`distrustVotesByVoterByGroupOwner`、`distrustReason`、`distrustVotersByGroupOwner`(+`Count`/`AtIndex`)、`distrustGroupOwners`(+`Count`/`AtIndex`)、`distrustRateByGroupId` | 删除 11 项（不信任投票机制整块不迁移） |
| 无 | `IGroupVerify.groupIdsByVerifier`(+`Count`/`AtIndex`)、`actionIdsByVerifier`(+`Count`/`AtIndex`)、`actionIds`(+`Count`/`AtIndex`)、`groupIdsCount`/`groupIdsAtIndex` | 删除 11 项 |
| 无 | `IGroupVerify.totalAccountScore`、`groupScore`、`MAX_ORIGIN_SCORE`、`PRECISION` | 删除 |

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ActionJoined`、`ActionWithdrawn`、`ActionExited` | `IGroupJoin.Join(...)`、`Exit(...)`（各含 3 个 accountCount 字段） | 改名+改参 |
| `VerificationBatchSubmitted(tokenAddress, actionId, groupId, round, batchIndex, scores[])` | `IGroupVerify.SubmitOriginScores(tokenAddress, round, actionId, groupId, startIndex, count, isComplete)` | 改名+改参（新增 `scores` 明细，去 `isComplete`） |
| `VerifierApplied`、`VerifierLocked` | 无 | 新增 |
| `ActionRewardMinted`、`RewardBurned` | 无（旧在 `IReward`） | 新增 |
| 无 | `IGroupManager.ActivateGroup`、`DeactivateGroup`、`UpdateGroupInfo` | 删除，**已确认需补回**（见下） |
| 无 | `IGroupJoin.TrialAccountsWaitingUpdated` | 删除 |
| 无 | `IGroupVerify.SetGroupDelegate`、`DistrustVote` | 删除（验证者委托与不信任投票机制不迁移） |

链群激活、停用、配置更新在新接口没有对应事件，属于可观测性净减少。**已确认这三个事件需要补回**——前端依赖它们做索引与通知。见 [README「已裁决待补齐」](README.md#已裁决待补齐)。

### 错误

新 15 个（完整清单）：`AlreadyInitialized`、`InvalidKVLength`、`InvalidParticipationAmount`、`InvalidCandidate`、`InvalidSplits`、`ApplicationNotActive`、`InvalidExecutor`、`UnauthorizedCallback`、`NotMemberOwner`、`ProposalNotVoted`、`InvalidRound`、`InsufficientExperienceQuota`、`VerifierAlreadyLocked`、`BatchIndexMismatch`、`RewardAlreadyMinted`。

其中 5 个有旧对应：`InvalidParticipationAmount` ← `JoinAmountZero`/`AmountBelowMinimum`、`InvalidCandidate` ← `NotVerifier`、`ApplicationNotActive` ← `GroupNotActive`（语义近似）、`AlreadyInitialized` 保留、`BatchIndexMismatch` ← `InvalidStartIndex`。

本接口独有的 3 个：`InvalidSplits`（`init` 的 `splits` 分成配置校验）、`VerifierAlreadyLocked`（新增的验证者竞选锁定）、`InsufficientExperienceQuota(providerMemberId, required, available)`（覆盖部分旧体验额度校验场景）。其余 7 个是全 action 层共用的样板错误（init/KV/回调权限/成员归属/提案未投票/轮次/重复铸造）。

旧三接口共 44 个错误，只有 5 个能映射到新声明（上一段）；其余 39 个按所属接口完整列出如下，均无新声明。**已确认这 39 个校验需要补回对应的错误声明**，实现中仍会触发，不能用 `require` 或通用错误替代。见 [README「已裁决待补齐」](README.md#已裁决待补齐)。

- **`IGroupJoin`（23 个）**：`JoinAmountZero`、`AlreadyInOtherGroup`、`NotJoinedAction`、`AmountBelowMinimum`、`ExceedsActionMaxJoinAmount`、`ExceedsGroupMaxJoinAmount`、`GroupCapacityExceeded`、`GroupAccountsFull`、`CannotJoinInactiveGroup`、`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`、`InvalidGroupId`、`AlreadyJoined`、`TrialAlreadyJoined`、`TrialArrayLengthMismatch`、`TrialAccountIsProvider`、`TrialAccountZero`、`TrialAmountZero`、`TrialAccountAlreadyAdded`、`TrialAccountNotInWaitingList`、`TrialProviderMismatch`、`AlreadyInitialized`、`InvalidFactoryAddress`。
- **`IGroupManager`（8 个）**：`GroupAlreadyActivated`、`GroupNotActive`、`InvalidMinMaxJoinAmount`、`CannotDeactivateInActivatedRound`、`OnlyGroupOwner`、`NotRegisteredExtensionInFactory`、`InsufficientActivationMinGovRatio`、`NoGovVotes`。
- **`IGroupVerify`（13 个）**：`OriginScoresEmpty`、`NotVerifier`、`ScoreExceedsMax`、`AlreadyVerified`、`InvalidStartIndex`、`ScoresExceedAccountCount`、`VerifyVotesZero`、`DistrustVoteExceedsVerifyVotes`、`InvalidReason`、`DistrustVoteZeroAmount`、`OnlyGroupOwner`、`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`。

按语义分组：容量校验（`GroupCapacityExceeded`、`GroupAccountsFull`、`ExceedsActionMaxJoinAmount`、`ExceedsGroupMaxJoinAmount`）、归属校验（`AlreadyInOtherGroup`、`AlreadyJoined`、`NotJoinedAction`）、体验资产校验（`TrialAlreadyJoined`、`TrialArrayLengthMismatch`、`TrialAccountIsProvider`、`TrialAccountZero`、`TrialAmountZero`、`TrialAccountAlreadyAdded`、`TrialAccountNotInWaitingList`、`TrialProviderMismatch`）、权限与初始化校验（`OnlyGroupOwner`、`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`、`InvalidFactoryAddress`）、不信任投票（`DistrustVoteExceedsVerifyVotes`、`DistrustVoteZeroAmount`、`InvalidReason`）。其中体验额度类场景由新接口的 `InsufficientExperienceQuota(providerMemberId, required, available)` 部分覆盖。

---

## 4. IGroupActionIndexes vs IGroupJoin 的 g* 索引

旧：`LOVE20TKM/extension-group/src/interface/IGroupJoin.sol#g*`。17 组索引、51 个函数（每组 3 个：`数组()` / `Count()` / `AtIndex(index)`），一一对应，无增删。

函数命名规则：每组 `<组名>` 派生三个函数 `<组名>(...)`（返回全量数组）、`<组名>Count(...)`（长度）、`<组名>AtIndex(..., index)`（逐项读取）。上表的「新/旧」列写的是**组名**，实际 ABI 是组名 + 这三类后缀。例如第 14 组对应 `gMemberIds` / `gMemberIdsCount` / `gMemberIdsAtIndex`（旧为 `gAccounts` / `gAccountsCount` / `gAccountsAtIndex`）。全文按组名列举是为了可读性，函数级核对请按此规则展开为 51 个。

变化只有两条规则：

1. 命名中的 `Account` → `MemberId`。
2. 参数与返回中的 `address account` → `uint256 memberId`。

| 索引组 | 新 | 旧 |
| --- | --- | --- |
| 1 | `gGroupIds` | 同名 |
| 2 | `gGroupIdsByMemberId` | `gGroupIdsByAccount` |
| 3 | `gGroupIdsByTokenAddress` | 同名 |
| 4 | `gGroupIdsByTokenAddressByMemberId` | `gGroupIdsByTokenAddressByAccount` |
| 5 | `gGroupIdsByTokenAddressByActionId` | 同名 |
| 6 | `gTokenAddresses` | 同名 |
| 7 | `gTokenAddressesByMemberId` | `gTokenAddressesByAccount` |
| 8 | `gTokenAddressesByGroupId` | 同名 |
| 9 | `gTokenAddressesByGroupIdByMemberId` | `gTokenAddressesByGroupIdByAccount` |
| 10 | `gActionIdsByTokenAddress` | 同名 |
| 11 | `gActionIdsByTokenAddressByMemberId` | `gActionIdsByTokenAddressByAccount` |
| 12 | `gActionIdsByTokenAddressByGroupId` | 同名 |
| 13 | `gActionIdsByTokenAddressByGroupIdByMemberId` | `gActionIdsByTokenAddressByGroupIdByAccount` |
| 14 | `gMemberIds` | `gAccounts` |
| 15 | `gMemberIdsByGroupId` | `gAccountsByGroupId` |
| 16 | `gMemberIdsByTokenAddress` | `gAccountsByTokenAddress` |
| 17 | `gMemberIdsByTokenAddressByGroupId` | `gAccountsByTokenAddressByGroupId` |

第 9 组的 `gTokenAddressesByGroupIdByMemberIdCount(groupId, memberId) > 0` 是 group-chat 判断链群归属的约定入口（见 [CONTEXT.md](../../CONTEXT.md)）。

---

## 5. IGroupServiceExecutor vs IGroupService + IGroupRecipients

旧：`LOVE20TKM/extension-group/src/interface/IGroupService.sol`、`IGroupRecipients.sol`。

四阶段轮次，复用 GroupAction 的验证结果，自身不执行验证。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `actionTokenAddress(serviceTokenAddress, serviceProposalId)` | `IGroupService.GROUP_ACTION_TOKEN_ADDRESS()` | 改名+改参（部署常量 → 按提案查询） |
| `totalGroupActionReward(actionTokenAddress, round) returns (reward, cached)` | `IGroupService.generatedActionReward(round)` | 改名+改参（新增 `cached` 返回） |
| `rewardDistribution(serviceTokenAddress, serviceProposalId, round, sourceActionId, groupId) returns (recipientIds[], ratios[], amounts[], ownerAmount)` | `IGroupService.rewardDistribution(address verifier, round, actionId, groupId) returns (addrs[], ratios[], amounts[], ownerAmount)` | 改参（`verifier` → 服务提案定位，`addrs` → `recipientIds`） |
| `setRecipients(sourceTokenAddress, sourceActionId, groupId, uint256[] recipientIds, ratios[], remarks[])` | `IGroupRecipients.setRecipients(tokenAddress, actionId, groupId, address[] addrs, ratios[], remarks[])` | 改参 |
| `recipients(sourceTokenAddress, sourceActionId, groupId, round) returns (recipientIds[], ratios[], remarks[])` | `IGroupRecipients.recipients(address groupOwner, tokenAddress, actionId, groupId, round) returns (addrs[], ratios[], remarks[])` | 改参（去 `groupOwner` 参数） |
| `burnRewardIfNeeded(uint256 round)` | `IReward.burnRewardIfNeeded(round)` | 保留 |
| `join(serviceTokenAddress, serviceProposalId, memberId, verificationInfos[])` | 旧 `IGroupService` 未声明，由 `ITokenJoin.join(uint256 amount, string[] verificationInfos)` 提供 | 跨接口迁移（补齐 `tokenAddress`/`proposalId` 前缀，去掉独立 `amount`） |
| `exit(serviceTokenAddress, serviceProposalId, memberId)` | 旧由 `ITokenJoin.exit()` / `IJoin.exit()` 提供 | 跨接口迁移 |
| `joinInfo(serviceTokenAddress, serviceProposalId, round, memberId) returns (bool joined)` | 旧由 `ITokenJoin.joinInfo(address account)` 提供（返回 `joinedRound, amount, lastJoinedBlock, exitableBlock`） | 跨接口迁移+改参（返回值简化为是否参与） |
| `serviceRewardByMember(serviceTokenAddress, serviceProposalId, round, memberId) returns (verifierReward, ownerReward, ownerBurned, claimed)` | 无 | 新增 |
| `currentVoteRound`、`currentJoinRound`、`currentVerifyRound`、`currentMintRound` | 无 | 新增 |
| `init(actionTargetAddress, memberNFTAddress, phaseAddress, stakeAddress, mintAddress, groupActionExecutorAddress)` | 无 | 新增 |
| 继承 `IProposalTarget` | 无 | 新增 |
| 无 | `IGroupService.GROUP_ACTION_FACTORY_ADDRESS()` | 删除（取消工厂） |
| 无 | `IGroupService.rewardByRecipient(verifier, round, actionId, groupId, recipient)` | 删除 |
| 无 | `IGroupService.hasActiveGroups(address owner)` | 删除 |
| 无 | `IGroupService.generatedActionRewardByVerifier(verifier, round)` | 删除（保留在 `IGroupActionExecutor`） |
| 无 | `IGroupService.govRatio(round, address account)` | 删除（保留在 `ILpExecutor`） |
| 无 | `IGroupService.PRECISION()`、`GOV_RATIO_MULTIPLIER()` | 删除 getter |
| 无 | `IGroupRecipients.getDistribution(groupOwner, tokenAddress, actionId, groupId, groupReward, round)` | 删除（合并进 `rewardDistribution`） |
| 无 | `IGroupRecipients.actionIdsWithRecipients`、`groupIdsByActionIdWithRecipients` | 删除 |
| 无 | `IGroupRecipients.PRECISION()`、`DEFAULT_MAX_RECIPIENTS()` | 删除 getter |

### 事件与错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ServiceRewardDistributed(serviceTokenAddress, serviceProposalId, actionTokenAddress, memberId, verifierReward, ownerReward, ownerBurned, round)` | `IGroupService.ClaimRewardDistribution(tokenAddress, round, actionId, address account, mintAmount, burnAmount, distributed, remaining)` | 改名+改参 |
| `SecondaryDistributionConfigured(sourceTokenAddress, sourceActionId, groupId, round, recipientIds[], ratios[])` | `IGroupRecipients.SetRecipients(tokenAddress, round, actionId, groupId, address account, recipients[], ratios[], remarks[])` | 改名+改参（去 `remarks` 字段） |
| `RewardBurned` | 无 | 新增 |
| 无 | `IGroupService.DistributeRecipient` | 删除（逐笔分配明细无事件） |
| 错误 `DistributionOverflow(configured, available)` | `IGroupRecipients.InvalidRatio()` | 改名+改参（语义近似） |
| 错误 `AlreadyInitialized`、`InvalidKVLength`、`InvalidRound`、`NotMemberOwner`、`ProposalNotVoted`、`UnauthorizedCallback`、`RewardAlreadyMinted` | 无 | 新增 |
| 无 | `IGroupService.NoActiveGroups`、`InvalidExtension`；`IGroupRecipients.TooManyRecipients`、`ZeroAddress`、`ZeroRatio`、`ArrayLengthMismatch`、`DuplicateAddress`、`RecipientCannotBeSelf`、`OnlyGroupOwner` | 删除 9 项 |
