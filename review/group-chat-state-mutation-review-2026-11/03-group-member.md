# GroupMember · 状态变量变更审查

> `group-chat/src/GroupMember.sol`，115 行，基线 `group-chat@e982df8`。
> 本合约只有一本成员名单；权限判定内联复用 `GroupAdmin.isAdminId`，没有第二份本地快照。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `GROUP_ADMIN_ADDRESS` | `address immutable` | 管理员快照来源 | 构造 `:25` |
| 2 | `GROUP_ADDRESS` | `address immutable` | MemberNFT 地址 | 构造 `:26` |
| 3 | `_memberState[groupId].memberIds` | `Uint256Set.Storage` | 群成员 ID 集合 | `_setMemberIds:79`（add / remove） |

`Uint256Set` 是 swap-and-pop 集合，`memberIds` 分页只承诺当前存储顺序，不承诺插入序。

## 2. 逐变量变更逻辑

### 2.1 `addMemberIds` / `removeMemberIds`（`:29-41`）

两个入口都只做一件事：把 `listed` 布尔传给 `_setMemberIds`。

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | 修饰器 `:92-101` | `onlyOperator(groupId, operatorId)` | 群不存在回 `GroupNotExist`；`operatorId == groupId` 要求调用者是群 owner；否则要求调用者是 operatorId 的 NFT owner 且 `GroupAdmin.isAdminId(groupId, operatorId)` |
| 2 | `:71-78` | 逐项 `IMemberNFT(GROUP_ADDRESS).ownerOf(memberId)` + 数组内去重 | 缺失 NFT 回 `ERC721NonexistentToken`；重复回 `DuplicateMemberId` |
| 3 | `:79` | `memberIds.add(memberId)` 或 `remove(memberId)` | 集合返回是否实际变化 |
| 4 | `:80-88` | 仅当 `changed` 时发 `MemberStatusChanged` | 幂等操作不发事件 |

### 2.2 `_memberState[groupId].memberIds`

- 唯一写入点是 `_setMemberIds:79`；没有删除整个群、迁移成员或批量覆盖的入口。
- 每个 ID 的 add/remove 与事件在同一个循环迭代内；后续项失败会回滚前面所有变更，批量是原子的。
- 成员资格只按 `groupId + memberId` 保存，不按 owner 地址保存：成员 NFT 转移后，新持有人继承该 ID 的成员资格；ID 本身不会因转移自动移出名单。
- 群 NFT 转移不会清空名单；新群 owner 继承现有成员集合，可继续增删。

## 3. 写入顺序与不可分割性

```text
onlyOperator（群存在 -> 调用者身份）
  -> 逐项：ownerOf 存在性 -> 数组内去重
        -> 集合 add/remove
        -> changed 时发事件
```

外部调用只有 `IMemberNFT.ownerOf` 与 `IGroupAdmin.isAdminId`（均为 view），没有状态变更回调；因此不需要重入锁。循环内任一项失败都会整批回滚。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `GMB-01` | Info | 批量长度无协议上限，重复检查是 O(n²)；owner/admin 可以自选批次，gas 由调用者承担 | E1 |
| `GMB-02` | Info | `removeMemberIds` 同样要求目标 NFT 存在；当前 MemberNFT 无 burn，故不阻塞，未来引入 burn 会留下“无法移除已烧毁 ID”的路径 | E1 |
| `GMB-03` | Info | 成员集合不随群 NFT 转移清空，也不随成员 NFT 转移改变；这是 ID 身份模型的直接结果，不是状态漂移 | E1 |

逐条说明：

- **`GMB-01`**：`_setMemberIds` 对每个 `i` 都回扫 `0..i-1` 查重，最坏 O(n²) 次比较；`ownerOf` 也是每项一次外部 view。没有上限，但写入口只有群 owner/有效 admin，且失败整批回滚，不构成第三方 DoS。
- **`GMB-02`**：`remove` 前也执行 `ownerOf`；MemberNFT 目前没有 burn（见 `MemberNFT` 审计 `NFT-04`），所以所有历史 ID 都可移除。若未来加入 burn，移除已烧毁 ID 会在 `ownerOf` 处回滚。
- **`GMB-03`**：名单以 `groupId + memberId` 为键，不存 owner。群 NFT 转移后 `onlyOperator` 的 owner 判定切换到新 owner，但名单内容不变；成员 NFT 转移后新持有人继承 ID。这是规格 `05-chat-types.md` 的 ID 身份模型，不是遗漏快照。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 管理员能否把任意 MemberNFT 加入名单 | 能；`onlyOperator` 只校验操作者身份，`ownerOf(memberId)` 只要求目标 NFT 存在。成员资格是群管理动作，不要求目标同意 |
| 群 NFT 转移后旧管理员还能否改名单 | 不能；`GroupAdmin.isAdminId` 的群 owner 快照失配，`onlyOperator` 回 `NotGroupOperator` |
| 重复 add / remove 是否会产生事件 | 不会；`changed == false` 时跳过事件，测试覆盖幂等语义 |
| 批量中重复 ID 是否只回滚重复项 | 不会；`DuplicateMemberId` 让整批回滚 |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| M1 | `memberIds` 无重复 | ✅ | `Uint256Set.add` 与数组去重双重保证 |
| M2 | 每个在集合中的 ID 都曾是存在的 MemberNFT | ✅ | add 前 `ownerOf`；MemberNFT 当前无 burn |
| M3 | 每次实际集合变化都伴随 `MemberStatusChanged`；无变化不发事件 | ✅ | `changed` 判定 |
| M4 | 只有群 owner 或“当前有效的 admin”能改名单 | ✅ | `_isOperator` + `GroupAdmin.isAdminId` |
| M5 | 批量操作原子 | ✅ | 单笔循环，无 try/catch |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 大批量 gas 上界 | 没有协议上限，测试未覆盖接近区块 gas 上限的批次 |
| 成员 NFT burn | 当前无 burn，未覆盖未来 burn 后的移除路径 |

### 4.5 结论

未发现 Critical / High / Medium。状态只有一本 `Uint256Set`，写入点唯一；集合变化与事件同笔，权限判定完全依赖 `GroupAdmin` 的当前快照。3 条 Info 均为批量成本、未来 burn 与 ID 身份模型的边界说明。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `GMB-01` | 登记：批量无上限、O(n²)、整批回滚 | `05-chat-types.md`「成员与管理员」 |
| `GMB-02` | 登记：删除要求 NFT 存在；未来 burn 为前置条件（同 `E-GM-02`） | `05-chat-types.md`「成员与管理员」 |
| `GMB-03` | 登记：名单以 `groupId + memberId` 为键，不随 NFT 转移清空 | `05-chat-types.md`「成员与管理员」 |
