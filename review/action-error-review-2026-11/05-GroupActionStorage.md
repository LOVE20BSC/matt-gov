# `action/GroupActionStorage.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/05-group-action-executor.md`。
> 范围：`src/GroupActionStorage.sol`（190 行）。本文件只承载 `GroupActionStorage.Layout` 一个根 struct、`GroupState` / `Protocol` 两个子 struct、6 个编译期常量与一个 `internal` 读取函数。

## 1. 结论

- **0 个错误声明 / 0 个发送点**：本库不 `revert`，也不 import 错误接口。所有失败都在消费方（`06/07/08/09`）表达。
- 与错误目录相关的只有两件事：**常量是错误载荷的上界来源**，以及**`memberAmountAt` 的加法是「相邻字段单位一致」的唯一合并点**。
- 6 个常量与 07 的错误表逐条对齐：`MAX_ORIGIN_SCORE = 100`、`MAX_VERIFICATION_BATCH = 100`、`MAX_DESCRIPTION_BYTES = 1024`、`MAX_VERIFICATION_ENTRIES = 16`、`MAX_VERIFICATION_TEXT_BYTES = 1024`、`PRECISION = 1e18`。
- 无 Medium / Low / Info 级的行为风险；1 条 Info 关于常量的载荷耦合。

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

无。本文件提供的是错误载荷里的上界与判定依据：

| 常量 | 值 | 出现在哪些错误的载荷里 |
| --- | --- | --- |
| `PRECISION` | `1e18` | `InvalidMaxJoinAmountRatio` / `InvalidActivationMinGovRatio` 的判据；`DistributionOverflow` 的上界（Service 侧另有同名常量） |
| `MAX_ORIGIN_SCORE` | `100` | `ScoreLimitExceeded(index, score, maxScore)` 的 `maxScore` |
| `MAX_VERIFICATION_BATCH` | `100` | `VerificationBatchTooLarge(count, maxCount)` 的 `maxCount` |
| `MAX_DESCRIPTION_BYTES` | `1024` | `DescriptionTooLong(length, maxLength)` 的 `maxLength` |
| `MAX_VERIFICATION_ENTRIES` | `16` | `TooManyVerificationEntries(count, maxCount)` / `TooManyVerificationValues(count, maxCount)` |
| `MAX_VERIFICATION_TEXT_BYTES` | `1024` | `VerificationKeyTooLong` / `VerificationDescriptionTooLong` / `VerificationValueTooLong` 的 `maxLength` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GAS-01 | Info | `src/GroupActionStorage.sol:18-23` | 6 个常量是 7 个错误的载荷上界来源，但它们是 `internal` 常量、不设 getter（05 明文「三个协议级上界是编译期常量，不进构造函数、不设 getter」）。链下要断言「`maxCount` 是否与当前部署一致」只能从源码或 `eth_call` 的 revert data 反推，无法像 `PRECISION()` / `DEFAULT_MAX_RECIPIENTS()` 那样直接读（Service 侧那两个是 `public constant`）。 | error-standards §4（载荷是公开 ABI 的一部分） | 无需改 ABI；建议在 05 的「实现约束」里补一张「常量 → 载荷字段」对照表（即本报告第 3 节），让链下不必读源码即可解释 `maxCount`。 |

### 4.2 已核对项

- 无 `revert` / `require` / `assert`；不 import 任何 `*Errors` 接口，符合 05「状态只有一份，由一个根 Layout 承载；库只承载逻辑，不声明状态变量」。
- `memberAmountAt` 把「自有」与「Provider 聚合」两个同单位字段相加，是 `joinedAmountByMemberId` 与 `finalScore` 的唯一合并点；两字段都是 join token 计价，单位一致，不违反 §4「相邻字段单位必须一致」。
- `GroupState` 的 `active` / `activatedRound` / `deactivatedRound` 与 `GroupAlreadyActivated` / `GroupNotActive` / `DeactivationLockedInActivatedRound` 三个错误的判据一一对应，字段语义与 05 一致。
- 承重不变式都已用 `// Load-bearing:` 登记：`originScoreDeductionByMemberId`（位置化已验证推导）、`verifiedGroupCountByRound`（轮级计数依赖「已完成群不可重复提交」）、`applicationIdHistory`（按轮解析申请）、`voterIdsByApplicationId`（只追加故 `reverse` 即首次投票逆序）。这些不变式被破坏时都**不会 revert**，属 README 的 X-05「静默失败形态」。

### 4.3 透传错误面

无外部调用（`memberAmountAt` 只读 storage）。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
forge build --sizes
```

> 扫描口径：本文件无 `revert <Error>(` 站点；常量值取自源码，已与 05/07 的正文逐条比对。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GAS-01 | Info | 已裁决（X-09 文档）：05 登记常量不进 getter、`maxCount` 必须按规格常量取值。 |
