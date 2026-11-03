# GroupActionVerify（库）事件赋值与发射审查

> 对象 `action/src/GroupActionVerify.sol`（853 行，`library`，经 `delegatecall` 由 `GroupActionExecutor` 调用）
> 声明 `action/src/interfaces/IGroupActionVerify.sol`（`IGroupActionVerifyEvents`，L12-73）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/05-group-action-executor.md`（验证者申请与排名、验证段落）

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 7 |
| 发射点 | 7（一对一） |
| 状态写入面（受事件覆盖） | 16 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 4 |
| 放行 | 可放行；4 项 P3 全部是「折叠路径依赖内部实现」与「indexed 布局不对称」，无资金风险 |

本库的 7 条事件覆盖了验证者席位的完整生命周期（申请 → 押金 → 计票 → 锁定 → 计分）与撤销路径。事件设计上最值得注意的是**位置化验证**：`OriginScoresSubmitted.scores[]` 不带 `memberId`，成员由「该轮成员集合的第 `startIndex + i` 个槽位」决定。这是 gas 优化下的有意取舍，但它把「成员集合的存储顺序」变成了一条对外契约，而这层契约只能靠重实现 `RoundHistoryUint256Set` 才能复现（`GAV-EV-1`）。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `VerifierApplicationSubmitted` | `tokenAddress`, `actionId`, `verifierId` | `_emitVerifierApplicationSubmitted:784`（由 `:170` 调用） | 申请四处 `:161-163` | 无（本笔结束） |
| `VerifierStakeDeposited` | 同上 | `_depositVerifierStake:845`（由 `:167` 调用） | `safeTransferFrom:844` | 返回 `submitVerifierApplication`，随后发 `VerifierApplicationSubmitted` |
| `VerifierApplicationCancelled` | 同上 | `cancelVerifierApplication:207` | 清申请四处 `:189-192` | 无 |
| `VerifierStakeRefunded` | 同上 | `cancelVerifierApplication:198` | `safeTransfer:197` | 同笔随后发 `VerifierApplicationCancelled` |
| `ApplicationVoteRecorded` | `tokenAddress`, `actionId`, `applicationId` | `_emitApplicationVoteRecorded:802`（由 `onProposalVoted:405` 调用） | 票数 `:400`、名册 `:401`、投票人金额 `:402`、排名 `:403` | 无 |
| `VerifierLocked` | `tokenAddress`, `actionId`, `verifierId` | `_submitOriginScores:740` | `lockedVerifierId:739` | 写分数四组 `:748`（`_scoreBatch`） |
| `OriginScoresSubmitted` | `tokenAddress`, `actionId`, `groupId` | `_submitOriginScores:760` | 分数四组 `:438-441`、群验证标记 `:458-461` | 无 |

族归属：全部 7 条 → `action.verification`。

## 三、逐事件赋值链

### 3.1 `VerifierApplicationSubmitted`

```
event VerifierApplicationSubmitted(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed verifierId,
    uint256 round,
    uint256 applicationId,
    uint256 previousApplicationId,
    bool hasPreviousApplication,
    string description
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `verifierId` | 入参 `:785-787` | 根键 → 父 id → actor |
| `round` | `_checkApplicationSubmission` 返回 `IPhase.currentPhase()` `:822` | **当前投票轮**（= 提交轮）；同时是 `applicationIdHistory` 的键（`:579`） |
| `applicationId` | `_replaceApplication` 返回 `++applicationIdCount` `:576` | 每 `(token, action)` 单调递增、不复用；修改申请 = 新 id |
| `previousApplicationId` | `self.currentApplicationId[...]` `:160`（在 `_replaceApplication` 覆写之前读） | `0` 表示首次申请 |
| `hasPreviousApplication` | `previousApplicationId != 0` `:791` | §6.7 要求的显式布尔，与 id 恒等可推但不得省略（见 `GAV-EV-2`） |
| `description` | calldata `:792` | ≤1024 字节（`:826-831`） |

前置判定顺序：`onlyMemberOwner:157` → `validGovVotes != 0` `:823-825` → 描述长度 `:826-831` → `createdRound != 0` `:832-834`。四道全部早于 `_replaceApplication` 的写入，失败零日志。

押金：`previousApplicationId == 0` 时才划转（`:165`），划转在事件之前（`VerifierStakeDeposited:845` → `VerifierApplicationSubmitted:784`）。

### 3.2 `VerifierStakeDeposited` / `VerifierStakeRefunded`

```
event VerifierStakeDeposited(address indexed tokenAddress, uint256 indexed actionId,
                             uint256 indexed verifierId, uint256 round, uint256 amount);
event VerifierStakeRefunded (address indexed tokenAddress, uint256 indexed actionId,
                             uint256 indexed verifierId, uint256 round, uint256 amount);
```

| 字段 | 存入（`:845`） | 退还（`:198`） |
| --- | --- | --- |
| `round` | `submitVerifierApplication` 的提交轮 `:167` | `IPhase.currentPhase()` `:183`（撤销轮） |
| `amount` | `verifierStakeAmountByActionId` `:165` | `verifierStakeAmountByActionId` `:195` |
| 资金步 | `safeTransferFrom(msg.sender, this, amount)` `:844` → emit | `safeTransfer(ownerOf(verifierId), amount)` `:197` → emit |

两条都是「转账后立即 emit」，符合 §4.4 第 2 步的方向。`amount` 恒等于行动级配置 `verifierStakeAmount`，只写一次，因此存入额与退还额必然相等——「已质押 ≡ 持有当前申请」这条不变式由 `verifierStake()`（`:216-226`）在读取侧再确认一次。

### 3.3 `VerifierApplicationCancelled`

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `verifierId` | 入参 `:208-210` | 同 3.1 |
| `round` | `IPhase.currentPhase()` `:183` | 撤销轮 |
| `applicationId` | `self.currentApplicationId[...]` `:184` | 被撤销的申请 id（`:185-187` 保证非 0） |

顺序：清四处状态（`:189-192`）→ 退押金并 emit `VerifierStakeRefunded`（`:195-205`）→ emit 本事件（`:207`）。金额事实先于生命周期事实，与 §4.4 的「`*Withdrawn` 早于 `*Exited`」同型。

撤销**不清 `lockedVerifierId`**，因此已锁定的验证者撤销后仍可继续提交分数（`GAV-EV-4`）。

### 3.4 `ApplicationVoteRecorded`

```
event ApplicationVoteRecorded(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 voterId,
    uint256 round,
    uint256 indexed applicationId,
    uint256 verifierId,
    uint256 voteAmountAdded,
    uint256 voteAmountTotal
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` | 入参 `:803-804` | 根键 → 父 id |
| `voterId` | 入参（来自 `Vote`）`:805` | actor，**非 indexed**（3 槽给了 `applicationId`，见 `GAV-EV-3`） |
| `round` | 入参（`Vote.currentRound()`）`:806` | 投票轮 |
| `applicationId` | `self.currentApplicationId[...]` `:392` | 主对象 id，indexed；`:393-395` 保证非 0 |
| `verifierId` | `abi.decode(targetData[1], (uint256))` `:391` | 被投的验证者 |
| `voteAmountAdded` | 入参 `voteAmount` `:414` | 本次增量 |
| `voteAmountTotal` | `voteAmountByApplicationId` 后置值 `:800-801` | 该申请在该轮的累计票（后置锚点） |

`voteAmount == 0` 时 `:397-399` 提前返回，不记账不发事件；`targetData` 只有保留项时 `:381-383` 也提前返回（本次投票未指定验证者）。两种「无事实」情形都零日志。

`voteAmountTotal` 是 §3.1 要求的累计值，`testApplicationVoteRecordedSeparatesRounds`（`:552`）按轮隔离断言，`testApplicationVoteRecordedEvent`（`:571`）断言累加。

### 3.5 `VerifierLocked`

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `verifierId` | `submission` 结构体 `:741-743` | 根键 → 父 id → actor |
| `round` | `currentVerifyRound(protocol.phaseAddress)` `:701`（= `phase - 2`，`:521-527`） | 验证轮 |

只在 `lockedVerifier == 0` 时发（`:738-746`），因此每 `(token, action, round)` 至多一条，是该轮「谁在验证」的唯一权威事实。位置在写 `lockedVerifierId:739` 之后、写分数 `:748` 之前——锁定事实先于计分事实，父子序正确。

### 3.6 `OriginScoresSubmitted`

```
event OriginScoresSubmitted(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 indexed groupId,
    uint256 round,
    uint256 verifierId,
    uint256 startIndex,
    uint256 totalFinalScore,
    uint256 verifiedGroupCount,
    bool roundVerified,
    bool groupVerified,
    uint256[] scores
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `groupId` | `submission` 结构体 `:761-763` | 根键 → 父 id → 本批次的对象（群） |
| `round` | `currentVerifyRound(...)` `:701` | 验证轮；`_checkOpenVerifier` 与成员集合都按此轮读取 |
| `verifierId` | `submission.verifierId` `:765` | 本批次的验证者（可能已撤销申请，见 `GAV-EV-4`） |
| `startIndex` | `submission.startIndex` `:766` | 已过 `startIndex != verifiedCount` 回滚 `StartIndexMismatch:722-724` |
| `totalFinalScore` | `self.totalFinalScore[...]` 后置值 `:767` | 该轮**跨群**累计最终分（§3.1 累计值） |
| `verifiedGroupCount` | `self.verifiedGroupCountByRound[...]` 后置值 `:768` | 该轮已完成的群数 |
| `roundVerified` | `self.roundVerified[...]` 后置值 `:769` | 该轮全部群完成 |
| `groupVerified` | `_scoreBatch` 返回值 `:748`（= `_markGroupVerified` 的返回值 `:442`） | 本批次是否推满该群游标 |
| `scores` | calldata `:771` | ≤`MAX_VERIFICATION_BATCH = 100`（`:695-699`），每项 ≤`MAX_ORIGIN_SCORE = 100`（`:730-736`） |

三个后置累计量 + 一个布尔，构成本轮的完整进度锚点：消费方可以由 `verifiedGroupCount` 与 `groupIdsByRound(round).totalCount` 独立复算 `roundVerified`，也可以由 `startIndex + scores.length` 复算该群的 `verifiedMemberCount`。`testOriginScoresSubmittedTotalFinalScoreMatchesFold`（`:785`）断言 `totalFinalScore` 等于逐成员折叠值。

`groupVerified` 与 `roundVerified` 的关系不是恒等：一个批次可以推满群（`groupVerified = true`）而该轮还有其他群未完成（`roundVerified = false`）。两者都由 `_markGroupVerified`（`:445-463`）在同一处状态写入后产生，不会自相矛盾。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `applicationIdCount` | `++:576` | `VerifierApplicationSubmitted.applicationId` |
| `currentApplicationId` | `:577` / `:191` | `VerifierApplicationSubmitted` / `VerifierApplicationCancelled` |
| `activeApplicationIds` | `add:578` / `remove:572,189` | 同上（派生名单） |
| `applicationIdHistory` | `record:579` / `record(0):192` | `VerifierApplicationSubmitted.round` / `VerifierApplicationCancelled.round` |
| `applicationVerifierId` / `applicationDescription` | `:162-163` | `VerifierApplicationSubmitted.verifierId` / `.description` |
| `rankedApplicationIds` | `_upsertRank:582-622` / `_removeFromRank:573,190` | 由 `ApplicationVoteRecorded` 折叠（派生排名，§6.9「验证排名」） |
| `voteAmountByApplicationId` | `+=:400` | `ApplicationVoteRecorded.voteAmountTotal` |
| `voterIdsByApplicationId` | `add:401` | `ApplicationVoteRecorded.voterId`（名册，append-only） |
| `voteAmountByApplicationIdByVoterId` | `+=:402` | `ApplicationVoteRecorded.voteAmountAdded` |
| `lockedVerifierId` | `:739` | `VerifierLocked.verifierId` |
| `finalScoreByGroupId` / `totalFinalScore` | `:438-439` | `OriginScoresSubmitted.totalFinalScore`（跨群累计） |
| `verifiedMemberCountByGroupId` | `:441` | 由 `startIndex + scores.length` 折叠（`OriginScoresSubmitted`） |
| `verifiedGroupCountByRound` | `++:458` | `OriginScoresSubmitted.verifiedGroupCount` |
| `roundVerified` | `:460` | `OriginScoresSubmitted.roundVerified` |
| `originScoreDeductionByMemberId` | `:475` | 由 `scores[]` + 位置化成员集合折叠（见 `GAV-EV-1`） |
| 押金（无独立状态，靠「持有当前申请」隐含） | — | `VerifierStakeDeposited` / `VerifierStakeRefunded` |

16 个写入面全部覆盖。押金没有独立账本这一点值得单独说明：`verifierStake()`（`:216-226`）的实现是「有当前申请 ⇒ 返回配置额」，因此押金余额不是一个可被写入的变量，而是一个由 `currentApplicationId != 0` 派生的值——「已质押 ≡ 持有当前申请」这条等价关系是承重的（`:194` 有 `// Load-bearing:` 注释）。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 7 个事件均以 `tokenAddress` 开头 |
| 族槽位 `action.verification` | 通过 | 根键 → `actionId` → 主体 id → `round` → `applicationId`/`verifierId` → 次级 id → 数值/布尔 → 文本/数组 |
| indexed ≤ 3（§6.3） | 部分通过 | 6 条为「根键/`actionId`/主体 id」；`ApplicationVoteRecorded` 为「根键/`actionId`/`applicationId`」，actor 降级（`GAV-EV-3`） |
| 显式布尔不得省略（§6.7） | 通过（待登记） | `hasPreviousApplication` 存在，但恒等对清单不可核对（`GAV-EV-2`） |
| 累计值每改变点携带（§3.1） | 通过 | `voteAmountTotal`、`totalFinalScore`、`verifiedGroupCount` 均为后置值 |
| 状态写入后 emit（§3.4.3） | 通过 | 7 个发射点全部在写入之后 |
| 依赖序（§3.4.5） | 通过 | `VerifierLocked` → `OriginScoresSubmitted`；`VerifierStakeDeposited` → `VerifierApplicationSubmitted`；`VerifierStakeRefunded` → `VerifierApplicationCancelled` |
| 批量逐条（§3.4.1） | 通过 | 一个批次一条 `OriginScoresSubmitted`，`scores[]` 是同一事实的数组载荷（不是 N 条事实的汇总） |
| 失败不留日志（§3.5） | 通过 | 全部校验早于写入；`_scoreBatch` 无回滚路径 |
| 动态字段上限（§6.8） | 通过 | `scores` ≤100；`description` ≤1024 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | 见第七节 |

## 六、发现

### GAV-EV-1（P3）`scores[]` 与 `memberId` 的绑定只能靠重放 `RoundHistoryUint256Set` 的 swap-and-pop 顺序

- 证据：`_scoreBatch`（`:429-437`）用 `_memberIds(self, token, action, round, groupId, verifiedCount, originScores.length)` 取出连续一段成员 id，再按下标与 `originScores` 配对（`:434`）。`_memberIds`（`:508-519`）调 `valuesByRound(round, offset, limit, false)`，其页内顺序由 `libs/src/RoundHistoryUint256Set.sol` 的槽位数组决定，删除是 swap-and-pop（`:31-46`）。事件只带 `scores` 与 `startIndex`。
- 问题：`originScoreDeductionByMemberId`（每成员 `100 − 原始分`）是「已验证成员 → 分数」的唯一链上存储，但 §6.9 的派生缓存清单里没有它，也没有「按轮成员集合顺序」这一推导输入。要折叠出同一映射，消费方必须（a）按 `GroupActionJoined` / `GroupActionWithdrawn` / `GroupActionExited` 重放成员集合的 swap-and-pop 槽位搬移，（b）叠加 RoundHistory 的「同轮只保留最后一次写入、空缺轮继承」语义，（c）再按 `startIndex + i` 对齐。三步任一走偏，分数会静默挂到错误的成员上。
- 影响：§3.3 的折叠等式在「总分」层面成立（`totalFinalScore` 有后置锚点），在「成员 → 分数」层面需要重实现库。第三方索引器实际上只能读 `finalScore()` / `originScore()` 的 view 来补，而这些 view 是**当前态**、不是历史态——历史轮的成员分数无法从事件流独立复现。
- 建议：在 §6.9 的派生缓存清单里登记 `originScoreDeductionByMemberId`，并注明推导输入是「`OriginScoresSubmitted.scores` + 该轮成员集合的槽位顺序（须按 `RoundHistoryUint256Set` 语义重放）」；`05-group-action-executor.md` 的「存储记扣分而非原始分」段落已经描述了位置化推导，但那段是给实现者看的，不是给消费方看的。

### GAV-EV-2（P3）`hasPreviousApplication` 属 §6.7 要求登记的恒等派生布尔，登记清单在仓库内不可得

- 证据：`:791` 直接以 `previousApplicationId != 0` 填充该字段，与 id 恒等可推。
- 问题：§6.7 明确「此类派生布尔属有意冗余，**须在 §8.1 恒等对清单登记**」，§8.1 第 1 条把清单位置指向 `.scratch/events-spec/03-migration-status.md`。该文件不在 `action` 仓，也不在 `matt-gov` 仓（`find` 零命中），因此无法核对本字段是否已登记。
- 影响：不是字段错误（字段本身符合 §6.7 的「不得省略」），而是**审计链断裂**：后续若有人以「与 id 恒等可推」为由删掉该字段，评审无法用清单反驳。
- 建议：把恒等对清单从 `.scratch` 迁到 `docs/event-standards.md` §7 的对象表旁边（§8.1 已声明「迁移冻结后该清单并入本文 §7」），至少先在本仓的 `script/events/` 下留一份快照；登记项应包含 `hasPreviousApplication ≡ previousApplicationId != 0`。

### GAV-EV-3（P3）`ApplicationVoteRecorded` 的 actor 未 indexed，与同族其余 6 条不对称

- 证据：`IGroupActionVerify.sol:63-72` 的 indexed 是 `tokenAddress`、`actionId`、`applicationId`；`voterId` 在 data 里。而同族 `VerifierApplicationSubmitted` / `VerifierApplicationCancelled` / `VerifierStakeDeposited` / `VerifierStakeRefunded` / `VerifierLocked` 的第三个 indexed 槽都给 `verifierId`（actor）。
- 问题：§6.3 的分配优先级是「根键 → 主对象 id 链 → actor」，`applicationId` 是主对象，因此这里把第三个槽给它**符合规则**；但 §6.3 同时要求「同组事件必须在迁移中对齐」，本族的 6:1 不对称没有书面理由。
- 影响：`voterId` 是投票人身份，钱包按 id 订阅「我投了哪些验证者票」时无法用 topic 过滤，只能拉全量再按 data 解包；而同一钱包按 `verifierId` 订阅「谁投了我」是可行的（`ApplicationVoteRecorded.verifierId` 同样在 data 里，也不可行）。两个方向都不可索引。
- 建议：在 §6.1 的 `action.verification` 族行下补一句「`ApplicationVoteRecorded` 的第三槽给主对象 `applicationId`，actor `voterId` 按 §6.3 降级为非 indexed」，把这条不对称从「看起来像疏漏」变成「已登记的选择」；若要可过滤，需牺牲 `applicationId` 的 indexed 或拆事件。

### GAV-EV-4（P3）`OriginScoresSubmitted.verifierId` 可能与已撤销的申请并存，折叠「该轮验证者」必须用 `VerifierLocked`

- 证据：`cancelVerifierApplication`（`:176-214`）清 `currentApplicationId` / `applicationIdHistory` / 排名，但**不清 `lockedVerifierId`**；`_submitOriginScores`（`:704-713`）在 `lockedVerifier == submission.verifierId` 时跳过 `_checkOpenVerifier`，因此已撤销申请的验证者仍可继续提交本轮的分数。
- 问题：事件流里会同时出现 `VerifierApplicationCancelled(round = R')` 与 `OriginScoresSubmitted(round = R, verifierId = 同一人)`，且 `R` 可能等于 `R'`（同轮撤销后再提交，因为 `lockedVerifierId` 仍在）。`05-group-action-executor.md` 明确这是有意的（「验证资格由当轮的排名决定…与是否仍持有申请无关」「已锁定即可继续提交」），但事件层面没有任何字段表达「该验证者已撤销申请但仍在验证」。
- 影响：以「当前有效申请」为口径折叠「第 R 轮验证者」的消费方会得出「该轮无人验证」的错误结论；`OriginScoresSubmitted` 与 `VerifierLocked` 两个口径不一致时没有任何链上信号可以裁决。
- 建议：把「折叠第 R 轮验证者以 `VerifierLocked` 为唯一权威」写进 `05-group-action-executor.md` 的验证段落（当前只写了「首个有效批次永久锁定验证者」这一句，没有说它是唯一权威来源）；或让 `OriginScoresSubmitted` 带 `verifierApplicationActive: bool`（成本较高，不推荐）。

### 正面结论（不计入发现）

- 7 条事件的「资金 → 金额事件 → 状态事件」方向一致：`VerifierStakeDeposited` 在转账后（`:844` → `:845`），`VerifierStakeRefunded` 在转账后（`:197` → `:198`）。
- `VerifierLocked` 每轮至多一条，`OriginScoresSubmitted` 每次提交一条，两者由 `lockedVerifierId` 的状态位串起来，顺序在代码里固定（`:739` → `:740` → `:748` → `:760`）。
- 三个后置累计量（`totalFinalScore`、`verifiedGroupCount`、`roundVerified`）与两个布尔（`groupVerified`、`roundVerified`）使本轮的验证进度可被完整复算，`testOriginScoresSubmittedTotalFinalScoreMatchesFold` 断言了累计值等于 fold。
- `voteAmount == 0` 与「未指定验证者」两种无事实情形都零日志（`:381-383`、`:397-399`）。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `VerifierApplicationSubmitted` | `:472` | 8 字段；首次申请 `previousApplicationId = 0` |
| `VerifierApplicationSubmitted` | `:655` | 修改申请携带旧 id |
| `VerifierStakeDeposited` | `:472` | 5 字段；位置早于 `VerifierApplicationSubmitted` |
| `VerifierStakeRefunded` | `:673` | 每次付款一条，与 `VerifierApplicationCancelled` 配对 |
| `VerifierApplicationCancelled` | `:608` | 5 字段 |
| `VerifierApplicationCancelled` | `:631` | `round` 为撤销轮（与申请轮区分） |
| `VerifierLocked` | `:472` | 4 字段；位置早于 `OriginScoresSubmitted` |
| `OriginScoresSubmitted` | `:472` | 11 字段全量（含 `scores` 两元素） |
| `OriginScoresSubmitted` | `:785` | `totalFinalScore` = 逐成员折叠值 |
| `ApplicationVoteRecorded` | `:571` | 8 字段 |
| `ApplicationVoteRecorded` | `:552` | 按轮隔离（`voteAmountTotal` 不跨轮累加） |
| `ApplicationVoteRecorded` | `:535` | emitter 为 Executor |

缺两条：(a) 「已锁定验证者撤销申请后继续提交」的事件序列（`GAV-EV-4` 的复现路径：`VerifierStakeRefunded` + `VerifierApplicationCancelled` + `OriginScoresSubmitted` 同轮共存）；(b) 一个成员集合经过「加入 → 退出 → 再加入」后再验证时，`scores[]` 与 `memberId` 的对齐（`GAV-EV-1` 的 swap-and-pop 复现路径）。
