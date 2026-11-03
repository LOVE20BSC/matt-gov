# MemberNFT 事件赋值与发射审查

- 实现：`core/src/MemberNFT.sol`（379 行，`6fdd0f1`）
- 声明：`core/src/interfaces/IMemberNFT.sol`（`IMemberNFTEvents`）
- 规范：`docs/event-standards.md` v1.1、`docs/specs/core/02-member-nft.md`
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 1（+ 3 个 ERC-721 标准事件，按 §5.4 不属规范正文） |
| 发射点 | 1 |
| P0 / P1 / P2 / P3 | 0 / 0 / 1 / 0 |
| 放行 | 可放行；1 项 P2 为累计锚点口径 |

`MemberMinted` 是「铸造事实」而非「持仓事实」：`owner` 是铸造接收人，当前持有人只从 ERC-721 `Transfer` 折叠。持有人集合按 §5.4 不进事件。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 顺序特殊性 |
| --- | --- | --- | --- | --- |
| `MemberMinted` | `memberId`, `owner` | `_mintMember:92` | id/名称/规范化名 `:78-80`、费用与销毁 `:82-87`、`_safeMint:89` | E3：`_safeMint` 的 `onERC721Received` 回调先于本事件，重入产生的内层 `MemberMinted` 可先出现 |

族归属：`core.member`（对象 id → 角色 → 数值 → 文本）。

## 2. 逐事件赋值链

```
event MemberMinted(
    uint256 indexed memberId,
    address indexed owner,
    uint256 cost,
    string name,
    string normalizedName
);
```

| 字段 | 赋值来源（源码行） | 取值口径 |
| --- | --- | --- |
| `memberId` | `tokenId = _nextTokenId++` `:78` | 从 1 单调递增、不复用；与 ERC-721 `Transfer.to == owner` 的 `tokenId` 同源 |
| `owner` | 入参 `memberOwner`（`mint:68` 传 `msg.sender`） | **铸造接收人**，不是当前持有人；回调中把 NFT 转走不改写本字段（§7.1） |
| `cost` | 入参 `mintCost`（`mint:67` `calculateMintCost(prefixedName)`） | 本次实际转入并销毁的数量；按**加 `Test` 前缀后**的名称字节数计价 `:63,67`；可为 0 |
| `name` | 入参 `name`（`prefixedName`，`mint:63`） | 加前缀后的最终存储名，用于显示 |
| `normalizedName` | `_checkName(prefixedName)` 的返回值 `:65` → `_toLowerCase` `:223` | ASCII 大写转小写，不做 Unicode casefold；`_tokenIdByNormalizedName` 的键 |

发射链（`_mintMember`）：

1. `tokenId = _nextTokenId++` `:78`；
2. `_memberNameByTokenId[tokenId] = name` `:79`、`_tokenIdByNormalizedName[normalizedName] = tokenId` `:80`；
3. `mintCost > 0` 时：`totalBurnedForMint += mintCost` `:83` → `safeTransferFrom(memberOwner, this, mintCost)` `:85` → `ILOVE20Token.burn(mintCost)` `:86`（子调用发 `TokenBurned`）；
4. `_safeMint(memberOwner, tokenId)` `:89`（进入 `_update` 维护 `_holders`，发 ERC-721 `Transfer`；E3 回调在此）；
5. `emit MemberMinted` `:92`。

依赖序：`TokenBurned`（费用销毁）→ `Transfer`（铸造）→ `MemberMinted`。费用销毁先于铸造事件的顺序由源码固定；`MemberMinted.cost` 不依赖 `TokenBurned` 的载荷，因此不构成 §3.4.5 的硬依赖，但消费方按日志顺序先看到销毁再看到铸造，语义自洽。

动态字段上限（§6.8）：`name` 与 `normalizedName` 均受 `MAX_NAME_LENGTH` 约束——`_checkName:220` 在铸造前校验 `len <= MAX_NAME_LENGTH`，`_toLowerCase` 逐字节映射、不改变长度，故两个字段同界。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1，自身即根键可省） | 通过 | 无 `tokenAddress`；`memberId` 为首字段 |
| 族槽位（对象 id → 角色 → 数值 → 文本） | 通过 | `memberId` → `owner` → `cost` → 文本 |
| indexed ≤ 3（§6.3） | 通过 | 2 个；`memberId`、`owner` 均可过滤 |
| 动态字段上限（§6.8） | 通过 | `MAX_NAME_LENGTH` 链上强制 |
| 状态写入后 emit（§3.4.3） | 通过 | 名称、费用、`_safeMint` 均在 emit 前 |
| E3 逆序许可（§3.4.7） | 通过 | `MemberNFT.t.sol:619` 断言内外层 id 交错但事实正确 |
| 累计值锚点（§3.1） | **不通过** | 见 MN-1 |
| 失败不留日志（§3.5） | 通过 | 名称非法/重复、余额不足、费用溢出均整笔回滚 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | `MemberNFT.t.sol:562` 断言 `memberId`/`owner`/`cost`/`name`/`normalizedName`；`Alice` vs `alice` 可判别 |

## 4. 发现

### [P2] MN-1 `totalBurnedForMint` 未在 `MemberMinted` 中携带后置总量

- 证据：`MemberNFT.sol:28` 声明 `totalBurnedForMint`，`:83` 在 `_mintMember` 内累加；`MemberMinted` 的载荷只有 `cost`（增量），没有累计值。
- 问题：这是「只由一个事件类改变的单维聚合量」——与 §3.1 明确举例要求携带后置总量的 `Stake.totalBurnedToken` 同构。`Stake.FeesSettled` 携带了 `totalBurnedToken` / `totalParentTokenBurned`，`MemberNFT` 没携带，两个 core 合约在同一维度上口径不一致。
- 影响：链下无法在不重放全部 `MemberMinted` 的前提下与 `totalBurnedForMint()` 对账；跨合约对账（首币 `totalSupply == LAUNCH_AMOUNT - totalBurnedForMint`，见 `Launch.t.sol:249`）必须做全量折叠。可折叠性本身成立（`MemberNFT.t.sol:661` 已断言 `Σcost == totalBurnedForMint`），缺的是逐点锚点。
- 建议：`MemberMinted` 追加 `totalBurnedForMint`（放在 `cost` 之后），并按 §3.1 在 `02-member-nft.md` 事件节登记「增量 + 后置总量」；ABI 基线与 `events-baseline.txt` 同步更新。若判定该值属「可由 `cost` 直接求和」而豁免，需在 §3.1 的恒等/可折叠清单登记理由，避免与 `Stake.totalBurnedToken` 的处理互相矛盾。

## 5. 附：状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 |
| --- | --- | --- |
| `_nextTokenId` | `:78` | `MemberMinted.memberId`（单调、不复用可直接判定） |
| `_memberNameByTokenId` / `_tokenIdByNormalizedName` | `:79-80` | `MemberMinted.name` / `normalizedName` |
| `totalBurnedForMint` | `:83` | 仅 `MemberMinted.cost` 可折叠，无后置总量 |
| 余额 / 持有人集合 | OZ `_update` | ERC-721 `Transfer`（§5.4；`AddHolder`/`RemoveHolder` 已删除，`MemberNFT.t.sol:562` 反向断言不出现） |
| `LOVE20_TOKEN_ADDRESS` / `initialized` | `init:56-57` | 一次性初始化参数，§3.2 豁免；部署 check 核对 |
