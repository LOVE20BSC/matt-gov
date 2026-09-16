# Core 迁移变更清单

本文档列出 BSC Core 相对于 LOVE20TKM 旧协议的所有变更。保留项直接引用旧代码位置，避免重复描述。

## 迁移原则

1. **身份统一**：所有业务主体统一使用 MemberNFT 的 `memberId`
2. **去凭证化**：质押不再产生 SL/ST ERC20 代币，状态直接归 `memberId`
3. **时间灵活**：引入无语义的 Phase 时间线，替代固定 4 阶段映射
4. **独立协议**：BSC 是新协议代际，不兼容旧合约存储、地址和历史状态

---

## 组件迁移矩阵

| 组件 | 状态 | 旧位置 | 新位置 | 核心变化 |
|------|------|--------|--------|----------|
| MemberNFT | 复制迁移 | `LOVE20TKM/group/src/LOVE20Group.sol` | core/MemberNFT.sol | 接口保留并去 group 字样、名称 64→32 bytes、费用代币地址改 init 传入 |
| Phase | 全新 | - | core/Phase.sol | 替代固定阶段，动态校准 |
| Stake | 重构 | `LOVE20TKM/core/src/LOVE20Stake.sol` | core/Stake.sol | 去 SL/ST 凭证，按 memberId 归属 |
| Submit | 保留 | `LOVE20TKM/core/src/LOVE20Submit.sol` | core/Submit.sol | 主体改为 memberId |
| Vote | 保留 | `LOVE20TKM/core/src/LOVE20Vote.sol` | core/Vote.sol | 主体改为 memberId |
| Mint | 修改 | `LOVE20TKM/core/src/LOVE20Mint.sol` | core/Mint.sol | 治理激励公式调整 |
| LOVE20Token | 重构 | `LOVE20TKM/core/src/LOVE20Token.sol` | core/LOVE20Token.sol | ERC20、父币、maxSupply 和 minter 保留；移除 SL/ST 依赖 |
| Launch | 修改 | `LOVE20TKM/core/src/LOVE20Launch.sol` | core/Launch.sol | 合并代币创建职责，发射次数按 memberId 记录 |
| TokenFactory | 删除 | `LOVE20TKM/core/src/LOVE20TokenFactory.sol` | 无（职责并入 core/Launch.sol） | 代币创建入口并入 Launch，不再部署独立合约 |

---

## 1. MemberNFT（复制迁移）

旧 `LOVE20TKM/group/src/LOVE20Group.sol` 整体复制为 `core/MemberNFT.sol`，业务逻辑不改；行为规范见 [MemberNFT 规格](core/02-member-nft.md)。"协议唯一身份"仅指各业务合约以 `memberId` 为键使用它（见 Stake、Submit、Vote、Mint、Launch 各节），本合约不新增承载或转移规则。

差异五项：

- **合约名与接口标识符**：`LOVE20Group` → `MemberNFT`，ERC721 名称 `LOVE20 Member NFT`、符号 `Member`；对外接口仅去除 group 字样且不重复 member（如 `groupNameOf` → `nameOf`、`GroupNameEmpty` → `NameEmpty`），持有人枚举另行改为分页（见下）——旧 Group 是成员身份 NFT，不是“群”的 NFT
- **名称长度上限**：`64 bytes` → `32 bytes`（避免与钱包地址混淆）
- **铸造费用代币地址**：由旧构造函数传入改为 `init(firstTokenAddress)`，由 `Launch.init` 在创建首币时同步调用一次
- **持有人枚举改分页**：`holdersCount()` 与 `holdersAtIndex(uint256 index)` 合并为 `holders(uint256 offset, uint256 limit, bool reverse) returns (address[] memory holderList, uint256 totalCount)`；`offset` 大于或等于总数时返回空数组与真实总数、不回滚，配套删除错误 `HolderIndexOutOfBounds(uint256 length)`。分页语义与 `Phase.syncObservations` 一致。持有人集合的精确去重语义不变（地址去重、自转账既不加入也不移除、移除采用 swap-and-pop）
- **铸造路径内部整理**：费用扣款由旧 `SafeERC20.safeTransferFrom` 的 `SafeERC20FailedOperation(address)` 改为 `IERC20.transferFrom` 失败后回滚 `FeeTransferFailed()`，回滚面全部落在 `IMemberNFT.sol`、不再依赖 OZ 库内错误；`_validateName` 顺带返回规范化名称，`mint` 内 `_toLowerCase` 只算一次。对外 ABI 只多出 `FeeTransferFailed`

