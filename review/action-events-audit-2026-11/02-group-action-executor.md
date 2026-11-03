# GroupActionExecutor 事件赋值与发射审查

> 对象 `action/src/GroupActionExecutor.sol`（750 行，`contract`，含 3 个 `public` 业务库的宿主）
> 声明 `action/src/interfaces/IActionExecutor.sol`（`IActionExecutorEvents.MemberRewardMinted`，L6-15）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/05-group-action-executor.md`、`07-minting.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| 本合约自身声明并发射的事件 | 1（`MemberRewardMinted`） |
| 经 `delegatecall` 在本地址发射的事件 | 17（`GroupActionManager` 4 + `GroupActionJoin` 6 + `GroupActionVerify` 7） |
| 本合约地址发出的事件种类合计 | 18 |
| 本合约地址的发射点合计 | 21（自身 1 + 库委托 20：Manager 4、Join 9、Verify 7） |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 2 |
| 放行 | 可放行；2 项 P3 均为「同一笔内多事件相对序」的记录缺口 |

一句话：本合约自身只发一条事件，但它是 18 条事件的**运行时发射者**——所有业务库都以 `delegatecall` 在本地址执行，`emitter` 恒为 Executor（`testGroupActionJoinedEmitsFromTheExecutor`、`testApplicationVoteRecordedEmitsFromTheExecutor` 各断言一次）。因此本报告的重点不是逐字段（各库报告已逐字段展开），而是**一笔交易内的事件序列**。

## 二、事件归属与委托结构

| 库 | 声明接口 | 事件 | 发射点（库内行） |
| --- | --- | --- | --- |
| `GroupActionManager` | `IGroupActionManagerEvents` / `IGroupActionExecutorEvents` | `GroupActionCreated`、`GroupActivated`、`GroupDeactivated`、`GroupConfigChanged` | 438 / 493 / 212 / 459 |
| `GroupActionJoin` | `IGroupActionJoinEvents` | `GroupActionJoined`、`GroupActionWithdrawn`、`GroupActionExited`、`ProviderQuotaAdded`、`ProviderQuotaRemoved`、`ProviderQuotaRestored` | 96 / 141,195,406 / 808 / 351 / 417,839 / 234 |
| `GroupActionVerify` | `IGroupActionVerifyEvents` | `OriginScoresSubmitted`、`VerifierApplicationSubmitted`、`VerifierApplicationCancelled`、`VerifierStakeDeposited`、`VerifierStakeRefunded`、`VerifierLocked`、`ApplicationVoteRecorded` | 760 / 784 / 207 / 845 / 198 / 740 / 802 |
| 本合约 | `IActionExecutorEvents` | `MemberRewardMinted` | 741 |

§4.1 的三条库 emit 条件逐条成立：库被状态所有者 `delegatecall`（四个库的写函数都是 `external`，Solidity 对 `public`/`external` 库函数生成 `delegatecall`）；事件声明在状态所有者的 interface（Executor 继承 `IGroupActionManager` / `IGroupActionJoin` / `IGroupActionVerify`，`GroupActionCreated` 声明在 `IGroupActionExecutorEvents`）；库不被语义不同的状态所有者共享（`GroupActionVerify` 的 `internal` 函数被 `GroupServiceExecutor` 内联复用，但那些函数不发事件——`currentVerifyRound` 是 `internal view`，编译期内联，不产生跨合约调用）。

## 三、`MemberRewardMinted` 逐字段

```
event MemberRewardMinted(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed memberId,
    uint256 round,
    uint256 mintAmount,
    uint256 burnAmount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:742` | 根键 |
| `actionId` | 入参 `:743` | 父对象 id |
| `memberId` | 入参 `:744` | 结算主体，indexed |
| `round` | 入参 `:745` | 被结算轮，非 indexed（3 个槽已满） |
| `mintAmount` | `Math.mulDiv(proposalReward, memberFinalScore, totalFinal)` `:725`，或 `mintActionReward` 返回值重算后同值 | 转给 `msg.sender` 的金额；`mintAmount != 0` 时才转账 `:737-739` |
| `burnAmount` | 声明于 `:705`，**全函数无赋值**，恒为 `0` | GroupAction 无销毁路径（ADR-004），共享事件的该字段在本发射者上结构性为 0 |

