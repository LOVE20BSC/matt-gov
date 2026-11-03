# core/ 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03）。行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/**`。
> 范围：`core/src/` 的 8 个实现合约；接口文件作为错误声明侧一并核对。
> 处置：报告基于 `6fdd0f1`；修复已落在 `f4f8d34` 工作树（未提交）。逐条决定与 ABI 变更见 [DISPOSITION.md](DISPOSITION.md)。

## 1. 任务与口径

对每个合约的**每个自定义错误**，穷举合约内所有 revert 站点（“发送”），记录站点判据与载荷实参（“赋值”），再按 error-standards 检查：声明位置、一条件一错误、命名、载荷、校验顺序、可达性、透传面与测试覆盖。

“赋值”指 revert 时写入 payload 的表达式；“发送”指 `revert <Error>(...)` 站点。纯 `assert`（Panic）不计入错误目录，另在对应合约的已核对项说明。

## 2. 总览（6fdd0f1 快照）

| 合约 | 声明 | 站点 | Medium | Low | Info | 报告 |
| --- | --- | --- | --- | --- | --- | --- |
| `Stake.sol` | 20 | 22 | 0 | 3 | 4 | [Stake.md](Stake.md) |
| `Mint.sol` | 9 | 10 | 0 | 3 | 3 | [Mint.md](Mint.md) |
| `Launch.sol` | 19 | 22 | 0 | 2 | 4 | [Launch.md](Launch.md) |
| `MemberNFT.sol` | 5 | 5 | 1 | 0 | 4 | [MemberNFT.md](MemberNFT.md) |
| `Submit.sol` | 15 | 15 | 0 | 1 | 3 | [Submit.md](Submit.md) |
| `Vote.sol` | 9 | 9 | 0 | 2 | 3 | [Vote.md](Vote.md) |
| `Phase.sol` | 1 | 3 | 0 | 0 | 2 | [Phase.md](Phase.md) |
| `LOVE20Token.sol` | 6 | 7 | 0 | 0 | 3 | [LOVE20Token.md](LOVE20Token.md) |
| **合计** | **84** | **93** | **1** | **11** | **26** | 8 份 |

## 3. 横切结论

### X-01 覆盖完整，无“未声明错误”

84 个错误声明全部至少有一个站点；93 个 revert 站点全部命中本模块 `I<Name>Errors` 的声明；`check_errors.py --check` 0 violations；无裸 `require`/`revert`。同名同签名跨模块重复声明 5 组（`AlreadyInitialized`×6、`NotMemberOwner`×5、`TokenNotRegistered`×2、`ZeroDistributorAddress`×2、`SourceAndTargetMemberIdsMustBeDifferent`×2），符合 §1“本地声明、selector 相同”。

### X-02 没有资金类错误路径

所有站点都在会整笔回滚的交易内；未发现“先写状态、后因错误回滚”导致残留的路径（EVM 整笔回滚），也未发现用 revert 代替必要状态更新的路径。`Stake._addLiquidity` 的 `ZeroLiquidityMinted` 是唯一在外部交互之后判定的站点，失败同样整笔回滚，且生产不可达。唯一的托管合约 `Stake` 的错误集合不改变资产归属。因此本次无 High/Critical；1 条 Medium 是配置域导致的入口砖化，不涉及资金。

### X-03 两个“正常路径不可达”的错误

`ZeroLiquidityMinted()`（`Stake.sol:658`）在参考 DEX 下不可达：`UniswapV2Pair.mint` 在流动性为 0 时先以字符串回滚（`dex/lib/v2-core/contracts/UniswapV2Pair.sol:125`），不会把 0 返回给调用方。`PairCreationFailed(address)`（`Launch.sol:259`）在正常路径下也不可达：工厂失败即字符串回滚、成功返回 pair；只有 create2 目标地址已有代码时才会返回 0，而该地址只能由工厂自身在同一 salt 下创建（`dex/lib/v2-core/contracts/UniswapV2Factory.sol:23-36`）。两者的测试都靠返回 0 的桩（`test/Stake.t.sol:2862`、`test/Launch.t.sol:377`），不能证明生产可达。按 §8 应删除或在规格限定前提。

### X-04 “一错两条件”三处

`Vote.ProposalNotSubmitted`（不存在 vs 本轮未推举）、`Mint.ProposalRewardUnavailable`（整池取消 vs 单提案未达标）、`Mint.MemberRewardUnavailable`（未投票 vs 金额全零）。三处都不影响资金，但违反 §2，且让调用方无法据 selector 选择重试/放弃。

### X-05 载荷口径四处

