# LOVE20BSC Action 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义社群行动 Proposal 类型，说明行动如何被创建、投票、加入、验证、结算和铸造激励，以及 LP 行动、链群行动和链群服务行动之间的边界。

## 1. 组件和依赖

`action` 由以下组件组成：

- `ActionTarget`：所有社群行动 Proposal 的统一 Target；
- LP 行动执行合约；
- 链群行动执行合约；
- 链群服务行动执行合约。

组件依赖 `core` 的 `MemberNFT`、`Stake`、`Submit`、`Vote`、`Mint` 和 `Phase` 接口。核心只传递 Proposal 上下文、治理票增量和不透明 KV；候选人、链群、LP、资产托管和服务分配由本代码库解释。

执行合约可以同时服务多个代币社区和多个 Proposal。所有可复用状态至少按 `tokenAddress + actionId + ActionRound` 隔离。

## 2. ActionTarget

### 2.1 Proposal 关联

行动类 Proposal 必须使用 `target = ActionTarget` 和 `targetMode = Callback`。Proposal 创建 KV 的第 `0` 项是保留项：`key = keccak256("executor")`，`value = abi.encode(executorAddress)`。

`executorAddress` 必须是非零且包含合约代码的地址。第 `0` 项之外的 KV 可以为空，业务字段和校验完全由 Executor 负责。
因此行动 Proposal 的创建 KV 至少包含第 `0` 项；“空初始化 KV”仅表示没有额外业务项，不能省略 `executor` 项。

ActionTarget 以 `tokenAddress + proposalId` 为唯一键保存 Executor，把完整创建 KV 原样转发给 Executor，不删除保留项、不重新分配数组。Executor 的 Proposal 创建回调就是该 Proposal 的初始化，重复初始化必须回滚；只有 ActionTarget 可以调用 Executor 的三个回调。

核心回调名称及标准参数为 `onProposalCreated(tokenAddress, proposalId, keys, values)`、`onProposalSubmitted(tokenAddress, proposalId, submitterId, keys, values)` 和 `onProposalVoted(tokenAddress, proposalId, voterId, votes, keys, values)`。

ActionTarget 不解析 `verificationRule`、`verificationKeys`、`verifierCandidateId` 或其他业务字段。推举回调使用 `submitterId`；投票回调的 `votes` 只表示本次新增治理票，`verifierCandidateId` 等信息放在投票 KV 中。

### 2.2 参与登记

ActionTarget 维护通用的“MemberNFT 是否参与某个行动”登记，并提供指定 `tokenAddress + actionId + memberId` 的当前参与判断，以及指定社区和成员的当前参与行动数量及列表。参与数量随登记写入和清除同步更新，供 `TokenMainManager` 常数时间判断社区行动参与资格，`TokenActionMainManager` 直接读取指定行动登记。ActionTarget 不维护成员跨所有社区的全局参与列表，也不接收或持有行动资产，不实现加入、退出、验证、结算和行动层分配。对于普通行动，ActionTarget 登记是前端“当前已参与行动”列表和外部参与资格判断的依据；Executor 的资产和业务状态由 Executor 自己维护，是资产与结算查询的依据。

链群行动是明确例外：链群行动 Executor 同时承担链群参与关系的维护职责，并作为“某个 `memberId` 当前是否属于某个 `groupId`”的唯一判断来源。该状态服务于链群业务和链群 Chat，不由 ActionTarget 推导。

正常流程由 Executor 完成：加入、追加、部分撤回、全部退出、资产返还、行动结束结算和登记清理。登记写入和正常清除只允许该 Proposal 关联的 Executor 调用；Executor 不能把未通过自身业务校验的记录写入 ActionTarget。Executor 失效时，当前 MemberNFT 持有人可以调用 `forceExit(tokenAddress, actionId, memberId)`，直接清除 ActionTarget 的通用登记并触发事件。该入口不调用 Executor、不转移资产、不承诺资产返还，前端默认隐藏，只作为最后兜底。

