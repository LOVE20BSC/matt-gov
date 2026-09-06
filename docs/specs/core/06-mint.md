# Mint 规格

本文档定义 Mint 合约规格。

---

## 1. 轮次激励池（修改）

### 1.1 参考实现

`LOVE20TKM/core/contracts/Mint.sol`

### 1.2 账本关系与公式

```text
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
govReward = available × roundRewardGovPerThousand / 1000
proposalReward = available × roundRewardProposalPerThousand / 1000
```

对每个代币社区，`rewardReserved`、`rewardMinted`、`rewardBurned` 是累计账本：

```text
unsettled = rewardReserved - rewardMinted - rewardBurned
```

`rewardReserved` 包含可铸造额度和准备阶段已确定要销毁的额度，因此始终满足 `rewardReserved >= rewardMinted + rewardBurned`。每个轮次只在准备时增加一次 `rewardReserved`，后续任何铸造或销毁都不得再次增加它。

其中 `roundRewardGovPerThousand` 和 `roundRewardProposalPerThousand` 为初始化参数（千分比），例如：
- `roundRewardGovPerThousand = 30`（3%）
- `roundRewardProposalPerThousand = 10`（1%）

Proposal 激励门槛：
```text
proposalVotes > 0
proposalVotes × 1000 >= totalVotes × proposalRewardMinVotePerThousand
```

其中 `proposalRewardMinVotePerThousand` 为初始化参数（千分比），例如 `50`（5%）。

### 1.3 轮次激励池准备逻辑（新增优化）

`prepareRewardIfNeeded(tokenAddress, round)` 可由任何地址调用，且每个 `(tokenAddress, round)` 只成功准备一次。Round 结束后执行以下固定流程：

1. 读取 Vote 在投票阶段冻结的 `totalVotes`、`eligibleProposalVotes` 和 `totalBoost`。若 `totalVotes == 0`，本轮两项激励均为 `0`，只记录“已准备”状态。
2. 若 `totalVotes > 0`，按本节公式计算 `govReward` 和 `proposalReward`，并一次性执行 `rewardReserved += govReward + proposalReward`。
3. 若 `totalBoost == 0`，将加速池 `govReward - floor(govReward / 2)` 计入 `rewardBurned`；该额度已经包含在本轮新增的 `rewardReserved` 中。
4. 若 `eligibleProposalVotes == 0`，将完整 `proposalReward` 计入 `rewardBurned`；该额度已经包含在本轮新增的 `rewardReserved` 中，本轮不得铸造 Proposal 激励。
5. 将本轮的 `govReward`、`proposalReward`、`eligibleProposalVotes` 和准备状态冻结。重复调用直接返回，不重算、不改写、不增加 `rewardReserved`。

治理激励或 Proposal 激励后续结算时，只能增加 `rewardMinted` 或 `rewardBurned`；不得再次增加 `rewardReserved`。

---

## 2. Proposal 激励铸造（保留逻辑）

### 2.1 参考实现

`LOVE20TKM/core/contracts/Mint.sol`

### 2.2 铸造公式

每个 Proposal 由其 `target` 单独铸造一次：
```text
实际数量 = proposalReward × proposalVotes / eligibleProposalVotes
```

其中 `eligibleProposalVotes` 为准备时从 `Vote` 读取并冻结的本轮所有达标 Proposal 票数总和；Proposal 未达门槛时不参与分配。该值为零时本轮全部 `proposalReward` 已在准备阶段销毁，因此不得执行 Proposal 铸造。

### 2.3 BSC 版说明

Core 层不包含 Action 扩展逻辑，铸造激励直接发送给 `target` 地址。如果 `target` 是扩展合约（如 ActionTarget），由扩展合约自行处理后续分发逻辑。

---

## 3. 治理激励

### 3.1 治理池拆分（保持旧版机制）

- **投票激励部分**（50%）：按成员实际投票行为分配
- **加速激励部分**（50%）：按加速质押份额占总加速质押的比例分配

### 3.2 计算公式

```solidity
// 固定 50/50 拆分
votePoolAmount = govReward / 2
boostPoolAmount = govReward - votePoolAmount  // 避免舍入损失

// 投票激励
voteReward = (votePoolAmount * memberVotes) / totalVotes  // 向下取整

// 加速激励（有 2 倍上限）
theoreticalBoost = (boostPoolAmount * memberBoost) / totalBoost  // 向下取整
boostReward = min(theoreticalBoost, voteReward * maxGovBoostRewardMultiplier)  // 基于投票激励的倍数上限
burnReward = theoreticalBoost - boostReward  // 溢出部分销毁
```

