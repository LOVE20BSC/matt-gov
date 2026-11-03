# Vote 事件赋值与发射审查

- 实现：`core/src/Vote.sol`（293 行，`6fdd0f1`）
- 声明：`core/src/interfaces/IVote.sol`（`IVoteEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/06-vote.md`
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 1 |
| 发射点 | 1（`_vote`；批量投票按 `proposalIds` 入参顺序每项一条） |
| P0 / P1 / P2 / P3 | 0 / 0 / 2 / 0 |
| 修复状态 | VT-1 / VT-2 已全部关闭（见 §4） |
| 放行 | 可放行；VT-1 / VT-2 已补齐 |

`VoteCast` 的载荷以**逐笔**增量与加速快照为主。审查时它不携带成员累计票数与本轮累计票数（VT-1），修复后已追加 `voteAmountTotal` / `totalVoteAmount` 两个后置锚点。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `VoteCast` | `tokenAddress`, `voterId`, `proposalId`（`round` 非 indexed） | `_vote:271` | 加速快照 `:232-245`、四张票数表 `:256-259`、三个索引 `:261-267` | `proposalTarget` 读取 `:282` → `Callback` 模式回调 `:286` |

族归属：`core.proposal`（根键 → round → 对象/actor id 链 → 地址 → 枚举 → bytes → 文本）。

## 2. 逐事件赋值链

```
event VoteCast(
    address indexed tokenAddress,
    uint256 round,
    uint256 indexed voterId,
    uint256 indexed proposalId,
    uint256 voteAmount,
    uint256 voteAmountTotal,
    uint256 totalVoteAmount,
    uint256 voterBoost,
    uint256 totalVoterBoost
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:273` | 根键 |
| `round` | `round = currentRound()` `:76`（= `Phase.currentPhase()`） | 非 indexed：3 个槽位被根键与两个 id 占满 |
| `voterId` | 入参 `memberId` `:274` | 调用者已由 `onlyMemberOwner:62` 绑定为该 NFT 持有人 |
| `proposalId` | 入参 `:275` | `:222` 已校验本轮已推举 |
| `voteAmount` | 入参 `:276` | **本次增量**，不是累计；`:227-230` 已拒绝 0 |
| `voterBoost` | `_voterBoostByMemberId[token][round][memberId]` `:277` | 成员本轮加速快照；首投记全量，后续只补正增量 |
| `totalVoterBoost` | `_totalVoterBoostByRound[token][round]` `:278` | 本轮全局加速快照 |

加速快照的赋值逻辑（`:232-245`）：

```
currentVoterBoost = _voterBoostByMemberId[token][round][memberId];
actualVoterBoost  = IStake.validBoostShares(token, round, memberId);
if (currentVoterBoost == 0) {            // 首投：记全量
    _voterBoostByMemberId[...] = actualVoterBoost;
    _totalVoterBoostByRound[round] += actualVoterBoost;
} else if (actualVoterBoost > currentVoterBoost) {   // 后续：只补差
    delta = actualVoterBoost - currentVoterBoost;
    _voterBoostByMemberId[...] = actualVoterBoost;
    _totalVoterBoostByRound[round] += delta;
}
// actual < current 时不更新，事件仍报旧快照
```

不变式：本轮一旦投票，`validBoostShares` 只可能增加——`unstake:196` 对「本轮已投票」直接回滚 `StakeRightsUsed`，`mergeStake:296` 对源成员同规则，`withdraw` 又要求先 `unstake`。因此 `actual < current` 分支在本轮内不可达，`voterBoost` 恒等于投票时点的 `validBoostShares`。

票数与索引写入（`:256-267`）：

| 写入 | 行 | 由事件承载方式 |
| --- | --- | --- |
| `_totalVoteAmountByRound[token][round] += voteAmount` | `:256` | 逐笔 `voteAmount` 折叠 |
| `_voteAmountByProposalId[token][round][proposalId] += voteAmount` | `:257` | 同上，按 `proposalId` 分组 |
| `_voteAmountByMemberId[token][round][memberId] = memberVoteAfter` | `:258`（`memberVoteAfter` 在 `:250` 预计算并先做上限判定） | 逐笔折叠 |
| `_voteAmountByMemberIdByProposalId[...] += voteAmount` | `:259` | 同上，双键分组 |
| `_votedProposalIds` / `_votedProposalIdsByMemberId` / `_voterIdsByProposalId` | `:261-267` | 只在「首次投票」时 push，顺序 = `VoteCast` 顺序 |

上限判定在写入前用**预计算值**完成（`:250-254`），失败回滚整批，不留半写状态。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | `tokenAddress` 首字段 |
| 族槽位（根键 → round → 对象/actor id 链 → 数值） | 通过 | `round` 在 `voterId` 之前；`voterId` → `proposalId` 均属 id 链 |
| indexed ≤ 3（§6.3） | 通过 | 3 个；`round` 主动降为非 indexed |
| **累计值锚点（§3.1）** | 通过（修复后） | `VoteCast.voteAmountTotal` / `totalVoteAmount` 携带后置值 |
| 状态写入后 emit（§3.4.3） | 通过 | 四张票数表与三个索引均先写 |
| 依赖序（§3.4.5） | 通过 | `VoteCast` 先于 Target 回调；回调内子事件晚于父事件 |
| 批量逐条 emit（§3.4.4） | 通过 | 按入参顺序每 Proposal 一条；`Vote.t.sol:1392` 断言顺序 |
| 失败不留日志（§3.5） | 通过 | `Vote.t.sol:1378` 断言 revert 后无 `VoteCast` |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 部分，见 VT-2 | `Vote.t.sol:1353` 覆盖 7 个字段 |

