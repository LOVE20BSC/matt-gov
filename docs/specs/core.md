# LOVE20BSC Core 规格

状态：BSC 版实现前冻结的独立规格。

本文档定义核心治理层、MemberNFT、阶段时间线、代币树、质押、Proposal、投票、激励铸造和基础子币发射的完整行为。

## 1. 协议模型

LOVE20 是社群铸币协议。每个 LOVE20 代币都有一个 `parentTokenAddress`。首个 LOVE20 代币的父币是公链原生代币的封装代币（BSC 为 WBNB）；该封装代币是协议树外的根父币，不是由 LOVE20 创建的代币。后续子币的父币是已登记的 LOVE20 代币。代币供应受 `maxSupply` 限制，协议按治理规则持续铸造激励；代币和治理状态全部在链上维护。

核心治理层包含：

- `MemberNFT`：统一参与身份；
- `Stake`：治理质押、加速质押、LP 份额和手续费结算；
- `Submit`：Proposal 创建和推举；
- `Vote`：治理投票及 Proposal Target 回调；
- `Mint`：轮次激励准备、治理激励和 Proposal 激励铸造；
- `Phase`：无语义的动态时间片时间线；
- `LOVE20Token`、`TokenFactory`：代币树和代币实例创建；
- 基础子币发射次数账本、次数融合、次数消耗和首批代币分发。

核心不解释任何具体 Proposal 扩展的业务字段。扩展只通过 Proposal Target 的通用接口接入。

## 2. 参与主体与通用约束

- 所有业务主体都是 `MemberNFT`，以 `memberId` 作为不可变身份主键。钱包地址只是当前控制者或交易调用者。
- `author`、`submitterId`、`voterId` 以及需要主体身份的其他参数均为 `memberId`。
- 代表成员写入状态时必须验证 `MemberNFT.ownerOf(memberId) == msg.sender`。
- MemberNFT 转移只改变当前控制者，不改变身份、历史投票、快照、已结算激励或历史事件；当前未铸造权益由新控制者继续操作。
- Phase、治理 Round、ActionRound 和 MemberNFT 的有效编号从 `1` 开始；Proposal ID 由 `Submit` 单调分配并保持稳定，不把某个具体起始值当作通用哨兵。
- 比例采用 `1e18` 精度；按比例分配的整数金额默认向下取整，发射阈值明确使用向上取整。
- 每个核心合约完成一次初始化后，依赖地址和初始化参数不可替换；不存在升级管理员或协议级后门。
- 外部调用使用重入保护和检查-更新-交互顺序，任何失败都不得留下半完成状态。

## 3. 代币树

### 3.1 代币实例

每个 `LOVE20Token` 至少包含：

- `parentTokenAddress`；首个代币固定为部署时配置的 WBNB，后续子币必须指向已登记的 LOVE20 代币；
- `maxSupply`；
- 核心 `minter`；
- ERC20 的 `totalSupply`、余额和授权。

只有 `minter` 可以铸造，且 `totalSupply + amount <= maxSupply`。持有人可以销毁自己持有的代币。首个代币的父币、名称、符号、首批供应量和分发者在协议首次部署时设定。

核心不维护父币托底池或通过销毁子币兑换父币的业务。流动性质押手续费中的父币由 `Stake` 通过 Router 买入社区代币后销毁。

### 3.2 TokenFactory

`TokenFactory` 负责创建子币并初始化核心依赖：

1. 校验父币是已登记的 LOVE20 代币；
2. 校验符号长度、格式和全局唯一性；
3. 创建子币并设置 `maxSupply`、首批铸造量和 `minter`；
4. 通过配置的 PancakeSwap Factory 创建或确认子币/父币 Pair；
5. 把子币地址返回给发射流程。

每个子币只有一个父币，地址和符号在代币树中唯一。`TokenFactory` 可因部署字节码限制保留为独立部署组件。

## 4. MemberNFT

`MemberNFT` 是协议唯一的通用身份 NFT。质押、Proposal、投票、发射次数和所有扩展参与关系均使用 `memberId` 关联；同一 MemberNFT 可以在多个代币社区拥有互相独立的状态。

