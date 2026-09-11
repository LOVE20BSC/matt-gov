# 新旧接口函数级对比

本目录是迁移分析证据，不是规格。ABI 以 [`interfaces/`](../../interfaces/) 为唯一来源；组件级迁移结论以 `docs/specs/CHANGES-*.md` 为准。本对比只回答一个问题：**新接口的每个函数、事件、错误来自旧代码哪里，或者是新增；旧代码的每个 ABI 去了哪里，或者被删除。**

实现前的三层 ABI 开工门槛与未决项见 [`abi-reconciliation.md`](abi-reconciliation.md)。

旧代码提交版本见 [`docs/repositories.md`](../../docs/repositories.md#旧代码基线)。

## 分层文档

| 文档 | 范围 |
| --- | --- |
| [core.md](core.md) | `interfaces/core/` 11 个接口 vs `LOVE20TKM/core`、`LOVE20TKM/group` |
| [action.md](action.md) | `interfaces/action/` 5 个接口 vs `LOVE20TKM/extension`、`extension-group`、`extension-lp` |
| [group-chat.md](group-chat.md) | `interfaces/group-chat/` 12 个接口 vs `LOVE20TKM/group-chat`、`LOVE20TKM/group` |

## 规模对比

| 侧 | 接口文件 | 接口声明 | 函数 | 事件 | 错误 |
| --- | --- | --- | --- | --- | --- |
| 新（`matt-gov/interfaces`） | 28 | 31 | 429 | 76 | 206 |
| 旧（6 个 LOVE20TKM 仓库） | 52 | 115 | 655 | 100 | 274 |

**统计口径**（三份分层文档的计数均可按此复现）：

- 旧侧文件 = 6 个 LOVE20TKM 仓库 `LOVE20TKM/<repo>/src` 下 `interface`/`interfaces` 目录内的全部 `.sol`；排除 `LOVE20TKM/group-chat/src/interfaces/external/`（14 个跨仓库镜像，非旧协议自有 ABI）；**包含** `LOVE20TKM/group/src/interfaces/ILOVE20Token.sol`（`core` 同名接口的逐字镜像，仅 import 路径不同）。
- 函数数按**声明条数**计，不做跨文件去重（同一函数名在不同接口各计一次）。
- 接口声明数与文件数不同：新侧 28 文件内含 **31 个** `interface` 声明——`IGroupChatRules.sol` 一个文件含 4 个（`IPostScopeSource`、`IPostBanSource`、`IBeforePostPlugin`、`IAfterPostPlugin`），其余文件各含 1 个；旧侧 52 文件内含 **115 个** `interface` 声明（去重后 112 个，`ILOVE20Token` 及其两个子接口在 `core` 与 `group` 各声明一次），其中 63 个是 `I<Name>Errors`/`I<Name>Events` 子接口——这 63 个子接口正是「跨层结构变化」第 2 条所说的内联化对象。
- **简写约定**（用于按名检索时的展开规则）：`X`(+`Count`/`AtIndex`) 表示 `X`、`XCount`、`XAtIndex` 三个函数；`aCount`/`AtIndex` 表示 `aCount` 与 `aAtIndex` 两个函数。旧协议大量使用「全量数组 + 长度 + 逐项读取」三件套，逐条列出会淹没差异，故按组名收敛。需要精确 ABI 时按此规则展开即可。

旧侧统计含 `IGroupMarket`、`ILOVE20SLToken`、`ILOVE20STToken` 等已裁决不迁移的接口。函数数下降主要来自三处：地址/ID 双路径合并、`extension` 实例模型改为单例多社区模型、公平发射募资与不信任投票等整块业务不迁移。

## 接口文件映射矩阵

### core

| 新接口 | 旧来源 | 状态 |
| --- | --- | --- |
| `core/IMemberNFT.sol` | `LOVE20TKM/group/src/interfaces/ILOVE20Group.sol` | 改名迁移 |
| `core/IPhase.sol` | `LOVE20TKM/core/src/interfaces/IPhase.sol` | 重构 |
| `core/ILOVE20Stake.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20Stake.sol` | 重构 |
| `core/ILOVE20Submit.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol` | 重构 |
| `core/ILOVE20Vote.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20Vote.sol` | 改名迁移 |
| `core/ILOVE20Mint.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20Mint.sol` | 重构 |
| `core/ILOVE20Launch.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20Launch.sol` | 重写 |
| `core/ILOVE20Token.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20Token.sol` | 微调 |
| `core/ILOVE20TokenFactory.sol` | `LOVE20TKM/core/src/interfaces/ILOVE20TokenFactory.sol` | 微调 |
| `core/IProposalTarget.sol` | 无 | 全新 |
| `core/ILaunchDistributor.sol` | 无 | 全新 |

### action

| 新接口 | 旧来源 | 状态 |
| --- | --- | --- |
| `action/IActionTarget.sol` | `LOVE20TKM/extension/src/interface/IExtensionCenter.sol`、`LOVE20TKM/extension/src/interface/IExtension.sol` | 重写 |
| `action/ILpExecutor.sol` | `LOVE20TKM/extension-lp/src/interface/ILp.sol`、`LOVE20TKM/extension/src/interface/ITokenJoin.sol`、`LOVE20TKM/extension/src/interface/IReward.sol` | 重写 |
| `action/IGroupActionExecutor.sol` | `LOVE20TKM/extension-group/src/interface/IGroupAction.sol`、`LOVE20TKM/extension-group/src/interface/IGroupManager.sol`、`LOVE20TKM/extension-group/src/interface/IGroupJoin.sol`、`LOVE20TKM/extension-group/src/interface/IGroupVerify.sol` | 重写 |
| `action/IGroupActionIndexes.sol` | `LOVE20TKM/extension-group/src/interface/IGroupJoin.sol#g*` | 改名迁移 |
| `action/IGroupServiceExecutor.sol` | `LOVE20TKM/extension-group/src/interface/IGroupService.sol`、`LOVE20TKM/extension-group/src/interface/IGroupRecipients.sol` | 重写 |

### group-chat

| 新接口 | 旧来源 | 状态 |
| --- | --- | --- |
| `group-chat/IGroupChat.sol` | `LOVE20TKM/group-chat/src/interfaces/IGroupChat.sol` | 保留（去地址主体） |
| `group-chat/IGroupAdmin.sol` | `LOVE20TKM/group-chat/src/interfaces/IGroupAdmin.sol` | 保留（去地址主体） |
| `group-chat/IGroupChatBanList.sol` | `LOVE20TKM/group-chat/src/interfaces/IGroupBanList.sol` | 改名迁移 |
| `group-chat/IGroupMember.sol` | `LOVE20TKM/group-chat/src/interfaces/IGroupMember.sol` | 保留 |
| `group-chat/IGroupChatDelegate.sol` | `LOVE20TKM/group/src/interfaces/IGroupDelegate.sol` | 跨仓库迁移 |
| `group-chat/IGroupChatRules.sol` | `LOVE20TKM/group-chat/src/interfaces/sources/IPostScopeSource.sol`、`sources/IPostBanSource.sol`、`plugins/IBeforePostPlugin.sol`、`plugins/IAfterPostPlugin.sol` | 四文件合并 |
| `group-chat/IGovVotedBanSource.sol` | `LOVE20TKM/group-chat/src/interfaces/sources/ban/IGovVotedBanSource.sol` | 保留（去地址主体） |
| `group-chat/IActionManager.sol` | `LOVE20TKM/group-chat/src/interfaces/managers/IBaseTokenActionScopeManager.sol`、`managers/IBaseManager.sol` | 扁平化合并 |
| `group-chat/ITokenManager.sol` | `LOVE20TKM/group-chat/src/interfaces/managers/IBaseTokenScopeManager.sol`、`managers/IBaseManager.sol` | 扁平化合并 |
| `group-chat/IAdminBanSource.sol` | `LOVE20TKM/group-chat/src/interfaces/sources/ban/IAdminBanSource.sol` | 补齐（1:1） |
| `group-chat/IGroupMemberScope.sol` | `LOVE20TKM/group-chat/src/interfaces/sources/scope/IGroupMemberScope.sol` | 补齐（1:1） |
| `group-chat/IGroupJoinScopeSource.sol` | `LOVE20TKM/group-chat/src/interfaces/sources/scope/IGroupJoinScopeSource.sol` | 补齐（依赖改名） |

三者均已纳入新接口，详见 [已确认并落地](#已确认并落地)。`IGroupJoinScopeSource` 不是 1:1：旧版依赖 `GROUP_JOIN_ADDRESS`（core `Join`，新协议已取消）改为 `GROUP_ACTION_EXECUTOR_ADDRESS`（action 层单例 Executor），`GROUP_MEMBER_ADDRESS` 原样保留。

## 整体删除的旧接口

| 旧接口 | 删除去向 | 依据 |
| --- | --- | --- |
| `LOVE20TKM/core/src/interfaces/ILOVE20Verify.sol` | 验证业务下移 `action` 层 `IGroupActionExecutor`；`stakedAmountOfVerifiers` 迁为 `ILOVE20Vote.stakedAmountOfVoters` | BSC 无独立核心验证阶段 |
| `LOVE20TKM/core/src/interfaces/ILOVE20Join.sol` | 参与业务下移 `action` 层各 Executor 的 `join`/`withdraw`/`exit`；随机抽样系列不迁移 | 核心不承载行动参与 |
| `LOVE20TKM/core/src/interfaces/ILOVE20Random.sol` | 不迁移 | 随机验证抽样机制随 Verify 一并移除 |
| `LOVE20TKM/core/src/interfaces/ILOVE20SLToken.sol` | 不迁移，份额进入 `ILOVE20Stake` 账本 | 去凭证化 |
| `LOVE20TKM/core/src/interfaces/ILOVE20STToken.sol` | 不迁移，份额进入 `ILOVE20Stake` 账本 | 去凭证化 |
| `LOVE20TKM/group/src/interfaces/IGroupDefaults.sol` | 不迁移 | 地址到默认 NFT 的便利映射不部署 |
| `LOVE20TKM/group/src/interfaces/IGroupMarket.sol` | 不迁移 | `LOVE20MemberMarket` 未部署且非核心依赖 |
| `LOVE20TKM/extension/src/interface/IExtensionFactory.sol` | 不迁移 | 取消工厂，Executor 为单例多社区合约 |
| `LOVE20TKM/extension/src/interface/IJoin.sol` | 语义并入各 Executor 的 `join`/`exit` | 无独立无金额参与接口 |
| `LOVE20TKM/extension/src/interface/IReward.sol` | 领取模型改为 `ActionTarget.mintProposalReward` 铸造分发 | 激励由协议按规则铸造 |
| `LOVE20TKM/extension-lp/src/interface/ILpFactory.sol` | 不迁移 | 同上，取消工厂 |
| `LOVE20TKM/extension-group/src/interface/IGroupActionFactory.sol`、`LOVE20TKM/extension-group/src/interface/IGroupServiceFactory.sol`、`LOVE20TKM/extension-group/src/interface/IExtensionGroupActionFactory.sol`、`LOVE20TKM/extension-group/src/interface/IExtensionGroupServiceFactory.sol` | 不迁移 | 同上，取消工厂 |
| `LOVE20TKM/group-chat/src/interfaces/sources/ban/IBanVoteWeightSource.sol` | 合并进 `IActionManager`、`ITokenManager` | 扁平化 |
| `LOVE20TKM/group/src/interfaces/ILOVE20Token.sol` | 不单独迁移：与 `core/ILOVE20Token.sol` 逐字相同（仅 import 路径不同），按 core 版对比 | 跨仓库镜像 |
| `LOVE20TKM/group-chat/src/interfaces/external/*.sol` | 直接引用 `core`、`action` 接口 | 外部依赖镜像不再复制 |

## 整块不迁移的旧接口（规模账）

上表中被判为「不迁移」的旧接口，其**全部成员随接口一并删除**，分层文档不再逐一列举。这里给出各自的规模，用于核对「旧侧 655 函数 / 100 事件 / 274 错误」的去处是否闭合。

| 旧接口 | 函数 | 事件 | 错误 |
| --- | --- | --- | --- |
| `LOVE20TKM/core/src/interfaces/ILOVE20Verify.sol` | 16 | 1 | 4 |
| `LOVE20TKM/core/src/interfaces/ILOVE20Join.sol` | 26 | 4 | 7 |
| `LOVE20TKM/core/src/interfaces/ILOVE20Random.sol` | 4 | 1 | 3 |
| `LOVE20TKM/core/src/interfaces/ILOVE20SLToken.sol` | 11 | 3 | 6 |
| `LOVE20TKM/core/src/interfaces/ILOVE20STToken.sol` | 5 | 2 | 3 |
| `LOVE20TKM/group/src/interfaces/IGroupDefaults.sol` | 5 | 2 | 4 |
| `LOVE20TKM/group/src/interfaces/IGroupMarket.sol` | 26 | 8 | 16 |
| `LOVE20TKM/extension/src/interface/IExtensionFactory.sol` | 6 | 1 | 0 |
| `LOVE20TKM/extension/src/interface/IJoin.sol` | 3 | 2 | 2 |
| `LOVE20TKM/extension/src/interface/IReward.sol` | 6 | 2 | 1 |
| `LOVE20TKM/extension-lp/src/interface/ILpFactory.sol` | 1 | 0 | 2 |
| `LOVE20TKM/extension-group/src/interface/IGroupActionFactory.sol` | 5 | 0 | 4 |
| `LOVE20TKM/extension-group/src/interface/IGroupServiceFactory.sol` | 3 | 0 | 1 |
| `LOVE20TKM/extension-group/src/interface/IExtensionGroupActionFactory.sol` | 0 | 0 | 0 |
| `LOVE20TKM/extension-group/src/interface/IExtensionGroupServiceFactory.sol` | 0 | 0 | 0 |
| `LOVE20TKM/group-chat/src/interfaces/sources/ban/IBanVoteWeightSource.sol` | 2 | 0 | 0 |
| **合计** | **119** | **26** | **53** |

其中三个规模较大、值得单独点名的删除块：

- **`IGroupMarket`（26/8/16）**：`LOVE20MemberMarket` 的挂单/报价/成交体系（`createListing`、`makeOffer`、`acceptOffer`、`buyListing`、`calculateFee`、`calculateSellerProceeds`、`highestOffer` 等）。Out of scope 已裁决（见 `.scratch/bsc-protocol-migration/map.md`），新协议无任何对应。
- **`ILOVE20Join`（26/4/7）**：核心参与业务，下移 action 层；随机抽样支撑结构（`numOfAccounts`/`indexToAccount`/`accountToIndex`/`prefixSum`、`randomAccounts*`）与按轮可回溯的 `verificationInfo*` 系列一并删除。
- **`ILOVE20Verify`（16/1/4）**：核心验证阶段取消；`stakedAmountOfVerifiers` 单点迁至 `ILOVE20Vote.stakedAmountOfVoters`，评分维度在 action 层重构为 `originScore`/`finalScore`/`totalFinalScore`（非一一对应）。

## 全新增加的接口

| 新接口 | 作用 | 旧协议对应机制 |
| --- | --- | --- |
| `core/IProposalTarget.sol` | Proposal 创建/推举/投票三回调 | 无；旧协议无 Target 回调 |
| `core/ILaunchDistributor.sol` | 子币发射后回调 `distributor` | 无；旧协议按认购比例直接领取 |
| `action/IGroupActionIndexes.sol` | 17 组可枚举全局索引独立成文件 | 旧内嵌在 `IGroupJoin` |

## 跨层结构变化

以下四点影响所有接口，各分层文档不再重复：

1. **主体从地址改为 memberId**。旧 `address account` / `address voter` / `address verifier` 等业务主体参数统一改为 `uint256 memberId` 及其派生名（`voterId`、`submitterId`、`verifierMemberId`、`providerMemberId`、`senderId`）。仅 ERC20/ERC721 标准接口、`distributor`、`target`、`executor`、事件中的 owner 快照和审计地址保留 `address`。
2. **错误与事件不再拆分子接口**。旧代码普遍使用 `I<Name>Errors` / `I<Name>Events` 子接口再继承（如 `ILOVE20Stake is ILOVE20StakeErrors, ILOVE20StakeEvents, IPhase`）；新接口把事件和错误直接内联在主接口内，不生成额外接口名。
3. **不再继承 IPhase**。旧 `ILOVE20Stake`、`ILOVE20Submit`、`ILOVE20Vote`、`ILOVE20Verify`、`ILOVE20Join`、`ILOVE20Random` 都 `is IPhase`，因此隐式暴露 `currentRound()`、`roundByBlockNumber()`。新接口改为 `init(phaseAddress, ...)` 依赖注入，各接口只按需自行声明 `currentRound()`（`ILOVE20Submit`、`ILOVE20Vote`、`IGroupChat`）或分阶段轮次（`currentVoteRound`/`currentJoinRound`/`currentVerifyRound`/`currentMintRound`）。
4. **常量 getter 改为按作用域查询或 init 参数**。旧代码把部署参数暴露为全大写 getter（`ROUND_REWARD_GOV_PER_THOUSAND`、`MAX_SUPPLY`、`LAUNCH_AMOUNT` 等）。新接口通常改为小驼峰 getter；TokenFactory 的 `LAUNCH_AMOUNT()`、`MAX_SUPPLY()` 保留旧大写命名，行动 Executor 的 Proposal KV 配置则保留 getter 名并补 `tokenAddress + actionId` 作用域；其余参数只作为 `init` 入参而不再提供 getter。后者是可查询能力的净减少，逐项列在各分层文档。

## 已确认并落地

以下五条经确认属于**新协议接口需要补齐的缺口**，不是文档缺陷。**五条均已落地到 `interfaces/` 并经 solc 0.8.17 编译通过**，各条括号中为实现结果。

1. **action 层错误声明需补齐**。旧三接口（`IGroupJoin`/`IGroupManager`/`IGroupVerify`）共 **44 条错误声明、40 个不同错误名**，其中 6 个已有新语义对应，6 个随删除机制一并删除，其余 28 个保留并补入 `IGroupActionExecutor`；另补充阶段未开始错误，接口错误数为 44，逐名核对见 [action.md §3「错误」](action.md)。
2. **链群配置变更事件**。`IGroupActionExecutor` 已声明 `ActivateGroup`、`DeactivateGroup`、`UpdateGroupInfo`，仅去掉 `owner`（主体改为 memberId，owner 快照不再进事件）、保留 `stakeAmount`；事件数为 11，供前端索引与通知。
3. **group-chat scope/ban 适配接口**。已补回 `IAdminBanSource.sol`、`IGroupMemberScope.sol` 和 `IGroupJoinScopeSource.sol`。三者声明地址 getter，行为契约分别来自 `IPostBanSource.isBanned` 或 `IPostScopeSource.canPost`；`IGroupJoinScopeSource` 使用 `GROUP_ACTION_EXECUTOR_ADDRESS()` 指向 action 层单例 Executor，并保留 `GROUP_MEMBER_ADDRESS()`。
4. **Mint 依赖地址 getter需补回，激励计算查询保持精简**。旧 `ILOVE20Mint` 提供 `voteAddress`/`verifyAddress`/`stakeAddress`，新版退化为仅 `init` 入参。确认结论：**补回 4 个常用依赖 getter**（前端与其他合约发现依赖的常用入口）；`memberNFTAddress` 仅通过 `init` 注入，不单独暴露 getter。`govVerifyReward`/`govBoostReward`/`calculateRoundGovReward`/`calculateRoundActionReward` 等激励计算查询**确认不补**，由调用方自行计算。注意 `verifyAddress` 对应的验证阶段已取消，补回时按新版实际依赖（`voteAddress`/`stakeAddress`/`submitAddress`/`launchAddress`）取用。**已落地**：`ILOVE20Mint` 补回上述 4 个 getter，函数数 19 → 23；4 个激励计算查询确认不补。
5. **链群维度汇总查询需补回**。旧 `IGroupJoin.totalJoinedAmountByGroupId`、`joinedAmount`、`totalJoinedAmountByGroupOwner` 在新接口没有对应，新版只有 `joinedAmountByMemberId` 与 `memberIdsByGroupId`，只能遍历成员累加。确认结论：**补回汇总查询**，遍历累加在成员规模大时不可用。**已落地**：补回 `totalJoinedAmountByGroupId(tokenAddress, actionId, round, groupId)` 与 `joinedAmount(tokenAddress, actionId, round)`（相对旧版新增 `actionId` 参数，单例多行动模型）；`totalJoinedAmountByGroupOwner` 按裁决不补（群归属改为链群维度，不再按 owner 地址聚合）。

## 核对方法与覆盖度

本目录的结论不是抽样得出，按以下六层逐条核对，每层均全量：

| 层 | 核对内容 | 结果 |
| --- | --- | --- |
| 1 | 规模数字：文件/接口声明/函数/事件/错误计数，README 表格与脚本输出逐位比对 | 新 28 / 31 / 429 / 76 / 206，旧 52 / 115 / 655 / 100 / 274，一致 |
| 2 | 反向：文档反引号内每个标识符，是否在新旧源码全集中 | 0 个虚构标识符（498 个候选 token 中未命中源码的 64 个均为类型名、结构体名、文件名与散文词） |
| 3 | 正向：旧侧 1029 条声明（655 函数 / 100 事件 / 274 错误）是否都有归处 | 880 条按名直接提及 + 67 条按简写约定展开 + 82 条归入整块规模账（该表合计 198 条，其中 116 条同时被按名提及），**未归类 0** |
| 4 | 签名级：文档中每条「函数名 + 参数序列」写法，与源码真实参数名序列逐条比对 | 见下 |
| 5 | 状态级：标注「保留」的条目，新旧类型序列是否真一致；事件与错误的字段级差异是否被文档覆盖 | 49 条「保留」全部真一致；13 处事件字段差异 + 1 处错误字段差异全部已记录 |
| 6 | 可编译性：改动后的 `interfaces/` 用 solc 0.8.17 全量编译 | 31 个接口、28 个文件全部编译通过，0 错误 0 警告；并生成 ABI 逐接口比对，确认改动只落在本文件列出的 9 个接口，无意外变更 |

第 6 层的 ABI 差分（与改动前 `git HEAD` 对比）只出现 9 个接口的差异，与五条补齐项、阶段错误补齐、一个语义修正及单例作用域修正对应：

| 接口 | fn | ev | err | 对应裁决 |
| --- | --- | --- | --- | --- |
| `IGroupActionExecutor` | 96 → 97 | 8 → 11 | 15 → 44 | 1、2、5、阶段未开始错误、单例行动作用域 |
| `ILpExecutor` | 19 → 19* | 5 | 10 | 单例行动作用域、阶段未开始错误 |
| `IGroupServiceExecutor` | 18 → 18* | 3 | 9 | 单例服务 Proposal 作用域、阶段未开始错误 |
| `ILOVE20Stake` | 18 | 4 | 11 → 10 | 删除误导性 `InvalidToAddress` |
| `ILOVE20Submit` | 14 | 2 | 7 | 保留旧 Submit 的三个专用 selector |
| `ILOVE20Mint` | 19 → 23 | 4 | 8 | 5 |
| `IAdminBanSource` | 0 → 2 | 0 | 0 → 1 | 3 |
| `IGroupMemberScope` | 0 → 2 | 0 | 0 → 1 | 3 |
| `IGroupJoinScopeSource` | 0 → 3 | 0 | 0 → 1 | 3 |

其余 21 个接口 ABI 逐字节未变。带 `*` 的行函数数量未变但参数签名已改变；左列为**完整 ABI 口径**（含继承成员，例如 `IGroupActionExecutor` = 自身 44 + `IGroupActionIndexes` 51 + `IProposalTarget` 3 = 98），与第 1 层的「自有声明」口径不同，两者都对。

两处有意的收敛（非遗漏）：`IGroupActionIndexes` 的 51 个 g\* 索引按 17 个组名列举；整块不迁移的旧接口只给规模与代表成员，不逐一列举——两者都在本文件中写明了展开规则或规模账。
