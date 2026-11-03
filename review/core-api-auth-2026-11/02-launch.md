# Launch 接口调用权限审查

> 对象 `core/src/Launch.sol`（350 行）
> 接口 `core/src/interfaces/ILaunch.sol`（145 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/08-launch.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 25（写 4 / 读 21） |
| 带鉴权 modifier | 3（`onlyMemberOwner` ×2、`onlyMint` ×1） |
| 无许可写入口 | 1（`init`） |
| 发现 | 5 条：Medium 1（与既有 DEP-01 同源，不新增计数）/ Low 1 / Info 3 |
| 接口对账 | 25 vs 25，**0 差异** |

一句话：**四个写入口里三个权限链闭合（成员身份 → 次数账本 → Mint 合约），唯一开口是 `init`——而它恰好是整个协议里权限后果最重的一处：它同时决定 `MEMBER_NFT_ADDRESS`（Launch 全部成员鉴权的信任根）、首币参数、Pair 工厂与铸造方。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 成员 NFT 持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `launchToken`（`memberId`）、`mergeLaunchCount`（`sourceMemberId`） |
| Mint 合约 | `msg.sender == MINT_ADDRESS` | `addLaunchCount` |
| 无 | 只判 `initialized` | `init` |
| 无 | — | 21 个只读 getter |

两条关键语义（`01-common-rules.md`「主体与权限」）：

1. **单向融合只增加目标状态，不要求调用者持有目标 NFT**——所以 `mergeLaunchCount` 只校验源，目标做存在性检查。
2. **处分成员权益时校验 `ownerOf(memberId) == msg.sender`**——发射次数是成员权益，故 `launchToken` 必须校验 `memberId` 的所有权。

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `init(LaunchInitParams)` | 无（一次性） | `if (initialized) revert` | 是 | `GenesisTokenCreated` |
| `launchToken(string,address,uint256,address,uint8,bytes[])` | `memberId` 持有人 | `onlyMemberOwner(memberId)` `L36` | 是（唯一修饰符） | `LaunchCountConsumed` → `TokenLaunched` |
| `mergeLaunchCount(address,uint256,uint256,uint256)` | `sourceMemberId` 持有人 | `onlyMemberOwner(sourceMemberId)` | 是 | `LaunchCountMerged` |
| `addLaunchCount(address,uint256,uint256)` | `MINT_ADDRESS` | `onlyMint` `L31` | 是 | `LaunchCountAdded` |

### 只读入口（21）

配置 getter 14：`MINT_ADDRESS`、`MEMBER_NFT_ADDRESS`、`ROOT_PARENT_TOKEN_ADDRESS`、`FIRST_TOKEN_ADDRESS`、`PAIR_FACTORY_ADDRESS`、`TOKEN_SYMBOL_LENGTH`、`LAUNCH_COUNT_THRESHOLD_RATIO`、`MAX_LAUNCH_COUNT`、`LAUNCH_AMOUNT`、`MAX_SUPPLY`、`MAX_TOKEN_SYMBOL_LENGTH`、`MAX_TOKEN_NAME_LENGTH`、`TEST_PREFIX_BYTES`、`initialized`。

查询 7：`isLOVE20Token`、`remainingLaunchCount`、`issuedLaunchCount`、`tokens`、`childTokens`、`tokenAddressBySymbol`、`parentToken`。全部无权限、无事件要求，规格明示 `isLOVE20Token` 对未登记地址返回 `false` 且不回滚。

## 四、逐入口判定

### `init` — 全部成员鉴权的信任根在这里被固定

- 唯一无许可写入口，只判 `initialized`。这与 `01-common-rules.md`「一次性依赖初始化入口统一为 `init`，一律不设调用者限制」一致，不是实现疏漏。
- 但本合约的 `init` 承担了比其他 `init` 更重的职责：它写入 `MEMBER_NFT_ADDRESS`，而 `Launch` 的两个成员入口、以及 `Stake`/`Submit`/`Vote`/`Mint` 的成员入口，全部以「某个 MemberNFT 合约的 `ownerOf`」为鉴权判据。**这一个是整个协议的鉴权信任根**，抢跑者只要把 `params.memberNFTAddress` 指向自己部署的合约，`_ownerOf` 就永久由攻击者决定，`onlyMemberOwner` 形同虚设。
- 次级后果：`ROOT_PARENT_TOKEN_ADDRESS`、`PAIR_FACTORY_ADDRESS`、`MINT_ADDRESS`、`LAUNCH_AMOUNT`、`MAX_SUPPLY`、首币名称/符号/distributor 一并被决定；`init` 内部还会 `new LOVE20Token(...)` 并以 `MINT_ADDRESS` 为其 minter，因此**该首币的铸造权也随 `MINT_ADDRESS` 一起被决定**。
- 兜底在部署期，不在合约：`DeployCore.s.sol:233` 调用 `Launch.init` 后，`L342` 校验 `launch.MEMBER_NFT_ADDRESS() == addrs.memberNFT`，`21_check.sh` 独立复核。这正是 dev-standards §5.7 的分工（部署期静态绑定由脚本校验）。
- 判定：**Medium，与既有审查的 DEP-01 同源，本报告不新增计数**，只补充权限侧结论——被抢跑的版本不是「参数错」，而是「鉴权根换人」。发布前检查必须把 `MEMBER_NFT_ADDRESS` 与各依赖合约的绑定同时核对，不能只核 `initialized()`。

