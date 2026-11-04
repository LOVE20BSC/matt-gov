# GroupActionJoin · 状态变量变更审查

> `action/src/GroupActionJoin.sol`，849 行，`action@0c1d1e2`。
> 职责：链群行动的参与面——加入、追加、部分撤回、退出、Provider 额度五件、按轮参与历史、归属索引与计数、成员验证信息值。**全仓最大的状态写入方**：一个 `join` 最多同时写 15 个 Layout 字段。
> 本卷只审状态写入，鉴权见 `action-api-auth-2026-11` 的 `05-group-action-join.md`，事件见 `action-events-audit-2026-11` 的 `04-group-action-join.md`。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局（本库写入的 Layout 字段）

按「写入时机」分三组。

### A. 参与账本（按轮，`RoundHistoryUint256`）

| # | 字段 | 键 | 写点 |
| --- | --- | --- | --- |
| A1 | `joinedRoundHistoryByMemberId` | token + action + member | `_registerMembership:678`、`_finalizeExit:783`（写 0） |
| A2 | `groupHistoryByMemberId` | 同上 | `_registerMembership:679`、`_finalizeExit:784`（写 0） |
| A3 | `ownAmountHistoryByMemberId` | 同上 | `_increaseAmount:740`、`_decreaseOwnAmount:769` |
| A4 | `providerAmountHistoryByMemberId` | 同上（全部 Provider 合计） | `_increaseAmount:752`、`_decreaseProviderAmount:619` |
| A5 | `providerAmountByMemberIdByProviderId` | 再加 providerId | `_increaseAmount:751`、`_decreaseProviderAmount:615` |
| A6 | `joinedAmountByGroupId` | token + action + group | `_increaseAmount:755`、`_decreaseOwnAmount:770`、`_decreaseProviderAmount:620` |
| A7 | `joinedAmountByActionId` | token + action | `_increaseAmount:756`、`_decreaseOwnAmount:771`、`_decreaseProviderAmount:621` |

### B. 按轮集合（`RoundHistoryUint256Set`）

| # | 字段 | 键 | 写点 |
| --- | --- | --- | --- |
| B1 | `memberIdsByGroupId` | token + action + group | `_registerMembership:680`（add）、`_finalizeExit:785`（remove） |
| B2 | `groupIdsByRound` | token + action | `_registerMembership:681`（add）、`_finalizeExit:787`（remove，仅当该群成员数归零） |
| B3 | `providerIdsByMemberId` | token + action + member | `_increaseAmount:749`（add，invested 由 0 变正时）、`_decreaseProviderAmount:617`（remove，归零时） |

### C. 当前态集合与计数（`Uint256Set` / `AddressSet` / 裸计数）

| # | 字段 | 键 | 写点 |
| --- | --- | --- | --- |
| C1 | `membershipCountByGroupIdByMemberId` | group + member | `_registerMembership:683`（`++`）、`_finalizeExit:790`（`--`） |
| C2 | `membershipCountByTokenAddress` | group + member + token | `_registerMembership:690`（`++`）、`_finalizeExit:801`（`--`） |
| C3 | `joinedTokenAddressesByGroupIdByMemberId` | group + member | `:692`（add）、`:803`（remove） |
| C4 | `joinedGroupIdsByMemberId` | member | `:686`（add）、`:793`（remove） |
| C5 | `joinedGroupIds` | — | `:688`（add）、`:795`（remove，仅当该群无人） |
| C6 | `joinedMemberIdsByGroupId` | group | `:685`（add）、`:792`（remove） |
| C7 | `joinedMemberIds` | — | `:687`（add）、`:798`（remove，仅当该成员无群） |

### D. Provider 额度与验证信息

