# Mint 规格

本文档定义 Mint 合约规格。

---

## 1. 轮次激励池（修改）

### 1.1 参考实现

`LOVE20TKM/core/contracts/Mint.sol`

### 1.2 保留公式

```text
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
govReward = available × roundRewardGovPerThousand / 1000
proposalReward = available × roundRewardProposalPerThousand / 1000
```

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

- `prepareRewardIfNeeded(tokenAddress, round)` 可由任何地址调用（保持旧版函数命名）
- 通常在 Round 结束后首次铸造前调用
- 首次铸造时如果未准备则回滚，提示调用者先准备激励池
- 准备时检查 `totalVotes`（Vote 合约的 `votesNum[tokenAddress][round]`）：
  - **如果 `totalVotes = 0`**：不预留激励，`govReward[tokenAddress][round] = 0`，`proposalReward[tokenAddress][round] = 0`，`rewardReserved` 不增加
  - **如果 `totalVotes > 0`**：
    - 按公式计算 `govReward` 和 `proposalReward`
    - 检查 `stakedAmountOfVoters[tokenAddress][round]`（该 Round 所有投票者的加速质押代币累计总量，由 Vote 合约维护）：
      - 如果为 0，将加速激励部分（`govReward / 2`）立即计入 `rewardBurned`，治理激励池实际只预留 `govReward / 2`
      - 如果大于 0，正常预留完整 `govReward`
    - 累加到 `rewardReserved`
- 准备操作是幂等的：重复调用已准备的 Round 直接返回，不重复预留

---

## 2. Proposal 激励铸造（保留逻辑）

### 2.1 参考实现

`LOVE20TKM/core/contracts/Mint.sol`

### 2.2 铸造公式

每个 Proposal 由其 `target` 单独铸造一次：
```text
实际数量 = proposalReward × proposalVotes / eligibleProposalVotes
```

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
- 若 `totalBoost == 0`，在该 Round 的首次治理激励铸造时，判断并将整个加速池一次性计入 `rewardBurned`
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