`InsufficientLaunchCount` 的 available/required 顺序（§4 要求 required 在前）、`ProposalNotFound` 缺 tokenAddress、`ZeroVoteAmount` 缺 token/round、`PairCreationFailed` 缺 tokenAddress（且 parent 不是失败主体）。四处都是“跨社区/跨轮日志无法定位”或“顺序与规范相反”。

### X-06 命名存量违规

`SourceAndTargetMemberIdsMustBeDifferent`（禁用 `Must`，两个模块）、`NotAllowedToStakeAtRoundZero`（规则句）、`InsufficientWaitingPhases`（名说 Phases、载荷是 Round）、`InvalidInitialSupply`（指向字段与条件不符）、`TargetPromisedWaitingPhasesTooShort`（`Too*` 承载关系条件）。都是存量 ABI，改动即破坏 selector，建议集中到一个 breaking 窗口。

### X-07 透传面登记不全

Stake 与 Submit/Vote 已登记 `ERC721NonexistentToken`；Mint 未登记 `Submit.ProposalNotFound` 与 `ERC721NonexistentToken`；Launch 的 `init` 未列 LOVE20Token 构造函数的 3 个 selector；MemberNFT 没有透传来源表。§1/§5 要求每个模块有一张表，不要求继承。

### X-08 规格与门禁缺口

- Vote 的顺序（资格先于形状）在 06-vote 写明，但未写 §5 要求的“理由”。
- 02-member-nft 没有校验顺序表；`MemberNFT` 的 4 个名称错误只以分句出现。
- `check_error_tests.py` 只做“错误名在测试文本中出现”的检查，不能证明 selector + 载荷断言；本次抽查的 6 处载荷断言与实现一致。
- Mint 的空批次语义（合法 no-op）只由测试固化，规格未写。

### X-09 无 selector 的失败形态

`MemberNFT.calculateMintCost` 的幂溢出（Panic 0x11，配置越界即可触发，Medium）、`Mint.rewardAvailable/reservedAvailable` 的下溢（Panic，比例和 >1e18 时）、`MemberNFT` 未初始化时的空 revert（0x）。Mint 的比例和由部署门禁（DeployCore/21_check）闭合；**MemberNFT 的幂上界没有任何门禁**（只校验非零），这是 E-NFT-01 判 Medium 的原因。空 revert 只在部署顺序错误时出现。

## 4. 方法与边界

- 静态穷举：脚本按 `revert <Error>(` 扫描 8 个实现文件，按最近的 `if` 提取判据，按括号平衡提取实参；再与 8 个接口文件的 `error` 声明双向对账（84 声明 / 93 站点，0 缺口）。
- 门禁：`check_errors.py --check`（声明位置、参数换行、动态载荷、同签名、死声明、目录漂移）0 violations；`check_error_tests.py` core 0 untested。
- 行为核对：04/05/06 的校验顺序表逐条对照实现；07/08 以规格正文的顺序描述对照。
- 基线回归：`forge test --summary` 当前树 **501 passed / 0 failed**（含未跟踪的 `test/audit/` 11 例；退出码 0）。
- 边界：本次不做 PoC、不改 `src/`；行号以 `core@6fdd0f1` 工作树为准。`test/audit/` 为未跟踪目录，未纳入。
- finding ID 统一 `E-<合约>-NN`，与同目录其他专项（如 `core-api-auth-2026-11/` 的 `STK-01`）区分。

## 5. 文件

| 文件 | 内容 |
| --- | --- |
| `README.md` | 任务、总览、横切结论、方法 |
| `DISPOSITION.md` | 逐条处置、ABI 变更、门禁结果、待办 |
| `Stake.md` | Stake 的逐错误明细与 findings |
| `Mint.md` | Mint 的逐错误明细与 findings |
| `Launch.md` | Launch 的逐错误明细与 findings |
| `MemberNFT.md` | MemberNFT 的逐错误明细与 findings |
| `Submit.md` | Submit 的逐错误明细与 findings |
| `Vote.md` | Vote 的逐错误明细与 findings |
| `Phase.md` | Phase 的逐错误明细与 findings |
| `LOVE20Token.md` | LOVE20Token 的逐错误明细与 findings |

> 严重度口径：`Medium` = 在通过现有部署门禁的配置下可使一个入口永久不可用；`Low` = 与 error-standards 的强制条款冲突或错误在生产不可达/不可定位，需要改 ABI 或规格；`Info` = 口径、文档与一致性，无行为风险。

## 附 A：错误 selector 索引（6fdd0f1 快照）

> 共 84 条声明；按合约列出，selector 由 `cast sig` 生成。修复后的 selector 与删除项见 [DISPOSITION.md](DISPOSITION.md)。同签名跨模块重复声明共用 selector。

