# MemberNFT

协议唯一的通用身份 NFT，同一 `memberId` 可拥有多个代币社区的独立状态。权限与转移语义见 [通用规则](01-common-rules.md#主体与权限)。

## 身份与名称

| 项 | 规则 |
| --- | --- |
| 合约 / ERC721 名称 / 符号 | `MemberNFT` / `LOVE20 Member NFT` / `Member` |
| ID | 从 `1` 单调递增，永不复用；`0` 表示未设置 |
| 名称长度 | `1` ~ `MAX_NAME_LENGTH` 字节，按 UTF-8 字节数计算，不是字符数；参数示例为 `32` |
| 名称校验 | 见 [名称校验](#名称校验) |
| 名称查询 | `mapping(string => uint256)` 保存规范化名称到 `memberId` 的映射；查询接口见 [接口](#接口) |
| 继承与枚举 | `ERC721Enumerable`；提供标准 ERC721、元数据和供应量/持有人名下 NFT 枚举能力 |

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

唯一性与规范化：仅把 ASCII 大写 `A-Z` 转为小写 `a-z`，不做 Unicode casefold，也不做 NFC/NFKC 规范化；其余字符按 UTF-8 字节精确比较。合约保存铸造时的原始名称用于显示，映射键为规范化后的名称。空名称回 `NameEmpty()`；含禁止字符回 `NameInvalidCharacters()`；超长回 `NameTooLong(length, MAX_NAME_LENGTH)`；名称重复回 `NameAlreadyExists(existingId)`。

## 铸造

接口见 [`IMemberNFT.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMemberNFT.sol)。

`MemberNFT` 的构造函数接收费用参数与首币地址，部署即完成绑定；不再有 `init` 入口，也没有 `initialized` 状态。首币地址与费用参数由部署 check 核对，不匹配则重新部署。首币地址为零或非合约地址时，`mint` 和 `calculateMintCost` 因无法从首币读取数据而回滚。

构造函数无调用者限制；部署成功即不可替换依赖或费用参数，没有修复或改绑入口，错误版本不得发布，需重新部署并核对受影响的依赖。

首币必须是已部署的合约且 `symbol()` 可读：构造函数不校验首币代码，绑定 EOA 或零地址时部署仍会成功，此后 `mint` 与 `calculateMintCost` 永久回滚。构造函数只写首币地址，不发事件（理由见[通用规则](01-common-rules.md#部署与安全)），绑定结果由部署 check 与 21_check 核对。

费用使用首个 LOVE20 代币，计算如下。参数含义见 [部署参数](00-protocol-model.md#部署参数)，四个参数均必须大于零，由 DeployCore 在广播前校验；构造函数只保存参数，不做静态校验。最大名称长度通过构造参数固定，BSC 部署配置使用 `32`。首币地址与费用参数由 21_check 核对，不匹配则重新部署。

```text
unmintedSupply = MAX_SUPPLY - totalSupply
baseCost = floor(unmintedSupply / baseDivisor)
mintCost = byteLength >= bytesThreshold
    ? baseCost
    : baseCost * multiplier ^ (bytesThreshold - byteLength)
```

`unmintedSupply` 取首币的未铸造量，`byteLength` 是名称字节数，`^` 表示幂。铸造时从调用者转入 `mintCost` 并立即销毁，累计到 `totalBurnedForMint`，返回新 `id` 与本次 `mintCost`。名称无效或重复、余额或授权不足、费用溢出时回滚。

`MemberMinted` 同时携带本次销毁量 `cost` 与销毁后的累计 `totalBurnedForMint`（后置值，`mintCost == 0` 时不变）：该聚合量只在铸造时改变，单条日志即可与 `totalBurnedForMint()` 对账，口径与 `Stake.FeesSettled.totalBurnedToken` 一致。`name` 与 `normalizedName` 均受 `maxNameLength` 约束，长度不变。

首币符号前 4 个字节为 `Test` 时，若名称长度不足 4 字节或前 4 个字节不是 `Test`，铸造前自动加 `Test` 前缀；前缀计入 `byteLength`、参与名称校验与费用计算，并作为存储名称。

沿用旧查询行为：`calculateMintCost` 只按传入名称的字节数计费，不补 `Test` 前缀，也不校验名称合法性或唯一性。测试币场景中，调用方应先按上述规则补前缀再询价；例如铸造 `abc` 的对应报价应查询 `Testabc`。`memberId(name)`、`isNameUsed` 仅做 ASCII 小写规范化，也需传入最终存储名称。

例：`baseCost = 100`、`bytesThreshold = 7`、`multiplier = 10`；6 字节名花费 `1000`，7 字节及以上花费 `100`。金额均以代币最小单位计。

费用使用 ERC20，入口为 `nonpayable`，不接受原生代币。费用参数在部署时固定；首币地址在 `MemberNFT` 构造函数传入，取自 `Launch.FIRST_TOKEN_ADDRESS()`（此时 `Launch` 已部署并完成首币创建）。依赖后部署的合约按部署顺序预先预测地址注入。

## 接口

对外接口见 [`IMemberNFT.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMemberNFT.sol)。它沿用旧 `LOVE20Group`，仅去除 group 字样重命名；本合约即 Member 本体，标识符不再重复 member。构造参数与铸造接口见 [铸造](#铸造)。

独有函数、事件和错误见 [`IMemberNFT.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/IMemberNFT.sol)；Core 接口继承 `IERC721Enumerable`，实现合约同时继承 `ERC721Enumerable` 和 `IMemberNFT`，由编译器核验接口实现。完整调用 ABI 使用目标合约编译产物，包含 OZ 提供的标准函数、事件和错误；扣费调用的 LOVE20Token 的 ERC20 标准错误由 LOVE20Token ABI 拥有，`SafeERC20FailedOperation` 通过库进入 MemberNFT ABI。

### 失败契约

`mint` 的校验顺序，任一步回滚整笔：

| 顺序 | 条件 | 回滚错误 |
| --- | --- | --- |
| 1 | 名称（已加 `Test` 前缀）为空 | `NameEmpty()` |
| 2 | 名称超过 `MAX_NAME_LENGTH` | `NameTooLong(length, maxLength)`，`length` 为前缀后字节数 |
| 3 | 名称含禁止字符或非法 UTF-8 | `NameInvalidCharacters()` |
| 4 | 规范化名称已存在 | `NameAlreadyExists(existingId)` |
| 5 | 费用转账或销毁失败 | `SafeERC20FailedOperation(address)` / ERC20 标准错误 |
| 6 | `_safeMint` 接收方拒绝 | OZ `ERC721InvalidReceiver(address)` |

构造函数不校验首币代码；绑定零地址或 EOA 时，`mint` 读零地址的 `symbol()`（名称前缀判定）、`calculateMintCost` 读零地址的 `MAX_SUPPLY()` 与 `totalSupply()`，均取回空数据、ABI 解码失败，以空 revert（0x）结束。

### 透传来源

| 来源 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `IERC20.transferFrom` | `SafeERC20FailedOperation(address)`、`ERC20InsufficientAllowance(address,uint256,uint256)`、`ERC20InsufficientBalance(address,uint256,uint256)` | 铸造费扣款 |
| `ILOVE20Token.burn` | `ERC20InsufficientBalance(address,uint256,uint256)` | 先转入再销毁；正常路径余额充足 |
| OZ ERC721 | `ERC721NonexistentToken(uint256)`、`ERC721IncorrectOwner(address,uint256,address)`、`ERC721InvalidReceiver(address)` | 用户转账与 `_safeMint`；标准错误由 OZ ABI 拥有 |

## 持有人枚举

`holders(offset, limit, reverse)` 按页返回唯一持有人地址，并同时返回集合总数 `totalCount`。它与 `ERC721Enumerable` 枚举的对象不同：后者按代币枚举（`totalSupply`、`tokenByIndex`、`tokenOfOwnerByIndex`），持有人集合按地址去重，同一地址持有多枚也只出现一次。

分页语义与 `Phase.observations` 一致：`offset` 大于或等于总数时返回空数组与真实 `totalCount`，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时按从新到旧返回。链上不提供全量遍历，只按页读取。

集合在每次余额变动时精确维护，不需要用事件重建：

- 铸造（`from == 0`）：接收方此前余额为 `0` 时加入
- 销毁（`to == 0`）：发送方此前余额为 `1` 时移除
- 转账：发送方此前余额为 `1` 时移除，接收方此前余额为 `0` 时加入
- 自转账（`from == to`）：既不加入也不移除

移除采用 swap-and-pop，因此集合内位置在移除后会重排；分页只承诺单次调用内的一致快照，位置不能作为稳定标识。自转账不触发集合变更。链下重建同一集合时按 ERC-721 `Transfer` 折叠；`AddHolder` / `RemoveHolder` 不再作为协议事件存在。

验收见 [Core 验收](09-testing.md)。