---

## 2. Phase（全新设计）

### 替代对象
- 旧版协议中硬编码的 4 阶段时间线（Vote、Join、Verify、Mint）

### 核心设计
- **无业务语义**：Phase 只维护连续时间片，不命名具体阶段
- **动态校准**：根据实际区块时间自动调整 `phaseBlocks`，使每个 Phase 接近目标自然天数
- **固定映射**：Core 治理和 Action 层各 Executor 按各自规格把 Phase 映射为业务轮次

### 关键特性
- 第一个 Phase 编号为 `1`
- 支持空 Phase（无交互时不逐个写入）
- `sync()` 任何地址可调用；按调用前 `currentPhase()` 全局限频，每个治理投票 Round 最多一次有效同步
- 同轮重复 `sync()` 无操作返回，不追加观测、不调整参数、不发事件，不能阻塞 Submit
- Submit 每轮首个推举自动调用一次 `sync()`；已同步时该调用无操作返回
- 默认先回溯最近 10 条观测，未命中时二分查找；偏差阈值 `adjustThreshold` 在初始化时配置

### 为什么新增
- 不同行动类型需要不同阶段数（LP 3阶段，链群 4阶段）
- 避免硬编码阶段映射，提升协议灵活性

---

## 3. Stake（重构）

### ✅ 保留逻辑
- **LP 份额计算**：参考 `LOVE20TKM/core/src/LOVE20Stake.sol`
- **手续费结算公式**：参考同文件的 sqrt(k) 结算逻辑
- **治理票公式**：`govVotes = lpShares × promisedWaitingPhases`

### 🔄 关键变化

#### 去凭证化
- **旧**：质押产生 SL/ST ERC20 代币
- **新**：不再产生凭证，状态直接存储在 Stake 合约
- **按 memberId 归属**：`stake[tokenAddress][memberId]`

#### 统一解锁
- **旧**：SL/ST 独立解锁
- **新**：流动性质押和加速质押必须同时申请、同时等待、同时提取

#### 融合支持
- **新增**：质押可以融合到另一个 MemberNFT
- **单向转移**：调用者只需控制来源 MemberNFT
- **场景**：支持 MemberNFT 场外交易时携带质押资产

