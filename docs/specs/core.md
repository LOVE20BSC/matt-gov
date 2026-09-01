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
- `Launch`：基础子币发射次数账本、次数融合、次数消耗和首批代币分发。

核心不解释任何具体 Proposal 扩展的业务字段。扩展只通过 Proposal Target 的通用接口接入。

## 2. 参与主体与通用约束

- 所有业务主体都是 `MemberNFT`，以 `memberId` 作为不可变身份主键。钱包地址只是当前控制者或交易调用者。
- `author`、`submitterId`、`voterId` 以及需要主体身份的其他参数均为 `memberId`。
- 减少或处分某个 MemberNFT 的资产、权益或业务状态时，必须验证 `MemberNFT.ownerOf(memberId) == msg.sender`；明确为单向融合目标的 MemberNFT 只增加状态，不要求由调用者持有。
- MemberNFT 转移只改变当前控制者，不改变身份、历史投票、快照、已结算激励或历史事件；当前未铸造权益由新控制者继续操作。
- Phase、治理 Round 和 MemberNFT 的有效编号从 `1` 开始；Proposal ID 由 `Submit` 单调分配并保持稳定，不把某个具体起始值当作通用哨兵。
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

首个代币使用 `Launch` 的一次性协议启动路径创建，不消耗发射次数，也不使用普通子币发射入口。`Launch` 仍是 `TokenFactory` 的唯一调用者；启动交易必须原子完成首个代币部署、协议代币登记、核心 `minter` 设置、首批代币铸造并发送到非零 `distributor`，以及首个代币/WBNB Pair 的创建或确认，任一步失败则整个启动回滚。启动成功后该路径永久关闭，不能创建第二个首个代币或改写其父币和分发结果。

**首个代币的 Airdrop 依赖**：BSC 首个代币的初始分发来源：
1. 在 BSC 上部署 `LOVE20TKM/burn` 仓库的 `Airdrop.sol` 合约
2. Airdrop 合约记录旧协议（Thinkium）参与者通过销毁活动获得的份额
3. 首个代币铸造后，按这些份额分发给对应地址

**来源可追溯性**：正式部署必须在文档中公开指向：
- `LOVE20TKM/burn` 仓库的 `Airdrop.sol`
- `DeployAirdrop.s.sol` 部署脚本
- `airdrop-design.md` 设计文档

这使任何人都可以验证首个代币分发的合法性和公平性。

注：`LOVE20TKM` 只读约束是指在实现 BSC 迁移期间不修改旧仓库代码；部署 Airdrop 到 BSC 可以手动操作，不属于迁移工作流的一部分。

核心不维护父币托底池或通过销毁子币兑换父币的业务。流动性质押手续费中的父币由 `Stake` 通过 Router 买入社区代币后销毁。

### 3.2 TokenFactory

`TokenFactory` 只接受协议 `Launch` 调用，负责创建子币并初始化核心依赖，任何其他地址都不能绕过发射次数和参数校验直接创建代币：

1. 普通子币校验父币是已登记的 LOVE20 代币；一次性首个代币启动只接受部署时固定的 WBNB，且仅在尚无首个代币时成立；
2. 校验符号长度、格式和全局唯一性；
3. 创建子币并设置 `maxSupply`、首批铸造量和 `minter`；
4. 通过配置的 PancakeSwap Factory 创建或确认子币/父币 Pair；
5. 把子币地址返回给发射流程。

每个子币只有一个父币，地址和符号在代币树中唯一。`TokenFactory` 可因部署字节码限制保留为独立部署组件，但不形成第二个发射入口。

## 4. MemberNFT

`MemberNFT` 是协议唯一的通用身份 NFT。质押、Proposal、投票、发射次数和所有扩展参与关系均使用 `memberId` 关联；同一 MemberNFT 可以在多个代币社区拥有互相独立的状态。

合约名为 `MemberNFT`，ERC721 名称为 `LOVE20 Member NFT`，符号为 `Member`。`memberId` 从 `1` 开始单调递增且永不复用；`0` 始终表示未设置。`mint(memberName)` 把 NFT 铸造给调用者并返回 `(memberId, mintCost)`。

### 4.1 名称校验

