# `core/Stake.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/04-stake.md`。
> 范围：`src/Stake.sol`（911 行）+ `src/interfaces/IStake.sol` 的 `IStakeErrors`。

## 1. 结论

- 20 个错误声明 / 22 个发送点（revert site）；声明与站点一一覆盖，无未声明 revert、无裸 `require`。
- 22 个站点都在会整笔回滚的路径上；唯一的“交互后判定”是 `ZeroLiquidityMinted`（外部转账与 `pair.mint` 之后，且生产不可达），失败时同笔回滚，无状态残留。
- 顺序与 `04-stake.md` 的六张校验表逐条一致；未发现顺序漂移。
- 主要问题集中在**可达性**与**命名/载荷口径**，无资金风险：3 条 Low（1 条可达性 + 2 条规范）+ 4 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 20 |
| revert 站点 | 22 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 3 / 4 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `AlreadyInitialized` | `AlreadyInitialized()` | 1 | 保留 |
| `NotAllowedToStakeAtRoundZero` | `NotAllowedToStakeAtRoundZero()` | 1 | 改名建议 |
| `ZeroTokenAmount` | `ZeroTokenAmount()` | 1 | 保留 |
| `ZeroParentTokenAmount` | `ZeroParentTokenAmount()` | 1 | 保留 |
| `ZeroBoostAmount` | `ZeroBoostAmount()` | 1 | 保留 |
| `InvalidPromisedWaitingPhases` | `InvalidPromisedWaitingPhases(uint256,uint256,uint256)` | 1 | 保留 |
| `PromisedWaitingPhasesDecreased` | `PromisedWaitingPhasesDecreased(uint256,uint256)` | 2 | 保留 |
| `UnstakeAlreadyRequested` | `UnstakeAlreadyRequested(address,uint256)` | 1 | 保留 |
| `UnstakeNotRequested` | `UnstakeNotRequested(address,uint256)` | 1 | 保留 |
| `NoStakedLiquidity` | `NoStakedLiquidity(address,uint256)` | 1 | 保留 |
| `InsufficientWaitingPhases` | `InsufficientWaitingPhases(uint256,uint256)` | 1 | 改名建议 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | 1 | 保留 |
| `StakeRightsUsed` | `StakeRightsUsed(address,uint256,uint256)` | 2 | 保留 |
| `SlippageExceeded` | `SlippageExceeded(uint256,uint256)` | 1 | 保留 |
| `SourceAndTargetMemberIdsMustBeDifferent` | `SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)` | 1 | 改名建议 |
| `TargetPromisedWaitingPhasesTooShort` | `TargetPromisedWaitingPhasesTooShort(uint256,uint256)` | 1 | 改名建议 |
| `TokenNotRegistered` | `TokenNotRegistered(address)` | 1 | 保留 |
| `PairMissing` | `PairMissing(address)` | 1 | 保留 |
| `ZeroLiquidityMinted` | `ZeroLiquidityMinted()` | 1 | 删除或文档化 |
| `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:20`
- 签名：`AlreadyInitialized()`
- 载荷：无
- 核对：无载荷，`init` 自身状态判定，符合 §5.4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:87` | `init` | `initialized` | `—` |

### `NotAllowedToStakeAtRoundZero` · 1 站点 · 改名建议

- 声明：`interfaces/IStake.sol:21`
- 签名：`NotAllowedToStakeAtRoundZero()`
- 载荷：无
- 核对：规则句式，见 E-STK-05；无载荷。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:474` | `_checkActiveRound` | `round == 0` | `—` |

### `ZeroTokenAmount` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:22`
- 签名：`ZeroTokenAmount()`
- 载荷：无
- 核对：无载荷；`tokenAmount == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:118` | `stakeLiquidity` | `tokenAmount == 0` | `—` |

### `ZeroParentTokenAmount` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:23`
- 签名：`ZeroParentTokenAmount()`
- 载荷：无
- 核对：无载荷；`parentTokenAmount == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:119` | `stakeLiquidity` | `parentTokenAmount == 0` | `—` |

### `ZeroBoostAmount` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:24`
- 签名：`ZeroBoostAmount()`
- 载荷：无
- 核对：无载荷；`boostAmount == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:141` | `stakeBoost` | `boostAmount == 0` | `—` |

