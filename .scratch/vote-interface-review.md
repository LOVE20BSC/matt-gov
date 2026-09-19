# Vote 接口设计 Review

## 一、枚举改分页

### 当前问题

`IVote.sol` 保留了旧的枚举模式，但这些集合都是**无界的**（由投票行为决定）：

```solidity
// 当前接口（旧枚举模式）
function accountVotedProposalIdsCount(address tokenAddress, uint256 round, uint256 memberId) external view returns (uint256);
function accountVotedProposalIdsAtIndex(address tokenAddress, uint256 round, uint256 memberId, uint256 index) external view returns (uint256 proposalId);

function accountsByProposalIdCount(address tokenAddress, uint256 round, uint256 proposalId) external view returns (uint256);
function accountsByProposalIdAtIndex(address tokenAddress, uint256 round, uint256 proposalId, uint256 index) external view returns (uint256 memberId);

function votedProposalIdsCount(address tokenAddress, uint256 round) external view returns (uint256);
function votedProposalIdsAtIndex(address tokenAddress, uint256 round, uint256 index) external view returns (uint256 proposalId);
```

### 迁移规范要求

`migration-standards.md` 第 75 行：

> **只有有界集合才提供全量读取。** 规模由常量或固定配置决定（社区总数、管理组名单）才算有界；由外部输入决定（成员数、提案数、推举记录数、消息数）一律按无界处理，只给分页

Submit 已按此规范改为分页（见 `CHANGES-core.md` 第 150-163 行）。

### 建议方案

#### 1. 成员维度：按 memberId 查询该成员在某轮投过的提案

**用户问题 1**："按 member 取全量用 votedProposalIdsByMemberId？"

**回答**：该成员某轮投过的提案数量理论无上限（可以投很多提案），应使用**分页**：

```solidity
// 建议：分页查询某成员在某轮投过的提案ID列表
function votedProposalIds(
    address tokenAddress,
    uint256 round,
    uint256 memberId,
    uint256 offset,
    uint256 limit,
    bool reverse
) external view returns (uint256[] memory proposalIdList, uint256 totalCount);
```

**命名依据**：
- 载荷：`proposalIds` 返回 ID 数组（轻量标识）
- 筛选条件：`(tokenAddress, round, memberId)` 是作用域键，定位到具体记录，不进名字
- `votedProposalIds` 表示"已投票的提案ID列表"
- 分页不进名字，由参数 `(offset, limit, reverse)` 表意

#### 2. 提案维度：按 proposalId 查询哪些成员投了该提案

某提案的投票者数量也是无界的，应使用**分页**：

```solidity
// 建议：分页查询某提案在某轮的投票者ID列表
function voterIds(
    address tokenAddress,
    uint256 round,
    uint256 proposalId,
    uint256 offset,
    uint256 limit,
    bool reverse
) external view returns (uint256[] memory memberIdList, uint256 totalCount);
```

**命名依据**：
- 载荷：`voterIds` 返回投票者的 memberId 数组
- 筛选条件：`(tokenAddress, round, proposalId)` 定位到该提案
- 与 `votedProposalIds` 对称：一个查"成员投了哪些提案"，一个查"提案被哪些成员投"

#### 3. 全局维度：某轮所有被投过票的提案

**用户问题 2**："当轮全部改为分页 votedProposalIds？"

**回答**：是的，全局维度也应该分页，但为避免与按成员查询的函数重名，建议命名为 `votedProposalIdsGlobal` 或直接在参数层面区分（不传 memberId）。

**方案 B**：独立命名

```solidity
// 全局维度
function votedProposalIds(
    address tokenAddress,
    uint256 round,
    uint256 offset,
    uint256 limit,
    bool reverse
) external view returns (uint256[] memory proposalIdList, uint256 totalCount);

// 成员维度（加 ByMemberId 后缀）
function votedProposalIdsByMemberId(
    address tokenAddress,
    uint256 round,
    uint256 memberId,
    uint256 offset,
    uint256 limit,
    bool reverse
) external view returns (uint256[] memory proposalIdList, uint256 totalCount);
```

**推荐并已采用**：方案 B（独立命名），与 Submit 的 `proposalIdsByAuthor` 模式一致，更清晰。

### 保留的批量查询函数

