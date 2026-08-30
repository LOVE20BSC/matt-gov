# LOVE20BSC Action 规格

状态：BSC 版实现前冻结的独立规格。

本文档描述 Proposal 扩展层的社群行动类型。它不要求读者先阅读旧扩展仓库；旧 `extension-lp` 只作为 V2 LP 行动的迁移来源。

## 1. 范围与非目标

本代码库包含：

- `ActionTarget`：社群行动 Proposal 的统一 Target；
- LP 行动执行合约（仅旧 `extension-lp` V2 业务的 BSC 重写）；
- 链群行动执行合约；
- 链群服务行动执行合约。

不包含：

- `Stake`、`Submit`、`Vote`、`Mint`、`MemberNFT` 和 `LOVE20Phase` 的实现；
- 核心 `LOVE20Verify`、随机抽取、代理验证者和不信任投票；
- 独立的 `ExtensionCenter`、按行动部署的工厂或每个行动单独创建执行合约；
- 群聊和 **Group Chat Delegate**；
- 公平发射后复杂分配机制（`launch` 本阶段不创建）。

## 2. 依赖与公共边界

`action` 依赖 `core` 的 `MemberNFT`、`Submit`、`Vote`、`Mint`、`Stake` 和 `LOVE20Phase` 接口。核心只知道 Proposal Target 的通用回调和铸造边界，不知道候选人、链群、LP 或服务分配业务。

执行合约可以复用于多个代币社区和多个 Proposal；状态必须带 `tokenAddress + actionId + ActionRound` 作用域。本代码库不通过工厂为每个行动部署实例。

## 3. ActionTarget

### 3.1 创建与回调

行动类 Proposal 的 Proposal Target 固定为 `ActionTarget`，`targetMode` 固定为 `Callback`。创建 KV 的第 `0` 项必须是 `key = keccak256("executor")`、`value = abi.encode(executorAddress)`。

`executorAddress` 必须是非零且有合约代码的地址。仅有这一项也允许创建，其他初始化校验交给执行合约。

`ActionTarget` 以 `tokenAddress + proposalId` 为唯一键保存 Executor，并把完整 KV 原样转发，不重新分配或删除第 `0` 项。三类回调名称为 `onProposalCreated`、`onProposalSubmitted`、`onProposalVoted`。

执行合约的对应回调只能由 `ActionTarget` 调用；Proposal 创建回调就是执行合约的初始化，理论上不可重复，重复创建回调必须回滚。推举回调传递 `submitterId`，投票回调传递 `voterId` 和本次增量 `votes`；候选 Member ID 等行动专属字段放在 KV 中。

### 3.2 参与登记与兜底退出

`ActionTarget` 合并原 ExtensionCenter 的通用登记职责，但不托管资产、不决定行动合法性、不实现具体加入/退出/验证/分配逻辑。正常加入、部分撤回、全部退出、资产返还和行动结束结算由对应 Executor 完成。

首版部署 `forceExit(tokenAddress, actionId, memberId)`。该入口仅允许当前 `MemberNFT` 持有人调用，只清理通用参与登记并发出事件，不调用失效 Executor，也不承诺返还资产；前端首版隐藏，只有执行合约失效时才作为最后兜底。正常流程不得依赖它。

### 3.3 查询与轮次

`ActionTarget` 提供两类查询：

- 指定 `executor + 治理轮次`，返回该 Executor 关联的 `proposalId[]`；
- 不指定 Executor，返回本轮所有有投票且已关联 Executor 的 `(proposalId, executor)`，供前端行动列表。

两类查询都先读取 `Vote` 本轮实际有投票的 Proposal，再逐个读取本地映射并筛选；不维护独立反向索引，不把 Executor 重复放进第一类返回值。首版按单轮一次性返回完整只读结果，不为查询额外设计分页；写入路径仍必须有批量边界。

统一轮次槽位为 `Vote -> Join -> Verify -> Mint`，ActionRound 从 `1` 开始。`Join` 表示加入、退出和行动参与状态变化。三类 Executor 共用这些槽位和同一 `Mint` 时间窗口；链群行动执行实际验证，链群服务和 LP 的 `Verify` 为空操作。是否可以铸造仍由各 Executor 的 `canMint` 自行判断。

