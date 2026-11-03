# GroupServiceExecutor 接口调用权限审查

> 对象 `action/src/GroupServiceExecutor.sol`（800 行）+ 继承的 `action/src/ExecutorBase.sol`（140 行）
> 接口 `action/src/interfaces/IGroupServiceExecutor.sol`（162 行，`is IGroupRecipients, IActionExecutor`）
> 二次分配配置面落在 `GroupRecipients` 库（另见本目录 09 号报告）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§5.2.2；`specs/action/06-service-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 35（写 8 / 读 27） |
| 鉴权 modifier | 3（`onlyMemberOwner`（基类）、`onlyGroupOwner`（本合约）、`onlyActionTarget`（基类）） |
| 无许可写入口 | 0 |
| 发现 | 6 条 Info；另有 2 条正面结论 |
| 接口对账 | 35 vs 35，**0 差异** |

一句话：**服务 Proposal 是三个 Executor 里唯一「同一个成员可以在两个角色上各拿一份」的——群 owner 份额与公共验证者份额分别计算、分别检查分子，互不影响。8 个写入口的权限面没有缺口：加入/退出/结算只认 `memberId` 持有人，二次分配配置只认 `groupId` 持有人，三个回调只认 ActionTarget。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| `memberId` 当前持有人 | `ownerOf(memberId) == msg.sender`（`ExecutorBase:29`） | `join`、`exit`、`mintMemberReward`、`mintMemberRewards` |
| `groupId` 当前持有人 | `MemberOwner.ownerOrZero(...) != 0 && == msg.sender`（`L56-65`） | `setRecipients` |
| ActionTarget | `msg.sender == ACTION_TARGET_ADDRESS`（`ExecutorBase:36`） | `onProposalCreated`、`onProposalSubmitted`、`onProposalVoted` |
| 无 | — | 27 个只读入口 |

本合约的 `onlyGroupOwner` 是**自己定义**的，与 `GroupActionExecutor` 把同名判定放在 `GroupActionManager` 库里不同（见 GSE-02）：

```solidity
modifier onlyGroupOwner(uint256 groupId) {
    address owner = MemberOwner.ownerOrZero(MEMBER_NFT_ADDRESS, groupId);
    if (owner == address(0)) revert GroupNotExist(groupId);
    if (owner != msg.sender) revert NotGroupOwner(groupId);
    _;
}
```

两处都是「先判零再比对」，两个错误分开（见 GSE-07）。

## 三、入口清单

### 写入口（8）

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `join(address,uint256,uint256)` | `memberId` 持有人 | `nonReentrant onlyMemberOwner` `L113-117` | 是 | `ServiceJoined` |
| `exit(address,uint256,uint256)` | `memberId` 持有人 | 同上 `L372-376` | 是 | `ServiceExited` |
| `setRecipients(address,uint256,uint256,uint256[],uint256[],string[])` | `groupId` 持有人 | `onlyGroupOwner` `L301-308` | 是 | `RecipientsChanged`（库内发） |
| `mintMemberReward(address,uint256,uint256,uint256)` | `memberId` 持有人 | `ExecutorBase:51` | 是 | `MemberRewardMinted` + `ServiceRewardsDistributed` |
| `mintMemberRewards(address,uint256[],uint256[],uint256)` | `memberId` 持有人 | `ExecutorBase:60` | 是 | 逐条同上 |
| `onProposalCreated(address,uint256,bytes[])` | ActionTarget | `onlyActionTarget` `L393-397` | 是 | `ServiceActionCreated` |
| `onProposalSubmitted(...)` | ActionTarget | `ExecutorBase:43`（空实现） | 是 | 无 |
| `onProposalVoted(...)` | ActionTarget | `onlyActionTarget` `L439-446` | 是 | 无（只校验项数） |

### 只读入口（27）

依赖与常量 9：`PRECISION`、`DEFAULT_MAX_RECIPIENTS`、`ACTION_TARGET_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`GROUP_ACTION_EXECUTOR_ADDRESS`、`LAUNCH_ADDRESS`、`MINT_ADDRESS`。

