# Core 迁移变更清单

本文档列出 BSC Core 相对于 LOVE20TKM 旧协议的所有变更。保留项直接引用旧代码位置，避免重复描述。

## 迁移原则

1. **身份统一**：所有业务主体从钱包地址改为 MemberNFT 的 `memberId`
2. **去凭证化**：质押不再产生 SL/ST ERC20 代币，状态直接归 `memberId`
3. **时间灵活**：引入无语义的 Phase 时间线，替代固定 4 阶段映射
4. **独立协议**：BSC 是新协议代际，不兼容旧合约存储、地址和历史状态

---

## 组件迁移矩阵

| 组件 | 状态 | 旧位置 | 新位置 | 核心变化 |
|------|------|--------|--------|----------|
| MemberNFT | 合并新增 | LOVE20TKM/group: LOVE20Group.sol | core/MemberNFT.sol | 名称 64→32 bytes，铸造费用公式保留 |
| Phase | 全新 | - | core/Phase.sol | 替代固定阶段，动态校准 |
| Stake | 重构 | LOVE20TKM/core: Stake.sol | core/Stake.sol | 去 SL/ST 凭证，按 memberId 归属 |
| Submit | 保留 | LOVE20TKM/core: Submit.sol | core/Submit.sol | 主体改为 memberId |
| Vote | 保留 | LOVE20TKM/core: Vote.sol | core/Vote.sol | 主体改为 memberId |
| Mint | 修改 | LOVE20TKM/core: Mint.sol | core/Mint.sol | 治理激励公式调整 |
| LOVE20Token | 保留 | LOVE20TKM/core: LOVE20Token.sol | core/LOVE20Token.sol | ERC20 基础不变 |
| TokenFactory | 保留 | LOVE20TKM/core: TokenFactory.sol | core/TokenFactory.sol | 创建流程不变 |
| Launch | 修改 | LOVE20TKM/core: Launch.sol | core/Launch.sol | 发射次数按 memberId 记录 |

---

## 1. MemberNFT（合并新增）

### 来源
- 合并旧 `LOVE20TKM/group` 仓库的 `LOVE20Group.sol`
- 升级为协议唯一身份 NFT

### ✅ 保留逻辑
- **名称校验**：参考 `LOVE20TKM/group/LOVE20Group.sol` 的 UTF-8 校验、ASCII 大小写不敏感、禁止字符类型
- **铸造费用公式**：保留短名称稀缺性公式（baseCost × multiplier ^ (bytesThreshold - byteLength)）

### 🔄 关键变化
- **名称长度**：`64 bytes` → `32 bytes`（避免与钱包地址混淆）
- **合约名**：`LOVE20Group` → `MemberNFT`
- **ERC721 名称**：`LOVE20 Member NFT`，符号 `Member`
- **用途扩展**：从群聊身份扩展为协议全局身份（质押、投票、发射次数）

### ➕ 新增能力
- 统一承载质押、投票、发射次数等所有业务状态
- MemberNFT 转移只改变控制者，不改变历史状态

### 📍 实现参考
```
旧代码：LOVE20TKM/group/contracts/LOVE20Group.sol
关注：名称校验（134-198行）、铸造费用（78-95行）
```

---

## 2. Phase（全新设计）

### 替代对象
- 旧版协议中硬编码的 4 阶段时间线（Vote、Join、Verify、Mint）

### 核心设计
- **无业务语义**：Phase 只维护连续时间片，不命名具体阶段
- **动态校准**：根据实际区块时间自动调整 `phaseBlocks`，使每个 Phase 接近目标自然天数
- **按需映射**：上层业务（Core 治理、Action 行动）自行映射 Phase 到业务轮次

### 关键特性
- 第一个 Phase 编号为 `1`
- 支持空 Phase（无交互时不逐个写入）
- `sync()` 任何地址可调用，用于校准时间
- Submit 每轮首个推举自动调用一次 `sync()`

### 为什么新增
- 不同行动类型需要不同阶段数（LP 3阶段，链群 4阶段）
- 避免硬编码阶段映射，提升协议灵活性

---

## 3. Stake（重构）

