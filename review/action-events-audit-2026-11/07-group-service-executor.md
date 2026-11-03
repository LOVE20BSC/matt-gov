# GroupServiceExecutor 事件赋值与发射审查

> 对象 `action/src/GroupServiceExecutor.sol`（800 行，`contract`，含 `GroupRecipients` 库的宿主）
> 声明 `action/src/interfaces/IGroupServiceExecutor.sol`（`IGroupServiceExecutorEvents`，L7-49）、`action/src/interfaces/IActionExecutor.sol`（`MemberRewardMinted`，L6-15）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/06-service-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 5（含共享类 `MemberRewardMinted`）+ 经库委托的 `RecipientPaid` / `RecipientsChanged` |
| 本合约地址的发射点 | 7（自身 5 + `GroupRecipients` 委托 2） |
| 状态写入面（受事件覆盖） | 10 |
| P0 / P1 / P2 / P3 | 0 / 0 / 1 / 2 |
| 放行 | 有 1 项 P2：结算的「聚合事件」全部晚于其明细事件，且该顺序未被 §3.4.6 的例外清单覆盖 |

服务层是 action 仓里唯一同时产出「角色细分」与「二次分配明细」两层事件的模块：`ServiceRewardsDistributed` 给 owner/验证者两个角色的金额拆分，`RecipientPaid` 给二次分配的逐笔付款。两者之间夹着共享类 `MemberRewardMinted`（公共口径的聚合值）。三层事件的相对顺序是本报告的主要问题（`GSE-EV-1`）。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `ServiceActionCreated` | `tokenAddress`, `actionId` | `onProposalCreated:430` | 四处配置 `:425-428` | 无 |
| `ServiceJoined` | `serviceTokenAddress`, `serviceActionId`, `memberId` | `join:131` | `ActionTarget.registerJoinState:129`（本合约无自身状态） | 无 |
| `ServiceExited` | 同上 | `exit:384` | `ActionTarget.clearJoinState:382` | 无 |
| `MemberRewardMinted` | `tokenAddress`, `actionId`, `memberId` | `_mintMemberReward:779` | 三处结算记录 `:744-746`、burn `:748-751`、`RecipientPaid` ×N（`:756`）、两笔转账 `:772-777` | `ServiceRewardsDistributed:787` |
| `ServiceRewardsDistributed` | `serviceTokenAddress`, `serviceActionId`, `actionTokenAddress` | `_mintMemberReward:787` | 同上 | 无 |
| `RecipientPaid`（库委托） | `serviceTokenAddress`, `serviceActionId`, `groupId` | `GroupRecipients:355` | `safeTransfer:241` | 循环下一个收款人 |
| `RecipientsChanged`（库委托） | `sourceTokenAddress`, `sourceActionId`, `groupId` | `GroupRecipients:106` | 三处历史 + 枚举集合 `:96-104` | 无 |

族归属：`ServiceActionCreated` → `action.config`；`ServiceJoined` / `ServiceExited` / `MemberRewardMinted` → `action.participation`；`ServiceRewardsDistributed` → `action.service`；`RecipientPaid` → `action.service`；`RecipientsChanged` → `action.recipients`。

## 三、逐事件赋值链

### 3.1 `ServiceActionCreated`

```
event ServiceActionCreated(
    address indexed tokenAddress,
    uint256 indexed actionId,
    address actionTokenAddress,
    uint256 govRatioMultiplier,
    uint256 publicVerifierRatio
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:431` | 根键（服务代币） |
| `actionId` | 入参 `serviceActionId` `:432` | 服务 Proposal 的 id |
| `actionTokenAddress` | `abi.decode(targetData[1], (address))` `:408` | 已过零地址 `:412-414`、父子关系 `:418-423`（相同或直接父币） |
| `govRatioMultiplier` | `targetData[2]` `:409` | 无上界（乘数可任意大，`_applyFormulas` 用 `mulDiv` 不会溢出） |
| `publicVerifierRatio` | `targetData[3]` `:410` | `<= 1e18`（`:415-417`，否则 `1e18 - r` 下溢） |

