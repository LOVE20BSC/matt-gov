# group-chat 仓事件赋值与发射专项审查

> 范围 `group-chat/src/` 全部 16 个实现源文件 + 16 个接口文件  
> 基线 `group-chat@e982df8`（`chore(deps): bump lib/action to the core error-review fixes`，工作树干净）  
> 审查日期 2026-11-03–11-04  
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`matt-gov/docs/specs/group-chat/00–08`、`group-chat/script/events/{event-families,events-baseline}.txt`

## 一、这份报告回答什么

对 group-chat 仓**每一个合约**，把**每一个事件**在合约内的**全部赋值来源与发射点**摊开，逐字段标注「这个值从哪来、在什么状态写入之后发、和哪条事件构成父子/依赖序」，再按事件规范给结论。

| 文档 | 对象 | 事件 | 发射点 | 独立发现 |
| --- | --- | --- | --- | --- |
| [01-group-chat.md](01-group-chat.md) | `GroupChat`（contract） | 9 | 9 | 3 P3 |
| [02-group-admin.md](02-group-admin.md) | `GroupAdmin`（contract） | 1 | 2 | 0（关联 `GL-EV-2/3/4`） |
| [03-group-member.md](03-group-member.md) | `GroupMember`（contract） | 1 | 1 | 0（关联 `GL-EV-2/4`） |
| [04-group-chat-ban-list.md](04-group-chat-ban-list.md) | `GroupChatBanList`（contract） | 1 | 1 | 0（关联 `GL-EV-2/4`） |
| [05-gov-voted-ban-source.md](05-gov-voted-ban-source.md) | `GovVotedBanSource`（contract） | 2 | 2 | 1 P2 + 1 P3 |
| [06-token-managers.md](06-token-managers.md) | `TokenScopeManagerBase` + `TokenMainManager` + `TokenGovManager` | 1 | 1（2 个运行时发射者） | 0 |
| [07-token-action-managers.md](07-token-action-managers.md) | `TokenActionScopeManagerBase` + `TokenActionMainManager` + `TokenActionGovManager` | 1 | 1（2 个运行时发射者） | 0 |
| [08-no-event-modules.md](08-no-event-modules.md) | 3 个 source、`ManagerBase`、`TokenManagerBase`、接口 | 0 | 0 | 0 |
| **合计** | 16 个实现源文件 + 16 个接口 | **16 个唯一事件名 / 18 条 ABI 条目** | **17** | **1 P2 + 8 P3** |

> 逐合约独立发现合计 1 P2 + 4 P3（含补录的 `GC-EV-3`）；跨合约的 4 条 P3（`GL-EV-1`–`GL-EV-4`）只记在本 README，并在相关合约报告中以「关联项」引用。
>
> 计数口径：**17 个静态 `emit` 站点 / 16 个唯一事件名 / 9 个运行时发射合约**。**18 是 `events-baseline.txt` 的 ABI 基线行数**（`TokenGroupActivated`、`TokenActionGroupActivated` 各由两个 concrete Manager 声明一份），不是发射点数。A2 落地后总表见 §十二。

### 合约 → 报告映射

| 实现合约 | 类型 | 报告 |
| --- | --- | --- |
| `GroupChat` | 有事件 | `01-group-chat.md` |
| `GroupAdmin` | 有事件 | `02-group-admin.md` |
| `GroupMember` | 有事件 | `03-group-member.md` |
| `GroupChatBanList` | 有事件 | `04-group-chat-ban-list.md` |
| `GovVotedBanSource` | 有事件 | `05-gov-voted-ban-source.md` |
| `TokenScopeManagerBase`（abstract） | 有事件（`TokenGroupActivated` 发射点） | `06-token-managers.md` |
| `TokenMainManager` | 有事件（继承 `TokenScopeManagerBase`） | `06-token-managers.md` |
| `TokenGovManager` | 有事件（继承 `TokenScopeManagerBase`） | `06-token-managers.md` |
| `TokenActionScopeManagerBase`（abstract） | 有事件（`TokenActionGroupActivated` 发射点） | `07-token-action-managers.md` |
| `TokenActionMainManager` | 有事件（继承 `TokenActionScopeManagerBase`） | `07-token-action-managers.md` |
| `TokenActionGovManager` | 有事件（继承 `TokenActionScopeManagerBase`） | `07-token-action-managers.md` |
| `ManagerBase`（abstract） | 无事件 | `08-no-event-modules.md` |
| `TokenManagerBase`（abstract） | 无事件 | `08-no-event-modules.md` |
| `AdminBanSource` | 无事件 | `08-no-event-modules.md` |
| `GroupJoinScopeSource` | 无事件 | `08-no-event-modules.md` |
| `GroupMemberScope` | 无事件 | `08-no-event-modules.md` |

