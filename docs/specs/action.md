# LOVE20BSC Action 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义社群行动 Proposal 类型，说明行动如何被创建、投票、加入、验证、结算和铸造激励，以及 LP 行动、链群行动和链群服务行动之间的边界。

## 1. 组件和依赖

`action` 由以下组件组成：

- `ActionTarget`：所有社群行动 Proposal 的统一 Target；
- LP 行动执行合约；
- 链群行动执行合约；
- 链群服务行动执行合约。

组件依赖 `core` 的 `MemberNFT`、`Stake`、`Submit`、`Vote`、`Mint` 和 `LOVE20Phase` 接口。核心只传递 Proposal 上下文、治理票增量和不透明 KV；候选人、链群、LP、资产托管和服务分配由本代码库解释。

执行合约可以同时服务多个代币社区和多个 Proposal。所有可复用状态至少按 `tokenAddress + actionId + ActionRound` 隔离。

## 2. ActionTarget

### 2.1 Proposal 关联

行动类 Proposal 必须使用 `target = ActionTarget` 和 `targetMode = Callback`。Proposal 创建 KV 的第 `0` 项是保留项：`key = keccak256("executor")`，`value = abi.encode(executorAddress)`。

`executorAddress` 必须是非零且包含合约代码的地址。第 `0` 项之外的 KV 可以为空，业务字段和校验完全由 Executor 负责。

ActionTarget 以 `tokenAddress + proposalId` 为唯一键保存 Executor，把完整创建 KV 原样转发给 Executor，不删除保留项、不重新分配数组。Executor 的 Proposal 创建回调就是该 Proposal 的初始化，重复初始化必须回滚；只有 ActionTarget 可以调用 Executor 的三个回调。

核心回调名称及标准参数为 `onProposalCreated(tokenAddress, proposalId, keys, values)`、`onProposalSubmitted(tokenAddress, proposalId, submitterId, keys, values)` 和 `onProposalVoted(tokenAddress, proposalId, voterId, votes, keys, values)`。

ActionTarget 不解析 `verificationRule`、`verificationKeys`、候选人 Member ID 或其他业务字段。推举回调使用 `submitterId`；投票回调的 `votes` 只表示本次新增治理票，候选 Member ID 等信息放在投票 KV 中。

### 2.2 参与登记

ActionTarget 维护通用的“MemberNFT 是否参与某个行动”登记，并向 Executor 提供查询。它不接收或持有行动资产，不实现加入、退出、验证、结算和行动层分配。

正常流程由 Executor 完成：加入、追加、部分撤回、全部退出、资产返还、行动结束结算和登记清理。Executor 失效时，当前 MemberNFT 持有人可以调用 `forceExit(tokenAddress, actionId, memberId)` 清理通用登记并触发事件。该入口不调用 Executor、不承诺资产返还，前端默认隐藏，只作为最后兜底。

### 2.3 查询

ActionTarget 提供两类按治理 Round 的只读查询：

1. 传入 `executor`，返回该 Executor 关联的 `proposalId[]`；
2. 不传入 `executor`，返回本轮所有有投票且已关联 Executor 的 `(proposalId, executor)`。

两类查询先从 `Vote` 读取本轮有投票的 Proposal，再按 Proposal ID 读取 ActionTarget 映射并筛选，不维护独立反向索引。第一类返回值不重复返回 Executor；第二类用于前端行动列表。首版单轮一次性返回完整只读结果，写入操作必须使用有界批次。

## 3. ActionRound

行动时间线把 `LOVE20Phase` 的无语义 Phase 组合为从 `1` 开始的 ActionRound，并固定四个时间槽位：`Vote -> Join -> Verify -> Mint`。

四个槽位同时属于不同的滚动 Round，不表示串行交易顺序。`Join` 表示加入、追加、退出和其他行动参与状态变化。

LP、链群行动和链群服务行动共用四个槽位和同一 Mint 时间窗口：LP 和链群服务的 Verify 槽位为空操作，链群行动在 Verify 槽位执行公共验证。每个 Executor 自己实现 `canMint(actionId, round)`；统一时间槽位不等于统一铸造资格。

