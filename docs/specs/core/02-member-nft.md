# MemberNFT 规格

本文档定义 MemberNFT 合约规格。

---

## 1. 定位

`MemberNFT` 是协议唯一的通用身份 NFT。质押、Proposal、投票、发射次数和所有扩展参与关系均使用 `memberId` 关联；同一 MemberNFT 可以在多个代币社区拥有互相独立的状态。

- 合约名：`MemberNFT`
- ERC721 名称：`LOVE20 Member NFT`
- 符号：`Member`
- `memberId` 从 `1` 开始单调递增且永不复用；`0` 始终表示未设置

---

## 2. 名称校验

### 2.1 实现基线

**参考**：`LOVE20TKM/group/contracts/LOVE20Group.sol` 的名称校验逻辑

### 2.2 BSC 版变更

- 最大长度由部署参数 `maxMemberNameLength` 确定（例如 `32 bytes`，避免与钱包地址混淆）
- 其他 UTF-8 校验规则、ASCII 大小写不敏感、禁止字符类型保持一致
- 名称存储和查询：使用 `mapping(string => uint256)` 存储规范化名称（小写）到 `memberId` 的映射，支持通过名称查找 memberId

Gas 成本在旧版实际部署中已验证可行，无需重新评估。

---

## 3. 铸造费用

### 3.1 公式

**保留旧版公式**：

```text
baseCost = unmintedSupply / baseDivisor
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost × multiplier ^ (bytesThreshold - byteLength)
```

- `baseDivisor`、`bytesThreshold` 和 `multiplier` 均在部署时确定且必须大于零
- `unmintedSupply` = 协议首个 LOVE20 代币的 `maxSupply - totalSupply`（即首个代币的未铸造量）
- 铸造费用使用协议首个 LOVE20 代币支付
- 铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`

### 3.2 计算示例

**假设参数**：
- `baseDivisor = 1e8`
- `bytesThreshold = 7`
- `multiplier = 10`
- `unmintedSupply = 1e10 token`

**计算结果**：
- `baseCost = 1e10 / 1e8 = 100 token`
- 铸造 "Alice"（5 bytes）：`mintCost = 100 × 10^(7-5) = 100 × 100 = 10000 token`
- 铸造 "Bob"（3 bytes）：`mintCost = 100 × 10^(7-3) = 100 × 10000 = 1000000 token`
- 铸造 "LongName"（8 bytes）：`mintCost = 100 token`（达到阈值，无倍数）
- 铸造 "VeryLongName"（12 bytes）：`mintCost = 100 token`（超过阈值，无倍数）

### 3.3 短名称稀缺性

名称越短，费用呈指数增长，激励用户使用较长名称。

### 3.4 参考实现

`LOVE20TKM/group/contracts/LOVE20Group.sol` 78-95 行

---

## 4. 铸造接口

```solidity
function mint(string memory name) external payable returns (uint256 memberId)
```

### 4.1 参数

- `name`：成员名称，必须通过名称校验（第2节）

### 4.2 返回值

- `memberId`：新铸造的 MemberNFT ID

### 4.3 支付

- 使用协议首个 LOVE20 代币支付 `mintCost`
- 从 `msg.sender` 转入并立即销毁

### 4.4 失败条件

- 名称校验失败（长度、字符、重复等）
- 代币余额不足或授权不足
- 费用计算溢出

---

## 5. 转移语义

MemberNFT 的转移不复制、不拆分、不重置任何历史。依赖身份的合约必须实时读取 `ownerOf(memberId)`，不能缓存钱包地址作为长期权限。MemberNFT 转移后，新持有人可以铸造尚未领取的治理激励、使用尚未消耗的发射次数、提取解锁期结束的解锁资产，以及继续控制当前质押状态。

供应量和按持有人查询使用标准 `ERC721Enumerable` 接口。
