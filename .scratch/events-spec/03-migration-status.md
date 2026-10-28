# 事件迁移状态

日期：2026-10-26（2026-10-27 收尾）
规范：`matt-gov/docs/event-standards.md` v1.1  
逐事件目标：`01-gap-table.md`；覆盖矩阵：`02-coverage-matrix.md`

## 基线（迁移前）

- core：全绿（forge test）。
- action：全绿（forge test）。
- group-chat：全绿（forge test）。

## 进度

| 仓 | 状态 | 测试 | 备注 |
|---|---|---|---|
| group-chat | 完成（未提交） | 162 passed / 0 failed | 已修：`AdminChanged` 合并为单事件（新增/刷新/删除均一条）；`SenderMentioned.messageId` 改 indexed；`GroupChatActivated` 携带初始 5 项配置并移除激活时的 4 个 Set* 冗余 emit；`MessagePosted` 含 content/quote/hasQuote/mentionAll；`MentionAll` 删除；delegate 快照旧+新。 |
| core | 完成（未提交） | 474 passed / 0 failed | 23 行全部落地；复核补 `authorId`（原 `author`）；name/symbol 上限落为 `MAX_TOKEN_NAME_LENGTH=96` / `MAX_TOKEN_SYMBOL_LENGTH=32`；title/details 1024B、targetData 16 KiB/16；`VoteCast` boost 快照、`GovRewardMinted` 去 `burnReward`、删除 holder 事件。 |
| action | 完成（未提交） | 457 passed / 0 failed | 34 文件；`ActionRegistered`、三个 `*ActionCreated`、域前缀拆名、`GroupActivated` 初始 config、`GroupConfigChanged` 旧+新、`RecipientTableChanged` 旧+新+remarks、`ApplicationVoteRecorded`、`ProviderQuotaRefunded`、`VerifierLocked` indexed、LP 清仓 `LpWithdrawn`+`LpExited`、`forceClearJoinState` 仅改名；库 emit 按规范 §4.1。 |

## Review 修复（2026-10-26）

- 硬格式：改动过的 interface 中所有多参数事件声明改为每行一个参数（org `dev-standards.md` §5.1）。
- `AdminChanged`：合并为单事件，新增 `prevListed`；刷新已存在管理员时旧/新 listed 均可还原。
- `VerifierApplicationSubmitted`：新增 `hasPreviousApplication`，消除 `previousApplicationId=0` 哨兵。
- `ProposalCreated`：title/details 后置到 target/targetMode/targetData 之后；topic/测试同步。
- `GroupActionJoined`/`GroupActionWithdrawn`：groupId/providerId 前移到 amount 之前。
- `GroupConfigChanged`/`RecipientTableChanged`：整组替换改为新组→旧组；规范 §6.1 改为「替换新组→旧组，逐字段 diff 旧→新」。
- 去重：`Launch._addLaunchCount`、`Stake._govVotesOf`、`LpExecutor._emitLpTerminal`、`GovVotedBanSource` 版本事件包装；`GroupConfigChanged` emit helper 统一 memory。
- 规范 §4.4 正常退出顺序改为「clearJoinState（JoinStateCleared）→ *Exited」，与代码/Q17 父先子一致。
- ABI 基线：三仓各自 `script/check-events.py` + `script/events-baseline.txt`；checker 通过（core 28 / action 34 / group-chat 23，concrete 合约含继承的标准事件）。
- 保留的 judgement-call 未改：`GroupActionManager` 两段长度检查、stack-too-deep 的 `_emit*` 包装、`MessagePosted.hasQuote`（规范要求）、`GovSenderBanChanged` 命名（规范要求）、`Vote._vote` 分块。

## 第二轮修复（2026-10-26）