Round 4：`currentVoteRound`、`currentJoinRound`、`currentVerifyRound`、`currentMintRound`。

服务配置 3：`actionTokenAddress`、`govRatioMultiplier`、`publicVerifierRatio`。

参与量 4：`joinedAmountByActionId`、`joinedAmountByMemberId`、`joinTokenAddress`、`totalGroupActionReward`。

结算 4：`serviceRewardByMemberId`、`memberReward`、`rewardDistribution`、`rewardByRecipientId`。

二次分配配置 3：`recipients`、`actionIdsWithRecipients`、`distribution`。

读面边界：`joinedAmountByActionId`/`joinedAmountByMemberId` 对 `round > _joinRound()` 返回 0（`L187`、`L201`）；`serviceRewardByMemberId` 与 `memberReward` 对不可结算轮次返回全零（`L254-257`、`L290-293`）；`currentVerifyRound` 在 phase < 3 时回滚 `RoundNotStarted(1,0)`。

## 四、逐入口判定

### `join` — 两类资格，满足其一即可

顺序（`L113-137`）：鉴权 → `currentJoinRound()` → `AlreadyJoined` → 解出 `actionTokenAddress` → `_isQualified` → `registerJoinState` → `ServiceJoined`。

`_isQualified`（`L588-607`）的两条路径：

| 路径 | 判据 | 代价 |
| --- | --- | --- |
| 群 owner | `GroupActionExecutor.hasActiveGroups(actionTokenAddress, memberId)` | 一次外部调用（O(1)） |
| 公共验证者候选 | 遍历该轮社区行动集，逐个读 `verifierApplication(...)` 的 `applicationId != 0` | O(votedActions) 次外部调用 |

- **不要求该轮已选出验证者**：只要「在该轮有有效申请」即可加入。规格明文。
- **资格按被加入轮判定**（`currentJoinRound()`），不是创建轮——服务 Proposal 创建之后每一轮都能加入。
- **`AlreadyJoined` 读 ActionTarget 注册表**而不是本地账本。因此 `ActionTarget.forceClearJoinState` 之后成员可以再次 `join` 并再发一条 `ServiceJoined`——注册表与本地状态的一致性由「服务侧不存本地加入账本」保证（服务侧只用 `isJoinedByRound`）。
- 资格循环无界，见 **GSE-06**。

### `exit` — 只清注册表

顺序（`L372-390`）：鉴权 → `isJoined` → `currentJoinRound()` → `clearJoinState` → `ServiceExited`。

- 服务侧没有资金，退出只清 ActionTarget 的加入态快照，没有资产可退。
- 因为服务侧不存本地账本，「退出」的全部后果就是让后续轮次的 `isJoinedByRound` 返回假。见 GSE-06 关于当轮结算资格的影响。

### `setRecipients` — 唯一的主体是群 owner 的配置入口

顺序：`onlyGroupOwner(groupId)` → `currentVerifyRound()`（作为实参求值）→ 库内 `UnknownSourceAction` → 三数组等长 → 上限 10 → 逐项（`recipientId != groupId`、比例非零、`remark ≤ 256`、去重、NFT 存在）→ 比例总和 ≤ 1e18 → 写三份历史 + 索引 → `RecipientsChanged`。

- **鉴权先于轮次**：modifier 在函数体之前执行，`currentVerifyRound()` 是函数实参、在 modifier 之后求值。`test/GroupServiceRecipients.t.sol:92 testSetRecipientsChecksOwnerBeforeRound` 用「phase = 0 且非群主」的场景断言先报 `NotGroupOwner`，钉死这条顺序。
- **只能写当前验证轮**：不接受调用者指定轮次，因此无法回写历史轮，也无法预写未来轮。
- **全部传空 = 显式清空**：写入空数组并在该轮移除 `actionIdsWithRecipients` 索引项，之后该轮及后续回退到空配置，不能重新找到清空前配置。

