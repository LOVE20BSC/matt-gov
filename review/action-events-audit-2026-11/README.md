# action 仓事件赋值与发射专项审查

> 范围 `action/src/` 全部 14 个源文件 + 11 个接口文  
> 基线 `action@e849e36`（`chore(deps): bump lib/core to the phase event snapshot`，工作区干净）  
> 审查日期 2026-11-03  
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`matt-gov/docs/specs/action/00–08`、`action/script/events/{event-families,events-baseline}.txt`

## 一、这份报告回答什么

对 action 仓**每一个合约**，把**每一个事件**在合约内的**全部赋值来源与发射点**摊开，逐字段标注「这个值从哪来、在什么状态写入之后发、和哪条事件构成父子/依赖序」，再按事件规范给结论。

| 文档                                                           | 对象                                                   | 事件                          | 发射点    | 发现               |
| ------------------------------------------------------------ | ---------------------------------------------------- | --------------------------- | ------ | ---------------- |
| [01-action-target.md](01-action-target.md)                   | `ActionTarget`（contract）                             | 4                           | 5      | 3 P3             |
| [02-group-action-executor.md](02-group-action-executor.md)   | `GroupActionExecutor`（contract，3 个库的宿主）              | 1 + 17 委托                   | 21     | 2 P3             |
| [03-group-action-manager.md](03-group-action-manager.md)     | `GroupActionManager`（library）                        | 4                           | 4      | 2 P3             |
| [04-group-action-join.md](04-group-action-join.md)           | `GroupActionJoin`（library）                           | 6                           | 9      | 4 P3             |
| [05-group-action-verify.md](05-group-action-verify.md)       | `GroupActionVerify`（library）                         | 7                           | 7      | 4 P3             |
| [06-group-recipients.md](06-group-recipients.md)             | `GroupRecipients`（library）                           | 2                           | 2      | 2 P3             |
| [07-group-service-executor.md](07-group-service-executor.md) | `GroupServiceExecutor`（contract，1 个库的宿主）             | 5 + 2 委托                    | 7      | 1 P2 + 2 P3      |
| [08-lp-executor.md](08-lp-executor.md)                       | `LpExecutor`（contract）                               | 5                           | 6      | 3 P3             |
| [09-no-event-modules.md](09-no-event-modules.md)             | `ExecutorBase`、两个 Storage、两条 RoundAxis、`MemberOwner` | 0                           | 0      | 0                |
| **合计**                                                       | 14 个源文件                                              | **34 条 ABI 条目 / 32 个唯一事件名** | **39** | **1 P2 + 23 P3** |

> 逐合约行合计 1 P2 + 22 P3；多出的 1 条 P3 是跨仓门禁缺口 `GL-EV-1`（不属任何单个合约），只记在本 README。

## 二、结论

| 项                              | 值                                                                                                                     |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| ABI 事件条目                       | 34（`MemberRewardMinted` 三个发射者各算一条，与 `events-baseline.txt` 一致）                                                         |
| 唯一事件名                          | 32（`event-families.txt` 32 行）                                                                                         |
| 发射点                            | 39                                                                                                                    |
| P0（资金损失 / 事件可被真实状态所有者伪造且不可区分）  | 0                                                                                                                     |
| P1（折叠结果与链上状态不一致且可触发）           | 0                                                                                                                     |
| P2（规范 MUST/SHOULD 违反，需书面理由或修复） | **1** |
| P3（可观测性/登记缺口，不阻塞） | **23** |
| 放行 | 有条件放行：1 项 P2 是事件顺序（`GSE-EV-1`，修复成本为一次代码块搬移）；2 条「库地址可伪造事件」的原判已由字节码实测否定并撤除，见 §五 |

