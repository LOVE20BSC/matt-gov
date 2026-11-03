# `core/Mint.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/07-mint.md`。
> 范围：`src/Mint.sol`（557 行）+ `src/interfaces/IMint.sol` 的 `IMintErrors`。

## 1. 结论

- 9 个错误声明 / 10 个发送点；全部命中，无未声明 revert、无裸 `require`。
- 没有资金类错误路径：`mint` 失败整笔回滚，`_rewardMinted`/`_rewardBurned`/`_launchCredit` 与代币供应同步回滚。
- 主要问题：2 个“一错两条件”、1 处跨模块错误面未登记、1 处载荷不对称；另有 3 条 Info（`RoundNotEnded` 载荷、空批次语义、下溢 Panic）。
- `mintGovRewards` 空批次是合法 no-op（测试固化），规格未写；见 E-MNT-05。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 9 |
| revert 站点 | 10 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 3 / 3 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `AlreadyInitialized` | `AlreadyInitialized()` | 1 | 保留 |
| `NotProposalTarget` | `NotProposalTarget(address,address)` | 1 | 保留 |
| `ZeroRecipientAddress` | `ZeroRecipientAddress()` | 2 | 保留 |
| `RoundNotEnded` | `RoundNotEnded(uint256)` | 1 | 保留（注记） |
| `ProposalRewardAlreadyMinted` | `ProposalRewardAlreadyMinted(address,uint256,uint256)` | 1 | 保留 |
| `MemberRewardAlreadyMinted` | `MemberRewardAlreadyMinted(address,uint256,uint256)` | 1 | 保留 |
| `ProposalRewardUnavailable` | `ProposalRewardUnavailable(address,uint256,uint256)` | 1 | 拆分建议 |
| `MemberRewardUnavailable` | `MemberRewardUnavailable(address,uint256,uint256)` | 1 | 拆分建议 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/IMint.sol:44`
- 签名：`AlreadyInitialized()`
- 载荷：无
- 核对：无载荷；`init` 自身状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:83` | `init` | `initialized` | `—` |

### `NotProposalTarget` · 1 站点 · 保留

- 声明：`interfaces/IMint.sol:45`
- 签名：`NotProposalTarget(address,address)`
- 载荷：`address caller, address expectedTarget`
- 赋值链：target ← `ISubmit.proposalTarget(tokenAddress, proposalId)`（`Mint.sol:179`）。
- 核对：载荷 `(caller, expectedTarget)`；两个地址都能定位，符合 §4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:181` | `onlyProposalTarget` | `msg.sender != target` | `msg.sender, target` |

### `ZeroRecipientAddress` · 2 站点 · 保留

- 声明：`interfaces/IMint.sol:49`
- 签名：`ZeroRecipientAddress()`
- 载荷：无
- 核对：无载荷；`mintProposalReward` 与 `_mintGovReward` 两处。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:193` | `mintProposalReward` | `recipient == address(0)` | `—` |
| 2 | `Mint.sol:507` | `_mintGovReward` | `recipient == address(0)` | `—` |

### `RoundNotEnded` · 1 站点 · 保留（注记）

