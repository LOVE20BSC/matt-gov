# TokenActionScopeManager 事件赋值与发射审查

> 对象 `group-chat/src/managers/TokenActionScopeManagerBase.sol`（178 行，`abstract contract`）+ `TokenActionMainManager.sol`（51 行）+ `TokenActionGovManager.sol`（38 行）+ 其父级 `ManagerBase.sol`（185 行）、`TokenManagerBase.sol`（88 行，无事件，见 `08`）
> 声明 `group-chat/src/interfaces/managers/ITokenActionScopeManagerBase.sol`（`ITokenActionScopeManagerBaseEvents`，L13-20）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/06-manager.md`、`07-events-errors.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点（源码） | 1（`_activateManagedAction:134`） |
| 运行时发射者 | 2（`TokenActionMainManager`、`TokenActionGovManager`） |
| 业务状态写入面 | 3（两向映射 + 列表）+ 1 个派生缓存（`_mintNonce`，见 `08`） |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0 |
| 放行 | 可放行；无独立发现，关联 `GL-EV-1`（emitter 已由共享 helper 覆盖）与 `GL-EV-2` 不适用（`_actionIdsByTokenAddress` 是 append-only 数组） |

`TokenActionGroupActivated` 是 `TokenActionMainManager` 与 `TokenActionGovManager` 的共享事件类：同一 schema、同一语义、声明在共享接口 `ITokenActionScopeManagerBaseEvents`。事件把「token + actionId → group」的托管链路写入事件流；`groupId` 来自 `MemberNFT.mint` 返回值，`operator` 是激活付款者，且因三个链路键占满 indexed 槽而降为 data 字段。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `TokenActionGroupActivated` | `tokenAddress`, `actionId`, `groupId` | `_activateManagedAction:134` | `_checkLOVE20Token:118`、`_checkExistingAction:119`、`_checkNotManaged:120`、`_mintManagedGroup:127`、`_managedActionByGroupId:129`、`_groupIdByActionId:131`、`_actionIdsByTokenAddress.push:132`、`_activateManagedGroup:133` | 返回 concrete `activate` |

`_activateManagedGroup:133` 调用 `GroupChat.activateChat(groupId, address(this), BAN_SOURCE_ADDRESS, BEFORE_POST_PLUGIN_ADDRESS, AFTER_POST_PLUGIN_ADDRESS)`，同一交易内先产生 `GroupChatActivated`（以及 core `MemberMinted`），最后产生 `TokenActionGroupActivated`。`testT112` / `testT113` 通过「取最后一条日志」的 helper 间接锁定该顺序。

## 三、逐事件赋值链

### 3.1 `TokenActionGroupActivated`

