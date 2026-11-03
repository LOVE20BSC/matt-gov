# GroupActionJoin（库）接口调用权限审查

> 对象 `action/src/GroupActionJoin.sol`（849 行，`library`，经 `delegatecall` 由 `GroupActionExecutor` 调用）
> 接口 `action/src/interfaces/IGroupActionJoin.sol`（256 行）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.4（退出顺序）、§5.2.2（失败顺序）；`specs/action/03-participation.md`、`specs/action/05-group-action-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| `external` 函数 | 17（写 6 / 读 11） |
| 带鉴权 modifier | 6（`onlyMemberOwner`，本库自定义） |
| 无许可写入口 | 0 |
| 发现 | 3 条 Info；另有 2 条正面结论 |
| 接口对账 | 由 `GroupActionExecutor` 侧统一对账（78 vs 78，0 差异） |

一句话：**参与资产的全部进出口（自有 + Provider 额度）都在这一个库里，6 个写入口全部 `onlyMemberOwner` 且都是函数体首道判定，成员与 Provider 两个主体分得很干净。两条需要记录的都是「状态清理被退款切开」这类顺序问题，不是越权。**

## 二、权限模型

本库只有一种鉴权形状，但作用在两个不同的主体上：

| 入口 | modifier 实参 | 权限主体 |
| --- | --- | --- |
| `join` | `memberId` | 成员 NFT 当前持有人 |
| `withdraw` | `memberId` | 成员 NFT 当前持有人 |
| `exit` | `memberId` | 成员 NFT 当前持有人 |
| `addProviderQuota` | `providerId` | Provider NFT 当前持有人 |
| `removeProviderQuota` | `providerId` | Provider NFT 当前持有人 |
| `withdrawProviderQuota` | `providerId` | Provider NFT 当前持有人 |

modifier 定义（`L29-38`）：

```solidity
modifier onlyMemberOwner(
    GroupActionStorage.Layout storage self,   // 未使用
    GroupActionStorage.Protocol memory protocol,
    uint256 memberId
) {
    if (IMemberNFT(protocol.memberNFTAddress).ownerOf(memberId) != msg.sender) {
        revert IActionExecutorErrors.NotMemberOwner(memberId);
    }
    _;
}
```

`self` 形参未被使用（见 `04-group-action-executor.md` GAE-05）。`protocol` 是本库判断身份的唯一外部输入，由 Executor 在每次调用时用五个 `immutable` 现拼（`GroupActionExecutor._protocol()`），因此本库不保存任何地址状态——库无状态，地址全部来自调用方。

## 三、入口清单

### 写入口（6）

| 函数 | 权限主体 | 首道判定 | 资金方向 | 事件 |
| --- | --- | --- | --- | --- |
| `join(address,uint256,uint256,uint256,uint256,uint256,string[])` | `memberId` 持有人 | `onlyMemberOwner` `L41-51` | `providerId == 0` 时从 `msg.sender` 拉取；非零不转账 | `GroupActionJoined` |
| `withdraw(address,uint256,uint256,uint256)` | `memberId` 持有人 | `onlyMemberOwner` `L118-125` | 退给 `msg.sender` | `GroupActionWithdrawn`（归零时另走 `_finalizeExit`） |
| `exit(address,uint256,uint256)` | `memberId` 持有人 | `onlyMemberOwner` `L178-184` | 自有部分退 `msg.sender`；Provider 部分不转出 | `GroupActionWithdrawn` + 逐 Provider `ProviderQuotaRestored` + `GroupActionExited` |
| `addProviderQuota(address,uint256,uint256,uint256,uint256[],uint256[])` | `providerId` 持有人 | `onlyMemberOwner` `L297-306` | 从 `msg.sender` 拉取总额 | 逐成员 `ProviderQuotaAdded` |
| `removeProviderQuota(address,uint256,uint256,uint256,uint256[])` | `providerId` 持有人 | `onlyMemberOwner` `L366-374` | 退给 `msg.sender` | 逐成员 `GroupActionWithdrawn` + `ProviderQuotaRemoved` |
| `withdrawProviderQuota(address,uint256,uint256,uint256,uint256,uint256)` | `providerId` 持有人 | `onlyMemberOwner` `L157-166` | 退给 `msg.sender` | `ProviderQuotaRemoved` |

### 只读入口（11）

`joinInfo`、`joinedAmountByGroupId`、`groupIdsByRound`、`memberIdsByGroupId`、`providerQuotas`、`providerAmountsByMemberId`、`joinedGroupIds`、`joinedGroupIdsByMemberId`、`joinedTokenAddressesByGroupIdByMemberId`、`joinedMemberIds`、`joinedMemberIdsByGroupId`。

分页签名统一为 `(…, offset, limit, reverse) → (列表, totalCount)`，越界返回空数组与真实总数、不回滚。`providerQuotas` 与 `providerAmountsByMemberId` 的页内成员是两个 `uint256`（定长），符合 §4.3 第 2 条。`joinInfo` 是点查而非集合，缺失返回全零 `JoinInfo`（`L254-256` 提前返回）。

## 四、逐入口判定

### `join` — 五个前置校验，鉴权在最前

顺序（`L41-106`）：鉴权 → `amount != 0` → `groupId != 0` → 群存在（`groupOwnerOrRevert`）→ 是否已属其他群 → 群约束（激活、上限、容量、最小加入量、行动上限）→ 写归属与参与量 → 首次时 `registerJoinState` → 写验证信息 → 追加金额 → 拉币 → 事件。

三条值得记录的权限性质：

1. **「同一行动只能属于一个群」由 `AlreadyInOtherGroup` 拦住**（`L74-77`），判据是 `groupHistoryByMemberId.latestValue()`——换群必须先正常退出，不能靠 `join` 改群。这使「群归属」成为成员不能单方面改写的状态（只能退出后重进）。
2. **`groupId` 只做存在性检查，不要求调用者拥有该群**（`L72`）。成员可以加入任何已激活的群，这与「群是开放加入的社区」一致；群 owner 通过 `maxCapacity`/`maxAccounts`/`minJoinAmount` 控制准入，而不是通过审批。
3. **`registerJoinState` 只在 `isJoined == false` 时调**（`L86-88`）。它是加入窗口下界（`JoinNotOpen`）的唯一来源，本库不重复判断轮次——符合规格。

### `withdraw` — 只减自有账本

顺序（`L118-154`）：鉴权 → `amount != 0` → 当前加入轮 → `amount <= ownAmount` → 减自有金额与群/行动总量 → 退币 → 事件 → 若自有与 Provider 双双归零则 `_finalizeExit`。

- **只动 `ownAmountHistoryByMemberId`**，不碰 `providerAmountHistoryByMemberId`。规格「`withdraw` 只减少自有账本，由成员当前持有人调用」在此落地。
- 归零判定同时看自有与全部 Provider 余额（`L151`），因此「撤完自己的但还有 Provider 额度」不会触发退出。

### `exit` — 结清全部来源，但 Provider 部分不转出

顺序（`L178-209`）：鉴权 → 当前加入轮 → 读 `groupId`/`ownAmount`/`providerAmount` → 两者皆零则 `NotJoined` → 减自有 + 退币 + `GroupActionWithdrawn` → `_restoreProviders`（逐 Provider 把已投入恢复为可用额度，发 `ProviderQuotaRestored`）→ `_finalizeExit`。

- Provider 来源在 `exit` 里**不转账**，只把「已投入」改回「可用额度」——Provider 仍可用 `removeProviderQuota` 取回。规格明文要求。
- 事件分三层：代币量只由 `GroupActionWithdrawn`（自有）与 `ProviderQuotaRestored`（Provider）承载；`GroupActionExited` 只表示退出状态、不带金额、最后发。

### 三个 Provider 额度入口

| 入口 | 校验顺序 | 关键性质 |
| --- | --- | --- |
| `addProviderQuota` | 鉴权 → 两数组等长 → `groupId != 0` → 群存在 → 群已激活 → 空数组直接返回 → 逐项（`memberId != providerId`、金额非零、NFT 存在）→ 汇总拉币 | 同一成员重复授予是**追加**，不回滚 |
| `removeProviderQuota` | 鉴权 → `groupId != 0` → 群存在 → 空数组直接返回 → 逐成员 `_revokeQuota` | 收回整笔授权，已投入部分同额减参与量，归零则自动退出 |
| `withdrawProviderQuota` | 鉴权 → `amount != 0` → `groupId != 0` → 群存在 → `amount <= 可用额度` | 只减未使用额度，**不改参与量** |

三者都不校验调用者是否拥有 `groupId`——见 **GAJ-01**。

### 只读入口的权限性质

11 个只读入口全部无权限、无回滚（除底层库的算术）。其中 `joinedGroupIds` / `joinedMemberIds` 是**跨全部社区与行动**的全局索引（`05-group-action-executor.md` 的 `joined*` 族），`isGroupMember` 就是 `membershipCountByGroupIdByMemberId != 0`。它们由参与事实驱动：只有真的有人参与过才入榜，退出后归零即出榜。

`ActionTarget.forceClearJoinState` **不修改这些索引**（规格明文），因此会出现「ActionTarget 注册表已清、本库 `isGroupMember` 仍为真」的短暂不一致——索引器须把两者当两个对象。

## 五、发现

### GAJ-01（Info）`withdrawProviderQuota` 只校验群存在，不要求调用者拥有该群

- 证据：`L166-175`，modifier 主体是 `providerId`；群侧只有 `GroupActionManager.groupOwnerOrRevert(protocol, groupId)`（只判 NFT 存在）。
- 后果：Provider 可以对**任何群、任何成员**撤回自己授予的未使用额度。
- 为什么不是越权：撤回的钱退给 `msg.sender`（Provider 自己），且只减少 `quotaAmountByGroupIdByProviderIdByMemberId[token][action][groupId][providerId][memberId]`——Provider 自己那份授权。成员参与量不变。
- 仍然登记的原因：函数签名里 `groupId` + `memberId` + `providerId` 三个 id 并列，读起来像「需要三个身份」；实际只需要 `providerId` 的持有人。集成方容易误以为要传自己的 `memberId`。建议在 `03-participation.md` 的额度接口段落加一句「`groupId`/`memberId` 是额度记录的定位键，不是权限主体」。

### GAJ-02（Info）未创建行动的 `join` 报 `GroupNotActive`，不是 `ActionNotCreated`

- 证据：`_checkGroupConstraints`（`L634-637`）先判 `group.active`，未激活即 `GroupNotActive(groupId)`。而群只能由 `activateGroup` 激活，后者要求 `createdRound != 0`。因此「行动未创建」在本路径上表现为「群未激活」。
- 与规格的偏差：`07-minting.md` 的错误表把 `ActionNotCreated` 定义为「行动尚未创建：群激活、验证者申请与三个 Executor 的成员结算都拒绝」——群激活与验证者申请确实报 `ActionNotCreated`，但 `join` 报的是 `GroupNotActive`。
- 判定：不是缺陷（`join` 本就不判行动存在性，规格也没要求），但错误语义偏移：链下无法从 `GroupNotActive` 区分「群还没激活」与「行动还没创建」。
- 建议：在 `03-participation.md` 的错误落点表里补一行「`join` 在行动未创建时表现为 `GroupNotActive`（经由群未激活）」，与 `05-group-action-executor.md` 已有的错误落点清单对齐。

### GAJ-03（Info）`exit` 与 `withdraw` 的状态清理被退款切成两段，CEI 不完全成立

- 证据：`exit`（`L192-206`）的顺序是「减自有金额（状态）→ 退币（外部调用）→ `GroupActionWithdrawn` → `_restoreProviders`（状态）→ `_finalizeExit`（状态 + `clearJoinState`）」；`withdraw` 的归零分支（`L137-153`）同型。
- 后果：退款发生时，`providerAmountHistoryByMemberId` 与群归属计数仍是旧值。若没有重入锁，重入的 `exit`/`withdraw` 会看到「自有已清零、Provider 未清」的中间态。
- 为什么当前安全：`GroupActionExecutor.exit`/`withdraw` 都带 `nonReentrant`（`GroupActionExecutor.sol:143`、`162`），锁在 Executor 的存储里，经 `delegatecall` 共享。
- 与 core `Stake.withdraw`（STK-01）的区别：那边是「没有锁 + `delete` 在外部调用之后」，这边是「有锁 + 清理顺序被切开」。锁使这条顺序不再承重，所以判定为 Info 而非 Low。
- 建议：若要消除对锁的依赖，把 `_restoreProviders` 的账本写入前移到退币之前（`ProviderQuotaRestored` 事件仍可留在后面发）。不改计算结果的纯顺序调整。

### GAJ-04（正面结论）6 个写入口全部 `onlyMemberOwner`，且都是函数体首道

- 证据：`L51`、`L125`、`L166`、`L184`、`L306`、`L374`——六处 modifier 紧贴函数签名，函数体第一句就是转调私有实现，没有「先做事再鉴权」的形状。
- 负例：`test/GroupActionJoin.t.sol:14/21/28` 三个用例分别以 `MEMBER2` 调 `join`/`withdraw`/`exit` 并断言 `NotMemberOwner(MEMBER1_ID)`，其中 `join` 传 `amount = 0`、`withdraw` 传 `amount = 0`、`exit` 传未加入的 `memberId`——三个「参数非法」的场景都先报鉴权错，证明鉴权确实是首道。
- 判定：§5.5「非授权方只拿到鉴权错误」在本库被完整覆盖。

### GAJ-05（正面结论）`clearJoinState` 的调用点收敛到一处

- 证据：`IActionTarget.clearJoinState` 在本库只出现一次（`L806`，`_finalizeExit` 内）。`_finalizeExit` 有三个调用点：`withdraw` 归零分支（`L152`）、`exit`（`L208`）、`_revokeQuota` 归零分支（`L431`）。
- 判定：加入态的清理只有一个出口，因此「注册表已清但本库仍认为已加入」这类不一致不可能由本库产生；三种退出路径（自有撤完、显式退出、Provider 收回）都走同一段清理代码，事件与状态写入不会分叉。

## 六、核对证据

```text
$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0