MemberNFT 的转移不复制、不拆分、不重置任何历史。依赖身份的合约必须实时读取 `ownerOf(memberId)`，不能缓存钱包地址作为长期权限。

## 5. Phase 与 Round

### 5.1 Phase

`Phase` 只维护连续的无语义时间片，不命名 Vote、Join、Verify、Mint 等业务阶段，也不定义上层 Round。

部署构造参数：

- `startBlock > 0`；
- `initialPhaseBlocks > 0`；
- `targetDays > 0`。

第一个 Phase 编号为 `1`。每条已生成记录保存 `startBlock`、生效的 `phaseBlocks`、`syncBlock` 和 `syncTimestamp`。同步观测时间戳不是阶段起始区块时间戳。

公开能力：

- `currentPhase()`：当前区块对应的 Phase；
- `phaseInfo(phaseNumber)`：阶段起始区块、阶段区块数和同步数据；
- `phaseAtBlock(blockNumber)`：指定区块的 Phase；
- `sync()`：任何地址可调用的校准入口。

未发生交互的空阶段不逐个写入。查询使用最近历史锚点，在已记录锚点之间二分定位，再按锚点当时的 `phaseBlocks` 推导目标阶段。已经生成的阶段记录不可回写。

### 5.2 动态校准

每次 `sync()` 都记录当前观测点，即使不调整参数。只检查最近一个满足 `currentBlock - syncBlock >= currentPhaseBlocks` 的有效观测点；没有有效点时只记录观测。

设 `targetSeconds = targetDays × 86400`，观测区块差为 `elapsedBlocks`，时间戳差为 `elapsedSeconds`：

- `elapsedSeconds == 0` 时不调整；
- 实际时长在目标的 `±10%` 内时不调整；
- 超出范围时，尚未生成阶段使用 `newPhaseBlocks = max(1, elapsedBlocks × targetSeconds / elapsedSeconds)`；
- 已经生成的下一阶段不回写，参数从之后第一个尚未生成的阶段生效。

上层按自身业务把 Phase 组合成 Round。治理 Round 和行动 Round 都从 `1` 开始；不同层的同号 Round 不代表同一对象。

## 6. Stake

### 6.1 状态

质押状态按 `tokenAddress + memberId` 隔离，直接存储在 `Stake`。每个社区至少维护：

- `totalLpShares`：社区全部流动性质押股份；
- `lpShares`：某个 `memberId` 持有的内部股份单位，不等同于 Pair 的 LP Token 数量；
- `withdrawableLp`：扣除已结算 `feeLp` 后，社区所有治理者共同拥有的可赎回 Pair LP 净资产；
- `boostStake`：加速质押数量；
- `promisedWaitingPhases`；
- `govVotes`；
- 统一解锁申请的 Phase、等待期和状态；
- 按 Round 的加速质押快照和累计历史。

流动性质押产生治理票；加速质押只参与治理激励的加速部分，不能单独取得治理资格。只有有有效流动性质押治理权的 MemberNFT 才能增加加速质押。某个 `memberId` 当前可赎回的 LP 为 `lpShares × withdrawableLp / totalLpShares`；提取时按该比例减少其股份和社区净资产。手续费结算减少 `withdrawableLp`，不减少 `totalLpShares`，因此不会改变股份比例，但会降低每份股份对应的净资产。

治理票公式：

```text
govVotes = lpShares × promisedWaitingPhases
```

### 6.2 流动性质押

调用者为目标 MemberNFT 提供社区代币和父币，`Stake` 将两种资产加入社区 Pair，取得 LP 份额并更新治理票。两种金额都必须大于零；等待期必须在部署的最小/最大范围内，且不得低于该成员此前承诺的等待期。

质押资产转入、LP 份额增加、治理票增加、社区总治理票更新和事件在同一交易完成。待处理解锁期间不能追加质押。

### 6.3 加速质押

调用者为拥有有效治理权的 MemberNFT 存入社区代币，增加 `boostStake`。等待期可以提高但不能降低。加速质押不产生独立治理票。

投票记账使用投票时快照：首次投票记录当时加速质押；同一 Round 后续再次投票时，只补记当前数量超过已记录数量的差额；没有后续投票时，单独增加的加速质押不进入本轮；数量未增加时不重复记账。