`memberName` 按 UTF-8 字节校验，必须非空且最多 `32 bytes`。名称保留用户提交的原始形式，但唯一性键只把 ASCII `A-Z` 转为小写，因此 ASCII 大小写不敏感且名称永久不能复用。名称不得包含 ASCII 空格、控制字符、DEL、Unicode 空白、零宽字符、行/段分隔符、方向控制字符、不可见数学运算符、废弃格式字符、无效或非最短 UTF-8、UTF-16 代理区编码和超出 `U+10FFFF` 的码点。公开查询至少支持按 `memberId` 取原始名称、判断名称是否已使用、按名称取 `memberId` 和返回规范化名称。

**名称校验实现基线**：名称校验逻辑可直接参考 `LOVE20TKM/group` 中 `LOVE20Group.sol` 的实现。BSC 版的主要变更：
- 最大长度降至 32 bytes（避免与钱包地址混淆）
- 其他 UTF-8 校验规则、ASCII 大小写不敏感、禁止字符类型保持一致

Gas 成本在旧版实际部署中已验证可行，无需重新评估。

### 4.2 铸造费用

铸造费用采用短名称稀缺性公式。设首个 LOVE20 代币的剩余未铸造量为 `unmintedSupply`：

```text
baseCost = unmintedSupply / baseDivisor
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost × multiplier ^ (bytesThreshold - byteLength)
```

`baseDivisor`、`bytesThreshold` 和 `multiplier` 均在部署时确定且必须大于零。铸造费用使用协议首个 LOVE20 代币支付；铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`。费用转入、销毁或安全铸造任一步失败时整笔回滚。

MemberNFT 的转移不复制、不拆分、不重置任何历史。依赖身份的合约必须实时读取 `ownerOf(memberId)`，不能缓存钱包地址作为长期权限。

供应量和按持有人查询使用标准 `ERC721Enumerable` 接口。若提供独立持有人数量接口，其状态更新必须显式忽略 `from == to` 的自转账，并与 `balanceOf` 的 `0 <-> 1` 边界一致；实现不得把可能因自转账失真的缓存统计作为权威数据。

## 5. Phase 与 Round

### 5.1 Phase

`Phase` 只维护连续的无语义时间片，不命名 Vote、Join、Verify、Mint 等业务阶段，也不定义上层 Round。

部署构造参数：

- `startBlock > 0`；
- `initialPhaseBlocks > 0`；
- `targetDays > 0`。

第一个 Phase 编号为 `1`。Phase 记录与同步观测记录分开：Phase 记录只保存 `startBlock` 和生效的 `phaseBlocks`；同步观测记录按调用顺序从 `1` 开始编号，保存 `blockNumber`、`timestamp`、调用前后的默认 `phaseBlocks` 和新参数开始生效的 `effectivePhase`。`effectivePhase = 0` 表示本次没有调整。观测时间戳不是 Phase 起始区块时间戳。

公开能力：

- `currentPhase()`：当前区块对应的 Phase；
- `phaseInfo(phaseNumber)`：阶段起始区块和阶段区块数；
- `phaseAtBlock(blockNumber)`：指定区块的 Phase；
- `syncObservationsCount()`、`syncObservation(observationId)`：同步观测数量和按 1-based ID 查询观测；
- `sync()`：任何地址可调用的校准入口。

`currentPhase()`、`phaseAtBlock(blockNumber)` 在目标区块早于 `startBlock` 时回滚 `PhaseNotStarted`；所有按编号查询都拒绝 `phaseNumber == 0`。未发生交互的空阶段不逐个写入。查询使用最近历史锚点，在已记录锚点之间二分定位，再按锚点当时的 `phaseBlocks` 推导目标阶段。下一 Phase 的 `startBlock` 是上一 Phase 结束后的首个区块；已经生成的 Phase 记录不可回写。

### 5.2 动态校准

每次 `sync()` 都先追加当前观测点，即使不调整参数。校准只使用此前观测中满足 `currentBlock - observation.blockNumber >= currentPhaseBlocks` 的最近一条；实现按单调递增的观测区块二分定位，不从末尾线性扫描。没有有效历史观测时只记录本次观测。

设 `targetSeconds = targetDays × 86400`，观测区块差为 `elapsedBlocks`，时间戳差为 `elapsedSeconds`，当前默认阶段区块数为 `currentPhaseBlocks`：

- `elapsedSeconds == 0` 时不调整；
- 先计算 `observedPhaseSeconds = elapsedSeconds × currentPhaseBlocks / elapsedBlocks`；该值在 `targetSeconds` 的 `±10%` 内时不调整；这样即使两个观测点之间跨过多个空 Phase，也只比较当前默认阶段区块数对应的估算自然时长；
- 超出范围时，尚未生成 Phase 使用 `newPhaseBlocks = max(1, elapsedBlocks × targetSeconds / elapsedSeconds)`；
- 已经生成的下一 Phase 不回写，新参数从之后第一个尚未生成的 Phase 生效，并把该编号写入本次观测的 `effectivePhase`。

核心 `Submit` 和 `Vote` 把 `Phase N` 一对一解释为治理 `Round N`，并提供无参数的 `currentRound()`。创建、推举和投票只写入当前治理 Round；当 `Phase.currentPhase() > N` 时，治理 Round N 的 Vote 时间片结束，`Vote` 对外返回该 Round 已结束，核心激励可以准备和铸造。`Mint` 只读取 `Vote` 的结束判断，不重复解释 Phase。行动层可以在同一时间线上采用自己的业务阶段映射；不同层的同号 Round 不代表同一业务对象。

## 6. Stake

### 6.1 状态

质押状态按 `tokenAddress + memberId` 隔离，直接存储在 `Stake`。每个社区至少维护：

- `totalLpShares`：社区全部流动性质押股份；
- `lpShares`：某个 `memberId` 持有的内部股份单位，不等同于 Pair 的 LP Token 数量；
- `withdrawableLp`：扣除已识别 `feeLp` 后，社区所有治理者共同拥有的可赎回 Pair LP 净资产；
- `boostStake`：加速质押数量；
- `promisedWaitingPhases`；
- `govVotes`；
- 统一解锁申请的 Phase、等待期和状态；
- 按 Round 的加速质押快照和累计历史。

流动性质押产生治理票；加速质押只参与治理激励的加速部分，不能单独取得治理资格。只有有有效流动性质押治理权的 MemberNFT 才能增加加速质押。某个 `memberId` 当前可赎回的 LP 为 `lpShares × withdrawableLp / totalLpShares`；提取时按该比例减少其股份和社区净资产。手续费刷新把新增 `feeLp` 从 `withdrawableLp` 中重分类，不减少 `totalLpShares`，因此不会改变股份比例，但会降低每份股份对应的净资产。

治理票公式：

```text
govVotes = lpShares × promisedWaitingPhases
```

### 6.2 流动性质押

调用者为目标 MemberNFT 提供社区代币和父币，`Stake` 将两种资产加入社区 Pair，取得 Pair LP 并铸造内部 LP Shares。两种金额都必须大于零；等待期必须在部署的最小/最大范围内，且不得低于该成员此前承诺的等待期。

加入 Pair 前先按第 6.6 节更新当时的 `feeLp` 和 `withdrawableLp`，设本次 Pair 实际铸造量为 `lpMinted`、加入前净资产为 `withdrawableLpBefore`：

```text
sharesMinted = totalLpShares == 0
    ? lpMinted
    : totalLpShares × lpMinted / withdrawableLpBefore
