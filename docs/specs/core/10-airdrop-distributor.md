# AirdropDistributor

AirdropDistributor 是首币与普通发射共用的可选 distributor：接收首批代币，按 Merkle 快照把该批供应分发给快照地址。它只做分发，不迁移 Burn 业务，也不在链上验证快照来源。完整 ABI 见 [`IAirdropDistributor.sol`](https://github.com/LOVE20BSC/core/blob/main/src/interfaces/distributor/IAirdropDistributor.sol)。

## 职责与依赖

合约负责：

- 为每个已配置的 `tokenAddress` 保存一份 Merkle Root 与可领取起始轮次。
- 校验「地址 + 份额」的 Merkle 证明，并按该代币的合约余额与剩余份额计算本次领取量。
- 只允许快照地址本人提交证明并领取。

合约不负责：

- 不在链上验证快照的来源链、来源区块或叶子份额之和；完整快照必须公开供任何人独立复算。
- 不登记、枚举或限制代币；领取时由调用者传入 `tokenAddress`。
- 不支持部分领取、同币重复领取或单笔多代币领取。
- 不设管理员、暂停、升级、截止时间、Root 更新或资产取回入口。

构造函数固定 `LAUNCH_ADDRESS` 与 `PHASE_ADDRESS`，按 `(launchAddress, phaseAddress, genesisTokenAddress, genesisMerkleRoot, genesisClaimDelayRounds)` 传入。两者都是部署后冻结的值，声明为 `public immutable`、以大写命名并直接提供同名 getter，与 `core` 其他构造函数冻结值（`Phase.ORIGIN_BLOCKS`、`LOVE20Token.MAX_SUPPLY`）一致——`immutable` 让「任何人都不可能改写它」由编译器保证，而不是靠「没有第二个写入口」的约定。

- `LAUNCH_ADDRESS` 是 `onTokenLaunched` 的唯一允许调用方；除构造函数这条首币路径外，它是唯一的配置写入路径。
- `PHASE_ADDRESS` 只用于读取 `currentPhase()`，是 `claimableFromRound` 的时间基准。
- 构造函数不做静态零值校验；依赖地址与首币配置由部署脚本在广播前校验、部署后核对，见 dev-standards §5.7。
- 部署时 `launchAddress` 与首币地址都尚未存在，由部署脚本按部署者 nonce 预测后传入，并在 `Launch` 部署后核对；首币地址恒为 `computeCreateAddress(launchAddress, 1)`。

构造函数在同一次部署内调用首币配置路径，因此首币在构造期即完成配置，不需要 `Launch` 回调。`Launch` 构造函数不调用 distributor 回调（首币固定 `NoCallback`），见 [Launch](08-launch.md#部署与首个代币)。构造期发出的 `AirdropConfigured` 是已登记的第二处「构造函数可发业务事件」例外：首币的配置没有其它事件覆盖，不在构造期发就只能丢失这次状态迁移，理由见 [通用规则](01-common-rules.md#部署与安全)。

## 常量

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `TOTAL_SHARE` | `1e18` | 每个代币快照的份额分母，编译期常量，不可按部署配置 |
| `MAX_CLAIM_DELAY_ROUNDS` | `1000` | `claimDelayRounds` 的上限，单位 Phase |

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
| 已领份额 | `tokenAddress` | `claimedShare`，累计被成功领取消耗的份额 |
| 领取标记 | `tokenAddress` + `claimer` | 是否已领取该代币 |
| 已领金额 | `tokenAddress` + `claimer` | 该地址成功领取时实际转出的代币数量（与 `AirdropClaimed.amount` 同值） |

另有一个按配置顺序追加的 `tokenAddress` 列表，供 `airdropInfos` 分页读取；首币是首个元素。列表只追加，不删除、不重排。

状态只写一次：每个 `tokenAddress` 的 Root、起始轮次在配置时写定，此后没有第二写入点；`claimedShare` 只增不减；领取标记与已领金额只会由「未领取」变为「已领取」。

## 份额与金额

```text
remainingShare = TOTAL_SHARE - claimedShare
amount = floor(balanceOf(this) × share ÷ remainingShare)
```

- `share` 是快照叶子中该地址的份额，最小单位为 `1e18` 分之一（`TOTAL_SHARE` 为 `1e18` 时，份额 `1e16` 表示 1%）。
- `remainingShare` 是**配置时点起算的剩余份额**，不是剩余资产比例；未领取时等于 `TOTAL_SHARE`。
- `amount` 按合约在领取时点的实际余额计算，用 `Math.mulDiv` 取 512 位中间结果后向下取整，不溢出、不先除后乘。
- 分母不为零：`claimedShare` 只在成功领取时增加，且每次成功领取都满足 `share <= remainingShare`，因此 `claimedShare < TOTAL_SHARE` 恒成立。
- 按剩余份额分配使后领取者按剩余资产的比例分享：最后一名份额恰为 `remainingShare` 的领取者得到 `balanceOf(this)` 全部，合约余额清零。
- 公式本身不假设 `Σleaves == 1e18`，那是链下的责任：分母恒为 `1e18`，若叶子份额之和不足，差额无人可领；若超出，先领取者按比例分走资产，后领取者在 `remainingShare` 耗尽后无法领取。

例如某一批快照只有两个叶子，份额为 `6e17` 与 `4e17`，配置时合约余额 `1000`（代币最小单位）。第一人领取 `floor(1000 × 6e17 ÷ 1e18) = 600`，此后余额 `400`、`remainingShare = 4e17`；第二人领取 `floor(400 × 4e17 ÷ 4e17) = 400`，余额归零。若顺序相反，第一人得 `400`、第二人得 `600`：两人各自占本批总额的比例不变，且都不超过自己份额对应的比例。

## 代币配置

两个入口共用同一条配置路径 `_configure(tokenAddress, merkleRoot, claimDelayRounds)`：构造函数用它为首币写入配置，`onTokenLaunched` 用它为普通发射的子币写入配置。因此首币与子币的错误集合、判定顺序、轮次夹取完全一致。

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

成功配置时按固定顺序做三件事：先写 Root 与 `claimableFromRound`，再把 `tokenAddress` 追加到列表，最后发出 `AirdropConfigured(tokenAddress, merkleRoot, claimableFromRound)`——`push` 发生在 `emit` 之前，因此事件发出时链上状态已经就绪，索引器收到日志时无需等待后续写入。`tokenAddress` 带 `indexed`；`merkleRoot` 是本次写入的根；`claimableFromRound` 是夹取与延迟相加后的**最终起始轮次**，索引器无须回算 `baseRound`。

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
| 1 | 存在 | `merkleRootByTokenAddress(tokenAddress) == bytes32(0)` | `TokenNotConfigured(address tokenAddress)` |
| 2 | 状态 | `currentPhase() < claimableFromRound` | `ClaimRoundNotReached(address tokenAddress, uint256 currentRound, uint256 claimableFromRound)` |
| 3 | 状态 | 该 `(tokenAddress, claimer)` 已领取 | `AirdropAlreadyClaimed(address tokenAddress, address claimer)` |
| 4 | — | 计算 `remaining = remainingShareByTokenAddress(tokenAddress)`（无判定） | — |
| 5 | 参数 | `share == 0` | `InvalidProof()` |
| 6 | 账本 | `share > remaining` | `ShareExceedsRemaining(uint256 share, uint256 remainingShare)` |
| 7 | 资格 | `proof` 与 `leafHash(claimer, share)` 不匹配 | `InvalidProof()` |
| 8 | — | `amount = Math.mulDiv(balanceOf(this), share, remaining)`（**不做 `amount == 0` 检查**，见下） | — |
| 9 | — | 写状态（CEI）：领取标记 → 已领金额 → `claimedShare` | — |
| 10 | 外部 | `safeTransfer(claimer, amount)` 失败 | `SafeERC20FailedOperation(address token)`，OZ 透传，不在本合约自有错误内 |
| 11 | — | 发 `AirdropClaimed`，`remainingShare` 为**领取后**的 `remaining - share` | — |
| 12 | — | `return amount` | — |

顺序固定为「存在性 → 状态 → 参数 → 账本 → 资格 → 外部」，先命中先回滚，同一入口内不重排。

- 第 2 步的未到轮次判定排在已领取判定之前，使「已经能领了没有」先于「领过没有」；两处都不泄露非公开状态，`claimableFromRound` 与领取标记本来都有 getter。
- 第 5 步是**显式拒绝 `share == 0`**，不是靠 merkle 校验顺带拒绝，也不复用 `ShareExceedsRemaining`。理由：归一化用 `floor(shares[i] × 1e18 ÷ rawTotal)`，极小份额会被截断为 `0`；若树中真的存在零份额叶子，不做显式拒绝就会走到「证明通过 → `amount == 0` → 置领取标记 → 转出 0 代币」，该地址**领取成功却什么也没拿到，并且永久失去该批的领取资格**。显式拒绝把这种情形变成可见的失败，而不是静默的资产损失。
- 第 5 步与第 7 步都回滚 `InvalidProof()`：对调用方来说两种情形同属「这份 proof 不能让我领到东西」，不新增 `ZeroShare` 之类的 selector。
- 零份额是链上链下双保险：链下生成器在 `_build()` 里 `require(normalized[i] > 0)` 直接拒绝产出零份额快照；链上仍独立拒绝，不依赖链下的保证——树可能是发射者自行构造的，链上不能假设它来自本仓的生成器。
- 第 8 步**不做 `amount == 0` 检查**，这是已论证的不可达分支而非遗漏，论证见下节。
- `ShareExceedsRemaining` 的载荷是请求份额与实际剩余份额，单位都是 `TOTAL_SHARE = 1e18` 的份额单位，不是代币数量。

`claim` 可能失败的错误全集 = 本合约自有 11 个错误中可达的 5 个（`TokenNotConfigured`、`ClaimRoundNotReached`、`AirdropAlreadyClaimed`、`ShareExceedsRemaining`、`InvalidProof`，其中 `InvalidProof` 在第 5、7 两处出现但只有一个 selector）**加上** OZ `SafeERC20` 透传的 `SafeERC20FailedOperation(address token)`。后者不属于本合约自有错误，链下分类必须同时识别它的来源。其余 6 个自有错误（`NotLaunchContract`、`InvalidDistributorDataCount`、`InvalidDistributorDataLength`、`TokenAlreadyConfigured`、`ZeroMerkleRoot`、`ClaimDelayRoundsExceeded`）只在配置路径可达，`claim` 不产生它们；5 + 6 恰好是全部 11 个。

### 资产去向与事件字段

资产只从本合约流向 `msg.sender`，没有其他去向：`claim` 不接收代币、不产生授权、不向任何第三方地址转账。写操作遵循「检查 → 更新 → 交互」：第 9 步全部状态写入完成后才执行第 10 步转账，转账成功后第 11 步发事件，失败则整笔回滚、状态与代币都不改变。

`AirdropClaimed` 的 `tokenAddress`、`claimer` 带 `indexed`；`share` 是本次消耗的份额；`amount` 是本次实际转出的代币数量；`remainingShare` 是**扣除本次份额后**的剩余份额，使索引器按日志顺序折叠即得下一个 `remainingShare`，无须回算——首条日志的 `remainingShare` 加上它自己的 `share` 等于 `TOTAL_SHARE`，其后每条加上前一条的 `remainingShare` 也成立。

### 为什么不需要 amount == 0 检查

`claim` 第 8 步算出的 `amount` 不做零值检查，这是已论证的不可达分支而非遗漏。论证需要三个前提。

**前提一：`claim` 始终维持 `balanceOf(this) >= remainingShare`。**

- 初始时 `balanceOf(this) == LAUNCH_AMOUNT`、`remainingShare == TOTAL_SHARE == 1e18`，而 `LAUNCH_AMOUNT >= 1e18` 由部署脚本在广播前校验；
- 归纳：成功领取要求 `share <= remainingShare`，转账后余额为 `balanceOf − floor(balanceOf × share ÷ remainingShare)`，去掉 `floor` 得下界 `balanceOf − balanceOf × share ÷ remainingShare = balanceOf × (remainingShare − share) ÷ remainingShare`，再由 `balanceOf >= remainingShare` 得该式 `>= remainingShare − share`，即新的余额仍不小于新的 `remainingShare`。

**前提二：成功领取必有 `share >= 1`。** 由第 5 步显式拒绝 `share == 0` 直接给出。注意这里**不**依赖「链下树没有零份额叶子」这一链下假设——加固后链上自己就排除了。

**前提三：`LAUNCH_AMOUNT >= 1e18`。** 由部署脚本校验，见上。

三者在手，`balanceOf × share >= remainingShare × 1 = remainingShare`，故 `amount = floor(balanceOf × share ÷ remainingShare) >= 1`。任一前提被破坏（去掉 `LAUNCH_AMOUNT >= 1e18` 的部署校验、或去掉第 5 步的显式拒绝）都必须重新论证本条。

没有部分领取：一次成功领取消耗该地址在该 token 上的全部份额（由叶子决定），再次调用回滚 `AirdropAlreadyClaimed`。

### 无重入锁

本合约不继承 `ReentrancyGuard`。三条前提共同保证无重入路径：

1. **LOVE20Token 没有转账钩子**：`LOVE20Token` 是标准 ERC20，没有 ERC777、`_update` 回调或可配置的转移钩子，`safeTransfer` 不会把控制权交还给任何第三方代码。
2. **配置入口唯一且只写一次**：`onTokenLaunched` 只接受 `LAUNCH_ADDRESS`，同一 token 第二次配置回滚 `TokenAlreadyConfigured`；`claim` 不写 Root 与起始轮次。领取期间没有可以改写配置的路径。
3. **CEI**：`claim` 先写全部状态（领取标记、已领金额、`claimedShare`），再转账，最后发事件；即使存在未预见的回调，重复进入时已命中 `AirdropAlreadyClaimed`。

任一条前提被破坏（例如未来把 `tokenAddress` 换成带转移钩子的代币、或新增配置写入入口）都必须同时重新评估本条，不能只改一处。

## 只读查询

| 入口 | 作用域 | 不存在时的行为 |
| --- | --- | --- |
| `merkleRootByTokenAddress(tokenAddress)` | 单点 | 未配置返回零值 |
| `claimableFromRoundByTokenAddress(tokenAddress)` | 单点 | 未配置返回 `0` |
| `claimedShareByTokenAddress(tokenAddress)` | 单点 | 未配置返回 `0` |
| `isClaimedByTokenAddressByClaimer(tokenAddress, claimer)` | 单点 | 未领取或未配置返回 `false` |
| `claimedAmountByTokenAddressByClaimer(tokenAddress, claimer)` | 单点 | 未领取或未配置返回 `0` |
| `remainingShareByTokenAddress(tokenAddress)` | 单点 | 未配置返回 `TOTAL_SHARE` |
| `TOTAL_SHARE()` / `MAX_CLAIM_DELAY_ROUNDS()` | 常量 | — |
| `leafHash(claimer, share)` | 纯函数 | — |

单点查询都不校验、不回滚：对任意地址返回零值（或 `false`），调用方自行区分「未配置」与「配置了但尚未领取」。判据是 `merkleRootByTokenAddress(tokenAddress) != bytes32(0)`。

### claimableAmount

`claimableAmount(tokenAddress, claimer, share, proof)` 是不写状态的预检，语义是「现在调用 `claim` 会得到多少」：没有调用者校验，任意地址可以查任意快照地址。

依次判定，任一不满足即返回 `0`，不校验也不回滚：

1. `merkleRootByTokenAddress(tokenAddress) == bytes32(0)`；
2. `currentPhase() < claimableFromRound`；
3. 该 `(tokenAddress, claimer)` 已领取；
4. `share == 0 || share > remainingShare`（与 `claim` 的第 5、6 步合并为一次判定，短路顺序与写版一致）；
5. `proof` 与 `leafHash(claimer, share)` 不匹配。

全部通过时返回与 `claim` 第 8 步相同的 `Math.mulDiv` 结果。这是 `claim` 前 8 步的只读镜像：判定条件、判定顺序、短路方向都相同，唯一区别是失败时统一返回 `0` 而不是 revert。

- **不能以返回 `0` 判断「无资格」**：`0` 同时表示「未配置」「未到轮次」「已领过」「份额非法」「证明不对」和「确实算出来是 0」六种情形，只读接口无法区分。需要原因时必须读各 getter 或直接模拟 `claim`。这与 Burn 原设计对只读预检的警告一致。
- 与 `claim` 的唯一语义差异是失败表达：写版按失败原因回滚不同错误，只读版一律 `return 0`；两者对「现在能不能领、能领多少」的结论一致。
- 返回值是**查询时点**的值，不是对下一笔交易的承诺：同批其他地址先领取会同时改变 `balanceOf(this)` 与 `remainingShare`，`amount` 随之变化。前端不得把预检结果当作可签名的数额，必须以交易内实际发生的 `AirdropClaimed.amount` 为准。

### 分页查询

`airdropInfos(offset, limit, reverse)` 分页读取已配置代币，返回 `AirdropInfo` 数组与配置总数 `totalCount`。`AirdropInfo` 的字段与取值：

| 字段 | 取值 |
| --- | --- |
| `tokenAddress` | 该批快照所属代币 |
| `merkleRoot` | 配置时写入的根 |
| `claimableFromRound` | 配置时算出的起始轮次 |
| `claimedShare` | 当前已领份额（后置累计值） |
| `remainingShare` | `TOTAL_SHARE - claimedShare`（当前值） |
| `contractBalance` | 该代币在本合约的当前余额 `balanceOf(this)`，逐元素读取 |

分页语义与 `Phase.observations`、`Launch.tokens` 一致：`offset` 大于或等于 `totalCount` 时返回空数组与真实 `totalCount`，不校验也不回滚；`limit` 大于剩余条数时按剩余条数返回；`reverse` 为 `true` 时从新到旧返回。列表按配置顺序追加（首币是第一个元素、构造函数里的首币配置即首次 `push`），`reverse = true` 时按插入的逆序返回，配合 `offset` 即可从最新配置向前翻页。

**不设独立计数入口**：集合总数由本入口返回的 `totalCount` 承担，`airdropInfos(0, 0, false)` 即取基数（`limit = 0` 返回空数组与真实 `totalCount`）。这是 `Pagination.pageCount` 的直接结果，不另设 `airdropCount()`。

`limit` 由调用方决定，合约不设死上限——这是分页语义的一部分，不额外开一个受限入口。代价是每页每个元素都要读一次 `balanceOf`（外部调用），所以 `limit` 同时决定一次 `eth_call` 的成本：配置数量大时前端应分页读取，不要用一次大 `limit` 拉全量，否则可能撞上节点的 gas 上限而不可调用。

`contractBalance` 是查询时点的实时值，不是快照时的首批供应量：已被领取的部分已转出合约，剩余量就是尚未领取的资产。领取进度需要对照 `remainingShare` 读，不能用余额单独推断——链下快照 `Σleaves` 与 `1e18` 的差会直接体现为两者的不成比例。

`AirdropInfo` 是 ABI 只读记录（`<X>Info`），承载查询结果，不是存储结构；合约内的存储是五个按 `tokenAddress`（及 `claimer`）索引的映射加一个只追加的 `address[]` 列表。

## 外部调用

| 调用 | 场景 | 失败处理 |
| --- | --- | --- |
| `IPhase(PHASE_ADDRESS).currentPhase()` | 配置时算 `claimableFromRound`、领取与预检时判轮次 | 协议固定依赖，不校验调用方；`Phase` 不在此处回滚，创世前返回 `0` |
| `IERC20(tokenAddress).balanceOf(address(this))` | `claim`、`claimableAmount`、`airdropInfos` | 已配置的 token 一定由 `Launch` 创建，是 `LOVE20Token`；不另设代码校验 |
| `IERC20(tokenAddress).safeTransfer(claimer, amount)` | `claim` | 失败整笔回滚，不吞异常、不降级为部分成功 |

`Launch` 对回调的透传数据只做形状层面的约定（见 [回调数据格式](#ontokenlaunched回调)），实际解码与全部业务校验在本合约完成；回调返回后 `Launch` 不再读取本合约的任何状态。

### 透传来源

| 来源 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| `SafeERC20`（OZ） | `SafeERC20FailedOperation(address token)` | `claim` 第 10 步转账失败时透传。**这是本合约唯一的外部错误来源**，不在自有 11 个错误内，链下分类必须单独识别；测试直接断言 OZ 的 selector，不要求本合约 ABI 自带 |

本合约的 11 个自有错误全部在 `IAirdropDistributorErrors` 中声明，实现文件不声明错误，也不从其他仓导入错误。`SafeERC20FailedOperation` 是库错误经 `SafeERC20` 使用进入调用方 ABI，不属于本模块 Errors。

## 边界与风险

- **Root 填错即资产锁死**：`merkleRoot` 在配置后不可更新，也没有取回入口。填错、或漏掉应得地址，该批首批供应里对应的份额将永久留在合约中，任何人无法取出。这是有意的设计取舍：可更新的 Root 等于把「谁能领多少」交给一个可以改口的中心角色。分发前必须以只读预检逐条核对。
- **链上无法验证 `Σleaves == 1e18`**：合约只有分母常量，看不到叶子集合。若链下快照份额之和小于 `1e18`，差额部分无人可领，余额永远留在合约里；若大于 `1e18`，先领取者按比例分走资产，后领取者在 `remainingShare` 耗尽后回滚 `ShareExceedsRemaining`，其应得份额拿不到。唯一防线是链下生成器的归一化与公开快照的独立复算。
- **金额随领取顺序变化**：`amount` 按剩余份额比例计算，同一地址在不同时点领取得到的数量不同。这不是缺陷而是设计：按剩余额分配使任何人都无法通过抢先领取占取超过自身份额比例的资产，也让最后一人清空余额。对账以 `AirdropClaimed.amount` 为准。
- **无管理员、无暂停、无取回入口**：没有 owner、admin、pause、rescue、upgrade，也没有改变 Root 或截止时间的入口。部署后合约行为只由代码与快照决定。
- **`NoCallback` 模式下把本合约设为子币 distributor 会锁死首批供应**：普通发射允许 `NoCallback`，此时 `Launch` 不调用回调，本合约不会为该子币写入任何配置；而 `LOVE20Token` 构造函数已把整批首批供应铸给 distributor 地址，本合约又没有取回入口。结果就是这批代币永久留在合约里、任何地址都无法领取（`claim` 恒回滚 `TokenNotConfigured`）。本合约唯一合法的子币接入方式是 `Callback` 模式并传入 64 字节配置。发射入口与前端必须在把 distributor 设为本合约时强制 `Callback`；`Launch` 本身不检查这种组合，因为它不知道 distributor 的业务语义。
- **前端必须预检**：最低限度要核对 `Σleaves == 1e18`、每条证明与 `leafHash` 一致、`claimableFromRound` 与部署所在轮次相符，并用 `claimableAmount` 逐条模拟。链上没有可弥补这些错误的手段，预检是唯一的失败前置点。

### 快照来源

首币空投的份额数据来源于旧 `LOVE20TKM/burn` 记录在链上的销毁活动结果（来源链 ID、来源区块、来源地址与份额快照）。本合约不引用该仓库的合约代码，只消费其链下快照生成器产出的 Merkle 快照；叶子格式与本合约逐字节一致：

```text
leaf     = keccak256(bytes.concat(keccak256(abi.encode(claimer, share))))
node     = keccak256(sorted(left, right))
```

树的每对节点按字节值排序后哈希，某层最后一个无配对节点直接提升到下一层；该格式与 OpenZeppelin `MerkleProof` 的排序证明验证一致，也要求链下生成器把份额归一化到精确 `1e18`。部署记录必须公开记录实际使用的来源链、来源区块、Merkle Root 与首币地址，使任何人可以独立复算，见 [仓库清单](../../repositories.md)。

验收见 [Core 验收](09-testing.md)。
