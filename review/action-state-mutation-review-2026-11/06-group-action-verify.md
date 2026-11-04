# GroupActionVerify · 状态变量变更审查

> `action/src/GroupActionVerify.sol`，853 行，`action@0c1d1e2`。
> 职责：验证者申请与押金、按轮投票记账与排名、原始分批次提交与「位置化已验证前缀」、群/轮两级累计分、验证信息值读取。**全仓唯一一个「写入量与轮次强绑定」的模块**：验证只写 `phase − 2` 那一轮。
> 本卷只审状态写入，鉴权见 `action-api-auth-2026-11` 的 `06-group-action-verify.md`，事件见 `action-events-audit-2026-11` 的 `05-group-action-verify.md`。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局（本库写入的 Layout 字段）

### A. 验证结果（按轮，只增）

| # | 字段 | 键 | 写点 |
| --- | --- | --- | --- |
| A1 | `originScoreDeductionByMemberId` | token + action + round + member | `_scoreMember:475`（仅 `score < 100` 时写 `100 − score`） |
| A2 | `verifiedMemberCountByGroupId` | token + action + round + group | `_scoreBatch:441`（游标推进） |
| A3 | `verifiedGroupCountByRound` | token + action + round | `_markGroupVerified:458`（`++`） |
| A4 | `roundVerified` | token + action + round | `_markGroupVerified:460`（单向置 true） |
| A5 | `finalScoreByGroupId` | token + action + round + group | `_scoreBatch:438`（累加） |
| A6 | `totalFinalScore` | token + action + round | `_scoreBatch:439`（累加） |
| A7 | `lockedVerifierId` | token + action + round | `_submitOriginScores:739`（首次有效批次写一次） |

### B. 验证者申请（常设，跨轮）

| # | 字段 | 键 | 写点 |
| --- | --- | --- | --- |
| B1 | `applicationIdCount` | token + action | `_replaceApplication:576`（`++`，单调） |
| B2 | `currentApplicationId` | token + action + verifier | `_replaceApplication:577`、`cancelVerifierApplication:191`（置 0） |
| B3 | `activeApplicationIds` | token + action | `_replaceApplication:578`（add）/`:572`（remove）、`cancel:189`（remove） |
| B4 | `applicationIdHistory` | token + action + verifier | `_replaceApplication:579`（record 新 id）、`cancel:192`（record 0） |
| B5 | `applicationVerifierId` | token + action + applicationId | `submitVerifierApplication:162`（写一次） |
| B6 | `applicationDescription` | 同上 | `submitVerifierApplication:163`（写一次） |

### C. 投票记账与排名（按轮）

| # | 字段 | 键 | 写点 |
| --- | --- | --- | --- |
| C1 | `voteAmountByApplicationId` | token + action + round + applicationId | `onProposalVoted:400`（`+=`，只增） |
| C2 | `voterIdsByApplicationId` | 同上 | `onProposalVoted:401`（add，只增） |
| C3 | `voteAmountByApplicationIdByVoterId` | 再加 voterId | `onProposalVoted:402`（`+=`） |
| C4 | `rankedApplicationIds` | token + action + round | `_upsertRank:602/615/617-621`、`_removeFromRank:644-646`、`_replaceApplication:573`、`cancel:190` |

### D. 只读

`verificationKeysByActionId` / `verificationDescriptionsByActionId`（Manager 写）、`verificationValueHistory`（Join 写）、`memberIdsByGroupId` / `groupHistoryByMemberId` / `ownAmount*` / `providerAmount*`（Join 写）在本库全部只读。

## 2. 逐变量变更逻辑

### 2.1 分数流水线：一次 `submitOriginScores` 写七个字段