| # | 字段 | 写点 |
| --- | --- | --- |
| D1 | `quotaAmountByGroupIdByProviderIdByMemberId` | `_addProviderQuota:347`（`+=`）、`_removeQuota:453`（置 0）、`_withdrawProviderQuota:832`（`-=`） |
| D2 | `quotaMemberIdsByGroupIdByProviderId` | `_addProviderQuota:348`（add）、`_removeQuota:454`（remove）、`_withdrawProviderQuota:834`（remove，归零时） |
| D3 | `verificationValueHistory` | `_applyVerificationInfos:725`（按 schema 下标 `record(round, value)`） |

## 2. 逐变量变更逻辑

### 2.1 `join`（`:41-106`）——一次写 15 个字段

| 顺序 | 位置 | 语句 | 失败形态 |
| --- | --- | --- | --- |
| 1 | `:51` | `onlyMemberOwner(memberId)` | `NotMemberOwner` |
| 2 | `:66-68` | `amount == 0` | `ZeroParticipationAmount` |
| 3 | `:69-71` | `groupId == 0` | `GroupNotExist(0)` |
| 4 | `:72` | `groupOwnerOrRevert(groupId)` | `GroupNotExist` |
| 5 | `:74-77` | `joinedGroupId != 0 && != groupId` | `AlreadyInOtherGroup` |
| 6 | `:79` | `_checkGroupConstraints(..., isFirstJoin)` | 见 2.2 |
| 7 | `:81` | `round = currentJoinRound()` | `RoundNotStarted(1,0)` |
| 8 | `:83-85` | 首次加入 → `_registerMembership` | 见 2.3 |
| 9 | `:86-88` | `!ActionTarget.isJoined` → `registerJoinState` | **外部写** |
| 10 | `:89` | `_applyVerificationInfos` | 见 2.6 |
| 11 | `:90` | `_increaseAmount` | 见 2.4 |
| 12 | `:92-94` | `providerId == 0` → `_pullJoinToken` | `safeTransferFrom` |
| 13 | `:96-105` | `GroupActionJoined` | — |

**第 9 步是本库唯一一处「先写外部注册表、后写本地账本」的顺序**（`LpExecutor.join` 是反过来的：先写本地、再 `registerJoinState`、再拉代币）。两者都安全（同笔回滚），但形状不一致：本库的 `_increaseAmount` 在外部写之后，若额度不足回滚，`ActionTarget` 的写入随同撤销，不产生「已注册未参与」。

### 2.2 `_checkGroupConstraints`（`:624-668`）——只读，但决定写入是否发生

| 顺序 | 位置 | 判据 | 错误 |
| --- | --- | --- | --- |
| 1 | `:635-637` | `group.active` | `GroupNotActive` |
| 2 | `:639-644` | `own + provider + amount <= maxJoinAmount`（非零时） | `GroupMaxJoinAmountExceeded` |
| 3 | `:646-654` | 首次加入：`memberCount < maxAccounts`（非零时）、`amount >= minJoinAmount` | `GroupAccountsFull` / `BelowMinJoinAmount` |
| 4 | `:656-662` | `groupTotal + amount <= maxCapacity`（非零时） | `GroupCapacityExceeded` |
| 5 | `:664-667` | `newTotal <= _maxJoinAmount(...)` | `ActionMaxJoinAmountExceeded` |

五条判据全部读**当前值**（`latestValue()` / `count()`），因此「本轮已发生的加入」都被计入。第 3 步的 `memberCount` 取 `memberIdsByGroupId.count()`，在 `_registerMembership` **之前**读，所以首次加入者不把自己算进人数上限。

### 2.3 `_registerMembership`（`:670-694`）——7 个字段同笔

| 位置 | 语句 | 条件 |
| --- | --- | --- |
| `:678` | `joinedRoundHistory.record(round, round)` | 值 = 轮次本身 |
| `:679` | `groupHistory.record(round, groupId)` | — |
| `:680` | `memberIdsByGroupId.add(round, memberId)` | — |
| `:681` | `groupIdsByRound.add(round, groupId)` | 幂等 |
| `:683` | `++membershipCountByGroupIdByMemberId` | — |
| `:684-689` | 计数 == 1 时 add 四个集合（C4/C5/C6/C7） | 「首次进入该群」 |
| `:690` | `++membershipCountByTokenAddress` | — |
| `:691-693` | 计数 == 1 时 add C3 | 「首次在该 token 下进入该群」 |

