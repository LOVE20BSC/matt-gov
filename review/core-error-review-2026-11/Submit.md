# `core/Submit.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/05-submit.md`。
> 范围：`src/Submit.sol`（339 行）+ `src/interfaces/ISubmit.sol` 的 `ISubmitErrors`。

## 1. 结论

- 15 个错误声明 / 15 个发送点；覆盖完整，无裸 `require`。
- 两个入口共用 `_checkSubmitPower` 与 `_submitByProposalId`，错误集合与顺序一致（05-submit:147-163）。
- 唯一 Low：`ProposalNotFound` 缺 `tokenAddress`，跨社区日志无法定位（E-SUB-01）。
- `submitNewProposal` 的“创建 + 推举”同笔原子，推举失败时 Proposal 不落地；规格未写明，见 E-SUB-02。其余 2 条 Info 为错误分界与跨模块 oracle 登记。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 15 |
| revert 站点 | 15 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 1 / 3 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `AlreadyInitialized` | `AlreadyInitialized()` | 1 | 保留 |
| `TitleEmpty` | `TitleEmpty()` | 1 | 保留 |
| `TitleTooLong` | `TitleTooLong(uint256,uint256)` | 1 | 保留 |
| `DetailsTooLong` | `DetailsTooLong(uint256,uint256)` | 1 | 保留 |
| `TargetDataTooMany` | `TargetDataTooMany(uint256,uint256)` | 1 | 保留 |
| `TargetDataTooLarge` | `TargetDataTooLarge(uint256,uint256)` | 1 | 保留 |
| `ZeroTargetAddress` | `ZeroTargetAddress()` | 1 | 保留 |
| `CallbackTargetNotContract` | `CallbackTargetNotContract(address)` | 1 | 保留 |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | 1 | 保留 |
| `NoGovVotes` | `NoGovVotes(address)` | 1 | 保留 |
| `ProposalNotFound` | `ProposalNotFound(uint256)` | 1 | 载荷调整 |
| `InsufficientSubmitPower` | `InsufficientSubmitPower(address,uint256,uint256,uint256)` | 1 | 保留 |
| `SubmitRoundFull` | `SubmitRoundFull(address,uint256,uint256)` | 1 | 保留 |
| `ProposalAlreadySubmitted` | `ProposalAlreadySubmitted(address,uint256,uint256)` | 1 | 保留 |
| `MemberAlreadySubmitted` | `MemberAlreadySubmitted(address,uint256,uint256)` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:30`
- 签名：`AlreadyInitialized()`
- 载荷：无
- 核对：无载荷；`init` 自身状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:56` | `init` | `initialized` | `—` |

### `TitleEmpty` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:31`
- 签名：`TitleEmpty()`
- 载荷：无
- 核对：无载荷；`titleLength == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:217` | `_checkProposalBody` | `titleLength == 0` | `—` |

