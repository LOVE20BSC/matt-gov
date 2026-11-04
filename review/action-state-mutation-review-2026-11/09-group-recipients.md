# GroupRecipients · 状态变量变更审查

> `action/src/GroupRecipients.sol`，367 行，`action@0c1d1e2`。
> 职责：服务行动的 owner 份额二次分配配置。写四个 Layout 字段（三本按轮数组历史 + 一个按轮集合），并在结算时按配置把 owner 份额拆给接收者。
> 本库是全仓唯一「配置按轮懒继承、且配置本身决定付款对象」的模块，因此状态的「哪一轮生效」比「写了什么」更重要。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局（本库写入的 Layout 字段）

| # | 字段 | 类型 | 键 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `recipientIdsHistory` | `RoundHistoryUint256Array.History` | 源代币 + 源行动 + 群 + 轮 | `_setRecipients:96` |
| 2 | `ratiosHistory` | 同上 | 同上 | `:97` |
| 3 | `remarksHistory` | `RoundHistoryStringArray.History` | 同上 | `:98` |
| 4 | `actionIdsWithRecipients` | `RoundHistoryUint256Set.Storage` | 源代币 + 群 | `:101`（add）、`:103`（remove） |

三本数组历史与一个集合的键都含 `round`，但只有数组历史的 `round` 是「配置变更轮」，集合的 `round` 是「该轮的有效集合快照」。

## 2. 逐变量变更逻辑

### 2.1 `setRecipients` → `_setRecipients`（`:48-118`）

| 顺序 | 位置 | 语句 | 守卫 |
| --- | --- | --- | --- |
| 1 | `GroupServiceExecutor:308` | `onlyGroupOwner(groupId)` | `GroupNotExist` / `NotGroupOwner` |
| 2 | `GroupServiceExecutor:312` | `round = currentVerifyRound()` | `phase < 3` 回滚 `RoundNotStarted(1,0)` |
| 3 | `:82-87` | `IGroupActionExecutor.joinTokenAddress(sourceToken, sourceAction) != 0` | `UnknownSourceAction` |
| 4 | `:89` | `_checkRecipients` | 见 2.2 |
| 5 | `:91-94` | 读 `prev*` 三份（`values(round)`，**带懒继承**） | — |
| 6 | `:96-98` | 写三本数组历史 `record(round, ...)` | — |
| 7 | `:100-104` | `recipientIds.length != 0` → add 集合；否则 remove | — |
| 8 | `:106-117` | `RecipientsChanged`（新表 + 旧表） | — |

第 5 步是唯一读旧值的地方，且读的是「`round` 时点的有效配置」而不是「`round` 原本写入的那一份」——见 M-GRC-01。

### 2.2 `_checkRecipients`（`:301-340`）

| 判据 | 错误 |
| --- | --- |
| 三数组等长 | `RecipientArrayLengthMismatch` |
| 长度 ≤ 10 | `TooManyRecipients` |
| `recipientId != groupId` | `RecipientIsGroupId` |
| `ratio != 0` | `ZeroRecipientRatio` |
| `remark` ≤ 256 字节 | `RemarkTooLong` |
| 无重复 `recipientId`（O(n²)） | `DuplicateMemberId` |
| `ownerOf(recipientId)` 可调 | 由 `IMemberNFT` 回滚 |
| `Σ ratios <= 1e18` | `DistributionOverflow` |

`Σ ratios < 1e18` 合法，余数归 owner（`:165`）。