### `launchToken` — 谁的次数谁花

- 校验：`onlyMemberOwner(memberId)` → 符号格式 → `distributor != 0` → 父币已登记 → **该父币维度剩余次数 > 0** → 递减 → 创建代币 → 登记账本 → 发事件 → 回调 distributor。
- 权限边界清晰：`memberId` 的所有权决定「能否花这份次数」，`_remainingLaunchCount[parentTokenAddress][memberId]` 决定「花谁的」——两者用同一个 `memberId`，无法用 A 的身份花 B 的次数。
- 次数递减发生在 `_createToken` **之前**（`L111-119`），外部调用（`new LOVE20Token`、`factory.getPair`/`createPair`、`distributor.onTokenLaunched`）都在账本封账之后。CEI 成立。
- `distributor` 是发射者自由指定的地址，`Callback` 模式下只要求 `code.length != 0`（`_checkDistributorMode`）。这是一个**由成员授权、指向任意合约的出口**：被指定的 distributor 会收到 `onTokenLaunched(tokenAddress, parentTokenAddress, memberId, distributorData)`，其中 `memberId` 是发射者身份。distributor 若误信该回调的调用者，需自行校验 `msg.sender == Launch`（见 §七）。
- `TokenLaunched` 在回调之前发出（`L139`），重入发射的内层事件会插在外层事件之后。这是事件顺序问题，不是权限问题。

### `mergeLaunchCount` — 只验源，不验目标

- `onlyMemberOwner(sourceMemberId)` + `sourceMemberId != targetMemberId` + `count != 0` + 代币已登记 + `_ownerOf(targetMemberId)` 存在性 + 源余额充足。
- 目标只做存在性检查，**不要求调用者持有目标 NFT**——与 `01-common-rules.md`「单向融合只增加目标状态」一致。副作用：可以把次数赠送给任意存在的 `memberId`，且不可撤回；没有资产损失，只有「送出去」。
- `_ownerOf(targetMemberId)` 的返回值被丢弃，作用是存在性断言；目标不存在时由 OZ 抛 `ERC721NonexistentToken`（见 LCH-03）。

### `addLaunchCount` — 唯一能增发的入口，且没有第二个

- `onlyMint`：`msg.sender == MINT_ADDRESS`。`MINT_ADDRESS` 由 `init` 固定、无 setter。
- 增发上限：`count > MAX_LAUNCH_COUNT - issuedCount` 回滚 `LaunchCountLimitExceeded`。`_issuedLaunchCount` 只增不减（`_addLaunchCount` 内 `+=`），因此上限是硬顶。
- **根级次数的伴生写入没有独立入口**：`addLaunchCount` 在 `tokenAddress == FIRST_TOKEN_ADDRESS` 时额外调 `_addLaunchCount(ROOT_PARENT_TOKEN_ADDRESS, …)`（`L201-203`），`_addLaunchCount` 是 `private`。这意味着「根父币维度的次数」只能由首币维度的授权写入伴生产生，任何人都无法直接给根维度记账。权限上是正确的收敛。
- 未初始化时 `MINT_ADDRESS == 0`，`msg.sender != 0` 恒成立 ⇒ 除 `address(0)` 外无法调用；而 `address(0)` 不可能发起交易。等价于「未初始化即关闭」。

## 五、发现

### LCH-01（Medium，与 DEP-01 同源，不新增计数）`init` 抢跑等于替换鉴权信任根

- 证据：`init` 无调用者限制（`L54-85`）；`params.memberNFTAddress` 只用于 `IMemberNFT(...).init(firstToken)`，无 `code.length` 校验；`_ownerOf` 直接读该地址（`L263-265`）。
- 影响：抢跑者把 `memberNFTAddress` 指向自己实现的合约后，`ownerOf` 返回攻击者地址 ⇒ `launchToken`、`mergeLaunchCount` 的 `onlyMemberOwner` 全部可被攻击者通过；同时首币参数与铸造方被决定。
- 兜底：`DeployCore.s.sol:342` 与 `21_check.sh` 核对绑定，不一致必须重部署。规格 `08-launch.md` 已声明该窗口，并要求逐项核对 `initialized()`、依赖地址、首币名称与符号、分发地址、发射参数。
- 建议：发布检查清单把 `MEMBER_NFT_ADDRESS` 列为**首要**核对项（其余项错了只是参数错，这一项错了是鉴权失效），并在 `21_check` 的失败信息里显式标注「鉴权根不匹配」。