```
event TokenActionGroupActivated(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed groupId,
    address operator
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `tokenAddress:135` | 根键；已过 `_checkLOVE20Token:118`（有代码且 `ILaunch.isLOVE20Token`） |
| `actionId` | 入参 `actionId:136` | 对象 id；`_checkExistingAction:142-147` 要求 `1 <= actionId <= proposalCount` |
| `groupId` | `_mintManagedGroup(...)` 返回值 `:127` | 由 `MemberNFT.mint` 返回；同一笔内写入两向映射与列表 |
| `operator` | `msg.sender:138` | 激活付款者；非 indexed，因为 3 个槽已给链路键（§6.3 纯链路事件规则） |

`_activateManagedAction:117-140` 的顺序：

1. `_checkLOVE20Token:118`、`_checkExistingAction:119`、`_checkNotManaged:120`。
2. 计算类型码 + payload（`symbol` 清洗、`symbol_actionId` 或仅 `actionId`），`_mintManagedGroup:127` 收费并 mint。
3. `_managedActionByGroupId[groupId] = ManagedAction(tokenAddress, actionId):129`。
4. `_groupIdByActionId[tokenAddress][actionId] = groupId:131`。
5. `_actionIdsByTokenAddress[tokenAddress].push(actionId):132`。
6. `_activateManagedGroup:133`：调用 `GroupChat.activateChat`，产生 `GroupChatActivated`。
7. `TokenActionGroupActivated:134`：最后发链路事件。

事件不携带初始 Chat 配置，由同笔 `GroupChatActivated` 承担；`TokenActionGroupActivated` 只表达托管链路与 actor。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `_managedActionByGroupId[groupId]` | `:129` | `TokenActionGroupActivated.tokenAddress` / `actionId` / `groupId` | 直接赋值；`AlreadyManaged` 挡住重复 |
| `_groupIdByActionId[tokenAddress][actionId]` | `:131` | 同上 | 反向映射 |
| `_actionIdsByTokenAddress[tokenAddress]`（append-only） | `:132` | `TokenActionGroupActivated` 顺序 | 按事件序即激活序；不是 `Uint256Set`，无 `GL-EV-2` 顺序问题 |
| `_mintNonce`（`ManagerBase`） | `_nextGroupName:134` | 无（§6.9 派生缓存） | 名称生成 nonce；见 `08` |

三个业务写入面全部有事件覆盖；`_mintNonce` 是 §6.9 登记的派生缓存。两向映射由同一条事件同时携带 token/action/group 覆盖。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `tokenAddress` 首字段；`gc.link` 槽位：根键 → `actionId` → `groupId` → actor |
| `gc.link` 槽位 / indexed（§6.1、§6.3） | 通过 | 3 个链路键 `tokenAddress` / `actionId` / `groupId` indexed；`operator` 入 data，符合纯链路事件规则 |
| 状态写入后 emit（§3.4.3） | 通过 | 两向映射、列表、`activateChat` 全部先于事件 |
| 依赖序（§3.4.5-6） | 通过 | `groupId` 来自 `MemberNFT.mint` 返回值（E2）；`GroupChatActivated` 先于链路事件；失败整笔回滚 |
| 批量逐条 emit（§3.4.1） | 通过 | 单 action 激活；无批量 |
| 零事实不发事件（§3.5） | 通过 | `ActionNotExist` / `AlreadyManaged` 在写前回滚，不写不发 |
| 共享事件类（§4.2） | 通过 | 声明在 `ITokenActionScopeManagerBaseEvents`；event-standards §4.2 已列 `TokenActionGroupActivated`（TokenActionMainManager、TokenActionGovManager）；baseline 两份声明 |
| 动态字段上限（§6.8） | 不适用 | 无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；事件声明在共享接口 |
| 测试断言（§8.1） | 通过 | `testT112` / `testT113` 通过 helper 断言 emitter、三个 topic 与 `operator` data；见 `TypedManagers.t.sol:594-609` |

## 六、发现

### 关联项

- `GL-EV-1`（P3，跨合约）：本事件类的 emitter 已经被 `TypedManagers.t.sol:603` 的 `assertEq(log.emitter, manager)` 覆盖；其余事件类仍缺。
- `GL-EV-2` 不适用：`_actionIdsByTokenAddress` 是 `uint256[]` append-only，页序可由事件序直接重建。

### 正面结论（不计入发现）

- `TokenActionGroupActivated` 是共享事件类的正确样板：同 schema、同语义、声明在共享 interface，两个 concrete Manager 都经 `_activateManagedAction` 发射，运行时 emitter 是各自 Manager。
- 事件在 `_mintManagedGroup`（外部 `MemberNFT.mint` 返回 `groupId`）之后发射，符合 E2；不预测、不重算 `groupId`。
- `_checkExistingAction` 在写前拒绝 `actionId == 0` 或超过 `proposalCount`，`_checkNotManaged` 拒绝重复托管；失败整笔回滚。
- 三个链路键占满 indexed 槽，`operator` 入 data，符合 §6.3 的纯链路事件规则；不为了 actor 地址牺牲链路键。
- 初始 Chat 配置由同笔 `GroupChatActivated` 承担，不在链路事件重复。
- `testT112` / `testT113` 对两个 Manager 都断言 emitter、三个 topic、`operator` data；`testT113B` 覆盖 `actionId == 0` 的失败。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `TokenActionGroupActivated` | `TypedManagers.t.sol:85-112`（T112，TokenActionGovManager） | helper 断言 emitter、`tokenAddress` / `actionId` / `groupId` 三个 topic、`operator` data |
| `TokenActionGroupActivated` | `TypedManagers.t.sol:149-207`（T113，TokenActionMainManager） | 同上；并核对 `actionByGroupId` / `groupIdByActionId` / `actions` |
| `TokenActionGroupActivated` | `TypedManagers.t.sol:594-609` | helper：`log.emitter == manager`、topic0、三个 topic、`operator` data |

## 八、复现

```bash
cd group-chat

python3 script/events/check-events.py
forge test --match-contract TypedManagersTest --match-test 'testT112|testT113'
# → 2 passed, 0 failed
```
