# Launch 与 TokenFactory 规格

本文档定义 Launch 和 TokenFactory 合约规格。

---

## 1. 发射次数（按 memberId 记录）

### 1.1 存储变更

- **旧版**：`launchCount[tokenAddress][address]`  
- **新版**：`launchCount[tokenAddress][memberId]`

### 1.2 发射次数产生机制（BSC 版新增）

- Mint 合约维护 `launchCredit[tokenAddress][memberId]`：累计铸造激励余额
- 每次成功铸造治理激励后，Mint 合约累加激励金额到 launchCredit
- 判断 launchCredit 是否达到阈值：`threshold = ceil((maxSupply - totalSupply) × launchRatio / 1e18)`
- 如果 `launchCredit >= threshold`：
  - 计算产生的发射次数：`count = floor(launchCredit / threshold)`
  - 扣除已使用的 launchCredit：`launchCredit -= count × threshold`
  - 调用 `Launch.addLaunchCount(tokenAddress, memberId, count)` 增加发射次数
- Launch 合约的 `addLaunchCount()` 只能由 Mint 合约调用（权限控制）

### 1.3 launchCredit 说明

- 发射阈值使用向上取整，随 totalSupply 动态调整
- 余额累计机制：未达阈值的部分保留在 launchCredit，继续累计
- **融合时只转移整数次数，不转移 `launchCredit`**（源的 launchCredit 保留，用户应在融合前等待 launchCredit 转化为整数次数）
- **提供查询接口**：用户可以查询任意 `(tokenAddress, memberId)` 的 `launchCredit` 余额，用于预测还需要多少激励才能产生下一次发射次数

### 1.4 launchCredit 累计示例

**假设**：`maxSupply = 10000 token`，`launchRatio = 0.01 = 1e16`，`totalSupply` 初始为 0

#### Round 1
- 成员 A 铸造 80 token 治理激励
- `threshold = ceil(10000 × 0.01) = 100 token`
- `launchCredit[A] = 80`，未达阈值
- Mint 不调用 Launch，`launchCount[A] = 0`

#### Round 2
- 成员 A 铸造 50 token 治理激励
- `launchCredit[A] = 80 + 50 = 130`
- `threshold = ceil((10000 - 80) × 0.01) = 100 token`
- `count = floor(130 / 100) = 1`
- Mint 消耗 100 token launchCredit，调用 `Launch.addLaunchCount(tokenAddress, A, 1)`
- `launchCredit[A] = 30`，`launchCount[A] = 1`

#### Round 3
- 成员 A 铸造 90 token 治理激励
- `launchCredit[A] = 30 + 90 = 120`
- `threshold = ceil((10000 - 130) × 0.01) = 99 token`
- `count = floor(120 / 99) = 1`
- Mint 消耗 99 token launchCredit，调用 `Launch.addLaunchCount(tokenAddress, A, 1)`
- `launchCredit[A] = 21`，`launchCount[A] = 2`

#### Round 4
- 成员 A 铸造 200 token 治理激励
- `launchCredit[A] = 21 + 200 = 221`
- `threshold = ceil((10000 - 220) × 0.01) = 98 token`
- `count = floor(221 / 98) = 2`（一次性跨越两个阈值）
- Mint 消耗 196 token launchCredit，调用 `Launch.addLaunchCount(tokenAddress, A, 2)`
- `launchCredit[A] = 25`，`launchCount[A] = 4`

**关键**：launchCredit 避免余额丢失，确保所有激励最终转化为发射次数。

### 1.5 新增约束

- 每个社区最多产生 `maxLaunchCount` 次发射（初始化参数）
- 达到上限后，该社区不再产生新的发射次数，launchCredit 继续累计但不再转化
- 已有的整数次数仍可融合转移和消耗

---

## 2. 发射次数融合（新增）

### 2.1 接口

```solidity
function mergeLaunchCount(
    address tokenAddress,
    uint256 sourceMemberId,
    uint256 targetMemberId,
    uint256 count
) external
```

### 2.2 设计意图

发射次数融合支持单向转移（调用者只需控制来源 MemberNFT），目的是让发射次数可以通过 MemberNFT 作为载体进行场外交易。

### 2.3 约束

- 源、目标必须是不同且已存在的 MemberNFT
- `count > 0`，调用者只需控制源 MemberNFT
- 目标 MemberNFT 必须存在（`ownerOf(targetMemberId)` 不回滚）
- 发射次数转移不携带 `launchCredit`，只转移整数次数
- 转移不破坏目标 MemberNFT 的既有状态（只增加，不减少）

成功后源次数减少、目标次数增加；目标原有次数及其他状态不减少，其他质押、投票、历史发射和事件不改变。

---

## 3. 发射（保留流程）

### 3.1 参考实现

`LOVE20TKM/core/contracts/Launch.sol`

### 3.2 发射规则

任何当前持有目标 MemberNFT 的钱包或合约都可以触发该社区子币发射，但必须消耗该成员的一次 `launchCount`。

分发合约由发射调用者决定，不同分发合约可实现各自的领取逻辑。分发合约接口没有通用定义，各自按需实现；建议至少提供 `claim(tokenAddress)` 接口和领取状态查询接口。

### 3.3 发射安全性

- 使用重入保护（`nonReentrant`）
- 遵循检查-更新-交互顺序：
  1. 检查：验证 `launchCount[tokenAddress][memberId] > 0`、代币参数有效性等
  2. 更新：扣除 `launchCount[tokenAddress][memberId] -= 1`
  3. 交互：创建子币、铸造首批代币、调用 distributor
- 整个发射流程原子性：如果分发合约调用失败（`revert`），整个交易回滚，子币创建不成功，发射次数不消耗
- 发射者需自行验证 distributor 合约的可靠性，承担 gas 耗尽等风险

---

## 4. TokenFactory

### 4.1 职责

TokenFactory 负责创建所有 LOVE20 代币实例。

- 部署新的 LOVE20Token 合约实例
- 只能由 Launch 合约调用（权限控制）
- 返回新创建的代币地址

### 4.2 接口

```solidity
function createToken(
    string memory name,
    string memory symbol,
    uint256 initialSupply,
    uint256 maxSupply,
    address to
) external returns (address tokenAddress)
```

### 4.3 参数

详见 `00-protocol-model.md` 第 2.7 节

- `name`：代币名称
- `symbol`：代币符号
- `initialSupply`：初始供应量（发射时铸造给 distributor）
- `maxSupply`：最大供应量
- `to`：初始代币接收者（distributor 地址）

### 4.4 权限

只能由 Launch 合约调用

### 4.5 效果

- 部署新的 LOVE20Token 合约实例
- 铸造 `initialSupply` 给 `to` 地址
- 返回新代币地址

### 4.6 失败条件

- 调用者不是 Launch 合约
- `maxSupply < initialSupply`
- `to` 是零地址
- 代币名称或符号为空
