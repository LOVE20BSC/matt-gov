# GroupAdmin 事件赋值与发射审查

> 对象 `group-chat/src/GroupAdmin.sol`（201 行，`contract`）
> 声明 `group-chat/src/interfaces/IGroupAdmin.sol`（`IGroupAdminEvents`，L18-31）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/01-lifecycle.md`、`05-chat-types.md`、`07-events-errors.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点 | 2 |
| 业务状态写入面 | 3 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0（独立发现） |
| 放行 | 可放行；本报告无独立缺陷，关联 `GL-EV-2`（`adminIds` 枚举顺序）、`GL-EV-3`（`operatorId ≡ groupId` 登记）、`GL-EV-4`（幂等零日志断言）见 README |

`AdminChanged` 同时承载「管理员增删」与「双 owner 快照刷新」两种状态迁移：前者由 `listed` / `prevListed` 区分，后者由新旧 `groupOwnerSnapshot` / `adminOwnerSnapshot` 区分。事件携带新快照组 → 旧快照组，符合 §6.7；批次逐条发事件，幂等或纯重复调用不写不发。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `AdminChanged`（新增或快照刷新） | `groupId`, `adminId`, `operator` | `_addAdminId:97` | 快照写入 `:87-88`、`adminIds.add:91` | 返回 `addAdmins` 循环 |
| `AdminChanged`（移除） | 同上 | `_removeAdminId:125` | `adminIds.remove:117`、快照删除 `:123-124` | 返回 `removeAdmins` 循环 |

`addAdmins` 在循环前完成 `_checkAdminIdList`（存在性 + 重复）、`_checkAdminIdsLimit`（上限）和 `groupOwnerSnapshot` 读取；`removeAdmins` 在循环前完成 `_checkAdminIdList`。任一条 revert 整批回滚，不会留下半批事件。

## 三、逐事件赋值链

### 3.1 `AdminChanged`

```
event AdminChanged(
    uint256 indexed groupId,
    uint256 indexed adminId,
    uint256 operatorId,
    address indexed operator,
    bool listed,
    address groupOwnerSnapshot,
    address adminOwnerSnapshot,
    bool prevListed,
    address prevGroupOwnerSnapshot,
    address prevAdminOwnerSnapshot
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:98` / `:126` | 根键 |
| `adminId` | 入参 `:99` / `:127` | 对象 id |
| `operatorId` | 入参 `:100` / `:128` | `onlyGroupOwner:189` 强制 `operatorId == groupId`，见 `GL-EV-3` |
| `operator` | `msg.sender:101` / `:129` | 群 owner；与 `owner` 实时解析 |
| `listed` | `true:102` / `false:130` | 新状态 |
| `groupOwnerSnapshot` | 新增：`groupOwnerSnapshot = _groupOwnerOrRevert(groupId):40`，事件 `:103`；移除：`address(0):131` | 新增时的群 owner 快照；移除后无快照 |
| `adminOwnerSnapshot` | 新增：`IMemberNFT(GROUP_ADDRESS).ownerOf(adminId):81`，事件 `:104`；移除：`address(0):132` | 新增时管理员 NFT 的 owner 快照；移除后无快照 |
| `prevListed` | `!added:92` / `true:133` | 新增时若已存在则为 true；移除时恒为 true |
| `prevGroupOwnerSnapshot` | `state.groupOwnerSnapshots[adminId]:82` / `:121` | 写前读取 |
| `prevAdminOwnerSnapshot` | `state.adminOwnerSnapshots[adminId]:83` / `:122` | 写前读取 |

新增路径（`_addAdminId:74-109`）：

1. 读 `adminOwnerSnapshot`（`ownerOf:81`）与两组 prev 快照（`:82-83`）。
2. `snapshotChanged = prevGroup != group || prevAdmin != adminOwner`（`:84-85`）；仅当变化时写两组快照（`:87-88`）。
3. `added = adminIds.add(adminId):91`；`prevListed = !added:92`。
4. `!added && !snapshotChanged` 时直接返回，不写不发（`:93-95`）；这是唯一的「已存在且快照不变」幂等分支。
5. 其余情况 emit：`listed=true`，`prevListed` 为 `false`（新增）或 `true`（快照刷新），新快照非零，旧快照为 prev。

移除路径（`_removeAdminId:111-137`）：

1. `adminIds.remove(adminId)` 为 false（本来不在）时返回，不写不发（`:117-119`）。
2. 读 prev 快照（`:121-122`），删除两组快照（`:123-124`）。
3. emit：`listed=false`，`prevListed=true`，新快照为零地址，旧快照为被删值。