两级计数（群级 / 群+token 级）分别驱动「成员是否在该群」与「该成员在该群的哪些社区有归属」。

### 2.4 `_increaseAmount`（`:729-757`）

| 分支 | 位置 | 写入 |
| --- | --- | --- |
| `providerId == 0` | `:740` | `ownAmountHistory.increase(round, amount)` |
| `providerId != 0` | `:742-753` | `invested = providerAmountByMemberIdByProviderId.latestValue()`；`available = quota − invested`；`amount > available` → `InsufficientProviderQuota`；`invested == 0` 时 add B3；两个 provider 账本 `increase` |
| 公共 | `:755-756` | `joinedAmountByGroupId.increase`、`joinedAmountByActionId.increase` |

`available = quota − invested`（`:743`）是唯一可能下溢的减法。不可达性证明见 §3 J6。

### 2.5 `_decreaseOwnAmount` / `_decreaseProviderAmount`（`:759-772` / `:603-622`）

| 函数 | 写入 |
| --- | --- |
| `_decreaseOwnAmount` | `ownAmountHistory.record(round, ownAmount − amount)`（`:769`，用调用方传入的前值）、`joinedAmountByGroupId.decrease`、`joinedAmountByActionId.decrease` |
| `_decreaseProviderAmount` | `providerAmountByMemberIdByProviderId.record(round, invested − amount)`（`:615`，内部自己读 `invested`）、归零时 remove B3、`providerAmountHistory.decrease`、`joinedAmountByGroupId.decrease`、`joinedAmountByActionId.decrease` |

两者的 `ownAmount` 传参方式不同：`_decreaseOwnAmount` 由调用方传入「减之前的值」（`withdraw:131` / `exit:187` 读一次、传两次），`_decreaseProviderAmount` 自己再读一次 `latestValue()`。在 `_restoreProviders` 的循环里，每个 provider 的 `invested` 都是独立读的，不会因为前一个 provider 的减量而失真。

### 2.6 `_applyVerificationInfos`（`:696-727`）

| 条件 | 行为 |
| --- | --- |
| `!isFirstJoin && values.length == 0` | **早退，保留旧值**（`:706-708`） |
| `values.length > 16` | `TooManyVerificationValues` |
| `values.length != keys.length` | `VerificationInfoLengthMismatch` |
| 单值 > 1024 字节 | `VerificationValueTooLong` |
| 通过 | 逐项 `verificationValueHistory[token][action][member][i].record(round, values[i])` |

写入键是 **schema 下标 `i`**，不是 key 字符串。校验只查长度，不查顺序。

### 2.7 `_finalizeExit`（`:774-815`）——8 个字段同笔

| 顺序 | 位置 | 语句 |
| --- | --- | --- |
| 1 | `:783-784` | 两个历史槽 `record(round, 0)`（显式终止点，不是 delete） |
| 2 | `:785` | `memberIdsByGroupId.remove(round, memberId)` |
| 3 | `:786-788` | 该群成员数 == 0 时 `groupIdsByRound.remove(round, groupId)` |
| 4 | `:790` | `--membershipCountByGroupIdByMemberId` |
| 5 | `:791-800` | 计数 == 0 时 remove C6/C4，并在「群无人」/「成员无群」时 remove C5/C7 |
| 6 | `:801` | `--membershipCountByTokenAddress` |
| 7 | `:802-804` | 计数 == 0 时 remove C3 |
| 8 | `:806` | `ActionTarget.clearJoinState`（外部写） |
| 9 | `:808-814` | `GroupActionExited` |

第 8 步在全部本地状态写完之后，且它是本库唯一的外部写。`ActionTarget.clearJoinState` 对「已被强制清理」的成员静默返回，因此不会重复发 `JoinStateCleared`。

### 2.8 Provider 额度五件

