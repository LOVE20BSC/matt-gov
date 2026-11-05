# TokenActionMainManager · 状态变量变更审查

> `group-chat/src/managers/TokenActionMainManager.sol`，51 行，基线 `group-chat@e982df8`。
> 本合约没有自有状态变量；它是 `TokenActionScopeManagerBase` 的 `am` 类型实例，资格由“最近投票或当前参与”二选一组成。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 来源 | 语义 |
| --- | --- | --- | --- |
| 1 | `GROUP_CHAT_ADDRESS` / `GROUP_ADDRESS` / `MAX_NAME_LENGTH` | `ManagerBase` | 托管群依赖与名称上限 |
| 2 | `BAN_SOURCE_ADDRESS` / `BEFORE_POST_PLUGIN_ADDRESS` / `AFTER_POST_PLUGIN_ADDRESS` | `ManagerBase` | 托管群固定槽位 |
| 3 | `ACTION_TARGET_ADDRESS` / `VOTE_ADDRESS` | `ManagerBase` | ActionTarget / Vote |
| 4 | `_mintNonce` | `ManagerBase` | 名称重试计数 |
| 5 | `STAKE_ADDRESS` / `LAUNCH_ADDRESS` / `PHASE_ADDRESS` | `TokenManagerBase` | Stake / Launch / Phase |
| 6 | `RECENT_ROUNDS` / `SUBMIT_ADDRESS` | `TokenActionScopeManagerBase` | 回看轮数 / Submit 地址 |
| 7 | `_managedActionByGroupId` / `_groupIdByActionId` / `_actionIdsByTokenAddress` | `TokenActionScopeManagerBase` | 行动托管三本状态 |

本合约**没有新增** storage；所有写入发生在基类 `_activateManagedAction`。

## 2. 逐变量变更逻辑

### 2.1 本合约新增写入：无

`activate(address tokenAddress, uint256 actionId)`（`:30-32`）转发到 `_activateManagedAction`；`_typeCode()`（`:26-28`）返回 `"am"`。写入顺序、守卫与回滚边界见 `08-token-action-scope-manager-base.md` §2.1。

### 2.2 资格谓词

`isSenderAllowed(groupId, senderId)`（`:34-42`）：

```solidity
ManagedAction storage action = _managedActionByGroupId[groupId];
address tokenAddress = action.tokenAddress;
return tokenAddress != address(0)
    && (
        _hasRecentActionVote(tokenAddress, action.actionId, senderId)
            || _hasActionParticipation(tokenAddress, action.actionId, senderId)
    );
```

| 分支 | 位置 | 读取 | 语义 |
| --- | --- | --- | --- |
| 最近投票 | 基类 `_hasRecentActionVote:149-167` | Vote 最近 `RECENT_ROUNDS` 轮 `voteAmountByMemberIdByProposalId` | 任一轮有票即 true |
| 当前参与 | `_hasActionParticipation:44-50` | `ActionTarget.isJoined(token, actionId, memberId)` | 当前加入该行动 |

- 未托管 group 的 `ManagedAction` 是零值，`tokenAddress == 0` 直接 false；
- 两个分支都是 view，不缓存、不惰性写入；
- `RECENT_ROUNDS` 为 0 时“最近投票”分支恒 false，但“当前参与”分支仍可成立（与 `TokenActionGovManager` 不同）。

## 3. 写入顺序与不可分割性

本合约没有新增写入；继承路径的写入顺序与回滚边界由 `TokenActionScopeManagerBase` 决定。资格查询不写状态。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `AMM-01` | Info | “当前参与”分支只查 `isJoined`，不查参与量/额度/是否已退出；`forceClearJoinState` 后若 `isJoined` 变 false，该分支立即失效 | E1 |
| `AMM-02` | Info | 与 `TokenActionGovManager` 不同，`RECENT_ROUNDS == 0` 不会让本合约资格恒 false；参与分支仍可放行 | E1 |
| `AMM-03` | Info | 两个分支都是实时 view；成员在投票窗口/参与状态之间的切换会立即改变资格 | E1 |

逐条说明：

- **`AMM-01`**：`IActionTarget.isJoined(token, actionId, memberId)` 返回当前加入状态；不读参与量。规格 `05-chat-types.md` 的“代币行动”定义为“最近 RECENT_ROUNDS 轮给该行动投票，或当前参与该行动”，与代码一致。`forceClearJoinState` 只清加入状态；若 Action 实现把 `isJoined` 变为 false，本分支失效，但最近投票分支仍可独立成立。
- **`AMM-02`**：`RECENT_ROUNDS` 只控制 `_hasRecentActionVote` 的循环次数；为 0 时该分支 false，`_hasActionParticipation` 不受影响。部署脚本要求 `RECENT_ROUNDS > 0`，所以正常部署两者都可用。
- **`AMM-03`**：资格是即时谓词，不是成员快照；GroupChat 每次发言重新调用 source，买卖/加入/退出都会立即反映。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 参与行动但从未投票是否可发言 | 可以；参与分支独立成立 |
| 投票过但已退出行动是否可发言 | 可以；最近投票分支仍成立（窗口内） |
| 未托管 group 是否会调用 ActionTarget | 不会；`tokenAddress == 0` 短路 |
| `RECENT_ROUNDS = 0` 是否会让 am 群完全无法发言 | 不会；参与分支仍可放行，但治理投票分支关闭 |
| 激活者是否获得管理权 | 不获得；Manager 持有 NFT |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| AM1 | 本合约不新增 storage | ✅ | 文件内无状态变量声明 |
| AM2 | `TYPE_CODE()` 恒为 `"am"` | ✅ | `:26-28` |
| AM3 | 未托管 group 的 `isSenderAllowed` 恒 false | ✅ | `tokenAddress == 0` 短路 |
| AM4 | 资格 = 最近投票 ∨ 当前参与 | ✅ | `:34-42` |
| AM5 | 继承的三本托管状态满足 `08-token-action-scope-manager-base.md` TA1–TA5 | ✅ | 基类唯一写入点 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| `forceClearJoinState` 后的资格变化 | 由 Action 仓测试覆盖；本仓未做跨仓集成 |
| `RECENT_ROUNDS = 0` 的组合行为 | 部署要求 >0；合约侧未测 |
| 参与量归零但 `isJoined` 仍 true | 取决于 ActionTarget 语义，本合约不读参与量 |

### 4.5 结论

未发现 Critical / High / Medium。本合约无自有状态；资格二分支全部实时 view，未托管 key 安全短路。3 条 Info 分别为参与分支语义、`RECENT_ROUNDS` 组合行为与实时资格。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `AMM-01` | 登记：参与分支只查 `isJoined`，`forceClearJoinState` 后失效 | `05-chat-types.md`「forceClearJoinState 与资格」 |
| `AMM-02` | 登记：`RECENT_ROUNDS = 0` 时 `am` 仍可放行 | `05-chat-types.md`「资格数据」、`06-manager.md`「四类 Manager」 |
| `AMM-03` | 登记：实时资格，不使用快照 | `05-chat-types.md`「资格数据」 |