事件不带 `round`：`createdRoundByActionId`（`:428`）与同笔 `ActionTarget.ActionRegistered.round` 同值，由后者承载（与 `GroupActionCreated` / `LpActionCreated` 同型）。

### 3.2 `ServiceJoined` / `ServiceExited`

```
event ServiceJoined(address indexed serviceTokenAddress, uint256 indexed serviceActionId,
                    uint256 indexed memberId, uint256 round);
event ServiceExited(address indexed serviceTokenAddress, uint256 indexed serviceActionId,
                    uint256 indexed memberId, uint256 round);
```

| 字段 | `ServiceJoined`（`:131`） | `ServiceExited`（`:384`） |
| --- | --- | --- |
| `serviceTokenAddress` / `serviceActionId` / `memberId` | 入参 `:132-134` | 入参 `:385-387` |
| `round` | `currentJoinRound()` `:118` | `currentJoinRound()` `:381` |

两条都不带金额（服务无仓位、无退款），只带根键 + `memberId` + `round`，与 §4.4「`GroupServiceExecutor` 无自身仓位也无退款，只有第 3、4 步」逐字对应：

```
join :  registerJoinState（→ JoinStateRegistered）  →  ServiceJoined
exit :  clearJoinState  （→ JoinStateCleared(false)） →  ServiceExited
```

`join` 的资格判定（`:120-127`）与 `exit` 的已加入判定（`:377-379`）全部早于 `registerJoinState` / `clearJoinState`，失败零日志。重复 `join` 回滚 `AlreadyJoined:120-122`，未加入 `exit` 回滚 `NotJoined:377-379`，因此两条事件都是「一进一出各一条」。

### 3.3 `MemberRewardMinted`（共享类）

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `memberId` | 入参 `:780-782` | 服务侧根键 → 服务 actionId → 结算主体 |
| `round` | 入参 `:783` | 被结算轮 |
| `mintAmount` | `settlement.verifierReward + settlement.ownerReward` `:718`，必要时经 `:728` 重算 | 聚合值：两个角色的可铸造之和（§4.2 明确本发射者上是聚合口径） |
| `burnAmount` | `settlement.ownerBurned` `:719` / `:729` | 与同笔 `ServiceRewardsDistributed.ownerBurned` **恒等**（§4.2 登记的有意冗余） |

前置写入 `:744-746`（`memberMinted`、`verifierRewardByMemberId`、`ownerBurnedByMemberId`）与 `:769-770`（`ownerDistributedByMemberId`、`ownerRemainingByMemberId`）全部早于 emit；burn（`:750`）与两笔 `safeTransfer`（`:773`、`:776`）也早于 emit。因此本事件是「状态与资金都已落定」之后才发的——这一点与 `GSE-EV-1` 有关：**它其实不需要等到二次分配结束**。

### 3.4 `ServiceRewardsDistributed`

