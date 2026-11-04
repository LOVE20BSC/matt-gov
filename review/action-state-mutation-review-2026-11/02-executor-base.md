# ExecutorBase · 状态变量变更审查

> `action/src/ExecutorBase.sol`，140 行，`action@0c1d1e2`。
> 职责：三个 Executor 的唯一抽象基类。**没有任何可变状态**——四个依赖全部是 `immutable`，在构造函数里从 `ActionTarget` 一次派生到底。本卷要审的是「不可变状态是怎么被定下来的」以及「基类替子类承担了哪些守卫」。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `ACTION_TARGET_ADDRESS` | `address immutable` | 回调门禁的唯一根 | 构造器 `:20` |
| 2 | `STAKE_ADDRESS` | `address immutable` | 治理票与质押源 | 构造器 `:23` |
| 3 | `MEMBER_NFT_ADDRESS` | `address immutable` | 25 个业务入口的鉴权函数 | 构造器 `:24` |
| 4 | `PHASE_ADDRESS` | `address immutable` | 三个 Round 轴 | 构造器 `:25` |

继承自 `ReentrancyGuard` 的 `_status` 是唯一可变的存储槽（`uint256`，0/1/2），由 `nonReentrant` 维护；本卷不展开（OZ 5.6.1 的公开语义）。

## 2. 逐变量变更逻辑

### 2.1 构造函数（`:19-26`）——一次派生链

| 顺序 | 位置 | 语句 | 若上一步为 0 的后果 |
| --- | --- | --- | --- |
| 1 | `:20` | `ACTION_TARGET_ADDRESS = actionTargetAddress` | 唯一入参，无零地址/代码校验 |
| 2 | `:23` | `STAKE_ADDRESS = IVote(IActionTarget(actionTargetAddress).VOTE_ADDRESS()).STAKE_ADDRESS()` | 若 `ActionTarget.init` 未执行，`VOTE_ADDRESS()` 返回 0 → 对 `address(0)` 调 `STAKE_ADDRESS()` 得到空返回 → ABI 解码失败 → **构造回滚** |
| 3 | `:24` | `MEMBER_NFT_ADDRESS = IStake(STAKE_ADDRESS).MEMBER_NFT_ADDRESS()` | 同上 |
| 4 | `:25` | `PHASE_ADDRESS = IStake(STAKE_ADDRESS).PHASE_ADDRESS()` | 同上 |

四步都是外部调用 + 解码，任何一步的返回值缺失或长度不对都会让部署失败。因此**「`ActionTarget.init` 必须先于三个 Executor 的构造」是一条隐式部署顺序约束**，它不由任何断言表达，只由 ABI 解码的失败形态表达。

`STAKE_ADDRESS` 刻意不从构造函数收第二个参数，而是从 `ActionTarget.VOTE_ADDRESS()` 反查（`:21-22` 的注释），因此「Executor 认为的 Stake」与「ActionTarget 认为的 Vote」不可能不一致——这是本基类最重要的一条结构性决定，代价是部署顺序被写死。

### 2.2 `nonReentrant` 的覆盖范围

`mintMemberReward`（`:51-58`）、`mintMemberRewards`（`:60-81`）在基类加锁；子类的业务入口各自加锁（`LpExecutor.join/withdraw/exit`、`GroupActionExecutor` 的 17 个写入口里 12 个、`GroupServiceExecutor.join/exit`）。基类不提供「统一加锁」，锁是逐入口的。

### 2.3 `_checkMintWindow`（`:107-128`）——四段守卫的顺序

| 顺序 | 位置 | 条件 | 错误 |
| --- | --- | --- | --- |
| 1 | `:115-117` | `createdRound == 0` | `ActionNotCreated` |
| 2 | `:118-120` | `round < createdRound` | `RoundBeforeActionCreated` |
| 3 | `:121-124` | `round > _mintRound()` | `RoundAfterMintWindow` |
| 4 | `:125-127` | `alreadyMinted` | `RewardAlreadyMinted` |

