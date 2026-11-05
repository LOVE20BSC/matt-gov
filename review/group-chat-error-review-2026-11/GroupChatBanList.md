# `group-chat/GroupChatBanList.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/01-lifecycle.md`、`05-chat-types.md`、`07-events-errors.md`。
> 范围：`src/GroupChatBanList.sol`（169 行）+ `src/interfaces/IGroupChatBanList.sol` 的 `IGroupChatBanListErrors`。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 4 条（0 Low / 4 Info）。

## 1. 结论

- 4 个错误声明 / 4 个 revert 站点；实现零声明，无裸 `require`/`revert`/`assert`。
- `banBySenderIds` / `unbanBySenderIds` 共用 `_setSenderIdBanTargets`：逐元素校验 0 值与重复后执行 Set 增删；已封禁再加、未封禁再删都是 no-op，不发事件。
- 目标只要求非零，不要求 MemberNFT 存在（允许预黑名单），与 05-chat-types:22 一致；这是与 `GroupMember` / `GroupAdmin` 的关键差异。
- 无 Low；4 条 Info：批量零值错误无载荷定位、规格缺校验顺序、重复封禁不更新操作者记录、空批次 no-op 未写。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 4 |
| revert 站点 | 4 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 0 / 4 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotGroupOperator` | `NotGroupOperator(uint256,uint256)` | `0x20e5d297` | 1 | 保留 |
| `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` | 1 | 保留 |
| `ZeroTargetSenderId` | `ZeroTargetSenderId()` | `0x16f52684` | 1 | 保留（批量定位见 E-BL-01） |
| `DuplicateMemberId` | `DuplicateMemberId(uint256)` | `0x1a494813` | 1 | 保留 |

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `GroupNotExist(groupId)` | `:149` | `onlyOperator` | `groupOwner == address(0)`；`groupOwner ← MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId)` | `groupId ← 入参` | `banBySenderIds`、`unbanBySenderIds` |
| 2 | `NotGroupOperator(groupId, operatorId)` | `:152` | `onlyOperator` | `!_isOperator(groupId, operatorId, groupOwner)` | `groupId ← 入参`；`operatorId ← 入参` | `banBySenderIds`、`unbanBySenderIds` |
| 3 | `ZeroTargetSenderId()` | `:142` | `_checkTargetSenderId` | `targetSenderId == 0` | —（零值本身即失败元素） | `banBySenderIds`、`unbanBySenderIds`（逐元素） |
| 4 | `DuplicateMemberId(memberId)` | `:113` | `_setSenderIdBanTargets` | `senderIds[j] == senderId`（`j < i`） | `memberId ← senderIds[i]` | `banBySenderIds`、`unbanBySenderIds`（逐元素） |

### 3.2 赋值与发送逻辑

```text
banBySenderIds / unbanBySenderIds
1. 鉴权  onlyOperator：
         群缺失（ownerOrZero == 0）           → GroupNotExist(groupId)
         operatorId == 0                     → NotGroupOperator(groupId, operatorId)
         operatorId == groupId               → msg.sender 必须是群 owner，否则 NotGroupOperator
         其他 operatorId                     → ownerOrZero(operatorId) == msg.sender 且 isAdminId(groupId, operatorId)，否则 NotGroupOperator
2. 元素  逐元素：
         senderId == 0                       → ZeroTargetSenderId()
         与前面元素重复                        → DuplicateMemberId(senderId)
         add / remove；changed 才更新 operator 记录并发 SenderBanChanged
```

- `_isOperator` 对 `operatorId` 用 `MemberOwner.ownerOrZero`，缺失的 operator NFT 得到地址 0，随后按鉴权失败回 `NotGroupOperator`，不透传 `ERC721NonexistentToken`。这与 07-events-errors:29 的“复合群鉴权回 `NotGroupOperator`”一致，也避免向未授权方泄露身份存在性。
- 与 `GroupMember` / `GroupAdmin` 不同，本模块不调用 `ownerOf(targetSenderId)`；`senderId = neverMinted` 可以正常封禁，符合 05-chat-types:22“允许预黑名单”。
- 逐元素先校验、后写入；后面的元素失败会让整笔回滚，批量原子（§6）。
- `changed == false` 时（重复封禁/重复解封）不更新 `senderIdBanOperatorStates`，也不发事件，属 Set 幂等（§6）。

### 3.3 已核对项

- `onlyOperator` 不要求 Chat 已激活，允许激活前维护名单；01-lifecycle 未禁止，`AdminBanSource` 可在激活前预置黑名单。
- `isSenderIdBanned`、`isSenderIdBannedBatch`、`senderIdBanDetails`、`senderIdBanList` 对缺失群返回 false / 0 / 空数组，不回滚；07-events-errors:35 的分工（写入口回 GroupNotExist，读面按各自规格返回空）成立。
- 解封会删除 operator 记录（`:130-138`），`senderIdBanDetails` 不会残留历史操作者。
- 测试：`test/OperatorAuth.t.sol`、`test/AdminBanSource.t.sol` 覆盖 4 个错误的 selector + 载荷；`testT123B` 锁定 swap-and-pop 后的 reverse 语义（08-testing:14）。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-BL-01 | Info | `src/GroupChatBanList.sol:110`、`:140-144` | 批量入口中 `ZeroTargetSenderId()` 无载荷，调用方只能按“输入数组中第一个 0”定位失败元素；`DuplicateMemberId` 则携带失败 ID。两者同为元素错误，定位能力不一致。 | §4（批量：失败元素键或索引）；§6（错误必须能定位失败元素） | **已按方案 A 落地**：不动 ABI，在 05-chat-types:23 与 07-events-errors:29 登记「按入参顺序返回第一个零值；`ZeroTargetSenderId()` 无载荷，定位靠回放」；新增索引进 breaking 窗口再评估 |
| E-BL-02 | Info | `src/GroupChatBanList.sol:35-47`、`:104-128` | 规格未按 §5 给 `banBySenderIds` / `unbanBySenderIds` 写校验顺序与错误集合；05-chat-types:60 只写“旧批量增删行为不变”。 | §5（每个外部写入口写明顺序与错误集合） | 已登记：05-chat-types:23「批量封禁/解封的顺序为鉴权 → 群存在性 → 逐元素零值 → 逐元素重复 → 写入」 |
| E-BL-03 | Info | `src/GroupChatBanList.sol:116-126` | 重复封禁（`changed == false`）不更新 `senderIdBanOperatorStates`，`senderIdBanDetails` 的“最后封禁操作者”保持首次记录。属 Set 幂等，但字段语义与“last banned by”字面不完全一致。 | §6（Set 幂等 no-op） | 已由 state 卷 `GBL-01` 关闭：05-chat-types:23「operator state 记录最后一次实际变更的操作者，重复封禁同一目标不改写，不表示最后请求者」 |
| E-BL-04 | Info | `src/GroupChatBanList.sol:104-108` | 空 `senderIds` 是合法 no-op（只做鉴权），规格未写。 | §6（no-op 语义） | 已登记：05-chat-types:23「空批次为 no-op，不写状态、不发事件」 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `MemberNFT.ownerOf`（经 `MemberOwner.ownerOrZero`） | 无（`ERC721NonexistentToken` 被映射为地址 0） | `onlyOperator` 的 `operatorId` 解析 | MemberOwner 库注释 |
| `IGroupAdmin.isAdminId` | 无自身错误 | `onlyOperator`（admin 分支） | 07-events-errors:29 |
| `GroupChatBanList` 自身 | 无标准错误继承 | — | 07-events-errors:25 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test --match-path test/OperatorAuth.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/IGroupChatBanList.sol`。
