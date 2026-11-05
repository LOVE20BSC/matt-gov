# TokenActionGovManager · 状态变量变更审查

> `group-chat/src/managers/TokenActionGovManager.sol`，38 行，基线 `group-chat@e982df8`。
> 本合约没有自有状态变量；它是 `TokenActionScopeManagerBase` 的 `ag` 类型实例，资格只看最近 `RECENT_ROUNDS` 轮是否给该行动投过票。
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

`activate(address tokenAddress, uint256 actionId)`（`:29-31`）转发到 `_activateManagedAction`；`_typeCode()`（`:25-27`）返回 `"ag"`。写入顺序、守卫与回滚边界见 `08-token-action-scope-manager-base.md` §2.1。

### 2.2 资格谓词

`isSenderAllowed(groupId, senderId)`（`:33-37`）：

```solidity
ManagedAction storage action = _managedActionByGroupId[groupId];
address tokenAddress = action.tokenAddress;
return tokenAddress != address(0) && _hasRecentActionVote(tokenAddress, action.actionId, senderId);
```

- 未托管 group 的 `ManagedAction` 是零值，`tokenAddress == 0` 直接 false；
- `_hasRecentActionVote`（基类 `:149-167`）从 `IVote.currentRound()` 起，最多回看 `RECENT_ROUNDS` 轮，任一轮 `voteAmountByMemberIdByProposalId(token, round, memberId, actionId) != 0` 即 true；
- 遇到 `round <= 1` 提前停止，避免把回看推到 Round 0；
- 只读，不缓存票权或资格。

`RECENT_ROUNDS` 是 immutable；为 0 时循环不执行，本合约资格恒 false（`TAM-02`）。

## 3. 写入顺序与不可分割性

本合约没有新增写入；继承路径的写入顺序与回滚边界由 `TokenActionScopeManagerBase` 决定。资格查询不写状态。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `AGM-01` | Info | 资格只看“最近 `RECENT_ROUNDS` 轮投过票”，不看当前是否参与行动、持币或治理票；这是“行动治理群”的定义 | E1 |
| `AGM-02` | Info | 回看轮数由 immutable `RECENT_ROUNDS` 决定，部署值越大 `isSenderAllowed` 的 view 调用次数越多；当前部署建议 3 | E1 |
| `AGM-03` | Info | 同一 action 可在 `TokenActionMainManager` 与 `TokenActionGovManager` 各建一个群；两者资格不同、映射独立 | E1 |

逐条说明：

- **`AGM-01`**：与 `TokenActionMainManager` 的“投票或参与”不同，本合约只保留“最近投票”分支。持币、治理票、当前参与都不单独构成资格。规格 `05-chat-types.md` 的“代币行动治理”行与此一致。
- **`AGM-02`**：`_hasRecentActionVote` 每轮回看一次 `voteAmountByMemberIdByProposalId`；`RECENT_ROUNDS` 没有合约层上限，部署脚本要求 >0。设置极大值会让 `isSenderAllowed` gas 线性增长。
- **`AGM-03`**：`am` / `ag` 两个实例各自持有自己的群 NFT 与映射；同一 token+action 在两个 Manager 中各激活一次是设计允许的，不构成重复状态。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 最近投过票但后来退出行动是否仍有资格 | 是；本群只看投票窗口，不看当前参与 |
| 只在当前轮投票但未到 `RECENT_ROUNDS` 窗口是否有效 | 当前轮在回看范围内，有效 |
| Round 1 之前是否可能回看下溢 | `round <= 1` 提前 break，不会到 0 |
| 未托管 group 是否会调用 Vote | 不会；`tokenAddress == 0` 短路 |
| 激活者是否获得管理权 | 不获得；Manager 持有 NFT |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| AG1 | 本合约不新增 storage | ✅ | 文件内无状态变量声明 |
| AG2 | `TYPE_CODE()` 恒为 `"ag"` | ✅ | `:25-27` |
| AG3 | 未托管 group 的 `isSenderAllowed` 恒 false | ✅ | `tokenAddress == 0` 短路 |
| AG4 | 回看不越过 Round 1 | ✅ | 基类 `round <= 1` 提前 break |
| AG5 | 继承的三本托管状态满足 `08-token-action-scope-manager-base.md` TA1–TA5 | ✅ | 基类唯一写入点 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| `RECENT_ROUNDS = 0` | 部署脚本要求 >0；合约侧未测 |
| 极大 `RECENT_ROUNDS` 的 gas 上界 | 未覆盖 |
| 跨轮投票窗口边界 | `testT112` 覆盖最近轮投票；未穷举窗口每一轮的边界 |

### 4.5 结论

未发现 Critical / High / Medium。本合约无自有状态；资格只读 Vote 的最近轮行动票，未托管 key 安全短路，回看有 Round 1 下界。3 条 Info 均为资格定义、回看成本与跨 Manager 实例说明。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `AGM-01` | 登记：`ag` 只看最近投票（既有文本已覆盖） | `05-chat-types.md` 类型表 |
| `AGM-02` | 登记：`RECENT_ROUNDS` 无协议上限，回看成本随取值增长 | `06-manager.md`「四类 Manager」 |
| `AGM-03` | 登记：同一 action 可在 `am` / `ag` 各自托管 | `06-manager.md`「四类 Manager」 |
