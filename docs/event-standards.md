# LOVE20BSC 事件规范

状态：v1.1（2026-10-27 裁决：§3.4 依赖序 + E1–E4、§4.4 固定退出顺序、§6.1 族槽位表改为强制）
适用范围：`core`、`action`、`group-chat` 生产合约；`libs` 无事件；`dex` 为 UniswapV2 上游源码，明确排除。
配套材料：逐事件迁移记录见 `.scratch/events-spec/01-gap-table.md`，领域覆盖矩阵见 `.scratch/events-spec/02-coverage-matrix.md`。

本规范只定义事件语义、发射归属、命名、字段与可执行化规则；**不重复维护函数、事件、错误签名**。每个事件的精确签名以对应仓库的 `src/interfaces/` 为准，并由各仓 ABI 事件清单基线守护。

---

## 1. 规范用语

- **必须**（MUST）：违反即视为规范缺陷，阻塞合并。
- **应当**（SHOULD）：除非有书面理由并在评审中记录，否则必须遵守。
- **可以**（MAY）：实现自由裁量。

本文中的「事件」只指协议自定义事件；ERC-20 / ERC-721 等标准事件不在本规范正文内。

---

## 2. 术语

| 术语 | 含义 |
|---|---|
| 业务事实 | 一次可命名的状态迁移或状态变更，例如「成员加入了行动」「群配置被修改」 |
| 业务投影 | 链下重建所需的业务对象状态：对象状态与生命周期、余额/份额/额度、影响解释的配置；不包含原始 storage 槽 |
| 折叠 | 按日志顺序把某对象的全量事件归约为业务投影的过程 |
| 根键 | 一个域内的顶层标识：core/action 为 `tokenAddress`，group-chat 为 `groupId` |
| 发射者 | 运行时写出该事实的合约；必须是该状态的所有者 |
| actor | 业务语义上的发起人；不是 `msg.sender` 的同义词 |
| 共享事件类 | 同一 schema、同一语义、可被多个发射者发射的事件类 |
| 派生缓存 | 可由事件流、标准事件与不可变配置确定性推导的内部值；不进入事件 |
| 捕获型失败 | 被显式捕获、业务继续执行的失败；与 revert 不同 |
| 纪元 | 协议轮次 `round`，是业务键，不是时间值 |

---

## 3. 语义模型

### 3.1 一条事件一条事实

每个协议事件必须对应唯一的业务事实或状态迁移。

- 必须使用事实增量模型：只携带该事实产生的字段，不重复未变化字段。
- 涉及累计值时可以携带发射时点的累计值（总量、余额、累计奖励等）；该值必须等于按日志顺序折叠出的结果，且不得替代增量字段。
- 一个聚合量被多个事件改变时（例如 `Stake` 的治理票总量、加速份额总量），**每个改变点都应当携带后置总量**；只在一部分改变点携带属于族内漂移，消费方无法判断字段缺失是「没变」还是「没记」。只在单个事件上变化的聚合量（如 `Stake.totalBurnedToken`）同样在改变它的事件上携带总量，使该维度有可直接对账的锚点。
- 同一金额出现在两条事件中不构成重复表达，前提是两条事件描述的是不同事实、且各自需要该金额：`GovRewardMinted.burnReward` 与同笔 `RewardBurned(BoostOverflow).amount` 同值，前者给出成员归属（`RewardBurned` 不带 `memberId`），后者记全局销毁账本。此类跨事件冗余必须在模块规格中登记理由。
- 同一事实不得由多条事件重复表达；同一状态维度的不同迁移可以拆成不同事件类（例如 `Activated` 与 `Deactivated`）。

### 3.2 可重建的业务投影

事件流必须足以重建业务投影；不承诺从事件重建原始 storage。

- 所有影响业务对象状态、生命周期、余额/份额/额度、以及影响解释的配置参数的可变写入，必须有事件覆盖。
- 不可变部署参数（constructor/immutable/一次性 `init`）不进入事件；其来源由部署清单与脚本承担。
- 派生缓存不进入事件；规范必须列明其推导来源（见 `.scratch/events-spec/01-gap-table.md` §7）。
- 配置与治理参数的任何可变变更都属于状态迁移，必须事件化。

### 3.3 折叠完整性

对任一业务对象，在任一区块：

> 该对象的全量事件按日志顺序折叠的结果 = 链上 view 能读到的业务投影。

这是覆盖矩阵与测试的验收判据。新增状态字段时，必须同时回答「哪个事件承载它」或「它由哪些事件/标准事件推导」。

### 3.4 批量与顺序

1. 批量操作必须逐条状态迁移逐条 emit；不得用一条汇总事件替代 N 条事实。
2. 批次边界就是交易本身；入参带有协议级 batch id 时，可以作为字段携带。
3. 每个事件必须在自身状态写入完成后 emit，payload 必须反映 emit 时点已提交的状态；携带累计值时必须等于按日志顺序折叠的结果。
4. 发射顺序必须确定，并由测试断言；批量入口有入参顺序时按入参顺序。
5. 若事件 A 的 payload 依赖事实 B 造成的状态（累计值、余额、费率、份额、注册表状态等），B 必须先于 A。这是**依赖序**，不是父子序。
6. 同一状态所有者、同一业务对象的生命周期事件，SHOULD 父事实先于子事实；跨合约、跨状态所有者的事实按依赖序，不按父子序。`Mint`、`Launch`、`ActionTarget`、`GroupActionJoin` 的跨所有者序列都属这一类。
7. 允许的逆序（封闭清单；仅放宽事件顺序，不放宽状态写入、原子性和 payload 正确性）：
   - **E1** 创建事件的主对象地址由同一 tx 的 `CREATE`/`CREATE2` 产生：主对象构造/初始事件 → 创建事件；创建事件在登记完成后立即 emit。
   - **E2** 事件字段只能由外部调用返回或调用后状态确定：外部调用 → 其子事件 → 依赖事件；不得预测或重复计算。
   - **E3** 标准回调（ERC-721 / ERC-1155 / ERC-777）：状态写入与回调不可拆分时，业务事件可在回调后 emit；重入产生的事件可交错。若要严格顺序，必须另设重入锁并单独论证。
   - **E4** 无金额终态标记 `*Exited`：全部金额、退款、注册表清理事实之后 emit；带金额的 `*Withdrawn` 不是终态标记，按依赖序发射。