| 入口 | 顺序 | 关键写入 |
| --- | --- | --- |
| `addProviderQuota:297` | 校验 → 循环写 D1/D2 → **最后**一次 `safeTransferFrom(totalAmount)`（`:362`） | 代币在状态写之后拉入（CEI ✅） |
| `removeProviderQuota:366` | 循环 `_revokeQuota` → 一次 `safeTransfer(totalRefund)`（`:389`） | 见 2.9 |
| `withdrawProviderQuota:157` | `available = quota − used` → `quota -= amount` → 归零则 remove D2 → `safeTransfer` | 只动未用额度，不动参与量 |

### 2.9 `_revokeQuota` / `_removeQuota`（`:392-455`）

| 顺序 | 位置 | 语句 |
| --- | --- | --- |
| 1 | `:445-448` | `refundable = quota`；为 0 → `QuotaNotGranted` |
| 2 | `:449` | `used = _quotaUsedAt(...)`（成员不在该群时为 0） |
| 3 | `:450-452` | `used != 0` → `_decreaseProviderAmount(..., used)`（同时减参与量三本账） |
| 4 | `:453-454` | quota 置 0、移出 D2 |
| 5 | `:427-432` | `used != 0 && own == 0 && provider == 0` → `_finalizeExit` |

第 5 步让 **Provider 能触发成员的自动退出**（`03-participation.md:23` 明确要求），因此 `_finalizeExit` 有三个调用方：`withdraw`、`exit`、`_revokeQuota`。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| J1 | `joinedAmountByActionId.value(r) == Σ_group joinedAmountByGroupId.value(r, g)` | ✅ | 六个写点全部成对（`:755/756`、`:770/771`、`:620/621`） |
| J2 | `joinedAmountByGroupId.value(r, g) == Σ_member (own + provider).value(r)`（该群成员） | ✅ | 同一批写点，成员侧与群侧同增同减 |
| J3 | `membershipCountByGroupIdByMemberId[g][m] == #{该 (g,m) 当前归属的 (token, action)}` | ✅ | `_registerMembership` 每个 `(token, action)` 首次加入 +1，`_finalizeExit` 对应 -1；见 J4 的成对性 |
| J4 | 每次 `_registerMembership` 恰有一次 `_finalizeExit` | ✅ | `_registerMembership` 只在 `joinedGroupId == 0` 时调用；`_finalizeExit` 只把 `groupHistory` 写成 0；三个触发点（`withdraw`/`exit`/`_revokeQuota`）都以「own == 0 且 provider == 0」为前提，之后 `groupHistory` 为 0，无法再次进入 |
| J5 | `membershipCountByTokenAddress[g][m][t] == #{该 token 下该 (g,m) 归属的 action}` | ✅ | 与 J3 同源（`:690` / `:801`） |
| J6 | `_increaseAmount` 的 `quota − invested` 不下溢 | ✅ | `invested` 只在 `_increaseAmount` 增加，且增加前校验 `amount <= quota − invested`；`quota` 只在 `_withdrawProviderQuota`（校验 `amount <= quota − used`，`used == invested` 当成员在该群）与 `_removeQuota`（`used == invested` 时同额减 `invested`）减少。因此「成员在当前群」这一前提下恒有 `invested <= quota` |
| J7 | `Σ_recipient`（二次分配）与 join 无关 | ✅ | 本库不写 `recipientIdsHistory` 族 |
| J8 | 所有 RoundHistory 写入轮单调不减 | ✅ | 唯一写入轮是 `currentJoinRound()` = `phase − 1` |
| J9 | 成员在同一 (token, action) 上至多属于一个群 | ✅ | `AlreadyInOtherGroup`（`:75-77`），且换群必须先 `_finalizeExit` 把 `groupHistory` 写成 0 |
| J10 | 退出后 `joinInfo` 全零 | ✅ | `joinedRound`/`groupId` 写 0，两个金额写 0 |

## 4. 发现