四段的顺序与规格 `04-lp-executor.md:39`「先判行动是否存在、再判轮次是否早于创建轮，两段不合并」一致。第 3 段读的是子类的 `_mintRound()`，而 `_mintRound()` 在阶段未开始时返回 **0**（`GroupActionRoundAxis:12`、`GroupServiceRoundAxis:7`、`LpRoundAxis:7`）——见 M-EB-01。

`alreadyMinted` 由调用方从各自的 `_memberMinted` 读出后传入（`:113`），因此基类不拥有「已结算」这个状态，只负责判定顺序。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| B1 | 四个 immutable 在部署后不可变 | ✅ | `immutable` |
| B2 | `STAKE_ADDRESS == IVote(ACTION_TARGET_ADDRESS.VOTE_ADDRESS()).STAKE_ADDRESS()` | ✅ | 构造器逐字派生（`:23`） |
| B3 | `MEMBER_NFT_ADDRESS` / `PHASE_ADDRESS` 与 `Stake` 自报的同名 getter 相等 | ✅ | 构造器逐字派生（`:24-25`） |
| B4 | `ACTION_TARGET_ADDRESS` 是 `ActionTarget` 且其 `init` 已执行 | ⚠️ 仅由部署脚本保证 | 构造器不校验代码、不校验 `initialized`；错绑的后果是回调门禁失效（只影响本 Executor） |
| B5 | `mintMemberRewards` 的两个返回数组与入参等长 | ✅ | `:76-77` 按 `length` 分配，`:78` 循环填满 |
| B6 | `mintMemberRewards` 的 `actionIds`/`rounds` 等长 | ✅ | `:72-74` 先判后循环 |

## 4. 发现

### M-EB-01 · 铸币阶段未开始时，内部路径报 `RoundAfterMintWindow(round, 0)`，ABI getter 报 `RoundNotStarted(1, 0)`

| 字段 | 值 |
| --- | --- |
| 位置 | `:121-124`（`_checkMintWindow`）、`:99-105`（`currentMintRound`） |
| 级别 | Info |
| 证据 | E1 |

`_mintRound()` 在 `phase < 4` 时返回 0（`GroupActionRoundAxis:12`、`GroupServiceRoundAxis:7`）或 `phase < 3` 时返回 0（`LpRoundAxis:7`）。两条路径对同一个「阶段还没开始」给出不同错误：

| 入口 | 判定 | 错误 |
| --- | --- | --- |
| `currentMintRound()`（ABI） | `round == 0` → revert | `RoundNotStarted(1, 0)` |
| `mintMemberReward(s)`（业务） | `round > 0`（因为 `round >= createdRound >= 1`） | `RoundAfterMintWindow(round, 0)` |

链下按错误名分类时，「铸币阶段未开始」会被拆成两类：查询类归 `RoundNotStarted`，结算类归 `RoundAfterMintWindow`。后者字面意思是「轮次太新」，语义正好相反（实际是「阶段太早」）。

不改状态，只影响错误契约。修法二选一：在 `_checkMintWindow` 第 3 段前加一句 `if (mintRound == 0) revert RoundNotStarted(1, 0)`，或让 `_mintRound()` 自己回滚（但那会与「轴库只做纯换算」的分层冲突，见 `02-phase-model.md`）。

### M-EB-02 · 四个 immutable 的取值依赖「`ActionTarget.init` 先执行」，该约束只由解码失败表达

| 字段 | 值 |
| --- | --- |
| 位置 | `:23-25` |
| 级别 | Info |
| 证据 | E1 |

`IVote(IActionTarget(actionTargetAddress).VOTE_ADDRESS()).STAKE_ADDRESS()` 是三层外部调用。若部署脚本在 `ActionTarget.init` 之前构造任一 Executor：