`ActionTarget` 提供无参数只读接口 `currentVoteRound()`、`currentJoinRound()`、`currentVerifyRound()` 和 `currentMintRound()`。它们直接通过 `LOVE20Phase` 推导，不存储 ActionRound 历史；不增加 `ActionRoundInfo`、`ActionRoundOf` 或带通用阶段参数的 `currentRound`。

## 4. 共同的资产与撤回规则

- ActionTarget 不持有行动资产；资产托管、验证快照和行动内分配由 Executor 自己处理。
- 体验资产按 `tokenAddress + memberId + actionId + provider` 独立记账，归 Provider 所有，退出返还对应 Provider；自有资产和体验资产可同时存在，部分撤回只减少指定账本。
- 行动自身快照前撤回会减少当轮参与权、验证权重和可得激励；快照后撤回不回写当轮验证集合、结果或激励，只影响后续轮次；余额归零才清除登记。
- NFT 转移不改变历史快照和已结算状态，新持有人继续操作当前未铸造权益。

## 5. LP 行动执行合约

LP Executor 是旧 `extension-lp` V2 业务的重写版本；旧 V1 和旧 LP 工厂不迁移。它使用 MemberNFT 作为参与主体，允许按行动规则部分撤回和正常退出，参与资产及返还由该 Executor 管理。

LP Executor 保留统一 `Vote`、`Join`、`Verify`、`Mint` 槽位，但 `Verify` 不执行公共验证业务。它在 `Mint` 槽位按自己的参与快照、LP 份额和 `canMint` 条件，通过 `ActionTarget -> Mint` 铸造行动 Proposal 激励；不得直接调用核心 Mint。LP 手续费结算依赖 `core.Stake` 的社区结算和销毁统计，不能自行复制第二套手续费账本。

## 6. 链群行动执行合约

### 6.1 公共验证者候选

- 候选人必须是目标代币社区拥有有效治理权的 MemberNFT，不要求 SL/ST 或额外押金；
- 只在投票阶段新增、撤销或修改申请，每次申请有新的 `applicationId`；
- 撤销/修改把该 MemberNFT 当前关联申请置为 `0`，从内部排名移除但不扫描完整列表、不清理旧票数、不自动补位；重新申请创建新 ID，从零计票；
- 申请说明、`verificationKeys`、`verificationKeyGuides` 和分成比例由链群行动 Executor 保存解释，比例使用 `1e18` 精度；投票阶段结束后本轮候选、排名和比例冻结，之后只影响下一轮。

验证阶段分割线在初始化时传入，必须严格递增，且每项 `0 < split < 1e18`。数组长度为 `n` 时，排名前 `n + 1` 名可验证；第 1 名从验证阶段开始即可提交。排名按累计票数降序、`applicationId` 升序；票数相等不替换当前末位。

完整申请列表保留用于前端分页历史查询；内部只维护前 `n + 1` 名和 `applicationId -> rankIndex`。投票只增量更新当前候选，已入榜向前交换，未入榜只和末位比较，不自动扫描补位。

### 6.2 候选投票

`Vote` 回调标准传入 `voterId` 和本次治理票增量；前端按 Executor 约定把候选 `memberId` 放入 KV。Executor 通过候选 Member ID 查找其当前 `applicationId`，关联为 `0` 时拒绝；本次全部 `votes` 记给该申请。核心 Vote 负责限制投票人本轮对该行动的治理票总量，Executor 不重复维护该累计值。多次投票只记录增量，下一次可以指定其他候选。

### 6.3 快照、开放与验证

行动阶段结束时快照所有至少有一个成员参与的链群 MemberNFT（`groupId`），空链群不纳入；之后停用、恢复或新增不改变集合。每个链群按历史成员顺序维护连续批次游标，`startIndex` 必须等于已验证数量，禁止重复、跳过和乱序。

验证开放区块由验证阶段起始区块和阶段区块数计算；第 `i` 名使用其前一条分割线（第 1 名为 `0`），不能使用验证阶段结束后的区块。首个有效批次永久锁定公共验证者 `memberId`；之后只能由该 MemberNFT 当前持有人继续提交，不设置失效、接管或代理。NFT 转移后由新持有人继续，锁定身份不变。