### 结算入口 — 两个角色、两份分子、一次校验

`_settlement`（`L482-513`）的判定顺序：

1. `isJoinedByRound(serviceToken, serviceActionId, round, memberId)` 为假 → 返回全零；
2. `_memberWeights` 两个权重都为零 → 返回全零；
3. `_denominator(scope) == 0` → 返回全零；
4. `actionReward(...) == 0` → 返回全零；
5. 否则套公式。

- 任一「全零」出口都让 `_mintMemberReward` 回滚 `MemberActionRewardUnavailable`，不置位已结算、不发事件——符合规格「两个分子都为零时不读取分母，视图返回全零，结算入口按零额规则回滚」。
- **两个角色分别检查**：`verifierWeight` 与 `ownerWeight` 任一非零就继续，所以同一 `memberId` 既是群 owner 又是锁定验证者时拿两份。规格明文要求「每个角色先检查自己的分子，为零只跳过该角色」。
- 收款方：`ownerRemaining` 与 `verifierReward` 都转给 `msg.sender`（`L772-777`）；二次分配部分转给各 `recipientId` 的**结算时**持有人（见 GSE-04）。

### 三个回调

| 回调 | 校验 | 状态写入 |
| --- | --- | --- |
| `onProposalCreated` | 项数恰 4 → 每项 32 字节 → `actionTokenAddress != 0` → `publicVerifierRatio ≤ 1e18` → 代币关系（同币或直接父币） | 三项配置 + 创建轮 |
| `onProposalVoted` | `targetData.length <= 1` | 无 |
| `onProposalSubmitted` | 仅 `onlyActionTarget` | 无 |

`onProposalCreated` 的代币关系校验是本合约唯一一条**跨合约读依赖**：`ILaunch(LAUNCH_ADDRESS).parentToken(sourceTokenAddress)`。`LAUNCH_ADDRESS` 从 Stake 派生（`L72`），在构造函数内缓存。

## 五、发现

### GSE-01（Info）协议级常量的 ABI 暴露口径在三个 Executor 之间不一致

- 现状：

  | 常量 | 位置 | 是否 ABI getter |
  | --- | --- | --- |
  | `GroupServiceExecutor.PRECISION` | 本合约 `L27` | **是**（`public constant`） |
  | `GroupServiceExecutor.DEFAULT_MAX_RECIPIENTS` | 本合约 `L28` | **是** |
  | `GroupServiceStorage.MAX_REMARK_BYTES` | 库 `L12` | 否 |
  | `GroupActionStorage.MAX_ORIGIN_SCORE` / `MAX_VERIFICATION_BATCH` / `MAX_DESCRIPTION_BYTES` | 库 `L19-21` | 否 |
  | `LpExecutor.PRECISION` | `L22`（`internal constant`） | 否 |

- 规格口径：`05-group-action-executor.md` 明确「三个协议级上界是编译期常量，不进构造函数、**不设 getter**」。`06-service-executor.md` 对 `DEFAULT_MAX_RECIPIENTS` 只说「协议级编译期常量」，没说不设 getter。
- 判定：不违反任何一条规格，但同类常量有三种暴露方式（`public` / `internal` / 库内 `constant`）。后果是链下无法用统一方式读协议上限——`DEFAULT_MAX_RECIPIENTS` 可读，`MAX_REMARK_BYTES` 不可读，而两者同属「二次分配配置面」。
- 建议：统一为「进 ABI」或「不进 ABI」二选一。若统一进 ABI，三个 Executor 都要暴露；若统一不进，本合约的两个 `public constant` 改成 `internal`。

### GSE-02（Info）同一个「群 owner 鉴权面」在两个兄弟合约里写法不同

