# GroupChatBanList · 状态变量变更审查

> `group-chat/src/GroupChatBanList.sol`，169 行，基线 `group-chat@e982df8`。
> 人工黑名单由“集合 + 最后变更操作者”两部分组成；权限与 `GroupMember` 一样内联判定。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `GROUP_ADMIN_ADDRESS` | `address immutable` | 管理员快照来源 | 构造 `:31` |
| 2 | `GROUP_ADDRESS` | `address immutable` | MemberNFT 地址 | 构造 `:32` |
| 3 | `_chatState[groupId].senderIdBanList` | `Uint256Set.Storage` | 被人工封禁的 senderId 集合 | `_setSenderIdBanTargets:116`（add / remove） |
| 4 | `_chatState[groupId].senderIdBanOperatorStates[senderId]` | `mapping(uint256 => BanOperatorState)` | 最后一次**实际变更**的 operator 地址与 operatorId | `_setSenderIdBanOperatorState:134`（写）、`:136`（delete） |

`BanOperatorState` 字段为 `(operatorAddress, operatorId)`；只保留最近一次状态变更，不保留历史链。

## 2. 逐变量变更逻辑

### 2.1 `banBySenderIds` / `unbanBySenderIds`（`:35-47`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | 修饰器 `:146-155` | `onlyOperator(groupId, operatorId)` | 群不存在回 `GroupNotExist`；`operatorId == groupId` 要求群 owner；否则要求调用者是 operatorId NFT owner 且 `GroupAdmin.isAdminId` |
| 2 | `:108-115` | 逐项 `_checkTargetSenderId` + 数组内去重 | target 只要求非零，不要求 MemberNFT 存在（允许预黑名单）；重复回 `DuplicateMemberId` |
| 3 | `:116` | `senderIdBanList.add` 或 `remove` | 集合返回是否实际变化 |
| 4 | `:117-126` | 仅 `changed` 时：写/删 operator state，发 `AdminSenderBanChanged` | 幂等操作不更新 operator state、不发事件 |

### 2.2 `senderIdBanList`

- 唯一写入点 `_setSenderIdBanTargets:116`；没有清空整张名单或按地址批量迁移的入口。
- target 不要求 NFT 存在；这允许在目标铸造/加入前预先封禁，符合规格 `05-chat-types.md` 的“只要求非零”。
- 群 NFT 转移不清空名单；新群 owner/新有效 admin 继承当前名单并可解封。

### 2.3 `senderIdBanOperatorStates`

- 只在 `changed == true` 时写：`listed == true` 写 `BanOperatorState(msg.sender, operatorId)`；`listed == false` delete。
- 对已封禁目标重复 `banBySenderIds`，`add` 返回 false，`changed == false`，**不会**把 operator state 改成本次调用者；该字段语义是“最后一次实际状态变更者”，不是“最后一次请求者”。
- 解封后 operator state 删除；再次封禁时重新写入新的 operator。

## 3. 写入顺序与不可分割性

```text
onlyOperator（群存在 -> 调用者身份）
  -> 逐项：target 非零 -> 数组内去重
        -> 集合 add/remove
        -> changed 时：operator state 写/删 + 事件
```

外部调用只有 `MemberNFT.ownerOf` 与 `GroupAdmin.isAdminId`（view），没有状态变更回调，因此不需要重入锁。批量中任一项失败会回滚前面所有集合、operator state 与事件。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `GBL-01` | Info | operator state 记录“最后一次实际变更”，不是“最后一次请求”：重复封禁同一目标不会更新操作者 | E1 |
| `GBL-02` | Info | 批量长度无协议上限，重复检查 O(n²)；target 不要求 NFT 存在是规格允许的预黑名单语义 | E1 |
| `GBL-03` | Info | 名单与 operator state 不随群 NFT 转移清空；新 owner 继承当前名单，旧 operator state 仅作历史记录 | E1 |

逐条说明：

- **`GBL-01`**：`changed` 为 false 时跳过 `_setSenderIdBanOperatorState` 与事件。因此“A 封禁 → B 再次封禁同一目标”后，详情里仍是 A。任何需要“最后请求者”的链下逻辑不能用该字段，只能看 `AdminSenderBanChanged` 事件。
- **`GBL-02`**：`_setSenderIdBanTargets` 每项回扫查重；没有 MAX 批次。target 只校验非零，`unban` 也不要求 NFT 存在，允许清理任意预黑名单 ID。写入口只有 owner/admin，失败整批回滚。
- **`GBL-03`**：状态以 `groupId + senderId` 为键；群 NFT 转移后 `onlyOperator` 的 owner 判定切换，名单内容与旧 operator 记录保留。旧 operator 记录不赋予任何权限，只是查询字段。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 预黑名单一个不存在的 memberId 是否会产生“永远无法解封”的条目 | 可以 `unban`，`_checkTargetSenderId` 只要求非零；不需要 NFT 存在 |
| 重复封禁是否会产生重复集合项 | 不会；`Uint256Set.add` 去重，且数组内重复直接 revert |
| 解封后 operator state 是否残留 | 不会；`_setSenderIdBanOperatorState(listed=false)` 显式 delete |
| 群 NFT 转移后旧管理员还能否解封 | 不能；`GroupAdmin.isAdminId` 的群 owner 快照失配，`onlyOperator` 回 `NotGroupOperator` |
| 批量中后面的 target 为零/重复是否只回滚该项 | 不会；整批回滚 |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| B1 | `senderIdBanList` 无重复 | ✅ | `Uint256Set.add` + 数组去重 |
| B2 | `senderIdBanOperatorStates[s]` 非零当且仅当 `senderIdBanList` 包含 `s` | ✅ | 只在 add 成功时写、只在 remove 成功时 delete；无其他写入 |
| B3 | 每次实际名单变化都伴随 `AdminSenderBanChanged`；无变化不发事件 | ✅ | `changed` 判定 |
| B4 | 只有群 owner 或当前有效 admin 能改名单 | ✅ | `_isOperator` + `GroupAdmin.isAdminId` |
| B5 | 批量操作原子 | ✅ | 单笔循环，无 try/catch |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| `senderIdBanOperatorStates` 的语义 | 测试覆盖事件与详情，但未单独锁定“重复封禁不更新 operator” |
| 大批量 gas 上界 | 没有协议上限，测试未覆盖接近区块 gas 上限的批次 |
| 群 NFT 转移后的名单继承 | 未单独测试；权限判定由 `GroupAdmin` 覆盖 |

