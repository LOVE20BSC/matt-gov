# Submit 与 Vote

Submit 管理 Proposal 创建和推举，Vote 管理当前治理 Round 投票。主体和权限见 [通用规则](01-common-rules.md)，Round 边界见 [Phase](03-phase.md#治理-round)。

## Proposal

Proposal 以 `tokenAddress + proposalId` 定位，ID 单调分配。

| 数据 | 内容 |
| --- | --- |
| `ProposalHead` | `id`、`author`（memberId）、`createAtBlock` |
| `ProposalBody` | 非空 `title`、可空 `details` |
| `target` | 非零激励接收地址 |
| `targetMode` | `NoCallback` 或 `Callback` |
| `keys` / `values` | 可选的不透明 KV；长度相等，可以同时为空 |

| target | NoCallback | Callback |
| --- | --- | --- |
| 非零 EOA | 合法，不回调 | 拒绝 |
| 非零合约 | 合法，不回调 | 创建、推举、投票都回调，空 KV 也回调 |
| 零地址 | 拒绝 | 拒绝 |

显式销毁可由专用 Target 合约接收后执行，不能用零 Target 隐式销毁。

```solidity
enum TargetMode { NoCallback, Callback }

struct ProposalHead {
    uint256 id;
    uint256 author;
    uint256 createAtBlock;
}
struct ProposalBody { string title; string details; }
struct ProposalParams {
    string title;
    string details;
    address target;
    TargetMode targetMode;
    bytes32[] keys;
    bytes[] values;
}

function init(
    address phaseAddress,
    address stakeAddress,
    address memberNFTAddress,
    uint256 submitMinPerThousand
) external;

function createProposal(
    address tokenAddress,
    uint256 memberId,
    ProposalParams calldata params
) external returns (uint256 proposalId);

function proposal(
    address tokenAddress,
    uint256 proposalId
) external view returns (
    ProposalHead memory head,
    ProposalBody memory body,
    address target,
    TargetMode targetMode,
    bytes32[] memory keys,
    bytes[] memory values
);

function proposalsCount(address tokenAddress) external view returns (uint256);
function proposalsAtIndex(address tokenAddress, uint256 index)
    external view returns (uint256 proposalId);
```

以上 `init` 属于 Submit。创建只保存 Proposal 并触发创建回调，不自动推举；调用者须持有 `memberId` 且满足 `canSubmit`。创建后内容和 Target 不变，重名标题不等于重复 Proposal。

## 推举

推举门槛沿用旧 Submit：从 Stake 读取当前成员 `validGovVotes(tokenAddress, memberId)` 与社区 `govVotesNum(tokenAddress)`；成员和社区票数均为正，且 `floor(validGovVotes * 1000 / govVotesNum) >= SUBMIT_MIN_PER_THOUSAND`。初始化门槛范围为 `1..1000`。

调用者必须持有 `memberId`。每个成员每社区每 Round 最多推举一个 Proposal，同一 Proposal 同轮只能被推举一次；创建不消耗推举次数。每轮首个成功推举自动调用 `Phase.sync`；推举已有 Proposal 不重复触发创建回调。

```solidity
function canSubmit(address tokenAddress, uint256 memberId) external view returns (bool);
function submit(
    address tokenAddress,
    uint256 memberId,
    uint256 proposalId
) external;
function isSubmitted(address tokenAddress, uint256 round, uint256 proposalId)
    external view returns (bool);
function submissionsCount(address tokenAddress, uint256 round)
    external view returns (uint256);
function submissionAtIndex(address tokenAddress, uint256 round, uint256 index)
    external view returns (uint256 proposalId, uint256 submitterId);
```

## 投票和加速快照

- 票数累加到 `votesNumByAccount[tokenAddress][round][memberId]`。同轮可多次投票，累计值不得超过本次从 `Stake.validGovVotes` 读取的 `maxVotesNum`。
- Vote 按 `tokenAddress + round + memberId` 保存已计入的加速快照，同时维护其总和 `stakedAmountOfVoters[tokenAddress][round]`。首次投票计入成员快照，再次投票仅补记当前质押高于已记值的正增量，不重复计入整份快照；未增加时不更新。
- 质押增加但没有后续投票，不更新 Vote 快照。Round 结束后成员快照与总量冻结；Mint 的 `memberBoost` 和 `totalBoost` 都从 Vote 读取，不能用 Stake 的最新余额替换其中一项。
- Vote 只保存每个 Proposal 的冻结票数和本轮有票 Proposal 列表，不维护达标 Proposal 总票数；Mint 在准备时按冻结结果计算该总数并缓存，不依赖行动验证结果。
- 批量投票或 Target 回调失败时，对应外层交易整体回滚。

```solidity
function init(
    address phaseAddress,
    address stakeAddress,
    address submitAddress,
    address memberNFTAddress,
    address mintAddress
) external;

function vote(
    address tokenAddress,
    uint256 memberId,
    uint256[] calldata proposalIds,
    uint256[] calldata votes,
    bytes32[][] calldata keys,
    bytes[][] calldata values
) external;

function currentRound() external view returns (uint256);
function isRoundEnded(uint256 round) external view returns (bool);
function canVote(address tokenAddress, uint256 memberId) external view returns (bool);
function maxVotesNum(address tokenAddress, uint256 memberId) external view returns (uint256);
function votesNum(address tokenAddress, uint256 round)
    external view returns (uint256);
function votesNumByProposalId(address tokenAddress, uint256 round, uint256 proposalId)
    external view returns (uint256);
function votesNumByAccount(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256);
function votesNumByAccountByProposalId(address tokenAddress, uint256 round, uint256 memberId, uint256 proposalId)
    external view returns (uint256);
function stakedAmountOfVotersByMemberId(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256);
function stakedAmountOfVoters(address tokenAddress, uint256 round)
    external view returns (uint256);
function votedProposalIdsCount(address tokenAddress, uint256 round)
    external view returns (uint256);
function votedProposalIdsAtIndex(address tokenAddress, uint256 round, uint256 index)
    external view returns (uint256 proposalId);
```

本节 `init` 属于 Vote；Submit 也提供相同的 `currentRound()`。`isRoundEnded(0)` 返回 false。投票调用者须持有 `memberId`，Proposal 必须已在当前轮推举。`proposalIds` 与 `votes` 必须非空且等长；`keys` 与 `values` 可以同时传空外层数组，表示每笔回调均使用空 KV，若传入则必须与 `proposalIds` 等长且每笔内层数组等长；每笔票数必须为正。按输入顺序累加并回调，重复 Proposal ID 按多笔增量处理，任何一笔失败全部回滚。批量没有协议固定长度上限，调用方可按区块 Gas 分批提交；测试记录首次失败规模。Core 不解析 KV 的业务内容。

保留旧 `votesNum*` 查询名；`Account` 参数在 BSC 为 `memberId`，不是地址。Mint 公式中的 `memberBoost` 对应 `stakedAmountOfVotersByMemberId`，`totalBoost` 对应 `stakedAmountOfVoters`。

## Target 回调

以下 ABI 从 ActionTarget 规格集中到 Core 定义；ActionTarget 转发同一上下文给 Executor，业务 KV 不由 Core 解析。

```solidity
function onProposalCreated(
    address tokenAddress,
    uint256 proposalId,
    bytes32[] memory keys,
    bytes[] memory values
) external;

function onProposalSubmitted(
    address tokenAddress,
    uint256 proposalId,
    uint256 submitterId,
    bytes32[] memory keys,
    bytes[] memory values
) external;

function onProposalVoted(
    address tokenAddress,
    uint256 proposalId,
    uint256 voterId,
    uint256 votes,
    bytes32[] memory keys,
    bytes[] memory values
) external;
```

`votes` 为本次增量，不是累计票数；`bytes32` 键用于比较，`bytes` 值承载 ABI 编码。创建、推举、投票分别触发对应回调。回调不要求 KV 非空；空 `keys`/`values` 仍必须调用回调并传递空数组。

创建和推举回调仅接受 Submit，投票回调仅接受 Vote；Executor 仅接受 ActionTarget 转发。回调前先写入对应 Proposal、推举或投票状态；回调可查询本次新状态，失败则一并回滚。

## 实现约束

- `NoCallback` 要求 `keys` 与 `values` 均为空，避免静默忽略业务数据；`Callback` 允许两数组同时为空。
- Vote 不在投票期间维护达标 Proposal 总票数。Round 结束后，Mint 只在准备时遍历本轮有票 Proposal，按冻结的 `totalVotes` 和 `proposalRewardMinVotePerThousand` 判断达标状态；准备完成后不再重复扫描 Vote 列表。
- `proposal` 查询不存在的 ID 回滚 `ProposalNotFound`；有效社区的空列表返回 0 或空数组，AtIndex 越界回滚 `IndexOutOfBounds`；无记录的票数/快照返回 0、`isSubmitted` 返回 false。所有索引从 0 开始，Proposal ID 从 1 开始。
- 历史来源 `LOVE20TKM/core/src/LOVE20Submit.sol`、`LOVE20TKM/core/src/LOVE20Vote.sol`、`LOVE20TKM/core/src/LOVE20Verify.sol` 仅作为保留逻辑参考，不能替代本文件规则。

验收见 [Core 验收](08-testing.md)。