ActionTarget 提供无参数只读接口 `currentVoteRound()`、`currentJoinRound()`、`currentVerifyRound()` 和 `currentMintRound()`，直接从 `LOVE20Phase` 推导，不保存 ActionRound 历史，也不提供带通用阶段参数的 `currentRound`、`ActionRoundInfo` 或 `ActionRoundOf`。

## 4. 共同参与模型

- 行动参与主体统一为 MemberNFT 的 `memberId`；钱包地址只作为当前控制者。
- 可复用行动状态至少按 `tokenAddress + actionId + round` 隔离；跨社区或跨行动读取必须拒绝。
- 体验资产按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账，归 Provider MemberNFT 所有，退出时返还对应 Provider。
- 自有资产和体验资产可以同时存在；部分撤回只减少指定账本，不互相抵扣。
- 行动快照前撤回会减少当轮参与权、验证权重和可得激励；快照后撤回不回写当轮验证集合、验证结果或激励，只影响后续 Round；余额归零后才清除通用登记。
- MemberNFT 转移不改变已发生的快照、投票、验证或已结算状态，新持有人继续操作当前未铸造权益。

## 5. LP 行动执行合约

### 5.1 初始化

LP Executor 至少配置参与 LP Token 地址、`govRatioMultiplier`、`minGovRatio`，以及从 Proposal `details` 读取的行动说明和 `verificationRule`。LP Token 必须来自配置的 PancakeSwap Factory，且实现 Uniswap V2 Pair 的份额和储备接口。

### 5.2 加入和时间权重

只有本轮已获得治理投票的 Proposal 可以加入。首次加入的 MemberNFT 必须满足当前有效治理票占社区总治理票的 `minGovRatio`；后续加入按行动规则允许追加。每次加入记录区块和数量，用于时间加权：`deduction = amount × (currentBlock - joinRoundStartBlock) / phaseBlocks`，`effectiveAmount = joinedAmount - deduction`。

行动 Round 的总有效数量为所有参与者 `effectiveAmount` 之和。加入、追加、验证信息更新和部分撤回由 LP Executor 自己执行；退出返还该 Executor 记录的资产。

### 5.3 LP 激励

当 Round 进入 Mint 槽位且满足 `canMint` 时，Executor 按有效 LP 占比计算参与者理论激励：`effectiveLpRatio = effectiveAmount / totalEffectiveAmount`，`theoretical = actionReward × effectiveLpRatio`。

若 `govRatioMultiplier == 0`，实际激励等于理论激励；否则令 `govRatio = validGovVotes(memberId) × 1e18 / totalGovVotes`，`govRatioCap = govRatio × govRatioMultiplier / 1e18`，`effectiveRatio = min(effectiveLpRatio, govRatioCap)`，`mint = actionReward × effectiveRatio`，`overflow = theoretical - mint`。`govRatioMultiplier` 使用 `1e18` 表示 1 倍。

`mint` 由 Executor 通过 `ActionTarget -> Mint` 铸造，`overflow` 销毁。治理占比在参与者结算时记录，随后查询返回冻结值。LP Executor 的 Verify 槽位为空操作。

## 6. 链群行动执行合约

### 6.1 行动和链群配置

每个链群行动 Proposal 绑定：`actionTokenAddress`、`activationMinGovRatio`、`activationStakeAmount`、`joinTokenAddress`、`maxJoinAmountRatio`，以及链群说明、成员最小/最大参与量、链群容量和成员数量上限等行动规则。

链群以 MemberNFT 的 `groupId` 标识，链群 owner 是该 NFT 主体，不是钱包地址。owner 当前持有人可以按规则激活、更新或取消激活链群；激活时检查治理票占比并锁定激活质押。配置更新对新加入和后续状态生效，不追溯已记录参与者。取消激活后禁止新增或追加，未完成验证的链群不能提交验证，历史参与者仍可按行动规则结算；激活质押返还当前群 NFT 持有人。

单个成员的最大参与量按行动规则计算，常用形式为 `maxJoinAmount = mintedJoinTokenSupply × maxJoinAmountRatio / 1e18 × actionVotes / totalVotes`。

### 6.2 加入、退出和体验模式

仅当 Proposal 在当前治理 Round 获得投票时可加入。MemberNFT 首次加入必须达到链群设置的最小参与量，并同时满足成员上限、链群容量、成员数量和行动最大参与量；可以在 Join 槽位追加并更新验证信息。正常退出、部分撤回、全部资产返还和行动结束清理由链群 Executor 完成。

