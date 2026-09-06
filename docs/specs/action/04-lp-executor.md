# LP Executor

仅迁移 LP V2 业务，不迁移 V1 和旧工厂。参与身份见 [共同参与模型](03-participation.md)，时间映射见 [行动阶段](02-phase-model.md)。

## 时间权重

每笔加入使用加入阶段起点和长度冻结时间扣减：

```text
deduction_i = min(amount_i, floor(amount_i * (joinBlock_i - joinPhaseStartBlock) / joinPhaseBlocks))
effectiveAmount = joinedAmount - deduction
effectiveLpRatio = floor(effectiveAmount * 1e18 / totalEffectiveAmount)
```

`amount_i` 是本笔加入量，`deduction` 为扣减汇总，`joinedAmount` 是成员加入总量。`totalEffectiveAmount` 是该行动 Round 的有效参与总量。阶段长度和起点不能在结算时改用另一阶段的值。

例：阶段共 100 区块，成员在开始后第 25 区块加入 100 个最小单位，扣减 25，有效量 75。

## 部分撤回

LP 支持部分撤回，沿用 V2 的聚合账本，不新增 lot：

```solidity
function withdraw(uint256 amount) external;
```

`amount` 不得超过当前 `joinedAmount`。撤回时按当前聚合比例同步减少 `joinedAmount`、`deduction` 和 `totalDeduction`；全额撤回执行旧 V2 的 `exit` 清理，加入区块与加入金额数组一并清空。撤回发生在加入阶段时更新当前 Round，阶段结束后不得回写已冻结 Round。

## 治理上限与分配

`govRatioMultiplier` 在 Proposal 创建时设置，使用 `1e18` 精度。成员 `validGovVotes(memberId)` 和社区 `totalGovVotes` 均在铸币时从 Stake 实时读取，用于上限而非 LP 权重。

启用上限且分母非零时：

```text
govRatio = floor(validGovVotes(memberId) * 1e18 / totalGovVotes)
govRatioCap = floor(govRatio * govRatioMultiplier / 1e18)
effectiveRatio = min(effectiveLpRatio, govRatioCap)
mintReward = floor(proposalReward * effectiveRatio / 1e18)
```

[组织验收](../../acceptance.md#行动公式零值边界) 规定：`totalEffectiveAmount == 0` 时行动激励为零；启用治理上限且 `totalGovVotes == 0` 时为零；`govRatioMultiplier == 0` 时关闭上限，不能因治理票为零而清零激励。先处理这些分支，再执行除法。

Executor 经 [铸造链路](07-minting.md#铸造链路) 一次取得本 Round 整笔 Proposal 激励，再按上述比例内部结算和处理溢出销毁；任何失败回滚。LP 参与和退出沿用 ExtensionLpV2 的聚合余额与按 Round 记录的扣减，不新增 lot。LP 手续费结算属于 Core Stake，不属于本 Executor。

## 实现约束

沿用 `LOVE20TKM/extension-lp/src/ExtensionLp.sol` 的聚合 `joinedAmount`、`_deduction`、`_totalDeduction`、加入区块和加入金额数组，以及完整 `exit` 清理逻辑；仅替换参与主体为 `memberId`，部分撤回只按聚合账本比例扣减。

验收见 [Action 验收](08-testing.md)。
