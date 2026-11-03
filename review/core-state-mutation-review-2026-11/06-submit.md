# Submit · 状态变量变更审查

> `core/src/Submit.sol`，339 行，`core@6fdd0f1`。
> Proposal 一经创建即长期存在，可按轮重复推举；「每成员每轮一个、每提案每轮一个、每社区每轮 1000 个」三条约束全靠本合约的三本账表达。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `SUBMIT_ROUND_LIMIT` | `uint256 constant = 1000` | 每社区每轮推举上限 | 编译期 |
| 2-5 | `MAX_TITLE_LENGTH` / `MAX_DETAILS_LENGTH` / `MAX_TARGET_DATA_BYTES` / `MAX_TARGET_DATA_COUNT` | `constant` | 动态字段上限 | 编译期 |
| 6 | `initialized` | `bool` | 一次性开关 | `init:58` |
| 7-9 | `PHASE_ADDRESS` / `STAKE_ADDRESS` / `MEMBER_NFT_ADDRESS` | `address` | 依赖 | `init:59-61` |
| 10 | `SUBMIT_MIN_RATIO` | `uint256` | 推举门槛占比（1e18 = 100%） | `init:62` |
| 11 | `_proposals` | `mapping(address => ProposalInfo[])` | 每社区全部 Proposal，**下标 0 ↔ `proposalId` 1** | `_createProposal:253` |
| 12 | `_proposalIdsByAuthor` | `mapping(address => mapping(uint256 => uint256[]))` | 作者 → 提案 ID 列表 | `_createProposal:254` |
| 13 | `_submits` | `mapping(address => mapping(uint256 => SubmitInfo[]))` | 每社区每轮的推举记录（分页用） | `_submitByProposalId:301` |
| 14 | `_submitInfoByProposalId` | `mapping(address => mapping(uint256 => mapping(uint256 => SubmitInfo)))` | 提案 → 推举记录（`isSubmitted` 用） | `:302-304` |
| 15 | `_submitInfoBySubmitterId` | `mapping(address => mapping(uint256 => mapping(uint256 => SubmitInfo)))` | 成员 → 推举记录（反查用） | `:305-307` |

`SubmitInfo` 的字段顺序是 `(submitterId, proposalId)`（`ISubmit.sol:25-28`），三处写入都用位置构造 `SubmitInfo(memberId, proposalId)`（`:296-299`），字段没有错位。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:49-63`）

| 位置 | 语句 | 守卫 |
| --- | --- | --- |
| `:55-57` | `if (initialized) revert; initialized = true` | — |
| `:59-62` | 3 个地址 + 1 个比例 | 无零地址/代码/范围校验（部署脚本负责） |

`SUBMIT_MIN_RATIO` 是**唯一影响写权限的参数**：`0` 会让 `requiredVotes` 恒为 0，`_meetsSubmitPower` 恒 false（`:84-86`），于是**任何人都无法推举**；`> 1e18` 会让门槛超过总票权，效果相同。它只在 `init` 写一次，没有 setter。

### 2.2 `_createProposal`：两本账 + 一个事件（`:241-268`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:246` | `proposalId = _proposals[token].length + 1` | **ID 由长度现算**，不存计数器；因此「ID 连续无空洞」是结构性成立的 |
| 2 | `:247-251` | 组 `ProposalHead{id, author, createAtBlock}` | `author = memberId`，`createAtBlock = block.number` |
| 3 | `:253` | `_proposals[token].push(ProposalInfo{head, body})` | `body` 整体入存储（含 `targetData`） |
| 4 | `:254` | `_proposalIdsByAuthor[token][memberId].push(proposalId)` | 与上一步同笔 |
| 5 | `:256-265` | `ProposalCreated`（含 `targetData` / `title` / `details`） | 日志可重建提案，无需回读 |