体验模式下，Provider MemberNFT 先把指定额度托管给链群 Executor，体验成员选择 Provider 使用该额度加入；体验成员不能追加体验额度。体验成员退出或 Provider 代为退出时，额度返还 Provider，体验成员获得的行动激励仍归体验成员。自有资产和体验资产互不影响。

### 6.3 公共验证者申请

公共验证者是链群行动 Executor 内部的候选角色，不是群 owner。候选人必须是 `actionTokenAddress` 社区中拥有有效治理权的 MemberNFT，不需要额外凭证或押金。

候选申请只在 Vote 槽位新增、撤销或修改：每次申请生成新的 `applicationId`，保存说明和分成比例 `r`（`0 <= r <= 1e18`）；撤销/修改把 MemberNFT 当前申请置为 `0`，从内部排名移除但保留旧申请和票数；新申请从零计票；Vote 槽位结束后本 Round 候选、排名和比例冻结，后续操作只影响下一 Round。

验证阶段分割线在 Executor 初始化时传入，数组必须严格递增且每项满足 `0 < split < 1e18`。有 `n` 个分割线时，排名前 `n + 1` 名可验证；第 1 名在 Verify 槽位开始即可提交。排名按累计候选票降序、`applicationId` 升序。

完整候选申请列表用于前端分页查询；合约内部只维护前 `n + 1` 名和 `applicationId -> rankIndex`。投票只对收到新增票的候选增量更新：榜内候选向前交换，榜外候选只和末位比较，不扫描完整列表、不自动补位；榜满时平票不替换末位。候选 Member ID 由投票 KV 传入，标准回调提供投票人的 `voterId` 和本次治理票增量。Executor 根据候选 Member ID 查找当前申请，当前申请为 `0` 时拒绝；本次全部治理票增量记给该申请。治理者同一 Round 可多次投票，但投给所有候选申请的累计候选票不得超过其对该行动的累计治理票。

### 6.4 快照和批量验证

Join 槽位结束时，Executor 快照所有至少有一个成员参与的链群 `groupId`；空链群不进入集合。之后群停用、恢复或新增不改变本 Round 集合。

每个链群按快照中的成员顺序保存验证游标。验证调用必须满足 `startIndex == verifiedCount`，批次连续，不得重复、跳过或乱序。首个有效批次永久锁定公共验证者 `memberId`；后续批次只能由该 MemberNFT 当前持有人提交，不设置失效、接管或代理。NFT 转移后由新持有人继续完成本 Round。

公共验证者对每个成员提交原始得分 `0..100`，成员最终得分为 `rawScore × joinedAmount`；链群总分为成员最终得分之和，行动总分为所有完成验证链群总分之和。必须完成全部快照链群验证才算完整。

无有效候选、候选总票为零、首个验证批次未能完成或任一链群验证不完整时，本 Round 的链群行动者、公共验证者、链群 owner 和链群服务行动层激励全部为零。底层 Proposal 激励仍可铸造，Executor 可以按规则销毁，但不能进行行动层分配。治理监督通过下一 Round 是否继续投票完成，不回溯历史激励。

### 6.5 链群行动激励

链群行动 Proposal 的行动激励由关联 Executor 一次性通过 ActionTarget 铸造。完整验证时按得分分配：`groupReward = actionReward × groupScore / totalGroupScore`，`memberReward = groupReward × memberScore / groupScore`。

Executor 可在内部把行动激励分配给参与者；ActionTarget 不留余额。Verify 结果、快照和激励状态按 `tokenAddress + actionId + round` 冻结。

## 7. 链群服务行动执行合约

### 7.1 服务范围和初始化

一个链群服务 Proposal 面向整个 `actionTokenAddress` 社区的链群行动集合，不绑定单个源 `actionId`。Proposal 的激励代币为 `rewardTokenAddress`，可以与行动代币相同，也可以使用父币激励子币社区；父子关系由服务 Executor 校验。

服务创建 KV 除第 `0` 项 `executor` 外，包含 `actionTokenAddress` 和 `govRatioMultiplier`。链群行动的验证分割线、链群 owner 接收主体和每个行动/链群的分配比例属于对应业务状态，不是服务全局初始化参数。

