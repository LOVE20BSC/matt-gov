# ActionTarget

ActionTarget 是社群行动 Proposal 的统一 Target。Core 和回调使用 `proposalId`，Executor 使用 `actionId`，两者数值相同；关联键为 `tokenAddress + proposalId`。

## 创建与回调

创建行动时指定 `tokenAddress`、`title`、`details`，并固定 `target = ActionTarget`、`targetMode = Callback`。Proposal 回调本身不要求 Target Data 非空；ActionTarget 创建行动另有一个必须的 `executor` 保留项，使用 Core 的 `targetData` 数组：

```text
targetData[0] = abi.encode(executorAddress)
```

`onProposalCreated` 按以下顺序校验，任一失败回滚整个创建操作：

```text
1. targetData.length >= 1
2. executor = abi.decode(targetData[0]) 非零且有代码
3. IActionExecutor(executor).actionTarget() == address(this)
4. 该 (tokenAddress, proposalId) 尚未记录 executor
```

第 1～3 步任一步失败回滚 `InvalidExecutor()`；第 4 步回滚，拒绝同一复合键重复创建，不覆盖已记录映射。

**Target Data 的位置契约**：Target Data 是无键的 `bytes[]`，只能按位置读取。ActionTarget 只读取并校验创建回调的第 `0` 项（executor 保留项），其余各项的数量、位置与编码**一律由该 Executor 在自己的规格中固定并在创建回调内自行校验**；ActionTarget 不解码、不校验、不截断，原样转发整个数组。推举与投票回调不含 executor 保留项（ActionTarget 用 `tokenAddress + proposalId` 映射定位 Executor），因此这两类回调的业务项从 `targetData[0]` 起算。项数与位置不匹配由各 Executor 用自己的错误拒绝，不在本层设通用错误。

| Core 调用时点 | ActionTarget 行为 |
| --- | --- |
| `onProposalCreated` | 按上表校验，保存 Executor 映射，原样转发完整创建 Target Data |
| `onProposalSubmitted` | 读取已保存映射，转发本次推举上下文和 Target Data |
| `onProposalVoted` | 读取映射，转发 `round`、`voterId`、本次增量票数及 Target Data，由 Executor 记账 |

完整签名统一见 [Core Target 回调](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IProposalTarget.sol)。ActionTarget 与每个 Executor 都实现这三类回调：ActionTarget 的 `onProposalCreated`/`onProposalSubmitted` 仅 Submit 可调用，`onProposalVoted` 仅 Vote 可调用；Executor 的同名回调仅接受 ActionTarget 调用，其他调用者回滚 `UnauthorizedCallback()`。任一回调失败均回滚对应外层操作。

## 加入与退出

记录当前成员是否加入行动，供加入列表和外部资格查询；包括 GroupAction，但不保存 Executor 的资产、验证或群归属。

**唯一写入者**：ActionTarget 是加入态的唯一所有者。Executor 判定「首次加入」必须读 `isJoined(tokenAddress, actionId, memberId)`，不得用自己的资产账本判定；成员全部退出时调用 `clearJoinState`。与行动类型无关的参与判定走 ActionTarget；某一行动类型的专属关系（如链群归属）走该 Executor。加入/退出是否满足阶段与资格条件由 Executor 判定，ActionTarget 只做登记。

**事件分层设计**：ActionTarget 发出简化的加入/退出事件（`Joined`、`Exited`，只包含 `tokenAddress, actionId, memberId, round`），记录通用加入状态；各 Executor（如 `ILpExecutor`、`IGroupActionExecutor`）在自己的合约中发出包含完整业务字段（`amount, isExperience, providerMemberId` 等）的同名事件。两层事件不冲突，各自记录各自层级的信息。ActionTarget 不发出 `Withdrawn` 事件，因为 withdraw 不改变加入状态。

