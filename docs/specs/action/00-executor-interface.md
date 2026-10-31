# IActionExecutor 通用接口

所有 Action 层 Executor（`ILpExecutor`、`IGroupActionExecutor`、`IGroupServiceExecutor`）继承 `IActionExecutor`，确保统一的自证绑定、回调契约、退出接口和投票/加入/铸币 Round 查询。

## 设计原则

**通用部分**（在 `IActionExecutor` 中定义）：
- 继承 `IProposalTarget`，实现 Core 层的三类回调；回调仅接受 ActionTarget 调用
- `ACTION_TARGET_ADDRESS()` — 自证绑定：ActionTarget 在 `onProposalCreated` 用它与 `address(this)` 握手，防止 executor 误配
- `exit(tokenAddress, actionId, memberId)` — 完全退出的签名是通用的
- `mintMemberReward(...)` / `memberReward(...)` 与事件 `MemberRewardMinted` — 成员级奖励的铸造与查询，签名三家一致（成员级奖励裁决）
- `mintMemberRewards(...)` — 批量成员结算（平行数组按下标配对，任一元素失败整笔回滚）
- `joinedAmountByActionId(...)` / `joinedAmountByMemberId(...)` / `joinTokenAddress(...)` — 截止加入轮 `round` 结束的累计参与量、按成员累计量与参与计价代币（`round` 大于当前加入轮时按未开始返回 0；计价代币与轮次无关，不带 `round`；口径由各 Executor 规格固定）。计价代币是 `joinedAmountByActionId` 的计价单位：LP 为 LP 对币、GroupAction 为 join token、GroupService 为行动代币（按激活质押代理计量）。前端展示行动列表与派生指标时只需读基座三者，无需按 Executor 分支。GroupAction 另有成员记录快照 `joinInfo(tokenAddress, actionId, round, memberId) returns (JoinInfo)`（`joinedRound` / `groupId` / `ownAmount` / `providerAmount`）：它**不重复给出聚合总量**，总量只有基座 `joinedAmountByMemberId` 一个来源
- 基座 `joinTokenAddress` 是唯一的通用计价代币 getter；LP 与 GroupAction 直接使用该名（不再重复声明）。GroupService 的计价代币语义是行动代币，保留 `actionTokenAddress` 作为领域别名，与基座 `joinTokenAddress` 同键同值——这是登记在案的单点例外，改其一必须同批改另一个
- `currentVoteRound()` / `currentJoinRound()` / `currentMintRound()` — 从 `Phase.currentPhase()` 推导的三阶段 Round；未开始回滚 `RoundNotStarted(1, 0)`（`requiredRound` 为 1，`currentRound` 为推导出的 0；0 是派生轮未开始的哨兵，需要当前 phase 时读 `Phase.currentPhase()`）
  推导与守卫分层见 [阶段模型](02-phase-model.md)：轴库只做 `phase → round` 纯换算，不 import 错误接口。

**非通用部分**（各 Executor 自行定义）：
- 构造函数与配置项 — LpExecutor / GroupActionExecutor 只收 ActionTarget（后者另收 splits），GroupServiceExecutor 只收 GroupActionExecutor（ActionTarget 从它反查）；行动配置来自行动创建时的 Target Data
- `join` — 参数因行动类型而异：
  - `ILpExecutor`: `join(tokenAddress, actionId, memberId, amount)`
  - `IGroupActionExecutor`: `join(tokenAddress, actionId, groupId, memberId, amount, providerId, verificationValues)` — 多了 `groupId` 与 `providerId`
  - `IGroupServiceExecutor`: `join(serviceTokenAddress, serviceActionId, memberId)` — 无 `amount` 与 `verificationValues`
- `withdraw` — 部分撤回接口，LP 和 GroupAction 需要，GroupService 不需要
- 事件 — 各 Executor 的业务字段不同，按域前缀各自声明 `GroupActionJoined`/`GroupActionWithdrawn`/`GroupActionExited`、`LpJoined`/`LpWithdrawn`/`LpExited`、`ServiceJoined`/`ServiceExited`
- `currentVerifyRound()` — 仅 GroupAction / GroupService 的四阶段流水线提供；LP 不声明

