# Submit 事件赋值与发射审查

- 实现：`core/src/Submit.sol`（339 行，`6fdd0f1`）
- 声明：`core/src/interfaces/ISubmit.sol`（`ISubmitEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/05-submit.md`
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 2 |
| 发射点 | 2 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 1 |
| 放行 | 可放行；1 项 P3 为跨合约顺序断言 |

`submitNewProposal` = 创建 + 推举，两个事件在同一笔内按「`ProposalCreated` → `ProposalSubmitted` → `Phase.sync` → 创建回调 → 推举回调」固定顺序发出，与 `05-submit.md:106-119` 的步骤表逐条对应。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `ProposalCreated` | `tokenAddress`, `proposalId`, `authorId` | `_createProposal:256` | `_proposals.push:253`、`_proposalIdsByAuthor.push:254` | 本 Round 名额/去重校验、推举写入 |
| `ProposalSubmitted` | `tokenAddress`, `submitterId`, `proposalId`（`round` 非 indexed） | `_submitByProposalId:312` | 三处推举记录 `:301-307` | `isFirstSubmit` 时 `Phase.sync():321`；随后 `onProposalCreated` / `onProposalSubmitted` 回调 |

族归属：`core.proposal`（根键 → round → 对象/actor id 链 → 地址 → 枚举 → bytes → 文本）。

## 2. 逐事件赋值链

### 2.1 `ProposalCreated`

```
event ProposalCreated(
    address indexed tokenAddress,
    uint256 indexed proposalId,
    uint256 indexed authorId,
    address target,
    TargetMode targetMode,
    bytes[] targetData,
    string title,
    string details
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `tokenAddress` `:257` | 根键；Submit 不校验是否已登记（`05-submit.md:9`） |
| `proposalId` | `_proposals[tokenAddress].length + 1` `:246` | 每社区从 1 单调分配；`0` 永不可用 |
| `authorId` | 入参 `memberId` `:259`（同时写入 `ProposalHead.author` `:249` 与作者索引 `:254`） | 创建者，非调用者地址；调用者已由 `onlyMemberOwner:98` 绑定为该 NFT 持有人 |
| `target` | `proposalBody.target` `:260` | `:235` 已拒绝零地址；`Callback` 时 `:236` 已要求有代码 |
| `targetMode` | `proposalBody.targetMode` `:261` | 枚举 |
| `targetData` | `proposalBody.targetData` `:262` | 不透明数组，链上上限 16 KiB / 16 项（`:223-233`） |
| `title` | `proposalBody.title` `:263` | 非空、≤1024 字节（`:216-218`） |
| `details` | `proposalBody.details` `:264` | 可空、≤1024 字节（`:220-221`） |

有意省略两个字段：

- `round`：Proposal 一经创建即长期存在，可在后续任意 Round 被推举；创建不属于任何 Round 的事实（`05-submit.md:139` 明确「不含 `round`」）。
- `createAtBlock`：存储于 `ProposalHead:250`，但 `block.number` 由日志元数据承担（§6.6），不进 payload。

动态字段上限（§6.8）：`title` / `details` 各 1024 字节，`targetData` 16 KiB 且 16 项，全部由 `_checkProposalBody` 在写入前链上强制，属事件契约的一部分（`05-submit.md:141`）。

### 2.2 `ProposalSubmitted`

```
event ProposalSubmitted(
    address indexed tokenAddress,
    uint256 round,
    uint256 indexed submitterId,
    uint256 indexed proposalId
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:314` | 根键 |
| `round` | `round = currentRound()` `:284`（= `Phase.currentPhase()`） | 非 indexed：3 个槽位已被根键、`submitterId`、`proposalId` 占满（§6.3 分配优先级） |
| `submitterId` | 入参 `memberId` `:315` | 推举人；每成员每社区每轮最多 1 个（`:288-291`） |
| `proposalId` | 入参 `:316` | 每 Proposal 每轮最多 1 次（`:285-287`） |

三处写入与三个读取面一一对应（`05-submit.md:114`）：

| 写入 | 行 | 读取面 |
| --- | --- | --- |
| `_submits[token][round].push(submitInfo)` | `:301` | `submitInfos`（分页，保序） |
| `_submitInfoByProposalId[token][round][proposalId]` | `:302-304` | `isSubmitted` / `submitterIdByProposalId` |
| `_submitInfoBySubmitterId[token][round][memberId]` | `:305-307` | `proposalIdBySubmitterId` |

`isFirstSubmit` 在 push 之后按 `length == 1` 判定 `:309`，随后 `Phase.sync():321`；`sync` 失败整笔回滚（`05-submit.md:98`）。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 两个事件均以 `tokenAddress` 开头 |
| 族槽位（根键 → round → id 链 → 地址 → 枚举 → bytes → 文本） | 通过 | `ProposalCreated` 的 `authorId` 在 `target` 之前；`ProposalSubmitted` 的 `round` 在 id 链之前 |
| indexed ≤ 3（§6.3） | 通过 | 各 3 个；`round` 主动降为非 indexed |
| 动态字段上限（§6.8） | 通过 | 见 2.1 |
| 状态写入后 emit（§3.4.3） | 通过 | 创建段先 push 再 emit；推举段先写三处再 emit |
| 父子序（§3.4.6） | 通过 | `ProposalCreated` → `ProposalSubmitted`；`submitNewProposal` 两段同笔 |
| 依赖序（§3.4.5） | 通过 | 回调在状态与事件之后，回调内产生的子事件晚于父事件 |
| 失败不留日志（§3.5） | 通过 | 门槛、去重、名额、`sync` 失败均整笔回滚 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | `Submit.t.sol:980` 断言 `ProposalCreated` 全部 8 个字段（含 `targetData` 两元素逐字节）；`Submit.t.sol:409` 断言 `ProposalSubmitted` 的 4 个字段；`proposalId` 与 `authorId` 用「先建一个 Proposal」的夹具分开 |

## 4. 发现

### [P3] SB-1 `ProposalSubmitted` 与同笔 `Phase` 事件的顺序未断言

- 证据：`Submit.t.sol:409` 的推举用例发生在 round 2，`_submits` 非空（round 1 已推举过），因此 `isFirstSubmit == false`，`Phase.sync()` 不触发；全仓没有「本社区本轮首笔推举 → `ProposalSubmitted` 后紧跟 `PhaseSynchronized`」的顺序断言。
- 问题：§3.4.4 要求跨合约可观察顺序确定并有测试。当前顺序由 `_submitByProposalId:312-321` 固定（先 emit 再 `sync`），但没有回归网。
- 影响：若实现把 `sync()` 提前到 emit 之前，`PhaseSynchronized` 会插到 `ProposalSubmitted` 之前；依赖「推举事实先于 Phase 观测」的索引器会漏配对该笔推举。
- 建议：补一条用例——新社区、新 Round 的首笔 `submit`（或 `submitNewProposal`），断言 `ProposalSubmitted` 的下标小于 `PhaseSynchronized` 的下标。

## 5. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_proposals`（head + body） | `:253` | `ProposalCreated`（全量字段，含 `targetData`） |
| `_proposalIdsByAuthor` | `:254` | 由 `ProposalCreated.authorId` + `proposalId` 折叠 |
| `_submits` / `_submitInfoByProposalId` / `_submitInfoBySubmitterId` | `:301-307` | `ProposalSubmitted`（同一事实的三条读路径） |
| `ProposalHead.createAtBlock` | `:250` | 日志元数据（§6.6），不进 payload |
| `initialized` / 依赖 / `SUBMIT_MIN_RATIO` | `init:58-62` | 一次性部署参数（§3.2 豁免） |