- `GroupServiceExecutor.onlyGroupOwner(uint256 groupId)`：定义在本合约（`L56`），错误用本合约的 `IGroupServiceExecutorErrors`。
- `GroupActionExecutor`：无本合约定义，判定在 `GroupActionManager.onlyGroupOwner(self, protocol, groupId)`（`L27`），错误用 `IGroupActionManagerErrors`。
- 判定：两者都对（§5.5 允许「错误名按各合约自己的 `I<Name>Errors` 取，允许不同」），但同一鉴权面在兄弟合约里一处「合约内」一处「库内」，评审时容易只看到其中一处。这是 24KB 拆分带来的必然不一致，登记即可。
- 建议：在 `06-service-executor.md` 的构造函数段补一句「本合约的群 owner 判定留在合约内，因为本合约没有对应的业务库」。

### GSE-03（Info）`setRecipients` 无 `nonReentrant`

- 证据：`L301-320`，只有 `onlyGroupOwner`；函数体调 `currentVerifyRound()`（→ `IPhase.currentPhase`）与库内写状态，无状态变更外呼。
- 判定：当前安全。与同合约的 `join`/`exit`（都有 `nonReentrant`）形状不一致，与 `GroupActionExecutor.setGroupConfig`（同型，也无锁）一致。
- 建议：与 `04-group-action-executor.md` GAE-03 一起处理——要么三条都加锁，要么在规格里统一说明「只调只读外部依赖的配置入口不设锁」。

### GSE-04（Info）二次分配的收款方是**结算时**的 NFT 持有人，不是配置时的持有人

- 证据：`GroupRecipients._distributeToRecipients`（`L241-243`）：`safeTransfer(IMemberNFT.ownerOf(recipientIds[j]), amount)`。
- 后果：群主在验证轮配置的接收人，若在结算前把 MemberNFT 转手，款项归新持有人。原接收人无法主张。
- 判定：与 core 审查的 MNT-03（`recipient` 任意 + NFT 可转移 = 临时持有人可截取）同型。这是「主体是身份、不是钱包」模型的必然结果，不是越权。
- 建议：在 `06-service-executor.md` 的二次分配段补一句「付款使用结算时接收 NFT 当前持有人」，与 `setRecipients` 段已有的「付款使用结算时接收 NFT 当前持有人」措辞对齐——规格在 `setRecipients` 段其实已经写了这一句，但没在 `distribution` 公式附近重复，容易被漏读。

### GSE-05（Info）`join` 的资格判定是 O(votedActions) 次外部调用，且无轮次级缓存

- 证据：`_isQualified`（`L588-607`）在 `hasActiveGroups` 为假时遍历 `_votedGroupActions(sourceTokenAddress, round)`，对每个行动调一次 `verifierApplication`（外部调用）。
- 规模上界：该轮社区行动集的大小由 Core 的每轮提案数上界保证（同 `ActionTarget.votedActions`，见 `01-action-target.md` AT-05），但该上界不在 `action` 仓内。
- 判定：不是权限缺陷，是可用性面——最坏情况下一次 `join` 的 gas 随该轮行动数线性增长，成员可能因 gas 超限而无法加入（可换轮次重试）。
- 建议：与 AT-05 一起，在 `06-service-executor.md` 写明该上界的数值与出处。

### GSE-06（Info）同一加入轮内退出，该轮的结算资格随之失效

- 证据：`exit` 调 `ActionTarget.clearJoinState`，后者在**当前加入轮**写零值终止点（`ActionTarget.sol:155-160`）；而 `_settlement` 的第一道判定是 `isJoinedByRound(..., round, memberId)`（`L489`）。
- 后果：成员在加入轮 N 退出后，`isJoinedByRound(N)` 返回假，因此第 N 轮的结算对该成员回滚 `MemberActionRewardUnavailable`。第 N−1 及更早轮次的快照不受影响。
- 判定：符合「同一加入轮内多次写入只保留最后一次，该轮结束状态以最后写入为准」的语义，不是缺陷。但它是**成员唯一会因自己的操作损失已积累权益的路径**——退出前应先结算可结算轮次。
- 建议：在 `06-service-executor.md` 的「加入与退出」段落写明这条，前端在退出确认时提示「本加入轮的结算资格将失效」。

