# IActionExecutor 通用接口

所有 Action 层 Executor（`ILpExecutor`、`IGroupActionExecutor`、`IGroupServiceExecutor`）继承 `IActionExecutor`，确保统一的回调契约和退出接口。

## 设计原则

**通用部分**（在 `IActionExecutor` 中定义）：
- 继承 `IProposalTarget`，接收 Core 层的三类回调（创建/推举/投票）
- `exit(tokenAddress, actionId, memberId)` — 完全退出的签名是通用的

**非通用部分**（各 Executor 自行定义）：
- `join` — 参数因行动类型而异：
  - `ILpExecutor`: `join(tokenAddress, actionId, memberId, amount, verificationInfos)`
  - `IGroupActionExecutor`: `join(tokenAddress, actionId, groupId, memberId, amount, verificationInfos)` — 多了 `groupId`
  - `IGroupServiceExecutor`: `join(serviceTokenAddress, serviceProposalId, memberId, verificationInfos)` — 无 `amount`
- `withdraw` — 部分撤回接口，LP 和 GroupAction 需要，GroupService 可能不需要
- 事件 — 各 Executor 的业务字段不同，各自声明 `Joined/Withdrawn/Exited` 事件

## 与 ActionTarget 的事件分层

**ActionTarget 层事件**（通用状态记录）：
```solidity
event ActionJoined(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round);
event ActionWithdrawn(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round);
event ActionExited(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round);
```

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

- **IGroupServiceExecutor.Joined**: 待规格确认，可能只包含基础字段

两层事件不冲突，各自记录各自层级的信息。参见 [ADR-003](../../adr/003-action-target-interface-simplification.md)。

## 接口定义

```solidity
interface IActionExecutor is IProposalTarget {
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
}
```

## 相关文档

- [ActionTarget 规格](01-action-target.md)
- [ADR-003: ActionTarget 接口简化设计](../../adr/003-action-target-interface-simplification.md)
- [`IActionExecutor.sol`](../../../interfaces/action/IActionExecutor.sol)
