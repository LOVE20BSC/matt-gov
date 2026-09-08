# 行动阶段与 Round

所有行动有投票、加入、铸币流程；加入阶段包括加入、退出及资产/参与状态变化。各 Executor 从 `Phase.currentPhase()` 计算业务 Round，不把当前 Phase 号直接当作所有阶段的 Round。

## 阶段映射

令 `p = currentPhase()`，下表保留当前 Action 规格的映射：

| Executor | 投票 Round | 加入 Round | 验证 Round | 铸币 Round |
| --- | --- | --- | --- | --- |
| LP（三阶段） | p | p - 1 | 无独立验证阶段 | p - 2 |
| GroupAction（四阶段） | p | p - 1 | p - 2 | p - 3 |
| GroupService（四阶段） | p | p - 1 | p - 2，复用行动结果 | p - 3 |

计算结果小于 1 时，阶段尚未开始，查询和操作回滚 `RoundNotStarted`，不得返回 0。结果有效只表示阶段已开始，实际参与或铸币条件仍由 Executor 校验。获得票的 Proposal 在同 Round 的下一 Phase 开放加入。

```solidity
function currentVoteRound() external view returns (uint256);
function currentJoinRound() external view returns (uint256);
function currentMintRound() external view returns (uint256);
```

GroupAction 和 GroupService 额外提供 `currentVerifyRound() external view returns (uint256)`；LP 不提供虚构的验证接口。加入类写操作只写当前加入 Round，验证只接受当前验证 Round，历史领取允许 `1 <= round <= currentMintRound()`。

冷启动示例：

| 当前 Phase | 已开始的最早业务 |
| --- | --- |
| 1 | Round 1 投票 |
| 2 | Round 1 加入；Round 2 投票 |
| 3 | Round 1 LP 铸币及 GroupAction 验证；Round 2 加入 |
| 4 | Round 1 GroupAction/GroupService 铸币；其他轮次继续流水运行 |

例：Phase 5 的加入 Round 为 4；LP 铸币 Round 为 3，链群/服务铸币 Round 为 2。

## 服务验证复用

服务 Proposal 面向整个 `actionTokenAddress` 社区的 GroupAction，不只绑定一个行动。服务在 Phase `N + 3` 结算 Round N，逐项读取 GroupAction 在 Phase `N + 2` 的同一 Round N 激励。

每个 GroupAction 的激励查询已包含源行动的验证和激励条件，GroupService 不重复筛选。不要求 GroupAction 先完成铸币，也不在 GroupService 内执行验证。聚合与分配公式见 [服务 Executor](06-service-executor.md)。

实现与组织上下文一致：LP 为三阶段，GroupAction 和 GroupService 为四阶段。
