# LOVE20BSC 跨仓库验收标准

本文件只记录组织级验收维度和证据要求；具体命令由各仓库 `README.md` 提供。

## 验收维度

- **可启动**：按各仓库 README 的前置条件和命令，能在干净工作区启动或运行。
- **可定位**：新人和 AI 能从 README、`AGENTS.md`、`CONTEXT.md`（如有）定位核心模块、入口和测试。
- **可集成**：`love20-anvil` 能按部署脚本启动本地链，并完成核心仓库与业务仓库的最小集成路径。
- **可发布**：地址、ABI、网络配置和前端环境变量来源明确；`interface-test` 验收后才能同步到 `interface`。
- **可自审**：负责 agent 在提交前完成第二遍自审，至少检查 diff、测试结果、跨仓库接口和文档同步；不要求外部 reviewer 才能通过。
- **无遗留**：代码、脚本、依赖和文档中不保留本次协议已删除或移出范围的旧组件，除非迁移票据明确标记为历史说明。
- **历史命名隔离**：迁移票据中的旧名称、旧 ABI 和旧实现事实必须明确标为历史讨论；实现只以目标仓库当前 `SPEC.md` 和本仓库组织约束为规范依据，票据与地图只用于追溯决策来源。
- **可追溯**：每项通过或失败都有命令、提交、日志或截图等最小证据，并能关联到对应仓库和提交。

## 具体场景验收

下列场景必须通过明确的测试路径验证。每个场景的验收方式、判定标准和测试位置见对应小节。

### Proposal 激励闭环
**覆盖要求**：
- 投票阶段结束前后准备
- 准备只写轮次级总状态且不逐个预写 Proposal
- 重复准备不改写
- 非 Target 铸造拒绝
- 各 Proposal Target 按冻结状态单独计算并铸造且单 Proposal 只能成功一次
- 行动类 `ActionTarget -> Mint -> executor` 转发
- 铸造失败整笔回滚

**测试方式**：
- 单元测试：`core/test/Mint.t.sol` 的 `test_PrepareOnlyOnce()`、`test_MintFailsBeforePrepare()`、`test_ProposalMintOnce()` 等
- 集成测试：`love20-anvil/scenarios/proposal-lifecycle.yml` 完整流程
- 验收证据：测试日志 + 覆盖率报告（要求该场景分支覆盖率 100%）

**判定标准**：
- 所有列出的单元测试通过
- 集成测试场景执行无失败断言
- Foundry 覆盖率报告显示相关函数分支覆盖率达 100%

### LP 行动执行合约
**覆盖要求**：覆盖旧 `extension-lp` V2 业务在 `action` 中的重写路径，包括 MemberNFT 参与、每笔加入时冻结时间扣减、部分撤回、整笔 Proposal 激励铸造后的内部成员结算/溢出销毁和失败回滚；不验收或迁移 V1 LP 实现。LP 手续费结算属于 `core/Stake`，不由 LP 行动 Executor 承担。

**测试方式**：
- 单元测试：`action/test/LPExecutor.t.sol` 的时间扣减、部分撤回、激励结算场景
- 集成测试：`love20-anvil/scenarios/lp-action-full-cycle.yml`
- 验收证据：对比旧 V2 实现的行为一致性测试报告

**判定标准**：
- 所有 V2 业务场景在新实现中通过
- 时间扣减公式与旧版一致
- 激励结算精度无损失

### 行动公式零值边界
**覆盖要求**：覆盖 LP 时间扣减封顶、`totalEffectiveAmount` 为零，以及治理上限启用时 `totalGovVotes` 为零；覆盖链群 `totalVotes`/`totalGroupScore`/`groupScore` 为零时不除零且行动层激励为零，并验证底层 Proposal 激励仍可独立处理。`govRatioMultiplier == 0` 时不得因治理票为零错误地清零 LP 或服务激励。

**测试方式**：
- 单元测试：边界值参数化测试
- Fuzzing：`test_ZeroBoundaries(uint256 effectiveAmount, uint256 totalVotes, uint256 multiplier)`
- 验收证据：Fuzzing 运行报告显示无 panic

**判定标准**：
- 零值输入不触发除零错误
- 激励计算结果符合规格定义
- Proposal 激励与行动激励正确隔离

### 治理融合与激励铸造
**覆盖要求**：覆盖调用者只控制来源 MemberNFT 时，可以把指定社区的治理质押单向融合进他人持有的有效目标 MemberNFT；目标既有资产不能减少。覆盖从流动质押或加速质押入口提高等待期时，按现有 LP Shares 原子重算成员和社区治理票。覆盖同一成员单轮铸造、显式 Round 数组的批量多轮铸造、逐轮三类结果和任一 Round 失败时整笔回滚。

