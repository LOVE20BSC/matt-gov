# ActionTarget 事件赋值与发射审查

> 对象 `action/src/ActionTarget.sol`（531 行，`contract`）
> 声明 `action/src/interfaces/IActionTarget.sol`（`IActionTargetEvents`，L6-32）
> 基线 `action@e849e36`（工作区干净）；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/action/01-action-target.md`、`07-minting.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 4 |
| 发射点 | 5 |
| 状态写入点（受事件覆盖） | 8 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 3 |
| 放行 | 可放行；3 项 P3 全部是跨合约顺序与字段口径的可观测性问题，无资金或状态风险 |

ActionTarget 是 action 仓唯一同时承担「注册表」「加入态」「行动级铸造」三个事实的合约，四类事件各管一层，没有一条事件被两个语义复用（`JoinStateCleared` 的 `forced` 是同一事实的显式布尔，不是两个事实）。所有 emit 都在自身状态写入之后，失败整笔回滚，无软失败事件。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `ActionRegistered` | `tokenAddress`, `actionId`, `executor` | `onProposalCreated:457` | `_executorByActionId:450`、`_createdRoundByActionId:453`、`_actionIds:454`、`_actionIdsByExecutor:455` | 回调 `executor.onProposalCreated:464`（子事件 `GroupActionCreated` / `LpActionCreated` / `ServiceActionCreated`） |
| `JoinStateRegistered` | `tokenAddress`, `actionId`, `memberId` | `registerJoinState:136` | `_memberIdsByActionId.add:129`、`_actionIdsByMemberId.add:133`、`_joinedRoundByMemberId:134` | 返回 Executor，由其在同笔内继续写仓位账本并发业务事件 |
| `JoinStateCleared`（`forced=false`） | 同上 | `clearJoinState:162` | 三处删除 `:155-160` | 返回 Executor，由其后发 `*Exited` |
| `JoinStateCleared`（`forced=true`） | 同上 | `forceClearJoinState:189` | 三处删除 `:182-187` | 无（不回调 Executor，§4.4 兜底） |
| `ActionRewardMinted` | `tokenAddress`, `actionId`, `round` | `mintActionReward:277` | 无（`amount` 来自 Mint 返回值） | 返回 Executor，由其分给成员并发 `MemberRewardMinted` |

族归属：`ActionRegistered` → `action.registry`；`JoinStateRegistered` / `JoinStateCleared` → `action.participation`；`ActionRewardMinted` → `action.round`。三族在本合约各有且仅有一组发射点，`script/events/check-events.py` 报 `34 events; families OK`。

## 三、逐事件赋值链

### 3.1 `ActionRegistered`

```
event ActionRegistered(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 round,
    address indexed executor
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:458` | 根键 |
| `actionId` | 入参 `proposalId` `:459` | Core 的 `proposalId` 即 action 层的 `actionId`，两者数值相同，不另设映射 |
| `round` | `createdRound = _currentRound()` `:452`，= `IPhase.currentPhase()` `:379` | 创建投票轮，也是该行动的首个加入轮；非 indexed（3 个槽被根键、`actionId`、`executor` 占满） |
| `executor` | `abi.decode(targetData[0], (address))` `:434` | 已过 `code.length != 0:435`、`ACTION_TARGET_ADDRESS() == address(this):438-444`、`AlreadyCreated:445` 三道校验 |

`round` 的取值口径是本事件最关键的一条：`createdRound` 在同一笔里还被写入 `_createdRoundByActionId`（`:453`），`registerJoinState` 用它做 `JoinNotOpen` 下界（`:120-122`），三个 Executor 又各自从 `currentPhase()` 重读一次写进自己的 `createdRoundByActionId`。四处必须同值，依据是「同一 tx 内 `block.number` 不变 ⇒ `phaseAtBlock` 不变」，这是一条隐式承重不变式（见 `AT-3`）。

`phase == 0` 的可达性已核实为不可达：`Submit.submitNewProposal` 的顺序是 `_createProposal` → `_submitByProposalId`（首次推举触发 `Phase.sync()`）→ `_callProposalCreated`，而 `Phase.sync()` 在 `phase == 0` 时回滚 `PhaseNotStarted`（`core/src/Phase.sol:88-89`）。因此 `createdRound == 0` 这一「未创建」哨兵不会与合法的 `round = 0` 撞车。

