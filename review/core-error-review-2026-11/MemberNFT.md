# `core/MemberNFT.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/02-member-nft.md`。
> 范围：`src/MemberNFT.sol`（379 行）+ `src/interfaces/IMemberNFT.sol` 的 `IMemberNFTErrors`。
> 处置：本报告为 `6fdd0f1` 快照；逐条决定、ABI 变更与撤回见 [DISPOSITION.md](DISPOSITION.md)。

## 1. 结论

- 5 个错误声明 / 5 个发送点；全部命中，无裸 `require`、无未声明 revert。
- 唯一一个 Medium：`calculateMintCost` 的幂运算没有上界，配置越界时以 Panic 永久挡住短名铸造/询价（E-NFT-01）。
- 其余为文档与载荷口径：前缀长度、缺校验顺序表、缺透传来源表、未初始化时的空 revert。
- `NameAlreadyExists`、`NameEmpty`、`NameInvalidCharacters` 的赋值与条件一一对应，无问题。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 5 |
| revert 站点 | 5 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 1 / 0 / 4 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `NameAlreadyExists` | `NameAlreadyExists(uint256)` | 1 | 保留 |
| `AlreadyInitialized` | `AlreadyInitialized()` | 1 | 保留 |
| `NameEmpty` | `NameEmpty()` | 1 | 保留 |
| `NameTooLong` | `NameTooLong(uint256,uint256)` | 1 | 保留（口径注记） |
| `NameInvalidCharacters` | `NameInvalidCharacters()` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `NameAlreadyExists` · 1 站点 · 保留

- 声明：`interfaces/IMemberNFT.sol:18`
- 签名：`NameAlreadyExists(uint256)`
- 载荷：`uint256 existingId`
- 赋值链：existingTokenId ← `_tokenIdByNormalizedName[normalizedName]`（`MemberNFT.sol:223-226`）。
- 核对：载荷 `(existingId)`；规范化名称命中已有 id，值可直接用于查询。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `MemberNFT.sol:226` | `_checkName` | `existingTokenId != 0` | `existingTokenId` |

### `AlreadyInitialized` · 1 站点 · 保留

- 声明：`interfaces/IMemberNFT.sol:19`
- 签名：`AlreadyInitialized()`
- 载荷：无
- 核对：无载荷；`init` 自身状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `MemberNFT.sol:55` | `init` | `initialized` | `—` |

### `NameEmpty` · 1 站点 · 保留

