# ActionTarget · 状态变量变更审查

> `action/src/ActionTarget.sol`，531 行，`action@0c1d1e2`（工作树干净）。
> 职责：行动注册表（`tokenAddress + actionId → executor`）+ 加入态的唯一所有者。四个 Executor 的「谁加入了哪个行动」全部记在这里，不在 Executor 里另存副本。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `initialized` | `bool` | 一次性开关 | `init:55` |
| 2 | `MEMBER_NFT_ADDRESS` | `address` | 成员身份根 | `init:63` |
| 3 | `SUBMIT_ADDRESS` | `address` | Core `Submit` | `init:64` |
| 4 | `VOTE_ADDRESS` | `address` | Core `Vote` | `init:65` |
| 5 | `MINT_ADDRESS` | `address` | Core `Mint`（唯一铸币出口） | `init:66` |
| 6 | `PHASE_ADDRESS` | `address` | 轮次源 | `init:67` |
| 7 | `_actionIdsByMemberId` | `mapping(address => mapping(uint256 => Uint256Set.Storage))` | 成员 → 当前加入的行动（**当前态**，可增删） | `registerJoinState:133`、`clearJoinState:159`、`forceClearJoinState:186` |
| 8 | `_memberIdsByActionId` | `mapping(address => mapping(uint256 => RoundHistoryUint256Set.Storage))` | 行动 → 按轮成员集合（**历史态**） | `registerJoinState:129`、`clearJoinState:155`、`forceClearJoinState:182` |
| 9 | `_joinedRoundByMemberId` | `mapping(address => mapping(uint256 => mapping(uint256 => uint256)))` | 行动 → 成员 → 当前加入轮（0 = 未加入） | `registerJoinState:134`、`clearJoinState:160`（`delete`）、`forceClearJoinState:187`（`delete`） |
| 10 | `_executorByActionId` | `mapping(address => mapping(uint256 => address))` | 行动绑定的 Executor（写一次，永不改） | `onProposalCreated:450` |
| 11 | `_createdRoundByActionId` | `mapping(address => mapping(uint256 => uint256))` | 行动的投票轮（0 = 未创建哨兵） | `onProposalCreated:453` |
| 12 | `_actionIds` | `mapping(address => uint256[])` | 社区全部行动 ID（升序、只增） | `onProposalCreated:454` |
| 13 | `_actionIdsByExecutor` | `mapping(address => mapping(address => uint256[]))` | Executor → 其绑定的行动（升序、只增） | `onProposalCreated:455` |