以下函数保留，因为它们是**按 ID 批量查询详情**，符合规范第 111-116 行：

```solidity
// 保留：按成员ID查询其投票详情（proposalIds + votes）
function votesNumsByMemberId(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256[] memory proposalIds, uint256[] memory votes);

// 保留：按指定proposalIds批量查询某成员的投票数
function votesNumsByMemberIdByProposalIds(
    address tokenAddress,
    uint256 round,
    uint256 memberId,
    uint256[] calldata proposalIds
) external view returns (uint256[] memory votes);
```

**命名检查**：
- `votesNumsByMemberId` ✓ 复数 + `ByMemberId` 筛选条件
- `votesNumsByMemberIdByProposalIds` ✓ 复数 + `ByMemberId` + `ByProposalIds`（按显式ID数组批量）

---

## 二、事件命名

### 当前设计

```solidity
event VoteCast(
    address indexed tokenAddress,
    uint256 round,
    uint256 indexed voterId,
    uint256 indexed proposalId,
    uint256 votes
);
```

### 问题

旧事件名为 `Vote`，新改为 `VoteCast`。根据 `migration-standards.md` 第 62 行：

> 保留旧命名；只有协议语义明确变化时才改名

从 `address voter` 改为 `uint256 voterId` 只是类型变化，语义未变。

### 其他事件命名模式

查看现有接口事件：
- `ProposalCreated` - 过去分词
- `ProposalSubmitted` - 过去分词
- `StakeMerged` - 过去分词
- `PhaseSynchronized` - 过去分词

**用户建议**："事件是不是应该改为 Voted"

### 建议

两种方案：

**方案 A**：保持旧名 `Vote`（名词形式）
```solidity
event Vote(
    address indexed tokenAddress,
    uint256 round,
    uint256 indexed voterId,
    uint256 indexed proposalId,
    uint256 votes
);
```
- 优点：符合"保留旧命名"原则
- 缺点：与其他过去分词事件风格不一致

**方案 B**：改为 `Voted`（过去分词）
```solidity
event Voted(
    address indexed tokenAddress,
    uint256 round,
    uint256 indexed voterId,
    uint256 indexed proposalId,
    uint256 votes
);
```
- 优点：与 `ProposalCreated`、`ProposalSubmitted`、`StakeMerged` 等命名风格统一
- 缺点：改变了旧命名

**推荐**：**方案 B（`Voted`）**，理由：
1. BSC 是新代际协议，事件命名统一性优先
2. `VoteCast` 比旧名 `Vote` 已经改了，说明可以改
3. 过去分词更符合"事件已发生"的语义

---

## 三、错误接口拆分

### 当前设计

Vote 的错误直接声明在 `IVote` 主接口中。

### Submit 的做法

Submit 拆分了 `ISubmitErrors` 子接口（`ISubmit.sol` 第 30-43 行）：

```solidity
interface ISubmitErrors {
    error AlreadyInitialized();
    error InvalidAddress();
    // ...
}

interface ISubmit is ISubmitErrors, ISubmitEvents {
    // ...
}
```

### 其他合约的做法

- `IStake` - 拆分了 `IStakeErrors` 和 `IStakeEvents`
- `IPhase` - 拆分了 `IPhaseErrors` 和 `IPhaseEvents`

### 建议

**拆分为独立子接口**，保持一致性：

```solidity
interface IVoteErrors {
    error AlreadyInitialized();
    error InvalidTargetDataLength();
    error ProposalNotSubmitted();
    error CannotVote();
    error NotEnoughVotesLeft();
    error VotesMustBeGreaterThanZero();
}

interface IVoteEvents {
    event Voted(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed voterId,
        uint256 indexed proposalId,
        uint256 votes
    );
}

interface IVote is IVoteErrors, IVoteEvents {
    // ...
}
```

---

## 四、命名规范检查

### 批量查询函数

当前：
```solidity
function votesNumsByMemberId(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256[] memory proposalIds, uint256[] memory votes);

function votesNumsByMemberIdByProposalIds(
    address tokenAddress,
    uint256 round,
    uint256 memberId,
    uint256[] calldata proposalIds
) external view returns (uint256[] memory votes);
```

**规范检查**（`migration-standards.md` 第 88-99 行）：

