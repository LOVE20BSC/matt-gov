# 新旧接口函数级对比

本目录是迁移分析证据，不是规格。ABI 以 [`interfaces/`](../../interfaces/) 为唯一来源；组件级迁移结论以 `docs/specs/CHANGES-*.md` 为准。本对比只回答一个问题：**新接口的每个函数、事件、错误来自旧代码哪里，或者是新增；旧代码的每个 ABI 去了哪里，或者被删除。**

旧代码提交版本见 [`docs/repositories.md`](../../docs/repositories.md#旧代码基线)。

## 分层文档

| 文档 | 范围 |
| --- | --- |
| [core.md](core.md) | `interfaces/core/` 11 个接口 vs `LOVE20TKM/core`、`LOVE20TKM/group` |
| [action.md](action.md) | `interfaces/action/` 5 个接口 vs `LOVE20TKM/extension`、`extension-group`、`extension-lp` |
| [group-chat.md](group-chat.md) | `interfaces/group-chat/` 9 个接口 vs `LOVE20TKM/group-chat`、`LOVE20TKM/group` |

## 规模对比

| 侧 | 接口文件 | 函数 | 事件 | 错误 |
| --- | --- | --- | --- | --- |
| 新（`matt-gov/interfaces`） | 25 | 420 | 73 | 170 |
| 旧（6 个 LOVE20TKM 仓库） | 52 | 655 | 100 | 274 |

**统计口径**（三份分层文档的计数均可按此复现）：

- 旧侧文件 = 6 个 LOVE20TKM 仓库 `src` 下 `interface`/`interfaces` 目录内的全部 `.sol`；排除 `group-chat/src/interfaces/external/`（14 个跨仓库镜像，非旧协议自有 ABI）；**包含** `group/src/interfaces/ILOVE20Token.sol`（`core` 同名接口的逐字镜像，仅 import 路径不同）。
- 函数数按**声明条数**计，不做跨文件去重（同一函数名在不同接口各计一次）。
- 接口声明数与文件数不同：新侧 25 文件内含 **28 个** `interface` 声明——`IGroupChatRules.sol` 一个文件含 4 个（`IPostScopeSource`、`IPostBanSource`、`IBeforePostPlugin`、`IAfterPostPlugin`），其余文件各含 1 个；旧侧 52 文件内含 **115 个** `interface` 声明（去重后 112 个，`ILOVE20Token` 及其两个子接口在 `core` 与 `group` 各声明一次），其中 63 个是 `I<Name>Errors`/`I<Name>Events` 子接口——这 63 个子接口正是「跨层结构变化」第 2 条所说的内联化对象。
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
| `action/IActionTarget.sol` | `LOVE20TKM/extension/src/interface/IExtensionCenter.sol`、`IExtension.sol` | 重写 |
| `action/ILpExecutor.sol` | `LOVE20TKM/extension-lp/src/interface/ILp.sol`、`LOVE20TKM/extension/src/interface/ITokenJoin.sol`、`IReward.sol` | 重写 |
| `action/IGroupActionExecutor.sol` | `LOVE20TKM/extension-group/src/interface/IGroupAction.sol`、`IGroupManager.sol`、`IGroupJoin.sol`、`IGroupVerify.sol` | 重写 |
| `action/IGroupActionIndexes.sol` | `LOVE20TKM/extension-group/src/interface/IGroupJoin.sol#g*` | 改名迁移 |
| `action/IGroupServiceExecutor.sol` | `LOVE20TKM/extension-group/src/interface/IGroupService.sol`、`IGroupRecipients.sol` | 重写 |

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
| `LOVE20TKM/extension-group/src/interface/IGroupActionFactory.sol`、`IGroupServiceFactory.sol`、`IExtensionGroupActionFactory.sol`、`IExtensionGroupServiceFactory.sol` | 不迁移 | 同上，取消工厂 |
| `LOVE20TKM/group-chat/src/interfaces/sources/ban/IBanVoteWeightSource.sol` | 合并进 `IActionManager`、`ITokenManager` | 扁平化 |
| `LOVE20TKM/group-chat/src/interfaces/sources/ban/IAdminBanSource.sol` | 无新接口文件 | 见待确认 1 |
| `LOVE20TKM/group-chat/src/interfaces/sources/scope/IGroupJoinScopeSource.sol` | 无新接口文件 | 见待确认 1 |
| `LOVE20TKM/group-chat/src/interfaces/sources/scope/IGroupMemberScope.sol` | 无新接口文件 | 见待确认 1 |
| `LOVE20TKM/group/src/interfaces/ILOVE20Token.sol` | 不单独迁移：与 `core/ILOVE20Token.sol` 逐字相同（仅 import 路径不同），按 core 版对比 | 跨仓库镜像 |
| `LOVE20TKM/group-chat/src/interfaces/external/*.sol` | 直接引用 `core`、`action` 接口 | 外部依赖镜像不再复制 |

## 整块不迁移的旧接口（规模账）

上表中被判为「不迁移」的旧接口，其**全部成员随接口一并删除**，分层文档不再逐一列举。这里给出各自的规模，用于核对「旧侧 655 函数 / 100 事件 / 274 错误」的去处是否闭合。

| 旧接口 | 函数 | 事件 | 错误 |
| --- | --- | --- | --- |
| `core/src/interfaces/ILOVE20Verify.sol` | 16 | 1 | 4 |
| `core/src/interfaces/ILOVE20Join.sol` | 26 | 4 | 7 |
| `core/src/interfaces/ILOVE20Random.sol` | 4 | 1 | 3 |
| `core/src/interfaces/ILOVE20SLToken.sol` | 11 | 3 | 6 |
| `core/src/interfaces/ILOVE20STToken.sol` | 5 | 2 | 3 |
| `group/src/interfaces/IGroupDefaults.sol` | 5 | 2 | 4 |
| `group/src/interfaces/IGroupMarket.sol` | 26 | 8 | 16 |
| `extension/src/interface/IExtensionFactory.sol` | 6 | 1 | 0 |
| `extension/src/interface/IJoin.sol` | 3 | 2 | 2 |
| `extension/src/interface/IReward.sol` | 6 | 2 | 1 |
| `extension-lp/src/interface/ILpFactory.sol` | 1 | 0 | 2 |
| `extension-group/src/interface/IGroupActionFactory.sol` | 5 | 0 | 4 |
| `extension-group/src/interface/IGroupServiceFactory.sol` | 3 | 0 | 1 |
| `extension-group/src/interface/IExtensionGroupActionFactory.sol` | 0 | 0 | 0 |
| `extension-group/src/interface/IExtensionGroupServiceFactory.sol` | 0 | 0 | 0 |
| `group-chat/src/interfaces/sources/ban/IBanVoteWeightSource.sol` | 2 | 0 | 0 |
| `group-chat/src/interfaces/sources/ban/IAdminBanSource.sol` | 1 | 0 | 1 |
| `group-chat/src/interfaces/sources/scope/IGroupJoinScopeSource.sol` | 2 | 0 | 1 |
| `group-chat/src/interfaces/sources/scope/IGroupMemberScope.sol` | 1 | 0 | 1 |
| **合计** | **123** | **26** | **56** |

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
4. **常量 getter 改为 init 参数**。旧代码把部署参数暴露为全大写 getter（`ROUND_REWARD_GOV_PER_THOUSAND`、`MAX_SUPPLY`、`LAUNCH_AMOUNT` 等）。新接口部分改为小驼峰 getter（`maxSupply`、`initialSupply`、`launchRatio`、`proposalRewardMinVotePerThousand`），部分只作为 `init` 入参而不再提供 getter。后者是可查询能力的净减少，逐项列在各分层文档。

## 已裁决待补齐

以下两条经确认属于**新协议接口需要补齐的缺口**，不是文档缺陷，也不再属于待确认。

1. **action 层错误声明需补齐**。新 `IGroupActionExecutor` 只声明 15 个错误，旧三接口（`IGroupJoin`/`IGroupManager`/`IGroupVerify`）共 44 个错误中仅 5 个有对应。确认结论：这些校验在实现中仍然存在，**需要补回对应的自定义错误声明**，而不是用 `require` 或通用错误替代。待补齐清单见 [action.md §3「错误」](action.md)。
2. **链群配置变更事件需补回**。旧 `IGroupManager` 的 `ActivateGroup`、`DeactivateGroup`、`UpdateGroupInfo` 三个事件在新 `IGroupActionExecutor` 无对应。确认结论：**需要补回**，前端依赖这些事件做索引与通知。

## 待确认

只列影响实施的缺口。

1. **group-chat 的 scope/ban source 适配接口无新定义**。旧 `IAdminBanSource`（人工黑名单作为 ban source）、`IGroupMemberScope`（成员名单作为 scope source）、`IGroupJoinScopeSource`（行动参与作为 scope source）三个适配层接口在新 `interfaces/group-chat/` 没有对应文件。新 `IGroupChat.setScopeSource`/`setBanSource` 仍接受任意实现 `IPostScopeSource`/`IPostBanSource` 的地址，`IGroupChatBanList` 和 `IGroupMember` 也仍然存在，因此业务能力未删除；缺的是这三个适配合约的 ABI 声明。需要确认：是有意省略（实现时按 `IGroupChatRules` 的两个基接口直接实现），还是漏写。
2. **Submit 推举去重与门槛错误无对应声明**。`docs/specs/CHANGES-core.md` 记录 Submit「保留推举门槛、去重逻辑」，但旧 `ILOVE20Submit` 的 `CannotSubmitAction`、`AlreadySubmitted`、`OnlyOneSubmitPerRound` 在新 `ILOVE20Submit` 的 4 个错误中没有对应项。需要确认这三种失败在新版用什么错误表达。
3. **Mint 依赖地址与部分激励查询 getter 缺失**。旧 `ILOVE20Mint` 提供 `voteAddress`/`verifyAddress`/`stakeAddress` 和 `govVerifyReward`/`govBoostReward`/`calculateRoundGovReward`/`calculateRoundActionReward` 等查询，新接口只有 `init` 入参而无 getter。需要确认前端和 `interface-test` 是否依赖这些查询。
4. **GroupActionExecutor 的链群维度汇总查询缺失**。旧 `IGroupJoin.totalJoinedAmountByGroupId`、`joinedAmount`、`totalJoinedAmountByGroupOwner` 在新接口没有对应函数，新接口只提供 `joinedAmountByMemberId` 和 `memberIdsByGroupId`。需要确认链群总额是否由前端遍历成员自行累加。

## 核对方法与覆盖度

本目录的结论不是抽样得出，按以下五层逐条核对，每层均全量：

| 层 | 核对内容 | 结果 |
| --- | --- | --- |
| 1 | 规模数字：文件/接口/函数/事件/错误计数，README 表格与脚本输出逐位比对 | 一致 |
| 2 | 反向：文档反引号内每个标识符，是否在新旧源码全集中 | 0 个虚构标识符 |
| 3 | 正向：旧侧 1029 条声明（655 函数 / 100 事件 / 274 错误）是否都有归处 | 880 条直接提及 + 88 条归入整块规模账 + 61 条可按简写约定展开，**未归类 0** |
| 4 | 签名级：文档中每条「函数名 + 参数序列」写法，与源码真实参数名序列逐条比对 | 287 条检查，0 不符 |
| 5 | 状态级：标注「保留」的条目，新旧类型序列是否真一致；事件与错误的字段级差异是否被文档覆盖 | 49 条「保留」全部真一致；13 处事件字段差异 + 1 处错误字段差异全部已记录 |

两处有意的收敛（非遗漏）：`IGroupActionIndexes` 的 51 个 g\* 索引按 17 个组名列举；整块不迁移的旧接口只给规模与代表成员，不逐一列举——两者都在本文件中写明了展开规则或规模账。
