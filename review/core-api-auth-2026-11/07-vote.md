# Vote 接口调用权限审查

> 对象 `core/src/Vote.sol`（293 行）
> 接口 `core/src/interfaces/IVote.sol`（132 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/06-vote.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 22（写 2 / 读 20） |
| 带鉴权 modifier | 1（`onlyMemberOwner`） |
| 无许可写入口 | 1（`init`） |
| 发现 | 3 条：全部 Info，另有 3 条正面结论 |
| 接口对账 | 22 vs 22，**0 差异** |

一句话：**唯一的业务写入口 `vote` 是 `onlyMemberOwner` 首道判定，票上限只读 Stake，回调在状态写完后触发；无锁但可重入成功——重入只会继续累加，且累计值仍受同一次读到的票上限约束。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 成员 NFT 持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `vote` |
| 无 | `if (initialized) revert` | `init` |
| 无 | — | 20 个只读入口 |

与 Submit 的差异：Vote 没有「每人每轮一次」的名额，票是**可累加**的。因此重入不会像 Submit 那样被名额锁死，安全性完全依赖「累计值 ≤ 本次读到的票上限」这一条。

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `init(address,address,address,address)` | 无（一次性） | `if (initialized) revert` | 是 | **无** |
| `vote(address,uint256,uint256[],uint256[],bytes[][])` | `memberId` 持有人 | `onlyMemberOwner(memberId)` `L62` | 是 | `VoteCast`（逐 Proposal） |

### 只读入口（20）

配置 getter 5：`initialized`、`PHASE_ADDRESS`、`STAKE_ADDRESS`、`SUBMIT_ADDRESS`、`MEMBER_NFT_ADDRESS`。

查询 15：`currentRound`、`isRoundEnded`、`canVote`、`maxVoteAmount`、`totalVoteAmount`、`voteAmountByProposalId`、`voteAmountByMemberId`、`voteAmountByMemberIdByProposalId`、`isProposalIdVoted`、`votedProposalIds`、`voterIdsByProposalId`、`votedProposalIdsByMemberId`、`voteAmountsByMemberIdByProposalIds`、`voterBoost`、`totalVoterBoost`。

## 四、逐入口判定

### `vote` — 一笔批量投票，权限三重约束

校验顺序（`L69-99` + `_vote` `L212-288`）：

1. `onlyMemberOwner(memberId)`；
2. `_maxVoteAmount(token, currentRound, memberId) == 0` → `NoVotingPower`（只读一次，批量内复用）；
3. 数组长度：`proposalIds` 非空、`voteAmounts` 等长、`targetData` 为空或等长；
4. 逐笔：`isSubmitted` → `voteAmount != 0` → 加速快照更新 → 累计票数 ≤ 票上限 → 写四张票表 → 名册 → `VoteCast` → 回调。

权限边界：

| 约束 | 作用 |
| --- | --- |
| `ownerOf(memberId) == msg.sender` | 不能替他人投票，也不能用他人的 `memberId` 消耗票权 |
| 票上限只读 Stake | 调用者无法自报票数；Stake 的 `validGovVotes` 由质押份额与承诺等待期决定 |
| 累计判定在循环内 | 同一批里先投的票计入后投的判定，超额那笔回滚整批 |
| 加速快照只增不减 | 首次记全量，后续只补正增量；调用者无法把快照调低以放大相对权重 |

### 重入语义：可重入，但不可越权

- `_vote` 的 `VoteCast` 与 target 回调在状态写完之后（`L271-287`），回调可重入 `vote`。
- 重入时 `msg.sender`、`memberId` 不变，`_maxVoteAmount` 会**重新读一次** Stake。若回调期间该成员在 Stake 增加了质押（`stakeLiquidity`/`stakeBoost`），新上限更高，重入可以继续投票。
- 这需要真实资产与真实身份，属于「同一交易内先加杠杆再投票」，与分成两笔交易等价；不构成越权。
- 若回调期间上限不变，重入累加仍受原上限约束，超额回滚整笔（含外层）。

### 名册与计票的一致性

- `voterIdsByProposalId` 只在「该成员对该提案首次投票」时追加（`isFirstVoteByMember && isFirstVoteOnProposal`），因此同一人对同一提案多次投票只占一行。
- `_votedProposalIds` 只在该提案本轮首次被投时追加，保证「本轮有票提案列表」无重复。
- 两张表都只追加、不删除，`reverse` 即「首次投票逆序」。

## 五、发现