### M-GAJ-01 · 两级归属计数用 `++`/`--` 且无零值守卫，成对性只由三个写点的组合保证

| 字段 | 值 |
| --- | --- |
| 位置 | `:683`、`:690`、`:790`、`:801` |
| 级别 | Info |
| 证据 | E1 |

`membershipCountByGroupIdByMemberId` 与 `membershipCountByTokenAddress` 都是裸 `uint256`，用前置 `++`/`--` 维护。`--` 在计数为 0 时下溢成 `2^256 − 1`，失败形态是 Panic 0x11 而不是业务错误；更糟的是它**不会回滚到「可见的 0」**，而是让「该成员是否在该群」永远返回 true（`isGroupMember` 判 `!= 0`）。

当前成对性成立（J4）：`_registerMembership` 只在 `joinedGroupId == 0` 时调用，`_finalizeExit` 只在该值为非 0 时被三个触发点调用，且调用后它变 0。但这条链没有任何显式断言或 `require(count > 0)` 兜底。规格 `05:37` 只写「加入/退出同步维护这些集合与归属计数」，没写「计数归零才移除」。

建议加 `if (count == 0) revert` 之类的显式守卫，或把计数改成 `RoundHistoryUint256` 以便审计；不改行为，只把 Panic 变成可读错误。

### M-GAJ-02 · `join` 先写外部注册表、后写本地账本，与 `LpExecutor.join` 的顺序相反

| 字段 | 值 |
| --- | --- |
| 位置 | `:86-90` vs `LpExecutor:170-179` |
| 级别 | Info |
| 证据 | E1 |

本库的 `join` 顺序是：`_registerMembership`（本地）→ `ActionTarget.registerJoinState`（外部）→ `_applyVerificationInfos`（本地）→ `_increaseAmount`（本地）→ 拉代币。`LpExecutor.join` 是：本地三本账 → `registerJoinState` → 拉代币。

两者都不违反 CEI 的实质（外部写不回调本合约，且同笔回滚），但**同一个语义在两个 Executor 上有两种顺序**，且本库的顺序让 `_increaseAmount`（可能因额度不足回滚）排在外部写之后。后果仅是可读性：读代码的人必须先确认「`registerJoinState` 不会失败」才能接受「外部写早于本地账本」。

规格 `05:54` 只说「下界由 ActionTarget 的 `registerJoinState` 兜住」，未规定本库内部的写入顺序。

### M-GAJ-03 · 验证信息值按 schema 下标绑定，链下传错顺序会静默错配

| 字段 | 值 |
| --- | --- |
| 位置 | `:717-726` |
| 级别 | Info |
| 证据 | E1 |

`verificationValues[i]` 被写到 `verificationValueHistory[token][action][member][i]`，`i` 是**模板 keys 的下标**。校验只比较 `values.length == keys.length`（`:714`），不校验 key 名、也不接收 key 名。

因此链下必须严格按 `verificationSchema(token, action)` 返回的 `keys[]` 顺序构造数组。传反了不会回滚，会把 `tweet_url` 写进 `twitter_handle` 的槽位，且此后的 `verificationValue(memberId, key)` 会按 key 名查到错配的值。

规格 `05:18` 写了「项数与模板 keys 不符回滚」，没有写「顺序敏感」。这是 ABI 层的固有限制（数组无键），但值得在规格里补一句「值按位置对应 keys，调用方必须按 `verificationSchema` 的顺序传」。

### M-GAJ-04 · `joinedRound` 会被「退出后重新加入」覆写，首次加入轮不可从状态读出

| 字段 | 值 |
| --- | --- |
| 位置 | `:678`（写 `round`）、`:783`（写 0） |
| 级别 | Info |
| 证据 | E1 |

`joinedRoundHistoryByMemberId` 存的是「当前这次加入的轮次」，不是「首次加入轮」。成员在第 5 轮加入、第 7 轮退出、第 7 轮重新加入后，`joinInfo(7)` 返回 `joinedRound = 7`；第 5 轮的记录仍在（`value(5) = 5`），但没有任何入口回答「该成员在这个行动上第一次加入是哪一轮」。