| 合约 | 错误 | 签名 | selector |
| --- | --- | --- | --- |
| Stake | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| Stake | `NotAllowedToStakeAtRoundZero` | `NotAllowedToStakeAtRoundZero()` | `0xbe9cd064` |
| Stake | `ZeroTokenAmount` | `ZeroTokenAmount()` | `0x82c4a8c9` |
| Stake | `ZeroParentTokenAmount` | `ZeroParentTokenAmount()` | `0xe6e1b13a` |
| Stake | `ZeroBoostAmount` | `ZeroBoostAmount()` | `0xbbaa8875` |
| Stake | `InvalidPromisedWaitingPhases` | `InvalidPromisedWaitingPhases(uint256,uint256,uint256)` | `0x50a046ad` |
| Stake | `PromisedWaitingPhasesDecreased` | `PromisedWaitingPhasesDecreased(uint256,uint256)` | `0x80336ded` |
| Stake | `UnstakeAlreadyRequested` | `UnstakeAlreadyRequested(address,uint256)` | `0xe8e88f47` |
| Stake | `UnstakeNotRequested` | `UnstakeNotRequested(address,uint256)` | `0x44357cd8` |
| Stake | `NoStakedLiquidity` | `NoStakedLiquidity(address,uint256)` | `0x42b29552` |
| Stake | `InsufficientWaitingPhases` | `InsufficientWaitingPhases(uint256,uint256)` | `0x84d77e73` |
| Stake | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| Stake | `StakeRightsUsed` | `StakeRightsUsed(address,uint256,uint256)` | `0xd2632e80` |
| Stake | `SlippageExceeded` | `SlippageExceeded(uint256,uint256)` | `0x71c4efed` |
| Stake | `SourceAndTargetMemberIdsMustBeDifferent` | `SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)` | `0x1049dc75` |
| Stake | `TargetPromisedWaitingPhasesTooShort` | `TargetPromisedWaitingPhasesTooShort(uint256,uint256)` | `0xe393d50b` |
| Stake | `TokenNotRegistered` | `TokenNotRegistered(address)` | `0xddef98d7` |
| Stake | `PairMissing` | `PairMissing(address)` | `0xeabd8816` |
| Stake | `ZeroLiquidityMinted` | `ZeroLiquidityMinted()` | `0xf4791324` |
| Stake | `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | `0xea74f32b` |
| Mint | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| Mint | `NotProposalTarget` | `NotProposalTarget(address,address)` | `0xc157502b` |
| Mint | `ZeroRecipientAddress` | `ZeroRecipientAddress()` | `0xceef9857` |
| Mint | `RoundNotEnded` | `RoundNotEnded(uint256)` | `0x652d87c5` |
| Mint | `ProposalRewardAlreadyMinted` | `ProposalRewardAlreadyMinted(address,uint256,uint256)` | `0xece01b78` |
| Mint | `MemberRewardAlreadyMinted` | `MemberRewardAlreadyMinted(address,uint256,uint256)` | `0xc157061f` |
| Mint | `ProposalRewardUnavailable` | `ProposalRewardUnavailable(address,uint256,uint256)` | `0x6b95e12e` |
| Mint | `MemberRewardUnavailable` | `MemberRewardUnavailable(address,uint256,uint256)` | `0x1392e03a` |
| Mint | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| Launch | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| Launch | `ZeroDistributorAddress` | `ZeroDistributorAddress()` | `0x71702079` |
| Launch | `TokenNameEmpty` | `TokenNameEmpty()` | `0x0d7673b5` |
| Launch | `TokenSymbolEmpty` | `TokenSymbolEmpty()` | `0xf09ce013` |
| Launch | `TokenNameTooLong` | `TokenNameTooLong(uint256,uint256)` | `0x312f5772` |
| Launch | `TokenSymbolTooLong` | `TokenSymbolTooLong(uint256,uint256)` | `0xb77a560d` |
| Launch | `InvalidTokenSymbolLength` | `InvalidTokenSymbolLength(uint256,uint256)` | `0x18a4669e` |
| Launch | `InvalidTokenSymbolCharacters` | `InvalidTokenSymbolCharacters()` | `0x7e279c58` |
| Launch | `TokenSymbolAlreadyExists` | `TokenSymbolAlreadyExists(bytes32)` | `0x98f23aa3` |
| Launch | `PairCreationFailed` | `PairCreationFailed(address)` | `0x90fa4b05` |
| Launch | `ParentTokenNotRegistered` | `ParentTokenNotRegistered(address)` | `0x7201021d` |
| Launch | `TokenNotRegistered` | `TokenNotRegistered(address)` | `0xddef98d7` |
| Launch | `DistributorNotContract` | `DistributorNotContract(address)` | `0x7c7610b0` |
| Launch | `InsufficientLaunchCount` | `InsufficientLaunchCount(uint256,uint256,uint256)` | `0x750e6e06` |
| Launch | `ZeroCount` | `ZeroCount()` | `0x047b9cec` |
| Launch | `SourceAndTargetMemberIdsMustBeDifferent` | `SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)` | `0x1049dc75` |
| Launch | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| Launch | `NotMintContract` | `NotMintContract(address)` | `0x3ab9a846` |
| Launch | `LaunchCountLimitExceeded` | `LaunchCountLimitExceeded(address,uint256,uint256)` | `0x9affae33` |
| MemberNFT | `NameAlreadyExists` | `NameAlreadyExists(uint256)` | `0x2350ee53` |
| MemberNFT | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| MemberNFT | `NameEmpty` | `NameEmpty()` | `0x1ff3ed9d` |
| MemberNFT | `NameTooLong` | `NameTooLong(uint256,uint256)` | `0x243cf1c9` |
| MemberNFT | `NameInvalidCharacters` | `NameInvalidCharacters()` | `0x9954195a` |
| Submit | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| Submit | `TitleEmpty` | `TitleEmpty()` | `0x5d0ff12d` |
| Submit | `TitleTooLong` | `TitleTooLong(uint256,uint256)` | `0x83dc6558` |
| Submit | `DetailsTooLong` | `DetailsTooLong(uint256,uint256)` | `0x8be47d4d` |
| Submit | `TargetDataTooMany` | `TargetDataTooMany(uint256,uint256)` | `0x3f77fa64` |
| Submit | `TargetDataTooLarge` | `TargetDataTooLarge(uint256,uint256)` | `0xb6bbb06e` |
| Submit | `ZeroTargetAddress` | `ZeroTargetAddress()` | `0xeaf673fd` |
| Submit | `CallbackTargetNotContract` | `CallbackTargetNotContract(address)` | `0x5816a336` |
| Submit | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| Submit | `NoGovVotes` | `NoGovVotes(address)` | `0xa0d4ddef` |
| Submit | `ProposalNotFound` | `ProposalNotFound(uint256)` | `0x428d06a9` |
| Submit | `InsufficientSubmitPower` | `InsufficientSubmitPower(address,uint256,uint256,uint256)` | `0x6898aba8` |
| Submit | `SubmitRoundFull` | `SubmitRoundFull(address,uint256,uint256)` | `0x0fe6aa6e` |
| Submit | `ProposalAlreadySubmitted` | `ProposalAlreadySubmitted(address,uint256,uint256)` | `0x9dcaa584` |
| Submit | `MemberAlreadySubmitted` | `MemberAlreadySubmitted(address,uint256,uint256)` | `0xc3487d0d` |
| Vote | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| Vote | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| Vote | `NoVotingPower` | `NoVotingPower(address,uint256)` | `0x8102b749` |
| Vote | `ProposalIdsEmpty` | `ProposalIdsEmpty()` | `0x46b9908e` |
| Vote | `ProposalVoteAmountsLengthMismatch` | `ProposalVoteAmountsLengthMismatch(uint256,uint256)` | `0xc1eadb2b` |
| Vote | `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | `0x232f36be` |
| Vote | `ProposalNotSubmitted` | `ProposalNotSubmitted(address,uint256,uint256)` | `0x354f9b03` |
| Vote | `ZeroVoteAmount` | `ZeroVoteAmount(uint256)` | `0x1ccf718a` |
| Vote | `VoteLimitExceeded` | `VoteLimitExceeded(address,uint256,uint256,uint256,uint256)` | `0xb60c38d3` |
| Phase | `PhaseNotStarted` | `PhaseNotStarted()` | `0xf2469089` |
| LOVE20Token | `ZeroInitialSupply` | `ZeroInitialSupply()` | `0x9243dc6c` |
| LOVE20Token | `InvalidInitialSupply` | `InvalidInitialSupply(uint256,uint256)` | `0x9906d24a` |
| LOVE20Token | `ZeroDistributorAddress` | `ZeroDistributorAddress()` | `0x71702079` |
| LOVE20Token | `DependencyNotContract` | `DependencyNotContract(address)` | `0x53516c3b` |
| LOVE20Token | `NotMinter` | `NotMinter(address)` | `0x361c31f2` |
| LOVE20Token | `MaxSupplyExceeded` | `MaxSupplyExceeded(uint256,uint256)` | `0xea058246` |