### 3.2 `JoinStateRegistered`

```
event JoinStateRegistered(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:137` | 根键 |
| `actionId` | 入参 `:138` | 父对象 id |
| `memberId` | 入参 `:139` | actor（登记主体），indexed |
| `round` | `joinRound = currentRound - 1` `:127`，`currentRound = _currentRound()` `:118` | **加入轮**，不是投票轮；`round` 非 indexed |

三道入口判定都先于写入：`onlyBoundExecutor:117` → `currentRound <= createdRound` 回滚 `JoinNotOpen:120-122` → `contains(memberId)` 幂等返回 `:123-125`。幂等分支不发事件，`testNoEventOnDuplicateJoin` 断言 `getRecordedLogs().length == 0`。

`joinRound` 的下界由 `JoinNotOpen` 兜住：`currentRound >= createdRound + 1 ⇒ joinRound >= createdRound`，因此登记轮永不早于创建轮，与 `01-action-target.md` 的「`ActionRegistered.round` 即首个加入轮」一致。

### 3.3 `JoinStateCleared`

```
event JoinStateCleared(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    bool forced
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:163-165` / `:190-192` | 同 3.2 |
| `round` | `joinRound = _joinRound()` `:153` / `:180`，= `currentRound - 1`，`currentRound == 0` 时取 0 `:382-385` | **清理时的当前加入轮**，不是原登记轮——加入态跨轮持续，成员可能若干轮后才退出 |
| `forced` | 字面量 `false:167` / `true:194` | `true` = owner 兜底清理（只清注册表、不回调 Executor、不结算资金） |

两个发射点写入的是同一份三处删除（`:155-160` 与 `:182-187` 逐字相同），差异只有 `forced` 与鉴权入口（`onlyBoundExecutor` vs `onlyMemberOwner`）。`round == 0` 分支不可达：登记需 `currentRound >= 2`，故 `joinRound >= 1`，且 Phase 单调不减。

### 3.4 `ActionRewardMinted`

```
event ActionRewardMinted(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed round,
    uint256 amount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:278` | 根键 |
| `actionId` | 入参 `:279` | 父对象 id |
| `round` | 入参 `:280` | 纪元键，indexed（本族允许，§6.3） |
| `amount` | `IMint.mintProposalReward(...)` 的返回值 `:275` | E2：字段由外部调用返回确定，不预测、不重算 |

`mintActionReward` 不写任何自身状态，去重由 Mint 的 `ProposalRewardAlreadyMinted` 承担（§7 铸造链路）。因此本事件是「事实的唯一载体」：`amount` 与 `actionReward(tokenAddress, actionId, round)` 铸造后的返回值同源，`testActionRewardMintedEvent`（`ActionTargetEvents.t.sol:65-81`）同时断言事件值与查询值相等。

`round` 不做存在性校验（`round` 只被透传给 Mint 与 Vote 的 `isProposalIdVoted`），所以事件可以携带任意 `round`——只要 Mint 认账。这不是缺陷：门槛与轮次有效性都由 Mint / Vote 判定，ActionTarget 不重复校验（`01-action-target.md`「ActionTarget 不校验业务 Round，也不校验 Proposal 的投票门槛」）。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `_executorByActionId` | `:450` | `ActionRegistered.executor` | 直接赋值，永不改写（`AlreadyCreated` 挡住） |
| `_createdRoundByActionId` | `:453` | `ActionRegistered.round` | 直接赋值 |
| `_actionIds`（全部行动，追加） | `:454` | 由 `ActionRegistered` 折叠（append-only） | `reverse` = 创建逆序 |
| `_actionIdsByExecutor` | `:455` | 同上 | 按 `executor` 分组 |
| `_memberIdsByActionId`（按轮集合） | `add:129` / `remove:155,182` | `JoinStateRegistered` / `JoinStateCleared` | 需重放 `RoundHistoryUint256Set` 的 swap-and-pop（见 `AT-2`） |
| `_actionIdsByMemberId` | `add:133` / `remove:159,186` | 同上 | 同上，但为无轮次的 `Uint256Set` |
| `_joinedRoundByMemberId` | `:134` / `delete:160,187` | `JoinStateRegistered.round` / `JoinStateCleared` 隐含清零 | `joinedRounds` 的返回值 = 最近一次 `JoinStateRegistered.round` |
| `initialized` + 五个依赖地址 | `init:55-67` | 无（一次性 `init`，§3.2 豁免） | 部署清单承担 |

