# GroupMember 事件赋值与发射审查

> 对象 `group-chat/src/GroupMember.sol`（115 行，`contract`）
> 声明 `group-chat/src/interfaces/IGroupMember.sol`（`IGroupMemberEvents`，L13-21）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/01-lifecycle.md`、`05-chat-types.md`、`07-events-errors.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点 | 1 |
| 业务状态写入面 | 1 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0（独立发现） |
| 放行 | 可放行；关联 `GL-EV-2`（`memberIds` 枚举顺序）、`GL-EV-4`（幂等零日志断言）见 README |

`GroupMember` 只维护「群成员名单」一个业务集合。`MemberStatusChanged` 用 `listed` 布尔表达加入/移除，旧值可由 `!listed` 推出（§6.7 允许布尔取反省略旧值）；每次集合真实变化发一条，批次按入参逐条，重复/无变化不发。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `MemberStatusChanged`（加入） | `groupId`, `memberId`, `operator` | `_setMemberIds:81` | `IMemberNFT.ownerOf(memberId):73`、重复检查 `:74-78`、`memberIds.add:79` | 返回 `addMemberIds` 循环 |
| `MemberStatusChanged`（移除） | 同上 | `_setMemberIds:81` | 同上（`memberIds.remove:79`） | 返回 `removeMemberIds` 循环 |

`addMemberIds` / `removeMemberIds` 的 `onlyOperator:31` / `:38` 在进入 `_setMemberIds` 前完成群存在性与 owner/admin 鉴权；`_setMemberIds` 内逐项校验 NFT 存在、数组内重复，再执行 add/remove。

## 三、逐事件赋值链

### 3.1 `MemberStatusChanged`

```
event MemberStatusChanged(
    uint256 indexed groupId,
    uint256 indexed memberId,
    uint256 operatorId,
    address indexed operator,
    bool listed
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:82` | 根键 |
| `memberId` | 入参 `:83` | 对象 id，当前项 |
| `operatorId` | 入参 `:84` | 群 owner 时为 `groupId`，admin 时为 `adminId`；`onlyOperator:92-101` 已鉴权 |
| `operator` | `msg.sender:85` | 实际调用者；owner 或有效 admin 的 NFT 当前 owner |
| `listed` | 入参 `listed:86` | `true` = 加入，`false` = 移除；旧值 `!listed` |

状态迁移：

1. `_setMemberIds:67-90` 遍历 `memberIdList`。
2. 每项 `IMemberNFT(GROUP_ADDRESS).ownerOf(memberId):73`：成员 ID 必须对应存在的 MemberNFT；数组内重复 `:74-78` 回 `DuplicateMemberId`。
3. `changed = listed ? add(memberId) : remove(memberId):79`；只有真实变化才 emit（`:80-88`）。
4. 任一项 revert 整批回滚；前序项的写入与事件一并撤销。

事件不携带 `prevListed`：因为只有 `changed == true` 才发，旧值必为 `!listed`；这与 §6.7「布尔取反可推的旧值可以省略」一致。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `_memberState[groupId].memberIds`（`Uint256Set`） | `add:79` / `remove:79` | `MemberStatusChanged.listed` | 按日志顺序取最后一次；`listed` 即成员状态 |

一个业务写入面，一条事件完整覆盖。`memberIds(groupId, offset, limit, reverse)` 的页内顺序依赖 `Uint256Set` 的当前存储顺序（`remove` 为 swap-and-pop），见 `GL-EV-2`。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `groupId` 首字段 |
| `gc.management` 槽位（§6.1） | 通过 | 根键 → `memberId` → `operatorId` → `operator` → `listed` |
| indexed ≤ 3（§6.3） | 通过 | `groupId` / `memberId` / `operator`；`operatorId` 入 data |
| 状态写入后 emit（§3.4.3） | 通过 | `add/remove:79` 先于 `emit:81` |
| 批量逐条 emit（§3.4.1） | 通过 | 每项一条；重复 ID 在项内拒绝；整批失败回滚 |
| 零事实不发事件（§3.5） | 通过 | `changed == false` 不发（`:80-88`） |
| 旧值（§6.7） | 通过 | `listed` 布尔取反可推，省略 `prevListed` |
| 动态字段上限（§6.8） | 不适用 | 无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；事件声明在 `IGroupMemberEvents` |
| 测试断言（§8.1） | 基本通过 | 加入/移除双向、字段全量；emitter 未断言（`GL-EV-1`）；幂等零日志未断言（`GL-EV-4`） |

## 六、发现

### 关联项（不重复计数）

- `GL-EV-2`（P3，跨合约）：`memberIds` 使用 `Uint256Set`，中间移除会把末位搬到被删位置；`memberIds(groupId, offset, limit, reverse)` 的页序是当前存储顺序，事件流只给出加入/移除时间序。要复现同一页内容必须重放 `Uint256Set.remove`，不能按事件时间序拼接。详见 README §五。
- `GL-EV-4`（P3，跨合约）：`testT133B` 在 `:44-45` 再次添加已在名单中的 `senderId`，但没有 `recordLogs` / `getRecordedLogs().length == 0` 断言；`changed == false` 的零日志分支没有测试。详见 README §五。
- `GL-EV-1`（P3，跨合约）：`testT133B1` 断言 topic 与 data，但没有断言 `log.emitter == address(member)`。详见 README §五。

### 正面结论（不计入发现）

- `MemberStatusChanged` 覆盖名单的全部真实变化；加入与移除共用同一事件，`listed` 明确方向，旧状态可推出。
- 批次按入参逐条发事件；`testT133B1` 对两个新增成员断言两条事件、topic 与 data，顺序与入参一致。
- 没有软失败/调试事件；重复 ID、缺失 NFT、无权限都由 custom error 回滚，不留日志。
- 管理员路径：`_isOperator:103-114` 要求 `operatorId` NFT 当前 owner 是 `msg.sender`，且 `GroupAdmin.isAdminId` 有效；事件 `operatorId` 记录 adminId，`operator` 记录实际地址。
- `memberIds` 的枚举顺序已在 `08-testing.md:14` 以及 `testT133B` 中按当前存储顺序验证；事件侧的折叠约束见 `GL-EV-2`。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `MemberStatusChanged` | `GroupMemberScope.t.sol:66-95`（T133B1） | 加入两条 + 移除一条；3 个 topic、`operatorId`、`listed`；顺序与入参一致 |
| `MemberStatusChanged` | `:35-64`（T133B） | 加入/移除、分页、重复添加；未断言零日志 |
| `MemberStatusChanged` | `:97-113`（T133B2） | owner 与 admin 两路径；未断言 emitter |

## 八、复现

```bash
cd group-chat

python3 script/events/check-events.py
forge test --match-contract GroupMemberScopeTest
# → 6 passed, 0 failed
```
