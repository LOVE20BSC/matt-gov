# LOVE20BSC 事件统一规范 · 逐事件差距表

日期：2026-10-26  
状态：已确认（2026-10-26）；本表只做设计裁决，不改代码。**2026-10-28 修订**：O11 改判、`LaunchCountConsumed.count` 删除、stake 系补全局总量、`lpTransferred` → `lpToMember`、`boostSharesAdded` 删除（见 O11/O15 与各事件行）  
基线：`core/src` 23 个声明、`action/src` 27 个声明、`group-chat/src` 23 个声明，共 73 个声明 / 66 个唯一名；全部有发射点；`libs/src` 无事件；`dex` 排除。  
规则索引：见 `matt-gov/docs/event-standards.md`（正文已写）；本文引用裁决编号 Q1–Q32。

---

## 0. 目标模型摘要

- 事件 = 一条业务事实 / 状态迁移；事实增量模型；累计值可选携带，必须等于折叠结果。
- 一条事实一个发射者（状态所有者）；事件声明在发射者 interface；库按 §4.1 的 DELEGATECALL 条件 emit；共享事件类必须同 schema、同语义、共享 interface、规范列明发射者。
- 命名 `<Object><PastParticiple>`；配置变更 `<Object>Changed`；全协议名字/schema 唯一。
- 字段顺序：根键 → 父对象 id 链 → 本对象 id → 角色 → 数值 → 文本/枚举。
- 根键：core/action 用 `tokenAddress`；group-chat 用全局唯一 `groupId`；两条 `TokenGroupActivated` / `TokenActionGroupActivated` 是 token/action ↔ group 的唯一链路。
- indexed ≤3；`round` 视为协议纪元键（不是时间值），可 indexed；actor 与主对象 id 优先。
- 配置变更旧值+新值；旧值恒等可推（布尔取反）可省；初始化与生命周期无旧值。
- 动态字段（`string`/`bytes`/数组）必须有链上强制上限。
- 事件声明与 emit 点均不写注释；每个事件至少一个测试断言；CI 维护 ABI 事件清单基线。

---

## 1. Core（23 个声明）

