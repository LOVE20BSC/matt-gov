# 首币 distributor 改用本仓 AirdropDistributor

## 状态

已接受 (2026-11-12)

## 背景

首币的全部分发一直由一个外部合约承担。上一版规格的写法是：Burn 活动结束后，从旧 `LOVE20TKM/burn` 代码库单独部署其 `Airdrop.sol` 到 BSC，作为首个代币 `distributor` 的外部依赖；部署记录公开指向 `Airdrop.sol`、`DeployAirdrop.s.sol` 与 `airdrop-design.md`。

这条路径带来三类成本：

1. **依赖边界模糊**。`core` 的首币分发依赖一个不在本组织仓库清单内的合约。对集成方来说，`Airdrop` 的 ABI、事件和错误既不在 `core/src/interfaces/` 里，也不受 `matt-gov` 的任何门禁守护：`check_errors.py`、`check_doc_payloads.py`、`check-events.py` 都扫不到它。全协议「自有 ABI 以各仓 `src/interfaces/` 为唯一来源」的规则在首币这条主路径上出现一个洞。
2. **验证成本落在人身上**。外部合约要靠「公开源码 + 部署记录」举证，而部署记录是人写的：来源提交、来源区块、Merkle Root、部署地址任何一项写错，都只能靠复核发现。本仓合约则可以被 ABI 基线与测试直接锁定。
3. **两条分发路径的语义会分叉**。普通发射的 distributor 是发射者自选的任意实现，首币的 distributor 是一个外部特例。同一份「首批供应按快照分发」的业务，在两处由两套代码、两套错误名、两套事件名承担。

另一项独立发现是份额归一化。外部 `Airdrop` 的 `totalShare` 是构造参数，构造函数只校验 `0 < totalShare <= 1e18`；对应的快照生成器只做 `require(totalShare <= WAD)`，是上限而不是恒等。多次 `mulDiv` 向下取整会掉尘埃，使 `Σleaves < 1e18`，差额部分永久无人可领，而链上没有任何手段发现这件事。

## 决策

**首币的 `distributor` 由「外部部署的旧 Burn Airdrop」改为本仓库的 `core/src/distributor/AirdropDistributor.sol`；`TOTAL_SHARE` 不用构造参数，硬编码为编译期常量 `1e18`，链下快照生成器必须把份额归一化到精确 `1e18`；独立 `launch` 仓库本阶段仍不创建。**

