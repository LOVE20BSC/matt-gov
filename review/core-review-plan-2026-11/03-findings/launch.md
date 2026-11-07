> 历史卷标注：本文中关于根父币计数维度与 `2 × MAX_LAUNCH_COUNT` 的描述已被 `dac6d59` 取代；正文保持原样，不再作为当前实现依据。

# Launch（含部署序列）

350 行、12,229 字节。`Launch` 不持资产；问题集中在「记账口径」与「部署序列」。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| LCH-01 | Info | 预建 Pair 被幂等复用（H-01 分支），无害；本次补测 |
| LCH-02 | Low | 一份额度买两次发射；根级账本不受 `MAX_LAUNCH_COUNT` 约束 |
| LCH-03 | Info | `mergeLaunchCount` 让发射额度可转让，单成员上限因此不存在 |
| LCH-04 | Info | `Test` 前缀让符号每代 +4 字节，深度被 `32` 卡在 6 代 |
| DEP-01 | **Medium** | 7 个 `init` 无调用者限制 + 逐笔广播，抢跑即产生 8 个不可删除的孤儿合约 |

---

## LCH-01 · 预建 Pair 被复用

| 字段 | 值 |
| --- | --- |
| 单元 | L4（`Launch:238-350`） |
| 文件:行 | `Launch:250-260` |
| 函数/变量 | `_createToken` / `factory.getPair` / `createPair` |
| 类别 | 幂等 / 外部依赖 |
| 严重度 | Info |
| 攻击者画像 | 任何人（可预测子币地址） |
| 前置条件 | 攻击者先于 `launchToken` 用 `createPair(predictedChild, parent)` 建好 Pair |
| 触发序列 | ①`nonce = getNonce(launch)`；②`predicted = createAddress(launch, nonce)`；③`factory.createPair(predicted, parent)`；④`launchToken(...)`；⑤`getPair != 0` → 跳过 `createPair`；⑥子币照常登记、可质押 |
| 影响 | **无**。Pair 的 `token0/token1` 必然是同一对地址（Factory 按地址排序部署），第一次 `pair.mint` 会用真实余额初始化 |
| 设计依据 | 幂等设计：`if getPair == 0 then createPair`，`PairCreationFailed` 只兜 `createPair` 返回 0 |
| 证据等级 | **E3** |
| 证据路径 | `test_launchReusesPrecreatedPair` |
| 置信度 | 高 |
| 状态 | 已关闭（覆盖缺口已补） |

### 为什么这件事值得单独测

H-01 在计划里被列为「分支零覆盖」。补测的价值不在于找 bug，而在于确认三件容易被想错的事：

1. **地址可预测**：`new LOVE20Token` 是 `CREATE`，地址 = `keccak(rlp(launch, nonce))`。测试用 `vm.computeCreateAddress` 算出同一个地址，`launchToken` 返回的确实是它。
2. **计数不增**：`factory.createdPairCount()` 在 `launchToken` 前后相同（测试断言），说明没有多建一个空 Pair。
3. **复用后可用**：子币被 `isLOVE20Token` 认可、`parentToken` 正确、`stakeLiquidity` 能拿到非零份额。

### 一个附带效应（不是缺陷）

攻击者可以在子币诞生**之前**把父币转进那个空 Pair。此时 `getReserves()` 仍是 `(0,0)`（`transfer` 不改储备），但 `pair.mint` 用 `balance − reserve` 计额，会把这笔捐赠算进 `amount1`：

```solidity
uint256 amount0 = balance0 - _reserve0;   // 只有存入者的量
uint256 amount1 = balance1 - _reserve1;   // 存入者的量 + 攻击者的捐赠
liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
```

结果是**第一个质押者白拿攻击者的捐赠**。攻击者没有任何回收路径（LP 归 `Stake`，`lastWithdrawableLp` 全部记给该成员）。同时 `_optimalAmounts:701-703` 在单侧储备为 0 时跳过滑点检查，返回原始数量——对首存正是正确行为。

所以这条路径的净效果是「自费送礼」，不登记。

---

## LCH-02 · 一份额度买两次发射