| # | 现事件（声明） | 目标事件 | 处置 | 目标字段 / 变更 | 备注 |
|---|---|---|---|---|---|
| 1 | `TokenMint` `ILOVE20Token:9` | `TokenMinted` | 改名 | 不变：`to` indexed、`amount` | 初始供给与运行期增发由「同 tx 的 `GenesisTokenCreated` + 日志顺序」区分，不加哨兵字段 |
| 2 | `TokenBurn` `ILOVE20Token:10` | `TokenBurned` | 改名 | 不变：`from` indexed、`amount` | — |
| 3 | `TokenLaunched` `ILaunch:45` | `GenesisTokenCreated` + `TokenLaunched` | 拆分 | 创世：`tokenAddress` i、`parent` i、`distributor`、`name`、`symbol`；发起：`tokenAddress` i、`parent` i、`launcherMemberId` i、`distributor`、`distributorMode`、`name`、`symbol` | 去掉 `launcherMemberId=0` 哨兵；补 `distributorMode` |
| 4 | `LaunchCountAdded` `ILaunch:53` | `LaunchCountAdded` | 改形 | 增 `issuedCount`（该账本累计）、`memberRemaining`（成员余额） | 首 token 镜像双发是两个独立账本，保留 |
| 5 | `LaunchCountMerged` `ILaunch:54` | `LaunchCountMerged` | 改形 | 增 `sourceRemaining`、`targetRemaining` | 转账型合并的双方后置余额 |
| — | — | `LaunchCountConsumed` | 新增 | `tokenAddress` i、`memberId` i、`remaining` | 覆盖 `Launch.sol:161` 的扣减缺口；由 `Launch.launchToken` 发射；`count` 恒为 1，2026-10-28 删除 |
| 6 | `Mint` `IMemberNFT:8` | `MemberMinted` | 改名 | 字段不变，顺序调整：`cost` 前移到 `name` 之前；`id` 改名为 `memberId`（`memberId` i、`owner` i、`cost`、`name`、`normalizedName`） | 顺序按 §6.1 core.member 族：对象 id → 角色 → 数值 → 文本；`id` 与全协议的 `memberId` 同义，按 §6.4 统一 |
| 7 | `AddHolder` `IMemberNFT:16` | `HolderAdded` 或删除 | 删除（已确认） | 若保留：`holder` i、`totalHolders` | 持有人集合可由 ERC721 `Transfer` 折叠；`totalHolders` 为冗余累计；见开放项 O1 |
| 8 | `RemoveHolder` `IMemberNFT:18` | `HolderRemoved` 或删除 | 删除（已确认） | 若保留：`holder` i、`totalHolders` | 同上 |
| 9 | `RewardPrepared` `IMint:11` | `RewardPrepared` | 保留 | 不变（含累计 `rewardReserved`/`rewardBurned`） | 零票分支与正常分支同 schema；原因由同 tx 的 `RewardBurned` 区分 |
| 10 | `GovRewardMinted` `IMint:20` | `GovRewardMinted` | 改形 | 保留 `voteReward`、`boostReward`、`burnReward`（2026-10-28 改判，见 O11） | `_launchCredit` 增量 = `voteReward+boostReward`，可由本事件推导 |
| 11 | `ProposalRewardMinted` `IMint:28` | `ProposalRewardMinted` | 保留 | 不变：`tokenAddress` i、`round` i、`proposalId` i、`recipient`、`amount` | `recipient` 为地址 |
| 12 | `RewardBurned` `IMint:35` | `RewardBurned` | 保留 | 不变：`tokenAddress` i、`round` i、`amount`、`reason` | `reason` 为有界 enum |
| 13 | `PhaseSynchronized` `IPhase:9` | `PhaseSynchronized` | 改形 | 删 `blockNumber`、`timestamp`、`adjusted`；保留 `phase` i、`phaseBlocks` | 块高/时间为日志元数据；`adjusted` 由同 tx 的 `PhaseAdjusted` 推导 |
| 14 | `PhaseAdjusted` `IPhase:16` | `PhaseAdjusted` | 保留 | 不变：`effectivePhase` i、`oldPhaseBlocks`、`newPhaseBlocks` | 新 segment `startBlock` 由日志块高推导 |
| 15 | `StakeLiquidity` `IStake:44` | `LiquidityStaked` | 改名+改形 | 增 `totalLiquidityShares`、`totalValidGovVotes`（全局后置）；其余不变 | LP 基准（`lastFeeLp` 等）为派生缓存，见 §7 |
| 16 | `StakeBoost` `IStake:58` | `BoostStaked` | 改名+改形 | 增 `totalBoostShares`、`totalValidBoostShares`、`totalValidGovVotes`；删与 `boostAmount` 恒等的 `boostSharesAdded` | 余额总量与当轮有效总量并存，见 O15 |
| 17 | `Unstake` `IStake:69` | `Unstaked` | 改名+改形 | 增 `totalValidBoostShares`、`totalValidGovVotes` | `unlockRequestPhase = round`，文档化 |
| 18 | `Withdraw` `IStake:78` | `StakeWithdrawn` | 改名+改形 | 增 `lpBurned`、`lpToMember`、`totalLiquidityShares`、`totalBoostShares` | 覆盖 LP 派发方式；基准为派生缓存；`lpTransferred` 2026-10-28 改名为 `lpToMember` |
| 19 | `FeesSettled` `IStake:88` | `FeesSettled` | 改形 | 增 `totalBurnedToken`、`totalParentTokenBurned`（累计） | 无实现手续费的 early-return 仅写派生缓存，不发事件（§7） |
| 20 | `StakeMerged` `IStake:95` | `StakesMerged` | 改名+改形 | 增 `targetGovVotes`、`targetLiquidityShares`、`targetBoostShares`、`targetPromisedWaitingPhases`、`prevSourceGovVotes`、`prevSourcePromisedWaitingPhases`、`totalValidGovVotes`；indexed 改为 `tokenAddress`、`sourceMemberId`、`targetMemberId`（`round` 改非 indexed） | 修复 target 未 indexed 的不一致；源被清空后其旧状态只能由 `prevSource*` 承载 |
| 21 | `ProposalCreated` `ISubmit:47` | `ProposalCreated` | 改形 | 增 `targetData`（`bytes[]`，新增链上总字节/元素上限）；`title`/`details` 加上限 | `targetData` 是提案可执行载荷，当前只有 calldata 有；见开放项 O4 |
| 22 | `ProposalSubmitted` `ISubmit:57` | `ProposalSubmitted` | 保留 | 不变：`tokenAddress` i、`round`、`submitterId` i、`proposalId` i | — |
| 23 | `Voted` `IVote:19` | `VoteCast` | 改名+改形 | 增 `voterBoost`（成员本轮快照）、`totalVoterBoost`（全局快照） | 覆盖 `Vote.sol:274-280` 的 boost 快照缺口 |