强制退出后，ActionTarget 查询立即不再返回该参与记录；Executor 的历史参与、资产和链群归属等业务状态均不回写。Executor 不能利用旧状态自动恢复 ActionTarget 登记；需要资产恢复时必须由 Executor 提供独立的恢复流程。链群归属只在链群 Executor 的正常退出流程中更新，因此 `forceExit` 本身不改变链群 Chat 资格。

### 2.3 查询

通用参与登记至少提供：

- `isParticipating(tokenAddress, actionId, memberId)`；
- `actionIdsByMemberId(tokenAddress, memberId)`、对应的 `Count` 和 `AtIndex`；
- 仅关联 Executor 可调用的 `registerParticipation(tokenAddress, actionId, memberId)` 和 `unregisterParticipation(tokenAddress, actionId, memberId)`。

`registerParticipation` 对已登记成员幂等，`unregisterParticipation` 对未登记成员回滚；`forceExit` 使用同一删除逻辑但权限属于 MemberNFT 当前持有人。列表使用 swap-and-pop 或等价常数时间删除，顺序不作为业务语义。

ActionTarget 提供两类按治理 Round 的只读查询：

1. `proposalIdsByExecutor(tokenAddress, round, executor)` 返回该 Executor 关联的 `proposalId[]`；
2. `proposals(tokenAddress, round)` 返回本轮所有有投票且已关联 Executor 的 `proposalIds[]` 和一一对应的 `executors[]`。

两类查询先从 `Vote` 读取本轮有投票的 Proposal，再按 Proposal ID 读取 ActionTarget 映射并筛选，不维护独立反向索引。第一类返回值不重复返回 Executor；第二类用于前端行动列表。首版单轮一次性返回完整只读结果，写入操作必须使用有界批次。

## 3. ActionRound

行动层把 `Phase` 的无业务语义时间片映射为从 `1` 开始的四个业务阶段及其 ActionRound：投票阶段、加入阶段、验证阶段、铸币阶段。设当前 `Phase` 编号为 `p`，四个无参数查询固定返回：`currentRoundMint() = p - 3`、`currentRoundVerify() = p - 2`、`currentRoundJoin() = p - 1`、`currentRoundVote() = p`。这四个值是同一时间点上四个阶段当前对应的轮次标签，不表示交易执行顺序；各阶段使用的区块边界仍由 `Phase` 的历史记录决定。

当某个计算结果小于 `1` 时，该阶段对应的轮次尚未开始，查询回滚 `RoundNotStarted`，不返回 `0`。因此 `Phase 1` 至 `Phase 3` 是行动轮次的启动窗口，`Phase 4` 才是四个阶段都具有有效轮次的首个时间点。

同一时刻，四个阶段分别处理不同的滚动 Round，不表示串行交易顺序。加入阶段包括加入、追加、退出和其他行动参与状态变化。

LP、链群行动和链群服务行动共用四个阶段和同一铸币时间窗口：LP 和链群服务的验证阶段为空操作，链群行动在验证阶段执行公共验证。每个 Executor 自己实现 `canMint(actionId, round)`；统一阶段不等于统一铸币资格。

ActionTarget 提供无参数只读接口 `currentRoundVote()`、`currentRoundJoin()`、`currentRoundVerify()` 和 `currentRoundMint()`，按上述公式直接从 `Phase` 推导，不保存 ActionRound 历史，也不提供带通用阶段参数的 `currentRound`、`ActionRoundInfo` 或 `ActionRoundOf`。

## 4. 共同参与模型

- 行动参与主体统一为 MemberNFT 的 `memberId`；钱包地址只作为当前控制者。
- 可复用行动状态至少按 `tokenAddress + actionId + round` 隔离；除本规格明确要求的链群跨社区、跨行动聚合查询外，跨社区或跨行动读取必须拒绝。
- 体验资产按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账，归 Provider MemberNFT 所有，退出时返还对应 Provider。
- 自有资产和体验资产可以同时存在；部分撤回只减少指定账本，不互相抵扣。
- 对使用按 Round 参与历史的 Executor，加入阶段内的撤回直接更新该 Round 的参与权、验证权重和可得激励；加入阶段结束后，该 Round 的参与历史不再改变，后续撤回只写入后续 Round。未使用参与历史的 Executor 按自身冻结点结算；余额归零后才清除通用登记。
- MemberNFT 转移不改变已发生的快照、投票、验证或已结算状态，新持有人继续操作当前未铸造权益。