```text
memberIdsByGroupId[round][group]  (只读，按轮快照)
        │  位置 [verifiedCount, verifiedCount+n)
        ▼
_scoreMember ──► originScoreDeductionByMemberId[round][member]   (仅 <100 分时写)
        │        return memberAmount(round) × score
        ▼
_scoreBatch  ──► finalScoreByGroupId[round][group] += Σ
             ──► totalFinalScore[round] += Σ
             ──► verifiedMemberCountByGroupId[round][group] = verifiedCount + n
             ──► _markGroupVerified
                     │  verifiedCount == memberCount ?
                     ├─ 否 → 返回 false
                     └─ 是 → verifiedGroupCountByRound[round]++
                              │  == groupIdsByRound.countByRound(round) ?
                              └─ 是 → roundVerified[round] = true
```

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:692-699` | `originScores` 非空、`<= 100` 项 | `OriginScoresEmpty` / `VerificationBatchTooLarge` |
| 2 | `:701` | `round = currentVerifyRound()` | `phase − 2`，`phase < 3` 回滚 `RoundNotStarted(1,0)` |
| 3 | `:704-713` | 已锁定则必须是同一验证者；未锁定则 `_checkOpenVerifier` | `VerifierAlreadyLocked` / `NoActiveApplication` / `VerifierNotRanked` / `VerifierNotOpen` |
| 4 | `:715-721` | `memberCount = memberIdsByGroupId.countByRound(round)`；已满则拒 | `GroupVerificationAlreadyComplete` |
| 5 | `:722-729` | `startIndex == verifiedCount` 且 `startIndex + n <= memberCount` | `StartIndexMismatch` / `ScoreCountExceeded` |
| 6 | `:730-736` | 逐项 `score <= 100` | `ScoreLimitExceeded` |
| 7 | `:738-746` | `lockedVerifier == 0` → 写 `lockedVerifierId` | `VerifierLocked` |
| 8 | `:748-757` | `_scoreBatch` | 见上图 |
| 9 | `:760-772` | `OriginScoresSubmitted`（带后置累计） | — |

第 5 步的 `startIndex == verifiedCount` 是**连续游标**的核心：它禁止跳批与重批，因此「每个成员只被计分一次」不靠去重集合，靠单调游标。

### 2.2 `_originScore`（`:481-506`）——位置化已验证推导

| 顺序 | 位置 | 判据 | 不满足时 |
| --- | --- | --- | --- |
| 1 | `:488-491` | `groupHistoryByMemberId.value(round) != 0` | `(0, false)` |
| 2 | `:492-495` | `verifiedMemberCountByGroupId[round][group] != 0` | `(0, false)` |
| 3 | `:496-503` | `indexPlusOne = memberSet.indexPlusOneHistory[memberId].value(round)`；`indexPlusOne != 0` 且 `indexPlusOne − 1 < verifiedCount` 且 `slotHistory[indexPlusOne−1].value(round) == memberId` | `(0, false)` |
| 4 | `:504-505` | `score = 100 − originScoreDeductionByMemberId[round][memberId]` | — |

第 3 步的三个合取项缺一不可：`indexPlusOne != 0` 排除未加入，`< verifiedCount` 排除「已加入但还没轮到他」，`slotHistory == memberId` 排除「槽位被 swap-and-pop 换成了别人」。第三项是关键——`indexPlusOneHistory` 是历史值，而 `slotHistory` 也是按轮历史，两者必须指向同一个人。

### 2.3 申请与押金（`:150-214`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:158` | `_checkApplicationSubmission` | 有治理票、描述 ≤ 1024、`createdRound != 0` |
| 2 | `:160` | `previousApplicationId = currentApplicationId[...]` | 决定要不要押金 |
| 3 | `:161` | `_replaceApplication` | 移除旧申请（B3/C4）→ `++applicationIdCount` → 写 B2/B3/B4 |
| 4 | `:162-163` | 写 B5/B6 | 申请 id 与说明 |
| 5 | `:165-168` | `previousApplicationId == 0` 时 `_depositVerifierStake` | `safeTransferFrom(msg.sender, this, stakeAmount)` |
| 6 | `:170-172` | `VerifierApplicationSubmitted` | — |

押金只收一次：`previousApplicationId != 0` 时为 0（`:165`）。因此 **「持有当前申请」⟺「押金已收」**，`verifierStake` 视图（`:216-226`）正是按这个等价写成的。

