# LpExecutor 事件赋值与发射审查

> 对象 `action/src/LpExecutor.sol`（533 行，`contract`）
> 声明 `action/src/interfaces/ILpExecutor.sol`（`ILpExecutorEvents`，L37-65）、`action/src/interfaces/IActionExecutor.sol`（`MemberRewardMinted`，L6-15）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/04-lp-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 5 |
| 发射点 | 6（`LpExited` ×2、`LpWithdrawn` ×2 调用点共用 1 个私有发射函数） |
| 状态写入面（受事件覆盖） | 10 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 3 |
| 放行 | 可放行；3 项 P3 全部是「时间权重扣减不进事件」的折叠代价，无资金风险 |

LP 是唯一「部分撤回」的行动类型，因此也是唯一需要在事件里表达「撤回后剩余有效参与量」的类型。当前实现只发 `LpWithdrawn.amount`（本次退回额），剩余量靠「余额 − 扣减」两段账本复算，而扣减账本没有事件字段——这是本报告三条发现的共同根源。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `LpActionCreated` | `tokenAddress`, `actionId` | `onProposalCreated:123` | 四处配置 `:118-121` | 无 |
| `LpJoined` | `tokenAddress`, `actionId`, `memberId` | `join:183` | 扣减与余额六处 `:170-175`、`registerJoinState:178`、`safeTransferFrom:181` | 无 |
| `LpWithdrawn` | 同上 | `_emitLpWithdrawn:288`（调用点 `withdraw:224`、`exit:253`） | 部分撤回：四处账本 `:216-219`；全额：`_clearJoinState:211`/`:249` | 全额路径随后 `clearJoinState` → `LpExited` |
| `LpExited` | 同上 | `withdraw:228`、`exit:257` | `_clearJoinState`（`:211`/`:249`）、`clearJoinState`（`:227`/`:255`） | 无（终态标记，§4.4 E4） |
| `MemberRewardMinted` | 同上 | `_mintMemberReward:524` | 三处结算记录 `:511-515`、burn `:518`、`safeTransfer:521` | 无 |

族归属：`LpActionCreated` → `action.config`；`LpJoined` / `LpWithdrawn` / `LpExited` / `MemberRewardMinted` → `action.participation`。

## 三、逐事件赋值链

### 3.1 `LpActionCreated`

```
event LpActionCreated(
    address indexed tokenAddress,
    uint256 indexed actionId,
    address joinTokenAddress,
    uint256 govRatioMultiplier,
    uint256 minGovRatio
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` | 入参 `:124-125` | 根键 → 父 id |
| `joinTokenAddress` | `abi.decode(targetData[1], (address))` `:104` | 已过零地址 `:108-110`、`_isRegisteredPair` `:111-113`（`token0`/`token1`/`getPair` 三重 try 校验） |
| `govRatioMultiplier` | `targetData[2]` `:105` | 无上界；`0` 表示关闭上限（`:311-313`） |
| `minGovRatio` | `targetData[3]` `:106` | `<= 1e18`（`:114-116`） |

事件不带 `round`（与另两个 Executor 同型，创建轮由 `ActionRegistered.round` 承载）。

### 3.2 `LpJoined`

```
event LpJoined(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    uint256 amount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:184-186` | 根键 → 父 id → actor |
| `round` | `currentJoinRound()` `:154`（= `LpRoundAxis.joinRound`，`phase - 1`） | 加入轮 |
| `amount` | 入参 `:188` | 已过 `amount == 0` 回滚 `ZeroParticipationAmount:150-152`、首次加入的 `minGovRatio` 判定 `:157-163` |

前置写入六处（`:170-175`）：`_deductionByMemberId +=`、`_deductionByRound +=`、`_joinBlocksByMemberId.push`、`_joinAmountsByMemberId.push`、`_joinedAmountByMemberId.increase`、`_joinedAmountByActionId.increase`。随后 `registerJoinState`（`:178`，仅首次）、`safeTransferFrom`（`:181`）、emit（`:183`）。

`round` 与扣减口径同源：`deductionAdded` 用 `phaseInfo(joinRound + 1)`（`:165`），而 `joinRound + 1 == currentPhase()`，因此扣减窗口就是「加入发生的那个 Phase」的起点与长度（`04-lp-executor.md` 的时间权重公式）。

事件只带 `amount`，**不带 `deductionAdded`**：扣减量由 `min(amount, floor(amount × elapsed / phaseBlocks))` 现算，消费方需要 `phaseStartBlock` / `phaseBlocks` 才能复现（见 `LPE-EV-1`）。

### 3.3 `LpWithdrawn`

```
event LpWithdrawn(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    uint256 amount
);
```