**集合读取**：成员的行动列表是无界集合（由成员加入次数决定），采用标准分页签名 `actionIdsByMemberId(tokenAddress, memberId, offset, limit, reverse) returns (actionIds[], total)`。行动的成员列表同样是无界集合，采用标准分页签名 `memberIdsByActionId(tokenAddress, actionId, offset, limit, reverse) returns (memberIds[], total)`。参数语义：越界返回空数组与真实总数、不回滚；`limit` 超剩余按剩余返回；`limit = 0` 只返回总数；`reverse` 为 true 时逆序遍历当前存储顺序。符合[集合读取设计原则](../../migration-standards.md#集合读取函数的设计原则)。

**历史查询**：提供按 round 的历史快照查询，`isJoinedByRound(tokenAddress, actionId, memberId, round)` 检查指定 round 时的加入状态，`memberIdsByActionIdByRound(tokenAddress, actionId, round, offset, limit, reverse)` 返回指定 round 时的成员列表（分页）。round 大于当前 round 时按未开始处理：`isJoinedByRound` 返回 false，列表返回空数组与 `total = 0`。

**顺序契约（不保证跨调用稳定）**：`actionIdsByMemberId`、`memberIdsByActionId`、`memberIdsByActionIdByRound` 由共享集合原语支撑——追加写入，删除用 swap-and-pop（把末位元素搬到被删元素的位置）。因此**同一集合、同一 `offset` 的返回内容不保证在两次调用之间稳定**，`reverse` 只表示「逆序遍历当前存储顺序」，仅在集合自建立以来没有发生过删除时才等于「加入逆序」。调用方（前端、索引）必须每次以 `total` 为准重新拉取，不得跨调用缓存 `offset`，也不得按「先拉首页、再按旧 `total` 增量补后续页」的方式拼接。

`actionIdsByExecutor`、`actions` 由 Vote 的只追加列表派生，顺序不受本契约约束，但两者的 `offset` 语义同样按上面执行。

完整 ABI 见 [`IActionTarget.sol`](../../../interfaces/action/IActionTarget.sol)。

`init` 只校验未初始化，重复调用回滚 `AlreadyInitialized()`；不设调用者限制、不保存部署者。四个依赖地址由 `memberNFTAddress()`/`submitAddress()`/`voteAddress()`/`mintAddress()` 提供，供发布前检查脚本逐项核对绑定结果；不把「部署后立即初始化」当作防抢跑保证。

**写操作权限**：`registerJoinState`/`clearJoinState`/`mintProposalReward` 仅该 `(tokenAddress, actionId)` 已注册绑定的 Executor 可调用——判据是 `executor[tokenAddress][actionId] == msg.sender` 且该绑定非零，未注册绑定时任何调用者都拒绝；不满足即回滚 `UnauthorizedExecutor(tokenAddress, actionId)`。`mintProposalReward` 的 `proposalId` 即 `actionId`，因此绑定键与铸造键一致，不存在「持某个行动的 Executor 去铸另一个行动」的路径。`forceExit` 仅该 memberId 的 MemberNFT 当前持有人可调用，否则 `NotMemberOwner(memberId)`。

重复加入、重复退出均不改状态、不发重复事件；因此 `forceExit` 后，Executor 正常调用 `clearJoinState` 必须成功且不改状态。重复铸造回滚 `AlreadyMinted(tokenAddress, actionId, round)`。不存在关联时 `executor` 返回零，但写操作拒绝零关联。`isJoined` 与 `isJoinedByRound` 无记录时返回 false。

**铸造信息查询**：`mintedProposalReward(tokenAddress, actionId, round)` 返回 `(amount, minted)`——`amount` 为本轮已铸造的金额，`minted` 表示本轮是否已铸造；未铸造与未关联的行动均返回 `(0, false)`，不回滚。前端与索引据此判断某行动某轮是否已领取，不需要扫描事件。

**激励链路对成员不透明**：Executor 每轮经 `mintProposalReward` 一次性领取该行动的整笔激励，去重键 `tokenAddress + actionId + round` 即行动级；领取后由 Executor 按自身账本分给参与成员。成员只与 Executor 的成员级入口打交道，不需要了解也不依赖 ActionTarget 这一层；ActionTarget 不向成员暴露任何领取入口。

## forceExit

`forceExit` 接口见 [`IActionTarget.sol`](../../../interfaces/action/IActionTarget.sol)。

Executor 失效时，成员 NFT 当前持有人可清除加入状态并触发事件。该操作不调用 Executor、不转资产、不承诺返还资产；前端默认隐藏，并需说明与正常退出的区别。

加入查询立即排除该记录；Executor 的资产、历史、结算及 GroupAction 归属不变，不能凭旧状态自动恢复加入状态。GroupAction 归属只能经 Executor 正常退出清理；对群聊资格的影响统一见 [Chat 类型](../group-chat/05-chat-types.md#forceexit-与资格)。

## Round 查询

行动阶段 Round 查询见 [阶段模型](02-phase-model.md) 及各 Executor 接口；`IActionTarget.sol` 提供按 Round 查询已关联 Proposal 的列表接口。

从 Vote 的 `votedProposalIds(tokenAddress, round, offset, limit, reverse)` 逐页读取本轮有票 Proposal，再按 `executor` 映射筛选，不维护独立反向索引，不在这里计算激励门槛；不能读成历史累计。不另设人工 Proposal 数量上限。

`actionIdsByExecutor` 与 `actions` 的 `total` 由「逐页读完本轮列表 → 按映射筛选 → 切片」得出，单次调用在同一交易内完成；本轮有票 Proposal 数量的上界由 Submit 的每轮提案数上界保证，ActionTarget 不额外限制。

**集合读取分页**：`actionIdsByExecutor(tokenAddress, round, executor, offset, limit, reverse)` 和 `actions(tokenAddress, round, offset, limit, reverse)` 均为无界集合（某轮某 executor 的行动数、某轮总行动数由外部创建决定），采用标准分页签名返回 `(列表, total)`。

## 实现约束

分页查询的 `offset` 越界返回空数组与真实总数，不回滚；`limit` 超剩余按剩余返回。forceExit 重复清理无操作，不发重复事件；不能以清理失败阻塞 Executor 正常退还资产。ActionTarget 不校验业务 Round，也不校验 Proposal 的投票门槛。

激励转发见 [铸造链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
