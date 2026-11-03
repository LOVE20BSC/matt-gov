# GroupActionJoin（库）事件赋值与发射审查

> 对象 `action/src/GroupActionJoin.sol`（849 行，`library`，经 `delegatecall` 由 `GroupActionExecutor` 调用）
> 声明 `action/src/interfaces/IGroupActionJoin.sol`（`IGroupActionJoinEvents`，L11-64）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/03-participation.md`、`05-group-action-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 6 |
| 发射点 | 9（`GroupActionWithdrawn` ×3、`ProviderQuotaRemoved` ×2、其余各 1） |
| 状态写入面（受事件覆盖） | 17 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 4 |
| 放行 | 可放行；4 项 P3 中 3 项是「事件与资金步的先后」，1 项是 `amount` 的两种量纲 |

本库是 action 层事件密度最高的模块：参与量的加减、Provider 额度的五个动作、加入态清理都在这里。**没有一条事件承载转账本身**——资金事实靠 `GroupActionWithdrawn`（自有来源）/ `ProviderQuotaRemoved`（额度退回）/ `ProviderQuotaRestored`（额度恢复、不转账）三条分工，`GroupActionExited` 是无金额终态标记。这套分工与 §4.4 一致，但两处「先发事件、后转账」的顺序与 §4.4 的字面要求有偏差。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `GroupActionJoined` | `tokenAddress`, `actionId`, `memberId` | `_join:96` | 归属索引 `:84`、`JoinStateRegistered` `:87`、验证值 `:89`、金额账本 `:90` | `safeTransferFrom` 已在 `:93`（仅 `providerId == 0`）完成 |
| `GroupActionWithdrawn` | 同上 | `withdraw:141` | `_decreaseOwnAmount:137`、`safeTransfer:139` | 归零时 `_finalizeExit:152` |
| `GroupActionWithdrawn` | 同上 | `exit:195` | `_decreaseOwnAmount:193`、`safeTransfer:194` | `_restoreProviders:206` |
| `GroupActionWithdrawn` | 同上 | `_revokeQuota:406` | `_removeQuota:403`（含 `_decreaseProviderAmount`） | `ProviderQuotaRemoved:417` |
| `GroupActionExited` | 同上 | `_finalizeExit:808` | 归属/计数/索引全清 `:783-804`、`clearJoinState:806` | 无（终态标记，§4.4 E4） |
| `ProviderQuotaAdded` | `tokenAddress`, `actionId`, `groupId` | `_addProviderQuota:351` | 额度 `:347`、名单 `:348` | 循环结束后汇总 `safeTransferFrom:362` |
| `ProviderQuotaRemoved` | 同上 | `_revokeQuota:417` | `_removeQuota:403` | 归零时 `_finalizeExit:431` |
| `ProviderQuotaRemoved` | 同上 | `_withdrawProviderQuota:839` | 额度 `:832`、名单 `:834`、`safeTransfer:837` | 无 |
| `ProviderQuotaRestored` | 同上 | `_restoreProviders:234` | `_decreaseProviderAmount:232` | `_finalizeExit:208`（调用方） |

族归属：`action.participation`（前五条）、`action.quota`（后三条）。

## 三、逐事件赋值链

### 3.1 `GroupActionJoined`

```
event GroupActionJoined(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    uint256 groupId,
    uint256 providerId,
    uint256 amount,
    string[] verificationValues
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:97-99` | 根键 → 父 id → actor |
| `round` | `GroupActionManager.currentJoinRound(protocol.phaseAddress)` `:81` | 加入轮；`:479-482` 在 `< 1` 时回滚 `RoundNotStarted(1, 0)` |
| `groupId` | 入参 `:101` | 已过 `groupId == 0` 回滚 `GroupNotExist:69-71`、群存在性 `:72` |
| `providerId` | 入参 `:102` | `0` = 自有资产（显式值，非哨兵，§3.6） |
| `amount` | 入参 `:103` | 已过 `amount == 0` 回滚 `ZeroParticipationAmount:66-68`；`providerId != 0` 时不超过可用额度 `:743-746` |
| `verificationValues` | calldata `:104` | 空数组 = **本次无新值**（§3.4.9），不表示清空；≤16 项、每项 ≤1024（`:709-724`） |