- `ApplicationVoteRecorded` 增加 `votesAdded`/`totalVotes`（增量+累计）；补 core `FeesSettled`/`PhaseAdjusted`/`ProposalSubmitted` 事件测试（core 463）。
- 删除解释性 emit 注释（保留 forge-lint/slither 指令）；规范 §6.10 明确工具指令豁免。
- 6 个 helper 移到各文件内部区；manager 事件移入 `I*Events`；Stake/Launch 剩余公式与字面量收敛；`GroupAdmin` 简化 `prevListed`；`_emitLpTerminal`→`_emitLpFullExit`。
- Checker 落到三仓 `script/check-events.py`（每次 build、按源码过滤 library/abstract/interface）；基线 28/34/23；删除 matt-gov 脚本。
- `GroupServiceMocks` `TokenBurn`→`TokenBurned`；matt-gov 当前 specs 由文档代理同步（`CHANGES-*`/ADR 历史不动）。
- 规范/差距表/覆盖矩阵/状态文档的旧名、顺序、`hasPreviousApplication`、`删除（已确认）`、派生缓存交叉引用与 `stateVersion` 说明已修；规范 §6.1 改为「默认新值→旧值；整组替换新组→旧组；迁移量 diff 旧→新」，§6.2/§6.4 增补跨 token 限定角色词。

## 第三轮修复（2026-10-27）

- group-chat 字段顺序：`AdminChanged`/`MemberStatusChanged`/`SenderBanChanged`/`DelegateChanged` 对象 id 在 actor 前；`SenderMentioned` 改为 `groupId, messageId, mentionedSenderId`；`MessagePosted` 的 `content` 后置，emit 改为从已落库 `StoredMessage` 读取以避免 stack-too-deep。
- `DelegateChanged(delegateId=0)` 保留为显式清除编码；`providerId=0` 定义为 self；规范 §3.6/§6.4 已登记。
- Checker 增加参数名/anonymous、移除 `src/interfaces/` 盲区、基线重生成（28/34/23）；三仓 `.github/workflows/events.yml` 已加。
- 新 action 错误参数名 `max`→`maxLength`/`maxCount`；helper 单行参数、空段、`I*BaseEvents` 命名、Mint 注释、Stake 剩余公式、`ApplicationVoteRecorded` emitter 断言已修（action 444）。
- 规范 §4.2 共享类清单补 manager 事件；§6.7 版本号旧值；§6.8 补 `scores`≤100 与「链上强制常量」；覆盖矩阵/差距表/acceptance/review-guide 已同步。
- 仍待：最终 review、提交/子模块同步（用户要求先不提交）。

## 收尾轮（2026-10-27）

- P1 文档：`03-participation`/`05-group-action-executor`/`08-testing`/`acceptance` 的 Provider 退出改为「自有金额发 `GroupActionWithdrawn` + 每个 Provider 发 `ProviderQuotaRefunded`」。
- `MemberMinted` 字段顺序改为 `memberId, owner, cost, name, normalizedName`；规范 §6.1 增参与类事件「memberId 在 round/groupId 前」的族规则。
- 规范 §6.8 补 `VerifierApplicationSubmitted.description`≤1024；`.scratch` 的「待写正文」改为「已写」；`core/04-stake` 补 `StakeWithdrawn.lpBurned`/`lpTransferred`。
- `_emitMessagePosted` 逐行参数/空行；`Mint` 残留注释删除；剩余 action 错误参数名统一 `maxLength`/`maxCount`/`maxScore`/`maxAmount`。
- Checker build 加 `--locked`；CI 增 `permissions: contents: read` 与 `forge test --summary`；三仓 flow 同步。
- 测试 463/445/162；checker 28/34/23；仍未 commit（按用户要求），等待最后一轮 review。

## 最终修复（2026-10-27，最后一轮 review 后）

- `RecipientPaid` 增 `sourceTokenAddress`（源行动根键）；emitter 改为 struct helper 避免栈深；测试/文档/基线同步。
- `05-group-action-executor` 的 Provider 撤回改写为「自有 `GroupActionWithdrawn(providerId=0)` + Provider 撤回带其 `providerId`」；`core/05-submit` 的 title/details/targetData 改为实际 1024B/16KiB/16；补 `08-launch`/`05`/`06` 的限额错误。
- 规范 §6.1 降为 SHOULD + 族槽位表（**已被下方「规范收敛」改为强制表**）；§6.8 补 `MemberNFT.normalizedName`、`GroupActivated.description`、`RecipientTableChanged.recipientIds/ratios`；`.scratch` 的 MemberMinted 顺序、5 项 config、O1 措辞、forceExit 现名已修。
- `DelegateChanged(delegateId=0)` 的 payload/清除断言、`ApplicationVoteRecorded` 非创建轮隔离测试已补；action 侧 `InvalidMaxJoinAmount`/`BelowMinJoinAmount` 的 `minAmount` 对齐。
- 破坏性变更登记：`VerifierLocked` topic2/data 由 round/memberId 互换；`MemberMinted` 字段顺序；`RecipientPaid` 增 `sourceTokenAddress`；group-chat 全部 topic 重建；离线消费方需重建过滤器/解码器。

