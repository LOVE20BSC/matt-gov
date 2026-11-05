# `group-chat/TokenManagerBase.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/06-manager.md`、`07-events-errors.md`。
> 范围：`src/managers/TokenManagerBase.sol` + `src/interfaces/managers/IManagerBase.sol` 的 `IManagerBaseErrors`。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 2 条（0 Low / 2 Info）。

## 1. 结论

- 1 个错误声明 / 1 个 revert 站点；声明在共享的 `IManagerBaseErrors`，站点只在派生合约 `TokenManagerBase`。
- `TokenNotLOVE20(address)` 一个 selector 覆盖「地址无代码」与「不是 LOVE20 token」两类；两类对调用方的处置相同（换 token），**登记为已知边界，不拆 ABI**。
- 无 Low；2 条 Info：`TokenNotLOVE20` 多条件合并（已知边界）、`ILaunch.isLOVE20Token` 与 `IERC20Metadata.symbol()` 的透传面未登记。
- 修正 `ManagerBase.md` 旧口径：本文件是「1 个声明 / 0 个本站点 / 1 个派生站点」，不是「无站点声明 0」。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 1（共享接口） |
| revert 站点 | 1（派生合约） |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Low / Info | 0 / 2 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `TokenNotLOVE20` | `TokenNotLOVE20(address)` | `0x518fd31e` | 1 | 保留，已知边界 |

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `TokenNotLOVE20(tokenAddress)` | `src/managers/TokenManagerBase.sol:36` | `_checkLOVE20Token` | `tokenAddress.code.length == 0 \|\| !ILaunch(LAUNCH_ADDRESS).isLOVE20Token(tokenAddress)` | `tokenAddress ← 入参` | `TokenMainManager`、`TokenGovManager` 的创建入口 |

### 3.2 赋值与发送逻辑

```text
_checkLOVE20Token(tokenAddress)
1. tokenAddress.code.length == 0                 → TokenNotLOVE20(tokenAddress)
2. !ILaunch(LAUNCH_ADDRESS).isLOVE20Token(token)  → TokenNotLOVE20(tokenAddress)
```

- 短路口径：无代码地址不会进入 `isLOVE20Token`，因此两种条件不会同时求值。
- `_tokenNamePayload` 与 `_love20TokenRequiresTestPrefix` 直接调用 `IERC20Metadata.symbol()`；`ILaunch.isLOVE20Token` 无 `try/catch`，异常数据或 core 回滚都会原样冒泡（E-TMB-02）。
- 声明与站点分离：声明在 `IManagerBaseErrors`，`ManagerBase.md` 的全仓站点统计为 0；本卷补齐派生站点 1。

### 3.3 已核对项

- 声明 / 站点闭合：1 / 1，与 `registry/errors.md:201` 一致。
- 与 07-events-errors:13 的 `TokenNotLOVE20` 口径、06-manager:16 的“非 LOVE20 token”一致。
- 派生 Manager 的 ABI 均包含 `0x518fd31e`；`TokenScopeManagerBase`、`TokenActionScopeManagerBase` 为 abstract，不单独部署。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-TMB-01 | Info | `src/managers/TokenManagerBase.sol:35-37` | `TokenNotLOVE20` 一个 selector 覆盖「无代码」与「非 LOVE20 token」两类。 | §2（一错误一条件） | 已知边界，不处理：两类对调用方的处置相同，载荷可自证失败地址；07-events-errors:13 已登记 |
| E-TMB-02 | Info | `src/managers/TokenManagerBase.sol:35`、`:41-44` | `ILaunch.isLOVE20Token` 无 `try/catch`；`_tokenNamePayload` 与 `_love20TokenRequiresTestPrefix` 直接调用 `IERC20Metadata.symbol()`，透传面未进 07 的按模块表。 | §5（规格写明透传面） | 已登记：07-events-errors「按模块登记透传面」 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `ILaunch.isLOVE20Token` | 无自身错误，core 回滚原样冒泡 | `_checkLOVE20Token` | 07-events-errors:25 |
| `IERC20Metadata.symbol()` | 无自身错误，token 回滚原样冒泡 | `_tokenNamePayload`、`_love20TokenRequiresTestPrefix` | 07-events-errors:25 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py group-chat
forge test --match-path test/ManagerEdgeErrors.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/managers/IManagerBase.sol`。
