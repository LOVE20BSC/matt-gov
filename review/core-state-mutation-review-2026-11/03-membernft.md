# MemberNFT · 状态变量变更审查

> `core/src/MemberNFT.sol`，379 行，`core@6fdd0f1`。
> 本合约是协议唯一的身份来源：`memberId` 由它单调分配，所有业务合约的 `onlyMemberOwner` 都回到 `ownerOf`。它的账本一旦写错，影响面是全部社区。
> 证据分级：E3 测试 / E2 算术或字节推导 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| 1 | `LOVE20_TOKEN_ADDRESS` | `address` | 身份费代币（首币） | `init:56` | 只写一次 |
| 2-5 | `BASE_DIVISOR` / `BYTES_THRESHOLD` / `MULTIPLIER` / `MAX_NAME_LENGTH` | `uint256 immutable` | 定价与长度参数 | 构造器 `:47-50` | 不可变 |
| 6 | `initialized` | `bool` | 一次性开关 | `init:57` | 只写一次 |
| 7 | `_nextTokenId` | `uint256`（内联初值 1） | 下一个身份 ID | `_mintMember:78`（`++`） | 只增 |
| 8 | `totalBurnedForMint` | `uint256` | 累计销毁的身份费 | `_mintMember:83` | 只增 |
| 9 | `_memberNameByTokenId` | `mapping(uint256 => string)` | ID → 铸造时的原始名称 | `_mintMember:79` | 只写一次/ID |
| 10 | `_tokenIdByNormalizedName` | `mapping(string => uint256)` | 规范化名称 → ID（唯一性来源） | `_mintMember:80` | 只写一次/名称 |
| 11 | `_holders` | `address[]` | 当前持有人集合（去重） | `_addHolder:181`、`_removeHolder:191/194` | 增删 |
| 12 | `_holderIndex` | `mapping(address => uint256)` | 持有人在 `_holders` 中的下标 | `_addHolder:182`、`_removeHolder:192/195` | 与集合同步 |
| 13 | ERC721 继承 | `_owners` / `_balances` / `_tokenApprovals` / `_operatorApprovals` | 标准状态 | `super._update`（`:203`）与 OZ 的 `_approve` | 随转移/授权 |
| 14 | ERC721Enumerable 继承 | `_ownedTokens` / `_ownedTokensIndex` / `_allTokens` / `_allTokensIndex` | 按地址/全局的枚举 | `super._update` | 随转移 |

`_nextTokenId` 用**内联初值** `= 1`（`:26`）而不是构造器赋值。本合约不可升级，因此没有「实现合约的初值不生效」问题。

## 2. 逐变量变更逻辑

### 2.1 `init`（`:54-58`）

| 位置 | 语句 | 守卫 | 备注 |
| --- | --- | --- | --- |
| `:55` | `if (initialized) revert AlreadyInitialized()` | — | — |
| `:56` | `LOVE20_TOKEN_ADDRESS = firstTokenAddress` | 无零地址/代码校验 | 规格 `02-member-nft.md:40` 明确由部署 check 核对 |
| `:57` | `initialized = true` | — | 写在地址之后；中间无外部调用，顺序无风险 |

`init` **无调用者限制**，且只能成功一次。被抢跑的后果不是「参数错」而是「`Launch.init` 整笔回滚」：`Launch:75` 直接调用 `IMemberNFT.init(firstToken)`，第二次必然 `AlreadyInitialized`。由于 `Launch.init` 是首币与全部依赖接线的唯一入口，这一笔回滚等于整次部署作废（与既有审查 `DEP-01` 同源，此处只补具体后果）。

### 2.2 `mint` → `_mintMember`（`:60-101`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | `:63` | `prefixedName = _addTestPrefixIfNeeded(name)` | 读首币 `symbol()`；**前缀在此加入**，后续长度、唯一性、计费都用加前缀后的名字 |
| 2 | `:65` | `normalizedName = _checkName(prefixedName)` | 非空、`<= MAX_NAME_LENGTH`、字符集、`_tokenIdByNormalizedName == 0`（`:215-228`） |
| 3 | `:67` | `mintCost = calculateMintCost(prefixedName)` | 只按字节数计价，不校验合法性/唯一性（`:103-122`） |
| 4 | `:78` | `tokenId = _nextTokenId++` | 先取后增；ID 从 1 起，`0` 永远是「未设置」 |
| 5 | `:79` | `_memberNameByTokenId[tokenId] = name` | 原始名称（含前缀） |
| 6 | `:80` | `_tokenIdByNormalizedName[normalizedName] = tokenId` | **唯一性在此落账**，早于所有外部调用 |
| 7 | `:83` | `totalBurnedForMint += mintCost`（仅 `mintCost > 0`） | 与下一步同笔 |
| 8 | `:85` | `safeTransferFrom(memberOwner, this, mintCost)` | 外部调用；失败整笔回滚 |
| 9 | `:86` | `burn(mintCost)` | 外部调用；`LOVE20Token.burn` 无回调 |
| 10 | `:89` | `_safeMint(memberOwner, tokenId)` | 写 ERC721 全套状态；对合约接收者回调 `onERC721Received` |
| 11 | `:92-98` | `MemberMinted` | 后置 ID/名称/费用 |

