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
| TokenFactory | 微调 | `LOVE20TKM/core/src/LOVE20TokenFactory.sol` | core/TokenFactory.sol | 旧创建职责保留；新增 distributor，移除 SL/ST 创建 |
| Launch | 修改 | `LOVE20TKM/core/src/LOVE20Launch.sol` | core/Launch.sol | 发射次数按 memberId 记录 |

---

## 1. MemberNFT（复制迁移）

旧 `LOVE20TKM/group/src/LOVE20Group.sol` 整体复制为 `core/MemberNFT.sol`，业务逻辑不改；行为规范见 [MemberNFT 规格](core/02-member-nft.md)。"协议唯一身份"仅指各业务合约以 `memberId` 为键使用它（见 Stake、Submit、Vote、Mint、Launch 各节），本合约不新增承载或转移规则。

差异仅三项：

- **合约名与接口标识符**：`LOVE20Group` → `MemberNFT`，ERC721 名称 `LOVE20 Member NFT`、符号 `Member`；对外接口全部保留，仅去除 group 字样且不重复 member（如 `groupNameOf` → `nameOf`、`GroupNameEmpty` → `NameEmpty`）——旧 Group 是成员身份 NFT，不是“群”的 NFT
- **名称长度上限**：`64 bytes` → `32 bytes`（避免与钱包地址混淆）
- **铸造费用代币地址**：由旧构造函数传入改为 `init(firstTokenAddress)`，由 `Launch.init` 在创建首币时同步调用一次

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
- **LP 份额计算**：参考 `LOVE20TKM/core/src/LOVE20Stake.sol` 154-184 行
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
旧代码：LOVE20TKM/core/src/LOVE20Stake.sol
保留公式：LP份额（154-184行）、手续费（248-276行）
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

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Submit.sol
保留：推举门槛、去重逻辑
修改：所有 address 参数改为 uint256 memberId
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

### ✅ 保留逻辑
- 发射次数阈值向上取整：参考 `LOVE20TKM/core/src/LOVE20Launch.sol`
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

#### 首个代币部署
- `Launch.init(...)` 在写入依赖和发射参数的同一笔初始化交易中，通过 `TokenFactory` 创建首个代币、设置 `minter`、发送首批代币到 Airdrop、创建首个代币/WBNB Pair，并同步调用 `MemberNFT.init(firstToken)` 完成其初始化
- `Launch` 的分发参数与 Proposal 的 `target + targetMode` 对齐：首币固定使用 Airdrop 和 `NoCallback`；普通发射可使用 `NoCallback` 或 `Callback`
- `Launch.init` 任一步失败则整笔回滚；成功后不得再次初始化或创建第二个首个代币
- Airdrop 来源和 Burn 追溯证据按部署记录保存

### 📍 实现参考
```
旧代码：LOVE20TKM/core/src/LOVE20Launch.sol
保留：阈值公式（向上取整）、累计逻辑
修改：地址 → memberId，新增融合接口
```

---

## 8. LOVE20Token & TokenFactory（职责保留、依赖调整）

### ✅ 保留
- ERC20 标准实现
- 代币树结构（parentTokenAddress）
- maxSupply 限制
- minter 权限控制
- TokenFactory 创建流程

### 🔄 BSC 调整
- `TokenFactory.createToken` 新增非零 `distributor`，首批供应量直接铸给该地址
- 删除 SL/ST 实例创建及其 Stake 依赖；Pair 仍由工厂创建
- 首个代币依赖 Airdrop 合约分发（来源：LOVE20TKM/burn 仓库）

### 📍 实现参考
```
旧代码：
  LOVE20TKM/core/src/LOVE20Token.sol
  LOVE20TKM/core/src/LOVE20TokenFactory.sol
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

核心验收场景见 `core/08-testing.md` 和组织级 `docs/acceptance.md`。关键变更的专项验收：

1. **MemberNFT 转移**：质押、投票、发射次数的历史不回写，当前未铸造权益由新持有人继续操作
2. **统一解锁**：流动性质押和加速质押必须同时申请、同时等待、同时提取
3. **质押融合**：向非调用者持有的目标 NFT 融合，只增加不减少目标状态
4. **发射次数融合**：部分融合、向非调用者持有的目标 NFT 转移
5. **治理激励拆分**：三段返回值（voteReward, boostReward, burnReward）
6. **批量多轮铸造**：原子性，任一 Round 失败则整笔回滚
7. **Phase 动态校准**：由初始化的 `adjustThreshold` 控制，超过阈值时计算新 phaseBlocks