$ python3 …/evidence/auth_scan.py | grep GroupActionJoin
GroupActionJoin  写入口 6  带 modifier 6  无 modifier 0
  [AUTH] join                 onlyMemberOwner,self,protocol,memberId
  [AUTH] withdraw             onlyMemberOwner,self,protocol,memberId
  [AUTH] withdrawProviderQuota onlyMemberOwner,self,protocol,providerId
  [AUTH] exit                 onlyMemberOwner,self,protocol,memberId
  [AUTH] addProviderQuota     onlyMemberOwner,self,protocol,providerId
  [AUTH] removeProviderQuota  onlyMemberOwner,self,protocol,providerId
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 鉴权先于金额（`join`） | `test/GroupActionJoin.t.sol:14` |
| 鉴权先于金额（`withdraw`） | `test/GroupActionJoin.t.sol:21` |
| 鉴权先于「已加入」（`exit`） | `test/GroupActionJoin.t.sol:28` |
| 非 Provider 调额度入口（×2） | `test/GroupActionJoin.t.sol:500-508` |
| 群不存在（`groupId = 0` 与不存在的 id） | `test/GroupActionJoin.t.sol:371/375/463/467` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | ActionTarget | `isJoined`、`registerJoinState`、`clearJoinState` |
| 被调 | Core `MemberNFT` | `ownerOf`（6 个入口的鉴权函数 + 逐成员存在性检查） |
| 被调 | `IERC20` | `safeTransferFrom`（`join` 自有来源、`addProviderQuota`）、`safeTransfer`（`withdraw`/`exit`/`removeProviderQuota`/`withdrawProviderQuota`） |
| 内联复用 | `GroupActionManager` | `groupOwnerOrRevert`、`currentJoinRound`、`_maxJoinAmount`（编译期内联，无跨库 `delegatecall`） |
| 读写 | `GroupActionStorage.Layout` | 全部参与量、归属、额度、验证信息值、Provider 索引 |