- 声明：`interfaces/IMemberNFT.sol:20`
- 签名：`NameEmpty()`
- 载荷：无
- 核对：无载荷；`len == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `MemberNFT.sol:219` | `_checkName` | `len == 0` | `—` |

### `NameTooLong` · 1 站点 · 保留（口径注记）

- 声明：`interfaces/IMemberNFT.sol:21`
- 签名：`NameTooLong(uint256,uint256)`
- 载荷：`uint256 length, uint256 maxLength`
- 赋值链：len ← `bytes(prefixedName).length`（`MemberNFT.sol:63-65`、`:217`）。
- 核对：`length` 是加 `Test` 前缀后的长度，见 E-NFT-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `MemberNFT.sol:220` | `_checkName` | `len > MAX_NAME_LENGTH` | `len, MAX_NAME_LENGTH` |

### `NameInvalidCharacters` · 1 站点 · 保留

- 声明：`interfaces/IMemberNFT.sol:25`
- 签名：`NameInvalidCharacters()`
- 载荷：无
- 核对：无载荷；失败对象是整串名称，逐码点白名单无法用定长载荷表达。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `MemberNFT.sol:221` | `_checkName` | `!_isValidNameChars(nameBytes)` | `—` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-NFT-01 | Medium | `src/MemberNFT.sol:103-122` | `calculateMintCost` 用 `MULTIPLIER ** (BYTES_THRESHOLD - byteLength)`，两个参数都没有上界：部署门禁只校验非零（`DeployCore.s.sol:129-132`；`21_check.sh:466-480` 的 `verify_positive`）。一个通过全部门禁的配置（例如 `MULTIPLIER=10`、`BYTES_THRESHOLD=100`）会让所有 `byteLength < BYTES_THRESHOLD` 的名称在 `calculateMintCost`/`mint` 中以 Panic 0x11 永久回滚；若 `MAX_NAME_LENGTH` 也不大于阈值（默认 32），则全部名称都不可铸造，属完全砖化，无资金损失。 | error-standards §7/§8（用户输入可达的失败应有确定 selector）；`02-member-nft.md:44-58` 只写“费用溢出时回滚” | 两层：① DeployCore 增加保守上界（如 `BYTES_THRESHOLD <= 64` 且 `MULTIPLIER ** maxDifference` 不溢出，或按 `bitLength(multiplier) * threshold < 256` 计算）；② 合约侧改逐步 `Math.tryMul`，溢出回 `MintCostOverflow()`（新 selector，需 breaking 窗口）。 |
| E-NFT-02 | Info | `src/MemberNFT.sol:63-67`、`:220` | `mint` 先加 `Test` 前缀再校验，`NameTooLong(length, maxLength)` 的 `length` 是**前缀后**的长度。调用方按自己输入的长度对不上（Testnet 差 4 字节）。 | error-standards §4；`02-member-nft.md:56` 已说明前缀计入 `byteLength` | 在 02-member-nft 的错误表写明“length 为施加 Test 前缀后的字节数”；或在载荷加 `prefixBytes`（破坏 ABI）。 |
| E-NFT-03 | Info | `src/MemberNFT.sol:215-228` | `_checkName` 的顺序是 空 → 超长 → 字符集 → 重名，但 02-member-nft 只用分句列出条件（`02-member-nft.md:34`），没有 §5 要求的“校验顺序 + 错误集合”表。多个条件同时不满足时，调用方无法从规格推出先命中哪一个。 | error-standards §5 | 补一张 4 行表（顺序/条件/错误），与 04-stake 的写法一致。 |
| E-NFT-04 | Info | `src/MemberNFT.sol:82-89` | `mint` 的失败集合包含 OZ ERC721/ERC20 错误与 `SafeERC20FailedOperation`；02-member-nft:68 已声明“标准错误由 OZ/代币 ABI 拥有”，但没有 §1 要求的“透传来源”表。 | error-standards §1 | 补表：`ERC721NonexistentToken`/`ERC721IncorrectOwner`（OZ ERC721）、`ERC20InsufficientBalance`/`ERC20InsufficientAllowance`（LOVE20Token）、`SafeERC20FailedOperation`（SafeERC20）。 |
| E-NFT-05 | Info | `src/MemberNFT.sol:63`、`:154-177` | 未初始化时 `mint` 先读 `LOVE20_TOKEN_ADDRESS` 的 `symbol()`；地址为 0 时调用返回空数据，ABI decode 失败，整笔以**空 revert（0x）**结束，没有 selector。02-member-nft:40 只写“无法读取而回滚”。 | error-standards §7（失败形态应可判别） | 在 02-member-nft 登记失败形态为“空 revert（0x）”；若要可判别，加 `NotInitialized()`（新 selector，需窗口）。 |

### 4.2 已核对项

- 声明全部在 `IMemberNFTErrors`；实现零声明；无裸 `require`/`revert`。
- `_checkName` 在写 `_memberNameByTokenId`/`_tokenIdByNormalizedName` 之前完成；`_mintMember` 任一步失败整笔回滚。
- `NameAlreadyExists` 的键是 ASCII 小写规范化后的名称，与 `isNameUsed`/`memberId` 同一口径。
- `check_error_tests.py`：0 untested；`test/MemberNFT.t.sol:293` 断言 `NameTooLong(overLimit.length, MAX_NAME_LENGTH)`。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `ILOVE20Token.burn` | `ERC20InsufficientBalance(address,uint256,uint256)` | 先 `transferFrom` 再 `burn`，正常路径余额充足；异常时冒泡。 |
| `IERC20.transferFrom` | `SafeERC20FailedOperation(address)`、`ERC20InsufficientAllowance` | 铸造费扣款。 |
| OZ ERC721 转账 | `ERC721NonexistentToken`、`ERC721IncorrectOwner`、`ERC721InvalidReceiver` | `_safeMint`/用户转账；标准错误由 OZ ABI 拥有。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/MemberNFT.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/IMemberNFT.sol`。