| 发射路径 | `round` | `amount` | 前置 |
| --- | --- | --- | --- |
| 部分撤回（`withdraw:224`） | `currentJoinRound()` `:203` | 入参 `:199-201`（`<= joinedAmount`，`WithdrawAmountExceeded:205-207`） | 四处账本 `:216-219` + `safeTransfer:222` |
| 全额撤回（`withdraw:224`） | 同上 | `memberJoinedAmount` `:209` | `_clearJoinState:211` + `safeTransfer:222` |
| `exit`（`:253`） | `currentJoinRound()` `:243` | `memberJoinedAmount` `:244` | `_clearJoinState:249` + `safeTransfer:251` |

三条路径共用 `_emitLpWithdrawn`（`:281-295`），payload 一致：本次退回的代币量 + 加入轮。位置恒在 `safeTransfer` 之后，符合 §4.4 第 2 步。

部分撤回的账本（`:213-219`）是：

```
deductionReduction = floor(memberDeduction × amount / memberJoinedAmount)
_deductionByMemberId  -= deductionReduction
_deductionByRound     -= deductionReduction
_joinedAmountByMemberId.record(joined - amount)
_joinedAmountByActionId.decrease(amount)
```

四个右侧都用撤回前值。事件只记录 `amount`，`deductionReduction` 与剩余扣减都不进 payload（`LPE-EV-2`）。

### 3.4 `LpExited`

```
event LpExited(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:229-231` / `:258-260` | 同 3.2 |
| `round` | `currentJoinRound()` `:203` / `:243` | 退出轮 |

无金额，是 §4.4 E4 的终态标记。两条清仓路径的顺序逐字符合 §4.4：

```
withdraw 全额 : _clearJoinState → safeTransfer → LpWithdrawn → clearJoinState → LpExited
exit          : _clearJoinState → safeTransfer → LpWithdrawn → clearJoinState → LpExited
```

部分撤回只发 `LpWithdrawn`、不发 `LpExited`（`:226` 的 `if (isFullExit)`），`testPartialWithdrawEmitsOnlyWithdrawn`（`LpExecutorEvents.t.sol:225`）断言。

`clearJoinState` 在注册表已被 `forceClearJoinState` 清过时幂等返回、不发 `JoinStateCleared`，但 `LpExited` 仍发——此时日志是 `LpWithdrawn → LpExited`，中间没有 `JoinStateCleared`。这与 §4.4「`JoinStateCleared(forced=true)` 只代表注册表清理」的分层一致，消费方不能把「`LpExited` 之前必有 `JoinStateCleared`」当成不变式。

### 3.5 `MemberRewardMinted`（共享类）

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:525-527` | 根键 → 父 id → 结算主体 |
| `round` | 入参 `:528` | 被结算轮（`LpRoundAxis.mintRound` = `phase - 2`） |
| `mintAmount` | `_calculateReward` 返回 `:503-504` | 转给 `msg.sender` 的金额（`mintAmount != 0` 才转，`:520-522`） |
| `burnAmount` | 同上 | 销毁量（`burnAmount != 0` 才 burn，`:517-519`）；纯销毁情形下 `mintAmount = 0` 而 `minted = true` |

前置写入三处（`:511-513`）+ 第四处 `_mintedGovRatioByMemberId`（`:514-515`，铸造时的治理占比快照）。事件只承载前三个的后两个值（`mintAmount`/`burnAmount`），`govRatio` 不进 payload（`LPE-EV-3`）。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_joinTokenAddressByActionId` / `_govRatioMultiplierByActionId` / `_minGovRatioByActionId` | `:118-120` | `LpActionCreated` 三个对应字段 |
| `_createdRoundByActionId` | `:121` | `ActionRegistered.round`（跨合约） |
| `_deductionByMemberId` | `+=:170` / `-=:216` / `delete:274` | `LpJoined.amount` + 块号 + `phaseInfo` 复算（`LPE-EV-1`） |
| `_deductionByRound` | `+=:171` / `-=:217` / `-=:273` | 同上（行动级聚合） |
| `_joinBlocksByMemberId` / `_joinAmountsByMemberId` | `push:172-173` / `delete:275-276` | `LpJoined.amount` + 日志元数据（`block.number`） |
| `_joinedAmountByMemberId` | `increase:174` / `record:218` / `record(0):277` | `LpJoined` / `LpWithdrawn` |
| `_joinedAmountByActionId` | `increase:175` / `decrease:219` / `decrease:278` | 同上（行动级聚合） |
| `_memberMinted` | `:511` | `MemberRewardMinted`（`round` + `memberId` 定位） |
| `_mintedRewardByMemberId` / `_burnedRewardByMemberId` | `:512-513` | `MemberRewardMinted.mintAmount` / `.burnAmount` |
| `_mintedGovRatioByMemberId` | `:514-515` | 无（§6.9「`govRatioAtMint`」派生缓存） |

