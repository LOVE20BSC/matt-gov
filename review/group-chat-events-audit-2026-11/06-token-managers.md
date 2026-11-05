# TokenScopeManager 事件赋值与发射审查

> 对象 `group-chat/src/managers/TokenScopeManagerBase.sol`（95 行，`abstract contract`）+ `TokenMainManager.sol`（50 行）+ `TokenGovManager.sol`（32 行）+ 其父级 `ManagerBase.sol`（185 行）、`TokenManagerBase.sol`（88 行，无事件，见 `08`）
> 声明 `group-chat/src/interfaces/managers/ITokenScopeManagerBase.sol`（`ITokenScopeManagerBaseEvents`，L6-12）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/06-manager.md`、`07-events-errors.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点（源码） | 1（`_activateToken:89`） |
| 运行时发射者 | 2（`TokenMainManager`、`TokenGovManager`） |
| 业务状态写入面 | 3（两向映射 + 列表）+ 1 个派生缓存（`_mintNonce`，见 `08`） |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0 |
| 放行 | 可放行；无独立发现，关联 `GL-EV-1`（emitter 已由共享 helper 覆盖）与 `GL-EV-2` 不适用（`_tokens` 是 append-only 数组） |

`TokenGroupActivated` 是 `TokenMainManager` 与 `TokenGovManager` 的共享事件类：同一 schema、同一语义、声明在共享接口 `ITokenScopeManagerBaseEvents`；两个运行时发射者分别是两个 concrete Manager，且都处于自身状态写入之后。事件把「token → group」的托管链路写入事件流，`groupId` 来自 `MemberNFT.mint` 的返回值，`operator` 是激活付款者。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `TokenGroupActivated` | `tokenAddress`, `groupId`, `operator` | `_activateToken:89` | `_checkLOVE20Token:76`、`_checkNotManaged:77`、`_mintManagedGroup:82`、`_tokenAddressByGroupId:84`、`_groupIdByTokenAddress:86`、`_tokens.push:87`、`_activateManagedGroup:88` | 返回 concrete `activate` |

`_activateManagedGroup:88` 调用 `GroupChat.activateChat(groupId, address(this), BAN_SOURCE_ADDRESS, BEFORE_POST_PLUGIN_ADDRESS, AFTER_POST_PLUGIN_ADDRESS)`，因此在同一交易内先产生 `GroupChatActivated`（以及 core `MemberMinted`），最后产生 `TokenGroupActivated`。`testT110` / `testT111` 通过「取最后一条日志」的 helper 间接锁定该顺序。

## 三、逐事件赋值链

### 3.1 `TokenGroupActivated`

