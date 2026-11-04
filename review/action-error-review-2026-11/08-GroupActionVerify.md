# `action/GroupActionVerify.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/05-group-action-executor.md（验证者申请与排名、验证）`。
> 范围：`src/GroupActionVerify.sol`（853 行）+ `src/interfaces/IGroupActionVerify.sol` 的 `IGroupActionVerifyErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 11 个错误声明 / 19 个发送点（含 5 个跨模块复用）；无未声明 revert、无裸 `require`、无 `assert`。
- `submitOriginScores` 的批次形状（非空、≤ 100）先于一切状态判定，符合 §6「批量入口一律原子：形状错误先回滚」。
- `_checkApplicationSubmission` 把资格（治理票）放在参数（说明长度）与存在性（行动已创建）之前，与 §5 的层序相反；对未创建行动的申请会以 `ZeroVerifyVotes` 报错，掩盖真正的阻塞原因。
- `VerifierAlreadyLocked` 的条件是「该轮已被**其他**验证者锁定」，名称读起来是对调用者的断言，且载荷不含被拒的 `verifierId`。
- 2 条 Low + 3 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 11 |
| revert 站点 | 19 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 2 / 3 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | IActionExecutorErrors | 1 | 保留 |
| `NoActiveApplication` | `NoActiveApplication(uint256)` | IGroupActionVerifyErrors | 3 | 保留 |
| `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | IActionTargetErrors | 1 | 保留 |
| `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | IActionTargetErrors | 1 | 保留 |
| `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |
| `VerifierNotRanked` | `VerifierNotRanked(uint256,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `VerifierNotOpen` | `VerifierNotOpen(uint256,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `OriginScoresEmpty` | `OriginScoresEmpty()` | IGroupActionVerifyErrors | 1 | 保留 |
| `VerificationBatchTooLarge` | `VerificationBatchTooLarge(uint256,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `VerifierAlreadyLocked` | `VerifierAlreadyLocked(address,uint256,uint256)` | IGroupActionVerifyErrors | 1 | 待裁决 |
| `GroupVerificationAlreadyComplete` | `GroupVerificationAlreadyComplete(uint256,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `StartIndexMismatch` | `StartIndexMismatch(uint256,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `ScoreCountExceeded` | `ScoreCountExceeded(uint256,uint256,uint256)` | IGroupActionVerifyErrors | 1 | 口径调整 |
| `ScoreLimitExceeded` | `ScoreLimitExceeded(uint256,uint256,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `ZeroVerifyVotes` | `ZeroVerifyVotes(address,uint256)` | IGroupActionVerifyErrors | 1 | 保留 |
| `DescriptionTooLong` | `DescriptionTooLong(uint256,uint256)` | IGroupActionExecutorErrors | 1 | 保留 |
| `ActionNotCreated` | `ActionNotCreated(address,uint256)` | IActionExecutorErrors | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:23`（跨模块复用，本模块不重复声明）
- 签名：`NotMemberOwner(uint256)` · selector `0x33393244`
- 载荷：`uint256 memberId`
- 核对：本地 modifier；载荷为身份键。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:56` | `modifier onlyMemberOwner` | `IMemberNFT(protocol.memberNFTAddress).ownerOf(memberId) != msg.sender` | `memberId` |

### `NoActiveApplication` · 3 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:111`
- 签名：`NoActiveApplication(uint256)` · selector `0xcda5095d`
- 载荷：`uint256 verifierId`
- 核对：三站点同条件；`verifierId` 单字段即可定位。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:186` | `function cancelVerifierApplication` | `applicationId == 0` | `verifierId` |
| 2 | `GroupActionVerify.sol:394` | `function onProposalVoted` | `applicationId == 0` | `verifierId` |
| 3 | `GroupActionVerify.sol:539` | `function _checkOpenVerifier` | `applicationId == 0` | `verifierId` |

### `TargetDataLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:57`（跨模块复用，本模块不重复声明）
- 签名：`TargetDataLengthMismatch(uint256,uint256)` · selector `0x232f36be`
- 载荷：`uint256 expected, uint256 actual`
- 核对：投票回调「最多 2 项」，`expected = 2` 表示上界；与 GroupAction 的区间双义不同，此处只有一端。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:385` | `function onProposalVoted` | `targetData.length > 2` | `2, targetData.length` |

### `InvalidTargetDataShape` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:61`（跨模块复用，本模块不重复声明）
- 签名：`InvalidTargetDataShape(uint256,uint256)` · selector `0x9c2b3988`
- 载荷：`uint256 index, uint256 length`
- 核对：`index = 1` 固定（第 0 项由 ActionTarget 校验）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:388` | `function onProposalVoted` | `targetData[1].length != 32` | `1, targetData[1].length` |

### `RoundNotStarted` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:40`（跨模块复用，本模块不重复声明）
- 签名：`RoundNotStarted(uint256,uint256)` · selector `0xea74f32b`
- 载荷：`uint256 requiredRound, uint256 currentRound`
- 核对：`(1, 0)`；`currentVerifyRound` 与 `ExecutorBase.currentJoinRound` 同构。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:524` | `function currentVerifyRound` | `round == 0` | `1, 0` |

### `VerifierNotRanked` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:77`
- 签名：`VerifierNotRanked(uint256,uint256)` · selector `0x8e9078b9`
- 载荷：`uint256 verifierId, uint256 round`
- 核对：`(verifierId, round)`；条件为「申请不在该轮榜内」，与 `VerifierNotOpen` 互斥。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:549` | `function _checkOpenVerifier` | `rank == rankedApplicationIds.length` | `verifierId, round` |

### `VerifierNotOpen` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:81`
- 签名：`VerifierNotOpen(uint256,uint256)` · selector `0x0ee7919b`
- 载荷：`uint256 verifierId, uint256 round`
- 核对：`(verifierId, round)`；条件为区块早于该名次开放块，可由 `SPLITS()` + `phaseInfo` 复算。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:559` | `function _checkOpenVerifier` | `block.number < startBlock + openOffset` | `verifierId, round` |

### `OriginScoresEmpty` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:76`
- 签名：`OriginScoresEmpty()` · selector `0xaafa066e`
- 载荷：无
- 核对：无载荷；批次形状错误，先于一切状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:693` | `function _submitOriginScores` | `originScores.length == 0` | `—` |

### `VerificationBatchTooLarge` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:94`
- 签名：`VerificationBatchTooLarge(uint256,uint256)` · selector `0x3b91a8c8`
- 载荷：`uint256 count, uint256 maxCount`
- 核对：`(count, maxCount)`；与 `OriginScoresEmpty` 同属形状层。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:696` | `function _submitOriginScores` | `originScores.length > GroupActionStorage.MAX_VERIFICATION_BATCH` | `originScores.length, GroupActionStorage.MAX_VERIFICATION_BATCH` |

### `VerifierAlreadyLocked` · 1 站点 · 待裁决

- 声明：`interfaces/IGroupActionVerify.sol:112`
- 签名：`VerifierAlreadyLocked(address,uint256,uint256)` · selector `0xa4ab638a`
- 载荷：`address tokenAddress, uint256 actionId, uint256 round`
- 核对：名称与条件不符、载荷缺被拒方，见 E-GAV-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:707` | `function _submitOriginScores` | ``lockedVerifier != 0 && lockedVerifier != submission.verifierId`` | `submission.tokenAddress, submission.actionId, round` |

### `GroupVerificationAlreadyComplete` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:90`
- 签名：`GroupVerificationAlreadyComplete(uint256,uint256)` · selector `0xec3ddd72`
- 载荷：`uint256 groupId, uint256 round`
- 核对：`(groupId, round)`；带 `memberCount != 0` 前置。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:720` | `function _submitOriginScores` | `memberCount != 0 && verifiedCount == memberCount` | `submission.groupId, round` |

### `StartIndexMismatch` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:98`
- 签名：`StartIndexMismatch(uint256,uint256)` · selector `0xdadbe49c`
- 载荷：`uint256 expected, uint256 actual`
- 核对：`(expected, actual)`；`expected` 为该群已验证数量。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:723` | `function _submitOriginScores` | `submission.startIndex != verifiedCount` | `verifiedCount, submission.startIndex` |

### `ScoreCountExceeded` · 1 站点 · 口径调整

- 声明：`interfaces/IGroupActionVerify.sol:102`
- 签名：`ScoreCountExceeded(uint256,uint256,uint256)` · selector `0xc6f0561d`
- 载荷：`uint256 startIndex, uint256 count, uint256 memberCount`
- 核对：第三字段非限定名，见 E-GAV-04。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:726` | `function _submitOriginScores` | `submission.startIndex + originScores.length > memberCount` | `submission.startIndex, originScores.length, memberCount` |

### `ScoreLimitExceeded` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:85`
- 签名：`ScoreLimitExceeded(uint256,uint256,uint256)` · selector `0x743bbb84`
- 载荷：`uint256 index, uint256 score, uint256 maxScore`
- 核对：`(index, score, maxScore)`；判定早于轮次/锁定者与状态层（逐元素参数先于 `currentVerifyRound()`），见 E-GAV-03。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:732` | `function _submitOriginScores` | `originScores[i] > GroupActionStorage.MAX_ORIGIN_SCORE` | `i, originScores[i], GroupActionStorage.MAX_ORIGIN_SCORE` |

### `ZeroVerifyVotes` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionVerify.sol:107`
- 签名：`ZeroVerifyVotes(address,uint256)` · selector `0x131e332f`
- 载荷：`address tokenAddress, uint256 verifierId`
- 核对：`(tokenAddress, verifierId)`；条件为当前 Phase 的有效治理票为 0。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:824` | `function _checkApplicationSubmission` | `IStake(protocol.stakeAddress).validGovVotes(tokenAddress, round, verifierId) == 0` | `tokenAddress, verifierId` |

### `DescriptionTooLong` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:40`（跨模块复用，本模块不重复声明）
- 签名：`DescriptionTooLong(uint256,uint256)` · selector `0x71a24cf3`
- 载荷：`uint256 length, uint256 maxLength`
- 核对：`(length, maxLength)`；1024 为编译期常量。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:828` | `function _checkApplicationSubmission` | `descriptionLength > GroupActionStorage.MAX_DESCRIPTION_BYTES` | `descriptionLength, GroupActionStorage.MAX_DESCRIPTION_BYTES` |

### `ActionNotCreated` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:19`（跨模块复用，本模块不重复声明）
- 签名：`ActionNotCreated(address,uint256)` · selector `0x36c193ae`
- 载荷：`address tokenAddress, uint256 actionId`
- 核对：`createdRound == 0`；排在最后一段，见 E-GAV-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionVerify.sol:833` | `function _checkApplicationSubmission` | `self.createdRoundByActionId[tokenAddress][actionId] == 0` | `tokenAddress, actionId` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GAV-01 | Low | `src/GroupActionVerify.sol:704-710` | `VerifierAlreadyLocked(tokenAddress, actionId, round)` 的判据是 `lockedVerifier != 0 && lockedVerifier != submission.verifierId`，即「本轮已被**别的**验证者锁定」。名称按 `<Subject><State>` 读作「该验证者已锁定」，与条件相反（若真是自己锁定，调用会通过）。载荷只有锁槽三要素，不含被拒的 `verifierId`，索引方要还原「谁被拒」必须解 calldata。 | error-standards §3（错误名描述失败状态）/ §4（主体键在前） | 改名 `RoundVerifierLocked(address tokenAddress, uint256 actionId, uint256 round, uint256 lockedVerifierId)`，把锁定者放进载荷（破坏性 ABI 变更）；或在 05 的错误表里写明「`VerifierAlreadyLocked` 指该轮锁槽已占用，被拒方不在载荷中」。 |
| E-GAV-02 | Low | `src/GroupActionVerify.sol:822-834` | `_checkApplicationSubmission` 的顺序是 资格(`ZeroVerifyVotes`) → 参数(`DescriptionTooLong`) → 存在性(`ActionNotCreated`)，与 §5 固定的「鉴权 → 参数 → 存在性 → 状态/资格」正好倒置。可观测后果：对一个**未创建**的行动提交 1025 字节说明且无治理票，回的是 `ZeroVerifyVotes`，调用方会去补票而不是去创建行动；补完票再提交才会看到 `ActionNotCreated`。规格 05 的叙述顺序与实现同向，但未按 §5 要求写明理由。 | error-standards §5 | 把 `ActionNotCreated` 提到最前、`DescriptionTooLong` 次之、`ZeroVerifyVotes` 最后；或在 05 的「验证者申请与排名」段补一句理由（“先判票权再判行动存在，避免为不存在的行动消耗 gas” 之类）。 |
| E-GAV-03 | Info | `src/GroupActionVerify.sol:730-736` | 逐元素的 `ScoreLimitExceeded` 排在 `VerifierAlreadyLocked` / `GroupVerificationAlreadyComplete` / `StartIndexMismatch` / `ScoreCountExceeded` 之后。§5 把参数层放在状态层之前，§6 只要求「形状错误先回滚、元素错误按顺序首个失败」。规格 05 的叙述把「每项不超过 100」写在 `startIndex` 之前，实现相反。后果仅限错误定位：批次里既有越界分数又有错位 `startIndex` 时，先报 `StartIndexMismatch`。 | error-standards §5 / §6；05 的叙述顺序 | 若希望与规格叙述一致，把分数上界的循环提到 `lockedVerifier` 判定之前；否则在 05 里把叙述顺序改成实现的顺序。 |
| E-GAV-04 | Info | `src/GroupActionVerify.sol:725-729` | `ScoreCountExceeded(startIndex, count, memberCount)` 的第三个字段是「该群该轮的真实成员数」，既是条件值也是上界，但字段名不是 §4 要求的限定名（`count → maxCount`）。它与 `TooManyRecipients(count, maxCount)` 等同族错误的命名习惯不一致。 | error-standards §4（边界参数用限定名） | 仅参数名改为 `maxCount`（selector 不变），或保持现状并在 07 的错误表里说明该字段就是真实成员数。 |
| E-GAV-05 | Info | `src/GroupActionVerify.sol:391-399` | `onProposalVoted` 在 `voteAmount == 0` 时**先**校验「验证者有无当前申请」，无申请则 `NoActiveApplication` 回滚整个 `vote()`；规格 05 只写「本次票数为零时既不记票也不记名册」，未写零票是否仍要求申请有效。若 Vote 会以零增量回调（例如同一人重复投票且增量被合并），一个指向未申请验证者的零票会拖死该笔投票。 | error-standards §5（写入口的错误集合须与规格一致） | 在 05 写明「零票回调仍需验证者有当前申请；无申请即回滚」，或把 `voteAmount == 0` 的提前返回提到申请校验之前。 |

### 4.2 已核对项

- 声明全部在 `IGroupActionVerifyErrors`；`NotMemberOwner` / `TargetDataLengthMismatch` / `InvalidTargetDataShape` / `RoundNotStarted` / `DescriptionTooLong` / `ActionNotCreated` 复用基座或 Executor 声明，符合 07。
- `NoActiveApplication(verifierId)` 三个站点条件一致（该轮生效的申请 id 为 0），只是入口不同（撤销、投票回调、提交验证），属同一条件的多站点，符合 §2。
- `StartIndexMismatch(expected, actual)` 的 `expected` 是该群已验证数量、`actual` 是入参 `startIndex`，顺序符合 §4；规格 07 的表述与之逐字一致。
- `VerificationBatchTooLarge(count, maxCount)` 与 `ScoreLimitExceeded(index, score, maxScore)` 的限定名符合 §4；100 为协议级编译期常量。
- `GroupVerificationAlreadyComplete(groupId, round)` 带 `memberCount != 0` 前置，空群不会命中；空群走 `ScoreCountExceeded(0, n, 0)`，无静默成功路径。
- `_checkOpenVerifier` 的 `VerifierNotRanked` / `VerifierNotOpen` 顺序正确（先入榜、后开窗），且 `splitIndex = rank - 1 < SPLITS.length` 恒成立（容量为 `SPLITS.length + 1`），无越界。
- `_scoreBatch` / `_markGroupVerified` 无 revert；`verifiedGroups` 越过该轮群数时静默不置位 `roundVerified`（承重不变式已用注释登记），属「静默失败」而非错误路径，见 README 的 X-05。
- `cancelVerifierApplication` 的押金退款跟随 `ownerOf(verifierId)` 的当前持有人，与 05「退款跟随 NFT 转移后的新持有人」一致。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `onlyMemberOwner` 与 `cancelVerifierApplication` 的退款收款人解析；来源 `MemberNFT`。
- `SafeERC20FailedOperation` / `AddressEmptyCode` — 验证者押金的 `safeTransferFrom` / `safeTransfer`；来源 OZ `SafeERC20`。
- `RoundNotStarted` 由本库 `currentVerifyRound` 抛出（站点记在本文件 `:524`），与 `ExecutorBase` 的同名 getter 载荷相同。
- `PhaseNotStarted` — `_checkOpenVerifier` 的 `IPhase.phaseInfo(round + 2)`；来源 `IPhase`。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。`onProposalVoted` 的 `targetData.length == 0 || == 1` 提前返回不计站点（不改状态、不回滚）。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GAV-01 | Low | 已裁决（W1 #4）：`VerifierAlreadyLocked` → `RoundVerifierLocked(tokenAddress, actionId, round, lockedVerifierId)`；1 站点 1 接口；测试与规格 07/05 同步。 |
| E-GAV-02 | Low | 已裁决（X-04 重排）：`_checkApplicationSubmission` 改为轮次 → 参数 → 存在性 → 资格；新增 `testApplicationChecksDescriptionBeforeActionExistence`；05 叙述与权限卷 `GAV-01` 标「已由错误卷重排」。 |
| E-GAV-03 | Info | 已裁决（实现口径，未改顺序）：`_submitOriginScores` 的逐元素分数检查本来就在批次参数之后、轮次/锁定者与完成态检查之前；锁定后提交越界分数的断言 `ScoreLimitExceeded(0, 101, 100)` 保留。 |
| E-GAV-04 | Info | 已裁决（文档口径）：`ScoreCountExceeded` 第三字段 `memberCount` → `maxCount`，selector 不变；规格 07/05 同步。 |
| E-GAV-05 | Info | 已裁决（X-09 文档）：05 登记零票仍须有申请、无申请回滚整个 `vote()`。 |