| 返回值/条件 | 记号 | 当前命名 | 符合？ |
|---|---|---|---|
| 记录数组 | `<复数>Infos` | `votesNums` | ⚠️ 应为 `votesInfos` 或简化 |
| 按键筛选 | `By<key>` | `ByMemberId` | ✓ |
| 显式 ID 数组 | `ByIds` | `ByProposalIds` | ✓ |

**问题**：`votesNums` 这个命名有歧义：
- `Nums` 通常指"数量"，但这里返回的是数组
- 应该用 `Infos` 后缀表示返回记录数组

### 命名决策

**保持 `votesNums` 前缀**（用户确认）：

```solidity
// 某成员的完整投票记录
function votesNumsByMemberId(address tokenAddress, uint256 round, uint256 memberId)
    external view returns (uint256[] memory proposalIds, uint256[] memory votes);

// 按指定proposalIds批量查询
function votesNumsByMemberIdByProposalIds(
    address tokenAddress,
    uint256 round,
    uint256 memberId,
    uint256[] calldata proposalIds
) external view returns (uint256[] memory votes);
```

**理由**：保持与旧接口命名的连续性。

---

## 五、完整建议接口

```solidity
// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IVoteErrors {
    error AlreadyInitialized();
    error InvalidTargetDataLength();
    error ProposalNotSubmitted();
    error CannotVote();
    error NotEnoughVotesLeft();
    error VotesMustBeGreaterThanZero();
    error InvalidAddress();
    error NotMemberOwner(uint256 memberId);
    error InvalidMemberId();
}

interface IVoteEvents {
    event Voted(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed voterId,
        uint256 indexed proposalId,
        uint256 votes
    );
}

interface IVote is IVoteErrors, IVoteEvents {
    // === 配置与初始化 ===
    function initialized() external view returns (bool);
    function stakeAddress() external view returns (address);
    function submitAddress() external view returns (address);
    function phaseAddress() external view returns (address);
    function memberNFTAddress() external view returns (address);
    function mintAddress() external view returns (address);
    
    function init(
        address phaseAddress,
        address stakeAddress,
        address submitAddress,
        address memberNFTAddress,
        address mintAddress
    ) external;

    // === 投票操作 ===
    function vote(
        address tokenAddress,
        uint256 memberId,
        uint256[] calldata proposalIds,
        uint256[] calldata votes,
        bytes[][] calldata targetData
    ) external;

    // === Round 信息 ===
    function currentRound() external view returns (uint256);
    function isRoundEnded(uint256 round) external view returns (bool);

    // === 投票资格与限额 ===
    function canVote(address tokenAddress, uint256 memberId) external view returns (bool);
    function maxVotesNum(address tokenAddress, uint256 memberId) external view returns (uint256);

    // === 票数查询 ===
    // 全局票数
    function votesNum(address tokenAddress, uint256 round) external view returns (uint256);
    
    // 按提案查票数
    function votesNumByProposalId(address tokenAddress, uint256 round, uint256 proposalId)
        external view returns (uint256);
    
    // 按成员查累计票数
    function votesNumByMemberId(address tokenAddress, uint256 round, uint256 memberId)
        external view returns (uint256);
    
    // 按成员+提案查票数
    function votesNumByMemberIdByProposalId(
        address tokenAddress,
        uint256 round,
        uint256 memberId,
        uint256 proposalId
    ) external view returns (uint256);

    // === 投票记录枚举（改为分页）===
    // 提案是否被投过票
    function isProposalIdVoted(address tokenAddress, uint256 round, uint256 proposalId)
        external view returns (bool);

    // 全局：某轮所有被投票的提案（分页）
    function votedProposalIds(
        address tokenAddress,
        uint256 round,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) external view returns (uint256[] memory proposalIdList, uint256 totalCount);

    // 成员维度：某成员某轮投过的提案（分页）
    function votedProposalIds(
        address tokenAddress,
        uint256 round,
        uint256 memberId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) external view returns (uint256[] memory proposalIdList, uint256 totalCount);

    // 提案维度：某提案的投票者列表（分页）
    function voterIds(
        address tokenAddress,
        uint256 round,
        uint256 proposalId,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) external view returns (uint256[] memory memberIdList, uint256 totalCount);

    // === 批量查询投票详情 ===
    // 某成员的完整投票记录（proposalIds + votes）
    function votesNumsByMemberId(address tokenAddress, uint256 round, uint256 memberId)
        external view returns (uint256[] memory proposalIds, uint256[] memory votes);

    // 按指定 proposalIds 批量查询某成员的投票数
    function votesNumsByMemberIdByProposalIds(
        address tokenAddress,
        uint256 round,
        uint256 memberId,
        uint256[] calldata proposalIds
    ) external view returns (uint256[] memory votes);

    // === 加速快照（Mint 使用）===
    function stakedAmountOfVotersByMemberId(
        address tokenAddress,
        uint256 round,
        uint256 memberId
    ) external view returns (uint256);
    
    function stakedAmountOfVoters(address tokenAddress, uint256 round)
        external view returns (uint256);
}
```

