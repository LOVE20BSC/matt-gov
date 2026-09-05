# Stake 规格

本文档定义 Stake 合约规格。

---

## 1. 核心变更

- **去凭证化**：不再产生 SL/ST ERC20 代币，状态直接存储在 Stake 合约
- **按 memberId 归属**：质押状态按 `tokenAddress + memberId` 隔离
- **统一解锁**：流动性质押和加速质押必须同时申请、同时等待、同时提取

---

## 2. 状态变量

### 2.1 按代币和成员隔离的质押状态

```solidity
mapping(address tokenAddress => mapping(uint256 memberId => StakeData)) stakes;

struct StakeData {
    uint256 lpShares;                    // LP 质押份额
    uint256 boostShares;                 // 加速质押份额（原 ST）
    uint256 promisedWaitingPhases;       // 承诺解锁期（Phase 数量）
    uint256 unlockRequestPhase;          // 解锁申请时的 Phase（0 = 未申请，≥1 = 已申请）
}
```

### 2.2 按代币汇总的全局状态

```solidity
mapping(address tokenAddress => TokenStakeGlobals) globals;

struct TokenStakeGlobals {
    uint256 totalLpShares;               // 全局 LP 份额总量
    uint256 withdrawableLp;              // 上次结算后的可提取 LP 数量（基准值）
    uint256 feeLp;                       // 累积的手续费 LP 数量
    uint256 sqrtKOfLp;                   // 上次记录的 sqrt(k) 基准
    uint256 totalBoostShares;            // 全局加速质押份额总量
}
```

### 2.3 按代币、轮次、成员记录的加速质押累计值

```solidity
// tokenAddress => round => memberId => cumulatedBoostShares
mapping(address => mapping(uint256 => mapping(uint256 => uint256))) cumulatedBoostShares;
```

### 2.4 状态变量说明

- `withdrawableLp`：每次质押/提取时更新的可提取 LP 基准，用于下次份额计算
- `feeLp`：累积的手续费 LP，不参与份额计算
- `sqrtKOfLp`：基于合约持有 LP 在 Pair 中占比计算的 sqrt(k) 值，用于判断手续费是否累积
- `cumulatedBoostShares`：按轮次累计的加速质押份额，用于投票激励计算（详见第 4 节）

---

## 3. 保留逻辑（引用旧代码）

### 3.1 流动性质押流程

**参考**：`LOVE20TKM/core/src/LOVE20Stake.sol` 120-134 行

用户质押时提供双币（代币 + 父币），Stake 合约将双币转入并调用 Router 添加 LP，获得的 LP token 用于计算 LP 份额。提取时，Stake 合约移除 LP 并将双币返还用户。

### 3.2 LP 份额计算

**参考**：`LOVE20TKM/core/src/LOVE20SLToken.sol` 79-83 行

```text
sharesMinted = totalLpShares == 0
    ? lpMinted
    : totalLpShares × lpMinted / withdrawableLp
```

### 3.3 手续费结算

**参考**：`LOVE20TKM/core/src/LOVE20SLToken.sol` 256-289 行（sqrt(k) 方法）

#### 计算流程

1. 计算当前 sqrtK：`currentSqrtKOfLp = sqrt(reserve0 × reserve1) × totalLp / pairTotalSupply`
2. 如果 `currentSqrtKOfLp > previousSqrtKOfLp`（手续费累积）：
   - `newWithdrawableLp = previousWithdrawableLp × previousSqrtKOfLp / currentSqrtKOfLp`
   - `newFeeLp = totalLp - newWithdrawableLp`
3. 如果 `currentSqrtKOfLp ≤ previousSqrtKOfLp`（未累积手续费或异常情况），跳过手续费结算
4. 更新 `withdrawableLp`、`feeLp` 和 `sqrtKOfLp`

#### 边界保护

- `currentSqrtKOfLp = 0` 或 `pairTotalSupply = 0` 时跳过手续费结算（异常情况）
- `currentSqrtKOfLp ≤ previousSqrtKOfLp` 时跳过手续费结算（未累积或 LP 被移除导致的下降）

#### 手续费结算效果

- 手续费累积 → `withdrawableLp` 下降 → 每份额对应的可提取 LP 减少
- 新质押者用相同 LP 获得更多份额（通货膨胀机制）
- 已质押者的份额占比被稀释
- LP 交易产生的手续费增量不归旧质押者，归协议所有
- 旧质押者取回的双币数量与质押时提供的双币数量相同（无池价格变化时）

#### 手续费结算示例

**说明**：以下示例使用简化数值和向下取整，实际实现遵循 Solidity 整数除法规则。

**初始状态**：
- A 质押 100 LP → 获得 100 份额
- `withdrawableLp = 100`, `sqrtKOfLp = sqrt(k1)`, `totalLpShares = 100`

**Pair 累积手续费**：
- Reserve 增长，`sqrt(k2) = 1.05 × sqrt(k1)`（增长 5%）
- 合约仍持有 100 LP，但 LP 价值增加了（包含手续费增量）