6 个配置槽 + 7 本账，共 13 个存储变量。`_memberIdsByActionId` 是唯一的按轮账本，其余都是当前态。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:51-68`）

| 位置 | 语句 | 守卫 |
| --- | --- | --- |
| `:52-55` | `if (initialized) revert; initialized = true` | 仅幂等，**无调用者限制** |
| `:57-61` | 从 `Mint` 反查 4 个地址 | 无零地址 / 无代码校验 |
| `:63-67` | 写 5 个配置槽 | — |

这 5 个槽是**本合约全部写入口的鉴权根**：`SUBMIT_ADDRESS`/`VOTE_ADDRESS` 决定三个回调谁能进，`MEMBER_NFT_ADDRESS` 决定 `forceClearJoinState` 的判据，`MINT_ADDRESS` 决定 `mintActionReward` 打到哪里，`PHASE_ADDRESS` 决定「现在第几轮」。抢跑后果已在 `action-api-auth-2026-11` 的 `AT-01` 登记，本卷不重复计数。

### 2.2 `registerJoinState`（`:113-142`）

| 顺序 | 位置 | 语句 | 失败形态 |
| --- | --- | --- | --- |
| 1 | `:117` | `onlyBoundExecutor` → `_isBoundExecutor` 先判 `bound != 0` 再比对 | `UnauthorizedExecutor` |
| 2 | `:118` | `currentRound = IPhase.currentPhase()` | 外部只读 |
| 3 | `:119-122` | `currentRound <= createdRound` → revert | `JoinNotOpen`（下界） |
| 4 | `:123-125` | `_memberIdsByActionId.contains(memberId)` → **静默 return** | — |
| 5 | `:128` | `joinRound = _joinRound()`（`ActionRoundAxis.joinRound`） | `currentRound >= 1` 由第 3 步保证；phase 0/1 时轴库返回 0，但第 3 步先命中 `JoinNotOpen` |
| 6 | `:129-132` | `_memberIdsByActionId.add(joinRound, memberId)` | 见 §3 I3 |
| 7 | `:133` | `_actionIdsByMemberId[token][memberId].add(actionId)` | 幂等 |
| 8 | `:134` | `_joinedRoundByMemberId[...] = joinRound` | — |

**关键**：第 4 步的幂等守卫读的是 `contains()`（最新集合），不是 `containsByRound(joinRound)`。因此「上一轮已退出、本轮重新加入」会走到第 6-8 步（`remove` 后 `latestValue()` 为 0），而「本轮已加入」直接返回。

### 2.3 `clearJoinState` / `forceClearJoinState`（`:144-196`）

两个函数体逐语句同构，只有三处差别：鉴权（`onlyBoundExecutor` vs `onlyMemberOwner`）、`forced` 字段、函数名。

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:149-151` / `:176-178` | `!contains(memberId)` → 静默 return | 幂等；**不报错** |
| 2 | `:153` / `:180` | `joinRound = _joinRound()`（`ActionRoundAxis.joinRound`） | 与 `registerJoinState:128` 同一实现，不再有第二份公式 |
| 3 | `:155-158` / `:182-185` | `_memberIdsByActionId.remove(joinRound, memberId)` | 只在当前加入轮形成终止点 |
| 4 | `:159` / `:186` | `_actionIdsByMemberId.remove(actionId)` | 当前态集合 |
| 5 | `:160` / `:187` | `delete _joinedRoundByMemberId[...]` | 归零 |

第 3 步只写 `joinRound`，历史轮（更早的成员记录）全部保留——这是 `isJoinedByRound` 能回答历史的原因，也是 `clearJoinState` 在「更晚的轮」执行时不会污染旧轮的原因。

### 2.4 `onProposalCreated`（`:423-469`）

| 顺序 | 位置 | 语句 | 守卫 |
| --- | --- | --- | --- |
| 1 | `:427` | `onlySubmit` | `NotSubmit` |
| 2 | `:428-433` | `targetData.length == 1` 且 `[0].length == 32` | `TargetDataLengthMismatch` / `InvalidTargetDataShape` |
| 3 | `:434-437` | `executor.code.length != 0` | `ExecutorNotContract` |
| 4 | `:438-444` | `try ACTION_TARGET_ADDRESS()` 握手并比对 | `ExecutorTargetMismatch` / `ExecutorHandshakeFailed` |
| 5 | `:445-447` | `_executorByActionId != 0` | `AlreadyCreated` |
| 6 | `:450` | 写 `_executorByActionId` | 唯一的「绑定」写入 |
| 7 | `:452-453` | `createdRound = currentPhase()`，写 `_createdRoundByActionId` | — |
| 8 | `:454` | `_actionIds[token].push(proposalId)` | — |
| 9 | `:455` | `_actionIdsByExecutor[token][executor].push(proposalId)` | — |
| 10 | `:457-462` | `ActionRegistered` | — |
| 11 | `:464-468` | 回调 `IActionExecutor(executor).onProposalCreated(...)` | 失败整笔回滚 |

第 6 步先写、第 11 步后回调，顺序正确（回调重入时 `AlreadyCreated` 已生效）。`proposalId` 由 Core `Submit` 按 `_proposals.length + 1` 分配且单调，因此 `_actionIds` 与 `_actionIdsByExecutor` 都是**严格升序**，分页 `reverse` 才有确定含义。

### 2.5 `mintActionReward`（`:264-283`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:268` | `onlyBoundExecutor` | 只有绑定 Executor 能拉 |
| 2 | `:269-271` | `IVote.isProposalIdVoted(token, round, actionId)` | `ProposalNotVoted` |
| 3 | `:273-275` | `IMint.mintProposalReward(token, round, actionId, bound)` | 铸给 `bound`（本 Executor 自己） |
| 4 | `:277-282` | `ActionRewardMinted` | — |