8. 每个事件的顺序约定（含上述逆序）必须有测试；累计值必须断言 `cumulative == fold`。
9. 数组型增量字段（如 `GroupActionJoined.verificationValues`）为空数组表示**本次事实没有新值**，不表示清空；折叠时不得用空数组覆盖既有值。只有语义本身是全量快照的字段才允许覆盖折叠。

### 3.5 失败

- revert 不会留下日志；失败由 custom error 表达。
- 禁止 attempted / rejected / failed 之类的「软失败」事件，禁止纯调试事件。
- 唯一允许的失败事件是**捕获型失败**：协议显式捕获异常并继续执行业务。此类事件必须命名为 `<Object>Failed`，携带失败对象与足够的错误指纹，且不得被当作操作成功的替代记录。
- 禁止 catch-all（`Updated` / `Changed` / `Set` 的 key-value 或 `bytes` 泛型容器）与 anonymous event。
- 标准事件（ERC-20 `Transfer`、ERC-721 `Transfer` 等）原样保留，不进入本规范正文，也不得被借用表达协议语义。

### 3.6 初始化与生命周期

- 初始化事件携带对象的初始状态，没有旧值。
- 生命周期事件由事件类型表达迁移方向（`Activated` / `Deactivated`、`Joined` / `Exited`），不再重复携带旧状态。
- 事件中不得使用哨兵值表达「不存在」：创世与发起拆成不同事件；可选引用用显式布尔字段（如 `hasQuote`）区分。
- `DelegateChanged.delegateId = 0` 是显式清除编码；`GroupActionJoined/Withdrawn.providerId = 0` 是 self 角色。两者是词表定义的显式值，不是「不存在」的哨兵。

### 3.7 部署后冻结

- 当前阶段允许全面 breaking；迁移必须一次性完成，规范不留兼容例外。
- 首次对外部署后，事件只增不改：新增事实 = 新增事件；字段或语义变更 = 新事件名；旧事件保留并标注 deprecated。
- 动态字段上限属于事件契约的一部分，变更同样受本节约束。

---

## 4. 发射归属

### 4.1 状态所有者

- 一条事实只允许一个发射者：该事实所写状态的所有者。
- 编排/执行合约只发射自己产生的类事实，不得替其他合约复述。
- 事件必须声明在发射者的 interface 中，不得只声明在实现合约里。
- 外部库可以 emit，当且仅当：被状态所有者 DELEGATECALL；事件声明在状态所有者的 interface；库不被多个语义不同的状态所有者共享（共享则必须是同 schema 同语义的共享类）。运行时 emitter 必须是状态所有者，测试必须断言 emitter 地址。
- 不满足上述条件的库不得 emit；库内产生的事实由调用合约负责 emit。
- 注册表兜底清理 `forceClearJoinState` 由 ActionTarget 自己发射，见 §4.4。

### 4.2 共享事件类

多个合约可以发射同一个事件类，前提是：

- 同一 schema、同一语义；
- 声明在共享 interface；
- 规范列出全部发射者。

共享类不违反「一条事实一个发射者」：每个运行时事实仍只有一个发射者。当前共享类：`MemberRewardMinted`（GroupActionExecutor、GroupServiceExecutor、LpExecutor；`mintAmount` = 为该成员铸造的总额，service 实收拆分由 `ServiceRewardsDistributed` 承担）、`TokenGroupActivated`（TokenMainManager、TokenGovManager）、`TokenActionGroupActivated`（TokenActionMainManager、TokenActionGovManager）。

共享类使用**未限定**的 `tokenAddress` / `actionId`：它们指发射者所属域的对象——`GroupServiceExecutor` 发射时是 service 代币与 service 行动，其余发射者是行动代币与行动 id。消费方必须先按发射者确定域，不得跨域混用；这也是共享类不能按 §6.2 拆成 `serviceTokenAddress` 的原因（拆了就变成两个事件类）。

`MemberRewardMinted.burnAmount` 与 `ServiceRewardsDistributed.ownerBurned` 在 `GroupServiceExecutor` 场景下是同一数字：共享类要保持三发射者同 schema，无法删字段，属**有意冗余**；折叠时以 `MemberRewardMinted` 为准，`ownerBurned` 只用于服务结算的自洽核对。

### 4.3 actor

- actor 是业务语义上的发起人；接口有显式账户参数时取该参数。
- 直接调用者 `msg.sender` 仅在确有必要时另设 `caller` 字段；actor 与 caller 不得共用一个字段名。
- 当 actor 就是主对象的所有者、且主对象 id 已 indexed（例如群主对 `GroupActivated` / `GroupConfigChanged`），actor 由对象所有权隐含，不再单列字段。

