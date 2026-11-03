# LOVE20Token · 状态变量变更审查

> `core/src/LOVE20Token.sol`，59 行，`core@6fdd0f1`。
> 本合约是唯一有「铸造上限」语义的 ERC20；`Launch` 为每枚社区代币部署一份，`Mint` 是唯一的 `MINTER`。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| 1 | `MAX_SUPPLY` | `uint256 immutable` | 终生上限，含构造时的 `initialSupply` | 构造器 `:32` | 不可变 |
| 2 | `MINTER` | `address`（storage） | 唯一铸造者，`Launch` 传入 `MINT_ADDRESS` | 构造器 `:33` | **只写一次** |
| 3 | `PARENT_TOKEN_ADDRESS` | `address`（storage） | 父币；`Stake` 用它找 Pair | 构造器 `:34` | **只写一次** |
| 4 | `_balances` / `_allowances` / `_totalSupply` | OZ `ERC20` 私有 | 标准余额、授权、总量 | `_mint` / `_burn` / `_transfer` / `_approve` / `_spendAllowance` | 随转账与铸造销毁变化 |
| 5 | `_name` / `_symbol` | OZ `ERC20` 私有 | 元数据 | 构造器 | 不可变（无 setter） |

`MINTER` 与 `PARENT_TOKEN_ADDRESS` 都是**构造后不再写**的普通 storage 变量，不是 `immutable`。这与 `MAX_SUPPLY` 的处理不一致（见 `TOK-04`）。

## 2. 逐变量变更逻辑

### 2.1 `MAX_SUPPLY` / `MINTER` / `PARENT_TOKEN_ADDRESS`

| 位置 | 语句 | 前置守卫 | 联动 | 事件 |
| --- | --- | --- | --- | --- |
| `:21-25` | 构造参数校验：`initialSupply != 0`、`maxSupply >= initialSupply`、`distributor != 0`、`minter.code.length != 0`、`parentTokenAddress.code.length != 0` | — | 任一失败整笔回滚 | — |
| `:27-31` | `_mint(distributor, initialSupply)` | 上式全部通过 | `_totalSupply`、`_balances[distributor]` | `TokenMinted` |
| `:32-34` | 三个赋值 | `_mint` 已成功 | — | — |

三个变量此后再无写入点（全仓 grep `MINTER =` / `PARENT_TOKEN_ADDRESS =` / `MAX_SUPPLY =` 只有这三行）。因此「改 minter」「换父币」「提上限」在代币层面**没有入口**，只能重部署；这一点与 `08-launch.md` 的「升级 Mint 需连同 Launch 重部署」一致。

### 2.2 `_totalSupply` / `_balances`

| 位置 | 语句 | 前置守卫 | 联动 | 事件 |
| --- | --- | --- | --- | --- |
| `:42` | `mint(address to, uint256 amount)` | `onlyMinter`（`:37-40`，**函数首条判定**） | — | — |
| `:43-44` | `remaining = MAX_SUPPLY - totalSupply()`；`amount > remaining` 回滚 `MaxSupplyExceeded(amount, remaining)` | `totalSupply() <= MAX_SUPPLY` 恒成立（见 §3） | — | — |
| `:45` | `_mint(to, amount)` | 上式 | `_totalSupply += amount`；`_balances[to] += amount`；`to == 0` 由 OZ 回滚 | `TokenMinted`（`:46-49`） |
| `:52-58` | `burn(uint256 amount)` | 无调用者限制；`amount <= balanceOf(msg.sender)` 由 OZ 保证 | `_totalSupply -= amount`；`_balances[msg.sender] -= amount` | `TokenBurned` |
| 继承 | `transfer` / `transferFrom` / `approve` | OZ 标准 | `_balances` 对转、`_allowances` 扣减 | `Transfer` / `Approval` |

`mint` 没有 `amount == 0` 守卫，`burn` 也没有；两者都会成功并发出一条零额事件（`TOK-03`）。

## 3. 不变式