### 6.4 统一解锁和提取

两类质押必须同时申请解锁、同时等待、同时提取：

1. 当前 MemberNFT 持有人发起统一解锁申请；
2. 申请立即清零治理票，禁止追加质押和融合；
3. 申请绑定 `memberId`、申请时 Phase 和等待期；MemberNFT 转移不重置倒计时；
4. 连续经过 `promisedWaitingPhases` 个底层 Phase 后，当前持有人一次性提取 LP 对应的两种资产和加速质押代币。

提取前先结算手续费。状态清零、Pair 操作和资产转账必须原子完成。

### 6.5 融合

融合接口显式接收 `tokenAddress`，每个代币社区独立处理。源、目标 MemberNFT 必须不同，调用者必须同时控制两者。以下情况禁止融合：

- 任一方存在待处理解锁申请；
- 当前投票 Round 中任一方已经发生非零投票；
- 目标等待期小于源等待期。

融合只处理尚未使用的当前质押状态。源的 LP 份额、加速质押和当前治理状态并入目标，合并后采用目标等待期；源身份保留但当前质押清零。已发生的投票、快照、已结算激励和事件仍归源 `memberId`。

### 6.6 LP 手续费和销毁统计

每个社区登记一个由 PancakeSwap Factory 返回的 Pair。`Stake` 根据 Pair 储备和历史 `sqrt(k)` 份额计算待结算 `feeLp`。低于最小手续费阈值时保留；达到阈值时，由 `settleFees(tokenAddress)` 或提取流程执行：

1. 从 Pair 取回 `feeLp`；
2. 社区代币直接销毁；
3. 父币按固定路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁；
4. 更新全局累计销毁量和按 `tokenAddress` 的社区累计销毁量。

手续费结算从 Pair 移除并销毁属于 `feeLp` 的净资产；`feeLp` 不归任何治理者。结算减少社区 `withdrawableLp`，不改变 `totalLpShares` 或任何成员的 `lpShares`。退出或部分提取按 `memberLpShares × withdrawableLp / totalLpShares` 计算当前可赎回 LP，再按该份额从 Pair 取回资产。兑换最小输出量按同一交易的当前储备计算，调用者不能传入任意路径。Pair、Router、销毁或统计更新失败时整笔交易回滚。

## 7. Proposal

### 7.1 数据结构

Proposal 由 `tokenAddress + proposalId` 定位。这里的 `tokenAddress` 同时表示该 Proposal 所属的治理社区和 Proposal 激励的铸币代币；Proposal 激励池由该社区的治理轮次决定。

Proposal 结构为：

- `ProposalHead`：`id`、`author`、`createAtBlock`；
- `ProposalBody`：`title`、`details`；`title` 非空，`details` 可为空；
- `target`：激励铸造接收主体，必须是非零 EOA 或合约；
- `targetMode`：`RewardOnly` 或 `Callback`。

`actionId` 是部分行动类 Proposal 对同一 `proposalId` 的业务别名，不创建第二个 ID。行动框架把 `details` 解释为 `verificationRule`；`verificationKeys` 和 `verificationKeyGuides` 等行动专属字段放在创建 KV 中。

### 7.2 Target 模式

| target | targetMode | 行为 |
| --- | --- | --- |
| 非零 EOA | `RewardOnly` | 合法，只接收铸造激励 |
| 非零合约 | `RewardOnly` | 合法，不触发回调 |
| 非零合约 | `Callback` | 合法，创建/推举/投票均回调，空 KV 也回调 |
| EOA | `Callback` | 拒绝 |

KV 使用等长的 `bytes32[] keys` 和 `bytes[] values`。`RewardOnly` 要求两数组为空；`Callback` 允许空数组并仍然触发回调。核心只校验长度并透传，不解释字段。

### 7.3 创建和推举

目标代币社区中，有效治理票占总治理票达到 `SUBMIT_MIN_PER_THOUSAND / 1000` 的 MemberNFT 当前持有人可以创建或推举 Proposal。创建新 Proposal 时可以在同一交易中完成本轮推举；已有 Proposal 可在后续 Round 推举。