## 规范收敛（2026-10-27，§3.4 / §4.4 / §6.1 上策裁决）

裁决：§6.1 选上策（重排 ABI 让族表真正成立）、§4.4 改 `LpExecutor`、`MemberNFT` 允许重入交错不加锁、`GroupDeactivated` 按普通状态迁移。

- **§3.4**：改为「依赖序 MUST + 父子序 SHOULD + E1–E4 封闭例外」；删除「父事实必须先于子事实」的无条件表述；补「累计值事件必须排在贡献事实之后」与「累计值断言 `cumulative == fold`」。
- **§4.4**：固定正常退出顺序为「executor 清自身状态 → 退款并立即发带金额的 `*Withdrawn` → `clearJoinState`（`JoinStateCleared(forced=false)`）→ `*Exited`」；`*Withdrawn` 必须早于 `JoinStateCleared`（否则朴素折叠会丢掉金额）；`*Exited` 无金额、最后发；`GroupDeactivated` 带金额且可逆，不套 E4。
- **§6.1**：族槽位表改为强制约束并逐族列明事件；新增 `action.round`、`action.quota`、`action.service`、`gc.plugin` 等族行；根键可为发射者自身（`TokenMinted`/`MemberMinted`/`PhaseSynchronized`）；`delegateId` 是 delegation 域根键。
- **代码**：`LpExecutor.withdraw`/`exit` 把 `clearJoinState` 从 `_clearJoinState` 拆出，顺序改为「清状态 → 转账 → `LpWithdrawn` → `clearJoinState` → `LpExited`」，与 `GroupActionJoin` 同形（action 测试 445→455）。`TokenGroupActivated`/`TokenActionGroupActivated` 的 `token` 参数改名 `tokenAddress`；`MemberMinted.id` 改名 `memberId`（group-chat 162 不变）。
- **E3**：`MemberNFT` 不加锁；规范写明「日志顺序 ≠ id 顺序」「`MemberMinted.owner` 是铸造接收人」；新增重入测试（内层先于外层、id 1/2、折叠 `totalBurnedForMint`）。
- **`GroupDeactivated`**：规范写明可逆，新增 `deactivate → activate` 测试（`deactivatedRound` 重置为 0）。
- **族表可执行化**：三仓 `script/event-families.txt`（事件 → 族）+ `check-events.py` 校验族覆盖、根键首字段、`round` 锚点；基线重生成（core 28 / action 34 / group-chat 23，含 3 个标准 ERC 事件）。
- **新增测试**：`RewardBurned → RewardPrepared`（依赖序 + 累计）、`LaunchCountAdded → GovRewardMinted`（跨合约依赖序）、`FeesSettled → StakeWithdrawn`、`LaunchCountAdded.issuedCount` 折叠、`OriginScoresSubmitted.totalFinalScore` 折叠、E1 `TokenMinted → GenesisTokenCreated`、E2 事件报告 `mintActionReward` 实际返回值、E3 重入、E4 `Withdrawn → JoinStateCleared → Exited`、边界成功值（96/32 名称符号、1024B title/details/description、16KiB×16 targetData、16 个 verification key 与 value、10 收款人 + 256B 备注）与对应 +1 拒绝（17 个 verification value）、部署配置 `tokenSymbolLength + 4 <= 32` 的 28 接受 / 29 拒绝。
- **破坏性变更清单（core/action 改名与重排）**：
  - core：`TokenMint`→`TokenMinted`、`TokenBurn`→`TokenBurned`、`Voted`→`VoteCast`、`StakeLiquidity`→`LiquidityStaked`、`StakeBoost`→`BoostStaked`、`Unstake`→`Unstaked`、`Withdraw`→`StakeWithdrawn`、`StakeMerged`→`StakesMerged`、`Mint`→`MemberMinted`（`id` 改名 `memberId`）；`TokenLaunched` 拆为 `GenesisTokenCreated` + `TokenLaunched`；删 `AddHolder`/`RemoveHolder`；`PhaseSynchronized` 删 `blockNumber`/`timestamp`/`adjusted`；`GovRewardMinted` 删 `burnReward`；`ProposalCreated` 增 `targetData`；`MemberMinted` 的 `cost` 前移。
  - action：`ActionCreated`→`ActionRegistered`（`round` 前移）、`Joined`/`Withdrawn`/`Exited`→`GroupActionJoined`/`GroupActionWithdrawn`/`GroupActionExited`（`groupId`/`providerId` 前移、增 `verificationValues`）、`SetRecipients`→`RecipientTableChanged`、`DistributeRecipient`→`RecipientPaid`（增 `sourceTokenAddress`）、`GroupConfigUpdated`→`GroupConfigChanged`、新增 `*ActionCreated`/`ApplicationVoteRecorded`/`ProviderQuotaRefunded`。
  - 消费方需按新 topic 重建过滤器与解码器；`GroupActionWithdrawn`/`MemberMinted` 是「字段不变、顺序调整」，旧解码器会静默错位。

