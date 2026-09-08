# GroupService Executor

服务 Proposal 的代币为 `serviceTokenAddress`，面向整个 `actionTokenAddress` 社区的 GroupAction，不绑定单个源 actionId。两者必须相同，或服务代币是行动代币的直接父币；其他关系拒绝。

阶段和源行动查询见 [服务验证复用](02-phase-model.md#服务验证复用)。分母统计 `actionTokenAddress` 社区本轮全部 GroupAction 的总激励。每次读取源行动激励时，GroupAction 自行处理其验证与激励条件，GroupService 不重复筛选。服务 Proposal 本轮没有可铸造激励时，由 `Mint.prepareRewardIfNeeded` 决定为零，Executor 不重复判断原因，owner 和公共验证者激励均为零。

## 权重

| 符号 | 含义 |
| --- | --- |
| `A[a]` | 源 GroupAction a 的总激励 |
| `r[a]` / `ratioForPublicVerifier` | 行动 a 的公共验证者比例，`1e18` 精度 |
| `totalGroupActionReward` | `actionTokenAddress` 社区本轮全部 GroupAction 的总激励，首次计算时缓存为本服务轮次分母 |
| `publicVerifierId[a]` | 行动 a 锁定的公共验证者 memberId |
| `m` | 结算主体 memberId；作为群 owner 时也是 groupId |
| `groupReward(a, m)` | Group m 在行动 a 的成员激励总和 |
| `serviceReward` | 本服务 Proposal 的整笔激励 |

首次为可铸币服务轮次准备、领取或销毁时，按 `actionTokenAddress + round` 计算并缓存分母。`actionTokenAddress` 是 GroupService 绑定的社区，不代表某个被聚合的源行动。分母始终统计该社区本轮全部 GroupAction 激励，不缩成单行动激励。后续结算读取缓存；查询不能写状态，未缓存时只计算返回。已计算的零值通过 `denominatorCached` 区分。

```solidity
mapping(address => mapping(uint256 => uint256))
    _totalGroupActionReward;
mapping(address => mapping(uint256 => bool))
    _denominatorCached;
```

```solidity
function totalGroupActionReward(
    address actionTokenAddress,
    uint256 round
) external view returns (uint256 reward, bool cached);

function init(address actionTargetAddress, address memberNFTAddress, address phaseAddress,
    address stakeAddress, address mintAddress, address groupActionExecutorAddress) external;
function join(address serviceTokenAddress, uint256 serviceProposalId, uint256 memberId,
    string[] calldata verificationInfos) external;
function exit(address serviceTokenAddress, uint256 serviceProposalId, uint256 memberId) external;
function joinInfo(address serviceTokenAddress, uint256 serviceProposalId, uint256 round, uint256 memberId)
    external view returns (bool joined);
function actionTokenAddress(address serviceTokenAddress, uint256 serviceProposalId) external view returns (address);
function serviceRewardByMember(address serviceTokenAddress, uint256 serviceProposalId, uint256 round, uint256 memberId)
    external view returns (uint256 verifierReward, uint256 ownerReward, uint256 ownerBurned, bool claimed);
function burnRewardIfNeeded(uint256 round) external;
```

创建 KV 固定为 `actionTokenAddress(address)` 和 `govRatioMultiplier(uint256)`，键取 keccak256，值取 abi.encode；代币关系在创建时校验。join/exit 校验当前 NFT 持有人，按 RoundHistory 记录服务资格。加入资格仍为有效群 owner 或有效候选，领取只计算该轮实际贡献。共同准备/领取/销毁 ABI 见 [行动铸造](07-minting.md#铸造链路)。

保留的权重公式：

```text
verifierWeightNumerator(m) = sum(A[a] * r[a] where publicVerifierId[a] == m)
ownerWeightNumerator(m) = sum(groupReward(a, m) * (1e18 - r[a]))
theoreticalVerifierReward(m) = floor(serviceReward * verifierWeightNumerator(m) / (totalGroupActionReward * 1e18))
theoreticalOwnerReward(m) = floor(serviceReward * ownerWeightNumerator(m) / (totalGroupActionReward * 1e18))
```

[组织验收](../../acceptance.md#groupservice-结算) 还要求：只有本轮加入服务 Proposal 的群 owner/候选 MemberNFT 可按人结算，未加入角色份额不重分配。角色分子为零时直接返回，不执行除法；两类角色都没有分子时也不需要读取分母。`totalGroupActionReward == 0` 时，任何地址可在轮次结束后调用 `burnRewardIfNeeded(round)` 销毁整笔服务激励。首次计算后缓存分母，后续结算直接读取。

## 治理上限

只约束群 owner，公共验证者按实际验证工作量直接获得权重激励，不受该上限影响。owner 超出上限的部分销毁，不转给其他 owner 或验证者：

```text
theoreticalOwnerRatio(m) = floor(ownerWeightNumerator(m) / totalGroupActionReward)  // 1e18 精度
govRatio(m) = floor(validGovVotes(m) * 1e18 / totalGovVotes)
govRatioCap(m) = floor(govRatio(m) * govRatioMultiplier(m) / 1e18)
actualOwnerRatio(m) = min(theoreticalOwnerRatio(m), govRatioCap(m))
actualOwnerReward(m) = floor(serviceReward * actualOwnerRatio(m) / 1e18)
ownerOverflow(m) = theoreticalOwnerReward(m) - actualOwnerReward(m)
```

其中 `theoreticalOwnerReward(m)` 使用上节权重公式；治理票读取 `Stake.validGovVotes(actionTokenAddress, m)` 和 `Stake.govVotesNum(actionTokenAddress)`。每个角色先检查自己的分子，为零只跳过该角色，不影响同一 memberId 的另一角色；两个分子都为零则直接返回。上限启用且总治理票为零时只销毁 owner 理论激励；乘数为零直接关闭上限。结算使用服务铸造时 `actionTokenAddress` 社区最新的有效治理票；已结算的查询返回记录结果，不重新套用后续票权。

`govRatioMultiplier` 来自服务 Proposal 创建时的 KV；owner 超额按每个 owner 单独记入 `ownerBurned`。服务代币已经由 Mint 铸造并转入 Executor 后，销毁直接调用该代币的 `burn(amount)`；不重复修改 Core Mint 的 `rewardBurned`。服务 Proposal 本轮没有激励时由 `Mint.prepareRewardIfNeeded` 处理，Executor 不重复判断。

## 二次分配

groupId 的当前 NFT 持有人按 `sourceTokenAddress + sourceActionId + groupId + round` 配置 `recipientIds[]`、`ratios[]`；查询指定 `round` 没有配置时，回退到不晚于该轮的最近配置，不使用未来轮次；不存在更早配置时视为未配置。所有对同一源行动提供激励的服务 Proposal 复用该配置。接收者为 memberId，比例使用 `1e18` 精度。owner 部分先按各源行动权重拆分，再应用对应配置；公共验证者部分直接给锁定验证者，不参与二次分配。

```solidity
function setRecipients(address sourceTokenAddress, uint256 sourceActionId, uint256 groupId,
    uint256[] calldata recipientIds, uint256[] calldata ratios, string[] calldata remarks) external;
function recipients(address sourceTokenAddress, uint256 sourceActionId, uint256 groupId, uint256 round)
    external view returns (uint256[] memory recipientIds, uint256[] memory ratios, string[] memory remarks);
function rewardDistribution(address serviceTokenAddress, uint256 serviceProposalId, uint256 round,
    uint256 sourceActionId, uint256 groupId) external view returns (
        uint256[] memory recipientIds, uint256[] memory ratios, uint256[] memory amounts, uint256 ownerAmount);
```

setRecipients 沿用旧 GroupRecipients：只写当前验证 Round，不允许指定已结束轮次；同轮更新覆盖该轮配置。三数组等长、最多 10 项，接收 NFT 有效、不得重复或等于 groupId。全部传空表示显式清空，该轮及后续回退到空配置，不能重新找到清空前配置。没有配置时 owner 保留全部该项预算。付款使用结算时接收 NFT 当前持有人。

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
- ownerBurned 按 `serviceTokenAddress + serviceProposalId + round + memberId` 保存实际销毁量，不影响源行动缓存；领取与销毁失败时标记、转账和代币 burn 全部回滚。
- 来源为旧 `LOVE20TKM/extension-group/src/ExtensionGroupService.sol`、`LOVE20TKM/extension-group/src/GroupRecipients.sol` 与 `LOVE20TKM/extension/src/ExtensionBaseReward.sol`。公共验证者份额及全社区分母以本文件 BSC 规则为准。

铸造见 [统一链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