| 不变式 | 是否成立 | 依据 |
| --- | --- | --- |
| `totalSupply() <= MAX_SUPPLY` | ✅ 结构成立 | 构造时 `initialSupply <= maxSupply`（`:22`）；`mint` 用 `remaining` 兜底（`:43-44`）；`burn` 只减。因此 `MAX_SUPPLY - totalSupply()` **不会下溢** |
| `MINTER` / `PARENT_TOKEN_ADDRESS` 终生不变 | ✅ 成立 | 无写入点 |
| `Σ balances == totalSupply` | ✅ 成立 | 全部经由 OZ 的 `_mint`/`_burn`/`_transfer` |
| `mint` 只由 `Mint` 合约触发 | ✅ 成立 | `Mint` 是 `MINTER`；`onlyMinter` 是函数体第一道判定，先于参数读取 |
| `burn` 只能烧自己的 | ✅ 成立 | `_burn(msg.sender, amount)` |

## 4. 与下游的状态耦合

| 下游读取 | 用途 | 写入侧影响 |
| --- | --- | --- |
| `Mint.rewardAvailable`（`Mint:452-456`） | `MAX_SUPPLY - totalSupply - reservedAvailable` | **任何持有人 `burn` 都会抬高 `rewardAvailable`**，即把「已发行的币」重新变成「未来可铸额度」。这是「燃烧→再铸」的设计，不是漏洞：燃烧者损失自己的余额，收益归后续轮次的参与者 |
| `MemberNFT.calculateMintCost`（`MemberNFT:103-122`） | `MAX_SUPPLY - totalSupply` 作为身份费基数 | 身份铸造会 `burn`，因此**每铸一个身份，下一个身份更贵**（正反馈）。该行为由「未铸造量」定义，属设计 |
| `Stake._pairSnapshot` / `_swapParentTokenForToken` | `PARENT_TOKEN_ADDRESS` 决定 Pair 与兑换路径 | 构造后不可改，路径稳定 |

## 5. 发现

| ID | 级别 | 位置 | 结论 | 建议 |
| --- | --- | --- | --- | --- |
| `TOK-03` | Info | `:42-50`、`:52-58` | 零额 `mint` / `burn` 无守卫，会发 `TokenMinted(0)` / `TokenBurned(0)`。账本无影响，但索引器与「每笔 mint 都代表增发」的假设会被打破 | 加 `if (amount == 0) return;`，或在 `Mint` 侧保证（当前 `Mint` 已保证 `mintAmount > 0`，所以只有外部直接调用 `burn(0)` 可达） |
| `TOK-04` | Info | `:9-10`、`:33-34` | `MINTER` 与 `PARENT_TOKEN_ADDRESS` 是构造后不再写的 storage，却未声明 `immutable`：`mint` 每笔多一次 `MINTER` 冷 SLOAD（约 2.1k gas），`PARENT_TOKEN_ADDRESS` 被 `Stake` 每次读取也走 storage 而非立即数；且「不可变」只是人工约定而非编译器保证 | 改为 `address public immutable MINTER;`。与 `MAX_SUPPLY` 一致，也与既有审查 `TOK-01` 的同一结论合并 |

> `TOK-01`（`burn` 对任何人开放、全仓无 rescue）已在 `core-review-plan-2026-11` 登记为 Info；本卷复核其状态面结论不变：`burn` 只能动 `msg.sender` 的余额，唯一外部效应是通过 `rewardAvailable` 影响未来轮次。

## 6. 已核对为正确的点

- `mint` 的上限判定读 `totalSupply()` 而不是本地计数，不存在「本地计数漂移」。
- `onlyMinter` 是 modifier、在函数体最前、自己判 `msg.sender`，符合仓库的调用者校验规范。
- 构造器对 `minter` / `parentTokenAddress` 用 `code.length == 0` 拒绝 EOA 与零地址，把「依赖未部署」挡在部署期。
- `_mint(distributor, initialSupply)` 在写 `MINTER` **之前**执行；即使 distributor 是恶意合约（ERC20 无回调，实际不可回调），也不会观察到半初始化的状态。

## 7. 覆盖缺口

- 未复核 OZ 5.6.1 的 `_mint`/`_burn` 实现细节，按其公开语义认定。
- `MAX_SUPPLY` 的取值域（`launchAmount <= maxSupply`）由部署脚本保证，合约只保证 `initialSupply <= maxSupply`。
