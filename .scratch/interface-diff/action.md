# action 层接口对比

状态列取值同 [core.md](core.md)。跨层共性变化见 [README](README.md#跨层结构变化)。

## IActionExecutor 通用接口

新增 `IActionExecutor` 作为所有 Executor 的基础接口，定义统一的自证绑定、回调契约、退出接口和 Round 查询。

```solidity
interface IActionExecutorEvents {
    event MemberRewardMinted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
        uint256 round, uint256 mintAmount, uint256 burnAmount);
}

interface IActionExecutorErrors {
    error AlreadyInitialized();
    error UnauthorizedCallback();
    error InvalidRound(uint256 round);
    error RoundNotStarted();
    error NotMemberOwner(uint256 memberId);
    error ProposalNotVoted(address tokenAddress, uint256 proposalId);
    error RewardAlreadyMinted(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round);
    error BatchLengthMismatch(uint256 actionIdsLength, uint256 roundsLength);
}

interface IActionExecutor is IProposalTarget, IActionExecutorEvents, IActionExecutorErrors {
    function actionTarget() external view returns (address);
    function initialized() external view returns (bool);
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function mintMemberReward(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round)
        external returns (uint256 mintAmount, uint256 burnAmount);
    function mintMemberRewards(address tokenAddress, uint256[] calldata actionIds, uint256 memberId,
        uint256[] calldata rounds)
        external returns (uint256[] memory mintAmounts, uint256[] memory burnAmounts);
    function needBurnReward(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (bool needed);
    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
    function memberReward(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round)
        external view returns (uint256 mintAmount, uint256 burnAmount, bool minted);
    function joinedAmount(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256 amount);
    function joinedAmountByMemberId(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 amount);
    function joinedAmountTokenAddress(address tokenAddress, uint256 actionId)
        external view returns (address joinedTokenAddress);
}
```

**事件分层**：
- `IActionExecutor` 只定义 `MemberRewardMinted` 事件（成员级结算留痕）；各 Executor 自行声明业务事件 `Joined`/`Withdrawn`/`Exited`（完整业务字段 `amount`、来源键 `providerId` 与链群 `groupId`）
- `IActionTarget` 定义 `ActionCreated/JoinStateRegistered/JoinStateCleared/ActionRewardMinted` 事件；加入态事件与登记函数同名系，`JoinStateCleared` 带 `forced` 区分正常清理与 forceExit，`ActionCreated` 带 `round`
- 两层事件名称不同、各记录各层级的信息；ActionTarget 不发 `Withdrawn`

**继承关系**：
- `ILpExecutor is IActionExecutor, ILpExecutorEvents`
- `IGroupActionExecutor is IGroupActionIndexes, IActionExecutor, IGroupActionJoin, IGroupActionVerify, IGroupActionManager, IGroupActionExecutorErrors`
- `IGroupServiceExecutor is IActionExecutor, IGroupServiceExecutorEvents`

各 Executor 根据业务需要扩展或覆盖 `join` 签名：
- **LpExecutor**：使用基础签名
- **GroupActionExecutor**：扩展 `groupId` 参数
- **GroupServiceExecutor**：覆盖签名，去掉 `amount` 参数（查看服务不需要金额）

详见 [`IActionExecutor.sol`](../../interfaces/action/IActionExecutor.sol) 和 [Executor 通用接口规格](../specs/action/00-executor-interface.md)。

---

## 本层最大的结构变化：实例模型 → 单例多社区模型

旧 `extension` 体系为每个 `tokenAddress + actionId` 部署一个 extension 实例，由工厂创建并在 `ExtensionCenter` 注册。因此旧接口分两类：

- **实例自身接口**（`ILp`、`IGroupAction`、`ITokenJoin`、`IReward`、`IJoin`、`IExtension`）：不带 `tokenAddress`/`actionId` 参数，作用域即该实例，如 `deduction(round, account)`。
- **共享单例接口**（`IGroupJoin`、`IGroupManager`、`IGroupVerify`、`IGroupRecipients`）：首参传 `address extension` 定位实例，如 `join(extension, groupId, amount, verificationInfos)`。

新 action 层每类 Executor 是一个单例合约，服务所有代币社区与行动。因此：

- 旧实例接口的函数统一补齐 `address tokenAddress, uint256 actionId` 前缀参数。
- 旧共享接口的 `address extension` 首参替换为 `address tokenAddress, uint256 actionId`。
- 旧实例上的行动配置 getter（例如 `GOV_RATIO_MULTIPLIER`、`JOIN_TOKEN_ADDRESS`）也补齐 `tokenAddress + actionId`，因为配置改由 Proposal 创建回调的 Target Data 按行动保存。
- 全部工厂接口删除：`IExtensionFactory`、`ILpFactory`、`IGroupActionFactory`、`IGroupServiceFactory`、`IExtensionGroupActionFactory`、`IExtensionGroupServiceFactory`。
- `FACTORY_ADDRESS()`、`initialize(address factory_)`、`initializeIfNeeded()`、`initialized()`、`TOKEN_ADDRESS()`、`actionId()` 一律删除，改为各 Executor 的 `init(...)` 一次性依赖注入。

以下各节不再对每个函数重复标注这一层参数变化的理由。

## Executor 的通用与非通用边界

新增 `IActionExecutor` 作为所有 Executor 的基础接口，定义通用部分：

- 继承 `IProposalTarget`：所有 Executor 接收 Core 层的三类回调（创建/推举/投票）
- `exit(tokenAddress, actionId, memberId)`：完全退出的签名是通用的

**非通用部分**各 Executor 自行定义：
- `join` 参数因行动类型而异（LP 需要 amount，GroupAction 需要 groupId，GroupService 不需要 amount）
- `withdraw` 签名虽类似但语义不同（LP 和 GroupAction 是部分撤回，GroupService 可能不需要）
- 事件字段不同（LP 的 Joined 只包含 amount，GroupAction 还包含 providerId/groupId）

完整接口见 [`IActionExecutor.sol`](../../interfaces/action/IActionExecutor.sol) 和 [规格文档](../../docs/specs/action/00-executor-interface.md)。

## 继承关系与完整 ABI 规模

新 action 层有 4 个接口带继承，其**完整 ABI = 自身声明 + 继承成员**。下表给出总数，各节表格只列自身声明的部分。

| 接口 | 自身函数 | 继承自 | 完整函数 ABI |
| --- | --- | --- | --- |
| `IActionTarget` | 22 | `IProposalTarget`（3） | 25 |
| `IActionExecutor` | 13 | `IProposalTarget`（3） | 16 |
| `ILpExecutor` | 8 | `IActionExecutor`（13）+ `IProposalTarget`（3） | 24 |
| `IGroupActionExecutor` | 8 | `IGroupActionIndexes`（6）+ `IGroupActionJoin`（11）+ `IGroupActionVerify`（13）+ `IGroupActionManager`（15）+ `IActionExecutor`（13）+ `IProposalTarget`（3）+ `IVerificationInfo`（4） | 73 |
| `IGroupServiceExecutor` | 11 | `IActionExecutor`（13）+ `IProposalTarget`（3） | 27 |

本表只统计**函数**；事件与错误见各节。`IActionTarget` 的自身声明数按 2026-10-02 Review 裁决后的接口重算（补 4 个依赖 getter + `initialized()`，删不可达错误，`join`/`exit` 改名为 `registerJoinState`/`clearJoinState`，另加派生的 `phaseAddress()` 与行动级销毁 `burnRewardIfNeeded`/`burnInfo`）。`IActionExecutor` 的行按成员级奖励、批量结算、行动级销毁判据与参与量查询裁决后重算：自身 13 个函数（`actionTarget`、`initialized`、`exit`、`mintMemberReward`、`mintMemberRewards`、`needBurnReward`、`currentVoteRound`、`currentJoinRound`、`currentMintRound`、`memberReward`、`joinedAmount`、`joinedAmountByMemberId`、`joinedAmountTokenAddress`），另有 8 个错误与 1 个事件。三个 Executor 的自身声明数不随共用基座的变化而变；`IGroupActionExecutor` 的 `Errors` 子接口拆分已在对应 Review 步完成。

旧侧对应情况：旧 `LOVE20TKM/group-chat/src/interfaces/sources/ban/IAdminBanSource.sol`、`LOVE20TKM/group-chat/src/interfaces/sources/scope/IGroupMemberScope.sol`、`LOVE20TKM/group-chat/src/interfaces/sources/scope/IGroupJoinScopeSource.sol`、`LOVE20TKM/group-chat/src/interfaces/sources/ban/IGovVotedBanSource.sol` 均通过 `is IPostBanSource`/`is IPostScopeSource` 继承行为契约（见 [group-chat.md](group-chat.md)）；旧 `LOVE20TKM/extension-group/src/interface/IExtensionGroupActionFactory.sol` 继承 `IGroupActionFactory`、`IExtensionFactory`，随工厂体系一并删除。

---

## 1. IActionTarget vs IExtensionCenter + IExtension

旧：`LOVE20TKM/extension/src/interface/IExtensionCenter.sol`、`LOVE20TKM/extension/src/interface/IExtension.sol`。

新 `IActionTarget` 继承 `IProposalTarget`，承担「提案与执行合约关联 + 通用加入/退出登记 + 成员→行动跨类型索引 + 激励中转」。旧 `ExtensionCenter` 的注册中心、委托、验证信息与「每行动一实例」职责不迁移；`addAccount` 的「本轮有票」前置校验改由各 Executor 按其阶段与资格规则判定：行动创建轮门禁由 `JoinNotOpen` 承担，逐轮奖励由铸造时的 Vote 门禁（`mintActionReward` / Mint）承担，加入本身不要求行动在加入轮有票。

**接口组织**：旧 `IExtensionCenter` 按 `IExtensionCenterEvents` + `IExtensionCenterErrors` + 主接口三部分声明；新 `IActionTarget` 保留相同结构：`IActionTargetEvents` + `IActionTargetErrors` + 主接口。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `memberNFTAddress()`、`submitAddress()`、`voteAddress()`、`mintAddress()` | `IExtensionCenter` 的 9 个依赖 getter | 保留 3 个（submit/vote/mint）、新增 `memberNFTAddress`、删除 6 个（stake/launch/uniswapV2Factory/join/verify/random） |
| `phaseAddress()` | 无 | 新增（init 时从 `IMint(mintAddress).phaseAddress()` 派生缓存并暴露；当前投票轮直读 Phase，不经 Mint/Vote 二跳） |
| `initialized()` | `IExtension.initialized`（`ExtensionBase.sol:27` 自动 getter） | 保留（与 core 六个接口同形；中转期间曾缺失，本轮补回） |
| `init(mintAddress)` | 无（旧为构造函数注入） | 新增（只收 Mint；`voteAddress`、`submitAddress`、`memberNFTAddress`、`phaseAddress` 全部从 Mint 派生，派生值零校验后缓存） |
| `isJoined(tokenAddress, actionId, uint256 memberId)` | `IExtensionCenter.isAccountJoined(tokenAddress, actionId, address account)` | 改名+改参（去 Account 前缀） |
| `isJoinedByRound(tokenAddress, actionId, memberId, round)` | `IExtensionCenter.isAccountJoinedByRound(...)` | 改名+改参（**保留**；旧 `validRound` 回滚 `RoundExceedsJoinRound` 改为按未开始返回 false） |
| `registerJoinState(tokenAddress, actionId, uint256 memberId)` | `IExtensionCenter.addAccount(tokenAddress, actionId, address account, verificationInfos[])` | 改名+改参（`verificationInfos` 移入各 Executor 的 `join`；幂等，不再回滚 `AccountAlreadyJoined`） |
| `clearJoinState(tokenAddress, actionId, uint256 memberId)` | `IExtensionCenter.removeAccount(tokenAddress, actionId, address account) returns (bool)` | 改名+改参（去返回值；未加入时返回无操作，不再返回 false） |
| `actionIdsByMemberId(tokenAddress, memberId, offset, limit, reverse) returns (actionIds[], total)` | `IExtensionCenter.actionIdsByAccount(tokenAddress, address account, address[] factories)` 部分对应 | 改名+改参（标准分页 `(offset, limit, reverse) → (列表, 总数)`；删除 factories 参数与 extensions/factories 返回数组） |
| `memberIdsByActionId(tokenAddress, actionId, round, offset, limit, reverse)` | `accounts`/`accountsCount`/`accountsAtIndex`、`accountsByRound`(+`Count`/`AtIndex`) | 改参（全量 + Count + AtIndex 六项合并为一个**按轮**标准分页函数；不带 `round` 的当前态列表不单设，当前态用 `isJoined` 点查或传当前轮读取——同一集合只留一条完整读取路径） |
| `executor(tokenAddress, actionId)` | `IExtensionCenter.extension(tokenAddress, actionId)` | 改名+改参（proposalId → actionId，Action 层视角） |
| `actionReward(tokenAddress, actionId, round) returns (amount, minted)` | 无 | 新增（铸造信息只读入口：已铸造返回记录值，未铸造返回按 Mint 账本计算的理论可铸造数量，已销毁返回 0；命名按集合读取规范的标量形态；旧无对应，成员自领模式下由 `govRatio(...).minted` 承担） |
| `forceExit(tokenAddress, actionId, memberId)` | 无 | 新增（应急登记清理） |
| `mintActionReward(tokenAddress, actionId, round) returns (uint256 amount)` | 无（旧 `IReward` 的整笔领取在实例内部） | 新增（激励中转；只接受已创建关联行动的 `actionId`，与同层查询 `actionReward` 同键序） |
| `burnRewardIfNeeded(tokenAddress, actionId, round)` | 无（旧整笔销毁在实例内部） | 新增（行动级整笔销毁：Executor 整笔退回后触发，判据经 `IActionExecutor.needBurnReward`，`InvalidRound` 校验已结束轮次） |
| `burnInfo(tokenAddress, actionId, round) returns (amount, burned)` | 无 | 新增（行动级销毁查询，与 `actionReward` 同键序同层） |
| `actionIdsByExecutor(tokenAddress, executor, offset, limit, reverse) returns (actionIds[], total)` | 无 | 新增（标准分页；某 Executor 名下全部行动，来自创建回调维护的追加索引） |
| `actions(tokenAddress, offset, limit, reverse) returns (actionIds[], executors[], total)` | 无 | 新增（标准分页；本代币全部已关联行动，同上索引派生） |
| `votedActions(tokenAddress, round, offset, limit, reverse) returns (actionIds[], executors[], total)` | 无 | 新增（标准分页；指定轮有投票的行动，从 Vote 本轮列表按映射筛选派生） |
| 继承 `IProposalTarget` 三回调 | 无（旧由业务合约扫本轮票自我发现） | 新增 |
| 无 | `IExtensionCenter.registerActionIfNeeded(tokenAddress, actionId)` | 删除（改由 `onProposalCreated` 回调建立关联） |
| 无 | `IExtensionCenter.factory(tokenAddress, actionId)` | 删除 |
| 无 | `IExtensionCenter.setExtensionDelegate`、`extensionDelegate`、`extensionTokenActionPair` | 删除 |
| 无 | `IExtensionCenter.updateVerificationInfo`、`verificationInfo`、`verificationInfoByRound` | 删除（改由创建回调的 Target Data 传入，落各 Executor） |
| 无 | `IExtension.joinedAmount()`、`joinedAmountByAccount(account)`、`joinedAmountTokenAddress()` | 删除（金额查询下移各 Executor） |

旧 `IExtension` 另有 4 个错误全部删除：`InvalidTokenAddress`、`ActionIdNotFound`、`MultipleActionIdsFound`、`RoundNotFinished`；1 个事件 `Initialize` 删除（改为 `init` 一次性注入，无事件）。`FACTORY_ADDRESS`、`TOKEN_ADDRESS`、`actionId`、`initializeIfNeeded`、`initialized` 5 个成员按本层开头的实例模型规则删除。

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ActionCreated(tokenAddress, actionId, executor, round)` | `IExtensionCenter.RegisterAction(tokenAddress, actionId, extension, factory)` | 改名+改参（去 factory 字段，增创建时的 `round`） |
| `ActionRewardMinted(tokenAddress, actionId, round, amount)` | 无（旧 `IReward.ClaimReward(...)` 是 per-member 口径，由各 Executor 的 `MemberRewardMinted` 承接） | 新增（**行动级整笔铸造**的事件留痕，与同层查询 `actionReward` 同源；`amount` 即 `mintActionReward` 的返回值） |
| `JoinStateRegistered(tokenAddress, actionId, memberId, round)` | `IExtensionCenter.AddAccount(tokenAddress, round, actionId, address account, accountCount)` | 改名+改参（事件与登记函数 `registerJoinState` 同名系，与 Executor 层业务事件 `Joined` 区分；删除 accountCount，业务字段由 Executor 层的 `Joined` 事件承载） |
| `JoinStateCleared(tokenAddress, actionId, memberId, round, bool forced)` | `IExtensionCenter.RemoveAccount(tokenAddress, round, actionId, address account, accountCount)` | 改名+改参（与 `clearJoinState` 同名系；`forced` 区分 Executor 正常清理与 forceExit） |
| 无 | `IExtensionCenter.SetExtensionDelegate`、`UpdateVerificationInfo`；`IExtension.Initialize` | 删除 |

`ForceExited` 不再单设：并入 `JoinStateCleared` 的 `forced` 字段（`forceExit` 以 `forced = true` 发出，带当前 `round`）。

ActionTarget 不发出 `Withdrawn`：部分撤回不改变加入状态，该事件只由 Executor 层发出（见 [ADR-003](../../docs/adr/003-action-target-interface-simplification.md)）。

ActionTarget 发出 `ActionRewardMinted` 而不是让各 Executor 各发一条：该事件的粒度是**行动级整笔**，去重键 `tokenAddress + actionId + round` 由 ActionTarget 定义（`01-action-target.md`），整笔也先落在 ActionTarget（Mint 铸给 Target 后再转给 Executor），四要素 `tokenAddress`/`actionId`/`round`/`amount` 在 `mintActionReward` 内全部可得。Executor 侧只发业务粒度的 `MemberRewardMinted`（见第 2 节）。

### 错误

新 13 个：`AlreadyInitialized`、`InvalidAddress`、`UnauthorizedCallback`、`UnboundProposal(tokenAddress, proposalId)`、`UnauthorizedExecutor(tokenAddress, actionId)`、`JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)`、`NotMemberOwner(memberId)`、`ProposalNotVoted(tokenAddress, proposalId)`、`InvalidExecutor`、`AlreadyCreated(tokenAddress, actionId)`、`AlreadyMinted(tokenAddress, actionId, round)`、`InvalidRound(round)`、`TransferFailed(tokenAddress, to, amount)`。其中 `InvalidRound` 为回归成员——A-04 曾以不可达删除，行动级销毁入口（`IVote.isRoundEnded` 校验）使其可达。阶段型 Executor 另在 `IActionExecutorErrors` 声明 `RoundNotStarted()`。错误与事件的相对顺序沿用旧 `IExtensionCenter` 槽位（迁移标准「保持旧接口中错误、事件的相对顺序」）：`UnauthorizedCallback` ← `OnlyExtensionOrDelegate` 族、`ProposalNotVoted` ← `ActionNotVotedInCurrentRound`、`InvalidExecutor` ← `InvalidExtensionFactory`/`InvalidExtensionAddress`、`AlreadyCreated` ← `ActionAlreadyRegisteredToOtherAction`；事件 `Joined`/`Exited`/`ActionCreated` 分别对应 `AddAccount`/`RemoveAccount`/`RegisterAction`。新增成员按语义就近插入（init 对置顶、授权簇相邻、`AlreadyMinted` 收尾）；**函数顺序不沿用旧槽位**，按 A-09 裁决为「依赖 getter → `initialized()` → `init` → 写 → 查询」。

旧 `IExtensionCenter` 13 个 + `IExtension` 4 个错误全部删除，其中语义继承：`InvalidExtensionAddress`/`InvalidExtensionFactory` → `InvalidExecutor`、`ActionNotVotedInCurrentRound` → `ProposalNotVoted`、`OnlyExtensionOrDelegate`/`OnlyAccountOrExtensionOrDelegate` → `UnauthorizedCallback`、`ActionAlreadyRegisteredToOtherAction` → `AlreadyCreated(tokenAddress, actionId)`（键改为 `(tokenAddress, proposalId)` 唯一）；旧构造函数的 require 零地址校验（非 ABI 错误）→ `InvalidAddress()`。`RoundExceedsJoinRound` 取消（越界不回滚）、`AccountAlreadyJoined` 取消（改为幂等）、`RewardAlreadyMinted` 移出（ActionTarget 侧改为行动级 `AlreadyMinted`）、`IndexOutOfBounds`/`InvalidRound`/`InvalidKVLength` 不再在 ActionTarget 声明（不可达）。

**加入态 round 口径（2026-10-05 定稿）**：加入态快照与 `JoinStateRegistered`/`JoinStateCleared` 事件的 round 为**加入轮**（= 当前投票轮 - 1），与三个 Executor 的加入 Round 同轴——旧仓为单一 Round 轴（`LOVE20TKM/core/src/Phase.sol:15-16`，merged 三合约同公式），偏移系新阶段模型引入，故 ActionTarget 显式对齐；证据与定稿过程见 `LOVE20BSC/.scratch/review-2026-10-04-action-target-implementation.md`，规格落点 `01-action-target.md` 历史查询段。`ActionCreated` 的 round 为创建投票轮（= 该行动首个加入轮）；`registerJoinState` 以 `JoinNotOpen` 硬校验当前投票轮大于创建轮，保证快照不落在创建轮之前。

---

## 2. ILpExecutor vs ILp + ITokenJoin + IReward

旧：`LOVE20TKM/extension-lp/src/interface/ILp.sol`、`LOVE20TKM/extension/src/interface/ITokenJoin.sol`、`LOVE20TKM/extension/src/interface/IReward.sol`。仅迁移 V2 LP 业务，V1 实现与旧 LP 工厂不迁移。

三阶段轮次（投票、加入、铸币）。

### 函数

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `GOV_RATIO_MULTIPLIER(tokenAddress, actionId)`、`MIN_GOV_RATIO(tokenAddress, actionId)` | `ILp` 同名 | 改参（补单例行动作用域；配置来自创建回调的 Target Data） |
| `deduction(tokenAddress, actionId, round, memberId) returns (amount, joinBlocks[], joinAmounts[])` | `ILp.deduction(round, address account) returns (deduction, joinBlocks[], joinAmounts[])` | 改参 |
| `totalDeduction(tokenAddress, actionId, round)` | `ILp.totalDeduction(round)` | 改参 |
| `govRatio(tokenAddress, actionId, round, memberId) returns (ratio, minted)` | `ILp.govRatio(round, address account) returns (ratio, claimed)` | 改参（返回名 `claimed` → `minted`，与基座成员结算标志统一） |
| `join(tokenAddress, actionId, memberId, amount)` | `ITokenJoin.join(uint256 amount, string[] verificationInfos)` | 改参（去掉 `verificationInfos`：LP 无验证阶段，验证信息落点不迁移） |
| `exit(tokenAddress, actionId, memberId)` | `ITokenJoin.exit()` | 改参 |
| `withdraw(tokenAddress, actionId, memberId, amount)` | 无（旧只有全额 `exit`） | 新增（部分撤回） |
| `joinedAmount(tokenAddress, actionId, round)`（基座继承） | `IExtension.joinedAmount()`、`ITokenJoin.joinedAmountByRound(round)` | 改参并上提基座（实例作用域 → token + actionId + 加入轮） |
| `joinedAmountByMemberId(tokenAddress, actionId, round, memberId)`（基座继承） | `IExtension.joinedAmountByAccount(address account)`、`ITokenJoin.joinedAmountByAccountByRound(address account, round)` | 改名+改参并上提基座（ByAccount → ByMemberId） |
| `currentVoteRound()`、`currentJoinRound()`、`currentMintRound()` | 无 | 新增（阶段映射显式化） |
| `init(actionTargetAddress, stakeAddress)` | 无 | 新增（MemberNFT、Phase 与 Pair Factory 从 Stake 派生；LP 的预期激励经 `ActionTarget.actionReward` 读取，无 `mintAddress` 依赖） |
| 继承 `IProposalTarget` | 无 | 新增 |
| 无 | `ITokenJoin.JOIN_TOKEN_ADDRESS()` | 删除（LP 场景由 `pairFactoryAddress` 推导） |
| 无 | `ITokenJoin.WAITING_BLOCKS()` | 删除 |
| 无 | `ITokenJoin.joinInfo(account) returns (joinedRound, amount, lastJoinedBlock, exitableBlock)` | 删除（LP 无退出等待期） |
| 无 | `IReward.reward(round)`、`rewardByAccount`、`claimReward`、`claimRewards`、`burnInfo` | 删除（领取模型 → 铸造分发模型；`burnInfo` 以行动级口径落到 `ActionTarget`，见 `IActionTarget`） |
| 无 | `IReward.burnRewardIfNeeded(round)` | 上提行动层（判定 = 基座 `needBurnReward`，执行 = `ActionTarget.burnRewardIfNeeded`） |

### 事件与错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `Joined(tokenAddress, actionId, memberId, round, amount)`、`Withdrawn`、`Exited` | `ITokenJoin.Join(tokenAddress, round, actionId, address account, amount)`、`Exit(...)` | 改名+改参（Executor 层事件包含完整业务字段；ActionTarget 层发出简化的 `Joined`/`Exited` 事件） |
| `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` | `IReward.ClaimReward(tokenAddress, round, actionId, address account, mintAmount, burnAmount)` | 改名+改参（`address account` → `uint256 memberId`；**per-member 口径与两个金额分量都沿用**；声明在共用基座 `IActionExecutorEvents`） |
| 错误 `InsufficientGovRatio()` | `ILp.InsufficientGovRatio()` | 保留 |
| 错误 `InvalidJoinTokenAddress()` | `ITokenJoin.InvalidJoinTokenAddress()` | 保留（落点改为创建回调的 `joinTokenAddress` 校验） |
| 错误 `InvalidJoinTokenFactory()` | `ILpFactory.InvalidJoinTokenFactory()` | 保留（落点改为创建回调的 Factory 登记交易对校验） |
| 错误 `NotJoined()` | `ITokenJoin.NotJoined()` | 保留（落点改为 `exit` 无加入记录） |
| 错误 `InvalidParticipationAmount()` | 无 | 新增（本接口与 GroupAction 共用，GroupService 不抛，故保留在各自子接口、不上提基座；承接 `JoinAmountZero`） |
| 错误 `InvalidTargetDataLength()` | 无 | 新增（Target Data 项数不符，命名同 core `IVoteErrors`） |
| 错误 `InvalidMinGovRatio()` | 无 | 新增（`minGovRatio > 1e18`） |
| 错误 `InvalidAddress()` | 无 | 新增（`init` 依赖零地址） |
| 错误 `AlreadyInitialized`、`UnauthorizedCallback`、`InvalidRound`、`RoundNotStarted`、`NotMemberOwner`、`ProposalNotVoted`、`RewardAlreadyMinted` | 无 | 新增（声明在共用基座 `IActionExecutorErrors`，本接口由继承获得） |
| 无 | `ITokenJoin.JoinAmountZero`、`NotEnoughWaitingBlocks()`；`IReward.AlreadyClaimed()` | 删除（`JoinAmountZero` 语义并入 `InvalidParticipationAmount`；退出等待取消，`NotEnoughWaitingBlocks` 不再需要；`AlreadyClaimed` 由基座 `RewardAlreadyMinted` 承接） |

LP 侧既不声明 `ActionRewardMinted`（在 `IActionTargetEvents`）也不声明 `RewardBurned`：LP 的销毁全部带成员归属（`burnReward = theoreticalReward − mintReward`，见 [LP Executor](../../docs/specs/action/04-lp-executor.md)），已并入 `MemberRewardMinted.burnAmount`，不存在无成员归属的整批销毁。旧 `IReward.BurnReward` 的对应物因此在 LP 侧删去，只在 `IGroupServiceExecutor` 保留（见第 5 节）。

LP 事件数为 **4**（`Joined`、`Withdrawn`、`Exited`，加基座继承的 `MemberRewardMinted`），错误数为 **16**（独有 8：`InvalidAddress`、`InvalidJoinTokenAddress`、`InvalidJoinTokenFactory`、`InvalidTargetDataLength`、`InvalidMinGovRatio`、`InsufficientGovRatio`、`InvalidParticipationAmount`、`NotJoined`；其余 8 个由基座继承），自身函数 **8**（`joinedAmount` 族四条上提基座），合计 ABI 44 条。

---

## 3. IGroupActionExecutor vs IGroupAction + IGroupManager + IGroupJoin + IGroupVerify

旧：`LOVE20TKM/extension-group/src/interface/IGroupAction.sol`、`LOVE20TKM/extension-group/src/interface/IGroupManager.sol`、`LOVE20TKM/extension-group/src/interface/IGroupJoin.sol`、`LOVE20TKM/extension-group/src/interface/IGroupVerify.sol`。四个旧接口合并为一个 Executor。

**继承**：`IGroupActionExecutor is IGroupActionIndexes, IActionExecutor, IGroupActionJoin, IGroupActionVerify, IGroupActionManager, IGroupActionExecutorErrors`。接口按**实现模块**拆成文件（与库一一对应），`IGroupActionExecutor` 自身只声明 Executor 本地实现的 8 个成员（4 个配置 getter、`SPLITS()`、`init`、`currentVerifyRound`、`generatedActionRewardByGroupId`）。因此其完整函数 ABI = 自身的 8 个 + `IGroupActionIndexes` 的 6 条索引查询 + `IGroupActionJoin` 的 11 个（含两条按轮历史读）+ `IGroupActionVerify` 的 13 个（另经 `IGroupActionVerify` 继承 `IVerificationInfo` 的 4 个）+ `IGroupActionManager` 的 15 个 + `IActionExecutor` 的 16 个（含 `IProposalTarget` 的 3 个回调），共 73 个。下文表格只列各成员的声明归属。

**文件次序与格式**：三个模块接口文件的成员顺序沿用旧文件次序（`IGroupActionJoin` ← `IGroupJoin`、`IGroupActionVerify` ← `IGroupVerify`、`IGroupActionManager` ← `IGroupManager`），删除成员的位置留空不补位，新增成员就近插入或成组追加在末尾；声明格式沿用旧文件与 `ILpExecutor` 的多行风格（参数每行一个、成员之间空行、多返回值折行 `returns (...)`），便于把新文件与旧文件并排逐段比对。`IGroupActionExecutor` 自身按下述次序：配置 getter → `init` → `currentVerifyRound` → `generatedActionRewardByGroupId`。

模块间次序核对（旧文件里存活的成员按原次序出现在新文件中）：`IGroupJoin` 的 `join`、`trialExit`→`providerWithdraw`、`joinInfo`、`totalJoinedAmountByGroupId`、`trialAccountsWaitingAdd/Remove`→`providerQuotaAdd/Remove`、`trialAccountsWaiting`→`providerQuota` 依次对应；`IGroupVerify` 的 `submitOriginScores`、`originScoreByAccount`→`originScore`、`accountScore`→`finalScore`、`totalGroupScore`→`totalFinalScore`、`verifiedAccountCount`→`verifiedMemberCount`、`isVerified`→`isRoundVerified`、`verifiers`→`lockedVerifierId` 依次对应；`IGroupManager` 的 `activateGroup`、`deactivateGroup`、`updateGroupInfo`→`updateGroupConfig`、`groupInfo` 依次对应且中间无删除。

结构体随模块走：`GroupConfig` 在 `IGroupActionManager.sol`、`VerifierApplication` 在 `IGroupActionVerify.sol`。36 个自有错误分列在四个错误子接口中（Join 15 / Verify 9 / Manager 7 / Executor 5）。

四阶段轮次（投票、加入、验证、铸币）。

### 结构体

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `GroupConfig { description, maxCapacity, minJoinAmount, maxJoinAmount, maxAccounts }` | `IGroupManager.GroupInfo { groupId, description, maxCapacity, minJoinAmount, maxJoinAmount, maxAccounts, isActive, activatedRound, deactivatedRound }` | 改名+改参（配置与状态拆分） |
| `VerifierApplication { applicationId, memberId, description }` | 无 | 新增（2026-10-07 移除动态字段 `votes`/`active` 与 `ratioForPublicVerifier`；票数走 `votesByVerifierIds`/`topVerifiers`，比例移至 GroupService） |

状态字段（`isActive`、`activatedRound`、`deactivatedRound`）从结构体移到 `groupInfo()` 的返回值。

### 链群配置

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `activateGroup(tokenAddress, actionId, groupId, GroupConfig)` | `IGroupManager.activateGroup(extension, groupId, description, maxCapacity, minJoinAmount, maxJoinAmount, maxAccounts_)` | 改参（展开参数 → 结构体） |
| `deactivateGroup(tokenAddress, actionId, groupId)` | `IGroupManager.deactivateGroup(extension, groupId)` | 改参 |
| `updateGroupInfo(tokenAddress, actionId, groupId, GroupConfig)` | `IGroupManager.updateGroupInfo(extension, groupId, newDescription, newMaxCapacity, newMinJoinAmount, newMaxJoinAmount, newMaxAccounts)` | 改参 |
| `groupInfo(tokenAddress, actionId, groupId) returns (config, active, activatedRound, deactivatedRound)` | `IGroupManager.groupInfo(extension, groupId) returns (GroupInfo)` | 改参 |
| `JOIN_TOKEN_ADDRESS(tokenAddress, actionId)`、`ACTIVATION_STAKE_AMOUNT(tokenAddress, actionId)`、`MAX_JOIN_AMOUNT_RATIO(tokenAddress, actionId)`、`ACTIVATION_MIN_GOV_RATIO(tokenAddress, actionId)` | `IGroupAction` 同名 | 改参（补单例行动作用域；配置来自创建回调的 Target Data） |
| `descriptionByRound`、`activeGroupIds`、`isGroupActive`、`maxJoinAmount`、`staked`、`totalStaked`、`totalStakedByMemberId`、`hasActiveGroups` | `IGroupManager.descriptionByRound`、`activeGroupIds`(+`Count`/`AtIndex`)、`isGroupActive`、`maxJoinAmount`、`staked`、`totalStaked`、`totalStakedByOwner`、`hasActiveGroups` | 批次二按覆盖原则补回、批次三收敛（改 `(tokenAddress, actionId)` 键与标准分页，`Count`/`AtIndex` 由分页总数覆盖；`totalStakedByOwner` 改 memberId 主体并定名 `totalStakedByMemberId`） |
| `tokenAddressesByGroupId`、`actionIdsByGroupId`、`actionIds` | `IGroupManager.tokenAddressesByGroupId`(+`Count`/`AtIndex`)、`actionIdsByGroupId`(+`Count`/`AtIndex`)、`actionIds`(+`Count`/`AtIndex`) | 批次二补回（改标准分页，`Count`/`AtIndex` 由分页总数覆盖） |
| 无 | `IGroupManager.activeGroupIdsByOwner`、`stakedByOwner`、`PRECISION` | 删除（批次三：`groupId` 即群主体 memberId，行动内激活用 `isGroupActive` 直查、激活群质押为常量 `ACTIVATION_STAKE_AMOUNT(tokenAddress, actionId)`；`PRECISION` 为实现常量） |

### 参与与 Provider 额度

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `join(tokenAddress, actionId, groupId, memberId, amount, providerId, verificationInfos[])` | `IGroupJoin.join(extension, groupId, amount, verificationInfos[])`、`IGroupJoin.trialJoin(extension, groupId, address provider, verificationInfos[])` | 改参（合并自有与体验入口：`providerId` 为 `0` 表示自有、非零表示 Provider 额度；重复调用为按来源追加） |
| `exit(tokenAddress, actionId, memberId)` | `IGroupJoin.exit(extension)` | 改参 |
| `withdraw(tokenAddress, actionId, memberId, amount)` | 无 | 新增（部分撤回，仅自有账本） |
| `joinInfo(tokenAddress, actionId, round, memberId) returns (joinedRound, amount, groupId, ownAmount, providerAmount)` | `IGroupJoin.joinInfo(extension, round, address account) returns (joinedRound, amount, groupId, address provider)` | 改参（去 `provider` 返回，2026-10-07 增 `ownAmount`/`providerAmount` 聚合；`amount` 为全部来源合计） |
| `memberIdsByGroupId(tokenAddress, actionId, round, groupId)` | `IGroupJoin.accountsByGroupId(extension, round, groupId)` | 改名+改参 |
| `joinedAmountByMemberId(tokenAddress, actionId, round, memberId)`（基座继承） | `IGroupJoin.joinedAmountByAccount(extension, round, address account)` | 改名+改参（上提基座） |
| `groupIds(tokenAddress, actionId, round, offset, limit, reverse) returns (groupIds[], total)` | `IGroupVerify.groupIds(extension, round)` | 改参（批次三恢复并补标准分页；该轮有参与成员的链群，验证者据此逐个验证） |
| `providerWithdraw(tokenAddress, actionId, memberId, providerId, amount)` | `IGroupJoin.trialExit(extension, address account)` | 改名+改参（全额退出 → 按额撤回，仅减指定 Provider 账本，仅该 Provider 当前持有人可调） |
| `providerQuotaAdd(tokenAddress, actionId, groupId, providerId, uint256[] memberIds, uint256[] amounts)` | `IGroupJoin.trialAccountsWaitingAdd(extension, groupId, address[] trialAccounts, uint256[] trialAmounts)` | 改名+改参（名单语义改为 Provider 额度：授予即存入合约；重复授予是追加，不再回滚） |
| `providerQuotaRemove(tokenAddress, actionId, groupId, providerId, uint256[] memberIds)` | `IGroupJoin.trialAccountsWaitingRemove(extension, groupId, address[] trialAccounts)` | 改名+改参（收回未使用额度并按额退还） |
| `providerQuota(tokenAddress, actionId, groupId, providerId, offset, limit, reverse) returns (memberIds[], amounts[], blockNumbers[], total)` | `IGroupJoin.trialAccountsWaiting(extension, groupId, address provider) returns (accounts[], trialAmounts[], blockNumbers[])` | 改名+改参（补标准分页；旧为无界全量读取） |
| `providerAmountsByMemberId(tokenAddress, actionId, round, memberId, offset, limit, reverse) returns (providerIds[], amounts[], total)` | 无 | 新增（标准分页；某成员全部有余额的来源及金额，供展示与管理） |
| 无 | `IGroupJoin.trialJoin(extension, groupId, address provider, verificationInfos[])` | 合并进 `join`（见上） |
| 无 | `IGroupJoin.trialAccountsWaitingRemoveAll`、`trialAccountsWaitingCount`、`trialAccountsWaitingAtIndex`、`trialAccountsJoined`(+`Count`/`AtIndex`) | 删除 6 项 |
| 无 | `IGroupJoin.groupIdByAccount` | 删除（`joinInfo` 返回 `groupId`） |
| `totalJoinedAmountByGroupId(tokenAddress, actionId, round, groupId)` | `IGroupJoin.totalJoinedAmountByGroupId(extension, round, groupId)` | **已补回**（改参：新增 `actionId`，单例多行动模型） |
| `joinedAmount(tokenAddress, actionId, round)`（基座继承） | `IGroupJoin.joinedAmount(extension, round)` | **已补回**（改参：新增 `actionId`，上提基座） |
| 无 | `IGroupJoin.totalJoinedAmountByGroupOwner` | 删除（群归属从 owner 地址改为链群维度，裁决不补） |
| 无 | `IGroupJoin.accountsByGroupIdCount`、`accountsByGroupIdAtIndex`、`accountIndexByGroupId` | 删除 |

### 验证与验证者竞选

新增公开验证者竞选机制（票据 [03-public-verifier-election](../bsc-protocol-migration/issues/03-public-verifier-election.md)），旧版按链群 owner 指派/委托验证。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `submitOriginScores(tokenAddress, actionId, verifierId, groupId, startIndex, originScores[])` | `IGroupVerify.submitOriginScores(extension, groupId, startIndex, originScores[])` | 改参（新增 `verifierId`；只能提交当前验证轮，不收 `round`） |
| `originScore(tokenAddress, actionId, round, memberId) returns (score, verified)` | `IGroupVerify.originScoreByAccount(extension, round, address account) returns (uint256)` | 改名+改参（新增 `verified` 返回） |
| `finalScore(tokenAddress, actionId, round, memberId) returns (score, verified)` | `IGroupVerify.accountScore(extension, round, address account)` | 改名+改参（2026-10-07 增 `verified` 返回，与 `originScore` 对齐） |
| `totalFinalScore(tokenAddress, actionId, round)` | `IGroupVerify.totalGroupScore(extension, round)` | 改名+改参 |
| `verifiedMemberCount(tokenAddress, actionId, round, groupId)` | `IGroupVerify.verifiedAccountCount(extension, round, groupId)` | 改名+改参 |
| `isRoundVerified(tokenAddress, actionId, round)` | `IGroupVerify.isVerified(extension, round, groupId)` | 改名+改参（粒度 groupId → round） |
| `lockedVerifierId(tokenAddress, actionId, round)` | `IGroupVerify.verifiers(extension, round)`(+`Count`/`AtIndex`) | 改名+改参（多验证者列表 → 单一锁定验证者） |
| `submitVerifierApplication(tokenAddress, actionId, memberId, description) returns (applicationId)` | 无 | 新增（2026-10-07 定名，原 `applyForVerifier`；`ratioForPublicVerifier` 移至 GroupService 按服务 Proposal 绑定） |
| `cancelVerifierApplication(tokenAddress, actionId, memberId)` | 无 | 新增 |
| `verifierApplication`、`verifierApplications`、`votesByVerifierIds`、`topVerifiers` | 无 | 新增 4 项（`verifierApplication` 回该成员当前申请、无则回零值结构体；`verifierApplications` 是唯一直接回含变长字段记录体的分页查询，消费方仅链下；`votesByVerifierIds` 按显式 id 批量回当轮票数、无票回 0；`topVerifiers` 按票数降序回 `verifierIds[]`/`votes[]`，榜容量前 `n` 名属有界集合） |
| `generatedActionRewardByGroupId(tokenAddress, actionId, round, groupId)` | `IGroupAction.generatedActionRewardByGroupId(round, groupId)` | 改参 |
| 无 | `IGroupAction.generatedActionRewardByVerifier(address verifier, round)` | 删除（旧参数实际表示链群 owner 地址；BSC 以 `groupId` 作为链群主体，使用 `generatedActionRewardByGroupId`） |
| `init(actionTargetAddress, stakeAddress, uint256[] splits)` | `IGroupManager.initialize(factory_)`、`IGroupJoin.initialize(factory_)`、`IGroupVerify.initialize(factory_)` | 改名+改参（三处初始化合并为一处；`memberNFTAddress`/`phaseAddress`/`voteAddress` 从 `stakeAddress` 派生，不收 `mintAddress`） |
| 无 | `IGroupVerify.setGroupDelegate`、`delegateByGroupId`、`canVerify`、`verifierByGroupId`、`submitterByGroupId` | 删除（验证者由竞选锁定，不再按链群委托） |
| 无 | `IGroupVerify.distrustVote`、`distrustVotesByGroupOwner`、`distrustVotesByVoterByGroupOwner`、`distrustReason`、`distrustVotersByGroupOwner`(+`Count`/`AtIndex`)、`distrustGroupOwners`(+`Count`/`AtIndex`)、`distrustRateByGroupId` | 删除 11 项（不信任投票机制整块不迁移） |
| 无 | `IGroupVerify.groupIdsByVerifier`(+`Count`/`AtIndex`)、`actionIdsByVerifier`(+`Count`/`AtIndex`)、`actionIds`(+`Count`/`AtIndex`)、`groupIdsCount`/`groupIdsAtIndex` | 删除 11 项 |
| 无 | `IGroupVerify.totalAccountScore`、`groupScore`、`MAX_ORIGIN_SCORE`、`PRECISION` | 删除 |

### 事件

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `Joined`、`Withdrawn`、`Exited` | `IGroupJoin.Join(...)`、`Exit(...)`（各含 3 个 accountCount 字段） | 改名+改参（Executor 层事件包含完整业务字段：`Joined`/`Withdrawn` 带 `amount`、来源键 `providerId` 与链群 `groupId`，`Exited` 带链群 `groupId`、不带金额；代币量只由 `Joined`/`Withdrawn` 承载；ActionTarget 层发出简化的 `Joined`/`Exited` 事件） |
| `ProviderQuotaAdded`、`ProviderQuotaRemoved` | 无 | 新增（授予/收回额度都转移代币，须可观测；按对称原则命名，`Removed` 带实际退还金额） |
| `OriginScoresSubmitted(tokenAddress, actionId, groupId, round, verifierId, startIndex, scores[])` | `IGroupVerify.SubmitOriginScores(tokenAddress, round, actionId, groupId, startIndex, count, isComplete)` | 改名+改参（新增 `scores` 明细，去 `isComplete`；2026-10-07 增 `verifierId` 并统一 `verifierMemberId` → `verifierId`；批次序号统一为 `startIndex`，`BatchIndexMismatch` 同步改名 `StartIndexMismatch`） |
| `VerifierApplicationSubmitted`、`VerifierApplicationCancelled`、`VerifierLocked` | 无 | 新增（`VerifierApplied` 2026-10-07 改名为 `VerifierApplicationSubmitted`，与取消事件同词干对称；`Cancelled` 批次六补 `round`，与 `Submitted` 字段对称——撤销与申请同在创建轮作用域） |
| `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` | 无（旧在 `IReward`） | 新增（声明在共用基座 `IActionExecutorEvents`；per-member 口径与两个金额分量沿用） |
| `GroupActivated`、`GroupDeactivated`、`GroupConfigUpdated` | `IGroupManager.ActivateGroup`、`DeactivateGroup`、`UpdateGroupInfo` | 已补回并改名（去 `owner` 字段，保留 `stakeAmount`；2026-10-07 按事件完成时态原则改名，`updateGroupInfo` 同步定名 `updateGroupConfig`） |
| 无 | `IGroupJoin.TrialAccountsWaitingUpdated` | 删除 |
| 无 | `IGroupVerify.SetGroupDelegate`、`DistrustVote` | 删除（验证者委托与不信任投票机制不迁移） |

`IGroupActionExecutor` 已声明 `GroupActivated`、`GroupDeactivated`、`GroupConfigUpdated`、`OriginScoresSubmitted`、`VerifierApplicationSubmitted`、`VerifierApplicationCancelled`、`VerifierLocked`、`Joined`、`Withdrawn`、`Exited`、`ProviderQuotaAdded`、`ProviderQuotaRemoved` 十二个事件：前三个源自旧 `IGroupManagerEvents` 同名事件，2026-10-07 按事件完成时态原则改名，去 `owner` 字段（主体改为 memberId，owner 快照不再进事件）、保留 `stakeAmount`；`ProviderQuotaAdded`/`ProviderQuotaRemoved`、`VerifierApplicationCancelled` 为 2026-10-07 按事件设计原则补齐——`providerQuotaAdd`/`providerQuotaRemove` 转移代币、`cancelVerifierApplication` 为新增写函数，此前无事件；`VerifierApplied` 同日改名为 `VerifierApplicationSubmitted`，与取消事件同词干对称。本接口 `init` 无事件，属「事件设计原则」允许的例外（一次性注入，状态可经 `initialized()` 与配置 getter 观测）；创建/投票回调的写入由 core 侧 `ActionCreated`/`Voted`（targetData 携带行动配置与候选）承载，不另发事件。本接口不自行声明 `ActionRewardMinted`（在 `IActionTargetEvents`）与 `RewardBurned`（在 `IActionTargetEvents`，销毁执行在 ActionTarget）；`needBurnReward` 提供行动级销毁判据。

### 错误

四个子接口共声明 **36 个**错误（另有 8 个共用基座错误由 `IActionExecutorErrors` 继承，完整错误 ABI 为 44），按实现模块归属：`IGroupActionJoinErrors` 15 个、`IGroupActionVerifyErrors` 9 个、`IGroupActionManagerErrors` 7 个、`IGroupActionExecutorErrors` 5 个（`InvalidAddress`、`InvalidSplits`、`InvalidTargetDataLength`、`VerificationInfoLengthMismatch`、`DescriptionTooLong`——后三个跨模块共用，归 Executor 自身）。其中 24 个自旧接口补齐/改名，见本节末表。

其中 5 个有旧对应：`InvalidParticipationAmount` ← `JoinAmountZero`/`AmountBelowMinimum`、`InvalidCandidate` ← `NotVerifier`、`GroupNotActive` 保留原名（旧 `IGroupManager` 的群未激活错误，改由群管理路径抛出，不再映射到 `ApplicationNotActive`）、`StartIndexMismatch` ← `InvalidStartIndex`、`InvalidAddress` ← 旧构造函数的零地址校验。

四个子接口独有的 6 个：`InvalidSplits`（`init` 的 `splits` 分割线校验，`IGroupActionExecutorErrors`）、`InvalidTargetDataLength`（创建与投票回调的 Target Data 项数，`IGroupActionExecutorErrors`）、`VerificationInfoLengthMismatch`（验证信息 schema 与成员值长度，`IGroupActionExecutorErrors`）、`ApplicationNotActive`（当前申请不存在或已失效，`IGroupActionVerifyErrors`）、`VerifierAlreadyLocked`（验证者竞选锁定，`IGroupActionVerifyErrors`）、`InsufficientProviderQuota(providerId, required, available)`（Provider 额度不足，`IGroupActionJoinErrors`）。阶段未开始、回调权限、成员归属、提案未投票、轮次、重复铸造等 6 个样板错误由基座承担。`InvalidKVLength` 已删除——无键 `bytes[]` 下不存在「两数组」，各 Executor 需要项数校验时自行声明。

旧三接口共 **44 条错误声明、40 个不同错误名**（`NotRegisteredExtensionInFactory` 在三个接口各声明一次，`ExtensionNotInitialized`、`OnlyGroupOwner` 各两次）。40 个名字的归处如下，**未归类 0、无杜撰名字**：

| 归类 | 数量 | 错误名 |
| --- | --- | --- |
| 已被现有新声明覆盖 | 5 | `JoinAmountZero`、`AmountBelowMinimum`（→ `InvalidParticipationAmount`）、`NotVerifier`（→ `InvalidCandidate`）、`AlreadyInitialized`（保留）、`InvalidStartIndex`（→ `StartIndexMismatch`） |
| **已补回（原名）** | 20 | `GroupNotActive`（`IGroupActionManagerErrors`）与按原名补回的 19 个，分散在 `IGroupActionJoinErrors`、`IGroupActionVerifyErrors`、`IGroupActionManagerErrors` 三个模块子接口 |
| 改名（Provider 额度词汇） | 5 | `TrialArrayLengthMismatch` → `QuotaArrayLengthMismatch`、`TrialAccountZero` → `QuotaMemberZero`、`TrialAccountIsProvider` → `QuotaMemberIsProvider`、`TrialAmountZero` → `QuotaAmountZero`、`TrialAccountNotInWaitingList(address account)` → `QuotaNotGranted(uint256 memberId)` |
| 裁决不补 | 10 | `AlreadyJoined`、`TrialAlreadyJoined`、`TrialAccountAlreadyAdded`、`TrialProviderMismatch`（统一 `join` 后重复加入与重复授予是追加，不再是错误）；`DistrustVoteExceedsVerifyVotes`、`DistrustVoteZeroAmount`、`InvalidReason`（不信任投票机制整块不迁移）；`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`、`InvalidFactoryAddress`（extension 工厂体系取消） |

补回与改名的 25 个错误对应新实现仍需暴露的校验，不能用 `require` 或通用错误替代；加上阶段未开始错误并扣除已删的 `InvalidKVLength` 后，接口错误数为 44（36 自有 + 基座 8）。见 [README「已确认并落地」](README.md#已确认并落地)。

其中 `TrialAccountNotInWaitingList(address account)` 按主体统一规则改为 `uint256 memberId`，并随额度词汇一并改名为 `QuotaNotGranted`；其余补回错误没有参数。

- **`IGroupJoin`（23 个）**：`JoinAmountZero`、`AlreadyInOtherGroup`、`NotJoinedAction`、`AmountBelowMinimum`、`ExceedsActionMaxJoinAmount`、`ExceedsGroupMaxJoinAmount`、`GroupCapacityExceeded`、`GroupAccountsFull`、`CannotJoinInactiveGroup`、`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`、`InvalidGroupId`、`AlreadyJoined`、`TrialAlreadyJoined`、`TrialArrayLengthMismatch`、`TrialAccountIsProvider`、`TrialAccountZero`、`TrialAmountZero`、`TrialAccountAlreadyAdded`、`TrialAccountNotInWaitingList(address account)`、`TrialProviderMismatch`、`AlreadyInitialized`、`InvalidFactoryAddress`。
- **`IGroupManager`（8 个）**：`GroupAlreadyActivated`、`GroupNotActive`、`InvalidMinMaxJoinAmount`、`CannotDeactivateInActivatedRound`、`OnlyGroupOwner`、`NotRegisteredExtensionInFactory`、`InsufficientActivationMinGovRatio`、`NoGovVotes`。
- **`IGroupVerify`（13 个）**：`OriginScoresEmpty`、`NotVerifier`、`ScoreExceedsMax`、`AlreadyVerified`、`InvalidStartIndex`、`ScoresExceedAccountCount`、`VerifyVotesZero`、`DistrustVoteExceedsVerifyVotes`、`InvalidReason`、`DistrustVoteZeroAmount`、`OnlyGroupOwner`、`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`。

按语义分组：容量校验（`GroupCapacityExceeded`、`GroupAccountsFull`、`ExceedsActionMaxJoinAmount`、`ExceedsGroupMaxJoinAmount`）、归属校验（`AlreadyInOtherGroup`、`NotJoinedAction`）、Provider 额度校验（`QuotaArrayLengthMismatch`、`QuotaMemberIsProvider`、`QuotaMemberZero`、`QuotaAmountZero`、`QuotaNotGranted`、`InsufficientProviderQuota`）、群管理校验（`GroupNotActive`、`CannotJoinInactiveGroup`、`InvalidGroupId`、`GroupAlreadyActivated`、`InvalidMinMaxJoinAmount`、`CannotDeactivateInActivatedRound`、`OnlyGroupOwner`、`InsufficientActivationMinGovRatio`、`NoGovVotes`）、权限与初始化校验（`NotRegisteredExtensionInFactory`、`ExtensionNotInitialized`、`InvalidFactoryAddress`）、不信任投票（`DistrustVoteExceedsVerifyVotes`、`DistrustVoteZeroAmount`、`InvalidReason`）。

---

## 4. IGroupActionIndexes vs IGroupJoin 的 g* 索引

旧：`LOVE20TKM/extension-group/src/interface/IGroupJoin.sol#g*`。17 组索引、51 个函数（每组 3 个：`数组()` / `Count()` / `AtIndex(index)`）。