### 4.4 正常退出与注册表兜底清理

正常退出必须经由 executor 完成，顺序固定为：

1. executor 清理自身仓位状态（份额、扣减、加入记录）；
2. 退款/转账给成员，并在转账后立即 emit 带金额的 `*Withdrawn`（若有）；
3. 回调 `ActionTarget.clearJoinState`，ActionTarget 发 `JoinStateCleared(forced=false)`；
4. executor 发 `*Exited`。

`*Withdrawn` 必须早于 `JoinStateCleared`：索引器把 `JoinStateCleared` 当作「成员已离开」的信号，金额事实若排在它之后，朴素折叠会丢掉这笔金额。

没有对应事实的步骤为空步，但相对顺序不变：`GroupServiceExecutor` 无自身仓位也无退款，只有第 3、4 步；`LpExecutor` 四步齐全。

`*Exited` 是**终态标记，最后发、不带金额**。带金额的 `*Withdrawn` 是普通事实，位置由第 2 步固定，不是终态标记；`GroupDeactivated` 带 `stakeAmount` 且可逆，按普通状态迁移处理，不套 `*Exited` 规则。

兜底清理函数 `forceClearJoinState`（原 `forceExit`）只在 executor 故障时使用，**只清 ActionTarget 的注册表**：

1. 必须只允许 member owner 调用；成员不在注册表时幂等返回。
2. 只清空成员的行动注册表，并 emit `JoinStateCleared(forced=true)`。
3. **不得回调 executor**：调用这个函数本身就意味着 executor 已不可信；任何回调都可能被故障合约阻断或吞掉 gas，反而使注册表无法清理。
4. 不结算资金、不 emit `*Exited`；executor 侧仓位保持原样，由用户走 executor 自己的退出路径（若仍可用）。
5. 索引器必须把「注册表状态」与「executor 仓位」视为两个对象：`JoinStateCleared(forced=true)` 只代表行动清单已清理，不代表仓位已关闭。

`forced` 保留为布尔字段：`true` = owner 兜底清理，`false` = executor 正常退出。

---

## 5. 命名

### 5.1 语法

- 事件名必须是 `<Object><PastParticiple>` 的事实句，PascalCase，无下划线。
- 配置变更必须是 `<Object>Changed`，携带旧值+新值。
- 全协议事件名与 schema 必须全局唯一；同名不同 payload 一律拆名。

### 5.2 对象前缀与拆名

跨合约同名不同义必须拆分。当前迁移包含：

- `Joined` / `Exited` / `Withdrawn` → `GroupActionJoined` / `LpJoined` / `ServiceJoined` 等域前缀。
- `Activate` → `GroupChatActivated` / `TokenGroupActivated` / `TokenActionGroupActivated`。
- `SetSenderIdBan` → `SenderBanChanged`（管理员封禁列表）/ `GovSenderBanChanged`（治理投票结果）。
- `Exited` 在 LP 与 Service 之间的 topic0 冲突随域前缀消除。

### 5.3 创建事实

- ActionTarget 的注册表事实为 `ActionRegistered`。
- 域对象创建事实为 `GroupActionCreated` / `ServiceActionCreated` / `LpActionCreated`，由 executor 在 `onProposalCreated` 发射，携带初始配置全量。
- 创世与普通发起拆分：`GenesisTokenCreated` + `TokenLaunched`；事件内不放哨兵值。

### 5.4 标准事件

ERC-20 / ERC-721 标准事件保持不变，不进入本规范正文。`AddHolder` / `RemoveHolder` 不再作为协议事件；持有人集合由 ERC-721 `Transfer` 折叠。

### 5.5 合并与删除

- `MentionAll` 合并进 `MessagePosted.mentionAll`。
- `SetAdminSnapshot` 合并进 `AdminChanged`（快照旧/新值 + membership 状态）。
- `GovernanceRewardMinted` 简化为 `GovRewardMinted`，与 `govReward` / `govVotes` / `govRatio` 同词根。

---

## 6. Payload

### 6.1 字段顺序

字段顺序的目标是 **根键 → 父对象 id 链 → 本对象 id → 角色 → 数值 → 文本/枚举**。族槽位表是这条目标的逐族实例，**表本身是强制约束**：同一事件族内槽位固定，不得族内漂移。

强制要求：

- 根键（该事件所属域的顶层标识）必须是第一个字段。根键由发射者自身代表时可以省略：`LOVE20Token` 的 `TokenMinted` / `TokenBurned`、`MemberNFT` 的 `MemberMinted`、`Phase` 的 `PhaseSynchronized` / `PhaseAdjusted` 都不带根键字段。delegation 域（跨群白名单）的根键是 `delegateId`。
- 同一事件族内槽位固定，不得族内漂移；各族由 `script/events/check-events.py` 按 `script/events/event-families.txt` 校验（族覆盖、根键首字段、`round` 锚点），ABI 顺序由 `script/events/events-baseline.txt` 锁定。
- actor 的 id 必须在其地址之前（`operatorId` → `operator`）；actor 地址与对象地址不共槽位。
- 配置/状态事件默认先携带新值、后携带旧值（`prev*` / `old*`）；整组替换按新组→旧组；旧值组内部沿用新值组的槽位顺序（`DelegateChanged` 的 `prevDelegateId` 与两个 `prev*` 快照同组）；以迁移量本身为事实的 diff 事件（如 `PhaseAdjusted`）按旧→新。