`_createProposal` **不做任何校验**：标题/正文/目标/上限都在 `_checkProposalBody`（`:215-239`）里，且在调用它之前完成（`:110`）。因此「写 `_proposals` 时数据已合法」是调用顺序保证的，不是函数自身保证的。

### 2.3 `_submitByProposalId`：三本账（`:277-324`）

| 顺序 | 位置 | 语句 / 判定 | 失败形态 |
| --- | --- | --- | --- |
| 1 | `:282` | `_checkExistingProposal` | `ProposalNotFound(proposalId)` |
| 2 | `:284` | `round = currentRound()` | — |
| 3 | `:285-287` | `isSubmitted(token, round, proposalId)` | `ProposalAlreadySubmitted` |
| 4 | `:288-291` | `_submitInfoBySubmitterId[token][round][memberId].submitterId != 0` | `MemberAlreadySubmitted` |
| 5 | `:292-294` | `_submits[token][round].length >= 1000` | `SubmitRoundFull` |
| 6 | `:296-299` | 构造 `SubmitInfo(memberId, proposalId)` | — |
| 7 | `:301` | `_submits[token][round].push` | — |
| 8 | `:302-304` | `_submitInfoByProposalId[...] = info` | — |
| 9 | `:305-307` | `_submitInfoBySubmitterId[...] = info` | — |
| 10 | `:309` | `isFirstSubmit = _submits[token][round].length == 1`（**push 之后**） | — |
| 11 | `:312-317` | `ProposalSubmitted` | — |
| 12 | `:319-322` | 首个推举 → `IPhase.sync()` | 外部调用，失败整笔回滚 |

三条约束分别落在第 3、4、5 步，**都在任何写入之前**；第 7-9 步是不可分割的同一笔（任一步失败整体回滚），所以「`_submits` 有记录但反查表没有」的中间态不存在。

### 2.4 `submitNewProposal` 与 `submit` 的差异（`:105-130`）

| 步骤 | `submitNewProposal` | `submit` |
| --- | --- | --- |
| 参数校验 | `_checkProposalBody`（`:110`） | 无（提案已存在） |
| 门槛 | `_checkSubmitPower`（`:111`） | `_checkSubmitPower`（`:126`） |
| 存在性 | 不适用（本笔新建） | `_checkExistingProposal`（`:125`） |
| 创建 | `_createProposal`（`:113`） | 无 |
| 推举 | `_submitByProposalId`（`:115`） | `_submitByProposalId`（`:128`） |
| 回调 | `onProposalCreated` → `onProposalSubmitted` | `onProposalSubmitted` |

`submitNewProposal` 的 `ProposalAlreadySubmitted` 分支不可达（`proposalId` 本笔才分配），这是规格 `05-submit.md:120` 明确写过的性质。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| B1 | `_proposals[t].length == n`，合法 ID 恰为 `1..n`，无空洞 | ✅ | ID = `length + 1`，只 push 不删 |
| B2 | `_proposalIdsByAuthor[t][a]` 恰为「`author == a` 的提案 ID」按创建序 | ✅ | 与 `_proposals.push` 同笔、同序 |
| B3 | 每条推举记录在 `_submits`、`_submitInfoByProposalId`、`_submitInfoBySubmitterId` 三处**逐字段一致** | ✅ | 三处写入用同一个 memory 结构体（`:296-307`） |
| B4 | `isSubmitted(t,r,p)` ⟺ `∃` 记录 `(t,r,p,·)` | ✅ | 判据是 `submitterId != 0`，而 `memberId` 从 1 起（`MemberNFT._nextTokenId = 1`） |
| B5 | `submitterIdByProposalId` 与 `proposalIdBySubmitterId` 在同一 `(t,r)` 下互为逆 | ✅ | 同一结构体的两个方向 |
| B6 | 每 `(t,r,member)` 至多 1 条、每 `(t,r,proposal)` 至多 1 条 | ✅ | 第 3、4 步先于写入 |
| B7 | `_submits[t][r].length <= 1000` | ✅ | 第 5 步先于 push |
| B8 | 本轮首个推举恰好触发一次 `Phase.sync()` | ✅ | `isFirstSubmit` 在 push 之后算，且同步本身幂等 |