---

## 2. Action（27 个声明 + 新增）

| # | 现事件（声明） | 目标事件 | 处置 | 目标字段 / 变更 | 备注 |
|---|---|---|---|---|---|
| 1 | `MemberRewardMinted` `IActionExecutor:7` | `MemberRewardMinted` | 保留（共享类） | 不变：`tokenAddress` i、`actionId` i、`memberId` i、`round`、`mintAmount`、`burnAmount` | 定义 `mintAmount` = 为该成员铸造的总额（entitlement），不是实收；service 的实收拆分在 `ServiceRewardsDistributed`；见开放项 O3 |
| 2 | `JoinStateRegistered` `IActionTarget:7` | `JoinStateRegistered` | 保留 | 不变 | ActionTarget 注册表事实，与 executor 的 `*Joined` 是两条事实 |
| 3 | `JoinStateCleared` `IActionTarget:13` | `JoinStateCleared` | 保留 | 不变（含 `forced`） | — |
| 4 | `ActionCreated` `IActionTarget:20` | `ActionRegistered` | 改名 | 字段不变，顺序调整：`round` 前移到 `executor` 之前（`tokenAddress` i、`actionId` i、`round`、`executor` i） | 注册表事实；域对象创建由各 executor 的 `*ActionCreated` 承载 |
| 5 | `ActionRewardMinted` `IActionTarget:26` | `ActionRewardMinted` | 保留 | 不变 | — |
| 6 | `GroupActivated` `IGroupActionManager:13` | `GroupActivated` | 改形 | 增初始 config：`description`、`maxCapacity`、`minJoinAmount`、`maxJoinAmount`、`maxAccounts` | 激活即写入 config；当前只带 `stakeAmount`；actor=群主，由 `groupId` 隐含 |
| 7 | `GroupDeactivated` `IGroupActionManager:20` | `GroupDeactivated` | 保留 | 不变 | 旧 active=true 由事件类型表达 |
| 8 | `GroupConfigUpdated` `IGroupActionManager:27` | `GroupConfigChanged` | 改名+改形 | 增旧值+新值：5 个 config 字段 + `description` | Q29(b)；见开放项 O7（体积） |
| 9 | `Joined` `IGroupActionJoin:5` | `GroupActionJoined` | 改名+改形 | 增 `verificationValues`（`string[]`，新增上限）；顺序调整：`groupId`、`providerId` 前移到 `amount` 之前 | 覆盖 `verificationValueHistory` 静默写；见开放项 O6 |
| 10 | `Withdrawn` `IGroupActionJoin:14` | `GroupActionWithdrawn` | 改名 | 字段不变，顺序调整：`groupId`、`providerId` 前移到 `amount` 之前 | provider 回填不再复用本事件，见新增 `ProviderQuotaRefunded` |
| 11 | `Exited` `IGroupActionJoin:23` | `GroupActionExited` | 改名 | 不变 | — |
| 12 | `ProviderQuotaAdded` `IGroupActionJoin:30` | `ProviderQuotaAdded` | 改形 | 增 `quotaTotal`（后置累计） | `quotaBlockNumber` 用日志块高 |
| 13 | `ProviderQuotaRemoved` `IGroupActionJoin:38` | `ProviderQuotaRemoved` | 保留 | 不变 | — |
| — | — | `ProviderQuotaRefunded` | 新增 | `tokenAddress` i、`actionId` i、`groupId` i、`providerId`、`memberId`、`amount` | 替代 `GroupActionJoin.sol:253` 复用 `Withdrawn` 但不是转账的语义漂移 |
| 14 | `Joined` `ILpExecutor:19` | `LpJoined` | 改名 | 不变 | join block 用日志块高 |
| 15 | `Withdrawn` `ILpExecutor:26` | `LpWithdrawn` | 改名 | 不变 | 全额提取应同时发 `LpExited`（行为修复，见 O8） |
| 16 | `Exited` `ILpExecutor:33` | `LpExited` | 改名 | 不变 | — |
| 17 | `SetRecipients` `IGroupRecipients:5` | `RecipientTableChanged` | 改名+改形 | 旧+新 `recipientIds`、`ratios`、`remarks`；三者均加链上上限 | Q31(a)+Q32(a)；见开放项 O7 |
| 18 | `DistributeRecipient` `IGroupServiceExecutor:8` | `RecipientPaid` | 改名+改形 | 增 `sourceTokenAddress`（源行动根键）；每收款人一条 | 循环内逐条 emit，符合 Q8 |
| 19 | `ServiceRewardDistributed` `IGroupServiceExecutor:17` | `ServiceRewardsDistributed` | 改名 | 不变 | `cacheDenominator` 为派生缓存（§7） |
| 20 | `Joined` `IGroupServiceExecutor:29` | `ServiceJoined` | 改名 | 不变 | — |
| 21 | `Exited` `IGroupServiceExecutor:35` | `ServiceExited` | 改名 | 不变 | 与 LP 的 `Exited` topic0 冲突随改名消除 |
| 22 | `OriginScoresSubmitted` `IGroupActionVerify:13` | `OriginScoresSubmitted` | 改形 | 增 `totalFinalScore`、`verifiedGroupCount`、`roundVerified`（后置累计） | 逐成员 finalScore 由 raw scores + `GroupActionJoined.amount` 推导；见 O10 |
| 23 | `VerifierApplicationSubmitted` `IGroupActionVerify:22` | `VerifierApplicationSubmitted` | 改形 | 增 `description`（≤1024B）、`previousApplicationId`（被替换的旧申请）与 `hasPreviousApplication` | 覆盖替换动作静默写 |
| 24 | `VerifierApplicationCancelled` `IGroupActionVerify:29` | `VerifierApplicationCancelled` | 保留 | 不变 | — |
| 25 | `VerifierStakeDeposited` `IGroupActionVerify:36` | `VerifierStakeDeposited` | 保留 | 不变 | — |
| 26 | `VerifierStakeRefunded` `IGroupActionVerify:43` | `VerifierStakeRefunded` | 保留 | 不变 | — |
| 27 | `VerifierLocked` `IGroupActionVerify:50` | `VerifierLocked` | 改形 | `memberId` 改为 indexed；indexed 改为 `tokenAddress`、`actionId`、`memberId`（`round` 改非 indexed） | 与同组其他 verifier 事件对齐 |
| — | — | `GroupActionCreated` | 新增 | `tokenAddress` i、`actionId` i、`joinTokenAddress`、`activationStakeAmount`、`maxJoinAmountRatio`、`activationMinGovRatio`、`verifierStakeAmount`、`verificationKeys[]`、`verificationDescriptions[]` | 覆盖 `GroupActionManager.onProposalCreated` 的 8 项静默写；由 `GroupActionExecutor` 发射；schema 字段需上限 |
| — | — | `ServiceActionCreated` | 新增 | `tokenAddress` i、`actionId` i、`actionTokenAddress`、`govRatioMultiplier`、`ratioForPublicVerifier` | 覆盖 `GroupServiceExecutor.onProposalCreated` 的 4 项静默写 |
| — | — | `LpActionCreated` | 新增 | `tokenAddress` i、`actionId` i、`joinTokenAddress`、`govRatioMultiplier`、`minGovRatio` | 覆盖 `LpExecutor.onProposalCreated` 的 4 项静默写 |
| — | — | `ApplicationVoteRecorded` | 新增 | `tokenAddress` i、`actionId` i、`applicationId` i、`round`、`candidateMemberId`、`votesAdded`、`totalVotes` | 覆盖 `GroupActionVerify.onProposalVoted` 的票数与排名静默写；排名由票数折叠；投票人由同 tx 的 `VoteCast` 关联 |

