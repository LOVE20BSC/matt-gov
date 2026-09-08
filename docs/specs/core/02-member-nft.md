# MemberNFT

协议唯一的通用身份 NFT，同一 `memberId` 可拥有多个代币社区的独立状态。权限与转移语义见 [通用规则](01-common-rules.md#主体与权限)。

## 身份与名称

| 项 | 规则 |
| --- | --- |
| 合约 / ERC721 名称 / 符号 | `MemberNFT` / `LOVE20 Member NFT` / `Member` |
| ID | 从 `1` 单调递增，永不复用；`0` 表示未设置 |
| 名称长度 | `1` ~ `maxMemberNameLength` 字节，按 UTF-8 字节数计算，不是字符数；参数示例为 `32` |
| 名称校验 | 见 [名称校验](#名称校验) |
| 名称查询 | `mapping(string => uint256)` 保存规范化名称到 `memberId` 的映射；查询接口见 [接口](#接口) |
| 枚举 | 使用标准 `ERC721Enumerable` 查询供应量和持有人名下 NFT |

## 名称校验

允许：ASCII 字母与数字、ASCII 可打印字符 `0x21-0x7E`（不含空格）、Unicode 字符（CJK、单码点表情符号等）。需要零宽连接符组合的复合表情符号不被支持。

拒绝，按 UTF-8 字节序列匹配：

| 类别 | 码点 |
| --- | --- |
| 空格 | U+0020、U+00A0、U+1680、U+2000–U+200A、U+202F、U+205F、U+3000 |
| 控制字符 | C0 U+0000–U+001F、C1 U+0080–U+009F、DEL U+007F |
| 行/段落分隔符 | U+2028、U+2029 |
| 方向格式化 | U+061C、U+202A–U+202E、U+2066–U+2069 |
| 零宽字符 | U+200B、U+200C、U+200D、U+200E、U+200F、U+034F、U+FEFF、U+2060、U+00AD |
| 不可见数学运算符 | U+2061–U+2064 |
| 废弃格式化字符 | U+206A–U+206F |

UTF-8 有效性：拒绝无效起始字节 `0x80-0xC1` 与 `0xF5-0xFF`、过长编码、UTF-16 代理对（U+D800–U+DFFF）、大于 U+10FFFF 的码点和不完整的多字节序列。

唯一性与规范化：仅把 ASCII 大写 `A-Z` 转为小写 `a-z`，不做 Unicode casefold，也不做 NFC/NFKC 规范化；其余字符按 UTF-8 字节精确比较。合约保存铸造时的原始名称用于显示，映射键为规范化后的名称。空名称、超长、含禁止字符和名称重复分别回滚 [接口](#接口) 中对应的错误。

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

费用使用 ERC20，入口为 `nonpayable`，不接受原生代币。费用参数在部署时固定；`MemberNFT.init(firstToken)` 由 `Launch.init` 在创建首币时同步调用一次。依赖后部署的合约按“先部署、后 `init`”顺序绑定。

## 接口

对外接口沿用旧 `LOVE20Group`，仅去除 group 字样重命名；本合约即 Member 本体，标识符不再重复 member。初始化与铸造接口见 [铸造](#铸造)。

```solidity
function calculateMintCost(string memory name) external view returns (uint256);
function normalizedNameOf(string memory name) external pure returns (string memory);
function idOf(string memory name) external view returns (uint256);
function nameOf(uint256 id) external view returns (string memory);
function isNameUsed(string memory name) external view returns (bool);

function firstTokenAddress() external view returns (address);
function baseDivisor() external view returns (uint256);
function bytesThreshold() external view returns (uint256);
function multiplier() external view returns (uint256);
function maxMemberNameLength() external view returns (uint256);
function totalBurnedForMint() external view returns (uint256);

function holdersCount() external view returns (uint256);
function holdersAtIndex(uint256 index) external view returns (address);

event Mint(
    uint256 indexed id,
    address indexed owner,
    string name,
    string normalizedName,
    uint256 cost
);
event AddHolder(address indexed holder, uint256 totalHolders);
event RemoveHolder(address indexed holder, uint256 totalHolders);

error NameEmpty();
error NameTooLong(uint256 length, uint256 maxLength);
error NameInvalidCharacters();
error NameAlreadyExists(uint256 existingId);
error HolderIndexOutOfBounds(uint256 length);
```

`holdersCount` 与 `holdersAtIndex` 是旧实现的非权威辅助查询，自转账后可能过期；可靠的持有人集合应通过 `Transfer` 事件或 `ERC721Enumerable` 重建。

## 待确认

- **`mint` 返回值**：旧接口为 `returns (uint256 tokenId, uint256 mintCost)`，本规格当前写为 `returns (uint256 memberId)`。来源：旧 `LOVE20TKM/group/src/interfaces/ILOVE20Group.sol`。受影响操作：调用方是否需要同步取回本次费用。
- **测试网名称前缀**：旧 `mint` 在首币符号以 `Test` 开头时自动给名称加 `Test` 前缀，影响存储名称、字节长度与费用。来源：旧 `LOVE20TKM/group/src/LOVE20Group.sol` 的 `_addTestPrefixIfNeeded`。BSC 是否保留该行为未定。

验收见 [Core 验收](08-testing.md)。
