# 合并 TokenFactory 到 Launch

## 状态

已确认

## 决策

不再部署独立的 `TokenFactory`。`Launch` 直接保存 `LAUNCH_AMOUNT`、`MAX_SUPPLY`，并在内部创建 `LOVE20Token`。

`TokenLaunched` 是唯一的代币创建事件，`name` 和 `symbol` 与最终部署的 LOVE20Token 完全一致。删除 `ITokenFactory`、`TokenFactory` 及其独立初始化流程。

## 原因

- 当前 TokenFactory 只有 Launch 一个调用者。
- 它不再创建 Pair、SL 或 ST，没有独立生命周期。
- 合并后减少一个部署地址、一次初始化和一组重复配置。
- 合并后的 Launch runtime 为 12,081 B（`optimizer = true`、`optimizer_runs = 200`），低于 24,576 B 合约体积限制。

## 取舍

该决策改变 `Launch.init` 和 `TokenLaunched` 的 ABI，旧部署不可兼容；当前版本尚未正式部署，因此接受该变更。

## 关联

- `core/src/Launch.sol`
- `core/src/interfaces/ILaunch.sol`
- `.scratch/bsc-protocol-migration/issues/09-repository-migration-matrix.md`：记录了原先保留 TokenFactory 的历史确认及本次推翻原因。
- `.scratch/bsc-protocol-migration/issues/16-migration-order-and-archive.md`：创建清单已标注 TokenFactory 职责并入 Launch。
- 第 1 步「规格与接口 Review」中关于保留 TokenFactory 的结论由本决策取代；该审查记录随其它过程报告归档在 `LOVE20BSC/.scratch/archive/`。