## 二、结论

| 项 | 值 |
| --- | --- |
| ABI 事件条目 | 18（`TokenGroupActivated` / `TokenActionGroupActivated` 各由两个 Manager 声明，与 `events-baseline.txt` 一致；**这是 ABI 行数，不是发射点数**） |
| 唯一事件名 | 16（`event-families.txt` 16 行；A2 后 17） |
| 发射点 | **17 个静态 `emit` 站点**，分布在 **9 个运行时发射合约** |
| P0（资金损失 / 事件可被真实状态所有者伪造且不可区分） | 0 |
| P1（折叠结果与链上状态不一致且可触发） | 0 |
| P2（规范 MUST/SHOULD 违反，需书面理由或修复） | **1**（`GVB-EV-1`），已由 A2 落地关闭 |
| P3（可观测性 / 测试 / 登记缺口，不阻塞） | **8** |
| 放行 | **放行**：`GVB-EV-1` 已按 A2 拆分 `SenderBanVoteCleared`（`prevSupportBan` / `prevSettledWeight` 携带旧值），`SenderBanVoteCast` 的 topic0 保持不变；其余 8 条 P3 已按本卷逐条补测试或登记 |

一句话：**事件覆盖是完整的**——17 个静态发射点覆盖了 group-chat 侧全部业务可变状态写入面（逐合约见各报告第四节），没有「写了、既不报、也无法推导」的字段，也没有「一条事件两个语义」的复用。原问题集中在三类：(a) 撤票/刷新归零复用 `SenderBanVoteCast` 的零哨兵（`GVB-EV-1`，A2 已拆为 `SenderBanVoteCleared`）；(b) 4 处事件测试断言不完整（`AfterPostPluginFailed`、动态上限成功侧、撤票/解封/多 voter 事件、托管激活存在性）；(c) 4 条跨合约的测试/登记缺口（emitter 3/16、`Uint256Set` 页序、`operatorId ≡ groupId`、幂等零日志）。合计 **9 条 = 1 P2 + 8 P3**。

## 三、方法与边界

做了什么：

1. 逐文件读完 `src/` 下 16 个实现源文件与 16 个接口，逐事件建立「字段 → 赋值来源（源码行）→ 语义」表，再补「前置写入」与「紧随其后的动作」。
2. 读完 `libs/src/Uint256Set.sol` 的 `add` / `remove` / `values`，确认 `remove` 是 swap-and-pop；这是 `GL-EV-2` 与各合约枚举顺序判断的依据。
3. 跑 `python3 script/events/check-events.py`，审查基线结果 `event manifest OK: 18 events; families OK; declaration style OK; emit style OK; emit keys OK`；A2 落地后为 19 events（见 §十二）。
4. 跑 `forge test --summary`，13 个测试套件共 **151 passed / 0 failed**；逐条读事件相关用例（`GroupChatLifecycle` / `GroupChatMessages` / `GroupChatPlugins` / `GroupAdmin` / `GroupMemberScope` / `AdminBanSource` / `GovVotedBanSource` / `TypedManagers`）并把断言对到各报告第七节。
5. 对「同一交易内 Phase 不会变化」「unchecked 区间」「`Uint256Set` 页序」等结论做代码级验证，而不是推断。
6. 量测 emitter 断言（基线 e982df8）：`test/` 下 `vm.recordLogs` **35** 处、审查时工作树 **36** 处、`vm.expectEmit` **0** 处、`.emitter` 断言 **3 处 / 3 个事件类**（`GroupAdmin.t.sol:238`、`TypedManagers.t.sol:600/617`）。本卷落地后 `recordLogs` **47** 处、`.emitter` **33 处 / 17 个事件类**（`expectEmit` 仍为 0）。

没有做（明确边界）：

- ERC-20 / ERC-721 标准事件（`Transfer` 等）：§9 不属本规范正文；只在需要回连时提及。
- 错误语义与鉴权（`GroupChat` 的 source 失败、`canPost` 边界、owner/admin 鉴权）：见同日 `group-chat-state-mutation-review-2026-11/` 与 `group-chat-api-auth-2026-11/`（后者正在生成）。
- 事件的**经济语义**：group-chat 无金额事件；`GovVotedBanSource` 的权重公式只核对「事件是否忠实表达实现算出的值」，不重审阈值经济性。
- 测试/脚本的 emit 写法：`check-events.py` 已扫描；本报告只核对「有无断言」与关键字段，不逐条审测试写法。

