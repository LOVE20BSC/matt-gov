# GroupActionManager（库）接口调用权限审查

> 对象 `action/src/GroupActionManager.sol`（506 行，`library`，经 `delegatecall` 由 `GroupActionExecutor` 调用）
> 接口 `action/src/interfaces/IGroupActionManager.sol`（209 行，含 `GroupConfig` 结构体）
> 基线 `action@8478619`（`src/` 自 `e849e36` 无实质变化，行号未位移）；审查日期 2026-11-03
> 判据 dev-standards §5.5、§5.2.2、§5.4；`specs/action/05-group-action-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| `external` 函数 | 16（写 4 / 读 12） |
| 带鉴权 modifier | 3（`onlyGroupOwner`，本库自定义） |
| 无许可写入口 | 1（`onProposalCreated`，鉴权在 Executor 的 `onlyActionTarget`） |
| 发现 | 4 条 Info；另有 2 条正面结论 |
| 接口对账 | 由 `GroupActionExecutor` 侧统一对账（78 vs 78，0 差异） |

一句话：**群的生命周期三件（激活、停用、改配置）都只认 `groupId` 的当前持有人，`groupOwnerOrRevert` 先判零再比对，避开了「不存在的群 = 零地址 = 零调用者」这个陷阱。三条质押计数器只在激活/停用两处成对增减，没有第三个写入口——这是本仓最干净的一组账本权限。**

## 二、权限模型

| 入口 | 权限主体 | 判定位置 |
| --- | --- | --- |
| `activateGroup` | `groupId` 持有人 | `onlyGroupOwner` `L27-36` + `L136` |
| `deactivateGroup` | `groupId` 持有人 | 同上 `L180` |
| `setGroupConfig` | `groupId` 持有人 | 同上 `L228` |
| `onProposalCreated` | ActionTarget | **本库无判定**，由 `GroupActionExecutor.onProposalCreated` 的 `onlyActionTarget`（`GroupActionExecutor.sol:104`）承担 |

`onlyGroupOwner` 的判定链（`L27-47`）：

```solidity
modifier onlyGroupOwner(Layout storage self, Protocol memory protocol, uint256 groupId) {
    if (groupOwnerOrRevert(protocol, groupId) != msg.sender) {
        revert IGroupActionManagerErrors.NotGroupOwner(groupId);
    }
    _;
}

