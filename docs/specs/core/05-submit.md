# Submit

Submit 管理 Proposal 的创建与当前治理 Round 的推举：`submitNewProposal` 在创建后立即推举，`submit` 单独推举已有 Proposal。Proposal 规则与权限见 [通用规则](01-common-rules.md)，Round 边界见 [Phase](03-phase.md#治理-round)。投票由 [Vote](06-vote.md) 独立管理。

## Proposal

Proposal 以 `tokenAddress + proposalId` 定位，ID 每社区单调分配、从 `1` 开始。`proposalId == 0` 无效，对未分配 ID 的访问回滚 `ProposalNotFound`。

Submit 不校验 `tokenAddress` 是否登记为 LOVE20 代币；推举门槛由 Stake 票数自然兜底。

Proposal 由合约分配的头部与创建者提供的主体组成，对外以 `ProposalInfo { ProposalHead head, ProposalBody body }` 读出。

| 数据 | 内容 |
| --- | --- |
| `ProposalHead` | `id`、`author`（创建者 `memberId`）、`createAtBlock`，全部由合约分配 |
| `ProposalBody` | 创建者提供的全部字段，见下 |

`ProposalBody`：

| 字段 | 内容 |
| --- | --- |
| `title` | 非空标题 |
| `details` | 可空正文 |
| `target` | 非零激励接收地址 |
| `targetMode` | `NoCallback` 或 `Callback` |
| `targetData` | 可选的不透明 Target Data 数组，可以为空 |

`ProposalBody` 既是 `submitNewProposal` 的入参，也是 `ProposalInfo` 的组成部分；两者同名同字段，不设第二套参数结构。

| target | NoCallback | Callback |
| --- | --- | --- |
| 非零 EOA | 合法，不回调 | 拒绝 |
| 非零合约 | 合法，不回调 | 创建、推举、投票都回调，空 Target Data 也回调 |
| 零地址 | 拒绝 | 拒绝 |

显式销毁可由专用 Target 合约接收后执行，不能用零 Target 隐式销毁。

结构体见 [`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)。

`submitNewProposal` 在一笔交易内完成「创建 + 推举」两步：先保存 Proposal 并触发创建回调，紧接着把它推举进当前 Round。调用者须持有 `memberId` 且满足 `canSubmit`，并因此消耗本 Round 的推举名额。创建后内容和 Target 不变，重名标题不等于重复 Proposal。

`NoCallback` 忽略 `targetData`，不要求为空；`Callback` 允许 `targetData` 为空，并在回调时原样透传。Target Data 的业务编码由 Target 自行定义。

## 接口

完整 ABI 见 [`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)。它沿用旧 `LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol` 的 Proposal 创建、推举、枚举和查询职责；旧接口中的行动专属字段已按 BSC 规则移出命名结构，改由不透明的 Target Data 经 `ProposalBody.targetData` 传递，业务主体由地址改为 `memberId`。

两个写入口沿用旧接口的动词配对与语义，`submitNewProposal` 就是「提交一个新提案」：创建与推举在同一笔内完成。`submit` 不创建，只把已有 `proposalId` 推举进当前 Round。Proposal 一经创建即长期存在，可在后续每个 Round 各被推举一次，推举者可以是作者以外的人。

读取面分三类，职责不重叠：

| 类 | 函数 | 用途 |
| --- | --- | --- |
| 分页 | `proposalIds`、`proposalIdsByAuthor`、`submitInfos` | 按 `(offset, limit, reverse)` 遍历集合，返回当页与集合真实总数 |
| 按 id 批量取详情 | `proposalInfosByIds` | 按显式 ID 数组批量读，返回数组与入参下标一一对应 |
| 单键 | `isSubmitted`、`proposalIdBySubmitter`、`submitterIdByProposalId` | 按键取布尔或单个标量 |

命名记号三条：**数组返回值在名字里体现载荷**——`Ids` 表示只回轻量标识，`Infos` 表示回记录本体，裸集合名不用于返回数组的函数，标量返回值不加后缀（`isSubmitted`、`proposalIdBySubmitter`、`submitterIdByProposalId`、`currentRound`）。**筛选条件进名字**——默认形态（集合全量）不加标记，按键筛选用 `By<key>`，显式 ID 数组用 `ByIds`，可串联成 `By<key>ByIds`。**是否分页不进名字**——分页由入参 `(offset, limit, reverse)` 决定，不为同一集合另设无窗口的全量重载。

分页函数的返回值形态随集合成员而定：`proposalIds`/`proposalIdsByAuthor` 只回 `proposalId`，`submitInfos` 回完整记录。判据是**页内每一项是否定长**——只有定长才能保证任意一页的体量与 `limit` 成正比（见 [分页查询](#分页查询)）。

上表三条单键查询：`isSubmitted(tokenAddress, round, proposalId)` 判某提案本轮是否已被推举；`proposalIdBySubmitter(tokenAddress, round, submitterId)` 与 `submitterIdByProposalId(tokenAddress, round, proposalId)` 是同一份推举记录的两个方向。每个成员每轮最多推举一个提案、每个提案每轮最多被推举一次，两种键在 `(tokenAddress, round)` 下**都是唯一键**，故两条都回标量，`0` 表示「本轮未推举」（`0` 既不是合法 `memberId` 也不是合法 `proposalId`，无需回滚）。三条并存不构成重复：**存在性判定与取值是两个不同的值**，`isSubmitted` 的 `bool` 不覆盖另外两条的返回，正如 `IMemberNFT.isNameUsed` 与 `idOf` 同键并存。

## 分页查询

三个分页查询都按 `(offset, limit, reverse)` 分页，并同时返回集合的真实总数；语义与 `Phase.syncObservations` 一致：`offset` 大于或等于总数时返回空数组与真实 `totalCount`，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时按从新到旧返回。不提供全量遍历，也不提供单独的计数入口——只取总数时传 `limit = 0`。

| 查询 | 作用域 | 返回 |
| --- | --- | --- |
| `proposalIds(tokenAddress, offset, limit, reverse)` | 某社区的全部 Proposal，按创建顺序 | `(proposalIdList, totalCount)` |
| `proposalIdsByAuthor(tokenAddress, author, offset, limit, reverse)` | 某成员创建的 Proposal，按创建顺序 | `(proposalIdList, totalCount)` |
| `submitInfos(tokenAddress, round, offset, limit, reverse)` | 某社区某 Round 的推举记录，按推举顺序 | `(submitInfoList, totalCount)` |

前两个只回 `proposalId`，详情走 [`proposalInfosByIds`](#按-id-批量取详情)。`submitInfos` 的每条记录含 `submitterId` 与 `proposalId`，「本轮推举了哪些提案」与「谁推举了哪个提案」由同一条读路径给出，不再拆成两个入口。某 Round 尚无推举或尚未开始时，`submitInfos` 返回空数组与 `0`，不回滚。

**分页只回定长数据**：页内成员由别人决定，`ProposalBody` 的 `title`/`details`/`targetData` 都不设长度上限，一旦分页回本体，某条大 `targetData` 的 Proposal 就能把包含它的整页顶到调用方 gas 上限之上，而且跳不过去——只能反复调小 `limit` 试探。需要详情时走 [按 id 批量取详情](#按-id-批量取详情)。`SubmitInfo` 全为 `uint256` 字段，分页回记录不触这条红线。

分页与批量查询都不校验 `tokenAddress` 是否已登记，也不校验 `memberId` 是否存在，与 [Proposal](#proposal) 一节的口径一致。

## 按 id 批量取详情

`proposalInfosByIds(tokenAddress, proposalIds[])` 返回的数组与入参下标一一对应，调用方据此把详情拼回 [`proposalIds`/`proposalIdsByAuthor`](#分页查询) 给出的顺序。

**入参数组不设上限**：它是只读、无状态写的批量查询，批量大小与由此产生的返回体量都由调用方自己选择，超限表现为调用方自己的 out-of-gas 回滚（减小批量即可重试），不会把代价转嫁给别人。这与 [复查清单](../../review-guide.md) 的「数组、批量参数和分页参数有最大边界」并不冲突——该条约束的是合约替调用者执行、且会写入状态的批量。

未分配过的 ID 回滚 `ProposalNotFound(proposalId)`，不静默补空：位置对齐是批量查询的语义基础，补空会让调用方无法判断缺失的是哪一项。空数组入参返回空数组。单条读传单元素数组，不另设单条详情入口。

`submitInfos` 分页与两条方向单键（`proposalIdBySubmitter`、`submitterIdByProposalId`）的分工：分页是集合的完整读取路径，两条单键是它在两把唯一键上的定点通道，三者读到的是同一份推举记录，不各自维护状态。

## 推举

推举门槛沿用旧 Submit：从 Stake 读取当前成员 `validGovVotes(tokenAddress, memberId)` 与社区 `globalGovVotes(tokenAddress)`；成员和社区票数均为正，且 `floor(validGovVotes * 1000 / globalGovVotes) >= SUBMIT_MIN_PER_THOUSAND`。初始化门槛范围为 `1..1000`。

`canSubmit` 实现：先判 `globalGovVotes(tokenAddress) == 0` 返回 `false`，再判 `validGovVotes(tokenAddress, memberId) == 0` 返回 `false`，最后计算千分比，避免除零 panic。

调用者必须持有 `memberId`。每个成员每社区每 Round 最多推举一个 Proposal，同一 Proposal 同轮只能被推举一次；两个入口共用这两条约束——`submitNewProposal` 在创建后立即推举，因此同样占用本 Round 的名额，创建不是免额度的旁路。每社区每轮首个成功推举自动调用 `Phase.sync()`；`sync` 已同步时无操作返回、不会回滚，但若失败则按外部调用失败处理，整笔交易回滚。`submit` 推举已有 Proposal 不重复触发创建回调。

## 校验顺序

`submitNewProposal` 的创建段与推举段在同一笔内依次执行，任一步回滚整笔：

1. **参数校验**：`title` 非空（`EmptyString("title")`）、`target` 非零（`InvalidAddress()`）、`targetMode` 合法（枚举范围内且 `Callback` 时 `target.code.length > 0`，否则 `InvalidTargetMode()`）
2. **存在性**：`memberId` 存在（`IMemberNFT.ownerOf` 不回滚）
3. **持有权**：`ownerOf(memberId) == msg.sender`（`NotMemberOwner(memberId)`）
4. **门槛**：`canSubmit(tokenAddress, memberId)`（`CannotSubmitAction()`）
5. **本轮名额**：同一成员同社区同 Round 尚未推举过（`OnlyOneSubmitPerRound()`）
6. 分配 `proposalId`，写入 `ProposalInfo` 与作者索引
7. 发出 `ProposalCreated` 事件
8. `Callback` 时回调 `IProposalTarget.onProposalCreated`
9. 写入三处推举状态：推举记录列表（供 `submitInfos`）、按 `proposalId` 的推举者（供 `isSubmitted` 与 `submitterIdByProposalId`）、按 `submitterId` 的反查（供 `proposalIdBySubmitter`）
10. 发出 `ProposalSubmitted` 事件
11. 本社区本轮首笔推举时调用 `Phase.sync()`
12. `Callback` 时回调 `IProposalTarget.onProposalSubmitted`

`submitNewProposal` 不会命中 `AlreadySubmitted()`：`proposalId` 在本笔内新分配，此前不存在任何推举记录，该判定只对 `submit` 可达。

`submit` 校验顺序：

1. **参数校验**：无显式参数校验
2. **存在性**：`proposalId` 存在（`ProposalNotFound(proposalId)`）、`memberId` 存在
3. **持有权**：`ownerOf(memberId) == msg.sender`（`NotMemberOwner(memberId)`）
4. **门槛**：`canSubmit(tokenAddress, memberId)`（`CannotSubmitAction()`）
5. **去重**：先判同一 Proposal 同轮是否已推举（`AlreadySubmitted()`）、再判同一成员同社区同轮是否已推举其他 Proposal（`OnlyOneSubmitPerRound()`）
6. 写入三处状态：推举记录列表、按 `proposalId` 的推举者、按 `submitterId` 的反查
7. 发出 `ProposalSubmitted` 事件
8. 本社区本轮首笔推举时调用 `Phase.sync()`
9. `Callback` 时回调 `IProposalTarget.onProposalSubmitted`

初始化校验：`phaseAddress`、`stakeAddress`、`memberNFTAddress` 非零（`InvalidAddress()`）；`submitMinPerThousand` 在 `1..1000` 范围（`ZeroAmount("submitMinPerThousand")` / `InvalidAmount()`）。

## 事件与错误

事件与错误定义见 [`ISubmit.sol`](../../../interfaces/core/ISubmit.sol)。

`ProposalCreated` 由 `submitNewProposal` 的创建段发出，包含 `author`（创建者 `memberId`）、`title`、`details`、`target`、`targetMode`；不含 `round`、不含 `targetData`。

`ProposalSubmitted` 由推举段发出，`submitNewProposal` 与 `submit` 各发一次，包含 `round`（= `currentRound()`）、`submitterId`、`proposalId`。走 `submitNewProposal` 时同一笔内先 `ProposalCreated`、后 `ProposalSubmitted`。

`targetData` 无法从事件重建，需按 id 批量回读 `proposalInfosByIds(tokenAddress, [proposalId])`。

错误：

| 错误 | 触发条件 |
| --- | --- |
| `AlreadyInitialized()` | 重复初始化 |
| `InvalidAddress()` | `init` 的任一地址为零；`submitNewProposal` 的 `target` 为零 |
| `InvalidTargetMode()` | `targetMode` 枚举越界，或 `Callback` 且 `target.code.length == 0` |
| `NotMemberOwner(uint256 memberId)` | `ownerOf(memberId) != msg.sender` |
| `EmptyString(string parameter)` | `title` 为空 |
| `ZeroAmount(string parameter)` | `init` 的 `submitMinPerThousand == 0` |
| `InvalidAmount()` | `init` 的 `submitMinPerThousand > 1000` |
| `RoundNotStarted()` | `currentRound() == 0`（Phase 尚未开始；当前不强制校验，由业务决定是否允许 Phase 0 创建与推举） |
| `ProposalNotFound(uint256 proposalId)` | `proposalInfosByIds` 传入未分配过的 ID；`submit` 的 `proposalId` 不存在 |
| `CannotSubmitAction()` | 门槛或资格不足（创建段与推举段共用） |
| `AlreadySubmitted()` | `submit` 中同一 Proposal 同轮重复推举 |
| `OnlyOneSubmitPerRound()` | 同一成员同社区同轮已推举过（两个入口共用） |

沿用旧 Submit 的三个专用 selector：`CannotSubmitAction`、`AlreadySubmitted`、`OnlyOneSubmitPerRound`。

## Target 回调

回调接口见 [`IProposalTarget.sol`](../../../interfaces/core/IProposalTarget.sol)。

创建和推举分别触发对应回调。创建与推举在同一笔交易内完成时，固定先 `onProposalCreated`、再 `onProposalSubmitted`，任一回调失败都回滚整笔。回调不要求 Target Data 非空；空 `targetData` 仍必须调用回调并传递空数组。创建回调仅接受 Submit；Executor 仅接受 ActionTarget 转发。回调前先写入对应 Proposal 或推举状态，失败则一并回滚。

验收见 [Core 验收](09-testing.md)。