### 3.3 关键特性

- 50/50 拆分是协议固定设计，使用整数除法简化计算
- `boostPoolAmount = govReward - votePoolAmount` 确保两池总和精确等于 `govReward`
- 加速激励上限倍数由初始化参数 `maxGovBoostRewardMultiplier` 确定（例如 `2`，表示 2 倍上限）
- `memberBoost` = 该 memberId 的加速质押份额（boostShares），记账机制见 `04-stake.md` 第 4 节
- `totalBoost` = 本轮所有投票者的加速质押份额总和（由 Vote 合约维护的 `stakedAmountOfVoters`）
- 若 `totalBoost == 0`，`prepareRewardIfNeeded` 为本轮完整预留 `govReward` 后，将加速激励部分一次性计入 `rewardBurned`；后续治理激励铸造不再重复判断或重复销毁
- **加速激励只能由投票者铸造**：只有在该 Round 投票的 memberId 才能铸造治理激励（包含投票激励和加速激励）；未投票的 memberId 即使有加速质押也无法铸造

### 3.4 2 倍上限示例

**假设**：`govReward = 1000 token`，`totalVotes = 100`，`totalBoost = 200`，`maxGovBoostRewardMultiplier = 2`

#### 场景 1：未达上限
- 成员 A：投票 10 票，加速质押 10 份额
- `voteReward = 500 × 10 / 100 = 50 token`
- `theoreticalBoost = 500 × 10 / 200 = 25 token`
- `boostReward = min(25, 50 × 2) = 25 token`（未达上限）
- `burnReward = 0`
- **A 总激励：75 token**

#### 场景 2：达到上限
- 成员 B：投票 10 票，加速质押 100 份额
- `voteReward = 500 × 10 / 100 = 50 token`
- `theoreticalBoost = 500 × 100 / 200 = 250 token`
- `boostReward = min(250, 50 × 2) = 100 token`（达到上限）
- `burnReward = 250 - 100 = 150 token`（销毁）
- **B 总激励：150 token**（投票 50 + 加速 100）

#### 场景 3：无加速质押
- 成员 C：投票 10 票，加速质押 0 份额
- `voteReward = 500 × 10 / 100 = 50 token`
- `theoreticalBoost = 0`
- `boostReward = 0`
- `burnReward = 0`
- **C 总激励：50 token**（仅投票激励）

### 3.5 上限设计理由

防止极端加速质押占用过多激励，确保投票行为仍是核心贡献。上限倍数由初始化参数 `maxGovBoostRewardMultiplier` 控制，为不同社区提供灵活性。

---

## 4. 批量铸造（新增）

### 4.1 接口

```solidity
mintGovReward(tokenAddress, memberId, round) 
    returns (voteReward, boostReward, burnReward)

mintGovRewards(tokenAddress, memberId, rounds[]) 
    returns (voteReward[], boostReward[], burnReward[])
```

### 4.2 行为

- `mintGovRewards(tokenAddress, memberId, rounds[])`
- 按输入顺序逐轮执行，返回与 `rounds` 等长的三类激励结果数组
- 任一 Round 失败则整笔交易回滚

### 4.3 单轮铸造失败条件

- Round 尚未结束（`Phase.currentPhase() <= round`）
- Round 激励池未准备（未调用 `prepareRewardIfNeeded`）
- 该 memberId 在该 Round 没有投票记录
- 该 Round 该 memberId 的激励已铸造

---

## 5. 与 Launch 交互（BSC 版新增）

### 5.1 launchCredit 维护

- Mint 合约维护 `launchCredit[tokenAddress][memberId]`：累计铸造激励余额
- 每次成功铸造治理激励后，Mint 合约自动累加该 memberId 的 launchCredit

### 5.2 发射次数产生

铸造治理激励后，如果 `launchCredit >= threshold`：
- Mint 合约计算产生的发射次数
- 消耗对应的 launchCredit
- 调用 `Launch.addLaunchCount(tokenAddress, memberId, count)` 增加发射次数

### 5.3 权限控制

`Launch.addLaunchCount()` 只能由 Mint 合约调用（权限控制）

### 5.4 设计理由

这种设计在产生发射次数时才跨合约调用，高频治理激励铸造时只累加 launchCredit，节省 gas。
