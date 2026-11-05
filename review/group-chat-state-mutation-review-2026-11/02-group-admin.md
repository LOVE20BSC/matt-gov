# GroupAdmin · 状态变量变更审查

> `group-chat/src/GroupAdmin.sol`，201 行，基线 `group-chat@e982df8`。
> 管理员是否“有效”不只看集合成员，还要看添加时保存的两份 owner 快照；这是本合约全部状态复杂度的来源。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `GROUP_ADDRESS` | `address immutable` | MemberNFT 地址 | 构造 `:28` |
| 2 | `MAX_ADMIN_IDS` | `uint256 immutable` | 每群管理员数量上限 | 构造 `:29` |
| 3 | `_adminState[groupId].adminIds` | `Uint256Set.Storage` | 已登记 adminId 集合（含失效） | `_addAdminId:91`、`_removeAdminId:117` |
| 4 | `_adminState[groupId].groupOwnerSnapshots[adminId]` | `mapping(uint256 => address)` | 添加时群 owner 地址 | `_addAdminId:87`、`_removeAdminId:123`（delete） |
| 5 | `_adminState[groupId].adminOwnerSnapshots[adminId]` | `mapping(uint256 => address)` | 添加时 admin NFT owner 地址 | `_addAdminId:88`、`_removeAdminId:124`（delete） |

`AdminState` 以 `groupId` 为键；同一 GroupAdmin 实例内不同群互不影响。`Uint256Set` 是 swap-and-pop 集合，`adminIds` 的枚举顺序不承诺插入序。

## 2. 逐变量变更逻辑

### 2.1 `_adminState[groupId].adminIds`

#### `addAdmins`（`:32-44`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | 修饰器 `:184-193` | `onlyGroupOwner(groupId, operatorId)` | `operatorId == groupId` 且 `msg.sender == MemberNFT.ownerOf(groupId)`；群不存在回 `GroupNotExist` |
| 2 | `:36` | `_checkAdminIdList` | 每个 adminId 的 NFT 必须存在（`ownerOf`），数组内不得重复 |
| 3 | `:37` | `_checkAdminIdsLimit` | 当前集合大小 + 数组内**尚未登记**的数量 ≤ `MAX_ADMIN_IDS` |
| 4 | `:40` | `groupOwnerSnapshot = _groupOwnerOrRevert(groupId)` | 与修饰器读取同一 owner；无外部状态变更调用 |
| 5 | `:41-43` | 逐项 `_addAdminId` | 同笔循环，任一项 revert 整批回滚 |

#### `_addAdminId`（`:74-109`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:81` | `adminOwnerSnapshot = IMemberNFT(GROUP_ADDRESS).ownerOf(adminId)` | admin NFT 当前 owner；缺失会 revert（前面已校验） |
| 2 | `:82-83` | 读两份旧快照 | — |
| 3 | `:84-85` | `snapshotChanged = 旧群 owner 快照 != 新群 owner 快照 || 旧 admin owner 快照 != 新 admin owner 快照` | — |
| 4 | `:86-89` | 若 `snapshotChanged`，写两份新快照 | 先写快照，后加集合 |
| 5 | `:91` | `added = adminIds.add(adminId)` | 返回 false 表示已在集合 |
| 6 | `:93-95` | 若 `!added && !snapshotChanged`，直接 return | 完全幂等，不写不发事件 |
| 7 | `:97-108` | `AdminChanged`，`listed: true`，`prevListed: !added` | 新加或“快照刷新”都发事件 |

`_addAdminId` 的两份快照与集合成员在同一笔交易内写入；不存在“集合已加、快照未写”的对外中间态。

#### `removeAdmins`（`:46-57`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | 修饰器 | `onlyGroupOwner` | 只有群 owner 可撤销管理员 |
| 2 | `:50` | `_checkAdminIdList` | 每个 adminId 的 NFT 必须存在，数组内不得重复 |
| 3 | `:53-56` | 逐项 `_removeAdminId` | — |

#### `_removeAdminId`（`:111-137`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:117` | `if (!adminIds.remove(adminId)) return;` | 不在集合则完全幂等，不删快照、不发事件 |
| 2 | `:121-122` | 读旧快照（仅用于事件） | — |
| 3 | `:123-124` | `delete` 两份快照 | 与集合删除同笔 |
| 4 | `:125-136` | `AdminChanged`，`listed: false`，新快照为零 | 事件带旧快照 |

### 2.2 `groupOwnerSnapshots` / `adminOwnerSnapshots`

- 两份快照只在 `_addAdminId` 写入、在 `_removeAdminId` 删除；`isAdminId` / `adminIds` 只读。
- 快照语义是“最近一次 add 时的 owner 地址”，不是“当前 owner”；因此 NFT 转移后管理员立即失效，转回原地址后无需重新 add 即恢复（`testT129E_adminsInvalidateAndRestoreAcrossGroupOwnerTransfer`、`testT129F_reapplyingSameAdminIdsUpdatesSnapshots`）。
- 对已登记 admin 再次 `addAdmins` 且任一快照变化时，会**刷新**两份快照并发 `AdminChanged(listed=true, prevListed=true)`；这既能把管理员重新绑定到 admin NFT 的新持有人，也能把管理员从旧 owner 失效状态恢复。
- `_isEffectiveAdminId`（`:172-182`）要求两份快照均非零，且当前群 owner / 当前 admin owner 分别等于快照；这是 `isAdminId` 的唯一判据。

## 3. 写入顺序与不可分割性