**测试方式**：
- 单元测试：`core/test/Stake.t.sol` 的融合场景、等待期提升场景
- 单元测试：`core/test/Mint.t.sol` 的单轮/批量铸造场景
- 验收证据：测试日志显示融合前后状态变化、批量铸造的原子性

**判定标准**：
- 融合后目标资产只增不减
- 等待期提升后治理票立即重算
- 批量铸造任一 Round 失败则全部回滚

### MemberNFT 发射次数边界
**覆盖要求**：覆盖本次铸造前剩余供应量的阈值向上取整、只有正数实际治理激励进入 `launchCredit`、剩余供应量为零时不计算阈值、一次治理激励跨过多个完整阈值、整数除法余数继续累计、每个社区达到 `maxLaunchCount` 后停止新增次数和额度、调用者只控制来源 MemberNFT 时向他人持有的目标 MemberNFT 部分融合整数次数但不转移 `launchCredit`、源次数扣减/目标次数增加的原子性，以及次数消耗后不能再次发射。

**测试方式**：
- 单元测试：`core/test/Launch.t.sol` 的阈值计算、跨阈值、余数累计、上限场景
- 单元测试：`core/test/Launch.t.sol` 的次数融合、消耗场景
- 验收证据：边界值测试日志

**判定标准**：
- 阈值向上取整正确
- 余数跨次铸造正确累计
- 达到上限后不再增加次数
- 次数融合不携带 `launchCredit`

### 子币发射分发边界
**覆盖要求**：覆盖只有 `Launch` 可调用 `TokenFactory`、首个代币通过一次性启动路径使用 WBNB 且不消耗发射次数、启动后不能重复创建首个代币、普通发射社区与 `parentTokenAddress` 一致、非零 `distributor`、`NoCallback`/`Callback` 两种分配模式、KV 长度校验、回调失败回滚、首次代币使用 Airdrop 目标，以及部署时登记的保留符号不能本地发射或复用。

**测试方式**：
- 单元测试：`core/test/Launch.t.sol` 的首个代币启动、普通发射场景
- 单元测试：`core/test/TokenFactory.t.sol` 的权限、重复创建拒绝场景
- 验收证据：首个代币部署与 Airdrop 集成日志

**判定标准**：
- 只有 Launch 能调用 TokenFactory
- 首个代币启动只能成功一次
- 两种分发模式回调行为正确
- 保留符号拒绝创建

### MemberNFT 转移归属
**覆盖要求**：覆盖转移前后质押、解锁倒计时、治理激励和行动内部未铸造激励均由当前持有人继续操作；旧持有人不能代铸，历史投票、按 Round 参与历史、已结算激励和事件不回写。

**测试方式**：
- 单元测试：`core/test/MemberNFT.t.sol` 的转移场景
- 集成测试：转移后激励铸造、解锁操作由新持有人执行
- 验收证据：事件日志显示历史不回写

**判定标准**：
- 转移后新持有人可操作未铸造权益
- 旧持有人操作被拒绝
- 历史投票和事件不变

### MemberNFT 铸造和统计
**覆盖要求**：覆盖 `LOVE20 Member NFT`/`Member` 元数据、从 `1` 开始且不复用的 ID、名称 `32 bytes` 上限、UTF-8 与不可见字符校验、ASCII 大小写不敏感唯一性、短名称费用和原子销毁，以及标准 ERC721Enumerable 查询和自转账不会破坏可选的持有人统计。

**测试方式**：
- 单元测试：`core/test/MemberNFT.t.sol` 的名称校验、铸造费用、唯一性场景
- Fuzzing：UTF-8 边界、自转账场景
- 验收证据：Gas 报告显示铸造费用计算正确

**判定标准**：
- 名称校验规则与 `LOVE20Group` 一致（长度调整为32）
- ASCII 大小写不敏感
- 自转账不破坏持有人统计