---

## 3. Group-chat（23 个声明）

| # | 现事件（声明） | 目标事件 | 处置 | 目标字段 / 变更 | 备注 |
|---|---|---|---|---|---|
| 1 | `Activate` `IGroupChat:30` | `GroupChatActivated` | 改名+改形 | 增初始 config：`postingAllowed`、`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`；保留 `groupId` i、`ownerId` i、`owner` i | 首次激活写入的 5 项 config 当前基本静默；零地址=关闭，文档化 |
| 2 | `SetPostingAllowed` `IGroupChat:32` | `PostingAllowedChanged` | 改名 | `postingAllowed`；旧值布尔取反可推，省略 | — |
| 3 | `SetScopeSource` `IGroupChat:36` | `ScopeSourceChanged` | 改名 | 保留 `prevSourceAddress`（旧值非可推） | — |
| 4 | `SetBanSource` `IGroupChat:44` | `BanSourceChanged` | 改名 | 保留 `prevSourceAddress` | — |
| 5 | `SetBeforePostPlugin` `IGroupChat:52` | `BeforePostPluginChanged` | 改名 | 保留 `prevPluginAddress` | — |
| 6 | `SetAfterPostPlugin` `IGroupChat:60` | `AfterPostPluginChanged` | 改名 | 保留 `prevPluginAddress` | — |
| 7 | `PostMessage` `IGroupChat:68` | `MessagePosted` | 改形 | 增 `content`（已有 `MAX_CONTENT_LENGTH`）、`quotedMessageId` + `hasQuote`、`mentionAll`；indexed 改为 `groupId`、`messageId`、`senderId`（`senderAddress` 改非 indexed） | 覆盖消息正文/引用/mentionAll 静默写；见 O5 |
| 8 | `MentionSenderId` `IGroupChat:76` | `SenderMentioned` | 改名 | 不变：`groupId` i、`mentionedSenderId` i、`messageId` i | 每提及一条，符合 Q8 |
| 9 | `MentionAll` `IGroupChat:78` | — | 删除 | 并入 `MessagePosted.mentionAll` | 避免同一事实两条事件 |
| 10 | `FailAfterPostPlugin` `IGroupChat:80` | `AfterPostPluginFailed` | 改名 | 不变（`errorHash`/`errorLength`/`errorSelector`） | Q26 捕获型失败事实 |
| 11 | `SetAdmin` `IGroupAdmin:12` | `AdminChanged` | 改名+改形 | 合并快照：增 `prevListed` 与 `groupOwnerSnapshot`/`adminOwnerSnapshot` 的旧+新值 | 同时覆盖 `removeAdmins` 删除快照的静默写；见 O2 |
| 12 | `SetAdminSnapshot` `IGroupAdmin:16` | — | 删除（合并） | 并入 `AdminChanged` | NFT 转移导致的失效由 core ERC721 `Transfer` 推导；见 O2 |
| 13 | `SetMemberId` `IGroupMember:10` | `MemberStatusChanged` | 改名 | `listed`；旧值布尔取反可推 | — |
| 14 | `SetSenderIdBan` `IGroupChatBanList:11` | `SenderBanChanged` | 改名 | `listed`；旧值布尔取反可推；`operatorAddress` 统一为 `operator` | 解禁时 operator 字段仍为执行者，语义明确 |
| 15 | `SetDelegateId` `IGroupChatDelegate:13` | `DelegateChanged` | 改名+改形 | 增 `ownerSnapshot`/`delegateOwnerSnapshot` 的旧+新值；保留 `prevDelegateId` | 覆盖两个 snapshot 静默写 |
| 16 | `ClearDelegatedGroupId` `IGroupChatDelegate:17` | `DelegationCleared` | 改名+改形 | 增快照旧值（新值为 0） | 清零事实独立于 `DelegateChanged` |
| 17 | `SetDelegatorWhitelistEnabled` `IGroupChatDelegate:19` | `DelegatorWhitelistChanged` | 改名 | `enabled`；旧值布尔取反可推 | — |
| 18 | `SetAllowedDelegatorGroupId` `IGroupChatDelegate:21` | `DelegatorGroupPermissionChanged` | 改名 | `allowed`；旧值布尔取反可推 | — |
| 19 | `SetSenderIdBanVote` `IGovVotedBanSource:17` | `SenderBanVoteCast` | 改名 | 保留累计 `supportWeight`/`opposeWeight`/`stateVersion`；旧方向由上一条事件推 | — |
| 20 | `SetSenderIdBan` `IGovVotedBanSource:28` | `GovSenderBanChanged` | 改名 | `listed`；旧值布尔取反可推 | — |
| 21 | `ChangeStateVersion` `IGovVotedBanSource:30` | `StateVersionChanged` | 改名 | `stateVersion`；旧值=new-1（每次+1），省略 | — |
| 22 | `Activate` `ITokenScopeManagerBase:7` | `TokenGroupActivated` | 改名 | 不变：`tokenAddress` i、`groupId` i、`operator` i | 链路事件 |
| 23 | `Activate` `ITokenActionScopeManagerBase:11` | `TokenActionGroupActivated` | 改名 | `tokenAddress` i、`actionId` i、`groupId` i；`operator` 非 indexed | 纯链路事件的 3 个 indexed 槽给链路键；actor 入 payload |

