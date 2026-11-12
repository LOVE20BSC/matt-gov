# AirdropDistributor

AirdropDistributor 是首币与普通发射共用的可选 distributor：接收首批代币，按 Merkle 快照把该批供应分发给快照地址。它只做分发，不迁移 Burn 业务，也不在链上验证快照来源。完整 ABI 见 [`IAirdropDistributor.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/distributor/IAirdropDistributor.sol)。

## 职责与依赖

合约负责：

- 为每个已配置的 `tokenAddress` 保存一份 Merkle Root 与可领取起始轮次。
- 校验「地址 + 份额」的 Merkle 证明，并按该代币的合约余额与剩余份额计算本次领取量。
- 只允许快照地址本人提交证明并领取。
- 为已配置代币保存一份「快照 URI」发现提示与发射者 `launcherMemberId`，并提供由当前 `launcherMemberId` 持有人更新的入口；URI 只作前端发现用，不参与任何领取判定。

合约不负责：

- 不在链上验证快照的来源链、来源区块、叶子份额之和，也不验证快照 URI 指向的文件内容与链上 Root 是否匹配；完整快照必须公开供任何人独立复算。
- 不登记、枚举或限制代币；领取时由调用者传入 `tokenAddress`。
- 不支持部分领取、同币重复领取或单笔多代币领取。
- 不设管理员、暂停、升级、截止时间、Root 更新或资产取回入口。

构造函数固定 `LAUNCH_ADDRESS` 与 `PHASE_ADDRESS`，按 `(launchAddress, phaseAddress, genesisTokenAddress, genesisMerkleRoot, genesisClaimDelayRounds)` 传入。两者都是部署后冻结的值，声明为 `public immutable`、以大写命名并直接提供同名 getter，与 `core` 其他构造函数冻结值（`Phase.ORIGIN_BLOCKS`、`LOVE20Token.MAX_SUPPLY`）一致——`immutable` 让「任何人都不可能改写它」由编译器保证，而不是靠「没有第二个写入口」的约定。

- `LAUNCH_ADDRESS` 是 `onTokenLaunched` 的唯一允许调用方；除构造函数这条首币路径外，它是唯一的配置写入路径。
- `PHASE_ADDRESS` 只用于读取 `currentPhase()`，是 `claimableFromRound` 的时间基准。
- `MEMBER_NFT_ADDRESS` **不新增构造参数**：快照 URI 鉴权需要的 MemberNFT 地址从 `LAUNCH_ADDRESS` 派生，即运行时读取 `ILaunch(LAUNCH_ADDRESS).MEMBER_NFT_ADDRESS()`（该 getter 已存在）。这与 dev-standards §5.2「能由入参地址的 getter 派生的依赖，不再重复入参」一致；不在构造期缓存该地址，因此 MemberNFT 部署顺序与地址预测不受本能力影响。
- 构造函数不做静态零值校验；依赖地址与首币配置由部署脚本在广播前校验、部署后核对，见 dev-standards §5.7。
- 部署时 `launchAddress` 与首币地址都尚未存在，由部署脚本按部署者 nonce 预测后传入，并在 `Launch` 部署后核对；首币地址恒为 `computeCreateAddress(launchAddress, 1)`。

构造函数在同一次部署内调用首币配置路径，因此首币在构造期即完成配置，不需要 `Launch` 回调。`Launch` 构造函数不调用 distributor 回调（首币固定 `NoCallback`），见 [Launch](08-launch.md#部署与首个代币)。构造期发出的 `AirdropConfigured` 是已登记的第二处「构造函数可发业务事件」例外：首币的配置没有其它事件覆盖，不在构造期发就只能丢失这次状态迁移，理由见 [通用规则](01-common-rules.md#部署与安全)。

## 常量

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `TOTAL_SHARE` | `1e18` | 每个代币快照的份额分母，编译期常量，不可按部署配置 |
| `MAX_CLAIM_DELAY_ROUNDS` | `1000` | `claimDelayRounds` 的上限，单位 Phase |
| `MAX_SNAPSHOT_URI_BYTES` | `256` | `snapshotUri` 的链上字节上限，`updateSnapshotUri` 写入前按 `bytes(snapshotUri).length` 校验 |

`MAX_SNAPSHOT_URI_BYTES` 使 `snapshotUri` 这个 `string` 虽变长但有 256 字节链上硬上限：单条记录最大体量有界，页内体量与 `limit` 成正比，不构成 dev-standards §4.3(2) 所禁止的无界记录。这是我们有意选择「`airdropInfos` 分页直接返回含 `string` 的 `AirdropInfo`」而非「分页只回 id、另设按 id 批量读」的论证——记录里的 `string` 受常量约束，不会像 §4.3(2) 担心的「一条大记录把整页顶过 gas 上限且跳不过去」，故分页可以回记录本体。上限对事件里的新值与旧值同样成立，见 [快照 URI 更新 · 事件字段](#事件字段) 与 [event-standards §6.8](../../event-standards.md#68-动态字段上限)。

`TOTAL_SHARE` 恒为 `1e18`，代币之间共用同一分母。「快照配满 100%」由三段各自独立成立的事实串成完整论证链，缺任何一段都不成立：

1. **链下补尾差**：链下生成器的 `normalizeShares()` 先算 `rawTotal = Σshares`，再 `normalized[i] = floor(shares[i] × 1e18 ÷ rawTotal)`，然后把 `1e18 − Σnormalized` 的尾差补给它本批份额最大的地址（并列取索引最小者）。`floor` 只丢尘埃，故 `Σnormalized <= 1e18` 恒成立，尾差不超过 `地址数 − 1` wei，补给后 `Σnormalized == 1e18` 精确相等。
2. **链下断言**：`_build()` 断言 `Σnormalized == 1e18` 且每个 `normalized[i] > 0`，并且归一化在**叶子构建之前**完成——叶子哈希、快照 JSON 中的份额与 Merkle Root 三者基于同一份数组，不可能互相不一致。任一断言失败即拒绝产出快照。
3. **链上不可能配错**：`TOTAL_SHARE` 是编译期 `constant`，不进构造函数、不是部署参数，发射者与部署脚本都无法传入错误的分母。

三段合起来才使「按份额比例分配」有确定的分母与确定的分子。只做到 `Σleaves <= 1e18` 不够：`1e18 − Σleaves` 的差额会永久留在合约里，任何地址都领不到，而链上没有任何手段发现这件事。归一化由链下工具保证，链上只消费结果，不重复校验。

## 状态

按 `tokenAddress` 保存，全部为 `internal` 映射，对外只经同名 getter 读取。

| 状态 | 键 | 值 |
| --- | --- | --- |
| Merkle Root | `tokenAddress` | 该批快照的根；零值表示未配置，是「是否已配置」的唯一判据 |
| 可领取起始轮次 | `tokenAddress` | `claimableFromRound`，单位 Phase，配置时一次写定 |
| 已领份额 | `tokenAddress` | `totalClaimedShare`，累计被成功领取消耗的份额 |
| 领取标记 | `tokenAddress` + `claimer` | 是否已领取该代币 |
| 已领金额 | `tokenAddress` + `claimer` | 该地址成功领取时实际转出的代币数量（与 `AirdropClaimed.amount` 同值） |
| 快照 URI | `tokenAddress` | `snapshotUri`，快照 JSON 的发现提示 URL；默认空串，仅由 `updateSnapshotUri` 写入，每次更新发事件（含旧值） |
| 发射者 memberId | `tokenAddress` | `launcherMemberId`，配置时一次写定；`0` 表示创世币，`updateSnapshotUri` 永久拒绝 |

另有一个按配置顺序追加的 `tokenAddress` 列表，供 `airdropInfos` 分页读取；首币是首个元素。列表只追加，不删除、不重排。

`launcherMemberId` 与 Root、起始轮次一样在配置时一次写定，此后没有第二写入点：`_configure` 的第四个参数由 `onTokenLaunched` 的 `launcherMemberId` 透传，构造函数为首币传 `0`。`snapshotUri` 是唯一可反复写入的状态，可由该 token 记录里的 `launcherMemberId` 对应的 `MemberNFT.ownerOf` 当前持有人更新；它不参与任何领取判定。`totalClaimedShare` 只增不减；领取标记与已领金额只会由「未领取」变为「已领取」。

## 份额与金额

```text
remainingShare = TOTAL_SHARE - claimedShare
amount = floor(balanceOf(this) × share ÷ remainingShare)
```

- `share` 是快照叶子中该地址的份额，最小单位为 `1e18` 分之一（`TOTAL_SHARE` 为 `1e18` 时，份额 `1e16` 表示 1%）。
- `totalRemainingShare` 是**配置时点起算的剩余份额**，不是剩余资产比例；未领取时等于 `TOTAL_SHARE`。
- `amount` 按合约在领取时点的实际余额计算，用 `Math.mulDiv` 取 512 位中间结果后向下取整，不溢出、不先除后乘。
- 分母不为零：`totalClaimedShare` 只在成功领取时增加，且每次成功领取都满足 `share <= remainingShare`，因此 `claimedShare < TOTAL_SHARE` 恒成立。
- 按剩余份额分配使后领取者按剩余资产的比例分享：最后一名份额恰为 `totalRemainingShare` 的领取者得到 `balanceOf(this)` 全部，合约余额清零。
- 公式本身不假设 `Σleaves == 1e18`，那是链下的责任：分母恒为 `1e18`，若叶子份额之和不足，差额无人可领；若超出，先领取者按比例分走资产，后领取者在 `totalRemainingShare` 耗尽后无法领取。

例如某一批快照只有两个叶子，份额为 `6e17` 与 `4e17`，配置时合约余额 `1000`（代币最小单位）。第一人领取 `floor(1000 × 6e17 ÷ 1e18) = 600`，此后余额 `400`、`remainingShare = 4e17`；第二人领取 `floor(400 × 4e17 ÷ 4e17) = 400`，余额归零。若顺序相反，第一人得 `400`、第二人得 `600`：两人各自占本批总额的比例不变，且都不超过自己份额对应的比例。

## 代币配置

两个入口共用同一条配置路径 `_configure(tokenAddress, merkleRoot, claimDelayRounds, launcherMemberId)`：构造函数用它为首币写入配置（`launcherMemberId = 0`），`onTokenLaunched` 用它为普通发射的子币写入配置（`launcherMemberId` 取回调第三个参数）。因此首币与子币的错误集合、判定顺序、轮次夹取完全一致；只有 `launcherMemberId` 的取值不同。

### onTokenLaunched（回调）

仅 `LAUNCH_ADDRESS` 可调用。`Launch` 在代币创建、首批供应到账、代币登记与次数扣减之后调用一次，原样透传 `distributorData`；`Launch` 不开放额外的补触发回调入口。

回调数据格式固定：

| 条件 | 值 |
| --- | --- |
| `distributorData` 元素个数 | 恰好 `1` |
| `distributorData[0]` 字节长度 | 恰好 `64` |
| 解码方式 | `abi.decode(distributorData[0], (bytes32, uint256))`，依次为 `merkleRoot`、`claimDelayRounds` |

`Launch` 只原样透传，不解析、不遍历；形状校验全部在本合约完成，任一不符即整笔发射回滚。

### 轮次夹取与 claimDelayRounds

```text
baseRound = currentPhase() == 0 ? 1 : currentPhase()
claimableFromRound = baseRound + claimDelayRounds
```

- `Phase` 在 `ORIGIN_BLOCKS` 之前返回 `0`，而 `0` 不是有效轮次；夹取到 `1` 使创世前的配置不会因为 `currentPhase() == 0` 而落到一个更早的、非法的起始轮次。
- `claimDelayRounds = 0` 表示**当轮可领**：当前轮次等于 `claimableFromRound` 即可领取，不等下一轮。这在首币场景下是常态——首币跟随部署所在轮次，配置完成后的同一轮就能领。
- `claimDelayRounds = 1` 表示配置后的下一轮才可领，以此类推。
- 上限 `MAX_CLAIM_DELAY_ROUNDS = 1000` 是协议常量，不按部署配置；超过即拒绝，不做截断。
- `claimableFromRound` 是配置时点的一次性快照，此后不随 `Phase` 校准或段长变化改写。

### 校验顺序与错误集合

首币与普通发射共用同一条 `_configure` 路径，因此两处的错误集合、判定顺序与轮次夹取完全一致。只有入口不同：构造函数直接传入三个参数，`onTokenLaunched` 先从 `distributorData` 解出 `merkleRoot` 与 `claimDelayRounds`。下表从 `onTokenLaunched` 的入口开始，构造函数的入口从第 4 步起（没有鉴权与形状校验两道）。

```text
1. 鉴权  调用者不是 LAUNCH_ADDRESS                   → NotLaunchContract(address caller)
2. 参数  distributorData.length != 1                 → InvalidDistributorDataCount(uint256 count, uint256 expectedCount)
3. 参数  distributorData[0].length != 64             → InvalidDistributorDataLength(uint256 length, uint256 expectedLength)
4. 存在  tokenAddress 已配置                         → TokenAlreadyConfigured(address tokenAddress)
5. 参数  merkleRoot == bytes32(0)                    → ZeroMerkleRoot()
6. 参数  claimDelayRounds > MAX_CLAIM_DELAY_ROUNDS   → ClaimDelayRoundsExceeded(uint256 claimDelayRounds, uint256 maxClaimDelayRounds)
```

第 2、3 步必须先于解码：字节序列未通过形状校验时无法安全 `abi.decode`。第 4 步排在参数校验之前，偏离 [错误与回滚标准](../../error-standards.md#五失败契约) 的默认序「参数 → 存在性」；理由是重复配置是比载荷内容更根本的拒绝条件——对已配置的 token，第二次配置无论载荷是什么都非法，先命中先回滚使失败原因不随载荷变化。首币与子币共用这条判定，故两处的错误优先级一致。

解码后 `merkleRoot` 为零即 `ZeroMerkleRoot()`；`claimDelayRounds` 为零是合法值。

成功配置时按固定顺序做四件事：先写 Root、`claimableFromRound` 与 `_launcherMemberIdByTokenAddress[tokenAddress] = launcherMemberId`，再把 `tokenAddress` 追加到列表，最后发出 `AirdropConfigured(tokenAddress, merkleRoot, claimableFromRound)`——`push` 发生在 `emit` 之前，因此事件发出时链上状态已经就绪，索引器收到日志时无需等待后续写入。`AirdropConfigured` 保持 3 字段，不携带 `launcherMemberId`，也不在配置期写入 `snapshotUri`（回调数据是严格 64 字节，不含 URI；URI 默认空串，由 `updateSnapshotUri` 单独写入）。`tokenAddress` 带 `indexed`；`merkleRoot` 是本次写入的根；`claimableFromRound` 是夹取与延迟相加后的**最终起始轮次**，索引器无须回算 `baseRound`。

同一 token 的第二次配置一律回滚 `TokenAlreadyConfigured(tokenAddress)`：没有 Root 更新入口，也没有删除入口。

## 领取

`claim(tokenAddress, share, proof)` 是无许可写入口，任何人都能调，但不是「替他人领取」。

### 仅本人领取

叶子中的地址恒为 `msg.sender`，本合约不提供指定收款地址的参数，也没有代领路径：

```text
leafHash(msg.sender, share) = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, share))))
```

符合「调用者没有任何指向他人的参数」的无许可判据（见 [通用规则](01-common-rules.md#无许可入口)）。理由：

- 领取是受益人对自己份额的处分，他人代领在协议上没有语义。
- 快照完成后份额边界是固定的，一次申领的收益全部进入受益人自己余额，没有可以挪走的收款地址，也没有可被抢跑改变的数量——`amount` 由 `share ÷ remainingShare` 的固定比例决定，抢跑只会改变同批其他人的相对所得比例，不改变任何人的绝对份额。
- 任何地址都能为某个快照地址提交证明，但没有动机：结果与受益人自己提交完全一致，且支付的是提交者的 gas。

`claim` 没有 `only*` modifier，**不设调用者限制**（`dev-standards` §5.5 要求对无限制写函数明文说明，不靠「没挂 modifier」隐式表达）。函数第一行把 `msg.sender` 快照进局部变量 `claimer`，此后全部判定与写状态都用该局部变量，语义与直接用 `msg.sender` 等价。

### 校验顺序与执行顺序

完整执行顺序共 12 步。第 1–7 步是校验（第 4 步只计算 `remaining`、本身不做判定），第 8–12 步是计算、写状态、转账、发事件与返回；第 1–7 步任一失败即整笔回滚，不产生任何状态写入与日志。

| # | 层 | 判定 | 失败错误 |
| --- | --- | --- | --- |
| 1 | 存在 | `airdropInfo(tokenAddress).merkleRoot == bytes32(0)` | `TokenNotConfigured(address tokenAddress)` |
| 2 | 状态 | `currentPhase() < claimableFromRound` | `ClaimRoundNotReached(address tokenAddress, uint256 currentRound, uint256 claimableFromRound)` |
| 3 | 状态 | 该 `(tokenAddress, claimer)` 已领取 | `AirdropAlreadyClaimed(address tokenAddress, address claimer)` |
| 4 | — | 计算 `remaining = TOTAL_SHARE - totalClaimedShare`（无判定） | — |
| 5 | 参数 | `share == 0` | `InvalidProof()` |
| 6 | 账本 | `share > remaining` | `ShareExceedsRemaining(uint256 share, uint256 remainingShare)` |
| 7 | 资格 | `proof` 与 `leafHash(claimer, share)` 不匹配 | `InvalidProof()` |
| 8 | — | `amount = Math.mulDiv(balanceOf(this), share, remaining)`（**不做 `amount == 0` 检查**，见下） | — |
| 9 | — | 写状态（CEI）：领取标记 → 已领金额 → `totalClaimedShare` | — |
| 10 | 外部 | `safeTransfer(claimer, amount)` 失败 | `SafeERC20FailedOperation(address token)`，OZ 透传，不在本合约自有错误内 |
| 11 | — | 发 `AirdropClaimed`，`totalRemainingShare` 为**领取后**的 `remaining - share` | — |
| 12 | — | `return amount` | — |

顺序固定为「存在性 → 状态 → 参数 → 账本 → 资格 → 外部」，先命中先回滚，同一入口内不重排。

- 第 2 步的未到轮次判定排在已领取判定之前，使「已经能领了没有」先于「领过没有」；两处都不泄露非公开状态，`claimableFromRound` 与领取标记本来都有 getter。
- 第 5 步是**显式拒绝 `share == 0`**，不是靠 merkle 校验顺带拒绝，也不复用 `ShareExceedsRemaining`。理由：归一化用 `floor(shares[i] × 1e18 ÷ rawTotal)`，极小份额会被截断为 `0`；若树中真的存在零份额叶子，不做显式拒绝就会走到「证明通过 → `amount == 0` → 置领取标记 → 转出 0 代币」，该地址**领取成功却什么也没拿到，并且永久失去该批的领取资格**。显式拒绝把这种情形变成可见的失败，而不是静默的资产损失。
- 第 5 步与第 7 步都回滚 `InvalidProof()`：对调用方来说两种情形同属「这份 proof 不能让我领到东西」，不新增 `ZeroShare` 之类的 selector。
- 零份额是链上链下双保险：链下生成器在 `_build()` 里 `require(normalized[i] > 0)` 直接拒绝产出零份额快照；链上仍独立拒绝，不依赖链下的保证——树可能是发射者自行构造的，链上不能假设它来自本仓的生成器。
- 第 8 步**不做 `amount == 0` 检查**，这是已论证的不可达分支而非遗漏，论证见下节。
- `ShareExceedsRemaining` 的载荷是请求份额与实际剩余份额，单位都是 `TOTAL_SHARE = 1e18` 的份额单位，不是代币数量。

`claim` 可能失败的错误全集 = 本合约自有 14 个错误中可达的 5 个（`TokenNotConfigured`、`ClaimRoundNotReached`、`AirdropAlreadyClaimed`、`ShareExceedsRemaining`、`InvalidProof`，其中 `InvalidProof` 在第 5、7 两处出现但只有一个 selector）**加上** OZ `SafeERC20` 透传的 `SafeERC20FailedOperation(address token)`。后者不属于本合约自有错误，链下分类必须同时识别它的来源。其余 9 个自有错误（配置路径 6 个：`NotLaunchContract`、`InvalidDistributorDataCount`、`InvalidDistributorDataLength`、`TokenAlreadyConfigured`、`ZeroMerkleRoot`、`ClaimDelayRoundsExceeded`；快照 URI 路径 3 个：`SnapshotUriEmpty`、`SnapshotUriTooLong`、`NotSnapshotUriUpdater`）`claim` 不产生；`TokenNotConfigured` 同时是领取与 URI 更新两条路径的存在性错误，只计一次。5 + 9 恰好是全部 14 个。

### 资产去向与事件字段

资产只从本合约流向 `msg.sender`，没有其他去向：`claim` 不接收代币、不产生授权、不向任何第三方地址转账。写操作遵循「检查 → 更新 → 交互」：第 9 步全部状态写入完成后才执行第 10 步转账，转账成功后第 11 步发事件，失败则整笔回滚、状态与代币都不改变。

`AirdropClaimed` 的 `tokenAddress`、`claimer` 带 `indexed`；`share` 是本次消耗的份额；`amount` 是本次实际转出的代币数量；`totalRemainingShare` 是**扣除本次份额后**的剩余份额，使索引器按日志顺序折叠即得下一个 `totalRemainingShare`，无须回算——首条日志的 `totalRemainingShare` 加上它自己的 `share` 等于 `TOTAL_SHARE`，其后每条加上前一条的 `totalRemainingShare` 也成立。

### 为什么不需要 amount == 0 检查

`claim` 第 8 步算出的 `amount` 不做零值检查，这是已论证的不可达分支而非遗漏。论证需要三个前提。

**前提一：`claim` 始终维持 `balanceOf(this) >= remainingShare`。**

- 初始时 `balanceOf(this) == LAUNCH_AMOUNT`、`remainingShare == TOTAL_SHARE == 1e18`，而 `LAUNCH_AMOUNT >= 1e18` 由部署脚本在广播前校验；
- 归纳：成功领取要求 `share <= remainingShare`，转账后余额为 `balanceOf − floor(balanceOf × share ÷ remainingShare)`，去掉 `floor` 得下界 `balanceOf − balanceOf × share ÷ remainingShare = balanceOf × (remainingShare − share) ÷ remainingShare`，再由 `balanceOf >= remainingShare` 得该式 `>= remainingShare − share`，即新的余额仍不小于新的 `totalRemainingShare`。

**前提二：成功领取必有 `share >= 1`。** 由第 5 步显式拒绝 `share == 0` 直接给出。注意这里**不**依赖「链下树没有零份额叶子」这一链下假设——加固后链上自己就排除了。

**前提三：`LAUNCH_AMOUNT >= 1e18`。** 由部署脚本校验，见上。

三者在手，`balanceOf × share >= remainingShare × 1 = remainingShare`，故 `amount = floor(balanceOf × share ÷ remainingShare) >= 1`。任一前提被破坏（去掉 `LAUNCH_AMOUNT >= 1e18` 的部署校验、或去掉第 5 步的显式拒绝）都必须重新论证本条。

没有部分领取：一次成功领取消耗该地址在该 token 上的全部份额（由叶子决定），再次调用回滚 `AirdropAlreadyClaimed`。

### 无重入锁

本合约不继承 `ReentrancyGuard`。三条前提共同保证无重入路径：

1. **LOVE20Token 没有转账钩子**：`LOVE20Token` 是标准 ERC20，没有 ERC777、`_update` 回调或可配置的转移钩子，`safeTransfer` 不会把控制权交还给任何第三方代码。
2. **配置入口唯一且只写一次**：`onTokenLaunched` 只接受 `LAUNCH_ADDRESS`，同一 token 第二次配置回滚 `TokenAlreadyConfigured`；`claim` 不写 Root 与起始轮次。领取期间没有可以改写配置的路径。
3. **CEI**：`claim` 先写全部状态（领取标记、已领金额、`totalClaimedShare`），再转账，最后发事件；即使存在未预见的回调，重复进入时已命中 `AirdropAlreadyClaimed`。

任一条前提被破坏（例如未来把 `tokenAddress` 换成带转移钩子的代币、或新增配置写入入口）都必须同时重新评估本条，不能只改一处。

## 快照 URI 更新

`updateSnapshotUri(tokenAddress, snapshotUri)` 写入一条「快照 JSON 的发现提示 URL」。它是本合约第二个外部写入口，也是唯一可反复写入状态的入口。URI 只供前端发现、**不参与任何领取判定**：Root 不可变，链上不校验 URI 指向的文件内容，也不因 URI 改变而调整 `claim` 或 `claimableAmount` 的任何逻辑，见 [边界与风险](#边界与风险)。

### 校验顺序与错误集合

按 [错误与回滚标准](../../error-standards.md#五失败契约) 的编号列表形态，逐条 层 → 条件 → 错误：

```text
1. 存在  airdropInfo(tokenAddress).merkleRoot == bytes32(0) → TokenNotConfigured(address tokenAddress)
2. 鉴权  launcherMemberId == 0                               → NotSnapshotUriUpdater(address caller, uint256 launcherMemberId)（载荷为 (msg.sender, 0)）
3. 鉴权  IMemberNFT(ILaunch(LAUNCH_ADDRESS).MEMBER_NFT_ADDRESS()).ownerOf(launcherMemberId) != msg.sender
                                                            → NotSnapshotUriUpdater(address caller, uint256 launcherMemberId)