后果：链下要算「成员在该群的加入时长」必须自己回放 `GroupActionJoined` / `GroupActionExited`，不能用 `joinedRound`。规格 `03:41` 只说 `joinInfo` 返回 `joinedRound`，未说明它是「当前段起点」。

### M-GAJ-05 · `_quotaUsedAt` 以「成员当前所属群」判定已用额度，换群后旧额度会突然显示为「全额可用」

| 字段 | 值 |
| --- | --- |
| 位置 | `:489-501`、`:743`、`:827` |
| 级别 | Info |
| 证据 | E1 |

`_quotaUsedAt` 的第一句是 `if (groupHistoryByMemberId.latestValue() != groupId) return 0;`。因此：

1. 成员在群 A 用掉 Provider P 的 100 额度；
2. 成员退出群 A（`_restoreProviders` 把 invested 归零，但群 A 的 quota 仍是 100）；
3. 成员加入群 B；
4. Provider 查 `providerQuotas(A, P)`，看到 `usedAmounts = 0`、可用额度 = 100。

这与规格 `03:41`「已使用额度取该成员在当前所属链群的已投入量（成员已不在该链群时为 0）」一致，所以不是缺陷。但**「可用额度」这个字段在成员换群后会突然变大**，Provider 若按「可用额度减少 = 被使用」来监控，会误判。`withdrawProviderQuota` 因此在成员离开后可以全额撤回，这是正确行为（资金确实没被使用）。

建议在规格的 `providerQuotas` 段落补一句「成员离开该群后，该群已用额度归零、可用额度回到全额」。

### M-GAJ-06 · `removeProviderQuota` 与 `withdrawProviderQuota` 的批量语义不对称，且前者对重复 memberId 会整批回滚

| 字段 | 值 |
| --- | --- |
| 位置 | `:366-390`（批量整笔收回）、`:157-175`（单人部分撤回） |
| 级别 | Info |
| 证据 | E1 |

两个入口都改 D1/D2，但语义不同：

| 入口 | 粒度 | 对参与量的影响 | 重复 id 的行为 |
| --- | --- | --- | --- |
| `removeProviderQuota` | 批量（`memberIds[]`） | 已投入部分同额减少参与量 | 第二次 `_removeQuota` 读到 quota 0 → `QuotaNotGranted` → **整批回滚** |
| `withdrawProviderQuota` | 单人 | 不影响参与量 | 不适用 |

批量接口没有长度上限（规格 `03:35` 明示「调用方按区块 Gas 分批操作」），因此「一次传 1000 个 memberId」会在最后一个失败时整批回滚，前面的状态写全部撤销。这不是缺陷，但链下批量脚本必须先去重。

### M-GAJ-07 · `_restoreProviders` 在遍历快照时删集合元素，依赖 `values()` 先物化

| 字段 | 值 |
| --- | --- |
| 位置 | `:211-243` |
| 级别 | Info（正面结论的口径说明） |
| 证据 | E1 |

`_restoreProviders` 先用 `values(0, providerCount, false)` 把集合物化成 memory 数组，再在循环里逐个 `_decreaseProviderAmount`（可能触发 `remove(round, providerId)` 的 swap-and-pop）。因为快照已物化，遍历不会跳过元素，也不会重复处理。

但这依赖 `Uint256Set.values` 的返回是 memory 副本（`Uint256Set:52` 返回 `self.items.paginate(...)`，`Pagination` 构造新数组）。如果将来把 `values()` 改成返回 storage 引用，这段会静默漏掉被换到前面的元素。规格 `05:35` 只对读面写了「不得跨调用缓存 offset」，没对写面写「遍历快照时删集合元素是安全的」。

## 5. 已核对为正确的点