8 个可变写入面全部有事件覆盖，无遗漏。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 4 个事件均以 `tokenAddress` 开头 |
| 族槽位（§6.1） | 通过 | `action.registry`：根键 → `actionId` → `round` → `executor`；`action.participation`：根键 → `actionId` → `memberId` → `round` → 布尔；`action.round`：根键 → `actionId` → `round` → 数值 |
| indexed ≤ 3 且按优先级（§6.3） | 通过 | `ActionRegistered` 3 个（根键 → 对象 id → 对象地址，`round` 降级）；`JoinState*` 3 个（根键 → 对象 id → actor）；`ActionRewardMinted` 3 个（含纪元键） |
| 状态写入后 emit（§3.4.3） | 通过 | 5 个发射点的前置写入见第二节 |
| 父子序 / 依赖序（§3.4.5-6） | 通过（`ActionRegistered` → 子配置事件；`ActionRewardMinted` → `MemberRewardMinted`） | 见 `AT-1` 对「注册表事件早于 Executor 账本」的说明 |
| 批量逐条 emit（§3.4.1） | 通过 | 本合约无批量入口；单笔一事实 |
| 失败不留日志（§3.5） | 通过 | 三道校验、Mint 回滚、`JoinNotOpen` 均整笔回滚 |
| 动态字段上限（§6.8） | 不适用 | 4 个事件无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 报 `declaration style OK; emit style OK; emit keys OK` |
| 测试断言（§8.1） | 通过 | `ActionTargetEvents.t.sol` 逐事件断言全部字段 + 两个幂等负例 + 两种 round 口径 |

## 六、发现

### AT-1（P3）注册表事件早于 Executor 的仓位账本，且两种行动类型的插入点不同

- 证据：`GroupActionJoin._join` 的顺序是「归属索引 `:84` → `registerJoinState:86-88` → 验证值 `:89` → 金额账本 `:90` → 拉币 `:92-94` → `GroupActionJoined:96`」；`LpExecutor.join` 的顺序是「扣减与金额账本 `:170-175` → `registerJoinState:177-179` → 拉币 `:181` → `LpJoined:183`」。同为「成员加入」这一跨合约事实，`JoinStateRegistered` 在 GroupAction 里落在账本**之前**，在 LP 里落在账本**之后**。
- 问题：§3.4.6 只约束「跨合约按依赖序」，未固定注册表事实与仓位事实的先后；两种实现给出了两种相对序，而规格 `01-action-target.md` 与 `03-participation.md` 都没有写这一条。
- 影响：索引器无法写一条通用规则「见到 `JoinStateRegistered` 即仓位已落账」。对 GroupAction，若在 `JoinStateRegistered` 处快照 `joinInfo`，会读到本笔加入之前的金额（同笔内后续 `GroupActionJoined` 才补齐）；对 LP 则读到已落账的值。
- 建议：在 `01-action-target.md` 的「事件分层设计」段落补一句——`JoinStateRegistered` 只承诺「先于同笔的业务事件」，与仓位账本的相对序由各 Executor 自定；或在 GroupAction 侧把 `registerJoinState` 后移到 `_increaseAmount` 之后（纯顺序调整，不改任何计算结果）。

### AT-2（P3）`JoinState*` 的 `round` 与按轮快照同源，但成员集合顺序只能靠重放库实现还原

- 证据：`_memberIdsByActionId` 是 `RoundHistoryUint256Set`，删除是 swap-and-pop（`libs/src/RoundHistoryUint256Set.sol:31-46`：把末位搬到被删位置）。`JoinStateRegistered` / `JoinStateCleared` 只携带单个 `memberId` 与轮次，不携带位置。
- 问题：`memberIdsByActionId(token, actionId, round, offset, limit, reverse)` 的**页内顺序**由库的 swap-and-pop 决定，而事件流只给出加入/退出的时间序。要复现同一页内容，消费方必须逐字重实现 `add` / `remove` 的槽位搬移，并叠加「同一轮多次写入只保留最后一次」的 RoundHistory 语义。
- 影响：§3.3 的折叠等式（事件折叠 = view）在**集合成员**层面成立，在**顺序**层面需要重实现库；`01-action-target.md` 已声明「`offset` 的返回内容不保证跨调用稳定」，但没有说明「从事件重建顺序必须复刻 swap-and-pop」。
- 建议：在该段的「顺序契约」里补一句「重建顺序需按 `RoundHistoryUint256Set` 的 swap-and-pop 语义重放，不得按事件时间序直接拼接」；这与 `AT-1` 是同一条消费方约束的两个面。