一句话：**事件覆盖是完整的**——39 个发射点覆盖了 action 侧全部可变状态写入面（逐合约 3–17 处，合计 80 余处，逐条见各报告第四节），没有「写了、既不报、也无法推导」的字段，也没有「一条事件两个语义」的复用。问题集中在三类：(a) 2 处「事件早于转账」（`GAJ-EV-2`/`GAJ-EV-3` 与 §4.4 的字面顺序有偏差）；(b) 4 处「折叠需要重实现库的存储语义」（`AT-2`、`GAV-EV-1`、`LPE-EV-1`、`LPE-EV-2`）；(c) 1 处「聚合事件晚于明细」（`GSE-EV-1`）。另有 1 条跨仓门禁缺口（`GL-EV-1`：§4.1 的「测试必须断言 emitter 地址」几乎没有落地），它不是事件本身的缺陷，而是回归探测的缺口。

## 三、方法与边界

做了什么：

1. 逐文件读完 `action/src/*.sol`（7,226 行含接口）与 `libs/src/` 中 6 个被使用的历史原语（`RoundHistoryUint256Set`、`RoundHistoryUint256`、`RoundHistoryUint256Array`、`Uint256Set`、`OrderedHistoryIndex`、`Pagination`），确认 `add`/`remove`/`record`/`value` 的精确语义——「折叠是否需要重实现库」这类判断只能靠读实现。
2. 对每条事件建立三列表：**字段 → 赋值来源（源码行）→ 语义说明**，再补第四列「前置写入」与第五列「紧随其后的动作」。
3. 跑 `python3 script/events/check-events.py`，结果 `event manifest OK: 34 events; families OK; declaration style OK; emit style OK; emit keys OK`。
4. 读四个专门的事件测试文件（`ActionTargetEvents` / `GroupActionEvents` / `GroupServiceEvents` / `LpExecutorEvents`，共 1,553 行），把每个事件的断言逐条对到第七节的表；缺口单列。
5. 对「边界不可达」类结论做代码级验证而不是推断。例：`createdRound == 0` 是 `ActionNotCreated` 的哨兵，`phase == 0` 时 `ActionRegistered.round` 也会是 0——核实 `Submit.submitNewProposal` 的顺序是 `_submitByProposalId`（触发 `Phase.sync()`，`phase == 0` 回滚 `PhaseNotStarted`）早于 `_callProposalCreated`，因此该哨兵不会与合法值撞车（`01-action-target.md` §3.1）。

没有做（明确边界）：

- ERC-20 / ERC-721 标准事件（`Transfer` / `Approval` / `ApprovalForAll`）：§9 明确不属本规范正文，只在需要回连时提及。
- `test/` 与 `script/` 的 emit 写法：只核对「有无断言」，不逐条审写法（`check-events.py` 已扫描）。
- 跨仓事件序列（`ActionRegistered` 与 core `ProposalCreated` 的先后）：属 core 侧审查，本次只记录 action 侧的依赖。
- 事件的**经济语义正确性**（金额公式、分配比例）：属 `06-service-executor.md` / `04-lp-executor.md` 的实现审查，本次只核对「事件是否忠实表达了实现算出的值」。

## 四、全仓事件总表