| 族 | 槽位序列 | 事件 |
|---|---|---|
| core.token | 角色 → 数值 | `TokenMinted`、`TokenBurned` |
| core.registry | 根键 → 父根键 → 对象 id → 角色 → 数值 → 枚举 → 文本 | `GenesisTokenCreated`、`TokenLaunched`、`LaunchCountAdded`、`LaunchCountMerged`、`LaunchCountConsumed` |
| core.member | 对象 id → 角色 → 数值 → 文本 | `MemberMinted` |
| core.round | 根键 → round → 对象 id → 角色 → 数值 → 枚举 | `RewardPrepared`、`GovRewardMinted`、`ProposalRewardMinted`、`RewardBurned` |
| core.phase | 对象 id → 数值（diff 事件旧→新） | `PhaseSynchronized`、`PhaseAdjusted` |
| core.stake | 根键 → round → memberId 链（1–2 个）→ 数值 | `LiquidityStaked`、`BoostStaked`、`Unstaked`、`StakeWithdrawn`、`FeesSettled`、`StakesMerged` |
| core.proposal | 根键 → round → 对象/actor id 链（1–2 个）→ 地址 → 枚举 → bytes → 文本 | `ProposalCreated`、`ProposalSubmitted`、`VoteCast` |
| action.registry | 根键 → actionId → round → executor | `ActionRegistered` |
| action.config | 根键 → actionId → 配置地址 → 配置数值 → 文本数组 | `GroupActionCreated`、`ServiceActionCreated`、`LpActionCreated` |
| action.group | 根键 → actionId → round → groupId → 配置值 → 旧值 | `GroupActivated`、`GroupDeactivated`、`GroupConfigChanged` |
| action.participation | 根键 → actionId → memberId → round → groupId → providerId → 数值/布尔 → 文本数组 | `GroupActionJoined`、`GroupActionWithdrawn`、`GroupActionExited`、`LpJoined`、`LpWithdrawn`、`LpExited`、`ServiceJoined`、`ServiceExited`、`JoinStateRegistered`、`JoinStateCleared`、`MemberRewardMinted` |
| action.round | 根键 → actionId → round → 数值 | `ActionRewardMinted` |
| action.quota | 根键 → actionId → groupId → providerId → memberId → 数值 | `ProviderQuotaAdded`、`ProviderQuotaRemoved`、`ProviderQuotaRefunded` |
| action.verification | 根键 → actionId → memberId/groupId → round → applicationId/verifierId → 次级 id（候选成员 / 上一申请）→ 数值/布尔 → 文本/数组 | `OriginScoresSubmitted`、`VerifierApplicationSubmitted`、`VerifierApplicationCancelled`、`VerifierStakeDeposited`、`VerifierStakeRefunded`、`VerifierLocked`、`ApplicationVoteRecorded` |
| action.recipients | 根键 → sourceActionId → round → groupId → 新表 → 旧表 | `RecipientTableChanged` |
| action.service | 根键 → serviceActionId → round → 对象链（groupId 或 actionTokenAddress）→ 源链/角色 → 数值 | `RecipientPaid`、`ServiceRewardsDistributed` |
| gc.management | 根键 → 对象标识（id 或对象地址）→ actor id → actor 地址 → 新值组 → 旧值组 | `AdminChanged`、`MemberStatusChanged`、`SenderBanChanged`、`GroupChatActivated`、`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged`、`DelegateChanged`、`DelegationCleared` |
| gc.delegation | delegateId → groupId（若有）→ delegateOwner → 值 | `DelegatorWhitelistChanged`、`DelegatorGroupPermissionChanged` |
| gc.ban-vote | 根键 → targetSenderId → voterId → 布尔 → 数值 → stateVersion | `SenderBanVoteCast`、`GovSenderBanChanged`、`StateVersionChanged` |
| gc.message | 根键 → messageId → senderId → sender → round → 引用 messageId → 数值/布尔 → content | `MessagePosted`、`SenderMentioned` |
| gc.plugin | 根键 → messageId → round → pluginAddress → 错误指纹 | `AfterPostPluginFailed` |
| gc.link | 根键 → 对象 id → actor | `TokenGroupActivated`、`TokenActionGroupActivated` |

槽位序列是「允许的顺序」，事件可以省略某槽（例如 `GroupActionExited` 无金额、`StateVersionChanged` 无 targetSenderId），但不得插入表外槽位或调整相对顺序。新增事件必须先归入某一族并在此表登记，否则 `check-events.py` 报错。

配置地址型事件把**新地址**放在「对象标识（对象地址）」槽，actor 排在其后（`ScopeSourceChanged` / `BanSourceChanged` 的 `sourceAddress`、`BeforePostPluginChanged` / `AfterPostPluginChanged` 的 `pluginAddress`）；布尔型配置事件仍是 actor 地址 → 新值（`PostingAllowedChanged`）。两种形状都在族表允许的槽内，不是族内漂移。

「对象/actor id 链」槽只固定「在地址之前」，不固定两者的先后：`ProposalCreated` 是对象（`proposalId`）→ actor（`authorId`），`ProposalSubmitted` / `VoteCast` 是 actor（`submitterId` / `voterId`）→ 对象（`proposalId`）；前者对象优先、后者 actor 优先，都合规。

### 6.2 根键与链路

