# GroupChatBanList 事件赋值与发射审查

> 对象 `group-chat/src/GroupChatBanList.sol`（169 行，`contract`）
> 声明 `group-chat/src/interfaces/IGroupChatBanList.sol`（`IGroupChatBanListEvents`，L14-22）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/01-lifecycle.md`、`05-chat-types.md`、`07-events-errors.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点 | 1 |
| 业务状态写入面 | 2 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0（独立发现） |
| 放行 | 可放行；关联 `GL-EV-2`（`senderIdBanList` 枚举顺序）、`GL-EV-4`（幂等零日志断言）见 README |

`GroupChatBanList` 维护管理员手工封禁名单与「最后一次封禁操作者」状态。`AdminSenderBanChanged` 同时覆盖 `listed=true`（封禁）与 `listed=false`（解封）；封禁时写入操作者快照，解封时删除操作者快照。事件在集合与操作者状态写入之后发射，重复封禁/解封不写不发。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `AdminSenderBanChanged`（封禁） | `groupId`, `targetSenderId`, `operator` | `_setSenderIdBanTargets:119` | `senderIdBanList.add:116`、`senderIdBanOperatorStates:134` | 返回 `banBySenderIds` 循环 |
| `AdminSenderBanChanged`（解封） | 同上 | `_setSenderIdBanTargets:119` | `senderIdBanList.remove:116`、`delete senderIdBanOperatorStates:136` | 返回 `unbanBySenderIds` 循环 |

`banBySenderIds` / `unbanBySenderIds` 的 `onlyOperator:37` / `:44` 完成群存在性与 owner/admin 鉴权；`_setSenderIdBanTargets` 内逐项检查 `targetSenderId != 0` 和数组内重复。

## 三、逐事件赋值链

### 3.1 `AdminSenderBanChanged`

```
event AdminSenderBanChanged(
    uint256 indexed groupId,
    uint256 indexed targetSenderId,
    uint256 operatorId,
    address indexed operator,
    bool listed
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:120` | 根键 |
| `targetSenderId` | `senderId:121` | 黑名单目标；只要求非零，不要求 MemberNFT 存在（允许预黑名单） |
| `operatorId` | 入参 `:122` | 群 owner 时为 `groupId`，admin 时为 `adminId`；`onlyOperator` 已鉴权 |
| `operator` | `msg.sender:123` | 实际调用者；与 `senderIdBanOperatorStates` 写入的地址同源 |
| `listed` | 入参 `listed:124` | `true` = 封禁，`false` = 解封；旧值 `!listed` |

状态迁移：

1. `_setSenderIdBanTargets:104-128` 遍历 `senderIds`。
2. 每项 `_checkTargetSenderId:110` 要求非零；数组内重复 `:111-115` 回 `DuplicateMemberId`。
3. `changed = listed ? add(senderId) : remove(senderId):116`。
4. `changed == true` 时 `_setSenderIdBanOperatorState:118`：封禁写 `BanOperatorState(msg.sender, operatorId)`（`:134`），解封删除（`:136`）；随后 emit。
5. `changed == false` 不写不发；任一项 revert 整批回滚。

解封事件的 `operator` / `operatorId` 是**解封者**，不是原封禁者。原封禁者仍可从更早的 `AdminSenderBanChanged(listed=true)` 事件还原；解封后 `senderIdBanDetails` 返回零操作者，与视图语义一致。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `senderIdBanList`（`Uint256Set`） | `add:116` / `remove:116` | `AdminSenderBanChanged.listed` | 按日志顺序取最后一次 |
| `senderIdBanOperatorStates[groupId][senderId]` | `:134` / `delete:136` | `AdminSenderBanChanged.operator` + `operatorId` | 封禁时新值，解封时删除；历史操作者由事件序列保留 |

两个业务写入面全部有事件覆盖。`senderIdBanList(groupId, offset, limit, reverse)` 的页序依赖 `Uint256Set` 当前存储顺序（swap-and-pop），见 `GL-EV-2`；`senderIdBanDetails` 的 `operatorAddresses` / `operatorIds` 对未封禁项返回零，与删除后的状态一致。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `groupId` 首字段 |
| `gc.management` 槽位（§6.1） | 通过 | 根键 → `targetSenderId` → `operatorId` → `operator` → `listed` |
| indexed ≤ 3（§6.3） | 通过 | `groupId` / `targetSenderId` / `operator`；`operatorId` 入 data |
| 状态写入后 emit（§3.4.3） | 通过 | 集合与操作者状态先写，事件后发 |
| 批量逐条 emit（§3.4.1） | 通过 | 每项一条；重复 ID/零目标在写前拒绝 |
| 零事实不发事件（§3.5） | 通过 | `changed == false` 不写不发（`:117-126`） |
| 旧值（§6.7） | 通过 | `listed` 布尔取反可推；未携带 `prevListed` |
| 动态字段上限（§6.8） | 不适用 | 无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；事件声明在 `IGroupChatBanListEvents` |
| 测试断言（§8.1） | 基本通过 | 封禁/解封、操作者、列表页、解封清空均有断言；emitter 未断言（`GL-EV-1`）；幂等零日志未断言（`GL-EV-4`） |

## 六、发现

### 关联项（不重复计数）

- `GL-EV-2`（P3，跨合约）：`senderIdBanList` 使用 `Uint256Set`，`remove` 为 swap-and-pop；`senderIdBanList(...)` 的页序是当前存储顺序，事件流只给出封禁/解封时间序。要复现页序必须重放 `Uint256Set.remove`。详见 README §五。
- `GL-EV-4`（P3，跨合约）：`testT123` 在 `:177-178` 重复封禁 `0x101`，但没有 `recordLogs` / 零日志断言；`changed == false` 的零日志分支没有测试。详见 README §五。
- `GL-EV-1`（P3，跨合约）：`testT120B` 断言 topic 与 data，但没有断言 `log.emitter == address(banList)`。详见 README §五。

### 正面结论（不计入发现）

- `AdminSenderBanChanged` 覆盖封禁/解封两个方向，`listed` 明确方向，旧值可推出。
- 封禁与解封的 `senderIdBanOperatorStates` 写入/删除都在事件之前；`testT128B` 断言解封后重新封禁的操作者切换，`testT128` 断言未封禁项返回零操作者。
- 目标只要求非零，不要求 NFT 存在，符合 `05-chat-types.md` 的预黑名单规则；零目标与重复 ID 都由 custom error 回滚。
- 批次按入参逐条发事件；`testT123` 的列表页与 `testT123B` 的 swap-and-pop 当前存储顺序均有覆盖。
- `senderIdBanList` 的 `reverse` 行为已在 `08-testing.md:14` 与 `testT123B` 中明确为「当前存储顺序」。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `AdminSenderBanChanged` | `AdminBanSource.t.sol:61-89`（T120B） | 封禁 + 解封；3 个 topic、`operatorId`、`listed`；未断言 emitter |
| `AdminSenderBanChanged` | `:346-397`（T128B） | 解封清空操作者、重新封禁切换操作者；未断言事件字段 |
| `AdminSenderBanChanged` | `:170-214`（T123） | 列表页、重复封禁（未断言零日志） |
| `AdminSenderBanChanged` | `:215-242`（T123B） | swap-and-pop 当前存储顺序（视图侧） |

## 八、复现

```bash
cd group-chat

python3 script/events/check-events.py
forge test --match-contract AdminBanSourceTest
# → 14 passed, 0 failed
```
