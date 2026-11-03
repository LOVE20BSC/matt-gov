# LOVE20Token 接口调用权限审查

> 对象 `core/src/LOVE20Token.sol`（59 行）
> 接口 `core/src/interfaces/ILOVE20Token.sol`（50 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5（调用者校验）、§4.2（事件）；`specs/core/01-common-rules.md`（主体与权限）

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 14（自有 5 / 继承 OZ ERC20 9） |
| 写入口 | 5（自有 2 + OZ 标准 3） |
| 带鉴权 modifier | 1（`onlyMinter`） |
| 无许可写入口 | 4（`burn` + OZ `transfer`/`approve`/`transferFrom`） |
| 发现 | 3 条，全部 Info；无权限缺陷 |
| 接口对账 | 14 vs 14，**0 差异**（无 impl-only、无 iface-only、无 mutability 差异） |

一句话：**这是全仓唯一没有「成员身份」概念的合约，权限面只有一条铸造闸门 `MINTER`，其余全是「处分自己」的标准 ERC20 语义。没有管理员、没有暂停、没有升级、没有 setter，四个不可变量之外没有任何可调用的配置面。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| `MINTER`（构造时固定为 Mint 合约） | `msg.sender == MINTER` | `mint` |
| 代币持有人本人 | 余额/授权在 OZ `_update`、`_spendAllowance` 内判定 | `burn`、`transfer`、`approve`、`transferFrom` |
| 无 | — | 9 个只读 getter |

`MINTER` 由 `Launch._createToken` 传入 `MINT_ADDRESS`（`Launch.sol:251`），`PARENT_TOKEN_ADDRESS` 同样由构造参数固定。两者都是普通 storage 变量但**没有任何 setter**，全仓检索无写入点，因此运行期不可变。

## 三、入口清单

### 写入口

| 函数 | 可见性 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- | --- |
| `mint(address,uint256)` | external | `MINTER` | `modifier onlyMinter` `L37` | 是（modifier 唯一修饰符） | `TokenMinted` |
| `burn(uint256)` | external | 持有人本人 | 无（`_burn(msg.sender, …)`） | — | `TokenBurned` |
| `transfer(address,uint256)` | public（OZ） | 持有人本人 | OZ `_update` | — | `Transfer` |
| `approve(address,uint256)` | public（OZ） | 持有人本人 | OZ 自身余额/授权语义 | — | `Approval` |
| `transferFrom(address,address,uint256)` | public（OZ） | 持有人或已授权方 | OZ `_spendAllowance` | — | `Transfer` |

### 只读入口

`MAX_SUPPLY`、`MINTER`、`PARENT_TOKEN_ADDRESS`（自有 immutable/storage getter）；`name`、`symbol`、`decimals`、`totalSupply`、`balanceOf`、`allowance`（OZ）。全部无权限，无事件要求。

## 四、逐入口判定

### `mint` — 单点铸造闸门

- 唯一铸造出口；`MINTER` 在构造时固定，且构造器要求 `minter.code.length != 0`（`L24`），不能是 EOA。
- 校验顺序：`onlyMinter` → `amount > MAX_SUPPLY - totalSupply()`（`L43-44`）。非授权方只拿到 `NotMinter(msg.sender)`，拿不到供应量状态，符合 §5.5「鉴权先于参数」。
- 无 setter、无 `burnFrom` 式的外部销毁通道 ⇒ 除 Mint 合约的奖励铸造外，供应量只减不增。
- `MAX_SUPPLY` 是 immutable，`mint` 的上限读取不经过任何可写状态。

### `burn` — 无许可，但只能烧自己