### 2.3 `distribute`（`:168-196`）——结算时的写入面

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:179-181` | `ownerReward == 0` 或 `ownerWeight == 0` → 返回 0 | 不写状态 |
| 2 | `:183-184` | 枚举 `actionIdsWithRecipients[sourceToken][group].valuesByRound(round, 0, max, false)` | **无界** |
| 3 | `:187-188` | 逐行动 `ownerSlice(...)` | 每行动一次外部 staticcall |
| 4 | `:192-194` | `_distributeToRecipients(...)` | 逐接收者 `safeTransfer` |

本函数**不写任何 Layout 字段**，只转账。因此「二次分配」没有自己的账本：实际转出额由调用方（`GroupServiceExecutor._mintMemberReward:756`）记入 `ownerDistributedByMemberId`。

### 2.4 `_distributeToRecipients`（`:220-257`）

| 顺序 | 位置 | 语句 |
| --- | --- | --- |
| 1 | `:231-233` | 读该源行动的 `recipientIds` / `ratios`（`values(round)`，带懒继承） |
| 2 | `:235` | `_calculateRecipientAmounts(slice, ids, ratios)` → `amounts[]` + `distributed` |
| 3 | `:236-256` | 逐项：`amount == 0` 跳过；否则 `safeTransfer(ownerOf(recipientId), amount)` + `RecipientPaid` |

### 2.5 `ownerSlice`（`:282-298`）

```text
groupReward = GroupActionExecutor.generatedActionRewardByGroupId(sourceToken, sourceAction, round, groupId)
groupReward == 0 → 0
return mulDiv(ownerReward, groupReward, ownerWeight)
```

`ownerWeight` 是调用方传入的「该成员全部源行动群切片之和」，因此 `Σ slices <= ownerReward`（逐项向下取整）。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| R1 | 三本数组历史的长度恒等 | ✅ | `:96-98` 同笔写，且 `_checkRecipients` 先判等长 |
| R2 | `actionIdsWithRecipients[t][g]` 在该轮包含 `a` ⟺ 该轮 `recipientIdsHistory[t][a][g]` 非空 | ✅ | `:100-104` 的 add/remove 与数组长度同判据 |
| R3 | `Σ amounts <= slice` | ✅ | `amounts[i] = floor(slice * ratio_i / 1e18)`，`Σ ratios <= 1e18` |
| R4 | `Σ slices <= ownerReward` | ✅ | `slice = floor(ownerReward * groupReward_a / ownerWeight)`，`Σ groupReward_a <= ownerWeight` |
| R5 | `distribute` 的返回值 == `projectedDistribution` 的返回值 | ✅ | 两者用同一 `_calculateRecipientAmounts` 与同一 `ownerSlice`，跳过条件也相同（`slice == 0`、`amount == 0`） |
| R6 | 配置对「未配置的轮」懒继承到最近的不晚于该轮的记录 | ✅ | `RoundHistory*Array.values(round)` 的语义（`RoundHistoryUint256:19-25`） |

## 4. 发现

### M-GRC-01 · `RecipientsChanged.prev*` 是「懒继承后的有效值」，不是「本轮原本写入的值」

| 字段 | 值 |
| --- | --- |
| 位置 | `:91-94`、`:114-116` |
| 级别 | Info |
| 证据 | E1 |

`prevRecipientIds` / `prevRatios` / `prevRemarks` 用 `values(round)` 读出，而 `values(round)` 在没有该轮记录时会**回退到不晚于该轮的历史**（`RoundHistoryUint256Array.values` → `value(round)` 的懒继承）。

因此：

| 情形 | `prev*` 实际内容 | 事件消费方的直觉 |
| --- | --- | --- |
| 本轮已配过、再次修改 | 本轮上一份配置 | ✅ 一致 |
| 本轮首次配置，但上一轮有配置 | **上一轮的配置** | ❌ 会以为是「本轮原来的配置」 |
| 从未配置过 | 空数组 | ✅ 一致 |

后果：链下若用 `RecipientsChanged.prev*` 做「本轮变更前快照」，在「本轮首次配置」这一最常见的情形下会拿到上一轮的配置，从而把一次「首次配置」误判为「修改」。规格 `06:89` 写「按新表→旧表携带」，没有定义「旧表」是「本轮原值」还是「有效值」。

修法：`prev*` 改为「仅当 `index.contains(round)` 时才读 `valueByRound[round]`，否则读空」。这会改变事件载荷，属破坏性变更，需与事件规范一起改。

### M-GRC-02 · 配置懒继承使「配一次、永久生效」成立，且集合无法区分「本轮配过」与「继承来的」

| 字段 | 值 |
| --- | --- |
| 位置 | `:96-104`、`:183-184`、`:231-233` |
| 级别 | Info |
| 证据 | E1 |

`actionIdsWithRecipients` 是 `RoundHistoryUint256Set`，`valuesByRound(round)` 同样懒继承。因此：

1. 群主在第 5 轮给行动 A 配了接收者，第 6、7 轮不做任何操作；
2. 第 6、7 轮 `actionIdsWithRecipients.valuesByRound(6/7)` 仍然包含 A（继承自第 5 轮）；
3. `_distributeToRecipients` 用 `values(6/7)` 读配置，也继承第 5 轮；
4. 因此第 6、7 轮的结算继续按第 5 轮的配置分给同样的接收者。

这是规格 `06:85` 明确要求的行为（「回退到不晚于该轮的最近配置」），也是「配置一次即可持续分账」的便利。但有两个未登记的后果：

- **`actionIdsWithRecipients(sourceToken, groupId, round, ...)` 返回的是「有效集合」，不是「该轮写入过的集合」**。链下按它统计「该群配置过哪些行动」会把继承来的也算进去。
- **「显式清空」是唯一的终止方式**，且清空后不能「恢复上一次的配置」（`06:89` 明说「该轮及后续回退到空配置，不能重新找到清空前配置」）。状态上清空就是 `record(round, [])`，旧记录仍在更早的轮里，但读路径永远回退到最近的一次（空）。

### M-GRC-03 · `distribute` 的循环无界，群主可以放大其成员的结算 gas

| 字段 | 值 |
| --- | --- |
| 位置 | `:183-195` |
| 级别 | Info |
| 证据 | E1 |

`distribute` 遍历该群在该轮**全部**已配置的源行动（`valuesByRound(round, 0, type(uint256).max, false)`），每个行动一次外部 staticcall（`ownerSlice` → `generatedActionRewardByGroupId`），每个非零接收者一次 `safeTransfer`。

循环长度 = 该群配置过的行动数 × 接收者数（≤10）。两个维度都由群主通过 `setRecipients` 控制，而付 gas 的是**结算的成员**（`mintMemberReward` 的调用者），不是群主。

因此群主可以把「配置 20 个行动的接收者」当成一种对群成员的 gas 税：成员每次结算都要为全部 20 个行动做切片计算，即使其中 19 个的 `groupReward` 为 0（`ownerSlice` 仍要发一次外部调用才知道是 0）。

这是本库唯一与「无界循环」相关的状态设计问题。缓解方式（不改语义）：在 `distribute` 里先读 `groupReward` 再决定是否调 `ownerSlice`（省一次 `mulDiv`，但省不掉 staticcall），或让群主显式指定本轮的源行动子集。

### M-GRC-04 · 配置不校验群是否激活、是否在该轮参与，任意群主可污染全局配置面

| 字段 | 值 |
| --- | --- |
| 位置 | `:82-89`（只校验源行动存在） |
| 级别 | Info |
| 证据 | E1 |

`_setRecipients` 的唯一存在性校验是「`sourceActionId` 是 GroupActionExecutor 创建过的行动」（`:83-87`）。它不校验：

- 该群在该行动上是否激活（`isGroupActive`）；
- 该群在该轮是否有成员参与（`memberIdsByGroupId.countByRound`）；
- 该群是否在该行动上有任何 `groupReward`。

后果是**无资金风险**的（`distribute` 只在 `groupReward > 0` 时付款，`ownerSlice` 会返回 0），但有三处可观测污染：

1. `actionIdsWithRecipients` 集合可以被任意群主写入任意行动，链下按集合统计「哪些行动有二次分配」会严重高估；
2. `RecipientsChanged` 事件流可以被任意群主刷（每个 `(源代币, 行动, 群)` 一次）；
3. `recipients(...)` 会对「从未参与的群」返回一份配置，看起来像「已配置但没分到钱」。

规格 `06:89` 只要求「源行动未由本 Executor 创建时回滚」，因此这是**规格授权的宽松面**。若要收紧，最小改动是在 `_setRecipients` 里加一次 `isGroupActive` 判断——但那会破坏「先配好、等激活」的用法，需产品决策。

## 5. 已核对为正确的点

- 三本数组历史同笔写、同判据维护集合（R1/R2），不会出现「数组有值但集合没有」。
- `_calculateRecipientAmounts` 逐项向下取整，`Σ amounts <= slice`（R3），且 `ownerAmount = groupReward − distributed` 不会下溢。
- `distribute` 与 `projectedDistribution` 用同一套计算，因此 `serviceRewardByMemberId` 的 `ownerDistributed` 投影与最终落地值一致（R5）——这是「视图可预演」的关键。
- `_checkRecipients` 的 `recipientId != groupId`（`:319-321`）挡住「owner 把份额分给自己」的循环，避免「owner 份额 → 自己」产生无意义的事件与转账。
- 空数组是合法的显式清空（`:100-104` 走 remove 分支），且三本历史都写空，不会留下「数组已清、集合未清」的中间态。
- `_distributeToRecipients` 跳过 `amount == 0` 的项（`:238-240`），因此不会为零额接收者发 `RecipientPaid`，也不会发零额 ERC20 转账。
- 比例和为 `1e18` 时合法（`> PRECISION` 才回滚），余数为 0，`ownerAmount = 0`，符合「100% 分配不下溢」。

## 6. 覆盖缺口

- 未测 `distribute` 在「群配置了 10 个行动但只有 1 个有 `groupReward`」时的实际 gas，因此 M-GRC-03 的成本量级只有结构判断，没有数值。
- 未审 `RoundHistoryStringArray` / `RoundHistoryUint256Array` 的 `values(round)` 在「该轮写入空数组」时是否与「未写入」可区分（按 `OrderedHistoryIndex.contains(round)` 应当可区分，未逐行复核）。
- 未审 `RecipientPaid` 事件的字段完整性（见 `action-events-audit-2026-11` 的 `06-group-recipients.md`）。
- 未审 `onlyGroupOwner` 在两个合约里的写法差异（`GSE-02` 已登记）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GRC-01` | 规格补写 | [`06-service-executor.md`](../../docs/specs/action/06-service-executor.md) 的「状态口径」：`RecipientsChanged` 的 `prev*` 是有效值，不是旧 `recInfo` 的原始拷贝 |
| `M-GRC-02` | 规格补写 | 同上：配置懒继承，集合无法区分「本轮配过」与「沿用上一轮」 |
| `M-GRC-03` | 设计保留 | `distribute` 无界循环，成本随接收人数线性增长且由份额承担；06 写明，不改源码 |
| `M-GRC-04` | 规格补写 | 同上：`setRecipients` 不校验群激活状态，任意群主可在停用群上配比例 |
