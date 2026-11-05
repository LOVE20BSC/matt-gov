# TokenActionScopeManagerBase · 状态变量变更审查

> `group-chat/src/managers/TokenActionScopeManagerBase.sol`，178 行，基线 `group-chat@e982df8`。
> 行动类 Manager 的托管映射：group → (token, actionId)、token+actionId → group、token → actionId 列表。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `RECENT_ROUNDS` | `uint256 immutable` | 行动投票资格回看轮数 | 构造 `:53` |
| 2 | `SUBMIT_ADDRESS` | `address immutable` | 从 ActionTarget 派生的 Submit 地址 | 构造 `:52` |
| 3 | `_managedActionByGroupId` | `mapping(uint256 => ManagedAction)` | groupId → (tokenAddress, actionId) | `_activateManagedAction:129` |
| 4 | `_groupIdByActionId` | `mapping(address => mapping(uint256 => uint256))` | token + actionId → groupId；0 表示未托管 | `_activateManagedAction:131` |
| 5 | `_actionIdsByTokenAddress` | `mapping(address => uint256[])` | token 下已托管 actionId，按激活顺序 | `_activateManagedAction:132`（push） |

`ManagedAction` 字段为 `(tokenAddress, actionId)`；三本状态在同一函数内成组写入，没有删除/覆盖路径。

## 2. 逐变量变更逻辑

### 2.1 `_activateManagedAction`（`:117-140`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | `:118` | `_checkLOVE20Token(tokenAddress)` | 有代码且 Launch 认可 |
| 2 | `:119` | `_checkExistingAction(tokenAddress, actionId)` | `actionId != 0` 且 `actionId <= ISubmit.proposalIds(token,0,0,false).totalCount` |
| 3 | `:120` | `_checkNotManaged(_groupIdByActionId[tokenAddress][actionId])` | 已托管回 `AlreadyManaged(已有 groupId)` |
| 4 | `:122-126` | 计算 Test 前缀、symbol、payload、名称 stem | symbol 为空时 payload 只用 actionId |
| 5 | `:127` | `_mintManagedGroup(...)` | 付款 + mint + 费用校验 |
| 6 | `:129` | `_managedActionByGroupId[groupId] = ManagedAction(tokenAddress, actionId)` | groupId 来自新 mint |
| 7 | `:131` | `_groupIdByActionId[tokenAddress][actionId] = groupId` | 与上一步同笔 |
| 8 | `:132` | `_actionIdsByTokenAddress[tokenAddress].push(actionId)` | 与上两步同笔 |
| 9 | `:133` | `_activateManagedGroup(groupId)` | 调 GroupChat.activateChat；失败整笔回滚 |
| 10 | `:134-139` | `TokenActionGroupActivated` 事件 | 在激活之后 |

关键点：

- 三本状态在同一笔交易内写入，`_checkNotManaged` 使用 `_groupIdByActionId[token][action] != 0`；actionId 0 在 `_checkExistingAction` 被拒，所以 0 可以作为哨兵。
- `_checkExistingAction` 只校验 `actionId <= proposalCount`；Submit 的 proposalId 从 1 连续递增且不删除，所以这等价于“存在该 ID 的 proposal”。它不额外校验该 proposal 是否为行动类型；行动 Manager 的语义是“为某个 proposal 建行动群”，由上层协议保证 proposal 是行动（见 `TAM-01`）。
- `_actionIdsByTokenAddress` 与 `_groupIdByActionId` 一一对应；`actions` 分页时用映射回填 groupId，不会漂移。
- 同一 token+actionId 可以在不同 Manager 类型/实例各托管一次（行动主群 / 行动治理群），本合约只保证本实例内一次。

### 2.2 查询入口

| 函数 | 位置 | 行为 |
| --- | --- | --- |
| `actionByGroupId` | `:29-32` | 返回 `ManagedAction` 两个字段；未托管返回 `(0,0)` |
| `groupIdByActionId` | `:34-36` | 返回映射；未托管返回 0 |
| `actions` | `:56-72` | 分页 `_actionIdsByTokenAddress[token]`，用 `_groupIdByActionId` 回填 groupId |
| `groupIdsByActionIds` | `:74-83` | 批量读映射 |
| `actionsByGroupIds` | `:85-97` | 批量读 `_managedActionByGroupId` |
| `voteWeight` | `:99-106` | 未托管返回 0；否则读当前轮行动票 |
| `totalVoteWeight` | `:108-115` | 未托管返回 0；否则读社区当前总有效治理票 |

### 2.3 资格查询

| 函数 | 位置 | 行为 |
| --- | --- | --- |
| `_hasRecentActionVote` | `:149-167` | 从 `IVote.currentRound()` 起，最多回看 `RECENT_ROUNDS` 轮；任一轮 `voteAmountByMemberIdByProposalId != 0` 即 true；遇到 `round <= 1` 提前停 |
| `_currentActionVoteWeight` | `:169-177` | 当前轮该 member 给该 action 的票数 |

`RECENT_ROUNDS` 是 immutable；为 0 时循环不执行，行动治理经理的“最近投票”资格恒 false（行动主经理仍可用 `isJoined` 分支，见 `12-token-action-main-manager.md`）。

## 3. 写入顺序与不可分割性

```text
_checkLOVE20Token
  -> _checkExistingAction
  -> _checkNotManaged
  -> 名称计算
  -> _mintManagedGroup（付款 + mint + 费用校验）
  -> 三本映射/列表
  -> GroupChat.activateChat
  -> 事件
```