```
event ServiceRewardsDistributed(
    address indexed serviceTokenAddress,
    uint256 indexed serviceActionId,
    uint256 round,
    address indexed actionTokenAddress,
    uint256 memberId,
    uint256 verifierReward,
    uint256 ownerReward,
    uint256 ownerBurned,
    uint256 ownerDistributed,
    uint256 ownerRemaining
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `serviceTokenAddress` / `serviceActionId` / `round` | 入参 `:788-790` | 服务侧三键 |
| `actionTokenAddress` | `settlement.actionTokenAddress` `:791` | 源链限定根键（§6.2） |
| `memberId` | 入参 `:792` | 结算主体；同一 `memberId` 可能同时是 owner 与锁定验证者，两个角色分别计价 |
| `verifierReward` | `settlement.verifierReward` `:793` | 公共验证者份额 |
| `ownerReward` | `settlement.ownerReward` `:794` | owner 份额（治理上限触发后为 `mulDiv(serviceReward, cap, PRECISION)`） |
| `ownerBurned` | `burnAmount` `:795` | owner 超额销毁；= `MemberRewardMinted.burnAmount` |
| `ownerDistributed` | `distributed` `:796` | 实际转给二次分配接收者的总额（= 同笔 `Σ RecipientPaid.amount`） |
| `ownerRemaining` | `remaining = ownerReward - distributed` `:768`、`:797` | 留在 owner 手中的部分（含无配置行动的整份切片与逐项取整余数） |

恒等式（`06-service-executor.md` 已声明）：`ownerReward == ownerDistributed + ownerRemaining`、`mintAmount == verifierReward + ownerReward`、`burnAmount == ownerBurned`。前两条由 `GroupServiceEvents.t.sol:44-59` 断言，第三条由同处断言。

`ownerDistributed` 是**唯一**把二次分配结果回填到角色事件里的字段，因此它必然晚于全部 `RecipientPaid`（依赖序，§3.4.5）。`ownerRemaining` 是聚合余量，不带「哪个源行动留了多少」的拆分（`GSE-EV-3`）。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `actionTokenAddressByActionId` / `govRatioMultiplierByActionId` / `publicVerifierRatioByActionId` | `:425-427` | `ServiceActionCreated`（三个对应字段） |
| `createdRoundByActionId` | `:428` | `ActionRegistered.round`（跨合约） |
| `memberMinted` | `:744` | `MemberRewardMinted` |
| `verifierRewardByMemberId` | `:745` | `MemberRewardMinted.mintAmount`（拆分）+ `ServiceRewardsDistributed.verifierReward` |
| `ownerBurnedByMemberId` | `:746` | `MemberRewardMinted.burnAmount` + `ServiceRewardsDistributed.ownerBurned` |
| `ownerDistributedByMemberId` | `:769` | `ServiceRewardsDistributed.ownerDistributed` |
| `ownerRemainingByMemberId` | `:770` | `ServiceRewardsDistributed.ownerRemaining` |
| `totalGroupActionRewardByRound`（分母缓存） | `cacheDenominator:741` | 无（派生缓存，§6.9「分红除数」） |
| 二次分配三张表 + 枚举集合 | `GroupRecipients:96-104` | `RecipientsChanged` |
| 加入态 | `ActionTarget.registerJoinState` / `clearJoinState` | `JoinStateRegistered` / `JoinStateCleared`（跨合约）+ `ServiceJoined` / `ServiceExited` |

10 个写入面全部覆盖。分母缓存（`:737-742`）是 §6.9 明确列出的派生缓存，且写入判据是**行动代币**的 `isRewardPrepared`（`:739`），不是服务代币——这条在 `:735-736` 有 `// Load-bearing:` 注释，是历史 bug 的修复点。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 全部以 `serviceTokenAddress` 或 `tokenAddress` 开头 |
| 族槽位 `action.config` / `action.participation` / `action.service` | 通过 | 见第三节各表 |
| indexed ≤ 3（§6.3） | 通过 | `ServiceRewardsDistributed` 用「根键 / `serviceActionId` / `actionTokenAddress`」三槽，`memberId` 降级 |
| 共享事件类（§4.2） | 通过 | `MemberRewardMinted` 三发射者同 schema；`burnAmount ≡ ownerBurned` 有意冗余已登记 |
| 状态写入后 emit（§3.4.3） | 通过 | 5 个自身发射点全部在写入之后 |
| 依赖序（§3.4.5） | 通过 | `ServiceRewardsDistributed.ownerDistributed` 依赖 `RecipientPaid` 的合计，故后者在先 |
| 父子序（§3.4.6） | **不通过** | `MemberRewardMinted` 与 `ServiceRewardsDistributed` 均晚于其明细 `RecipientPaid`（`GSE-EV-1`） |
| 退出四步序（§4.4） | 通过 | 服务无仓位无退款，只有第 3、4 步：`JoinStateCleared` → `ServiceExited` |
| 失败不留日志（§3.5） | 通过 | 零额回滚 `MemberActionRewardUnavailable:720-722`、`:730-732` 均早于任何 emit |
| 动态字段上限（§6.8） | 通过 | 5 条事件无变长字段（`RecipientPaid`/`RecipientsChanged` 见 `GroupRecipients` 报告） |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | 见第七节 |