```
event TokenGroupActivated(
    address indexed tokenAddress,
    uint256 indexed groupId,
    address indexed operator
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `tokenAddress:90` | 根键；已过 `_checkLOVE20Token:76`（有代码且 `ILaunch.isLOVE20Token`） |
| `groupId` | `_mintManagedGroup(...)` 返回值 `:82` | 由 `MemberNFT.mint` 返回；同一笔内写入 `_tokenAddressByGroupId:84` / `_groupIdByTokenAddress:86` / `_tokens:87` |
| `operator` | `msg.sender:92` | 激活付款者；`_mintManagedGroup:80` 从 `msg.sender` 收取铸造费（零费用不转账），不因付款获得 Chat 管理权 |

`_activateToken:75-94` 的顺序：

1. `_checkLOVE20Token:76`：token 有代码且是 LOVE20 token。
2. `_checkNotManaged:77`：`_groupIdByTokenAddress[tokenAddress] == 0`，重复激活回 `AlreadyManaged`。
3. `_managedGroupNameStem + _mintManagedGroup:80-82`：计算名称、从 `msg.sender` 收费、`MemberNFT.mint` 得到 `groupId`。
4. `_tokenAddressByGroupId:84`、`_groupIdByTokenAddress:86`、`_tokens.push:87`。
5. `_activateManagedGroup:88`：调用 `GroupChat.activateChat`，产生 `GroupChatActivated`。
6. `TokenGroupActivated:89`：最后发链路事件。

事件不携带初始 Chat 配置（`postingAllowed` / scope / ban / plugins）；这些由同笔 `GroupChatActivated` 携带。`TokenGroupActivated` 只表达「token ↔ group ↔ operator」的托管链路，符合 `06-manager.md` 的「名称只是展示标签，身份从链路事件与 getter 读取」。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `_tokenAddressByGroupId[groupId]` | `:84` | `TokenGroupActivated.tokenAddress` / `groupId` | 直接赋值；`AlreadyManaged` 挡住重复 |
| `_groupIdByTokenAddress[tokenAddress]` | `:86` | 同上 | 直接赋值；反向映射 |
| `_tokens`（append-only） | `:87` | `TokenGroupActivated` 顺序 | 按事件序即激活序；不是 `Uint256Set`，无 `GL-EV-2` 顺序问题 |
| `_mintNonce`（`ManagerBase`） | `_nextGroupName:134` | 无（§6.9 派生缓存） | 名称生成 nonce，不进入业务投影；见 `08` |

三个业务写入面全部有事件覆盖；`_mintNonce` 是 §6.9 登记的派生缓存。`_tokenAddressByGroupId` / `_groupIdByTokenAddress` 是互相反向的同一事实，事件同时携带 token 与 group，不需要额外事件。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `tokenAddress` 首字段；`gc.link` 槽位：根键 → `groupId` → `operator` |
| `gc.link` 槽位 / indexed（§6.1、§6.3） | 通过 | `tokenAddress` / `groupId` / `operator` 三个 indexed；纯链路事件的链路键优先 |
| 状态写入后 emit（§3.4.3） | 通过 | 两向映射、`_tokens`、`activateChat` 全部先于事件 |
| 依赖序（§3.4.5-6） | 通过 | `groupId` 来自 `MemberNFT.mint` 返回值（E2）；`GroupChatActivated` 先于链路事件；失败整笔回滚 |
| 批量逐条 emit（§3.4.1） | 通过 | 单 token 激活；无批量 |
| 零事实不发事件（§3.5） | 通过 | 重复激活直接回 `AlreadyManaged`，不写不发 |
| 共享事件类（§4.2） | 通过 | 声明在 `ITokenScopeManagerBaseEvents`；event-standards §4.2 已列 `TokenGroupActivated`（TokenMainManager、TokenGovManager）；baseline 两份声明 |
| 动态字段上限（§6.8） | 不适用 | 无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；事件声明在共享接口 |
| 测试断言（§8.1） | 通过 | `testT110` / `testT111` 通过 helper 断言 emitter、三个 topic 与空 data；见 `TypedManagers.t.sol:578-592` |

## 六、发现

### 关联项

- `GL-EV-1`（P3，跨合约）：本事件类的 emitter 已经被 `TypedManagers.t.sol:586` 的 `assertEq(log.emitter, manager)` 覆盖，是 group-chat 仓内 3 个带 emitter 断言的事件类之一；其余事件类仍缺。
- `GL-EV-2` 不适用：`_tokens` 是 `address[]` append-only，页序可由事件序直接重建，不使用 `Uint256Set` 的 swap-and-pop。

### 正面结论（不计入发现）

- `TokenGroupActivated` 是共享事件类的正确样板：同 schema、同语义、声明在共享 interface，两个 concrete Manager 都经 `_activateToken` 发射，运行时 emitter 是各自 Manager。
- 事件在 `_mintManagedGroup`（外部 `MemberNFT.mint` 返回 `groupId`）之后发射，符合 E2「字段只能由外部调用返回确定」；不预测、不重算 `groupId`。
- 事件在两向映射与 `_tokens` 写入之后发射，`AlreadyManaged` 挡住重复激活；失败整笔回滚，不会出现「已映射未发事件」或「已发事件未映射」。
- 初始 Chat 配置不在本事件重复，由同笔 `GroupChatActivated` 承担，避免两个事件表达同一配置事实。
- `testT110` / `testT111` 对两个 Manager 都断言了 emitter、三个 topic、空 data 与 Manager 地址；`testT115` / `testT117` 等覆盖命名，不涉及事件。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `TokenGroupActivated` | `TypedManagers.t.sol:22-57`（T110，TokenMainManager） | helper 断言 emitter、`tokenAddress` / `groupId` / `operator` 三个 topic、空 data |
| `TokenGroupActivated` | `TypedManagers.t.sol:59-83`（T111，TokenGovManager） | 同上；并核对 `tokenAddressByGroupId` / `groupIdByTokenAddress` / `tokens` |
| `TokenGroupActivated` | `TypedManagers.t.sol:578-592` | helper：`log.emitter == manager`、topic0、三个 topic、空 data |

## 八、复现

```bash
cd group-chat

python3 script/events/check-events.py
forge test --match-contract TypedManagersTest --match-test 'testT110|testT111'
# → 2 passed, 0 failed
```