## 四、全仓事件总表

> 行号为**审查基线 e982df8**。A2 落地后 `GovVotedBanSource` 的 3 条事件行号与新增 `SenderBanVoteCleared` 见 §十二。

| # | 事件 | 发射者 | 族 | 发射点 | 本报告 |
| --- | --- | --- | --- | --- | --- |
| 1 | `GroupChatActivated` | GroupChat | gc.management | `GroupChat:135` | 01 |
| 2 | `PostingAllowedChanged` | GroupChat | gc.management | `GroupChat:161` | 01 |
| 3 | `ScopeSourceChanged` | GroupChat | gc.management | `GroupChat:554` | 01 |
| 4 | `BanSourceChanged` | GroupChat | gc.management | `GroupChat:563` | 01 |
| 5 | `BeforePostPluginChanged` | GroupChat | gc.management | `GroupChat:591` | 01 |
| 6 | `AfterPostPluginChanged` | GroupChat | gc.management | `GroupChat:600` | 01 |
| 7 | `MessagePosted` | GroupChat | gc.message | `GroupChat:938` | 01 |
| 8 | `SenderMentioned` | GroupChat | gc.message | `GroupChat:258` | 01 |
| 9 | `AfterPostPluginFailed` | GroupChat | gc.plugin | `GroupChat:284` | 01 |
| 10 | `AdminChanged` | GroupAdmin | gc.management | `GroupAdmin:97`、`:125` | 02 |
| 11 | `MemberStatusChanged` | GroupMember | gc.management | `GroupMember:81` | 03 |
| 12 | `AdminSenderBanChanged` | GroupChatBanList | gc.management | `GroupChatBanList:119` | 04 |
| 13 | `SenderBanVoteCast` | GovVotedBanSource | gc.ban-vote | `GovVotedBanSource:298` | 05 |
| 14 | `GovSenderBanChanged` | GovVotedBanSource | gc.ban-vote | `GovVotedBanSource:319` | 05 |
| 15 | `TokenGroupActivated` | TokenMainManager、TokenGovManager | gc.link | `TokenScopeManagerBase:89` | 06 |
| 16 | `TokenActionGroupActivated` | TokenActionMainManager、TokenActionGovManager | gc.link | `TokenActionScopeManagerBase:134` | 07 |

族分布：`gc.management` 9、`gc.ban-vote` 2、`gc.message` 2、`gc.plugin` 1、`gc.link` 2；合计 16 个唯一事件名、17 个静态发射点、9 个运行时发射合约（5 个有事件合约 + 4 个 concrete Manager）。`events-baseline.txt` 18 行 = 16 + `TokenGroupActivated` / `TokenActionGroupActivated` 各多一份 concrete Manager 声明；**18 是 ABI 行数，不是发射点数**。

## 五、发现索引

### P2（1 条）

| 编号 | 标题 | 位置 | 处置 |
| --- | --- | --- | --- |
| GVB-EV-1 | 撤票与刷新归零复用 `SenderBanVoteCast`，用 `settledWeight = 0` 表达「无票」 | `05` §六 | **A2 已落地**：拆出 `SenderBanVoteCleared`，归零路径由新事件携带 `prevSupportBan` / `prevSettledWeight`；`SenderBanVoteCast` 的 topic0 保持 `0x3bc5296d…` |

逐条说明：

- **`GVB-EV-1`**：`_clearVoteIfFound:243-244` 与 `_refreshVoteIfFound:275-279` 在删票后调用 `_settleVote(..., false, 0, ...)`；`_settleVote:298-306` 原样写入 `supportBan=false`、`settledWeight=0`。`_setVoteIfChanged:198-200` 已禁止零权重投票，因此 `settledWeight == 0` 只表示「票已删除」，是 §3.6 禁止的「用哨兵值表达不存在」。`supportWeight` / `opposeWeight` 后置总量仍正确，影响是折叠语义，不是资金或权限；但这是 MUST 级规范违反，需要书面例外或修复。详见 `05-gov-voted-ban-source.md` §六。

### P3（8 条）

