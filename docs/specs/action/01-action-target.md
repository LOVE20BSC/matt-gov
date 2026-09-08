# ActionTarget

ActionTarget 是社群行动 Proposal 的统一 Target。Core 和回调使用 `proposalId`，Executor 使用 `actionId`，两者数值相同；关联键为 `tokenAddress + proposalId`。

## 创建与回调

创建行动时指定 `tokenAddress`、`title`、`details`，并固定 `target = ActionTarget`、`targetMode = Callback`。KV 使用 Core 的平行 `keys` / `values` 数组：

```text
keys[0] = keccak256("executor")
values[0] = abi.encode(executorAddress)
```

第 0 项必须存在且键正确，解码后的 Executor 非零且有代码；其余项可为空，由 Executor 定义。校验失败回滚整个创建操作。

| Core 调用时点 | ActionTarget 行为 |
| --- | --- |
| `onProposalCreated` | 校验保留项，保存 Executor 映射，原样转发完整创建 KV |
| `onProposalSubmitted` | 读取已保存映射，转发本次推举上下文和 KV |
| `onProposalVoted` | 读取映射，转发 `voterId`、本次增量票数及 KV，由 Executor 记账 |

完整签名统一见 [Core Target 回调](../core/05-submit-vote.md#target-回调)。Executor 只接受 ActionTarget 转发，不接受外部直接调用；同一复合键重复创建回调必须拒绝，任一回调失败均回滚对应外层操作。

## 加入与退出

记录当前成员是否加入行动，供加入列表和外部资格查询；包括 GroupAction，但不保存 Executor 的资产、验证或群归属。

```solidity
function init(address memberNFTAddress, address submitAddress, address voteAddress, address mintAddress)
    external;
function isAccountJoined(
    address tokenAddress,
    uint256 actionId,
    uint256 memberId
) external view returns (bool);
function actionIdsByMemberId(address tokenAddress, uint256 memberId)
    external view returns (uint256[] memory actionIds);
function actionIdsByMemberIdCount(address tokenAddress, uint256 memberId)
    external view returns (uint256 count);
function actionIdsByMemberIdAtIndex(
    address tokenAddress,
    uint256 memberId,
    uint256 index
) external view returns (uint256 actionId);
function join(
    address tokenAddress,
    uint256 actionId,
    uint256 memberId
) external;
function exit(
    address tokenAddress,
    uint256 actionId,
    uint256 memberId
) external;
function executor(address tokenAddress, uint256 proposalId) external view returns (address);
function mintProposalReward(address tokenAddress, uint256 round, uint256 proposalId)
    external returns (uint256 amount);
```

`init` 仅部署授权者可调用一次。join/exit/mint 仅关联 Executor 可调用；创建/推举回调仅 Submit 可调用，投票回调仅 Vote 可调用。重复加入、重复退出均不改状态；因此 `forceExit` 后，Executor 正常调用 `exit` 必须成功且不改状态。重复铸造回滚。不存在关联时 `executor` 返回零，但写操作拒绝零关联。`isAccountJoined` 无记录时返回 false。

## forceExit

```solidity
function forceExit(
    address tokenAddress,
    uint256 actionId,
    uint256 memberId
) external;
```

Executor 失效时，成员 NFT 当前持有人可清除加入状态并触发事件。该操作不调用 Executor、不转资产、不承诺返还资产；前端默认隐藏，并需说明与正常退出的区别。

加入查询立即排除该记录；Executor 的资产、历史、结算及 GroupAction 归属不变，不能凭旧状态自动恢复加入状态。GroupAction 归属只能经 Executor 正常退出清理；对群聊资格的影响统一见 [Chat 类型](../group-chat/05-chat-types.md#forceexit-与资格)。

## Round 查询

```solidity
function proposalIdsByExecutor(
    address tokenAddress,
    uint256 round,
    address executor
) external view returns (uint256[] memory proposalIds);
function proposals(address tokenAddress, uint256 round)
    external view returns (
        uint256[] memory proposalIds,
        address[] memory executors
    );
```

从 Vote 的 `votedProposalIdsCount` / `votedProposalIdsAtIndex` 读取本轮有票 Proposal，再按映射筛选，不维护独立反向索引，不在这里计算激励门槛；不能读成历史累计。不另设人工 Proposal 数量上限，服务结算只扫描该轮实际有票且已关联的列表。

## 实现约束

列表按单轮完整返回，不新增分页。空集合返回空数组；Count 返回数量，AtIndex 的索引从 0 开始，越界回滚 `IndexOutOfBounds`。forceExit 重复清理无操作，不发重复事件；不能以清理失败阻塞 Executor 正常退还资产。

激励转发见 [铸造链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