- core / action：根键为 `tokenAddress`（发射者自身即根对象时省略，见 §6.1）；父链按域携带 `round`、`memberId`、`proposalId`、`actionId`、`groupId`。
- 跨 token 的服务事件使用限定角色名：`sourceTokenAddress` / `sourceActionId`、`serviceTokenAddress` / `serviceActionId`、`actionTokenAddress`；这些是根键的限定形式，不构成新的根键。
- group-chat：根键为全局唯一、递增、不复用的 `groupId`。
- token/action ↔ group 的唯一链路是 `TokenGroupActivated` 与 `TokenActionGroupActivated`；群名与所有者在 core `MemberMinted`。
- 规范维护「对象 → 根键 → 链路事件」表；跨仓对象必须能用 `groupId` 无歧义关联。

### 6.3 indexed

- 每个事件最多 3 个 indexed。
- `round` 是协议纪元键，可以 indexed；`block.timestamp` / `block.number` 不 indexed、也不进入 payload。
- 分配优先级：根键 → 主对象 id 链 → actor。主对象键占满时，actor 降为非 indexed 字段。
- 纯链路事件（`TokenActionGroupActivated`）的 3 个槽给链路键；actor 入 payload。
- `string` / `bytes` / 动态数组绝不 indexed；禁止 anonymous event。
- actor 与主对象 id 应当 indexed；同组事件必须在迁移中对齐（`VerifierLocked`、`StakesMerged`）。

### 6.4 角色词表

角色词表是封闭的：同一角色在全协议只用一种写法。

- `<role>` 表示地址，`<role>Id` 表示协议 id；同一角色同时出现地址与 id 时必须成对，且 **id 在地址之前**（`operatorId` → `operator`、`ownerId` → `owner`、`senderId` → `sender`）。
- 固定取值包括：`tokenAddress`、`sender` / `senderId`、`owner` / `ownerId`、`operator` / `operatorId`、`admin` / `adminId`、`delegate` / `delegateId`、`delegateOwner`、`memberId`、`voterId`、`submitterId`、`recipientId`、`providerId`、`verifierId`、`launcherMemberId`、`authorId`、`targetSenderId`、`mentionedSenderId`、`candidateMemberId`、`sourceMemberId` / `targetMemberId`。
- 角色 id 的旧值加 `prev` 前缀（`prevDelegateId`）；成员 id 一律写 `memberId`，不得写成 `id`（`MemberMinted` 已统一）。
- 对象 id 一律写 `<object>Id`：`actionId`、`proposalId`、`applicationId`、`previousApplicationId`、`messageId`、`quotedMessageId`、`groupId`、`serviceActionId` / `sourceActionId`。对象 id 不登记为角色。
- 对象地址与 actor 地址分列：`executor`、`distributor`、`recipient`、`target`、`joinTokenAddress`、`actionTokenAddress`、`sourceAddress`、`pluginAddress`、`to` / `from` 是对象或对手方地址，不占 actor 槽位。
- 快照角色统一为 `<object>Snapshot`：`ownerSnapshot`、`delegateOwnerSnapshot`、`groupOwnerSnapshot`、`adminOwnerSnapshot`；旧值加 `prev` 前缀（`prevOwnerSnapshot`、`prevDelegateOwnerSnapshot`、`prevGroupOwnerSnapshot`、`prevAdminOwnerSnapshot`）。
- 配置地址按配置项命名：`scopeSource`、`banSource`、`beforePostPlugin`、`afterPostPlugin`；旧值加 `prev` 前缀（`prevSourceAddress`、`prevPluginAddress`）。
- 父链根键：`parentTokenAddress`；`tokenAddress` 是根键本身，两者不得互换成 `token` / `parent`。
- 跨 token 的服务事件使用限定角色：`sourceTokenAddress` / `sourceActionId`、`serviceTokenAddress` / `serviceActionId`、`actionTokenAddress`。
- `providerId = 0` 表示自筹来源（self）；`DelegateChanged.delegateId = 0` 表示清除委托。两者是显式值，不另设布尔。
- 禁止同义混用：`author`（id）改为 `authorId`，`senderAddress` 改为 `sender`，`token` 改为 `tokenAddress`。

### 6.5 金额与 Token 语义

- 语义事件必须自带 token 地址与金额，使协议账目仅凭协议事件流即可重建，不依赖回连 ERC-20 `Transfer`。
- 不重复复制 `from` / `to`，除非第三方不被 actor/subject 隐含。
- ERC-20 `Transfer` 只作底层审计，不作为协议账目的唯一来源。

### 6.6 时间与元数据

- 不写 `block.timestamp` / `block.number`；日志本身已带这些元数据。
- 只写业务时间（deadline、period、eta 等）。`round` 是业务键，不属于时间元数据。
- `stateVersion` 等版本字段是事实时点的值，不是交易末态；同一交易内可逐次自增并逐条记录。
- 机器可读的值不得用 `string`；`string` 只用于事实本身就是文本的场景（名称、描述、正文）。

### 6.7 旧值与新值

- 配置变更必须携带旧值+新值。
- 旧值由新值恒等可推时可以省略（例如布尔取反、每次 +1 的版本号）。
- 表状/结构配置一律旧+新；批量配置的低频事件可以因此变大。
- 初始化事件无旧值；生命周期事件不重复旧状态。
- 非配置的状态迁移（投票、销毁等）由上一条同对象事件提供旧值。
- 快照型配置按「新快照组 → 旧快照组」排列，组内沿用新值组的槽位顺序：`DelegateChanged` 的 `delegateId, owner, ownerSnapshot, delegateOwnerSnapshot` 之后才是 `prevDelegateId, prevOwnerSnapshot, prevDelegateOwnerSnapshot`；`AdminChanged` 的 `listed, groupOwnerSnapshot, adminOwnerSnapshot` 之后才是 `prevListed, prevGroupOwnerSnapshot, prevAdminOwnerSnapshot`。