同一 Proposal 在同一 Round 只能推举一次；同一推举者在同一 Round 只能推举一个 Proposal。创建和推举的校验、状态写入及回调顺序固定：

```text
核心校验 -> 写入状态 -> onProposalCreated -> onProposalSubmitted
```

任一回调失败，外层整笔交易回滚。

### 7.4 投票

拥有有效治理权的 MemberNFT 在 Vote 时间片使用不超过自身 `validGovVotes` 的治理票。同一 Round 可以多次投票，每次只写入本次新增票数；数组长度必须一致，每个增量大于零，Proposal 必须已在本 Round 推举。累计票数超过可用治理票时回滚。

Vote 保存 Round 总票、Proposal 总票、成员总票、成员对 Proposal 的票、当轮有票 Proposal 列表和各 Proposal 的投票成员列表。

批量投票中每个 Proposal 可以附带独立 KV。只有 `targetMode = Callback` 才触发目标回调，空 KV 也回调。通用投票回调参数为 `tokenAddress`、`proposalId`、`voterId`、本次增量 `votes` 和 KV；任意一个回调失败，整笔批量投票回滚。

通用回调接口：

```solidity
onProposalCreated(address tokenAddress, uint256 proposalId,
    bytes32[] keys, bytes[] values)
onProposalSubmitted(address tokenAddress, uint256 proposalId,
    uint256 submitterId, bytes32[] keys, bytes[] values)
onProposalVoted(address tokenAddress, uint256 proposalId,
    uint256 voterId, uint256 votes, bytes32[] keys, bytes[] values)
```

## 8. Mint

### 8.1 轮次激励池

Vote 时间片结束后，任何地址可以调用 `prepareProposalRewards(tokenAddress, round)`。该调用只写入一次 Round 级冻结状态，不枚举、不预写每个 Proposal 的金额。状态至少包括治理激励池、Proposal 激励池、达到门槛的 Proposal 总票数、各池预留量/已铸造量/已销毁量，以及社区级跨轮次汇总的预留量/已铸造量/已销毁量。社区级汇总用于控制 `maxSupply`，各池账用于防止治理池和 Proposal 池重复消费同一额度。

设：

```text
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
govPool = available × ROUND_REWARD_GOV_PER_THOUSAND / 1000
proposalPool = available × ROUND_REWARD_PROPOSAL_PER_THOUSAND / 1000
```

准备时一次性增加 `rewardReserved` 并冻结本轮池子；初始化必须保证两个激励比例之和不超过 `1000 / 1000`。重复准备不重算、不重复预留。尚未结束 Vote 时间片的 Round 不可准备。

达到 Proposal 激励门槛的条件为：

```text
proposalVotes >= totalVotes × PROPOSAL_REWARD_MIN_VOTE_PER_THOUSAND / 1000
```

准备时冻结所有合格 Proposal 的总票数作为分母。未达门槛的 Proposal 不参与 Proposal 池分配。

如果本 Round 没有任何治理投票，治理池和 Proposal 池均为 `0`，本轮不产生激励。若有投票但没有合格 Proposal，则 `eligibleProposalVotes = 0`，本轮没有 Proposal 可以铸造；对应池子只能通过一次性的显式销毁/结算路径处理，不能转给其他 Round 或 Proposal。

### 8.2 Proposal 激励铸造

每个 Proposal 由其 `target` 单独铸造一次：

1. Target 调用 Mint，不能由第三方代铸；
2. Mint 检查 Round 已准备、Vote 已结束、Proposal 达到门槛且尚未铸造；
3. 实际数量为 `proposalPool × proposalVotes / eligibleProposalVotes`；
4. 协议把实际数量铸给 Target，并返回数量，调用者不能指定成员或金额；
5. 标记 Proposal 已铸造，重复调用回滚。

行动类 Proposal 由关联 Executor 调用 `ActionTarget`，再由 `ActionTarget` 以自身身份调用 Mint；ActionTarget 在同一交易中把全部实际数量转给 Executor。

### 8.3 治理激励