**本轮裁决：保留 5 组、收敛为按真实问题组织的查询**（51 → 5 条分页 + 1 条布尔）。理由：17 组全是**无界集合的全量数组读取**，违反 [集合读取函数的设计原则](../../docs/migration-standards.md#集合读取函数的设计原则)；逐条核对后只有第 9 组有具名调用方（group-chat 的链群归属判据），其余 16 组在规格中没有任何消费方。协议与 Group Chat 均未部署，改动无兼容负担。保留的 5 组正好是「一跳维度」的五个方向，丢掉的是全部两跳组合与反向维度。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `isGroupMember(uint256 groupId, uint256 memberId) returns (bool)` | `gTokenAddressesByGroupIdByMemberIdCount(uint256 groupId, uint256 memberId) > 0`（第 9 组） | 新增（同一份存储的存在性布尔读；调用方见 [group-chat](group-chat.md)） |
| `gGroupIds(uint256 offset, uint256 limit, bool reverse) returns (uint256[], uint256)` | `gGroupIds`（第 1 组，全量 + `Count` + `AtIndex`） | 改参（三件套合并为一个标准分页查询，名称不变） |
| `gGroupIdsByMemberId(uint256 memberId, uint256 offset, uint256 limit, bool reverse) returns (uint256[], uint256)` | `gGroupIdsByAccount`（第 2 组） | 改名+改参（`Account` → `MemberId`；三件套合并为分页） |
| `gTokenAddressesByGroupIdByMemberId(uint256 groupId, uint256 memberId, uint256 offset, uint256 limit, bool reverse) returns (address[], uint256)` | `gTokenAddressesByGroupIdByAccount`（第 9 组） | 改名+改参（同上） |
| `gMemberIds(uint256 offset, uint256 limit, bool reverse) returns (uint256[], uint256)` | `gAccounts`（第 14 组） | 改名+改参（同上） |
| `gMemberIdsByGroupId(uint256 groupId, uint256 offset, uint256 limit, bool reverse) returns (uint256[], uint256)` | `gAccountsByGroupId`（第 15 组） | 改名+改参（同上） |
| 无 | 其余 12 组共 36 个函数 | 删除（无具名调用方；无界集合不再提供全量读取） |

旧侧 51 个函数的去向逐条闭合：第 1、2、9、14、15 组各 3 个函数合并为 1 条分页查询（共 15 → 5），另加第 9 组的伴生布尔 `isGroupMember`；其余 12 组（第 3、4、5、6、7、8、10、11、12、13、16、17 组，36 个函数）随本裁决删除。`g*` 记号在新接口中保留，含义是「由参与事实维护、跨全部社区的当前索引」——只有真的有人参与过才会入榜，与本合约既有的「群激活」（`GroupNotActive`）不是一回事。

加入阶段写入的按轮历史另提供两条读，不属本接口：`groupIds(tokenAddress, actionId, round, offset, limit, reverse)` 与该轮某链群的 `memberIdsByGroupId(...)`。前者旧在 `IGroupVerify`（旧实现由**验证提交时登记**该轮链群），新设计的验证集合改由加入阶段形成，故随实现归属移入 `IGroupActionJoin.sol`；后者对应旧 `IGroupJoin.accountsByGroupId`，本就在加入侧，名称与位置不变。

删除的 12 组：Group ID 维度的按社区、跨社区按行动、跨社区按成员枚举（第 3、4、5 组），Token Address 维度的全部（第 6–8 组），Action ID 维度的全部（第 10–13 组），Member ID 维度的按社区与按社区按链群枚举（第 16、17 组）。需要时按同一分页签名新增单条查询，不再维护维度组合。

---

## 5. IGroupServiceExecutor vs IGroupService + IGroupRecipients

旧：`LOVE20TKM/extension-group/src/interface/IGroupService.sol`、`LOVE20TKM/extension-group/src/interface/IGroupRecipients.sol`。

四阶段轮次，复用 GroupAction 的验证结果，自身不执行验证。

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `actionTokenAddress(serviceTokenAddress, serviceProposalId)` | `IGroupService.GROUP_ACTION_TOKEN_ADDRESS()` | 改名+改参（部署常量 → 按提案查询） |
| `totalGroupActionReward(actionTokenAddress, round) returns (reward, cached)` | `IGroupService.generatedActionReward(round)` | 改名+改参（新增 `cached` 返回） |
| `rewardDistribution(serviceTokenAddress, serviceProposalId, round, sourceActionId, groupId) returns (recipientIds[], ratios[], amounts[], ownerAmount)` | `IGroupService.rewardDistribution(address verifier, round, actionId, groupId) returns (addrs[], ratios[], amounts[], ownerAmount)` | 改参（`verifier` → 服务提案定位，`addrs` → `recipientIds`） |
| `setRecipients(sourceTokenAddress, sourceActionId, groupId, uint256[] recipientIds, ratios[], remarks[])` | `IGroupRecipients.setRecipients(tokenAddress, actionId, groupId, address[] addrs, ratios[], remarks[])` | 改参 |
| `recipients(sourceTokenAddress, sourceActionId, groupId, round) returns (recipientIds[], ratios[], remarks[])` | `IGroupRecipients.recipients(address groupOwner, tokenAddress, actionId, groupId, round) returns (addrs[], ratios[], remarks[])` | 改参（去 `groupOwner` 参数） |
| `burnRewardIfNeeded(tokenAddress, actionId, round)`（落在 ActionTarget，GS 经 `needBurnReward` 提供判据） | `IReward.burnRewardIfNeeded(round)` | 改参并跨层（单例服务 Proposal 作用域 → token + actionId） |
| `join(serviceTokenAddress, serviceProposalId, memberId, verificationInfos[])` | 旧 `IGroupService` 未声明，由 `ITokenJoin.join(uint256 amount, string[] verificationInfos)` 提供 | 跨接口迁移（补齐 `tokenAddress`/`proposalId` 前缀，去掉独立 `amount`） |
| `exit(serviceTokenAddress, serviceProposalId, memberId)` | 旧由 `ITokenJoin.exit()` / `IJoin.exit()` 提供 | 跨接口迁移 |
| `joinInfo(serviceTokenAddress, serviceProposalId, round, memberId) returns (bool joined)` | 旧由 `ITokenJoin.joinInfo(address account)` 提供（返回 `joinedRound, amount, lastJoinedBlock, exitableBlock`） | 跨接口迁移+改参（返回值简化为是否参与） |
| `serviceRewardByMember(serviceTokenAddress, serviceProposalId, round, memberId) returns (verifierReward, ownerReward, ownerBurned, claimed)` | 无 | 新增 |
| `currentVoteRound`、`currentJoinRound`、`currentVerifyRound`、`currentMintRound` | 无 | 新增 |
| `init(actionTargetAddress, stakeAddress, groupActionExecutorAddress)` | 无 | 新增（`memberNFTAddress`/`phaseAddress`/`voteAddress` 从 `stakeAddress` 派生，不收 `mintAddress`） |
| 继承 `IProposalTarget` | 无 | 新增 |
| 无 | `IGroupService.GROUP_ACTION_FACTORY_ADDRESS()` | 删除（取消工厂） |
| 无 | `IGroupService.rewardByRecipient(verifier, round, actionId, groupId, recipient)` | 删除 |
| 无 | `IGroupService.hasActiveGroups(address owner)` | 删除 |
| 无 | `IGroupService.generatedActionRewardByVerifier(verifier, round)` | 删除（链群主激励改由 `generatedActionRewardByGroupId` 按 groupId 查询） |
| 无 | `IGroupService.govRatio(round, address account)` | 删除（保留在 `ILpExecutor`） |
| 无 | `IGroupService.PRECISION()`、`GOV_RATIO_MULTIPLIER()` | 删除 getter |
| 无 | `IGroupRecipients.getDistribution(groupOwner, tokenAddress, actionId, groupId, groupReward, round)` | 删除（合并进 `rewardDistribution`） |
| 无 | `IGroupRecipients.actionIdsWithRecipients`、`groupIdsByActionIdWithRecipients` | 删除 |
| 无 | `IGroupRecipients.PRECISION()`、`DEFAULT_MAX_RECIPIENTS()` | 删除 getter |

### 事件与错误

| 新 | 旧 | 状态 |
| --- | --- | --- |
| `ServiceRewardDistributed(serviceTokenAddress, serviceProposalId, actionTokenAddress, memberId, verifierReward, ownerReward, ownerBurned, round)` | `IGroupService.ClaimRewardDistribution(tokenAddress, round, actionId, address account, mintAmount, burnAmount, distributed, remaining)` | 改名+改参（成员级的**追加事件**：基座 `MemberRewardMinted` 记公共口径，本事件追加 `actionTokenAddress` 与角色拆分；须满足 `MemberRewardMinted.mintAmount == verifierReward + ownerReward`、`.burnAmount == ownerBurned`） |
| `SecondaryDistributionConfigured(sourceTokenAddress, sourceActionId, groupId, round, recipientIds[], ratios[])` | `IGroupRecipients.SetRecipients(tokenAddress, round, actionId, groupId, address account, recipients[], ratios[], remarks[])` | 改名+改参（去 `remarks` 字段） |
| `RewardBurned` | 无 | 新增（**整批销毁**：服务轮次无可分配源行动时销毁整笔服务激励，无成员归属，因此不并入成员级事件） |
| `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` | 无（旧在 `IReward`） | 新增（声明在共用基座 `IActionExecutorEvents`） |
| 无 | `IGroupService.DistributeRecipient` | 删除（逐笔分配明细无事件） |
| 错误 `DistributionOverflow(configured, available)` | `IGroupRecipients.InvalidRatio()` | 改名+改参（语义近似） |
| 错误 `AlreadyInitialized`、`InvalidRound`、`RoundNotStarted`、`NotMemberOwner`、`ProposalNotVoted`、`UnauthorizedCallback`、`RewardAlreadyMinted` | 无 | 新增（声明在共用基座 `IActionExecutorErrors`，本接口由继承获得） |
| 无 | `IGroupService.NoActiveGroups`、`InvalidExtension`；`IGroupRecipients.TooManyRecipients`、`ZeroAddress`、`ZeroRatio`、`ArrayLengthMismatch`、`DuplicateAddress`、`RecipientCannotBeSelf`、`OnlyGroupOwner` | 删除 9 项 |

GS 事件数为 **5**（`Joined`、`Exited`、`ServiceRewardDistributed`、`SecondaryDistributionConfigured`，加基座继承的 `MemberRewardMinted`），错误数为 **9**（`DistributionOverflow` 独有，其余 8 个由基座继承），自身函数 **11**（2026-10-07 增 `ratioForPublicVerifier`），合计 ABI 41 条。

## 2026-10-07 接口修订批次二（事件设计原则落地 + 旧接口覆盖补齐）

本批次按 `docs/migration-standards.md`「事件设计原则」与「新接口完全覆盖旧接口」要求修订，覆盖前文各表对应行；模块规格待本批确认后同步。

### IGroupActionJoin

- `Withdrawn`、`Exited` 补 `groupId` 字段，与 `Joined` 对齐（退出可索引到链群）。
- `ProviderQuotaAdded`/`ProviderQuotaRemoved` 由批量数组改为单成员 `memberId` + `amount`；`providerQuotaAdd`/`providerQuotaRemove` 逐成员发多条日志。
- `providerMemberId` 全部简化为 `providerId`（含 `InsufficientProviderQuota` 参数）。
- 删除 `groupIds`（行动轮维度群列表，群集合读取由 Manager 侧承担）。
- 删除 `providerAmount`（按来源单值）；`joinInfo` 返回追加 `ownAmount`、`providerAmount` 聚合值，分来源明细走 `providerAmounts`。
- `providerAmountsByMemberId` 曾按主体键口径短暂改为 `providerAmounts`，批次五裁决严格按「按键筛选 By<key>」定名 `providerAmountsByMemberId`（memberId 为筛选键进名）。

### IGroupActionVerify

- `ratioForPublicVerifier` 移出申请流程，移入 `IGroupServiceExecutor` 作为绑定 `serviceProposalId` 的参数（先落只读入口；写入路径预期走服务提案 target data，待确认）。
- `submitOriginScores` 去掉 `round` 入参（只能提交最新验证轮）；事件仍带 `round` 由实现回填。
- `finalScore` 返回追加 `verified`，与 `originScore` 对齐。
- `applyForVerifier` 改名 `submitVerifierApplication`，事件 `VerifierApplicationApplied` 同步改名 `VerifierApplicationSubmitted`，与 `cancelVerifierApplication`/`VerifierApplicationCancelled` 成对同词干。
- 删除 `currentApplicationId`；新增 `verifierApplication(tokenAddress, actionId, memberId)` 回该成员当前申请（无则回零值结构体）。
- `verifierApplications` 去掉 `round`，回当前全部未取消申请。
- `VerifierApplication` 结构体移除动态字段 `votes`、`active` 与 `ratioForPublicVerifier`，仅留 `applicationId`、`memberId`、`description`。
- 新增 `verifierVotes(tokenAddress, actionId, round, verifierIds[])` 按 id 批量回当轮票数（下标对齐，无票回 0 不回滚）。
- `topVerifiers` 改回 `verifierIds[]` + `votes[]`（票数高到低；变长 `description` 不进榜内记录）。

### IGroupActionManager

- `updateGroupInfo` 改名 `updateGroupConfig`，事件 `GroupInfoUpdated` 同步改名 `GroupConfigUpdated`（与 `GroupConfig` 结构体对齐）。
- 按旧 `IGroupManager` 补齐覆盖：旧 `extension` 键翻译为 `(tokenAddress, actionId)`，Count/AtIndex 三件套统一翻译为标准分页 `(offset, limit, reverse) → (列表, 真实总数)`。补回 `descriptionByRound`、`activeGroupIdsByOwner`、`activeGroupIds`、`isGroupActive`、`maxJoinAmount`（按轮投票占比推导）、`stakedByOwner`、`staked`、`totalStaked`、`totalStakedByOwner`（token 维度、跨行动）、`tokenAddressesByGroupId`、`actionIdsByGroupId`、`actionIds`、`hasActiveGroups`。
- 不补：`FACTORY_ADDRESS`/`initialize`（extension 工厂体系已删）、`PRECISION`（实现常量，暴露口径待定）、各 Count/AtIndex（分页总数已覆盖）。

### IGroupServiceExecutor

- 新增 `ratioForPublicVerifier(serviceTokenAddress, serviceProposalId)` 只读入口，写入路径待确认。

### 2026-10-07 批次三（成员主体收敛与按轮群列表恢复）

- `groupId` 即群主体 `memberId`，同一成员**在同一行动上**至多激活一个链群：删除 `activeGroupIdsByOwner`（行动内激活与否用 `isGroupActive(tokenAddress, actionId, groupId)` 直查）；删除 `stakedByOwner`（激活群质押为常量 `ACTIVATION_STAKE_AMOUNT(tokenAddress, actionId)`）。不设行动维度的按 owner 激活/质押查询。
- 保留社区级跨行动判定与聚合：`hasActiveGroups(tokenAddress, owner)`（GroupService 加入时一次判定该成员在本代币社区是否有激活链群）；`totalStakedByOwner(tokenAddress, owner)`（各行动 `ACTIVATION_STAKE_AMOUNT` 可能不同且激活行动数未知，一次调用直出累计激活质押）。`staked(tokenAddress, actionId)` 与 `totalStaked(tokenAddress)` 两个聚合账本不变。
- 恢复 `IGroupActionJoin.groupIds(tokenAddress, actionId, round, offset, limit, reverse)`（批次二曾删除）：该轮有参与成员的链群列表，验证者据此逐个验证链群。

### 2026-10-07 批次四（Review 收尾）

- 主体统一：`hasActiveGroups(tokenAddress, owner: address)` → `hasActiveGroups(tokenAddress, memberId)`；`totalStakedByOwner` → `totalStakedByMemberId(tokenAddress, memberId)`（MemberNFT 转移后地址变化、memberId 不变，消费方 GroupService.join 手持 memberId）。
- 验证者命名统一：`verifierMemberId` → `verifierId`；`OriginScoresSubmitted` 增 `verifierId` 字段，事件自包含验证者身份。
- `joinInfo().amount` 与基座 `joinedAmountByMemberId` 同键同值确认为有意并存：基座是跨 Executor 统一聚合口径，`joinInfo` 是成员记录快照（口径落 `00-executor-interface.md`）。
- `DistributionOverflow` 从 `IGroupServiceExecutor` 主接口体内拆入 `IGroupServiceExecutorErrors` 子接口，与其他接口的 Events/Errors 拆分一致。
- `ratioForPublicVerifier` 写入路径确认为服务提案创建回调 `targetData[3]`。
- `IGroupServiceExecutor.sol` 暂不迁入 action 仓库：本轮迁移范围为 GroupAction，接口保留在 `matt-gov/interfaces/action/`，待 Group Service 迁移启动时再同步；action 仓库 `src/interfaces/` 现为 9 个文件，仅含 ActionTarget/LP/GroupAction 范围。

### 2026-10-07 批次五（review 报告采纳与对账清理）

外部 review 报告经逐条核实后采纳，裁决与清理如下：

- **榜容量**：`topVerifiers` 榜容量统一为前 `n` 名（`candidateCount = n = splits.length + 1`，与「只保存可开放的前 n 名」「可开放人数 = `SPLITS().length + 1`」三处一致）；规格 05 与 08-testing 的「前 n + 1」表述已改。
- **批次序号统一 `startIndex`**：`OriginScoresSubmitted` 事件字段 `batchIndex` 改为 `startIndex`（与函数参、规格词汇一致），错误 `BatchIndexMismatch` 改名 `StartIndexMismatch(expected, actual)`，参数语义落 `07-minting` 错误表。
- **命名严格化**：`providerAmounts` 定名 `providerAmountsByMemberId`、`verifierVotes` 定名 `votesByVerifierIds`（严格按「载荷 + 条件」命名表；memberId 为筛选键进名）。
- **接口注释清理**：`IVerificationInfo.sol` 移除 4 条接口体注释（语义在规格 05「验证信息」段）。
- **对账清理**：本文件函数计数表（62→73；GS 自身 10→11、合计 26→27）、错误计数（自有 35→36、完整 43→44）、主表函数行（`submitVerifierApplication` 族、`submitOriginScores`、`joinInfo`、`groupIds`、Provider 额度族、Manager 补回与删除行）、事件行（`GroupConfigUpdated`/`VerifierApplicationSubmitted`）、结构体行全部对齐现接口；README 文件表 g* 计数与事件名同步。
- `joinInfo().amount` 与基座 `joinedAmountByMemberId` 同键同值为有意并存（口径见 `00-executor-interface.md`，批次四已确认）。
- CHANGES-action §6 修正退出语义（外部指认）：成员 `exit` 只把 Provider 来源恢复为可用额度、不转出合约，`providerQuotaRemove` 才把代币退回 Provider 当前持有人；旧 `trialExit` 直接退款属旧行为，原「保留逻辑」中的错误表述移除，行为变更落「关键变化」。

### 2026-10-07 批次六（二轮 review 收尾）

- 主表事件行 :323 补齐（`providerId`、`Withdrawn`/`Exited` 带 `groupId`）；错误散文 :338/:340 与 core.md:477、README:146 的改名残留（`StartIndexMismatch`、`InsufficientProviderQuota(providerId, ...)`、`verifierId`/`providerId` 派生名）清零。
- `VerifierApplicationCancelled` 补 `round` 字段，与 `VerifierApplicationSubmitted` 对称（撤销与申请同在创建轮作用域）。
- `providerAmountsByMemberId` 口径落 03：按 `round` 轮快照返回有余额来源（RoundHistory 懒继承），替换歧义的「当前」。
- `descriptionByRound` 只读契约落 05：RoundHistory 懒继承，无记录继承最近历史，从未设置返回空串（旧实现 `_descriptionHistory[...].value(round)` 同源）。
- README「核对方法与覆盖度」的六层计数为 2026-10-06 评审轮次快照，本批大改后的全量重算需重跑其核对脚本，本批不做代拟更新。
