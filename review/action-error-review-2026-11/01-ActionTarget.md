# `action/ActionTarget.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/01-action-target.md`。
> 范围：`src/ActionTarget.sol`（531 行）+ `src/interfaces/IActionTarget.sol` 的 `IActionTargetErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 15 个错误声明 / 20 个发送点；声明与站点一一覆盖，无未声明 revert、无裸 `require`、无 `assert`。
- 站点全部落在会整笔回滚的路径上；唯一的跨合约外呼（Executor 握手、Mint 铸造）失败同样整笔回滚，无状态残留。
- `try/catch` 的语义是本文件最容易写错的一处，已用最小复现实测：success 块内的 `revert` **不会**被同一 `try` 的 `catch` 捕获，因此 `ExecutorTargetMismatch` 与 `ExecutorHandshakeFailed` 互斥且都可达（见 4.2）。
- 主要问题集中在载荷表达式与顺序口径，无资金风险：3 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 15 |
| revert 站点 | 20 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 3 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `AlreadyInitialized` | `AlreadyInitialized()` | IActionTargetErrors | 1 | 保留 |
| `UnauthorizedExecutor` | `UnauthorizedExecutor(address,uint256)` | IActionTargetErrors | 1 | 保留 |
| `NotSubmit` | `NotSubmit(address)` | IActionTargetErrors | 1 | 保留 |
| `NotVote` | `NotVote(address)` | IActionTargetErrors | 1 | 保留 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | IActionTargetErrors | 1 | 保留 |
| `JoinNotOpen` | `JoinNotOpen(address,uint256,uint256,uint256)` | IActionTargetErrors | 1 | 保留 |
| `ProposalNotVoted` | `ProposalNotVoted(address,uint256)` | IActionTargetErrors | 1 | 口径调整 |
| `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | IActionTargetErrors | 2 | 口径调整 |
| `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | IActionTargetErrors | 3 | 保留 |
| `ExecutorNotContract` | `ExecutorNotContract(address)` | IActionTargetErrors | 1 | 保留 |
| `ExecutorTargetMismatch` | `ExecutorTargetMismatch(address,address)` | IActionTargetErrors | 1 | 保留 |
| `ExecutorHandshakeFailed` | `ExecutorHandshakeFailed(address)` | IActionTargetErrors | 1 | 保留 |
| `AlreadyCreated` | `AlreadyCreated(address,uint256)` | IActionTargetErrors | 1 | 保留 |
| `UnboundProposal` | `UnboundProposal(address,uint256)` | IActionTargetErrors | 2 | 保留 |
| `TargetDataExecutorMismatch` | `TargetDataExecutorMismatch(address,address)` | IActionTargetErrors | 2 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:35`
- 签名：`AlreadyInitialized()` · selector `0x0dc149f0`
- 载荷：无
- 核对：无载荷；`init` 的自身状态判定，符合 §5.4 的重复初始化语义。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:53` | `function init` | `initialized` | `—` |

### `UnauthorizedExecutor` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:43`
- 签名：`UnauthorizedExecutor(address,uint256)` · selector `0x89d3c18e`
- 载荷：`address tokenAddress, uint256 actionId`
- 核对：判据为「调用者不是该行动已绑定的 Executor」；未注册绑定是该条件的子集，规格 01 明文。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:72` | `modifier onlyBoundExecutor` | `!_isBoundExecutor(tokenAddress, actionId)` | `tokenAddress, actionId` |

### `NotSubmit` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:36`
- 签名：`NotSubmit(address)` · selector `0x3c7708ea`
- 载荷：`address caller`
- 核对：载荷为调用者地址（§4 主体键）；创建与推举回调共用同一 modifier，条件一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:79` | `modifier onlySubmit` | `msg.sender != SUBMIT_ADDRESS` | `msg.sender` |

### `NotVote` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:37`
- 签名：`NotVote(address)` · selector `0x20edde6a`
- 载荷：`address caller`
- 核对：同上，`onProposalVoted` 专用；两者共用 `caller` 语义，未合并成通用 `NotAuthorized`，符合 §2 的「不得用通用名承载多个条件」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:86` | `modifier onlyVote` | `msg.sender != VOTE_ADDRESS` | `msg.sender` |

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:38`
- 签名：`NotMemberOwner(uint256)` · selector `0x33393244`
- 载荷：`uint256 memberId`
- 核对：载荷为身份键；`forceClearJoinState` 专用。`ownerOf` 在身份不存在时先回透传 `ERC721NonexistentToken`，与 §5「身份解析属于鉴权」一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:93` | `modifier onlyMemberOwner` | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `memberId` |

### `JoinNotOpen` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:47`
- 签名：`JoinNotOpen(address,uint256,uint256,uint256)` · selector `0x81013803`
- 载荷：`address tokenAddress, uint256 actionId, uint256 currentRound, uint256 createdRound`
- 核对：四字段按「主体键 → 条件值」排列；`currentRound` 是当前投票轮、`createdRound` 是创建轮，与 01 的「加入在投票后一个阶段开放」同源。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:121` | `function registerJoinState` | `currentRound <= createdRound` | `tokenAddress, actionId, currentRound, createdRound` |

### `ProposalNotVoted` · 1 站点 · 口径调整

- 声明：`interfaces/IActionTarget.sol:53`
- 签名：`ProposalNotVoted(address,uint256)` · selector `0x82bbc7fd`
- 载荷：`address tokenAddress, uint256 proposalId`
- 核对：载荷字段名 `proposalId` 与实参 `actionId` 不一致，见 E-AT-03；条件本身单一（`isProposalIdVoted` 为假，涵盖无票与未达门槛，规格 07 表同样写作「无票或未达门槛」）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:270` | `function mintActionReward` | `!IVote(VOTE_ADDRESS).isProposalIdVoted(tokenAddress, round, actionId)` | `tokenAddress, actionId` |