### ❌ 删除能力
- 不再产生 SL（Staking Liquidity）代币
- 不再产生 ST（Staking Token）代币
- 删除 SL/ST 的独立解锁流程

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Stake.sol
保留公式：LP 份额和手续费结算逻辑
删除：SL/ST铸造逻辑（移除 ERC20 依赖）
```

---

## 4. Submit（保留，主体变更）

### ✅ 保留逻辑
- Proposal 创建和推举流程：参考 `LOVE20TKM/core/src/LOVE20Submit.sol`
- 推举门槛计算（SUBMIT_MIN_RATIO）
- 每轮首个推举触发 Phase 同步；若本轮已有同步则无操作返回，不影响推举

### 🔄 关键变化
- **主体身份**：`submitterAddress` → `submitterId (memberId)`
- **权限校验**：`msg.sender` → `MemberNFT.ownerOf(submitterId) == msg.sender`
- **创建入口改名**：`submitNewAction(tokenAddress, ActionBody)` → `submitNewProposal(tokenAddress, memberId, ProposalBody)`，沿用旧 `submitNewAction`/`submit` 的动词配对；**保留旧代码「创建后立即推举」的语义**——旧 `submitNewAction` 内部即 `_createAction` + `_submitByActionId` 一笔完成，新接口同样在同一笔内先创建再推举，两个入口共用「每人每轮一个」「每提案每轮一次」两条名额约束
- **校验顺序对齐 core 统一口径**：旧 `submitNewAction` 先查 `canSubmit` 再校验参数，新接口按「参数 → 存在性 → 持有 → 门槛 → 本轮名额」执行。非行为差异（任一不满足都回滚整笔），改的是错误优先级：参数非法且不满足门槛时报精确参数错误而非 `CannotSubmitAction()`

### 🆕 接口新增（2026-09-15）
- **错误声明拆出子接口**：`ISubmitErrors` 独立声明（含新增 7 个错误，另有 1 个改名）
- **删除无用常量**：移除 `MAX_VERIFICATION_KEY_LENGTH()`（无消费者）
- **补全 getter**：新增 `initialized()`, `phaseAddress()`, `memberNFTAddress()`
- **两条方向单键查询**（旧 `submitInfo` / `submitInfoBySubmitter` 各改名，返回值都由 `ActionSubmitInfo` 收为单个标量，`0` 表示本轮未推举）：
  - `proposalIdBySubmitter()` - 由成员在某轮推举的提案反查（旧 `submitInfoBySubmitter`）
  - `submitterIdByProposalId()` - 由提案反查其推举者（旧 `submitInfo`），与上一条互为逆
  - **原因**：`(tokenAddress, round)` 下的推举记录是 `(proposalId, submitterId)` 对，且「每人每轮一个」「每提案每轮一次」使两种键都是唯一键；两条单键是两个方向的定点通道，`submitInfos()` 的分页是集合的完整读取路径，三者读同一份记录。旧接口的两个方向本就互为镜像，按同样方式改名
- **单键存在性判定保留**：`isSubmitted()` 是旧接口同名同参的保留成员，回 `bool`；它与 `submitterIdByProposalId()` 同键但给出的是两个不同的值（存在性 vs 取值），不构成重复，如同 `IMemberNFT.isNameUsed` 与 `idOf`
- **删除 minStake 字段**：
  - 从 `ProposalBody` 删除 `minStake`（旧 `ActionBody` 的该字段）
  - 删除 `submitNewProposal` 中的 `minStake > 0` 校验（`ZeroAmount("minStake")` 不再用于此处）
  - `ProposalCreated` 事件不含 `minStake`
  - **原因**：BSC 架构删除统一 Join 模块，旧代码中 `minStake` 用于首次加入门槛的逻辑已移至 Action 层各 Executor 独立配置
- **结构体按旧分层重组**：
  - 新增 `ProposalInfo { ProposalHead head, ProposalBody body }`，对应旧 `ActionInfo { ActionHead head, ActionBody body }`
  - `ProposalBody` 改为「创建者提供的全部字段」：`title`、`details`、`target`、`targetMode`、`targetData`，`submitNewProposal` 的入参与 `ProposalInfo` 的组成共用这一个结构
  - `ActionSubmitInfo` 改名 `SubmitInfo`，字段 `submitter` 由地址改为 `submitterId`
  - **原因**：旧 `ActionBody` 就是创建者提供的全部字段，保留两套同字段的名字只会让 `submitNewProposal` 的入参与 `proposalInfosByIds()` 的返回看起来属于不同结构
- **枚举改用分页**：
  - 删除 6 个函数：`proposalsCount()`、`proposalsAtIndex()`、`proposalsByAuthorCount()`、`proposalsByAuthorAtIndex()`、`submissionsCount()`、`submissionAtIndex()`
  - 新增 3 个分页函数，统一 `(offset, limit, reverse)` 入参、按页返回并同时给出集合真实总数，语义同 `Phase.syncObservations`：
    - `proposalIds(address tokenAddress, uint256 offset, uint256 limit, bool reverse)` 返回 `(uint256[] proposalIdList, uint256 totalCount)`
    - `proposalIdsByAuthor(address tokenAddress, uint256 author, uint256 offset, uint256 limit, bool reverse)` 返回 `(uint256[] proposalIdList, uint256 totalCount)`
    - `submitInfos(address tokenAddress, uint256 round, uint256 offset, uint256 limit, bool reverse)` 返回 `(SubmitInfo[] submitInfoList, uint256 totalCount)`
  - **原因**：与 Phase 的 `syncObservations` 分页模式保持一致，单次调用获取数据 + 总数，Gas 效率更高
- **读取面三类**：分页 = `proposalIds`/`proposalIdsByAuthor`/`submitInfos`；按 id 批量取详情 = `proposalInfosByIds(proposalIds[])`；单键 = `isSubmitted`、`proposalIdBySubmitter`、`submitterIdByProposalId`
  - **分页返回值随成员是否定长**：`proposalIds`/`proposalIdsByAuthor` 只回 `proposalId`，因为 `ProposalBody` 的 `title`/`details`/`targetData` 都不设长度上限，分页回本体时某条大 `targetData` 就能把整页顶到调用方 gas 上限之上且跳不过去；`submitInfos` 回完整记录，因为 `SubmitInfo` 全为 `uint256`，任意一页的体量都与 `limit` 成正比
  - **不设单条详情入口**：读一条传单元素数组，避免出现只差一个字母、返回值却是两种东西的近名对
  - **命名记号**：数组返回值在名字里体现载荷——`Ids` 只回轻量标识、`Infos` 回记录本体，裸集合名不用于返回数组的函数；筛选条件进名字（默认全量不标记、`By<key>` 按键、`ByIds` 显式 ID 数组）；是否分页不进名字，由入参 `(offset, limit, reverse)` 决定，不为同一集合另设无窗口的全量重载
  - 旧 `actionsAtIndex`/`actionSubmitsAtIndex` 直接在枚举里回结构体，改为「分页回标识 + 按 id 批量取详情」
  - **命名依据**：分页记号沿用 core 已实现集合读取的复数集合名（`syncObservations`、`holders`、`tokens`、`childTokens`、`boostUpdatedRounds`）与 group-chat 里轻量标识带 `Ids` 的先例（`votedSenderIds`、`memberIds`）；「按显式 ID 数组取记录」沿用 group-chat 的 `chatInfos`/`roundInfos`（复数 + `Infos`）。仓库现有 28 个分页函数全部以参数 `(offset, limit, reverse)` 表意，名字里不带任何分页记号，本接口沿用同一口径

#### 新增与改名错误（相对旧代码，用于精准 revert）
| 错误名 | 触发条件 | Selector |
|--------|----------|----------|
| `EmptyString(string field)` | 标题为空 | `0x62a65aec` |
| `ZeroAmount(string field)` | `submitMinPerThousand == 0` | `0x3b3e6350` |
| `InvalidAmount()` | `submitMinPerThousand > 1000` | `0x2c5211c6` |
| `InvalidAddress()` | `init` 参数或 `target` 为零 | `0xe6c4247b` |
| `InvalidTargetMode()` | targetMode 枚举越界或 Callback 且 target 无代码 | `0x2589e3a0` |
| `RoundNotStarted()` | `currentRound() == 0`（业务可选校验） | `0x8e9c6e1c` |
| `NotMemberOwner(uint256 memberId)` | 调用者不持有该 memberId | `0x33393244` |
| `ProposalNotFound(uint256 proposalId)` | proposalId 不存在（旧 `ActionIdNotExist()` 改名并加参） | `0x428d06a9` |

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Submit.sol
保留：推举门槛、去重逻辑、核心 selector
修改：所有 address 参数改为 uint256 memberId
新增：精准错误、缺失 getter、ISubmitErrors 子接口、ProposalInfo 包装与按 id 批量取详情 proposalInfosByIds(proposalIds[])
删除：MAX_VERIFICATION_KEY_LENGTH()、minStake 字段及其校验、6 个枚举函数
改名：actionInfo → proposalInfosByIds（去掉单条入口，改为按 id 批量）、submitInfoBySubmitter → proposalIdBySubmitter、submitInfo → submitterIdByProposalId（两个方向各改名，返回值都收为单个标量）
合并：actionsCount/AtIndex → proposalIds、authorActionIdsCount/AtIndex → proposalIdsByAuthor、actionSubmitsCount/AtIndex → submitInfos（分页回记录）
```

