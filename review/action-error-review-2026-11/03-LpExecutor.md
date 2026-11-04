# `action/LpExecutor.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/04-lp-executor.md`。
> 范围：`src/LpExecutor.sol`（533 行）+ `src/interfaces/ILpExecutor.sol` 的 `ILpExecutorErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 9 个错误声明 / 12 个发送点（含 3 个基座复用）；无未声明 revert、无裸 `require`、无 `assert`。
- 三个写入口的鉴权 → 参数 → 轮次 → 余额/资格顺序与 04 的表格逐条一致；`_mintMemberReward` 的窗口校验走基座 `_checkMintWindow`，与另两个 Executor 同源。
- 唯一的「交互后判定」是 `MemberActionRewardUnavailable`（`mintActionReward` 之后），失败整笔回滚，Mint 的铸造与预留一并撤销，无残留。
- 无 Medium / Low；4 条 Info 集中在「一错多因」口径与规格未写明的实现细节。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 9 |
| revert 站点 | 12 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 4 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | ILpExecutorErrors | 2 | 保留 |
| `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | ILpExecutorErrors | 1 | 保留 |
| `ZeroJoinTokenAddress` | `ZeroJoinTokenAddress()` | ILpExecutorErrors | 1 | 保留 |
| `InvalidJoinTokenFactory` | `InvalidJoinTokenFactory(address,address)` | ILpExecutorErrors | 1 | 保留 |
| `InvalidMinGovRatio` | `InvalidMinGovRatio(uint256)` | ILpExecutorErrors | 1 | 保留 |
| `ZeroParticipationAmount` | `ZeroParticipationAmount()` | ILpExecutorErrors | 2 | 保留 |
| `InsufficientGovRatio` | `InsufficientGovRatio(uint256,uint256)` | ILpExecutorErrors | 1 | 保留 |
| `WithdrawAmountExceeded` | `WithdrawAmountExceeded(uint256,uint256)` | ILpExecutorErrors | 1 | 保留 |
| `NotJoined` | `NotJoined(address,uint256,uint256)` | ILpExecutorErrors | 1 | 保留 |
| `MemberActionRewardUnavailable` | `MemberActionRewardUnavailable(address,uint256,uint256,uint256)` | IActionExecutorErrors | 1 | 口径调整 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `TargetDataLengthMismatch` · 2 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:17`
- 签名：`TargetDataLengthMismatch(uint256,uint256)` · selector `0x232f36be`
- 载荷：`uint256 expected, uint256 actual`
- 核对：创建回调「恰为 4 项」与投票回调「最多 1 项」两处语义不同但条件单一（项数不符），`expected` 分别表示精确值与上界；与 GroupAction 的区间双义（E-GAM-01）不同，这里两处各自只有一个边界。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:95` | `function onProposalCreated` | `targetData.length != 4` | `4, targetData.length` |
| 2 | `LpExecutor.sol:139` | `function onProposalVoted` | `targetData.length > 1` | `1, targetData.length` |