> 补充（同日）：本决策落地后追加了「快照 URI」能力，见 [后续：快照 URI 能力](#后续快照-uri-能力)。错误数由 11 增至 14、事件数由 2 增至 3，均只增不改。

具体后果：

- 新建 `core/src/distributor/AirdropDistributor.sol` 与 `core/src/interfaces/distributor/IAirdropDistributor.sol`；`ILaunchDistributor.sol` 迁入 `src/interfaces/distributor/`。错误按 local-first 在本模块的 `IAirdropDistributorErrors` 声明（11 个），事件在 `IAirdropDistributorEvents` 声明（2 个）。
- 首币由 `AirdropDistributor` 的构造函数完成配置：`(launchAddress, phaseAddress, genesisTokenAddress, genesisMerkleRoot, genesisClaimDelayRounds)`。部署顺序变为 `Phase → AirdropDistributor → Launch → MemberNFT → Stake → Submit → Vote → Mint`，首币地址由部署脚本按 `computeCreateAddress(launchAddress, 1)` 预测。`Launch` 构造函数不调用回调，首币仍固定 `NoCallback`。
- `TOTAL_SHARE = 1e18` 是编译期常量，不可按部署配置。份额分母统一，`claimableAmount` 与 `claim` 的分配公式对每个代币相同。
- 领取按剩余份额比例分配：`amount = floor(balanceOf(this) × share ÷ remainingShare)`，`remainingShare = TOTAL_SHARE - claimedShare`。最后一名份额恰为 `remainingShare` 的领取者清空合约余额。
- `claim` 的校验顺序固定为 存在性 → 状态 → 参数 → 账本 → 资格，共六层；其中 `share == 0` 是**显式拒绝**（回滚 `InvalidProof()`），位置在 `ShareExceedsRemaining` 与证明校验之前。零份额是链上链下双保险：链下生成器在 `_build()` 断言 `normalized[i] > 0` 拒绝产出零份额快照，链上仍独立拒绝，不依赖链下。
- 叶子格式与 Burn 快照生成器逐字节兼容：`keccak256(bytes.concat(keccak256(abi.encode(claimer, share))))`，节点按字节序排序后哈希，与 OpenZeppelin `MerkleProof` 的排序证明一致。旧 `LOVE20TKM/burn` 只作为**链上数据来源**（销毁活动结果）与**链下快照生成器工具**被引用，不再作为合约依赖；`Airdrop.sol`、`DeployAirdrop.s.sol`、`airdrop-design.md` 三个链接从规格中删除。
- 链下生成器补上归一化：先算 `rawTotal = Σshares`，再 `normalized[i] = floor(shares[i] × 1e18 ÷ rawTotal)`，把余数补给最大份额地址（并列取索引最小者），并断言 `Σnormalized == 1e18`。归一化必须在叶子构建之前完成，否则叶子哈希、JSON 份额与 Merkle Root 三者会不一致。「配满 100%」因此由三段独立事实串成：链下补尾差使 `Σ == 1e18`、`_build()` 断言 `Σ == 1e18` 且每个 `normalized[i] > 0`、链上 `TOTAL_SHARE` 是 `constant` 使发射者无法传入错误分母。
- `claimDelayRounds` 的语义写死为 `claimableFromRound = baseRound + claimDelayRounds`，其中 `baseRound = currentPhase() == 0 ? 1 : currentPhase()`；`delay = 0` 当轮可领。夹取的理由是 `Phase` 在 `ORIGIN_BLOCKS` 之前返回 `0`，而 `0` 不是有效轮次。
- 新增分页查询 `airdropInfos(offset, limit, reverse)`，返回 `AirdropInfo[]`（6 个字段：`tokenAddress` / `merkleRoot` / `claimableFromRound` / `claimedShare` / `remainingShare` / `contractBalance`）与 `totalCount`，使前端与索引器不必自己维护配置列表。语义与 `Phase.observations`、`Launch.tokens` 一致；不设独立计数入口，`airdropInfos(0, 0, false)` 即取基数。合约内新增只追加的 `_tokenAddresses` 列表作为分页数据源。
- 独立 `launch` 仓库本阶段仍不创建（`repositories.md` 的分阶段结论不变）。`AirdropDistributor` 归 `core`，理由是它与 `Launch` 的发射流程共用同一次回调、同一条非零 distributor 校验，且只有 214 行、远低于 24576 B 体积上限。

### 被否决的方案

**继续外部部署旧 `Airdrop.sol`。** 否决理由是不满足「自有 ABI 以 `src/interfaces/` 为唯一来源」：它的错误、事件和 `claimableAmount` 语义都不进本组织的错误目录与事件基线，首币这条主路径的失败契约无法由门禁保证。而且 `totalShare` 作为构造参数使「配满 100%」只能靠部署时的人工核对。

**把 `AirdropDistributor` 放进独立 `launch` 仓库。** 否决理由是当前没有其它业务需要它：`Launch` 是它唯一的配置来源，`core` 是它唯一的部署位置。为一个合约新建一个代码库会同时引入跨仓依赖、双份 CI 与版本对齐成本，与 `launch` 仓库「未来需求明确后再建」的原结论冲突。

**`TOTAL_SHARE` 作为构造参数。** 否决理由是它把「快照是否配满」从编译期硬保证降级为部署期配置。硬编码使错误的 `totalShare` 变成编译错误而不是部署事故；代价是历史快照若 `Σleaves != 1e18` 必须重新生成，这是可接受的。

**给 `claim` 加 `amount == 0` 检查。** 否决理由是分支不可达：`TOTAL_SHARE = 1e18`、`share == 0` 已被显式拒绝（故成功领取的 `share >= 1`）、部署脚本保证 `LAUNCH_AMOUNT >= 1e18` 且 `claim` 维持 `balanceOf(this) >= remainingShare`，故 `amount >= 1`。`LAUNCH_AMOUNT >= 1e18` 成为这条不变式的前提，由部署脚本在广播前校验。

**让零份额靠 merkle 校验顺带拒绝。** 初版如此，已推翻：归一化可能把极小份额截断为 `0`，若树中真存在零份额叶子，不做显式拒绝会走到「证明通过 → `amount == 0` → 置领取标记 → 转出 0 代币」，该地址领取成功却什么也没拿到，并永久失去该批资格。现改为显式拒绝，且不复用 `ShareExceedsRemaining`。

**引入 `ReentrancyGuard`。** 否决理由是三条前提同时成立时没有重入路径：`LOVE20Token` 无转账钩子；配置入口唯一（只接受 `LAUNCH_ADDRESS`，同一 token 二次配置回滚 `TokenAlreadyConfigured`）；`claim` 走 CEI 先写状态后转账。前提写进规格，任一条被破坏都必须重新评估。

## 后果

### 正面影响

1. **首币分发进入门禁**。`AirdropDistributor` 的 11 个错误自动进入 `registry/errors.{json,md}` 与 `check_error_tests.py` 的覆盖检查，2 个事件进入 `core/script/events/events-baseline.txt` 与族表，规格中的错误载荷由 `check_doc_payloads.py` 逐字段校验。
2. **「配满 100%」成为编译期保证**。`TOTAL_SHARE = 1e18` 不可能被配置错；链上只负责按份额比例分配，把份额正确性的责任集中到链下生成器这一处，而生成器有归一化断言与独立复算。
3. **首币与子币共用一套分发语义**。同一个合约既能作为首币 distributor（构造期配置），也能作为子币 distributor（`Callback` 模式配置），错误名、事件名、公式、轮次语义只有一份。
4. **部署记录从「举证外部合约」退化为「举证数据来源」**。公开记录只需覆盖来源链、来源区块、Merkle Root 与首币地址，不再需要证明一个外部合约的源码与部署对应关系。

### 负面影响

1. **部署顺序与地址预测整体前移**。新增 `AirdropDistributor` 占用 nonce +1，`Launch` 及其后所有合约的预测偏移量各加 1；部署脚本的每一处 `computeCreateAddress` 都要改，改错即在部署后核对处失败。本轮一次性完成。
2. **`TOTAL_SHARE` 不再可配置**。若将来出现「份额分母不同于 1e18」的需求，只能改源码并重新部署 `AirdropDistributor`。当前无此需求。
3. **链下生成器必须改**。旧生成器只做 `Σ <= 1e18` 的上限校验，归一化补丁改变了快照生成规则；历史快照若未归一化，`ValidateAirdropSnapshot` 会直接拒绝。已授权修改旧 `LOVE20TKM/burn` 的链下工具（只改脚本与文档，不改其生产合约）。
4. **`claimer` 命名已按名词表收敛**。首轮实现曾写作 `claimerAddress`，与 `naming-standards.md` §10「角色与流向地址保留角色名（`recipient`、`distributor`、`owner`）」冲突；该字段是 actor 而非实体地址，不带 `Address` 后缀。已在 ABI 冻结前统一改为 `claimer`，同步改 `ByClaimerAddress` → `ByClaimer`。

## 后续：快照 URI 能力

本决策落地后追加了「让子币发射者把 Merkle 快照 JSON 的 URL 登记到链上」的能力，使前端只读 `AirdropDistributor` 配置即可发现各子币快照、无需前端开发者手工整合（前端去中心化）。改动落在同一合约与接口，不新增构造参数：`MEMBER_NFT_ADDRESS` 从 `ILaunch(LAUNCH_ADDRESS).MEMBER_NFT_ADDRESS()` 派生（getter 已存在），URI 鉴权按 `IMemberNFT.ownerOf(launcherMemberId) == msg.sender` 实时判定，权限随 MemberNFT 转手；`launcherMemberId` 由 `onTokenLaunched` 回调第三个参数透传、配置期一次写定，创世币记为 `0`。新增 `AirdropInfo` 第 7 字段 `snapshotUri`、`MAX_SNAPSHOT_URI_BYTES = 256` 常量、`AirdropSnapshotUriUpdated` 事件与 3 个错误（`SnapshotUriEmpty`、`SnapshotUriTooLong`、`NotSnapshotUriUpdater`），错误与事件都只增不改。

**核心取舍：链上不校验 URI 指向的 Merkle 文件内容。** `snapshotUri` 是**发现提示（hint），不是授权**：Merkle Root 在配置后不可变，领取资格只由 `proof` 对链上 Root 的校验决定，链上既读不到链下文件、也不应把「谁能领多少」交给一个可改口的 URL。因此：

- 链上不 `fetch`、不校验文件内容与 Root 是否匹配，也不因 URI 改变而调整任何领取逻辑。若链上要做这件事，只能由调用方把整份快照或树数据传进合约，代价是把链下可独立完成、可反复复算的校验搬上链，且 Root 不可变的前提下这种校验对领取结果没有增益。
- 校验责任明确落在前端：`fetch(uri)` → 重建 Merkle 树 → 断言 `Σleaves == 1e18` 且重建 root == 链上 `merkleRoot` → 不匹配则**提交前拦截、不展示可领数量**。这把 URI 失效（错文件、被改成钓鱼站、失联）的最坏结果限定为「前端找不到数据」，不可能让任何人多领或少领，也不会产生错误的可领数量诱导。
- 代价是安全模型依赖前端正确实现这道校验；规格与验收把它写成明文前置条件，不靠链上兜底。这是「链上最小化 + 链下可独立复算」既有路线（Root 不可变、无管理员、无取回）的延续，不是新开的信任假设。

创世币 `launcherMemberId = 0`，因 `MemberNFT._nextTokenId = 1` 使 `memberId 0` 永不铸造，故创世 URI 永久为空且无人可设——刻意设计，首币快照仍由部署记录公开举证，不依赖某个发射者。`onlySnapshotUriUpdater` modifier 第一行是 `TokenNotConfigured` 存在性检查、第二行起才是鉴权：若把鉴权放最前，未配置 token 会先落到 `ownerOf(0)` 抛 OZ `ERC721NonexistentToken`，掩盖 `TokenNotConfigured`；modifier 整体仍是函数体第一道判定，满足 dev-standards §5.5。

## 关联

- [AirdropDistributor 规格](../specs/core/10-airdrop-distributor.md)
- [Launch](../specs/core/08-launch.md)
- [Core 验收](../specs/core/09-testing.md)
- [组织验收：首币空投分发](../acceptance.md#首币空投分发)
- [仓库清单](../repositories.md)
- [事件规范 §6.1 族表](../event-standards.md#61-字段顺序)：新增 `core.distributor` 族
- `core/src/distributor/AirdropDistributor.sol`、`core/src/interfaces/distributor/IAirdropDistributor.sol`
- 上一版结论（外部部署旧 Burn `Airdrop`）见 `matt-gov/.scratch/bsc-protocol-migration/issues/10-bsc-frontend-and-deployment.md`，由本决策取代；该票据保留为历史，不回写成新的讨论。