## 5. LP 行动执行合约

### 5.1 初始化

LP Executor 至少配置参与 LP Token 地址、`govRatioMultiplier`、`minGovRatio`，以及从 Proposal `details` 读取的行动说明和 `verificationRule`。LP Token 必须来自配置的 PancakeSwap Factory，且实现 Uniswap V2 Pair 的份额和储备接口。

### 5.2 加入和时间权重

只有对应 ActionRound 在同编号投票阶段已获得治理投票的 Proposal 才能在其加入阶段加入。首次加入的 MemberNFT 必须满足当前有效治理票占社区总治理票的 `minGovRatio`；后续加入按行动规则允许追加。每次加入记录该笔的 `joinBlock_i` 和 `amount_i`，并在加入时使用该 Round 的加入阶段起始区块与阶段区块数冻结时间扣减；后续结算不使用结算区块重新计算。

行动 Round 的总有效数量为所有参与者 `effectiveAmount` 之和。加入、追加、验证信息更新和部分撤回由 LP Executor 自己执行；退出返还该 Executor 记录的资产。时间扣减采用以下线性规则，并显式封顶避免阶段结束后的整数下溢：

```text
deduction_i = min(
    amount_i,
    amount_i × (joinBlock_i - joinPhaseStartBlock) / joinPhaseBlocks
)
deduction = Σ deduction_i
effectiveAmount = joinedAmount - deduction
```

加入发生在加入阶段内，因此正常情况下 `joinBlock_i - joinPhaseStartBlock < joinPhaseBlocks`；`min` 只用于防止异常边界造成下溢。当 `totalEffectiveAmount == 0` 时，LP 行动层激励为 `0`，不执行比例除法。`totalGovVotes == 0` 只在启用治理上限时使实际激励为 `0`；`govRatioMultiplier == 0` 时不读取治理票分母。

加入阶段内部分撤回按撤回前的累计状态同比减少数量与扣减值：

```text
removedDeduction = deduction × withdrawAmount / joinedAmount
joinedAmount -= withdrawAmount
deduction -= removedDeduction
```

这样撤回不会选择性移除早加入或晚加入批次，也不能提高剩余资产的时间权重。撤回量必须大于 `0` 且不超过 `joinedAmount`；全量撤回同时清除 ActionTarget 登记，部分撤回后余额大于 `0` 时保留登记。

### 5.3 LP 激励

当 Round 进入铸币阶段且满足 `canMint` 时，Executor 先经 ActionTarget 一次性铸造整个 Proposal 的 `proposalIncentive`，再按有效 LP 占比计算参与者理论激励：

```text
effectiveLpRatio = effectiveAmount × 1e18 / totalEffectiveAmount
theoreticalIncentive = proposalIncentive × effectiveLpRatio / 1e18
```

若 `govRatioMultiplier == 0`，实际激励等于理论激励；否则令：

```text
govRatio = validGovVotes(memberId) × 1e18 / totalGovVotes
govRatioCap = govRatio × govRatioMultiplier / 1e18
effectiveRatio = min(effectiveLpRatio, govRatioCap)
mintIncentive = proposalIncentive × effectiveRatio / 1e18
overflowIncentive = theoreticalIncentive - mintIncentive
```

`govRatioMultiplier` 使用 `1e18` 表示 1 倍；启用上限且 `totalGovVotes == 0` 时 `mintIncentive = 0`、`overflowIncentive = theoreticalIncentive`。

Executor 从已取得的 Proposal 激励余额向成员转账 `mintIncentive` 并销毁 `overflowIncentive`，成员结算不再逐人调用核心 Mint。治理占比在参与者结算时记录，随后查询返回冻结值；每个成员每轮只能结算一次。无人参与时整个 Proposal 激励由 Executor 销毁。LP Executor 的验证阶段为空操作。

## 6. 链群行动执行合约

### 6.1 行动和链群配置

