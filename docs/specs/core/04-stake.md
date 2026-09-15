# Stake

Stake 按 `tokenAddress + memberId` 维护流动性质押和加速质押，不发行 SL/ST 凭证。两类资产共享解锁生命周期；权限见 [通用规则](01-common-rules.md)。

## 状态

结构体和完整 ABI 见 [`IStake.sol`](../../../interfaces/core/IStake.sol)。

| 字段 | 含义 |
| --- | --- |
| `liquidityShares` / `boostShares` | 成员流动性份额 / 加速质押份额 |
| `promisedWaitingPhases` | 承诺解锁期，单位 Phase |
| `unlockRequestPhase` | 申请 Phase；0 表示未申请 |
| `totalLiquidityShares` / `totalBoostShares` | 社区份额总量 |
| `totalLp` | 合约持有的 LP 代币总量 |
| `lastWithdrawableLp` | 上次结算后的可提取 LP 基准 |
| `lastFeeLp` | 上次结算后的协议手续费 LP 基准 |
| `lastSqrtKOfLp` | 上次结算的 sqrt(k) 基准 |
| `cumulatedBoostShares[tokenAddress][round][memberId]` | 指定治理 Round 的累计加速份额 |
| `pairAddress[tokenAddress]` | 社区对应的 PancakeSwap Pair 地址 |
| `totalBurnedToken[tokenAddress]` | 社区代币全局累计销毁量 |
| `totalBurnedParentToken[tokenAddress]` | 父币全局累计销毁量（换币前） |

## 流动性质押与手续费

`init` 仅部署授权者可调用一次，固定 `routerAddress`、`pairFactoryAddress` 和 `MAX_WITHDRAWABLE_TO_FEE_RATIO`。所有成员写操作校验当前 NFT 持有人；`voteAddress` 用于融合时检查来源本轮投票。金额单位为代币最小单位，等待期为 Phase。

每个社区在首次质押时通过 `pairFactoryAddress.getPair(tokenAddress, parentTokenAddress)` 获取并保存唯一 Pair；Pair 为零地址时拒绝。

调用者提供社区代币及父币，Stake 转入双币并通过 Router 添加 LP，再按 LP 数量计份额；提取时移除 LP 并返还双币。

```text
sharesMinted = totalLiquidityShares == 0
    ? lpMinted
    : floor(totalLiquidityShares * lpMinted / lastWithdrawableLp)

currentSqrtKOfLp = floor(sqrt(reserve0 * reserve1) * totalLp / pairTotalSupply)
newWithdrawableLp = floor(lastWithdrawableLp * lastSqrtKOfLp / currentSqrtKOfLp)
newFeeLp = totalLp - newWithdrawableLp
```

