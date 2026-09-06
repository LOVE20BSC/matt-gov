# LP Executor

沿用旧 `ExtensionLp` 的聚合余额、时间扣减和历史查询，采用 V2 的 LP 准入规则；不部署旧业务工厂。BSC 新增部分撤回，业务按 `tokenAddress + actionId` 隔离，参与主体为 MemberNFT。

## 配置与接口

部署依赖通过一次性 `init` 绑定；每个行动的配置由创建回调解析，不能放进共享合约的全局 init。

```solidity
function init(address actionTargetAddress, address memberNFTAddress, address phaseAddress,
    address stakeAddress, address mintAddress, address pairFactoryAddress) external;
function join(address tokenAddress, uint256 actionId, uint256 memberId,
    uint256 amount, string[] calldata verificationInfos) external;
function withdraw(address tokenAddress, uint256 actionId, uint256 memberId, uint256 amount) external;
function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
function joinedAmount(address tokenAddress, uint256 actionId) external view returns (uint256);
function joinedAmountByMemberId(address tokenAddress, uint256 actionId, uint256 memberId)
    external view returns (uint256);
function joinedAmountByRound(address tokenAddress, uint256 actionId, uint256 round)
    external view returns (uint256);
function joinedAmountByMemberIdByRound(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round)
    external view returns (uint256);
function deduction(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256 amount, uint256[] memory joinBlocks, uint256[] memory joinAmounts);
function totalDeduction(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256);
function govRatio(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
    external view returns (uint256 ratio, bool claimed);
```

创建 KV 的键为 `keccak256` 后的名称，值用 `abi.encode`：`joinTokenAddress(address)`、`govRatioMultiplier(uint256)`、`minGovRatio(uint256)` 必填；可选 `verificationKeys(string[])` 和 `verificationKeyGuides(string[])` 必须等长。LP 必须是已配置 Pair Factory 登记的交易对，V2 不要求交易对包含激励代币。两个治理比例使用 `1e18` 精度，`minGovRatio <= 1e18`。

写操作要求调用者持有 memberId；加入/追加金额为正，首次加入满足 `minGovRatio`。LP 从调用者转入 Executor，撤回时转给当前持有人。首次参与登记到 ActionTarget，全部退出后清除；失败全部回滚。激励接口见 [行动铸造](07-minting.md#铸造链路)。

## 时间权重

每笔加入按本轮加入 Phase 的起点和长度计算：

```text
deductionAdded = min(amount, floor(amount * elapsedJoinBlocks / joinPhaseBlocks))
effectiveAmount = joinedAmount - deduction
totalEffectiveAmount = totalJoinedAmount - totalDeduction
effectiveLpRatio = floor(effectiveAmount * 1e18 / totalEffectiveAmount)
```

余额按 RoundHistory 继承，扣减只属于加入发生的 Round。跨轮持续参与时旧余额保留，新一轮扣减从 0 开始；追加只累加本次扣减。阶段起点和长度不可用结算时参数重算。

## 部分撤回

撤回只更新当前加入 Round，不能改已冻结历史；金额须满足 `0 < amount <= joinedAmount`，并沿用旧退出等待：`block.number >= lastJoinedBlock + 1`。

```text
deductionReduction = floor(deduction * amount / joinedAmount)
joinedAmount -= amount
totalJoinedAmount -= amount
deduction -= deductionReduction
totalDeduction -= deductionReduction
```

所有右侧均使用撤回前值。减少成员扣减和总扣减的数量必须相同；全额撤回时公式自然取尽剩余扣减，不留余数。部分撤回保留原加入区块/金额数组作为记录，不逐笔缩放；数组之和不再代表当前余额。全部退出清空当前 Round 的上述数组、当前参与登记和最后加入区块，不删除过去 Round。

例（最小单位）：余额 7、扣减 3，撤回 2 后扣减减少 0，剩余余额 5、扣减 3；再全部退出取尽剩余扣减 3。

## 治理上限与分配

成员与社区治理票均在领取时读取 `Stake.validGovVotes(tokenAddress, memberId)` 和 `Stake.govVotesNum(tokenAddress)`。已领取轮次的 `govRatio` 返回当时记录，不受后续质押变化影响。

```text
theoreticalReward = floor(proposalReward * effectiveLpRatio / 1e18)
govRatio = floor(validGovVotes * 1e18 / totalGovVotes)
govRatioCap = floor(govRatio * govRatioMultiplier / 1e18)
mintReward = floor(proposalReward * min(effectiveLpRatio, govRatioCap) / 1e18)
burnReward = theoreticalReward - mintReward
```

先处理零值：无有效参与量时成员激励为零；乘数为 0 时关闭上限并返回理论激励；上限启用且总治理票为 0 时该成员理论激励全部销毁。未参与的轮次查询返回零。销毁调用 Token.burn，不修改 Core 的取消预留账本。

来源：旧 `extension-lp/src/ExtensionLp.sol`、`ExtensionLpFactoryV2.sol` 和 `extension/src/ExtensionBaseRewardTokenJoin.sol`。部分撤回是 BSC 新增，不声称旧 V2 已具备。验收见 [Action 验收](08-testing.md)。