每个链群行动 Proposal 绑定：`activationMinGovRatio`、`activationStakeAmount`、`joinTokenAddress`、`maxJoinAmountRatio`，以及链群说明、成员最小/最大参与量、链群容量和成员数量上限等行动规则。`actionTokenAddress` 直接使用 Proposal 创建回调的 `tokenAddress`，不得在业务 KV 中再传入一个可能不一致的副本。

链群以 MemberNFT 的 `groupId` 标识，链群 owner 是该 NFT 主体，不是钱包地址。owner 当前持有人可以按规则激活、更新或取消激活链群；激活时检查治理票占比并锁定激活质押。配置更新对新加入和后续状态生效，不追溯已记录参与者。取消激活后禁止新增或追加，未完成验证的链群不能提交验证，历史参与者仍可按行动规则结算；激活质押返还当前群 NFT 持有人。

单个成员的最大参与量按行动规则计算，常用形式为 `maxJoinAmount = mintedJoinTokenSupply × maxJoinAmountRatio / 1e18 × actionVotes / totalVotes`。当 `totalVotes == 0` 时，最大参与量为 `0`，不能激活或加入。

### 6.2 加入、退出和体验模式

仅当 Proposal 在对应 ActionRound 的同编号投票阶段获得投票时，才可在该 Round 的加入阶段加入。MemberNFT 首次加入必须达到链群设置的最小参与量，并同时满足成员上限、链群容量、成员数量和行动最大参与量；可以在加入阶段追加并更新验证信息。正常退出、部分撤回、全部资产返还和行动结束清理由链群 Executor 完成。

体验模式下，Provider MemberNFT 先把指定额度托管给链群 Executor，体验成员选择 Provider 使用该额度加入；体验成员不能追加体验额度。体验成员退出或 Provider 代为退出时，额度返还 Provider，体验成员获得的行动激励仍归体验成员。自有资产和体验资产互不影响。

链群 Executor 以当前有效的 `tokenAddress + actionId + groupId + memberId` 参与关系为事实来源；每个 `tokenAddress + actionId + memberId` 最多关联一个 `groupId`。同一关系首次建立时写入索引，追加和部分撤回不重复写入；只有通过 Executor 正常全部退出该行动时才删除该关系。MemberNFT 转移不改变关系。

Executor 必须维护下列 17 组跨其所有代币社区和链群行动的可枚举全局索引：

- Group ID：`gGroupIds`、`gGroupIdsByMemberId`、`gGroupIdsByTokenAddress`、`gGroupIdsByTokenAddressByMemberId`、`gGroupIdsByTokenAddressByActionId`；
- Token Address：`gTokenAddresses`、`gTokenAddressesByMemberId`、`gTokenAddressesByGroupId`、`gTokenAddressesByGroupIdByMemberId`；
- Action ID：`gActionIdsByTokenAddress`、`gActionIdsByTokenAddressByMemberId`、`gActionIdsByTokenAddressByGroupId`、`gActionIdsByTokenAddressByGroupIdByMemberId`；
- Member ID：`gMemberIds`、`gMemberIdsByGroupId`、`gMemberIdsByTokenAddress`、`gMemberIdsByTokenAddressByGroupId`。

每组索引都提供同名全量数组查询、追加 `Count` 的数量查询和追加 `AtIndex` 的单项查询；`AtIndex` 在原查询参数后追加 `index`。例如：

- `gTokenAddressesByGroupIdByMemberId(groupId, memberId) -> address[]`；
- `gTokenAddressesByGroupIdByMemberIdCount(groupId, memberId) -> uint256`；
- `gTokenAddressesByGroupIdByMemberIdAtIndex(groupId, memberId, index) -> address`；
- `gActionIdsByTokenAddressByGroupIdByMemberId(tokenAddress, groupId, memberId) -> uint256[]`，以及对应的 `Count` 和 `AtIndex`。

`Count + AtIndex` 就是客户端分页接口，不额外提供 `offset/limit` 查询；同一轮分页读取应固定在同一区块，索引顺序不作为业务语义。退出一个行动时，只有在较低维度已不存在其他有效参与关系后，才能逐层删除对应的 Member ID、Action ID、Token Address 或 Group ID 上层索引。例如，成员退出某链群的一个行动后，只要仍在任意代币社区的任意行动中参与该链群，`gTokenAddressesByGroupIdByMemberIdCount(groupId, memberId)` 就仍大于 `0`。

