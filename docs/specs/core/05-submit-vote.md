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
| `keys` / `values` | 不透明 KV；长度相等，可以同时为空 |

| target | NoCallback | Callback |
| --- | --- | --- |
| 非零 EOA | 合法，不回调 | 拒绝 |
| 非零合约 | 合法，不回调 | 创建、推举、投票都回调，空 KV 也回调 |
| 零地址 | 拒绝 | 拒绝 |

显式销毁可由专用 Target 合约接收后执行，不能用零 Target 隐式销毁。

```solidity
enum TargetMode { NoCallback, Callback }

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
    ProposalParams calldata params
) external returns (uint256 proposalId);

function proposal(
    address tokenAddress,
    uint256 proposalId
) external view returns (
    uint256 id,
    uint256 author,
    uint256 createAtBlock,
    string memory title,
    string memory details,
    address target,
    TargetMode targetMode,
    bytes32[] memory keys,
    bytes[] memory values
);

function proposalsCount(address tokenAddress) external view returns (uint256);
function proposalsAtIndex(address tokenAddress, uint256 index)
    external view returns (uint256 proposalId);
```

## 推举

推举使用 `SUBMIT_MIN_PER_THOUSAND` 千分比门槛，同一 Round 去重。每轮首个成功推举自动调用 `Phase.sync`；推举已有 Proposal 不重复触发创建回调。

```solidity
function submit(address tokenAddress, uint256 proposalId) external;
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
- Vote 在投票期间维护 `eligibleProposalVotes`，即本轮所有达标 Proposal 的票数总和。治理 Round 结束后票数自然冻结，Mint 读取而不依赖行动验证结果；门槛公式见 [Mint](06-mint.md#账本与数据来源)。
- 批量投票或 Target 回调失败时，对应外层交易整体回滚。

```solidity
function vote(
    address tokenAddress,
    uint256[] calldata proposalIds,
    uint256[] calldata votes
) external;

function totalVotes(address tokenAddress, uint256 round)
    external view returns (uint256);
function proposalVotes(address tokenAddress, uint256 round, uint256 proposalId)
    external view returns (uint256);
function memberVotes(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256);
function eligibleProposalVotes(address tokenAddress, uint256 round)
    external view returns (uint256);
function memberBoost(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256);
function totalBoost(address tokenAddress, uint256 round)
    external view returns (uint256);
function votedProposalIdsCount(address tokenAddress, uint256 round)
    external view returns (uint256);
function votedProposalIdAtIndex(address tokenAddress, uint256 round, uint256 index)
    external view returns (uint256 proposalId);
```

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

`votes` 为本次增量，不是累计票数；`bytes32` 键用于比较，`bytes` 值承载 ABI 编码。创建、推举、投票分别触发对应回调。

## 实现约束

- `NoCallback` 要求 `keys` 与 `values` 均为空，避免静默忽略业务数据。
- `eligibleProposalVotes` 按旧 Verify 的逐轮历史列表逻辑维护：每次投票导致本轮总票变化后，按本轮已投票 Proposal 列表重新判断门槛并更新总和；不新增固定 Proposal 数量上限。
- 历史来源 `LOVE20Submit.sol`、`LOVE20Vote.sol`、`LOVE20Verify.sol` 仅作为保留逻辑参考，不能替代本文件规则。

验收见 [Core 验收](08-testing.md)。