| #  | 事件                             | 发射者                                                | 族                    | 发射点           | 本报告 |
| -- | ------------------------------ | -------------------------------------------------- | -------------------- | ------------- | --- |
| 1  | `ActionRegistered`             | ActionTarget                                       | action.registry      | `:457`        | 01  |
| 2  | `ActionRewardMinted`           | ActionTarget                                       | action.round         | `:277`        | 01  |
| 3  | `JoinStateRegistered`          | ActionTarget                                       | action.participation | `:136`        | 01  |
| 4  | `JoinStateCleared`             | ActionTarget                                       | action.participation | `:162`、`:189` | 01  |
| 5  | `GroupActionCreated`           | GroupActionExecutor（`GroupActionManager:438`）      | action.config        | 1             | 03  |
| 6  | `GroupActivated`               | GroupActionExecutor（`GroupActionManager:493`）      | action.group         | 1             | 03  |
| 7  | `GroupDeactivated`             | GroupActionExecutor（`GroupActionManager:212`）      | action.group         | 1             | 03  |
| 8  | `GroupConfigChanged`           | GroupActionExecutor（`GroupActionManager:459`）      | action.group         | 1             | 03  |
| 9  | `GroupActionJoined`            | GroupActionExecutor（`GroupActionJoin:96`）          | action.participation | 1             | 04  |
| 10 | `GroupActionWithdrawn`         | GroupActionExecutor（`GroupActionJoin:141/195/406`） | action.participation | 3             | 04  |
| 11 | `GroupActionExited`            | GroupActionExecutor（`GroupActionJoin:808`）         | action.participation | 1             | 04  |
| 12 | `ProviderQuotaAdded`           | GroupActionExecutor（`GroupActionJoin:351`）         | action.quota         | 1             | 04  |
| 13 | `ProviderQuotaRemoved`         | GroupActionExecutor（`GroupActionJoin:417/839`）     | action.quota         | 2             | 04  |
| 14 | `ProviderQuotaRestored`        | GroupActionExecutor（`GroupActionJoin:234`）         | action.quota         | 1             | 04  |
| 15 | `OriginScoresSubmitted`        | GroupActionExecutor（`GroupActionVerify:760`）       | action.verification  | 1             | 05  |
| 16 | `VerifierApplicationSubmitted` | GroupActionExecutor（`GroupActionVerify:784`）       | action.verification  | 1             | 05  |
| 17 | `VerifierApplicationCancelled` | GroupActionExecutor（`GroupActionVerify:207`）       | action.verification  | 1             | 05  |
| 18 | `VerifierStakeDeposited`       | GroupActionExecutor（`GroupActionVerify:845`）       | action.verification  | 1             | 05  |
| 19 | `VerifierStakeRefunded`        | GroupActionExecutor（`GroupActionVerify:198`）       | action.verification  | 1             | 05  |
| 20 | `VerifierLocked`               | GroupActionExecutor（`GroupActionVerify:740`）       | action.verification  | 1             | 05  |
| 21 | `ApplicationVoteRecorded`      | GroupActionExecutor（`GroupActionVerify:802`）       | action.verification  | 1             | 05  |
| 22 | `MemberRewardMinted`           | GroupActionExecutor（自身 `:741`）                     | action.participation | 1             | 02  |
| 23 | `ServiceActionCreated`         | GroupServiceExecutor                               | action.config        | `:430`        | 07  |
| 24 | `ServiceJoined`                | GroupServiceExecutor                               | action.participation | `:131`        | 07  |
| 25 | `ServiceExited`             | GroupServiceExecutor                        | action.participation | `:384`                   | 07  |
| 26 | `ServiceRewardsDistributed` | GroupServiceExecutor                        | action.service       | `:787`                   | 07  |
| 27 | `MemberRewardMinted`        | GroupServiceExecutor（自身 `:779`）             | action.participation | 1                        | 07  |
| 28 | `RecipientPaid`             | GroupServiceExecutor（`GroupRecipients:355`） | action.service       | 1                        | 06  |
| 29 | `RecipientsChanged`         | GroupServiceExecutor（`GroupRecipients:106`） | action.recipients    | 1                        | 06  |
| 30 | `LpActionCreated`           | LpExecutor                                  | action.config        | `:123`                   | 08  |
| 31 | `LpJoined`                  | LpExecutor                                  | action.participation | `:183`                   | 08  |
| 32 | `LpWithdrawn`               | LpExecutor                                  | action.participation | `:224`、`:253`（共用 `:288`） | 08  |
| 33 | `LpExited`                  | LpExecutor                                  | action.participation | `:228`、`:257`            | 08  |
| 34 | `MemberRewardMinted`        | LpExecutor（自身 `:524`）                       | action.participation | 1                        | 08  |

## 五、发现索引

### P2（1 条）

