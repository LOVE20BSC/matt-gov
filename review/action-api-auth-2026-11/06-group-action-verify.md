# GroupActionVerify（库）接口调用权限审查

> 对象 `action/src/GroupActionVerify.sol`（853 行，`library`，经 `delegatecall` 由 `GroupActionExecutor` / `GroupServiceExecutor` 调用）
> 接口 `action/src/interfaces/IGroupActionVerify.sol`（260 行，`is IVerificationInfo`）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§5.2.2（失败顺序）、§4.3（集合读取）；`specs/action/05-group-action-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| `external` 函数 | 21（写 4 / 读 17） |
| 带鉴权 modifier | 3（`onlyMemberOwner`，本库自定义） |
| 无许可写入口 | 1（`onProposalVoted`，鉴权在 Executor 的 `onlyActionTarget`） |
| 发现 | 4 条 Info；另有 2 条正面结论 |
| 接口对账 | 由 `GroupActionExecutor` 侧统一对账（78 vs 78，0 差异） |

一句话：**验证者申请、撤销、评分提交三条写入口都只认 `verifierId` 的当前持有人，押金与「持有当前申请」同生共死；投票回调的鉴权不在这里，在 Executor 上。唯一有实质内容是错误优先级：`submitVerifierApplication` 的三类失败顺序与 §5.2.2 相反，而规格正文与实现一致——这是规范与规格的冲突，需要裁决而不是改代码。**

## 二、权限模型

| 入口 | 权限主体 | 判定位置 |
| --- | --- | --- |
| `submitOriginScores` | `verifierId` 持有人 | `onlyMemberOwner` `L50-59` + `L70` |
| `submitVerifierApplication` | `verifierId` 持有人 | 同上 `L157` |
| `cancelVerifierApplication` | `verifierId` 持有人 | 同上 `L182` |
| `onProposalVoted` | ActionTarget | **本库无判定**，由 `GroupActionExecutor.onProposalVoted` 的 `onlyActionTarget`（`GroupActionExecutor.sol:112`）承担 |

「验证者」不是一个独立的身份类型——它就是一个 `memberId`，被某个行动在某一轮选为公共验证者。因此三处鉴权都用同一句 `ownerOf(verifierId) == msg.sender`，与成员入口完全同型。这意味着**验证者身份不可委派**：NFT 的 ERC721 授权（`approve`/`setApprovalForAll`）不延伸到验证入口，多签或托管合约必须自己作为 `msg.sender` 调用。这与 core 审查的 G-02（业务层不认 ERC721 授权）是同一件事，在 action 仓同样成立。

## 三、入口清单

### 写入口（4）

| 函数 | 权限主体 | 首道判定 | 资金方向 | 事件 |
| --- | --- | --- | --- | --- |
| `submitOriginScores(address,uint256,uint256,uint256,uint256,uint256[])` | `verifierId` 持有人 | `onlyMemberOwner` `L61-70` | 无 | `VerifierLocked`（首次）、`OriginScoresSubmitted` |
| `submitVerifierApplication(address,uint256,uint256,string)` | `verifierId` 持有人 | `onlyMemberOwner` `L150-157` | 首次申请从 `msg.sender` 拉押金 | `VerifierStakeDeposited`、`VerifierApplicationSubmitted` |
| `cancelVerifierApplication(address,uint256,uint256)` | `verifierId` 持有人 | `onlyMemberOwner` `L176-182` | 押金退给 `ownerOf(verifierId)` | `VerifierStakeRefunded`、`VerifierApplicationCancelled` |
| `onProposalVoted(address,uint256,uint256,uint256,uint256,bytes[])` | ActionTarget | 无（Executor 侧 `onlyActionTarget`） | 无 | `ApplicationVoteRecorded` |

### 只读入口（17）

申请与排名 5：`verifierApplication`、`verifierApplications`、`verifierStake`、`topVerifiers`、`voteAmountsByVerifierIds`。

投票名册 2：`applicationVoters`、`applicationVotersByVerifierId`。

分数与验证状态 6：`originScore`、`finalScore`、`totalFinalScore`、`verifiedMemberCount`、`isRoundVerified`、`lockedVerifierId`。

验证信息 4：`verificationSchema`、`verificationValue`、`verificationInfos`、`verificationInfosByRound`。

读面边界：全部不回滚。`verifierApplication` 无记录返回零值结构体（`applicationId = 0`）；`voteAmountsByVerifierIds` 无票返回 0；`applicationVotersByVerifierId` 该轮无申请返回空数组与 0；`originScore`/`finalScore` 未验证返回 `(0, false)`。唯一的回滚是 `currentVerifyRound()`（`internal`，`L521-527`），在 phase < 3 时 `RoundNotStarted(1,0)`。

## 四、逐入口判定

### `submitOriginScores` — 首个有效批次永久锁定验证者

顺序（`_submitOriginScores` `L686-773`）：鉴权 → 批次非空 → 批次 ≤ 100 → `currentVerifyRound()` → 锁定者判定 → 群成员数/已验证数 → `startIndex` 连续性 → 分数上限 → 锁定（首次）→ 计分 → 事件。

- **锁定者判定**（`L704-713`）：`lockedVerifierId != 0` 时必须是本人，否则 `VerifierAlreadyLocked`；未锁定时走 `_checkOpenVerifier`（排名内 + 分割窗口已开）。
- **`startIndex` 必须严格等于该群已验证数量**（`L722-724`）→ `StartIndexMismatch`。这使验证批次必须按历史成员顺序连续消费，不能跳、不能重、不能乱序——「同一成员只被评一次」由这条游标保证，而不是靠去重表。
- **锁定写入在计分之前**（`L738-746`），因此「已锁定」与「已计入分数」在同一笔里同生共死；若计分回滚，锁定也回滚。
- **无 `nonReentrant`**：本路径唯一的对外调用是 `IPhase.phaseInfo`（只读），没有状态变更外呼。见 `04-group-action-executor.md` GAE-03。

### `submitVerifierApplication` — 新建或替换，押金只在首次

顺序（`_checkApplicationSubmission` `L814-835`）：`round = currentPhase()` → `validGovVotes > 0` → 描述 ≤ 1024 → `createdRound != 0` → 然后 `_replaceApplication`（旧申请移出榜单与活跃集）→ 首次申请时拉押金 → 事件。

- **「修改申请」等价于「撤销后重新申请」**：`_replaceApplication` 给新 `applicationId`（单调递增），旧 id 从 `activeApplicationIds` 与当前轮排名里移除，新 id 从零计票。
- **押金只在 `previousApplicationId == 0` 时收取**（`L165-168`）。因此「修改」不退款也不再收——押金始终是「一份」。
- 错误优先级见 **GAV-01**。

### `cancelVerifierApplication` — 撤销即全额退款

顺序（`L176-214`）：鉴权 → `currentPhase()` 作轮次 → `currentApplicationId != 0` → 移出活跃集与当前轮排名 → 清 `currentApplicationId` → 在**投票轮**写入零值终止点 → 押金全额退给 `ownerOf(verifierId)` → 事件。

- **押金与「持有当前申请」是同一件事**：`verifierStake`（`L216-226`）的判据就是 `currentApplicationId != 0`。因此「已质押」不可能脱离「有当前申请」存在，反之亦然。见 GAV-05。
- 退款对象是 `ownerOf(verifierId)` 而不是 `msg.sender`——两者相同（鉴权已保证），但写成 `ownerOf` 使「钱跟着身份走」显式化。
- 撤销**不收回**已获得的验证资格：锁定与分数按轮独立，撤销只影响后续轮次。规格明文要求。

### `onProposalVoted` — 库内唯一无鉴权的写入口

顺序（`L372-417`）：项数为 0 或 1 → 直接返回（不指定验证者）→ 项数 > 2 → `TargetDataLengthMismatch` → 第 1 项 32 字节 → 解出 `verifierId` → `currentApplicationId != 0` → `NoActiveApplication` → `voteAmount == 0` 则返回 → 累加票数 + 名册 + 排名 → 事件。

- 鉴权完全由 Executor 的 `onlyActionTarget` 承担，本库不自判。这在结构上是对的：库函数是 `external`，由 Executor `delegatecall`，`msg.sender` 在库内仍是原始调用者——如果库内再加一道判定，会与 Executor 的判定重复。
- **不校验 `round`**：`round` 由 Vote 传入（Vote 自己的 `currentRound()`）。规格已写明「回调不校验轮次——`Vote` 传的是它自己的 `currentRound()`，而提案只能在其创建轮或之后被投票，因此 `round` 恒不早于创建轮」。这条依赖的完整性由 Vote 保证，不在本库。
- **用 `currentApplicationId` 而非按轮历史解析**：投票记给「此刻的当前申请」。若验证者在同一轮内替换申请，此前累积的票留在旧申请 id 上，新申请从零开始——与「替换等价于撤销后重新申请」同源。

### 排名与窗口

`_upsertRank`（`L582-622`）维护当前轮前 `SPLITS.length + 1` 名：票数降序、`applicationId` 升序（平票时较早申请优先）；榜满时榜外必须**严格超过**末位才替换（`L599`）。

`_checkOpenVerifier`（`L529-561`）：`rank == 0` 直接放行（第 1 名在验证阶段起点即可提交）；否则 `openOffset = ceil(phaseBlocks × SPLITS[rank-1] / 1e18)`，`block.number < startBlock + openOffset` 则 `VerifierNotOpen`。见 GAV-04。

## 五、发现

### GAV-01（Info，规格与规范冲突，待裁决）`submitVerifierApplication` 的错误优先级与 §5.2.2 相反

- 证据（`_checkApplicationSubmission` `L822-834`）：先 `validGovVotes == 0 → ZeroVerifyVotes`（**资格**），再 `description > 1024 → DescriptionTooLong`（**参数**），最后 `createdRound == 0 → ActionNotCreated`（**存在性**）。
- §5.2.2 规定的顺序是「鉴权 → 参数 → 存在性 → 状态/资格 → 账本/交互」。
- 规格正文与实现一致：`05-group-action-executor.md` 写「申请者须持有 verifierId 且有该社区有效治理票（无票回滚 `ZeroVerifyVotes`）；`description` 以字节计不超过 1024……未创建的行动（`createdRound == 0`）回滚 `ActionNotCreated`」，顺序即 资格 → 参数 → 存在性。
- 判定：**实现没错，是规格与全局规范冲突**。本报告不判实现缺陷，登记为待裁决项。
- 实际影响有限：三个条件都不携带「他人信息」，无信息泄漏面；影响的是链下错误分类的稳定性——同一个「未创建行动」的调用，若描述过长会先报 `DescriptionTooLong`，若没有治理票会先报 `ZeroVerifyVotes`。
- 建议：二选一——按 §5.2.2 调整实现（把描述长度检查提到最前、`createdRound` 提到第二），并同步改规格；或保留实现，在 §5.2.2 增一条「资格校验若需外部只读调用，允许排在参数之前」的例外说明。

### GAV-02（Info）`onProposalVoted` 在库内无任何 modifier，鉴权完全外置

- 证据：`L372-380`，函数签名后直接进函数体，无 `only*`。
- 当前安全：唯一调用方是 `GroupActionExecutor.onProposalVoted`，后者带 `onlyActionTarget`。
- 风险形状：这是本库唯一「鉴权与实现分居两个文件」的写入口。若将来有第二个合约复用本库的 `onProposalVoted`（例如给 GroupService 加投票回调），必须自己记得挂 `onlyActionTarget`。规格未把这条写成「调用方必须校验」的契约。
- 建议：在 `05-group-action-executor.md` 的库接口映射表里给这一行加「本库不判调用者，调用方必须判」的标注（该表目前只写「推举回调当前只校验调用者」）。

### GAV-03（Info）同一个库里并存两个轮次口径

- 证据：`submitVerifierApplication` 与 `cancelVerifierApplication` 用 `IPhase.currentPhase()`（投票轮）；`submitOriginScores` 用 `currentVerifyRound()`（= phase − 2）。
- 判定：这是有意的——申请与撤销发生在投票轮，评分发生在验证轮，两者相差 2。规格已分别写明。
- 仍然登记的原因：两个口径在同一文件内相邻出现，且都以裸 `uint256 round` 命名，没有后缀区分。`applicationIdHistory.record(round, ...)` 与 `verifiedMemberCountByGroupId[...][round]` 用的是**不同的 round 空间**，读代码时极易混用。建议把局部变量改名为 `voteRound` / `verifyRound`（不改 ABI，只改局部名）。

### GAV-04（Info）`verifierApplications` 分页直接回含变长字段的记录体

- 证据：`L246-265`，返回 `VerifierApplication[]`，结构体含 `string description`（≤ 1024 字节）。
- §4.3 第 2 条要求「含变长成员 → 只回 id，本体另设按 id 批量」。规格已登记为唯一例外：「该查询的消费方只有链下展示；若日后出现链上调用方，须改为『只回 id + 按 id 批量』」。
- 判定：已登记例外，符合 §4.3 的「必须在模块规格里明写该契约」。补充一条规格没写的量：一页最坏体量是 `limit × 1024` 字节，调用方须自行把 `limit` 压到能承受的值。
- 建议：在规格该段补上这个量级，让「只给链下用」这条约束可核对。

### GAV-05（正面结论）押金与「持有当前申请」是同一判据，没有第三条路径

- 证据：`submitVerifierApplication` 只在 `previousApplicationId == 0` 时收押金（`L165`）；`cancelVerifierApplication` 在 `currentApplicationId != 0` 时退款（`L184-205`）；`verifierStake` 的判据是 `currentApplicationId != 0`（`L222`）。
- 判定：三条读/写路径共用 `currentApplicationId` 一个状态位，因此「已质押」与「有当前申请」不可能分叉。`verifierStakeAmountByActionId` 又是单写值（只在创建回调写一次），所以金额也不会漂移。这是「用同一个状态位表达同一件事」的正确写法。

### GAV-06（正面结论）`SPLITS[rank-1]` 的越界由 `_upsertRank` 的容量上界保证

- 证据：`_upsertRank` 用 `capacity = self.SPLITS.length + 1`（`L590`），榜长超过容量时先 `pop` 再插入（`L595-603`），因此 `rankedApplicationIds.length <= SPLITS.length + 1`，最大 `rank`（0 基）为 `SPLITS.length`，`splitIndex = rank - 1 <= SPLITS.length - 1`。`SPLITS` 为空时容量为 1，`rank` 只能为 0 并提前返回（`L551-553`）。
- 判定：索引越界（Panic 0x32）在当前路径不可达。这条不变式是「验证者能提交」与「合约不回滚」之间的唯一屏障，值得记录为正面结论。

## 六、核对证据

```text
$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0

