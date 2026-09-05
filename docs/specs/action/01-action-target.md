# ActionTarget 统一框架

本文档定义 ActionTarget 合约规格。

---

## 1. 术语说明

每个行动对应一个 Core Proposal。在 ActionTarget 和 Core 回调接口中使用 `proposalId`，在 Executor 业务逻辑和查询接口中使用 `actionId`。两者数值相同：`actionId = proposalId`。

---

## 2. Proposal 关联

### 2.1 与 Core 治理的对接

行动 Proposal 通过 Core Submit 在治理 Round 创建：

**创建参数**：
- `tokenAddress`: 社区代币地址
- `target`: ActionTarget 合约地址（必须）
- `targetMode`: `Callback`（必须）
- `title`/`details`: 行动标题和详情
- `kvList[0]`: `(key=keccak256("executor"), value=abi.encode(executorAddress))`

### 2.2 Core 调用流程

1. **创建时**：Core Submit 调用 `ActionTarget.onProposalCreated()`
   - ActionTarget 记录 `proposalId → executorAddress` 映射
   - ActionTarget 转发完整 KV 到 Executor 的 `onProposalCreated()`
   
2. **推举时**：Core Submit 调用 `ActionTarget.onProposalSubmitted()`
   - ActionTarget 转发到 Executor 的 `onProposalSubmitted()`
   
3. **投票时**：Core Vote 调用 `ActionTarget.onProposalVoted()`
   - ActionTarget 根据 proposalId 找到 executor
   - 调用 `executor.onProposalVoted(tokenAddress, proposalId, voterId, votes, ...)`
   - Executor 记录成员投票权重

### 2.3 Executor 保留项（关键设计）

- 创建 KV 的第 `0` 项固定为：`key = keccak256("executor")`，`value = abi.encode(executorAddress)`
- `executorAddress` 必须是非零且包含合约代码的地址
- 第 `0` 项之外的 KV 可以为空，业务字段由 Executor 负责

**设计理由**：ActionTarget 是通用框架，不预设业务字段，仅通过 kvList[0] 约定获得 Executor 地址；其余 KV 由各 Executor 自行定义和解析。

### 2.4 验证时机

ActionTarget 在 `onProposalCreated` 回调中验证：
- `kvList.length > 0`
- `kvList[0].key == keccak256("executor")`
- decode 后的 `executorAddress` 非零且包含合约代码

验证失败则回滚整个 Proposal 创建交易。

ActionTarget 以 `tokenAddress + proposalId` 为唯一键保存 Executor，把完整创建 KV 原样转发给 Executor。Executor 的三个回调只能通过 ActionTarget 转发，不接受外部直接调用。

### 2.5 回调接口

```solidity
function onProposalCreated(
    address tokenAddress,
    uint256 proposalId,
    bytes32[] memory keys,
    bytes[] memory values
) external;

function onProposalSubmitted(
    address tokenAddress,
    uint256 proposalId,
    uint256 submitterId,
    bytes32[] memory keys,
    bytes[] memory values
) external;

function onProposalVoted(
    address tokenAddress,
    uint256 proposalId,
    uint256 voterId,
    uint256 votes,
    bytes32[] memory keys,
    bytes[] memory values
) external;
```

**回调接口参数说明**：key 使用 bytes32 便于链上索引和比较；value 使用 bytes 支持任意长度的 abi.encode 数据。

---

## 3. 参与登记

ActionTarget 维护通用的"MemberNFT 是否参与某个行动"登记，供前端"当前已参与行动"列表和外部参与资格判断使用。

### 3.1 设计边界

- ActionTarget 登记所有行动的参与关系（包括 Group Action）
- 只登记参与关系，不持有资产
- 资产和业务状态由 Executor 维护
- Group Action 的额外业务逻辑（如群组归属）由 Group Action Executor 维护

### 3.2 接口

- `isAccountJoined(tokenAddress, actionId, memberId)` — 沿用旧代码命名
- `actionIdsByMemberId(tokenAddress, memberId)`、对应的 `Count` 和 `AtIndex`
- `registerParticipation(tokenAddress, actionId, memberId)` — 仅关联 Executor 可调用
- `unregisterParticipation(tokenAddress, actionId, memberId)` — 仅关联 Executor 可调用

---

## 4. forceExit（应急兜底）

### 4.1 入口

```solidity
function forceExit(
    address tokenAddress,
    uint256 actionId,
    uint256 memberId
) external;
```

### 4.2 设计意图

Executor 失效时，当前 MemberNFT 持有人可以直接清除 ActionTarget 的通用登记。

### 4.3 行为

- 清除 ActionTarget 登记并触发事件
- 不调用 Executor、不转移资产、不承诺资产返还
- 前端默认隐藏，只作为最后兜底

### 4.4 用户体验提示

- `forceExit` 只清除 ActionTarget 的通用登记，不修改群组归属
- 用户调用后仍可能保留群组 Chat 资格（归属在 Group Action Executor）
- 要完全退出群组（包括 Chat），需通过 Group Action Executor 的正常退出流程
- 前端应明确提示这一差异，避免用户困惑

### 4.5 对 Chat 资格的影响

- **代币社区/行动 Chat**：立即失去资格（资格检查通过 `ActionTarget.isAccountJoined()` 实现，forceExit 后立即失效）
- **群组 Chat**：不失去资格（资格检查通过 Group Action Executor 的 17 组归属索引实现，因此不受影响；详见 `group-chat/03-chat-types.md`）

### 4.6 限制

- ActionTarget 查询立即不再返回该参与记录
- Executor 的历史参与、资产和群组归属等业务状态均不更新
- 群组归属只在 Group Action Executor 的正常退出流程（成员完整退出群组在该社区的最后一个 Group Action）中更新

---

## 5. 查询

### 5.1 按 Round 查询（新增）

1. `proposalIdsByExecutor(tokenAddress, round, executor)` 返回该 Executor 关联的 `proposalId[]`
2. `proposals(tokenAddress, round)` 返回本轮所有有投票且已关联 Executor 的 `proposalIds[]` 和一一对应的 `executors[]`

两类查询先从 `Vote` 读取本轮有投票的 Proposal，再按 Proposal ID 读取 ActionTarget 映射并筛选，不维护独立反向索引。"有投票"指 `Vote.votedCount(tokenAddress, proposalId) > 0`。

### 5.2 设计理由

不维护独立反向索引，避免状态同步开销，查询时动态筛选即可满足需求。