| 编号       | 标题                                                           | 位置      | 一句话                                                                                             |
| -------- | ------------------------------------------------------------ | ------- | ----------------------------------------------------------------------------------------------- |
| GSE-EV-1 | 结算的两条聚合事件都晚于其明细 `RecipientPaid`，且不在 §3.4.6 例外清单内             | `07` §六 | `MemberRewardMinted` 的 payload 在 `:746` 已定稿却不依赖二次分配，可前移；`ServiceRewardsDistributed` 是依赖序、应登记为例外 |

> **已撤除（GAM-EV-3 / GR-EV-3，原判 P2）**：初版把「`GroupActionCreated` / `RecipientsChanged` 可从库地址直接伪造」判为 P2，理由是 4 个 `public library` 部署后有独立地址、其 `external` 写函数可被普通 `CALL` 执行。**字节码实测否定了这条推断**：Solidity 为含 `external` 函数的库在 dispatcher 前置自地址守卫（`PUSH20 <自身地址> ADDRESS EQ`），直接 `CALL` 时 `ADDRESS() == 自身地址` 成立即 revert、零日志；库的 `emit` 只有 `internal`（编译期内联）与 `external`（只能 `DELEGATECALL`）两条路径，emitter 恒为状态所有者。详见 `03` §六与 `06` §六的「已撤除的结论」。残余的纵深防御建议（这两个入口的守卫全来自入参）转由 `action-api-auth-2026-11` 的 GAM-01 / GRC-01 承接。

### P3（23 条）

| 编号       | 标题                                                                                                | 位置      | 类别         |
| -------- | ------------------------------------------------------------------------------------------------- | ------- | ---------- |
| AT-1     | 注册表事件早于 Executor 仓位账本，两种行动类型插入点不同                                                                 | `01` §六 | 跨合约顺序      |
| AT-2     | `JoinState*` 的成员集合顺序只能靠重放库实现还原                                                                    | `01` §六 | 折叠路径       |
| AT-3     | `createdRound` 在四处各写一份，同值是隐式不变式                                                                   | `01` §六 | 隐式不变式      |
| GAE-EV-1 | `MemberRewardMinted.burnAmount` 在本发射者上恒为 0                                                        | `02` §七 | 共享类空字段     |
| GAE-EV-2 | 批量结算未规定「行动级铸造只出现一次」的锚点                                                                            | `02` §七 | 批量顺序       |
| GAM-EV-1 | 三个质押聚合量只在改变点携带增量，无后置总量                                                                            | `03` §六 | §3.1 聚合量   |
| GAM-EV-2 | `deactivatedRound` 的归零只能由 §7.2 规则推导                                                               | `03` §六 | 快照字段       |
| GAJ-EV-1 | `GroupActionWithdrawn.amount` 在 `providerId != 0` 时是参与量，与 `ProviderQuotaRemoved.amount` 重复表达同一笔资金 | `04` §六 | 量纲/折叠口径    |
| GAJ-EV-2 | `removeProviderQuota` 的退款转账晚于 `GroupActionExited`                                                 | `04` §六 | §4.4 顺序    |
| GAJ-EV-3 | `addProviderQuota` 的存款转账晚于全部 `ProviderQuotaAdded`                                                 | `04` §六 | §4.4 方向    |
| GAJ-EV-4 | 「已使用额度」无后置锚点，折叠需要成员当前群归属                                                                          | `04` §六 | 折叠路径       |
| GAV-EV-1 | `scores[]` 与 `memberId` 的绑定只能靠重放 swap-and-pop                                                     | `05` §六 | 折叠路径       |
| GAV-EV-2 | `hasPreviousApplication` 的恒等对登记清单在仓库内不可得                                                          | `05` §六 | 登记缺口       |
| GAV-EV-3 | `ApplicationVoteRecorded` 的 actor 未 indexed，与同族 6 条不对称                                            | `05` §六 | indexed 布局 |
| GAV-EV-4 | `OriginScoresSubmitted.verifierId` 可能与已撤销申请并存                                                     | `05` §六 | 折叠口径       |
| GR-EV-1  | `prev*` 三组数组未在 §6.8 上限基线表登记                                                                       | `06` §六 | 登记缺口       |
| GR-EV-2  | 配置侧与付款侧都无法按收款人过滤                                                                                  | `06` §六 | indexed 布局 |
| GSE-EV-2 | `ownerRemaining` 是聚合余量，无法按源行动拆分                                                                   | `07` §六 | 折叠路径       |
| GSE-EV-3 | `action.config` 族不带 `round`，创建轮只在上游事件里                                                            | `07` §六 | 跨合约依赖      |
| LPE-EV-1 | 时间权重扣减不进事件，扣减账本未登记为派生缓存                                                                           | `08` §六 | 折叠路径       |
| LPE-EV-2 | 部分撤回的 `deductionReduction` 与剩余扣减都不进事件                                                             | `08` §六 | 折叠路径       |
| LPE-EV-3 | 共享事件的 `round` 在 LP 与 GroupAction 上相位偏移不同                                                          | `08` §六 | 共享类语义      |
| GL-EV-1  | §4.1「测试必须断言 emitter 地址」在执行层几乎没有落地（跨仓门禁缺口） | `README` §五 | 门禁缺口 |

