# GroupActionExecutor 接口调用权限审查

> 对象 `action/src/GroupActionExecutor.sol`（750 行）+ 继承的 `action/src/ExecutorBase.sol`（140 行）
> 接口 `action/src/interfaces/IGroupActionExecutor.sol`（81 行，`is IGroupActionVerify, IGroupActionIndexes, IActionExecutor`）
> 业务实现落在四个 `public` 库：`GroupActionJoin`、`GroupActionVerify`、`GroupActionManager`（另见本目录 05/06/07 三份报告）
> 基线 `action@8478619`（`src/` 自 `e849e36` 无实质变化，行号未位移）；审查日期 2026-11-03
> 判据 dev-standards §5.5、§3.3（24KB 拆分）、§5.2.2；`specs/action/05-group-action-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 78（写 17 / 读 61） |
| 本合约定义的鉴权 modifier | 0（全部在库里；仅 `onlyActionTarget` 来自基类） |
| 业务写入口 | 12（其中 10 条动钱，全部 `nonReentrant`） |
| 无许可写入口 | 0 |
| 发现 | 5 条 Info；另有 2 条正面结论 |
| 接口对账 | 78 vs 78，**0 差异** |

一句话：**17 个写入口里 12 条业务入口的鉴权不在这个合约上，而在被 `delegatecall` 的库里——`nonReentrant` 留在 Executor、`onlyMemberOwner`/`onlyGroupOwner` 留在库，两者拼起来才是一次完整的入口校验。功能上没有任何缺口（12 条入口逐条有主体、10 条动钱入口全部有锁），但这是全仓唯一一处「ABI 上读不出鉴权」的地方，也是 §5.5 字面未覆盖的位置。**

## 二、权限模型

本合约的权限主体有五个，分散在三个库里：

| 权限主体 | 判定 | 判定位置 | 覆盖入口 |
| --- | --- | --- | --- |
| ActionTarget | `msg.sender == ACTION_TARGET_ADDRESS` | `ExecutorBase:36` | `onProposalCreated`、`onProposalSubmitted`、`onProposalVoted` |
| `memberId` 当前持有人 | `ownerOf(memberId) == msg.sender` | `GroupActionJoin:29` | `join`、`withdraw`、`exit` |
| `providerId` 当前持有人 | `ownerOf(providerId) == msg.sender` | `GroupActionJoin:29` | `withdrawProviderQuota`、`addProviderQuota`、`removeProviderQuota` |
| `verifierId` 当前持有人 | `ownerOf(verifierId) == msg.sender` | `GroupActionVerify:50` | `submitOriginScores`、`submitVerifierApplication`、`cancelVerifierApplication` |
| `groupId` 当前持有人 | `ownerOrZero(groupId) != 0 && == msg.sender` | `GroupActionManager:27` | `activateGroup`、`deactivateGroup`、`setGroupConfig` |
| `memberId` 当前持有人 | `ownerOf(memberId) == msg.sender` | `ExecutorBase:29` | `mintMemberReward`、`mintMemberRewards` |

**「持有 memberId」与「持有 groupId」是同一把钥匙的两个用途。** `groupId` 本身就是某个成员 NFT 的 `memberId`（`05-group-action-executor.md`：`groupId` 是群主体的 `memberId`）。因此一个地址同时持有多把钥匙时，它可以同时扮演成员、Provider、验证者、群 owner 四个角色——这些角色之间没有互斥校验，也没有「不能给自己投票」之类的自反限制。这是设计选择（主体模型统一为 MemberNFT），不是缺陷。

## 三、入口清单

### 写入口（17）

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `onProposalCreated(address,uint256,bytes[])` | ActionTarget | `onlyActionTarget` `L104` | 是 | `GroupActionCreated`（库内发） |
| `onProposalSubmitted(...)` | ActionTarget | `ExecutorBase:43`（空实现） | 是 | 无 |
| `onProposalVoted(...)` | ActionTarget | `onlyActionTarget` `L112` | 是 | `ApplicationVoteRecorded`（库内发） |
| `join(address,uint256,uint256,uint256,uint256,uint256,string[])` | `memberId` 持有人 | `nonReentrant` + 库 `onlyMemberOwner` `L128` | 是 | `GroupActionJoined` |
| `withdraw(address,uint256,uint256,uint256)` | `memberId` 持有人 | 同上 `L143` | 是 | `GroupActionWithdrawn` |
| `withdrawProviderQuota(address,uint256,uint256,uint256,uint256,uint256)` | `providerId` 持有人 | 同上 `L148` | 是 | `ProviderQuotaRemoved` |
| `exit(address,uint256,uint256)` | `memberId` 持有人 | 同上 `L162` | 是 | `GroupActionWithdrawn` + `ProviderQuotaRestored` + `GroupActionExited` |
| `addProviderQuota(address,uint256,uint256,uint256,uint256[],uint256[])` | `providerId` 持有人 | 同上 `L208` | 是 | 逐条 `ProviderQuotaAdded` |
| `removeProviderQuota(address,uint256,uint256,uint256,uint256[])` | `providerId` 持有人 | 同上 `L222` | 是 | `GroupActionWithdrawn` + `ProviderQuotaRemoved` |
| `submitOriginScores(address,uint256,uint256,uint256,uint256,uint256[])` | `verifierId` 持有人 | **库 `onlyMemberOwner`** `L320` | 是 | `VerifierLocked`（首次）、`OriginScoresSubmitted` |
| `submitVerifierApplication(address,uint256,uint256,string)` | `verifierId` 持有人 | `nonReentrant` + 库 `onlyMemberOwner` `L380` | 是 | `VerifierApplicationSubmitted`（+`VerifierStakeDeposited`） |
| `cancelVerifierApplication(address,uint256,uint256)` | `verifierId` 持有人 | 同上 `L392` | 是 | `VerifierApplicationCancelled`（+`VerifierStakeRefunded`） |
| `activateGroup(address,uint256,uint256,tuple)` | `groupId` 持有人 | `nonReentrant` + 库 `onlyGroupOwner` `L505` | 是 | `GroupActivated` |
| `deactivateGroup(address,uint256,uint256)` | `groupId` 持有人 | 同上 `L515` | 是 | `GroupDeactivated` |
| `setGroupConfig(address,uint256,uint256,tuple)` | `groupId` 持有人 | **库 `onlyGroupOwner`** `L520` | 是 | `GroupConfigChanged` |
| `mintMemberReward(address,uint256,uint256,uint256)` | `memberId` 持有人 | `ExecutorBase:51` | 是 | `MemberRewardMinted` |
| `mintMemberRewards(address,uint256[],uint256[],uint256)` | `memberId` 持有人 | `ExecutorBase:60` | 是 | 逐条 `MemberRewardMinted` |

**12 条业务写入口的鉴权分布**：10 条挂在库里（`GroupActionJoin` 6、`GroupActionVerify` 3、`GroupActionManager` 3），2 条既无 Executor 级 modifier 也无 `nonReentrant`（`submitOriginScores`、`setGroupConfig`），鉴权同样在库里。

### 只读入口（61）

按用途分组（全部无权限、无事件要求）：

| 组 | 数量 | 成员 |
| --- | --- | --- |
| 依赖与配置 | 6 | `ACTION_TARGET_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`VOTE_ADDRESS`、`SPLITS` |
| Round | 4 | `currentVoteRound`、`currentJoinRound`、`currentVerifyRound`、`currentMintRound` |
| 行动配置 | 6 | `joinTokenAddress`、`activationStakeAmount`、`maxJoinAmountRatio`、`activationMinGovRatio`、`verifierStakeAmount`、`maxJoinAmount` |
| 群状态 | 4 | `groupState`、`isGroupActive`、`descriptionByRound`、`activeGroupIds` |
| 参与量 | 8 | `joinInfo`、`joinedAmountByActionId`、`joinedAmountByMemberId`、`joinedAmountByGroupId`、`groupIdsByRound`、`memberIdsByGroupId`、`providerQuotas`、`providerAmountsByMemberId` |
| 归属索引 | 6 | `isGroupMember`、`joinedGroupIds`、`joinedGroupIdsByMemberId`、`joinedTokenAddressesByGroupIdByMemberId`、`joinedMemberIds`、`joinedMemberIdsByGroupId` |
| 群/行动索引 | 4 | `tokenAddressesByGroupId`、`actionIdsByGroupId`、`actionIdsWithActiveGroups`、`hasActiveGroups` |
| 质押 | 3 | `staked`、`totalStaked`、`stakedByMemberId` |
| 验证 | 10 | `originScore`、`finalScore`、`totalFinalScore`、`verifiedMemberCount`、`isRoundVerified`、`lockedVerifierId`、`verificationSchema`、`verificationValue`、`verificationInfos`、`verificationInfosByRound` |
| 验证者申请 | 7 | `verifierStake`、`verifierApplication`、`verifierApplications`、`voteAmountsByVerifierIds`、`topVerifiers`、`applicationVoters`、`applicationVotersByVerifierId` |
| 激励 | 3 | `generatedActionReward`、`generatedActionRewardByGroupId`、`memberReward` |