本合约**不写任何状态**：`round` 由 Executor 自选，窗口与「是否已铸」全由 `Mint` 判定。`AT-02` 已登记「不校验铸币窗口」，本卷只补一句状态视角的结论：因为不写状态，重入与重复调用都不会在本合约留下痕迹，`Mint` 的 `_proposalMinted` 是唯一幂等点。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| I1 | `_executorByActionId[t][a] != 0` ⟹ 该 `(t,a)` 只在 `onProposalCreated` 写过一次 | ✅ | `AlreadyCreated`（`:445`）先于写入；`_executorByActionId` 无删除路径 |
| I2 | `_actionIds[t]` 严格升序、无重复 | ✅ | `proposalId` 单调（Core `Submit._createProposal`）+ I1 |
| I3 | `_memberIdsByActionId` 的每次 `record` 轮次单调不减 | ✅ | 唯一写入轮是 `_joinRound()` = `ActionRoundAxis.joinRound`，`currentPhase()` 单调不减 |
| I4 | `_joinedRoundByMemberId[t][a][m] != 0` ⟺ `_memberIdsByActionId[t][a].contains(m)` | ✅ | 三个写点成对：`register` 同时置两者，两个 `clear` 同时清两者 |
| I5 | `_actionIdsByMemberId[t][m]` 恰为「`m` 当前加入的行动」 | ✅ | 与 I4 同笔、同判据 |
| I6 | 加入轮 `>=` 创建轮 | ✅ | `:120` 的 `currentRound <= createdRound` 拒掉「投票轮内加入」；`joinRound = _joinRound() >= createdRound` |
| I7 | `_createdRoundByActionId != 0` 对所有已创建行动成立 | ✅ | `Submit._submitByProposalId` 在 `_callProposalCreated` 之前调 `Phase.sync()`，`phase == 0` 时 `sync` 回滚 `PhaseNotStarted`，因此创建回调不可能在 Phase 0 执行 |
| I8 | `isJoinedByRound(t, a, r, m)` 对 `r > _joinRound()` 恒 false | ✅ | `:212-214` 早退；避免读到未来轮的懒继承值 |

## 4. 发现

### M-AT-01 · `joinedRounds` 是当前态，`isJoinedByRound` 是历史态，两者对已退出成员给出相反答案

| 字段 | 值 |
| --- | --- |
| 位置 | `:221-236`（`joinedRounds`）、`:206-219`（`isJoinedByRound`）、`:160`（`delete`） |
| 级别 | Info |
| 证据 | E1 |

`joinedRounds(token, actionId, memberIds[])` 读 `_joinedRoundByMemberId`，而该槽在 `clearJoinState` 里被 `delete`（`:160`）。所以一个在第 5 轮加入、第 7 轮退出的成员：

- `joinedRounds(...)` → `0`（与「从未加入」不可区分）
- `isJoinedByRound(..., 5, ...)` → `true`

`isJoinedByRound(..., 7, ...)` → `false`（`remove` 在 7 形成终止点），所以按轮读是对的；错的是 `joinedRounds` 的名字——它返回的是「当前加入轮」，不是「加入过哪些轮」。链下若用 `joinedRounds` 判「是否参与过」，会把已退出的成员全部判成未参与。

`joinedRounds` 是 `IActionTarget` 的 ABI，改名是破坏性变更。最小修正是在规格 `01-action-target.md` 的读面表里把语义写成「当前加入轮，退出后归零」，或另加一个按轮读取的入口。

### M-AT-02 · 强制清理与正常清理在状态上完全等价，`forced` 只存在于事件

| 字段 | 值 |
| --- | --- |
| 位置 | `:144-169` vs `:171-196` |
| 级别 | Info |
| 证据 | E1 |

两个函数写的是同样的三个槽位（`:155-160` 与 `:182-187` 逐语句相同），唯一的差别是 `JoinStateCleared.forced`（`:167` / `:194`）。后果：`forceClearJoinState` 之后，链上状态查询无法回答「这个成员是被群主/成员自己强制移出的，还是走完了正常退出」——只能回放日志。