---

## 5. Vote（保留，主体变更）

### ✅ 保留逻辑
- 投票流程和票数记录：参考 `LOVE20TKM/core/src/LOVE20Vote.sol`
- 投票增量机制（支持同一 Round 多次投票）
- Proposal Target 回调机制

### 🔄 关键变化
- **主体身份**：`voterAddress` → `voterId (memberId)`
- **权限校验**：`msg.sender` → `MemberNFT.ownerOf(voterId) == msg.sender`

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Vote.sol
保留：投票记录结构、增量逻辑
修改：所有 address 参数改为 uint256 memberId
```

---

## 6. Mint（修改）

### ✅ 保留逻辑
- 轮次激励池准备：参考 `LOVE20TKM/core/src/LOVE20Mint.sol`
- Proposal 激励门槛和分配公式

### 🔄 关键变化

#### 治理激励术语调整
- **旧**：verifyReward（验证激励，50%）+ boostReward（加速激励，50%）
- **新**：voteReward（投票激励，50%）+ boostReward（加速激励，50%）

**机制保持一致**：
- 50/50 拆分保持不变：`govReward / 2`
- 第一部分按投票行为分配（旧称"验证激励"，新称"投票激励"）
- 第二部分按加速质押分配（仍称"加速激励"）
- 2 倍上限机制保持不变

**变更理由**：
- BSC 版无独立验证阶段，投票即治理参与，"投票激励"更准确
- 加速激励名称保持一致

#### 加速质押参与激励分配
- **旧**：加速质押参与治理激励的加速部分分配（50%），并受 2 倍上限
- **新**：继续参与同一 50% 加速激励，并继续受 2 倍上限；BSC 仅把份额归属从地址改为 `memberId`

#### 批量铸造
- **新增**：`mintGovRewards(tokenAddress, memberId, rounds[])`
- **原子性**：批量多轮铸造，任一 Round 失败则整笔回滚

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Mint.sol
保留：轮次准备、Proposal 分配
修改：治理激励改为 50%/50% 拆分，增加 2 倍上限
```