读面边界：`joinedAmountByActionId` / `joinedAmountByMemberId` 对 `round > _joinRound()` 返回 0（`L618`、`L630`）；`memberReward` 对未创建/超窗口/未完成验证的轮次返回 `(0,0,false)`（`L653-666`）；`currentVerifyRound` 在 phase < 3 时回滚 `RoundNotStarted(1,0)`。前两者不回滚，后者回滚——同一合约内两种口径并存，链下需按入口区分。

## 四、逐入口判定

### 动钱入口：10 条全部 `nonReentrant`

| 入口 | 资金方向 | 锁 |
| --- | --- | --- |
| `join` | `safeTransferFrom(msg.sender → this)`（仅 `providerId == 0`） | 有 |
| `withdraw` | `safeTransfer(this → msg.sender)` | 有 |
| `withdrawProviderQuota` | `safeTransfer(this → msg.sender)` | 有 |
| `exit` | `safeTransfer(this → msg.sender)` | 有 |
| `addProviderQuota` | `safeTransferFrom(msg.sender → this)` | 有 |
| `removeProviderQuota` | `safeTransfer(this → msg.sender)` | 有 |
| `submitVerifierApplication` | `safeTransferFrom(msg.sender → this)`（仅首次申请） | 有 |
| `cancelVerifierApplication` | `safeTransfer(this → ownerOf(verifierId))` | 有 |
| `activateGroup` | `safeTransferFrom(msg.sender → this)`（质押非零时） | 有 |
| `deactivateGroup` | `safeTransfer(this → msg.sender)` | 有 |