前置写入：`memberMinted:733`、`memberMintedReward:734`、`memberBurnedReward:735`；随后转账 `:737-739`；最后 emit `:741`。顺序是「状态 → 资金 → 事件」，符合 §3.4.3 与 §6.5（语义事件自带金额，不依赖 ERC-20 `Transfer` 回连）。

`mintAmount == 0 && burnAmount == 0` 时回滚 `MemberActionRewardUnavailable:729-731`，不置位、不发事件——与 `07-minting.md` 的零额拒绝同口径。由于 `burnAmount` 恒 0，本发射者的零额条件退化为 `mintAmount == 0`。

### 与行动级事件的关系

`_mintMemberReward` 在 `:721-724` 可能调用 `ActionTarget.mintActionReward`，后者在 `ActionTarget:277` 发 `ActionRewardMinted`。因此成员结算的完整序列是：

```
ActionRewardMinted(tokenAddress, actionId, round, amount)   ← ActionTarget 发
  → MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, 0)   ← 本合约发
  → ERC-20 Transfer(mintAmount)                               ← 已在上一条之前
```

`ActionRewardMinted` 一定早于 `MemberRewardMinted`：前者在 `:723` 的调用内发出，后者在 `:741`。这是父子序的正确方向（行动级整笔 → 成员级切片）。但注意 `:723` 早于 `:733` 的状态写入，即「行动级铸造事件」先于「成员级结算状态」——这不违反 §3.4.3（`ActionRewardMinted` 的 payload 只依赖 Mint 的返回值），也不构成依赖序问题。

## 四、逐入口事件序列

事件序列按「状态写入 → 资金 → 事件」拆开记录；括号内为库内行号。

### 4.1 创建（`onProposalCreated` → `GroupActionManager.onProposalCreated`）

```
[ActionTarget] ActionRegistered                        (ActionTarget:457)
→ [本地址] GroupActionCreated                          (Manager:438)
```

两事件同笔，中间无其他日志。`ActionRegistered.round` 与本库 `createdRoundByActionId`（Manager:123）同值，见 `01-action-target.md` AT-3。

### 4.2 群生命周期

| 入口 | 序列 |
| --- | --- |
| `activateGroup` | 写 `groupState`/描述快照/六组索引/三处质押聚合（Manager:151-164）→ `safeTransferFrom` 质押（:166-168）→ `GroupActivated`（:493） |
| `deactivateGroup` | 写 `groupState`/索引/质押聚合（:193-206）→ `safeTransfer` 退质押（:208-210）→ `GroupDeactivated`（:212） |
| `setGroupConfig` | 读旧配置（:236）→ 写 `group.config` 与描述快照（:239-240）→ `GroupConfigChanged`（:459） |

三条都是「状态 → 资金 → 事件」，`setGroupConfig` 无资金步。`GroupActivated` / `GroupDeactivated` 互为可逆迁移，`GroupConfigChanged` 携带新组→旧组全量（§6.7）。

### 4.3 参与

| 入口 | 序列 |
| --- | --- |
| `join` | 归属索引（Join:84）→ `JoinStateRegistered`（ActionTarget:136）→ 验证值（Join:89）→ 金额账本（Join:90）→ `safeTransferFrom`（Join:92-94，仅 `providerId == 0`）→ `GroupActionJoined`（Join:96） |
| `withdraw` | 减自有金额（Join:137）→ `safeTransfer`（Join:139）→ `GroupActionWithdrawn`（Join:141）→ 归零时 `JoinStateCleared`（ActionTarget:162）→ `GroupActionExited`（Join:808） |
| `exit` | 减自有金额（Join:193）→ `safeTransfer`（Join:194）→ `GroupActionWithdrawn`（Join:195）→ 逐 Provider `ProviderQuotaRestored`（Join:234）→ `JoinStateCleared`（ActionTarget:162）→ `GroupActionExited`（Join:808） |
| `addProviderQuota` | 逐成员写额度（Join:346-348）→ 逐成员 `ProviderQuotaAdded`（Join:351）→ 汇总 `safeTransferFrom`（Join:362） |
| `withdrawProviderQuota` | 写额度（Join:832-835）→ `safeTransfer`（Join:837）→ `ProviderQuotaRemoved`（Join:839） |
| `removeProviderQuota` | 逐成员 `_removeQuota`（Join:403）→ 逐成员 `GroupActionWithdrawn`（Join:406）→ `ProviderQuotaRemoved`（Join:417）→ 归零时 `JoinStateCleared`（ActionTarget:162）→ `GroupActionExited`（Join:808）→ 汇总 `safeTransfer`（Join:389） |