`cancelVerifierApplication`（`:176-214`）反向：移除 B3/C4 → `currentApplicationId = 0` → `applicationIdHistory.record(round, 0)` → 退押金给 `ownerOf(verifierId)`。

### 2.4 `_upsertRank`（`:582-622`）——容量 + 有序插入

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:590` | `capacity = SPLITS.length + 1` | 可开放名额数 |
| 2 | `:592` | `_removeFromRank` | 先摘掉自己（重复投票时重排） |
| 3 | `:595-603` | 榜满且本次票数 `<=` 末位 → **早退** | 票已入账，但不进榜 |
| 4 | `:605-614` | 线性找插入点（票降序、id 升序） | — |
| 5 | `:615-621` | push + 右移 + 回填 | — |

第 3 步的早退是「票数与排名不同步」的源头：`voteAmountByApplicationId` 已加，但 `rankedApplicationIds` 不含该项。见 M-GAV-06。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| V1 | `verifiedMemberCountByGroupId[round][g] == 该群在 round 已计分的成员数` | ✅ | 唯一写入点是 `_scoreBatch:441`，值 = 旧游标 + 本批项数，且第 5 步保证不超 `memberCount` |
| V2 | `finalScoreByGroupId[round][g] == Σ 已计分成员的 memberAmount × score` | ✅ | 读改写累加（`:431-438`），批次之间不覆盖 |
| V3 | `totalFinalScore[round] == Σ_g finalScoreByGroupId[round][g]` | ✅ | 与 V2 同一循环累加，增量相同 |
| V4 | 每个成员每轮至多计分一次 | ✅ | 连续游标（`startIndex == verifiedCount`）+ 「已完成则拒」 |
| V5 | `roundVerified` 只在 `verifiedGroupCount == groupIdsByRound.countByRound(round)` 时置 true | ✅ | `:459` |
| V6 | `verifiedGroupCountByRound` 不超过该轮群数 | ✅ | 每群完成后即不可再提交（`GroupVerificationAlreadyComplete`），因此每群至多 +1 |
| V7 | `voteAmountByApplicationId[round][app] == Σ_voter voteAmountByApplicationIdByVoterId[round][app][voter]` | ✅ | `:400` 与 `:402` 同一 `+=`，名册去重不影响金额累加 |
| V8 | `rankedApplicationIds[round]` 严格降序（票）、同票按 id 升序、长度 ≤ `SPLITS.length + 1` | ✅ | `:610` 的比较式 + `:595-603` 的容量裁剪 |
| V9 | 持有当前申请 ⟺ 押金已收 | ✅ | 押金只在 `previousApplicationId == 0` 时收（`:165`），而 `previousApplicationId == 0` 与「当前无申请」等价（`currentApplicationId` 唯一写点） |
| V10 | 验证只写 `phase − 2` 轮 | ✅ | `currentVerifyRound()` 是唯一轮次源 |

## 4. 发现

### M-GAV-01 · 替换或撤销申请后，旧申请的票与名册仍留在状态里，该轮「各申请票数之和」可以大于实际投票数

| 字段 | 值 |
| --- | --- |
| 位置 | `:400-402`（只增）、`:563-580`（`_replaceApplication` 只动 B2/B3/B4 + 当前轮排名）、`:176-214`（撤销） |
| 级别 | Info |
| 证据 | E1 |

`_replaceApplication` 做四件事：从 `activeApplicationIds` 移除旧 id、从**当前轮**排名移除旧 id、`++applicationIdCount`、写新的 B2/B3/B4。它**不动** `voteAmountByApplicationId[round][oldApp]`、`voterIdsByApplicationId[round][oldApp]`、`voteAmountByApplicationIdByVoterId[round][oldApp][voter]`。

因此同一个投票轮内可以出现：

| 申请 | 状态 | `voteAmountByApplicationId` |
| --- | --- | --- |
| `app#1`（被替换） | 不在榜、`applicationIdHistory` 已指向 `app#2` | 保留（例如 500） |
| `app#2`（新） | 在榜、从 0 计票 | 例如 200 |

