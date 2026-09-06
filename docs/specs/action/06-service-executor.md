# 链群服务 Executor

服务 Proposal 的代币为 `serviceTokenAddress`，面向整个 `actionTokenAddress` 社区的链群行动，不绑定单个源 actionId。两者必须相同，或服务代币是行动代币的直接父币；其他关系拒绝。

阶段、行动列表与验证完成查询见 [服务验证复用](02-phase-model.md#服务验证复用)。分母统计 `actionTokenAddress` 社区本轮全部链群行动的总激励，分子只统计完成全部验证的行动；不要求源行动已铸币，不包含 Gas 补偿。服务 Proposal 本轮没有可铸造激励时，由 `Mint.prepareRewardIfNeeded` 决定为零，Executor 不重复判断原因，owner 和公共验证者激励均为零。

## 权重

| 符号 | 含义 |
| --- | --- |
| `A[a]` | 源链群行动 a 的总激励 |
| `r[a]` / `ratioForPublicVerifier` | 行动 a 的公共验证者比例，`1e18` 精度 |
| `totalGroupActionReward` | `actionTokenAddress` 社区本轮全部链群行动的总激励，首次计算时缓存为本服务轮次分母 |
| `verifierId[a]` | 行动 a 锁定的验证者 memberId |
| `m` | 结算主体 memberId，作链群 owner 时也是 groupId |
| `groupReward(a, m)` | 链群 m 在行动 a 的成员激励总和 |
| `serviceReward` | 本服务 Proposal 的整笔激励 |

服务 Executor 首次计算某个 `actionTokenAddress + groupActionId + round` 时，读取并保存 `totalGroupActionReward`；后续该键的结算只读缓存，不重复遍历链群行动。另用 `denominatorCached` 区分“尚未计算”和“已计算且为 0”。

```solidity
mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
    _totalGroupActionReward;
mapping(address => mapping(uint256 => mapping(uint256 => bool)))
    _denominatorCached;
```

```solidity
function totalGroupActionReward(
    address actionTokenAddress,
    uint256 groupActionId,
    uint256 round
) external view returns (uint256 reward, bool cached);

function burnRewardIfNeeded(uint256 round) external;
```

保留的权重公式：

```text
verifierWeightNumerator(m) = sum(A[a] * r[a])  // 仅累加 verifierId[a] == m 的行动
ownerWeightNumerator(m) = sum(groupReward(a, m) * (1e18 - r[a]))
theoreticalVerifierReward(m) = floor(serviceReward * verifierWeightNumerator(m) / (totalGroupActionReward * 1e18))
theoreticalOwnerReward(m) = floor(serviceReward * ownerWeightNumerator(m) / (totalGroupActionReward * 1e18))
```

[组织验收](../../acceptance.md#链群服务结算) 还要求：只有本轮加入服务 Proposal 的链群 owner/候选 MemberNFT 可按人结算，未加入角色份额不重分配。行动未完成验证时不贡献分子，但仍计入 `totalGroupActionReward` 分母。首次计算后缓存分母，后续结算直接读取。

## 治理上限

只约束链群 owner，公共验证者按实际验证工作量直接获得权重激励，不受该上限影响。owner 超出上限的部分销毁，不转给其他 owner 或验证者：

```text
theoreticalOwnerRatio(m) = floor(ownerWeightNumerator(m) / totalGroupActionReward)  // 1e18 精度
govRatio(m) = floor(validGovVotes(m) * 1e18 / totalGovVotes)
govRatioCap(m) = floor(govRatio(m) * govRatioMultiplier(m) / 1e18)
actualOwnerRatio(m) = min(theoreticalOwnerRatio(m), govRatioCap(m))
actualOwnerReward(m) = floor(serviceReward * actualOwnerRatio(m) / 1e18)
ownerOverflow(m) = theoreticalOwnerReward(m) - actualOwnerReward(m)
```

其中 `theoreticalOwnerReward(m)` 使用上节权重公式；`validGovVotes(actionTokenAddress, m)` 和 `totalGovVotes(actionTokenAddress)` 在服务铸造时读取最新有效治理票。先判断各角色权重分子，分子为零直接返回，不执行除法。`totalGovVotes == 0` 且上限启用时，owner 实际激励为 0，理论 owner 激励按 owner 分别记入服务执行合约的 `ownerBurned`。`govRatioMultiplier == 0` 关闭 owner 上限，此时 `actualOwnerReward = theoreticalOwnerReward`。`totalGroupActionReward == 0` 时不进行比例计算；沿用旧 `ExtensionBaseReward.burnRewardIfNeeded(round)` 的专用入口，由任何地址在轮次结束后幂等销毁该轮未分配服务激励。

`govRatioMultiplier` 来自服务 Proposal 创建时的 KV；治理票使用 `actionTokenAddress` 社区在服务铸造时的最新有效值；owner 超额按每个 owner 单独记入 `ownerBurned`。服务代币已经由 Mint 铸造并转入 Executor 后，销毁直接调用该代币的 `burn(amount)`；不重复修改 Core Mint 的 `rewardBurned`。服务 Proposal 本轮没有激励时由 `Mint.prepareRewardIfNeeded` 处理，Executor 不重复判断。

## 二次分配

链群 NFT 当前持有人按 `sourceTokenAddress + sourceActionId + groupId + round` 配置 `recipientIds[]`、`ratios[]`；查询指定 `round` 没有配置时，回退到不晚于该轮的最近配置，不使用未来轮次；不存在更早配置时视为未配置。所有对同一源行动提供激励的服务 Proposal 复用该配置。接收者为 memberId，比例使用 `1e18` 精度。owner 部分先按各源行动权重拆分，再应用对应配置；验证者部分直接给锁定验证者，不参与二次分配。

配置比例总和不得超过 `1e18`，正好 100% 合法；超过时在配置阶段拒绝。以下计算中的 `actualOwnerReward` 是本次待分配预算，金额逐步向下取整：

```text
theoreticalRecipientReward[i] = floor(recipientRatio[i] * actualOwnerReward / 1e18)
theoreticalTotal = sum(theoreticalRecipientReward[i])
actualRecipientReward[i] = theoreticalRecipientReward[i]
```

各项取整后的总支出不得超过预算，舍入余数归 owner；100% 分配不得下溢。

## 实现约束

- `DistributionOverflow` 在配置比例总和超过 `1e18` 时触发；正好 `1e18` 合法。
- 二次分配配置键为 `sourceTokenAddress + sourceActionId + groupId + round`；分配事件另带服务 Proposal 上下文。
- 原来源 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol` 仅作为行为参考；服务加入、配置及结算 ABI 在实现接口中补齐。

铸造见 [统一链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