### GSE-07（正面结论）`onlyGroupOwner` 先判零再比对，两个错误分离

- 证据：`L56-65`，`ownerOrZero` 返回零 → `GroupNotExist`；非零但不等于 `msg.sender` → `NotGroupOwner`。
- 负例：`test/GroupServiceRecipients.t.sol:101`（`GroupNotExist(999999)`）与 `:84`（`NotGroupOwner`）分别覆盖两条分支。
- 判定：与 `GroupActionManager.groupOwnerOrRevert` 同型，正确。

### GSE-08（正面结论）结算的两个角色独立计权，同一成员可合法拿两份

- 证据：`_applyFormulas`（`L515-558`）分别算 `verifierReward`（`publicVerifierRatio × verifierWeight`）与 `ownerReward`（`(1e18 − publicVerifierRatio) × ownerWeight`），两者互不影响；`_memberWeights`（`L609-624`）同时累加 `ownerWeight` 与 `verifierWeight`。
- 判定：符合规格「每个角色先检查自己的分子，为零只跳过该角色，不影响同一 `memberId` 的另一角色」。权限上这意味着**一个成员可以同时是某行动的群 owner 与另一行动的锁定验证者，两份收益都归它**——没有互斥校验，也不需要。

## 六、核对证据

```text
$ forge inspect GroupServiceExecutor abi --json | jq '[.[]|select(.type=="function")]|length'
35    # 写 8 / 读 27
$ forge inspect GroupServiceExecutor abi  vs  IGroupServiceExecutor
0 差异

$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0

$ forge build --sizes | grep GroupServiceExecutor
| GroupServiceExecutor | 18,392 | 19,655 | 6,184 |   # 距 24,576 上限 6,184 字节
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 非 ActionTarget 调三个回调 | `test/GroupServiceConstructor.t.sol:177/183/195` |
| 非持有人 `join` | `test/GroupServiceJoin.t.sol:116` `testJoinRejectsNonMemberOwner` |
| 非持有人 `exit` | `test/GroupServiceJoin.t.sol:199` `testExitRejectsNonMemberOwner` |
| NFT 转移后按新持有人判定 | `test/GroupServiceJoin.t.sol:248` `testExitFollowsCurrentOwnerAfterTransfer` |
| 非群主 `setRecipients` | `test/GroupServiceRecipients.t.sol:84` |
| 鉴权先于轮次 | `test/GroupServiceRecipients.t.sol:92` |
| 群不存在（`setRecipients`） | `test/GroupServiceRecipients.t.sol:101` |
| 群主仍受轮次约束 | `test/GroupServiceRecipients.t.sol:109` `testSetRecipientsOwnerStillChecksRound` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | ActionTarget | `isJoined`/`isJoinedByRound`、`registerJoinState`、`clearJoinState`、`mintActionReward`、`actionReward`、`votedActions` |
| 被调 | `GroupActionExecutor` | `hasActiveGroups`、`verifierApplication`、`totalStaked`、`stakedByMemberId`、`generatedActionReward`、`generatedActionRewardByGroupId`、`lockedVerifierId`、`joinTokenAddress` |
| 被调 | Core `Launch` | `parentToken`（代币关系校验） |
| 被调 | Core `Mint` | `isRewardPrepared`（分母缓存判据） |
| 被调 | Core `Phase` / `Stake` | `currentPhase`、`validGovVotes`、`totalValidGovVotes`（治理上限） |
| 被调 | Core `MemberNFT` | `ownerOf`（群主鉴权、二次分配付款对象） |
| 被调 | `GroupRecipients` | `setRecipients`、`distribute`、`distribution`、`projectedDistribution`、`ownerSlice` |