## 最终核对

- 事件声明：**76 / 唯一名 76**（core 23、action 32、group-chat 21），跨仓无重名；旧事件名在 `src/` 零残留。
- 测试：core **474**、action **457**、group-chat **162**，全部 0 失败。
- 改动范围：三仓 `src/`、`test/`、`script/check-events.py`、`script/event-families.txt`、`script/events-baseline.txt`；matt-gov 规范与 `.scratch` 产物；未触碰 `lib/`、submodule、git 配置；未 commit/push。
- 字段顺序规则：整组替换新组→旧组，逐字段 diff 旧→新；actor 的 id 在地址之前（已写入规范 §6.1/§6.4/§6.7）。

## 外部 review 修复（2026-10-27 收尾）

- `registry/errors.{json,md}` 重生成：本轮新增的 12 条错误签名未登记，`check_errors.py --check` 曾报 2 处漂移；重生成后 `violations: 0`。
- `specs/action/00-executor-interface.md` 的 `ActionRegistered` 签名改为 ABI 实序（`round` 在 `executor` 前）。
- `specs/group-chat/07-events-errors.md` 的 `token` → `tokenAddress`。
- `CHANGES-action.md` 增「事件与接口改名（2026-10-27）」对照表，正文保留迁移时点名称（不篡改历史决策）。
- 规范：§3.4 增数组型增量字段的空数组语义；§4.2 说明 `MemberRewardMinted.burnAmount` 与 `ServiceRewardsDistributed.ownerBurned` 的有意冗余；§6.1 说明配置地址事件的槽位形状；§6.8 说明 schema 还受 `targetData` 16 KiB 约束。`05-submit.md` 记日志体量的 gas 取舍。
- 新增测试：`testEvent_RewardPreparedReservedMatchesFold`（§8.8 的 `rewardReserved` 折叠）、`testProposalTargetDataRejectsOversizedVerificationSchema`（schema 走真实 `Submit` 路径受 16 KiB 约束）、`testGroupActionJoinedTopUpCarriesNoVerificationValues`（追加加入空数组不清空既有值）。
- `DeployCore` 的 `tokenSymbolLength + 4 <= 32` 改为具名常量 `MAX_TOKEN_SYMBOL_LENGTH` / `TEST_PREFIX_BYTES`。
- 跨仓指针预演（不提交）：`action` 以 `--remappings "@core/=../core/src"`（仓内符号链接）**457 全绿**、`group-chat` 以 `--remappings "@action/=../action/src"` **162 全绿** ⇒ 子模块 bump 后预计无编译/测试断点，提交后仍需按真实指针复跑。
- 事件载荷断言加固（2026-10-28）：把「同类型字段在夹具里恒等值」与「只断言 `topics[0]`/`topics.length`」两类盲区逐处消除（core 的 Stake/Submit/Vote/Mint、action 的跨 token 场景、group-chat 的 4 个配置事件与消息事件），并新增 `testIntegration_BoostOverflowBurnCarriesRoundAndAmount` 覆盖 settle 路径的 `RewardBurned`；同时删除 3 个零断言测试（`testEvent_RewardBurnedForBoostOverflow` 的 mock 接错槽、两个 `...Cancelled*` 空壳）。校验方式：对 `emit` 做**抽样**变异——交换两个同类型实参的取值后跑全量 `forge test`，判据是套件是否失败（单用例失败不算）。采样口径：同一 `(文件, 事件)` 最多取 2 个互换点，再截断到 60；core 全量候选点 306，实采 41。修复前 32 处无感，修复后 core 41/41、action 30/30、group-chat 34/36（余 2 处为编译不安全的互换，已跳过）。**这是抽样结论，不等于「无盲区」**：抽不到的恒等值夹具照样存在——收尾 review 就抓到一处（`GovRewardMinted.voteReward` 与 `boostReward` 在默认夹具下同为 20% 池份额，互换后 474 个测试零失败），已把 boost 池份额改成 30% 并复跑变异确认可捕获。常设判据是 §8.1 的取值可判别要求。
- 终态：core **474**、action **457**、group-chat **162**；checker 28/34/23；`check_errors --check` 0；部署脚本 37/48/13。