按类别统计（23 条）：折叠路径 6（`AT-2`、`GAJ-EV-4`、`GAV-EV-1`、`GSE-EV-2`、`LPE-EV-1`、`LPE-EV-2`）、§4.4/顺序 2、登记缺口 2、indexed 布局 2、聚合量与快照 2、跨合约 2、共享类 2、量纲 1、批量 1、隐式不变式 1、折叠口径 1、门禁缺口 1。

### GL-EV-1 详情：`emitter` 断言的执行缺口

§4.1 末句是 MUST：「运行时 emitter 必须是状态所有者，**测试必须断言 emitter 地址**」。三仓的实际落地（量测口径：`test/` 下 `grep`，2026-11-03）：

| 仓 | `vm.expectEmit` 调用 | 其中带 emitter | `recordLogs` 断言块 | 手工 `.emitter` 校验 |
| --- | --- | --- | --- | --- |
| core | 10（另有 1 处本地接口声明） | **4**（5 参形式，`StakeDonation.t.sol:352/388/429/460`） | 59 / 57 | 16（多为 `if` 定位，少数 `require`） |
| action | 50（另有 5 处本地接口声明） | **0** | 29 / 29 | 11（10 处 `require` + 1 处 `_indexOf` 辅助） |
| group-chat | 0 | 0 | 36 / 36 | 0 |

- 结论：`expectEmit(address(...))` 形式三仓均为 **0 处**；4 参 `vm.expectEmit` 只比对 topic 与 data，报错是 `param mismatch`，事件真的从错误地址发出时**测试仍然绿**。
- action 并非完全没有 emitter 校验：11 处手工 `require(logs[i].emitter == address(...))` 覆盖了 `GroupActionJoined` / `ProviderQuotaAdded` / `RecipientPaid` / `LpActionCreated` / `LpJoined` 与三处 `JoinStateCleared`（`GroupActionEvents.t.sol:29/91/210/360`、`GroupServiceEvents.t.sol:32/94/190`、`LpExecutorEvents.t.sol:28/62/150/176`）。所以缺口是「50 处 `expectEmit` 里 0 处校验 emitter」，不是「完全没有」。
- group-chat 也不是「0 处事件断言」：它有 36 个 `recordLogs` 块、27 处 `topics[0]` 断言、20 处 `abi.decode` 字段断言，只是同样不校验 `emitter`。
- 建议的机械改动量是 **56 处**（action 50 + core 6），不是 66 处；group-chat 只需在既有 36 个 `recordLogs` 块各补一行 `emitter` 断言，不需要新写用例。
- 静态门禁：`check-events.py` 目前不含 library / emitter / delegatecall 规则。可加一条「`test/` 内每个 `expectEmit` 必须带 emitter，或其后 20 行内出现 `.emitter ==` 断言」，把纸面条款变成可执行门禁。

