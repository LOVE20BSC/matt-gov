# IActionExecutor 通用接口

所有 Action 层 Executor（`ILpExecutor`、`IGroupActionExecutor`、`IGroupServiceExecutor`）继承 `IActionExecutor`，确保统一的自证绑定、回调契约、退出接口和投票/加入/铸币 Round 查询。

## 设计原则

**通用部分**（在 `IActionExecutor` 中定义）：
- 继承 `IProposalTarget`，实现 Core 层的三类回调；回调仅接受 ActionTarget 调用
- `actionTarget()` — 自证绑定：ActionTarget 在 `onProposalCreated` 用它与 `address(this)` 握手，防止 executor 误配
- `initialized()` — 与 core 六个接口同形
- `exit(tokenAddress, actionId, memberId)` — 完全退出的签名是通用的
- `currentVoteRound()` / `currentJoinRound()` / `currentMintRound()` — 从 `Phase.currentPhase()` 推导的三阶段 Round；未开始回滚 `RoundNotStarted`

**非通用部分**（各 Executor 自行定义）：
- `init` 与配置项 — 各 Executor 依赖不同，配置来自行动创建时的 Target Data
- `join` — 参数因行动类型而异：
  - `ILpExecutor`: `join(tokenAddress, actionId, memberId, amount, verificationInfos)`
  - `IGroupActionExecutor`: `join(tokenAddress, actionId, groupId, memberId, amount, verificationInfos)` — 多了 `groupId`
  - `IGroupServiceExecutor`: `join(serviceTokenAddress, serviceProposalId, memberId, verificationInfos)` — 无 `amount`
- `withdraw` — 部分撤回接口，LP 和 GroupAction 需要，GroupService 不需要
- 事件 — 各 Executor 的业务字段不同，各自声明 `Joined/Withdrawn/Exited` 事件
- `currentVerifyRound()` — 仅 GroupAction / GroupService 的四阶段流水线提供；LP 不声明

## 与 ActionTarget 的事件分层

**ActionTarget 层事件**（通用状态记录，完整定义见 [`IActionTargetEvents`](../../../interfaces/action/IActionTarget.sol)）：
```solidity
event ActionCreated(address indexed tokenAddress, uint256 indexed actionId, address indexed executor);
event Joined(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
event Exited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
event ForceExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId);
```

ActionTarget 不发出 `Withdrawn`：部分撤回不改变加入状态，该事件只由 Executor 层发出。

**Executor 层事件示例**（业务细节记录，各 Executor 字段不同）：

- **ILpExecutor.Joined**: 包含 `amount`（LP 无体验资产，字段更简洁）
```solidity
event Joined(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round, uint256 amount);
```

- **IGroupActionExecutor.Joined**: 包含 `amount, isExperience, providerMemberId, groupId`
```solidity
event Joined(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round, uint256 amount, 
    bool isExperience, uint256 providerMemberId, uint256 groupId);
```

两层事件名相同、签名不同，各自记录各自层级的信息。参见 [ADR-003](../../adr/003-action-target-interface-simplification.md)。

## 接口定义

```solidity
interface IActionExecutor is IProposalTarget, IActionExecutorErrors {
    function actionTarget() external view returns (address);
    function initialized() external view returns (bool);
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
}
```

`IActionExecutor` 只装三处真正共享的成员：自证绑定、初始化查询、完全退出与 Round 查询。各 Executor 的 `Errors` 子接口按各自旧文件拆分。

## 与 ActionTarget 的调用关系

Executor 不使用加密调用 `ActionTarget` 上同名的 `join`/`exit`：ActionTarget 侧的登记入口命名为 `registerJoinState` / `clearJoinState`，与 `IActionExecutor.exit`（动本金）语义区分。加入态的唯一所有者是 ActionTarget，Executor 判定首次加入必须读 `IActionTarget.isJoined`，不得自建「是否加入」副本。

## 相关文档

- [ActionTarget 规格](01-action-target.md)
- [ADR-003: ActionTarget 接口简化设计](../../adr/003-action-target-interface-simplification.md)
- [`IActionExecutor.sol`](../../../interfaces/action/IActionExecutor.sol)
