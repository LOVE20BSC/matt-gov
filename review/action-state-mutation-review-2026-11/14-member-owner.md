# MemberOwner · 状态变量变更审查

> `action/src/MemberOwner.sol`，26 行，`action@0c1d1e2`。
> 职责：把 `IMemberNFT.ownerOf` 的「token 不存在」翻译成 `address(0)`，其余失败原样透传。**无状态、无事件、无错误定义**，但它是一个「错误翻译层」，因此本卷的审查对象是「翻译的边界」。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

无。文件内没有状态变量、常量、struct 或 mapping。

| 函数 | 签名 | 返回 | 说明 |
| --- | --- | --- | --- |
| `ownerOrZero` | `(address memberNFTAddress, uint256 memberId) → address` | 存在则返回 owner，不存在返回 `address(0)`，其他失败原样 revert | `internal view` |

两个调用方：

| 调用方 | 用途 |
| --- | --- |
| `GroupActionManager.groupOwnerOrRevert:42` | `owner == 0` → `GroupNotExist(groupId)` |
| `GroupServiceExecutor.onlyGroupOwner:57` | `owner == 0` → `GroupNotExist(groupId)` |

## 2. 逐变量变更逻辑

无状态写入。唯一的外部读是 `IMemberNFT(memberNFTAddress).ownerOf(memberId)`，用 `try/catch` 包裹。

| 路径 | 条件 | 行为 |
| --- | --- | --- |
| 成功 | `ownerOf` 返回 | 原样返回 owner |
| 失败 1 | `err.length >= 4 && bytes4(err) == ERC721NonexistentToken.selector` | 返回 `address(0)` |
| 失败 2 | 其他任何 revert（含空 returndata、其他 selector） | `assembly { revert(add(err, 0x20), mload(err)) }` 原样透传 |

第 3 条用 assembly 而不是 `revert(err)`，是为了保留**原始 returndata 的完整字节**（`revert(err)` 只能传 `bytes`，语义相同但会多一次 ABI 编码；assembly 直接转发内存）。注释（`:21`）说明「长度检查保证前四字节存在」，因此 `bytes4(err)` 的 cast 安全。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| Z1 | 返回 `address(0)` ⟺ `memberId` 不存在 | ✅ | ERC721 不可能把 token 铸给 `address(0)`（OZ 5.6.1 `_mint` 有 `ERC721InvalidReceiver(0)`），因此「存在且 owner 为 0」不可达 |
| Z2 | 除「不存在」外的所有失败都不被吞 | ✅ | 只匹配 `ERC721NonexistentToken.selector` 一个分支 |
| Z3 | 透传的 returndata 与原始字节相同 | ✅ | `assembly { revert(add(err, 0x20), mload(err)) }` |
| Z4 | 函数无状态、可安全内联到任意调用点 | ✅ | `internal view`，无存储访问 |

## 4. 发现

### M-MOS-01 · 只识别 `ERC721NonexistentToken` 一个 selector，其他「不存在」形态会透传

| 字段 | 值 |
| --- | --- |
| 位置 | `:18-19` |
| 级别 | Info |
| 证据 | E1 |

翻译层只认一个 selector。以下情形不会被翻译成 `address(0)`，而是把 NFT 的错误原样抛给调用方：

| 情形 | 实际错误 | 调用方期望 |
| --- | --- | --- |
| `MemberNFT` 是代理，代理层的 fallback 对未知 selector revert 自定义错误 | 代理的错误 | `GroupNotExist` |
| `MemberNFT` 地址上没有代码 | 空 returndata → `try/catch` 的 catch 分支拿到空 `bytes` → `err.length < 4` → 透传空 revert | `GroupNotExist`（或部署期就该失败） |
| 未来把 `MemberNFT` 换成 ERC721 的其他实现（错误 selector 不同） | 新 selector | `GroupNotExist` |

当前 `MemberNFT` 是 OZ 5.6.1 的 `ERC721` + `ERC721Enumerable`，`ownerOf` 的不存在路径固定回 `ERC721NonexistentToken(tokenId)`，因此第 1、3 行不可达。第 2 行（地址无代码）在部署脚本校验后不可达。