### 6.8 动态字段上限

事件中的每个 `string` / `bytes` / 数组字段必须有链上强制上限；上限属于事件契约，必须写入规范并由链上强制常量（接口或实现库）与测试守护。

v1 基线：

| 字段 | 上限 |
|---|---|
| `MessagePosted.content` | 现有 `MAX_CONTENT_LENGTH` |
| `MemberNFT` 名称 / `normalizedName` | 现有 `MAX_NAME_LENGTH` |
| `TokenLaunched` / `GenesisTokenCreated` 的 name/symbol | `MAX_TOKEN_NAME_LENGTH = 96`、`MAX_TOKEN_SYMBOL_LENGTH = 32`（init 与发起路径统一，按 Test 前缀后的实际长度校验） |
| `ProposalCreated.title` / `details` | 各 ≤1024 字节 |
| `ProposalCreated.targetData` | ≤16 KiB、≤16 个元素 |
| `GroupConfigChanged.description` | 现有 1024 字节 |
| `GroupActivated.description` | 现有 1024 字节 |
| `RecipientTableChanged.remarks` | 每条 ≤256 字节，条数 ≤`DEFAULT_MAX_RECIPIENTS` |
| `RecipientTableChanged.recipientIds` / `ratios` | ≤`DEFAULT_MAX_RECIPIENTS`（10 项） |
| `GroupActionCreated.verificationKeys` / `verificationDescriptions` | ≤16 项，每项 ≤1024 字节 |
| `GroupActionJoined.verificationValues` | ≤16 项，每项 ≤1024 字节 |
| `OriginScoresSubmitted.scores` | ≤`MAX_VERIFICATION_BATCH`（100） |
| `VerifierApplicationSubmitted.description` | ≤1024 字节 |

无界字段不得进入事件。确实无法加上限的文本属于元数据，必须列入「不承诺重建」的窄名单，不得静默遗漏。

`GroupActionCreated.verificationKeys` / `verificationDescriptions` 的「16 项 ×1024 字节」是**事件字段上界**；实际创建路径还要受 `ProposalCreated.targetData` 的 16 KiB 总量约束（schema 作为 `targetData[6]` 传输），链上可达的最坏值低于该上界。绕过 `Submit` 直调 `onProposalCreated` 的边界测试不覆盖这层约束。

### 6.9 派生缓存

内部记账缓存不得进入事件，但必须可由以下三类输入确定性推导：

1. 协议事件流；
2. 标准事件（ERC-20 / ERC-721 / UniswapV2 `Sync` 等）；
3. 不可变部署参数。

当前派生缓存清单与推导来源见 `.scratch/events-spec/01-gap-table.md` §7，包括 Launch credit、Stake LP 基准、pair 地址、Phase 观测、holder 集合、分红除数、`govRatioAtMint`、验证排名、provider 索引、join block/amount、mint nonce、delegate 索引、ban operator 状态、stateVersion、admin 有效性与消息索引。

### 6.10 注释

事件声明与 emit 点均不写解释性注释；语义只存在于本规范。复述式注释与「何时发射」注释一律不写；`forge-lint` / `slither` 等工具指令除外。

---

## 7. 领域对象模型

对象模型是本规范长期维护的部分；事件签名仍以各仓 `src/interfaces/` 为准。

### 7.1 Core

| 对象 | 状态迁移 | 事件类 |
|---|---|---|
| RootToken | 初始供给、增发、销毁 | `TokenMinted`、`TokenBurned`；标准 `Transfer` / `Approval` |
| TokenRegistry | 创世、发起子币、额度发放/合并/消耗 | `GenesisTokenCreated`、`TokenLaunched`、`LaunchCountAdded`、`LaunchCountMerged`、`LaunchCountConsumed` |
| MemberNFT | 铸造、转移、持有人集合 | `MemberMinted`；标准 `Transfer` / `Approval` / `ApprovalForAll` |
| Phase | 同步观测、调整段长 | `PhaseSynchronized`、`PhaseAdjusted` |
| StakePosition | 加流动性、加 boost、解锁、提取、手续费结算、合并 | `LiquidityStaked`、`BoostStaked`、`Unstaked`、`StakeWithdrawn`、`FeesSettled`、`StakesMerged` |
| Proposal | 创建、提交 | `ProposalCreated`、`ProposalSubmitted` |
| Vote | 投票 | `VoteCast` |
| RewardRound | 准备奖池、gov 奖励、提案奖励、取消池燃烧 | `RewardPrepared`、`GovRewardMinted`、`ProposalRewardMinted`、`RewardBurned` |

`MemberNFT` 的 `_safeMint` 回调先于 `MemberMinted`（E3），因此：

- 日志顺序不保证等于 `memberId` 顺序；重入时内层 `MemberMinted` 可能早于外层。
- `MemberMinted.owner` 是**铸造接收人**，不是当前持有人；当前持有人只从 ERC-721 `Transfer` 折叠。
- 回调中把刚铸出的 NFT 转走不影响 `owner` 字段——它记录的是铸造事实，不是持仓事实。

### 7.2 Action