治理激励按 `tokenAddress + round + memberId` 隔离，返回 `(verifyIncentive, boostIncentive, overflowIncentive)`。治理池固定分为两个各占 50% 的部分（`GOV_VERIFY_SHARE = 0.5e18`、`GOV_BOOST_SHARE = 0.5e18`）；总治理票为 `0` 时三项均为 `0`：

- `verifyIncentive = govPool × GOV_VERIFY_SHARE / 1e18 × memberVotes / totalVotes`；
- `theoreticalBoost = govPool × GOV_BOOST_SHARE / 1e18 × memberBoost / totalBoost`，`totalBoost == 0` 时为零；
- `boostIncentive = min(theoreticalBoost, verifyIncentive × 2)`；
- `overflowIncentive = theoreticalBoost - boostIncentive`，溢出部分销毁。

`memberBoost` 和 `totalBoost` 使用投票时已记录的加速质押快照。50%/50% 划分和 2 倍上限是固定协议常量，不是部署参数。当前 MemberNFT 持有人可以铸造该成员尚未铸造的治理激励；治理激励只能成功铸造一次，溢出只能成功销毁一次。

治理和 Proposal 激励按社区、Round 和主体完全隔离。不同 Round 可以同时准备并按任意顺序铸造；已准备 Round 的冻结状态不受之后质押、退出或融合影响。

## 9. 基础子币发射

### 9.1 发射次数

发射次数按 `tokenAddress + memberId` 记录整数 `launchCount`，每个社区另记录累计已产生次数 `issuedLaunchCount`。

治理激励铸造时，以本次铸造前的剩余供应量计算阈值，并向上取整：

```text
threshold = ceil((maxSupply - totalSupply) × launchRatio / 1e18)
```

一次铸造可以跨过多个阈值，余数继续累计。每个社区最多产生 `maxLaunchCount = X` 次；达到 `X` 后治理激励仍可铸造，但不再增加次数。次数消耗或融合不降低 `issuedLaunchCount`。

### 9.2 发射

任何当前持有目标 MemberNFT 的钱包或合约都可以触发该社区子币发射，但必须消耗该成员的一次 `launchCount`。发射次数不能跨社区使用。

发射参数至少包含子币符号、父币地址、非零 `distributor`、`distributorMode` 和可选等长 `distributorKeys`/`distributorValues`：

- `RewardOnly`：创建子币，把配置的首批代币发送给 `distributor`，不回调；
- `Callback`：`distributor` 必须是合约，调用 `onTokenDistributed(childTokenAddress, amount, keys, values)`；回调失败整笔发射回滚。

中心化或去中心化只描述 `distributor` 后续的分配方式，不限制发射调用者。保留代币没有本地发射次数，不能触发新的子币发射。协议首次部署产生的首个代币也必须填写非零 `distributor`，由外部 Airdrop 合约接收首批代币。

### 9.3 发射次数融合

`mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)` 支持同一社区的部分次数融合。源、目标不同，`count > 0`，调用者必须同时控制两个 MemberNFT，源次数必须足够。成功后源次数减少、目标次数增加；其他质押、投票、历史发射和事件不改变。

## 10. 事件、错误和验收

事件至少覆盖：MemberNFT 铸造/转移、质押/解锁/提取/融合、Phase 生成/同步、Proposal 创建/推举/投票、激励准备/铸造/销毁、发射次数增加/融合/消耗、子币创建/分发、Pair 手续费结算和销毁。事件主键使用 `tokenAddress`、`memberId`、`proposalId`、`round`。

以下情况必须回滚：无效成员或控制者、零地址 Target/Distributor、非法模式、KV 长度不等、Proposal 或推举重复、投票超额、Round 未结束或未准备、重复铸造/销毁、待解锁时追加或融合、等待期不足、跨社区次数操作、发射次数不足或超社区上限、外部 Pair/Router 调用失败和任何 Target 回调失败。

验收至少覆盖：NFT 转移后的权限连续性、统一解锁和融合、LP 份额与手续费销毁统计、PancakeSwap 兼容性、Phase 空阶段和动态校准、Proposal/投票回调原子性、Round 级准备与 Proposal 单项铸造、治理激励三段结果和投票增量补差、发射阈值向上取整/多阈值/社区上限/部分融合，以及两种 Distributor 模式。