### `TitleTooLong` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:32`
- 签名：`TitleTooLong(uint256,uint256)`
- 载荷：`uint256 length, uint256 maxLength`
- 核对：载荷 `(length, maxLength)`，符合 §4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:218` | `_checkProposalBody` | `titleLength > MAX_TITLE_LENGTH` | `titleLength, MAX_TITLE_LENGTH` |

### `DetailsTooLong` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:36`
- 签名：`DetailsTooLong(uint256,uint256)`
- 载荷：`uint256 length, uint256 maxLength`
- 核对：载荷 `(length, maxLength)`；details 允许为空，只判上限。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:221` | `_checkProposalBody` | `detailsLength > MAX_DETAILS_LENGTH` | `detailsLength, MAX_DETAILS_LENGTH` |

### `TargetDataTooMany` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:40`
- 签名：`TargetDataTooMany(uint256,uint256)`
- 载荷：`uint256 count, uint256 maxCount`
- 核对：载荷 `(count, maxCount)`，符合 §4 尺寸类。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:225` | `_checkProposalBody` | `targetDataCount > MAX_TARGET_DATA_COUNT` | `targetDataCount, MAX_TARGET_DATA_COUNT` |

### `TargetDataTooLarge` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:44`
- 签名：`TargetDataTooLarge(uint256,uint256)`
- 载荷：`uint256 totalLength, uint256 maxLength`
- 赋值链：targetDataBytes ← `Σ bytes(targetData[i]).length`（`Submit.sol:227-232`）。
- 核对：载荷 `(totalLength, maxLength)`；`totalLength` 是逐元素累加值，不是单元素长度。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:232` | `_checkProposalBody` | `targetDataBytes > MAX_TARGET_DATA_BYTES` | `targetDataBytes, MAX_TARGET_DATA_BYTES` |

### `ZeroTargetAddress` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:48`
- 签名：`ZeroTargetAddress()`
- 载荷：无
- 核对：无载荷；`target == address(0)`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:235` | `_checkProposalBody` | `proposalBody.target == address(0)` | `—` |

### `CallbackTargetNotContract` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:49`
- 签名：`CallbackTargetNotContract(address)`
- 载荷：`address target`
- 核对：载荷 `(target)`；只在 `TargetMode.Callback` 下判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:237` | `_checkProposalBody` | `proposalBody.targetMode == TargetMode.Callback && proposalBody.target.code.length == 0` | `proposalBody.target` |

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:50`
- 签名：`NotMemberOwner(uint256)`
- 载荷：`uint256 memberId`
- 核对：单键；NFT 不存在时先抛 OZ 错误。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:100` | `onlyMemberOwner` | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) != msg.sender` | `memberId` |

### `NoGovVotes` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:51`
- 签名：`NoGovVotes(address)`
- 载荷：`address tokenAddress`
- 核对：载荷 `(tokenAddress)`；`totalVotes == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:91` | `_checkSubmitPower` | `totalVotes == 0` | `tokenAddress` |

### `ProposalNotFound` · 1 站点 · 载荷调整