该轮实际投出的票是 500（都投给了当时的 `app#1`），但两张申请的票数之和是 700。规格 `05:69` 明确「替换等价于撤销后重新申请，旧 ID 失效、新 ID 从零计票」，所以这是设计；但**状态里没有任何标记表示「app#1 已失效」**——只能靠 `applicationIdHistory.value(round) != app#1` 反推。链下若按「遍历所有 applicationId 求和」对账，会系统性高估。

修法（不破坏语义）：在规格的读面表里写明「按申请聚合票数时，只统计 `applicationIdHistory` 在该轮指向的申请」。

### M-GAV-02 · 满分不写扣分槽，因此「已验证」不能用扣分槽判断

| 字段 | 值 |
| --- | --- |
| 位置 | `:473-477`（`score < MAX_ORIGIN_SCORE` 才写）、`:496-505`（位置前缀推导） |
| 级别 | Info |
| 证据 | E1 |

`_scoreMember` 只在原始分低于 100 时写 `originScoreDeductionByMemberId`（满分走零写入，省一次冷写）。因此：

- `originScoreDeductionByMemberId[round][m] == 0` 有两种含义：**未验证** 或 **验证得满分**。
- 「已验证」只能由「成员在集合中的位置 `< verifiedMemberCountByGroupId`」推出（`_originScore:496-503`）。

这不是缺陷（规格 `05:83` 明说「存储记扣分而非原始分」「已验证不占存储位」），但它是一个**必须写进集成文档的陷阱**：任何按「扣分槽非零」统计已验证人数的链下脚本都会漏掉所有满分成员。本卷把它列为发现而非正面结论，是因为 `GroupActionStorage:118-124` 的 `Load-bearing` 注释只解释了「位置化」的时序前提，没有写「零值二义」。

### M-GAV-03 · 申请 id 单调递增且旧申请的说明永久保留，`applicationIdCount` 无上限

| 字段 | 值 |
| --- | --- |
| 位置 | `:576`、`:162-163` |
| 级别 | Info |
| 证据 | E1 |

`applicationIdCount` 只增不减，`applicationVerifierId` / `applicationDescription` 写一次永不删。一个反复「修改申请」的验证者，每改一次就留下一条永久记录（`description` 最多 1024 字节）。

这是「申请常设 + 修改等价于重新申请」的必然代价。上限由验证者的 gas 决定，没有协议级约束。`activeApplicationIds` 是可增删的 `Uint256Set`，因此「当前有效申请」的枚举不受影响；受影响的只有 `verifierApplication(round, verifierId)` 能回看到的历史申请体。

### M-GAV-04 · `lockedVerifierId` 无超时、无接管路径，锁定者失联则整轮零激励

| 字段 | 值 |
| --- | --- |
| 位置 | `:738-746`、`:704-713` |
| 级别 | Info |
| 证据 | E1 |

首次有效批次把验证者写进 `lockedVerifierId` 后，其他任何验证者都不能再为该轮提交（`VerifierAlreadyLocked`）。规格 `05:94` 已明说「锁定者失联、未完成时，行动层激励为零」。

状态视角要补的是**唯一恢复路径**：`onlyMemberOwner(verifierId)` 判的是 `ownerOf`，所以把 MemberNFT 转给一个愿意继续验证的人，新持有人可以续验（游标 `verifiedMemberCountByGroupId` 保留）。除此之外没有任何覆盖机制——没有超时、没有治理、没有二次锁定。这意味着「锁一轮」的成本是一个 MemberNFT 的转移 + 一个批次的 gas，而收益是让该轮所有参与者的激励归零。

这不是新发现的攻击面（规格承认），但值得在 ADR 层面确认：**这是否是可接受的 DoS 面**。

### M-GAV-05 · `roundVerified` 的成立条件依赖「验证轮集合冻结」，该前提不在本库内可验证