### 链群全局索引与 Group Chat 主体
**覆盖要求**：覆盖链群 Executor 的 17 组 Group ID、Token Address、Action ID、Member ID 索引及每组全量数组/`Count`/`AtIndex` 一致性；覆盖同一成员跨社区、跨行动参与，退出一个行动但仍有其他关系时不得提前删除上层索引，最后一个关系退出后逐层清理，以及 `forceExit` 不修改这些业务索引。覆盖四类 typed Manager、普通 owner 管理型 Chat、规则槽位、插件、消息与分页行为；覆盖成员、管理员、委托、发言、提及、黑名单目标和黑名单投票者均按 `memberId` 运行，并确认不存在默认 MemberNFT 映射、默认身份发言入口、地址黑名单/投票/查询或其他地址主体接口。治理黑名单覆盖代币治理票与行动 Proposal 投票两类票权、全社区治理票分母、支持票严格超过反对票 `10` 倍且达到 `0.3%` 的双阈值、撤票和任何人刷新。链群 Chat 覆盖纯成员名单和”成员名单或链群 Executor 当前归属”标准资格源，并使用 `gTokenAddressesByGroupIdByMemberIdCount(groupId, senderId) > 0` 判断 Executor 归属；最后一次正常退出使资格失效，ActionTarget 的 `forceExit` 不单独改变资格。owner 快照及消息/事件调用地址只用于 NFT 转移有效性和审计，不得成为业务主体。

**测试方式**：
- 单元测试：`action/test/ChainGroupExecutor.t.sol` 的17组索引一致性场景
- 单元测试：`group-chat/test/GroupChat.t.sol` 的成员、委托、黑名单场景
- 集成测试：跨行动参与、`forceExit` 后索引和资格状态
- 验收证据：索引查询日志、Group Chat 资格判断日志

**判定标准**：
- 17组索引 Count 与 AtIndex 一致
- forceExit 不修改 Executor 业务索引
- Group Chat 无地址主体接口
- Executor 归属判断使用正确的索引查询

### Target 组合与幂等性
**覆盖要求**：覆盖 `NoCallback`/`Callback` 与 EOA/合约的合法组合、Callback + EOA 拒绝、缺少 executor 保留项的行动创建 KV 拒绝、仅 executor 项可创建，以及同一 `tokenAddress + proposalId` 重复创建回调回滚。

**测试方式**：
- 单元测试：`action/test/ActionTarget.t.sol` 的 Target 模式组合场景
- 验收证据：各组合的成功/拒绝行为日志

**判定标准**：
- 不合法组合被拒绝
- 重复创建回调回滚
- executor 保留项校验正确

### ActionTarget / Executor 状态边界
**覆盖要求**：覆盖仅关联 Executor 可登记/正常清除、当前 MemberNFT 持有人可 `forceExit`、强制退出后 ActionTarget 当前参与查询清除而 Executor 资产及链群归属状态不回写，以及不通过旧 Executor 状态自动恢复登记。

**测试方式**：
- 单元测试：`action/test/ActionTarget.t.sol` 的 forceExit 场景
- 集成测试：forceExit 后 ActionTarget 与 Executor 状态差异
- 验收证据：状态查询对比日志

**判定标准**：
- forceExit 后 ActionTarget 查询返回空
- Executor 资产状态未改变
- 链群归属不因 forceExit 变化

### Proposal Target 回调
**覆盖要求**：覆盖 Proposal 创建、提案推举、提案投票三类回调；覆盖创建回调只发生一次、推举已有 Proposal 不重复创建回调、`submitterId`、`voterId`、增量票和 KV 透传，以及回调失败时对应外层交易整体回滚。

**测试方式**：
- 单元测试：`core/test/Submit.t.sol`、`core/test/Vote.t.sol` 的回调场景
- Mock 合约：模拟回调失败场景
- 验收证据：回调调用次数、参数正确性、失败回滚日志

**判定标准**：
- 创建回调只调用一次
- 回调失败外层交易回滚
- 参数透传无丢失

### 公共验证者与 Round 历史
**覆盖要求**：覆盖加入、追加、体验加入、部分撤回和全部退出逐笔更新当前 Round；覆盖同轮多次变更、最后成员退出移除链群、无交互 Round 继承最近历史，以及加入阶段结束后不能回写。验证阶段无需前置状态准备交易即可读取目标 Round 历史；验证提交按成员历史顺序使用连续游标。首个验证批次永久锁定后验证者停止提交时，本轮行动层激励保持为 `0`，底层 Proposal 激励仍可按规则铸造或销毁，且不允许未经授权的其他候选人接管。

**测试方式**：
- 单元测试：`action/test/ChainGroupExecutor.t.sol` 的 Round 历史、验证场景
- 集成测试：多轮变更、验证者锁定场景
- 验收证据：Round 历史查询日志、验证激励分配日志

**判定标准**：
- Round 历史按加入阶段操作正确记录
- 验证者锁定后行动层激励为0
- 底层 Proposal 激励独立处理

### Phase 与候选边界
**覆盖要求**：覆盖 Phase 边界与同步观测分账、每次同步追加观测、按区块二分选择最近有效观测、`±10%` 动态校准、首个成功推举自动同步、治理 Round 与 Phase 的一对一映射及历史不可回写；覆盖无候选人、候选票为零、平票按 `applicationId` 排序、申请版本切换、排名锁定、分割线按排名映射、开放区块向上取整和阈值区块包含判断。