### VOT-01（Info）`vote` 无 `nonReentrant`，但重入不突破票上限

- 证据：`vote` 无锁；`_maxVoteAmount` 在每笔 `vote` 调用开头读取（`L77`），重入会重读。
- 判定：重入的每一次调用都重新执行「累计 ≤ 上限」检查，因此总量始终受限。与 Submit 的「每轮一次名额」不同，Vote 的重入是**语义上允许的追加投票**。
- 建议：不改代码。在 `06-vote.md` 补一句「投票回调可重入，重入按新读到的票上限重新判定累计」，让集成方知道回调里加杠杆是可行的。

### VOT-02（Info）`vote` 不校验 `tokenAddress` 是否登记，靠 Stake 返回 0 兜底

- 证据：`_maxVoteAmount` 直接调 `IStake.validGovVotes`（`L291`），后者不做 `_checkToken`（`Stake.validGovVotes` 只 `_checkRoundStarted`）。
- 影响：对任意未登记地址投票，票上限为 0 → `NoVotingPower(tokenAddress, memberId)`。失败路径明确，无状态写入。
- 判定：与 `05-submit.md`「Submit 不校验 tokenAddress 是否登记；推举门槛由 Stake 票数自然兜底」同构。不是缺陷，但两处依赖同一条隐含前提：**Stake 对未登记代币的票权必然为 0**。该前提由「`stakeLiquidity`/`stakeBoost` 都 `_checkToken`」保证，属结构性不变式。
- 建议：在 `01-common-rules.md` 增一句「未登记代币的票权恒为 0」，把这条前提从两个模块规格的重复叙述提升为通则。

### VOT-03（Info）`voterBoost` 快照与解锁的时序由 Stake 侧兜住

- 证据：`_vote` 首次投票写入 `_voterBoostByMemberId` 与 `_totalVoterBoostByRound`（`L233-245`）；Stake 的 `unstake` 要求本轮未投票（`_hasUsedStakeRights`）。
- 含义：成员不能「先投票把快照记高，再在同一轮解锁把 Stake 快照清零」，因为解锁在投票后会被 `StakeRightsUsed` 拒绝。
- 判定：这是跨合约的时序约束，Vote 侧未做任何校验，完全依赖 Stake。属正面结论，但记录该依赖：**若未来放宽 `unstake` 的「本轮未用票权」限制，Vote 的快照会与实际质押脱节，Mint 的 boost 奖励会被放大。**

### VOT-04（正面结论）鉴权先于票上限有负例钉死

- 证据：`test/Vote.t.sol:677-680`（非持有人 → `NotMemberOwner`）、`L718-721`（所有权限与上限同时不满足时，报的是 `NotMemberOwner`，注释明写「ownership is reported」）。
- 判定：符合 §5.5「非授权方只拿到鉴权错误」，且该用例直接覆盖了「两个错误都可报时的优先级」。

### VOT-05（正面结论）票上限每批只读一次，不做逐笔外部调用放大

- 证据：`_maxVoteAmount` 在 `vote` 开头调用一次（`L77`），结果作为 `voteLimit` 传入 `_vote`。
- 判定：批量长度不影响外部调用次数；同时保证「同一批内上限一致」，不会出现「前几笔按旧上限、后几笔按新上限」的不一致。

### VOT-06（正面结论）`init` 只保存地址，不派生、不调用外部合约

- 证据：`L46-60` 只写四个地址并置 `initialized`。
- 判定：与 Mint 的 `init`（读 `Vote.PHASE_ADDRESS()`）、Launch 的 `init`（建币、建 Pair、调 MemberNFT）相比，Vote 的初始化没有外部依赖，因此不存在隐式顺序约束。

## 六、核对证据

```text
$ forge inspect Vote abi --json                # 22 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 读 | `Phase.currentPhase` | `currentRound()` |
| 读 | `MemberNFT.ownerOf` | 鉴权函数 |
| 读 | `Stake.validGovVotes` | 票上限（每批一次） |
| 读 | `Stake.validBoostShares` | 加速快照（逐笔） |
| 读 | `Submit.isSubmitted` / `Submit.proposalTarget` | 推举前置与回调目标 |
| 写 | `IProposalTarget.onProposalVoted` | 回调出口；实现方须校验 `msg.sender == Vote` |
| 被读 | `Mint._prepareRewardIfNeeded` / `_govRewardCalculation` | 奖励分配的票数与 boost 全部来自本合约的冻结快照 |
| 被读 | `Stake._hasUsedStakeRights` | 解锁前置条件 |