---

## 4. 新增事件汇总

| 事件 | 发射者 | 触发 | 关键字段 | 覆盖的缺口 |
|---|---|---|---|---|
| `GenesisTokenCreated` | `Launch` | `Launch.init` | `tokenAddress` i、`parent` i、`distributor`、`name`、`symbol` | 创世哨兵 `launcherMemberId=0` |
| `LaunchCountConsumed` | `Launch` | `launchToken` 扣减后 | `tokenAddress` i、`memberId` i、`remaining` | `Launch.sol:161` 静默扣减 |
| `GroupActionCreated` | `GroupActionExecutor` | `onProposalCreated` | 8 项 action 配置 + verification schema | `GroupActionManager.onProposalCreated` 全部静默写；域对象创建事实 |
| `ServiceActionCreated` | `GroupServiceExecutor` | `onProposalCreated` | 4 项 service 配置 | `GroupServiceExecutor.onProposalCreated` 全部静默写；域对象创建事实 |
| `LpActionCreated` | `LpExecutor` | `onProposalCreated` | 3 项 LP 配置 | `LpExecutor.onProposalCreated` 全部静默写；域对象创建事实 |
| `ApplicationVoteRecorded` | `GroupActionVerify` | `onProposalVoted` | `applicationId`、`candidateMemberId`、`votesAdded`、`totalVotes` | 票数/排名静默写 |
| `ProviderQuotaRefunded` | `GroupActionJoin` | `_refundProviders` | `providerId`、`memberId`、`amount` | 复用 `Withdrawn` 的语义漂移 |