| 字段 | 值 |
| --- | --- |
| 位置 | `:459`（`verifiedGroups == countByRound(round)`）、`GroupActionStorage:126-131`（`Load-bearing` 注释） |
| 级别 | Info |
| 证据 | E1 |

`roundVerified` 的判定是「已完成群数 == 该轮群数」。后者读 `groupIdsByRound.countByRound(round)`，是一个**按轮历史值**；前者是累加器。两者相等要求：

1. 该轮的 `groupIdsByRound` 在验证期间不再变化（否则群数变了，累加器追不上）；
2. 每个群只能完成一次（否则累加器超调）。

第 2 条由 `GroupVerificationAlreadyComplete` 保证。第 1 条**不在本库内**：它依赖 `GroupActionJoin._registerMembership` / `_finalizeExit` 只写 `currentJoinRound()`（= `phase − 1`），而验证轮是 `phase − 2`。这条时序由两个不同的库各自维护，没有任何断言把它们绑在一起。

后果形态是**静默**的：如果将来有一条路径在验证轮写了 `groupIdsByRound`（例如新增「强制退出」直接清集合），该轮的 `roundVerified` 会永远不成立，所有成员的结算都返回 `MemberActionRewardUnavailable`，且没有任何 revert 提示。`GroupActionStorage:126-131` 已用 `Load-bearing` 注释登记了这条前提，但注释在 Layout 里、写入在 Join 里，跨文件。

建议：在 `GroupActionJoin._registerMembership` / `_finalizeExit` 的写入点各加一句 `// Load-bearing: 只能写 currentJoinRound()`，或在 `GroupActionStorage` 里加一个 `assert(round == currentJoinRound())` 的调试入口。

### M-GAV-06 · 榜外申请不可枚举：有票但未上榜的申请只能按 id 猜

| 字段 | 值 |
| --- | --- |
| 位置 | `:595-603`（榜满早退）、`:246-265`（`verifierApplications` 只列 active） |
| 级别 | Info |
| 证据 | E1 |

`_upsertRank` 在榜满且本次票数不超过末位时**早退**，但 `voteAmountByApplicationId` 已经累加。于是存在三类申请：

| 类 | 在 `activeApplicationIds` | 在 `rankedApplicationIds` | 有票数 |
| --- | --- | --- | --- |
| 在榜 | ✅ | ✅ | ✅ |
| 榜外有票 | ✅ | ❌ | ✅ |
| 榜外无票 | ✅ | ❌ | 0 |

`topVerifiers` 只返回榜内；`verifierApplications` 返回全部 active 但**不带票数**；`voteAmountsByVerifierIds` 需要调用方先知道 verifierId。因此「列出该轮所有拿到票的验证者（含榜外）」在链上没有入口，只能遍历 `applicationIdCount` 逐个 `voteAmountByApplicationId`。

这不算缺陷（榜外申请本来就不参与验证），但它让「票数去哪了」在链上不可自证——与 M-GAV-01 是同一类对账缺口的两面。

### M-GAV-07 · `onProposalVoted` 对「没有验证者项」静默返回，投票成功但不记任何验证者票

| 字段 | 值 |
| --- | --- |
| 位置 | `:381-383` |
| 级别 | Info |
| 证据 | E1 |

`targetData.length == 0 || == 1` 时直接 `return`。因此 `Vote.vote` 传一个只有 executor 项（或空）的 `targetData`，投票本身成功、`VoteCast` 照发，但本库不写 C1/C2/C3/C4 任何字段。

规格 `05:79` 已写明「投票 Target Data 为空表示不指定验证者」，所以是设计。但它与「指定了一个没有当前申请的验证者」的失败形态不对称：后者回滚 `NoActiveApplication` 并**整笔撤销投票**，前者静默成功。同一个「这一票算给谁」的问题，两种输入一个成功一个失败，链下无法从 `VoteCast` 区分。

## 5. 已核对为正确的点