```text
onlyGroupOwner
  -> 数组校验（存在性 + 去重）
  -> 数量上限
  -> 逐项：读当前 admin owner -> 计算 snapshotChanged
        -> 写两份快照（若有变化）
        -> 集合 add
        -> 事件
```

- 外部调用只有 `MemberNFT.ownerOf`（view）与 `MemberOwner.ownerOrZero`（内部 view）；没有状态变更回调，因此不需要重入锁。
- 循环内任一项失败（例如后续 adminId 不存在）都会回滚前面所有 add/快照/事件，批量语义是原子的。
- `MAX_ADMIN_IDS` 只在 `addAdmins` 检查；`removeAdmins` 不受上限影响。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `GAD-01` | Info | 失效管理员仍占用 `MAX_ADMIN_IDS` 名额：群 owner 转移后旧管理员全部失效，但集合大小不变；新 owner 必须先撤销旧条目才能添加新管理员 | E1 |
| `GAD-02` | Info | 对已登记 admin 再次 `addAdmins` 会刷新快照，可能把管理员权限转交给 admin NFT 的当前持有人；事件用 `prevListed` / 旧快照区分“新增”与“刷新” | E1 |
| `GAD-03` | Info | `removeAdmins` 仍要求每个 adminId 的 NFT 存在；当前 MemberNFT 无 burn 入口，所以不构成阻塞，但未来若引入 burn 会出现“无法撤销已烧毁管理员” | E1 |

逐条说明：

- **`GAD-01`**：`_checkAdminIdsLimit` 用 `state.adminIds.count()`，不区分 `_isEffectiveAdminId`。群 NFT 转移后，所有旧管理员的 `groupOwnerSnapshots` 失配，`isAdminId` 为 false，但 `adminIds` 仍计入上限。新 owner 可通过 `adminIds(groupId)` 枚举并 `removeAdmins` 清理；这是可恢复的运营成本，不是状态不一致。
- **`GAD-02`**：刷新路径是有意的“重新绑定”：`_addAdminId` 在 `snapshotChanged` 时写新 admin owner 快照。群 owner 本来就有权任命任意 NFT 持有人为管理员，所以不是越权；但读事件的人必须看 `prevListed` 与旧快照，不能把 `listed=true` 一律当成新增。
- **`GAD-03`**：`_checkAdminIdList` 在 add 和 remove 都调用 `ownerOf`。MemberNFT 没有 burn，管理员 ID 永久存在；若未来加入 burn，撤销路径会回滚在 `ERC721NonexistentToken`。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 快照刷新是否会让旧管理员在群 owner 转移后继续有效 | 不会；`_isEffectiveAdminId` 每次都对比当前群 owner 与当前 admin owner，快照只是“当时地址” |
| 群 owner 转回原地址后管理员自动恢复是否越权 | 是规格明确的“转回恢复”语义；新 owner 若不希望恢复，可在持有期间撤销 |
| 批量 add 中前面的项已写入、后面项失败是否留下半完成 | 不会；EVM 整笔回滚 |
| `adminIds` 枚举顺序是否稳定 | 不承诺；`Uint256Set` swap-and-pop，`adminIds` 的主要用途是读取当前集合与有效性，不用于顺序协议 |
| 管理员能否自己任命管理员 | 不能；`addAdmins` / `removeAdmins` 只有群 owner（`operatorId == groupId`），见 `testT129D` |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| A1 | `adminIds` 无重复；`groupOwnerSnapshots` / `adminOwnerSnapshots` 非零当且仅当 adminId 在集合中 | ✅ | add 先写快照再加集合；remove 先删集合再删快照；无其他写入 |
| A2 | `isAdminId(g, a) == true` 蕴含两份快照均非零且当前 owner 与快照一致 | ✅ | `_isEffectiveAdminId` 定义 |
| A3 | 集合大小 ≤ `MAX_ADMIN_IDS` | ✅ | `_checkAdminIdsLimit` 在任何 add 之前 |
| A4 | 每次实际集合变化都伴随 `AdminChanged`；无变化不发事件 | ✅ | `_addAdminId` 的 `!added && !snapshotChanged` 早退；`_removeAdminId` 的 remove 失败早退 |
| A5 | 批量 add/remove 原子 | ✅ | 单笔循环，无 try/catch，任一项 revert 整批回滚 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| `MAX_ADMIN_IDS = 0` | 部署脚本是否允许 0、以及全零上限的运营含义未在合约层约束 |
| 管理员 NFT burn | 当前 MemberNFT 无 burn，未覆盖未来引入 burn 后的撤销路径 |
| 群 NFT 转移后旧管理员集合的清理成本 | 测试覆盖失效/恢复，未量化“满上限 + 全失效”时的清理步骤 |

### 4.5 结论

未发现 Critical / High / Medium。集合、两份快照、事件三者在同一笔交易内成对变化；所有写入口只有群 owner，且 `operatorId` 必须等于 `groupId`。3 条 Info 分别对应“失效名额占用”“快照刷新语义”“未来 burn 的撤销前置条件”，都不破坏当前状态一致性。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `GAD-01` | A（文档）：上限按已登记集合计，失效条目需显式撤销 | `05-chat-types.md`「成员与管理员」 |
| `GAD-02` | 登记：重复添加刷新快照，事件 `listed = true, prevListed = true` | `05-chat-types.md`「成员与管理员」 |
| `GAD-03` | 登记：删除要求 NFT 存在；未来 burn 为前置条件（同 `E-GA-02`） | `05-chat-types.md`「成员与管理员」、`07-events-errors.md`「错误」 |
