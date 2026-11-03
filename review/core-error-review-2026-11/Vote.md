# `core/Vote.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/06-vote.md`。
> 范围：`src/Vote.sol`（293 行）+ `src/interfaces/IVote.sol` 的 `IVoteErrors`。

## 1. 结论

- 9 个错误声明 / 9 个发送点；全部命中，无裸 `require`。
- 批量内逐笔抛错，载荷带逐笔上下文（proposalId / 累计值），超限整批回滚。
- 2 条 Low：`ProposalNotSubmitted` 一错两条件、`ZeroVoteAmount` 缺上下文键。
- 3 条 Info：资格先于形状的顺序无理由（§5 要求）、`_vote` 先写快照后判额度、同批允许重复 proposalId 未写明。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 9 |
| revert 站点 | 9 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 2 / 3 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `AlreadyInitialized` | `AlreadyInitialized()` | 1 | 保留 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | 1 | 保留 |
| `NoVotingPower` | `NoVotingPower(address,uint256)` | 1 | 保留 |
| `ProposalIdsEmpty` | `ProposalIdsEmpty()` | 1 | 保留 |
| `ProposalVoteAmountsLengthMismatch` | `ProposalVoteAmountsLengthMismatch(uint256,uint256)` | 1 | 保留 |
| `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | 1 | 保留 |
| `ProposalNotSubmitted` | `ProposalNotSubmitted(address,uint256,uint256)` | 1 | 拆分/文档化 |
| `ZeroVoteAmount` | `ZeroVoteAmount(uint256)` | 1 | 载荷调整 |
| `VoteLimitExceeded` | `VoteLimitExceeded(address,uint256,uint256,uint256,uint256)` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:5`
- 签名：`AlreadyInitialized()`
- 载荷：无
- 核对：无载荷；`init` 自身状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:53` | `init` | `initialized` | `—` |

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:6`
- 签名：`NotMemberOwner(uint256)`
- 载荷：`uint256 memberId`
- 核对：单键；NFT 不存在时先抛 OZ 错误。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:64` | `onlyMemberOwner` | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `memberId` |

### `NoVotingPower` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:7`
- 签名：`NoVotingPower(address,uint256)`
- 载荷：`address tokenAddress, uint256 memberId`
- 核对：载荷 `(tokenAddress, memberId)`；`voteLimit == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:79` | `vote` | `voteLimit == 0` | `tokenAddress, memberId` |

### `ProposalIdsEmpty` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:11`
- 签名：`ProposalIdsEmpty()`
- 载荷：无
- 核对：无载荷；`proposalIds.length == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:82` | `vote` | `proposalIds.length == 0` | `—` |

### `ProposalVoteAmountsLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:12`
- 签名：`ProposalVoteAmountsLengthMismatch(uint256,uint256)`
- 载荷：`uint256 proposalIdsLength, uint256 voteAmountsLength`
- 核对：载荷 `(proposalIdsLength, voteAmountsLength)`，两值可判别。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:85` | `vote` | `proposalIds.length != voteAmounts.length` | `proposalIds.length, voteAmounts.length` |

### `TargetDataLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:16`
- 签名：`TargetDataLengthMismatch(uint256,uint256)`
- 载荷：`uint256 proposalIdsLength, uint256 targetDataLength`
- 核对：载荷 `(proposalIdsLength, targetDataLength)`；只在传入非空 `targetData` 时判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:88` | `vote` | `targetData.length != 0 && targetData.length != proposalIds.length` | `proposalIds.length, targetData.length` |

### `ProposalNotSubmitted` · 1 站点 · 拆分/文档化

- 声明：`interfaces/IVote.sol:20`
- 签名：`ProposalNotSubmitted(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 proposalId`
- 赋值链：isSubmitted ← `ISubmit.isSubmitted(token, round, proposalId)`（`Vote.sol:222`）。
- 核对：同时表示“id 不存在”与“本轮未推举”，见 E-VOT-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:224` | `_vote` | `!ISubmit(SUBMIT_ADDRESS).isSubmitted(tokenAddress, round, proposalId)` | `tokenAddress, round, proposalId` |

### `ZeroVoteAmount` · 1 站点 · 载荷调整

- 声明：`interfaces/IVote.sol:25`
- 签名：`ZeroVoteAmount(uint256)`
- 载荷：`uint256 proposalId`
- 赋值链：proposalId ← 入参 `proposalIds[i]`；voteAmount ← 同下标 `voteAmounts[i]`。
- 核对：缺 `tokenAddress`/`round`，见 E-VOT-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:229` | `_vote` | `voteAmount == 0` | `proposalId` |

### `VoteLimitExceeded` · 1 站点 · 保留