这是「增量型」事件：同一轮内多次 `join` 逐条记录（§3.4.1），余额由累加折叠，`verificationValues` 空数组不覆盖既有值。事件**不区分首次加入与追加**——`isFirstJoin`（`joinedGroupId == 0`，`:79`）只影响约束校验与归属登记，不进 payload；消费方从 `groupId` 是否变化与前一事件推导。

### 3.2 `GroupActionWithdrawn`（三个发射点）

```
event GroupActionWithdrawn(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    uint256 groupId,
    uint256 providerId,
    uint256 amount
);
```

| 发射点 | `round` | `groupId` | `providerId` | `amount` | `amount` 的量纲 |
| --- | --- | --- | --- | --- | --- |
| `withdraw:141` | `currentJoinRound:130` | `groupHistoryByMemberId.latestValue():135` | 字面量 `0:147` | 入参 `amount` | **转账额**（`safeTransfer:139` 给 `msg.sender`） |
| `exit:195` | `currentJoinRound:185` | `groupHistoryByMemberId.latestValue():186` | 字面量 `0:201` | `ownAmount`（= 全部自有余额 `:187`） | **转账额**（`safeTransfer:194` 给 `msg.sender`） |
| `_revokeQuota:406` | 入参 `round` | 入参 `groupId` | 入参 `providerId` | `used`（= 该 Provider 的已投入量 `:449`） | **参与量**（代币随整笔授权退回 Provider，由 `ProviderQuotaRemoved.amount` 承载） |

三处共用同一 schema，但第三处的 `amount` 不是「转给成员的钱」而是「成员参与量的减少」——这是 `GAJ-EV-1` 的核心。

`withdraw` 与 `exit` 的两处都在 `safeTransfer` **之后** emit，符合 §4.4 第 2 步「转账后立即 emit 带金额的 `*Withdrawn`」。第三处（`_revokeQuota`）的转账在 `removeProviderQuota:389` 汇总执行，晚于所有事件（`GAJ-EV-2`）。

### 3.3 `GroupActionExited`

```
event GroupActionExited(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    uint256 groupId
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:809-811` | 同 3.1 |
| `round` | 入参（三个调用方均传 `currentJoinRound`） | 退出轮 |
| `groupId` | 入参 | 退出时的归属群 |

无金额、无 `providerId`——§4.4「`*Exited` 是终态标记，最后发、不带金额」。`_finalizeExit` 的唯一调用点是三个：`withdraw:152`（自有撤完）、`exit:208`（显式退出）、`_revokeQuota:431`（Provider 收回后归零）。三种触发原因**不在事件里区分**，只能由前序事件推断（有 `providerId != 0` 的 `GroupActionWithdrawn` ⇒ Provider 收回路径）。

`_finalizeExit` 的顺序：清归属与索引 `:783-804` → `clearJoinState:806`（`JoinStateCleared(forced=false)`）→ `GroupActionExited:808`，逐字符合 §4.4 第 3、4 步。

### 3.4 `ProviderQuotaAdded`