## 4. 发现

### [P2] VT-1 `VoteCast` 缺本轮/成员累计票数锚点

- 状态：已修复。`VoteCast` 在 `voteAmount` 之后追加 `voteAmountTotal`（成员本轮后置累计）与 `totalVoteAmount`（该轮后置总量），`06-vote.md` 与 ABI 基线同步。
- 证据：`Vote.sol:256` 维护 `_totalVoteAmountByRound`、`:258` 维护 `_voteAmountByMemberId`，两者都只由 `VoteCast` 改变；事件载荷 `:271-279` 只有逐笔 `voteAmount`，没有后置总量。
- 问题：§3.1 第 3 条要求「只由单个事件类改变的聚合量也在改变它的事件上携带后置总量」，并明确举了 `Stake.totalBurnedToken` 为例。本合约的两个票数聚合量正属此类，却只能靠全量折叠。同一规范下 `action` 的 `ApplicationVoteRecorded` 带了 `voteAmountTotal`，core 的 `VoteCast` 没有，跨仓口径不一致。
- 影响：
  1. `Mint` 的 `voteReward = votePool × memberVote / totalVote` 依赖这两个量，链下复核必须重放全部 `VoteCast`，无法用单条事件就地校验；
  2. 无法用事件判定「本次投票是否触及 `voteLimit`」——`voteLimit` 本身也不在载荷里。
- 建议：`VoteCast` 追加两个字段（放在 `voteAmount` 之后）：`voteAmountTotal`（该成员本轮后置累计）与 `totalVoteAmount`（本轮后置总量）。属 ABI/规范变更，须同步 `06-vote.md` 事件节、`events-baseline.txt` 与 `Vote.t.sol`。若判定「可由 `voteAmount` 折叠」而豁免，需按 §8.1 的豁免机制登记理由，与 `ApplicationVoteRecorded` 的处理对齐。

### [P2] VT-2 载荷用例中 `voterBoost` 与 `totalVoterBoost` 恒等，不可判别

- 状态：已修复。夹具改为两名成员各带 boost（50 / 40）并先投一票，测得事件断言 `voterBoost == 40`、`totalVoterBoost == 90`；`40` 与 30 票的 `voteAmount` 也不同值。
- 证据：`Vote.t.sol:1353-1375`——夹具只有一名有加速份额的投票人（`stake.setBoost(TOKEN, 1, memberId, 50)`），断言 `voterBoost == 50` 且 `totalVoterBoost == 50`；其他用例（`:1090-1157`）同样是单成员，两个查询值始终相同。
- 问题：同一事件内两个相邻 `uint256` 在全部夹具中取值相同，互换实参后测试仍通过，按 §8.1 属「没断言」。二者语义不同（成员快照 vs 全局合计），在两名以上有 boost 的投票人场景下必然分离。
- 影响：把 `voterBoost` 赋成 `_totalVoterBoostByRound`（或反之）不会被发现；`Mint` 的 `boostReward` 用 `voterBoost / totalVoterBoost`，两者互换会把单人份额当成全局份额，直接放大奖励。
- 建议：夹具改为两名成员各有 boost（例如 50 与 30），断言 `voterBoost == 50`、`totalVoterBoost == 80`。

## 5. 观察（非缺陷）

1. `actualVoterBoost < currentVoterBoost` 时事件报旧值而非实时值。该分支在本轮内不可达（见 §2 不变式），是防御性写法；若将来放开「投票后仍可减少有效加速」，`voterBoost` 会变成过期快照，需要在规范中改述为「本轮已记快照」而不是「投票时点的有效加速」。
2. `VoteCast.round` 非 indexed，但 `round` 是协议纪元键，消费方按轮过滤需扫全部 `VoteCast`。这是 §6.3 分配优先级的正常取舍（根键 + 两个 id 已占满），不是缺陷；若未来需要按轮订阅，只能牺牲 `proposalId` 或 `voterId` 的 indexed 位。

## 6. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_totalVoteAmountByRound` | `:256` | 逐笔 `voteAmount` 折叠（无后置锚点，见 VT-1） |
| `_voteAmountByProposalId` | `:257` | 同上（按 `proposalId` 分组） |
| `_voteAmountByMemberId` | `:258` | 同上（按 `voterId` 分组） |
| `_voteAmountByMemberIdByProposalId` | `:259` | 同上（双键分组） |
| `_votedProposalIds` / `_votedProposalIdsByMemberId` / `_voterIdsByProposalId` | `:261-267` | 由「每个键首次出现」的 `VoteCast` 折叠 |
| `_voterBoostByMemberId` / `_totalVoterBoostByRound` | `:238-243` | `VoteCast.voterBoost` / `totalVoterBoost`（后置值） |
| `initialized` / 四个依赖地址 | `init:55-59` | 一次性部署参数（§3.2 豁免） |