**顺序评价**：唯一性键（`:80`）在第一次外部调用（`:85`）之前落账，因此重入 `mint` 无法用同名再铸一枚（第二次会在 `_checkName` 被拒）。这是本合约最重要的一条 CEI，写法正确。

### 2.3 `_update`：ERC721 状态与持有人集合（`:198-213`）

```solidity
from = super._update(to, tokenId, auth);          // 先写 _owners/_balances/枚举
if (from == to) return from;                       // 自转账：集合不动
if (from != 0 && balanceOf(from) == 0) _removeHolder(from);
if (to   != 0 && balanceOf(to)   == 1) _addHolder(to);
```

| 场景 | `from` | `to` | 读到的余额 | 集合动作 |
| --- | --- | --- | --- | --- |
| 铸造 | `0` | `X` | `balanceOf(X) == 1` | `_addHolder(X)` |
| 转移（发送方清空） | `A` | `B` | `balanceOf(A) == 0` | `_removeHolder(A)`；若 `balanceOf(B) == 1` 再 `_addHolder(B)` |
| 转移（发送方仍持有） | `A` | `B` | `balanceOf(A) > 0` | 只可能加 B |
| 自转账 | `A` | `A` | — | 早退，无动作 |
| 销毁 | `A` | `0` | `balanceOf(A) == 0` | `_removeHolder(A)` —— **无入口可达**（见 `NFT-04`） |

`balanceOf` 读的是 `super._update` **之后**的值，所以「减到 0」「加到 1」的判断都是后置状态，不会重复增删。

### 2.4 `_addHolder` / `_removeHolder`（`:179-196`）

| 函数 | 语句 | 前置 | 结果 |
| --- | --- | --- | --- |
| `_addHolder` | `index = _holders.length`；`push`；`_holderIndex[holder] = index` | 只在 `balanceOf(holder) == 1` 时调用 | 追加到尾部 |
| `_removeHolder` | `index = _holderIndex[holder]`；若 `index != last` 用尾元素填空并改尾元素下标；`pop`；`delete _holderIndex[holder]` | 只在 `balanceOf(holder) == 0` 时调用 | swap-and-pop，顺序不稳定 |

唯一可能出错的情形是「`_holderIndex[holder]` 失效」：若某地址不在集合里却带着 `0` 下标进入 `_removeHolder`，会把 `_holders[0]` 覆盖掉。该情形需要「余额归零但从未 `_addHolder`」，而所有铸造都经过 `_addHolder`，转移也不改变「是否曾加入」这一事实，因此不可达。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| N1 | `_nextTokenId` 严格递增，ID 永不复用 | ✅ | 唯一写入是 `++`；无 burn 入口，不存在「回收 ID」的路径 |
| N2 | `_tokenIdByNormalizedName[n] != 0` ⟺ 名称 `n` 已被占用（永久） | ✅ | 只写一次，无 `delete`；`0` 不是合法 ID |
| N3 | 每个已铸造 ID 必有非空 `_memberNameByTokenId` | ✅ | `:78-80` 同笔写入 |
| N4 | `_holders` == `{a | balanceOf(a) > 0}`，无重复，`_holderIndex` 指向正确位置 | ✅ | 由 `_update` 的三个分支维护；自转账早退 |
| N5 | `totalBurnedForMint` == Σ 已成功收取的身份费 | ✅ | `:83` 与 `:85-86` 同笔，失败整体回滚 |
| N6 | `Σ balances == _allTokens.length` | ✅ | OZ `ERC721Enumerable` |
| N7 | 名称映射的键只做 ASCII 小写折叠，不做 NFC/NFKC | ✅（按设计） | `:365-378`；后果见 `NFT-05` |

## 4. 发现

### NFT-04 · 没有 burn 入口，销毁分支是死代码，名称永久不可回收

| 字段 | 值 |
| --- | --- |
| 位置 | `:198-213`（`to == 0` 分支）、`:79-80`（永不清理的映射） |
| 级别 | Info |
| 证据 | E1 |