```
event ProviderQuotaAdded(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed groupId,
    uint256 providerId,
    uint256 memberId,
    uint256 amount,
    uint256 quotaTotal
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `groupId` | 入参 `:352-354` | 根键 → 父 id → 对象 id |
| `providerId` | 入参 `:355` | actor（授权方），非 indexed（3 槽已满） |
| `memberId` | `memberIds[i]` `:356` | 被授权成员 |
| `amount` | `amounts[i]` `:357` | 本笔授予额；`:341-343` 已拒零 |
| `quotaTotal` | `quotaTotal = 原额度 + amounts[i]` `:346` → `:358` | 该成员在该 `(group, provider)` 下的**后置**授权额度 |

逐成员一条（§3.4.1），`amount` 之和等于 `:362` 的 `safeTransferFrom` 总额。`quotaTotal` 是后置锚点，与 `ProviderQuotaRemoved.quotaTotal` 配对，使授权额度这一维度可从事件流直接对账。

### 3.5 `ProviderQuotaRemoved`（两个发射点）

| 发射点 | `amount` | `quotaTotal` | 量纲 |
| --- | --- | --- | --- |
| `_revokeQuota:417` | `refundable` = `_removeQuota` 返回的**整笔授权** `:445` | 字面量 `0:424` | **转账额**（整笔授权退回 Provider，含未用 + 已投入） |
| `_withdrawProviderQuota:839` | 入参 `amount`（≤ 可用额度 `:828-830`） | `quotaAfter = quota - amount` `:831` | **转账额**（只退未使用部分） |

两处的 `amount` 都是「退回给 Provider 的代币量」，`quotaTotal` 都是后置授权额度，量纲一致。差异只在 `quotaTotal` 的取值：整笔收回时恒为 0，部分撤回时是余量。

注意 `_revokeQuota` 的 `amount` 是**整笔授权**，其中「已投入」那部分同时被 `GroupActionWithdrawn.amount`（同笔、`providerId != 0`）表达了一次——这是 `GAJ-EV-1`。

### 3.6 `ProviderQuotaRestored`

```
event ProviderQuotaRestored(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed groupId,
    uint256 providerId,
    uint256 memberId,
    uint256 amount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `groupId` | 入参 `:235-237` | 同 3.4 |
| `providerId` | `providerIds[i]` `:238` | 逐个有余额的 Provider |
| `memberId` | 入参 `:239` | 退出成员 |
| `amount` | `invested`（`providerAmountByMemberIdByProviderId.latestValue()` `:227-228`） | 已投入 → 可用额度的恢复量 |

不带 `quotaTotal`：本事件不改变授权额度（`quotaAmountByGroupIdByProviderIdByMemberId` 不动），只把「已投入」退回「可用」。因此 `quotaTotal` 缺失不是族内漂移（§3.1），而是该维度未变——但「已使用额度」这一维度因此没有后置锚点（`GAJ-EV-4`）。

`amount == 0` 的 Provider 被 `:229-231` 跳过，不发事件，避免零额日志。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `joinedRoundHistoryByMemberId` | `record:678` / `record(0):783` | `GroupActionJoined.round` / `GroupActionExited` |
| `groupHistoryByMemberId` | `record:679` / `record(0):784` | `GroupActionJoined.groupId` / `GroupActionExited.groupId` |
| `ownAmountHistoryByMemberId` | `increase:740` / `record:769` | `GroupActionJoined.amount`（`providerId = 0`）/ `GroupActionWithdrawn.amount`（`providerId = 0`） |
| `providerAmountHistoryByMemberId` | `increase:752` / `decrease:619` | `GroupActionJoined` / `GroupActionWithdrawn` / `ProviderQuotaRestored`（按 `providerId` 归组折叠） |
| `providerIdsByMemberId` | `add:749` / `remove:617` | 同上（派生索引） |
| `providerAmountByMemberIdByProviderId` | `increase:751` / `record:615` | 同上（按来源的明细） |
| `memberIdsByGroupId` | `add:680` / `remove:785` | `GroupActionJoined` / `GroupActionExited` |
| `groupIdsByRound` | `add:681` / `remove:787` | 同上（派生索引） |
| `joinedAmountByGroupId` | `increase:755` / `decrease:620,770` | 同上（群级聚合） |
| `joinedAmountByActionId` | `increase:756` / `decrease:621,771` | 同上（行动级聚合） |
| `quotaAmountByGroupIdByProviderIdByMemberId` | `:347` / `:453` / `:832` | `ProviderQuotaAdded.quotaTotal` / `ProviderQuotaRemoved.quotaTotal` |
| `quotaMemberIdsByGroupIdByProviderId` | `add:348` / `remove:454,834` | 同上（派生名单） |
| `membershipCountByGroupIdByMemberId` | `++:683` / `--:790` | `GroupActionJoined` / `GroupActionExited`（按群归组计数） |
| `membershipCountByTokenAddress` | `++:690` / `--:801` | 同上 |
| `joinedTokenAddressesByGroupIdByMemberId` | `add:692` / `remove:803` | 同上（派生索引） |
| `joinedGroupIds` / `joinedGroupIdsByMemberId` / `joinedMemberIds` / `joinedMemberIdsByGroupId` | `:685-688` / `:792-799` | 同上（四组派生索引，条件增删） |
| `verificationValueHistory` | `record:725` | `GroupActionJoined.verificationValues` |

17 个写入面全部覆盖。四个 `joined*` 集合与 `membershipCount*` 是纯派生（由 `(token, action, group, member)` 的加入/退出事实折叠），符合 §6.9。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 6 个事件均以 `tokenAddress` 开头 |
| 族槽位 `action.participation` | 通过 | 根键 → `actionId` → `memberId` → `round` → `groupId` → `providerId` → 数值/布尔 → 文本数组 |
| 族槽位 `action.quota` | 通过 | 根键 → `actionId` → `groupId` → `providerId` → `memberId` → 数值 |
| indexed ≤ 3（§6.3） | 通过 | participation 三事件用根键/`actionId`/`memberId`；quota 三事件用根键/`actionId`/`groupId`（`providerId` 是 actor，按「主对象键占满时 actor 降级」处理） |
| 批量逐条 emit（§3.4.1） | 通过 | `addProviderQuota` / `removeProviderQuota` / `_restoreProviders` 均循环内逐条 emit |
| 数组型增量为空 = 无新值（§3.4.9） | 通过 | `verificationValues` 空数组语义有专门用例 `:171` |
| 退出四步序（§4.4） | 部分通过 | `withdraw` / `exit` 完全符合；`removeProviderQuota` 路径的转账在 `*Exited` 之后（`GAJ-EV-2`） |
| 资金先于金额事件（§4.4 第 2 步） | 部分通过 | `withdraw`/`exit` 符合；`addProviderQuota` 与 `removeProviderQuota` 的转账在事件之后（`GAJ-EV-2`/`GAJ-EV-3`） |
| 失败不留日志（§3.5） | 通过 | 全部校验早于写入；批量内任一元素失败整笔回滚 |
| 动态字段上限（§6.8） | 通过 | `verificationValues` ≤16 项 ×1024 字节（`:709-724`） |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | 见第七节；含 E4 顺序断言与「逐来源一条」断言 |

## 六、发现

### GAJ-EV-1（P3）`GroupActionWithdrawn.amount` 在 `providerId != 0` 时是参与量而非转账额，与 `ProviderQuotaRemoved.amount` 重复表达同一笔资金

- 证据：`_revokeQuota`（`:392-433`）先发 `GroupActionWithdrawn{providerId, amount: used}`（`:406-415`），再发 `ProviderQuotaRemoved{amount: refundable, quotaTotal: 0}`（`:417-425`），其中 `refundable` 是**整笔授权**（`_removeQuota:445` 在清零前读取），`used` 是其中已投入的部分（`:449`）。实际转给 Provider 的是 `removeProviderQuota:389` 的 `totalRefund = Σ refundable`，即 `used + (refundable − used)`。
- 问题：同一笔 `used` 同时出现在 `GroupActionWithdrawn.amount`（参与量维度）与 `ProviderQuotaRemoved.amount`（授权额度维度）里。§3.1 允许这种跨事件冗余，但要求「必须在模块规格中登记理由」。`03-participation.md` 只写了「该笔参与量发 `GroupActionWithdrawn`、授权额度发 `ProviderQuotaRemoved`」，没有写明 `ProviderQuotaRemoved.amount` 已含已投入部分，也没有写明「两者不可相加」。
- 影响：任何按「`GroupActionWithdrawn.amount` 之和 = 成员收到的代币」折叠的索引器，在 Provider 路径上会把一笔 0 转账（钱给了 Provider）记成一笔支出，且与 `ProviderQuotaRemoved.amount` 重复计数一次。`testProviderQuotaRemoveWithdrawsTheUsedPart`（`:306-341`）恰好把这两个数（60 与 100）并列断言，但没有任何注释说明它们不可相加。
- 建议：在 `03-participation.md` 的「撤回与退出」段落补一句——「`GroupActionWithdrawn.amount` 是参与量维度：`providerId = 0` 时等于转给成员的代币，`providerId != 0` 时只是参与量减少，代币由 `ProviderQuotaRemoved.amount` 整笔退给 Provider，两者不得相加」；并在事件规范的 `action.participation` 族表下加同样一句。

### GAJ-EV-2（P3）`removeProviderQuota` 的退款转账晚于 `GroupActionExited`

- 证据：`removeProviderQuota`（`:366-390`）先 `for` 循环 `_revokeQuota`（`:385-387`，内部可能发 `GroupActionWithdrawn`、`ProviderQuotaRemoved`、`JoinStateCleared`、`GroupActionExited`），循环结束后才 `safeTransfer(msg.sender, totalRefund)`（`:389`）。
- 问题：§4.4 的固定顺序是「清自身状态 → 退款/转账 → 发带金额的 `*Withdrawn` → `clearJoinState` → `*Exited`」，并注明「没有对应事实的步骤为空步，但相对顺序不变」。本路径把第 2 步挪到了第 4 步之后：`GroupActionExited`（终态标记）先于转账。
- 影响：金额事实（`ProviderQuotaRemoved.amount`）仍在 `*Exited` 之前，所以「朴素折叠丢金额」这个 §4.4 想防的问题没有发生；但「终态标记之后不再有资产变动」这条更强的消费方假设被打破——按 `*Exited` 关闭仓位、随后核对余额的实现会看到余额在关闭后才变化。`testProviderQuotaRemoveWithdrawsTheUsedPart` 只断言三条事件的存在与字段，不断言转账位置，因此无回归网。
- 建议：把 `safeTransfer` 拆进循环（每个成员退一次）或先累计后「先转账、再逐条 emit」，使顺序回到 §4.4；若不改，需在 `03-participation.md` 显式登记「Provider 整笔收回路径的转账在全部事件之后，属有意例外」，并补一条断言转账日志下标大于 `GroupActionExited` 的用例把现状钉住。

### GAJ-EV-3（P3）`addProviderQuota` 的存款转账晚于全部 `ProviderQuotaAdded`

- 证据：`:336-360` 循环内逐成员写额度并 emit（`:351`），`:362` 才 `safeTransferFrom(msg.sender, address(this), totalAmount)`。
- 问题：事件报「额度已授予」（`quotaTotal` 为后置值），但资金尚未进入合约。§3.4.3 要求「payload 必须反映 emit 时点已提交的状态」——额度状态确实已提交，所以不算违规；但 §4.4 的「转账后立即 emit」方向在这里是反的，且这是全仓唯一一处「先记存款事实、后收款」的形态（对比 `LpExecutor.join:181` 与 `VerifierStakeDeposited:844` 都是先转账后 emit）。
- 影响：整笔原子，失败全部回滚，所以不存在「额度记了钱没到」的持久状态。风险在可观测性：单笔 tx 的日志看起来像「N 笔授予 + 0 笔转账」，需要额外回连 ERC-20 `Transfer` 才能确认资金到位；若将来把 `addProviderQuota` 改成部分成功（例如逐成员 try/catch），这条顺序会变成真缺陷。
- 建议：把 `safeTransferFrom` 前移到循环之前（总额先算一遍，或直接在循环内按成员转账），使「资金 → 额度 → 事件」与其余入口同型；成本是多一次 `amounts` 求和遍历。

### GAJ-EV-4（P3）「已使用额度」这一维度没有后置锚点，折叠需要成员当前群归属

- 证据：`providerQuotas().usedAmounts[i] = _quotaUsedAt(...)`（`:482`、`:489-501`），而 `_quotaUsedAt` 的实现是「成员当前所属群 ≠ 查询群 ⇒ 返回 0，否则返回 `providerAmountByMemberIdByProviderId.latestValue()`」。`ProviderQuotaAdded` / `Removed` 带 `quotaTotal`（授权额度），`ProviderQuotaRestored` 不带任何后置值。
- 问题：授权额度有后置锚点（两处 `quotaTotal`），已使用额度没有。要折叠 `usedAmounts`，消费方必须同时持有（a）该 `(token, action, member, provider)` 的全局已投入量（由 `GroupActionJoined` / `GroupActionWithdrawn` / `ProviderQuotaRestored` 三处按 `providerId` 折叠），与（b）该成员在该轮的群归属（由 `GroupActionJoined.groupId` / `GroupActionExited` 折叠）。两者任一缺失，`providerQuotas` 的第三列就复现不出来。
- 影响：`03-participation.md` 说「已使用额度取该成员在当前所属链群的已投入量（成员已不在该链群时为 0）」——这条规则本身要求消费方先算归属。跨群复用同一 Provider 的成员（`_quotaUsedAt` 注释 `:486-488` 描述的场景）会得到「旧群的 used = 0、新群的 used = 全部投入」，事件流不直接给出这个切分。
- 建议：在 `03-participation.md` 的 `providerQuotas` 段落写明「`usedAmounts` 不是独立账本，是『全局已投入』按『当前群归属』的投影；折叠顺序必须是先算归属再取投入」，或在 `ProviderQuotaRestored` / `ProviderQuotaRemoved` 上补 `usedTotal` 后置值。

### 正面结论（不计入发现）

- `withdraw` / `exit` 两条路径的「状态 → 转账 → `GroupActionWithdrawn` → `JoinStateCleared` → `GroupActionExited`」逐字符合 §4.4，`testExitOrdersWithdrawnThenRegistryClearThenExited`（`:344-371`）用三条日志的下标与 emitter 断言了这条顺序。
- `exit` 按来源拆分：自有金额一条 `GroupActionWithdrawn(providerId = 0)`，每个有余额的 Provider 一条 `ProviderQuotaRestored`（`:211-243`），`GroupActionExited` 不带金额——与 `03-participation.md`「代币量只由 `GroupActionJoined` 与 `GroupActionWithdrawn` 承载」逐条对应。`testExitEmitsPerSourceWithdrawnThenExited`（`:222-258`）断言「自有 → 恢复 → 退出」三条且 `logs.length == 3`。
- `_restoreProviders` 跳过 `invested == 0` 的 Provider（`:229-231`），不发零额事件。
- 三处 `_finalizeExit` 收敛到同一段清理代码，事件与状态写入不会分叉（与 `action-api-auth-2026-11/05-group-action-join.md` GAJ-05 的结论一致）。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `GroupActionJoined` | `:75` | 8 字段全量（含空 `verificationValues`） |
| `GroupActionJoined` | `:145` | 首次加入携带验证值 |
| `GroupActionJoined` | `:171` | 追加不携带验证值（§3.4.9 空数组语义） |
| `GroupActionJoined` | `:840` / `:871` | 16 项 / 17 项边界 |
| `GroupActionWithdrawn` | `:260` | 自有部分撤回，`providerId = 0`、`amount = 40e18` |
| `GroupActionWithdrawn` | `:222` | `exit` 的自有腿 |
| `GroupActionWithdrawn` | `:306` | Provider 收回的已投入部分，`providerId != 0` |
| `GroupActionExited` | `:222` / `:344` | 位置与字段；`round`、`groupId` |
| `ProviderQuotaAdded` | `:75` | 逐成员一条，`amount` 与 `quotaTotal` 区分 |
| `ProviderQuotaRemoved` | `:260` | 部分撤回：`amount = 50e18`、`quotaTotal = 100e18` |
| `ProviderQuotaRemoved` | `:306` | 整笔收回：`amount = 100e18`、`quotaTotal = 0` |
| `ProviderQuotaRestored` | `:222` | `amount`、`providerId`、`memberId`、`groupId` topic |

缺三条：(a) `removeProviderQuota` 路径的转账与 `GroupActionExited` 的先后（GAJ-EV-2）；(b) `addProviderQuota` 的转账与事件的先后（GAJ-EV-3）；(c) `providerQuotas().usedAmounts` 在跨群复用 Provider 时的取值（GAJ-EV-4）。