加上继承的两个结算入口（`mintMemberReward`/`mintMemberRewards`），**12 条动钱入口全部有锁**。这是全仓最完整的一组重入防护。

### `join` — 一个入口，两个资金来源

`join` 的 `providerId` 决定资产来源，也决定鉴权主体的**附加**关系：

| `providerId` | 资金来源 | 额外校验 |
| --- | --- | --- |
| `0` | 从 `msg.sender` 拉取代币 | 无（鉴权已保证 `msg.sender` 是 `memberId` 持有人） |
| 非零 | 扣减 Provider 的可用额度，不转账 | `InsufficientProviderQuota`（额度不足）、`QuotaNotGranted`（未授予） |

关键点：**`providerId != 0` 时不校验 `msg.sender` 是否与 Provider 有关系**——成员可以消耗任何 Provider 授予给他的额度。这是设计（Provider 授予即让渡使用权），但意味着「谁的钱被花」由 Provider 单方面决定，成员只需选择用不用。

`join` 还会在首次加入时调 `ActionTarget.registerJoinState`（`GroupActionJoin:86-88`），后者判 `currentRound > createdRound` → `JoinNotOpen`。**加入窗口的下界因此由 ActionTarget 承担，本合约不重复判断**——符合规格「下界由 ActionTarget 的 `registerJoinState` 兜住」。

### `withdrawProviderQuota` — 主体是 Provider，受益方也是 Provider

- 鉴权 `onlyMemberOwner(providerId)`：Provider 的当前持有人。
- 但函数签名里还有 `memberId` 与 `groupId`：`groupId` 只做存在性检查（`groupOwnerOrRevert`），不要求调用者拥有该群；`memberId` 是被撤回额度的对象。
- 资金流向 `msg.sender`（Provider），只减少 Provider 自己的授权额度，成员参与量不变。因此「Provider 可以操作任何群、任何成员的额度记录」是安全的——它只能动自己授予的那份。见 **GAJ-01**。

### `removeProviderQuota` — 唯一能强制减少成员参与量的入口

它把「可用额度 + 已投入」一并退回 Provider，已投入部分同额减少成员参与量，成员总量归零时自动走 `_finalizeExit`（清群归属 + `clearJoinState` + `GroupActionExited`）。这意味着**Provider 单方面可以强制成员退出行动**——成员的仓位不由成员自己独占。这是 Provider 模式的固有后果，规格已写明（`03-participation.md`：「Provider 自己的 `removeProviderQuota` 收回整笔授权」），本报告只登记其权限后果：成员在 Provider 额度上的「参与量」不是成员可以单方面保住的资产。

### 验证者三件