| 对象 | 状态迁移 | 事件类 |
|---|---|---|
| ActionRegistry | 注册/绑定 executor | `ActionRegistered` |
| ActionConfig | GroupAction / Service / LP 初始化 | `GroupActionCreated`、`ServiceActionCreated`、`LpActionCreated` |
| GroupConfig | 激活、停用、配置变更 | `GroupActivated`、`GroupDeactivated`、`GroupConfigChanged` |
| JoinState | 注册表注册/清除、加入、提取、退出 | `JoinStateRegistered`、`JoinStateCleared`、`GroupActionJoined`、`GroupActionWithdrawn`、`GroupActionExited`、`LpJoined`、`LpWithdrawn`、`LpExited`、`ServiceJoined`、`ServiceExited` |
| ProviderQuota | 配额增加、移除、退出回填 | `ProviderQuotaAdded`、`ProviderQuotaRemoved`、`ProviderQuotaRefunded` |
| Verification | 申请、取消、质押、退款、原始分、投票、锁定 | `VerifierApplicationSubmitted`、`VerifierApplicationCancelled`、`VerifierStakeDeposited`、`VerifierStakeRefunded`、`OriginScoresSubmitted`、`ApplicationVoteRecorded`、`VerifierLocked` |
| RecipientTable | 设置收款表、分发 | `RecipientTableChanged`、`RecipientPaid` |
| Rewards | 行动奖励、成员奖励、服务分发 | `ActionRewardMinted`、`MemberRewardMinted`、`ServiceRewardsDistributed` |
| JoinStateFallback | owner 兜底清理注册表（不回调 executor、不结算资金） | `JoinStateCleared(forced=true)` |

`LpExecutor` 的清仓迁移必须统一：只要 `_clearJoinState` 执行（全额 `withdraw` 或 `exit`），必须同时产出 `LpWithdrawn`（金额事实）与 `LpExited`（生命周期事实），顺序按 §4.4。

`GroupDeactivated` 是**可逆**的 active→inactive 状态迁移：`activateGroup` 允许对已停用的群重新激活并把 `deactivatedRound` 重置为 0。它不是终态，不适用 E4 的 `*Exited` 规则；索引器按最后一次 `GroupActivated` / `GroupDeactivated` 折叠 `active`，不得把停用当永久关闭。

### 7.3 Group-chat

| 对象 | 状态迁移 | 事件类 |
|---|---|---|
| ChatConfig | 激活、发言开关、scope/ban source、插件 | `GroupChatActivated`、`PostingAllowedChanged`、`ScopeSourceChanged`、`BanSourceChanged`、`BeforePostPluginChanged`、`AfterPostPluginChanged` |
| Message | 发布、提及、afterPost 失败 | `MessagePosted`、`SenderMentioned`、`AfterPostPluginFailed` |
| AdminSet | 管理员增删、快照刷新 | `AdminChanged` |
| MemberSet | 成员状态 | `MemberStatusChanged` |
| BanSet | 管理员封禁、投票、结果封禁、版本自增 | `SenderBanChanged`、`SenderBanVoteCast`、`GovSenderBanChanged`、`StateVersionChanged` |
| Delegation | 设置、清零、白名单、群权限 | `DelegateChanged`、`DelegationCleared`、`DelegatorWhitelistChanged`、`DelegatorGroupPermissionChanged` |
| ManagerLink | token → group、token+action → group | `TokenGroupActivated`、`TokenActionGroupActivated` |
| GroupName | 群名铸造 | core `MemberMinted`（跨仓链路） |

### 7.4 跨仓折叠

- **群对象**：`MemberMinted`（`memberId` 即 `groupId`，携带名称/所有者）+ 两条链路事件 + `GroupActivated`（组配置）+ `GroupChatActivated`（聊天配置）+ 后续 `*Changed`，折叠结果必须等于三仓 view 的并集。
- **管理员有效性**：`AdminChanged`（快照旧/新 + membership）+ core ERC-721 `Transfer`（owner 变化）。
- **兜底清理**：`JoinStateCleared(forced=true)` 只代表 ActionTarget 注册表清理；不回调 executor、不要求 executor 事件；executor 仓位由自身退出路径处理。
- 其余对象的折叠不变量见 `.scratch/events-spec/02-coverage-matrix.md` §4。

---

## 8. 可执行化