## 六、§6.8 动态字段上限矩阵

§6.8 要求「事件中的每个 `string` / `bytes` / 数组字段必须有链上强制上限」。34 条事件里 7 条含变长字段，逐条核对如下：

| 事件                             | 字段                                                | 上限                         | 链上常量                                                       | 强制点                          |
| ------------------------------ | ------------------------------------------------- | -------------------------- | ---------------------------------------------------------- | ---------------------------- |
| `GroupActionCreated`           | `verificationKeys` / `verificationDescriptions`   | 16 项 ×1024 字节              | `MAX_VERIFICATION_ENTRIES` / `MAX_VERIFICATION_TEXT_BYTES` | `GroupActionManager:98-118`  |
| `GroupActionJoined`            | `verificationValues`                              | 16 项 ×1024 字节              | 同上                                                         | `GroupActionJoin:709-724`    |
| `GroupActivated`               | `description`                                     | 1024 字节                    | `MAX_DESCRIPTION_BYTES`                                    | `GroupActionManager:399-404` |
| `GroupConfigChanged`           | `description` / `prevDescription`                 | 各 1024 字节                  | 同上                                                         | 同上（新值校验一次，旧值必然已合规）           |
| `VerifierApplicationSubmitted` | `description`                                     | 1024 字节                    | 同上                                                         | `GroupActionVerify:826-831`  |
| `OriginScoresSubmitted`        | `scores`                                          | 100 项                      | `MAX_VERIFICATION_BATCH`                                   | `GroupActionVerify:695-699`  |
| `RecipientsChanged`            | `recipientIds` / `ratios` / `remarks`             | ≤10 项；`remarks` 每条 ≤256 字节 | `DEFAULT_MAX_RECIPIENTS` / `MAX_REMARK_BYTES`              | `GroupRecipients:307-339`    |
| `RecipientsChanged`            | `prevRecipientIds` / `prevRatios` / `prevRemarks` | **未登记**（实际同界）              | 同上（间接）                                                     | 同上（同一写入口）→ `GR-EV-1`         |

另注：`GroupActionCreated.verificationKeys` 的「16 ×1024」是**事件字段上界**，创建路径还受 `ProposalCreated.targetData` 的 16 KiB 总量约束（schema 作为 `targetData[6]`），链上可达的最坏值低于该上界——§6.8 已登记这条注释。

## 七、正面结论

以下 8 条是本次审查确认「做对了、且值得保持」的设计，建议在后续改动中不要回退：