- 声明：`interfaces/ISubmit.sol:52`
- 签名：`ProposalNotFound(uint256)`
- 载荷：`uint256 proposalId`
- 核对：缺 `tokenAddress`，见 E-SUB-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:273` | `_checkExistingProposal` | `proposalId == 0 \|\| proposalId > _proposals[tokenAddress].length` | `proposalId` |

### `InsufficientSubmitPower` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:53`
- 签名：`InsufficientSubmitPower(address,uint256,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 memberId, uint256 validVotes, uint256 requiredVotes`
- 赋值链：requiredVotes ← `ceil(totalVotes × SUBMIT_MIN_RATIO / 1e18)`（`Submit.sol:73-82`）。
- 核对：载荷 `(tokenAddress, memberId, validVotes, requiredVotes)`，actual+limit 完整。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:94` | `_checkSubmitPower` | `!_meetsSubmitPower(validVotes, requiredVotes)` | `tokenAddress, memberId, validVotes, requiredVotes` |

### `SubmitRoundFull` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:59`
- 签名：`SubmitRoundFull(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 limit`
- 赋值链：length ← `_submits[tokenAddress][round].length`（`Submit.sol:292-293`）。
- 核对：载荷 `(tokenAddress, round, limit)`；limit 是常量 1000。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:293` | `_submitByProposalId` | `_submits[tokenAddress][round].length >= SUBMIT_ROUND_LIMIT` | `tokenAddress, round, SUBMIT_ROUND_LIMIT` |

### `ProposalAlreadySubmitted` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:64`
- 签名：`ProposalAlreadySubmitted(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 proposalId`
- 赋值链：round ← `currentRound()`（`Submit.sol:284`）；三键均来自入参与当前轮。
- 核对：载荷 `(tokenAddress, round, proposalId)`，与键一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:286` | `_submitByProposalId` | `isSubmitted(tokenAddress, round, proposalId)` | `tokenAddress, round, proposalId` |

### `MemberAlreadySubmitted` · 1 站点 · 保留

- 声明：`interfaces/ISubmit.sol:69`
- 签名：`MemberAlreadySubmitted(address,uint256,uint256)`
- 载荷：`address tokenAddress, uint256 round, uint256 memberId`
- 赋值链：round ← `currentRound()`（`Submit.sol:284`）；三键均来自入参与当前轮。
- 核对：载荷 `(tokenAddress, round, memberId)`，与键一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `Submit.sol:291` | `_submitByProposalId` | `_submitInfoBySubmitterId[tokenAddress][round][memberId] .submitterId != 0` | `tokenAddress, round, memberId` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-SUB-01 | Low | `src/Submit.sol:270-275` | `ProposalNotFound(uint256 proposalId)` 缺 `tokenAddress`。proposalId 是每社区独立自增的序号（`:246`），只带 id 时跨社区日志/多 token 批量调用无法定位是哪一个社区。§4 要求主体键在前。 | error-standards §4；`05-submit.md:158` | 改为 `ProposalNotFound(address tokenAddress, uint256 proposalId)`（破坏 ABI）；或规格说明“调用方已知 tokenAddress，省略以省 gas”。 |
| E-SUB-02 | Info | `src/Submit.sol:105-119` | `submitNewProposal` 先 `_createProposal`（写数组 + 发 `ProposalCreated`），再 `_submitByProposalId`；若命中 `MemberAlreadySubmitted`/`SubmitRoundFull`，整笔回滚，Proposal 不会留下。语义正确，但错误只报推举失败，调用方可能误以为 Proposal 已创建。规格未写“创建与推举同笔原子”。 | error-standards §6（Transition 必须改变状态或回 `Already<State>`）；`05-submit.md:147-163` | 在 05-submit 的 `submitNewProposal` 段补一句“创建与推举同笔原子；推举失败则 Proposal 不落地、不占用 id”。 |
| E-SUB-03 | Info | `src/Submit.sol:84-96` | `NoGovVotes` 与 `InsufficientSubmitPower` 的分界依赖 `requiredVotes != 0`：`SUBMIT_MIN_RATIO == 0` 时 `requiredVotes == 0`，即使 `totalVotes > 0`、`validVotes == 0` 也回 `InsufficientSubmitPower(valid=0, required=0)`，而不是 `NoGovVotes`。部署门禁禁止 0（`21_check.sh:485`），链上无守卫。 | error-standards §2/§5；`05-submit.md:159-160` | 规格写明该组合下的错误选择；或把 `_meetsSubmitPower` 的 `requiredVotes != 0` 拆成显式分支（会改错误优先级，需同步规格与测试）。 |
| E-SUB-04 | Info | `src/Submit.sol:162-182` | `proposalTarget` 同时是 Vote/Mint 的存在性 oracle：无效 id 回 `ProposalNotFound`，而 `proposalInfosByProposalIds` 批量读取也整批回滚。错误本身正确，但跨模块调用方（Mint/Vote）的 ABI 不含该 selector，登记缺口见 E-MNT-03/VOT 文档。 | error-standards §1/§5 | 在各调用方模块的“透传来源”表登记 `ProposalNotFound`；Submit 本身无需改。 |

### 4.2 已核对项

- 声明全部在 `ISubmitErrors`；实现零声明；无裸 `require`/`revert`。
- 两个入口的校验顺序与 05-submit:147-163 的表一致：`submitNewProposal` 先参数后资格；`submit` 先存在性后资格。
- `_submitByProposalId` 在写 `_submits`/两张索引后发事件，再在首个推举时 `sync`；回调 `_callProposalCreated` 在所有状态写入之后（`:301-326`）。
- `SUBMIT_ROUND_LIMIT = 1000` 与 `SubmitRoundFull` 的 `limit` 同源；`TargetData` 上限 16 项 / 16 KiB 与规格一致。
- `check_error_tests.py`：0 untested；`test/Submit.t.sol` 对 `ProposalNotFound`、`InsufficientSubmitPower`、`SubmitRoundFull` 均有载荷断言。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(uint256)` | `onlyMemberOwner`；05-submit:157 已登记。 |
| `IPhase.sync` | `PhaseNotStarted()` | 首个推举触发；轮 0 时 `NoGovVotes` 先命中，实际不可达。 |
| `IProposalTarget.onProposalCreated/onProposalSubmitted` | 任意 revert data | 第三方回调；05-submit:42 声明原样透传、失败整笔回滚。 |
| `IStake.validGovVotes/totalValidGovVotes` | `RoundNotStarted(uint256,uint256)` | 传当前轮，不会触发；依赖异常的读失败按 §7 冒泡。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/Submit.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/ISubmit.sol`。
