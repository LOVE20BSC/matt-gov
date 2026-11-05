# `group-chat/GroupAdmin.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/01-lifecycle.md`、`05-chat-types.md`、`07-events-errors.md`。
> 范围：`src/GroupAdmin.sol`（201 行）+ `src/interfaces/IGroupAdmin.sol` 的 `IGroupAdminErrors`。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 3 条（0 Low / 3 Info）。

## 1. 结论

- 4 个错误声明 / 4 个 revert 站点；实现文件零声明，无裸 `require`/`revert`/`assert`。
- `addAdmins` 先完成整批存在性与重复校验、再校验数量上限、最后才写入；`removeAdmins` 逐元素校验后删除。两入口都原子。
- 错误载荷符合 §4：`AdminIdsLimitExceeded` 为 `groupId + 预计总数 + maxCount`，`DuplicateMemberId` 定位失败元素。
- 无 Low；3 条 Info 均为规格登记缺口：两入口的校验顺序与错误集合、删除路径的严格模式、空批次 no-op 语义。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 4 |
| revert 站点 | 4 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 0 / 3 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotGroupOperator` | `NotGroupOperator(uint256,uint256)` | `0x20e5d297` | 1 | 保留（复合鉴权，同 [GroupChat](GroupChat.md) E-GC-05） |
| `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` | 1 | 保留 |
| `DuplicateMemberId` | `DuplicateMemberId(uint256)` | `0x1a494813` | 1 | 保留 |
| `AdminIdsLimitExceeded` | `AdminIdsLimitExceeded(uint256,uint256,uint256)` | `0x2ffd6226` | 1 | 保留 |

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `GroupNotExist(groupId)` | `:198` | `_groupOwnerOrRevert` | `owner == address(0)`；`owner ← MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId)` | `groupId ← 入参` | `addAdmins`、`removeAdmins`（经 `onlyGroupOwner`） |
| 2 | `NotGroupOperator(groupId, operatorId)` | `:190` | `onlyGroupOwner` | `operatorId != groupId \|\| msg.sender != owner`；`owner ← _groupOwnerOrRevert(groupId)` | `groupId ← 入参`；`operatorId ← 入参` | `addAdmins`、`removeAdmins` |
| 3 | `DuplicateMemberId(memberId)` | `:144` | `_checkAdminIdList` | `adminIdList[i] == adminIdList[j]`（`j < i`） | `memberId ← adminIdList[i]` | `addAdmins`、`removeAdmins` |
| 4 | `AdminIdsLimitExceeded(groupId, count, maxCount)` | `:168` | `_checkAdminIdsLimit` | `count > MAX_ADMIN_IDS` | `groupId ← 入参`；`count ← state.adminIds.count() + _newAdminIdsCount(state, adminIdList)`；`maxCount ← MAX_ADMIN_IDS` | `addAdmins` |

### 3.2 赋值与发送逻辑

#### `addAdmins(groupId, operatorId, adminIdList)`

```text
1. 鉴权    onlyGroupOwner：群存在 → 否则 GroupNotExist(groupId)
                          operatorId != groupId 或 msg.sender != owner → NotGroupOperator(groupId, operatorId)
2. 参数    _checkAdminIdList：逐元素 ownerOf(id)（缺失 → ERC721NonexistentToken）
                             逐元素查重 → DuplicateMemberId(id)
3. 上限    _checkAdminIdsLimit：state.adminIds.count() + 新增唯一数 > MAX_ADMIN_IDS
                             → AdminIdsLimitExceeded(groupId, count, MAX_ADMIN_IDS)
4. 写入    _addAdminId：更新双快照、加入集合、按需发 AdminChanged
```

- `count` 是“本次添加完成后的预计总数”，不是当前值；`_newAdminIdsCount` 只计尚未列出的 ID（`:150-160`）。
- 整批校验先于写入，任一步失败整笔回滚；同一 `adminId` 在 `_addAdminId` 内再次 `ownerOf`（`:81`），与第 2 步重复，只影响 gas。

#### `removeAdmins(groupId, operatorId, adminIdList)`

```text
1. 鉴权    onlyGroupOwner：同上
2. 参数    _checkAdminIdList：逐元素 ownerOf(id)、查重
3. 删除    逐元素 remove；不存在于集合 → no-op；存在 → 删快照、发 AdminChanged(listed=false)
```

- `removeAdmins` 不检查数量上限（上限只在添加侧生效）。
- 删除路径也要求 NFT 存在：`removeAdmins(groupId, operatorId, [neverMintedId])` 回 `ERC721NonexistentToken` 而非 no-op。这是 07-events-errors:27 的严格模式口径（缺失成员角色 ID 回标准错误），但 05-chat-types:59 只写“行为不变”，没有把“删除也是严格模式”写进规格（E-GA-02）。
- 由于 `MemberNFT` 无销毁入口，已加入名单的 ID 永远能通过存在性校验，不存在“烧毁后无法清理”的路径。

### 3.3 已核对项

- `_isEffectiveAdminId` 要求群 owner 快照与 admin owner 快照同时命中（`:172-182`）；这是读面语义，不产生错误。
- 重复添加同一 admin：`_addAdminId` 在“已列出且快照未变”时直接返回，不发事件（Set 幂等，§6）；快照变化时发 `AdminChanged(listed=true, prevListed=true)`，与 01-lifecycle:30“转移失效/转回恢复”一致。
- `AdminIdsLimitExceeded` 的 `count` 包含已失效但仍列出的 admin；达到上限后需先 `removeAdmins` 才能继续添加，属 Set 语义，不是错误缺陷。
- 测试：`test/GroupAdmin.t.sol` 对 4 个错误均有 `expectRevert` + 载荷断言（含 `AdminIdsLimitExceeded` 的三参数）。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-GA-01 | Info | `src/GroupAdmin.sol:32-57` | 规格未按 §5 给 `addAdmins` / `removeAdmins` 写“校验顺序 + 错误集合”。07-events-errors 只列模块错误清单，05-chat-types:60 只写“旧批量增删行为不变”。 | §5（每个外部写入口写明顺序与错误集合） | 已登记：05-chat-types:60「`addAdmins` 的顺序为鉴权 → 群存在性 → 逐元素 NFT 存在性 → 逐元素重复 → 上限 → 写入」 |
| E-GA-02 | Info | `src/GroupAdmin.sol:139-148` | 删除路径同样要求 `ownerOf` 成功：对从未铸造的 ID 回 `ERC721NonexistentToken` 而非 no-op。§6 允许严格模式，但要求“必须在规格写明”；当前只有 07 的通用身份规则，没有点明删除入口。 | §6（批量删除默认 no-op；严格模式须写明） | 已由 state 卷 `GAD-03` 关闭：05-chat-types:60「`removeAdmins` / `removeMemberIds` 要求对应 NFT 当前存在」 |
| E-GA-03 | Info | `src/GroupAdmin.sol:32-44` | 空 `adminIdList` 是合法 no-op（校验通过、不发事件），规格未写；与 Mint 空批次同类。 | §6（no-op 语义） | 已登记：05-chat-types:60「空批次为 no-op」；不允许新增参数错误来禁止空批次 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `MemberNFT.ownerOf` | `ERC721NonexistentToken(memberId)` | `addAdmins`、`removeAdmins`（`_checkAdminIdList`） | 07-events-errors:27；08-testing:9 |
| `IGroupAdmin` 自身 | 无 | — | — |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test --match-path test/GroupAdmin.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/IGroupAdmin.sol`。