### LCH-02（Low）`launchToken` 无重入锁，distributor 回调可再次发射

- 证据：`launchToken` 无 `nonReentrant`；`ILaunchDistributor.onTokenLaunched` 回调在函数末尾（`L149-151`）；账本（次数递减、`_tokens`、`_parentTokenByTokenAddress`、`_tokenAddressBySymbol`、`_childTokens`）全部在回调前写完。
- 判定：**不构成越权**。重入需要同一 `msg.sender` 再持有该 `memberId`，且该父币维度还有剩余次数；重入产生的第二笔发射与「连续调两次」语义等价。CEI 已成立，不会出现同一份次数被重复花。
- 风险边界：若 distributor 在回调里改变外部状态（例如自己记账），它看到的是「外层已完全封账」的世界；这是它可以依赖的。
- 建议：在 `08-launch.md` 补一句「发射回调可重入，外层账本在回调前已封账；distributor 如需拒绝重入应自行加锁」。当前规格未写这一条。

### LCH-03（Info）目标 `memberId` 不存在时的错误不是 `NotMemberOwner`

- 证据：`mergeLaunchCount` 用 `_ownerOf(targetMemberId)` 做存在性检查（`L167`），目标不存在时由 OZ 抛 `ERC721NonexistentToken(targetMemberId)`。
- 与 §5.5 的关系：「非授权方只拿到鉴权错误，不能借错误差异探测内部状态」。这里 `msg.sender` 是合法源持有人，探测的是**目标是否存在**，而不是自己是否被授权；且 `memberId` 由 ERC721Enumerable 公开可枚举，无信息增量。
- 判定：不构成缺陷。建议在 `01-common-rules.md` 统一声明「`memberId` 不存在时由 `ownerOf` 抛 `ERC721NonexistentToken`」，避免每个模块规格各自补一句（`06-vote.md` 已单独写了这句，其余四处未写）。

### LCH-04（Info）`MINT_ADDRESS` 与代币的 `MINTER` 没有交叉校验

- 证据：`addLaunchCount` 只认 `MINT_ADDRESS`（`L32`）；代币的 `MINTER` 由 `_createToken` 传入 `MINT_ADDRESS`（`L251`），两者在构造上必然一致。
- 判定：当前无风险。但「加次数」与「铸币」是两个独立授权面，若未来引入第二个铸造方或迁移 Mint 合约，必须同时改这两处，否则会出现「能加次数但不能铸币」或反之。建议在 `08-launch.md` 的依赖表里把这条一致性列为部署期不变量。

### LCH-05（正面结论）发射次数的账本不可被外部直接改写

- 证据：`_remainingLaunchCount`、`_issuedLaunchCount` 的唯一写入点是 `_addLaunchCount`（private）与 `launchToken` 内的递减、`mergeLaunchCount` 内的搬移。
- 判定：三个入口分别对应「增发（仅 Mint）」「消耗（仅持有人）」「搬移（仅源持有人）」，没有第四个写入口。`issuedLaunchCount` 只增，`remainingLaunchCount` 的减少只发生在消耗与搬移，恒等式 `Σ剩余 + 已消耗 = 已产生` 由结构保证。

## 六、核对证据

```text
$ forge inspect Launch abi --json            # 25 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

鉴权负例测试（全部断言「鉴权先于参数/存在性/账本」）：

| 用例 | 位置 | 断言 |
| --- | --- | --- |
| 非持有人发射 | `test/Launch.t.sol:921-924` | `NotMemberOwner(aliceMemberId)` |
| 转移后原持有人发射 | `test/Launch.t.sol:1008-1011` | 同上 |
| 非持有人合并 | `test/Launch.t.sol:1191-1194` | 同上 |
| 鉴权先于参数 | `test/Launch.t.sol:1215-1218` | 同上（`count == 0` 也先报鉴权） |
| 鉴权先于账本 | `test/Launch.t.sol:1248-1251` | 同上 |
| 非 Mint 加次数 | `test/Launch.t.sol:1337-1340`、`1345-1348` | `NotMintContract(caller)` |
| 鉴权先于计数上限 | `test/Launch.t.sol:1437-1440` | 同上 |
| 未初始化也先报鉴权 | `test/Launch.t.sol:1480-1483` | 同上 |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 下游 | `LOVE20Token`（构造） | 传 `MINTER = MINT_ADDRESS`、父币地址 |
| 下游 | `MemberNFT.init` | `init` 内代调，把首币地址交给 MemberNFT；**Launch 不保存 MemberNFT 之外的部署者信息** |
| 下游 | `IUniswapV2Factory` | `getPair`/`createPair`，Pair 生命周期归 Launch |
| 下游 | `ILaunchDistributor.onTokenLaunched` | 发射回调；**实现方必须校验 `msg.sender == Launch`**（`action` 仓未见该接口实现，属本仓库外契约） |
| 上游 | `Mint._updateLaunchCredit` | 唯一调用 `addLaunchCount` 的合约 |
