# MemberNFT

协议唯一的通用身份 NFT，同一 `memberId` 可拥有多个代币社区的独立状态。权限与转移语义见 [通用规则](01-common-rules.md#主体与权限)。

## 身份与名称

| 项 | 规则 |
| --- | --- |
| 合约 / ERC721 名称 / 符号 | `MemberNFT` / `LOVE20 Member NFT` / `Member` |
| ID | 从 `1` 单调递增，永不复用；`0` 表示未设置 |
| 名称长度 | 不超过 `maxMemberNameLength` 字节，参数示例为 `32` |
| 名称校验 | UTF-8 合法性、禁止字符和 ASCII 大小写不敏感唯一性 |
| 名称查询 | `mapping(string => uint256)` 保存规范化名称到 `memberId` 的映射 |
| 枚举 | 使用标准 `ERC721Enumerable` 查询供应量和持有人名下 NFT |

## 铸造

```solidity
function init(address firstTokenAddress) external;
```

```solidity
function mint(string memory name) external returns (uint256 memberId);
```

费用使用首个 LOVE20 代币，计算如下。参数含义见 [初始化参数](00-protocol-model.md#初始化参数)，前三个费用参数均必须大于零。

```text
unmintedSupply = maxSupply - totalSupply
baseCost = floor(unmintedSupply / baseDivisor)
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost * multiplier ^ (bytesThreshold - byteLength)
```

`unmintedSupply` 取首币的未铸造量，`byteLength` 是名称字节数，`^` 表示幂。铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`，返回新 ID。名称无效或重复、余额或授权不足、费用溢出时回滚。

例：`baseCost = 100`、`bytesThreshold = 7`、`multiplier = 10`；6 字节名花费 `1000`，7 字节及以上花费 `100`。金额均以代币最小单位计。

名称禁止字符清单和 UTF-8 校验沿用旧 `LOVE20Group`，实现时按同一源码规则迁移；最大长度改为 `32 bytes`。费用使用 ERC20，入口为 `nonpayable`，不接受原生代币。

费用参数在部署时固定；`MemberNFT.init(firstToken)` 只能由预先绑定的 Launch 调用一次。依赖后部署的合约按“先部署、后 `init`”顺序绑定。

验收见 [Core 验收](08-testing.md)。