### `InvalidPromisedWaitingPhases` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:25`
- 签名：`InvalidPromisedWaitingPhases(uint256,uint256,uint256)`
- 载荷：`uint256 value, uint256 minPhases, uint256 maxPhases`
- 赋值链：minPhases/maxPhases ← init 写入的 `PROMISED_WAITING_PHASES_MIN/MAX`（`Stake.sol:95-96`）；value ← 入参 `promisedWaitingPhases`。
- 核对：载荷 `(value, minPhases, maxPhases)`，限定名符合 §4；上下界都来自 storage。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:479` | `_checkPromisedWaitingPhases` | `promisedWaitingPhases < PROMISED_WAITING_PHASES_MIN \|\| promisedWaitingPhases > PROMISED_WAITING_PHASES_MAX` | `promisedWaitingPhases, PROMISED_WAITING_PHASES_MIN, PROMISED_WAITING_PHASES_MAX` |

### `PromisedWaitingPhasesDecreased` · 2 站点 · 保留

- 声明：`interfaces/IStake.sol:30`
- 签名：`PromisedWaitingPhasesDecreased(uint256,uint256)`
- 载荷：`uint256 requested, uint256 current`
- 赋值链：requested ← 入参；current ← `member.promisedWaitingPhases`（storage）。
- 核对：载荷 `(requested, current)`；两个站点分别是 `stakeLiquidity` 与 `stakeBoost`，条件同为“新值小于已承诺值”。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:128` | `stakeLiquidity` | `promisedWaitingPhases < member.promisedWaitingPhases` | `promisedWaitingPhases, member.promisedWaitingPhases` |
| 2 | `Stake.sol:149` | `stakeBoost` | `promisedWaitingPhases < member.promisedWaitingPhases` | `promisedWaitingPhases, member.promisedWaitingPhases` |

### `UnstakeAlreadyRequested` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:34`
- 签名：`UnstakeAlreadyRequested(address,uint256)`
- 载荷：`address tokenAddress, uint256 memberId`
- 核对：载荷 `(tokenAddress, memberId)`；主体键在前，`unlockRequestPhase != 0` 触发。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:494` | `_checkNoUnstakeRequest` | `member.unlockRequestPhase != 0` | `tokenAddress, memberId` |

### `UnstakeNotRequested` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:38`
- 签名：`UnstakeNotRequested(address,uint256)`
- 载荷：`address tokenAddress, uint256 memberId`
- 核对：载荷同左；`unlockRequestPhase == 0` 触发。与 `UnstakeAlreadyRequested` 构成一对状态错误。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:233` | `withdraw` | `member.unlockRequestPhase == 0` | `tokenAddress, memberId` |

### `NoStakedLiquidity` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:42`
- 签名：`NoStakedLiquidity(address,uint256)`
- 载荷：`address tokenAddress, uint256 memberId`
- 核对：载荷 `(tokenAddress, memberId)`；`No*` 前缀不在 §3 表内，但与 `NoGovVotes`/`NoVotingPower` 存量风格一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:502` | `_checkStakedLiquidity` | `member.liquidityShares == 0` | `tokenAddress, memberId` |

### `InsufficientWaitingPhases` · 1 站点 · 改名建议

- 声明：`interfaces/IStake.sol:46`
- 签名：`InsufficientWaitingPhases(uint256,uint256)`
- 载荷：`uint256 currentRound, uint256 unlockRound`
- 赋值链：unlockRound ← `member.unlockRequestPhase + promisedWaitingPhases`（`Stake.sol:237-241`）；currentRound ← `_currentRound()`。
- 核对：名称写 Phases、载荷是 Round，见 E-STK-03。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:241` | `withdraw` | `round <= member.unlockRequestPhase + promisedWaitingPhases` | `round, member.unlockRequestPhase + promisedWaitingPhases` |

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:50`
- 签名：`NotMemberOwner(uint256)`
- 载荷：`uint256 memberId`
- 核对：单键 `memberId`；`ownerOf` 先于本错误，NFT 不存在时抛 OZ `ERC721NonexistentToken`（04-stake:159 已登记）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:106` | `onlyMemberOwner` | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `memberId` |

### `StakeRightsUsed` · 2 站点 · 保留

- 声明：`interfaces/IStake.sol:51`
- 签名：`StakeRightsUsed(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 memberId`
- 赋值链：round ← `_currentRound()`（`Stake.sol:195` / `:295`），不是入参。
- 核对：载荷 `(tokenAddress, round, memberId)`；`unstake` 与 `mergeStake` 两处共用。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:197` | `unstake` | `_hasUsedStakeRights(tokenAddress, round, memberId)` | `tokenAddress, round, memberId` |
| 2 | `Stake.sol:297` | `mergeStake` | `_hasUsedStakeRights(tokenAddress, round, sourceMemberId)` | `tokenAddress, round, sourceMemberId` |

### `SlippageExceeded` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:56`
- 签名：`SlippageExceeded(uint256,uint256)`
- 载荷：`uint256 actualDeviation, uint256 maxDeviation`
- 赋值链：deviation ← 期望量 − 折算量；maxDeviation ← `floor(期望量 × slippage / 1e18)`（`Stake.sol:752-757`）。
- 核对：载荷 `(actualDeviation, maxDeviation)`；判据用 `Math.mul512` 全精度比较，载荷 `maxDeviation` 为向下取整的容差，触发时必有 `actual > max`，两者不会混淆。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:757` | `_checkSlippage` | `deviationHigh > productHigh \|\| (deviationHigh == productHigh && deviationLow > productLow)` | `deviation, maxDeviation` |

### `SourceAndTargetMemberIdsMustBeDifferent` · 1 站点 · 改名建议

- 声明：`interfaces/IStake.sol:60`
- 签名：`SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)`
- 载荷：`uint256 sourceMemberId, uint256 targetMemberId`
- 核对：`Must` 为 §3 明令禁用的句式，见 E-STK-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:284` | `mergeStake` | `sourceMemberId == targetMemberId` | `sourceMemberId, targetMemberId` |

