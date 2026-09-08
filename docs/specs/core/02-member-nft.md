# MemberNFT

协议唯一的通用身份 NFT，同一 `memberId` 可拥有多个代币社区的独立状态。权限与转移语义见 [通用规则](01-common-rules.md#主体与权限)。

## 身份与名称

| 项 | 规则 |
| --- | --- |
| 合约 / ERC721 名称 / 符号 | `MemberNFT` / `LOVE20 Member NFT` / `Member` |
| ID | 从 `1` 单调递增，永不复用；`0` 表示未设置 |
| 名称长度 | `1` ~ `maxNameLength` 字节，按 UTF-8 字节数计算，不是字符数；参数示例为 `32` |
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

`init` 只允许第一次成功调用；合约以 `initialized` 状态拒绝后续调用并回滚 `AlreadyInitialized()`。部署验证脚本必须核对首币地址和全部费用参数。

```solidity
function mint(string memory name) external returns (uint256 id, uint256 mintCost);
```

费用使用首个 LOVE20 代币，计算如下。参数含义见 [初始化参数](00-protocol-model.md#初始化参数)，前三个费用参数均必须大于零。

```text
unmintedSupply = maxSupply - totalSupply
baseCost = floor(unmintedSupply / baseDivisor)
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost * multiplier ^ (bytesThreshold - byteLength)
```

`unmintedSupply` 取首币的未铸造量，`byteLength` 是名称字节数，`^` 表示幂。铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`，返回新 `id` 与本次 `mintCost`。名称无效或重复、余额或授权不足、费用溢出时回滚。

首币符号前 4 个字节为 `Test` 时，若名称长度不足 4 字节或前 4 个字节不是 `Test`，铸造前自动加 `Test` 前缀；前缀计入 `byteLength`、参与名称校验与费用计算，并作为存储名称。

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
function maxNameLength() external view returns (uint256);
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

## 持有人枚举

`holdersCount()` 返回唯一持有人地址数，`holdersAtIndex(index)` 返回第 `index` 个持有人地址（从 `0` 开始，越界回滚 `HolderIndexOutOfBounds(length)`）。它与 `ERC721Enumerable` 枚举的对象不同：后者按代币枚举（`totalSupply`、`tokenByIndex`、`tokenOfOwnerByIndex`），持有人集合按地址去重，同一地址持有多枚也只出现一次。

集合在每次余额变动时精确维护，不需要用事件重建：

- 铸造（`from == 0`）：接收方此前余额为 `0` 时加入
- 销毁（`to == 0`）：发送方此前余额为 `1` 时移除
- 转账：发送方此前余额为 `1` 时移除，接收方此前余额为 `0` 时加入
- 自转账（`from == to`）：既不加入也不移除

移除采用 swap-and-pop，因此 `holdersAtIndex` 的索引在移除后会重排，不能作为稳定标识。

验收见 [Core 验收](08-testing.md)。