---

## 六、主要变更总结

| 类别 | 旧设计 | 新设计 | 原因 |
|------|--------|--------|------|
| **枚举 → 分页** | `*Count()` + `*AtIndex()` | `*(offset, limit, reverse) returns (list, totalCount)` | 无界集合，按迁移规范改分页 |
| **事件命名** | `Vote` | `Voted` | 与其他事件过去分词风格统一 |
| **错误拆分** | 直接在主接口 | `IVoteErrors` 子接口 | 与 Stake/Submit/Phase 保持一致 |
| **Account → MemberId** | `votesNumByAccount` | `votesNumByMemberId` | 统一使用 memberId 术语 |
| **Account → MemberId** | `votesNumByAccountByProposalId` | `votesNumByMemberIdByProposalId` | 统一使用 memberId 术语 |
| **新增函数** | 无 | `voterIds()` 分页 | 按提案查投票者，对称设计 |
| **重载** | 无 | `votedProposalIds(...)` 两个重载 | 全局 vs 按成员，参数数量区分 |

---

## 七、与旧接口的 ABI 对账

### 删除的函数（枚举 → 分页）

- `accountVotedProposalIdsCount()`
- `accountVotedProposalIdsAtIndex()`
- `accountsByProposalIdCount()`
- `accountsByProposalIdAtIndex()`
- `votedProposalIdsCount()`
- `votedProposalIdsAtIndex()`

### 新增的函数

- `initialized()`
- `phaseAddress()`
- `memberNFTAddress()`
- `mintAddress()`
- `votedProposalIds(tokenAddress, round, offset, limit, reverse)` - 全局分页
- `votedProposalIds(tokenAddress, round, memberId, offset, limit, reverse)` - 成员分页
- `voterIds(tokenAddress, round, proposalId, offset, limit, reverse)` - 投票者分页

### 改名的函数

- `votesNumByAccount` → `votesNumByMemberId`
- `votesNumByAccountByActionIds` → `votesNumByMemberIdByProposalIds`

### 改名的错误

- `ActionNotSubmitted` → `ProposalNotSubmitted`

### 新增的错误

- `InvalidAddress()`
- `NotMemberOwner(uint256 memberId)`
- `InvalidMemberId()`

### 改名的事件

- `Vote` → `Voted`

### 事件字段变更

- `address indexed voter` → `uint256 indexed voterId`
- `uint256 indexed actionId` → `uint256 indexed proposalId`

---

## 八、待确认问题

1. **函数重载**：`votedProposalIds` 的两个重载（全局 vs 按成员）在 Solidity 和 ABI 中是否会有问题？
   - Solidity 支持重载，selector 不同
   - 但调用时需要明确参数数量，不会混淆

2. **错误完整性**：是否需要新增 `InvalidMemberId` 和 `NotMemberOwner` 错误？
   - 与 Stake/Submit 保持一致
   - 精准报错

---

## 九、最终确认的设计

✅ **已确认**：
1. 枚举改分页 - 使用 `(offset, limit, reverse)` 模式
2. 事件改名为 `Voted` - 与其他事件保持过去分词风格
3. 错误拆分为 `IVoteErrors` 子接口
4. `Account` 改为 `MemberId` - 所有函数名统一使用 `MemberId` 术语
5. **保持** `votesNums` 前缀 - 不简化为 `votes`

---

## 下一步

确认以上设计后，进入第二步：**旧代码基线提交**。