必须完成全部快照链群验证才算本轮完整。无有效候选、候选投票为零、验证者失联或批次不完整时，链群行动者、服务者、公共验证者和链群 owner 的行动层激励均为 `0`；底层 Proposal 激励仍可按 `core` 规则铸造，Executor 可按自身规则销毁，但不得进行行动层分配。治理监督通过下一轮不给有问题候选投票完成，不回溯历史激励。

链群 owner 是链群 MemberNFT（`groupId`）主体，不是钱包地址；不保留 `setGroupDelegate`、代理验证者或群级验证 Delegate。

## 7. 链群服务行动执行合约

链群服务沿用旧版业务范围但取消工厂：一个服务 Proposal 面向整个 `actionTokenAddress` 社区的链群行动，不绑定单个源 `actionId`。Proposal 的激励代币为 `rewardTokenAddress`，可以是同币，也可以是父币激励子币社区；父子关系校验仍由业务执行合约完成。

服务创建 KV 除第 `0` 项 `executor` 外，只需保留旧版业务初始化参数 `actionTokenAddress` 和 `govRatioMultiplier`。链群行动的验证分割线属于对应链群行动 Executor；链群 owner 的接收主体和比例按链群、行动、服务轮次配置，不重复塞入服务全局初始化 KV。服务加入只接受两类 MemberNFT：目标社区有效链群的 owner，或相关链群行动中存在有效公共验证者申请的候选人；不要求当轮已经选出验证者。

服务 Executor 在 `Mint` 槽位：

1. 通过 `ActionTarget` 查询整个社区本服务 Executor 关联的 `proposalId[]`；
2. 按核心治理投票门槛筛出可铸造的行动 Proposal；
3. 过滤无公共验证者或未完成全量验证的行动；
4. 按完整行动的行动激励权重分摊服务 Proposal 实际铸造预算；
5. 按每个行动冻结的公共验证者比例 `r` 分给验证者，余款按服务规则分给链群 owner 及配置接收主体。

公共验证者激励来自链群服务 Proposal，不从链群行动 Proposal 扣除。服务没有 gas 补偿逻辑。

所有比例使用 `1e18`，每个链群比例总和不得超过 `1e18`，允许正好 `1e18`。各项向下取整，累计分配不得超过行动预算，余数归链群 owner；100% 分配时 owner 可为零，绝不能因 `budget - distributed` 下溢。使用同一组未截断分子/分母的全精度计算，修复旧版服务激励因二次舍入导致无法铸造的问题。旧函数语义统一命名为 `generatedActionRewardByOwner`。

## 8. 铸造闭环、事件与错误

行动激励闭环固定为 `executor -> ActionTarget -> Mint -> ActionTarget -> executor`。Executor 一次铸造该 Proposal 本轮全部行动激励，ActionTarget 不留余额，Executor 再按内部规则分配。只有关联 Executor 可发起该入口；任一步失败整笔回滚。公共验证未完成时可以取得底层 Proposal 激励后销毁，但不能把它分给行动者或服务者。

实现至少应发出行动创建/映射、推举、投票增量、申请创建/撤销/修改、排名变化、参与/撤回/退出、快照批次、验证锁定/完成、行动激励铸造/销毁、服务分配和 `forceExit` 事件。

至少拒绝：零地址或 EOA Executor、非 ActionTarget 回调、重复创建、KV 长度不等、非成员控制者、错误轮次、非法候选/分割线、无效批次、锁定后换验证者、重复铸造、超额分配和分配下溢。

## 9. 验收场景

必须覆盖：ActionTarget 三类回调及原子回滚、Executor 映射和重复初始化、四个轮次查询、LP V2 迁移和部分撤回、候选申请版本切换与排名平票、前 `n + 1` 开放时间、快照批次连续性和 NFT 转移续验、无候选/失联导致行动层激励为零、完整验证后的验证者/owner 分配、服务跨整个社区聚合、同币与父币激励子币、100% 二次分配和旧舍入溢出回归、`generatedActionRewardByOwner` 查询与单次铸造保护。