---

## 5. 删除 / 合并

| 事件 | 处置 | 理由 | 替代 |
|---|---|---|---|
| `AddHolder` / `RemoveHolder` | 删除（已确认） | 持有人集合可由 ERC721 `Transfer` 折叠；`totalHolders` 为冗余累计 | core `Transfer` |
| `MentionAll` | 删除 | 与 `MessagePosted.mentionAll` 同一事实 | `MessagePosted.mentionAll` |
| `SetAdminSnapshot` | 删除（合并） | 快照变化是 admin 状态的一部分；独立事件在删除快照时又静默 | `AdminChanged` 的旧/新快照字段 |

---

## 6. 配置旧值 / 新值核对

| 配置事件 | 旧值 | 新值 | 结论 |
|---|---|---|---|
| `GroupConfigChanged` | 5 字段 + description | 同 | Q29(b) 落地；体积见 O7 |
| `RecipientTableChanged` | 3 数组 | 同 | Q31(a)+Q32(a)；体积/上限见 O7 |
| `GroupActivated` | 无（初始化） | 5 字段 + description | 初始化无旧值 |
| `ScopeSourceChanged` / `BanSourceChanged` / `*PluginChanged` | `prev*` | 新 | 已有旧值，保留 |
| `AdminChanged` | 两个快照 | 两个快照 | 新增旧值；`listed` 布尔取反可推 |
| `DelegateChanged` | `prevDelegateId` + 两个快照 | 新 | 新增快照旧值 |
| `DelegationCleared` | 两个快照 | 0 | 新增旧值 |
| `PostingAllowedChanged` / `MemberStatusChanged` / `SenderBanChanged` / `DelegatorWhitelistChanged` / `DelegatorGroupPermissionChanged` / `GovSenderBanChanged` | 布尔取反可推 | 新 | 省略旧值（Q32a） |
| `StateVersionChanged` | new-1 | 新 | 省略旧值 |
| `SenderBanVoteCast` | 上一条投票事件 | 新 vote + 累计权重 | 非配置变更，不强制旧值 |

---

## 7. 派生缓存（明确不进入事件，附推导来源）