| 编号 | 标题 | 位置 | 类别 |
| --- | --- | --- | --- |
| GC-EV-1 | `AfterPostPluginFailed` 的 `pluginAddress` 未断言，`messageId` / `round` 在用例中同值，短错误数据未覆盖 | `01` §六 | 测试断言 |
| GC-EV-2 | `content` 4096 / 提及 32 的上限成功侧没有用例，只有 `max + 1` 失败（且 33 条用重复 ID） | `01` §六 | 边界测试 |
| GC-EV-3 | 托管激活只断言「最后一条」link 事件，`GroupChatActivated` 完全缺失时测试仍通过 | `01` §六 | 测试断言 |
| GVB-EV-2 | 撤票/刷新归零、`GovSenderBanChanged(listed=false)`、多 voter 后置总量没有事件断言 | `05` §六 | 测试断言 |
| GL-EV-1 | §4.1「测试必须断言 emitter」只覆盖 3/16 事件类 | `README` §六 | 门禁缺口 |
| GL-EV-2 | `Uint256Set` 枚举页序只能靠重放 swap-and-pop 还原，事件流不携带位置 | `README` §六 | 折叠路径 |
| GL-EV-3 | `operatorId ≡ groupId` 的协议恒等未在 §8.1 登记，测试无法区分两字段 | `README` §六 | 登记缺口 |
| GL-EV-4 | `GroupAdmin` / `GroupMember` / `GroupChatBanList` 的幂等零日志分支没有测试 | `README` §六 | 测试断言 |

按类别统计（8 条）：测试断言 5（`GC-EV-1`、`GC-EV-2`、`GC-EV-3`、`GVB-EV-2`、`GL-EV-4`）、边界测试计入 `GC-EV-2`、门禁缺口 1（`GL-EV-1`）、折叠路径 1（`GL-EV-2`）、登记缺口 1（`GL-EV-3`）。

> 计数由 8 条补成 9 条：原卷自报 8 条 = 1 P2 + 7 P3；本次复核补录 `GC-EV-3`（`01-group-chat.md:297` 的托管激活存在性断言），合计 **9 条 = 1 P2 + 8 P3**。

### 各 P3 的落地位置

- `GC-EV-1`：`01-group-chat.md` §六；`test/GroupChatPlugins.t.sol:409-484`（`T072` priming + `topics[1..3]`/`round`/`emitter`）、`:485-512`（`T075`）、`:513-540`（`T076`）、`:541-560`（`T076B` 短错误）；`test/mocks/MockPlugins.sol` 新增 `MockAfterPostShortErrorPlugin`。
- `GC-EV-2`：`01-group-chat.md` §六；`test/GroupChatMessages.t.sol:601-616`（`T086` 改用互不相同 ID）、`:618-656`（`T086B` 4096 字节正文 + 32 提及成功侧）。
- `GC-EV-3`：`01-group-chat.md:297`；`test/TypedManagers.t.sol:592-613`、`:614-637` 两个 helper（新增 `logs.length == 2` 与 `GroupChatActivated` 存在性/下标断言）。
- `GVB-EV-2`：`05-gov-voted-ban-source.md` §六；`test/GovVotedBanSource.t.sol:221-297`（`T131E` 多 voter `SenderBanVoteCast` 后置总量 + `GovSenderBanChanged(listed=false)`）。
- `GL-EV-1`：本 README §六；已给 13 个缺失事件类各补一行 emitter 断言（`GroupChat` 9 类、`GroupMember` / `GroupChatBanList` / `GovVotedBanSource` 各 1 类；`SenderBanVoteCleared` 随 A2 一并断言）。
- `GL-EV-2`：`02` / `03` / `04` / `05` 的「关联项」；`libs/src/Uint256Set.sol:23-37`；已登记到 `docs/specs/group-chat/04-query.md:32`。
- `GL-EV-3`：`01` / `02` 的「关联项」；`GroupChat:687-696`、`GroupAdmin:184-193`；已登记到 `docs/event-standards.md` §8.1 与 `.scratch/events-spec/03-migration-status.md:106-114`。
- `GL-EV-4`：`02` / `03` / `04` 的「关联项」；`GroupAdmin:93-95`、`GroupMember:79-88`、`GroupChatBanList:116-126`；新增 `test/GroupAdmin.t.sol:75-91`（`T129B2`）、`test/GroupMemberScope.t.sol:99-117`（`T133B3`）、`test/AdminBanSource.t.sol:93-109`（`T120C`）。

## 六、跨合约项详情

### GL-EV-1：`emitter` 断言的执行缺口

