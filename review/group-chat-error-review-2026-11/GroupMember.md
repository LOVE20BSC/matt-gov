# `group-chat/GroupMember.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/01-lifecycle.md`、`05-chat-types.md`、`07-events-errors.md`。
> 范围：`src/GroupMember.sol`（115 行）+ `src/interfaces/IGroupMember.sol` 的 `IGroupMemberErrors`。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 3 条（0 Low / 3 Info）。

## 1. 结论

- 3 个错误声明 / 3 个 revert 站点；实现零声明，无裸 `require`/`revert`/`assert`。
- 成员名单是“成员 ID 集合”，不绑定 NFT 当前持有人；增删都要求 `ownerOf(memberId)` 成功，缺失回 `ERC721NonexistentToken`。
- `addMemberIds` / `removeMemberIds` 共用 `_setMemberIds`：逐元素存在性 → 重复 → Set 增删；已列出再加、未列出再删都是 no-op。
- 无 Low；3 条 Info：规格缺校验顺序、删除路径严格模式未写明、空批次 no-op 未写。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 3 |
| revert 站点 | 3 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 0 / 3 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotGroupOperator` | `NotGroupOperator(uint256,uint256)` | `0x20e5d297` | 1 | 保留 |
| `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` | 1 | 保留 |
| `DuplicateMemberId` | `DuplicateMemberId(uint256)` | `0x1a494813` | 1 | 保留 |

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `GroupNotExist(groupId)` | `:95` | `onlyOperator` | `groupOwner == address(0)`；`groupOwner ← MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId)` | `groupId ← 入参` | `addMemberIds`、`removeMemberIds` |
| 2 | `NotGroupOperator(groupId, operatorId)` | `:98` | `onlyOperator` | `!_isOperator(groupId, operatorId, groupOwner)` | `groupId ← 入参`；`operatorId ← 入参` | `addMemberIds`、`removeMemberIds` |
| 3 | `DuplicateMemberId(memberId)` | `:76` | `_setMemberIds` | `memberIdList[j] == memberId`（`j < i`） | `memberId ← memberIdList[i]` | `addMemberIds`、`removeMemberIds`（逐元素） |

### 3.2 赋值与发送逻辑

```text
addMemberIds / removeMemberIds
1. 鉴权  onlyOperator：
         群缺失（ownerOrZero == 0）           → GroupNotExist(groupId)
         operatorId == 0                     → NotGroupOperator(groupId, operatorId)
         operatorId == groupId               → msg.sender 必须是群 owner，否则 NotGroupOperator
         其他 operatorId                     → ownerOrZero(operatorId) == msg.sender 且 isAdminId(groupId, operatorId)，否则 NotGroupOperator
2. 元素  逐元素：
         IMemberNFT(GROUP_ADDRESS).ownerOf(memberId)  // 缺失 → ERC721NonexistentToken(memberId)
         与前面元素重复                        → DuplicateMemberId(memberId)
         add / remove；changed 才发 MemberStatusChanged
```

- `ownerOf` 的结果被丢弃，仅用于存在性校验；身份存在性公开，不属于泄露（§5）。
- `memberId == 0` 不单独回 `Zero*`，而是 `ownerOf(0)` 的 `ERC721NonexistentToken(0)`；07-events-errors:27 明确“0 值按缺失处理”，与 `GroupChatBanList` 的 `ZeroTargetSenderId()` 分工不同。
- 逐元素先校验、后写入；后面的元素失败整笔回滚，批量原子（§6）。
- 删除也要求 `ownerOf` 成功：`removeMemberIds(groupId, operatorId, [neverMintedId])` 回 `ERC721NonexistentToken` 而非 no-op（E-GM-02）。由于 MemberNFT 无销毁入口，已加入的 ID 不会出现“无法删除”的路径。

### 3.3 已核对项

- 成员名单与 NFT 所有权分离：NFT 转移不改变名单，符合 05-chat-types:59“成员/管理员...owner 快照...行为不变”。
- 与 `GroupMemberScope` 的关系：`isMemberId(groupId, senderId)` 只查名单；发言路径仍要求 `ownerOf(senderId) == msg.sender`，名单本身不构成发言授权。
- 读面对缺失群返回 false / 空数组，不回滚。
- 测试：`test/OperatorAuth.t.sol`、`test/GroupMemberScope.t.sol` 覆盖 3 个错误的 selector + 载荷；`testT133B` 覆盖成员增删。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-GM-01 | Info | `src/GroupMember.sol:29-41`、`:67-90` | 规格未按 §5 给 `addMemberIds` / `removeMemberIds` 写校验顺序与错误集合；05-chat-types:60 只写“行为不变”。 | §5（每个外部写入口写明顺序与错误集合） | 已登记：05-chat-types:60「`addMemberIds` / `addAdmins` 的顺序为鉴权 → 群存在性 → 逐元素 NFT 存在性 → 逐元素重复 → `addAdmins` 上限 → 写入」 |
| E-GM-02 | Info | `src/GroupMember.sol:67-78` | 删除路径也要求 `ownerOf` 成功，属 §6 的严格模式；规格只在 07 写通用身份规则，没有点明删除入口。 | §6（批量删除默认 no-op；严格模式须写明） | 已由 state 卷 `GAD-03` 关闭：05-chat-types:60「`removeAdmins` / `removeMemberIds` 要求对应 NFT 当前存在」 |
| E-GM-03 | Info | `src/GroupMember.sol:67-90` | 空 `memberIdList` 是合法 no-op（只做鉴权），规格未写。 | §6（no-op 语义） | 已登记：05-chat-types:60「空批次为 no-op」 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `MemberNFT.ownerOf` | `ERC721NonexistentToken(memberId)` | `addMemberIds`、`removeMemberIds`（`_setMemberIds`） | 07-events-errors:27；08-testing:9 |
| `MemberNFT.ownerOf`（经 `MemberOwner.ownerOrZero`） | 无（映射为地址 0） | `onlyOperator` 的 `operatorId` 解析 | MemberOwner 库注释 |
| `IGroupAdmin.isAdminId` | 无自身错误 | `onlyOperator`（admin 分支） | 07-events-errors:29 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test --match-path test/OperatorAuth.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/IGroupMember.sol`。