| 状态 | 位置 | 推导来源 |
|---|---|---|
| `_launchCredit` | `Mint.sol:519,530` | `GovRewardMinted.voteReward+boostReward` − `LaunchCountAdded.count × threshold`；threshold 由 `TokenMinted` + 不可变 `LAUNCH_RATIO`/`maxSupply` 计算 |
| Stake 全局/成员 LP 基准（`lastFeeLp`、`lastWithdrawableLp`、`lastSqrtKOfLp`、`totalLp`） | `Stake.sol:542,545,579-580,692-693,705,731-734` | 由 `LiquidityStaked`/`StakeWithdrawn`/`StakesMerged`/`FeesSettled` 的份额与金额，配合 Uniswap pair `Sync` 折叠 |
| `_pairAddress` | `Stake.sol:475` | `factory.getPair(token,parent)`，可从不可变配置推导 |
| `_lastSettlePhase`、Phase 观测历史 | `Stake.sol:774`、`Phase.sol:102-105` | 内部计时缓存；业务结果由 `FeesSettled`/`PhaseSynchronized`/`PhaseAdjusted` 覆盖 |
| MemberNFT 持有人集合 | `MemberNFT.sol:252-291` | ERC721 `Transfer` 折叠（若删除 `AddHolder`/`RemoveHolder`） |
| `cacheDenominator` | `GroupServiceExecutor.sol:784` | `RecipientTableChanged` 的 ratios + 奖励金额 |
| `_govRatioAtMint` | `LpExecutor.sol:518` | mint 时点的 Stake/Vote 状态 + 既有事件折叠；若需绝对自足，见 O10 |
| `GroupActionVerify` 排名数组 | `GroupActionVerify.sol:420,584-624` | `ApplicationVoteRecorded` 按票数排序 |
| `providerIdsByMemberId` / `providerAmountByProviderId` | `GroupActionJoin.sol:719-728` | `ProviderQuotaAdded/Removed/Refunded` + `GroupActionJoined/Withdrawn` |
| `_joinBlocks` / `_joinAmounts` | `LpExecutor.sol:195-200` | `LpJoined`/`LpWithdrawn` + 日志块高 |
| `_mintNonce` | `ManagerBase.sol:134` | 群创建事件（core `MemberMinted` + manager 链路事件）的计数 |
| delegate 原始索引 | `GroupChatDelegate.sol:22` | `DelegateChanged`/`DelegationCleared` |
| ban 列表 operator 状态 | `GroupChatBanList.sol:128-130` | `SenderBanChanged` 的 actor + `listed` |
| `stateVersion` | `GovVotedBanSource.sol:324` | `StateVersionChanged` 每次 +1 |
| admin 有效性 | `GroupAdmin.sol:129-139` | `AdminChanged` 快照 + core ERC721 `Transfer`（owner 变化） |
| 消息/轮次索引 | `GroupChat.sol:254-258,612-622` | `MessagePosted`/`SenderMentioned` 折叠 |

---

## 8. 审计驱动的规则细化（需确认）

1. **`round` 是协议纪元键，不是时间值**：可 indexed；Q11 的「时间不进 payload/不 indexed」只约束 `block.timestamp`/`block.number`。
2. **indexed 优先级**：根键 → 主对象 id 链 → actor；只有 3 槽，actor 在主对象键占满时降为非 indexed 字段。纯链路事件（`TokenActionGroupActivated`）的 3 槽给链路键，actor 入 payload。
3. **actor 隐含**：当 actor 就是主对象的所有者且主对象 id 已 indexed（`GroupActivated`/`GroupConfigChanged` 的群主、`GroupActionManager` 的 group owner），不再单列 actor 字段。
4. **共享类语义**：`MemberRewardMinted.mintAmount` 统一定义为「为该成员铸造的总额」；service 的实收拆分由 `ServiceRewardsDistributed` 承担。共享类不因实现差异拆分。
5. **事件内不放哨兵**：创世拆事件；`quotedMessageId` 用 `hasQuote` 消除 0 歧义；其余可选 id 只在事实存在时发射，不做哨兵表达。

---

## 9. 已确认处置（2026-10-26）

> 用户 2026-10-26 确认：O1–O14 全部按建议执行；原 `GovernanceRewardMinted` 简化为 `GovRewardMinted`。