### `TargetPromisedWaitingPhasesTooShort` · 1 站点 · 改名建议

- 声明：`interfaces/IStake.sol:64`
- 签名：`TargetPromisedWaitingPhasesTooShort(uint256,uint256)`
- 载荷：`uint256 targetPhases, uint256 sourcePhases`
- 赋值链：targetPhases ← `target.promisedWaitingPhases`；sourcePhases ← `source.promisedWaitingPhases`（`Stake.sol:540-547`）。
- 核对：`Too<Size>` 承载关系条件，见 E-STK-04；仅在目标非空时触发。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:545` | `_mergeIntoTarget` | `!targetIsEmpty && target.promisedWaitingPhases < source.promisedWaitingPhases` | `target.promisedWaitingPhases, source.promisedWaitingPhases` |

### `TokenNotRegistered` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:68`
- 签名：`TokenNotRegistered(address)`
- 载荷：`address tokenAddress`
- 核对：载荷 `(tokenAddress)`；每次调用都问 `Launch.isLOVE20Token`，注册不可撤销。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:486` | `_checkToken` | `!ILaunch(LAUNCH_ADDRESS).isLOVE20Token(tokenAddress)` | `tokenAddress` |

### `PairMissing` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:69`
- 签名：`PairMissing(address)`
- 载荷：`address tokenAddress`
- 赋值链：pair ← `factory.getPair(tokenAddress, PARENT_TOKEN_ADDRESS)`（`Stake.sol:526-529`）。
- 核对：载荷 `(tokenAddress)`；只在首次解析并缓存 Pair 时可达，缓存后不会再抛。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:529` | `_pairFor` | `pair == address(0)` | `tokenAddress` |

### `ZeroLiquidityMinted` · 1 站点 · 删除或文档化

- 声明：`interfaces/IStake.sol:70`
- 签名：`ZeroLiquidityMinted()`
- 载荷：无
- 赋值链：lpMinted ← `IUniswapV2Pair(pair).mint(address(this))` 的返回值（`Stake.sol:657`）。
- 核对：参考 V2 Pair 下不可达，见 E-STK-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:658` | `_addLiquidity` | `added.lpMinted == 0` | `—` |

### `RoundNotStarted` · 1 站点 · 保留

