# `action/GroupActionExecutor.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/05-group-action-executor.md、07-minting.md`。
> 范围：`src/GroupActionExecutor.sol`（750 行）+ `src/interfaces/IGroupActionExecutor.sol` 的 `IGroupActionExecutorErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 7 个错误声明 / 1 个发送点。Executor 本体只保留成员级结算（约 1.6KB）与链上被其他合约读取的查询，其余业务经 `delegatecall` 落到三个业务库；本文件的 7 个声明全部由三个库抛出，Executor 自身零站点。
- 唯一的站点 `MemberActionRewardUnavailable` 与 LP、GroupService 同源（基座声明、三个实现各一处），条件是「结算无产出」。
- `burnAmount` 恒为 0（全链路无销毁路径，ADR-004），因此 `if (mintAmount == 0 && burnAmount == 0)` 实际等价于 `mintAmount == 0`。
- 无 Medium / Low；2 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 7 |
| revert 站点 | 1 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 2 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `MemberActionRewardUnavailable` | `MemberActionRewardUnavailable(address,uint256,uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `MemberActionRewardUnavailable` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:30`（跨模块复用，本模块不重复声明）
- 签名：`MemberActionRewardUnavailable(address,uint256,uint256,uint256)` · selector `0x4cd933ce`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId, uint256 round`
- 核对：唯一站点；条件为结算无产出，`burnAmount` 恒为 0 见 E-GAE-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionExecutor.sol:730` | `function _mintMemberReward` | `mintAmount == 0 && burnAmount == 0` | `tokenAddress, actionId, memberId, round` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GAE-01 | Info | `src/GroupActionExecutor.sol:729-731` | 判据写成 `mintAmount == 0 && burnAmount == 0`，但本合约从不为 `burnAmount` 赋值（`:735` 写的是恒零值），全链路也没有销毁入口（ADR-004）。两条件式读起来像有「纯销毁仍可结算」的路径，实际只有 `mintAmount == 0` 一条。三个 Executor 都用了同一句式，LP 与 Service 确实有 `burnAmount > 0` 的情形，只有本合约没有。 | error-standards §8（不保留不可达路径） | 无需改行为；建议在 05 的「行动激励」段写明「GroupAction 无销毁量，`burnAmount` 恒为 0，零额判定等价于 `mintAmount == 0`」。 |
| E-GAE-02 | Info | `src/GroupActionExecutor.sol:311-322` | `submitOriginScores` 是唯一没有 `nonReentrant` 的写入口（`join` / `withdraw` / `exit` / Provider 额度四件 / 验证者申请两件都有）。当前它的外呼只有 `IPhase.phaseInfo` 与 `IPhase.currentPhase`，没有可重入面，因此不构成风险；但同类入口的守卫不一致，未来若在验证路径上加外呼（例如读 Stake）会留下缺口。 | error-standards §5（写入口契约一致）/ dev-standards §5.5 | 补 `nonReentrant`，或在 05 的「实现约束」写明「验证路径不外呼可变状态，故不加锁」。 |

### 4.2 已核对项

- 7 个声明（`ZeroJoinTokenAddress` / `InvalidMaxJoinAmountRatio` / `InvalidActivationMinGovRatio` / `TargetDataLengthMismatch` / `InvalidTargetDataShape` / `VerificationInfoLengthMismatch` / `DescriptionTooLong`）全部由三个业务库抛出，声明属主是「模块」而不是「合约」，与 05「一个业务一个库、一个库一个接口文件」的拆分口径一致。
- Executor 的所有写入口都带 `nonReentrant`（除 E-GAE-02 的 `submitOriginScores`），库函数经 `delegatecall` 执行，`msg.sender` 与 storage 与 Executor 一致；库内 modifier 的鉴权因此仍以原始调用者为判据。
- `_mintMemberReward` 的窗口校验走基座 `_checkMintWindow`，`createdRound` 与 `memberMinted` 都从同一份 Layout 读，与另两个 Executor 同源。
- `MemberActionRewardUnavailable` 的载荷四字段为「行动主体键 + 被结算轮」，与声明一致；零额回滚不置位 `memberMinted`、不发事件，可重试（07 明文）。
- `memberReward` / `generatedActionReward` / `generatedActionRewardByGroupId` 在不可结算时返回 0 而不回滚，符合 05「按轮次返回 0，不返回部分结果」。

### 4.3 透传错误面

- `ERC721NonexistentToken` — 基座 `mintMemberReward(s)` 的 `onlyMemberOwner`；来源 `MemberNFT`。
- `SafeERC20FailedOperation` — 成员结算的 `safeTransfer`；来源 OZ。
- `ReentrancyGuardReentrantCall` — `nonReentrant`；来源 OZ。
- 三个业务库抛出的全部错误（`IGroupActionJoinErrors` / `IGroupActionManagerErrors` / `IGroupActionVerifyErrors` / `IActionExecutorErrors`）在本合约的 ABI 上可见，因为它们由 Executor 继承；这与 §1「调用方接口默认不继承透传的标准错误」不冲突（它们是本模块自有错误，只是实现在库里）。
- `JoinNotOpen` / `ProposalNotVoted` / `ProposalRewardAlreadyMinted` — 经 ActionTarget / Mint 冒泡。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。库函数的站点记在各自库文件（06/07/08），本文件只统计 Executor 自身的 `revert`。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GAE-01 | Info | 已裁决（W1 #5）：`_mintMemberReward` 重写为「验证未完成或总分为零 → `MemberRewardPoolEmpty`；成员分为零 → `MemberHasNoVote`；取整 → `MemberRewardRoundedToZero`」；`burnAmount` 恒 0 写进规格 04/05。 |
| E-GAE-02 | Info | 已裁决（X-09 文档）：05 登记 `submitOriginScores` 不加 `nonReentrant` 的理由。 |