| 入口 | 前置校验（库内） | 权限后果 |
| --- | --- | --- |
| `submitVerifierApplication` | `validGovVotes > 0` → `ZeroVerifyVotes`；描述 ≤ 1024 → `DescriptionTooLong`；`createdRound != 0` → `ActionNotCreated` | 首次申请押金从 `msg.sender` 划入 |
| `cancelVerifierApplication` | `currentApplicationId != 0` → `NoActiveApplication` | 押金全额退给 `ownerOf(verifierId)` |
| `submitOriginScores` | `lockedVerifierId` 非零则必须等于 `verifierId`；否则 `_checkOpenVerifier`（排名 + 分割窗口） | 首次有效批次永久锁定验证者 |

三条都只认 `verifierId` 的当前持有人，**NFT 转移后新持有人无缝续任**——这正是规格要求的「首个有效验证批次永久锁定验证者 MemberNFT；NFT 转移后新持有人续验，不能由未经授权的验证者接管」。押金也随之转移（见 GAE-04）。

`submitOriginScores` 是唯一既无 `nonReentrant` 也无 Executor 级 modifier 的写入口（见 GAE-03）。

### 群三件

| 入口 | 主体 | 关键约束 |
| --- | --- | --- |
| `activateGroup` | `groupId` 持有人 | `createdRound != 0`（`ActionNotCreated`）→ 未激活（`GroupAlreadyActivated`）→ 配置合法 → 治理票占比达下限 → 拉取质押 |
| `deactivateGroup` | `groupId` 持有人 | 已激活 → 非同一加入轮（`DeactivationLockedInActivatedRound`）→ 退还质押 |
| `setGroupConfig` | `groupId` 持有人 | 已激活 → 配置合法 → 写当前加入轮描述快照 |

`activateGroup` 的 `ActionNotCreated` 前置是权限设计的一部分：创建回调之前 `activationStakeAmount` 为零、`activationMinGovRatio` 未设，放行会让群零押金入场并绕开下限。规格已写明这条理由。

`deactivateGroup` 的「同一轮不可停用」使「激活即质押、当轮不可退」成立——这是对**质押退出**的时间锁，虽然它表现为轮次校验而非鉴权。同一轮的质押在当轮无法撤回，下一轮可以。

### 三个回调

| 回调 | 校验 | 状态写入 |
| --- | --- | --- |
| `onProposalCreated` | `onlyActionTarget`，其余全在 `GroupActionManager`（项数 6～7、第 1～5 项 32 字节、比例上限、schema 长度） | 六项行动配置 + 创建轮 + 验证模板 |
| `onProposalVoted` | `onlyActionTarget`，其余在 `GroupActionVerify`（项数 ≤ 2、第 1 项 32 字节、必须有当前申请） | 验证者票数 + 名册 + 排名 |
| `onProposalSubmitted` | 仅 `onlyActionTarget` | 无 |

## 五、发现

### GAE-01（Info）12 条业务写入口的鉴权在库里，`§5.5` 的字面要求未覆盖「库」这一位置

- 证据：本合约的 `join`（`L128`）、`withdraw`（`L143`）等 10 条只挂 `nonReentrant`，`submitOriginScores`（`L320`）、`setGroupConfig`（`L520`）连 `nonReentrant` 都没有；12 条的 `onlyMemberOwner`/`onlyGroupOwner` 全部在 `GroupActionJoin:29`、`GroupActionVerify:50`、`GroupActionManager:27`。
- §5.5 原文：「modifier 定义在**合约自身**，或它继承的**唯一抽象基类**里」。库既不是合约自身，也不是基类。
- 规格已登记这一偏离：`05-group-action-executor.md` 写「`requireMemberOwner` 已按 §5.5 改为各库本地的 `onlyMemberOwner` modifier」。所以这是**规格主动选择的方案**，不是实现走偏。
- 为什么 `check_caller_auth.py` 不报：该脚本只校验两件事——`msg.sender` 判定是否写在 `only*` modifier 里、每个 `only*` 是否判调用者/有 revert/以 `_;` 收尾。它不校验 modifier 定义在哪个文件或哪个合约，因此无法发现这处偏离（`violations: 0` 不代表 §5.5 的这条被满足）。
- 后果（不是缺陷，是接口契约的可读性问题）：ABI 读者看 `join` 只看到 `nonReentrant`，看不到「必须是 `memberId` 的持有人」。集成方若按 ABI 猜权限，会把 `join` 当成无许可入口。规格是唯一说明，而接口按 §4.1 不写 NatSpec。
- **处置（A-3，已裁决：规范 + 门禁，不改代码）**：§5.5 增「实现体进库时 modifier 可定义在库，但模块规格必须列『入口 → 鉴权主体』映射表」；`check_caller_auth.py` 显式覆盖库文件并新增「库内 `only*` 必须被本文件入口使用」规则（改动前后 `violations` 均为 0）；`05-group-action-executor.md` 的「入口与鉴权主体」节即规格映射表，本报告第三节是审计副本。