- mint 在映射之前，activateChat 在映射之后；两者都是受信 Core / GroupChat，正常路径无重入写入口。
- 三本状态写入连续且无 try/catch；activateChat 失败回滚 mint、付款与全部映射。
- 查询全部只读；没有惰性写入。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `TAM-01` | Info | `_checkExistingAction` 只看 `actionId <= proposalCount`，不校验该 proposal 是否为行动；行动语义由 Submit/Action 层保证 | E1 |
| `TAM-02` | Info | `RECENT_ROUNDS == 0` 时行动治理经理的最近投票资格恒 false，行动主经理仍可用参与分支；这是部署参数语义，不是状态写入分支 | E1 |
| `TAM-03` | Info | 三本状态没有删除/迁移路径；token+action 托管后永久保留 | E1 |
| `TAM-04` | Info | `RECENT_ROUNDS` 没有协议上限，回看循环最多 `RECENT_ROUNDS` 次外部 view；部署值越大，`isSenderAllowed` gas 越高 | E1 |

逐条说明：

- **`TAM-01`**：`_checkExistingAction`（`:142-147`）调用 `ISubmit.proposalIds(token,0,0,false)` 取 `totalCount`，然后判 `actionId == 0 || actionId > proposalCount`。Submit 的 proposalId 连续无空洞，所以这等价于“proposal 存在”；但若存在非行动的 proposal，也会被接受。规格 `06-manager.md` 的“行动不存在或 actionId 为 0 回 ActionNotExist”只要求存在性，未要求类型校验。
- **`TAM-02`**：`TokenActionGovManager.isSenderAllowed` 只调用 `_hasRecentActionVote`；`RECENT_ROUNDS = 0` 时循环不执行，返回 false。`TokenActionMainManager` 还接受 `_hasActionParticipation`，所以不受该参数影响。部署脚本要求 `RECENT_ROUNDS > 0`。
- **`TAM-03`**：没有 remove/transfer/reconfigure 入口；GroupChat 配置由 Manager 固定。规格明确“不转出、不重配”。
- **`TAM-04`**：`_hasRecentActionVote` 每轮调用一次 `IVote.voteAmountByMemberIdByProposalId`（view）。`RECENT_ROUNDS` 由部署参数决定，当前建议值 3；若设置极大，`isSenderAllowed` 可能超出区块 gas，导致该类群无法发言。合约没有上限保护。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| `RECENT_ROUNDS` 回看遇到 round 0 是否下溢 | 循环在 `round <= 1` 时 break，`round--` 前有判定；不会到 0 |
| 三本映射是否会只写一半 | 不会；连续写入，任一步失败整笔回滚 |
| `_actionIdsByTokenAddress` 是否可能重复 actionId | 不会；`_checkNotManaged` 在 push 前拒绝 |
| 同一 action 在不同 Manager 建群是否冲突 | 不算；行动主群/治理群是不同类型，各自独立映射 |
| 行动不存在时是否会把付款/mint 留下 | 不会；`_checkExistingAction` 在 mint 之前 |
| `actions` 分页的 groupId 是否可能为 0 | 不会；列表与映射同笔写入，0 仅表示未托管 |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| TA1 | `_managedActionByGroupId[g] = (t,a)` ⟺ `_groupIdByActionId[t][a] = g` | ✅ | 同笔写入，无其他写入/删除 |
| TA2 | `_actionIdsByTokenAddress[t]` 无重复，且每个 actionId 的映射指向自己的 group | ✅ | `_checkNotManaged` + 同笔 push |
| TA3 | 每个 groupId 都有已 mint MemberNFT 且 GroupChat 已激活 | ✅ | mint 成功后写映射；activateChat 失败回滚 |
| TA4 | 未托管 group 的 `voteWeight` / `totalVoteWeight` 返回 0 | ✅ | `ManagedAction.tokenAddress == 0` 分支 |
| TA5 | `RECENT_ROUNDS` 回看不越过 Round 1 | ✅ | `round <= 1` 提前 break |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 非行动 proposal | 合约不区分；测试没有覆盖“用普通 proposal 建行动群” |
| 极大 `RECENT_ROUNDS` | 部署参数建议 3，未覆盖 gas 爆炸边界 |
| 恶意 MemberNFT 重入 | 信任模型外 |

### 4.5 结论

未发现 Critical / High / Medium。三本状态在 `_activateManagedAction` 内成组写入，存在性与重复检查都在 mint 之前；查询对未托管 key 返回 0。4 条 Info 均为行动存在性语义、`RECENT_ROUNDS` 参数、永久保留与循环 gas 边界。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `TAM-01` | B（代码）：激活期用 `IActionTarget.executorByActionId` 判定类型，复用 `ActionNotExist`，不改 ABI；补反向测试 `testT113C` | `TokenActionScopeManagerBase.sol`、`06-manager.md`「四类 Manager」 |
| `TAM-02` | 登记：`RECENT_ROUNDS = 0` 时 `ag` 恒 false、`am` 参与分支不受影响 | `06-manager.md`「四类 Manager」、`05-chat-types.md`「资格数据」 |
| `TAM-03` | 登记：action 托管无删除/迁移（既有文本已覆盖） | `06-manager.md`「转移与失效」 |
| `TAM-04` | 登记：`RECENT_ROUNDS` 无协议上限，回看成本线性增长 | `06-manager.md`「四类 Manager」 |