§4.1 末句是 MUST：「运行时 emitter 必须是状态所有者，**测试必须断言 emitter 地址**」。当前 group-chat 的落地（量测口径：`test/` 下 `grep`，基线 e982df8）：

| 指标 | 数量（基线 e982df8） | 本卷落地后 | 说明 |
| --- | --- | --- | --- |
| `vm.recordLogs` | 35（审查时工作树 36） | **47** | 事件断言主要形态 |
| `vm.expectEmit` | 0 | **0** | 无 4 参/5 参 `expectEmit`；emitter 一律手工断言 |
| 手工 `.emitter` 断言 | **3** | **33** | 基线 `GroupAdmin.t.sol:238`（`AdminChanged`）、`TypedManagers.t.sol:600` / `:617`（两个 link helper；本卷加 GC-EV-3 断言后为 `:606` / `:629`） |
| 有 emitter 断言的事件类 | **3 / 16** | **17 / 17** | `AdminChanged`、`TokenGroupActivated`、`TokenActionGroupActivated` 为基线已有；其余 13 类 + `SenderBanVoteCleared` 本卷补齐 |
| 缺 emitter 断言的事件类 | **13 / 16** | **0** | `GroupChatActivated`、`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged`、`MessagePosted`、`SenderMentioned`、`AfterPostPluginFailed`、`MemberStatusChanged`、`AdminSenderBanChanged`、`SenderBanVoteCast`、`GovSenderBanChanged` |

- 结论：group-chat 不是「0 处事件断言」——基线有 35 个 `recordLogs` 块、大量 `topics[0]` / `data` 断言，也已有 3 处手工 emitter 断言；缺口是「13 个事件类只要在既有 `recordLogs` 块各补一行 `assertEq(log.emitter, address(...))`」。本卷已按此闭合到 17/17。
- 与既有审查的差异：`matt-gov/review/action-events-audit-2026-11/README.md:146` 的表格把 group-chat 的 emitter 断言记为 0；本次以基线 e982df8 实测为 **3 处 / 3 个事件类**（口径：`vm.expectEmit = 0`，全部为手工 `.emitter` 断言）。以本次实测为准，建议该表后续同步更正。
- 门禁取舍：`check-events.py` 目前没有 `expectEmit` 规则，group-chat 也全仓不使用 `expectEmit`；因此本卷选择**补测试断言**而非移植 action 仓的「`recordLogs` 后必须出现带 emitter 的 `expectEmit`」门禁。若要防止回退，可在后续单独加静态检查。

### GL-EV-2：`Uint256Set` 枚举页序需要重放 swap-and-pop

`Uint256Set.remove`（`libs/src/Uint256Set.sol:23-37`）在删除中间元素时把末位搬到被删位置；`values(offset, limit, reverse)`（`:47-53`）直接分页当前 `items` 数组。因此以下视图的页序是**当前存储顺序**，不是插入序或事件时间序：

| 合约 | 视图 | 内部集合 | 事件事实 |
| --- | --- | --- | --- |
| GroupAdmin | `adminIds(groupId)` | `adminIds.items` | `AdminChanged` 只给成员增删 |
| GroupMember | `memberIds(groupId, offset, limit, reverse)` | `memberIds.items` | `MemberStatusChanged` 只给成员增删 |
| GroupChatBanList | `senderIdBanList(groupId, offset, limit, reverse)` | `senderIdBanList.items` | `AdminSenderBanChanged` 只给封禁/解封 |
| GovVotedBanSource | `votedSenderIds`、`votersBySenderId` | `senderIdTargets.items`、`target.voters.items` | `SenderBanVoteCast` / `GovSenderBanChanged` 只给投票/名单变化 |

- 现状：`08-testing.md:14` 已把 `reverse` 的视图行为登记为「当前存储顺序」，并有 `testT123B_banListReverseWalksCurrentStorageOrder`、`testT135B_votedSenderIdsReverseWalksCurrentStorageOrder`、`testT135C_votersBySenderIdReverseWalksCurrentStorageOrder`、`testT133B_adminCanAddAndRemoveMemberIds` 覆盖。
- 缺口：**事件侧**没有登记「重建页序必须重放 `Uint256Set.add/remove` 的 swap-and-pop，不得按事件时间序拼接」。§3.3 的「事件折叠 = view」在成员集合层面成立，在页序层面需要重实现库；这与 action 仓 `AT-2` 同型。
- 建议：在 `event-standards.md` §6.9 的派生缓存清单或 `docs/specs/group-chat/04-query.md` 补一句「`Uint256Set` 枚举页序为当前存储顺序；事件折叠需按 add/remove 的 swap-and-pop 重放」；若页序是业务契约，考虑改用 append-only 索引。