## 六、发现

### GSE-EV-1（P2）结算的两条聚合事件都晚于其明细 `RecipientPaid`，且该顺序不在 §3.4.6 的例外清单内

- 证据：`_mintMemberReward` 的顺序是「写结算记录 `:744-746` → burn `:748-751` → `GroupRecipients.distribute`（内部逐笔 `RecipientPaid`，`:753-767`）→ 算余量并写 `:768-770` → 两笔转账 `:772-777` → `MemberRewardMinted:779` → `ServiceRewardsDistributed:787`」。`GroupServiceEvents.t.sol:16` 的注释直接写着「Two recipient transfers, then the paired settlement events」，说明这是已知形态。
- 问题：§3.4.6 要求「同一状态所有者、同一业务对象的生命周期事件，SHOULD 父事实先于子事实」，且 §1 规定 SHOULD 违反「除非有书面理由并在评审中记录，否则必须遵守」。允许的逆序只有 E1–E4，四条都不覆盖「聚合事件晚于其明细」。其中：
  - `ServiceRewardsDistributed.ownerDistributed` **确实依赖** `RecipientPaid` 的合计，属 §3.4.5 的依赖序，无法前移——这条应该被登记为例外而不是判为缺陷；
  - `MemberRewardMinted` 的 `mintAmount = verifierReward + ownerReward`、`burnAmount = ownerBurned` 在 `:733` 就已定稿，**完全不依赖二次分配结果**，可以前移到 `:746` 之后、burn 之前，因此它晚于明细属于无理由的倒置。
- 影响：一笔服务结算的日志形状是 `RecipientPaid × N → MemberRewardMinted → ServiceRewardsDistributed`。把 `MemberRewardMinted` 当作「成员结算完成」信号的索引器，会先收到该结算产生的付款明细、后收到结算本身，必须做乱序缓冲；而 `MemberRewardMinted` 是三个 Executor 共用的口径，只有 Service 这一发射者是倒序的——跨行动类型统一的折叠逻辑会在这里失效。
- 建议：把 `:779` 的 `MemberRewardMinted` 前移到 `:746` 之后（payload 已定稿、状态已写入），使顺序变为 `MemberRewardMinted → RecipientPaid × N → ServiceRewardsDistributed`；同时在 `06-service-executor.md` 的「成员级结清」段落书面登记 `ServiceRewardsDistributed` 晚于 `RecipientPaid` 是依赖序例外（E2 的同类形态），并补一条断言 `MemberRewardMinted` 下标小于第一条 `RecipientPaid` 的用例。

### GSE-EV-2（P3）`ownerRemaining` 是聚合余量，事件流无法按源行动拆分

- 证据：`distribute`（`GroupRecipients:168-196`）遍历 `actionIdsWithRecipients(sourceToken, groupId, round)`，对每个源行动算 `slice = ownerSlice(...)` 并二次分配，返回 `distributed = Σ 各源行动的已分配额`。`remaining = ownerReward - distributed`（`GroupServiceExecutor:768`）是**跨源行动的总余量**，事件里只有这一个数。
- 问题：owner 的自留额由两部分组成——「无配置行动的整份切片」与「有配置行动逐项取整的余数」。前者按源行动区分，后者是尘量；两者在 `ownerRemaining` 里合并成一个标量。`RecipientPaid` 只覆盖已分配部分，不覆盖任何自留部分。
- 影响：想按源行动对账「这个群 owner 在源行动 A 上拿了自己多少」的消费方无法从事件流得出——只能读 `rewardByRecipientId(..., recipientId = groupId)`（`GroupServiceExecutor:139-159`），而它是**当前态投影**、依赖当时的配置与账本，不能复现历史轮。
- 建议：在 `06-service-executor.md` 的「二次分配」段落补一句「`ownerRemaining` 是跨源行动的聚合值，逐源行动的 owner 自留额不承诺可从事件重建」，把这条列入 §6.9 的「不承诺重建」窄名单；若要可重建，需为每个源行动补一条事件，代价是每笔结算多 N 条日志，不建议。

