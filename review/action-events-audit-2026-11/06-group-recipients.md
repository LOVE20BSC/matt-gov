# GroupRecipients（库）事件赋值与发射审查

> 对象 `action/src/GroupRecipients.sol`（367 行，`library`，经 `delegatecall` 由 `GroupServiceExecutor` 调用）
> 声明 `action/src/interfaces/IGroupRecipients.sol`（`IGroupRecipientsEvents`，L3-16）、`action/src/interfaces/IGroupServiceExecutor.sol`（`IGroupServiceExecutorEvents.RecipientPaid`，L15-24）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/06-service-executor.md`（二次分配段落）

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 2 |
| 发射点 | 2（一对一） |
| 状态写入面（受事件覆盖） | 4 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 2 |
| 放行 | 可放行；2 项 P3 为 §6.8 登记缺口与 indexed 布局，无逻辑问题 |

二次分配只有两条事件：配置侧 `RecipientsChanged`（新表 → 旧表全量）与付款侧 `RecipientPaid`（逐收款人一条）。两条都在转账之后发出，金额可从事件流完整重建。`Σ RecipientPaid.amount = ownerDistributed` 这条恒等式由 `GroupServiceExecutor.ServiceRewardsDistributed.ownerDistributed` 交叉锚定，是本模块最重要的一条可对账关系。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `RecipientsChanged` | `sourceTokenAddress`, `sourceActionId`, `groupId` | `_setRecipients:106`（由 `setRecipients:59` 调用） | 三处历史 `:96-98`、枚举集合 `:100-104` | 无（本笔结束） |
| `RecipientPaid` | `serviceTokenAddress`, `serviceActionId`, `groupId` | `_emitRecipientPaid:355`（由 `_distributeToRecipients:244` 调用） | `safeTransfer:241-243` | 循环继续下一个收款人；返回后由 `GroupServiceExecutor` 汇总 |

族归属：`RecipientsChanged` → `action.recipients`；`RecipientPaid` → `action.service`。

## 三、逐事件赋值链

### 3.1 `RecipientsChanged`

```
event RecipientsChanged(
    address indexed sourceTokenAddress,
    uint256 indexed sourceActionId,
    uint256 round,
    uint256 indexed groupId,
    uint256[] recipientIds,
    uint256[] ratios,
    string[] remarks,
    uint256[] prevRecipientIds,
    uint256[] prevRatios,
    string[] prevRemarks
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `sourceTokenAddress` | 入参 `:107` | 根键的**限定形式**（§6.2：`sourceTokenAddress` 是根键限定，不构成新根键） |
| `sourceActionId` | 入参 `:108` | 父对象 id；已过 `UnknownSourceAction:82-87`（源行动必须由本 Executor 创建） |
| `round` | `GroupServiceExecutor.currentVerifyRound()` `:312` | 当前验证轮；配置只写当前验证轮，不能指定已结束轮次 |
| `groupId` | 入参 `:110` | 配置主体（群 owner 的 memberId）；已过 `onlyGroupOwner:308` |
| `recipientIds` | calldata `:111` | ≤`DEFAULT_MAX_RECIPIENTS = 10`（`:312-314`）、去重（`:329-333`）、≠`groupId`（`:319-321`）、NFT 存在（`:334`） |
| `ratios` | calldata `:112` | 逐项 > 0（`:322-324`）、总和 ≤`1e18`（`:337-339`） |
| `remarks` | calldata `:113` | 每条 ≤`MAX_REMARK_BYTES = 256`（`:325-328`） |
| `prevRecipientIds` / `prevRatios` / `prevRemarks` | `values(round)` `:91-94`，在 `record` **之前**读取 | 旧表全量；该轮无记录时按 RoundHistory 懒继承返回「不晚于该轮最近一次的配置」 |

新表 → 旧表（§6.7「表状/结构配置一律旧+新」），组内三数组同序。三处 `record`（`:96-98`）在同一轮覆写，因此同轮多次 `setRecipients` 只保留最后一份快照，事件仍逐条记录（§3.4.4）。

「显式清空」的语义：`table.recipientIds.length == 0` 时 `actionIdsWithRecipients.remove(round, sourceActionId)`（`:103`），`record(round, [])` 会在该轮写入空数组并登记键（`libs/src/RoundHistoryUint256Array.sol:15-22` 的 `record` 无条件写 `valueByRound[round]`），因此 `values(round)` 返回空而不是回退到更早配置。这与「从未配置」在折叠上可区分（前者有 `RecipientsChanged` 事件且新表为空）。

### 3.2 `RecipientPaid`

```
event RecipientPaid(
    address indexed serviceTokenAddress,
    uint256 indexed serviceActionId,
    uint256 round,
    uint256 indexed groupId,
    address sourceTokenAddress,
    uint256 sourceActionId,
    uint256 recipientId,
    uint256 amount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `serviceTokenAddress` | 入参（`_distributeToRecipients` 形参）`:356` | 根键（服务侧） |
| `serviceActionId` | 入参 `:357` | 服务 Proposal 的 actionId |
| `round` | 入参 `:358` | 被结算轮（= 配置轮 = 验证轮） |
| `groupId` | 入参 `:359` | 群主体 |
| `sourceTokenAddress` | 入参 `:360` | 源链限定根键 |
| `sourceActionId` | 入参 `:361` | 源行动 id（`actionIdsWithRecipients` 的枚举项 `:186`） |
| `recipientId` | `recipientIds[j]` `:362` | 收款人 memberId，非 indexed（见 `GR-EV-2`） |
| `amount` | `amounts[j] = Math.mulDiv(slice, ratios[j], PRECISION)` `:350` | 逐项向下取整；`amount == 0` 的项被 `:238-240` 跳过，不发事件 |

每条都在 `safeTransfer`（`:241-243`，收款人为该 `recipientId` 的当前持有人）之后 emit，符合 §4.4 第 2 步方向与 §6.5（语义事件自带金额与 token 地址）。

同一条事件携带了「服务侧根键 + 源链限定根键」两套坐标，因此单条日志即可定位「哪个服务结算、哪个源行动的哪个群的哪个收款人拿了多少」，不需要回连 `RecipientsChanged` 或 `ServiceRewardsDistributed`。这是本仓 `action.service` 族的设计要点。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `recipientIdsHistory` | `record:96` | `RecipientsChanged.recipientIds` |
| `ratiosHistory` | `record:97` | `RecipientsChanged.ratios` |
| `remarksHistory` | `record:98` | `RecipientsChanged.remarks` |
| `actionIdsWithRecipients` | `add:101` / `remove:103` | `RecipientsChanged`（按 `recipientIds` 是否为空推导） |
| （无状态）结算结果 | — | `RecipientPaid`（逐笔）+ `GroupServiceExecutor` 的 `ownerDistributed` / `ownerRemaining` |

本库没有结算状态：`distribute` 只转账、不记账，`distributed` 作为返回值交给 `GroupServiceExecutor`（`:756`）落到 `ownerDistributedByMemberId`（`GroupServiceExecutor:769`）。因此「二次分配」这一层的账本在 Executor，事件在库——两个模块的边界正好落在 §4.1「发射者即状态所有者」的反面：这里库发的两条事件都不是本库的状态（配置表是 `GroupServiceStorage` 的，付款是 `GroupServiceExecutor` 的），而是**同一 Layout / 同一地址**下的状态。

按 §4.1 判定：`GroupRecipients` 与 `GroupServiceStorage` 共享同一个 `GroupServiceStorage.Layout`，运行在 `GroupServiceExecutor` 地址上，`delegatecall` 调用方就是状态所有者，事件声明在 `GroupServiceExecutor` 继承的接口里。三条条件逐条成立。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `RecipientsChanged` 以 `sourceTokenAddress` 开头（根键限定形式）；`RecipientPaid` 以 `serviceTokenAddress` 开头 |
| 族槽位 `action.recipients` | 通过 | 根键 → `sourceActionId` → `round` → `groupId` → 新表 → 旧表 |
| 族槽位 `action.service` | 通过 | 根键 → `serviceActionId` → `round` → 对象链（`groupId`）→ 源链（`sourceTokenAddress`/`sourceActionId`）→ 角色 → 数值 |
| indexed ≤ 3（§6.3） | 通过 | 两条各 3 个 |
| 表状配置旧+新（§6.7） | 通过 | 三组数组逐一配对，旧值在 `record` 之前读取 |
| 状态写入后 emit（§3.4.3） | 通过 | `:96-104` 先于 `:106` |
| 资金先于金额事件（§4.4） | 通过 | `safeTransfer:241` 早于 `emit:244` |
| 动态字段上限（§6.8） | 部分通过 | 新表三数组有上限；`prev*` 三数组未在 §6.8 基线表登记（`GR-EV-1`） |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；`_emitRecipientPaid` 用 `RecipientPaidParams` memory struct 承载 8 个字段，规避 legacy codegen 的 DUP16 栈深（`:30-39`、`:354-365`） |
| 测试断言（§8.1） | 通过 | 见第七节 |

## 六、发现

### GR-EV-1（P3）`prev*` 三组数组未在 §6.8 的动态字段上限基线表登记

- 证据：§6.8 基线表登记了 `RecipientsChanged.recipientIds` / `ratios`（≤`DEFAULT_MAX_RECIPIENTS`）与 `RecipientsChanged.remarks`（每条 ≤256 字节、条数 ≤`DEFAULT_MAX_RECIPIENTS`），但没有登记 `prevRecipientIds` / `prevRatios` / `prevRemarks`。
- 问题：这三个字段同样是 `string[]` / `uint256[]`，§6.8 要求「事件中的**每个** `string` / `bytes` / 数组字段必须有链上强制上限」。实际实现是有界的——`prev*` 只能由 `_setRecipients` 写入，与新表走同一套 `_checkRecipients`（`:301-340`），因此同界；但「同界」是靠写入路径推导的，不是登记的事实。
- 影响：事件 payload 的最坏体积是 6 个数组：新表 10×(32+32+256) + 旧表同量 ≈ 6.4 KB（不含 ABI 头）。这个数字没有任何地方写着；若将来 `DEFAULT_MAX_RECIPIENTS` 从 10 提到 50，payload 会变成 32 KB 级，而 §6.8 的基线表看起来仍然「已覆盖」。
- 建议：在 §6.8 的表里把 `RecipientsChanged` 那两行改成「`recipientIds`/`ratios`/`remarks` **及对应 `prev*` 三组**：≤`DEFAULT_MAX_RECIPIENTS`，`remarks` 每条 ≤256 字节」，并在 `06-service-executor.md` 的 `setRecipients` 段落注明「旧表与新表同界，因为它们只能由同一入口写入」。

### GR-EV-2（P3）配置侧与付款侧都无法按收款人过滤

- 证据：`RecipientsChanged` 的 3 个 indexed 槽给了 `sourceTokenAddress`/`sourceActionId`/`groupId`，`recipientIds` 是数组（§6.3 明令「动态数组绝不 indexed」）；`RecipientPaid` 的 3 个槽给了 `serviceTokenAddress`/`serviceActionId`/`groupId`，`recipientId` 在 data 里。
- 问题：§6.3 的优先级「根键 → 主对象 id 链 → actor」在两条事件上都指向「链路键优先」，这是对的；但结果是「一个成员想知道自己作为收款人收到过多少」既不能订阅配置事件、也不能订阅付款事件，只能全量扫描后按 data 解包。
- 影响：这是 `action.service` 族的固有取舍（服务侧与源侧各三个键，已经用满），不是实现错误。但对账场景（成员自查收入）没有可用的索引路径；`rewardByRecipientId`（`GroupServiceExecutor:139-159`）是唯一入口，而它是**当前态投影**、只能按 `(serviceToken, round, serviceActionId, sourceActionId, groupId)` 五元组逐条查，不能跨轮聚合。
- 建议：在 §6.3 的「分配优先级」段落后补一句已知代价——「`action.service` / `action.recipients` 族以链路键占满 indexed 槽，收款人维度不可过滤，链下对账须全量扫描或读 `rewardByRecipientId`」；若确有需求，另加一条只带 `(serviceTokenAddress, recipientId)` 的「收款汇总」事件会违反 §3.1 的一条事实一条事件，因此不建议。

### 已撤除的结论（GR-EV-3，原判 P2）库地址不可被直接 `CALL`，`RecipientsChanged` 的 emitter 唯一

本报告初版曾把「`RecipientsChanged` 可从库地址直接伪造」列为 P2，理由是 `setRecipients` 是 `external` 且无 modifier、两道守卫（`joinTokenAddress != 0` 与 `ownerOf(recipientId)`）都来自 `protocol` 形参、而 `GroupRecipients` 是部署后有独立地址的 `public library`。**这条推断被字节码与运行实测否定，已撤除。**

机制与 `GroupActionManager` 完全同型：`GroupRecipients` 的 `deployedBytecode` 开头是 `PUSH20 <自身地址> ADDRESS EQ`（`out/GroupRecipients.sol/GroupRecipients.json` 里地址位是链接期占位 `0x00…00`；`GroupServiceExecutor` 的 `linkReferences` 在 7 个偏移上引用本库），部署时填入库的真实地址。直接 `CALL` 时 `ADDRESS() == 自身地址` 成立 → 立即 revert，零日志。库的 `emit` 只有 `internal`（内联）与 `external`（只能 `DELEGATECALL`）两条路径，emitter 恒等于调用合约，即 `GroupServiceExecutor`。

残余价值（不是事件缺陷）：两道守卫全来自 `protocol` 形参这一点仍值得作为**纵深防御**记录——事件唯一性目前依赖「编译器守卫」，若将来库改为 `internal` 或编译器移除该守卫，就没有第二道了。这属接口权限视角，见 `action-api-auth-2026-11/09-group-recipients.md` GRC-01。


### 正面结论（不计入发现）

- `RecipientsChanged` 的旧值在 `record` 之前读取（`:91-94` 早于 `:96-98`），不会出现「新旧同值」；三组数组一一配对，长度由 `_checkRecipients:307-311` 保证相等。
- 「显式清空」与「从未配置」在事件与存储两侧都可区分：前者发 `RecipientsChanged` 且新表为空、`record(round, [])` 在该轮登记键；后者既无事件也无键，`values(round)` 回退到更早配置。
- `RecipientPaid` 在转账之后 emit，`amount == 0` 的项被跳过（`:238-240`），不发零额日志。
- 逐项向下取整、余数归 owner：`Σ amounts = distributed`（`:235`、`:351`），`ownerRemaining = ownerReward - distributed`（`GroupServiceExecutor:768`），恒有 `ownerReward == ownerDistributed + ownerRemaining`——`GroupServiceEvents.t.sol:44-55` 断言了这组等式（`ownerReward 90e18 = ownerDistributed 36e18 + ownerRemaining 54e18`）。
- `_emitRecipientPaid` 用 memory struct 承载 8 个字段（`:354-365`），规避了 legacy codegen 在 emit 参数里放多重 mapping 读导致的 stack too deep。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `RecipientsChanged` | `test/GroupServiceRecipients.t.sol`（整文件） | 配置写入、清空、越界（>10、比例和为 0、重复、等于 groupId、备注 >256）、按轮懒继承 |
| `RecipientPaid` | `GroupServiceEvents.t.sol:101-120` | 两条逐收款人断言（`groupId` topic、`sourceTokenAddress`、`sourceActionId`、`recipientId`、`amount` 全部区分取值） |
| `RecipientPaid` | `:32` | emitter 为 `GroupServiceExecutor` |
| 两条 | `:44-55` | `ownerReward == ownerDistributed + ownerRemaining`、`Σ 转账 + 销毁 == serviceReward` |

缺一条：`RecipientsChanged` 的**旧表**在「该轮从未配置、回退到更早轮次」时的取值断言。当前 `GroupServiceRecipients.t.sol` 覆盖了配置与清空，但没有用例构造「轮 5 配置、轮 6 不配置、轮 7 再配置」并断言轮 7 事件的 `prev*` 是轮 5 的表（懒继承）。建议补一条，这是 `GR-EV-1` 与折叠语义共同的薄弱点。