`totalLp` 是合约持有 LP 数量，`pairTotalSupply` 是 Pair 的 LP 总供应。仅当 `currentSqrtKOfLp > lastSqrtKOfLp` 时重分类手续费；`pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 或基准未增长时跳过结算，不能先除零再判断。结算更新 `lastWithdrawableLp`、`lastFeeLp` 和 `lastSqrtKOfLp`。

手续费增量归协议，不归旧质押者。重分类后可提取 LP 下降；相同新存入 LP 对应更多份额。无池价变化的比例模型中，这是剥离手续费，不是损失本金；整数舍入仍须按公式计算。

例（整数模型）：原可提取 LP 为 120，旧/新 sqrt(k) 基准为 100/120，重分类后可提取 LP 为 100、手续费 LP 为 20。原总份额为 120 时，新存入 100 LP 得到 120 份额。

## 手续费结算与销毁

任何人可调用 `settleFees(tokenAddress)` 单独结算手续费；提取本金前也自动结算。按上述公式重分类后，若 `feeLp × MAX_WITHDRAWABLE_TO_FEE_RATIO >= withdrawableLp`，从 Pair 取回 `feeLp` 对应双币：

1. 社区代币直接销毁
2. 父币按固定路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁
3. 最小输出量由同笔交易按当前 Pair 储备计算，不接受调用方传入
4. 更新 `totalBurnedToken` 和 `totalBurnedParentToken`（换币前父币数量）

低于阈值时保留待结算；Pair、Router、销毁或统计更新任一步失败，整笔回滚。每次只处理一个代币社区。

无质押的有效成员返回零状态；`canWithdraw` 在未申请或未到期时返回 false。历史查询读取不晚于目标 Round 的最近记录，含明确归零记录。Vote 从上述历史查询取加速份额，并自行维护投票快照。

## 治理票与加速质押

```text
govVotes = liquidityShares * promisedWaitingPhases
```

Vote 每次投票通过 `Stake.validGovVotes(tokenAddress, memberId)` 读取当前有效票，不冻结治理票上限；追加质押、改变承诺等待期和申请解锁会影响票权。加速质押本身不产生票权。

`cumulatedBoostShares` 在新 Round 首次操作时承接最近历史值，增减加速份额时更新本轮；无操作轮次读取最近记录，申请解锁后禁止追加，原说明要求累计值不再更新。这是 Stake 的质押历史，不是 Mint 的结算快照；Mint 只读取 [Vote 保存的投票快照](06-vote.md#投票和加速快照)。

例：Round 4 记录 50，Round 5 追加 30 后为 80；后续无变动轮次读取 80，不逐轮复制。

## 解锁与提取

1. 当前 NFT 持有人申请统一解锁，记录申请 Phase 和承诺等待期，立即清零治理票，禁止追加及融合。
2. 满足 `currentPhase >= unlockRequestPhase + promisedWaitingPhases` 后，当前持有人一次提取 LP 对应双币和加速代币；不能分别解锁、分别提取。
3. NFT 转移不重置等待期，不限制解锁中的 NFT 转移。查询应返回申请 Phase、承诺等待期和是否可提取，任何人可按社区和成员查询。

## 融合

用于同一社区质押的单向转移，可支持 NFT 场外交易：

- 源和目标不同且已存在；调用者必须持有源，不要求持有目标。
- 任一方待解锁时拒绝；源或目标任一在当前治理 Round 已有非零投票时拒绝。
- 空目标（`promisedWaitingPhases = 0`）继承源等待期；非空目标等待期短于源则拒绝，否则保持目标等待期。
- 源全部流动性份额和加速份额并入目标，源当前质押清零。目标原资产不得减少，历史投票和激励不回写。
- 目标本轮已投票仍可接收，后续按增加后的票权上限补投增量；源已投票禁止融合，防止同一份资产重复投票。
- 融合后按目标份额正常提取双币和加速代币；解锁中的成员需完成提取后才可再次融合。

## 实现约束

事件与错误定义见 [`IStake.sol`](../../../interfaces/core/IStake.sol)。

- 当前质押余额为 `0` 就表示没有质押；只有 RoundHistory 的历史查询需要区分”本轮没有记录”和”本轮明确归零”，直接沿用旧 RoundHistory 的显式记录语义，不新增额外布尔状态。
- 流动性写操作统一先校验参数和权限并锁定重入；读取 Pair 状态，在任何除法前处理 `pairTotalSupply == 0`、`currentSqrtKOfLp == 0` 和基准未增长；需要 Router、Pair 或 ERC20 调用时，以外部调用成功返回的实际数量计算并更新 `lastWithdrawableLp`、`lastFeeLp`、`lastSqrtKOfLp`、成员份额和社区总份额。任一步失败全部回滚。BSC 不使用 SL/ST 凭证，所有份额和可提取 LP 直接存入 Stake。
- 手续费结算失败（Pair 取回、Router 兑换、销毁或统计更新任一失败）时整笔结算回滚；提取本金前自动结算手续费，手续费结算失败则提取也回滚。
- 空目标沿用本文件的等待期继承例外；未列出的只读字段按 `MemberStake` 和 `GlobalStake` 直接暴露查询。
- `stakeData()` 和 `globalStakeData()` 返回的 `tokenAmountForLiquidity` / `parentTokenAmountForLiquidity` 以及 `withdrawableLp` / `feeLp` 都是查询时根据当前 Pair 状态现算的值，不是直接读取存储的历史基准。

历史来源：`LOVE20TKM/core/src/LOVE20Stake.sol` 和 `LOVE20TKM/core/src/LOVE20SLToken.sol`；提交已固定，当前 BSC 行为以本文件为准。验收见 [Core 验收](09-testing.md)。