`withdraw` / `exit` 的序列逐字对应 §4.4 四步；`removeProviderQuota` 的转账落在最后（见 `GroupActionJoin` 报告 GAJ-EV-2）。`addProviderQuota` 的转账落在 N 条事件之后（见 GAJ-EV-3）。

### 4.4 验证

| 入口 | 序列 |
| --- | --- |
| `submitVerifierApplication` | 写申请三处（Verify:161-163）→ `safeTransferFrom` 押金（Verify:844）→ `VerifierStakeDeposited`（Verify:845）→ `VerifierApplicationSubmitted`（Verify:784） |
| `cancelVerifierApplication` | 清申请四处（Verify:189-192）→ `safeTransfer` 退押金（Verify:197）→ `VerifierStakeRefunded`（Verify:198）→ `VerifierApplicationCancelled`（Verify:207） |
| `onProposalVoted`（有业务项） | 写票数/名册/排名（Verify:400-403）→ `ApplicationVoteRecorded`（Verify:802） |
| `submitOriginScores` | 写 `lockedVerifierId`（Verify:739）→ `VerifierLocked`（Verify:740）→ 写分数四组（Verify:438-441）→ `OriginScoresSubmitted`（Verify:760） |

### 4.5 结算

```
[ActionTarget] ActionRewardMinted          (ActionTarget:277)   ← 仅当本轮未铸造
→ 写 memberMinted 三处                      (GAE:733-735)
→ ERC-20 Transfer(mintAmount)              (GAE:737-739)
→ MemberRewardMinted                       (GAE:741)
```

批量入口 `mintMemberRewards` 逐元素执行同一段，N 条 `MemberRewardMinted` 按入参顺序排列（§3.4.4「批量入口有入参顺序时按入参顺序」）。`ActionRewardMinted` 只在第一个元素触发（其后 `actionMinted == true` 走 `:721` 的短路）。