### `TargetDataLengthMismatch` · 2 站点 · 口径调整

- 声明：`interfaces/IActionTarget.sol:57`
- 签名：`TargetDataLengthMismatch(uint256,uint256)` · selector `0x232f36be`
- 载荷：`uint256 expected, uint256 actual`
- 核对：两处 `actual` 曾硬编码为 `0`（W1 已改写为 `targetData.length`），见 E-AT-01；`expected = TARGET_DATA_LENGTH` 表示下界（至少 1 项），与 Executor 侧「恰为 N 项」的用法不同义，属 §4「边界参数用限定名」的擦边（`expected` 未表达「下界」）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:432` | `function onProposalCreated` | `targetData.length < TARGET_DATA_LENGTH` | `targetData.length, TARGET_DATA_LENGTH` |
| 2 | `ActionTarget.sol:485` | `function onProposalSubmitted` | `targetData.length < TARGET_DATA_LENGTH` | `targetData.length, TARGET_DATA_LENGTH` |

### `InvalidTargetDataShape` · 3 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:61`
- 签名：`InvalidTargetDataShape(uint256,uint256)` · selector `0x9c2b3988`
- 载荷：`uint256 index, uint256 length`
- 核对：三处 `index` 恒为 0（executor 保留项），符合 01「本层只读第 0 项」；`length` 为该项实际字节数。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:432` | `function onProposalCreated` | `targetData[0].length != 32` | `0, targetData[0].length` |
| 2 | `ActionTarget.sol:485` | `function onProposalSubmitted` | `targetData[0].length != 32` | `0, targetData[0].length` |
| 3 | `ActionTarget.sol:514` | `function onProposalVoted` | `targetData[0].length != 32` | `0, targetData[0].length` |

### `ExecutorNotContract` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:65`
- 签名：`ExecutorNotContract(address)` · selector `0xa6585817`
- 载荷：`address executor`
- 核对：`code.length == 0` 覆盖零地址与 EOA，符合 §3。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:436` | `function onProposalCreated` | `executor.code.length == 0` | `executor` |

### `ExecutorTargetMismatch` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:66`
- 签名：`ExecutorTargetMismatch(address,address)` · selector `0x77523042`
- 载荷：`address expected, address actual`
- 核对：实参 `(address(this), acknowledged)` 顺序符合 §4「expected + actual」；只在握手成功但自报地址不符时触发。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:440` | `function onProposalCreated` | `acknowledged != address(this)` | `address(this), acknowledged` |

### `ExecutorHandshakeFailed` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:70`
- 签名：`ExecutorHandshakeFailed(address)` · selector `0x4042953c`
- 载荷：`address executor`
- 核对：`catch` 分支，条件是「握手调用本身回滚」；与 `ExecutorTargetMismatch` 互斥（实测见 4.2）。规格 01 要求「归一为」该错误，实现无 selector 转译、直接吞掉原始 revert data，符合 §7「非预期失败不映射成领域错误」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:443` | `function onProposalCreated` | ``catch`（握手调用本身回滚）` | `executor` |

### `AlreadyCreated` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:75`
- 签名：`AlreadyCreated(address,uint256)` · selector `0xca699de2`
- 载荷：`address tokenAddress, uint256 actionId`
- 核对：第 4 步、晚于握手外呼，见 E-AT-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:446` | `function onProposalCreated` | `_executorByActionId[tokenAddress][proposalId] != address(0)` | `tokenAddress, proposalId` |

### `UnboundProposal` · 2 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:39`
- 签名：`UnboundProposal(address,uint256)` · selector `0x283a3095`
- 载荷：`address tokenAddress, uint256 proposalId`
- 核对：两站点同一条件（推举/投票回调遇到未绑定键）；规格注明结构上不可达，仅防御 Core 侧缺陷，属 §8 允许的「防御不可达」——但它是**可达声明 + 不可达站点**，与「不可达错误应删除」不冲突（见 4.2）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:479` | `function onProposalSubmitted` | `bound == address(0)` | `tokenAddress, proposalId` |
| 2 | `ActionTarget.sol:510` | `function onProposalVoted` | `bound == address(0)` | `tokenAddress, proposalId` |

### `TargetDataExecutorMismatch` · 2 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:71`
- 签名：`TargetDataExecutorMismatch(address,address)` · selector `0xb4d298bc`
- 载荷：`address expected, address actual`
- 核对：`(bound, targetDataExecutor)` 顺序正确；推举与投票共用，条件一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `ActionTarget.sol:489` | `function onProposalSubmitted` | `targetDataExecutor != bound` | `bound, targetDataExecutor` |
| 2 | `ActionTarget.sol:518` | `function onProposalVoted` | `targetDataExecutor != bound` | `bound, targetDataExecutor` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-AT-01 | Info | `src/ActionTarget.sol:429`、`:482` | `TargetDataLengthMismatch(1, 0)` 的第二个实参写成字面量 `0`，而不是条件里的 `targetData.length`。当前分支下两者恒等，但载荷不再由判据表达式派生：条件一旦改成 `length < 1` 之外的形态，日志会给出错误的 `actual`。 | error-standards §4（载荷以声明为唯一来源，实参应取自判据） | 改为 `revert TargetDataLengthMismatch(1, targetData.length);`。 |
| E-AT-02 | Info | `src/ActionTarget.sol:438-447` | `AlreadyCreated` 排在对 Executor 的握手外呼之后（规格列为第 4 步）。§5 的顺序是「状态/资格 → 账本/交互」，此处把状态判定放在交互之后，规格 01 也未按 §5 要求写明理由。可观测后果：对同一 `(tokenAddress, actionId)` 的重复创建回调仍会先执行一次外部调用，若该 Executor 此后失效，调用方拿到的是 `ExecutorHandshakeFailed` 而不是 `AlreadyCreated`。 | error-standards §5（顺序固定，自定义顺序须写明理由） | 在 01-action-target.md 的编号列表后补一句理由（“先验 Executor 再查重，避免把不可用 Executor 登记为创建失败原因”），或把 `AlreadyCreated` 提到握手之前。 |
| E-AT-03 | Info | `src/ActionTarget.sol:270` | `ProposalNotVoted` 声明参数名为 `proposalId`，实现传入的是 `actionId`。二者是规格明文规定的同值别名（`proposalId == actionId`），但载荷字段名与本模块调用点的语义不一致，链下按参数名生成的文档会误导集成方。 | error-standards §4（载荷字段名按本模块语义） | 声明改名 `ProposalNotVoted(address tokenAddress, uint256 actionId)`（仅参数名，selector 不变）。 |

