# core 层接口对比

状态列取值：`保留`（签名完全一致）、`改名`（仅标识符变）、`改参`（参数或返回值变）、`改名+改参`、`新增`、`删除`。

跨层共性变化（memberId 主体化、错误/事件子接口内联、不再继承 `IPhase`、部分配置 getter 按决议删除并改为 init 参数）见 [README](README.md#跨层结构变化)，本文不重复解释理由。Core 新接口统一使用 `Proposal`；`Action*` 仅出现在旧接口名称或 Action 层语境中。

---

## 1. IMemberNFT vs ILOVE20Group

旧：`LOVE20TKM/group/src/interfaces/ILOVE20Group.sol`。整体复制迁移，仅去 group 字样。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `LOVE20_TOKEN_ADDRESS()` | `LOVE20_TOKEN_ADDRESS()` | 保留 |
| `BASE_DIVISOR()` | `BASE_DIVISOR()` | 保留 |
| `BYTES_THRESHOLD()` | `BYTES_THRESHOLD()` | 保留 |
| `MULTIPLIER()` | `MULTIPLIER()` | 保留 |
| `MAX_NAME_LENGTH()` | `MAX_GROUP_NAME_LENGTH()` | 改名（去掉 `GROUP`；值 64 → 32 bytes） |
| `initialized()` | 无 | 新增（公开初始化状态） |
| `init(address firstTokenAddress)` | 无（旧为构造函数入参） | 新增 |
| `mint(string calldata name) returns (uint256 id, uint256 mintCost)` | `mint(string calldata groupName) returns (uint256 tokenId, uint256 mintCost)` | 改名（接口仅参数/返回名变化；实现入参由 `memory` 改为 `calldata`，selector 不变） |
| `calculateMintCost(string calldata name)` | `calculateMintCost(string memory groupName)` | 改名+改参（接口数据位置变化，selector 不变；实现保留 `public` + `memory` 供内部复用） |
| `nameOf(uint256 id)` | `groupNameOf(uint256 tokenId)` | 改名 |
| `isNameUsed(string calldata name)` | `isGroupNameUsed(string calldata groupName)` | 改名 |
| `idOf(string calldata name)` | `tokenIdOf(string calldata groupName)` | 改名 |
| `normalizedNameOf(string calldata name)` | `normalizedNameOf(string calldata groupName)` | 保留 |
| `totalBurnedForMint()` | 同名 | 保留 |
| `holders(uint256 offset, uint256 limit, bool reverse) returns (address[] memory holderList, uint256 totalCount)` | `holdersCount()`、`holdersAtIndex(uint256 index)` | 改名+改参（两个单点查询合并为一个分页查询，语义变，见下） |
| `balanceOf`、`ownerOf`、`safeTransferFrom`×2、`transferFrom`、`approve`、`setApprovalForAll`、`getApproved`、`isApprovedForAll`、`totalSupply`、`tokenByIndex`、`tokenOfOwnerByIndex` | 旧接口未声明（实现继承 ERC721Enumerable） | 保留（通过 OZ 继承，Core 接口继承 `IERC721Enumerable`，准备接口不重复声明） |
| `supportsInterface`、`name`、`symbol`、`tokenURI` | 旧实现继承 ERC165/ERC721 | 保留（通过 OZ 继承；`supportsInterface` 来自 `IERC165`，`name`/`symbol`/`tokenURI` 来自 `IERC721Metadata`，Core 接口继承 `IERC721Metadata`，准备接口不重复声明） |

`holdersCount`/`holdersAtIndex` 合并为分页 `holders`：旧接口注释标为 Deprecated、non-authoritative（自转账后可能失准）；新版规格要求精确维护去重持有人集合，自转账不加入也不移除，并按页返回，`offset` 越界返回空数组与真实总数而不再回滚，因此 `HolderIndexOutOfBounds` 一并删除。分页语义与 `Phase.syncObservations` 一致。见 [`core/02-member-nft.md`](../../docs/specs/core/02-member-nft.md)。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `Mint(uint256 id, address owner, string name, string normalizedName, uint256 cost)` | `Mint(uint256 tokenId, address owner, string groupName, string normalizedName, uint256 cost)` | 改名（仅字段名） |
| `AddHolder(address holder, uint256 totalHolders)` | 同 | 保留 |
| `RemoveHolder(address holder, uint256 totalHolders)` | 同 | 保留 |
| `Transfer`、`Approval`、`ApprovalForAll` | 旧接口未声明 | 保留（通过 OZ 继承，不在准备接口重复声明） |

### 错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `NameAlreadyExists(uint256 existingId)` | `GroupNameAlreadyExists(uint256 existingTokenId)` | 改名 |
| `NameEmpty()` | `GroupNameEmpty()` | 改名 |
| `NameTooLong(uint256 length, uint256 maxLength)` | `GroupNameTooLong(uint256 length, uint256 maxLength)` | 改名 |
| `NameInvalidCharacters()` | `GroupNameInvalidCharacters()` | 改名 |
| 无 | `HolderIndexOutOfBounds(uint256 length)` | 删除（分页 `offset` 越界返回空数组与真实总数，不回滚） |
| `AlreadyInitialized()` | 无 | 新增（配合 `init`） |

OZ 5 的标准回滚由固定依赖提供：`IERC721Errors`、`ERC721OutOfBoundsIndex`、`ERC721EnumerableForbiddenBatchMint`、`SafeERC20FailedOperation` 进入实现的编译 ABI，替代相关 OZ 4 字符串回滚；不在准备接口重复声明。两侧均无 MemberNFT 自有结构体或枚举。

除改名和初始化外，迁移修复自转账的持有人集合维护，使用 OZ 5 `_update` 更新后的余额判断地址加入/移除；`Transfer` 先于持有人变更事件。费用公式、UTF-8 校验和 Test 前缀/报价的旧行为保留，详见模块规格。四个构造参数和首币地址新增零值拒绝，不新增专用 selector。

---

## 2. IPhase vs IPhase

旧：`LOVE20TKM/core/src/interfaces/IPhase.sol`。从「业务轮次时间线」重构为「无语义时间片 + 动态校准」。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ORIGIN_BLOCKS()` | `originBlocks()` | 改名（配置 getter 统一大写） |
| `ORIGIN_PHASE_BLOCKS()` | 无 | 新增（初始时间片长度，与当前值分离） |
| `TARGET_SECONDS()` | 无 | 新增 |
| `ADJUST_THRESHOLD()` | 无 | 新增 |
| `SYNC_OBSERVATION_LIMIT()` | 无 | 新增 |
| `currentPhaseBlocks()` | `phaseBlocks()` | 改名（语义：恒定长度 → 可被校准的当前长度） |
| `currentPhase()` | `currentRound()` | 改名（语义：业务轮次 → 无语义时间片） |
| `phaseInfo(uint256 phaseNumber) returns (uint256 startBlock, uint256 phaseBlocks_)` | 无 | 新增 |
| `phaseAtBlock(uint256 blockNumber)` | `roundByBlockNumber(uint256 blockNumber)` | 改名 |
| `syncObservations(uint256 offset, uint256 limit, bool reverse) returns (uint256[] blockNumbers, uint256[] blockTimestamps, uint256 totalCount)` | 无 | 新增（分页读取观测） |
| `sync() returns (bool adjusted, uint256 newPhaseBlocks)` | 无 | 新增 |
| 事件 `PhaseSynchronized`、`PhaseAdjusted` | 无 | 新增 |
| 错误 `InvalidPhase(uint256)`、`InvalidKeyOrder()` | 无 | 新增 |
| 无 | 错误 `RoundNotStarted()` | 删除（改由 Phase 的 `InvalidPhase` 承担；Action Executor 与 Group Chat 各自另声明同名错误） |

旧 4 个函数全部改名（`originBlocks`→`ORIGIN_BLOCKS`、`phaseBlocks`→`currentPhaseBlocks`、`currentRound`→`currentPhase`、`roundByBlockNumber`→`phaseAtBlock`）；新 11 个函数 = 改名 4 + 新增 7。旧唯一错误 `RoundNotStarted` 删除，新错误 2 个均为新增。新 `IPhase` 新增的四个配置 getter 对应构造函数新增的四个参数，`SYNC_OBSERVATION_LIMIT` 约束 `sync` 单次可处理的观测条数。

旧 `IPhase` 被 6 个 core 接口继承并因此隐式暴露 `currentRound()`；新 `IPhase` 是独立合约接口，不被继承。

---

## 3. IStake vs ILOVE20Stake

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Stake.sol`。去 SL/ST 凭证（份额直接在 Stake 记账）+ 按 memberId 归属 + `stakeToken` 改造为 `stakeBoost` + 新增 `settleFees`/`mergeStake`。另有两个旧仓来源并入：`LOVE20TKM/core/src/LOVE20SLToken.sol` 的 LP/手续费结算公式，以及 `LOVE20TKM/periphery/src/LOVE20Hub.sol` 的入池最优量折算与滑点校验。DEX 依赖以 `IPair`、`IPairFactory`、`IRouter` 三个最小接口声明。

### 结构体

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `MemberStake { liquidityShares, boostShares, promisedWaitingPhases, unlockRequestPhase }` | `AccountStakeStatus { slAmount, stAmount, promisedWaitingPhases, requestedUnstakeRound, govVotes }` | 改名+改参（5 字段 → 4 字段） |
| `GlobalStake { totalLiquidityShares, totalLp, lastWithdrawableLp, lastFeeLp, lastSqrtKOfLp, totalBoostShares }` | 无 | 新增 |

字段对应：`slAmount` → `liquidityShares`、`stAmount` → `boostShares`、`requestedUnstakeRound` → `unlockRequestPhase`；`govVotes` 字段移除，改由 `validGovVotes()` 查询。

两个结构体只声明内部存储布局，不作为查询返回格式：`stakeData`/`globalStakeData` 把需要的字段逐项展开为标量，并追加按当前 Pair 状态现算的 LP 对应代币数量。见 [`core/04-stake.md`](../../docs/specs/core/04-stake.md)。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `initialized()` | 无 | 新增（公开初始化状态） |
| `phaseAddress()`、`memberNFTAddress()`、`voteAddress()`、`routerAddress()`、`pairFactoryAddress()` | 无 | 新增（依赖 getter） |
| `init(phaseAddress, memberNFTAddress, voteAddress, routerAddress, pairFactoryAddress, promisedWaitingPhasesMin, promisedWaitingPhasesMax, maxWithdrawableToFeeRatio)` | 无 | 新增 |
| `settleFees(address tokenAddress)` | 无 | 新增（手续费单独结算入口） |
| `stakeLiquidity(tokenAddress, tokenAmount, parentTokenAmount, slippage, promisedWaitingPhases, uint256 memberId) returns (govVotesAdded, liquiditySharesAdded)` | `stakeLiquidity(tokenAddress, tokenAmountForLP, parentTokenAmountForLP, promisedWaitingPhases, address to) returns (govVotesAdded, slAmountAdded)` | 改参（`to` → `memberId`、新增 `slippage`，返回份额改名；原 `LOVE20Hub` 的最优量折算与滑点校验并入本入口） |
| `stakeBoost(tokenAddress, boostAmount, promisedWaitingPhases, uint256 memberId) returns (uint256 govVotesAdded)` | `stakeToken(tokenAddress, tokenAmount, promisedWaitingPhases, address to) returns (uint256 govVotesAdded)` | 改名+改参 |
| `unstake(tokenAddress, uint256 memberId)` | `unstake(tokenAddress)` | 改参 |
| `withdraw(tokenAddress, uint256 memberId)` | `withdraw(tokenAddress)` | 改参 |
| `mergeStake(tokenAddress, uint256 sourceMemberId, uint256 targetMemberId)` | 无 | 新增 |
| `PROMISED_WAITING_PHASES_MIN()`、`PROMISED_WAITING_PHASES_MAX()` | 同名 | 保留 |
| `MAX_WITHDRAWABLE_TO_FEE_RATIO()` | 旧在 `ILOVE20SLToken`/`ILOVE20TokenFactory` | 跨接口迁移（手续费重分类阈值改由 Stake 持有，并同时用作单笔结算量） |
| `pairAddress(address tokenAddress)`、`totalBurnedToken(address tokenAddress)`、`totalParentTokenBurned(address tokenAddress)` | 无 | 新增 |
| `globalGovVotes(address tokenAddress)` | `govVotesNum(address tokenAddress)` | 改名（`global` 前缀区分社区总量与成员量） |
| `stakeData(tokenAddress, uint256 memberId) returns (liquidityShares, boostShares, promisedWaitingPhases, unlockRequestPhase, tokenAmountForLiquidity, parentTokenAmountForLiquidity)` | `accountStakeStatus(tokenAddress, address account) returns (AccountStakeStatus)` | 改名+改参（主体改 `memberId`；结构体展开为标量并追加两项现算 LP 数量） |
| `validGovVotes(tokenAddress, uint256 memberId)` | `validGovVotes(tokenAddress, address account)` | 改参 |
| `globalStakeData(address tokenAddress) returns (totalLiquidityShares, totalLp, withdrawableLp, feeLp, totalBoostShares, tokenAmountForLiquidity, parentTokenAmountForLiquidity)` | 无 | 新增（社区总量；`lastSqrtKOfLp` 只作内部结算基准，不对外） |
| `canWithdraw(tokenAddress, uint256 memberId)` | 无 | 新增 |
| `cumulatedBoostShares(tokenAddress, uint256 round, uint256 memberId)` | `cumulatedTokenAmountByAccount(tokenAddress, uint256 round, address account)` | 改名+改参（语义：累计代币量 → 累计 boost 份额） |
| `globalBoostUpdatedRounds(tokenAddress, uint256 offset, uint256 limit, bool reverse) returns (uint256[] rounds, uint256 totalCount)` | `stakeTokenUpdatedRoundsCount(tokenAddress)` + `stakeTokenUpdatedRoundsAtIndex(tokenAddress, uint256 index)` | 合并+改名+改参 |
| `boostUpdatedRounds(tokenAddress, uint256 memberId, uint256 offset, uint256 limit, bool reverse) returns (uint256[] rounds, uint256 totalCount)` | `stakeTokenUpdatedRoundsByAccountCount(tokenAddress, address account)` + `stakeTokenUpdatedRoundsByAccountAtIndex(tokenAddress, address account, uint256 index)` | 合并+改名+改参 |
| 无 | `initialStakeRound(tokenAddress)` | 删除 |
| 无 | `caculateGovVotes(uint256 lpAmount, uint256 promisedWaitingPhases)` | 删除（旧名含拼写错误，且不再对外承诺票数公式） |
| 无 | `cumulatedTokenAmount(tokenAddress, uint256 round)` | 删除（按成员版本改语义保留，去掉全局版本） |

旧自有函数 17 个 = 保留 2 + 改名 1 + 改参 4 + 改名+改参 3 + 合并 4 + 删除 3；新 27 个 = 保留 2 + 改名 1 + 改参 4 + 改名+改参 3 + 合并 2 + 新增 15。合并项都是「数量 + 逐项下标」两函数合成一个分页函数，故旧侧 4 个计数为 2 个新函数。旧接口另外继承 `IPhase` 得到 4 个时间线查询（`originBlocks`/`phaseBlocks`/`currentRound`/`roundByBlockNumber`），该继承取消后由 `phaseAddress()` 指向的 `Phase` 提供。

### 事件

旧 4 个事件全部改参（其中 `StakeToken` 连名一起改），另有 2 个新增：

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `StakeLiquidity` | `StakeLiquidity` | 改参（`address account` → `uint256 memberId`；`tokenAmountForLP`/`parentTokenAmountForLP` → `tokenAmount`/`parentTokenAmount`；`slAmountAdded`/`slAmount` → `liquiditySharesAdded`/`liquidityShares`；新增 `tokenAmountDesired`/`parentTokenAmountDesired`，字段数 10 → 12） |
| `StakeBoost` | `StakeToken` | 改名+改参（`address account` → `uint256 memberId`；`tokenAmount` → `boostAmount`；`stAmount` → `boostSharesAdded` + `boostShares`，字段数 8 → 9） |
| `Unstake` | `Unstake` | 改参（`address account` → `uint256 memberId`；`slAmount`/`stAmount` → `liquidityShares`/`boostShares`） |
| `Withdraw` | `Withdraw` | 改参（`address account` → `uint256 memberId`；`slAmount` → `liquidityShares`；`stAmount` → `boostShares`；`tokenAmountForLp`/`parentTokenAmountForLp` → `tokenAmountForLiquidity`/`parentTokenAmountForLiquidity`） |
| `FeesSettled` | 无 | 新增（旧 `ILOVE20SLToken.WithdrawFee` 的对应事件，按完成时命名） |
| `StakeMerged` | 无 | 新增（按完成时命名） |

### 错误

旧 11 个 = 保留 8 + 改名 1 + 删除 2；新 20 个 = 保留 8 + 改名 1 + 新增 11。

保留 8 个（相对顺序不变）：`AlreadyInitialized`、`NotAllowedToStakeAtRoundZero`、`StakeAmountMustBeSet`、`UnstakeAlreadyRequested`、`UnstakeNotRequested`、`PromisedWaitingPhasesOutOfRange`、`PromisedWaitingPhasesMustBeGreaterOrEqualThanBefore`、`NoStakedLiquidity`。

改名 1 个：`NotEnoughWaitingBlocks` → `NotEnoughWaitingPhases`（等待单位由区块改为时间片）。

删除 2 个：`InvalidToAddress()`（新接口不再接收 `to` 地址）、`RoundHasNotStartedYet()`（轮次未开始的语义由 `IStakeErrors.InvalidPhase(uint256)` 承接，与 `IPhaseErrors.InvalidPhase` 同名同参数、selector 相同）。

新增 11 个：`InvalidTokenAddress`、`InvalidMemberId`、`NotMemberOwner(uint256 memberId)`、`SourceAndTargetMustBeDifferent()`、`SourceHasVotedInCurrentRound()`、`TargetPromisedWaitingPhasesTooShort()`、`InvalidAddress()`、`ZeroAmount(string parameter)`、`InvalidAmount()`、`SlippageExceeded(uint256 slippage, uint256 deviation)`、`InvalidPhase(uint256 phaseNumber)`。后 7 个服务于 `init`、`stakeLiquidity`、`mergeStake` 与 `settleFees` 入口；`SlippageExceeded` 承接旧 `LOVE20Hub` 的两条 `require` 字符串，第一个参数是请求容差、第二个是实际偏离；`InvalidPhase` 承接删除的 `RoundHasNotStartedYet`。

错误顺序：保留 8 项的旧相对顺序不变（原 `InvalidToAddress` 位置直接消失），改名项与 11 个新增项插在其后。

---

## 4. ISubmit vs ILOVE20Submit

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol`。从「行动提案」抽象为「通用 Proposal + Target + Target Data」，行动特有字段全部移出。

### 结构体与枚举

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ProposalHead { uint256 id, uint256 author, uint256 createAtBlock }` | `ActionHead { uint256 id, address author, uint256 createAtBlock }` | 改名+改参（`author` 由地址改为 `memberId`） |
| `ProposalBody { string title, string details, address target, TargetMode targetMode, bytes[] targetData }` | `ActionBody { minStake, maxRandomAccounts, whiteListAddress, title, verificationRule, verificationKeys[], verificationInfoGuides[] }` | 改名+改参（7 字段 → 5 字段） |
| `ProposalInfo { ProposalHead head, ProposalBody body }` | `ActionInfo { ActionHead head, ActionBody body }` | 改名 |
| `SubmitInfo { uint256 submitterId, uint256 proposalId }` | `ActionSubmitInfo { address submitter, uint256 actionId }` | 改名+改参（主体由地址改为 `memberId`；字段名 `submitter` → `submitterId`） |
| `enum TargetMode { NoCallback, Callback }` | 无 | 新增 |

旧 `ActionBody` 的 `minStake`、`maxRandomAccounts`、`whiteListAddress`、`verificationRule`、`verificationKeys`、`verificationInfoGuides` 不进入新 `ProposalBody`，改由 `targetData` 的不透明 Target Data 传给对应 Target；`title` 保留，新增 `details`、`target`、`targetMode`。

`ProposalBody` 既是 `submitNewProposal` 的入参，也是 `ProposalInfo` 的组成，不另立 `Params` 结构。旧 4 个结构体全部有对应（4 个改名），另新增 `TargetMode` 枚举。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `stakeAddress()` | 同名 | 保留 |
| `SUBMIT_MIN_PER_THOUSAND()` | 同名 | 保留 |
| `isSubmitted(tokenAddress, round, proposalId)` | `isSubmitted(tokenAddress, round, actionId)` | 保留（仅参数名） |
| `phaseAddress()` | 无 | 新增 |
| `memberNFTAddress()` | 无 | 新增 |
| `initialized()` | 无 | 新增 |
| `init(phaseAddress, stakeAddress, memberNFTAddress, submitMinPerThousand)` | 无 | 新增 |
| `currentRound()` | 旧由 `is IPhase` 隐式提供 | 新增（显式声明） |
| `canSubmit(tokenAddress, uint256 memberId)` | `canSubmit(tokenAddress, address account)` | 改参 |
| `submitNewProposal(tokenAddress, memberId, ProposalBody) returns (uint256 proposalId)` | `submitNewAction(tokenAddress, ActionBody) returns (uint256 actionId)` | 改名+改参 |
| `submit(tokenAddress, memberId, proposalId)` | `submit(tokenAddress, actionId)` | 改参 |
| `proposalInfosByIds(tokenAddress, proposalIds[]) returns (ProposalInfo[])` | `actionInfo(tokenAddress, actionId) returns (ActionInfo)` | 改名+改参（去掉单条入口，改按显式 ID 批量，返回与入参下标一一对应） |
| `proposalIds(tokenAddress, offset, limit, reverse) returns (proposalIdList, totalCount)` | `actionsCount(tokenAddress)` + `actionsAtIndex(tokenAddress, index)` | 合并+改名+改参 |
| `proposalIdsByAuthor(tokenAddress, author, offset, limit, reverse) returns (proposalIdList, totalCount)` | `authorActionIdsCount(tokenAddress, address author)` + `authorActionIdsAtIndex(tokenAddress, address author, index)` | 合并+改名+改参 |
| `submitInfos(tokenAddress, round, offset, limit, reverse) returns (SubmitInfo[], totalCount)` | `actionSubmitsCount(tokenAddress, round)` + `actionSubmitsAtIndex(tokenAddress, round, index)` | 合并+改名+改参（分页回完整记录而非 id 列表） |
| `proposalIdBySubmitter(tokenAddress, round, submitterId) returns (uint256 proposalId)` | `submitInfoBySubmitter(tokenAddress, round, address submitter) returns (ActionSubmitInfo)` | 改名+改参（主体改 `memberId`，返回值收为 `proposalId`） |
| `submitterIdByProposalId(tokenAddress, round, proposalId) returns (uint256 submitterId)` | `submitInfo(tokenAddress, round, actionId) returns (ActionSubmitInfo)` | 改名+改参（返回值收为 `submitterId`；与上一条互为逆） |
| 无 | `MAX_VERIFICATION_KEY_LENGTH()` | 删除（无消费者；验证内容已下移到 Target Data） |
| 无 | `canJoin(tokenAddress, actionId, address account)` | 删除（下移 action 层） |

`submitNewProposal` 沿用旧 `submitNewAction` 的动词与语义，`submit` 沿用旧名。旧 `submitNewAction` 的内部就是 `_createAction` + `_submitByActionId`，新接口同样在同一笔内先创建再推举，这对名称因此名副其实。旧代码里创建即占用该成员本轮的推举名额、同一提案每轮只能被推举一次，两条约束原样保留；`submit` 只推举已有提案，可跨轮、推举者可为作者以外的人。

三处枚举合并为分页：参数顺序为「作用域键 → `offset` → `limit` → `reverse`」，并同时返回真实总数，与 `IPhase.syncObservations`、`IMemberNFT.holders`、`ILaunch.tokens`/`childTokens`、`IStake` 的分页一致。旧 `actionsCount`/`actionsAtIndex` 与 `authorActionIdsCount`/`authorActionIdsAtIndex`、`actionSubmitsCount`/`actionSubmitsAtIndex` 的按下标访问随之取消，因此不再声明越界错误。

**分页返回值随页内成员是否定长**：`ProposalBody` 的 `title`/`details`/`targetData` 都不设长度上限，页内成员又由别人决定，一页里落进一条大 `targetData` 就能让整页超出调用方 gas 上限且无法跳过，所以 `proposalIds`/`proposalIdsByAuthor` 只回 `proposalId`，本体走 `proposalInfosByIds(proposalIds[])` 按 id 批量取；`SubmitInfo` 全为 `uint256`，任意一页的体量都与 `limit` 成正比，故 `submitInfos` 分页直接回完整记录。旧 `actionsAtIndex`/`actionSubmitsAtIndex` 直接在枚举里回结构体，这条路被撤掉了。不设单条详情入口：读一条传单元素数组，避免出现只差一个字母、返回值却是两种东西的近名对。

命名记号三条：**数组返回值在名字里体现载荷**——`Ids` 只回轻量标识、`Infos` 回记录本体，裸集合名不用于返回数组的函数，标量返回值不加后缀；**筛选条件进名字**——默认全量不标记，按键用 `By<key>`，显式 ID 数组用 `ByIds`，可串联成 `By<key>ByIds`（group-chat 的 `votedSenderIds`、`chatInfos`/`roundInfos` 即此记号）；**是否分页不进名字**——由入参 `(offset, limit, reverse)` 决定，不为同一集合另设无窗口的全量重载。仓库现有 28 个分页函数一律以参数表意，名字里不带 `Paginated`/`Paged`/`Page`。

单键查询三条：`isSubmitted` 与两条方向单键 `proposalIdBySubmitter`/`submitterIdByProposalId`。后两条是旧 `submitInfo`/`submitInfoBySubmitter` 各改名而来——`(tokenAddress, round)` 下的推举记录是 `(proposalId, submitterId)` 对，且「每人每轮一个」「每提案每轮一次」使两种键都是唯一键，旧接口的两个方向本就互为镜像，故按同样方式改名、返回值都由 `ActionSubmitInfo` 收为单个标量（`0` = 本轮未推举）；`submitInfos` 的分页是集合的完整读取路径，两条单键是两个方向的定点通道，三者读同一份记录。`isSubmitted` 保留是因为它是旧接口同名同参的保留成员——它与 `submitterIdByProposalId` 同键但给出两个不同的值（存在性 vs 取值），不构成重复，如同 `IMemberNFT.isNameUsed` 与 `idOf`。

旧 `ILOVE20Submit` 继承 `IPhase`，旧 ABI 另外包含 Phase 的全部查询（`currentPhase`、`currentBlockInPhase`、`phaseAtBlock`、`sync` 等）。新版把 Phase 拆为独立合约，`ISubmit` 只显式声明 `currentRound()`，时间线经 `phaseAddress()` 指向的 `Phase` 读取。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ProposalCreated(tokenAddress, proposalId, uint256 author, string title, string details, address target, TargetMode targetMode)` | `ActionCreate(tokenAddress, round, address author, actionId, ActionBody actionBody)` | 改名+改参 |
| `ProposalSubmitted(tokenAddress, round, uint256 submitterId, proposalId)` | `ActionSubmit(tokenAddress, round, address submitter, actionId)` | 改名+改参 |

`ProposalCreated` 去掉 `round` 字段、`ActionBody` 结构展开为 `title`/`details`、新增 `target`/`targetMode`，且**不含 `targetData`**：`TokenLaunched` 与 `VoteCast` 同样有透传数据入参而事件不发，三个合约口径一致。`targetData` 是不透明的机器数据，Target 由回调取得、索引器由 `proposalInfosByIds(proposalIds[])` 取得，事件带它只增加永久落盘。

`ProposalSubmitted` 由两个写入口共发：`submitNewProposal` 一笔内先 `ProposalCreated` 后 `ProposalSubmitted`，`submit` 只发后者。旧 `ActionCreate`/`ActionSubmit` 也是这个顺序（`submitNewAction` 内先 `_createAction` 后 `_submitByActionId`），回调亦然（先 `onProposalCreated` 后 `onProposalSubmitted`）。

### 错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `AlreadyInitialized()` | 同 | 保留 |
| `CannotSubmitAction()` | 同 | 保留 |
| `AlreadySubmitted()` | 同 | 保留 |
| `OnlyOneSubmitPerRound()` | 同 | 保留 |
| `ProposalNotFound(uint256 proposalId)` | `ActionIdNotExist()` | 改名+改参（新增参数） |
| `InvalidAddress()` | 无 | 新增 |
| `InvalidTargetMode()` | 无 | 新增 |
| `NotMemberOwner(uint256 memberId)` | 无 | 新增 |
| `EmptyString(string parameter)` | 无 | 新增 |
| `ZeroAmount(string parameter)` | 无 | 新增 |
| `InvalidAmount()` | 无 | 新增 |
| `RoundNotStarted()` | 无 | 新增 |
| 无 | `MinStakeZero()` | 删除（字段已移出 Proposal 主体） |
| 无 | `MaxRandomAccountsZero()` | 删除（字段已移出 Proposal 主体） |
| 无 | `TitleEmpty()` | 删除（`title` 仍在主体，改用 `EmptyString("title")`） |
| 无 | `VerificationRuleEmpty()` | 删除（字段已移出 Proposal 主体） |
| 无 | `VerificationKeyLengthExceeded()` | 删除（字段已移出 Proposal 主体） |

旧 10 个错误 = 保留 4 + 改名 1 + 删除 5；新 12 个 = 保留 4 + 改名 1 + 新增 7。错误顺序：保留 4 项的旧相对顺序不变（`AlreadyInitialized` → `CannotSubmitAction` → `AlreadySubmitted` → `OnlyOneSubmitPerRound`），改名项与 7 个新增项插在其后。

逐条件的错误映射与各入口的校验顺序见 [`core/05-submit.md`](../../docs/specs/core/05-submit.md)。

---

## 5. IVote vs ILOVE20Vote

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Vote.sol`。全量保留，`actionId` → `proposalId`、`account` → `memberId`，新增 Target Data 与投票者质押量查询。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `stakeAddress()`、`submitAddress()` | 同名 | 保留 |
| `vote(tokenAddress, memberId, proposalIds[], votes[], bytes[][] targetData)` | `vote(tokenAddress, actionIds[], votes[])` | 改参（新增 memberId 与二维 Target Data） |
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
| `InvalidTargetDataLength()` | 无 | 新增 |
| `AlreadyInitialized()`、`CannotVote()`、`NotEnoughVotesLeft()`、`VotesMustBeGreaterThanZero()` | 同 | 保留 |

---

## 6. IMint vs ILOVE20Mint

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
| `PROPOSAL_REWARD_MIN_VOTE_PER_THOUSAND()` | `ACTION_REWARD_MIN_VOTE_PER_THOUSAND()` | 改名（保留大写配置 getter） |
| `govRewardByMemberId(tokenAddress, round, memberId) returns (voteReward, boostReward, burnReward, minted)` | `govRewardByAccount(tokenAddress, round, address account) returns (verifyReward, boostReward, burnReward, isMinted)` | 改名+改参（成员 ID 替代账户地址；返回值语义改为投票激励；selector `0x8c25b309` 取代 `0x5eccfa65`） |
| `proposalRewardByProposalId(tokenAddress, round, proposalId) returns (amount, minted)` | `actionRewardByActionIdByAccount(tokenAddress, round, actionId, address account) returns (reward, isMinted)` | 改名+改参（去 account 维度、返回值从 `(reward, prepared, isMinted)` 改为 `(amount, minted)`；selector `0x11eefe4c` 取代 `0x30f5cfb6`） |
| `rewardReserved`、`rewardMinted`、`rewardBurned`、`isRewardPrepared`、`govReward`、`rewardAvailable`、`reservedAvailable` | 同名 | 保留 |
| `eligibleProposalVotes(tokenAddress, round)` | 无 | 新增 |
| `launchCredit(tokenAddress, memberId)` | `numOfMintGovRewardByAccount(tokenAddress, address account)` | 语义替代（铸造次数计数 → 未消耗发射额度；整数次数移入 `ILOVE20Launch.launchCount`） |
| `init(voteAddress, submitAddress, launchAddress, memberNFTAddress, proposalRewardMinVotePerThousand, roundRewardGovPerThousand, roundRewardProposalPerThousand, maxGovBoostRewardMultiplier)` | 无 | 新增（8 参数，selector `0x8187933a`） |
| `voteAddress()`、`submitAddress()`、`launchAddress()` | `voteAddress()`、`verifyAddress()`、`stakeAddress()` | `verifyAddress` 随验证阶段取消改为 `submitAddress`，并按新版依赖增加 `launchAddress`；删除 `stakeAddress()`；函数数 19 → 23 → 27（成员增加后）→ 27（移除 `stakeAddress()` 后保持） |
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

旧 6 个全部保留（`AlreadyInitialized`、`NoRewardAvailable`、`AlreadyMinted`、`RoundNotReadyToMint`、`NotEnoughReward`、`NotEnoughRewardToBurn`）；新增 `NotMemberOwner(uint256 memberId)`、`InvalidAddress()`、`InvalidAmount()`、`UnauthorizedCaller()`。`ProposalNotFound` 属于 ISubmit，不在 IMint 中。

---

## 7. ILaunch vs ILOVE20Launch

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Launch.sol`，并整体并入 `ILOVE20TokenFactory.sol`（其成员去向见「删除的旧函数」之后）。变化最大的接口：旧版是「公平发射募资 + 认购 + 领取」，新版是「子币创建 + 发射次数账本」。整块募资分配业务不迁移（`launch` 代码库本阶段不创建）。

接口组织：旧文件为 `ILOVE20LaunchErrors` → `ILOVE20LaunchEvents` → `ILOVE20Launch` 三段，新 `ILaunch.sol` 保留同样三段（`ILaunchErrors` → `ILaunchEvents` → `ILaunch`）；枚举 `DistributorMode` 置于文件作用域顶部，与旧文件在顶部放 `struct LaunchInfo` 和常量一致。

### 保留与改造

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `mintAddress()` | 同名 | 保留 |
| `TOKEN_SYMBOL_LENGTH()` | 同名 | 保留（配置语义不变，`init` 新增对应的 `tokenSymbolLength` 参数） |
| `isLOVE20Token(tokenAddress)` | 同名 | 保留 |
| `launchToken(tokenSymbol, parentTokenAddress, memberId, distributor, distributorMode, bytes[] distributorData) returns (tokenAddress)` | `launchToken(tokenSymbol, parentTokenAddress) returns (tokenAddress)` | 改参（2 → 6 参数；新增发起成员、分配者、回调模式与不透明分配数据） |
| `launchCount(tokenAddress, uint256 memberId)` | `remainingLaunchCount(parentTokenAddress, address account)` | 改名+改参（剩余次数 → 累计次数账本） |
| `enum DistributorMode { NoCallback, Callback }` | 无 | 新增 |
| `init(LaunchInitParams)` | 无 | 新增（一次完成依赖（含 Pair Factory）、发射参数、供应量配置和首币元数据初始化） |
| `memberNFTAddress()`、`rootParentTokenAddress()`、`pairFactoryAddress()`、`LAUNCH_RATIO()`、`MAX_LAUNCH_COUNT()`、`LAUNCH_AMOUNT()`、`MAX_SUPPLY()` | 无 | 新增（`pairFactoryAddress()` 承接旧 `ILOVE20TokenFactory.uniswapV2Factory()` 的建池职责） |
| `initialized()` | 旧实现有 `bool public initialized`（自动 getter 进入合约 ABI，未写进旧接口） | 新增（公开初始化状态，与 `IMemberNFT` 对齐，供发布前检查脚本核对） |
| `mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)` | 无 | 新增 |
| `addLaunchCount(tokenAddress, memberId, count)` | 无 | 新增 |
| `issuedLaunchCount(tokenAddress)` | 无 | 新增 |
| `tokens(uint256 offset, uint256 limit, bool reverse) returns (address[] tokenList, uint256 totalCount)` | `tokensCount()`/`tokensAtIndex(uint256)` | 改名+改参（数量 + 逐项读取 → 分页查询，新增 `totalCount` 与 `reverse`） |
| `childTokens(address parentTokenAddress, uint256 offset, uint256 limit, bool reverse) returns (address[] tokenList, uint256 totalCount)` | `childTokensCount(address)`/`childTokensAtIndex(address, uint256)` | 改名+改参（同上） |
| `tokenAddressBySymbol(string calldata symbol)` | `tokenAddressBySymbol(string memory symbol)` | 保留（`memory` → `calldata`，selector 不变） |
| `parentTokenOf(address tokenAddress)` | 无（旧 `launchInfo(address)` 返回的 `LaunchInfo.parentTokenAddress` 字段） | 新增（登记状态与父币地址的读取入口，`isLOVE20Token` 复用同一账本） |

函数顺序：保留的旧函数相对顺序不变（`mintAddress` → `TOKEN_SYMBOL_LENGTH` → `isLOVE20Token` → `launchToken` → 原 `remainingLaunchCount` 位置 → 原 `tokensCount`/`childTokensCount`/`tokenAddressBySymbol` 位置）；新增的依赖 getter 紧跟依赖 getter 组，供应量 getter 紧跟其他配置 getter，`initialized`、`init` 置于配置 getter 之后。

### 删除的旧函数

| 分组 | 旧函数 |
| --- | --- |
| 募资认购生命周期 | `contribute`、`withdraw`、`claim`、`claimInfo`、`contributed`、`lastContributedBlock`、`launchInfo` |
| 募资参数常量 | `FIRST_PARENT_TOKEN_FUNDRAISING_GOAL`、`PARENT_TOKEN_FUNDRAISING_GOAL`、`SECOND_HALF_MIN_BLOCKS`、`WITHDRAW_WAITING_BLOCKS` |
| 发射资格门槛 | `MIN_GOV_REWARD_MINTS_TO_LAUNCH`（改为 `launchCount` 账本 + `maxLaunchCount` 上限） |
| 代币枚举（按发射者或募资状态） | `childTokensByLauncherCount`/`AtIndex`、`launchingTokensCount`/`AtIndex`、`launchedTokensCount`/`AtIndex`、`launchingChildTokensCount`/`AtIndex`、`launchedChildTokensCount`/`AtIndex`、`participatedTokensCount`/`AtIndex`（代币列表、某社区子币列表和符号账本保留为分页查询与 `tokenAddressBySymbol`，见上表；按成员聚合的发射历史由 `TokenLaunched` 的 `launcherMemberId` 链下索引） |
| 依赖地址 | `submitAddress()`、`tokenFactoryAddress()` |

旧 36 个函数 = 保留 4 + 改参 1 + 改名+改参 1 + 合并 4 + 删除 26；新 21 个 = 保留 4 + 改参 1 + 改名+改参 1 + 合并 2 + 新增 13。`tokensCount`+`tokensAtIndex`、`childTokensCount`+`childTokensAtIndex` 各合成一个分页函数，故旧侧 4 个计数为新侧 2 个。

`tokenFactoryAddress()` 随 `ILOVE20TokenFactory` 一并消失：新 `Launch` 自己创建代币（`init` 建首币、`launchToken` 建子币），不再有独立工厂。旧 `ILOVE20TokenFactory` 的其余成员去向如下，`AlreadyInitialized()`、`EmptyString(string)`、`InvalidAmount()`、`UnauthorizedCaller()` 四个错误与 `ILaunchErrors` 同名项合并，`ZeroAddress(string parameter)` 统一为 `InvalidAddress()`。

| 旧 `ILOVE20TokenFactory` 成员 | 去向 |
| --- | --- |
| `mintAddress()`、`LAUNCH_AMOUNT()`、`MAX_SUPPLY()` | `ILaunch` 同名保留 |
| `createToken(parentTokenAddress, name, symbol)` | 折入 `Launch.init`（首币）与 `ILaunch.launchToken`（子币） |
| 事件 `TokenCreate(tokenAddress, parentTokenAddress, name, symbol)` | 并入 `ILaunchEvents.TokenLaunched`（补 `launcherMemberId`/`distributor`） |
| `MAX_WITHDRAWABLE_TO_FEE_RATIO()`、`uniswapV2Factory()` | `MAX_WITHDRAWABLE_TO_FEE_RATIO()` 跨接口迁移到 `IStake`；`uniswapV2Factory()` 拆为 `ILaunch.pairFactoryAddress()`（建池）与 `IStake.pairFactoryAddress()`（读取），两处必须指向同一个 Factory |
| `launchAddress()`、`stakeAddress()` | 删除（两者都是旧工厂回指其调用方的地址；Pair 生命周期仍留在 `Launch`，由其在创建代币时建池） |

MemberNFT 的配置 getter 同样遵循大写命名；`MAX_NAME_LENGTH()` 仅去掉旧名中的 `GROUP`，其余配置 getter 保持旧名。

`struct LaunchInfo`（11 字段）与常量 `CLAIM_DELAY_BLOCKS` 同步删除。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `TokenLaunched(tokenAddress, parentTokenAddress, uint256 launcherMemberId, address distributor, string name, string symbol)` | `LaunchToken(tokenAddress, string tokenSymbol, parentTokenAddress, address account)`、`TokenCreate(tokenAddress, parentTokenAddress, string name, string symbol)` | 合并创建与发射事件（`TokenCreate` 来自旧 `ILOVE20TokenFactory`）；增加 `launcherMemberId`/`distributor` |
| `LaunchCountAdded`、`LaunchCountMerged` | 无 | 新增 |
| 无 | `Contribute`、`Withdraw`、`Claim`、`SecondHalfStart`、`LaunchEnd` | 删除 |

次数消耗不单独声明事件：`launchToken` 已发 `TokenLaunched`（含 `launcherMemberId`），每次发射恰消耗一次次数，消耗历史可由它重建，余量用 `launchCount` 查询。

首币由 `init` 创建、没有发起成员，因此 `TokenLaunched` 的 `launcherMemberId` 取 `0`；三个事件的触发入口与字段取值见 [`core/08-launch.md`](../../docs/specs/core/08-launch.md)。

### 错误

保留 5 个：`AlreadyInitialized`、`InvalidTokenSymbol`、`TokenSymbolExists()`（触发条件 `tokenAddressBySymbol[最终符号] != address(0)`，与旧 `_launchToken` 相同）、`InvalidTokenAddress()`（触发条件 `!isLOVE20Token(tokenAddress)`，与旧 `contribute` 相同）、`InvalidParentToken()`（触发条件 `!isLOVE20Token(parentTokenAddress)`，与旧 `launchToken` 相同）。

新增 11 个：`InvalidAddress`、`InvalidDistributorMode`、`ZeroAmount(string parameter)`、`UnauthorizedCaller`、`NotMemberOwner(uint256 memberId)`、`CountMustBeGreaterThanZero()`、`SourceAndTargetMustBeDifferent()`、`NotEnoughLaunchCount`、`LaunchCountLimitReached`、`InvalidAmount()`、`EmptyString(string parameter)`。

删除 11 个：`NotEligibleToLaunchToken`、`LaunchAlreadyEnded`、`LaunchNotEnded`、`ClaimDelayNotPassed`、`NoContribution`、`NotEnoughWaitingBlocks`、`TokensAlreadyClaimed`、`LaunchAlreadyExists`、`ParentTokenNotSet`、`ZeroContribution`、`InvalidToAddress`。

错误顺序：保留 5 项的旧相对顺序不变（`AlreadyInitialized` → `InvalidTokenSymbol` → `TokenSymbolExists` → `InvalidTokenAddress` → `InvalidParentToken`），11 个新增项插在其后。

逐条件的错误映射与初始化交易顺序见 [`core/08-launch.md`](../../docs/specs/core/08-launch.md)。

---

## 8. ILOVE20Token vs ILOVE20Token

旧：`LOVE20TKM/core/src/interfaces/ILOVE20Token.sol`。业务能力不变，仅去 SL/ST 依赖；ERC20 标准能力由实现的 `ERC20` 提供，Core 接口继承 `IERC20`、`IERC20Metadata`，准备接口仅声明自有能力。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `maxSupply`、`minter`、`parentTokenAddress`、`mint`、`burn` | 同名 | 保留 |
| `name`、`symbol`、`decimals`、`totalSupply`、`balanceOf`、`transfer`、`allowance`、`approve`、`transferFrom` + 事件 `Transfer`、`Approval` | 旧由 `is IERC20, IERC20Metadata` 继承 | 保留（通过 OZ 继承，不在准备接口重复声明） |
| 事件 `TokenMint`、`TokenBurn` | 同名 | 保留 |
| 错误 `InvalidAddress`、`NotMinter`、`ExceedsMaxSupply`、`InvalidSupply` | 同 | 保留 |
| 无 | `slAddress()`、`stAddress()` | 删除（去凭证化） |
| 无 | `parentPool()`、`burnForParentToken(uint256 amount) returns (uint256 parentTokenAmount)` | 删除（去 SL/ST 后不再有「销毁本币换回父币」的通路） |
| 无 | 事件 `BurnForParentToken` | 删除（上一条的配套事件） |
| 无 | 错误 `InsufficientBalance()` | 删除（仅被 `burnForParentToken` 使用） |
| 无 | 错误 `AlreadyInitialized()` | 删除（本合约由构造函数初始化，无 `init`） |

旧自有 9 个函数 = 保留 5 + 删除 4；旧 3 个事件 = 保留 2 + 删除 1；旧 6 个错误 = 保留 4 + 删除 2。

---

## 9. 全新接口

### IProposalTarget

`core/IProposalTarget.sol`，旧协议无对应机制。三个回调：

- `onProposalCreated(tokenAddress, proposalId, bytes[] targetData)`
- `onProposalSubmitted(tokenAddress, proposalId, submitterId, bytes[] targetData)`
- `onProposalVoted(tokenAddress, proposalId, voterId, votes, bytes[] targetData)`

`votes` 为本次增量票数，`targetData` 是不透明的 Target Data 数组。旧协议的行动扩展通过 `IExtensionCenter.registerActionIfNeeded` 主动注册，不存在核心向 Target 的回调。

### ILaunchDistributor

`core/ILaunchDistributor.sol`，单个回调 `onTokenLaunched(tokenAddress, parentTokenAddress, launcherMemberId, bytes[] distributorData)`。旧协议首批代币按认购比例由参与者自行 `claim`，无 distributor 概念。

---

## 10. 旧 core 接口整体删除明细

### ILOVE20Verify（16 函数 / 1 事件 / 4 错误）

`LOVE20TKM/core/src/interfaces/ILOVE20Verify.sol` 整体删除。核心不再有独立验证阶段。

| 旧 | 去向 |
| --- | --- |
| `verify(tokenAddress, actionId, abstentionScore, scores[])` | `action` 层 `IGroupActionExecutor.submitOriginScores(...)` |
| `stakedAmountOfVerifiers(tokenAddress, round)` | `IVote.stakedAmountOfVoters(tokenAddress, round)` |
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

三者整体删除，无对应新接口。`ILOVE20SLToken` 的 `tokenAmounts`、`uniswapV2PairReserves`、`MAX_WITHDRAWABLE_TO_FEE_RATIO` 等 LP 份额与手续费查询能力，部分由 `IStake.globalStakeData` 的 `withdrawableLp`/`feeLp` 承接（`MAX_WITHDRAWABLE_TO_FEE_RATIO` 本身迁到 `IStake`，`lastSqrtKOfLp` 只作内部结算基准不对外）。