### `InvalidTargetDataShape` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:21`
- 签名：`InvalidTargetDataShape(uint256,uint256)` · selector `0x9c2b3988`
- 载荷：`uint256 index, uint256 length`
- 核对：`index` 在循环中取自 `i`，能定位失败项；`length` 为该项字节数。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:100` | `function onProposalCreated` | `targetData[i].length != 32` | `i, targetData[i].length` |

### `ZeroJoinTokenAddress` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:7`
- 签名：`ZeroJoinTokenAddress()` · selector `0x8a1b296f`
- 载荷：无
- 核对：非合约参数零值，符合 §3 `Zero<Field>`；字段名与 `joinTokenAddress` 一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:109` | `function onProposalCreated` | `lpTokenAddress == address(0)` | `—` |

### `InvalidJoinTokenFactory` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:8`
- 签名：`InvalidJoinTokenFactory(address,address)` · selector `0x17318f81`
- 载荷：`address joinToken, address factory`
- 核对：「外部：source」两字段（参与代币 + 工厂），符合 §4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:112` | `function onProposalCreated` | `!_isRegisteredPair(lpTokenAddress, PAIR_FACTORY_ADDRESS)` | `lpTokenAddress, PAIR_FACTORY_ADDRESS` |

### `InvalidMinGovRatio` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:12`
- 签名：`InvalidMinGovRatio(uint256)` · selector `0x30a418eb`
- 载荷：`uint256 value`
- 核对：`Invalid<Field>(value)`，条件为 `> 1e18`；载荷即越界值，有行动价值。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:115` | `function onProposalCreated` | `minGovRatioValue > PRECISION` | `minGovRatioValue` |

### `ZeroParticipationAmount` · 2 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:25`
- 签名：`ZeroParticipationAmount()` · selector `0x4ae8f898`
- 载荷：无
- 核对：无载荷；加入与撤回共用一个条件（金额为零），符合 §3。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:151` | `function join` | `amount == 0` | `—` |
| 2 | `LpExecutor.sol:200` | `function withdraw` | `amount == 0` | `—` |

### `InsufficientGovRatio` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:13`
- 签名：`InsufficientGovRatio(uint256,uint256)` · selector `0x39a246e7`
- 载荷：`uint256 required, uint256 actual`
- 核对：`(required, actual)`；`required` 取自创建回调写入的 `minGovRatio`，`actual` 为当前轮现算值。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:161` | `function join` | `memberGovRatio < minGovRatioValue` | `minGovRatioValue, memberGovRatio` |

### `WithdrawAmountExceeded` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:26`
- 签名：`WithdrawAmountExceeded(uint256,uint256)` · selector `0xbffdd230`
- 载荷：`uint256 amount, uint256 joined`
- 核对：`(amount, joined)`；两个 `uint256` 同单位，符合 §4「相邻字段单位一致」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:206` | `function withdraw` | `amount > memberJoinedAmount` | `amount, memberJoinedAmount` |

### `NotJoined` · 1 站点 · 保留

- 声明：`interfaces/ILpExecutor.sol:30`
- 签名：`NotJoined(address,uint256,uint256)` · selector `0x847d1a6f`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId`
- 核对：三字段为行动主体键；只在 `exit` 使用，与 04 表一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:246` | `function exit` | `memberJoinedAmount == 0` | `tokenAddress, actionId, memberId` |

### `MemberActionRewardUnavailable` · 1 站点 · 口径调整

- 声明：`interfaces/IActionExecutor.sol:30`（跨模块复用，本模块不重复声明）
- 签名：`MemberActionRewardUnavailable(address,uint256,uint256,uint256)` · selector `0x4cd933ce`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId, uint256 round`
- 核对：结果条件（`mintAmount == 0 && burnAmount == 0`），三种成因见 E-LP-01；载荷四字段为行动主体键 + 被结算轮。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LpExecutor.sol:508` | `function _mintMemberReward` | `mintAmount == 0 && burnAmount == 0` | `tokenAddress, actionId, memberId, round` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-LP-01 | Info | `src/LpExecutor.sol:507-509` | `MemberActionRewardUnavailable` 一个站点承载三种成因：有效参与总量为零、行动激励为零、逐项取整为零。三者都「无产出」，且都可待激励就绪后重试，行动价值相同，因此不构成 §2 的实质违规；但 core 侧的 `Mint.MemberRewardUnavailable` 被同口径 review 判为「一错两条件」，两仓的处置口径需要对齐。 | error-standards §2 / §4（行动价值决定载荷与拆分） | 在 07-minting.md 的错误表里显式写明「该错误的条件是结果条件（`mintAmount == 0 && burnAmount == 0`），不是成因」，与 core 的 `MemberRewardUnavailable` 采用同一句话。 |
| E-LP-02 | Info | `src/LpExecutor.sol:104-116` | `govRatioMultiplier` 在创建回调里没有上界校验（只有 `minGovRatio <= 1e18`）。安全性依赖 `Math.mulDiv` 不溢出这一实现细节：任意大的乘数只会让 `govRatioCap` 饱和，结算仍不失败。04 只写「两个治理比例使用 `1e18` 精度」，未写明乘数无上界及其后果。 | error-standards §5（写入口的错误集合须与规格一致） | 在 04 的校验表补一行：「`govRatioMultiplier` 无上界，取任意 `uint256` 均不会使结算回滚；上限关闭用 `0` 表示」。 |
| E-LP-03 | Info | `src/LpExecutor.sol:177-179` | `registerJoinState`（可回 `JoinNotOpen`）排在全部账本写入之后。整笔回滚，无残留；但 §5 的「状态/资格先于账本」在该入口是靠「账本写完后调用 ActionTarget」实现的，规格 04 未说明这一跨合约顺序。 | error-standards §5 | 在 04 的「校验与回滚」段补一句：加入开放性的判定由 ActionTarget 在登记时承担，因此位于本合约账本写入之后，失败整笔回滚。 |
| E-LP-04 | Info | `src/LpExecutor.sol:200-207` | 同一「无余额」状态在两个入口给出两个错误：`withdraw(amount>0)` 回 `WithdrawAmountExceeded(amount, 0)`，`exit` 回 `NotJoined(...)`。04 的表格把两者分列，属有意区分（撤回是额度条件、退出是状态条件），已核对；但调用方需要先知道「哪个入口」才能解释错误。 | error-standards §2（一个条件一个错误）/ §6（Transition 语义） | 无需改实现；建议在 04 的表格下补一句「`withdraw` 不判加入态，余额为零一律回 `WithdrawAmountExceeded`」。 |

### 4.2 已核对项

- 声明全部在 `ILpExecutorErrors`；`NotMemberOwner` / `RoundNotStarted` / `ActionNotCreated` / `RoundBeforeActionCreated` / `RoundAfterMintWindow` / `RewardAlreadyMinted` / `MemberActionRewardUnavailable` 复用基座声明，符合 07。
- 创建回调顺序：项数 → 每项 32 字节 → 零地址 → 工厂登记 → `minGovRatio` 上界，与 04 表格逐条一致；`InvalidJoinTokenFactory(joinToken, factory)` 的「主体 → 来源」顺序符合 §4「外部：source」。
- `InsufficientGovRatio(required, actual)` 的 required 在前，符合 §4「额度：`required + available`」；core 侧被判过的 `InsufficientLaunchCount(available, required)` 反例在这里没有重演。
- `WithdrawAmountExceeded(amount, joined)` 的「实际值 → 上限」顺序符合 §4。
- `_calculateReward` 在 `govRatioMultiplier == 0` 时直接返回理论值、在社区总治理票为 0 时返回 `(0, theoreticalReward)`，与 04「乘数为 0 关闭上限」「总治理票为 0 时全部销毁」一致；无除零路径（`totalEffectiveAmount == 0` 在 `_pendingMemberReward` 与 `_mintMemberReward` 都提前返回）。
- `_isRegisteredPair` 对 `token0`/`token1`/`getPair` 三次外呼都用 `try/catch` 归一为 `false`（→ `InvalidJoinTokenFactory`），符合 §7「调用方任意输入：形态校验，失败归 `Invalid*`」。
- 全额撤回与 `exit` 的事件顺序为「清状态 → 退款 → `LpWithdrawn` → `clearJoinState` → `LpExited`」，与 04 及事件规范 §4.4 一致。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `onlyMemberOwner`；来源 `MemberNFT`。
- `SafeERC20FailedOperation` / `AddressEmptyCode` — `safeTransfer` / `safeTransferFrom`；来源 OZ。
- `ReentrancyGuardReentrantCall` — `nonReentrant`；来源 OZ。
- `ProposalNotVoted` / `ProposalRewardAlreadyMinted` / `RoundNotEnded` / `ProposalBelowThreshold` / `ProposalPoolEmpty` / `ProposalRewardRoundedToZero` — `mintActionReward` → ActionTarget → Mint。来源 ABI：`IActionTargetErrors` / `IMint`。
- `PhaseNotStarted` — `IPhase.phaseInfo`（仅在 Phase 未初始化时）；来源 `IPhase`。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。`_isRegisteredPair` 的三处 `catch` 不计站点（不 `revert`，归一为布尔）。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-LP-01 | Info | 已裁决（W1 #5 + 量纲拆分）：成员级拆为 `ZeroEffectiveJoinAmount`（LP 有效加入量为零，原 `MemberHasNoVote` 槽位）、`MemberRewardPoolEmpty` / `MemberRewardRoundedToZero` 保持与 core 同名；`LpExecutor` 4 个出口、`IActionExecutor` 声明同步、测试 2 处同步；规格 04/07/08 同步。 |
| E-LP-02 | Info | 已裁决（X-09 文档）：04 补 `govRatioMultiplier` 无上界、安全性依赖 `mulDiv` 不溢出。 |
| E-LP-03 | Info | 已裁决（X-09 文档）：04 登记「账本先写、`registerJoinState` 后写」的自定义顺序。 |
| E-LP-04 | Info | 已裁决（X-09 文档）：04 登记 `withdraw` 与 `exit` 两个「无余额」错误的语义差异，保留双错误。 |