- 声明：`interfaces/IStake.sol:71`
- 签名：`RoundNotStarted(uint256,uint256)`
- 载荷：`uint256 requestedRound, uint256 currentRound`
- 核对：载荷 `(requestedRound, currentRound)`；仅 view 入口，`round > current` 触发，等于当前轮合法。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Stake.sol:459` | `_checkRoundStarted` | `round > currentRound` | `round, currentRound` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-STK-01 | Low | `src/Stake.sol:657-658` | `ZeroLiquidityMinted()` 在参考 DEX 下不可达：`UniswapV2Pair.mint` 在流动性算得 0 时先以字符串 `UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED` 回滚，不会把 0 返回给调用方。唯一能触发该分支的测试用的是恒返回 0 的 `MockPairZeroMint`。 | error-standards §8“不保留不可达错误”；`dex/lib/v2-core/contracts/UniswapV2Pair.sol:125`；`test/Stake.t.sol:2862-2864`（stub）、`:2782`（断言） | 若只支持参考 V2：删除声明、测试与 04-stake:42 的对应句。若要支持“返回 0 的兼容 Pair”：在 04-stake 明写该前提，并把测试改名成兼容性用例。保留现状则调用方永远看不到该 selector，只会收到字符串 revert。 |
| E-STK-02 | Low | `src/interfaces/IStake.sol:60-63`、`src/interfaces/ILaunch.sol:53-56` | `SourceAndTargetMemberIdsMustBeDifferent` 使用 `Must` 规则句；error-standards §3 对新错误明令禁用 `Only*`/`Must*`/`Cannot*`。同签名在两个模块各自声明（允许），但两个 ABI 都暴露该名字。 | error-standards §3；站点 `Stake.sol:284`、`Launch.sol:159` | 下一个 breaking 窗口改成状态式命名，如 `SourceEqualsTarget(uint256 sourceMemberId)`；两模块同时改，selector 一起变。 |
| E-STK-03 | Low | `src/Stake.sol:240-241` | `InsufficientWaitingPhases(currentRound, unlockRound)` 的名字说“等待 Phase 不足”，载荷却是两个 Round 编号（`round` 与 `unlockRequestPhase + promisedWaitingPhases`）。§4 要求相邻字段单位一致，不一致时把单位写进字段名。 | error-standards §4；`04-stake.md:220` 同样把载荷写成 Round | 改名为 `UnlockRoundNotReached(uint256 currentRound, uint256 unlockRound)`；或在规格固化“Phases 指等待期长度，载荷是 Round 编号”，并在接口注释写清。 |
| E-STK-04 | Info | `src/Stake.sol:544-547` | `TargetPromisedWaitingPhasesTooShort(targetPhases, sourcePhases)` 用 `Too<Size>` 表达“目标短于源”的关系条件；§3 把 `Too*` 限定为尺寸语义，缺口/不足用 `Insufficient*`。 | error-standards §3 | 改为 `TargetPromisedWaitingPhasesBelowSource(uint256 targetPhases, uint256 sourcePhases)`，或在 04-stake 固化“此处 TooShort 专指相对源的比较”。 |
| E-STK-05 | Info | `src/Stake.sol:472-475` | `NotAllowedToStakeAtRoundZero()` 是规则句（“不允许在轮 0 质押”），§3 要求错误名描述失败状态而不是规则。它也不携带任何载荷。 | error-standards §3 | 改为 `StakeNotStarted()` 或 `StakeRoundZero()`；语义上仅表示 `phase == 0`，与 `RoundNotStarted`（请求了未来轮）区分。 |
| E-STK-06 | Info | `src/interfaces/IStake.sol:71-74` 与 `04-stake.md:110` | 规格把 `RoundNotStarted` 的参数写成 `requiredRound`，接口声明是 `requestedRound`。`check_doc_payloads.py` 只校验“类型 + 参数名”都写出的引用，此处只写了名字，漏检。 | error-standards §5“载荷以 I<Name>Errors 声明为唯一来源”；`check_doc_payloads.py` 的匹配条件 | 规格改成 `requestedRound`；或在规格里写出完整类型 `RoundNotStarted(uint256 requestedRound, uint256 currentRound)` 让脚本接管。 |
| E-STK-07 | Info | `src/Stake.sol:785-799`、`:258-276` | `lpAmount == 0` 时 `withdraw` 不转账、不报错，仍 `delete` 仓位并发零额 `StakeWithdrawn`。重分类可把 `lastWithdrawableLp` 打到 0，此时成员份额确实不值钱；但错误契约上没有“提取了 0”的信号。 | `04-stake.md:62-66`（重分类可把可提取 LP 降到 0）；error-standards §6（Transition 必须改变状态） | 不要加 revert（会把 0 价值仓位永久锁死）；在 04-stake 的 withdraw 表补一行“LP 折算为 0 时成功、仓位清零、发零额事件”。 |

### 4.2 已核对项

- 声明全部在 `IStakeErrors`，实现文件零声明；无裸 `require`/`revert`（`check_errors.py` 0 violations）。
- 22 个站点逐一有判据与实参；`SlippageExceeded` 的实际/上限、`StakeRightsUsed` 的 round、`TargetPromisedWaitingPhasesTooShort` 的双方值都与条件一致。
- 顺序与 04-stake 六张表一致：`stakeLiquidity` 11 步、`stakeBoost` 7 步、`unstake` 5 步、`withdraw` 6 步、`mergeStake` 9 步、`settleFees` 2 步。
- `check_error_tests.py`：core 0 untested；抽查 `test/Stake.t.sol:1064` 断言 `SlippageExceeded(100e18, 10e18)`，载荷与实现一致。
- `withdraw` 的 `delete` 在外部转账之后（S3 关注点），本次仅从错误契约确认：该路径没有错误守卫，失败由 ERC20 转账异常冒泡；属设计取舍，不在本报告定级。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `MemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner` 与 `mergeStake` 的目标存在性检查；04-stake:159 已登记。 |
| `LOVE20Token.transfer/transferFrom` | `SafeERC20FailedOperation(address)`、ERC20 标准错误 | `_pull`/`_push`；04-stake:159 登记 SafeERC20。 |
| `IUniswapV2Pair.mint/burn`、`IUniswapV2Router02.swap*` | 字符串 revert（`UniswapV2: ...`） | 参考 V2 实现；不属于 core 错误目录。 |
| `Launch.isLOVE20Token`、`IVote.SUBMIT_ADDRESS`、`ISubmit.proposalIdBySubmitterId` | 协议内固定依赖 | 非预期失败按 §7 原样冒泡。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/Stake.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/IStake.sol`。