### GL-EV-3：`operatorId ≡ groupId` 的协议恒等未登记

- 证据：`GroupChat.onlyGroupOwner:687-696` 要求 `operatorId == groupId`；`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged` 都使用该 modifier；`GroupAdmin.onlyGroupOwner:184-193` 同样要求 `operatorId == groupId`，`AdminChanged.operatorId` 恒为 `groupId`。测试如 `GroupChatLifecycle.t.sol:174-176`、`GroupChatPlugins.t.sol:184-186`、`:238-240`、`GroupAdmin.t.sol:50-52` 都用 owner 路径，`groupId` 与 `operatorId` 同值。
- 问题：§8.1 要求协议上恒等的成对字段在恒等对清单登记理由；当前只登记了 `GroupChatActivated.ownerId ≡ groupId`，未登记这些 `operatorId ≡ groupId`。测试把两个同类型字段互换仍会通过，属于「无法区分」的夹具。
- 影响：不是行为缺陷（两字段恒等，互换无语义差异），但会让事件契约误以为 `operatorId` 能表达「哪个操作者」；实际 owner 路径上它只是 `groupId` 的副本。若未来支持 admin 操作这些配置，字段才有多值意义。
- 建议：在 §8.1 恒等对清单补一行「`GroupChat` 配置事件 / `AdminChanged` 的 `operatorId` 在 owner 路径恒等于 `groupId`，理由是事件字段保留且 `onlyGroupOwner` 强制相等」；或在规格中明确 `operatorId` 只是 `groupId` 的同义字段。

### GL-EV-4：幂等零日志断言只覆盖部分合约

| 合约 | 幂等分支 | 代码 | 现有测试 | 零日志断言 |
| --- | --- | --- | --- | --- |
| GroupChat | `setPostingAllowed` 同值、`_setSource` 同地址、`_setPostPlugin` 同地址 | `:155-157`、`:547-549`、`:584-586` | `GroupChatLifecycle.t.sol:161-165`、`GroupChatPlugins.t.sol:191-195`、`:245-249` | 有 |
| GovVotedBanSource | 权重/方向未变刷新 | `:207-209`、`:270-273` | `GovVotedBanSource.t.sol:176-178` | 有（零日志） |
| GroupAdmin | 已存在且快照不变 | `:93-95` | 无 | **无** |
| GroupMember | 已在名单再次添加 / 不在名单再次移除 | `:79-88` | `GroupMemberScope.t.sol:41-42` 再次添加但未记录日志 | **无** |
| GroupChatBanList | 已封禁再次封禁 / 未封禁再次解封 | `:116-126` | `AdminBanSource.t.sol:177-178` 再次封禁但未记录日志 | **无** |

- 影响：若将来在这些分支误发事件，现有测试不会失败；§8.1 的「发射次数/发射条件」在这些合约上没有回归网。
- 建议：在现有重复添加/重复封禁用例前后加 `vm.recordLogs()` + `getRecordedLogs().length == 0`，或在同一用例内断言日志数量。

## 七、§6.8 动态字段上限矩阵

§6.8 要求「事件中的每个 `string` / `bytes` / 数组字段必须有链上强制上限」。16 个唯一事件里只有 `MessagePosted` 含动态字段；`AfterPostPluginFailed` 用固定宽度指纹替代 `bytes`。

| 事件 | 字段 | 上限 | 链上常量 / 强制点 | 测试 |
| --- | --- | --- | --- | --- |
| `MessagePosted` | `content` | 4096 字节 | `MAX_CONTENT_LENGTH:16`；`_post:229-231` | `max + 1` 失败 + 恰好 4096 成功（`testT086B`）；已闭合 `GC-EV-2` |
| `MessagePosted` | `mentionedSenderCount` | 32（子事件条数） | `MAX_MENTIONED_SENDER_IDS:17`；`_checkMentionedSenderIds:837-839` | 32 条互不相同成功 + 33 条互不相同失败（`testT086B` / `testT086`）；已闭合 `GC-EV-2` |
| `AfterPostPluginFailed` | `errorHash` / `errorLength` / `errorSelector` | 固定宽度（`bytes32` / `uint256` / `bytes4`） | `_post:278-290`；不写原始 `bytes` | 4 字节错误 + 2 字节短错误（`errorLength=2`、`errorSelector=0`，`testT076B`）；已闭合 `GC-EV-1` |
| 其余 13 个事件 | 无 `string` / `bytes` / 数组 | 不适用 | — | — |

