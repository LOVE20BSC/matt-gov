# MemberNFT 接口调用权限审查

> 对象 `core/src/MemberNFT.sol`（379 行）
> 接口 `core/src/interfaces/IMemberNFT.sol`（74 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/02-member-nft.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 31（自有 15 / 继承 OZ 16） |
| 写入口 | 7（自有 2 + OZ 标准 5） |
| 带鉴权 modifier | **0** |
| 无许可写入口 | 7（`init`、`mint` + OZ `approve`/`setApprovalForAll`/`transferFrom`/`safeTransferFrom` ×2） |
| 发现 | 5 条：Medium 1（与 DEP-01 同源）/ Info 4 |
| 接口对账 | 31 vs 31，**0 差异** |

一句话：**这是全仓唯一「零鉴权 modifier」的合约——但它的 `ownerOf` 是其他五个合约的鉴权函数。它自己不需要鉴权：身份是任何人都能买的公共品，`init` 是唯一一次性的绑定入口，其余写操作都是 ERC721 标准语义。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 任何地址 | 无（支付身份费） | `mint` |
| 任何地址 | 无（一次性） | `init` |
| NFT 持有人 / 被授权方 | OZ ERC721 标准（`_update`、`_isAuthorized`） | `approve`、`setApprovalForAll`、`transferFrom`、`safeTransferFrom` ×2 |
| 无 | — | 24 个只读入口 |

本合约**不定义任何 `modifier`**，也不读取 `msg.sender` 做业务判定。`check_caller_auth.py` 对本文件无输出，符合预期：没有调用者校验，就没有「校验写错地方」的问题。

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 事件 |
| --- | --- | --- | --- |
| `init(address firstTokenAddress)` | 无（一次性） | `if (initialized) revert` | **无** |
| `mint(string name)` | 任何地址（付费） | 无；费用从 `msg.sender` 划转并销毁 | `MemberMinted` |
| `approve(address,uint256)` | NFT 持有人或被授权方 | OZ `_isAuthorized` | `Approval` |
| `setApprovalForAll(address,bool)` | NFT 持有人 | OZ `_isAuthorized` | `ApprovalForAll` |
| `transferFrom(address,address,uint256)` | 持有人或被授权方 | OZ `_update` + `_isAuthorized` | `Transfer` |
| `safeTransferFrom(address,address,uint256)` | 同上 | 同上 + `onERC721Received` | `Transfer` |
| `safeTransferFrom(address,address,uint256,bytes)` | 同上 | 同上 | `Transfer` |

### 只读入口（24）

自有配置 7：`LOVE20_TOKEN_ADDRESS`、`BASE_DIVISOR`、`BYTES_THRESHOLD`、`MULTIPLIER`、`MAX_NAME_LENGTH`、`initialized`、`totalBurnedForMint`。

自有查询 6：`calculateMintCost`、`memberName`、`isNameUsed`、`memberId`、`normalizeName`、`holders`。

OZ 标准 11：`name`、`symbol`、`tokenURI`、`balanceOf`、`ownerOf`、`getApproved`、`isApprovedForAll`、`totalSupply`、`tokenByIndex`、`tokenOfOwnerByIndex`、`supportsInterface`。

## 四、逐入口判定

### `init` — 一次性的定价源绑定

- 无调用者限制、只判 `initialized`，与 `01-common-rules.md` 一致。
- 绑定的是 `LOVE20_TOKEN_ADDRESS`，它决定两件事：
  1. **身份价格**：`calculateMintCost = (MAX_SUPPLY - totalSupply) / BASE_DIVISOR × MULTIPLIER^n`，全部读该代币；
  2. **名称前缀**：`_addTestPrefixIfNeeded` 读该代币的 `symbol()`，以 `Test` 开头则给所有新名字强制加前缀。