## 五、状态写入与事件覆盖对照（本合约自身）

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_layout.memberMinted` | `:733` | `MemberRewardMinted`（`round` + `memberId` 定位） |
| `_layout.memberMintedReward` | `:734` | `MemberRewardMinted.mintAmount` |
| `_layout.memberBurnedReward` | `:735` | `MemberRewardMinted.burnAmount`（恒 0） |
| 三个 `immutable` + `_layout.SPLITS` | 构造函数 `:31-34` | 无（§3.2 豁免，`21_check.sh` 复核） |

## 六、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `MemberRewardMinted` 以 `tokenAddress` 开头 |
| 族槽位 `action.participation` | 通过 | 根键 → `actionId` → `memberId` → `round` → 数值 |
| indexed ≤ 3（§6.3） | 通过 | 3 个；`round` 主动降级 |
| 共享事件类（§4.2） | 通过 | `MemberRewardMinted` 三个发射者同 schema；`burnAmount` 在本发射者恒 0、在 `LpExecutor` / `GroupServiceExecutor` 可非零 |
| 状态写入后 emit（§3.4.3） | 通过 | `:733-735` 先于 `:741` |
| 依赖序（§3.4.5） | 通过 | `ActionRewardMinted` → `MemberRewardMinted` |
| 批量逐条（§3.4.1） | 通过 | `mintMemberRewards` 循环内逐条 emit |
| 失败不留日志（§3.5） | 通过 | 零额回滚、`RewardAlreadyMinted` 均在 emit 之前 |
| 动态字段上限（§6.8） | 不适用 | 无变长字段 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | `GroupActionEvents.t.sol:713` 断言 6 字段 |

## 七、发现

### GAE-EV-1（P3）`MemberRewardMinted.burnAmount` 在本发射者上恒为 0，事件契约与实现存在结构性空字段

- 证据：`_mintMemberReward`（`:700-749`）中 `burnAmount` 只在签名 `:705` 声明，函数体内无任何赋值；`:729` 与 `:741` 都以它参与判定与 payload。
- 问题：`MemberRewardMinted` 是 §4.2 的共享事件类，三个发射者同 schema。GroupAction 侧无销毁路径（ADR-004「全链路无销毁路径」），所以该字段永远为 0。这在 schema 上是必要的（共享类不能删字段），但**在 GroupAction 这一发射者上它是常量**，消费方不能据此判断「本发射者是否支持销毁」。
- 影响：`GroupActionEvents.t.sol:713` 断言 `burnAmount == 0`；若将来 GroupAction 引入销毁，同一字段会从常量变为变量，事件契约不变但折叠规则要改，属冻结后不可逆的语义扩张。
- 建议：在 `05-group-action-executor.md` 的「行动激励」段落显式写一句「GroupAction 的 `MemberRewardMinted.burnAmount` 恒为 0，销毁只存在于 LP 与 Service」；这与 §4.2 已登记的「`burnAmount` 与 `ownerBurned` 有意冗余」是同一条记录习惯。

### GAE-EV-2（P3）`mintMemberRewards` 批量结算的事件序列未规定「行动级铸造只出现一次」的锚点

- 证据：`:78-80` 循环调用 `_mintMemberReward`；`:721-724` 的 `if (!actionMinted && proposalReward != 0)` 使 `ActionRewardMinted` 只在第一个元素发出。
- 问题：批量入口的日志是 `ActionRewardMinted → MemberRewardMinted × k`，但**没有任何字段表明这批成员属于同一次批量调用**（§3.4.2 允许携带 batch id，本入口没有）。消费方只能按「同一 tx」归组。
- 影响：一次批量结算跨越多轮时（`rounds[]` 每元素不同），`ActionRewardMinted` 可能出现多次（每个不同的 `(actionId, round)` 各一次），与 `MemberRewardMinted` 交错，形成 `A → M M → A → M` 的形状。§3.4.4 要求顺序确定并有测试，当前 `GroupActionEvents.t.sol` 没有跨轮批量用例。
- 建议：补一条「`mintMemberRewards` 传两个不同 round 的 `(actionId, round)`」的顺序用例，断言两条 `ActionRewardMinted` 各自早于对应 `MemberRewardMinted`；或在 `07-minting.md` 的批量段落写明该交错形状。

### 正面结论（不计入发现）

- 18 条事件的运行时 `emitter` 全部是本合约地址；库委托不改变发射者，§4.1 成立。两条专门用例（`GroupActionEvents.t.sol:203`、`:535`）各断言一次 `logs[i].emitter == address(executor)`。
- `_mintMemberReward` 的三处状态写入先于转账、转账先于事件，三个 Executor 同型（`LpExecutor:511-524`、`GroupServiceExecutor:744-779`）。
- `MemberRewardMinted` 与 `ActionRewardMinted` 的金额关系有测试：`GroupActionEvents.t.sol:713` 断言 `mintAmount == Math.mulDiv(proposalReward, finalScore, totalFinal)`，`ActionTargetEvents.t.sol:65` 断言行动级 `amount` 与查询同源。

## 八、测试断言对照

| 事件 | 用例 |
| --- | --- |
| `MemberRewardMinted` | `GroupActionEvents.t.sol:713`（6 字段 + 金额公式） |
| `GroupActionCreated` | `:23`、`:54`（schema 全量）、`:758`（16 项边界） |
| `GroupActionJoined` | `:75`、`:145`、`:171`（空验证值语义）、`:203`（emitter）、`:840`（16 项边界）、`:871`（17 项拒绝） |
| `GroupActionWithdrawn` / `GroupActionExited` | `:222`、`:260`、`:344`（E4 顺序） |
| `ProviderQuotaAdded` / `Removed` / `Restored` | `:75`、`:260`、`:306` |
| `GroupActivated` / `Deactivated` / `ConfigChanged` | `:412`、`:374`（可逆）、`:894`（1024 字节描述） |
| `VerifierApplicationSubmitted` / `Cancelled` / `StakeDeposited` / `StakeRefunded` / `Locked` | `:472`、`:608`、`:631`、`:655`、`:673` |
| `OriginScoresSubmitted` | `:472`、`:785`（累计值 = fold） |
| `ApplicationVoteRecorded` | `:535`（emitter）、`:552`（按轮隔离）、`:571` |