10 个写入面全部覆盖或已登记为派生缓存。`_deductionByMemberId` / `_deductionByRound` 是**未登记的派生缓存**（`LPE-EV-1` 的核心）：它们由 `LpJoined.amount` + 加入块号 + `phaseInfo` 确定性推导，但 §6.9 的清单里只有「Stake LP 基准」，没有 action 侧的扣减账本。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 5 个事件均以 `tokenAddress` 开头 |
| 族槽位 `action.config` / `action.participation` | 通过 | 见第三节各表 |
| indexed ≤ 3（§6.3） | 通过 | 全部 3 个（根键 / `actionId` / `memberId`），`round` 一致降级 |
| 清仓必发两条（§7.2 末段） | 通过 | 全额撤回与 `exit` 都发 `LpWithdrawn` + `LpExited`；部分撤回只发前者 |
| 退出四步序（§4.4） | 通过 | 清自身状态 → 转账 → `LpWithdrawn` → `JoinStateCleared` → `LpExited`，两条路径逐字一致 |
| 状态写入后 emit（§3.4.3） | 通过 | 6 个发射点全部在写入之后 |
| 资金先于金额事件（§4.4 第 2 步） | 通过 | `safeTransfer:222`/`:251` 早于 `_emitLpWithdrawn` |
| 失败不留日志（§3.5） | 通过 | 全部校验早于写入；零额结算回滚 `:507-509` |
| 动态字段上限（§6.8） | 不适用 | 5 个事件无变长字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | 见第七节 |

## 六、发现

### LPE-EV-1（P3）时间权重扣减不进事件，`_deductionByMemberId` / `_deductionByRound` 是未登记的派生缓存

- 证据：`join` 在 `:165-171` 现算 `deductionAdded = min(amount, floor(amount × (block.number − phaseStartBlock) / phaseBlocks))` 并写入两处账本；`LpJoined`（`:183-189`）只带 `amount`。`deduction()`（`:332-341`）与 `deductionByRound()`（`:343-345`）把这两个账本暴露成 view。
- 问题：要复现 `deduction()`，消费方需要（a）`LpJoined.amount`、（b）该笔加入的 `block.number`（日志元数据，可取）、（c）该 Phase 的 `startBlock` 与 `phaseBlocks`。（c）来自 core `Phase.phaseInfo`，其可重建性依赖 `PhaseSynchronized` 事件与 `ORIGIN_BLOCKS` 常量。这条推导链在 §6.9 的派生缓存清单里没有登记（清单里有「Stake LP 基准」，但那是 core 侧质押的 LP 基准，不是 action 侧的时间权重扣减）。
- 影响：§3.3 的折叠等式在 `_joinedAmountByMemberId` 层面成立（`LpJoined`/`LpWithdrawn` 直接给余额），在**有效参与量**层面依赖外部合约的事件流。若 `Phase` 的段长调整事件缺失或消费方未订阅，`deduction()` 复现不出来，而 `MemberRewardMinted` 的金额正是按有效参与量算的——对账断在中间一环。
- 建议：在 §6.9 的派生缓存清单里加一行「action LP 时间权重扣减（`_deductionByMemberId` / `_deductionByRound`）：推导输入 = `LpJoined.amount` + 加入块号 + `Phase.phaseInfo(phase)` 的 `(startBlock, phaseBlocks)`」，并注明它是**唯一**依赖 Phase 段长事件才能折叠的 action 侧账本。

### LPE-EV-2（P3）部分撤回的 `deductionReduction` 与剩余扣减都不进事件

- 证据：`withdraw` 的部分撤回分支（`:213-219`）算 `deductionReduction = floor(memberDeduction × amount / memberJoinedAmount)`，然后同时减两处扣减与两处余额；`LpWithdrawn` 只带 `amount`。
- 问题：`_deductionByMemberId` 的折叠不能只靠「加 `LpJoined.amount` 的扣减、减 `LpWithdrawn.amount`」——扣减的减少量是**按比例**的，不是等额。消费方必须逐笔重放 `floor(deduction × amount / joined)`，且每一步都要用「撤回前的 `deduction` 与 `joined`」这两个中间值。
- 影响：这是 LP 独有的形态（GroupAction 没有扣减，Service 没有仓位），因此不能复用其他 Executor 的折叠逻辑。`04-lp-executor.md` 的「部分撤回与退出」段落给出了公式，但事件契约里没有任何字段锚定结果；`test/GroupActionEvents.t.sol` 那套「累计值 = fold」的断言在 LP 侧只有余额维度（`LpExecutorEvents.t.sol` 没有 `deduction` 的 fold 用例）。
- 建议：补一条用例——「加入 100、扣减 30、撤回 40」后断言 `deduction() == 30 − floor(30×40/100) == 18` 且 `joinedAmountByMemberId == 60`，并在事件侧断言 `LpWithdrawn.amount == 40` 只表达余额变化、不表达扣减变化；若要在事件里锚定，可考虑给 `LpWithdrawn` 加 `deductionTotal`（后置扣减），代价是每次撤回多 32 字节。