```

`totalLpShares > 0` 时必须同时满足 `withdrawableLpBefore > 0`，否则无法得到公平份额价格并回滚；`lpMinted` 和 `sharesMinted` 都必须大于 `0`。成功后 `withdrawableLp += lpMinted`、`totalLpShares += sharesMinted`、成员 `lpShares += sharesMinted`。计算使用全精度乘除并向下取整，不能按本次投入的代币名义金额直接增加 Shares。

质押资产转入、LP 份额增加、治理票增加、社区总治理票更新和事件在同一交易完成。待处理解锁期间不能追加质押。

### 6.3 加速质押

调用者为拥有有效治理权的 MemberNFT 存入社区代币，增加 `boostStake`。等待期可以提高但不能降低。加速质押不产生独立治理票。

无论从流动性质押还是加速质押入口提高 `promisedWaitingPhases`，都必须在同一交易中按新等待期重算该成员已有 LP Shares 的治理票，并同步更新社区总治理票：

```text
newGovVotes = lpShares × newPromisedWaitingPhases
totalGovVotes = totalGovVotes - oldGovVotes + newGovVotes
```

提高等待期本身不改变 `lpShares` 或 `boostStake`；没有 LP Shares 时治理票仍为 `0`。

**加速质押的激励分配机制**：加速质押不产生治理投票权，但参与治理激励中的加速部分分配。具体分配公式见第 8.3 节治理激励。流动性质押产生治理投票权，并参与投票激励（对应旧版"验证激励"）分配。两类质押可以同时存在，共享解锁生命周期。

投票记账使用投票时快照：首次投票记录当时加速质押；同一 Round 后续再次投票时，只补记当前数量超过已记录数量的差额；没有后续投票时，单独增加的加速质押不进入本轮；数量未增加时不重复记账。一次批量投票无论包含多少 Proposal，都只对该 `tokenAddress + round + voterId` 执行一次快照补差，不能按 Proposal 重复增加成员或全局加速质押量。

### 6.4 统一解锁和提取

两类质押必须同时申请解锁、同时等待、同时提取：

1. 当前 MemberNFT 持有人发起统一解锁申请；
2. 申请立即清零治理票，禁止追加质押和融合；
3. 申请绑定 `memberId`、申请时 Phase 和等待期；MemberNFT 转移不重置倒计时；
4. 连续经过 `promisedWaitingPhases` 个底层 Phase 后，当前持有人一次性提取 LP 对应的两种资产和加速质押代币。

提取前先结算手续费。状态清零、Pair 操作和资产转账必须原子完成。

### 6.5 融合

融合接口显式接收 `tokenAddress`，每个代币社区独立处理。源、目标 MemberNFT 必须不同且都已存在；调用者只需控制源 MemberNFT，不要求控制目标 MemberNFT。以下情况禁止融合：

- 任一方存在待处理解锁申请；
- 当前投票 Round 中任一方已经发生非零投票；
- 目标等待期小于源等待期。

融合只处理尚未使用的当前质押状态。**"已使用"是指该质押已在当前 Round 投票，或已进入解锁倒计时期。**未投票且未解锁的质押可以融合进目标 MemberNFT；已投票或已解锁的质押不能融合，避免破坏投票快照和解锁生命周期。

**融合转移的设计意图**：质押融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让这些资产可以通过 MemberNFT 作为载体进行场外交易。

**约束**：
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 来源质押必须未投票且未解锁
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

**场景**：持有人可以在紧急情况下将部分资产转移到另一个 MemberNFT，而无需等待解锁期或获得目标 NFT 持有人的签名授权。这不是攻击向量，因为转移只能增强目标 NFT 的资产，不能削弱或锁定它。

源的 LP Shares 和加速质押单向并入目标，不能修改或取走目标原有资产；合并后采用目标等待期，并按下式原子重算当前治理票和社区总治理票：

```text
targetLpSharesAfter = targetLpSharesBefore + sourceLpSharesBefore
targetGovVotesAfter = targetLpSharesAfter × targetPromisedWaitingPhases
sourceLpSharesAfter = 0
sourceGovVotesAfter = 0
```

社区总治理票先减去源、目标融合前治理票，再增加目标融合后治理票。源身份保留但当前质押和加速质押清零，已发生的投票、快照、已结算激励和事件仍归源 `memberId`。

### 6.6 LP 手续费和销毁统计

每个社区登记一个由 PancakeSwap Factory 返回的 Pair。`Stake` 为每个社区维护 `feeLp`、`withdrawableLp` 和上次基线 `previousSqrtKOfLp`。刷新手续费账本时，设：

```text
previousLp = feeLp + withdrawableLp
currentSqrtKOfLp = sqrt(reserve0 × reserve1) × previousLp / pairTotalSupply