### GAE-02（Info）`activationStakeAmountByActionId` 的「只写一次」由 ActionTarget 保证，本合约无本地守卫

- 证据：`GroupActionManager:86-88` 有 `Load-bearing:` 注释——「written only here. Refunds read this value instead of a per-group ledger, so a later write while groups are active would over-refund out of the other groups' stake」。而 `GroupActionManager.onProposalCreated` 本身无 `AlreadyCreated` 守卫，无条件覆写该值。
- 唯一防线：`ActionTarget.onProposalCreated` 的 `_executorByActionId != 0 → AlreadyCreated`（`ActionTarget.sol:445`），且绑定永不删除。
- 判定：当前不可达。但这条不变式的强度完全依赖另一个合约，而 `ACTION_TARGET_ADDRESS` 虽为 `immutable`，若部署时指向一个不设 `AlreadyCreated` 的 ActionTarget 实现，退款会按被放大后的 `activationStakeAmount` 从其他群的头寸里多退。
- 建议：把「单写」这条也写进 `05-group-action-executor.md` 的部署期不变量（当前只写在代码注释里），并在 `DeployAction.s.sol` 广播前断言 `ACTION_TARGET_ADDRESS` 是预期实现。

### GAE-03（Info）`submitOriginScores` 的入口形状与其余 11 条不一致

- 证据：`L320-331` 既无 `nonReentrant`，也无任何 Executor 级 modifier，函数体是一行库调用；鉴权完全在 `GroupActionVerify:70` 的 `onlyMemberOwner`。
- 当前安全：库内路径只调 `IPhase.phaseInfo`（只读）与 `IPhase.currentPhase`（只读），没有状态变更外呼，因此不需要锁。
- 风险形状：这条入口是「唯一没有第二道防线」的写入口。若将来在 `_submitOriginScores` 里加入任何状态变更外呼（例如把 `OriginScoresSubmitted` 之外的通知回调加进来），它会成为唯一漏锁的路径。`setGroupConfig` 同理（`L520`，库内只调 `currentJoinRound` → `IPhase.currentPhase`）。
- 建议：给两条都加 `nonReentrant`（成本一次 SSTORE，与同合约其他 10 条一致），或在规格里显式写明「这两条不含状态变更外呼，故不设锁」，让后续改动者知道加外呼时必须同步加锁。

### GAE-04（Info）激活质押与验证者押金的取回权随 MemberNFT 转移

- 证据：`activateGroup` 从 `msg.sender` 拉质押（`GroupActionManager:166-168`），`deactivateGroup` 退给 `msg.sender`（`L208-210`）；`submitVerifierApplication` 从 `msg.sender` 拉押金，`cancelVerifierApplication` 退给 `ownerOf(verifierId)`（`GroupActionVerify:197`）。
- 后果：`groupId` / `verifierId` 的 NFT 一旦转移，质押/押金的取回权一并转移——原持有人失去取回资格，新持有人获得。规格对验证者押金是明说的（「退还给该 verifierId 的当前持有人」），对激活质押没有明说。
- 判定：不是越权（新持有人本来就是该身份的控制者），但是「资产随身份走」的价值转移，与 core 审查的 MNT-03 同型。若群 NFT 转给一个无法调用 `deactivateGroup` 的合约，该笔质押会冻结在该群上，直到 NFT 再被转出。
- 建议：在 `05-group-action-executor.md` 的群管理段落补一句「激活质押的取回权属于 `groupId` 的当前持有人，随 NFT 转移」，与验证者押金的措辞对齐。

### GAE-05（Info）三个库的 `only*` modifier 都收了未使用的 `Layout storage self` 形参

- 证据：`GroupActionJoin:29-38`、`GroupActionVerify:50-59`、`GroupActionManager:27-36`——三处签名都是 `(Layout storage self, Protocol memory protocol, uint256 id)`，而 `self` 在 modifier 体内一次都没用到（判定只用 `protocol` 与 `id`）。
- 影响：§5.5 专门提醒「modifier 形参占栈：参数多的函数若因此 stack too deep，把函数体拆进私有 `_<name>(...)`」。这里恰好相反——在一个已经因为参数多而需要拆函数体（`GroupActionJoin.join` 已如此处理）的模块里，modifier 多占了一个 storage 指针的栈位。
- 建议：删掉 `self` 形参，三处同步。改后 `check_caller_auth.py` 仍应 `violations: 0`。

