# 协议模型与初始化参数

本文档定义 LOVE20BSC 的协议模型和初始化参数。

---

## 1. 协议模型

LOVE20 是社群铸币协议。每个 LOVE20 代币都有一个 `parentTokenAddress`。首个 LOVE20 代币的父币是公链原生代币的封装代币（BSC 为 WBNB）；该封装代币是协议树外的根父币，不是由 LOVE20 创建的代币。后续子币的父币是已登记的 LOVE20 代币。代币供应受 `maxSupply` 限制，协议按治理规则持续铸造激励；代币和治理状态全部在链上维护。

核心治理层包含：

- `MemberNFT`：统一参与身份（合并旧 LOVE20Group）
- `Stake`：治理质押、加速质押、LP 份额和手续费结算
- `Submit`：Proposal 创建和推举（旧版 Action 重命名为 Proposal）
- `Vote`：治理投票及 Proposal Target 回调
- `Mint`：轮次激励准备、治理激励和 Proposal 激励铸造
- `Phase`：无语义的动态时间片时间线（全新设计）
- `LOVE20Token`、`TokenFactory`：代币树和代币实例创建
- `Launch`：基础子币发射次数账本、次数融合、次数消耗和首批代币分发

核心不解释任何具体 Proposal 扩展的业务字段。扩展只通过 Proposal Target 的通用接口接入。

---

## 2. 初始化参数

以下参数在协议部署和初始化时确定，之后不可更改：

### 2.1 MemberNFT 初始化参数

**参考**：`LOVE20Group.sol` 构造函数

- `baseDivisor`：铸造费用基准除数（例如 1e8）
- `bytesThreshold`：名称长度阈值，低于此值费用按倍数增长（例如 7）
- `multiplier`：短名称费用增长倍数（例如 10）
- `maxMemberNameLength`：成员名称最大字节长度（例如 32，避免与钱包地址混淆）

首个代币地址不在部署时传入；首币由 `Launch.init(...)` 创建后，调用一次性 `MemberNFT.init(tokenAddress)` 绑定。

### 2.2 Phase 构造参数

**注意**：BSC 版全新设计，不参考旧版

- `originBlocks`：协议启动区块号
- `phaseBlocks`：初始 Phase 时长（区块数）
- `targetDays`：目标天数，用于动态校准（例如 7 天，BSC 版新增）

### 2.3 Stake 初始化参数

**参考**：旧版 `LOVE20Stake.sol` 初始化逻辑；BSC 版一次性入口统一命名为 `init(...)`

- `promisedWaitingPhasesMin`：最小承诺解锁期（Phase 数）
- `promisedWaitingPhasesMax`：最大承诺解锁期（Phase 数）

### 2.4 Submit 初始化参数

**BSC 版调整**

- `phaseAddress`：Phase 合约地址（BSC 版新增，用于动态校准）
- `stakeAddress`：Stake 合约地址
- `submitMinPerThousand`：推举门槛（千分比，例如 10 = 1%）

### 2.5 Mint 初始化参数

**BSC 版调整**：旧版 Action → Proposal

- `voteAddress`：Vote 合约地址
- `submitAddress`：Submit 合约地址
- `stakeAddress`：Stake 合约地址
- `proposalRewardMinVotePerThousand`：Proposal 获得激励的最低票数比例（千分比，例如 50 = 5%）
- `roundRewardGovPerThousand`：治理激励池比例（千分比，例如 30 = 3%）
- `roundRewardProposalPerThousand`：Proposal 激励池比例（千分比，例如 10 = 1%）
- `maxGovBoostRewardMultiplier`：加速激励倍数上限（例如 2）

### 2.6 Launch 初始化参数

**BSC 版重新设计**

- `tokenFactoryAddress`：TokenFactory 合约地址
- `mintAddress`：Mint 合约地址
- `memberNFTAddress`：MemberNFT 合约地址
- `rootParentTokenAddress`：协议树根父币地址（BSC 为 WBNB）
- `pairFactoryAddress`：PancakeSwap Factory 合约地址（用于创建 Pair）
- `routerAddress`：PancakeSwap Router 合约地址（用于添加流动性）
- `launchRatio`：发射阈值比例（1e18 精度，例如 1e16 = 1%，BSC 版新增参数）
- `maxLaunchCount`：每个社区最大发射次数（例如 100）

### 2.7 TokenFactory 初始化与子币创建参数

- `launchAddress`：唯一允许创建代币的 `Launch` 合约地址；通过 `TokenFactory.init(...)` 一次性写入

**参考**：`LOVE20Token.sol` 构造函数

- `name`：代币名称
- `symbol`：代币符号
- `initialSupply`：初始供应量（发射时铸造给 distributor）
- `maxSupply`：最大供应量
- `to`：初始代币接收者（distributor 地址）
