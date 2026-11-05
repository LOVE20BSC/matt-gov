# `group-chat/GovVotedBanSource.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），行号按该提交；`:145/:148` 为 state 卷 `TAM-01` 之后的当前行号。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/05-chat-types.md`、`07-events-errors.md`。
> 范围：`src/sources/ban/GovVotedBanSource.sol`（470 行）+ `src/interfaces/sources/ban/IGovVotedBanSource.sol` 的 `IGovVotedBanSourceErrors`。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 3 条（0 Low / 3 Info）。

## 1. 结论

- 7 个错误声明 / 10 个 revert 站点；实现零声明，无裸 `require`/`revert`/`assert`。
- `BanVoteWeightSourceUnavailable` 一个 selector 覆盖「source 无代码」与「`voteWeight`/`totalVoteWeight` 调用失败」两类，属同一「权重源不可用」语义，**登记为已知边界，不拆 ABI**。
- `NotMemberOwner` 与 GroupChat、`ZeroTargetSenderId` 与 GroupChatBanList 为跨模块同名同签名，均 local-first 声明，不构成 `check_errors.py` 的一错多签名违规。
- 无 Low；3 条 Info：视图对无代码 source 的返回口径不一致、撤票/刷新先查 source 再查记录、`BanVoteWeightSourceUnavailable` 多条件合并（最后一条为已知边界）。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 7 |
| revert 站点 | 10 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 0 / 3 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` | 1 | 保留 |
| `BanVoteWeightSourceUnavailable` | `BanVoteWeightSourceUnavailable(uint256,address)` | `0x76befc7f` | 3 | 保留，已知边界 |
| `ZeroTargetSenderId` | `ZeroTargetSenderId()` | `0x16f52684` | 1 | 保留，与 BanList 共享 |
| `ZeroVoteWeight` | `ZeroVoteWeight(uint256,uint256)` | `0xbeffc593` | 1 | 保留 |
| `VoteUnchanged` | `VoteUnchanged(uint256,uint256,uint256)` | `0x96c2cbe9` | 1 | 保留 |
| `VoteNotFound` | `VoteNotFound(uint256,uint256,uint256)` | `0x4f90f748` | 2 | 保留 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` | 1 | 保留，与 GroupChat 共享 |

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `GroupNotExist(groupId)` | `:329` | `_sourceOrRevert` | `MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId) == address(0)` | `groupId ← 入参` | vote / clear / refresh |
| 2 | `BanVoteWeightSourceUnavailable(groupId, source)` | `:332` | `_sourceOrRevert` | 群 owner 无代码 | `groupId ← 入参`；`source ← ownerOrZero` | 同上 |
| 3 | `BanVoteWeightSourceUnavailable(groupId, source)` | `:348` | `_voteWeightOrRevert` | `IBanVoteWeightSource(source).voteWeight(...)` 抛错/解码失败 | 同上 | 投票、刷新 |
| 4 | `BanVoteWeightSourceUnavailable(groupId, source)` | `:356` | `_totalVoteWeightOrRevert` | `IBanVoteWeightSource(source).totalVoteWeight(...)` 抛错/解码失败 | 同上 | 投票、撤票、刷新 |
| 5 | `ZeroTargetSenderId()` | `:383` | `_checkTargetSenderId` | `targetSenderId == 0` | 无 | vote / clear / refresh |
| 6 | `ZeroVoteWeight(groupId, voterId)` | `:199` | `_setVoteIfChanged` | 投票/改票时 `voteWeight == 0`；刷新路径权重 0 时清除票，不触发 | 两者均为入参 | vote |
| 7 | `VoteUnchanged(groupId, targetSenderId, voterId)` | `:187` | `_setVoteIfChanged` | 记录存在、方向相同、`settledWeight` 未变 | 三者均为入参 | vote |
| 8 | `VoteNotFound(groupId, targetSenderId, voterId)` | `:227` | `_clearVoteIfFound` | 记录不存在（`settledWeight == 0`） | 三者均为入参 | clear |
| 9 | `VoteNotFound(groupId, targetSenderId, voterId)` | `:250` | `_refreshVoteIfFound` | 记录不存在（`settledWeight == 0`） | 三者均为入参 | refresh |
| 10 | `NotMemberOwner(voterId)` | `:180` | `onlyVoterOwner` | `ownerOf(voterId) != msg.sender` | `voterId ← 入参` | vote / clear（refresh 无鉴权） |

### 3.2 赋值与发送逻辑