- `_increaseAmount` 的两个分支在「群总账 + 行动总账」上的写入完全一致（`:755-756` 在 if/else 之外），因此 A6/A7 与 A3/A4 的增量恒等（J1/J2）。
- `withdraw` 的自动退出判据（`:151`）在退款之后读 `providerAmountHistory.latestValue()`，而 `_decreaseOwnAmount` 不触碰 provider 账本，判据不会被自己刚写的值污染。
- `exit` 的三段（自有归零 → `_restoreProviders` → `_finalizeExit`）顺序与规格 `03:24` 的「自有返还 → Provider 恢复为可用额度 → 清归属」一致。
- `_finalizeExit` 的两个历史槽写 `0` 而不是 `delete`（`:783-784`），符合「RoundHistory 懒继承必须留显式终止点，不能靠清空 mapping 伪造退出」（规格 `05:112`）。
- `groupIdsByRound` 只在「该群当前成员数归零」时移除（`:786`），且判据用 `count()`（最新值）而非 `countByRound(round)`——这是正确的：要维护的是「当前集合」，历史轮的集合由 `record(round, ...)` 固化。
- `_addProviderQuota` 的代币划转在循环之后一次完成（`:362`），循环内只写状态，不存在「部分成员已付款」的中间态。
- `_withdrawProviderQuota` 的 `available = quota − used` 与 `_increaseAmount` 的 `available = quota − invested` 用同一套 `_quotaUsedAt`，两处口径一致。
- `join` 的 `_checkGroupConstraints` 全部在写入之前，五条判据的失败都不会留下任何状态。
- `providerId == 0` 与 `!= 0` 的资金来源严格分离：前者拉代币，后者只扣额度，不会出现「既拉代币又扣额度」。

## 6. 覆盖缺口

- 未测 `_restoreProviders` 在「同一成员对同一 Provider 有多笔额度（不同群）」时的行为；按 `providerAmountByMemberIdByProviderId` 的键（无 group）应只归零一次，但 `_restoreProviders` 按 `providerIdsByMemberId` 去重遍历，未构造多群场景验证。
- 未复核 `GroupActionJoined` / `GroupActionWithdrawn` 与状态写入的顺序（见 `action-events-audit-2026-11` 的 `04-group-action-join.md`，其中 `GAJ-EV-2`/`GAJ-EV-3` 指出两处「事件早于转账」）。
- 未审 `groupOwnerOrRevert` 的 `ownerOf` 失败路径（`MemberOwner.ownerOrZero` 只吞 `ERC721NonexistentToken`，见 `13-member-owner.md`）。
- 未测 Provider 额度在「成员已退出但 quota 未收回」状态下的 `providerQuotas` 返回值与 `_quotaUsedAt` 的一致性（按代码应返回 `used = 0`、可用 = 全额，未跑测试确认）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GAJ-01` | 规格补写 | [`05-group-action-executor.md`](../../docs/specs/action/05-group-action-executor.md) 的「状态口径」：两级归属计数是裸计数，成对性只由三个写点组合保证，链下不得把计数当独立真值 |
| `M-GAJ-02` | 口径登记 | `join` 先写 `ActionTarget` 注册表、后写本地账本，失败整笔回滚；与 `LpExecutor.join` 的顺序差异不产生可观测状态，05 规格已按「外部先写」描述 |
| `M-GAJ-03` | 规格补写 | 同上：验证信息值按 schema 位置绑定，链下必须保序，传错顺序会静默错配 |
| `M-GAJ-04` | 规格补写 | 同上：`joinedRound` 是当前段起点，退出后重新加入会覆写，首次加入轮不可从状态读出 |
| `M-GAJ-05` | 口径核对 | 03 规格已写明「成员已不在该群时为 0」，本条无需改动源码或文档 |
| `M-GAJ-06` | 规格补写 | 同上：`removeProviderQuota` 与 `withdrawProviderQuota` 批量语义不对称，重复 `memberId` 整批回滚，链下批量脚本须先去重 |
| `M-GAJ-07` | 口径登记 | `_restoreProviders` 先物化 `values()` 快照再删元素，实现安全；不改源码 |