### ✅ 保留逻辑
- **LP 份额计算**：参考 `LOVE20TKM/core/Stake.sol` 154-184 行
- **手续费结算公式**：参考同文件 248-276 行（sqrt(k) 方法）
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
旧代码：LOVE20TKM/core/contracts/Stake.sol
保留公式：LP份额（154-184行）、手续费（248-276行）
删除：SL/ST铸造逻辑（移除 ERC20 依赖）
```

---

## 4. Submit（保留，主体变更）

### ✅ 保留逻辑
- Proposal 创建和推举流程：参考 `LOVE20TKM/core/Submit.sol`
- 推举门槛计算（SUBMIT_MIN_RATIO）
- 每轮首个推举触发 Phase 同步

### 🔄 关键变化
- **主体身份**：`submitterAddress` → `submitterId (memberId)`
- **权限校验**：`msg.sender` → `MemberNFT.ownerOf(submitterId) == msg.sender`

### 📍 实现参考
```
旧代码：LOVE20TKM/core/contracts/Submit.sol
保留：推举门槛、去重逻辑
修改：所有 address 参数改为 uint256 memberId
```

---

## 5. Vote（保留，主体变更）

### ✅ 保留逻辑
- 投票流程和票数记录：参考 `LOVE20TKM/core/Vote.sol`
- 投票增量机制（支持同一 Round 多次投票）
- Proposal Target 回调机制

### 🔄 关键变化
- **主体身份**：`voterAddress` → `voterId (memberId)`
- **权限校验**：`msg.sender` → `MemberNFT.ownerOf(voterId) == msg.sender`

### 📍 实现参考
```
旧代码：LOVE20TKM/core/contracts/Vote.sol
保留：投票记录结构、增量逻辑
修改：所有 address 参数改为 uint256 memberId
```

---

## 6. Mint（修改）

### ✅ 保留逻辑
- 轮次激励池准备：参考 `LOVE20TKM/core/Mint.sol`
- Proposal 激励门槛和分配公式

### 🔄 关键变化

#### 治理激励拆分（重要变更）
- **旧**：验证激励（一个池，对应旧版术语）
- **新**：投票激励（50%）+ 加速激励（50%）

**投票激励**：
```solidity
// 常量：GOV_VOTE_SHARE = 0.5e18
voteReward = govReward * GOV_VOTE_SHARE / 1e18 * memberVotes / totalVotes
```

**加速激励**（新增）：
```solidity
// 常量：GOV_BOOST_SHARE = 0.5e18
theoreticalBoost = govReward * GOV_BOOST_SHARE / 1e18 * memberBoost / totalBoost
boostReward = min(theoreticalBoost, voteReward * 2)  // 基于投票激励的2倍上限
burnReward = theoreticalBoost - boostReward  // 销毁
```

#### 加速质押机制
- **旧**：加速质押不参与激励分配
- **新**：加速质押参与治理激励的加速部分，但有 2 倍上限

#### 批量铸造
- **新增**：`mintGovRewards(tokenAddress, memberId, rounds[])`
- **原子性**：批量多轮铸造，任一 Round 失败则整笔回滚

### 📍 实现参考
```
旧代码：LOVE20TKM/core/contracts/Mint.sol
保留：轮次准备、Proposal 分配
修改：治理激励改为 50%/50% 拆分，增加 2 倍上限
```

---

## 7. Launch（修改）

### ✅ 保留逻辑
- 发射次数阈值向上取整：参考 `LOVE20TKM/core/Launch.sol`
- 次数累计和余额结转逻辑
- 子币创建和首批分发流程

### 🔄 关键变化

#### 按 memberId 记录
- **旧**：`launchCount[tokenAddress][address]`
- **新**：`launchCount[tokenAddress][memberId]`

#### 次数融合
- **新增**：`mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)`
- **部分转移**：支持转移指定数量的发射次数
- **单向转移**：调用者只需控制来源 MemberNFT

#### 社区次数上限
- **新增**：每个社区最多产生 `maxLaunchCount` 次发射
- **达到上限后**：治理激励仍可铸造，但不再增加发射次数

### 📍 实现参考
```
旧代码：LOVE20TKM/core/contracts/Launch.sol
保留：阈值公式（向上取整）、累计逻辑
修改：地址 → memberId，新增融合接口
```

---

## 8. LOVE20Token & TokenFactory（保留）

### ✅ 完全保留
- ERC20 标准实现
- 代币树结构（parentTokenAddress）
- maxSupply 限制
- minter 权限控制
- TokenFactory 创建流程

### 🔄 微调
- 首个代币依赖 Airdrop 合约分发（来源：LOVE20TKM/burn 仓库）

### 📍 实现参考
```
旧代码：
  LOVE20TKM/core/contracts/LOVE20Token.sol
  LOVE20TKM/core/contracts/TokenFactory.sol
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

## 10. 首个代币部署（新增依赖）

### 新增流程
BSC 首个代币在部署 Core 合约时内部原子完成创建：

1. 在 BSC 上部署 `LOVE20TKM/burn` 仓库的 `Airdrop.sol` 合约
2. Airdrop 合约记录旧协议（Thinkium）参与者通过销毁活动获得的份额
3. 部署 Core 合约时，内部创建首个代币并将首批代币发送到 Airdrop 合约

**Airdrop 合约特性**：
- 支持任意 ERC20 代币的分发，不绑定特定代币
- 份额按代币独立记录：某代币领取后该份额即消耗，即使该代币后续余额增加也不能重复领取
- 未领取份额对应的代币余额归属于剩余未领取者

### 可追溯性
正式部署必须在文档中公开指向：
- `LOVE20TKM/burn` 仓库的 `Airdrop.sol`
- `DeployAirdrop.s.sol` 部署脚本
- `airdrop-design.md` 设计文档

### 📍 实现参考
```
旧代码：LOVE20TKM/burn（Airdrop 合约）
新增：Launch 的一次性协议启动路径
```

---

## 删除组件

| 组件 | 原位置 | 删除原因 |
|------|--------|----------|
| GroupDefaults | LOVE20TKM/group | BSC 不迁移默认配置 |
| LOVE20MemberMarket | LOVE20TKM/core | 未部署，不属于核心依赖 |
| SL/ST Token | LOVE20TKM/core/Stake.sol | 去凭证化，状态直接归 memberId |
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

核心验收场景见 `core.md` 第 10 节。关键变更的专项验收：

1. **MemberNFT 转移**：质押、投票、发射次数的历史不回写，当前未铸造权益由新持有人继续操作
2. **统一解锁**：流动性质押和加速质押必须同时申请、同时等待、同时提取
3. **质押融合**：向非调用者持有的目标 NFT 融合，只增加不减少目标状态
4. **发射次数融合**：部分融合、向非调用者持有的目标 NFT 转移
5. **治理激励拆分**：三段返回值（voteReward, boostReward, burnReward）
6. **批量多轮铸造**：原子性，任一 Round 失败则整笔回滚
7. **Phase 动态校准**：±10% 内不调整，超出范围时计算新 phaseBlocks
