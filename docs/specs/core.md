# LOVE20BSC Core 规格

状态：BSC 版实现前冻结的独立规格。

本文档描述 `core` 当前应实现的行为。读者不需要先阅读 `LOVE20TKM` 或迁移讨论；旧名称只在迁移依据中出现，不能作为当前接口依据。

## 1. 范围与非目标

`core` 是核心治理层和基础身份、阶段、发射能力，包含：

- `MemberNFT`（实现名可为 `LOVE20Member`）；
- `Stake`、`Submit`、`Vote`、`Mint`；
- `LOVE20Phase`；
- 基础子币创建、发射次数账本、次数融合和次数消耗；
- `LOVE20TokenFactory`。保留它是因为代币创建实现可能需要拆分部署字节码，不表示业务层普遍使用工厂。

以下内容不属于 `core`：

- LP、链群行动、链群服务和 `ActionTarget`；
- 群聊、**Group Chat Delegate** 和 P2P Chat；
- `LOVE20Verify`、随机抽取、代理验证者和不信任投票；
- 初始空投业务。首个代币的 `distributor` 可指向旧 [`LOVE20TKM/burn`](https://github.com/LOVE20TKM/burn) 独立部署的 Airdrop；空投合约不迁入本仓库；
- 公平发射后的复杂分配机制。本阶段不创建 `launch` 代码库。

## 2. 依赖与边界

`core` 不依赖 `action`、`group-chat` 或未来的 `launch`。它只定义通用 Proposal Target 回调边界，不导入或解释任何行动执行合约。

LP 质押依赖部署时传入的 PancakeSwap `Factory` 和 `Router`，目标部署必须提供与 Uniswap V2 兼容的 `Factory`、`Pair`、`Router` 接口和行为。兼容性验收以 `Stake` 的 LP 份额、手续费、兑换报价、储备更新和失败回滚结果为准，不能只看 ABI 或硬编码 Uniswap 手续费率。

## 3. 参与主体与权限

- 所有业务主体使用 `MemberNFT` 的 `memberId`。钱包地址只表示当前控制者或交易调用者。
- 需要代表某个成员写状态时，必须验证 `ownerOf(memberId) == msg.sender`。NFT 转移只改变控制者，不改变 `memberId`、历史记录或既有归属。
- `author`、`submitterId`、`voterId` 均为 `memberId`，不记录裸地址作为业务主键。
- 任何地址可以调用不绑定控制权的公开同步或轮次级准备函数，但不能绕过 NFT 控制权铸造成员激励。

## 4. 状态模型与不变量

### 4.1 MemberNFT

`MemberNFT` 是统一身份 NFT。治理质押、解锁状态、治理权、未铸造治理激励和发射次数都按 `memberId` 归属。不存在地址到默认 NFT 的 `MemberDefaults` 便利映射。

### 4.2 Stake

治理质押状态至少按 `tokenAddress + memberId` 隔离，直接存储在 `Stake`，不再铸造 SL/ST 凭证：

- 流动性质押产生治理票；
- 加速质押只参与治理激励的加速分配，不能单独取得治理资格；只有具有有效流动性质押治理权时才能增加加速质押；
- 两类质押共享一个解锁申请、等待条件和提取操作；申请时治理票立即清零并禁止追加质押；
- 等待 `promisedWaitingPhases` 个连续底层 Phase 后，由当前 NFT 持有人一次性提取两类质押；NFT 转移不重置或延长倒计时；
- `lpShares` 与 `withdrawableLp` 是双账本。手续费结算减少可赎回 LP，不改变份额总账，退出按当前份额比例结算，不能制造无法兑付的总量。

融合显式接收 `tokenAddress`，按社区隔离：

- 源、目标必须不同，调用者必须同时控制两个 MemberNFT；
- 任一方存在待处理解锁申请，或当前投票轮发生过非零投票，均禁止融合；
- 目标的等待期必须大于等于源的等待期；
- 只合并尚未使用的当前质押状态，合并后的状态使用目标等待期；源身份保留但当前质押清零；
- 已发生的投票、快照、已结算激励和历史事件永远归原 `memberId`，不回写。

### 4.3 LP 手续费与销毁统计

每个社区登记一个由 PancakeSwap Factory 查出的唯一 Pair。退出本金前或公开 `settleFees(tokenAddress)` 调用时，按旧版 `sqrt(k)` 增长逻辑计算待结算 `feeLp`，沿用最小手续费阈值。达到阈值后：

1. 从 Pair 取回 `feeLp`；
2. 社区代币部分直接销毁；
3. 父币部分仅通过固定直连路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁；
4. 更新全局销毁累计量和按 `tokenAddress` 的社区累计量。

兑换最小输出量由同一交易按当前储备计算，调用者不能注入任意路径。Pair、Router、销毁或统计更新失败时整笔结算/退出回滚。不得假定外部 PancakeSwap 使用固定 Uniswap 费率。

### 4.4 LOVE20Phase

`LOVE20Phase` 是无语义的底层时间线，不出现 Vote、Join、Verify、Mint 等上层阶段名称，也不定义业务 Round。

上层业务自行把 Phase 组合为 Round；Round 从 `1` 开始，存储值 `0` 只表示尚未设置，不是有效业务轮次。

构造参数为 `startBlock`、`initialPhaseBlocks`、`targetDays`，均大于零；第一个 Phase 编号为 `1`，有效查询不会返回第 `0` 个 Phase。每条已生成记录至少保存：

- `startBlock`；
- 生效的 `phaseBlocks`；
- 生成或同步时的 `syncBlock`、`syncTimestamp`。

公开只读/写接口语义为：

- `currentPhase()`：当前区块所在的 Phase；
- `phaseInfo(phaseNumber)`：已生成 Phase 的完整记录，未逐个存储的空区间按最近历史锚点推导；
- `phaseAtBlock(blockNumber)`：按历史记录和当时参数反推 Phase；
- `sync()`：任何地址可调用。

每次 `sync()` 都记录当前观测点，即使不改变参数。只检查最近一个满足 `currentBlock - syncBlock >= currentPhaseBlocks` 的有效观测点；没有满足条件的观测点时不调整下一阶段参数。若观测时长偏离 `targetDays × 86400` 超过 `±10%`，按 `newPhaseBlocks = elapsedBlocks × targetSeconds / elapsedSeconds` 调整尚未生成阶段，结果至少为 `1`；`elapsedSeconds == 0` 时跳过调整。已经生成的阶段不可回写，下一参数从尚未生成的阶段生效。APY 由前端按目标自然日计算，不进入合约。

### 4.5 Proposal

Proposal 以 `tokenAddress + proposalId` 定位，由 `Submit` 创建、推举，由 `Vote` 表决，由 `Mint` 铸造提案激励。数据命名为：

- `ProposalHead`：至少 `id`、`author`、`createAtBlock`；
- `ProposalBody`：至少 `title`、`details`；`title` 非空，`details` 可为空；
- `target`：提案激励铸造接收主体，必须是非零 EOA 或合约；
- `targetMode`：`RewardOnly` 或 `Callback`。

行动层把 `details` 解释为 `verificationRule`；核心不为行动字段重复建列。`actionId` 只是行动类 Proposal 的同值业务别名，普通 Proposal 不使用它。

`targetMode` 组合固定为：

| 目标 | 模式 | 结果 |
| --- | --- | --- |
| 非零 EOA | `RewardOnly` | 合法，仅接收铸造激励 |
| 非零合约 | `RewardOnly` | 合法，不回调 |
| 非零合约 | `Callback` | 合法，创建/推举/投票均回调，KV 为空也回调 |
| EOA | `Callback` | 拒绝 |

通用回调为：

```solidity
onProposalCreated(address tokenAddress, uint256 proposalId,
    bytes32[] keys, bytes[] values)
onProposalSubmitted(address tokenAddress, uint256 proposalId,
    uint256 submitterId, bytes32[] keys, bytes[] values)
onProposalVoted(address tokenAddress, uint256 proposalId,
    uint256 voterId, uint256 votes, bytes32[] keys, bytes[] values)
```

`keys.length` 必须等于 `values.length`。核心只透传不透明 KV，不理解行动业务；投票回调的 `votes` 是本次增量治理票，批量投票的每个 Proposal 有独立 KV。创建、推举或任意批量投票回调失败，外层整笔交易回滚；同笔创建并推举时先创建回调，再推举回调。

### 4.6 Vote 与 Mint

同一轮允许同一 MemberNFT 多次投票。`Vote` 只累计每次新增治理票，不能重复记录已记账值；行动层候选投票等业务字段通过 KV 传递。

投票结束后，任何地址可调用 `prepareProposalRewards(tokenAddress, round)`。它只准备并冻结该社区该轮的 Proposal 总激励和分配所需总状态，不枚举、不预写每个 Proposal 的额度；重复调用不得重算或重复预留。指定治理轮次是否结束由核心治理轮次规则判断，`Mint` 不解释 Phase 的上层名称。

每个 Proposal 由自己的 Proposal Target 单独铸造一次：

- `mintProposalReward(tokenAddress, round, proposalId)` 只能由已记录的 `target` 调用；
- `Mint` 按冻结的 Vote 状态计算实际数量，将代币铸给 Target 并返回数量；调用方不能指定 `memberId` 或任意 `amount`；
- 同一 Proposal 成功一次后再次调用拒绝；未准备、投票未结束、非 Target 调用均拒绝；
- 行动类 Proposal 由关联 `executor` 经 `ActionTarget` 间接调用，核心不直接依赖执行合约。

治理激励保留三段结果 `(verifyIncentive, boostIncentive, overflowIncentive)`，但统一称为“铸造激励”：

- `verifyIncentive` 按成员本轮累计治理票数 / 全体投票人治理票总数计算；
- 加速质押按投票时快照做增量记账，只有同轮后续再次投票才补记新增部分；没有后续投票不单独记账；
- 理论加速激励按成员累计已记账加速质押 / 全体已记账加速质押计算；
- `boostIncentive = min(theoreticalBoost, verifyIncentive × MAX_GOV_BOOST_REWARD_MULTIPLIER)`；
- `overflowIncentive = theoreticalBoost - boostIncentive`，溢出部分销毁；前两项一并铸造为治理激励。

治理激励、Proposal 激励均按 `tokenAddress + round + memberId/proposalId` 隔离。不同轮次可同时准备、按任意顺序铸造；已准备轮次的冻结额度不受之后质押、退出或融合影响。必须修复重复铸造和重复销毁状态，不能因重复调用反复销毁。

## 5. 公共接口语义

实现必须提供等价于以下能力的公开入口（具体参数顺序可按代码风格确定，但不得改变语义）：

- MemberNFT 铸造、转移、控制权校验和按成员查询；
- Stake 质押、追加、统一申请解锁、统一提取、按社区融合、手续费结算和全局/社区销毁统计；
- Submit 创建 Proposal、推举 Proposal 和查询 `ProposalHead`/`ProposalBody`；
- Vote 单笔/批量投票、按社区和轮次查询有投票 Proposal；
- Mint 准备轮次级 Proposal 总激励、按 Proposal Target 铸造 Proposal 激励、按 MemberNFT 铸造治理激励；
- 基础发射、发射次数融合和发射次数/已产生次数查询。

### 基础子币发射

发射次数按 `tokenAddress + memberId` 记录。治理激励铸造前，以剩余供应量计算阈值并向上取整：

```text
threshold = ceil((maxSupply - totalSupply) × launchRatio / 1e18)
```

一次铸造跨过多个阈值时增加对应整数次数，余数继续累计。每个社区最多产生 `maxLaunchCount = X` 次；达到 `X` 后治理激励仍可铸造，但不再新增次数。次数消耗或融合不降低社区累计已产生次数。

任何当前持有对应 MemberNFT 的钱包或合约可触发发射；每次消耗一次，不跨社区使用。发射必须提供非零 `distributor` 和 `distributorMode`，可附带等长 `distributorKeys`/`distributorValues`：

- `RewardOnly`：创建子币并把首批代币发送给 `distributor`，不回调；
- `Callback`：`distributor` 必须是合约，调用 `onTokenDistributed(childTokenAddress, amount, keys, values)`；回调失败整笔发射回滚。

中心化/去中心化只描述 `distributor` 后续如何分配，不限制谁触发发射。保留代币没有本地发射次数，不能再次触发发射。发射次数融合支持同一社区源 MemberNFT 向目标 MemberNFT 转移正整数的部分次数，源/目标由同一控制者操作，原子完成。

## 6. 事件、错误与原子性

实现至少应为成员转移、质押/解锁/提取/融合、Phase 生成与同步、Proposal 创建/推举/投票、激励准备/铸造/销毁、发射次数增加/融合/消耗、子币创建/分发和手续费销毁发出可索引事件。事件使用 `tokenAddress`、`memberId`、`proposalId`、`round` 等实际主键，不用地址替代 NFT 身份。

无效目标、非法模式、KV 长度不等、无权限成员、重复 Proposal/投票/铸造、未结束轮次、未准备激励、超额融合/消耗、非法 Phase 参数、PancakeSwap 兼容性调用失败都必须明确回滚。回调失败、手续费结算失败、激励转账失败、发射分发回调失败和状态更新失败不得留下半完成状态。

## 7. 验收场景

至少覆盖：MemberNFT 转移后新持有人继续解锁和铸造、统一解锁与融合边界、LP 份额和手续费销毁统计、PancakeSwap 实际地址上的 LP 数值一致性、Phase 空轮次查询和 `±10%` 校准、重复/批量投票增量、轮次级准备与 Proposal 单项一次性铸造、三段治理激励及重复销毁修复、阈值向上取整/跨多个阈值/`X` 上限、部分次数融合与消耗、两种 distributor 模式和首个 Airdrop 外部目标。