- 因此**抢跑 `init` 等于同时夺取「身份定价权」与「名称空间前缀控制权」**；更直接的是，`Launch.init` 内部会调 `IMemberNFT(...).init(firstToken)`（`Launch.sol:75`），一旦本合约被抢先初始化，`Launch.init` 整笔 revert `AlreadyInitialized()`，协议只能重新部署。
- 无 `code.length` 校验：绑定 EOA 时 `init` 会成功（`init` 无返回值，对无代码地址的高层调用不 revert），随后 `mint`/`calculateMintCost` 因读取 `symbol()` 而 revert。部署 check 负责兜底。

### `mint` — 无许可的公共铸造

- 任何人可为自己铸造一个身份，无需邀请、白名单或管理员批准。这是「身份是公共品」的设计。
- 权限边界：`tokenId` 由 `_nextTokenId++` 分配，`_memberNameByTokenId` 与 `_tokenIdByNormalizedName` 同时写入；`_safeMint(memberOwner = msg.sender, …)`。**没有把 tokenId 或名字写给别人的分支**，所以不存在「代他人铸造」的越权面。
- 费用路径：`safeTransferFrom(msg.sender → this, mintCost)` 后 `burn(mintCost)`，两笔都作用于调用者自己的余额；`totalBurnedForMint` 累加。
- 无重入锁：`_safeMint` 会触发接收者 `onERC721Received`，但所有状态（名字映射、`totalBurnedForMint`、`_nextTokenId`）都在 `_safeMint` 之前写完，重入只会分配新的 `tokenId`，没有共享状态竞争。
- 未初始化时 `LOVE20_TOKEN_ADDRESS == 0`，`symbol()`/`MAX_SUPPLY()` 调用 revert，`mint` 不可用——规格已声明「未初始化时 `mint` 与 `calculateMintCost` 回滚」。

### OZ 标准入口 — 授权只覆盖转移，不覆盖业务

`approve`/`setApprovalForAll` 授予的是**转移权**，不是业务权。协议其余五个合约的成员入口一律用 `ownerOf(memberId) == msg.sender`，因此：

| 场景 | 是否可行 |
| --- | --- |
| 被授权方 `transferFrom` 把身份转给他人 | 可行（OZ 标准） |
| 被授权方代替持有人 `stakeLiquidity` / `vote` / `submit` / `mintGovReward` | **不可行**（`ownerOf != msg.sender`） |
| 多签合约持有 NFT 后自行调用业务入口 | 可行（`msg.sender` 即合约） |

这是 `01-common-rules.md`「钱包地址仅作控制者或调用者，处分权益时校验 `ownerOf == msg.sender`」的直接结果，不是实现偏差。但它意味着**协议的业务权限粒度比 ERC721 的授权粒度更粗**：想委托业务操作，只能整体转移 NFT（连同解锁倒计时、未领奖励、发射次数一起转移）。

### `_update` 钩子维护持有人集合

`holders` 数组在 `_update` 内维护：`from` 余额归零则移除，`to` 余额从 0 变 1 则追加。`_update` 只由 OZ 的 mint/transfer/burn 调用，外部无法直接触发；`_addHolder`/`_removeHolder` 是 `internal`。无权限面。

## 五、发现

### NFT-01（Medium，与 DEP-01 同源，不新增计数）`init` 抢跑可夺取定价权并阻断 Launch

- 证据：`init` 无调用者限制（`L54-58`）；`LOVE20_TOKEN_ADDRESS` 决定 `calculateMintCost`（`L103-122`）与 `_addTestPrefixIfNeeded`（`L154-177`）；`Launch.init` 会代调本合约 `init`（`Launch.sol:75`）。
- 影响：① 抢跑者把 `LOVE20_TOKEN_ADDRESS` 指向自建代币，可把身份价格压到接近 0（自建代币的 `MAX_SUPPLY - totalSupply` 由它决定），并控制名称前缀；② `Launch.init` 随后必然 revert，协议需重部署。
- 兜底：`DeployCore` 部署后核对首币地址与 `initialized()`（`DeployCore.s.sol` 的绑定检查段），`21_check.sh` 独立复核。
- 判定：与 DEP-01 同一根因，不新增计数。补充结论：**这是唯一一处「无鉴权入口直接影响其他合约能否完成初始化」的耦合**，发布检查应把「MemberNFT 是否被抢先初始化」作为独立检查项。

