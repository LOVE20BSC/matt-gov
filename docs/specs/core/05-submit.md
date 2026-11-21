# Submit

Submit 管理 Proposal 的创建与当前治理 Round 的推举：`submitNewProposal` 在创建后立即推举，`submit` 单独推举已有 Proposal。Proposal 规则与权限见 [通用规则](01-common-rules.md)，Round 边界见 [Phase](03-phase.md#治理-round)。投票由 [Vote](06-vote.md) 独立管理。

## Proposal

Proposal 以 `tokenAddress + proposalId` 定位，ID 每社区单调分配、从 `1` 开始。`proposalId == 0` 无效，对未分配 ID 的访问回滚 `ProposalNotFound(tokenAddress, proposalId)`。

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
| `creationData` | 提案创建时提供的一段 `bytes`，可以传 `0x` |

`ProposalBody` 既是 `submitNewProposal` 的入参，也是 `ProposalInfo` 的组成部分；两者同名同字段，不设第二套参数结构。

| target | NoCallback | Callback |
| --- | --- | --- |
| 非零 EOA | 合法，不回调 | 拒绝 |
| 非零合约 | 合法，不回调 | 创建、推举、投票都回调，数据为空时也回调 |
| 零地址 | 拒绝 | 拒绝 |

显式销毁可由专用 Target 合约接收后执行，不能用零 Target 隐式销毁。

`target` 同时是提案激励的唯一铸造主体：`Mint.mintProposalReward` 只接受该地址调用，铸造规则见 [Mint 的 Proposal 结算](07-mint.md#proposal-结算)。`Callback` 模式要求它是合约，`NoCallback` 模式允许 EOA。

结构体见 [`ISubmit.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ISubmit.sol)。

`submitNewProposal` 在一笔交易内完成「创建 + 推举」两步：先保存 Proposal，再写入当前 Round 的推举状态，最后执行创建与推举回调。调用者须持有 `memberId` 且满足 `canSubmit`，并因此消耗本 Round 的推举名额；回调执行时 Proposal 与推举状态都已完整写入，不能通过融合转出来源质押。创建后内容和 Target 不变，重名标题不等于重复 Proposal。

`creationData` 随提案正文保存。`submitData` 由本次推举者提供，可以每轮传不同的内容。`Callback` 模式下，创建回调收到 `creationData`，推举回调收到 `submitData`。两者的业务编码均由 Target 定义，无附加数据时传 `0x`。

## 接口

`submitNewProposal` 接收含 `creationData` 的 `ProposalBody`，并另收本次 `submitData`。已有提案的 `submit` 接收 `proposalId` 和本次 `submitData`。完整 ABI 见 [`ISubmit.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ISubmit.sol)。

两个写入口沿用旧接口的动词配对与语义，`submitNewProposal` 就是「提交一个新提案」：创建与推举在同一笔内完成。`submit` 不创建，只把已有 `proposalId` 推举进当前 Round；两个入口都在回调前完成推举状态写入。Proposal 一经创建即长期存在，可在后续每个 Round 各被推举一次，推举者可以是作者以外的人。

读取面分三类，职责不重叠：

| 类 | 函数 | 用途 |
| --- | --- | --- |
| 分页 | `proposalIds`、`proposalIdsByAuthor`、`submitInfos` 及对应的 `ByTarget` 查询 | 按 `(offset, limit, reverse)` 遍历集合，返回当页与集合真实总数 |
| 按 id 批量取详情 | `proposalInfosByProposalIds` | 按显式 ID 数组批量读，返回数组与入参下标一一对应 |
| 单键 | `isSubmitted`、`proposalIdBySubmitterId`、`submitterIdByProposalId` | 按键取布尔或单个标量 |

命名记号三条：**数组返回值在名字里体现载荷**——`Ids` 表示只回轻量标识，`Infos` 表示回记录本体，裸集合名不用于返回数组的函数，标量返回值不加后缀（`isSubmitted`、`proposalIdBySubmitterId`、`submitterIdByProposalId`、`currentRound`）。**筛选条件进名字**——默认形态（集合全量）不加标记，按键筛选用 `By<key>`，显式 ID 数组用 `By<Key>Ids`，多键串联时 id 数组的那把键带 `Ids`（`voteAmountsByMemberIdByProposalIds`）。**是否分页不进名字**——分页由入参 `(offset, limit, reverse)` 决定，不为同一集合另设无窗口的全量重载。

提案分页只返回 `proposalId`，推举分页返回定长的 `SubmitInfo`。两类列表的页内数据量都随 `limit` 成正比（见 [分页查询](#分页查询)）。

上表三条单键查询：`isSubmitted(tokenAddress, round, proposalId)` 判某提案本轮是否已被推举；`proposalIdBySubmitterId(tokenAddress, round, submitterId)` 与 `submitterIdByProposalId(tokenAddress, round, proposalId)` 是同一份推举记录的两个方向。每个成员每轮最多推举一个提案、每个提案每轮最多被推举一次，两种键在 `(tokenAddress, round)` 下**都是唯一键**，故两条都回标量，`0` 表示「本轮未推举」（`0` 既不是合法 `memberId` 也不是合法 `proposalId`，无需回滚）。三条并存不构成重复：**存在性判定与取值是两个不同的值**，`isSubmitted` 的 `bool` 不覆盖另外两条的返回，正如 `IMemberNFT.isNameUsed` 与 `memberId(name)` 同键并存。

## 分页查询

分页查询都按 `(offset, limit, reverse)` 分页，并同时返回集合的真实总数；语义与 `Phase.observations` 一致：`offset` 大于或等于总数时返回空数组与真实 `totalCount`，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时按从新到旧返回。不提供全量遍历，也不提供单独的计数入口——只取总数时传 `limit = 0`。

| 查询 | 作用域 | 返回 |
| --- | --- | --- |
| `proposalIds(tokenAddress, offset, limit, reverse)` | 某社区的全部 Proposal，按创建顺序 | `(proposalIdList, totalCount)` |
| `proposalIdsByTarget` | 某社区指向指定 Target 的 Proposal，按创建顺序 | `(proposalIdList, totalCount)` |
| `proposalIdsByAuthor(tokenAddress, author, offset, limit, reverse)` | 某成员创建的 Proposal，按创建顺序 | `(proposalIdList, totalCount)` |
| `proposalIdsByAuthorByTarget` | 某成员创建且指向指定 Target 的 Proposal，按创建顺序 | `(proposalIdList, totalCount)` |
| `submitInfos(tokenAddress, round, offset, limit, reverse)` | 某社区某 Round 的推举记录，按推举顺序 | `(submitInfoList, totalCount)` |
| `submitInfosByTarget` | 某社区某 Round 内指向指定 Target 的提案推举记录，按推举顺序 | `(submitInfoList, totalCount)` |

提案详情可通过 [`proposalInfosByProposalIds`](#按-id-批量取详情) 按 ID 读取。每条推举记录含 `submitterId` 与 `proposalId`。某个 Round 尚无推举时，推举分页返回空数组与总数 `0`。

`ByTarget` 按 Proposal 创建时保存的 Target 地址匹配，两种 Target Mode 均可命中。筛选后的集合决定总数和分页范围。未知 Target 或没有匹配记录时返回空数组与总数 `0`。

分页返回定长数据。`ProposalBody` 的 `title` 和 `details` 各可达 1024 字节，`creationData` 可达 16 KiB。把它们放进分页会让单页成本随内容体量变化。调用方可以按需 [按 id 批量取详情](#按-id-批量取详情)。

分页与批量查询都不校验 `tokenAddress` 是否已登记，也不校验 `memberId` 是否存在，与 [Proposal](#proposal) 一节的口径一致。

## 按 id 批量取详情

`proposalInfosByProposalIds(tokenAddress, requestedProposalIds)` 返回的数组与入参下标一一对应，调用方据此把详情拼回[提案分页](#分页查询)给出的顺序。

**入参数组不设上限**：它是只读、无状态写的批量查询，批量大小与由此产生的返回体量都由调用方自己选择，超限表现为调用方自己的 out-of-gas 回滚（减小批量即可重试），不会把代价转嫁给别人。这与 [复查清单](../../review-guide.md) 的「数组、批量参数和分页参数有最大边界」并不冲突——该条约束的是合约替调用者执行、且会写入状态的批量。

未分配过的 ID 回滚 `ProposalNotFound(tokenAddress, proposalId)`，不静默补空：位置对齐是批量查询的语义基础，补空会让调用方无法判断缺失的是哪一项。空数组入参返回空数组。单条读传单元素数组，不另设单条详情入口。

`submitInfos` 分页与两条方向单键（`proposalIdBySubmitterId`、`submitterIdByProposalId`）的分工：分页是集合的完整读取路径，两条单键是它在两把唯一键上的定点通道，三者读到的是同一份推举记录，不各自维护状态。

`proposalTarget(tokenAddress, proposalId)` 返回该 Proposal 的 `target` 与 `targetMode`，未分配过的 ID 回滚 `ProposalNotFound(tokenAddress, proposalId)`。Vote 只需这两个字段即可判断是否回调，读取成本与正文大小无关。

## 推举

推举门槛沿用旧 Submit：从 Stake 读取当前成员 `govVotes(tokenAddress, currentRound, memberId)` 与社区 `totalGovVotes(tokenAddress, currentRound)`；成员和社区治理权均为正，且 `govVotes >= ceil(totalGovVotes * SUBMIT_MIN_RATIO / 1e18)`。部署门槛范围为 `1..1e18`（`1e18` 表示 100%）。

`canSubmit` 实现：`Math.mulDiv` 按全精度计算 `requiredVotes = ceil(totalGovVotes * SUBMIT_MIN_RATIO / 1e18)`，`requiredVotes == 0`（社区总治理权为零）或 `govVotes < requiredVotes` 时返回 `false`，否则返回 `true`；`Ceil` 保证门槛不被截断，全精度乘法避免大票数溢出。它只判断票权门槛，不判断本轮成员名额、提案去重或社区推举总数。两个写入口复用同一组读数：社区总治理权为零时回滚 `NoGovVotes(tokenAddress)`，否则票权不足回滚 `InsufficientSubmitPower(tokenAddress, memberId, validVotes, requiredVotes)`。

调用者必须持有 `memberId`。每个成员每社区每 Round 最多推举一个 Proposal，同一 Proposal 同轮只能被推举一次；两个入口共用这两条约束——`submitNewProposal` 在创建后立即推举，因此同样占用本 Round 的名额，创建不是免额度的旁路。每社区每轮首个成功推举自动调用 `Phase.sync()`；`sync` 已同步时无操作返回、不会回滚，但若失败则按外部调用失败处理，整笔交易回滚。`submit` 推举已有 Proposal 不重复触发创建回调。

每社区每 Round 最多推举 **1,000 个 Proposal**，两个入口在共同推举路径中按已成功推举的记录数检查；达到上限后回滚 `SubmitRoundFull(tokenAddress, round, 1000)`，新 Proposal 的创建及作者索引也一并回滚。上限固定，不增加部署参数；新一轮、其他社区独立计数，历史累计 Proposal 数不受此限制。名额先到先得，已有推举仍可投票和铸造激励。该限制使 Mint 的单轮有票 Proposal 扫描最多 1,000 项，不限制调用者自行选择的多轮批量铸造大小。

## 校验顺序

两个入口都先完成鉴权（`memberId` 存在且调用者为当前持有人），再按下列顺序校验；非持有人只拿到鉴权错误。两者都遵循「鉴权 → 参数/存在性 → 门槛/资格 → 本轮名额 → 账本写入 → 事件 → 外部调用」的分层（见 [错误与回滚标准](../../error-standards.md#五失败契约)），本轮名额判定必须在任何创建或推举写入之前。

`submitNewProposal` 的创建段与推举段在同一笔内依次执行，任一步回滚整笔。按下列顺序校验：

1. **鉴权**：`memberId` 存在且 `ownerOf(memberId) == msg.sender`（鉴权 modifier；不存在由 MemberNFT 回滚，非持有人回滚 `NotMemberOwner(memberId)`）
2. **参数校验**：先校验 `title` 非空与 `title`、`details`、`creationData` 的字节上限，再校验 `target` 非零且 `Callback` 模式下有合约代码
3. **门槛**：社区总治理权为零回 `NoGovVotes(tokenAddress)`；否则 `canSubmit(tokenAddress, memberId)`（`InsufficientSubmitPower(tokenAddress, memberId, validVotes, requiredVotes)`）
4. **本轮名额**：同一成员同社区同 Round 尚未推举过（`MemberAlreadySubmitted(tokenAddress, round, memberId)`），且社区本 Round 已推举数小于 1,000（`SubmitRoundFull(tokenAddress, round, 1000)`）
5. 分配 `proposalId`，写入 `ProposalInfo` 以及按作者、按 Target、按作者和 Target 联合查询的索引
6. 发出 `ProposalCreated` 事件
7. 写入全轮及按 Target 的推举记录列表、按 `proposalId` 取推举者的映射、按 `submitterId` 取 Proposal 的映射
8. 发出 `ProposalSubmitted` 事件
9. 本社区本轮首笔推举时调用 `Phase.sync()`
10. `Callback` 时回调 `IProposalTarget.onProposalCreated`
11. `Callback` 时回调 `IProposalTarget.onProposalSubmitted`

`submitNewProposal` 不会命中 `ProposalAlreadySubmitted(tokenAddress, round, proposalId)`：`proposalId` 在本笔内新分配，此前不存在任何推举记录，该判定只对 `submit` 可达。

`submit` 校验顺序：

1. **鉴权**：`memberId` 存在且 `ownerOf(memberId) == msg.sender`（鉴权 modifier）
2. **存在性**：`proposalId` 存在（`ProposalNotFound(tokenAddress, proposalId)`）
3. **门槛**：社区总治理权为零回 `NoGovVotes(tokenAddress)`；否则 `canSubmit(tokenAddress, memberId)`（`InsufficientSubmitPower(tokenAddress, memberId, validVotes, requiredVotes)`）
4. **提案去重**：同一 Proposal 同轮尚未推举（`ProposalAlreadySubmitted(tokenAddress, round, proposalId)`）
5. **本轮名额**：同一成员同社区同 Round 尚未推举其他 Proposal（`MemberAlreadySubmitted(tokenAddress, round, memberId)`），且社区本 Round 已推举数小于 1,000（`SubmitRoundFull(tokenAddress, round, 1000)`）
6. 写入全轮及按 Target 的推举记录列表、按 `proposalId` 取推举者的映射、按 `submitterId` 取 Proposal 的映射
7. 发出 `ProposalSubmitted` 事件
8. 本社区本轮首笔推举时调用 `Phase.sync()`
9. `Callback` 时回调 `IProposalTarget.onProposalSubmitted`

构造函数校验：`0 < submitMinRatio <= 1e18` 由 DeployCore 广播前校验，`PHASE_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS` 有代码由 DeployCore 部署后校验；两者均由 21_check 独立复核；构造函数只保存入参，不做静态校验。

## 事件与错误

事件与错误定义见 [`ISubmit.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/ISubmit.sol)。

`ProposalCreated` 由 `submitNewProposal` 的创建段发出，记录提案编号、作者 `authorId`（创建者的 `memberId`）和完整正文。索引器可从中读出 `creationData`。

`title` 和 `details` 的上限各为 1024 字节，`creationData` 的上限为 16 KiB。创建日志体量随这三个字段增长。

`ProposalSubmitted` 由推举段发出，记录推举记账所用的 `round`、`submitterId` 和 `proposalId`。`submitData` 只用于本次回调。走 `submitNewProposal` 时同一笔内先 `ProposalCreated`、后 `ProposalSubmitted`。

错误：

| 错误 | 触发条件 |
| --- | --- |
| `TitleEmpty()` | `title` 为空 |
| `TitleTooLong(uint256 length, uint256 maxLength)` | `title` 字节数超过 `MAX_TITLE_LENGTH`（1024） |
| `DetailsTooLong(uint256 length, uint256 maxLength)` | `details` 字节数超过 `MAX_DETAILS_LENGTH`（1024） |
| `CreationDataTooLarge` | `creationData` 字节数超过 `MAX_CREATION_DATA_BYTES`（16 KiB） |
| `ZeroTargetAddress()` | `submitNewProposal` 的 `target` 为零 |
| `CallbackTargetNotContract(address target)` | `targetMode == Callback` 且 `target.code.length == 0` |
| `NotMemberOwner(uint256 memberId)` | `ownerOf(memberId) != msg.sender`；`memberId` 不存在时由 MemberNFT 回滚 `ERC721NonexistentToken` |
| `ProposalNotFound(address tokenAddress, uint256 proposalId)` | `proposalInfosByProposalIds` 传入未分配过的 ID；`submit` 的 `proposalId` 不存在 |
| `NoGovVotes(address tokenAddress)` | 社区总治理权为零，无法计算推举门槛；两个入口共用 |
| `InsufficientSubmitPower(address tokenAddress, uint256 memberId, uint256 validVotes, uint256 requiredVotes)` | 社区总治理权非零但成员治理权不足；`requiredVotes` 为 `ceil(totalGovVotes * SUBMIT_MIN_RATIO / 1e18)`；两个入口共用 |
| `SubmitRoundFull(address tokenAddress, uint256 round, uint256 limit)` | 本社区本 Round 已推举数达到 `limit`（1,000）；两个入口共用 |
| `ProposalAlreadySubmitted(address tokenAddress, uint256 round, uint256 proposalId)` | `submit` 中同一 Proposal 同轮重复推举 |
| `MemberAlreadySubmitted(address tokenAddress, uint256 round, uint256 memberId)` | 同一成员同社区同轮已推举过；两个入口共用 |

## Target 回调

回调接口见 [`IProposalTarget.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IProposalTarget.sol)。

创建与推举在同一笔交易内完成时，先写提案和推举账本，再依次调用 `onProposalCreated` 和 `onProposalSubmitted`。推举回调的 `round` 与该笔推举记录一致。`Callback` 模式即使数据为 `0x` 也调用对应回调。任一回调失败都回滚整笔。

验收见 [Core 验收](09-testing.md)。