### GAE-06（正面结论）成员与 Provider 两个鉴权主体分工明确，且有互不越权的负例

- 证据：`join`/`withdraw`/`exit` 用 `onlyMemberOwner(memberId)`；`addProviderQuota`/`removeProviderQuota`/`withdrawProviderQuota` 用 `onlyMemberOwner(providerId)`。
- 负例：`test/GroupActionJoin.t.sol:500-508` 用 `MEMBER1` 调 `addProviderQuota` 与 `withdrawProviderQuota`，两处都断言 `NotMemberOwner(PROVIDER_ID)`——即「成员身份不授予 Provider 权限」。反向（Provider 身份不授予成员权限）由「成员入口只收 `memberId`」结构性保证，无法传错。
- 判定：符合规格「Provider 身份不授予成员 `exit` 权限，也不授予成员管理 Provider 额度的权限」。

### GAE-07（正面结论）12 条动钱入口全部有重入锁

- 证据：见第四节表格，10 条本合约 + 2 条继承，全部 `nonReentrant` 且是最左 modifier（§5.5 强制）。
- 判定：这是全仓防护最完整的一组。对比 core 的 `Stake`（明确不设锁，靠 CEI），本合约选择了「锁 + CEI」双重保护。

## 六、核对证据

```text
$ forge inspect GroupActionExecutor abi --json | jq '[.[]|select(.type=="function")]|length'
78    # 写 17 / 读 61
$ forge inspect GroupActionExecutor abi  vs  IGroupActionExecutor
0 差异

$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0

$ forge build --sizes | grep GroupActionExecutor
| GroupActionExecutor | 22,019 | 23,344 | 2,557 |   # 距 24,576 上限 2,557 字节
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 非 ActionTarget 调创建回调 | `test/GroupActionManager.t.sol:274` |
| 非 ActionTarget 调投票回调 | `test/GroupActionVerifyFlow.t.sol:261` |
| 非持有人 `join` | `test/GroupActionJoin.t.sol:14` `testJoinChecksOwnerBeforeAmount` |
| 非持有人 `withdraw` | `test/GroupActionJoin.t.sol:21` |
| 非持有人 `exit` | `test/GroupActionJoin.t.sol:28` |
| 非 Provider 调额度入口 | `test/GroupActionJoin.t.sol:500-508` |
| 非持有人 `submitOriginScores` | `test/GroupActionVerifyFlow.t.sol:159` |
| 非群主 `activateGroup` | `test/GroupActionManager.t.sol:89` |
| 非群主 `deactivateGroup` | `test/GroupActionManager.t.sol:202` |
| 非群主 `setGroupConfig` | `test/GroupActionManager.t.sol:246` |
| 鉴权先于行动存在性（结算） | `test/GroupActionExecutor.t.sol:335` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | ActionTarget | 三类回调（`onlyActionTarget`）；`registerJoinState`/`clearJoinState`/`mintActionReward` |
| 被调 | Core `Phase` | `currentPhase`、`phaseInfo`（三轴 Round 与分割窗口） |
| 被调 | Core `Stake` | `validGovVotes`、`totalValidGovVotes`（验证者资格、激活下限、治理上限） |
| 被调 | Core `Vote` | `totalVoteAmount`、`voteAmountByProposalId`（`maxJoinAmount` 的计算分母） |
| 被调 | Core `MemberNFT` | `ownerOf`（四个鉴权函数） |
| 被调 | `GroupActionJoin` / `GroupActionVerify` / `GroupActionManager` | 12 条业务入口的 `delegatecall` 目标 |
| 被读 | `GroupServiceExecutor` | `hasActiveGroups`、`verifierApplication`、`generatedActionReward(ByGroupId)`、`lockedVerifierId`、`totalStaked`、`stakedByMemberId`、`joinTokenAddress`、`isGroupMember` |

## 处置

`GAE-01`（并入 A-3）、`GAE-02`～`GAE-05`、`GAM-01`、`GAM-02`、`GAM-05`、`GAV-01`、`GAV-02`、`GAJ-03`、`SUP-01` 的落点见 `README.md` §十；规格映射表在 `05-group-action-executor.md` 的「入口与鉴权主体」节。