### GSE-EV-3（P3）`ServiceActionCreated` 与 `LpActionCreated` / `GroupActionCreated` 一样不带 `round`，依赖跨合约同值

- 证据：`:428` 写 `createdRoundByActionId`，事件 `:430-436` 无 `round` 字段。
- 问题：三个 Executor 的创建事件都不带 `round`，创建轮统一由同笔 `ActionTarget.ActionRegistered.round` 承载。这本身是合理分工（`action.config` 族没有 `round` 槽），但它是 `GSE-EV-3` 想登记的点：**「行动创建轮」这个事实的唯一事件锚点不在创建者自己的事件里**，而在被调用方的上游事件里。同一条依赖在 `01-action-target.md` AT-3 已从 ActionTarget 侧提出。
- 影响：任何只订阅「某个 Executor 地址」的索引器（按 emitter 过滤）都拿不到创建轮——它必须同时订阅 `ActionTarget`。这在多 Executor 部署下是可用性问题，不是正确性问题。
- 建议：在 `action.config` 族表下补一句「本族不含 `round`，创建轮取同笔 `ActionRegistered.round`（同一 tx 内 `currentPhase()` 不变）」，让这条跨合约依赖从「读者自己发现」变成「规范写明」。

### 正面结论（不计入发现）

- `ServiceJoined` / `ServiceExited` 与 §4.4 的「空步」条款逐字对应：服务无仓位、无退款，只有「`clearJoinState` → `*Exited`」两步。
- `ServiceRewardsDistributed` 同时给出 `ownerReward` / `ownerDistributed` / `ownerRemaining` 三个数，配合 `RecipientPaid` 可完整还原 owner 侧的资金去向（除 `GSE-EV-2` 的逐源行动拆分）。
- 分母缓存的写入判据是行动代币的 `isRewardPrepared`（`:739`），并带 `// Load-bearing:` 说明（`:735-736`）——这是历史超额支付 bug 的修复点，属事件无关但影响结算正确性的关键约束。
- 结算的零额分支（`:720-722`、`:730-732`）都在任何 emit 之前回滚，不置位、不发事件。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `ServiceActionCreated` | `GroupServiceEvents.t.sol:183` | emitter 为 Executor；5 字段 |
| `ServiceJoined` | `test/GroupServiceJoin.t.sol`（整文件） | 资格、重复加入、跨轮加入 |
| `ServiceExited` | `GroupServiceEvents.t.sol:165` | 4 字段；位置晚于 `JoinStateCleared` |
| `MemberRewardMinted` | `:142` | 6 字段；`mintAmount` 与返回值一致 |
| `MemberRewardMinted` | `:34` | 下标早于 `ServiceRewardsDistributed`（未断言早于 `RecipientPaid`） |
| `ServiceRewardsDistributed` | `:9` | 10 字段；`ownerReward` / `ownerBurned` / `ownerDistributed` / `ownerRemaining` 四个数全量 |
| `RecipientPaid` | `:9` / `:101-120` | 逐收款人一条，字段全量区分 |
| 全部 | `:61-68` | `Σ 转账 + 销毁 == serviceReward`，executor 余额归零 |

缺两条：(a) `MemberRewardMinted` 与 `RecipientPaid` 的先后（`GSE-EV-1`，当前只断言了 `MemberRewardMinted < ServiceRewardsDistributed`）；(b) `ownerRemaining` 在有配置/无配置源行动混合时的取值（`GSE-EV-2`）。