- `ActionTarget.VOTE_ADDRESS()` 返回 `address(0)`；
- 对 `address(0)` 发起 `STATICCALL` 成功但返回空；
- `STAKE_ADDRESS()` 的返回值解码失败 → `abi.decode` 回滚 → 构造回滚。

也就是说，**顺序错误的表现是「部署失败」而不是「部署成功但接错线」**——这是好的失败形态，但它不可读：报错是解码 panic，不是一句 `ActionTargetNotInitialized`。部署脚本已经按正确顺序执行（`DeployAction`），本卷只记录「这条顺序约束没有显式断言」。

### M-EB-03 · `mintMemberRewards` 无批量上限，且循环内可能逐项触发外部铸币

| 字段 | 值 |
| --- | --- |
| 位置 | `:60-81` |
| 级别 | Info |
| 证据 | E1 |

只校验两数组等长（`:72`），没有长度上限。循环体 `_mintMemberReward` 在 `!actionMinted` 时会调用 `ActionTarget.mintActionReward`（`GroupActionExecutor:723`、`LpExecutor:501`），即**每次迭代可能带一次跨合约铸币 + 一次 `safeTransfer`**。

后果：单笔 gas 上界由调用者自选；批量里任意一项失败整笔回滚，因此不存在部分结算。这是调用者自付的成本，不是攻击面（`onlyMemberOwner` + `nonReentrant`），但与 `Vote` 的批次上限（`VOT-03`）一样属于「协议不设上界、由调用者控制」的口径，规格未登记。

## 5. 已核对为正确的点

- 四个 immutable 全部在构造器一次写定，没有任何 setter 或二次初始化入口（对比 `ActionTarget.init`）。
- `STAKE_ADDRESS` 的单点派生（`:23`）使「ActionTarget 认的 Vote」与「Executor 认的 Stake」不可能分叉，比让部署脚本传两个地址更安全。
- 两个 modifier 都自己判调用者、有 revert、以 `_;` 收尾（`EB-03`/`EB-04` 已登记，本卷复核仍成立）。
- `_checkMintWindow` 的四段顺序与规格一致，且 `alreadyMinted` 由子类传入——基类不复制「已结算」状态，避免了两份账。
- `mintMemberRewards` 的返回数组按入参长度预分配（`:76-77`），循环下标与两个数组严格对齐，不会出现长度错位。
- `currentVoteRound`/`currentJoinRound`/`currentMintRound` 三个 getter 的 `RoundNotStarted(1, 0)` 载荷一致（`:86`、`:94`、`:102`）。

## 6. 覆盖缺口

- `ReentrancyGuard._status` 的状态机按 OZ 5.6.1 的公开语义认定，未逐行复核。
- 未审三个 Executor 各自的 `nonReentrant` 覆盖是否完整（见 `action-api-auth-2026-11` 的 `GAE-07`、`GSE-03`、`G-05`）。
- 未测「`ActionTarget` 已初始化但指向一个 `VOTE_ADDRESS()` 返回非零垃圾值的假 Target」时的构造函数行为（结论：只要返回值能解码就构造成功，之后每次回调都会失败——属部署期信任问题，与 `AT-03` 同源）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-EB-01` | 已修复 | `ExecutorBase._checkMintWindow` 在 `mintRound == 0` 时回滚 `RoundNotStarted(1, 0)`，`RoundAfterMintWindow` 只用于「已开始但已过窗」；`LpExecutor.t.sol` 的窗口断言同步更新。修复后 `ExecutorBase` 140 → 143 行，`:121` 之后的行号后移 3 行 |
| `M-EB-02` | 规格补写 | [`00-executor-interface.md`](../../docs/specs/action/00-executor-interface.md) 的「状态口径」：`init` 必须先于 Executor 部署与绑定，部署脚本以 `initialized()` 断言收尾 |
| `M-EB-03` | 规格补写 | 同上：批量不设长度上限，逐元素可能触发外部铸币，任一元素失败整笔回滚，不存在部分结算 |
