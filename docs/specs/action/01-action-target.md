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
2. 第 0 项恰为 32 字节（abi.encode(address) 的形态），abi.decode 后非零且有代码
3. IActionExecutor(executor).actionTarget() == address(this)
4. 该 (tokenAddress, proposalId) 尚未记录 executor
```

第 1～3 步任一步失败回滚 `InvalidExecutor()`；第 4 步回滚 `AlreadyCreated(tokenAddress, actionId)`，拒绝同一复合键重复创建，不覆盖已记录映射。

**Target Data 的位置契约**：Target Data 是无键的 `bytes[]`，只能按位置读取。ActionTarget 只读取并校验第 `0` 项（executor 保留项）并原样转发整个数组；其余各项的数量、位置与编码**一律由该 Executor 在自己的规格中固定并在对应回调内自行校验**。**创建与推举回调传入同一份** `body.targetData`（core `Submit.sol:289,296`）：第 `0` 项均为 executor 保留项，业务项从 `1` 起算；投票回调传入投票者在 `vote()` 中提供的该项数据（core `Vote.sol:322`）：非空时第 `0` 项必须为已绑定 Executor 地址、其后为业务项，为空时不携带业务数据。**转发门禁**：三类回调中 `targetData` 非空时，第 `0` 项必须解码为该行动已绑定的 Executor 地址（创建回调即握手绑定的地址），否则回滚 `InvalidExecutor()`；投票回调的 `targetData` 可为空，为空时原样转发。项数与位置不匹配由各 Executor 用自己的错误拒绝，不在本层设通用错误。

| Core 调用时点 | ActionTarget 行为 |
| --- | --- |
| `onProposalCreated` | 按上表校验，保存 Executor 映射并登记行动索引（`actions`/`actionIdsByExecutor` 的数据源，追加写入、从不删除），原样转发完整创建 Target Data |
| `onProposalSubmitted` | 读取已保存映射，转发本次推举上下文和 Target Data |
| `onProposalVoted` | 读取映射，转发 `round`、`voterId`、本次增量票数及 Target Data，由 Executor 记账 |

完整签名统一见 [Core Target 回调](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IProposalTarget.sol)。ActionTarget 与每个 Executor 都实现这三类回调：ActionTarget 的 `onProposalCreated`/`onProposalSubmitted` 仅 Submit 可调用，`onProposalVoted` 仅 Vote 可调用；Executor 的同名回调仅接受 ActionTarget 调用，其他调用者回滚 `UnauthorizedCallback()`。推举与投票回调遇到未绑定 `(tokenAddress, proposalId)` 时回滚 `UnboundProposal(tokenAddress, proposalId)`——结构上不可达（创建回调必先于推举），仅防御 Core 侧缺陷。任一回调失败均回滚对应外层操作。

## 加入与退出

记录当前成员是否加入行动，供加入列表和外部资格查询；包括 GroupAction，但不保存 Executor 的资产、验证或群归属。

**唯一写入者**：ActionTarget 是加入态的唯一所有者。Executor 判定「首次加入」必须读 `isJoined(tokenAddress, actionId, memberId)`，不得用自己的资产账本判定；成员全部退出时调用 `clearJoinState`。与行动类型无关的参与判定走 ActionTarget；某一行动类型的专属关系（如链群归属）走该 Executor。加入/退出是否满足阶段与资格条件由 Executor 判定，ActionTarget 只做登记。

**事件分层设计**：ActionTarget 发出加入态登记事件 `JoinStateRegistered` / `JoinStateCleared`（与登记函数同名系，只包含 `tokenAddress, actionId, memberId, round`；`JoinStateCleared` 另带 `forced` 字段，区分 Executor 正常清理与 `forceExit` 应急清理），记录通用加入状态；各 Executor（如 `ILpExecutor`、`IGroupActionExecutor`）在自己的合约中发出包含完整业务字段（`amount, isExperience, providerMemberId` 等）的业务事件（`Joined`、`Exited`）。两层事件名称不同，各自记录各自层级的信息。ActionTarget 不发出 `Withdrawn` 事件，因为 withdraw 不改变加入状态。

同一分层适用于激励，但两条事件的**名字与参数都不同**，因为层级与主体不同：行动级的整笔铸造由 ActionTarget 的 `ActionRewardMinted(tokenAddress, actionId, round, amount)` 记录，成员级的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` 由各 Executor 记录（见 [铸造链路](07-minting.md#铸造链路)）。`ActionRewardMinted` 的四个字段全部取自 `mintActionReward` 这一笔调用本身，不需要额外状态。

**集合读取**：成员的行动列表是无界集合（由成员加入次数决定），采用标准分页签名 `actionIdsByMemberId(tokenAddress, memberId, offset, limit, reverse) returns (actionIds[], total)`。行动的成员列表同样是无界集合，但只保留一条完整读取路径——按轮读取 `memberIdsByActionId(tokenAddress, actionId, round, offset, limit, reverse) returns (memberIds[], total)`（指定 `round` 时的成员列表）；不带 `round` 的当前态列表不单设，当前态用 `isJoined` 点查或传当前轮读取。参数语义：越界返回空数组与真实总数、不回滚；`limit` 超剩余按剩余返回；`limit = 0` 只返回总数；`reverse` 为 true 时逆序遍历当前存储顺序。符合[集合读取设计原则](../../migration-standards.md#集合读取函数的设计原则)。

**历史查询**：提供按 round 的历史快照查询，`isJoinedByRound(tokenAddress, actionId, memberId, round)` 检查指定 round 时的加入状态，`memberIdsByActionId(tokenAddress, actionId, round, offset, limit, reverse)` 返回指定 round 时的成员列表（分页）。round 的口径是**加入轮**（= 当前投票轮 - 1，加入在投票后一个阶段开放，见 [阶段模型](02-phase-model.md)），与三个 Executor 的加入 Round 同轴；加入态事件与按轮快照同源，事件中的 round 也是加入轮。快照不会落在创建轮之前——该不变式由 `registerJoinState` 的 `JoinNotOpen` 入口校验保证（见写操作权限）；`ActionCreated` 的 round 即创建投票轮，也是该行动的首个加入轮，因此以它查询成员列表可得首个加入窗口的成员。round 大于当前加入轮时按未开始处理：`isJoinedByRound` 返回 false，列表返回空数组与 `total = 0`。按轮快照的读法随共享原语：查询的 `round` 上没有写入时，返回该轮之前最近一次记录的状态（空缺轮继承先前状态）；早于首次写入返回未加入 / 空列表。同一加入轮内的多次写入（加入、退出、再加入）在该轮只保留最后一次写入的值——事件仍按发生顺序逐条记录；两者并用时，以事件顺序还原过程，以快照读取该轮结束状态。

**顺序契约（不保证跨调用稳定）**：`actionIdsByMemberId`、`memberIdsByActionId` 由共享集合原语支撑——追加写入，删除用 swap-and-pop（把末位元素搬到被删元素的位置）。因此**同一集合、同一 `offset` 的返回内容不保证在两次调用之间稳定**，`reverse` 只表示「逆序遍历当前存储顺序」，仅在集合自建立以来没有发生过删除时才等于「加入逆序」。调用方（前端、索引）必须每次以 `total` 为准重新拉取，不得跨调用缓存 `offset`，也不得按「先拉首页、再按旧 `total` 增量补后续页」的方式拼接。

`actions`、`actionIdsByExecutor` 由创建回调维护的**追加写入、从不删除**的索引派生，`reverse` 即创建逆序；`votedActions` 由 Vote 的本轮只追加列表派生，顺序随 Vote。三者的 `offset` 语义同样按上面执行。

完整 ABI 见 [`IActionTarget.sol`](../../../interfaces/action/IActionTarget.sol)。

`init` 校验未初始化与依赖地址非零：重复调用回滚 `AlreadyInitialized()`，任一依赖地址为零回滚 `InvalidAddress()`；不设调用者限制、不保存部署者。四个依赖地址由 `memberNFTAddress()`/`submitAddress()`/`voteAddress()`/`mintAddress()` 提供，供发布前检查脚本逐项核对绑定结果；不把「部署后立即初始化」当作防抢跑保证。Phase 地址不经 init 传入，由 init 时从 `IVote(voteAddress).phaseAddress()` 派生缓存——Vote 须先完成 init，否则其 phaseAddress 为零、回滚 `InvalidAddress()`；派生保证 ActionTarget 与投票轴共享同一 Phase，此后当前投票轮直读 `IPhase.currentPhase()`，不经 Vote 二跳；派生结果经 `phaseAddress()` 暴露，检查脚本核对它与 Vote 的 phaseAddress 一致。

**写操作权限**：`registerJoinState`/`clearJoinState`/`mintActionReward` 仅该 `(tokenAddress, actionId)` 已注册绑定的 Executor 可调用——判据是 `executor[tokenAddress][actionId] == msg.sender` 且该绑定非零，未注册绑定时任何调用者都拒绝；不满足即回滚 `UnauthorizedExecutor(tokenAddress, actionId)`。`registerJoinState` 另有硬性入口校验：当前投票轮必须**大于**该行动的创建轮（`ActionCreated` 的 round），否则回滚 `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)`——加入在投票后一个阶段开放，投票轮未走完不得登记加入；`clearJoinState`/`forceExit` 无需该校验（已加入本身蕴含加入轮已开放，且轮次单调不减）。`mintActionReward` 只接受已创建关联行动的 `actionId`，绑定键与铸造键一致，不存在「持某个行动的 Executor 去铸另一个行动」的路径。`burnRewardIfNeeded(tokenAddress, actionId, round)` 任何人可触发（permissionless）——未绑定行动直接无操作；只能处理已结束轮次（否则回滚 `InvalidRound(round)`）；该轮未铸造或激励为零（读取 Mint 的 `proposalRewardByProposalId`）时无操作（先于判据调用）；随后经 `IActionExecutor.needBurnReward` 取得业务判据，为真时调用 Mint 的 `burnUnmintedProposalReward(tokenAddress, round, proposalId)` 核销该轮预留激励——按行动精确归因，无代币移动；重复调用无操作。`forceExit` 仅该 memberId 的 MemberNFT 当前持有人可调用，否则 `NotMemberOwner(memberId)`。

重复加入、重复退出均不改状态、不发重复事件；因此 `forceExit` 后，Executor 正常调用 `clearJoinState` 必须成功且不改状态。重复铸造回滚 `AlreadyMinted(tokenAddress, actionId, round)`。不存在关联时 `executor` 返回零，但写操作拒绝零关联。`isJoined` 与 `isJoinedByRound` 无记录时返回 false。

**铸造信息查询**：`actionReward(tokenAddress, actionId, round)` 返回 `(amount, minted)`——`amount` 在已铸造时为本轮实际铸造金额、未铸造时为本轮理论可铸造数量（按 Mint 账本计算，未投票、未达门槛、零额度或已销毁时为 `0`），`minted` 表示本轮是否已铸造；未关联的行动返回 `(0, false)`，已关联但未铸造的行动返回 `(理论数量, false)`，均不回滚。前端与索引据此判断某行动某轮是否已铸造与可铸造数量，不需要扫描事件；同一笔铸造另由 `ActionRewardMinted(tokenAddress, actionId, round, amount)` 留痕，`amount` 与该查询铸造后的返回值同源，供历史回溯与审计使用。`burnInfo(tokenAddress, actionId, round)` 返回 `(amount, burned)`——本轮已销毁的金额与是否已销毁，与 `RewardBurned` 事件同源；未销毁与未关联返回 `(0, false)`，不回滚。

**激励链路对成员不透明**：Executor 每轮经 `mintActionReward` 一次性铸造该行动的整笔激励，去重键 `tokenAddress + actionId + round` 即行动级；铸造后由 Executor 按自身账本分给参与成员。成员只与 Executor 的成员级入口打交道，不需要了解也不依赖 ActionTarget 这一层；ActionTarget 不向成员暴露任何领取入口。

## forceExit

`forceExit` 接口见 [`IActionTarget.sol`](../../../interfaces/action/IActionTarget.sol)。

Executor 失效时，成员 NFT 当前持有人可清除加入状态并触发 `JoinStateCleared(..., forced = true)`，与 Executor 正常清理的唯一区别是该字段。该操作不调用 Executor、不转资产、不承诺返还资产；前端默认隐藏，并需说明与正常退出的区别。

加入查询立即排除该记录；Executor 的资产、历史、结算及 GroupAction 归属不变，不能凭旧状态自动恢复加入状态。GroupAction 归属只能经 Executor 正常退出清理；对群聊资格的影响统一见 [Chat 类型](../group-chat/05-chat-types.md#forceexit-与资格)。

## Round 查询

行动阶段 Round 查询见 [阶段模型](02-phase-model.md) 及各 Executor 接口。

**行动登记索引**：`actions(tokenAddress, offset, limit, reverse) returns (actionIds[], executors[], total)` 与 `actionIdsByExecutor(tokenAddress, executor, offset, limit, reverse) returns (actionIds[], total)` 由 `onProposalCreated` 维护的追加写入索引派生（绑定建立后永不删除，故 `reverse` 即创建逆序），前者为本代币全部已关联行动，后者为某 Executor 名下的行动。两者均为无界集合（由行动创建数决定），采用标准分页签名。

**本轮有投票的行动**：`votedActions(tokenAddress, round, offset, limit, reverse) returns (actionIds[], executors[], total)` 一次读取 Vote 的 `votedProposalIds(tokenAddress, round, 0, type(uint256).max, false)` 取得本轮有票 Proposal 全列表（Pagination 对超限 `limit` 返回剩余；列表规模上界由 Submit 的每轮提案数上界保证），再按 `executor` 映射筛选，不在这里计算激励门槛；不能读成历史累计。其 `total` 由「读完本轮列表 → 按映射筛选 → 切片」得出，单次调用在同一交易内完成，ActionTarget 不另设人工 Proposal 数量上限。

## 实现约束

分页查询的 `offset` 越界返回空数组与真实总数，不回滚；`limit` 超剩余按剩余返回。forceExit 重复清理无操作，不发重复事件；不能以清理失败阻塞 Executor 正常退还资产。ActionTarget 不校验业务 Round，也不校验 Proposal 的投票门槛。

激励转发见 [铸造链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。