### 6.3 公共验证者申请

公共验证者是链群行动 Executor 内部的候选角色，不是群 owner。候选人必须是 `actionTokenAddress` 社区中拥有有效治理权的 MemberNFT，不需要额外凭证或押金。

候选申请只在投票阶段新增、撤销或修改：每次申请生成新的 `applicationId`，保存说明和分成比例 `r`（`0 <= r <= 1e18`）；撤销/修改把 MemberNFT 当前申请置为 `0`，从内部排名移除但保留旧申请和票数；新申请从零计票；投票阶段结束后本 Round 候选、排名和比例冻结，后续操作只影响下一 Round。

验证阶段分割线在 Executor 初始化时传入，数组必须严格递增且每项满足 `0 < split < 1e18`。有 `n` 个分割线时，排名前 `n + 1` 名可验证；第 1 名在验证阶段开始即可提交。排名按累计候选票降序、`applicationId` 升序。

对排名为 `rank >= 2` 的候选人，`splits[rank - 2]` 是其开放比例。开放区块按本轮验证阶段对应的 Phase 记录计算：

```text
openOffset = ceil(verifyPhaseBlocks × splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

当 `block.number >= openBlock` 时该排名开放。`splits = []` 时只有第 1 名可验证；向上取整避免整数截断导致候选人在分割线之前提前开放。

链群行动投票 KV 使用 `key = keccak256("verifierCandidateId")`，`value = abi.encode(uint256 verifierCandidateId)`；该 ID 是候选人的 MemberNFT ID，不是 `applicationId`。

完整候选申请列表用于前端分页查询；合约内部只维护前 `n + 1` 名和 `applicationId -> rankIndex`。投票只对收到新增票的候选增量更新：榜内候选向前交换，榜外候选只和末位比较，不扫描完整列表、不自动补位；榜满时平票不替换末位。`verifierCandidateId` 由投票 KV 传入，其值是候选人的 MemberNFT ID；标准回调提供投票人的 `voterId` 和本次治理票增量。Executor 根据 `verifierCandidateId` 查找当前申请，当前申请为 `0` 时拒绝；本次全部治理票增量记给该申请。治理者同一 Round 可多次投票，但投给所有候选申请的累计候选票不得超过其对该行动的累计治理票。

### 6.4 按 Round 参与历史和批量验证

链群 Executor 通过加入阶段内逐笔发生的加入、追加、体验加入、部分撤回和全部退出交易，自然形成每轮参与快照。每笔交易都以 `currentRoundJoin()` 为键更新该行动的 Round 历史。历史至少包含：本 Round 有参与成员的 `groupId` 集合、各链群的 `memberId` 集合及顺序、各成员的链群归属和参与量、各链群参与总量及行动参与总量。

同一 Round 内的多笔交易持续更新该 Round 的最终值，不为同一 Round 重复创建版本。首次成员加入时把链群加入本 Round 的链群集合；最后一名成员全部退出时移除该链群；追加和仍有余额的部分撤回不重复增删成员或链群。查询某一 Round 时，已有该 Round 记录就直接读取；没有记录则读取不晚于该 Round 的最近一次历史值，没有任何更早记录时返回空集合或 `0`。因此整轮无人交互时自然继承上一轮状态，不需要复制或同步交易。

加入阶段结束后，任何参与变更只能写入后续 Round，目标 Round 的最终历史状态就是验证依据。验证阶段按同一 Round 直接读取链群集合、成员顺序和参与量，无需其他状态准备交易；空链群不在集合内，后续链群停用、恢复、新增或成员变更均不得回写该 Round。实现按 Round 记录集合数量、索引项和成员反向索引，使加入和退出交易直接形成可查询的历史。

公共验证者可以分批提交验证。每个链群按目标 Round 历史中的成员顺序保存验证游标；调用必须满足 `startIndex == verifiedCount`，批次连续，不得重复、跳过或乱序，且只能验证目标 Round 链群集合中的成员。本 Round 本行动的首个有效验证批次永久锁定一个公共验证者 `memberId`，该验证者负责完成目标 Round 历史集合内全部链群的验证；后续批次只能由该 MemberNFT 当前持有人提交，不设置失效、接管或代理。NFT 转移后由新持有人继续完成本 Round。

公共验证者对每个成员提交原始得分 `0..100`，成员最终得分为 `rawScore × joinedAmount`；链群总分为成员最终得分之和，行动总分为所有完成验证链群总分之和。必须完成目标 Round 历史集合内的全部链群才算完整。

无有效候选、候选总票为零、锁定的公共验证者未完成目标 Round 的全部链群或任一链群验证不完整时，本 Round 的链群行动者、公共验证者、链群 owner 和链群服务行动层激励全部为零。没有任何成员参与的行动无法提交验证，该行动的公共验证者和链群 owner 也没有激励；该行动的 Proposal 激励仍可由 Executor 铸造后立即销毁，不能进行行动层分配。治理监督通过下一 Round 是否继续投票完成，不回溯历史激励。

### 6.5 链群行动激励

链群行动 Proposal 的行动激励由关联 Executor 一次性通过 ActionTarget 铸造。完整验证时按得分分配：

```text
groupIncentive = proposalIncentive × groupScore / totalGroupScore
memberIncentive = groupIncentive × memberScore / groupScore
```

Executor 可在内部把行动激励分配给参与者；ActionTarget 不留余额。参与历史、Verify 结果和激励状态按 `tokenAddress + actionId + round` 隔离。完整验证但 `totalGroupScore == 0` 时，行动层激励为 `0`；单个 `groupScore == 0` 时，该链群激励为 `0`，均不执行比例除法。底层 Proposal 激励仍可按核心规则铸造，Executor 可以按规则销毁。

链群行动 Executor 至少提供 `generatedActionIncentive(round)`、`generatedActionIncentiveByGroupId(round, groupId)` 和 `generatedActionIncentiveByOwner(round, ownerId)`。链群 owner 就是链群 `MemberNFT` 本身，因此 `ownerId == groupId`，后两个查询在当前模型中返回同一主体产生的行动激励；保留 `ByOwner` 命名是为了明确它在链群服务分配中的角色语义。链群服务只读取最终冻结值。

## 7. 链群服务行动执行合约

### 7.1 服务范围和初始化

一个链群服务 Proposal 面向整个 `actionTokenAddress` 社区的链群行动集合，不绑定单个源 `actionId`。该 Proposal 的 `tokenAddress` 记为 `serviceTokenAddress`，同时是服务 Proposal 所属治理社区和服务激励的铸币代币；服务 Proposal 可铸造的总激励只由 `serviceTokenAddress` 社区的治理轮次决定，与被服务的 `actionTokenAddress` 社区治理无关。两者必须满足 `serviceTokenAddress == actionTokenAddress`，或 `serviceTokenAddress` 是 `actionTokenAddress` 的直接父币；不允许跨多级父子关系。`actionTokenAddress` 只用于筛选被服务行动和读取行动层状态，该关系由服务 Executor 在创建回调中校验。

服务执行合约部署时在构造函数传入可复用的链群行动执行合约 `actionExecutor`，该地址必须是非零合约地址。服务创建 KV 除第 `0` 项 `executor` 外，包含 `actionTokenAddress` 和 `govRatioMultiplier`；不再在每个 Proposal 的 KV 中传入 `actionExecutor`。链群行动的验证分割线、链群 owner 接收主体和每个行动/链群的分配比例属于对应业务状态，不是服务全局初始化参数。

### 7.2 服务加入

服务加入主体是 MemberNFT，满足以下任一条件即可加入：是 `actionTokenAddress` 社区中有效链群的 owner，或在相关链群行动中存在有效公共验证者申请。加入发生在对应 ActionRound 的加入阶段，且服务 Proposal 必须在同编号投票阶段获得投票。加入不要求该 Round 已选出公共验证者，也不承诺一定产生服务激励；服务加入量按整个社区聚合。

服务激励按人结算，但 MemberNFT 只有在该服务 Proposal 的对应 ActionRound 已完成加入，才可以结算自己的公共验证者和/或链群 owner 激励。未加入者即使具有角色也不能结算，其理论份额不重新分配；该份额与舍入余数留在服务 Executor，不建立余数账本，也不参与之后的成员分配。

### 7.3 服务激励聚合

服务 Executor 在铸币阶段通过 ActionTarget 一次性取得 `servicePool`，来源是 `serviceTokenAddress` 社区对应服务 Proposal 的冻结 Proposal 激励；之后按 MemberNFT 分人结算，不把底层 Proposal 激励拆成多个独立铸造请求。随后逐个检查 `actionTokenAddress` 社区的链群行动：

1. 通过 ActionTarget 使用 `actionExecutor` 查询 `actionTokenAddress` 社区关联的全部 Proposal；
2. 对每个 Proposal 确认本轮至少有一个成员参与、目标 Round 历史集合内的全部链群均已完成验证、行动激励已经最终确定，并确认实际锁定的公共验证者及其申请分成比例。任一条件不满足时，该行动的行动激励权重为 `0`，不进入服务激励分母；该行动的 Proposal 激励只能由 Executor 销毁；
3. 设符合条件的行动 `a` 的行动激励权重为 `A[a]`，全部符合条件行动的权重为 `T = Σ A[a]`。`A[a]` 使用行动 Executor 记录的最终行动激励，不使用尚未确定的 Proposal 预估值；
4. 当 `T > 0` 时，对每个行动只读取一次实际锁定的公共验证者 `verifierId[a]`、其申请分成比例 `r[a]`，以及每个 MemberNFT 在该行动名下链群产生的行动激励 `ownerActionIncentive(a, m)`，并累计两类权重：

   ```text
   verifierWeightNumerator(m) = Σ(A[a] × r[a])
       // 仅对 verifierId[a] == m 的行动累加

   ownerWeightNumerator(m) = Σ(ownerActionIncentive(a, m) × (1e18 - r[a]))

   theoreticalVerifierIncentive(m) =
       servicePool × verifierWeightNumerator(m) / (T × 1e18)

   theoreticalOwnerIncentive(m) =
       servicePool × ownerWeightNumerator(m) / (T × 1e18)
   ```

   `ownerActionIncentive(a, m)` 由行动 Executor 返回，表示作为 `groupId` 的 MemberNFT `m` 在行动 `a` 中产生的行动激励。每个行动的公共验证者分成先按该行动的实际比例折算为公共验证者权重，链群 owner 权重使用同一行动的剩余比例；所有行动的权重分别累加后再计算分子/分母，不建立跨行动的全局 ownerPool。全局服务激励计算直接向下取整，不维护、不补发舍入余数；未分配的最小单位留在服务 Executor 中。
5. 对同一 MemberNFT，将两类理论激励合并后只进行一次治理占比封顶：

   ```text
   theoreticalIncentive(m) =
       theoreticalVerifierIncentive(m) + theoreticalOwnerIncentive(m)
   ```

   ```text
   govRatio(m) = validGovVotes(actionTokenAddress, m) × 1e18
                 / totalGovVotes(actionTokenAddress)

   capRatio(m) = govRatio(m) × govRatioMultiplier / 1e18

   actualIncentive(m) = min(
       theoreticalIncentive(m),
       servicePool × capRatio(m) / 1e18
   )
   ```

   `govRatioMultiplier == 0` 表示不封顶，此时不读取 `totalGovVotes`；否则 `totalGovVotes == 0` 时 `govRatio` 按 `0` 处理。将 `theoreticalIncentive(m) - actualIncentive(m)` 销毁。实际激励按以下同一缩放比例拆回公共验证者和链群 owner 两部分，避免两次独立取整后超过实际预算：

   ```text
   actualVerifierIncentive = actualIncentive × theoreticalVerifierIncentive
                             / theoreticalIncentive
   actualOwnerIncentive = actualIncentive - actualVerifierIncentive
   ```

   公共验证者部分直接给实际锁定的验证者；链群 owner 部分按该 `groupId` 在各行动中的激励权重拆分，并按链群配置的接收主体和比例执行二次分配。`theoreticalIncentive(m) == 0` 时两类实际激励均为 `0`，不进行缩放除法。

公共验证者激励来自链群服务 Proposal，不从链群行动 Proposal 扣除。服务激励不存在 gas 补偿。

设成员 `m` 在所有符合条件行动中累计得到的公共验证者理论激励为 `verifierTheory(m)`，链群 owner 理论激励为 `ownerTheory(m)`：

```text
theoreticalIncentive(m) = verifierTheory(m) + ownerTheory(m)
```

同一 MemberNFT 同时是公共验证者和链群 owner 时，两部分合并后只封顶一次；只有链群 owner 时只计算链群 owner 激励，只有公共验证者时只计算公共验证者激励。该治理票占比在每个已加入 `memberId` 首次结算本服务 Proposal 的该 Round 时冻结；每个 `memberId` 在该服务 Proposal 的该 Round 只能结算一次，且只能由该 MemberNFT 当前持有人触发。

`A[a]` 只有该行动完成全部验证且行动激励最终确定时才进入 `T`。若 `T == 0`，所有行动层服务激励均为 `0`；已经铸造的 `servicePool` 必须整体销毁，不能分配给其他行动或 MemberNFT。公共验证者分成只由该行动实际锁定的候选申请比例决定。

### 7.4 二次分配和舍入

所有比例使用 `1e18`。链群 owner 当前持有人可以按 `serviceProposalId + actionId + groupId + round` 配置二次分配的 `recipientIds[]` 和 `ratios[]`；接收主体必须是已存在的 MemberNFT，结算时转给其当前持有人。数组长度必须相等且不超过部署时固定的 `maxRecipients`，每个比例大于 `0`，比例总和不得超过 `1e18`，允许正好为 `1e18`。

全局服务激励和各角色激励均直接向下取整，不维护、不补发舍入余数，未分配的最小单位留在服务 Executor 中。链群 owner 二次分配的各接收金额向下取整，`groupBudget - distributed` 的余数归该链群 owner；比例为 100% 时 owner 金额可以为零。

预算分配使用同一组分子/分母计算；任何中间结果不得因独立向下取整导致累计份额超过服务 Proposal 实际铸造量。若出现 `distributed > budget`，属于非法超额分配，必须回滚；不能用静默截断掩盖错误。铸造、销毁、转账和状态更新必须在同一笔交易中完成。

## 8. 铸造闭环、事件和错误

行动激励闭环固定为 `executor -> ActionTarget -> Mint -> ActionTarget -> executor`。Executor 一次铸造一个 Proposal 在该 Round 的全部行动激励，再在内部完成参与者、公共验证者和 owner 分配。只有关联 Executor 可以发起；任何失败都回滚，ActionTarget 不保留余额。

实现至少发出 Proposal 关联、行动参与/撤回/退出、公共验证者申请和排名、验证批次/锁定/完成、行动激励铸造/销毁、服务分配和 `forceExit` 事件。Round 快照由参与状态变更事件及对应历史状态共同证明。

至少拒绝：零地址或 EOA Executor、非 ActionTarget 回调、重复初始化、KV 长度不等、无效 Round、非 MemberNFT 控制者、未投票 Proposal、非法参与量、体验额度不足、非法候选或分割线、候选申请已失效、验证批次跳跃/重复、锁定后更换验证者、重复铸造，以及服务非法超额分配导致的下溢。

## 9. 验收场景

至少覆盖：三类 Proposal 回调和原子回滚；ActionTarget 映射、查询和 forceExit；四阶段 ActionRound；LP 时间加权、治理票上限和部分撤回；链群激活、配置更新、成员/体验参与、17 组链群全局索引的全量/Count/AtIndex 一致性、跨社区和跨行动关系、逐层清理、最后一次正常退出和 forceExit 状态边界、候选申请版本切换、排名平票、前 `n + 1` 开放、逐笔交易形成 Round 历史、同轮多次变更、空轮继承、验证批次连续性、NFT 转移续验、无候选/失联导致行动层激励为零；完整验证后的成员和链群激励；服务跨整个社区聚合、同币/父币服务、公共验证者比例、100% 二次分配和全精度舍入边界。