---

## 7. Launch（修改）

### ✅ 保留的旧行为

旧 `LOVE20TKM/core/src/LOVE20Launch.sol` 中真正被完整保留的只有四项：

- `isLOVE20Token` 的登记判定
- `tokenSymbol` 的长度与字符集校验
- `tokenSymbol + "@" + parentSymbol` 名称拼法，以及父币符号前 4 字节为 `Test` 时施加的测试网前缀（校验之后施加，实际符号可超出配置长度）
- `launchToken` 的“检查—创建—登记”外部调用骨架

### 🆕 新增设计（旧实现中不存在）

- **发射次数阈值换算与额度结转**：旧 `LOVE20Mint` 只在每次治理激励铸造时对账户计数 `+1`，旧 `LOVE20Launch` 用整数除法反推剩余次数，既没有阈值、也没有额度累计与余数结转。阈值向上取整、余数保留、跨多次阈值属新设计，见 [Mint 的发射额度](core/07-mint.md#发射额度的生成)
- **社区次数上限**：每个社区最多产生 `MAX_LAUNCH_COUNT` 次发射
- **次数融合**：`mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)`
- **分发模式与回调**：`distributor`、`DistributorMode` 与不透明的 `bytes[] distributorData`

### 🔄 关键变化

#### 按 memberId 记录
- **旧**：`launchCount[tokenAddress][address]`
- **新**：`launchCount[tokenAddress][memberId]`

#### 发射资格
- **旧**：`remainingLaunchCount` 叠加 `Submit.canSubmit` 与 Mint 的铸造计数整除，发射需要推举资格
- **新**：只看 `launchCount` 账本与 NFT 当前所有权；`submitAddress` 依赖与 `canSubmit` 门槛删除

#### 次数融合
- **新增**：`mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)`
- **部分转移**：支持转移指定数量的发射次数
- **单向转移**：调用者只需控制来源 MemberNFT

#### 社区次数上限
- **新增**：每个社区最多产生 `MAX_LAUNCH_COUNT` 次发射
- **达到上限后**：治理激励仍可铸造，但不再增加发射次数

#### 首个代币部署
- `Launch.init(LaunchInitParams)` 在同一笔初始化交易中写入依赖、发射和供应量参数，直接创建首个代币、设置 `minter`、发送首批代币到 Airdrop，并同步调用 `MemberNFT.init(firstToken)` 完成其初始化；Pair 由 `Stake` 在首次 LP 质押时按需创建
- `Launch` 的分发参数与 Proposal 的 `target + targetMode` 对齐：首币固定使用 Airdrop 和 `NoCallback`；普通发射可使用 `NoCallback` 或 `Callback`
- `Launch.init` 任一步失败则整笔回滚；成功后不得再次初始化或创建第二个首个代币
- Airdrop 来源和 Burn 追溯证据按部署记录保存

#### 不迁移的业务
公平发射募资与认购领取整块不迁移：`contribute`、`withdraw`、`claim`、`claimInfo`、`LaunchInfo` 的其余 10 个字段、`CLAIM_DELAY_BLOCKS` 全部删除。按发射者或募资状态划分的枚举（`childTokensByLauncher*`、`launching*`、`launched*`、`participatedTokens*`）也删除；代币列表与某社区子币列表保留为分页查询（`tokens`、`childTokens`），符号到地址账本保留为 `tokenAddressBySymbol`（子币符号全局唯一，`TokenSymbolExists`），代币地址到父币地址保留为 `parentTokenOf`。

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Launch.sol
保留：isLOVE20Token、符号校验、名称拼法与 Test 前缀、launchToken 骨架
新增：阈值换算与额度结转（见 07-mint）、社区上限、次数融合、分发模式
修改：地址 → memberId，删除 submitAddress 与 canSubmit 门槛
```

---

## 8. LOVE20Token & Launch（代币创建职责合并）

### ✅ 保留
- ERC20 标准实现
- 代币树结构（parentTokenAddress）
- maxSupply 限制
- minter 权限控制
- Launch 内部代币创建流程

### 🔄 BSC 调整
- Launch 内部创建逻辑接收非零 `distributor`，首批供应量直接铸给该地址
- 删除 SL/ST 实例创建及其 Stake 依赖；Pair 生命周期移入 `Stake`，由其在首次 LP 质押时按需创建
- 首个代币依赖 Airdrop 合约分发（来源：LOVE20TKM/burn）
- 删除 `burnForParentToken`、`parentPool()`、`BurnForParentToken` 事件和 `InsufficientBalance` 错误：BSC 版不再由代币合约承担父币赎回，社区手续费中父币的换币与销毁由 `Stake` 结算（见 [Stake](core/04-stake.md)）；`parentTokenAddress` 保留，`Stake` 用它判定代币是否已登记。同时移除随之不再需要的 `ReentrancyGuard` 继承

### 📍 实现参考
```
旧代码：
  LOVE20TKM/core/src/LOVE20Token.sol
  LOVE20TKM/core/src/LOVE20TokenFactory.sol（创建职责已并入 Launch）
保留：完整 ERC20 逻辑、代币树结构
```

---

## 9. Proposal Target（修改）

### 🔄 关键变化

#### 零地址 Target 禁止
- **旧**：允许零地址（激励自动销毁）
- **新**：Target 必须是非零 EOA 或合约
- **理由**：避免遗忘填写导致激励永久丢失

#### Target 模式扩展
- **新增**：`NoCallback` 和 `Callback` 两种模式
- **设计意图**：支持未来业务扩展框架（如 ActionTarget）

### 📍 实现参考
```
旧代码：LOVE20TKM/core（隐式处理）
新增：显式 targetMode 枚举
```

---

## 删除组件

| 组件 | 原位置 | 删除原因 |
|------|--------|----------|
| GroupDefaults | LOVE20TKM/group | BSC 不迁移默认配置 |
| SL/ST Token | LOVE20TKM/core/src/LOVE20Stake.sol | 去凭证化，状态直接归 memberId |
| 地址主体接口 | 所有合约 | 统一使用 memberId |

---

## 实现检查清单

实现时必须确认：

- [ ] 所有业务主体使用 `memberId`，不使用 `address` 作为长期键
- [ ] Stake 不产生 SL/ST ERC20 代币
- [ ] Phase 不包含业务阶段名称（Vote/Join/Verify/Mint）
- [ ] 治理激励拆分为 50% 投票激励 + 50% 加速激励
- [ ] 加速激励有 2 倍上限，溢出部分销毁
- [ ] 发射次数按 `tokenAddress + memberId` 记录
- [ ] 发射次数支持部分融合转移
- [ ] MemberNFT 名称最大长度 32 bytes
- [ ] Proposal Target 不允许零地址
- [ ] 首个代币通过 Airdrop 合约分发

---

## 验收边界

核心验收场景见 `core/09-testing.md` 和组织级 `docs/acceptance.md`。关键变更的专项验收：

1. **MemberNFT 转移**：质押、投票、发射次数的历史不回写，当前未铸造权益由新持有人继续操作
2. **统一解锁**：流动性质押和加速质押必须同时申请、同时等待、同时提取
3. **质押融合**：向非调用者持有的目标 NFT 融合，只增加不减少目标状态
4. **发射次数融合**：部分融合、向非调用者持有的目标 NFT 转移
5. **治理激励拆分**：三段返回值（voteReward, boostReward, burnReward）
6. **批量多轮铸造**：原子性，任一 Round 失败则整笔回滚
7. **Phase 动态校准**：由初始化的 `adjustThreshold` 控制，超过阈值时计算新 phaseBlocks
