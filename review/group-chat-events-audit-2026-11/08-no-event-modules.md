# 无事件模块审查

> 对象 `group-chat/src/sources/ban/AdminBanSource.sol`（18 行）、`src/sources/scope/GroupJoinScopeSource.sol`（24 行）、`src/sources/scope/GroupMemberScope.sol`（18 行）、`src/managers/ManagerBase.sol`（185 行）、`src/managers/TokenManagerBase.sol`（88 行）及全部接口文件
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/00–08`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 0 |
| 发射点 | 0 |
| 业务状态写入面 | 0（`ManagerBase._mintNonce` 为派生缓存；`GroupChat._reentrancyStatus` 在 `01` 已计入瞬态锁） |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0 |
| 放行 | 可放行；无事件模块没有「写了不报」的业务状态 |

本报告覆盖 3 个只读 source、2 个无事件基类，以及 `src/interfaces/` 下的接口文件。它们没有协议事件，也没有需要事件覆盖的业务状态写入；`ManagerBase` 的 `_mintNonce` 是 §6.9 明确允许的派生缓存。

## 二、逐模块

### 2.1 `AdminBanSource`

- 对象 `src/sources/ban/AdminBanSource.sol`（18 行），`contract`；接口 `IAdminBanSource`（`isBanned`）。
- 状态：仅 `GROUP_BAN_LIST_ADDRESS` immutable（构造），无可变业务状态。
- 逻辑：`isBanned(groupId, senderId)` 直接读 `IGroupChatBanList.isSenderIdBanned`（`:15-17`）。
- 事件：无。黑名单事实由 `GroupChatBanList.SenderBanChanged` 承载，`AdminBanSource` 只是读取适配器，不重复发射。
- 结论：0 事件合理；无状态写入。

### 2.2 `GroupJoinScopeSource`

- 对象 `src/sources/scope/GroupJoinScopeSource.sol`（24 行），`contract`；接口 `IGroupJoinScopeSource`（`isSenderAllowed`）。
- 状态：仅 `GROUP_MEMBER_ADDRESS`、`GROUP_ACTION_EXECUTOR_ADDRESS` immutable（构造）。
- 逻辑：先查 `IGroupMember.isMemberId`，再查 `IGroupActionIndexes.isGroupMember`（`:18-23`）。
- 事件：无。成员事实由 `GroupMember.MemberStatusChanged` / GroupAction 索引事件承载；本合约只做组合读取。
- 结论：0 事件合理；无状态写入。

### 2.3 `GroupMemberScope`

- 对象 `src/sources/scope/GroupMemberScope.sol`（18 行），`contract`；接口 `IGroupMemberScope`（`isSenderAllowed`）。
- 状态：仅 `GROUP_MEMBER_ADDRESS` immutable（构造）。
- 逻辑：直接返回 `IGroupMember.isMemberId`（`:15-17`）。
- 事件：无。成员事实由 `GroupMember.MemberStatusChanged` 承载。
- 结论：0 事件合理；无状态写入。

### 2.4 `ManagerBase`

- 对象 `src/managers/ManagerBase.sol`（185 行），`abstract contract`；接口 `IManagerBase`。
- 状态：
  - 6 个 immutable：`GROUP_CHAT_ADDRESS`、`GROUP_ADDRESS`、`MAX_NAME_LENGTH`、`BAN_SOURCE_ADDRESS`、`BEFORE_POST_PLUGIN_ADDRESS`、`AFTER_POST_PLUGIN_ADDRESS`（构造，§3.2 豁免）。
  - `_mintNonce`（`:32`）：每次 `_nextGroupName` 尝试递增（`:133-135`），用于名称随机串消歧；属于 §6.9 的 `mint nonce` 派生缓存，不进入事件。群名事实由 core `MemberMinted` 承载，托管链路由 concrete Manager 的 `TokenGroupActivated` / `TokenActionGroupActivated` 承载。
  - `onERC721Received`（`:58-67`）：只校验 `msg.sender == GROUP_ADDRESS && from == address(0)`，无状态写入、无事件；这是安全接收回调，不是业务事实。
- 事件：无。`ManagerBase` 不直接发射事件；`_activateManagedGroup` 调 `GroupChat.activateChat`，由 GroupChat 发 `GroupChatActivated`；concrete Manager 发链路事件。
- 结论：0 事件合理；`_mintNonce` 是派生缓存，其余状态都是 immutable。

### 2.5 `TokenManagerBase`

- 对象 `src/managers/TokenManagerBase.sol`（88 行），`abstract contract`；接口通过 `TokenScopeManagerBase` / `TokenActionScopeManagerBase` 暴露。
- 状态：`STAKE_ADDRESS`、`LAUNCH_ADDRESS`、`PHASE_ADDRESS` 三个 immutable（构造，`:16-32`）。
- 逻辑：`_checkLOVE20Token` / `currentPhase` / symbol 清洗，只读。
- 事件：无。token / phase 事实由 core / action 事件承载，`TokenManagerBase` 不写业务状态。
- 结论：0 事件合理。

### 2.6 接口与插件/源接口

- `src/interfaces/IGroupChat.sol`、`IGroupAdmin.sol`、`IGroupMember.sol`、`IGroupChatBanList.sol`、`managers/*.sol`、`sources/*.sol`、`plugins/*.sol` 均只声明事件/错误/函数，不发射事件。
- `IAfterPostPlugin` / `IBeforePostPlugin` 是插件接口，插件实现不在本仓库生产合约范围内；`BeforePostPlugin` / `AfterPostPlugin` 的事件由 GroupChat 发射。
- `IPostBanSource` / `IPostScopeSource` / `IAdminBanSource` / `IBanVoteWeightSource` 只读接口，无事件。

## 三、状态覆盖核对

| 模块 | 可变业务状态 | 承载事件/推导 | 结论 |
| --- | --- | --- | --- |
| `AdminBanSource` | 无 | 读 `GroupChatBanList` 的 `SenderBanChanged` 结果 | 无缺口 |
| `GroupJoinScopeSource` | 无 | 读 `GroupMember` / GroupAction 索引事件结果 | 无缺口 |
| `GroupMemberScope` | 无 | 读 `GroupMember.MemberStatusChanged` 结果 | 无缺口 |
| `ManagerBase` | `_mintNonce` | §6.9 派生缓存（mint nonce）；名称事实由 core `MemberMinted` | 无缺口 |
| `TokenManagerBase` | 无（immutable） | 构造/部署清单 | 无缺口 |
| 接口文件 | 无 | 不适用 | 无缺口 |

## 四、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 「所有影响业务对象状态的可变写入必须有事件覆盖」（§3.2） | 通过 | 三个 source / 两个基类无可变业务状态；`_mintNonce` 是派生缓存 |
| 派生缓存登记（§6.9） | 通过 | event-standards §6.9 已列 `mint nonce`；`_reentrancyStatus` 在 `01` 按瞬态锁处理 |
| 禁止软失败/调试事件（§3.5） | 通过 | 0 事件，不存在软失败/调试事件 |
| 事件声明在发射者 interface（§4.1） | 不适用 | 无发射者 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 扫描 `src/` 无违例 |
| 不可变部署参数不进事件（§3.2） | 通过 | 三个 source 与两个基类的依赖地址都是 immutable/构造 |

## 五、发现

无独立发现。

### 正面结论（不计入发现）

- 三个 source 都是只读适配器，没有把「读取结果」误写成事件；黑名单/成员/归属事实仍由写入口的事件承载，避免重复表达同一事实。
- `ManagerBase` 只提供命名、付款、mint、激活和 ERC721 接收的通用机制，不维护类型清单、不发射事件；类型码和 payload 由各 concrete Manager 自己定义，事件由 concrete Manager 发射。
- `_mintNonce` 是唯一可变字段，且是 §6.9 已登记的派生缓存；群名的最终事实由 core `MemberMinted` 承载，托管链路由 `TokenGroupActivated` / `TokenActionGroupActivated` 承载。
- `onERC721Received` 只接受协议 NFT 合约、`from == 0` 的铸造回调，无状态写入；普通安全转入被拒绝，不产生事件。
- `TokenManagerBase` 的三个依赖地址都是 immutable，构造后不可改；不需要事件。

## 六、复现

```bash
cd group-chat

python3 script/events/check-events.py
# → event manifest OK: 18 events; families OK; declaration style OK; emit style OK; emit keys OK

grep -rn "emit " src/sources/ src/managers/ManagerBase.sol src/managers/TokenManagerBase.sol
# → 无输出
forge test --match-contract GroupJoinScopeSourceTest
forge test --match-contract GroupMemberScopeTest
forge test --match-contract AdminBanSourceTest
# → 4 + 6 + 14 passed, 0 failed
```