`SUP-01`（api-auth）已把这个「只吞一个 selector」登记为**正面样本**（口径清晰）。本卷从状态视角补一句：这个选择的代价是**「群不存在」的错误来源依赖 `MemberNFT` 的具体实现**——换实现时 `GroupNotExist` 会静默变成别的错误，而 `GroupActionManager` / `GroupServiceExecutor` 两处的 25 个业务入口都会受影响。

### M-MOS-02 · 群身份用「容错查表」、成员身份用「严格查表」，两种口径并存

| 字段 | 值 |
| --- | --- |
| 位置 | `:12-25`（容错）vs `ExecutorBase:29-34`、`GroupActionJoin:29-38`、`GroupActionVerify:50-59`（严格） |
| 级别 | Info |
| 证据 | E1 |

全仓对 `ownerOf` 有两种用法：

| 用法 | 位置 | 不存在时 |
| --- | --- | --- |
| 容错（`ownerOrZero`） | `GroupActionManager.groupOwnerOrRevert`、`GroupServiceExecutor.onlyGroupOwner` | `GroupNotExist(groupId)` |
| 严格（直接 `ownerOf`） | `ExecutorBase.onlyMemberOwner`、`GroupActionJoin.onlyMemberOwner`、`GroupActionVerify.onlyMemberOwner`、`ActionTarget.onlyMemberOwner` | 透传 `ERC721NonexistentToken(memberId)` |

两种口径的差别不是实现细节，而是**错误契约**：调用方传一个不存在的 `groupId` 得到 `GroupNotExist`，传一个不存在的 `memberId` 得到 `ERC721NonexistentToken`。前者是本协议的领域错误，后者是 ERC721 的标准错误。

规格 `05:115` 明确要求「链群身份不存在的错误落点：群管理、`join`、`addProviderQuota`、`removeProviderQuota` 回滚 `GroupNotExist(groupId)`」，但没写「成员身份不存在时回什么」。链下按 `GroupNotExist` 分类「身份不存在」会漏掉所有成员侧的失败。

## 5. 已核对为正确的点

- `address(0)` 作为「不存在」哨兵无歧义（Z1）：ERC721 不允许零地址 owner，因此「存在但 owner 为 0」不可达。
- 只吞一个 selector（Z2），其余原样透传——这是「最小翻译面」的正确形态，不会掩盖 NFT 的真实故障。
- 透传用 assembly 保留原始 returndata（Z3），调用方（或调试工具）能看到 NFT 的原始错误，而不是被包一层。
- `try/catch` 的存在使「群不存在」成为**领域错误**而不是「NFT 层的错误」，两个群管理入口因此能给出 `GroupNotExist` / `NotGroupOwner` 两个可区分的错误（`GAM-04`/`GSE-07` 已登记为正面）。
- 函数无状态、无事件，可被任意调用点内联，不会引入存储读写或重入面。

## 6. 覆盖缺口

- `try/catch` 在 EVM 上总是编译成一次真实的外部调用 + returndata 拷贝，无法内联成一次 `STATICCALL` 之外的形态。因此每个群管理入口都比「直接 `ownerOf`」多付一次 returndata 拷贝与 selector 比较——未量化这部分 gas。
- 未审 `MemberNFT` 若被替换成非 OZ 实现时 `ownerOf` 的错误 selector 会是什么（结论：`ownerOrZero` 会透传，`GroupNotExist` 不再出现）。
- 未测「`memberNFTAddress` 指向无代码地址」时的实际 revert 数据（按 `try/catch` 语义应为空 `bytes`，但未跑用例）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-MOS-01` | 口径登记 | 只翻译 `ERC721NonexistentToken` 一个 selector，其余错误原样透传；05 规格已按此描述，不改源码 |
| `M-MOS-02` | 规格补写 | [`05-group-action-executor.md`](../../docs/specs/action/05-group-action-executor.md) 的「状态口径」：成员身份严格查表（`ownerOf` 失败即回滚），群身份容错（零地址回 `0`） |