if currentSqrtKOfLp > previousSqrtKOfLp:
    newWithdrawableLp = withdrawableLp × previousSqrtKOfLp / currentSqrtKOfLp
    newFeeLp = previousLp - newWithdrawableLp
else:
    newWithdrawableLp = withdrawableLp
    newFeeLp = feeLp
```

全部除法向下取整；实现必须避免 `reserve0 × reserve1` 和后续乘法中间溢出。`previousLp == 0` 或 `pairTotalSupply == 0` 时不产生手续费。该计算只把新增手续费对应的 LP 从 `withdrawableLp` 重分类到 `feeLp`，始终保持 `newFeeLp + newWithdrawableLp == previousLp`，因此不会凭空增加或减少合约持有的 LP。

首次增加 LP，以及每次刷新后又发生增加 LP、提取 LP 或结算 `feeLp` 时，都以操作完成后的 Pair 储备、Pair 总供应量和本合约最终持有 LP 重新写入 `previousSqrtKOfLp`；只读查询不得改写基线。手续费低于以下阈值时保留在 `feeLp`：

```text
feeLp × MAX_WITHDRAWABLE_TO_FEE_RATIO < withdrawableLp
```

达到或超过阈值时，由 `settleFees(tokenAddress)` 或提取流程执行：

1. 从 Pair 取回 `feeLp`；
2. 社区代币直接销毁；
3. 父币按固定路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁；
4. 更新全局累计销毁量和按 `tokenAddress` 的社区累计销毁量。

手续费结算从 Pair 移除并销毁属于 `feeLp` 的资产；`feeLp` 不归任何治理者。手续费刷新时已经从 `withdrawableLp` 重分类，实际结算只把 `feeLp` 清零，不得再次扣减 `withdrawableLp`；结算和刷新都不改变 `totalLpShares` 或任何成员的 `lpShares`。统一解锁完成后的全量提取按 `memberLpShares × withdrawableLp / totalLpShares` 计算当前可赎回 LP，再按该份额从 Pair 取回资产；Core 治理质押不提供绕过统一解锁的部分提取。兑换最小输出量按同一交易的当前储备计算，调用者不能传入任意路径。Pair、Router、销毁或统计更新失败时整笔交易回滚。

## 7. Proposal

### 7.1 数据结构

Proposal 由 `tokenAddress + proposalId` 定位。这里的 `tokenAddress` 同时表示该 Proposal 所属的治理社区和 Proposal 激励的铸币代币；Proposal 激励池由该社区的治理轮次决定。

Proposal 结构为：

- `ProposalHead`：`id`、`author`、`createAtBlock`；
- `ProposalBody`：`title`、`details`；`title` 非空，`details` 可为空；
- `target`：激励铸造接收主体，必须是非零 EOA 或合约；
- `targetMode`：`NoCallback` 或 `Callback`。

`actionId` 是部分行动类 Proposal 对同一 `proposalId` 的业务别名，不创建第二个 ID。行动框架把 `details` 解释为 `verificationRule`；`verificationKeys` 和 `verificationKeyGuides` 等行动专属字段放在创建 KV 中。

### 7.2 Target 模式与扩展性

Proposal Target 设计为地址类型而非强制 MemberNFT，是为了支持未来的业务扩展框架。当前 ActionTarget 是第一个扩展框架；未来可能出现其他类型的提案扩展，它们可以是合约地址或 EOA，由 Target 自身决定如何处理激励。这种灵活性使协议可以在不修改核心层的前提下接入新的业务模式。

| target | targetMode | 行为 |
| --- | --- | --- |
| 非零 EOA | `NoCallback` | 合法，只接收铸造激励 |
| 非零合约 | `NoCallback` | 合法，不触发回调 |
| 非零合约 | `Callback` | 合法，创建/推举/投票均回调，空 KV 也回调 |
| EOA | `Callback` | 拒绝 |

**零地址 Target 禁止的理由**：
1. 避免因遗忘填写地址导致激励永久丢失
2. 正常提案应该有明确的激励接收主体
3. 如需销毁激励，应创建专用销毁合约（铸造后立即销毁），使意图显式化

早期阶段，零地址销毁预期是伪需求；未来若有真实需求，可通过扩展实现。

KV 使用等长的 `bytes32[] keys` 和 `bytes[] values`。`NoCallback` 要求两数组为空；`Callback` 允许空数组并仍然触发回调。核心只校验长度并透传，不解释字段。

### 7.3 创建和推举

目标代币社区的总治理票必须大于 `0`。MemberNFT 的有效治理票满足 `memberGovVotes * 1e18 >= totalGovVotes * SUBMIT_MIN_RATIO` 时，其当前持有人可以创建或推举 Proposal；`SUBMIT_MIN_RATIO` 使用 `1e18` 精度且必须大于 `0`、不超过 `1e18`。创建新 Proposal 时可以在同一交易中完成本轮推举；已有 Proposal 可在后续 Round 推举。每个推举者每轮只能推举一个 Proposal，因此正数门槛把单轮推举 Proposal 数量限制在有限范围内。

每个治理 Round 的首个成功推举在写入 Proposal 推举状态前自动调用一次 `Phase.sync()`；其他地址仍可在任意区块直接调用 `sync()`。如果后续校验或 Target 回调回滚，自动同步产生的观测也随外层交易回滚，不算成功观测。

同一 Proposal 在同一 Round 只能推举一次；同一推举者在同一 Round 只能推举一个 Proposal。`onProposalCreated` 只在 Proposal 首次创建时调用一次；创建时同时完成本轮推举，则随后再调用 `onProposalSubmitted`。推举已有 Proposal 只调用 `onProposalSubmitted`，绝不再次调用创建回调。新建并同时推举时的校验、状态写入及回调顺序固定：

```text
核心校验 -> 写入状态 -> onProposalCreated -> onProposalSubmitted
```

任一回调失败，外层整笔交易回滚。

### 7.4 投票

拥有有效治理权的 MemberNFT 在 Vote 时间片使用不超过自身 `validGovVotes` 的治理票；每次投票都读取当时的 `validGovVotes`，不在首次投票时冻结。LP 质押或等待期增加后，后续投票可以使用新增的治理票；解锁、质押减少或融合使当前可用治理票不足时，后续超额投票回滚，已记录的历史票数不回写。同一 Round 可以多次投票，每次只写入本次新增票数；数组长度必须一致，每个增量大于零，Proposal 必须已在本 Round 推举。

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

Vote 时间片结束后，任何地址可以调用 `prepareRewards(tokenAddress, round)`。该调用同时准备治理池和 Proposal 池；它遍历 Vote 保存的当轮有票 Proposal，计算达门槛 Proposal 的票数总和，但不逐个预写 Proposal 金额，只写入一次 Round 级冻结状态。状态至少包括独立的 `prepared` 标志、治理激励池、Proposal 激励池、达到门槛的 Proposal 总票数、各池预留量/已铸造量/已销毁量，以及社区级跨轮次汇总的预留量/已铸造量/已销毁量。即使本轮两个池均为 `0`，`prepared` 也必须准确记录已准备，不能用非零金额代替准备状态。社区级汇总用于控制 `maxSupply`，各池账用于防止治理池和 Proposal 池重复消费同一额度。

设：

```text
reservedAvailable = rewardReserved - rewardMinted - rewardBurned
available = maxSupply - totalSupply - reservedAvailable
govPool = available × ROUND_REWARD_GOV_RATIO / 1e18
proposalPool = available × ROUND_REWARD_PROPOSAL_RATIO / 1e18
```

准备时一次性增加 `rewardReserved` 并冻结本轮池子；两个比例均使用 `1e18` 精度且不超过 `1e18`，初始化必须保证二者之和不超过 `1e18`。重复准备不重算、不重复预留。尚未结束 Vote 时间片的 Round 不可准备。

`rewardBurned` 表示本轮已取消、不会实际铸造的预留额度，不是先铸币再调用 ERC20 `burn`；它从 `reservedAvailable` 中移除后可进入后续 Round 的可用额度。已经铸给 Target/Executor 后再销毁的代币属于真实 ERC20 销毁，通过 `totalSupply` 减少反映，不重复计入 Mint 的 `rewardBurned`。任何时刻必须满足 `rewardReserved >= rewardMinted + rewardBurned`，同一份预留只能从未结算状态转为已铸造或已销毁一次。按成员或 Proposal 向下取整产生的最小单位余数不重新分配，继续保留为未结算预留。

达到 Proposal 激励门槛的条件为：

```text
proposalVotes > 0
proposalVotes × 1e18 >= totalVotes × PROPOSAL_REWARD_MIN_VOTE_RATIO
```

`PROPOSAL_REWARD_MIN_VOTE_RATIO` 使用 `1e18` 精度且必须大于 `0`、不超过 `1e18`。实现必须使用不会中间溢出的等价比较。准备时冻结所有合格 Proposal 的总票数作为分母；未达门槛的 Proposal 不参与 Proposal 池分配。准备扫描的最大集合受正数 `SUBMIT_MIN_RATIO` 限制，部署参数和 gas 基线必须保证该上限可在一笔交易中完成。

如果本 Round 没有任何治理投票，治理池和 Proposal 池均为 `0`，本轮不产生激励。若有投票但没有合格 Proposal，则 `eligibleProposalVotes = 0`，本轮没有 Proposal 可以铸造，Proposal 池直接记为 `0`，不预留、不延后结算，也不转给其他 Round 或 Proposal。

### 8.2 Proposal 激励铸造

每个 Proposal 由其 `target` 单独铸造一次：

1. Target 调用 Mint，不能由第三方代铸；
2. Mint 检查 Round 已准备、Vote 已结束、Proposal 达到门槛且尚未铸造；
3. 实际数量为 `proposalPool × proposalVotes / eligibleProposalVotes`；
4. 协议把实际数量铸给 Target，并返回数量，调用者不能指定成员或金额；
5. 使用独立的 `proposalSettled` 状态标记本 Proposal 已结算，实际数量即使因整数舍入为 `0` 也不能再次结算；重复调用回滚。

行动类 Proposal 由关联 Executor 调用 `ActionTarget`，再由 `ActionTarget` 以自身身份调用 `mintProposalReward`；ActionTarget 在同一交易中把全部实际数量转给 Executor。

### 8.3 治理激励

治理激励按 `tokenAddress + round + memberId` 隔离，返回 `(verifyReward, boostReward, overflowReward)`。治理池固定分为两个各占 50% 的部分：

- **投票激励部分**（`GOV_VERIFY_SHARE = 0.5e18`，对应旧版"验证激励"）：按成员实际投票行为分配
- **加速激励部分**（`GOV_BOOST_SHARE = 0.5e18`）：按加速质押份额占总加速质押的比例分配

总治理票为 `0` 时三项均为 `0`：

- `verifyReward = govPool × GOV_VERIFY_SHARE / 1e18 × memberVotes / totalVotes`；
- `theoreticalBoost = govPool × GOV_BOOST_SHARE / 1e18 × memberBoost / totalBoost`；
- `boostReward = min(theoreticalBoost, verifyReward × 2)`；
- `overflowReward = theoreticalBoost - boostReward`，溢出部分计入 `rewardBurned`，取消对应预留而不铸币。

`memberBoost` 和 `totalBoost` 使用投票时已记录的加速质押快照。若 `totalBoost == 0`，本轮整个加速池由轮次级 `boostBurned` 状态一次性计入 `rewardBurned`，所有成员的 `theoreticalBoost`、`boostReward` 和 `overflowReward` 均为 `0`；该取消预留不能由每个成员重复执行。50%/50% 划分和 2 倍上限是固定协议常量，不是部署参数。当前 MemberNFT 持有人可以铸造该成员尚未铸造的治理激励；独立的 `govSettled` 状态必须在本轮结算时设置，不以实际铸造量是否大于 `0` 判断。治理激励只能成功结算一次，溢出只能成功销毁一次，从而修复零铸造量或仅销毁时可重复处理的旧问题。

治理激励同时提供单轮和批量多轮铸造。批量入口接收同一 `tokenAddress + memberId` 的非空 `rounds[]`，按输入顺序逐轮执行与单轮入口相同的准备状态、归属、重复铸造和供应上限校验，并返回与 `rounds` 等长的三类激励结果数组；任一 Round 失败则整笔交易回滚。每个 Round 独立更新铸造/销毁状态和发射额度，批量调用不能合并账目或绕过单轮只能成功一次的限制，重复 Round 会在第二次处理时按重复铸造回滚。

接口形式为 `mintGovReward(tokenAddress, memberId, round)` 和 `mintGovRewards(tokenAddress, memberId, rounds[])`；两者都要求调用者是该 `memberId` 当前的 MemberNFT 持有人，不能传入钱包地址作为激励主体。批量接口返回按输入 Round 对齐的 `(verifyReward[], boostReward[], overflowReward[])`。

治理和 Proposal 激励按社区、Round 和主体完全隔离。不同 Round 可以同时准备并按任意顺序铸造；已准备 Round 的冻结状态不受之后质押、退出或融合影响。

## 9. 基础子币发射

### 9.1 发射次数

发射次数按 `tokenAddress + memberId` 记录整数 `launchCount` 和未消耗的累计发射额度 `launchCredit`，每个社区另记录累计已产生次数 `issuedLaunchCount`。每个社区最多产生 `maxLaunchCount` 次发射，该值在协议部署时通过构造函数传入，所有社区共享相同上限。达到上限后，该社区不再产生新的发射次数，但已有的整数次数仍可融合转移和消耗发射。

治理激励铸造时，以本次铸造前的剩余供应量计算本次阈值，并向上取整：

```text
threshold = ceil((maxSupply - totalSupplyBeforeMint) × launchRatio / 1e18)
```

只有本次实际铸造的治理激励大于 `0` 时才更新发射额度。剩余供应量为 `0` 时不计算阈值，也不更新 `launchCredit`；否则，本次实际铸造的治理激励先加入该 `tokenAddress + memberId` 的 `launchCredit`，再使用本次阈值计算完整次数：

```text
newCount = min(launchCredit / threshold, maxLaunchCount - issuedLaunchCount)
launchCredit -= newCount × threshold
launchCount[tokenAddress][memberId] += newCount
issuedLaunchCount[tokenAddress] += newCount
```

一次铸造可以跨过多个阈值；整数除法的余数保留在 `launchCredit`，继续与下一次实际铸造的治理激励累计。每个社区达到 `maxLaunchCount` 后治理激励仍可铸造，但不再增加次数或累计新的发射额度。次数消耗或融合不降低 `issuedLaunchCount`。

社区初始化的 `launchRatio` 和 `maxLaunchCount` 必须为正数。新增次数受 `maxLaunchCount - issuedLaunchCount` 限制；当剩余可产生次数为零时，不再增加任何成员的发射次数或 `launchCredit`。发射次数融合只转移已有的整数 `launchCount`，不转移 `launchCredit`，也不回写治理激励历史。

### 9.2 发射

任何当前持有目标 MemberNFT 的钱包或合约都可以触发该社区子币发射，但必须消耗该成员的一次 `launchCount`。发射次数不能跨社区使用；调用中的 `parentTokenAddress` 必须等于提供次数的 `tokenAddress`。

发射参数至少包含子币符号、父币地址、非零 `distributor`、`distributorMode` 和可选等长 `distributorKeys`/`distributorValues`：

- `NoCallback`：创建子币，把配置的首批代币发送给 `distributor`，不回调；
- `Callback`：`distributor` 必须是合约，调用 `onTokenDistributed(childTokenAddress, amount, keys, values)`；回调失败整笔发射回滚。

中心化或去中心化只描述 `distributor` 后续的分配方式，不限制发射调用者。协议部署时初始化全局保留符号集合，用于登记其他链已经发射且不得在本地复用的代币符号；保留符号不能由 `Launch` 或 `TokenFactory` 创建，登记保留符号本身不产生、消耗或转移任何社区的发射次数。协议首次部署产生的首个代币也必须填写非零 `distributor`，由外部 Airdrop 合约接收首批代币。

### 9.3 发射次数融合

`mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)` 支持同一社区的部分次数融合。源、目标必须是不同且已存在的 MemberNFT，`count > 0`，调用者只需控制源 MemberNFT，不要求控制目标 MemberNFT，且源次数必须足够。成功后源次数减少、目标次数增加；目标原有次数及其他状态不减少，其他质押、投票、历史发射和事件不改变。

**发射次数融合的设计意图**：发射次数融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让发射次数可以通过 MemberNFT 作为载体进行场外交易。

**约束**：
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 发射次数转移不携带 `launchCredit`，只转移整数次数
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

**场景**：持有人可以在紧急情况下将部分发射次数转移到另一个 MemberNFT，而无需获得目标 NFT 持有人的签名授权。这不是攻击向量，因为转移只能增强目标 NFT 的资产，不能削弱或锁定它。

## 10. 事件、错误和验收

事件至少覆盖：MemberNFT 铸造/转移、质押/解锁/提取/融合、Phase 生成/同步、Proposal 创建/推举/投票、激励准备/铸造/销毁、发射额度和次数增加/融合/消耗、子币创建/分发、Pair 手续费结算和销毁。事件主键使用 `tokenAddress`、`memberId`、`proposalId`、`round`。

以下情况必须回滚：无效成员或来源控制者、零地址 Target/Distributor、非法模式、KV 长度不等、Proposal 或推举重复、投票超额、Round 未结束或未准备、重复铸造/销毁、批量治理激励中存在任一无效 Round、待解锁时追加或融合、等待期不足、跨社区次数操作、发射次数不足或超社区上限、外部 Pair/Router 调用失败和任何 Target 回调失败。

验收至少覆盖：NFT 转移后的权限连续性、统一解锁和向非调用者持有目标 NFT 的融合、LP 份额与手续费销毁统计、PancakeSwap 兼容性、Phase 空阶段和动态校准、Proposal/投票回调原子性、Round 级准备与 Proposal 单项铸造、治理激励三段结果/投票增量补差/批量多轮铸造原子性、发射阈值向上取整/多阈值/社区上限/向非调用者持有目标 NFT 部分融合，以及两种 Distributor 模式。