1. 每个事件至少一个测试断言：发射条件、发射次数、字段顺序、indexed 布局、**字段取值**。同一事件内两个同类型字段必须由**取值可区分**的夹具断言——把两个实参互换后测试仍通过，等于没有断言。协议上恒等的成对字段免于此条，但必须满足其一并在 `.scratch/events-spec/03-migration-status.md` 的「恒等对」清单登记理由（迁移冻结后该清单并入本文 §7 的对象表，随对象表一起维护）：(a) §6.4 的 `<role>Id` / `<role>` 成对槽位，且该 id 必然等于另一字段（`GroupChatActivated.ownerId` ≡ `groupId`，因为群就是群主的 MemberNFT）；(b) 1:1 记账使两个字段恒等，或同事件内两个字段的乘积恒等于第三个字段（`StakesMerged.targetGovVotes` ≡ `targetLiquidityShares × targetPromisedWaitingPhases`、`prevSourceGovVotes` ≡ `liquiditySharesMerged × prevSourcePromisedWaitingPhases`）——后者保留派生值是为了让消费方免于复算，属有意冗余。两个字段只是「本次夹具恰好同值」不构成恒等，必须改夹具让它们分开。
2. 每个仓库维护两份事件表：从 ABI 生成的「事件清单」基线 `script/events/events-baseline.txt`，以及「事件 → 族」映射 `script/events/event-families.txt`。检查器 `<repo>/script/events/check-events.py` 校验族覆盖、根键首字段与 `round` 锚点，并对比 ABI 基线；新增/修改/删除事件必须显式更新两份表。检查器内的族槽位表是 §6.1 的**逐仓切片**，只登记本仓发射的族，全量以本文为准；切片之外的部分（ABI 扫描、基线比对、槽位判定）三仓逐字节相同。各仓 `.github/workflows/ci.yml` 在 push/PR 运行该检查器。
3. 新增或修改事件时，必须同步更新覆盖矩阵与本文的对象模型；只改代码不改模型视为规范缺陷。
4. 事件声明与 emit 点不写注释；语义只写在本文。
5. 事件签名以各仓 `src/interfaces/` 为准；本文不复制签名。
6. 共享事件类的全部发射者必须在本文 §4.2 与 ABI 基线中列明。
7. 顺序测试必须覆盖依赖序（§3.4 第 5 条），至少：`RewardBurned → RewardPrepared`、`FeesSettled → StakeWithdrawn`、`TokenMinted`/`LaunchCountAdded` → 依赖它们的 `GovRewardMinted`。
8. 累计值测试必须断言 `cumulative == fold`，至少覆盖 `RewardPrepared.rewardBurned`/`rewardReserved`、`OriginScoresSubmitted.totalFinalScore`、`LaunchCountAdded.issuedCount`、`ApplicationVoteRecorded.totalVotes`、`FeesSettled.totalBurnedToken`/`totalParentTokenBurned`，以及按事件逐个枚举的聚合量：`totalValidGovVotes` 在 `LiquidityStaked`/`BoostStaked`/`Unstaked`/`StakesMerged`；`totalValidBoostShares` 在 `BoostStaked`/`Unstaked`；`totalBoostShares` 在 `BoostStaked`/`StakeWithdrawn`；`totalLiquidityShares` 在 `LiquidityStaked`/`StakeWithdrawn`。两个 `valid*` 总量必须等于同轮 `Added - Removed`，两个余额/份额总量必须等于 `totalStakeData` 的同名字段——只断言其中一个锚点不算覆盖。
9. 例外路径测试必须逐条覆盖 E1–E4：
   - E1：`TokenMinted → GenesisTokenCreated`/`TokenLaunched`，事件中的地址与部署地址一致；
   - E2：mock 返回值与预计算不同，事件报告实际返回值；
   - E3：接收方在 `onERC721Received` 中重入 `mint`，外层 `MemberMinted` 仍正确；
   - E4：`*Withdrawn`/`*Refunded` → `JoinStateCleared` → `*Exited`；部分撤回不产生 `*Exited`；真实 ActionTarget 下顺序一致。
10. 边界成功值必须有测试（恰好等于上限时成功，上限 +1 时失败）：16 个 verification key/value、1024 字节 title/details/description、16 KiB 与 16 个 targetData 元素、10 个 recipient、256 字节 remark、96/32 字节 name/symbol。

---

## 9. 不适用范围

- `dex`（UniswapV2 上游源码）、测试、脚本、部署产物。
- `libs`：当前无事件；若未来新增，自动纳入本规范。
- ERC-20 / ERC-721 等标准事件。
- 不可变部署参数（constructor / immutable / 一次性 `init`）。
- 派生缓存与链下元数据（必须按 §6.9 可推导，或列入不承诺重建的窄名单）。
- 跨合约业务缺陷的修复实现（如 LP 清仓事件补发）——本规范锁定可观察行为，实现单独立项；`forceExit` → `forceClearJoinState` 的改名属于实现变更。

---

## 10. 迁移与冻结

1. 当前迁移允许全面 breaking：改名、改字段、改 indexed、合并/拆分、新增/删除。迁移一次性完成，不保留兼容层。
2. 逐事件迁移记录见 `.scratch/events-spec/01-gap-table.md`；该表是迁移期的权威清单，迁移完成后由各仓 `src/interfaces/`、ABI 基线与本文对象模型接管。
3. 首次对外部署后进入冻结：只增不改；新事实 = 新事件；字段/语义变更 = 新事件名；旧事件保留并标 deprecated。
4. 动态字段上限与 indexed 布局属于事件契约，冻结后同样只增不改。

---

## 11. 参考

- 逐事件迁移记录：`.scratch/events-spec/01-gap-table.md`
- 领域覆盖矩阵与派生缓存：`.scratch/events-spec/02-coverage-matrix.md`
- 接口（精确签名）：
  - `core/src/interfaces/ILOVE20Token.sol`、`ILaunch.sol`、`IMemberNFT.sol`、`IMint.sol`、`IPhase.sol`、`IStake.sol`、`ISubmit.sol`、`IVote.sol`
  - `action/src/interfaces/IActionTarget.sol`、`IActionExecutor.sol`、`IGroupActionManager.sol`、`IGroupActionJoin.sol`、`IGroupActionVerify.sol`、`IGroupRecipients.sol`、`IGroupServiceExecutor.sol`、`ILpExecutor.sol`
  - `group-chat/src/interfaces/IGroupChat.sol`、`IGroupAdmin.sol`、`IGroupMember.sol`、`IGroupChatBanList.sol`、`IGroupChatDelegate.sol`、`sources/ban/IGovVotedBanSource.sol`、`managers/ITokenScopeManagerBase.sol`、`managers/ITokenActionScopeManagerBase.sol`
- 错误规范：`matt-gov/docs/error-standards.md`（事件与错误的分工：revert 用错误，成功/捕获型失败用事件）