这不构成缺陷（强制清理的语义就是「与正常退出等价地摘掉注册表记录」），但它是**唯一一处「状态不能回答、只有事件能回答」的事实**，与 `event-standards` §3.1「快照型事件」的取舍相反。链下索引必须把 `JoinStateCleared.forced` 落库，否则该事实永久丢失。

### M-AT-03 · 三本注册表只增不删，没有行动注销路径

| 字段 | 值 |
| --- | --- |
| 位置 | `:450`、`:454`、`:455` |
| 级别 | Info |
| 证据 | E1 |

`_executorByActionId`、`_actionIds`、`_actionIdsByExecutor` 都没有删除或改写路径。后果：

1. 一个绑定到错误 Executor 的行动无法修正（`AlreadyCreated` 永久挡住重新绑定）。
2. `_actionIdsByExecutor` 的数组随行动数单调增长，`actionIdsByExecutor` 的分页成本只增不减。
3. `actions()` 每次翻页都要为命中项逐个读 `_executorByActionId`（`:332-338`），冷读成本 × 页长。

这是注册表语义的必然（行动是历史事实），但规格没有写明「不可注销」，链下容易误以为存在治理兜底。

## 5. 已核对为正确的点

- `_isBoundExecutor`（`:98-104`）先判 `bound != address(0)` 再比对，避开「未绑定行动 + `msg.sender == 0`」的 0 哨兵陷阱（`AT-06` 已登记，本卷从状态视角复核仍成立）。
- 三个写入口的鉴权全部是函数体首道，先于任何状态读（`:117`、`:148`、`:175`）。
- `registerJoinState` 的幂等守卫在**写之前**（`:123`），因此「重复注册」不会产生第二个 `JoinStateRegistered`，也不会把 `_joinedRoundByMemberId` 推到更晚的轮。
- `clearJoinState`、`forceClearJoinState` 与 `registerJoinState` 的 `joinRound` 都取 `_joinRound()`（`ActionRoundAxis` 单一实现）；三处口径一致，不存在「注册在轮 5、清理在轮 4」的错位。
- `_memberIdsByActionId.remove` 的 `lastIndex` 计算（`RoundHistoryUint256Set:36`）依赖 `countHistory.latestValue() > 0`；本合约的 `remove` 前面都有 `contains` 守卫，两者由 I4 绑定，因此不会出现空集上 `- 1` 下溢。
- `onProposalCreated` 的握手（`:438-444`）在写 `_executorByActionId` **之前**，因此「绑定了一个不认本 Target 的 Executor」不会留下半绑定状态。
- `mintActionReward` 不写状态，`Mint` 的 `_proposalMinted` 是唯一幂等点，重复调用不会二次铸币。
- `_boundActions`（`:387-421`）用 `count` 游标原地压缩，`actionIds`/`executors` 两个数组的前 `count` 项对齐，不会返回尾部脏数据。

## 6. 覆盖缺口

- 未复核 `IVote.votedProposalIds` 在 `round` 无记录时的返回（`_boundActions:399` 依赖它返回空数组而非回滚）；该行为属 core `Vote` 的读面，本卷按「越界返回空数组」认定。
- 未测 `onProposalCreated` 在 `targetData[0]` 指向一个 `ACTION_TARGET_ADDRESS()` 返回正确值但 `onProposalCreated` 必然回滚的合约时的 gas 成本（结论是整笔回滚，与状态无关）。
- 未审 `init` 抢跑面的权限后果，见 `action-api-auth-2026-11` 的 `AT-01`。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-AT-01` | 规格补写 | [`01-action-target.md`](../../docs/specs/action/01-action-target.md) 的「状态口径」：`joinedRounds` 只表示当前加入轮，退出归零；历史参与只读 `isJoinedByRound` |
| `M-AT-02` | 规格补写 | 同上：强制清理与正常清理在状态上等价，`forced` 只存在于事件，链下索引必须落库该字段 |
| `M-AT-03` | 规格补写 | 同上：三本注册表只增不删，`AlreadyCreated` 是永久守卫，没有注销或重绑路径 |