### 7.2 服务加入

服务加入主体是 MemberNFT，满足以下任一条件即可加入：是 `actionTokenAddress` 社区中有效链群的 owner，或在相关链群行动中存在有效公共验证者申请。加入不要求该 Round 已选出公共验证者，也不承诺一定产生服务激励。服务加入量按整个社区聚合。

### 7.3 服务激励聚合

服务 Executor 在 Mint 槽位：

1. 通过 ActionTarget 查询本服务 Executor 在 `actionTokenAddress` 社区关联的全部 Proposal；
2. 按核心治理门槛筛出有资格铸造行动激励的 Proposal；
3. 过滤无公共验证者或未完成全部链群快照验证的行动；
4. 按完整行动的行动激励权重分摊服务 Proposal 的实际铸造预算；
5. 对每个行动按公共验证者申请时冻结的比例 `r` 分配验证者份额，余款进入链群 owner 分配；
6. 按链群配置的接收主体和比例执行二次分配。

公共验证者激励来自链群服务 Proposal，不从链群行动 Proposal 扣除。服务激励不存在 gas 补偿。

服务参与者的理论激励按其服务的完整行动/链群行动激励占完整行动总激励的比例计算：`theoretical = servicePool × generatedActionRewardByOwner(memberId) / totalCompleteActionReward`。治理占比为 `govRatio = validGovVotes(memberId) × 1e18 / govVotesNum(actionTokenAddress)`；当 `govRatioMultiplier == 0` 时 `effectiveRatio = 1e18`，否则 `effectiveRatio = min(1e18, govRatio × govRatioMultiplier / 1e18)`；实际铸造为 `mint = theoretical × effectiveRatio`，溢出为 `overflow = theoretical - mint`，并销毁溢出。`govRatioMultiplier` 使用 `1e18` 表示 1 倍。

`generatedActionRewardByOwner` 表示链群 owner 作为服务主体产生的未封顶服务份额；公共验证者的 `r` 份额按行动预算单独计算。治理票占比在服务激励铸造时冻结。

### 7.4 二次分配和舍入

所有比例使用 `1e18`。每个链群的接收比例总和不得超过 `1e18`，允许正好为 `1e18`。各接收金额向下取整，累计分配不能超过该链群预算，舍入余数归链群 owner；比例为 100% 时 owner 金额可以为零。

预算分配使用未提前截断的同一组分子/分母进行全精度计算；任何中间结果不得因独立向下取整导致累计份额超过服务 Proposal 实际铸造量。铸造、销毁、转账和状态更新必须在同一笔交易中完成，不能因 `budget - distributed` 下溢而回滚。

## 8. 铸造闭环、事件和错误

行动激励闭环固定为 `executor -> ActionTarget -> Mint -> ActionTarget -> executor`。Executor 一次铸造一个 Proposal 在该 Round 的全部行动激励，再在内部完成参与者、公共验证者和 owner 分配。只有关联 Executor 可以发起；任何失败都回滚，ActionTarget 不保留余额。

实现至少发出 Proposal 关联、行动参与/撤回/退出、公共验证者申请和排名、验证快照/批次/锁定/完成、行动激励铸造/销毁、服务分配和 `forceExit` 事件。

至少拒绝：零地址或 EOA Executor、非 ActionTarget 回调、重复初始化、KV 长度不等、无效 Round、非 MemberNFT 控制者、未投票 Proposal、非法参与量、体验额度不足、非法候选或分割线、候选申请已失效、验证批次跳跃/重复、锁定后更换验证者、重复铸造、服务超额分配和下溢。

## 9. 验收场景

至少覆盖：三类 Proposal 回调和原子回滚；ActionTarget 映射、查询和 forceExit；四槽位 ActionRound；LP 时间加权、治理票上限和部分撤回；链群激活、配置更新、成员/体验参与、候选申请版本切换、排名平票、前 `n + 1` 开放、快照批次连续性、NFT 转移续验、无候选/失联导致行动层激励为零；完整验证后的成员和链群激励；服务跨整个社区聚合、同币/父币服务、公共验证者比例、100% 二次分配和全精度舍入边界。
