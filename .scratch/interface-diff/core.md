# core 层接口对比

状态列取值：`保留`（签名完全一致）、`改名`（仅标识符变）、`改参`（参数或返回值变）、`改名+改参`、`新增`、`删除`。

跨层共性变化（memberId 主体化、错误/事件子接口内联、不再继承 `IPhase`、常量 getter 改 init 参数）见 [README](README.md#跨层结构变化)，本文不重复解释理由。Core 新接口统一使用 `Proposal`；`Action*` 仅出现在旧接口名称或 Action 层语境中。

---

## 1. IMemberNFT vs ILOVE20Group

旧：`LOVE20TKM/group/src/interfaces/ILOVE20Group.sol`。整体复制迁移，仅去 group 字样。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `firstTokenAddress()` | `LOVE20_TOKEN_ADDRESS()` | 改名 |
| `baseDivisor()` | `BASE_DIVISOR()` | 改名 |
| `bytesThreshold()` | `BYTES_THRESHOLD()` | 改名 |
| `multiplier()` | `MULTIPLIER()` | 改名 |
| `maxNameLength()` | `MAX_GROUP_NAME_LENGTH()` | 改名（值 64 → 32 bytes） |
| `mint(string name) returns (uint256 id, uint256 mintCost)` | `mint(string groupName) returns (uint256 tokenId, uint256 mintCost)` | 改名（仅参数/返回名） |
| `calculateMintCost(string calldata name)` | `calculateMintCost(string memory groupName)` | 改名+改参（`memory` → `calldata`） |
| `nameOf(uint256 id)` | `groupNameOf(uint256 tokenId)` | 改名 |
| `idOf(string calldata name)` | `tokenIdOf(string calldata groupName)` | 改名 |
| `isNameUsed(string calldata name)` | `isGroupNameUsed(string calldata groupName)` | 改名 |
| `normalizedNameOf(string calldata name)` | `normalizedNameOf(string calldata groupName)` | 保留 |
| `totalBurnedForMint()` | 同名 | 保留 |
| `holdersCount()` | 同名 | 保留（语义变，见下） |
| `holdersAtIndex(uint256 index)` | 同名 | 保留（语义变，见下） |
| `init(address firstTokenAddress)` | 无（旧为构造函数入参） | 新增 |
| `balanceOf`、`ownerOf`、`safeTransferFrom`×2、`transferFrom`、`approve`、`setApprovalForAll`、`getApproved`、`isApprovedForAll`、`totalSupply`、`tokenByIndex`、`tokenOfOwnerByIndex` | 旧接口未声明（实现继承 ERC721Enumerable） | 新增（显式声明 12 个标准函数） |

`holdersCount`/`holdersAtIndex` 签名不变但语义反转：旧接口注释标为 Deprecated、non-authoritative（自转账后可能失准）；新版规格要求精确维护去重持有人集合，自转账不加入也不移除。见 [`core/02-member-nft.md`](../../docs/specs/core/02-member-nft.md)。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `Mint(uint256 id, address owner, string name, string normalizedName, uint256 cost)` | `Mint(uint256 tokenId, address owner, string groupName, string normalizedName, uint256 cost)` | 改名（仅字段名） |
| `AddHolder(address holder, uint256 totalHolders)` | 同 | 保留 |
| `RemoveHolder(address holder, uint256 totalHolders)` | 同 | 保留 |
| `Transfer`、`Approval`、`ApprovalForAll` | 旧接口未声明 | 新增（ERC721 显式声明） |

### 错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `NameEmpty()` | `GroupNameEmpty()` | 改名 |
| `NameTooLong(uint256 length, uint256 maxLength)` | `GroupNameTooLong(uint256 length, uint256 maxLength)` | 改名 |
| `NameInvalidCharacters()` | `GroupNameInvalidCharacters()` | 改名 |
| `NameAlreadyExists(uint256 existingId)` | `GroupNameAlreadyExists(uint256 existingTokenId)` | 改名 |
| `HolderIndexOutOfBounds(uint256 length)` | 同 | 保留 |
| `AlreadyInitialized()` | 无 | 新增（配合 `init`） |

---

## 2. IPhase vs IPhase

旧：`LOVE20TKM/core/src/interfaces/IPhase.sol`。从「业务轮次时间线」重构为「无语义时间片 + 动态校准」。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `originBlocks()` | 同名 | 保留 |
| `phaseBlocks()` | 同名 | 保留 |
| `currentPhase()` | `currentRound()` | 改名（语义：业务轮次 → 无语义时间片） |
| `phaseAtBlock(uint256 blockNumber)` | `roundByBlockNumber(uint256 blockNumber)` | 改名 |
| `phaseInfo(uint256 phaseNumber) returns (uint256 startBlock, uint256 phaseBlocks_)` | 无 | 新增 |
| `sync() returns (bool adjusted, uint256 newPhaseBlocks)` | 无 | 新增 |
| `syncObservationsCount()` | 无 | 新增 |
| `syncObservation(uint256 observationId) returns (uint256 blockNumber, uint256 blockTimestamp)` | 无 | 新增 |
| 事件 `PhaseSynchronized`、`PhaseAdjusted` | 无 | 新增 |
| 错误 `InvalidPhase(uint256)`、`ObservationNotFound(uint256)` | 无 | 新增 |
| 无 | 错误 `RoundNotStarted()` | Core 不声明；由 Action Executor 与 Group Chat 各自声明 |

旧 `IPhase` 被 6 个 core 接口继承并因此隐式暴露 `currentRound()`；新 `IPhase` 是独立合约接口，不被继承。

---

## 3. ILOVE20Stake vs ILOVE20Stake

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Stake.sol`。去 SL/ST 凭证 + 按 memberId 归属 + 新增融合。

### 结构体

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `StakeData { lpShares, boostShares, promisedWaitingPhases, unlockRequestPhase }` | `AccountStakeStatus { slAmount, stAmount, promisedWaitingPhases, requestedUnstakeRound, govVotes }` | 改名+改参 |
| `TokenStakeGlobals { totalLpShares, withdrawableLp, feeLp, sqrtKOfLp, totalBoostShares }` | 无 | 新增 |

字段对应：`slAmount` → `lpShares`、`stAmount` → `boostShares`、`requestedUnstakeRound` → `unlockRequestPhase`；`govVotes` 字段移除，改由 `validGovVotes()` 查询。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `PROMISED_WAITING_PHASES_MIN()`、`PROMISED_WAITING_PHASES_MAX()` | 同名 | 保留 |
| `govVotesNum(address tokenAddress)` | 同名 | 保留 |
| `stakeLiquidity(tokenAddress, tokenAmount, parentTokenAmount, promisedWaitingPhases, uint256 memberId) returns (govVotesAdded, lpSharesAdded)` | `stakeLiquidity(tokenAddress, tokenAmountForLP, parentTokenAmountForLP, promisedWaitingPhases, address to) returns (govVotesAdded, slAmountAdded)` | 改参 |
| `stakeToken(tokenAddress, tokenAmount, promisedWaitingPhases, uint256 memberId)` | `stakeToken(tokenAddress, tokenAmount, promisedWaitingPhases, address to)` | 改参 |
| `unstake(tokenAddress, uint256 memberId)` | `unstake(tokenAddress)` | 改参 |
| `withdraw(tokenAddress, uint256 memberId)` | `withdraw(tokenAddress)` | 改参 |
| `accountStakeStatus(tokenAddress, uint256 memberId) returns (StakeData)` | `accountStakeStatus(tokenAddress, address account) returns (AccountStakeStatus)` | 改参 |
| `validGovVotes(tokenAddress, uint256 memberId)` | `validGovVotes(tokenAddress, address account)` | 改参 |
| `cumulatedTokenAmountByAccount(tokenAddress, round, uint256 memberId)` | `cumulatedTokenAmountByAccount(tokenAddress, round, address account)` | 改参 |
| `stakeTokenUpdatedRoundsCount(tokenAddress)`、`stakeTokenUpdatedRoundsAtIndex(tokenAddress, index)` | 同名 | 保留 |
| `stakeTokenUpdatedRoundsByAccountCount(tokenAddress, uint256 memberId)`、`stakeTokenUpdatedRoundsByAccountAtIndex(tokenAddress, uint256 memberId, index)` | 同名（`address account`） | 改参 |
| `mergeStake(tokenAddress, sourceMemberId, targetMemberId)` | 无 | 新增 |
| `tokenStakeGlobals(tokenAddress) returns (TokenStakeGlobals)` | 无 | 新增 |
| `canWithdraw(tokenAddress, uint256 memberId)` | 无 | 新增 |
| `init(phaseAddress, memberNFTAddress, voteAddress, routerAddress, pairFactoryAddress, promisedWaitingPhasesMin, promisedWaitingPhasesMax)` | 无 | 新增 |
| 无 | `initialStakeRound(tokenAddress)` | 删除 |
| 无 | `caculateGovVotes(lpAmount, promisedWaitingPhases)` | 删除（旧名含拼写错误） |
| 无 | `cumulatedTokenAmount(tokenAddress, round)` | 删除（保留了按账户版本，去掉全局版本） |

### 事件

四个事件全部保留名称，字段作 memberId 化与份额改名：

| 事件 | 变化 |
| --- | --- |
| `StakeLiquidity` | `address account` → `uint256 memberId`；`slAmountAdded`/`slAmount` → `lpSharesAdded`/`lpShares` |
| `StakeToken` | `address account` → `uint256 memberId`；`stAmount` → `boostSharesAdded` + `boostShares`（字段数 8 → 9） |
| `Unstake` | `address account` → `uint256 memberId`；`slAmount`/`stAmount` → `lpShares`/`boostShares` |
| `Withdraw` | `address account` → `uint256 memberId`；`slAmount` → `lpShares`；`stAmount` → `boostShares`；`tokenAmountForLp`/`parentTokenAmountForLp` → `tokenAmountForLP`/`parentTokenAmountForLP` |

### 错误

保留 10 个错误；删除旧的 `InvalidToAddress()`（新接口不再接收 `to` 地址）：`AlreadyInitialized`、`NotAllowedToStakeAtRoundZero`、`StakeAmountMustBeSet`、`UnstakeAlreadyRequested`、`UnstakeNotRequested`、`PromisedWaitingPhasesOutOfRange`、`PromisedWaitingPhasesMustBeGreaterOrEqualThanBefore`、`NoStakedLiquidity`、`NotEnoughWaitingBlocks`、`RoundHasNotStartedYet`。

---

## 4. ILOVE20Submit vs ILOVE20Submit

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol`。从「行动提案」抽象为「通用 Proposal + Target + KV」，行动特有字段全部移出。

### 结构体与枚举

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ProposalHead { uint256 id, uint256 author, uint256 createAtBlock }` | `ActionHead { uint256 id, address author, uint256 createAtBlock }` | 改名+改参（`author` 类型变） |
| `ProposalBody { string title, string details }` | `ActionBody { minStake, maxRandomAccounts, whiteListAddress, title, verificationRule, verificationKeys[], verificationInfoGuides[] }` | 改名+改参（7 字段 → 2 字段） |
| `ProposalParams { title, details, target, targetMode, keys[], values[] }` | 无 | 新增 |
| `enum TargetMode { NoCallback, Callback }` | 无 | 新增 |
| 无 | `ActionInfo { head, body }` | 删除（`proposal()` 改为多返回值） |
| 无 | `ActionSubmitInfo { address submitter, uint256 actionId }` | 删除（`submissionAtIndex()` 改为多返回值） |

旧 `ActionBody` 的 `minStake`、`maxRandomAccounts`、`whiteListAddress`、`verificationRule`、`verificationKeys`、`verificationInfoGuides` 不进入新 Proposal 主体，改由 `ProposalParams.keys/values` 的不透明 KV 传给对应 Target。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `stakeAddress()` | 同名 | 保留 |
| `SUBMIT_MIN_PER_THOUSAND()` | 同名 | 保留 |
| `MAX_VERIFICATION_KEY_LENGTH()` | 同名 | 保留 |
| `createProposal(tokenAddress, memberId, ProposalParams) returns (uint256 proposalId)` | `submitNewAction(tokenAddress, ActionBody) returns (uint256 actionId)` | 改名+改参 |
| `submit(tokenAddress, memberId, proposalId)` | `submit(tokenAddress, actionId)` | 改参 |
| `canSubmit(tokenAddress, uint256 memberId)` | `canSubmit(tokenAddress, address account)` | 改参 |
| `isSubmitted(tokenAddress, round, proposalId)` | `isSubmitted(tokenAddress, round, actionId)` | 保留（仅参数名） |
| `proposal(tokenAddress, proposalId) returns (head, body, target, targetMode, keys, values)` | `actionInfo(tokenAddress, actionId) returns (ActionInfo)` | 改名+改参 |
| `proposalsCount(tokenAddress)` | `actionsCount(tokenAddress)` | 改名 |
| `proposalsAtIndex(tokenAddress, index) returns (uint256 proposalId)` | `actionsAtIndex(tokenAddress, index) returns (ActionInfo)` | 改名+改参（返回完整结构 → 仅 ID） |
| `submissionsCount(tokenAddress, round)` | `actionSubmitsCount(tokenAddress, round)` | 改名 |
| `submissionAtIndex(tokenAddress, round, index) returns (proposalId, submitterId)` | `actionSubmitsAtIndex(tokenAddress, round, index) returns (ActionSubmitInfo)` | 改名+改参 |
| `currentRound()` | 旧由 `is IPhase` 隐式提供 | 新增（显式声明） |
| `init(phaseAddress, stakeAddress, memberNFTAddress, submitMinPerThousand)` | 无 | 新增 |
| 无 | `canJoin(tokenAddress, actionId, address account)` | 删除（下移 action 层） |
| 无 | `submitInfo(tokenAddress, round, actionId)` | 删除 |
| 无 | `submitInfoBySubmitter(tokenAddress, round, address submitter)` | 删除 |
| 无 | `authorActionIdsCount(tokenAddress, address author)` | 删除 |
| 无 | `authorActionIdsAtIndex(tokenAddress, address author, index)` | 删除 |

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ProposalCreated(tokenAddress, proposalId, uint256 author, string title, string details, address target, TargetMode targetMode)` | `ActionCreate(tokenAddress, round, address author, actionId, ActionBody actionBody)` | 改名+改参 |
| `ProposalSubmitted(tokenAddress, round, uint256 submitterId, proposalId)` | `ActionSubmit(tokenAddress, round, address submitter, actionId)` | 改名+改参 |

`ProposalCreated` 去掉 `round` 字段、`ActionBody` 结构展开为 `title`/`details`、新增 `target`/`targetMode`。

### 错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `AlreadyInitialized()` | 同 | 保留 |
| `ProposalNotFound(uint256 proposalId)` | `ActionIdNotExist()` | 改名+改参（新增参数） |
| `InvalidKVLength()` | 无 | 新增 |
| `IndexOutOfBounds(uint256 length)` | 无 | 新增 |
| 无 | `MinStakeZero()`、`MaxRandomAccountsZero()`、`VerificationRuleEmpty()`、`VerificationKeyLengthExceeded()` | 删除（对应字段已移出 Proposal 主体） |
| 无 | `TitleEmpty()` | 删除（`title` 仍在主体，校验错误未声明） |
| `CannotSubmitAction()`、`AlreadySubmitted()`、`OnlyOneSubmitPerRound()` | 同名 | 保留（沿用旧 Submit 的门槛与去重 selector） |

---

## 5. ILOVE20Vote vs ILOVE20Vote

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Vote.sol`。全量保留，`actionId` → `proposalId`、`account` → `memberId`，新增 KV 与投票者质押量查询。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `stakeAddress()`、`submitAddress()` | 同名 | 保留 |
| `vote(tokenAddress, memberId, proposalIds[], votes[], keys[][], values[][])` | `vote(tokenAddress, actionIds[], votes[])` | 改参（新增 memberId 与二维 KV） |
| `canVote(tokenAddress, uint256 memberId)` | `canVote(tokenAddress, address account)` | 改参 |
| `maxVotesNum(tokenAddress, uint256 memberId)` | `maxVotesNum(tokenAddress, address account)` | 改参 |
| `votesNum(tokenAddress, round)` | 同名 | 保留 |
| `votesNumByProposalId(tokenAddress, round, proposalId)` | `votesNumByActionId(tokenAddress, round, actionId)` | 改名 |
| `votesNumByAccount(tokenAddress, round, uint256 memberId)` | `votesNumByAccount(tokenAddress, round, address account)` | 改参 |
| `votesNumByAccountByProposalId(tokenAddress, round, memberId, proposalId)` | `votesNumByAccountByActionId(tokenAddress, round, address account, actionId)` | 改名+改参 |
| `isProposalIdVoted(tokenAddress, round, proposalId)` | `isActionIdVoted(tokenAddress, round, actionId)` | 改名 |
| `votedProposalIdsCount(tokenAddress, round)` | `votedActionIdsCount(tokenAddress, round)` | 改名 |
| `votedProposalIdsAtIndex(tokenAddress, round, index)` | `votedActionIdsAtIndex(tokenAddress, round, index)` | 改名 |
| `accountVotedProposalIdsCount(tokenAddress, round, memberId)` | `accountVotedActionIdsCount(tokenAddress, round, address account)` | 改名+改参 |
| `accountVotedProposalIdsAtIndex(tokenAddress, round, memberId, index)` | `accountVotedActionIdsAtIndex(tokenAddress, round, address account, index)` | 改名+改参 |
| `votesNumsByMemberId(tokenAddress, round, memberId) returns (proposalIds[], votes[])` | `votesNumsByAccount(tokenAddress, round, address account) returns (actionIds[], votes[])` | 改名+改参 |
| `votesNumsByMemberIdByProposalIds(tokenAddress, round, memberId, uint256[] calldata proposalIds)` | `votesNumsByAccountByActionIds(tokenAddress, round, address account, uint256[] memory actionIds)` | 改名+改参（`memory` → `calldata`） |
| `accountsByProposalIdCount(tokenAddress, round, proposalId)` | `accountsByActionIdCount(tokenAddress, round, actionId)` | 改名 |
| `accountsByProposalIdAtIndex(...) returns (uint256 memberId)` | `accountsByActionIdAtIndex(...) returns (address)` | 改名+改参（返回类型变） |
| `currentRound()` | 旧由 `is IPhase` 隐式提供 | 新增（显式声明） |
| `isRoundEnded(uint256 round)` | 无 | 新增 |
| `stakedAmountOfVoters(tokenAddress, round)` | `ILOVE20Verify.stakedAmountOfVerifiers(tokenAddress, round)` | 跨接口迁移 |
| `stakedAmountOfVotersByMemberId(tokenAddress, round, memberId)` | 无 | 新增 |
| `init(phaseAddress, stakeAddress, submitAddress, memberNFTAddress, mintAddress)` | 无 | 新增 |

### 事件与错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `VoteCast(tokenAddress, round, uint256 voterId, proposalId, votes)` | `Vote(tokenAddress, round, address voter, actionId, votes)` | 改名+改参 |
| `ProposalNotSubmitted()` | `ActionNotSubmitted()` | 改名 |
| `InvalidKVLength()` | 无 | 新增 |
| `AlreadyInitialized()`、`CannotVote()`、`NotEnoughVotesLeft()`、`VotesMustBeGreaterThanZero()` | 同 | 保留 |

---

## 6. ILOVE20Mint vs ILOVE20Mint

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Mint.sol`。`action*` → `proposal*`、`verifyReward` → `voteReward`、新增批量铸造，同时大幅收缩查询面。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `prepareRewardIfNeeded(tokenAddress, uint256 round)` | `prepareRewardIfNeeded(tokenAddress)` | 改参（新增 round） |
| `mintGovReward(tokenAddress, memberId, round) returns (voteReward, boostReward, burnReward)` | `mintGovReward(tokenAddress, round) returns (verifyReward, boostReward, burnReward)` | 改参（新增 memberId，首返回改名） |
| `mintGovRewards(tokenAddress, memberId, rounds[]) returns (voteRewards[], boostRewards[], burnRewards[])` | 无 | 新增（批量原子铸造） |
| `mintProposalReward(tokenAddress, round, proposalId) returns (uint256 amount)` | `mintActionReward(tokenAddress, round, actionId) returns (uint256)` | 改名 |
| `isProposalIdWithReward(tokenAddress, round, proposalId)` | `isActionIdWithReward(tokenAddress, round, actionId)` | 改名 |
| `proposalReward(tokenAddress, round)` | `actionReward(tokenAddress, round)` | 改名 |
| `proposalRewardMinVotePerThousand()` | `ACTION_REWARD_MIN_VOTE_PER_THOUSAND()` | 改名 |
| `govRewardByAccount(tokenAddress, round, memberId) returns (voteReward, boostReward, burnReward, minted)` | `govRewardByAccount(tokenAddress, round, address account) returns (verifyReward, boostReward, burnReward, isMinted)` | 改参 |
| `proposalRewardInfo(tokenAddress, round, proposalId) returns (amount, prepared, minted)` | `actionRewardByActionIdByAccount(tokenAddress, round, actionId, address account) returns (reward, isMinted)` | 改名+改参（去 account 维度，新增 prepared） |
| `rewardReserved`、`rewardMinted`、`rewardBurned`、`isRewardPrepared`、`govReward`、`rewardAvailable`、`reservedAvailable` | 同名 | 保留 |
| `eligibleProposalVotes(tokenAddress, round)` | 无 | 新增 |
| `launchCredit(tokenAddress, memberId)` | `numOfMintGovRewardByAccount(tokenAddress, address account)` | 语义替代（铸造次数计数 → 未消耗发射额度；整数次数移入 `ILOVE20Launch.launchCount`） |
| `init(voteAddress, submitAddress, stakeAddress, launchAddress, memberNFTAddress, proposalRewardMinVotePerThousand, roundRewardGovPerThousand, roundRewardProposalPerThousand, maxGovBoostRewardMultiplier)` | 无 | 新增 |
| `voteAddress()`、`submitAddress()`、`stakeAddress()`、`launchAddress()` | `voteAddress()`、`verifyAddress()`、`stakeAddress()` | `verifyAddress` 随验证阶段取消改为 `submitAddress`，并按新版依赖增加 `launchAddress`；函数数 19 → 23。见 [已确认 4](README.md#已确认并落地) |
| 无 | `ROUND_REWARD_GOV_PER_THOUSAND()`、`ROUND_REWARD_ACTION_PER_THOUSAND()`、`MAX_GOV_BOOST_REWARD_MULTIPLIER()` | 删除 getter（改为 init 入参） |
| 无 | `govVerifyReward(tokenAddress, round)`、`govBoostReward(tokenAddress, round)` | 删除，**已裁决不补**（激励计算查询由调用方自行计算） |
| 无 | `calculateRoundGovReward(tokenAddress)`、`calculateRoundActionReward(tokenAddress)` | 删除，**已裁决不补**（同上） |
| 无 | `boostRewardBurnCheckeded(tokenAddress, round)`、`actionRewardBurnChecked(tokenAddress, round)` | 删除（前者旧名含拼写错误） |
| 无 | `govRewardMintedByAccount(tokenAddress, round, address account)` | 删除（合并进 `govRewardByAccount` 的 `minted`） |
| 无 | `actionRewardMintedByAccount(tokenAddress, round, actionId, address account)` | 删除 |

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `RewardPrepared(tokenAddress, round, govReward, proposalReward, eligibleProposalVotes, rewardReserved, rewardBurned)` | `PrepareReward(tokenAddress, round, govRewardAmount, actionRewardAmount)` | 改名+改参（2 → 5 数据字段） |
| `GovernanceRewardMinted(tokenAddress, round, uint256 memberId, voteReward, boostReward, burnReward)` | `MintGovReward(tokenAddress, round, address account, verifyReward, boostReward, burnReward)` | 改名+改参 |
| `ProposalRewardMinted(tokenAddress, round, proposalId, address target, uint256 amount)` | `MintActionReward(tokenAddress, round, actionId, address account, reward)` | 改名+改参（`account` → `target`） |
| `RewardBurned(tokenAddress, round, amount, bytes32 reason)` | `BurnActionReward(tokenAddress, round, burnReward)` + `BurnBoostReward(tokenAddress, round, burnReward)` | 两事件合并，用 `reason` 区分 |

### 错误

旧 6 个全部保留（`AlreadyInitialized`、`NoRewardAvailable`、`AlreadyMinted`、`RoundNotReadyToMint`、`NotEnoughReward`、`NotEnoughRewardToBurn`）；新增 `ProposalNotFound(uint256 proposalId)`、`NotMemberOwner(uint256 memberId)`。

---

## 7. ILOVE20Launch vs ILOVE20Launch

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Launch.sol`。变化最大的接口：旧版是「公平发射募资 + 认购 + 领取」，新版是「子币创建 + 发射次数账本」。整块募资分配业务不迁移（`launch` 代码库本阶段不创建）。

### 保留与改造

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `tokenFactoryAddress()`、`mintAddress()` | 同名 | 保留 |
| `isLOVE20Token(tokenAddress)` | 同名 | 保留 |
| `launchToken(tokenSymbol, parentTokenAddress, memberId, distributor, distributorMode, keys[], values[]) returns (tokenAddress)` | `launchToken(tokenSymbol, parentTokenAddress) returns (tokenAddress)` | 改参（2 → 7 参数） |
| `launchCount(tokenAddress, uint256 memberId)` | `remainingLaunchCount(parentTokenAddress, address account)` | 改名+改参（剩余次数 → 累计次数账本） |
| `enum DistributorMode { NoCallback, Callback }` | 无 | 新增 |
| `init(tokenFactory, mint, memberNFT, rootParentToken, distributor, launchRatio, maxLaunchCount, name, symbol)` | 无 | 新增 |
| `memberNFTAddress()`、`rootParentTokenAddress()`、`launchRatio()`、`maxLaunchCount()` | 无 | 新增 |
| `mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)` | 无 | 新增 |
| `addLaunchCount(tokenAddress, memberId, count)` | 无 | 新增 |
| `issuedLaunchCount(tokenAddress)` | 无 | 新增 |

### 删除的旧函数

| 分组 | 旧函数 |
| --- | --- |
| 募资认购生命周期 | `contribute`、`withdraw`、`claim`、`claimInfo`、`contributed`、`lastContributedBlock`、`launchInfo` |
| 募资参数常量 | `FIRST_PARENT_TOKEN_FUNDRAISING_GOAL`、`PARENT_TOKEN_FUNDRAISING_GOAL`、`SECOND_HALF_MIN_BLOCKS`、`WITHDRAW_WAITING_BLOCKS`、`TOKEN_SYMBOL_LENGTH` |
| 发射资格门槛 | `MIN_GOV_REWARD_MINTS_TO_LAUNCH`（改为 `launchCount` 账本 + `maxLaunchCount` 上限） |
| 代币枚举 | `tokensCount`/`tokensAtIndex`、`childTokensCount`/`AtIndex`、`childTokensByLauncherCount`/`AtIndex`、`launchingTokensCount`/`AtIndex`、`launchedTokensCount`/`AtIndex`、`launchingChildTokensCount`/`AtIndex`、`launchedChildTokensCount`/`AtIndex`、`participatedTokensCount`/`AtIndex`、`tokenAddressBySymbol` |
| 依赖地址 | `submitAddress()` |

`struct LaunchInfo`（11 字段）与常量 `CLAIM_DELAY_BLOCKS` 同步删除。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `LaunchToken(tokenAddress, parentTokenAddress, uint256 launcherMemberId, address distributor)` | `LaunchToken(tokenAddress, string tokenSymbol, parentTokenAddress, address account)` | 改参（去 `tokenSymbol`，`account` → `launcherMemberId`，新增 `distributor`） |
| `LaunchCountAdded`、`LaunchCountMerged`、`LaunchCountConsumed` | 无 | 新增 |
| 无 | `Contribute`、`Withdraw`、`Claim`、`SecondHalfStart`、`LaunchEnd` | 删除 |

### 错误

保留 2 个：`AlreadyInitialized`、`InvalidTokenSymbol`。

新增 7 个：`InvalidAddress`、`InvalidKVLength`、`InvalidDistributorMode`、`UnauthorizedCaller`、`NotMemberOwner(uint256 memberId)`、`NotEnoughLaunchCount`、`LaunchCountLimitReached`。

删除 14 个：`TokenSymbolExists`、`NotEligibleToLaunchToken`、`LaunchAlreadyEnded`、`LaunchNotEnded`、`ClaimDelayNotPassed`、`NoContribution`、`NotEnoughWaitingBlocks`、`TokensAlreadyClaimed`、`LaunchAlreadyExists`、`ParentTokenNotSet`、`ZeroContribution`、`InvalidTokenAddress`、`InvalidToAddress`、`InvalidParentToken`。

---

## 8. ILOVE20Token vs ILOVE20Token

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Token.sol`。业务能力不变，仅去 SL/ST 依赖；ERC20 标准能力继续通过 `IERC20`、`IERC20Metadata` 继承。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `maxSupply`、`minter`、`parentTokenAddress`、`parentPool`、`mint`、`burn`、`burnForParentToken` | 同名 | 保留 |
| `name`、`symbol`、`decimals`、`totalSupply`、`balanceOf`、`transfer`、`allowance`、`approve`、`transferFrom` + 事件 `Transfer`、`Approval` | 旧由 `is IERC20, IERC20Metadata` 继承 | 显式声明（能力不变） |
| 事件 `TokenMint`、`TokenBurn`、`BurnForParentToken` | 同名 | 保留 |
| 无 | `slAddress()`、`stAddress()` | 删除（去凭证化） |
| 错误 `InvalidAddress`、`NotMinter`、`ExceedsMaxSupply`、`InsufficientBalance`、`InvalidSupply` | 同 | 保留 |
| 无 | 错误 `AlreadyInitialized()` | 删除 |

---

## 9. ILOVE20TokenFactory vs ILOVE20TokenFactory

旧：`LOVE20TKM/core/src/interfaces/ILOVE20TokenFactory.sol`。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `createToken(parentTokenAddress, string calldata name, string calldata symbol, address distributor)` | `createToken(parentTokenAddress, string memory name, string memory symbol)` | 改参（新增 `distributor`，`memory` → `calldata`） |
| 无 | `uniswapV2Factory()` | 删除（Pair 创建移入 Stake） |
| `LAUNCH_AMOUNT()` | 同名 | 保留（常量 getter 保持旧大写命名） |
| `MAX_SUPPLY()` | 同名 | 保留（常量 getter 保持旧大写命名） |
| `launchAddress()`、`mintAddress()` | 同名 | 保留 |
| `init(launchAddress, mintAddress, initialSupply, maxSupply)` | 无 | 新增 |
| 无 | `stakeAddress()` | 删除（去 SL/ST 依赖） |
| 无 | `MAX_WITHDRAWABLE_TO_FEE_RATIO()` | 删除（手续费结算移入 `Stake`） |
| 事件 `TokenCreated(tokenAddress, parentTokenAddress, name, symbol, address distributor)` | `TokenCreate(tokenAddress, parentTokenAddress, name, symbol)` | 改名+改参 |
| 错误 `InvalidAddress()` | `ZeroAddress(string parameter)` | 改名+改参（去参数） |
| 错误 `EmptyString()` | `EmptyString(string parameter)` | 改参（去参数） |
| 错误 `InvalidSupply()` | `InvalidAmount()` | 改名 |
| 错误 `AlreadyInitialized()`、`UnauthorizedCaller()` | 同 | 保留 |

---

## 10. 全新接口

### IProposalTarget

`core/IProposalTarget.sol`，旧协议无对应机制。三个回调：

- `onProposalCreated(tokenAddress, proposalId, keys[], values[])`
- `onProposalSubmitted(tokenAddress, proposalId, submitterId, keys[], values[])`
- `onProposalVoted(tokenAddress, proposalId, voterId, votes, keys[], values[])`

`votes` 为本次增量票数。旧协议的行动扩展通过 `IExtensionCenter.registerActionIfNeeded` 主动注册，不存在核心向 Target 的回调。

### ILaunchDistributor

`core/ILaunchDistributor.sol`，单个回调 `onTokenLaunched(tokenAddress, parentTokenAddress, launcherMemberId, keys[], values[])`。旧协议首批代币按认购比例由参与者自行 `claim`，无 distributor 概念。

---

## 11. 旧 core 接口整体删除明细

### ILOVE20Verify（16 函数 / 1 事件 / 4 错误）

`LOVE20TKM/core/src/interfaces/ILOVE20Verify.sol` 整体删除。核心不再有独立验证阶段。

| 旧 | 去向 |
| --- | --- |
| `verify(tokenAddress, actionId, abstentionScore, scores[])` | `action` 层 `IGroupActionExecutor.submitOriginScores(...)` |
| `stakedAmountOfVerifiers(tokenAddress, round)` | `ILOVE20Vote.stakedAmountOfVoters(tokenAddress, round)` |
| `score`、`scoreWithReward`、`abstentionScoreWithReward`、`scoreByActionId`、`scoreByActionIdByAccount`、`scoreByVerifier`、`scoreByVerifierByActionId`、`scoreByVerifierByActionIdByAccount` | `action` 层 `originScore`/`finalScore`/`totalFinalScore`（维度重构，非一一对应） |
| `firstTokenAddress`、`randomAddress`、`stakeAddress`、`voteAddress`、`joinAddress`、`RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND` | 删除 |
| 事件 `Verify` | `action` 层 `VerificationBatchSubmitted` |
| 错误 `ScoresAndAccountsLengthMismatch`、`ScoresExceedVotesNum`、`ScoresMustIncrease` | 删除；`action` 层新增 `BatchIndexMismatch` |

弃权分（`abstentionScore`）机制在新 action 层接口中无对应字段。

### ILOVE20Join（26 函数 / 4 事件 / 7 错误）

`LOVE20TKM/core/src/interfaces/ILOVE20Join.sol` 整体删除，参与业务下移。

| 旧 | 去向 |
| --- | --- |
| `join(tokenAddress, actionId, additionalAmount, verificationInfos[])` | 各 Executor 的 `join(...)`（`ILpExecutor`、`IGroupActionExecutor`、`IGroupServiceExecutor`） |
| `withdraw(tokenAddress, actionId)` | `ILpExecutor.withdraw`、`IGroupActionExecutor.withdraw` |
| `amountByActionId`、`amountByActionIdByAccount`、`amountByAccount` | `joinedAmount`、`joinedAmountByMemberId` 等 |
| `actionIdsByAccount`(+`Count`/`AtIndex`) | `IActionTarget.actionIdsByMemberId`(+`Count`/`AtIndex`) |
| `updateVerificationInfo`、`verificationInfo`、`verificationInfoByRound`、`verificationInfoUpdateRoundsCount`/`AtIndex` | 删除（改为 `join` 时传 `verificationInfos`，不再独立更新与按轮回溯） |
| `prepareRandomAccountsIfNeeded`、`randomAccounts`、`randomAccountsByRandomSeed`、`randomAccountsByActionIdCount`/`AtIndex` | 删除（随机抽样不迁移） |
| `numOfAccounts`、`indexToAccount`、`accountToIndex`、`prefixSum` | 删除（前缀和抽样支撑结构随随机抽样一并移除） |
| `JOIN_END_PHASE_BLOCKS`、`submitAddress`、`voteAddress`、`randomAddress` | 删除 |

### ILOVE20Random、ILOVE20SLToken、ILOVE20STToken

三者整体删除，无对应新接口。`ILOVE20SLToken` 的 `tokenAmounts`、`uniswapV2PairReserves`、`MAX_WITHDRAWABLE_TO_FEE_RATIO` 等 LP 份额与手续费查询能力，部分由 `ILOVE20Stake.tokenStakeGlobals` 的 `withdrawableLp`/`feeLp`/`sqrtKOfLp` 承接。
