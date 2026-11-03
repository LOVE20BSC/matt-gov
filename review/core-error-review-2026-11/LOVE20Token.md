# `core/LOVE20Token.sol` 错误赋值与发送专项 Review

> 基线：`core@6fdd0f1`（2026-11-03），行号按当前工作树。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/core/08-launch.md`。
> 范围：`src/LOVE20Token.sol`（59 行）+ `src/interfaces/ILOVE20Token.sol` 的 `ILOVE20TokenErrors`。

## 1. 结论

- 6 个错误声明 / 7 个发送点；覆盖完整，无裸 `require`。
- 构造器 5 个校验全部在 `_mint` 之前；`mint` 先算 remaining 再铸，供应上限不可越过。
- 3 条 Info：`InvalidInitialSupply` 的名字指向 `initialSupply`，实际条件是 `maxSupply < initialSupply`；零地址接收方与 `burn` 余额不足由 OZ 透传（ABI 自包含，符合 §1）。
- 零地址接收方与余额不足由 OZ 标准错误透传，`ILOVE20Token` 继承 `IERC20Errors`，ABI 自包含（符合 §1）。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 6 |
| revert 站点 | 7 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 3 |

## 2. 错误清单

| 错误 | 签名 | 站点 | 判定 |
| --- | --- | --- | --- |
| `ZeroInitialSupply` | `ZeroInitialSupply()` | 1 | 保留 |
| `InvalidInitialSupply` | `InvalidInitialSupply(uint256,uint256)` | 1 | 改名建议 |
| `ZeroDistributorAddress` | `ZeroDistributorAddress()` | 1 | 保留 |
| `DependencyNotContract` | `DependencyNotContract(address)` | 2 | 保留 |
| `NotMinter` | `NotMinter(address)` | 1 | 保留 |
| `MaxSupplyExceeded` | `MaxSupplyExceeded(uint256,uint256)` | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；“实参赋值”列就是 revert 时写入 payload 的表达式。

### `ZeroInitialSupply` · 1 站点 · 保留

- 声明：`interfaces/ILOVE20Token.sol:20`
- 签名：`ZeroInitialSupply()`
- 载荷：无
- 核对：无载荷；`initialSupply == 0`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LOVE20Token.sol:21` | `constructor` | `initialSupply == 0` | `—` |

### `InvalidInitialSupply` · 1 站点 · 改名建议

- 声明：`interfaces/ILOVE20Token.sol:21`
- 签名：`InvalidInitialSupply(uint256,uint256)`
- 载荷：`uint256 value, uint256 maxSupply`
- 赋值链：initialSupply/maxSupply ← 构造入参（`Launch.init` 的 `launchAmount`/`maxSupply`）。
- 核对：名字指向的字段与失败条件不一致，见 E-TOK-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LOVE20Token.sol:22` | `constructor` | `maxSupply < initialSupply` | `initialSupply, maxSupply` |

### `ZeroDistributorAddress` · 1 站点 · 保留

- 声明：`interfaces/ILOVE20Token.sol:25`
- 签名：`ZeroDistributorAddress()`
- 载荷：无
- 核对：无载荷；distributor 是 EOA 可用的接收方，属非合约参数。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LOVE20Token.sol:23` | `constructor` | `distributor == address(0)` | `—` |

### `DependencyNotContract` · 2 站点 · 保留

- 声明：`interfaces/ILOVE20Token.sol:26`
- 签名：`DependencyNotContract(address)`
- 载荷：`address dependency`
- 赋值链：minter ← `MINT_ADDRESS`；parentTokenAddress ← 根父币（均由 `Launch.init` 传入）。
- 核对：载荷 `(dependency)`；minter 与 parentToken 两个站点共用，条件同为“无代码”。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LOVE20Token.sol:24` | `constructor` | `minter.code.length == 0` | `minter` |
| 2 | `LOVE20Token.sol:25` | `constructor` | `parentTokenAddress.code.length == 0` | `parentTokenAddress` |

### `NotMinter` · 1 站点 · 保留

- 声明：`interfaces/ILOVE20Token.sol:27`
- 签名：`NotMinter(address)`
- 载荷：`address caller`
- 核对：载荷 `(caller)`；`mint` 唯一入口。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LOVE20Token.sol:38` | `onlyMinter` | `msg.sender != MINTER` | `msg.sender` |

### `MaxSupplyExceeded` · 1 站点 · 保留

- 声明：`interfaces/ILOVE20Token.sol:28`
- 签名：`MaxSupplyExceeded(uint256,uint256)`
- 载荷：`uint256 requested, uint256 remaining`
- 赋值链：remaining ← `MAX_SUPPLY − totalSupply()`（`LOVE20Token.sol:43`）。
- 核对：载荷 `(requested, remaining)`，actual+limit 完整。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `LOVE20Token.sol:44` | `mint` | `amount > remaining` | `amount, remaining` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-TOK-01 | Info | `src/LOVE20Token.sol:22` | `InvalidInitialSupply(initialSupply, maxSupply)` 的名字指向 `initialSupply`，实际失败条件是 `maxSupply < initialSupply`（非法的是 maxSupply 相对初始供应的关系）。§3 的 `Invalid<Field>` 应指向非法字段。 | error-standards §3；站点 `:22` | 改为 `MaxSupplyBelowInitialSupply(uint256 initialSupply, uint256 maxSupply)`（破坏 ABI）；或在 Natspec/规格说明“以初始供应为参照”。 |
| E-TOK-02 | Info | `src/LOVE20Token.sol:42-45` | `mint` 不校验 `to != address(0)`，零地址由 OZ `ERC20InvalidReceiver` 透传；`ILOVE20Token` 继承 `IERC20Errors`，ABI 自包含（符合 §1）。`Mint` 已在入口判 `recipient`，core 内该路径不可达。 | error-standards §1/§7 | 无需改代码；在 07-mint 或 08-launch 的透传表登记 `ERC20InvalidReceiver` 即可。 |
| E-TOK-03 | Info | `src/LOVE20Token.sol:52-57` | `burn` 的余额不足由 OZ `ERC20InsufficientBalance` 透传；Stake/MemberNFT 的规格已登记来源，Launch 不调用 `burn`。 | error-standards §1/§7 | 无需改代码；保持“标准错误由产生者拥有”。 |

### 4.2 已核对项

- 声明在 `ILOVE20TokenErrors`；实现零声明；无裸 `require`/`revert`。
- 构造器校验顺序：初始供应零 → 上限小于初始 → distributor 零 → minter 无代码 → parent 无代码，全部在 `_mint` 之前。
- `MaxSupplyExceeded` 的 `remaining` 是本次调用前的 `MAX_SUPPLY - totalSupply()`，与 §4 actual+limit 一致。
- `mint` 的 `onlyMinter` 是首道判定；`burn` 开放给任何持币者，无权限错误。
- `check_error_tests.py`：0 untested；`test/LOVE20Token.t.sol` 断言 `MaxSupplyExceeded` 载荷。

### 4.3 透传错误面

| 来源调用 | 可能出现的 selector | 说明 |
| --- | --- | --- |
| OZ ERC20 | `ERC20InvalidReceiver(address)`、`ERC20InsufficientBalance(address,uint256,uint256)`、`ERC20InsufficientAllowance(address,uint256,uint256)` | 标准错误由 OZ ABI 拥有；`ILOVE20Token` 显式继承 `IERC20Errors`。 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd core
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：`src/LOVE20Token.sol` 中每个 `revert <Error>(...)` 计一个站点；载荷为括号内实参原文；判据取该 revert 之前最近的 `if`。声明行号取 `src/interfaces/ILOVE20Token.sol`。