| 字段 | 值 |
| --- | --- |
| 单元 | L3（`Launch:154-236`） |
| 文件:行 | `Launch:187-204`、`Launch:334-349` |
| 函数/变量 | `addLaunchCount` / `_addLaunchCount` / `_issuedLaunchCount` |
| 类别 | 账本口径 |
| 严重度 | Low |
| 攻击者画像 | 无（设计口径） |
| 前置条件 | 从首币获得发射额度 |
| 触发序列 | ①`Mint` 在首币上记账 1 次 → `addLaunchCount(FIRST, m, 1)`；②`_addLaunchCount(FIRST, m, 1)` 且 `_addLaunchCount(ROOT, m, 1)`；③`launchToken(parent=FIRST)` 扣 FIRST 的剩余；④`launchToken(parent=ROOT)` 扣 ROOT 的剩余；⑤同一份额度支持两次发射 |
| 影响 | 社区总数上限为 `2 × MAX_LAUNCH_COUNT`（首币级与根级各一份）；根级 `_issuedLaunchCount` 可超过 `MAX_LAUNCH_COUNT` |
| 设计依据 | `:201-203` 的镜像记账；`MAX_LAUNCH_COUNT` 的检查只针对入参 `tokenAddress`（`:194-197`） |
| 证据等级 | E1 |
| 证据路径 | `Launch:194-203`、`:334-349` |
| 置信度 | 高（算术确定） |
| 状态 | 已关闭（判定为可接受） |

### 为什么不升级

- 根级额度只用于「挂到根币下面」的发射，首币级额度只用于「挂到首币下面」的发射。两者是**不同的父节点**，不是同一份权利的重复消费。
- `_issuedLaunchCount[ROOT]` 溢出上限没有后果：`issuedLaunchCount(ROOT)` 只有 view 会读，而 `MAX_LAUNCH_COUNT` 的比较永远发生在被记账的那个代币上。
- `addLaunchCount(ROOT, ...)` 虽然 `:195` 会下溢 revert，但这条路径不可达：`Mint` 只对「有票、有供应上限」的代币工作，而 `ROOT = router.WETH()`（`DeployCore:85`）没有 `MAX_SUPPLY()`，任何 `mintGovReward(ROOT, ...)` 都会在 `_govRewardCalculation` 早退后 revert。

### 真正该记的边界

> 根级发行量由首币额度镜像决定，所以「首币社区」事实上是整个发射树的唯一闸门。首币的发射额度一旦发满，整棵树停止生长——包括根级。

这不是缺陷，但它决定了「发射树的高度与宽度都由首币的 `MAX_LAUNCH_COUNT` 与 `LAUNCH_RATIO` 决定」，部署时应把这两个参数当成全局参数看，而不是首币的局部参数。

---

## LCH-03 · 发射额度可转让

| 字段 | 值 |
| --- | --- |
| 单元 | L3 |
| 文件:行 | `Launch:154-185` |
| 函数/变量 | `mergeLaunchCount` |
| 类别 | 设计自洽 |
| 严重度 | Info |
| 攻击者画像 | 任意 source 的 NFT 持有人 |
| 前置条件 | source 有剩余额度，target 是已存在的 memberId |
| 触发序列 | ①`mergeLaunchCount(token, source, target, n)`；②source 减 n，target 加 n；③`_issuedLaunchCount` 不变 |
| 影响 | 额度可集中到一个成员手里；`MAX_LAUNCH_COUNT` 只约束「每代币累计发行」，不约束「每个成员持有多少」 |
| 设计依据 | 与 `mergeStake` 同构：把「身份」当作可组合的载体 |
| 证据等级 | E1 |
| 证据路径 | `Launch:169-175` |
| 置信度 | 高 |
| 状态 | 已关闭 |

与 `mergeStake` 一起看，`MemberNFT` 事实上是「治理仓位 + 发射额度」的可转让容器。这是明确的组合性设计，不是漏洞；但意味着「每人最多发射 N 次」这类宣传口径不成立，能说的只有「每代币累计最多发行 `MAX_LAUNCH_COUNT` 次」。

---

## LCH-04 · `Test` 前缀压缩发射深度

