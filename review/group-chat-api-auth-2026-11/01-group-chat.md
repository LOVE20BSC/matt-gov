# GroupChat 接口调用权限审查

> 对象 `group-chat/src/GroupChat.sol`（951 行）
> 接口 `group-chat/src/interfaces/IGroupChat.sol`（326 行）
> 基线 `group-chat@e982df8`（工作树干净；相对 `72d7226` 仅 `lib/action` 子模块 bump，`src/` 无差异）
> 审查日期 2026-11-04
> 判据 `matt-gov/docs/dev-standards.md` §5.5（调用者校验）、§5.7（校验分层）、§4.3（分页与批量查询）；`matt-gov/docs/specs/group-chat/01-lifecycle.md`、`03-posting.md`、`04-query.md`、`05-chat-types.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 35（写 7 / 读 28） |
| 鉴权 modifier | 3（`onlySenderOwner`、`onlyChatOwner`、`onlyGroupOwner`） |
| 写入口带 `nonReentrant` | 7 / 7（均在最左） |
| 无许可写入口 | **0** |
| 发现 | 1 条 Low + 2 条 Info；另有 6 条正面结论 |
| 接口对账 | 35 vs 35，**0 差异** |
| 机械核验 | `check_caller_auth.sh group-chat/src` → `violations: 0`；`forge test` → 151 passed |

一句话：**GroupChat 是群聊仓写入权限的汇聚点——7 个写入口全部先鉴权、再业务；管理员只能 `mentionAll`，不能改配置；`senderId == groupId` 的 scope/ban 豁免只属于群 NFT 持有人。真正的风险不在越权，而在群 owner 可把 source/plugin 配成任意有代码地址（自伤），以及 `canPost` 预检查未覆盖 Phase 未启动。**

### 1.1 审查范围（S-1）

处置：A（不补盘）。本卷只审多角色写入口合约 `GroupChat.sol`；`GroupAdmin`、`GroupMember`、`GroupChatBanList`、各 Manager 与 source 的鉴权由同基线 `group-chat-state-mutation-review-2026-11` 的逐入口不变量与 `check_caller_auth` 机械覆盖，不在本卷重复展开。

## 二、权限模型

| 权限主体 | 判据 | 覆盖入口 |
| --- | --- | --- |
| 群 NFT 当前持有人 | `MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId) == msg.sender`（`L814-819`） | `activateChat`；5 个配置 setter（且 `operatorId == groupId`） |
| `senderId` NFT 当前持有人 | `IMemberNFT(GROUP_ADDRESS).ownerOf(senderId) == msg.sender`（`L90-95`） | `post` |
| 群 NFT 持有人或有效 admin | `senderId == groupId` 或 `IGroupAdmin.isAdminId(groupId, senderId)`（`L705-713`） | 仅 `post` 内部的 `mentionAll` 子检查 |
| 任何地址 | 无 | 28 个只读入口 |

### 2.1 两个 owner 判定

`onlyChatOwner`（`L97-102`）与 `onlyGroupOwner`（`L687-696`）都以同一个地址为鉴权根：

```solidity
function _groupOwnerOrRevert(uint256 groupId) internal view returns (address owner) {
    owner = MemberOwner.ownerOrZero(GROUP_ADDRESS, groupId);
    if (owner == address(0)) revert GroupNotExist(groupId);
}
```

- `onlyChatOwner(groupId)` 只判 `msg.sender == owner`，供 `activateChat` 使用（该入口没有 `operatorId`）。
- `onlyGroupOwner(groupId, operatorId)` 额外要求 `operatorId == groupId`，供 5 个配置 setter 使用；`operatorId` 只作为事件字段。
- 两个 modifier 的差异只有「是否携带 `operatorId`」，owner 判定本身重复了一份。`check_caller_auth.py` 不检查重复；这是可读性取舍，不构成鉴权缺口（见 GC-03 的说明）。

### 2.2 管理员权限边界

管理员在 GroupChat 中只有一处权限：`mentionAll`。`_checkMentionAllOperator` 先放行 `senderId == groupId`，再查 `IGroupAdmin.isAdminId(groupId, senderId)`。**管理员不能调用任何配置 setter**：`onlyGroupOwner` 要求 `msg.sender == owner`，管理员不是 owner；即使传入 `operatorId == groupId` 也会在 `msg.sender != owner` 处失败（测试 `testT209_adminCannotSetChatConfig`）。管理员也不因 `mentionAll` 权限绕过 scope/ban（`02-rules.md`、`03-posting.md`）。

## 三、入口清单

### 3.1 写入口（7）

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 关键业务校验 | 事件 |
| --- | --- | --- | --- | --- | --- |
| `activateChat(uint256,address,address,address,address)` `L104` | 群 NFT 持有人 | `nonReentrant onlyChatOwner(groupId)` `L97` | 是 | 未激活；source/plugin 非零时必须有代码（`L118-121`） | `GroupChatActivated` |
| `setPostingAllowed(uint256,uint256,bool)` `L147` | 群 NFT 持有人 | `nonReentrant onlyGroupOwner(groupId,operatorId)` `L687` | 是 | `operatorId == groupId`（modifier）；已激活（`L152`） | `PostingAllowedChanged` |
| `setScopeSource(uint256,uint256,address)` `L169` | 群 NFT 持有人 | 同上 | 是 | 已激活；source 非零时有代码；同值 no-op（`L546-549`） | `ScopeSourceChanged` |
| `setBanSource(uint256,uint256,address)` `L177` | 群 NFT 持有人 | 同上 | 是 | 同上 | `BanSourceChanged` |
| `setBeforePostPlugin(uint256,uint256,address)` `L185` | 群 NFT 持有人 | 同上 | 是 | 已激活；plugin 非零时有代码；同值 no-op（`L583-586`） | `BeforePostPluginChanged` |
| `setAfterPostPlugin(uint256,uint256,address)` `L193` | 群 NFT 持有人 | 同上 | 是 | 同上 | `AfterPostPluginChanged` |
| `post(uint256,uint256,string,uint256[],bool,uint256)` `L201` | `senderId` NFT 持有人 | `nonReentrant onlySenderOwner(senderId)` `L90` | 是 | 群存在/已激活/允许发言；正文、提及、`mentionAll`、引用；scope/ban；before 插件 | `MessagePosted`、`SenderMentioned`、`AfterPostPluginFailed` |

### 3.2 只读入口（28）

| 分组 | 函数 | 主体 | 边界 |
| --- | --- | --- | --- |
| 地址与常量 getter（5） | `GROUP_ADDRESS`、`GROUP_ADMIN_ADDRESS`、`PHASE_ADDRESS`、`MAX_CONTENT_LENGTH`、`MAX_MENTIONED_SENDER_IDS` | 任何地址 | 常量/immutable，无状态读取 |
| 配置查询（8） | `chatInfo` `L297`、`chatInfosByGroupIds` `L301`、`isPostingAllowed` `L329`、`scopeSource` `L334`、`banSource` `L339`、`beforePostPlugin` `L344`、`afterPostPlugin` `L349`、`canPost` `L354` | 任何地址 | 除 `canPost` 外均要求群存在；`canPost` 以 `PostRejectionReason` 返回 `GroupNotExist` |
| 消息查询（10） | `message` `L370`、`messages` `L379`、`messagesByRound` `L389`、`messagesBySenderId` `L405`、`messageIdsBySenderId` `L416`、`messagesByMentionedSenderId` `L427`、`messageIdsByMentionedSenderId` `L444`、`mentionAllMessages` `L457`、`mentionAllMessageIds` `L468`、`senderIds` `L479` | 任何地址 | 群必须存在；单条 `messageId` 越界回 `MessageNotFound`；集合按 `(offset,limit,reverse)` 分页 |
| 轮次与发现（5） | `currentRound` `L362`、`groupIds` `L490`、`rounds` `L499`、`roundInfo` `L516`、`roundInfosByRounds` `L521` | 任何地址 | `currentRound` 在 Phase 返回 0 时回 `RoundNotStarted(1,0)`；`roundInfo` 对空 Round 返回零值；`rounds` 只枚举有消息的 Round |

## 四、逐入口判定

### 4.1 `activateChat` — 一次性，owner 独占

- 鉴权：`onlyChatOwner`；非 owner 回 `NotGroupOwner(groupId)`；群不存在回 `GroupNotExist(groupId)`（`_groupOwnerOrRevert` 先于 owner 比较）。
- 首道业务校验：`config.activated` 为真回 `ChatAlreadyActivated(groupId)`（`L114-116`）。
- source/plugin 只做「非零则必须有代码」校验（`L118-121`、`L821-831`），不校验接口是否匹配。零地址表示该槽位关闭。
- 激活同时写 `firstActivatedOwner` / `firstActivatedBlockNumber` / `firstActivatedTimestamp`，把 `groupId` 追加到全局 `_groupIds`，并按 `postingAllowed = true` 初始化（`L123-133`）。
- 激活后不能再调用 `activateChat`；配置只能走 5 个 setter。
- 事件 `GroupChatActivated` 的 `ownerId` 固定为 `groupId`，`owner` 为当前 owner（`L135-144`）。

### 4.2 配置 setter — 只有群 owner，管理员无权

5 个 setter 共享同一形状：

1. modifier 先判 `operatorId == groupId` 且 `msg.sender == owner`；
2. 函数体首条 `_checkActivated(groupId)`（`L152`、`L542`、`L579`），即群存在且已激活；
3. 地址槽位再做「非零必须有代码」；
4. 新旧值相同直接 `return`，不发事件；
5. 变更发对应 `*Changed` 事件，携带 `operatorId`、`operator = msg.sender` 与 `prev*`。

`setPostingAllowed` 与四个槽位 setter 的权限完全相同；**管理员不能改配置**，这是规格 `01-lifecycle.md` 的明文要求。`operatorId` 不参与权限计算之外的任何写入，仅用于事件；传 `0` 或非 `groupId` 都回 `NotGroupOperator(groupId, operatorId)`。

### 4.3 `post` — 唯一消息写入入口

校验顺序与 `03-posting.md` 一致：

| 步骤 | 代码 | 结果 |
| --- | --- | --- |
| 1. 调用者持有 `senderId` | `onlySenderOwner` `L90-95` | 非 owner 回 `NotMemberOwner(senderId)`；NFT 不存在时由 `ownerOf` 抛 `ERC721NonexistentToken` |
| 2. 群存在且已激活 | `_checkActivated` `L698-703` | `GroupNotExist` / `ChatNotActivated` |
| 3. 允许发言 | `L221-224` | `PostingNotAllowed` |
| 4. 正文非空且 ≤ 4096 字节 | `L226-231` | `ContentEmpty` / `ContentTooLong` |
| 5. 提及列表 ≤ 32、每个 NFT 存在、无重复 | `_checkMentionedSenderIds` `L833-849` | `TooManyMentionedSenderIds` / `ERC721NonexistentToken` / `DuplicateMemberId` |
| 6. `mentionAll` 资格 | `_checkMentionAllOperator` `L705-713` | `MentionAllUnauthorized` |
| 7. 引用消息存在 | `_checkQuotedMessageId` `L924-931` | `QuotedMessageNotFound` |
| 8. 当前 Round | `currentRound` `L362-368` | `RoundNotStarted` |
| 9. scope → ban | `_postSourceRejection` `L725-752` | `ScopeRejected` / `BanRejected` / `ScopeSourceFailed` / `BanSourceFailed` |
| 10. before 插件 | `L240-244` | 插件 revert 整笔回滚 |
| 11. 写入消息、索引、Round、事件 | `L246-263` | `MessagePosted` + 逐条 `SenderMentioned` |
| 12. after 插件 | `L265-294` | 失败捕获并 `AfterPostPluginFailed`，消息保留 |

- **scope/ban 豁免只属于 `senderId == groupId`**（`L730-732`）：群 NFT 持有人以群身份发言时跳过 scope/ban；以其他 NFT 身份发言仍走 source。
- **`mentionAll` 不豁免 scope/ban**：管理员通过 `mentionAll` 检查后仍要过第 9 步。
- 消息存储 `senderAddress = msg.sender`（`L865`），即调用时 `senderId` 的持有人。
- `beforePostPlugin` 失败不捕获；`afterPostPlugin` 失败捕获，事件只带 `keccak256(err)`、长度和首 4 字节 selector，不把无界 `bytes` 写入事件（`L277-292`）。
- 全函数 `nonReentrant`；after 插件重入被 `Reentrant()` 拦截（测试 `testT075_afterPostReenterIsBannedByNonReentrant`）。

### 4.4 只读面

- `chatInfo` / `chatInfosByGroupIds` 通过 `_chatInfo` → `_groupOwnerOrRevert`，任一 groupId 不存在整笔回滚 `GroupNotExist`（测试 `testT011C`）；批量入参长度无上限。
- `isPostingAllowed` / 四个槽位 getter 只要求群存在，不要求已激活；未激活群返回 `false` / 零地址。
- `canPost` 只做核心与 source 预检查，不验证 sender 所有权、正文、提及、引用、before 插件（`03-posting.md`「预检查」）；返回封闭枚举 `PostRejectionReason`。
- `currentRound` 直接读 `IPhase(PHASE_ADDRESS).currentPhase()`，Phase 返回 0 时回 `RoundNotStarted(1,0)`。
- `message` / `messages` / `messagesByRound` / `messagesBySenderId` / `messageIdsBySenderId` / `messagesByMentionedSenderId` / `messageIdsByMentionedSenderId` / `mentionAllMessages` / `mentionAllMessageIds` / `senderIds` / `rounds` 全部按 `(offset, limit, reverse) → (列表, totalCount)` 分页；`limit = 0` 只取总数。
- `groupIds` 是全局已激活群列表，不要求群存在；`rounds` 只枚举有消息的 Round；`roundInfo` / `roundInfosByRounds` 对空 Round 返回 `RoundSpan(round, 0, 0, 0)`。
- 所有只读函数不改变状态，不需要鉴权；`canPost` 不校验 sender 所有权是规格明示的预检查例外。

## 五、发现

### GC-01（Low）`canPost` 不覆盖 Phase 未启动，预检查可能比 `post` 乐观

- 证据：`canPost` → `_canPost`（`L354-360`、`L775-808`）只检查群存在、已激活、允许发言、sender 存在、scope/ban；`post` 在 `L238` 调用 `currentRound()`，Phase 返回 0 时回 `RoundNotStarted(1,0)`（`L362-368`）。
- 后果：Phase 尚未启动时，`canPost` 可以返回 `(true, None)`，而同一 `(groupId, senderId)` 的 `post` 回滚 `RoundNotStarted`。`canPost` 的枚举没有对应原因，链下若把它当前置判据会误判。
- 为什么不是鉴权问题：`canPost` 是只读预检查，规格 `03-posting.md` 明确它不验证正文、提及、引用和 before 插件；Phase 未启动属于同类时间条件。本报告只登记口径差异，不建议为此扩展 `PostRejectionReason`（会改 ABI）。
- 建议：在 `03-posting.md` 的「预检查」段补一句「Phase 未启动时 `canPost` 不返回拒绝原因，`post` 仍会回 `RoundNotStarted`」；或链下把 `currentRound()` 的 `RoundNotStarted` 作为独立前置条件。处置：A（文档已落地），已在 [`03-posting.md`](../../docs/specs/group-chat/03-posting.md) 的「校验顺序」第 8 步与「预检查」段补登；不改 `PostRejectionReason` 枚举、不改 `_canPost`。

### GC-02（Info）`activateChat` / setter 对 source/plugin 只验代码，不验接口

- 证据：`_checkSourceAddress`（`L821-825`）与 `_checkPluginAddress`（`L827-831`）只判 `code.length != 0`；`beforePostPlugin` 调用不捕获（`L240-244`），`afterPostPlugin` 调用捕获（`L265-294`）。
- 后果：
  1. 群 owner 可以把 `beforePostPlugin` 配成不实现 `beforePost` 的合约，之后所有非群身份发言都回滚；owner 可以再改回来，属于自伤。
  2. 托管群的配置由 Manager 构造参数固定，owner 是 Manager，**没有任何人能改**；一个不兼容的 before 插件会让所有托管群永久无法发言。error 卷无条目承载本问题，由本卷独家登记。
  3. `scopeSource` / `banSource` 接口不匹配时，`post` 会把失败转成 `ScopeSourceFailed` / `BanSourceFailed` 并回滚；`afterPostPlugin` 不匹配则只发 `AfterPostPluginFailed`，消息仍落盘。
- 建议：A（文档 + 部署清单）：在 [`01-lifecycle.md`](../../docs/specs/group-chat/01-lifecycle.md) 激活段与 [`06-manager.md`](../../docs/specs/group-chat/06-manager.md) 部署段写明托管群的 `banSource` / `beforePostPlugin` / `afterPostPlugin` 必须在广播前人工核对接口；`21_check.sh` 维持代码存在性检查，合约层不做接口探针。owner 自管群保持现状。处置：A（文档已落地）。

### GC-03（Info）两个 owner modifier 重复同一判定

- 证据：`onlyChatOwner`（`L97-102`）与 `onlyGroupOwner`（`L687-696`）都调用 `_groupOwnerOrRevert` 并比较 `msg.sender`；前者用于 `activateChat`，后者用于 5 个 setter。
- 后果：无鉴权后果；新增 owner-only 入口时需要决定挂哪一个，存在误用风险（例如给需要 `operatorId` 的入口挂了 `onlyChatOwner`，会丢掉 `operatorId == groupId` 检查）。
- 建议：保留两个 modifier 的现状（签名不同、语义清楚），新增入口时按「是否携带 `operatorId`」选择。本项不构成 §5.5 违规，`check_caller_auth.py` 通过。处置：无需动作——`src` 不加注释（`dev-standards §5.3`）；两个 modifier 保持现状。

### 正面结论（不编号为发现）

1. **鉴权先于业务状态**：`post` 的 `onlySenderOwner` 在 `_checkActivated` 之前；配置 setter 的 `onlyGroupOwner` 在 `_checkActivated` 之前；测试 `testT010B_postAndSettersCheckAuthBeforeGroupState`、`testT015_managementWritesRejectNonexistentGroup` 锁定。
2. **`nonReentrant` 全部最左**：7 个写入口均为 `nonReentrant` 后接鉴权，符合 §5.5；after 插件重入被拦截（`testT075`），before/after 插件不能改 Core 状态（`testT076`）。
3. **管理员不能改配置**：`testT209_adminCannotSetChatConfig`；`mentionAll` 是管理员唯一额外权限（`testT049`）。
4. **scope/ban 豁免只属于群身份**：`senderId == groupId` 才跳过 source；管理员不因 `mentionAll` 绕过（`testT070G_ownerBypassesScopeAndBanSources`）。
5. **after 插件失败隔离**：消息与通知事件保留，失败以 `AfterPostPluginFailed` 记录，不把原始 `bytes` 写入事件。
6. **只读面无写权限**：28 个只读入口没有状态修改或外部状态调用；`canPost` 对 source 失败返回原因而不是回滚。

## 六、接口对账

| 项 | 结果 |
| --- | --- |
| ABI 函数 | 35 vs 35，0 差异 |
| 函数名 / 入参 / 返回值 | 全等 |
| mutability | 全等（`view`） |
| 实现多出的 ABI | 无 |
| 接口多出的函数 | 无 |

5 个 public constant/immutable getter（`GROUP_ADDRESS`、`GROUP_ADMIN_ADDRESS`、`PHASE_ADDRESS`、`MAX_CONTENT_LENGTH`、`MAX_MENTIONED_SENDER_IDS`）均在 `IGroupChat` 声明；`currentRound` 为 `public view`，接口为 `external view`，selector 与返回一致。

## 七、测试覆盖

- 鉴权顺序：`testT010`、`testT010B`、`testT014`、`testT015`、`testT209`。
- `post`：`testT040`、`testT042`、`testT042B`、`testT049`、`testT070G`、`testT071`、`testT072`、`testT075`、`testT076`。
- 配置 setter：`testT013`、`testT070D`、`testT070E`、`testT070F`、`testT073`。
- 查询/分页：`testT011B`、`testT011C`、`testT050`、`testT051`～`testT055`、`testT060`～`testT068`、`testT083`～`testT086`。
- 全仓：`forge test` → 151 passed / 0 failed / 0 skipped。

## 八、取证

- `matt-gov/review/group-chat-api-auth-2026-11/evidence/output.txt`
- `python3 matt-gov/review/group-chat-api-auth-2026-11/evidence/auth_scan.py`
- `bash matt-gov/script/check_caller_auth.sh src`