4. 参数  bytes(snapshotUri).length == 0                      → SnapshotUriEmpty()
5. 参数  bytes(snapshotUri).length > MAX_SNAPSHOT_URI_BYTES → SnapshotUriTooLong(uint256 length, uint256 maxLength)
```

第 1–3 步在 `onlySnapshotUriUpdater(tokenAddress)` modifier 内，第 4–5 步在函数体内；成功后写 `_snapshotUriByTokenAddress[tokenAddress] = snapshotUri` 并发出 `AirdropSnapshotUriUpdated(tokenAddress, snapshotUri, prevSnapshotUri)`。`prevSnapshotUri` 是写入前的存储值，首次更新为空串。

**鉴权写在 `only*` modifier 且是函数体第一道判定**（dev-standards §5.5）：modifier 挂在 `updateSnapshotUri` 上，函数体第一条语句就是参数长度校验，鉴权在 modifier 里先于它执行。modifier 整体仍是函数体的第一道判定；`onlySnapshotUriUpdater` 只做判定、不写状态、只读 `ownerOf`，以 `_;` 收尾，形状由 `check_caller_auth.py` 守护。这是 dev-standards §5.5 要求的「无限制写函数明文说明、不靠没挂 modifier 隐式表达」的反面——本入口**有**调用者限制，且限制在 modifier 里明文表达。

**modifier 第一行是存在性检查，第二行起才是鉴权，这是有意取舍**：`onlySnapshotUriUpdater` 的第一行先判 `merkleRoot == bytes32(0)` 并回 `TokenNotConfigured(tokenAddress)`，之后才读 `launcherMemberId`、判 `0`、读 `ownerOf`。若把鉴权放到最前，未配置的 token 会先落到 `IMemberNFT(...).ownerOf(0)`，而 `memberId 0` 永不铸造，OZ ERC721 会抛 `ERC721NonexistentToken(0)`，把本应报的 `TokenNotConfigured` 掩盖掉。把存在性提前使「未配置」始终以本模块自有错误表达，不受鉴权路径里的标准错误干扰；modifier 整体仍是函数体第一道判定，满足 dev-standards §5.5。error-standards §5 的默认序是「鉴权 → 参数 → 存在性」，本入口把存在性并入鉴权 modifier 且置于最前，是有理由的模块级偏离，写在此处留痕。

**权限随 MemberNFT 转手**：modifier 每次调用都实时执行 `ILaunch(LAUNCH_ADDRESS).MEMBER_NFT_ADDRESS()` → `IMemberNFT(...).ownerOf(launcherMemberId)`，与 `msg.sender` 比较；不缓存发射者地址、不在配置期固化持有人（review-guide「NFT 转移后权限实时读取 owner，不缓存旧地址」）。NFT 转手后，新持有人立即获得更新权、旧持有人立即失去。`launcherMemberId` 本身在配置时写定、不可改，转移的是 `memberId` 的持有人而不是这个 id。

**创世币永久拒绝**：构造函数为首币传 `launcherMemberId = 0`，第 2 步直接回 `NotSnapshotUriUpdater(msg.sender, 0)`，不会落到 `ownerOf(0)`。因 `MemberNFT._nextTokenId = 1`，`memberId 0` 永不铸造，故创世 URI 永久为空且无人可设——这是刻意设计，不是遗漏，详见 [边界与风险](#边界与风险)。

参数校验在鉴权之后（error-standards §5 的「鉴权 → 参数」序）：长度按 `bytes(snapshotUri).length` 取，`length == 0` 与 `length > 256` 都拒绝，恰好 `256` 合法；超过上限不截断。

### 事件字段

`AirdropSnapshotUriUpdated(tokenAddress, snapshotUri, prevSnapshotUri)` 按「根键 → 新值 → 旧值」排列：`tokenAddress` 是根键、带 `indexed`；`snapshotUri` 是本次写入的新 URI；`prevSnapshotUri` 是写入前的旧 URI（首次更新为空串）。两个 `string` 都不 `indexed`（event-standards §6.3），都受 `MAX_SNAPSHOT_URI_BYTES = 256` 链上上限守护，见 [event-standards §6.8](../../event-standards.md#68-动态字段上限)。URI 可反复更新、不是一次性初始化，因此按 event-standards §6.7「配置变更必须携带旧值+新值」带旧值。

## 只读查询

| 入口 | 作用域 | 不存在时的行为 |
| --- | --- | --- |
| `airdropInfo(tokenAddress)` | 单条 | 返回该批完整 `AirdropInfo`（8 字段）；未配置的 token 返回全零结构体与空 `snapshotUri`，不回滚 |
| `isClaimed(tokenAddress, claimer)` | 单点 | 未领取或未配置返回 `false` |
| `claimedAmount(tokenAddress, claimer)` | 单点 | 未领取或未配置返回 `0` |
| `TOTAL_SHARE()` / `MAX_CLAIM_DELAY_ROUNDS()` / `MAX_SNAPSHOT_URI_BYTES()` | 常量 | — |
| `leafHash(claimer, share)` | 纯函数 | — |

按 `tokenAddress` 的其余字段不单独开 getter，全部经 `airdropInfo(tokenAddress)` 一次取回——`tokenAddress` 是作用域键（定位而不是筛选），按[命名规范](../../naming-standards.md) §7.3 不进函数名；`airdropInfo` 与分页的 `airdropInfos` 构成 §7.6 允许的单复数对。调用方要判断某个 token 是否已配置，读 `airdropInfo(tokenAddress).merkleRoot != bytes32(0)`。

`launcherMemberId` 没有 getter，也不在 `AirdropInfo` 里：前端判断「这个币的 URI 还能不能更新」不看读接口，而是看 `updateSnapshotUri` 是否回滚 `NotSnapshotUriUpdater`（创世币回滚时载荷里的 `launcherMemberId` 为 `0`）。

### claimableAmount

`claimableAmount(tokenAddress, claimer, share, proof)` 是不写状态的预检，语义是「现在调用 `claim` 会得到多少」：没有调用者校验，任意地址可以查任意快照地址。

依次判定，任一不满足即返回 `0`，不校验也不回滚：

1. `airdropInfo(tokenAddress).merkleRoot == bytes32(0)`；
2. `currentPhase() < claimableFromRound`；
3. 该 `(tokenAddress, claimer)` 已领取；
4. `share == 0 || share > remainingShare`（与 `claim` 的第 5、6 步合并为一次判定，短路顺序与写版一致）；
5. `proof` 与 `leafHash(claimer, share)` 不匹配。

全部通过时返回与 `claim` 第 8 步相同的 `Math.mulDiv` 结果。这是 `claim` 前 8 步的只读镜像：判定条件、判定顺序、短路方向都相同，唯一区别是失败时统一返回 `0` 而不是 revert。

- **不能以返回 `0` 判断「无资格」**：`0` 同时表示「未配置」「未到轮次」「已领过」「份额非法」「证明不对」和「确实算出来是 0」六种情形，只读接口无法区分。需要原因时必须读各 getter 或直接模拟 `claim`。这与 Burn 原设计对只读预检的警告一致。
- 与 `claim` 的唯一语义差异是失败表达：写版按失败原因回滚不同错误，只读版一律 `return 0`；两者对「现在能不能领、能领多少」的结论一致。
- 返回值是**查询时点**的值，不是对下一笔交易的承诺：同批其他地址先领取会同时改变 `balanceOf(this)` 与 `totalRemainingShare`，`amount` 随之变化。前端不得把预检结果当作可签名的数额，必须以交易内实际发生的 `AirdropClaimed.amount` 为准。

### 分页查询

`airdropInfos(offset, limit, reverse)` 分页读取已配置代币，返回 `AirdropInfo` 数组与配置总数 `totalCount`。`AirdropInfo` 的字段与取值：

| 字段 | 取值 |
| --- | --- |
| `tokenAddress` | 该批快照所属代币 |
| `merkleRoot` | 配置时写入的根 |
| `claimableFromRound` | 配置时算出的起始轮次 |
| `totalClaimedShare` | 当前已领份额（后置累计值） |
| `totalRemainingShare` | `TOTAL_SHARE - totalClaimedShare`（当前值） |
| `totalClaimedAmount` | 该代币累计已实际转出的代币数量（由 `claim` 累加） |
| `remainingAmount` | 该代币在本合约的当前余额 `balanceOf(this)`，逐元素读取 |
| `snapshotUri` | 该代币当前登记的快照 URI；默认空串 |

两个恒等式把四个数值锁在一起，链下可直接对账：

```text
totalClaimedShare + totalRemainingShare == TOTAL_SHARE            // 份额账本
totalClaimedAmount + remainingAmount   == 该代币的初始首批供应量   // 金额账本
```

份额一侧恒等式由 `TOTAL_SHARE` 是常量保证。金额一侧的前提是该代币从`Launch` 收到的首批供应量之外再无转入：任何人都能向本合约 `transfer` 任意代币，误转会抬高 `remainingAmount` 而不改变 `totalClaimedAmount`，两条恒等式就此不等——这是链下需要留意的口径，不是合约缺陷（合约没有取回入口，误转无法撤销）。

分页语义与 `Phase.observations`、`Launch.tokens` 一致：`offset` 大于或等于 `totalCount` 时返回空数组与真实 `totalCount`，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时从新到旧返回。列表按配置顺序追加（首币是第一个元素、构造函数里的首币配置即首次 `push`），`reverse = true` 时按插入的逆序返回，配合 `offset` 即可从最新配置向前翻页。

**不设独立计数入口**：集合总数由本入口返回的 `totalCount` 承担，`airdropInfos(0, 0, false)` 即取基数（`limit = 0` 返回空数组与真实 `totalCount`）。这是 `Pagination.pageCount` 的直接结果，不另设 `airdropCount()`。

`limit` 由调用方决定，合约不设死上限——这是分页语义的一部分，不额外开一个受限入口。代价是每页每个元素都要读一次 `balanceOf`（外部调用），所以 `limit` 同时决定一次 `eth_call` 的成本：配置数量大时前端应分页读取，不要用一次大 `limit` 拉全量，否则可能撞上节点的 gas 上限而不可调用。

`remainingAmount` 是查询时点的实时值，不是快照时的首批供应量：已被领取的部分已转出合约，剩余量就是尚未领取的资产。领取进度需要对照 `totalRemainingShare` 读，不能用余额单独推断——链下快照 `Σleaves` 与 `1e18` 的差会直接体现为两者的不成比例。

`AirdropInfo` 是 ABI 只读记录（`<X>Info`），承载查询结果，不是存储结构；合约内的存储是七个按 `tokenAddress`（及 `claimer`）索引的映射加一个只追加的 `address[]` 列表。`snapshotUri` 作为第 7 字段追加在末尾，使既有 6 字段的语义与下标不变；它虽是 `string`，但有 256 字节链上硬上限，见 [常量](#常量) 与 [event-standards §6.8](../../event-standards.md#68-动态字段上限)。

## 外部调用

| 调用 | 场景 | 失败处理 |
| --- | --- | --- |
| `IPhase(PHASE_ADDRESS).currentPhase()` | 配置时算 `claimableFromRound`、领取与预检时判轮次 | 协议固定依赖，不校验调用方；`Phase` 不在此处回滚，创世前返回 `0` |
| `IERC20(tokenAddress).balanceOf(address(this))` | `claim`、`claimableAmount`、`airdropInfos` | 已配置的 token 一定由 `Launch` 创建，是 `LOVE20Token`；不另设代码校验 |
| `IERC20(tokenAddress).safeTransfer(claimer, amount)` | `claim` | 失败整笔回滚，不吞异常、不降级为部分成功 |
| `ILaunch(LAUNCH_ADDRESS).MEMBER_NFT_ADDRESS()` | `updateSnapshotUri` 的 `onlySnapshotUriUpdater` modifier 内派生 MemberNFT 地址 | 协议固定依赖（已有 getter），每次调用实时读取，不缓存；非预期失败 rethrow |
| `IMemberNFT(memberNFT).ownerOf(launcherMemberId)` | `updateSnapshotUri` 的 `onlySnapshotUriUpdater` modifier 内判当前持有人 | 只读判定；`launcherMemberId == 0` 分支在调用前已拒绝，故不会因 `ownerOf(0)` 抛 `ERC721NonexistentToken` |

`Launch` 对回调的透传数据只做形状层面的约定（见 [回调数据格式](#ontokenlaunched回调)），实际解码与全部业务校验在本合约完成；回调返回后 `Launch` 不再读取本合约的任何状态。`MEMBER_NFT_ADDRESS()` 由 `LAUNCH_ADDRESS` 派生、不新增构造参数，见 [职责与依赖](#职责与依赖)。

### 透传来源

| 来源 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `SafeERC20`（OZ） | `SafeERC20FailedOperation(address token)` | `claim` 第 10 步转账失败时透传。**这是本合约转账路径唯一的外部错误来源**，不在自有 14 个错误内，链下分类必须单独识别；测试直接断言 OZ 的 selector，不要求本合约 ABI 自带 |

`updateSnapshotUri` 的 `ownerOf` 只读判定不产生透传错误：`launcherMemberId == 0` 在第 2 步直接拒绝，绝不落到 `ownerOf(0)`，故 `ERC721NonexistentToken` 对本入口不可达；非零 `launcherMemberId` 必然是已铸造的 `memberId`（由 `Launch` 回调透传），`ownerOf` 不会因不存在而回滚。

本合约的 14 个自有错误全部在 `IAirdropDistributorErrors` 中声明，实现文件不声明错误，也不从其他仓导入错误：`SnapshotUriEmpty`、`SnapshotUriTooLong`、`NotSnapshotUriUpdater` 是 URI 能力新增的 3 个，`TokenNotConfigured` 由领取与 URI 更新两条路径复用、不重复声明。`SafeERC20FailedOperation` 是库错误经 `SafeERC20` 使用进入调用方 ABI，不属于本模块 Errors。

## 边界与风险

- **Root 填错即资产锁死**：`merkleRoot` 在配置后不可更新，也没有取回入口。填错、或漏掉应得地址，该批首批供应里对应的份额将永久留在合约中，任何人无法取出。这是有意的设计取舍：可更新的 Root 等于把「谁能领多少」交给一个可以改口的中心角色。分发前必须以只读预检逐条核对。
- **链上无法验证 `Σleaves == 1e18`**：合约只有分母常量，看不到叶子集合。若链下快照份额之和小于 `1e18`，差额部分无人可领，余额永远留在合约里；若大于 `1e18`，先领取者按比例分走资产，后领取者在 `totalRemainingShare` 耗尽后回滚 `ShareExceedsRemaining`，其应得份额拿不到。唯一防线是链下生成器的归一化与公开快照的独立复算。
- **金额随领取顺序变化**：`amount` 按剩余份额比例计算，同一地址在不同时点领取得到的数量不同。这不是缺陷而是设计：按剩余额分配使任何人都无法通过抢先领取占取超过自身份额比例的资产，也让最后一人清空余额。对账以 `AirdropClaimed.amount` 为准。
- **无管理员、无暂停、无取回入口**：没有 owner、admin、pause、rescue、upgrade，也没有改变 Root 或截止时间的入口。部署后合约行为只由代码与快照决定。
- **`NoCallback` 模式下把本合约设为子币 distributor 会锁死首批供应**：普通发射允许 `NoCallback`，此时 `Launch` 不调用回调，本合约不会为该子币写入任何配置；而 `LOVE20Token` 构造函数已把整批首批供应铸给 distributor 地址，本合约又没有取回入口。结果就是这批代币永久留在合约里、任何地址都无法领取（`claim` 恒回滚 `TokenNotConfigured`）。本合约唯一合法的子币接入方式是 `Callback` 模式并传入 64 字节配置。发射入口与前端必须在把 distributor 设为本合约时强制 `Callback`；`Launch` 本身不检查这种组合，因为它不知道 distributor 的业务语义。
- **前端必须预检**：最低限度要核对 `Σleaves == 1e18`、每条证明与 `leafHash` 一致、`claimableFromRound` 与部署所在轮次相符，并用 `claimableAmount` 逐条模拟。链上没有可弥补这些错误的手段，预检是唯一的失败前置点。
- **快照 URI 是发现提示、不是授权**：`snapshotUri` 只告诉前端「去哪里找快照 JSON」，Merkle Root 在配置后不可变，链上**不校验** URI 指向的文件内容是否与 Root 匹配，也不因 URI 改变而调整任何领取逻辑。URI 指向错文件、被改成钓鱼站、或失联，最坏结果只是「前端找不到数据」，不可能让任何人多领或少领——领取资格只由 `proof` 对链上 Root 的校验决定。前端因此必须自行完成下一条的校验流程，不能把 URI 当作可信数据源。
- **前端校验流程（提交前拦截）**：`airdropInfos` 分页拿到 `snapshotUri` → `fetch(uri)` 取回快照 JSON → 按 [快照来源](#快照来源) 的叶子格式重建 Merkle 树 → 断言 `Σleaves == 1e18` 且重建出的 root 等于链上 `merkleRoot` → **任一不匹配则在提交交易前拦截、不展示可领数量**（不发起 `claim`、不给用户「可领 X」的误导）→ 匹配后从文件中查已连接钱包地址的 `share` 与 `proof`，用 `claimableAmount` 模拟，再让用户提交 `claim`。URI 内容不通过校验时，领取入口必须保持不可用，而不是退化为「用链上 Root 盲领」。
- **前端去中心化**：子币发射者无需说服前端开发者手工整合自己的快照，自己调用 `updateSnapshotUri` 登记 URI 即可；前端只读 `airdropInfos` 就能发现所有已登记的子币。这把新币上线的协作成本从「改前端代码 + 发版」降为「发射者链上一笔交易」。
- **GitHub Pages 可行性**：实测 `https://love20bsc.github.io/docs/` 返回 `access-control-allow-origin: *`，浏览器可直接 `fetch`；前端本身部署在 GitHub Pages 时与快照同源，连 CORS 都不用考虑。`MAX_SNAPSHOT_URI_BYTES = 256` 对形如 `https://<user>.github.io/<repo>/<path>/<file>.json` 的 URL 绰绰有余（约 60 字节的实测串远低于上限）。
- **创世币 URI 永久为空且无人可设**：构造期首币的 `launcherMemberId = 0`；因 `MemberNFT._nextTokenId = 1`，`memberId 0` 永不铸造，`onlySnapshotUriUpdater` 第 2 步对 `launcherMemberId == 0` 直接回 `NotSnapshotUriUpdater(msg.sender, 0)`（不落到 `ownerOf(0)`）。因此首币没有 URI 更新者、URI 恒为空串——这是刻意设计，不是遗漏：首币快照由部署记录公开举证（来源链、来源区块、Merkle Root、首币地址），不依赖某个可改口的发射者。

### 快照来源

首币空投的份额数据来源于旧 `LOVE20TKM/burn` 记录在链上的销毁活动结果（来源链 ID、来源区块、来源地址与份额快照）。本合约不引用该仓库的合约代码，只消费其链下快照生成器产出的 Merkle 快照；叶子格式与本合约逐字节一致：

```text
leaf     = keccak256(bytes.concat(keccak256(abi.encode(claimer, share))))
node     = keccak256(sorted(left, right))
```

树的每对节点按字节值排序后哈希，某层最后一个无配对节点直接提升到下一层；该格式与 OpenZeppelin `MerkleProof` 的排序证明验证一致，也要求链下生成器把份额归一化到精确 `1e18`。部署记录必须公开记录实际使用的来源链、来源区块、Merkle Root 与首币地址，使任何人可以独立复算，见 [仓库清单](../../repositories.md)。

验收见 [Core 验收](09-testing.md)。