| 字段 | 值 |
| --- | --- |
| 单元 | L4 |
| 文件:行 | `Launch:319-332`、`Launch:246-249` |
| 函数/变量 | `_addTestPrefixIfNeeded` / `MAX_TOKEN_SYMBOL_LENGTH` |
| 类别 | 参数域 / 边界 |
| 严重度 | Info |
| 攻击者画像 | 无 |
| 前置条件 | 根币符号以 `Test` 开头（测试网惯例） |
| 触发序列 | ①首币符号 `TestXXXX`；②子币符号 = 用户传入的 `TOKEN_SYMBOL_LENGTH` 字节 + `Test`；③第 g 代长度为 `L + 4g`；④`L + 4g > 32` 时 `:248` revert `TokenSymbolTooLong` |
| 影响 | 测试网上发射树最深 6 代（`L = 8`）；主网 `ROOT = WBNB` 不带前缀，深度不受此限 |
| 设计依据 | 前缀在长度校验**之后**追加（`_checkValidTokenSymbol:271` 先比 `TOKEN_SYMBOL_LENGTH`），所以 `DeployCore:148-151` 用 `L + 4 ≤ 32` 兜底 |
| 证据等级 | E1 |
| 证据路径 | `Launch:121-129`、`:271-272`、`:246-249`、`DeployCore:148-151`、`21_check:250-265` |
| 置信度 | 高 |
| 状态 | 已关闭 |

名字侧不受影响：`tokenName = symbol + "@" + parentSymbol`，最坏 32+1+32 = 65 ≤ `MAX_TOKEN_NAME_LENGTH = 96`。

---

## DEP-01 · `init` 抢跑：8 个不可删除的孤儿合约

| 字段 | 值 |
| --- | --- |
| 单元 | 部署序列（表 F） |
| 文件:行 | `Stake:83-94`、`Mint:82-98`、`Submit:55-58`、`Vote:52-55`、`Launch:55-66`、`MemberNFT:55-58`、`DeployCore:89-91` |
| 函数/变量 | 全部 `init`；`_validateDeployment` |
| 类别 | 部署 / 初始化 |
| 严重度 | **Medium** |
| 攻击者画像 | 任何观察 mempool 的人（BSC 上即任意 searcher） |
| 前置条件 | 部署者按 `11_deploy.sh --slow` 逐笔广播（`--slow` 会等每笔确认） |
| 触发序列 | ①部署脚本广播 `new Stake()`；②攻击者看到 `Stake` 地址后立刻调 `Stake.init(...)`，参数任填；③部署者的 `init` 撞 `AlreadyInitialized` 回滚；④同理打断其余 `init`；⑤`_validateDeployment` 在 `stopBroadcast` 之后才跑，发现时 8 个合约已在链上、无 `selfdestruct` |
| 影响 | 确定性损失：部署被打断 + 8 个孤儿合约（Gas）+ 接线与经济常量由首个调用者决定；资金损失是条件性的（要部署方无视脚本非零退出继续公布） |
| 设计依据 | `init` 只防重复，不防「谁先」；校验放在广播之后 |
| 证据等级 | E1 |
| 证据路径 | 表 F；`DeployCore:85-91` 的顺序；`11_deploy.sh` 的 `--slow` |
| 置信度 | 高 |
| 状态 | 已确认待修 |

### 为什么独立判为 Medium

四个事实各自都「不新」，但组合起来是一条完整的、无需资金前置的攻击：

1. **每个 `init` 都是公开的**：`Stake.init:83` 只看 `initialized`；
2. **广播是逐笔的**：`--slow` 让每笔都单独上链，攻击者有完整的窗口；
3. **不可逆**：没有 setter，`initialized` 一次为真；
4. **校验在最后**：`DeployCore:91` 的 `_validateDeployment` 跑在 `stopBroadcast()` 之后，它的失败只意味着「脚本退出码非零」，不会回滚任何已广播的交易。

抢跑的产物不是「明显错误的副本」而是**语法合法、语义任意**的配置：`Stake:83-94` 对 `FEE_SETTLEMENT_RATIO`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS` 一个 `require` 都没有；`Mint:82-98` 对 4 个地址与 4 个比例零校验；`Launch:55-66` 让 5 个经济常量原样落库。

### 顺序事实

`Launch.init:75` 在内部调 `MemberNFT.init(firstToken)`。所以：

- 抢跑 `MemberNFT.init` → 之后 `Launch.init` 整笔回滚（含首币部署）；
- 抢跑 `Launch.init` → 首币由攻击者的参数决定，`MemberNFT` 也被绑到攻击者的币上。

### 约束与失效边界

| 项 | 内容 |
| --- | --- |
| 约束 | 需要攻击者能观察到部署交易；私有 mempool / Flashbots 式通道可消除窗口 |
| 失效边界 | 若部署方在检测到 `AlreadyInitialized` 后**继续**公布地址，用户会与攻击者配置的合约交互——这时才产生资金损失 |
| 损失承担者 | 部署方（重部署的 gas 与时间）；条件性地，用户（若地址被公布） |