## 4. 发现

### SUB-01 · 创建段先落账、再判名额；上限常量无 getter

| 字段 | 值 |
| --- | --- |
| 位置 | `:113`（`_createProposal`）、`:285-294`（名额与总数校验在 `_submitByProposalId` 内） |
| 级别 | Info |
| 证据 | E1 |

规格 `05-submit.md:111-114` 的步骤表是「4 判名额 → 5 分配 ID 并写 ProposalInfo → 7 判 1000 上限并写推举状态」，而代码是「分配 ID 并写 ProposalInfo（`:113`）→ 判名额与上限（`:285-294`）→ 写推举状态」。差别只在**回滚前的写入顺序**：`MemberAlreadySubmitted` / `SubmitRoundFull` 命中时，`_proposals` 与 `_proposalIdsByAuthor` 已经被写了一次，然后随整笔回滚撤销。

可观测性上是等价的（事件也被撤销，`_proposals.length` 回退），因此不构成缺陷。列出的原因是：这两条校验是「本轮名额」而不是「提案合法性」，放在创建之后意味着**创建段的 gas 已经花掉**（含 16 KiB `targetData` 的存储与日志），失败时调用者白付。若要省这笔 gas，可把三条唯一性/上限判定（`:285-294`）提到 `_createProposal` 之前；不改 ABI。

另：`SUBMIT_ROUND_LIMIT` 是 `private constant`，没有 getter。链下只能从 `SubmitRoundFull(token, round, 1000)` 的载荷里学到上限，或者在源码里查。建议加 `function SUBMIT_ROUND_LIMIT() external pure returns (uint256)`（新增 selector，非破坏性）。

### SUB-02 · `_submits` 按「轮」分数组，跨轮只增不减

| 字段 | 值 |
| --- | --- |
| 位置 | `:35-36`、`:191`、`:301` |
| 级别 | Info |
| 证据 | E1 |

`_submits[token][round]` 是每轮一个独立数组，上限 1000 只约束**单轮**；跨轮没有任何清理，也没有全局上限。`submitInfos(token, round, …)` 只能按轮分页，链下要枚举「某社区的全部推举」必须逐轮调用。这不是缺陷（提案与推举都是历史记录），但意味着存储单调增长且没有「全量」读路径；链下索引应直接折叠 `ProposalSubmitted` 事件，而不是遍历映射。

## 5. 已核对为正确的点

- 三条唯一性约束（提案、成员、总数）都在写入之前判定，且顺序与规格一致（提案 → 成员 → 总数）。
- `proposalId = length + 1` 与 `_proposals[id - 1]` 的换算在所有读取点一致（`:168`、`:179`、`:327`、`:334`），没有一处用错基准。
- `_checkExistingProposal` 同时挡住 `0` 与 `> length`，所以 `proposalId - 1` 不会下溢。
- `submitInfos` 的分页下标来自 `Pagination.paginateIndices(totalCount, …)`，`offset >= total` 返回空数组而不回滚。
- `_callProposalCreated` / `_callProposalSubmitted` 都在状态写完、事件发完之后执行；回调里再进 `submit` 会被 `ProposalAlreadySubmitted` / `MemberAlreadySubmitted` 挡住。
- `sync()` 失败会整笔回滚，不会留下「推举成功但 Phase 没同步」的状态。

## 6. 覆盖缺口

- 未复核 `ProposalBody` 在 `calldata → memory → storage` 三次拷贝中的 gas 上界（与状态正确性无关）。
- 未测 `SubmitRoundFull` 在 1000 条边界上的 gas（既有审查 `MNT-02` 已记录单轮 1000 提案的扫描成本）。
