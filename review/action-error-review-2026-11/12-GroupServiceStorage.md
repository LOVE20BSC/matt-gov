# `action/GroupServiceStorage.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/06-service-executor.md`。
> 范围：`src/GroupServiceStorage.sol`（80 行）。本文件承载 `GroupServiceStorage.Layout`、`Protocol`、3 个常量、分母缓存的两个读写函数与 `groupReward` 一个外呼包装。

## 1. 结论

- **0 个错误声明 / 0 个发送点**：本库不 `revert`，也不 import 错误接口；失败由 `11/13` 表达。
- 与错误目录相关的是**三个常量的载荷耦合**与**分母缓存判据的承重不变式**。
- 3 个常量与 06/07 的错误表对齐：`PRECISION = 1e18`（`InvalidRatioForPublicVerifier` 的判据与 `DistributionOverflow` 的上界）、`DEFAULT_MAX_RECIPIENTS = 10`（`TooManyRecipients` 的 `maxCount`）、`MAX_REMARK_BYTES = 256`（`RemarkTooLong` 的 `maxLength`）。
- 无 Medium / Low / Info 级行为风险；1 条 Info 关于缓存判据的可观测性。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 0 |
| revert 站点 | 0 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 1 |

## 2. 错误清单

本文件无错误声明，也无 `revert` 站点。

## 3. 逐错误明细

无。常量与载荷的对应关系：

| 常量 | 值 | 出现在哪些错误的载荷里 |
| --- | --- | --- |
| `PRECISION` | `1e18` | `InvalidRatioForPublicVerifier(value)` 的判据（`> 1e18`）；`DistributionOverflow(configured, available)` 的 `available` |
| `DEFAULT_MAX_RECIPIENTS` | `10` | `TooManyRecipients(count, maxCount)` 的 `maxCount` |
| `MAX_REMARK_BYTES` | `256` | `RemarkTooLong(index, length, maxLength)` 的 `maxLength` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GSS-01 | Info | `src/GroupServiceStorage.sol:48-63` | `cachedDenominator` / `cacheDenominator` 是一对无守卫的裸读写：缓存**只在** `GroupServiceExecutor._mintMemberReward`（`13:737-742`）里按「行动代币轮次已 `isRewardPrepared`」写入，读侧（`totalGroupActionReward`、`_denominator`）不做任何校验。承重不变式已用 `// Load-bearing:` 登记（`:65-68`），但破坏它不会 revert，只会让第二个结算人超额领取——这是一条**没有错误出口**的资金不变式。 | error-standards §5（失败契约）/ §8（不可达不变量用 assert） | 保持现状（写侧判据已经足够）；建议在 06 的「分母缓存」段显式写出「缓存一旦写入不可修正，因此写侧判据是唯一防线」，并把 `13` 的回归用例 `testRegression_RealSourceBurnCannotOverpayServiceBudget` 交叉引用到该段。 |

### 4.2 已核对项

- 无 `revert` / `require` / `assert`；不 import 任何 `*Errors` 接口。
- 3 个常量与 06/07 的正文逐条一致；`PRECISION` 与 `GroupActionStorage.PRECISION` 是两个独立的本地常量（值相同），符合 §1「本地声明、不跨模块导入」。
- `groupReward` 是对 `IGroupActionExecutor.generatedActionRewardByGroupId` 的纯读包装，该查询在未完成验证时返回 0 而不回滚（05 明文），因此本库不产生错误路径。
- 缓存键是**行动代币**（`actionTokenAddress`）而非服务代币，字段名 `totalGroupActionRewardByRound` 与 06 的「判据必须是行动代币的 `isRewardPrepared`」一致；父币服务 / 子币行动的场景下不会串键。
- `Layout` 的字段顺序即存储布局；06 明文「字段的插入、删除或重排都会移动后续槽位，本仓无生产部署，变更后必须整体重新部署」。

### 4.3 透传错误面

`groupReward` 外呼 `GroupActionExecutor.generatedActionRewardByGroupId`，该函数不 `revert`（所有分支返回 0 或金额），因此本库无透传面。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
forge test --match-contract GroupServiceSettlementTest
```

> 扫描口径：本文件无 `revert <Error>(` 站点；常量值取自源码，已与 06/07 正文比对。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GSS-01 | Info | 已裁决（X-09 文档）：06 登记 `cachedDenominator` 唯一写入口、`cacheDenominator` 无幂等守卫的边界。 |