### LPE-EV-3（P3）共享事件的 `round` 在 LP 与 GroupAction 上对应不同的 Phase 偏移

- 证据：`LpRoundAxis.mintRound = phase − 2`（`LpRoundAxis.sol:12-15`），`GroupActionRoundAxis.mintRound = phase − 3`（`GroupActionRoundAxis.sol:17-20`）；两个 Executor 都发 `MemberRewardMinted`，`round` 都是「被结算轮」。
- 问题：字段语义一致（业务轮），但「哪一轮现在可结算」的判定不同。§4.2 已登记 `MemberRewardMinted` 是共享类，并说明「消费方必须先按发射者确定域」；本条是同一思路在**时间轴**上的延伸，规范里没有写。
- 影响：按 `(tokenAddress, actionId, memberId, round)` 去重或关联 `MemberRewardMinted` 的消费方，若把「round = 当前 phase − 3」当成通用规则，会在 LP 上算错一轮——把还在验证中的轮次当成可结算，或反过来漏掉已可结算的一轮。共享类只在 `tokenAddress`/`actionId` 的域上做了区分，`round` 的相位偏移没有。
- 建议：在 §4.2 的共享类说明里补一句——「`MemberRewardMinted.round` 是被结算的业务轮；可结算窗口随发射者不同（LP：`phase − 2`；GroupAction / Service：`phase − 3`），消费方须按发射者选择偏移」。这与已有的「`tokenAddress` / `actionId` 指发射者所属域」是同一条注释的延伸。

### 正面结论（不计入发现）

- 两条清仓路径（全额 `withdraw` 与 `exit`）的日志序列完全一致：`LpWithdrawn → JoinStateCleared → LpExited`，`testFullWithdrawClearsRegistryAfterRefund`（`LpExecutorEvents.t.sol:136`）与 `testExitClearsRegistryAfterRefund`（`:162`）各断言一次「退款早于清注册表」。
- 部分撤回只发 `LpWithdrawn`、不发 `LpExited`（`:226`），`testPartialWithdrawEmitsOnlyWithdrawn`（`:225`）断言。
- `MemberRewardMinted` 在 burn 与转账之后 emit（`:517-524`），`testMemberRewardMintedEventWithBurn`（`:188`）与 `testMemberRewardReportsTheMintedReturnNotThePrecomputedAmount`（`:258`）分别断言纯销毁与「返回值优先于预计算值」。
- `_joinBlocksByMemberId` / `_joinAmountsByMemberId` 在部分撤回时**不缩放**（`04-lp-executor.md` 明确「保留原数组作为记录」），因此它们只增不减、只在全额清仓时 `delete`——消费方可以按数组长度识别「本轮的加入笔数」。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `LpActionCreated` | `LpExecutorEvents.t.sol:9` | 5 字段 |
| `LpActionCreated` | `:22` | emitter 为 Executor |
| `LpJoined` | `:43` | 5 字段 |
| `LpJoined` | `:56` | 结构与 `round` 口径 |
| `LpWithdrawn` | `:76` | 部分撤回，`amount` 与余额变化一致 |
| `LpWithdrawn` + `LpExited` | `:90` | 全额撤回：两条且顺序正确 |
| `LpWithdrawn` + `LpExited` | `:113` | `exit`：两条且顺序正确 |
| 清仓顺序 | `:136` / `:162` | 退款早于 `clearJoinState` |
| `MemberRewardMinted` | `:188` | 纯销毁：`mintAmount = 0`、`burnAmount > 0` |
| `MemberRewardMinted` | `:238` | 铸造只发一条（不夹带其他事件） |
| `MemberRewardMinted` | `:258` | `memberReward` 返回铸造实际值而非预计算值 |

缺两条：(a) 部分撤回后的 `deduction()` / `deductionByRound()` 取值（`LPE-EV-2`）；(b) `LpWithdrawn` 在「撤回后仍有 Provider 来源余额」时不触发 `LpExited` —— LP 无 Provider 额度，本条不适用，改为「撤回后仍有余额」的部分撤回已由 `:225` 覆盖。
