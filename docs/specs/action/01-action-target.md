# ActionTarget

ActionTarget 是社群行动 Proposal 的统一 Target。Core 和回调使用 `proposalId`，Executor 使用 `actionId`，两者数值相同；关联键为 `tokenAddress + proposalId`。

## 创建与回调

创建行动时指定 `tokenAddress`、`title`、`details`，并设 `target = ActionTarget`、`targetMode = Callback`。`ProposalBody.creationData` 的前 20 字节是 Executor 地址，剩余字节按该 Executor 的约定编码。Executor 无需配置时只传地址。使用内置 Executor 时按其配置结构体填写 `executorParams`。

```solidity
creationData = abi.encodePacked(executorAddress, abi.encode(executorParams));
```

1. 调用者须为 Submit，否则回滚 `NotSubmit`。
2. 创建数据须至少有 20 字节，否则回滚 `CreationDataTooShort`。取前 20 字节得到 Executor 地址。地址没有合约代码时回滚 `ExecutorNotContract`。
3. 调用 `ACTION_TARGET_ADDRESS()` 握手。调用回滚或返回的数据无法解码为地址时回滚 `ExecutorHandshakeFailed`。返回的地址与当前 ActionTarget 不同时回滚 `ExecutorTargetMismatch`。
4. 检查行动尚未绑定 Executor，重复绑定回滚 `AlreadyCreated`。先检查握手能优先报告调用方传入的 Executor 接线错误。
5. 记录绑定，发出 `ActionRegistered`，并将地址后的所有字节原样交给 Executor。

推举与投票直接按已保存的绑定找到 Executor。`submitData` 和 `voteData` 由各自操作者提供，可传 `0x`，业务格式由 Executor 定义。内置 Executor 的推举回调只校验调用者。

| Core 调用时点 | ActionTarget 行为 |
| --- | --- |
| `onProposalCreated` | 保存 Executor 绑定并登记行动索引，转发内层创建配置 |
| `onProposalSubmitted` | 按绑定转发本次推举的轮次、成员和 `submitData` |
| `onProposalVoted` | 按绑定转发本次投票的轮次、成员、票数增量和 `voteData` |

ActionTarget 的推举回调仅接受 Submit 调用，投票回调仅接受 Vote。Executor 的回调仅接受 ActionTarget。未绑定时，推举和投票回调回滚 `UnboundProposal`。Executor 的回调可能携带任意 revert data，ActionTarget 原样传出，外层操作随之回滚。完整声明见 [IProposalTarget](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IProposalTarget.sol) 与 [IActionExecutor](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionExecutor.sol)。

提案创建者可以绑定任何通过握手的 Executor。绑定授予该合约在此行动上调用 `registerJoinState`、`clearJoinState` 和 `mintActionReward` 的权限。投票者可从提案正文的 `creationData` 核对 Executor。

## 加入与退出

记录当前成员是否加入行动，供加入列表和外部资格查询；包括 GroupAction，但不保存 Executor 的资产、验证或链群归属。

**唯一写入者**：ActionTarget 是加入态的唯一所有者。Executor 判定「首次加入」必须读 `isJoined(tokenAddress, actionId, memberId)`，不得用自己的资产账本判定；成员全部退出时调用 `clearJoinState`。与行动类型无关的参与判定走 ActionTarget；某一行动类型的专属关系（如链群归属）走该 Executor。加入/退出是否满足阶段与资格条件由 Executor 判定，ActionTarget 只做登记。

**事件分层设计**：ActionTarget 发出加入态登记事件 `JoinStateRegistered` / `JoinStateCleared`（与登记函数同名系，只包含 `tokenAddress, actionId, memberId, round`；`JoinStateCleared` 另带 `forced` 字段，区分 Executor 正常清理与 `forceClearJoinState` 兜底清理），记录通用加入状态。两个事件的 `round` 口径不同：`JoinStateRegistered.round` 是**登记时的加入轮**；`JoinStateCleared.round` 是**清理时的当前加入轮**，不一定是原登记轮——加入态跨轮持续存在，成员可能在若干轮之后才退出。各 Executor（如 `ILpExecutor`、`IGroupActionExecutor`）在自己的合约中发出包含完整业务字段（`amount, providerId, groupId` 等）的业务事件（`GroupActionJoined`、`LpJoined`、`ServiceJoined` 等域前缀名）。两层事件名称不同，各自记录各自层级的信息。ActionTarget 不发出 `*Withdrawn` 事件，因为 withdraw 不改变加入状态。