`MessagePosted` 的 `mentionedSenderIds` 本身不在事件 payload 中，只以子事件 `SenderMentioned` 表达，条数由 `MAX_MENTIONED_SENDER_IDS = 32` 约束；`GroupChatActivated` 的四个地址槽位是定长；`AdminChanged` 的六个地址/布尔字段是定长。

## 八、正面结论

以下 8 条是本次审查确认「做对了、且值得保持」的设计，建议在后续改动中不要回退：

1. **零遗漏覆盖**：17 个静态发射点（9 个运行时发射合约）覆盖全部业务可变状态写入面；`GroupChat` 17 个业务写入面、`GroupAdmin` 3 个、`GroupMember` 1 个、`GroupChatBanList` 2 个、`GovVotedBanSource` 6 个、两个 Manager 各 3 个，均有承载事件或 §6.9 派生缓存。没有「写了、既不报、也无法推导」的字段。
2. **一条事实一个发射者**：16 个唯一事件名对应 18 个 ABI 条目（18 只是 ABI 行数）；唯一的多发射者是 §4.2 登记的共享类 `TokenGroupActivated` / `TokenActionGroupActivated`；没有任何事件被两个语义复用。A2 后为 17 / 19。
3. **声明与发射写法全绿**：`check-events.py` 报 `18 events; families OK; declaration style OK; emit style OK; emit keys OK`（A2 后 `19 events`）；所有事件声明在发射者/共享 interface，无 anonymous、无 catch-all。
4. **状态写入后 emit**：17 个静态发射点（A2 后 18 个）的前置写入逐条见各报告第二节；无「先发后写」；配置 setter 同值/同地址 no-op 零日志。
5. **父子和依赖序**：`MessagePosted` → `SenderMentioned` → `AfterPostPluginFailed` 由 `testT048` / `testT072` 断言；`SenderBanVoteCast` / `SenderBanVoteCleared` → `GovSenderBanChanged` 由 `testT130C` / `testT131E` 断言；托管群 `GroupChatActivated` → `TokenGroupActivated` / `TokenActionGroupActivated` 由 `TypedManagers` 两个 helper 同时断言存在性、下标与 emitter（`GC-EV-3` 已闭合）。
6. **派生态有来源**：`firstActivatedOwner` / block / timestamp 由 `GroupChatActivated` + 日志元数据推导；管理员有效性由 `AdminChanged` 快照 + core ERC-721 `Transfer` 推导；消息四类索引、`_groupIds`、Manager 两向映射和 `_mintNonce` 均有 §6.9 来源。
7. **捕获型失败唯一且信息充分**：`AfterPostPluginFailed` 是唯一捕获型失败事件，命名 `<Object>Failed`，携带 `pluginAddress` + `errorHash` + `errorLength` + `errorSelector`；after 插件失败不回滚消息，before 插件失败整笔回滚，符合 `03-posting.md`。
8. **动态字段有界**：`MessagePosted.content` 4096、提及 32 条；`AfterPostPluginFailed` 不写无界 `bytes`；其余事件无动态字段。

## 九、测试与门禁复现

```bash
cd group-chat

# 1) 事件清单、族覆盖、声明与发射写法
python3 script/events/check-events.py
# → 基线 e982df8: event manifest OK: 18 events
# → A2 落地后: 19 events; event families OK: 17 protocol events

# 2) 发射点总数（静态 emit 语句）
grep -rn "emit " src/ | wc -l
# → 基线 17（9 个运行时发射合约）；A2 落地后 18
# 注意：events-baseline.txt 的 18 行是 ABI 行数，不是发射点数

# 3) 事件断言形态
grep -rn "vm.recordLogs" test/ | wc -l  # → 基线 35（审查时工作树 36）；本卷后 46
grep -rn "vm.expectEmit" test/ | wc -l  # → 0
grep -rn "\.emitter" test/ | wc -l      # → 基线 3；本卷后 33（17 个事件类全覆盖）

# 4) 全量测试
forge test --summary
# → 基线 151 passed, 0 failed（13 个套件）；本卷新增用例后见 §十二
```

## 十、与既有审查的关系