1. **零遗漏覆盖**：每一个可变状态写入面都**要么有承载事件、要么可归入 §6.9 的派生缓存**（后者如 `_deductionBy*`、`originScoreDeductionByMemberId`、分母缓存——这三处也正是 `LPE-EV-1` / `GAV-EV-1` 指出「未登记」的地方）。没有出现「写了、既不报、也无法推导」的字段。`initialized` 与 `immutable` 属 §3.2 豁免。
2. **一条事实一个发射者**：32 个事件名对应 34 个 ABI 条目，唯一的多发射者是 §4.2 登记的共享类 `MemberRewardMinted`；没有任何事件被两个语义复用。
3. **库委托路径的发射者唯一**：四个 `public` 库的 22 个发射点（4 + 9 + 7 + 2）在经 Executor `delegatecall` 调用时落在 `GroupActionExecutor` / `GroupServiceExecutor` 地址；「直接 `CALL` 库地址」被编译器的自地址守卫堵死（`PUSH20 <自身地址> ADDRESS EQ`，实测 revert、零日志），因此库的 `emit` 只有 `internal` 内联与 `external` delegatecall 两条路径，emitter 恒为状态所有者，§4.1 成立。
4. **§4.4 主路径逐字符合**：`LpExecutor` 的两条清仓路径（全额撤回、`exit`）与 `GroupActionJoin` 的 `withdraw`/`exit` 都是「清状态 → 转账 → `*Withdrawn` → `JoinStateCleared` → `*Exited`」，`testExitOrdersWithdrawnThenRegistryClearThenExited` 断言三条日志的 topic、顺序与第二条的 emitter。
5. **累计值有锚点**：`OriginScoresSubmitted.totalFinalScore` / `verifiedGroupCount` / `roundVerified`、`ApplicationVoteRecorded.voteAmountTotal`、`ProviderQuotaAdded/Removed.quotaTotal` 都是后置值，且各有「累计 = fold」或「按轮隔离」用例。
6. **数组型增量的空值语义正确**：`GroupActionJoined.verificationValues` 的空数组表示「本次无新值」，有专门用例（`GroupActionEvents.t.sol:171`），不会被误折叠成清空（§3.4.9）。
7. **零额不发事件**：`ProviderQuotaRestored` 跳过 `invested == 0`、`RecipientPaid` 跳过 `amount == 0`、`JoinState*` 在幂等分支零日志、`ApplicationVoteRecorded` 在 `voteAmount == 0` 或未指定验证者时零日志——四类「无事实」情形都不产生软失败日志（§3.5）。
8. **声明与发射写法全绿**：`check-events.py` 报 `34 events; families OK; declaration style OK; emit style OK; emit keys OK`，即 §6.11 的「一参数一行 / 具名参数 / 一 KV 一行」在 `src/` 无违例。

## 八、复现

```bash
cd action

# 1) 事件清单、族覆盖、声明与发射写法
python3 script/events/check-events.py
# → event manifest OK: 34 events; families OK; declaration style OK; emit style OK; emit keys OK

# 2) 发射点总数
grep -rn "emit " src/ | wc -l          # → 39

# 3) 四个事件测试文件
forge test --match-path 'test/*Events.t.sol'

# 4) 事件相关全量
forge test --match-test 'Event|Events' 
```

## 九、与既有审查的关系

| 既有文档 | 关系 |
| --- | --- |
| `matt-gov/review/action-api-auth-2026-11/`（9 份，同日） | 接口调用权限视角。本次是事件视角，两者互补：该审查的 GAJ-03（CEI 不完全）从重入角度讨论 `exit`/`withdraw` 的「状态清理被退款切开」，本次的 `GAJ-EV-2`/`GAJ-EV-3` 从事件顺序角度讨论同一批代码（前者判 Info 因有 `nonReentrant`，后者判 P3 因 §4.4 是事件契约）。**已同步更正**：该审查的 GAM-01「附带一条」、GRC-01 与 README G-03 原先写着「库可被直接调用并 emit 伪造事件」，该结论已被字节码实测否定；现已改为「已撤回」记录并保留机制说明，其登记项从 39 调整为 38（Info 37 → 36）、09 号报告从 4 条 Info 调整为 3 条。本报告初版的 `GAM-EV-3`/`GR-EV-3` 即由此误判，已撤除 |
| `matt-gov/review/core-events-audit-2026-11/` | core 侧同型审查（8 份逐合约 + README）。本次沿用其报告结构（结论表 → 事件总览 → 逐事件赋值链 → 状态覆盖 → 规范对照 → 发现 → 测试对照），便于跨仓比对同一事件在两侧的口径（如 `ActionRewardMinted` 与 `ProposalRewardMinted`） |
| `matt-gov/docs/event-standards.md` v1.1 | 判据。本次提出的登记类建议（`GAV-EV-2`、`GR-EV-1`、`GAM-EV-2`、`LPE-EV-3`、`GSE-EV-1`、`GL-EV-1`）落在该文档的 §6.8 / §7.2 / §4.2 / §4.1 / §3.1 五处 |