## 与 ActionTarget 的事件分层

**ActionTarget 层事件**（加入态登记，与登记函数同名系；完整定义见 [`IActionTargetEvents`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionTarget.sol)）：
```solidity
event ActionRegistered(address indexed tokenAddress, uint256 indexed actionId, uint256 round, address indexed executor);
event JoinStateRegistered(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
event JoinStateCleared(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round, bool forced);
event ActionRewardMinted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round, uint256 amount);
```

ActionTarget 不发出 `*Withdrawn`：部分撤回不改变加入状态，该事件只由 Executor 层发出。`JoinStateCleared` 的 `forced` 区分 Executor 正常清理（`forced = false`）与 `forceClearJoinState` 兜底清理（`forced = true`），不再单设 `ForceExited` 事件。`ActionRegistered` 在转发创建回调之前发出：先登记注册表事实，再进入 Executor 的 `onProposalCreated`（域对象创建事件 `GroupActionCreated` / `ServiceActionCreated` / `LpActionCreated` 在回调内发出）。

**Executor 层事件示例**（业务细节记录，各 Executor 字段不同）：

- **ILpExecutor.LpJoined**: 包含 `amount`（LP 无 Provider 额度来源，字段更简洁）
```solidity
event LpJoined(address indexed tokenAddress, uint256 indexed actionId,
    uint256 indexed memberId, uint256 round, uint256 amount);
```

- **IGroupActionExecutor.GroupActionJoined**: 包含 `groupId, providerId, amount` 与 `verificationValues`
```solidity
event GroupActionJoined(address indexed tokenAddress, uint256 indexed actionId,
    uint256 indexed memberId, uint256 round, uint256 groupId,
    uint256 providerId, uint256 amount, string[] verificationValues);
```

两层事件名称不同（ActionTarget 层为加入态登记事件 `JoinStateRegistered`/`JoinStateCleared`，Executor 层为按域前缀的业务事件 `GroupActionJoined`/`LpJoined`/`ServiceJoined` 等），各自记录各自层级的信息。参见 [ADR-003](../../adr/003-action-target-interface-simplification.md)。

## 接口定义

```solidity
interface IActionExecutor is IProposalTarget, IActionExecutorEvents, IActionExecutorErrors {
    function ACTION_TARGET_ADDRESS() external view returns (address);
    function STAKE_ADDRESS() external view returns (address);
    function MEMBER_NFT_ADDRESS() external view returns (address);
    function PHASE_ADDRESS() external view returns (address);

    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function mintMemberReward(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external returns (uint256 mintAmount, uint256 burnAmount);
    function mintMemberRewards(address tokenAddress, uint256[] calldata actionIds, uint256[] calldata rounds,
        uint256 memberId)
        external returns (uint256[] memory mintAmounts, uint256[] memory burnAmounts);

    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
    function memberReward(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 mintAmount, uint256 burnAmount, bool minted);
    function joinedAmountByActionId(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256 amount);
    function joinedAmountByMemberId(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 amount);
    function joinTokenAddress(address tokenAddress, uint256 actionId)
        external view returns (address joinedTokenAddress);
}
```

`IActionExecutor` 装六处真正共享的成员：自证绑定、初始化查询、完全退出、Round 查询、成员级奖励（`mintMemberReward`/`mintMemberRewards`/`memberReward` 与事件 `MemberRewardMinted`，成员级奖励裁决定稿）、参与量查询（`joinedAmount` 族，按加入轮累计）。各 Executor 的 `Errors` 子接口按各自旧文件拆分。

## 与 ActionTarget 的调用关系

Executor 不使用加密调用 `ActionTarget` 上同名的 `join`/`exit`：ActionTarget 侧的登记入口命名为 `registerJoinState` / `clearJoinState`，与 `IActionExecutor.exit`（动本金）语义区分。加入态的唯一所有者是 ActionTarget，Executor 判定首次加入必须读 `IActionTarget.isJoined`，不得自建「是否加入」副本。

## 相关文档

- [ActionTarget 规格](01-action-target.md)
- [ADR-003: ActionTarget 接口简化设计](../../adr/003-action-target-interface-simplification.md)
- [`IActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionExecutor.sol)