```text
vote / clear / refresh
1. 鉴权  vote/clear：onlyVoterOwner(voterId)
         IMemberNFT.ownerOf(voterId)  // 缺失 → ERC721NonexistentToken(voterId)
         owner 非 msg.sender          → NotMemberOwner(voterId)
         refresh 无鉴权（任何人可结算过期票，见 05-chat-types:43）
2. 参数  _checkTargetSenderId：
         targetSenderId == 0          → ZeroTargetSenderId()
3. 存在  _sourceOrRevert：
         群缺失                        → GroupNotExist(groupId)
         owner 无代码                  → BanVoteWeightSourceUnavailable(groupId, owner)
4. 权重  voteWeight / totalVoteWeight 调用失败 → BanVoteWeightSourceUnavailable(groupId, source)
5. 记录  clear/refresh：记录缺失     → VoteNotFound(...)
         vote：权重 0                → ZeroVoteWeight(...)
         方向与权重未变              → VoteUnchanged(...)
```

- 投票/撤票/刷新都以 `_sourceOrRevert` 为前置；source 不可用时先回 `BanVoteWeightSourceUnavailable`，记录存在性检查在其后（E-GVB-02）。
- `refreshVoteByTargetSenderId` 无鉴权，设计为任何人可把过期票结算到实时权重；state 卷 `GVB-06` 已确认，05-chat-types:43 有书面口径。
- 视图 `voteStatusBySenderId`、`voteWeightsBySenderIdsByVoterId`、`votedSenderIds`、`votersBySenderId` 在 source 无代码时返回空/零；`voteStatusBySenderIds`、`isBanned`、`isSenderIdBannedBatch` 直接读已结算状态（E-GVB-01）。
- `BanVoteWeightSourceUnavailable` 的 3 个站点共享一个 selector，载荷 `(groupId, source)` 可自证失败对象；「无代码」与「调用失败」对调用方的处置相同（替换 source），不拆 ABI（E-GVB-03，已知边界）。
- 跨模块同名同签名：`NotMemberOwner` 与 `GroupChat.sol:92`、`ZeroTargetSenderId` 与 `GroupChatBanList.sol:142`，签名一致、各模块 local-first 声明，符合 `check_errors.py` 口径。

### 3.3 已核对项

- 声明 / 站点闭合：7 / 10，与 `registry/errors.md` 第 175、180、186、192、201、204-207 行一致。
- 与 07-events-errors:22 的 7 条完全对应；与 05-chat-types 的投票/撤票/刷新口径一致，除 E-GVB-02 的顺序表述。
- 测试：`test/GovVotedBanSource.t.sol`、`test/GroupChatBanList*.t.sol` 覆盖 7 个错误的 selector + 载荷。
- `IBanVoteWeightSource` 调用被 `try/catch` 归一，不产生透传错误；`IMemberNFT.ownerOf` 的 `ERC721NonexistentToken` 按 07:27 透传登记。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-GVB-01 | Info | `src/sources/ban/GovVotedBanSource.sol:66-142` | 视图对 source 无代码的处理不一致：`voteStatusBySenderId`、`voteWeightsBySenderIdsByVoterId`、`votedSenderIds`、`votersBySenderId` 返回空/零，`isBanned`/`voteStatusBySenderIds` 直接读已结算状态；05-chat-types:47 只登记了单条 `voteStatusBySenderId`。 | §5（规格写明查询口径） | 已登记：05-chat-types「查询视图」段 |
| E-GVB-02 | Info | `src/sources/ban/GovVotedBanSource.sol:254-286` | 撤票/刷新在 source 不可用时先回 `BanVoteWeightSourceUnavailable`，与 05-chat-types:39「找不到记录回 `VoteNotFound`」的表述不完整。 | §5（校验顺序与错误集合） | 已登记：05-chat-types 投票段 |
| E-GVB-03 | Info | `src/sources/ban/GovVotedBanSource.sol:332`、`:348`、`:356` | `BanVoteWeightSourceUnavailable` 一个 selector 覆盖「无代码」与「调用失败」两类。 | §2（一错误一条件） | 已知边界，不处理：两类对调用方的处置相同，载荷可自证失败对象；05-chat-types:27 已登记 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `MemberNFT.ownerOf` | `ERC721NonexistentToken(voterId)` | `onlyVoterOwner`（vote/clear） | 07-events-errors:27 |
| `IBanVoteWeightSource.voteWeight` / `totalVoteWeight` | 无（`try/catch` 归一为 `BanVoteWeightSourceUnavailable`） | vote/clear/refresh | 05-chat-types:27、07-events-errors:25 |
| `MemberOwner.ownerOrZero` | 无（映射为地址 0） | `_sourceOrRevert` | MemberOwner 库注释 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py group-chat
forge test --match-path test/GovVotedBanSource.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/sources/ban/IGovVotedBanSource.sol`。