function groupOwnerOrRevert(Protocol memory protocol, uint256 groupId) internal view returns (address) {
    address owner = MemberOwner.ownerOrZero(protocol.memberNFTAddress, groupId);
    if (owner == address(0)) revert IGroupActionManagerErrors.GroupNotExist(groupId);
    return owner;
}
```

**先判零是必须的。** 若不判零，`ownerOrZero` 对不存在的 `groupId` 返回 `address(0)`，`0 == msg.sender` 只对零地址成立——EVM 保证 `msg.sender != 0`，所以不会放行，但这依赖 EVM 层保证而非合约语义。显式判零把「群不存在」与「你不是群主」分成两个错误（`GroupNotExist` / `NotGroupOwner`），既更准确也更安全。这与 core 侧 `ownerOrDelegateIdOf` 的 0 哨兵缺陷同型，此处写法正确（见 GAM-04）。

## 三、入口清单

### 写入口（4）

| 函数 | 权限主体 | 首道判定 | 资金方向 | 事件 |
| --- | --- | --- | --- | --- |
| `onProposalCreated(address,uint256,bytes[])` | ActionTarget | 无（Executor 侧） | 无 | `GroupActionCreated` |
| `activateGroup(address,uint256,uint256,GroupConfig)` | `groupId` 持有人 | `onlyGroupOwner` `L129-136` | 从 `msg.sender` 拉激活质押 | `GroupActivated` |
| `deactivateGroup(address,uint256,uint256)` | `groupId` 持有人 | `onlyGroupOwner` `L174-180` | 退给 `msg.sender` | `GroupDeactivated` |
| `setGroupConfig(address,uint256,uint256,GroupConfig)` | `groupId` 持有人 | `onlyGroupOwner` `L221-228` | 无 | `GroupConfigChanged` |

### 只读入口（12）

群状态 4：`groupState`、`isGroupActive`、`descriptionByRound`、`activeGroupIds`。

质押 3：`staked`、`totalStaked`、`stakedByMemberId`。

索引 4：`tokenAddressesByGroupId`、`actionIdsByGroupId`、`actionIdsWithActiveGroups`、`hasActiveGroups`。

计算 1：`maxJoinAmount`。

读面边界：全部不回滚。`descriptionByRound` 无记录返回空串（RoundHistory 懒继承）；`maxJoinAmount` 在加入轮未开始或票数为零时返回 0 而不是回滚（`L371-382`）——这条很重要，因为它是 `join` 的上限判据，返回 0 会让任何 `newTotal > 0` 的加入都失败（`ActionMaxJoinAmountExceeded`），而不是让 `join` 崩掉。

## 四、逐入口判定

### `onProposalCreated` — 六项配置 + 可选验证模板，写一次

顺序（`L50-126`）：项数 6～7 → 第 1～5 项 32 字节 → 解出五项 → `joinTokenAddress != 0` → 两个比例 ≤ 1e18 → 写五项配置 → 可选写验证模板 → 写 `createdRound` → `GroupActionCreated`。

- **无 `AlreadyCreated` 守卫**，无条件覆写。唯一性由 ActionTarget 保证（见 GAM-01）。
- `activationStakeAmountByActionId` 的注释标了 `Load-bearing:`——「written only here. Refunds read this value instead of a per-group ledger, so a later write while groups are active would over-refund out of the other groups' stake」。这条不变式的强度完全依赖 ActionTarget（见 `04-group-action-executor.md` GAE-02）。

### `activateGroup` — 三件前置 + 一次质押

顺序（`L129-171`）：鉴权 → `createdRound != 0` → 未激活 → 配置合法 → 治理票占比达下限 → 当前加入轮 → 写群状态与描述快照 → 三处质押计数 → 四个索引 → 拉质押 → 事件。

- **`createdRound != 0` 前置是权限设计**：创建回调之前 `activationStakeAmount` 为零、`activationMinGovRatio` 未设，放行会让群零押金入场并绕开下限。规格已写明。
- **治理票下限**（`_checkActivationMinGovRatio` `L407-431`）：`minGovRatio == 0` 时直接放行（该行动不设下限）；否则要求 `totalValidGovVotes != 0`（否则 `NoGovVotes`）且群主占比 ≥ 下限。这是**唯一一处「不满足资格就不许获得权限」的门槛**——群主不能靠激活群来规避治理票门槛。
- **状态写入先于拉币**（`L151-168`），CEI 成立。

### `deactivateGroup` — 同一加入轮不可停用

顺序（`L174-219`）：鉴权 → 已激活 → `round != activatedRound` → 读质押额 → 写群状态 → 三处质押计数减 → 四个索引减 → 退质押 → 事件。

- **`DeactivationLockedInActivatedRound`**（`L187-189`）是唯一的轮次约束，效果是「激活即质押、当轮不可退」。它表现为轮次校验而非鉴权，但实际是一条**质押退出时间锁**：同一轮的质押在当轮无法撤回，下一轮可以。
- 退款对象是 `msg.sender`（当前群主），质押来源是激活时的持有人——见 `04-group-action-executor.md` GAE-04。
- 索引清理有两条级联判定（`L201-206`）：`actionIdsByGroupId` 归零才从 `tokenAddressesByGroupId` 移除；`activeGroupIdsByActionId` 归零才从 `activeActionIds` 移除。两条都只看「当前是否还有」，不看历史——符合规格「四组索引只反映当前激活状态，不保留停用历史」。

### `setGroupConfig` — 改配置不改质押

顺序（`L221-243`）：鉴权 → 已激活 → 配置合法 → 读旧配置 → 写新配置 + 描述快照 → `GroupConfigChanged`（新→旧全字段）。

- **不校验加入轮**：任何轮次都能改配置（`activateGroup`/`deactivateGroup` 才受轮次约束）。规格未禁止，但意味着群主可以在成员加入的同一轮内抬高 `minJoinAmount` 或缩小 `maxCapacity`——对已加入的成员无影响（约束只在 `join` 时判），对后续加入者立即生效。
- 事件携带新旧两份全量（`L451-475`），符合 §4.2「旧值不是布尔取反可推，必须逐项携带」。

### 只读入口的两处语义陷阱

1. **`hasActiveGroups(address tokenAddress, uint256 memberId)`**（`L357-363`）的语义是「该成员**作为群主体**在该社区是否存在激活行动」，实现是 `actionIdsByGroupId[tokenAddress][memberId].count() != 0`——即把 `memberId` 当 `groupId` 用。参数名 `memberId` 掩盖了这个角色转换。见 **GAM-05**。
2. **`maxJoinAmount`**（`L365-390`）读的是 `joinTokenAddressByActionId` 的 `totalSupply`，不是激励代币。因此它的量纲是「参与代币的流通量 × 比例 × 该行动票占比」，与 `activationStakeAmount`（同为参与代币）一致，与激励代币无关。

## 五、发现

### GAM-01（Info）`onProposalCreated` 无库内 modifier 且无条件覆写，唯一性完全由 ActionTarget 承担

- 证据：`L50-126`，无 `only*`；写 `joinTokenAddressByActionId`、`activationStakeAmountByActionId`、`maxJoinAmountRatioByActionId`、`activationMinGovRatioByActionId`、`verifierStakeAmountByActionId`、`verificationKeysByActionId`/`verificationDescriptionsByActionId`、`createdRoundByActionId` 共七组。
- 唯一防线：`ActionTarget.onProposalCreated` 的 `AlreadyCreated`（`ActionTarget.sol:445`）。
- 与 `L86-88` 的 `Load-bearing:` 注释并列看：该注释声明「这个值只在这里写」，但「只写一次」这件事本库不校验。二者合起来是一个**跨合约不变式**：本库承诺「不写第二次」，ActionTarget 承诺「不给第二次机会」。
- 附带一条（与 README G-03 同源，**已更正**）：`onProposalCreated` 的守卫**全部来自入参**（`targetData` 的形状与数值、`protocol.phaseAddress`），没有一条读 `Layout`。初版据此推断「直接调用本库地址也能通过全部守卫并发出 `GroupActionCreated`」，**该推断被字节码实测否定**：Solidity 为含 `external` 函数的库在 dispatcher 前置自地址守卫（`PUSH20 <自身地址> ADDRESS EQ`），直接 `CALL` 时 `ADDRESS() == 自身地址` 成立即在函数体执行前 revert、零日志，因此那五道守卫根本不会被求值。库的 `emit` 只有 `internal` 内联与 `external` `DELEGATECALL` 两条路径，emitter 恒为 `GroupActionExecutor`。
- 仍然成立的部分：本入口是**唯一一个守卫完全不读 `Layout` 的库级写入口**，事件唯一性目前依赖「编译器守卫」与「ActionTarget 的 `AlreadyCreated`」两道；若将来库改为 `internal`、或编译器移除该守卫，就只剩后者。这属纵深防御，不是当前缺陷。
- 建议：把这条写进 `05-group-action-executor.md` 的部署期不变量（与 GAE-02 同一条），并在 `DeployAction.s.sol` 广播前断言 `ACTION_TARGET_ADDRESS` 是预期实现。

### GAM-02（Info）`onlyGroupOwner` 的 `Layout storage self` 形参未使用

- 证据：`L27-36`，modifier 体内只用 `protocol` 与 `groupId`。
- 与 `GroupActionJoin:29`、`GroupActionVerify:50` 是同一处问题，三处应一起改（见 `04-group-action-executor.md` GAE-05）。

### GAM-03（Info）同一加入轮内不可停用，使当轮质押无法撤回

- 证据：`L186-189`，`round == group.activatedRound` 时回滚 `DeactivationLockedInActivatedRound(groupId, round)`。
- 权限后果：群主在激活的当轮没有「反悔」能力——质押至少锁定一个加入轮。这是对**群主自己**的限制，不是对第三方，因此不构成他人可利用的面。
- 副作用：`deactivateGroup` 是取回激活质押的唯一入口，它与 `activateGroup` 都受加入轮约束，因此「激活 → 当轮停用」这条快速往返被禁止，`staked*` 三处计数器不会在同一轮内抖动。
- 判定：设计意图清晰（规格错误表已登记该错误），但规格正文只写「`deactivateGroup` 在链群激活的同一加入轮停用回滚 `DeactivationLockedInActivatedRound`」，没写「这条的作用是让质押至少锁定一轮」。建议补上因果。

### GAM-04（正面结论）`groupOwnerOrRevert` 先判零再比对，把「不存在」与「不是主人」分成两个错误

- 证据：`L38-47`。
- 判定：与 core 侧 `ownerOrDelegateIdOf` 的 0 哨兵缺陷同型，此处写法正确。两个错误分离也让链下能区分「群 id 打错」与「用错钱包」。
- 负例：`test/GroupActionManager.t.sol:93`（`GroupNotExist(999)`）与 `:89`/`:202`/`:246`（`NotGroupOwner`）分别覆盖两条分支。

### GAM-05（Info）`hasActiveGroups(tokenAddress, memberId)` 的第二个参数实际是 `groupId`

- 证据：`L357-363` 的实现是 `self.actionIdsByGroupId[tokenAddress][memberId].count() != 0`——索引的第一维是 `groupId`。
- 语义（规格）：`hasActiveGroups` 判定「该成员**自身作为链群主体**在该社区是否存在激活行动」，是 GroupService 的加入资格判据。
- 问题：参数名 `memberId` 在类型上没错（`groupId` 就是某个 `memberId`），但读接口的人会以为「传任意成员 id 就能查他参与过的群」，而实际语义是「传某个群主 id，查他名下有没有激活群」。同一个合约里 `stakedByMemberId(tokenAddress, memberId)` 用的是**真**成员语义，两个相邻的 `ByMemberId` 入口语义不同。
- 判定：不构成权限缺陷（只读、无副作用），但属接口契约的歧义。建议在 `05-group-action-executor.md` 的索引表里给该行加一句「`memberId` 在此处是群主体（= `groupId`）」，或改名（属 ABI 变更，需按 §5.2 的破坏性变更流程处理）。

### GAM-06（正面结论）三处质押计数器只有激活/停用两个写入口，且成对增减

- 证据：`stakedByActionId`、`totalStaked`、`stakedByMemberId` 只在 `L159-161`（增）与 `L197-199`（减）被写；退款额读的是单写值 `activationStakeAmountByActionId`（`L157`、`L191`）。
- 判定：没有第三个写入口，因此「三处计数之和与实际托管余额」不会因漏改某个入口而漂移。加上 `activationStakeAmountByActionId` 单写，退款额与实际拉入额恒等——这是本仓最干净的一组账本权限。

## 六、核对证据

```text
$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0