语义要点：`AdminChanged` 不是单纯的「新增/移除」事件，而是「管理员状态或快照变化」事件。`listed=true, prevListed=true` 表示**已在列表中但快照刷新**（例如管理员 NFT 转移后由群 owner 重新添加、或群 owner 转移后重新添加），消费方必须读 `prevListed` 与新旧快照，不能只按 `listed` 计数新增。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `adminIds`（`Uint256Set`） | `add:91` / `remove:117` | `AdminChanged.listed` | 按日志顺序取最后一次；`prevListed` 区分新增/快照刷新/移除 |
| `groupOwnerSnapshots` | `:87-88` / `delete:123` | `AdminChanged.groupOwnerSnapshot` / `prevGroupOwnerSnapshot` | 新值 + 旧值 |
| `adminOwnerSnapshots` | `:87-88` / `delete:124` | `AdminChanged.adminOwnerSnapshot` / `prevAdminOwnerSnapshot` | 新值 + 旧值 |
| `isAdminId` 有效性 | 无独立写入 | 由两组快照 + core ERC-721 `Transfer` 折叠 | §7.4；快照匹配当前 group/admin owner 即有效 |

三个业务写入面全部有事件覆盖。管理员有效性是派生值：`_isEffectiveAdminId:172-182` 实时比较快照与 `MemberOwner.ownerOrZero`，不单独存储；NFT 转移只改变 ERC-721 标准事件，不需要 `AdminChanged`。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `groupId` 首字段 |
| `gc.management` 槽位（§6.1） | 通过 | 根键 → `adminId` → `operatorId` → `operator` → 新值组（`listed`, 两快照）→ 旧值组（`prevListed`, 两 prev 快照） |
| indexed ≤ 3（§6.3） | 通过 | `groupId` / `adminId` / `operator`；`operatorId` 入 data |
| 状态写入后 emit（§3.4.3） | 通过 | 快照与集合写入都在 emit 之前 |
| 批量逐条 emit（§3.4.1） | 通过 | `addAdmins` / `removeAdmins` 循环每项一条；重复 ID 在循环前拒绝 |
| 零事实不发事件（§3.5） | 通过 | 已存在且快照不变 `:93-95`；移除不存在的 admin `:117-119` |
| 旧值+新值（§6.7） | 通过 | 新快照组 → 旧快照组；`prevListed` 始终携带 |
| 动态字段上限（§6.8） | 不适用 | 无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；事件声明在 `IGroupAdminEvents` |
| 测试断言（§8.1） | 基本通过 | 新增/移除/快照刷新三类都有用例；emitter 断言的正面样板见 `GroupAdmin.t.sol:238`；关联 `GL-EV-2` / `GL-EV-3` / `GL-EV-4` |

## 六、发现

### 关联项（不重复计数）

- `GL-EV-2`（P3，跨合约）：`adminIds` 使用 `Uint256Set`，`remove` 是 swap-and-pop（`libs/src/Uint256Set.sol:23-37`），`adminIds(groupId)` 的页内顺序是**当前存储顺序**，事件流只给出成员增删，无法仅按事件时间序重建页序。详见 README §五。
- `GL-EV-3`（P3，跨合约）：`AdminChanged.operatorId` 在所有可达路径恒等于 `groupId`（`onlyGroupOwner:189`），属协议恒等；§8.1 只登记了 `GroupChatActivated.ownerId ≡ groupId`，未登记本字段，测试无法区分两者。详见 README §五。
- `GL-EV-4`（P3，跨合约）：`!added && !snapshotChanged` 的零日志分支没有测试。`testT129F` 覆盖的是「已存在但快照变化 → 发事件」，`testT129B` 覆盖新增/移除；没有一条用例在重复添加且快照不变时断言 `getRecordedLogs().length == 0`。详见 README §五。

### 正面结论（不计入发现）

- `AdminChanged` 的 `listed` / `prevListed` 与新旧快照完整覆盖「新增」「快照刷新」「移除」三种状态迁移；`testT129F` / `testT129G` 专门断言 `listed=true, prevListed=true` 的快照刷新。
- `GroupAdmin.t.sol:238` 断言 `log.emitter == address(groupAdmin)`，是 group-chat 仓内少数带 emitter 断言的事件测试之一。
- `_checkAdminIdList` 在循环前拒绝重复/不存在的 admin，`_checkAdminIdsLimit` 在循环前拒绝超上限，任一项失败不会产生半批事件。
- 管理员有效性按「快照 + ERC-721 Transfer」派生，不把 `isAdminId` 结果写入状态，符合 §3.2 / §6.9。
- 移除事件把新快照写成零地址、旧快照写成被删值，`prevListed=true` 明确标识移除；折叠不会把「移除」误判为「从未添加」。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `AdminChanged` | `GroupAdmin.t.sol:45-73`（T129B） | 新增 + 移除；10 个字段全量；`logs.length == 1`；emitter |
| `AdminChanged` | `:131-148`（T129F） | 已存在但快照变化：`listed=true`、`prevListed=true`、新旧快照；emitter |
| `AdminChanged` | `:150-166`（T129G） | 群 owner 快照变化：`groupOwnerSnapshot` 与 `prevGroupOwnerSnapshot` 可区分 |
| `AdminChanged` | `:168-219`（T129D） | 输入上限、重复 ID、列表顺序；未断言零日志 |
| 缺 | — | 重复添加且快照不变的零日志分支（`GL-EV-4`） |
| 缺 | — | `adminIds` 页序在中间移除后的当前存储顺序（`GL-EV-2`） |

## 八、复现

```bash
cd group-chat

python3 script/events/check-events.py
forge test --match-contract GroupAdminTest
# → 8 passed, 0 failed
```