$ python3 …/evidence/auth_scan.py | grep GroupActionVerify
GroupActionVerify  写入口 4  带 modifier 3  无 modifier 1
  [AUTH] submitOriginScores        onlyMemberOwner,self,protocol,verifierId
  [AUTH] submitVerifierApplication onlyMemberOwner,self,protocol,verifierId
  [AUTH] cancelVerifierApplication onlyMemberOwner,self,protocol,verifierId
  [NONE] onProposalVoted           -
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 非持有人 `submitOriginScores` | `test/GroupActionVerifyFlow.t.sol:159` `testOriginScoreSubmissionReverts` |
| 非持有人申请/撤销且不收费 | `test/GroupActionVerifyFlow.t.sol:558` `testVerifierApplicationGuardsDoNotCharge` |
| 非 ActionTarget 调投票回调 | `test/GroupActionVerifyFlow.t.sol:261` `testCallbackGuards` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | Core `MemberNFT` | `ownerOf`（3 个入口的鉴权函数；`cancelVerifierApplication` 的退款对象） |
| 被调 | Core `Phase` | `currentPhase`（申请/撤销轮次）、`phaseInfo`（分割窗口） |
| 被调 | Core `Stake` | `validGovVotes`（申请门槛） |
| 被调 | `IERC20` | `safeTransferFrom`（押金存入）、`safeTransfer`（押金退还） |
| 被调 | ActionTarget | `clearJoinState` 不在此库；本库不调 ActionTarget |
| 被复用 | `GroupServiceExecutor` | `currentVerifyRound`（`setRecipients` 的轮次来源）、`isRoundVerified` 语义 |
| 内联复用 | `GroupActionRoundAxis` | `verifyRound` 纯换算 |