- `_scoreBatch` 的读改写（`:431-439`）在批次之间不覆盖：`groupFinal`/`totalFinal` 都从存储读旧值再累加，且两个累加器的增量完全相同（V2/V3）。
- `startIndex == verifiedCount` 的严格相等（`:722`）同时挡住跳批、重批与乱序，是「每成员只计分一次」的唯一依赖。
- `_originScore` 的三重合取（`:498-503`）足以排除「槽位被 swap-and-pop 换成别人」的误判，因为 `slotHistory` 与 `indexPlusOneHistory` 都是按轮历史值。
- `_upsertRank` 的容量上界 `SPLITS.length + 1` 与 `_checkOpenVerifier` 的 `SPLITS[rank − 1]` 下标上界一致：`rank <= SPLITS.length` ⟹ `rank − 1 <= SPLITS.length − 1`，不会越界（`GAV-06` 已登记该性质，本卷复核仍成立）。
- `_checkOpenVerifier` 的 `phaseInfo(round + 2)` 取的是**当前** Phase 的精确段（`round = phase − 2`），不是外推值，因此开放时刻不会因未来段长变化而漂移。
- 押金的「收一次、退一次」由 `previousApplicationId == 0` 唯一决定（V9），不存在「未交押金却退款」或「重复交押金」。
- `cancelVerifierApplication` 退给 `ownerOf(verifierId)` 而非 `msg.sender`，与 `onlyMemberOwner` 判据同源，不存在「代领」。
- `onProposalVoted` 的 `voteAmount == 0` 早退（`:397-399`）在写任何状态之前，零票不会产生名册项。
- `voterIdsByApplicationId` 是 `Uint256Set`（只增不删），因此 `applicationVoters` 的 `reverse` 精确等于「首次投票逆序」，不需要 swap-and-pop 的偏移补偿。
- `applicationIdHistory` 的 `record(round, 0)` 形成显式终止点（`:192`），使「该轮已撤销」与「该轮从未申请」在按轮读取上可区分（前者 `value(round) == 0` 且 `index.contains(round)`）。

## 6. 覆盖缺口

- 未测「同一验证者在同一轮内替换申请后，旧申请的票是否仍能被 `applicationVoters(round, oldApp)` 读到」——按代码应可读到（C2 未清理），但未跑测试确认。
- 未复核 `_markGroupVerified` 在 `memberCount` 因历史懒继承而从更早轮取值的边界（该轮无写入时 `countByRound` 回退到最近记录）；按「无写入 = 无人变动」应当正确，未构造用例。
- 未审 `submitOriginScores` 的 gas 上界（单批 100 项 × 每项一次冷写 + 一次集合定位）；规格把它定为协议常量 100。
- 未审押金划转的 CEI 顺序（`_replaceApplication` 先写状态、`_depositVerifierStake` 后转账），`nonReentrant` 在 Executor 侧，未逐条验证 21 个入口的锁覆盖。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GAV-01` | 规格补写 | [`05-group-action-executor.md`](../../docs/specs/action/05-group-action-executor.md) 的「状态口径」：旧申请的票与名册永久保留，该轮各申请票数之和可大于实际投票数 |
| `M-GAV-02` | 规格补写 | 同上：已验证只能读 `roundVerified` 集合，不能读扣分槽（满分不占存储位） |
| `M-GAV-03` | 规格补写 | 同上：申请 id 只增，旧申请说明永久保留，`applicationIdCount` 无上限 |
| `M-GAV-04` | 规格补写 | 同上：`lockedVerifierId` 无超时、无接管，锁定者失联则整轮零激励；治理只能重开轮 |
| `M-GAV-05` | 规格补写 | 同上：`roundVerified` 的前提是「验证轮集合冻结」，由阶段模型保证，写入口只能在 `currentJoinRound()` |
| `M-GAV-06` | 规格补写 | 同上：榜外申请不可枚举，链下只能按 id 扫描 |
| `M-GAV-07` | 规格补写 | 同上：`onProposalVoted` 对空 `targetData` 静默返回，投票成功但不记任何验证者票 |