**测试方式**：
- 单元测试：`core/test/Phase.t.sol` 的同步、校准场景
- 单元测试：`action/test/ChainGroupExecutor.t.sol` 的候选排名、分割线场景
- 验收证据：Phase 调整日志、候选排序日志

**判定标准**：
- 动态校准在 ±10% 范围外生效
- 候选排序规则正确
- Phase 历史不可回写

### ActionRound 统一性
**覆盖要求**：覆盖 `Phase 1..3` 对 LP 行动和 `Phase 1..4` 对链群行动的冷启动期，各 Executor 查询尚未开始阶段时回滚 `RoundNotStarted` 且不返回 `0`。覆盖 LP 行动使用 3 阶段模型（投票-加入-铸币），链群行动使用 4 阶段模型（投票-加入-验证-铸币）。覆盖各 Executor 从 `Phase.currentPhase()` 正确计算自己的业务 Round，投票和加入的 Phase 映射在所有行动类型中一致（投票发生在 Phase p，同轮次加入发生在 Phase p+1）。各 Executor 提供标准查询接口，实现可参考旧代码库 `LOVE20TKM` 中的 Extension 接口。

**测试方式**：
- 单元测试：`action/test/LPExecutor.t.sol` 和 `action/test/ChainGroupExecutor.t.sol` 的 Phase 1-3/4 查询场景
- 集成测试：两类行动在同一 Phase 的投票和加入 Round 一致性
- 验收证据：Round 计算日志

**判定标准**：
- Phase 1-2 查询 LP 铸币 Round 回滚 RoundNotStarted
- Phase 1-3 查询链群铸币 Round 回滚 RoundNotStarted
- 相同 Phase 下，两类行动的投票和加入 Round 相同
- 各 Executor 提供 `currentVoteRound()`、`currentJoinRound()`、`currentMintRound()` 等标准接口

### LP 兼容性
**覆盖要求**：覆盖目标 PancakeSwap Factory/Pair/Router 在 `Stake` 场景下的 LP Shares 铸造、`sqrt(k)` 手续费重分类、结算阈值、结算不重复扣减 `withdrawableLp`、兑换报价、储备/基线更新、按份额提取和失败回滚；不得仅以 ABI 可编译作为兼容性结论。

**测试方式**：
- 单元测试：`compatibility/test/PancakeSwapCompatibility.t.sol` 的 Stake 集成场景
- 对比测试：与 Uniswap V2 参考实现的数值一致性
- 验收证据：兼容性测试报告、目标网络实测日志

**判定标准**：
- LP Shares 计算与 Uniswap V2 一致
- 手续费重分类公式正确
- 失败场景正确回滚

### 链群服务结算
**覆盖要求**：覆盖服务代币与行动代币相同或为其直接父币、非直接关系拒绝；覆盖只有当轮已加入服务 Proposal 的链群 owner/公共验证者候选 MemberNFT 才能按人结算、未加入角色份额不重分配、完整验证行动才进入分母、公共验证者与 owner 激励合并后只做一次治理上限，以及 `1e18` 乘数精度和 100% 二次分配不下溢。

**测试方式**：
- 单元测试：`action/test/ChainGroupServiceExecutor.t.sol` 的服务结算场景
- 验收证据：结算金额分配日志、精度验证日志

**判定标准**：
- 服务代币关系校验正确
- 未加入角色不参与分配
- 二次分配精度无损失

### 外部依赖兼容性
**覆盖要求**：`compatibility` 必须分别对本地 Uniswap V2/WETH9 参考实现和每个准备部署的目标网络 profile 的 WBNB、PancakeSwap Factory/Pair/Router 执行测试，覆盖接口返回值、Pair 创建和 LP 铸造/销毁、Swap 手续费与储备变化、Router 报价和实际输出、Token 顺序、失败回滚及协议计算所需的 `sqrt(k)` 数据；测试记录目标链、合约地址、区块高度和提交，任何未验证的外部地址不得进入对应 BSC 部署配置。

**测试方式**：
- 单元测试：`compatibility/test/*.t.sol` 按目标网络分组
- 集成测试：实际网络 fork 测试
- 验收证据：每个目标网络的兼容性报告

**判定标准**：
- 每个目标网络通过全部兼容性测试
- 测试报告包含合约地址、区块高度
- 未验证地址不在部署配置中

## 证据记录

每次 BSC 发布或候选发布，在本文件追加一条记录，至少包含：日期、目标网络、涉及仓库和提交、执行命令、结果、失败项及后续处理票据。