| # | 问题 | 建议 | 影响 |
|---|---|---|---|
| O1 | `AddHolder`/`RemoveHolder` 是否删除？ | 删除，持有人集合由 ERC721 `Transfer` 折叠 | 少 2 个事件；`totalHolders` 查询需折叠 |
| O2 | `SetAdminSnapshot` 是否合并进 `AdminChanged`？ | 合并；NFT 转移失效由 core `Transfer` 推导 | 少 1 个事件；`AdminChanged` 增 4 个快照字段（旧/新×2） |
| O3 | `MemberRewardMinted` 共享类语义 | 保留共享；`mintAmount` = 铸造总额，实收拆分在 `ServiceRewardsDistributed` | 三个 executor 不改 schema |
| O4 | `ProposalCreated` 是否携带 `targetData`？ | 携带，新增总字节/元素上限（建议 16 KiB / 16 元素） | 提案接口行为变化；事件体积增加 |
| O5 | `MessagePosted` 是否携带 `content`？ | 携带（已有 `MAX_CONTENT_LENGTH` 上限） | 每条消息日志增大；gas 上升 |
| O6 | `GroupActionJoined` 是否携带 `verificationValues`？ | 携带，新增单值 ≤1024B、数组 ≤16 的上限 | join 事件增大；需新增校验 |
| O7 | `RecipientTableChanged` 旧+新三数组 + `GroupConfigChanged` 旧+新五字段 | 按 Q29(b)/Q32(a) 执行 | 低频配置事件体积翻倍；需给 remarks 加单串上限（建议 256B） |
| O8 | `LpExecutor.withdraw` 全额提取是否补发 `LpExited`？ | 已确认：只要 `_clearJoinState` 执行（全额 withdraw 或 exit），统一发 `LpWithdrawn` + `LpExited`；`exit()` 补 `LpWithdrawn` | 两处 emit + 测试；纳入事件重构 |
| O9 | `forceExit` 的语义与命名 | 已改判：executor 故障时的兜底，只清 ActionTarget 注册表并发 `JoinStateCleared(forced=true)`；**不回调 executor**、不结算资金、不发 `*Exited`；重命名 `forceClearJoinState`（现有 `clearJoinState` 是 executor 回调，不能复用） | 防止有问题的 executor 永久污染成员行动清单；不新增失败事件；实现仅为改名与文档 |
| O10 | `OriginScoresSubmitted` 的逐成员 finalScore / LP 的 `_govRatioAtMint` 是否补字段？ | 先按派生缓存；若要求绝对自足再补 | 事件体积 vs 折叠复杂度 |
| O11 | `GovRewardMinted.burnReward` 是否删除？ | **2026-10-28 改判：保留**。`RewardBurned` 不带 `memberId`，成员归属只能由 `GovRewardMinted` 给出；且 `voteReward + boostReward == 0 && burnReward > 0` 可达，事件名 `Minted` 会失真 | 多一个与 `RewardBurned` 同值的字段，属有意冗余（§3.1） |
| O12 | 需新增的链上上限：`TokenLaunched.name/symbol`（init 路径）、`ProposalCreated.title/details`、`verificationKeys/Descriptions`、`verificationValues`、`remarks`、`targetData` | 全部加上限并写入规范；具体数值见 O4–O7 | 接口级校验变更 |
| O13 | `PostMessage` indexed 是否改为 `groupId, messageId, senderId`？ | 是；`senderAddress` 入 payload | 提高按消息 id 过滤能力；地址过滤需后置 |
| O14 | `VerifierLocked` / `StakesMerged` indexed 对齐 | 按 §1/§2 执行 | 修复同组不一致 |
| O15 | 加速份额是否需要成员级「有效值」字段？ | 不需要：`BoostStaked`/`StakesMerged`/`StakeWithdrawn` 三个时点上 `boostShares` 就是有效值，`Unstaked` 之后有效值恒为 0（由事件名承载）。全局侧相反，`totalBoostShares` 与 `totalValidBoostShares` 会分叉，两者并存 | 成员级不新增字段；全局新增一个总量 |

---

## 10. 验收判据（规范正文引用）

1. 任一对象在任一区块的业务投影 = 其全量事件按日志顺序折叠的结果。
2. 每条事件只由状态所有者发射；共享类发射者在规范中列明。
3. 每个新增/修改事件有测试断言：发射条件、次数、字段顺序、indexed 布局。
4. CI 对比 ABI 生成的事件清单基线；任何事件增删改必须显式更新基线。
5. 规范正文不重复签名；逐事件签名以各仓 `src/interfaces/` 为准。