### NFT-02（Low）`init` 未校验 `firstTokenAddress` 有代码

- 证据：`init` 只判 `initialized`（`L53` 有一行 `// forge-lint: disable-next-item(missing-zero-check)`），不校验零地址与代码。
- 影响：绑定 EOA/零地址时 `init` 成功（`init` 无返回值），此后 `mint` 与 `calculateMintCost` 永久 revert，且无重初始化路径。
- 与规范的关系：dev-standards §5.7 把「依赖是否有代码」划给部署脚本，所以合约不校验是**符合分工**的；`01-common-rules.md` 也明说「依赖代码与派生值由 `DeployCore` 部署后校验」。
- 判定：不构成实现缺陷。但本合约的后果是「身份铸造永久不可用」，比一般依赖错绑更重，建议在 `02-member-nft.md` 的部署期不变量里显式列出「`LOVE20_TOKEN_ADDRESS` 必须是首币且 `symbol()` 可读」。

### NFT-03（Info）`mint` 无重入锁，但 CEI 成立

- 证据：状态写入（`_nextTokenId`、名字映射、`totalBurnedForMint`、转账、销毁）全部在 `_safeMint` 之前（`L78-89`）。
- 判定：重入只会产生新的 `tokenId`，等价于同一交易内连续铸造两次。名字从「检查」到「写入」之间只隔 `calculateMintCost`（`view` 外部读取），没有任何能写 `_tokenIdByNormalizedName` 的路径，因此不存在名字被抢占的窗口。
- 记录为正面样本：**无锁但安全，因为不存在「读—外部调用—写」的窗口**。

### NFT-04（Info）`normalizeName` 只折叠 ASCII 大小写，接口未声明

- 证据：`_toLowerCase` 只处理 `0x41-0x5A`（`L365-378`）；`02-member-nft.md` 已明确「不做 Unicode casefold，也不做 NFC/NFKC」。
- 判定：与规格一致。接口层不写 NatSpec（§4.1），所以唯一性语义只能从规格读；集成方若按 `normalizeName` 自行判重，会得到与合约一致的结论。不构成问题。

### NFT-05（Info）`init` 无事件，且未在规格写明理由

- 证据：`init` 只写 `LOVE20_TOKEN_ADDRESS` 与 `initialized`，无事件。
- 规范：§4.2 允许「确无观测价值的写函数（如 `init`）为例外，须在对账文档写明理由」。`02-member-nft.md` 说明了绑定必须由部署 check 核对，但没有直接写「因此不发事件」。
- 建议：在 `02-member-nft.md` 的 `init` 段落补一句，与 `Launch.init` 发 `GenesisTokenCreated` 的差异一并说明（Launch 的首币创建是业务事件，MemberNFT 的绑定只是配置）。

## 六、核对证据

```text
$ forge inspect MemberNFT abi --json          # 31 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

本合约无鉴权分支，故无 `NotMemberOwner` 类负例；`MemberNFT.t.sol` 覆盖名称校验、费用计算、`holders` 增删与转移后余额归零的移除路径。

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 上游 | `Launch.init` | 代调 `init(firstToken)`；抢跑窗口的另一半 |
| 上游 | `LOVE20Token`（首币） | `MAX_SUPPLY`、`totalSupply`、`symbol`、`burn`、`transferFrom` 全部读/调它 |
| 下游 | `Stake`/`Submit`/`Vote`/`Mint`/`Launch` | 它们的 `onlyMemberOwner` 全部以本合约 `ownerOf` 为判据——**本合约是五个合约的鉴权函数** |
