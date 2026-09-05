# Submit 与 Vote 规格

本文档定义 Proposal 创建、推举和投票流程。

---

## 1. Proposal 数据结构

Proposal 由 `tokenAddress + proposalId` 定位。

### 1.1 结构（保留）

- `ProposalHead`：`id`、`author`、`createAtBlock`
- `ProposalBody`：`title`、`details`；`title` 非空，`details` 可为空
- `target`：激励铸造接收主体（必须是非零地址）
- `targetMode`：`NoCallback` 或 `Callback`
- `keys`、`values`：KV 数据（可选，两者长度必须相等或同时为空）

---

## 2. Target 模式（修改）

### 2.1 零地址禁止（新规则）

- **旧版**：允许零地址（激励自动销毁）
- **新版**：Target 必须是非零 EOA 或合约
- **理由**：避免遗忘填写导致激励永久丢失

### 2.2 Target 模式表

| target | targetMode | 行为 |
| --- | --- | --- |
| 非零 EOA | `NoCallback` | 合法，只接收铸造激励 |
| 非零合约 | `NoCallback` | 合法，不触发回调 |
| 非零合约 | `Callback` | 合法，创建/推举/投票均回调，空 KV 也回调 |
| EOA | `Callback` | 拒绝 |
| 零地址 | 任何 | 拒绝 |

如需销毁激励，应创建专用销毁合约（铸造后立即销毁），使意图显式化。

---

## 3. Submit：创建和推举（保留逻辑）

### 3.1 参考实现

`LOVE20TKM/core/src/LOVE20Submit.sol`

### 3.2 保留

- 推举门槛计算（`SUBMIT_MIN_PER_THOUSAND`，千分比）
- 同一 Round 推举去重
- Proposal ID 单调递增分配

### 3.3 变更

- 主体身份 `address` → `memberId`
- 旧版 `Action` → 新版 `Proposal`
- **新增**：每轮首个推举时自动调用 `Phase.sync()` 进行动态校准（BSC 版新功能）

---

## 4. Vote：投票（保留逻辑）

### 4.1 参考实现

`LOVE20TKM/core/src/LOVE20Vote.sol`

### 4.2 保留

- 投票机制：调用者投出的票数累加到 `votesNumByAccount[tokenAddress][round][memberId]`
- 投票上限检查：累计投票数不能超过 `maxVotesNum`（从 Stake 合约读取当前有效治理票）
- Proposal Target 回调机制
- 批量投票原子性

### 4.3 投票机制说明

- 投票使用当前有效治理票（由 Stake 合约的 `validGovVotes` 函数计算，参考旧版 `LOVE20Stake.sol` 65-88 行）
- 同一 Round 可多次投票，每次投票累加票数，总票数不能超过当前有效治理票
- 投票时不做快照，每次投票都检查当前的 `maxVotesNum`
- 参考旧版 `LOVE20Vote.sol` 84 行：`maxVotesNum` 调用 `Stake.validGovVotes` 实时读取

### 4.4 加速质押累计总量维护（新增说明）

- Vote 合约维护 `stakedAmountOfVoters[tokenAddress][round]`：该 Round 所有投票者的加速质押累计总量
- 投票时，如果该 memberId 在该 Round 首次投票，累加其加速质押份额到该状态
- 如果该 memberId 非首次投票，只累加相比于上次投票加速质押的增量（新快照 - 旧快照）
- 该状态用于 Mint 合约判断是否有加速质押参与，决定加速激励池的分配或销毁（见 `06-mint.md` 第 1 节）
- 参考旧版 `LOVE20Verify.sol` 108-112 行的 `stakedAmountOfVerifiers` 维护逻辑，BSC 版由 Vote 合约接管此职责

### 4.5 变更

主体身份 `address` → `memberId`