### AT-3（P3）`createdRound` 在四处各写一份，事件只承载其中一份，同值是隐式不变式

- 证据：`_createdRoundByActionId`（本合约 `:453`）、`GroupActionManager.createdRoundByActionId`（`:123`）、`LpExecutor._createdRoundByActionId`（`:121`）、`GroupServiceExecutor._layout.createdRoundByActionId`（`:428`）四处各读一次 `IPhase.currentPhase()`；事件侧只有 `ActionRegistered.round` 一份。
- 问题：四个值必须相等，依赖「同一 tx 内 `block.number` 不变」。这条不变式没有任何测试或注释守护：若将来有人在回调里改为读 `block.number ± 1` 或引入延迟初始化，事件与 Executor 的「行动是否已创建」判定会静默分叉（`createdRound == 0` 是 `ActionNotCreated` 的判据）。
- 影响：`ActionRegistered.round` 是这四个副本的唯一外部锚点；一旦分叉，`GroupActionCreated` 之后的 `ActionNotCreated` / `RoundBeforeActionCreated` 与事件流对不上，且不会 revert。
- 建议：在 `ActionTarget.onProposalCreated` 的 `_createdRoundByActionId` 写入处加一行 `// Load-bearing:` 注释，说明「Executor 侧会重读同一 `currentPhase()`，两者必须同值」；或在 `01-action-target.md` 的创建回调段落登记该等式。

### 正面结论（不计入发现）

- 4 个事件全部覆盖 7 个可变状态写入面，无「写了不报」的字段。
- 两个幂等分支（重复登记、重复清理）都不发事件，`testNoEventOnDuplicateJoin` / `testNoEventOnDuplicateClearAndForceClearJoinState` 用 `getRecordedLogs().length == 0` 断言。
- `ActionRewardMinted.amount` 严格取 Mint 返回值（E2），`testActionRewardMintedEvent` 断言事件值与 `actionReward` 查询值相等。
- `forceClearJoinState` 不回调 Executor、不发 `*Exited`、幂等返回，与 §4.4 的兜底清理五条逐条对应。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `ActionRegistered` | `ActionTargetEvents.t.sol:9` | 4 字段全量；`round = 1`（创建轮） |
| `ActionRegistered` | `:126` | `round` 为投票轮：`setPhase(7)` 后 `round = 7` |
| `JoinStateRegistered` | `:20` | 4 字段；`round = 1`（`setPhase(2)` ⇒ 加入轮 1） |
| `JoinStateRegistered` | `:103` | `round` 为加入轮而非投票轮：`setPhase(3)` ⇒ `round = 2` |
| `JoinStateCleared` | `:33` | `forced = false`，`round = 2`（清理轮） |
| `JoinStateCleared` | `:49` | `forced = true`，同一载荷其余字段 |
| `JoinStateCleared` | `:103` | 清理轮 `= 3`，与登记轮 2 区分 |
| `ActionRewardMinted` | `:65` | 4 字段；`amount` 与 `actionReward` 同源 |
| 全部 | `:83` / `:92` | 幂等分支零日志 |

缺一条：没有任何用例断言 `ActionRegistered` 与同笔 `GroupActionCreated` 的**先后**。当前顺序由 `:457` 早于 `:464` 固定，但无回归网——若将来把回调提前到 emit 之前，索引器会先看到配置事件、后看到注册事件，`ActionRegistered` 之前拿不到 `executor` 映射。建议补一条「创建一笔 GroupAction，断言 `ActionRegistered` 的日志下标小于 `GroupActionCreated`」的用例（与 `core` 侧 `ProposalCreated → ProposalSubmitted` 的顺序断言同型）。
