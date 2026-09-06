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

## 参与登记

登记当前成员是否参与行动，供参与列表和外部资格查询；包括链群行动，但不保存 Executor 的资产、验证或链群归属。

| 接口示意 | 规则 |
| --- | --- |
| `isAccountJoined(tokenAddress, actionId, memberId)` | 查询当前登记，沿用该函数名 |
| `actionIdsByMemberId(tokenAddress, memberId)` | 行动数组，另有同名 Count、AtIndex 查询 |
| `registerParticipation(tokenAddress, actionId, memberId)` | 仅关联 Executor 可登记 |
| `unregisterParticipation(tokenAddress, actionId, memberId)` | 仅关联 Executor 可正常清除 |

## forceExit

```solidity
function forceExit(
    address tokenAddress,
    uint256 actionId,
    uint256 memberId
) external;
```

Executor 失效时，成员 NFT 当前持有人可清除通用登记并触发事件。该操作不调用 Executor、不转资产、不承诺返还资产；前端默认隐藏，并需说明与正常退出的区别。

登记查询立即排除该记录；Executor 的资产、历史、结算及链群归属不变，不能凭旧状态自动恢复登记。链群归属只能经 Executor 正常退出清理；对群聊资格的影响统一见 [Chat 类型](../group-chat/05-chat-types.md#forceexit-与资格)。

## Round 查询

| 接口示意 | 返回 |
| --- | --- |
| `proposalIdsByExecutor(tokenAddress, round, executor)` | 本轮关联该 Executor 的 Proposal ID 数组 |
| `proposals(tokenAddress, round)` | 本轮有票且已关联 Executor 的 `proposalIds[]`、`executors[]`，一一对应 |

从 Vote 读取本轮有票 Proposal，再按映射筛选，不维护独立反向索引，不在这里计算激励门槛。按旧 Verify/Vote 的本轮 Proposal 列表查询，不能读成历史累计。Proposal 数量受推举门槛约束，不另设人工数量上限；服务结算只扫描该轮实际有票且已关联的列表。

## 实现约束

除已列回调和 forceExit 外，查询及登记 ABI 在实现接口中补齐；空集合返回空数组，分页越界按统一查询规则处理。服务结算只扫描 Vote 已记录的本轮列表，不新增独立反向索引或人工数量上限。

激励转发见 [铸造链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