### 4.5 结论

未发现 Critical / High / Medium。集合与 operator state 成对变化，且只在 `changed` 时写入；`BanOperatorState` 不存在“集合已删、operator 残留”的路径。3 条 Info 分别是字段语义、批量成本/预黑名单与群转移继承，不影响账本一致性。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `GBL-01` | 登记：operator state 为最后一次实际变更（同 `E-BL-03`） | `05-chat-types.md`「黑名单」 |
| `GBL-02` | 登记：批量无上限、允许预黑名单 | `05-chat-types.md`「黑名单」 |
| `GBL-03` | 登记：名单与 operator state 不随群 NFT 转移清空 | `05-chat-types.md`「黑名单」 |

## 5. 补充审查：`GovVotedBanSource`（GVB）

审查对象：[GovVotedBanSource.sol](file:///Users/BigPolarBear/Documents/github/LOVE20BSC/group-chat/src/sources/ban/GovVotedBanSource.sol)。该合约有自有 `ChatState` 存储与写入面；`refreshVoteByTargetSenderId`（`:62-64`）无调用者鉴权，`voteByTargetSenderId` / `clearVoteByTargetSenderId` 使用 `onlyVoterOwner`。

| ID | 不变量 | 结论 | 证据 |
| --- | --- | --- | --- |
| `GVB-01` | `settledWeight == 0` ⟺ 不在 `voters` | 成立 | 新增票在 `_setVoteIfChanged`（`:191-223`）同笔写票重并加入 `voters`；`_refreshVoteIfFound`（`:254-286`）在权重归零时调 `_removeVote`（`:391-397`）；`_clearVoteIfFound`（`:231-246`）同路径。未见“票重 0 仍留在 `voters`”的写入。 |
| `GVB-02` | 名单命中 ⟺ 阈值谓词成立 | 结算时点成立；实时口径不成立（已知过期） | `_syncBanList`（`:310-324`）在每次结算后用当次 `totalWeight` 调 `_isTargetBanned`（`:371-379`）写名单；外部票权变化不会自动触发同步，名单可能滞后，`05-chat-types.md:43` 已声明“结算结果可提前刷新、可能过期”。不是实现缺陷。 |
| `GVB-03` | `refresh` 不改变 `supportBan` 立场 | 成立 | `_refreshVoteIfFound`（`:254-286`）保留 `vote.supportBan`，按原立场先 `_removeWeight` 再加新权重；非零刷新发 `SenderBanVoteCast`，归零路径发 `SenderBanVoteCleared`，原立场由 `prevSupportBan` 携带（随 events 卷 A2 对齐）。 |
| `GVB-04` | `voters` / `targets` 归零清理无残留 | 成立（可枚举集合）；映射空壳保留 | `_removeVoteAfterWeightRemoved`（`:399-410`）在 `voters.count() == 0` 时移出 `senderIdTargets`；`senderIdTargetStates` 是含嵌套 mapping 的 struct，Solidity 无法 `delete`，仅保留零值空壳，不参与枚举。名单在 `_syncBanList` 中按谓词移出。 |
| `GVB-05` | `_removeWeight` 无下溢 | 成立 | `_removeWeight`（`:432-438`）使用 0.8 检查算术；减数来自该票已计入的 `settledWeight`，刷新路径先减旧值再加新值（`:275` / `:282`），清除路径只减非零票重（`:231-246`）。 |
| `GVB-06` | 任意调用者对同一 voterId 结果一致 | 成立 | `refreshVoteByTargetSenderId`（`:62-64`）不读 `msg.sender`；权重来自 `IGroupActionVote` 与 `MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId)`，与调用者无关；同一状态下重复调用走 `weight == settledWeight` 的仅同步分支（`:265-273`）。 |

结论：6 项核对中 5 项成立，`GVB-02` 仅在“实时口径”不成立且为规格已声明的结算过期语义；未发现需要改代码的违反，按指示只报告、未改代码。`check_caller_auth` 不能覆盖 `refresh` 的无鉴权写入（脚本只检查“鉴权是否放错位置”，不检查“漏写鉴权”）。
