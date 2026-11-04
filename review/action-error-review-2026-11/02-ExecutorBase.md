# `action/ExecutorBase.sol` 错误赋值与发送专项 Review

> 基线：`action@2014788`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/00-executor-interface.md、02-phase-model.md、07-minting.md`。
> 范围：`src/ExecutorBase.sol`（140 行）+ `src/interfaces/IActionExecutor.sol` 的 `IActionExecutorErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 9 个错误声明 / 10 个发送点；三个 Executor 共用的鉴权、批量、轮次与结算窗口守卫都落在这里，声明与站点一一覆盖。
- `_checkMintWindow` 的四段顺序（未创建 → 早于创建轮 → 超过铸币轮 → 已结算）与 04 的表格逐条一致，是三个 Executor 共用的唯一结算顺序来源。
- `mintMemberRewards` 的批量形状错误排在鉴权之后，符合 07「批量入口同样先鉴权」与 08「空数组也需通过鉴权」。
- 无 Medium / Low；2 条 Info 均为写法与透传登记口径。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 9 |
| revert 站点 | 10 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 2 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | IActionExecutorErrors | 1 | 保留 |
| `NotActionTarget` | `NotActionTarget(address)` | IActionExecutorErrors | 1 | 保留 |
| `BatchLengthMismatch` | `BatchLengthMismatch(uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |
| `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | IActionExecutorErrors | 3 | 口径调整 |
| `ActionNotCreated` | `ActionNotCreated(address,uint256)` | IActionExecutorErrors | 1 | 保留 |
| `RoundBeforeActionCreated` | `RoundBeforeActionCreated(uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |
| `RoundAfterMintWindow` | `RoundAfterMintWindow(uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |
| `RewardAlreadyMinted` | `RewardAlreadyMinted(address,uint256,uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:23`
- 签名：`NotMemberOwner(uint256)` · selector `0x33393244`
- 载荷：`uint256 memberId`
- 核对：载荷为身份键；三个 Executor 与 `GroupActionJoin` / `GroupActionVerify` 的本地 modifier 共用同一 selector，属 §1 允许的重复声明。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:31` | `modifier onlyMemberOwner` | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `memberId` |

### `NotActionTarget` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:18`
- 签名：`NotActionTarget(address)` · selector `0x67b7e647`
- 载荷：`address caller`
- 核对：载荷为调用者地址；三类回调共用，条件一致。规格 07 明确该错误「按同签名共用规则声明在基座」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:38` | `modifier onlyActionTarget` | `msg.sender != ACTION_TARGET_ADDRESS` | `msg.sender` |

### `BatchLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:36`
- 签名：`BatchLengthMismatch(uint256,uint256)` · selector `0x81b5b207`
- 载荷：`uint256 actionIdsLength, uint256 roundsLength`
- 核对：形状错误，两个长度都进载荷；排在鉴权之后，符合 07。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:73` | `function mintMemberRewards` | `length != rounds.length` | `length, rounds.length` |

### `RoundNotStarted` · 3 站点 · 口径调整

- 声明：`interfaces/IActionExecutor.sol:40`
- 签名：`RoundNotStarted(uint256,uint256)` · selector `0xea74f32b`
- 载荷：`uint256 requiredRound, uint256 currentRound`
- 核对：三站点同义不同写法，见 E-EB-01；`requiredRound` 恒为 1，`currentRound` 恒为 0。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:86` | `function currentVoteRound` | `phase < 1` | `1, phase` |
| 2 | `ExecutorBase.sol:94` | `function currentJoinRound` | `round == 0` | `1, 0` |
| 3 | `ExecutorBase.sol:102` | `function currentMintRound` | `round == 0` | `1, 0` |

### `ActionNotCreated` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:19`
- 签名：`ActionNotCreated(address,uint256)` · selector `0x36c193ae`
- 载荷：`address tokenAddress, uint256 actionId`
- 核对：结算第一段守卫，`createdRound == 0`；规格 05「行动存在性判定统一回滚 `ActionNotCreated`」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:116` | `function _checkMintWindow` | `createdRound == 0` | `tokenAddress, actionId` |

### `RoundBeforeActionCreated` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:44`
- 签名：`RoundBeforeActionCreated(uint256,uint256)` · selector `0x1edd1ded`
- 载荷：`uint256 round, uint256 createdRound`
- 核对：第二段，`(round, createdRound)` 顺序为「实际值 → 下界」，符合 04「两段不合并」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:119` | `function _checkMintWindow` | `round < createdRound` | `round, createdRound` |

### `RoundAfterMintWindow` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:48`
- 签名：`RoundAfterMintWindow(uint256,uint256)` · selector `0x45297019`
- 载荷：`uint256 round, uint256 mintRound`
- 核对：`(round, mintRound)`；`mintRound = 0` 时任何 `round >= 1` 都命中，与 04 表「铸币阶段未开始时任何轮次都不在有效阶段」一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:123` | `function _checkMintWindow` | `round > mintRound` | `round, mintRound` |

### `RewardAlreadyMinted` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:24`
- 签名：`RewardAlreadyMinted(address,uint256,uint256,uint256)` · selector `0xf41a3e9f`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId, uint256 round`
- 核对：四字段为「主体键（token/action/member）→ 条件值（round）」；排在最后一段，重复结算优先于其它判定之后的语义正确。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ExecutorBase.sol:126` | `function _checkMintWindow` | `alreadyMinted` | `tokenAddress, actionId, memberId, round` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-EB-01 | Info | `src/ExecutorBase.sol:86` | `currentVoteRound` 写 `RoundNotStarted(1, phase)`，而 `currentJoinRound` / `currentMintRound` 写 `RoundNotStarted(1, 0)`。三个站点语义相同（`currentRound` 恒为 0），写法却不一致：前者依赖「`phase < 1` 时 `phase` 必为 0」这一隐含事实，后者直接写字面量。 | error-standards §4（载荷取自判据）/ §2（同一条件同一表达） | 统一为 `revert RoundNotStarted(1, 0);`，或在 02-phase-model 里说明 `currentVoteRound` 的 `currentRound` 直接取 `phase`。 |
| E-EB-02 | Info | `src/ExecutorBase.sol:56`、`:60-69` | `nonReentrant` 排在 `onlyMemberOwner` 之前，因此重入路径先回 OZ 的 `ReentrancyGuardReentrantCall`，不会回 `NotMemberOwner`。这不是缺陷（重入本身就该先拒绝），但该 selector 属透传面，07 的透传登记表只列了 `ERC721NonexistentToken` / `SafeERC20FailedOperation`，未列 `ReentrancyGuardReentrantCall`。 | error-standards §1 / §5（透传来源表） | 在 07-minting.md 的透传登记里补 `ReentrancyGuardReentrantCall`（来源 OZ `ReentrancyGuard`）与 `AddressEmptyCode`（来源 OZ `Address`）。 |

### 4.2 已核对项

- 声明全部在 `IActionExecutorErrors`，实现零声明；9 个声明在三个 Executor 与两个 GroupAction 库里被复用，符合 07「共用且签名一致的 9 个错误声明在基座」。
- `NotMemberOwner` 在 `IActionTargetErrors` 与 `IActionExecutorErrors` 各声明一次（同签名、selector 相同 `0x33393244`），符合 §1「相同条件允许本地重复声明」。
- `BatchLengthMismatch(actionIdsLength, roundsLength)` 用两数组各自长度作载荷，能定位哪一侧不等长，符合 §4「批量：失败元素键或索引」。
- `_checkMintWindow` 的 `alreadyMinted` 由调用方从 storage 读入，三处调用（`LpExecutor:492`、`GroupActionExecutor:712`、`GroupServiceExecutor:714`）传的都是各自的 `memberMinted` 位，无遗漏。
- `currentJoinRound` / `currentMintRound` 的 `RoundNotStarted(1, 0)` 与 02-phase-model「`requiredRound` 为 1、`currentRound` 为推导出的 0」一致。
- 空数组批量结算在鉴权后返回空结果、不改状态（`:76-81`），符合 07 的「空数组在鉴权通过后返回空结果」。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `onlyMemberOwner` 的 `ownerOf`；来源 `MemberNFT`。
- `ReentrancyGuardReentrantCall` — `nonReentrant`；来源 OZ `ReentrancyGuard`（未在 07 登记）。
- `SafeERC20FailedOperation` / `AddressEmptyCode` — 各 Executor 的 `safeTransfer(From)`；来源 OZ `SafeERC20` / `Address`。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01；`modifier` 内的站点函数名记为 `modifier <name>`。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-EB-01 | Info | 已裁决（文档口径）：`RoundNotStarted(1, phase)` 与 `(1, 0)` 在 `phase < 1` 时载荷等价，规格 00/07 以 `(1, 0)` 为规范写法，不改 src。 |
| E-EB-02 | Info | 已裁决（文档口径）：保留 `nonReentrant` 先于 `onlyMemberOwner`（OZ 惯例），规格 00 登记，非缺陷。 |