**B 质押 100 LP**：
1. 手续费结算：
   - `newWithdrawableLp = 100 × sqrt(k1) / sqrt(k2) = 100 / 1.05 ≈ 95.24`
   - `newFeeLp = 100 - 95.24 = 4.76`
   - 更新：`withdrawableLp = 95.24`, `feeLp = 4.76`, `sqrtKOfLp = sqrt(k2)`

2. B 铸造份额：
   - `sharesMinted = 100 × 100 / 95.24 ≈ 105`
   - B 获得 **105 份额**（比 A 多 5%）
   - 更新：`withdrawableLp = 95.24 + 100 = 195.24`, `totalLpShares = 205`

3. 最终状态：
   - 总 LP：200（包含手续费增量），可提取 LP：195.24，协议 feeLp：4.76
   - A 占 100/205 ≈ 48.78%，可提 195.24 × 100 / 205 ≈ 95.24 LP（对应质押时的双币数量）
   - B 占 105/205 ≈ 51.22%，可提 195.24 × 105 / 205 ≈ 100 LP（对应质押时的双币数量）
   - 协议累积 `feeLp = 4.76`（对应手续费增量）

**关键**：通货膨胀机制确保新旧质押者都能取回质押时提供的双币数量（无池价格变化时），手续费增量归协议所有。

### 3.4 治理票公式

**保留旧版**：

```text
govVotes = lpShares × promisedWaitingPhases
```

### 3.5 治理票计算时机

**参考**：`LOVE20TKM/core/src/LOVE20Stake.sol` 65-88 行

- 治理票通过 `validGovVotes` 函数实时计算，不快照
- 投票时，Vote 合约调用 `Stake.validGovVotes(tokenAddress, memberId)` 读取当前有效治理票
- 每次质押追加、解锁申请都会改变治理票（通过改变 `lpShares` 或 `promisedWaitingPhases`）
- BSC 版保留旧版的 `validGovVotes` 逻辑，只是参数从 `address` 改为 `memberId`

---

## 4. 加速质押（保留旧版机制）

加速质押在旧版和新版都参与治理激励的加速部分分配（见 `06-mint.md` 第 3 节）。

加速质押不产生治理投票权，只参与加速激励分配。流动性质押产生治理投票权，参与投票激励分配。两类质押可以同时存在，共享解锁生命周期。

### 4.1 加速质押记账

**保留旧版逻辑**：参考 `LOVE20TKM/core/src/LOVE20Stake.sol` 的 `_cumulatedTokenAmountByAccount` 机制

旧版按 round 维护每个 account 的累计加速质押代币数量（`_cumulatedTokenAmountByAccount[tokenAddress][round][account]`），新版改为按 memberId 维护累计加速质押份额（`cumulatedBoostShares[tokenAddress][round][memberId]`）。记录时机和逻辑保持一致：
- 进入新 round 时，复制上一轮的累计值作为本轮起点
- 加速质押增减时，直接更新当前 round 的累计值
- 铸造加速激励时读取当前 round 的累计值
- 没有加速质押变动时，累计值自然继承上一轮
- 解锁申请后不能再追加质押，累计值不再更新

### 4.2 累计值读取逻辑

**保留旧版**：

- 读取指定 Round 的累计值时，如果该 Round 未记录（mapping 默认值为 0），则查找该 Round **之前最近的有记录的 Round**，返回那个 Round 的累计值
- 这确保了解锁申请后，后续所有 Round 都能读取到**解锁申请时的累计值**
- 参考实现：`LOVE20TKM/core/src/LOVE20Stake.sol` 335-359 行的 `cumulatedTokenAmountByAccount` 函数

### 4.3 累计值继承示例

**无手续费场景**：

- **Round 4**：成员 A 提供 100 代币 + 100 WBNB 添加 LP（无手续费时获得 100 LP 份额），同时加速质押 50 代币
  - Round 4 累计加速质押 = 50 代币
- **Round 5 开始**：A 追加提供 50 代币 + 50 WBNB 添加 LP（无手续费时获得 50 LP 份额），同时加速质押 30 代币，承诺解锁期保持或增加
  - 首次操作时，复制 Round 4 累计值：50 代币
  - 追加后更新 Round 5 累计值：80 代币
- **Round 5 投票**：A 投票后，Vote 合约累加 A 的加速质押份额（80 代币）到 `stakedAmountOfVoters[tokenAddress][5]`
- **Round 6 开始**：A 无操作，Round 6 累计值自然继承 Round 5 的 80 代币
- **Round 7**：A 申请解锁，解锁申请后不能再追加质押，Round 7 的累计值保持为 80 代币
- **Round 8**：A 仍在解锁期内，无法追加质押
  - 读取 Round 8 累计值：未记录，查找最近的有记录 Round（Round 5），返回 80 代币
- **Round 9**：读取 Round 9 累计值，同样返回 80 代币（继承机制）