- 声明：`interfaces/IVote.sol:26`
- 签名：`VoteLimitExceeded(address,uint256,uint256,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 memberId, uint256 cumulativeVoteAmount, uint256 maxVoteAmount`
- 赋值链：memberVoteAfter ← `_voteAmountByMemberId[...] + voteAmount`（`Vote.sol:250`）；voteLimit ← `_maxVoteAmount(...)`（`Vote.sol:77`）。
- 核对：载荷 `(tokenAddress, round, memberId, cumulative, max)`；`cumulative` 为含本笔的累计值，规格 `06-vote.md:70` 已写明。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Vote.sol:253` | `_vote` | `memberVoteAfter > voteLimit` | `tokenAddress, round, memberId, memberVoteAfter, voteLimit` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-VOT-01 | Low | `src/Vote.sol:221-225` | `ProposalNotSubmitted(tokenAddress, round, proposalId)` 只查 `ISubmit.isSubmitted`，因此同时覆盖“proposalId 从未存在”与“存在但本轮未推举”两个条件；§2 要求一个 selector 一个条件，且前者用 `ProposalNotFound` 更准确。 | error-standards §2；`06-vote.md:68` 把条件写成“该 Proposal 本轮未推举” | 先在 Submit 判存在（多一次外部调用/gas），或在 06-vote 明确“未推举含不存在”，并把错误名改成 `ProposalNotSubmittedInRound`（破坏 ABI）。 |
| E-VOT-02 | Low | `src/Vote.sol:227-230` | `ZeroVoteAmount(uint256 proposalId)` 只带 proposalId；同文件的 `ProposalNotSubmitted` 带 `(token, round, proposalId)`、`VoteLimitExceeded` 带 `(token, round, memberId, ...)`。跨社区/多轮日志里，单独的 proposalId 无法定位。 | error-standards §4（主体键在前、批量错误能定位元素） | 改为 `ZeroVoteAmount(address tokenAddress, uint256 round, uint256 proposalId)`（破坏 ABI）；或在规格说明“外层循环已带上下文”。 |
| E-VOT-03 | Info | `src/Vote.sol:76-89` | `vote` 的顺序是 鉴权 → 资格（`NoVotingPower`）→ 形状（非空/等长/`targetData`），与 error-standards §5 的默认序“鉴权→参数→存在性→状态/资格”不同。06-vote:28-34 明示了这个顺序，但没有写理由；§5 允许模块自定义，前提是写明理由。后果：无票权调用者的形状错误被 `NoVotingPower` 掩盖，且形状校验前已做一次 `validGovVotes` 外部调用。 | error-standards §5；`06-vote.md:28-34` | 在 06-vote 补一句理由（如“先判资格，避免为无票权地址解析 calldata”）；否则按默认序把形状校验前移（会改错误优先级，需同步测试）。 |
| E-VOT-04 | Info | `src/Vote.sol:232-254` | `_vote` 先更新加速快照（写 `_voterBoostByMemberId`/`_totalVoterBoostByRound`），再判 `VoteLimitExceeded`。当前靠整笔回滚保证一致性，06-vote:36-37 的步骤 3→4 也明示；但“先写后判”让失败路径多两次 SSTORE，也容易被后续改动误用。 | error-standards §6（先校验后写入的默认读法）；`06-vote.md:36-37` | 把额度判定前移到快照写入之前（语义等价，失败更省 gas）；若保留现状，在 06-vote 注明“快照写入依赖额度判定失败整笔回滚”。 |
| E-VOT-05 | Info | `src/Vote.sol:248-267` | 同一批 `proposalIds` 允许重复 id：第二笔按增量累加，`isFirstVoteByMember` 为 false，因此名册/有票列表不重复；额度按累计判定。行为正确，但 06-vote 未写“同批可重复”。 | error-standards §6（Set/Transition 语义）；`06-vote.md:54` | 在 06-vote 补一句“同一批可重复 proposalId，按增量累加、名册只记一次”。 |

### 4.2 已核对项

- 声明全部在 `IVoteErrors`；实现零声明；无裸 `require`/`revert`。
- 9 个站点逐一对齐判据；`VoteLimitExceeded` 的 `cumulative` 是 `memberVoteAfter`（含本笔），与 06-vote:70 一致。
- `voteLimit` 入口读一次，循环内用累计值判定；任一笔超限整批回滚（`test/Vote.t.sol:960` 等断言）。
- 回调前状态已落盘：`:256-268` 写票数与名册、`:271-279` 发事件，`:281-286` 才回调；符合 R2。
- `isRoundEnded(0) == false`，与 06-vote:54 一致；`maxVoteAmount` 直接读 Stake 当前轮。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner`；06-vote:63 已登记。 |
| `ISubmit.isSubmitted/proposalTarget` | `ProposalNotFound(uint256)` | `isSubmitted` 不抛；`proposalTarget` 在已推举后必存在，理论上不触发。 |
| `IProposalTarget.onProposalVoted` | 任意 revert data | 第三方回调；06-vote:54 声明原样透传、失败整笔回滚。 |
| `IStake.validGovVotes/validBoostShares` | `RoundNotStarted(uint256,uint256)` | 传当前轮，不会触发；依赖异常的读失败按 §7 冒泡。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/Vote.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/IVote.sol`。