`ERC721` 与 `ERC721Enumerable` 都不提供公开 `burn`，本合约也没有自定义 burn。因此 `_update` 的 `to == 0` 分支**没有任何入口可达**，`_removeHolder` 只在「转出最后一枚」时被调用。连带后果：

1. `_nextTokenId` 永不回退，ID 空间单调增长（符合规格「ID 永不复用」）；
2. `_memberNameByTokenId` 与 `_tokenIdByNormalizedName` 只增不减，**名称一旦占用就永久占用**，即使该 NFT 被转到一个弃用地址；
3. 规格 `02-member-nft.md:79` 的「销毁（`to == 0`）：发送方此前余额为 `1` 时移除」描述的是一个不可达分支。

这不是缺陷（没有销毁入口是产品选择），但它是「名称稀缺性」的唯一来源：名称的价值来自永久占用。建议在规格里把该分支标注为「为未来 burn 预留」，避免读者以为存在销毁路径。

### NFT-05 · 黑名单遗漏「渲染为空白」的码点，可铸造视觉空名

| 字段 | 值 |
| --- | --- |
| 位置 | `:230-363`（`_isValidNameChars`）、`:223`（唯一性键） |
| 级别 | Info（与 `NFT-01` 同源，码点不同） |
| 证据 | E1 / E2 |

`_isValidNameChars` 的实现与规格 `02-member-nft.md:20-32` 的拒绝表**逐条一致**，问题在表本身漏了几类「占位符」字符。下列码点都能通过校验，且在常见字体里不显示任何笔画：

| 码点 | UTF-8 | 代码中的分支 | 渲染 |
| --- | --- | --- | --- |
| U+115F HANGUL CHOSEONG FILLER | `E1 85 9F` | 3 字节，`byte1 == 0xE1` 只拦 `9A 80` | 空白 |
| U+1160 HANGUL JUNGSEONG FILLER | `E1 85 A0` | 同上 | 空白 |
| U+3164 HANGUL FILLER | `E3 85 A4` | `byte1 == 0xE3` 只拦 `80 80` | 空白 |
| U+FFA0 HALFWIDTH HANGUL FILLER | `EF BE A0` | `byte1 == 0xEF` 只拦 `BB BF` | 空白 |
| U+2800 BRAILLE PATTERN BLANK | `E2 A0 80` | `byte2 == 0x80/0x81` 才拦 | 空白 |
| U+180E MONGOLIAN VOWEL SEPARATOR | `E1 A0 8E` | 同上 | 空白（`NFT-01` 已举证） |

后果：一个「看起来没有名字」的身份可以合法铸造，且名称永久占用；配合 `NFT-01` 的同形字，身份展示层无法用「名字非空」作为可信判据。建议把上表除 U+180E 外的 5 个码点加入拒绝表，或在 `_checkName` 增加「去除占位符后非空」的判定。

### 复核 `NFT-03`：尾部供应下身份费为 0

`baseCost = unmintedSupply / BASE_DIVISOR`（`:110`）。当 `unmintedSupply < BASE_DIVISOR` 时 `baseCost == 0`，`mintCost == 0`，`_mintMember` 跳过转账与销毁但**照常分配 ID 与名称**（`:82-87`）。开发参数 `BASE_DIVISOR = 1e7`、`MAX_SUPPLY = 1e28`，即最后 1e7 wei 的未铸量（约 1e-11 枚代币）对应免费身份，实际影响可忽略；但这是「价格公式的连续段」，不是异常。既有审查 `NFT-03` 已登记，本卷仅从写入路径确认：免费铸造不会跳过 `_tokenIdByNormalizedName` 的占用。

## 5. 已核对为正确的点

- 唯一性键在第一次外部调用之前落账（`:80` vs `:85`），重入无法绕过。
- `_safeMint` 的 `onERC721Received` 回调发生在 `_update` 之后，此时持有人集合已更新；回调内把 NFT 转走会再走一次 `_update`，集合仍自洽（先加后减）。
- 自转账 `from == to` 早退，不会把持有人从集合里删掉再加回来（顺序会变，但集合不变）。
- `_mintMember` 用局部变量 `tokenId`，事件读的是局部值，不受后续写入影响。
- `_checkName` 在 `_addTestPrefixIfNeeded` **之后**调用，前缀计入长度与唯一性；与规格 `02-member-nft.md:56` 一致。

## 6. 覆盖缺口

- 未跑 `holders()` 在大量增删后的下标一致性测试；结论来自 `_update` 的三个分支穷举。
- 未复核 OZ `ERC721Enumerable._update` 的内部写入顺序，按其公开语义认定。