$ python3 …/evidence/auth_scan.py | grep GroupActionManager
GroupActionManager  写入口 4  带 modifier 3  无 modifier 1
  [NONE] onProposalCreated  -
  [AUTH] activateGroup      onlyGroupOwner,self,protocol,groupId
  [AUTH] deactivateGroup    onlyGroupOwner,self,protocol,groupId
  [AUTH] setGroupConfig     onlyGroupOwner,self,protocol,groupId
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 非群主 `activateGroup` | `test/GroupActionManager.t.sol:89` |
| 群不存在（`activateGroup`） | `test/GroupActionManager.t.sol:93` |
| 非群主 `deactivateGroup` | `test/GroupActionManager.t.sol:202` |
| 非群主 `setGroupConfig` | `test/GroupActionManager.t.sol:246` |
| 非 ActionTarget 调创建回调 | `test/GroupActionManager.t.sol:274` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | Core `MemberNFT` | `ownerOf`（经 `MemberOwner.ownerOrZero`，3 个入口的鉴权函数） |
| 被调 | Core `Phase` | `currentPhase`（创建轮、激活轮、描述快照轮） |
| 被调 | Core `Stake` | `totalValidGovVotes`、`validGovVotes`（激活下限） |
| 被调 | Core `Vote` | `totalVoteAmount`、`voteAmountByProposalId`（`maxJoinAmount`） |
| 被调 | `IERC20` | `totalSupply`（`maxJoinAmount` 基数）、`safeTransferFrom`（质押）、`safeTransfer`（退款） |
| 被复用 | `GroupActionJoin` | `groupOwnerOrRevert`、`currentJoinRound`、`_maxJoinAmount`（编译期内联） |

## 处置

`GAM-01`、`GAM-02`、`GAM-03`、`GAM-05` 的落点见 `README.md` §十（`05-group-action-executor.md`）；本卷不改库代码。
