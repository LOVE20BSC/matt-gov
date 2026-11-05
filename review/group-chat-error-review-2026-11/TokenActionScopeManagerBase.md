# `group-chat/TokenActionScopeManagerBase.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03）；`:145/:148` 为 state 卷 `TAM-01` 之后的当前行号（原 `:142/:145`）。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/06-manager.md`、`07-events-errors.md`。
> 范围：`src/managers/TokenActionScopeManagerBase.sol` + `src/interfaces/managers/ITokenActionScopeManagerBase.sol` 的 `ITokenActionScopeManagerBaseErrors`。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件新增 1 条（0 Low / 1 Info），另有 1 条跨卷关闭项。

## 1. 结论

- 1 个错误声明 / 2 个 revert 站点；实现零声明，无裸 `require`/`revert`/`assert`。
- `ActionNotExist(address,uint256)` 一个 selector 覆盖「actionId 非法」与「proposal 不是行动」两种语义。state 卷 `TAM-01` 已裁决「复用、不改 ABI」，并在 06-manager:7 写明两条件；本卷按“已由 state 卷关闭”记账，不再生成重复裁决条目。
- 无 Low；1 条 Info：`ISubmit.proposalIds`、`IActionTarget.executorByActionId`、`IVote.voteAmountByMemberIdByProposalId`、`IMemberNFT.ownerOf` 的透传面未进 07 的按模块表。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 1 |
| revert 站点 | 2 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 0 / 1 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `ActionNotExist` | `ActionNotExist(address,uint256)` | `0x9c0f73f0` | 2 | 保留；语义复用已由 state 卷 TAM-01 关闭 |

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `ActionNotExist(tokenAddress, actionId)` | `:145` | `_checkExistingAction` | `actionId == 0 \|\| actionId > proposalCount` | 两者均为入参 | `_createManagedAction` 及派生 Manager 的激活入口 |
| 2 | `ActionNotExist(tokenAddress, actionId)` | `:148` | `_checkExistingAction` | `executorByActionId(proposalId) == address(0)`（proposal 存在但不是行动） | 同上 | 同上 |

### 3.2 赋值与发送逻辑

```text
_checkExistingAction(tokenAddress, actionId)
1. proposalCount ← ISubmit(SUBMIT_ADDRESS).proposalIds(tokenAddress).length
2. actionId == 0 || actionId > proposalCount        → ActionNotExist(tokenAddress, actionId)
3. executor ← IActionTarget(ACTION_TARGET_ADDRESS).executorByActionId(tokenAddress, actionId)
4. executor == address(0)                            → ActionNotExist(tokenAddress, actionId)
```

- 两种条件对调用方的处置不同（修正 ID / 放弃激活该 proposal），但 state 卷 `TAM-01` 以「新增 selector 的收益低于复用成本」裁决保留复用；06-manager:7 已写明“id 非法或非行动 proposal 回 `ActionNotExist`”。
- `ISubmit.proposalIds`、`IActionTarget.executorByActionId` 无 `try/catch`；core 合约回滚或返回异常数据时原样冒泡（E-TAM-01）。
- `_hasRecentActionVote` 读取 `IVote.voteAmountByMemberIdByProposalId`，同样不归一。

### 3.3 已核对项

- 声明 / 站点闭合：1 / 2，与 `registry/errors.md:175` 一致。
- 与 07-events-errors:23 的 Manager 行、06-manager:7 的类型校验口径一致。
- 行号相对基线已后移 3 行（state 卷 TAM-01 插入校验），引用旧行号的历史卷不改写。
- 派生合约：`TokenActionMainManager`、`TokenActionGovManager` 共用该基类，ABI 均包含 `0x9c0f73f0`。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-TAM-01 | Info | `src/managers/TokenActionScopeManagerBase.sol:142-150`、`_hasRecentActionVote` | `ISubmit.proposalIds`、`IActionTarget.executorByActionId`、`IVote.voteAmountByMemberIdByProposalId`、`IMemberNFT.ownerOf` 的透传面未进 07 的按模块表。 | §5（规格写明透传面） | 已登记：07-events-errors「按模块登记透传面」 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `ISubmit.proposalIds` | 无自身错误，core 回滚原样冒泡 | `_checkExistingAction` | 07-events-errors:25 |
| `IActionTarget.executorByActionId` | 无自身错误，core 回滚原样冒泡 | `_checkExistingAction` | 07-events-errors:25 |
| `IVote.voteAmountByMemberIdByProposalId` | 无自身错误，core 回滚原样冒泡 | `_hasRecentActionVote` | 07-events-errors:25 |
| `IMemberNFT.ownerOf` | `ERC721NonexistentToken(id)` | 托管群解析 | 07-events-errors:27 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py group-chat
forge test --match-path test/TokenActionScopeManagerBase.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/managers/ITokenActionScopeManagerBase.sol`。