- `_burn(msg.sender, amount)`，无 allowance 语义：**任何人无法烧他人余额**（OZ `_burn` 不做授权检查，只减 `msg.sender`）。
- 无许可不会损害他人：销毁只减少 `totalSupply`，从而扩大 `Mint.rewardAvailable = MAX_SUPPLY - totalSupply - reservedAvailable`。这是「放弃自己的代币，为全员扩大可分配空间」，不存在把他人权益转移的路径。
- 该通道被两处依赖：`MemberNFT._mintMember`（身份费，`MemberNFT.sol:86`）与 `Stake._realizeFees`（手续费销毁，`Stake.sol:864`）。两者都先持有代币再调用 `burn`，因此销毁量来自合约自身余额，不触碰用户余额。

### OZ 标准入口

`transfer`/`approve`/`transferFrom` 的权限完全由 OZ 5.6.1 的 `_update` 与 `_spendAllowance` 决定，本合约未覆写。业务层没有任何地方依赖这三个入口做鉴权（`Stake`、`Mint` 只用 `mint`/`burn`），因此 OZ 的授权语义不会外溢成协议权限。

## 五、发现

### TOK-01（Info）不可变语义靠「没有 setter」隐式表达，`MINTER`/`PARENT_TOKEN_ADDRESS` 未用 `immutable`

- 证据：`MAX_SUPPLY` 声明为 `immutable`（`L8`），`MINTER`（`L9`）与 `PARENT_TOKEN_ADDRESS`（`L10`）是普通 storage，但只在构造器赋值。
- 影响：无运行期风险（无写入点）；差异只在部署字节码与 gas——storage 版每次读取是 SLOAD（2100 gas 冷读），immutable 是 PUSH 常量。
- 建议：两者改为 `immutable`。ABI getter 不变，`Launch` 侧无需改动。若保留 storage，建议在声明处写一行注释说明「构造后无写入，等价 immutable」，否则下次改动容易误加 setter 而无声破坏不可变性。

### TOK-02（Info）`burn` 的无许可边界应写进规格

- 证据：`burn` 无 modifier、无 `initialized` 判定，`_burn(msg.sender, …)`（`L52-53`）。
- 现状：`01-common-rules.md` 只声明「`init` 一律不设调用者限制」，没有为「无许可的资产销毁入口」立通则；本合约的 `burn`、`MemberNFT.mint`、`Phase.sync`、`Stake.settleFees` 四处无许可写入口各自散落在模块规格里。
- 建议：在 `01-common-rules.md` 增一节「无许可入口」，列全这四处的判据（只能处分自己 / 只能推进已到期流程 / 只能按真实数据采样），让「为什么不需要鉴权」成为可核对的一条规则，而不是四处独立论证。

### TOK-03（Info）`mint` 的错误载荷只带调用者，不带剩余额度

- 证据：`NotMinter(address caller)`（`ILOVE20Token.sol`）；超额时抛 `MaxSupplyExceeded(requested, remaining)`。
- 判定：**不构成问题**。`NotMinter` 不带剩余额度，非授权方无法借错误差异探测供应量；`MaxSupplyExceeded` 只对已授权的 MINTER 可见。这是「鉴权错误最小化」的正确写法，记录为正面样本。

## 六、核对证据

```text
$ forge inspect LOVE20Token abi --json | jq '[.[]|select(.type=="function")]|length'
14
$ forge inspect ILOVE20Token abi --json | jq '[.[]|select(.type=="function")]|length'
14
# 逐签名 diff：impl-only 0 / iface-only 0 / mutability 差异 0

$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

鉴权负例测试：`core/test/LOVE20Token.t.sol:120-123` 断言 `NotMinter(address(this))`；`core/test/MemberNFT.t.sol` 覆盖 `burn` 通道的身份费扣减。

## 七、跨合约位置

- 上游：`Launch._createToken` 部署本合约，`MINTER = MINT_ADDRESS`、父币地址由 Launch 传入（`Launch.sol:250-252`）。
- 下游：`Mint.mintProposalReward` / `_mintGovReward` 调 `mint`（唯一合法铸造方）；`MemberNFT`、`Stake` 调 `burn`。
- 本合约不读取任何外部合约，无跨合约鉴权依赖。