| 既有文档 | 关系 |
| --- | --- |
| `matt-gov/review/group-chat-state-mutation-review-2026-11/`（同基线 e982df8） | 状态变量变更视角。本次是事件视角，两者互补：该审查的 `GCH-01`（`canPost` 不检查 `RoundNotStarted`）、`GCH-03`（source 返回畸形数据不进入 `try/catch`）等 Info 不属于事件缺陷，本次只在 `01` 的「没有做」边界中引用，不重复登记 |
| `matt-gov/review/action-events-audit-2026-11/` | action 仓同型审查。本次沿用其报告结构（结论表 → 事件总览 → 逐事件赋值链 → 状态覆盖 → 规范对照 → 发现 → 测试对照），便于跨仓比对「共享事件类」「emitter 断言」「Uint256Set 顺序」等口径 |
| `matt-gov/review/core-events-audit-2026-11/` | core 仓同型审查；group-chat 的 `MemberMinted` / ERC-721 `Transfer` 折叠依赖 core 侧事件 |
| `matt-gov/docs/event-standards.md` v1.1 | 判据。本次提出的登记类建议（`GVB-EV-1`、`GL-EV-2`、`GL-EV-3`、`GL-EV-1`）落在 §3.6 / §6.9 / §8.1 / §4.1 四处 |
| `matt-gov/docs/specs/group-chat/00–08` | 模块规格。`05-chat-types.md:38-44` 的撤票/刷新/权重规则是 `GVB-EV-1` 的直接依据；`08-testing.md:14` 已登记 swap-and-pop 视图行为，本次补充事件折叠侧要求 |

## 十一、放行条件

1. ~~**修复或书面豁免 `GVB-EV-1`**~~：已按 **A2** 拆分 `SenderBanVoteCleared`，`SenderBanVoteCast.topic0` 保持不变。
2. ~~**补 `GVB-EV-2` / `GC-EV-1` / `GC-EV-2` 的事件断言**~~：已补（`T131E`、`T072`/`T075`/`T076`/`T076B`、`T086`/`T086B`）。
3. ~~**补 `GL-EV-1` 的 emitter 断言**~~：已给 13 个事件类补行，现 17/17 事件类有 emitter 断言。
4. ~~**登记 `GL-EV-2` / `GL-EV-3` / `GL-EV-4`**~~：已登记到 `04-query.md`、`event-standards.md` §8.1 / `03-migration-status.md`，并补三个幂等零日志测试。
5. **补录 `GC-EV-3`**：已补托管激活存在性/下标断言（`TypedManagers.t.sol` 两个 helper）。
6. 已重跑 `check-events.py`、`check_errors.py`、`check_error_tests.py`、`check_doc_payloads.py`、`check_caller_auth.py` 与 `forge test`，全部 0 失败。

## 十二、落地记录（A2，2026-11-05）

| 项 | 值 |
| --- | --- |
| 新增事件 | `SenderBanVoteCleared(uint256 indexed groupId, uint256 indexed targetSenderId, uint256 indexed voterId, bool prevSupportBan, uint256 prevSettledWeight, uint256 supportWeight, uint256 opposeWeight)` |
| topic0 | `0xb71550ca268333d35e85a302034bff25fd605b4a703a599ed5806f809320dae3`（`SenderBanVoteCast` 保持 `0x3bc5296d…`） |
| 声明 | `src/interfaces/sources/ban/IGovVotedBanSource.sol:41-49`（`SenderBanVoteCast` 声明之后） |
| 发射点 | `src/sources/ban/GovVotedBanSource.sol:315`（`settledWeight == 0` 分支）；`SenderBanVoteCast` 移至 `:325`；`GovSenderBanChanged` 移至 `:347` |
| 旧值捕获 | `_setVoteIfChanged:211-212`、`_clearVoteIfFound:247-248`、`_refreshVoteIfFound:283-284`；`_settleVote:302` 9 参签名按归零/非零分流 |
| baseline | `events-baseline.txt` 18 → **19**；`event-families.txt` 16 → **17** |
| 计数 | 静态 `emit` 17 → **18**；唯一事件名 16 → **17**；运行时发射合约仍 **9**；ABI 行 18 → **19** |
| 测试 | `T130C` / `T131` / `T131D` 事件断言同步；新增 `T131E`（旧立场/旧权重与后置总量可区分）。全仓 **158 passed / 0 failed**（审计基线 151，+7） |
| 体积 / ABI | `GovVotedBanSource` 运行时 7,423 → **7,564 B**（+141）；initcode 7,648 → **7,789 B**（+141）；ABI md5 `bf085bb4…` → `45450f14…`；其余 5 个合约 ABI md5 不变 |