### 4.2 已核对项

- 声明全部在 `IActionTargetErrors`，实现文件零声明；`check_errors.py --check` 0 violations。
- `ExecutorNotContract(executor)` 用 `code.length == 0` 同时覆盖零地址与 EOA，符合 §3「必填合约依赖只保留 `*NotContract`，零地址由 `*NotContract(0)` 覆盖」。
- `UnauthorizedExecutor` 的判据是 `bound != address(0) && bound == msg.sender` 的否定，未注册绑定与绑定他人共用一个 selector；规格 01「写操作权限」明文如此（“未注册绑定时任何调用者都拒绝”），属单一条件「调用者不是该行动已绑定的 Executor」。
- `registerJoinState` 的 `JoinNotOpen` 载荷顺序为 `(tokenAddress, actionId, currentRound, createdRound)`，主体键在前、条件值在后，符合 §4。
- `onProposalVoted` 在 `targetData` 为空时整体跳过第 0 项校验并原样转发，与 01 的「投票回调可为空」一致。
- **`try/catch` 语义实测**（`/tmp/tctest`，solc 0.8.37）：success 块内 `revert Mismatch(...)` 冒泡为 `0x8b3096fc`（`Mismatch`），未被同 `try` 的 `catch` 归一为 `0xd8aa3c9b`（`HandshakeFailed`）；内层调用自身 revert 时才进 `catch`。因此 `ExecutorTargetMismatch` 可达、`ExecutorHandshakeFailed` 仅覆盖「握手调用本身失败」，与 01 的表述一致。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `onlyMemberOwner` 的 `IMemberNFT.ownerOf(memberId)`；`memberId` 不存在时先于 `NotMemberOwner` 抛出。来源 ABI：`MemberNFT` / OZ `IERC721Errors`。
- `ProposalRewardAlreadyMinted` / `RoundNotEnded` / `ProposalBelowThreshold` / `ProposalPoolEmpty` / `ProposalRewardRoundedToZero` / `ZeroRecipientAddress` — `mintActionReward` → `Mint.mintProposalReward`。来源 ABI：`IMint`。规格 07 只登记了 `ProposalRewardAlreadyMinted`，其余 5 个未登记。
- `PhaseNotStarted`（若 `Phase` 未初始化）— `_currentRound()`。来源 ABI：`IPhase`。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/ActionTarget.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`，`catch` 分支单独标注。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-AT-01 | Info | 已裁决（W1 #1）：两站点改写为 `InsufficientTargetDataItems(targetData.length, 1)`，`(1, 0)` 字面量消除；`ActionTarget.t.sol` 两处断言同步。 |
| E-AT-02 | Info | 已裁决（文档口径）：保留「握手先于重复创建」，规格 01 第 4 步补顺序理由；不改实现。 |
| E-AT-03 | Info | 已裁决（文档口径）：`ProposalNotVoted` 声明参数名 `proposalId` → `actionId`，selector 不变，无站点改动。 |
