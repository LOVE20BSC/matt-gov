# GovVotedBanSource 事件赋值与发射审查

> 对象 `group-chat/src/sources/ban/GovVotedBanSource.sol`（470 行，`contract`）
> 声明 `group-chat/src/interfaces/sources/ban/IGovVotedBanSource.sol`（`IGovVotedBanSourceEvents`，L30-46）
> 基线 `group-chat@e982df8`（工作树干净）；审查日期 2026-11-03
> 判据 `matt-gov/docs/event-standards.md` v1.1（下称 §x.y）、`docs/specs/group-chat/05-chat-types.md`、`07-events-errors.md`、`08-testing.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 2（审查基线）；A2 后 3 |
| 发射点 | 2（审查基线）；A2 后 3 |
| 业务状态写入面 | 6 |
| P0 / P1 / P2 / P3 | 0 / 0 / **1** / 1（独立发现） |
| 放行 | **放行**：`GVB-EV-1` 已按 A2 拆分 `SenderBanVoteCleared` 关闭；`GVB-EV-2` 已补事件断言 |

`GovVotedBanSource` 把治理加权投票结算为「目标支持/反对权重」与「目标是否在治理封禁名单」。三条事件分别承载「某 voter 的已结算票」「某 voter 的票被清除」与「目标名单状态」：`SenderBanVoteCast` / `SenderBanVoteCleared` 先发（含后置 `supportWeight` / `opposeWeight`），`GovSenderBanChanged` 后发。顺序由 `_settleVote` → `_syncBanList` 固定。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `SenderBanVoteCast` | `groupId`, `targetSenderId`, `voterId` | `_settleVote:325` | `senderIdTargets.add` / `voters.add` / 权重增减 / `vote.supportBan` / `vote.settledWeight`（`_setVoteIfChanged:211-220`）；撤票与刷新见 `_clearVoteIfFound:247` / `_refreshVoteIfFound:283-284` | `_syncBanList:335` |
| `SenderBanVoteCleared`（A2 新增） | `groupId`, `targetSenderId`, `voterId` | `_settleVote:315` | `_removeVote` / `_removeWeight`；`prevSupportBan` / `prevSettledWeight` 在删除前捕获（`_clearVoteIfFound:247-248`、`_refreshVoteIfFound:283-284`） | `_syncBanList:335` |
| `GovSenderBanChanged` | `groupId`, `targetSenderId` | `_syncBanList:347` | `senderIdBanList.add/remove:416-421` | 返回 `_settleVote` / `_refreshVoteIfFound` |

`_settleVote` 的调用者（A2 后按 `settledWeight == 0` 分流）：

- `_setVoteIfChanged:223`：新票、改方向、改权重 → `SenderBanVoteCast`。
- `_clearVoteIfFound:250`：撤票，传 `false, 0, prevSupportBan, prevSettledWeight` → `SenderBanVoteCleared`。
- `_refreshVoteIfFound:288`（归零）/ `:296`（非零）：归零 → `SenderBanVoteCleared`；非零 → `SenderBanVoteCast`。

`_syncBanList` 也由 `_refreshVoteIfFound:271` 在「权重未变」时直接调用；此时不会发 `SenderBanVoteCast`，只有名单翻转才发 `GovSenderBanChanged`。

## 三、逐事件赋值链

### 3.1 `SenderBanVoteCast`

```
event SenderBanVoteCast(
    uint256 indexed groupId,
    uint256 indexed targetSenderId,
    uint256 indexed voterId,
    bool supportBan,
    uint256 settledWeight,
    uint256 supportWeight,
    uint256 opposeWeight
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:299` | 根键 |
| `targetSenderId` | 入参 `:300` | 被投票的 sender；只要求非零 |
| `voterId` | 入参 `:301` | 投票者 memberId |
| `supportBan` | `_settleVote` 入参 `:302` | 新票/改向：新方向；撤票与归零刷新：`false` |
| `settledWeight` | 入参 `:303` | 新票/改向：实时权重；撤票与归零刷新：`0` |
| `supportWeight` | `target.supportWeight:304` | **后置**支持总量；权重增减已在此前完成 |
| `opposeWeight` | `target.opposeWeight:305` | **后置**反对总量 |

写入路径与事件值：

| 路径 | 入口 | 状态写入 | 事件值 |
| --- | --- | --- | --- |
| 新票 | `_setVoteIfChanged:211-220` | `senderIdTargets.add`、`voters.add`、`_addWeight`、`vote.supportBan/settledWeight` | `supportBan` 新方向，`settledWeight` 实时权重，后置总量 |
| 改方向/改权重 | 同上 | `_removeWeight` 旧、`_addWeight` 新、`vote.*` 更新 | 新方向、新权重、后置总量 |
| 撤票 | `_clearVoteIfFound:247-251` | `_removeVote`（删 vote、`voters.remove`、可能 `senderIdTargets.remove`）、`_settleVote(false,0,prevSupportBan,prevSettledWeight)` | **`SenderBanVoteCleared`**：`prevSupportBan` / `prevSettledWeight` + 后置总量 |
| 刷新归零 | `_refreshVoteIfFound:283-289` | `_removeWeight`、`_removeVoteAfterWeightRemoved`、`_settleVote(false,0,prev...)` | 同上 |
| 刷新改权重 | `_refreshVoteIfFound:294-297` | `_removeWeight` 旧、`_addWeight(target, prevSupportBan, weight)`、`vote.settledWeight` 更新 | 保留原方向（`prevSupportBan`）、新权重、后置总量；发 `SenderBanVoteCast` |

`_voteWeightOrRevert:340-350` 在权重为 0 时于 `_setVoteIfChanged:198-200` 回 `ZeroVoteWeight`，因此 `settledWeight == 0` 只可能出现在非事件路径；A2 后 `SenderBanVoteCast.settledWeight` 恒非零，归零路径改发 `SenderBanVoteCleared`。

### 3.2 `GovSenderBanChanged`

```
event GovSenderBanChanged(
    uint256 indexed groupId,
    uint256 indexed targetSenderId,
    bool listed
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` | 入参 `:320` | 根键 |
| `targetSenderId` | 入参 `:321` | 被结算的目标 |
| `listed` | `shouldList = _isTargetBanned(...):313`，写入 `:318` | 后置名单状态；与 `listed=false` 一起表达移除 |

`_syncBanList:310-324` 先算 `shouldList`，与 `_isBanListed` 比较；无变化直接返回（`:314-316`）；有变化时先 `_setBanListed:318`，再 emit。`_isTargetBanned:371-379` 使用后置 `supportWeight` / `opposeWeight` 与实时 `totalVoteWeight`；阈值由 `BAN_THRESHOLD_RATIO` / `MIN_SUPPORT_TO_OPPOSE_MULTIPLIER` 决定。

### 3.3 `SenderBanVoteCleared`（A2 新增）

```
event SenderBanVoteCleared(
    uint256 indexed groupId,
    uint256 indexed targetSenderId,
    uint256 indexed voterId,
    bool prevSupportBan,
    uint256 prevSettledWeight,
    uint256 supportWeight,
    uint256 opposeWeight
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `groupId` / `targetSenderId` / `voterId` | 入参 `:316-318` | 三个根键/对象槽 |
| `prevSupportBan` | 删除前 `vote.supportBan`（`:247`、`:283`） | 被清除票的原方向，不用零哨兵 |
| `prevSettledWeight` | 删除前 `vote.settledWeight`（`:248`、`:284`） | 被清除票的原权重 |
| `supportWeight` / `opposeWeight` | 删除后的 `target.supportWeight` / `target.opposeWeight`（`:321-322`） | 后置总量 |

`_settleVote:314-323` 在 `settledWeight == 0` 时发射本事件，否则发射 `SenderBanVoteCast`（`:325-334`）；两条分支之后都调用 `_syncBanList`（`:335`）。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `senderIdTargets`（`Uint256Set`） | 首次投票 `:212`；最后票删除 `:408` | `SenderBanVoteCast` 的 voter 记录 | 首次投票加入；该 target 的 `voters` 清零时移除 |
| `senderIdTargetStates[senderId].supportWeight` | `_addWeight` / `_removeWeight:424-438` | `SenderBanVoteCast.supportWeight` | 每个 voter 事件的后置总量；也可按 voter 事件重算 |
| `senderIdTargetStates[senderId].opposeWeight` | 同上 | `SenderBanVoteCast.opposeWeight` | 同上 |
| `senderIdTargetStates[senderId].votes[voterId]` | `_setVoteIfChanged:219-220` / `delete:405` | `SenderBanVoteCast` 的 `supportBan` / `settledWeight`；删除由 `SenderBanVoteCleared` 承载 | 按 voter 取 `SenderBanVoteCast`；收到 `SenderBanVoteCleared` 即删除该 voter |
| `senderIdTargetStates[senderId].voters`（`Uint256Set`） | `add:213` / `remove:406` | `SenderBanVoteCast.voterId` / `SenderBanVoteCleared.voterId` | 首次投票加入；撤票/归零移除 |
| `senderIdBanList`（`Uint256Set`） | `_setBanListed:416-421` | `GovSenderBanChanged.listed` | 按日志顺序取最后一条 |

六个业务写入面全部有事件覆盖；`voters` / `senderIdTargets` 是 `Uint256Set`，枚举页序需要重放 swap-and-pop（`GL-EV-2`）。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 三条事件均以 `groupId` 开头 |
| `gc.ban-vote` 槽位（§6.1） | 通过 | 根键 → `targetSenderId` → `voterId` → 布尔 → 数值；`SenderBanVoteCleared` 的布尔/数值是旧值 + 后置总量；`GovSenderBanChanged` 省略 voter 槽 |
| indexed ≤ 3（§6.3） | 通过 | `SenderBanVoteCast` / `SenderBanVoteCleared` 各 3 个（三个 id）；`GovSenderBanChanged` 2 个 |
| 状态写入后 emit（§3.4.3） | 通过 | 票与权重先写，`SenderBanVoteCast` / `SenderBanVoteCleared` 后发；名单先写，`GovSenderBanChanged` 后发 |
| 依赖序（§3.4.5） | 通过 | `SenderBanVoteCast` / `SenderBanVoteCleared` → `GovSenderBanChanged`；名单判定依赖后置权重 |
| 批量逐条 emit（§3.4.1） | 通过 | 单票入口；无批量投票 |
| 零事实不发事件（§3.5） | 通过 | 权重/方向未变的重复投票回 `VoteUnchanged`（`:207-209`）；权重未变刷新只有名单翻转才发 `GovSenderBanChanged`（`:314-316`） |
| 旧值（§6.7） | 通过 | `GovSenderBanChanged.listed` 布尔可反推；`SenderBanVoteCleared` 显式携带 `prevSupportBan` / `prevSettledWeight`（A2） |
| 累计值（§3.1） | 通过 | `supportWeight` / `opposeWeight` 是后置总量；`settledWeight` 是 voter 权重 |
| 动态字段上限（§6.8） | 不适用 | 无 `string` / `bytes` / 数组字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿；事件声明在 `IGovVotedBanSourceEvents` |
| 测试断言（§8.1） | 通过（本卷已闭合） | 初始投票、列表翻转、撤票/刷新归零、解封、多 voter 后置总量、旧值与后置总量可区分均有断言（`GVB-EV-2`、`T131E`）；emitter 已断言（`GL-EV-1`） |

## 六、发现

### GVB-EV-1（P2）撤票与刷新归零复用 `SenderBanVoteCast`，用 `settledWeight = 0` 表达「无票」

- 证据：`_clearVoteIfFound:243-244` 在 `_removeVote` 后调用 `_settleVote(state, groupId, targetSenderId, voterId, false, 0, totalWeight)`；`_refreshVoteIfFound:275-279` 在权重归零时同样调用 `_settleVote(..., false, 0, ...)`；`_settleVote:298-306` 原样把 `supportBan=false`、`settledWeight=0` 写入事件。`_setVoteIfChanged:198-200` 对权重 0 的投票回 `ZeroVoteWeight`，因此 `settledWeight == 0` 在 `SenderBanVoteCast` 中只表示「票已被删除」。
- 问题：§3.6 明确「事件中不得使用哨兵值表达「不存在」；可选引用用显式布尔字段区分」。这里用一个业务上不可能出现的 `settledWeight=0` 表达「voter 已无票」，并且把 `supportBan` 填成 `false`——对曾经投支持票的 voter，撤票事件的方向字段与其历史方向相反。事件名 `VoteCast` 也不能表达「撤票」这一反向迁移；§3.1 允许同一状态维度的不同迁移拆成不同事件类。
- 影响：按 voter 折叠的消费方必须特判 `settledWeight == 0`，否则会把撤票记成「反对票权重 0」；若未来出现合法的零权重票语义（例如弃权），该哨兵将无法区分。`supportWeight` / `opposeWeight` 后置总量仍正确，所以这是**语义/可重建性**问题，不是资金或权限问题。
- 建议（二选一）：
  1. 在 `SenderBanVoteCast` 增加显式 `bool cleared`（或 `bool hasVote`），撤票/归零刷新时 `cleared = true`、`supportBan` 填被删除票的原方向（或明确忽略）；同步更新 `IGovVotedBanSource`、`events-baseline.txt`、`event-families.txt`、`check-events.py` 的族槽位与测试。
  2. 拆分 `SenderBanVoteCleared(groupId, targetSenderId, voterId, prevSupportBan, prevSettledWeight, supportWeight, opposeWeight)`，把撤票/归零刷新从 `VoteCast` 中移出；`voteByTargetSenderId` / `refreshVoteByTargetSenderId` 的规格与测试同步。
  若坚持保留单一事件，必须在 `05-chat-types.md` 或 `07-events-errors.md` 明确登记为 §3.6 的书面例外，并给出「`settledWeight == 0` 即无票、`supportBan` 不参与折叠」的折叠规则；当前文档只写了「撤票移除旧权重」，没有这条例外。
- **处置（A2，已落地）**：采用方案 2，新增 `SenderBanVoteCleared`（`IGovVotedBanSource.sol:41-49`），`_settleVote:314-334` 按 `settledWeight == 0` 分流；`prevSupportBan` / `prevSettledWeight` 在删除前捕获（`_clearVoteIfFound:247-248`、`_refreshVoteIfFound:283-284`）。`SenderBanVoteCast` 的签名与 topic0（`0x3bc5296d…`）不变；新事件 topic0 为 `0xb71550ca…`。`events-baseline.txt` 18→19、`event-families.txt` 16→17；`05-chat-types.md:31/41`、`07-events-errors.md:56`、`08-testing.md:23`、`event-standards.md:421`、`02-coverage-matrix.md:95/111` 同步。

### GVB-EV-2（P3）撤票/刷新归零、解封与多 voter 后置总量没有事件断言

- 证据：
  - `testT130C`（`GovVotedBanSource.t.sol:112-138`）只覆盖第一次支持票：`logs.length == 2`、`SenderBanVoteCast` 的 `supportBan=true` / `settledWeight=7` / `supportWeight=7` / `opposeWeight=0`，随后 `GovSenderBanChanged(listed=true)`。
  - `testT131`（`:140-166`）覆盖撤票与刷新对**视图**的影响，但没有 `recordLogs`；`testT131C`（`:168-193`）只断言「权重未变刷新零日志」与视图翻名单，没有断言 `GovSenderBanChanged(listed=false)`；`testT131D`（`:195-209`）只断言阈值以下只发投票事件。
  - `testT130` / `testT130B`（`:56-110`）有多 voter、支持/反对与刷新，但没有事件断言；`supportWeight` / `opposeWeight` 的后置总量只在单 voter 的 T130C 中断言。
- 问题：§8.1 要求每个事件至少断言发射条件、次数、字段与取值；§8.8 要求累计值断言 `cumulative == fold`。当前测试没有覆盖：撤票事件的 `settledWeight=0` / 后置总量、刷新归零、`GovSenderBanChanged(listed=false)`、两个 voter 之后的 `supportWeight` / `opposeWeight`。
- 影响：`GVB-EV-1` 所依赖的「归零即撤票」语义没有测试锁定；如果 `_settleVote` 在撤票时传错方向或总量，现有视图测试可能仍然通过（视图由存储重算），但事件流已错。
- 建议：补事件断言：撤票后 `SenderBanVoteCast` 的 `settledWeight=0`、后置总量；刷新归零同样；权重未变但名单翻转时只有 `GovSenderBanChanged(listed=false)`；两个 voter 支持/反对后 `SenderBanVoteCast.supportWeight` / `opposeWeight` 等于 fold；所有事件断言 emitter（`GL-EV-1`）。若按 `GVB-EV-1` 新增 `cleared` 或拆事件，上述用例同步改造。
- **处置（已落地）**：新增 `testT131E`（`GovVotedBanSource.t.sol:221-297`）覆盖三类缺口：① 第二个 voter 的 `SenderBanVoteCast`（`supportBan=false`、`settledWeight=5`、`supportWeight=7`、`opposeWeight=5`）与随后 `GovSenderBanChanged(listed=false)`；② 撤票 `SenderBanVoteCleared(prevSupportBan=true, prevSettledWeight=7)` 与后置 `support=0 / oppose=5`；③ 刷新归零 `SenderBanVoteCleared(prevSupportBan=false, prevSettledWeight=5)` 与后置 `support=7 / oppose=0`，均与 `prev*` 取值可区分。`T130C` / `T131D` 的事件断言同步到新语义，`T131` 新增归零路径的 `SenderBanVoteCleared` 断言，`T131C` 的「同值刷新零日志」断言经 A2 仍成立（该用例不产生日志，无需 emitter）。

### 关联项（不重复计数）

- `GL-EV-2`（P3，跨合约）：`votedSenderIds` 使用 `senderIdTargets.values`，`votersBySenderId` 使用 `target.voters.values`；两者都是 `Uint256Set` 当前存储顺序，事件流只给出投票/撤票时间序。`08-testing.md:14` 已把 `reverse` 行为登记为「当前存储顺序」，但事件折叠规则未登记重放 swap-and-pop 的要求。详见 README §五。
- `GL-EV-1`（P3，跨合约）：~~`testT130C` 没有断言 `log.emitter == address(banSource)`~~；本卷已补（`T130C` / `T131D` / `T131E`）。详见 README §五。

### 正面结论（不计入发现）

- `SenderBanVoteCast` 的 `supportWeight` / `opposeWeight` 是后置总量，且事件在权重增减之后发射；单 voter 用例正确。
- `GovSenderBanChanged` 在名单写入之后发射，且只在 `listed` 实际翻转时发；`_syncBanList:314-316` 的 no-op 零日志有 `testT131C:176-178` 覆盖。
- 权重/方向未变的重复投票回 `VoteUnchanged`，不做名单同步；`testT131C` 覆盖。
- 权重源不可用时，写入/撤票/刷新先回 `BanVoteWeightSourceUnavailable`；视图侧按规格降级，`testT133` 覆盖。
- `refreshVoteByTargetSenderId` 无鉴权、幂等、结果与调用者无关；权重未变时只同步名单，不发投票事件；符合 `05-chat-types.md`。
- 不设版本字段/版本事件；每次已结算变更由 `SenderBanVoteCast` / `SenderBanVoteCleared` / `GovSenderBanChanged` 携带（A2 后三条），符合 `07-events-errors.md`。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `SenderBanVoteCast` | `GovVotedBanSource.t.sol:112-138`（T130C） | 单 voter 支持票；3 个 topic、4 个 data 字段、emitter |
| `SenderBanVoteCast` | `:195-209`（T131D） | 阈值以下只发投票事件；emitter |
| `SenderBanVoteCast` | `:221-297`（T131E） | 第二 voter 反对票；后置 `support=7 / oppose=5`；emitter |
| `SenderBanVoteCleared` | `:221-297`（T131E） | 撤票与刷新归零；`prevSupportBan` / `prevSettledWeight` 与后置总量可区分；emitter |
| `GovSenderBanChanged` | `:112-138`（T130C） | `listed=true` 字段；emitter |
| `GovSenderBanChanged` | `:221-297`（T131E） | `listed=false`（解封）与 `listed=true`（复封）；emitter |
| 已闭合 | — | 撤票/刷新归零的旧方向/旧权重与后置总量（`GVB-EV-2`） |
| 已闭合 | — | 两个 voter 以上的 `supportWeight` / `opposeWeight` 事件值（`GVB-EV-2`） |
| 已闭合 | — | 解封 `GovSenderBanChanged(listed=false)` 事件（`GVB-EV-2`） |

## 八、复现

```bash
cd group-chat

python3 script/events/check-events.py
forge test --match-contract GovVotedBanSourceTest
# → 19 passed, 0 failed
```