同一分层适用于激励，但两条事件的**名字与参数都不同**，因为层级与主体不同：行动级的整笔铸造由 ActionTarget 的 `ActionRewardMinted(tokenAddress, actionId, round, amount)` 记录，成员级的 `MemberRewardMinted(tokenAddress, actionId, memberId, round, mintAmount, burnAmount)` 由各 Executor 记录（见 [铸造链路](07-minting.md#铸造链路)）。`ActionRewardMinted` 的四个字段全部取自 `mintActionReward` 这一笔调用本身，不需要额外状态。

**集合读取**：成员的行动列表是无界集合（由成员加入次数决定），采用标准分页签名 `actionIdsByMemberId(tokenAddress, memberId, offset, limit, reverse) returns (actionIds[], totalCount)`。行动的成员列表同样是无界集合，但只保留一条完整读取路径——按轮读取 `memberIdsByActionId(tokenAddress, round, actionId, offset, limit, reverse) returns (memberIds[], totalCount)`（指定 `round` 时的成员列表）；不带 `round` 的当前态列表不单设，当前态用 `isJoined` 点查或传当前轮读取。参数语义：越界返回空数组与真实总数、不回滚；`limit` 超剩余按剩余返回；`limit = 0` 只返回总数；`reverse` 为 true 时逆序遍历当前存储顺序。符合[集合读取设计原则](../../dev-standards.md#43-集合读取函数)。

**历史查询**：提供按 round 的历史快照查询，`isJoinedByRound(tokenAddress, round, actionId, memberId)` 检查指定 round 时的加入状态，`memberIdsByActionId(tokenAddress, round, actionId, offset, limit, reverse)` 返回指定 round 时的成员列表（分页）。round 的口径是**加入轮**（= 当前投票轮 - 1，加入在投票后一个阶段开放，见 [阶段模型](02-phase-model.md)），与三个 Executor 的加入 Round 同轴；加入态事件与按轮快照同源，`JoinStateRegistered.round` 也是加入轮（`JoinStateCleared.round` 例外，它是清理时的当前加入轮，见上）。快照不会落在创建轮之前——该不变式由 `registerJoinState` 的 `JoinNotOpen` 入口校验保证（见写操作权限）；`ActionRegistered` 的 round 即创建投票轮，也是该行动的首个加入轮，因此以它查询成员列表可得首个加入窗口的成员。round 大于当前加入轮时，两条查询均回滚 `RoundNotStarted(round, joinRound)`。按轮快照的读法随共享原语：查询的 `round` 上没有写入时，返回该轮之前最近一次记录的状态（空缺轮继承先前状态）；早于首次写入返回未加入 / 空列表。同一加入轮内的多次写入（加入、退出、再加入）在该轮只保留最后一次写入的值——事件仍按发生顺序逐条记录；两者并用时，以事件顺序还原过程，以快照读取该轮结束状态。

**加入轮查询**：`joinedRounds(tokenAddress, actionId, memberIds[]) returns (uint256[] rounds)` 批量返回每个成员的加入轮（数组与入参等长、按下标配对）。round 口径与 `JoinStateRegistered` 一致，为登记时的加入轮；未加入（从未加入、已退出或已 `forceClearJoinState`）与未关联的行动/代币返回 0。该查询反映当前状态；历史过程以事件顺序还原，历史快照以按轮查询读取。

**顺序契约（不保证跨调用稳定）**：`actionIdsByMemberId`、`memberIdsByActionId` 由共享集合原语支撑——追加写入，删除用 swap-and-pop（把末位元素搬到被删元素的位置）。因此**同一集合、同一 `offset` 的返回内容不保证在两次调用之间稳定**，`reverse` 只表示「逆序遍历当前存储顺序」，仅在集合自建立以来没有发生过删除时才等于「加入逆序」。调用方（前端、索引）必须每次以 `totalCount` 为准重新拉取，不得跨调用缓存 `offset`，也不得按「先拉首页、再按旧 `totalCount` 增量补后续页」的方式拼接。

`actions`、`actionIdsByExecutor` 由创建回调维护的**追加写入、从不删除**的索引派生，`reverse` 即创建逆序；`votedActionIds` 读取 Vote 中按 `tokenAddress + round + ActionTarget` 索引的本轮投票提案，再按 executor 映射筛除未绑定提案，保留 Vote 的首次投票顺序。三者的 `offset` 语义同样按上面执行。

完整 ABI 见 [`IActionTarget.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionTarget.sol)。

`ActionTarget` 的构造函数只接收 Mint 地址，并在构造期从 Mint 读取 `VOTE_ADDRESS`、`SUBMIT_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS` 保存，同时保存 `MINT_ADDRESS`；**不设调用者限制、不保存部署者、不做零地址校验**——与 core 卷 `DEP-01` 同一分工：部署期静态不变量由部署脚本在广播前校验，合约侧不重复校验。

构造注入后不存在「部署后第一笔交易被抢跑」的初始化窗口：五个绑定在同一笔部署交易内完成。**这五个绑定值就是本合约全部写入口的鉴权根**：`SUBMIT_ADDRESS`/`VOTE_ADDRESS` 门禁三类 Core 回调，`MEMBER_NFT_ADDRESS` 是成员持有人判据，`PHASE_ADDRESS` 决定加入轮与结算轮，`MINT_ADDRESS` 是唯一铸造出口；部署脚本广播前校验、`21_check.sh` 部署后逐项复核这五个值。

`mintAddress` 及从 Mint 派生出的 `voteAddress`、`submitAddress`、`memberNFTAddress`、`phaseAddress` 有代码是部署期静态不变量。四项派生依赖在构造函数内各读取一次并缓存，经同名 getter 暴露；Mint 须先完成部署。`phaseAddress` 由 Mint 从 Vote 派生后再由 ActionTarget 读取，ActionTarget 因此与投票轴共享同一 Phase，当前投票轮直读 `IPhase.currentPhase()`，不经 Mint 或 Vote 二跳。

**写操作权限**：`registerJoinState`/`clearJoinState`/`mintActionReward` 仅该 `(tokenAddress, actionId)` 已注册绑定的 Executor 可调用——判据是 `executor[tokenAddress][actionId] == msg.sender` 且该绑定非零，未注册绑定时任何调用者都拒绝；不满足即回滚 `UnauthorizedExecutor(tokenAddress, actionId)`。`registerJoinState` 另有硬性入口校验：当前投票轮必须**大于**该行动的创建轮（`ActionRegistered` 的 round），否则回滚 `JoinNotOpen(tokenAddress, actionId, currentRound, createdRound)`——加入在投票后一个阶段开放，投票轮未走完不得登记加入；`clearJoinState`/`forceClearJoinState` 无需该校验（已加入本身蕴含加入轮已开放，且轮次单调不减）。`mintActionReward` 只接受已创建关联行动的 `actionId`，绑定键与铸造键一致，不存在「持某个行动的 Executor 去铸另一个行动」的路径。`forceClearJoinState` 仅该 memberId 的 MemberNFT 当前持有人可调用：存在但不是持有人回 `NotMemberOwner(memberId)`，id 不存在时 `ownerOf` 的 `ERC721NonexistentToken` 原样冒泡（与 03-participation 的 Provider 额度路径同口径）。

**结算窗口由 Executor 校验。** LP 执行器使用 `phase−2`，Group/Service 执行器使用 `phase−3`。`mintActionReward` 把已投票行动交给 Mint 结算，Mint 校验投票轮是否已结束。

重复加入、重复退出均不改状态、不发重复事件；因此 `forceClearJoinState` 后，Executor 正常调用 `clearJoinState` 必须成功且不改状态。重复铸造回滚 Mint 的 `ProposalRewardAlreadyMinted(tokenAddress, round, proposalId)`——行动级去重键 `tokenAddress + actionId + round` 由 Mint 的状态位承担，ActionTarget 不另存铸造状态位。不存在关联时 `executor` 返回零，但写操作拒绝零关联。`isJoined` 无记录时返回 false；`isJoinedByRound` 在加入轮已开始但无记录时返回 false。

**铸造信息查询。** `actionReward(tokenAddress, round, actionId)` 返回 `(amount, minted)`。绑定 Executor 的行动从 Mint 的 `proposalRewardSettlement` 读取结算结果。`Unsettled` 返回可铸造金额和 `false`，`Minted` 返回实际铸造金额和 `true`。`Burned` 和未绑定的行动返回 `(0, false)`，供 Executor 判断可分配额度。已销毁的实际金额可从 Core 查询。铸造时发出的 `ActionRewardMinted.amount` 与查询的已铸造金额一致。

**激励链路对成员不透明**：Executor 每轮经 `mintActionReward` 一次性铸造该行动的整笔激励，去重键 `tokenAddress + actionId + round` 即行动级；铸造后由 Executor 按自身账本分给参与成员。成员只与 Executor 的成员级入口打交道，不需要了解也不依赖 ActionTarget 这一层；ActionTarget 不向成员暴露任何激励铸造入口。

## forceClearJoinState

`forceClearJoinState` 接口见 [`IActionTarget.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IActionTarget.sol)。

Executor 失效时的兜底清理：成员 NFT 当前持有人可清除加入态登记并发 `JoinStateCleared(..., forced = true)`。该函数**只清 ActionTarget 的注册表**：

- 不回调 Executor：调用这个函数本身就意味着 Executor 已不可信，任何回调都可能被故障合约阻断或吞掉 gas，反而使注册表无法清理。
- 不结算资金、不转资产，也不发 `*Exited`；Executor 侧仓位保持原样，由用户走 Executor 自己的退出路径（若仍可用）。
- 成员不在注册表时幂等返回，不发重复事件；前端默认隐藏，并需说明与正常退出的区别。

加入查询立即排除该记录；Executor 的资产、历史、结算及 GroupAction 归属不变，不能凭旧状态自动恢复加入状态。索引器必须把「注册表状态」与「Executor 仓位」视为两个对象：`JoinStateCleared(forced = true)` 只代表行动清单已清理，不代表仓位已关闭。GroupAction 归属只能经 Executor 正常退出清理；对群聊资格的影响统一见 [Chat 类型](../group-chat/05-chat-types.md#forceclearjoinstate-与资格)。

## Round 查询

行动阶段 Round 查询见 [阶段模型](02-phase-model.md) 及各 Executor 接口。

**行动登记索引**：`actions(tokenAddress, offset, limit, reverse) returns (actionIds[], executors[], totalCount)` 与 `actionIdsByExecutor(tokenAddress, executor, offset, limit, reverse) returns (actionIds[], totalCount)` 由 `onProposalCreated` 维护的追加写入索引派生（绑定建立后永不删除，故 `reverse` 即创建逆序），前者为本代币全部已关联行动，后者为某 Executor 名下的行动。两者均为无界集合（由行动创建数决定），采用标准分页签名。

**本轮有投票的行动**由 `votedActionIds` 查询。它通过 Vote 的 `votedProposalIdsByTarget` 读取本轮指向当前 ActionTarget 且收到过投票的 Proposal，再按 `executorByActionId` 筛掉未绑定项。`NoCallback` 提案可以指向当前 ActionTarget，但不会建立 executor 映射。筛选后的列表沿用 Vote 的首次投票顺序，以该列表计算总数并分页。每个社区每轮最多推举 1,000 个 Proposal，两条本轮投票行动查询的候选数都受这个上限约束。见 [Submit 推举规则](../core/05-submit.md#推举)。

**按 Executor 集合的本轮投票行动**由 `votedActionIdsByExecutors` 查询。它从同一列表中保留 executor 属于给定集合的行动，按首次投票顺序返回全部匹配结果。`actionExecutors` 与 `actionIds` 逐项对齐。给定集合为空时返回空数组，重复传入同一个 executor 不会产生重复项。GroupService 结算读取 GroupAction 在验证完成时登记的来源激励和权重。见 [服务 Executor](06-service-executor.md#权重)。

## 实现约束

分页查询的 `offset` 越界返回空数组与真实总数，不回滚；`limit` 超剩余按剩余返回。`forceClearJoinState` 重复清理无操作，不发重复事件；它不回调 Executor、不阻塞也不参与 Executor 的资金结算，因此 Executor 故障不会把注册表清理拖死。ActionTarget 不校验各 Executor 的铸造窗口，也不校验 Proposal 的投票门槛。

激励转发见 [铸造链路](07-minting.md#铸造链路)，验收见 [Action 验收](08-testing.md)。

## 状态口径

- `joinedRounds` 只表示**当前加入轮**：成员退出后归零，与「从未加入」不可区分；「是否在某轮参与过」只能由 `isJoinedByRound` 回答，链下不得用 `joinedRounds` 判定历史参与。
- `forceClearJoinState` 与 `clearJoinState` 在状态上完全等价，差别只在事件 `JoinStateCleared.forced`；「被强制清理」这一事实只能由事件还原，链下索引必须落库该字段。
- 三本注册表（`executorByActionId`、`actionIds`、`actionIdsByExecutor`）只增不删，没有行动注销或重新绑定的路径；`AlreadyCreated` 是永久守卫，链下不得假设存在治理兜底。
- 加入轮派生统一走 `ActionRoundAxis.joinRound`（中立轴库，`ExecutorBase._joinRound()` 是唯一实现）：`registerJoinState` 经自身 `_joinRound()` 取值，与 `clearJoinState` / `forceClearJoinState` 及三个 Executor 使用同一来源；`registerJoinState` 内不再内联 `currentPhase() - 1`。`phase` 为 0/1 时轴库返回 0，但 `currentRound <= createdRound` 的守卫先命中 `JoinNotOpen`，回滚语义不变（`testRegisterJoinStateRejectsBeforeJoinOpens` 覆盖 phase 0 与 1）。