---

## 5. 统一解锁和提取

### 5.1 流程

**新设计**：

1. 当前 MemberNFT 持有人发起统一解锁申请
2. 申请立即清零治理票，禁止追加质押和融合
3. 申请绑定 `memberId`、申请时 Phase 和解锁期；MemberNFT 转移不重置倒计时
4. 经过 `promisedWaitingPhases` 个底层 Phase 后，当前持有人一次性提取 LP 对应的两种资产和加速质押代币
5. 解锁期结束后，当前 MemberNFT 持有人（可能已不是申请时的持有人）有权提取全部资产

### 5.2 解锁状态查询

- Stake 合约提供查询接口，返回解锁申请状态（申请时 Phase、承诺解锁期、是否可提取）
- MemberNFT 持有人或潜在买家可以查询任意 `memberId` 在任意代币的解锁状态
- MemberNFT 转移是 ERC721 标准行为，Stake 合约不限制解锁中的 NFT 转移

---

## 6. 融合（新增）

### 6.1 设计意图

质押融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让这些资产可以通过 MemberNFT 作为载体进行场外交易。

### 6.2 约束

- 源、目标 MemberNFT 必须不同且都已存在
- 调用者只需控制源 MemberNFT，不要求控制目标 MemberNFT
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 来源质押必须未投票且未解锁
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

### 6.3 禁止融合的情况

- 任一方存在待处理解锁申请（`unlockRequestPhase != 0`）
- 当前治理 Round 中源 MemberNFT 已经发生非零投票
- 目标质押的承诺解锁期（`promisedWaitingPhases`）小于源质押的承诺解锁期

### 6.4 承诺解锁期约束

- 如果目标没有质押（`promisedWaitingPhases = 0`），融合后目标使用源的承诺解锁期
- 如果目标有质押但解锁期更短，拒绝融合（防止通过融合缩短承诺解锁期，绕过锁定约束）
- 如果目标解锁期 ≥ 源解锁期，允许融合，**融合后目标保持原有的承诺解锁期**（取两者最大值，由于前置条件保证 `target >= source`，实际就是保持目标的值）

### 6.5 禁止融合的设计理由

#### 1. 源已投票禁止融合 → 防止重复计票

**问题场景**：
- 源 NFT 有 100 LP 份额，投票 100 票给 Proposal A
- 源融合到目标 NFT
- 目标 NFT 现在有源的 100 LP 份额，再投票又投出 100 票
- **结果**：同一份质押资产产生了两次投票（源的历史投票 + 目标的新投票），重复计票

#### 2. 解锁申请中禁止融合 → 防止治理权复活

**问题场景**：
- 源 NFT 有 100 LP 份额，申请解锁（治理票立即清零）
- 源融合到目标 NFT
- 目标 NFT 获得源的 100 LP 份额，重新产生治理票
- **结果**：已解锁（治理票为 0）的质押通过融合"复活"了治理权，绕过解锁限制

#### 3. 为什么目标已投票不影响融合

目标已投票后接收融合不会重复计票：
- 目标的历史投票基于融合前的份额（如 50 LP → 50 票）
- 源的份额转入（如 100 LP）后，目标总份额变为 150 LP
- 如果目标后续再投票，按投票增量机制：增量 = 150 - 50 = 100 票
- 增量正好对应源转入的份额，**不重复计票**

### 6.6 用户影响

- 源 MemberNFT 在本轮投票前可自由融合
- 源 MemberNFT 投票后需等到下一轮才能融合
- 目标 MemberNFT 是否投票不影响融合
- 任一方有解锁申请时，必须等待解锁期结束并完成提取后才能融合

### 6.7 融合接口

```solidity
function mergeStake(
    address tokenAddress,
    uint256 sourceMemberId,
    uint256 targetMemberId
) external
```

**参数**：
- `tokenAddress`：要融合的代币地址
- `sourceMemberId`：来源 MemberNFT ID（调用者必须是其持有人）
- `targetMemberId`：目标 MemberNFT ID（必须存在，但调用者不需要持有）

**效果**：
- 将 `sourceMemberId` 在该代币的全部质押状态转移到 `targetMemberId`
- LP 质押份额、加速质押份额、承诺解锁期合并到目标
- 源质押清零

**失败条件**：
- 调用者不是 `sourceMemberId` 的持有人
- `targetMemberId` 不存在
- 任一方存在待处理解锁申请（`unlockRequestPhase != 0`）
- 当前治理 Round 中源 MemberNFT 已投票
- 目标的 `promisedWaitingPhases` 小于源的 `promisedWaitingPhases`

### 6.8 融合后的状态等价性

- 融合后的质押状态与原始质押流程等价
- 提取时，Stake 合约按目标 MemberNFT 的份额比例移除 LP，正常返还双币
- 加速质押代币也正常返还

源的 LP Shares 和加速质押单向并入目标，不能修改或取走目标原有资产。
