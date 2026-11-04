# `action/GroupServiceExecutor.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/06-service-executor.md、02-phase-model.md、07-minting.md`。
> 范围：`src/GroupServiceExecutor.sol`（800 行）+ `src/interfaces/IGroupServiceExecutor.sol` 的 `IGroupServiceExecutorErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 10 个错误声明 / 13 个发送点（含 2 个基座复用）；无未声明 revert、无裸 `require`、无 `assert`。
- `_mintMemberReward` 里有两处完全相同的 `MemberActionRewardUnavailable` 守卫，第二处（`:730`）在 Mint 的返回值与理论值同源的前提下不可达。
- `join` 与 `exit` 的状态判定顺序相反（`join` 先判轮次、`exit` 先判加入态），对称入口不一致。
- `join` 对未创建的服务行动不判 `ActionNotCreated`，由 `NotQualified(0, round, memberId)` 兜住，载荷指向零地址。
- 1 条 Low + 4 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 10 |
| revert 站点 | 13 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 1 / 4 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `GroupNotExist` | `GroupNotExist(uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `NotGroupOwner` | `NotGroupOwner(uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `AlreadyJoined` | `AlreadyJoined(address,uint256,uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `NotQualified` | `NotQualified(address,uint256,uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `NotJoined` | `NotJoined(address,uint256,uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | IGroupServiceExecutorErrors | 2 | 保留 |
| `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `ZeroActionTokenAddress` | `ZeroActionTokenAddress()` | IGroupServiceExecutorErrors | 1 | 保留 |
| `InvalidRatioForPublicVerifier` | `InvalidRatioForPublicVerifier(uint256)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `ActionTokenParentMismatch` | `ActionTokenParentMismatch(address,address,address)` | IGroupServiceExecutorErrors | 1 | 保留 |
| `MemberActionRewardUnavailable` | `MemberActionRewardUnavailable(address,uint256,uint256,uint256)` | IActionExecutorErrors | 2 | 口径调整 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `GroupNotExist` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:82`
- 签名：`GroupNotExist(uint256)` · selector `0xfeddf96a`
- 载荷：`uint256 groupId`
- 核对：`onlyGroupOwner` 里由 `ownerOrZero` 返回 0 触发；本地声明，见 E-GSE-05。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:59` | `modifier onlyGroupOwner` | `owner == address(0)` | `groupId` |

### `NotGroupOwner` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:83`
- 签名：`NotGroupOwner(uint256)` · selector `0x54a55079`
- 载荷：`uint256 groupId`
- 核对：`(groupId)`；排在存在性之后，符合 §5「身份解析属于鉴权」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:62` | `modifier onlyGroupOwner` | `owner != msg.sender` | `groupId` |

### `AlreadyJoined` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:77`
- 签名：`AlreadyJoined(address,uint256,uint256)` · selector `0x8a8846f7`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId`
- 核对：三字段为服务行动主体键；条件是「已加入」，与 `NotJoined` 互斥。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:121` | `function join` | `IActionTarget(ACTION_TARGET_ADDRESS).isJoined(serviceTokenAddress, serviceActionId, memberId)` | `serviceTokenAddress, serviceActionId, memberId` |

### `NotQualified` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:52`
- 签名：`NotQualified(address,uint256,uint256)` · selector `0xd52b235e`
- 载荷：`address actionTokenAddress, uint256 round, uint256 memberId`
- 核对：`(actionTokenAddress, round, memberId)`；`round` 为被加入轮，与 06 一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:126` | `function join` | `!_isQualified(sourceTokenAddress, round, memberId)` | `sourceTokenAddress, round, memberId` |

### `NotJoined` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:72`
- 签名：`NotJoined(address,uint256,uint256)` · selector `0x847d1a6f`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId`
- 核对：三字段；`exit` 专用，排在轮次判定之前，见 E-GSE-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:378` | `function exit` | `!IActionTarget(ACTION_TARGET_ADDRESS).isJoined(tokenAddress, actionId, memberId)` | `tokenAddress, actionId, memberId` |

### `TargetDataLengthMismatch` · 2 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:64`
- 签名：`TargetDataLengthMismatch(uint256,uint256)` · selector `0x232f36be`
- 载荷：`uint256 expected, uint256 actual`
- 核对：创建「恰 4 项」与投票「最多 1 项」，两端各自单一。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:399` | `function onProposalCreated` | `targetData.length != 4` | `4, targetData.length` |
| 2 | `GroupServiceExecutor.sol:448` | `function onProposalVoted` | `targetData.length > 1` | `1, targetData.length` |

### `InvalidTargetDataShape` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:68`
- 签名：`InvalidTargetDataShape(uint256,uint256)` · selector `0x9c2b3988`
- 载荷：`uint256 index, uint256 length`
- 核对：循环 `i = 0..3`，能定位失败项。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:404` | `function onProposalCreated` | `targetData[i].length != 32` | `i, targetData[i].length` |

### `ZeroActionTokenAddress` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:57`
- 签名：`ZeroActionTokenAddress()` · selector `0x95bf90a9`
- 载荷：无
- 核对：非合约参数零值，符合 §3；字段名与 `actionTokenAddress` 一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:413` | `function onProposalCreated` | `sourceTokenAddress == address(0)` | `—` |

### `InvalidRatioForPublicVerifier` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:58`
- 签名：`InvalidRatioForPublicVerifier(uint256)` · selector `0x790182dd`
- 载荷：`uint256 value`
- 核对：`> 1e18`；载荷为越界值。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:416` | `function onProposalCreated` | `publicVerifierRatioValue > PRECISION` | `publicVerifierRatioValue` |

### `ActionTokenParentMismatch` · 1 站点 · 保留

- 声明：`interfaces/IGroupServiceExecutor.sol:59`
- 签名：`ActionTokenParentMismatch(address,address,address)` · selector `0x4757480b`
- 载荷：`address actionTokenAddress, address serviceTokenAddress, address actualParentTokenAddress`
- 核对：三地址齐备（行动代币、服务代币、实际父币），符合 06 的载荷要求。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:421` | `function onProposalCreated` | `parentTokenAddress != tokenAddress` | `sourceTokenAddress, tokenAddress, parentTokenAddress` |

### `MemberActionRewardUnavailable` · 2 站点 · 口径调整

- 声明：`interfaces/IActionExecutor.sol:30`（跨模块复用，本模块不重复声明）
- 签名：`MemberActionRewardUnavailable(address,uint256,uint256,uint256)` · selector `0x4cd933ce`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId, uint256 round`
- 核对：两站点同条件；第二处不可达，见 E-GSE-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupServiceExecutor.sol:721` | `function _mintMemberReward` | `mintAmount == 0 && burnAmount == 0` | `tokenAddress, actionId, memberId, round` |
| 2 | `GroupServiceExecutor.sol:731` | `function _mintMemberReward` | `mintAmount == 0 && burnAmount == 0` | `tokenAddress, actionId, memberId, round` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GSE-01 | Low | `src/GroupServiceExecutor.sol:724-733` | 第二处 `MemberActionRewardUnavailable` 不可达。`:717` 的 `_settlement` 在 `serviceReward == 0` 时已提前返回，因此走到 `:720` 且未回滚，意味着 `mintAmount != 0`、`serviceReward != 0`；`:726` 的 `mintActionReward` 返回值与 `actionReward` 的理论值同源（`Mint.mintProposalReward` 直接返回 `_proposalRewardCalculation` 的同一结果，`core/src/Mint.sol:203`），`_applyFormulas` 用相同输入重算必得相同结果（它重读的 `currentPhase` 与治理票在同一笔内不变），`:730` 的判据恒为假。 | error-standards §8（不保留不可达路径） | 删除 `:730-732` 的重复守卫，或改成 `assert(mintAmount != 0 || burnAmount != 0);` 表达「铸造后金额不得变化」这一不变式。 |
| E-GSE-02 | Info | `src/GroupServiceExecutor.sol:118-126`、`:377-381` | `join` 的顺序是 `currentJoinRound` → `AlreadyJoined` → `NotQualified`，`exit` 的顺序是 `NotJoined` → `currentJoinRound`。两个对称入口对「阶段未开始」与「加入态不符」的优先级相反：阶段未开始时 `exit` 一个从未加入的成员会回 `NotJoined` 而不是 `RoundNotStarted`。 | error-standards §5（同一模块内一致） | 把 `exit` 的 `currentJoinRound()` 提到 `NotJoined` 之前，与 `join` 对齐。 |
| E-GSE-03 | Info | `src/GroupServiceExecutor.sol:124-127` | `join` 对未创建（或已创建但 `actionTokenAddress` 未写入）的服务行动不判 `ActionNotCreated`：`sourceTokenAddress` 读到 `address(0)`，`_isQualified(0, round, memberId)` 必然为假，于是回 `NotQualified(0, round, memberId)`。载荷里的零地址无法区分「服务行动不存在」与「资格不足」，且前者应先于资格判定（§5 的存在性层）。 | error-standards §5 / §4（可定位） | 在 `_isQualified` 之前加 `if (createdRound == 0) revert ActionNotCreated(serviceTokenAddress, serviceActionId);`。 |
| E-GSE-04 | Info | `src/GroupServiceExecutor.sol:720`、`:730` | 与 LP 同族的「一错多因」：`MemberActionRewardUnavailable` 同时承载「未加入该轮」「权重为 0」「分母为 0」「服务激励为 0」「逐项取整为 0」五种成因。规格 06 把它们并列写成「两个分子都为零时不读取分母，结算入口按零额规则回滚」，即按结果条件定义，与 LP 的口径一致（见 E-LP-01）。 | error-standards §2 / §4 | 与 E-LP-01 一并处置：在 07 的错误表里统一写明「该错误是结果条件」。 |
| E-GSE-05 | Info | `src/GroupServiceExecutor.sol:56-65` | `onlyGroupOwner` 用裸名 `GroupNotExist` / `NotGroupOwner` 引用本地 `IGroupServiceExecutorErrors` 的声明，而 `GroupActionManager` / `GroupActionJoin` 对同名错误一律用限定名。语义与声明归属都正确（§1 的「本地声明」），只是可读性上难以一眼看出这两个错误是本地声明还是从别处导入。 | dev-standards（可读性）/ §1 | 改为 `revert IGroupServiceExecutorErrors.GroupNotExist(groupId);` 的限定写法，与全仓一致。 |

### 4.2 已核对项

- 声明全部在 `IGroupServiceExecutorErrors`；`NotMemberOwner` / `RoundNotStarted` / `ActionNotCreated` / `RoundBeforeActionCreated` / `RoundAfterMintWindow` / `RewardAlreadyMinted` / `BatchLengthMismatch` / `MemberActionRewardUnavailable` 复用基座 `IActionExecutorErrors`，符合 07 的「9 个共享错误声明在基座」。
- 创建回调顺序：项数（恰 4）→ 每项 32 字节 → 行动代币非零 → 公开验证者比例 ≤ 1e18 → 代币关系，与 06 逐条一致；`ActionTokenParentMismatch(actionTokenAddress, serviceTokenAddress, actualParentTokenAddress)` 三字段齐备，符合 06 的载荷要求。
- `NotQualified(actionTokenAddress, round, memberId)` 的 `round` 是**被加入轮**（`currentJoinRound()`），与 06「资格判定用被加入的那一轮」一致。
- `_settlement` 的四段提前返回（未加入 / 权重全零 / 分母为零 / 服务激励为零）都不回滚，视图返回全零、结算入口回零额错误，与 06 的「两个分子都为零时不读取分母」一致。
- `_applyFormulas` 的上限判定用 `cap >= ceilDiv(ownerRatioWeight, denominator)`（`Math.mulDiv(…, 1, …, Ceil)`），与 06「除法形式不会溢出」一致；`ownerBurned = theoreticalOwnerReward - ownerReward` 不下溢。
- 分母缓存写入的判据是 `IMint.isRewardPrepared(settlement.actionTokenAddress, round)`（**行动代币**），与 06「判据必须是行动代币的 `isRewardPrepared`」逐字一致；缓存命中后不再重写。
- `ownerReward == ownerDistributed + ownerRemaining` 由 `remaining = ownerReward - distributed` 保证；`MemberRewardMinted.mintAmount == verifierReward + ownerReward` 由 `:718` 的求和保证。
- `exit` 只写当轮快照、不追回已发生轮，`clearJoinState` 后发 `ServiceExited`，与 06 及事件规范 §4.4 一致。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `onlyMemberOwner` 与 `MemberOwner.ownerOrZero`（后者把该 selector 翻译为 `GroupNotExist`，其余原样冒泡）；来源 `MemberNFT`。
- `SafeERC20FailedOperation` / `AddressEmptyCode` — 成员结算的两笔 `safeTransfer`；来源 OZ。
- `ReentrancyGuardReentrantCall` — `nonReentrant`；来源 OZ。
- `ProposalNotVoted` / `ProposalRewardAlreadyMinted` / `RoundNotEnded` / `ProposalBelowThreshold` / `ProposalPoolEmpty` / `ProposalRewardRoundedToZero` — `mintActionReward` → ActionTarget → Mint。
- `RoundNotStarted` 由 `GroupActionVerify.currentVerifyRound`（`setRecipients` 路径）与 `ExecutorBase.currentJoinRound`（`join` / `exit` 路径）抛出，站点分别记在 `08` 与 `02`。
- `IGroupActionExecutor` / `IGroupRecipients` 抛出的错误经 `delegatecall` 之外的普通外呼冒泡（`generatedActionReward`、`verifierApplication`、`joinTokenAddress` 等），例如 `GroupActionVerify` 的 view 函数不 revert，因此实际可达面很窄。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。`_mintMemberReward` 的两处站点按出现顺序编号，第二处的不可达性论证见 E-GSE-01。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GSE-01 | Low | 已裁决（W1 #5 附带）：删除 `mintMemberReward` 内不可达的第二处零值守卫；删除唯一覆盖它的 `testMintedZeroAfterARichProjectionReverts`；规格 07 不再描述该站点。 |
| E-GSE-02 | Info | 已裁决（X-04 重排）：`exit` 的 `currentJoinRound()` 提到 `NotJoined` 之前；新增 `testExitChecksTheRoundBeforeTheJoinState`。 |
| E-GSE-03 | Info | 已裁决（X-04 重排）：`join` 在轮次后补 `ActionNotCreated`；新增 `testJoinRejectsUncreatedActionBeforeQualification`。 |
| E-GSE-04 | Info | 已裁决（W1 #5 + 量纲拆分）：`Settlement.cause` 驱动三分——成员级 `ZeroRewardWeight`（**有意合并**「未按轮加入」与「验证者/owner 两个权重都为零」两种子成因：`NotJoined` 表达的是 `exit` 的**当前**加入状态且载荷不带 `round`，复用到结算会与「该轮未加入」混淆，故不拆）、轮级 `MemberRewardPoolEmpty`、取整 `MemberRewardRoundedToZero`；测试 6 处改期望；规格 06/07/08 同步。 |
| E-GSE-05 | Info | 已裁决（文档口径）：06 登记裸名 / 限定名引用同名同签名，不影响「一名一签名」。 |
