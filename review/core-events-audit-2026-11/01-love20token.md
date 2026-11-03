# LOVE20Token 事件赋值与发射审查

- 实现：`core/src/LOVE20Token.sol`（59 行，`6fdd0f1`）
- 声明：`core/src/interfaces/ILOVE20Token.sol`（`ILOVE20TokenEvents`）
- 规范：`docs/event-standards.md` v1.1
- 审查日期：2026-11-03

## 0. 结论

| 项 | 值 |
| --- | --- |
| 协议事件 | 2 |
| 发射点 | 3（`TokenMinted` 2、`TokenBurned` 1） |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 0 |
| 放行 | 可放行。事件契约与规范一致，无待修项 |

本合约是「发射者自身即根键」的形态：`TokenMinted` / `TokenBurned` 都不带 `tokenAddress`，符合 §6.1「根键由发射者自身代表时可以省略」。标准 ERC-20 `Transfer` / `Approval` 由 OZ 继承，按 §5.4 不进规范正文，也不与协议事件混用。

## 1. 事件与发射点总览

| 事件 | indexed | 发射点 | 发射次数 |
| --- | --- | --- | --- |
| `TokenMinted(to, amount)` | `to` | `constructor:28`、`mint:46` | 每笔 1 次 |
| `TokenBurned(from, amount)` | `from` | `burn:54` | 每笔 1 次 |

族归属：`core.token`（槽位「角色 → 数值」），见 `core/script/events/event-families.txt`。

## 2. 逐事件赋值链

### 2.1 `TokenMinted`

声明（`ILOVE20Token.sol`）：`event TokenMinted(address indexed to, uint256 amount);`

| 发射点 | 触发条件 | 前置写入 | 字段赋值 | 后置动作 |
| --- | --- | --- | --- | --- |
| `constructor:28` | 部署即执行一次，`initialSupply > 0` 且 `maxSupply >= initialSupply`（`:21-22`） | `_mint(distributor, initialSupply)` `:27`；`MAX_SUPPLY/MINTER/PARENT_TOKEN_ADDRESS` 在 emit **之后**写入 `:32-34` | `to = distributor`（构造参数 `:17`）；`amount = initialSupply`（构造参数 `:15`） | 无 |
| `mint:46` | `onlyMinter`（`:37-40`）且 `amount <= MAX_SUPPLY - totalSupply()`（`:43-44`） | `_mint(to, amount)` `:45` | `to = to`（入参 `:42`）；`amount = amount`（入参 `:42`） | 无 |

赋值说明：

- `amount` 是本次增量，不是累计供应；累计供应由 OZ `Transfer` 事件折叠（`Transfer(0, to, amount)`），属标准事件覆盖，不构成 §3.1 的累计锚点缺口。
- 构造路径与 `mint` 路径共用同一事件类、同一语义（「新增供应并记入某地址」），不构成同名不同义。
- 构造路径在 emit 之后才写 `MINTER` / `PARENT_TOKEN_ADDRESS`：这两个字段属一次性构造参数（§3.2 豁免），且不在 payload 中，因此 emit 时点不影响载荷正确性。

### 2.2 `TokenBurned`

声明：`event TokenBurned(address indexed from, uint256 amount);`

| 发射点 | 触发条件 | 前置写入 | 字段赋值 | 后置动作 |
| --- | --- | --- | --- | --- |
| `burn:54` | 无鉴权，任何人销毁自己的余额；余额不足由 OZ `_burn` 回滚 | `_burn(msg.sender, amount)` `:53` | `from = msg.sender`；`amount = amount`（入参 `:52`） | 无 |

赋值说明：

- `from` 取 `msg.sender`，与 `_burn` 的扣减主体同源，不存在「事件主体与实际扣减主体不一致」的窗口。
- 销毁后 `totalSupply` 由 `Transfer(from, 0, amount)` 覆盖。

## 3. 规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段或自身即根键（§6.1） | 通过 | 两个事件均无 `tokenAddress`，发射者为代币自身 |
| 族槽位（`core.token`：角色 → 数值） | 通过 | `to`/`from` 在前，`amount` 在后 |
| indexed ≤ 3（§6.3） | 通过 | 各 1 个 |
| 动态字段上限（§6.8） | 不适用 | 无动态字段 |
| 状态写入后 emit（§3.4.3） | 通过 | `_mint` / `_burn` 均在 emit 前 |
| 失败不留日志（§3.5） | 通过 | `MaxSupplyExceeded` / OZ 余额错误均 revert |
| 声明与发射写法（§6.11） | 通过 | `check-events.py`：`declaration style OK; emit style OK; emit keys OK` |
| 测试断言（§8.1） | 通过 | `LOVE20Token.t.sol:68` 断言 topic0、indexed 数量、`to`/`from` 取值、`amount` 取值 |

## 4. 发现

无。

补充记录（非缺陷，供索引器实现参考）：

1. 构造期的 `TokenMinted` 是「初始供应创建」事实，与 `mint` 的「增发」事实共用事件类；消费方若需区分创世与增发，用 `Launch.GenesisTokenCreated` / `Launch.TokenLaunched` 的 `tokenAddress` 关联，不要用日志序号推断。
2. 本合约的 `TokenMinted` / `TokenBurned` 会作为子事件出现在 `Mint`、`Stake`、`MemberNFT` 的交易里；跨合约折叠时按发射者地址定域（`emitter == tokenAddress`），不可按交易聚合。