#### 恒等对（§8.1 豁免登记）

| 事件 | 成对字段 | 理由 |
|---|---|---|
| `GroupChatActivated` | `groupId` / `ownerId` | 群就是群主的 MemberNFT，`ownerId` 必然等于 `groupId`；保留 `ownerId` 是为满足 §6.4 的 id/address 成对，不是冗余 |
| `StakesMerged` | `targetGovVotes` ≡ `targetLiquidityShares` × `targetPromisedWaitingPhases` | 同事件内两个字段的乘积；保留派生值让消费方免于复算 |
| `StakesMerged` | `prevSourceGovVotes` ≡ `liquiditySharesMerged` × `prevSourcePromisedWaitingPhases` | 同上；`prevSource*` 是融合前源成员状态，源被清空后只能由此处取 |

`BoostStaked.boostAmount` / `boostSharesAdded` 的旧豁免已撤销：该字段 2026-10-28 直接删除，`boostAmount` 本身就是份额增量。

成员份额与全局总量（`boostShares` / `totalBoostShares`、`liquidityShares` / `totalLiquidityShares`）**不豁免**：单成员夹具下它们必然相等，测试必须再引入一个成员让二者分开。

### 2026-10-28 增补：加速份额统一为 valid 口径

「累计加速份额」在语义上是**当轮有效值**（申请解锁即归零），与 `validGovVotes` 同一词根，故整族改名：

| 旧 | 新 |
|---|---|
| `cumulatedBoostShares(token, round, memberId)` | `validBoostShares(token, round, memberId)` |
| `_boostHistoryByMember` | `_validBoostSharesByMember` |
| `_globalBoostHistory` | `_totalValidBoostSharesAdded` / `_totalValidBoostSharesRemoved`（`total` 为二者之差） |
| 事件字段 `totalCumulatedBoostShares` | `totalValidBoostShares` |
| —（新增） | `totalValidBoostShares(token, round)`，社区口径，与成员口径同款 `RoundNotStarted` 守卫 |

`globalBoostUpdatedRounds` / `boostUpdatedRounds` 随后**直接删除**（2026-10-28 同日决定）：全仓零生产调用方，「哪些 Round 发生过变更」完全可由 `BoostStaked`/`Unstaked`/`StakesMerged` 的 `round` 折叠得到，属派生缓存（§6.9）。删除后 `Stake` 不再 import `Pagination`。

新增的不变量：`totalValidBoostShares(token, round) == Σ_m validBoostShares(token, round, m)`，事件里的 `totalValidBoostShares` 必须等于该查询结果。

## 待收尾

1. **提交授权**：三仓需要提交后，才能把 `action/lib/core` 指向新 core、把 `group-chat/lib/action` 指向新 action；随后重跑跨仓集成测试。用户未授权前不提交。
2. 子模块同步：core → `action/lib/core` → `group-chat/lib/action`（group-chat 内嵌 core）。
3. ABI 事件清单基线：三仓 `script/check-events.py` + `script/events-baseline.txt`（28/34/23，带参数名/anonymous）+ `script/event-families.txt`（族表）+ `.github/workflows/ci.yml` 已就绪；提交后 CI 生效。
4. 更新差距表迁移状态与项目记忆。