- 声明：`interfaces/IMint.sol:50`
- 签名：`RoundNotEnded(uint256)`
- 载荷：`uint256 round`
- 赋值链：round ← 入口入参；判定读 `Phase.currentPhase()`（`Mint.sol:100-112`）。
- 核对：只带 `round`，无当前 Phase，见 E-MNT-04。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:112` | `_prepareRewardIfNeeded` | `!_isRoundEnded(round)` | `round` |

### `ProposalRewardAlreadyMinted` · 1 站点 · 保留

- 声明：`interfaces/IMint.sol:51`
- 签名：`ProposalRewardAlreadyMinted(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 proposalId`
- 核对：载荷 `(tokenAddress, round, proposalId)`，与状态位键完全一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:199` | `mintProposalReward` | `_proposalMinted[tokenAddress][round][proposalId]` | `tokenAddress, round, proposalId` |

### `MemberRewardAlreadyMinted` · 1 站点 · 保留

- 声明：`interfaces/IMint.sol:56`
- 签名：`MemberRewardAlreadyMinted(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 memberId`
- 核对：载荷 `(tokenAddress, round, memberId)`，与状态位键完全一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:513` | `_mintGovReward` | `_govMinted[tokenAddress][round][memberId]` | `tokenAddress, round, memberId` |

### `ProposalRewardUnavailable` · 1 站点 · 拆分建议

- 声明：`interfaces/IMint.sol:61`
- 签名：`ProposalRewardUnavailable(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 proposalId`
- 赋值链：amount ← `_proposalRewardCalculation(...)`（`Mint.sol:202`）；为 0 的两条路径见 E-MNT-01。
- 核对：承载“整池取消”与“本提案未达标”两个条件，见 E-MNT-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:204` | `mintProposalReward` | `amount == 0` | `tokenAddress, round, proposalId` |

### `MemberRewardUnavailable` · 1 站点 · 拆分建议

- 声明：`interfaces/IMint.sol:66`
- 签名：`MemberRewardUnavailable(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 memberId`
- 赋值链：三项和 ← `_govRewardCalculation(...)`（`Mint.sol:516-519`）；为 0 的两条路径见 E-MNT-02。
- 核对：承载“未投票”与“三项全零”两个条件，见 E-MNT-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:519` | `_mintGovReward` | `voteReward + boostReward + burnReward == 0` | `tokenAddress, round, memberId` |

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IMint.sol:71`
- 签名：`NotMemberOwner(uint256)`
- 载荷：`uint256 memberId`
- 核对：单键；NFT 不存在时先抛 OZ `ERC721NonexistentToken`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Mint.sol:227` | `onlyMemberOwner` | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `memberId` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-MNT-01 | Low | `src/Mint.sol:203-205`、`:314-321`、`:335-337` | `ProposalRewardUnavailable(tokenAddress, round, proposalId)` 同时表示两种不同的不可结算原因：`eligibleVoteAmount == 0`（整轮 Proposal 池在准备阶段已取消）与 `proposalVoteAmount < minVoteAmount`（本提案未达标）。§2 要求一个 selector 只对应一个条件。 | error-standards §2；`07-mint.md:70-76` 把两种条件列在同一错误下 | 拆成 `ProposalPoolUnavailable(...)` 与 `ProposalBelowThreshold(...)`（破坏 ABI，需窗口）；若坚持合并，在 07-mint 写明“两类均永久不可结算，故不区分”的理由。 |
| E-MNT-02 | Low | `src/Mint.sol:369-371`、`:518-520` | `MemberRewardUnavailable(tokenAddress, round, memberId)` 同时表示“本轮未投票（`memberVoteAmount == 0`）”与“三项奖励全为 0”。前者可用 `canVote`/票记录预判，后者是金额计算问题，调用方的处置不同。 | error-standards §2；`07-mint.md:95-110` | 拆 `MemberHasNoVote(...)` 与 `MemberRewardIsZero(...)`；或在规格固化“两者都表示不可结算”。 |
| E-MNT-03 | Low | `src/Mint.sol:175-184`、`:345-354`、`:413-427` | 两个铸造入口的失败集合包含其他模块的错误，但 `IMintErrors` 与 07-mint 都没有“透传来源”表：`mintProposalReward`/`proposalRewardByProposalId` 先经 `ISubmit.proposalTarget`，无效 id 回 `ProposalNotFound(uint256)`；`govRewardByMemberId` 与治理入口先经 `ownerOf`，不存在回 `ERC721NonexistentToken(uint256)`。 | error-standards §1（透传来源表）、§5（写入口错误集合）；`07-mint.md:132-150` | 在 07-mint 增加“透传来源”表，登记 `ProposalNotFound`（来源 ISubmit）与 `ERC721NonexistentToken`（来源 MemberNFT），并链接来源 ABI；`IMint` 不继承这两个错误（符合 §1）。 |
| E-MNT-04 | Info | `src/Mint.sol:100-113` | `RoundNotEnded(uint256 round)` 只带请求轮次，没有 `currentPhase`；与 Stake 的 `RoundNotStarted(requestedRound, currentRound)` 口径不对称，排查时要额外读一次 Phase。 | error-standards §4“没有行动价值时省略载荷”与“主体键在前”的取舍 | 加 `currentPhase`（破坏 ABI）或在 07-mint 说明“当前轮可由 Phase 直接读，故省略”。 |
| E-MNT-05 | Info | `src/Mint.sol:241-262` | `mintGovRewards(tokenAddress, [], memberId, recipient)` 鉴权通过后直接返回三个空数组：不改变状态、不发事件、不回 `*Unavailable`。§6 要求 Transition 型入口“必须改变状态，或回 `Already<State>`”，空批次是第三种结果。测试 `test/Mint.t.sol:137-146` 已把它固化为合法 no-op。 | error-standards §6；`07-mint.md:150-153` 只写“按输入顺序执行”，未写空批次 | 在 07-mint 补一句“空批次为合法 no-op，返回等长空数组”；不要改成 revert（会破坏已发布语义与测试）。 |
| E-MNT-06 | Info | `src/Mint.sol:452-460` | `rewardAvailable` / `reservedAvailable` 的下溢以 Panic 0x11 呈现，没有 selector；触发条件是 `rewardReserved - minted - burned` 或 `MAX_SUPPLY - totalSupply - reservedAvailable` 为负。部署门禁已卡两比例和 ≤1e18（`DeployCore.s.sol:158-163`、`21_check.sh:517-523`），正常配置不可达。 | error-standards §7/§8（失败形态应可判别）；`07-mint.md:30-34` 只写账本不变式 | 在 07-mint 登记“配置越界时失败形态为 Panic”，或在 DeployCore 之外再加一条链上 `require`（会改 gas，不改 selector）。 |

### 4.2 已核对项

- 声明全部在 `IMintErrors`，实现零声明；无裸 `require`/`revert`。
- 10 个站点逐一对齐判据：`RoundNotEnded` 在准备前、`AlreadyMinted` 在计算前、`Unavailable` 在写状态位前。
- `mintGovReward` 与 `mintGovRewards` 共用 `_mintGovReward`，错误集合与顺序一致；批量任一失败整笔回滚（`test/Mint.t.sol:123-134`）。
- `_prepareRewardIfNeeded` 的 `_isRewardPrepared` 提前返回先于 `RoundNotEnded`，与 07-mint:44“已准备则直接返回”一致。
- `check_error_tests.py`：0 untested；`Mint.t.sol` 对 `MemberRewardAlreadyMinted`、`ZeroRecipientAddress` 等均有载荷断言。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `ISubmit.proposalTarget` | `ProposalNotFound(uint256)` | `onlyProposalTarget` 与 `proposalRewardByProposalId` 的存在性前置；见 E-MNT-03。 |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner` 与 `govRewardByMemberId`；见 E-MNT-03。 |
| `ILOVE20Token.mint` | `MaxSupplyExceeded(uint256,uint256)`、`ERC20InvalidReceiver(address)` | `_rewardMinted` 与供应上限不一致时由代币合约拒绝；`recipient` 已在本层判零。 |
| `ILaunch.addLaunchCount` | `TokenNotRegistered(address)`、`LaunchCountLimitExceeded(...)` | `count` 已受 `maxNewCount` 约束；未登记 token 会让整笔铸造回滚。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/Mint.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/IMint.sol`。
