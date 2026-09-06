# Compatibility 规格

Compatibility 只验证 BSC 外部依赖能否满足 Core/Action 的接口、状态变化和数值要求；提供测试夹具和证据，不部署 LOVE20 生产合约，也不是业务运行时依赖。

## 对象与配置

每个 profile 独立记录链 ID、RPC 标识、固定测试区块、WBNB、Factory、Router、Pair 地址或创建参数：

- `anvil`
- `bsc97_dev`
- `bsc56_public_test`
- `bsc56_public`

两个 `bsc56_*` 均为 chain ID 56，但地址、配置、代币符号和前端环境必须隔离。未通过本规格的地址不得进入 Core、Action 或 Script 部署配置。

本地参考实现记录 WETH9、ERC20、Uniswap V2 Factory/Pair/Router 的源码版本、编译器、优化器和部署区块。目标 profile 另记录地址、runtime bytecode 摘要、验证源码链接（如有）和测试提交。

## 兼容条件

兼容不要求源码相同，而要求 LOVE20 依赖的结果相同。手续费、权限或 fork 差异若影响 Stake 的余额、份额、储备、报价、sqrt(k) 或回滚语义，则阻断接入。

| 组件 | 必测行为 |
| --- | --- |
| WBNB/WETH9 | `deposit`、`withdraw`、余额、原生转账、ERC20 转账/授权；余额不足和非法金额回滚 |
| Factory | `getPair`、`createPair`、代币顺序、Pair 唯一性和重复创建 |
| Pair | `token0`、`token1`、`getReserves`、`totalSupply`、`mint`、`burn`、`swap` |
| Router | `getAmountsOut`、`swapExactTokensForTokens`、路径和 `amountOutMin` |
| 数值 | LP 份额、储备、供应、手续费、实际输出、k/sqrt(k) 与整数舍入 |
| 失败 | 数量、路径、滑点、权限及外部调用失败后状态不变 |

不能仅凭 ABI 编译或 selector 相同判定兼容。

## Stake 回放

每个 profile 执行同一最小流程：

1. 社区代币与父币加入 Pair，取得 LP 并读取份额。
2. 交易后读取储备、LP 供应和 sqrt(k)。
3. 结算 feeLp，核对社区代币销毁，以及父币通过 Router 换成社区代币后的销毁。
4. 核对 withdrawableLp、totalLpShares、成员 lpShares 和按份额提取。
5. 对 Pair、Router、销毁和滑点失败执行整体回滚测试。

测试金额、储备、手续费和 sqrt(k) 保存整数值，并记录每一步舍入。参考与目标差异只有在不影响上述结果时可接受。

## 证据与判定

每次测试记录：

- profile、链 ID、区块、地址、runtime bytecode 摘要；
- 参考实现版本、执行提交、测试标识或交易哈希；
- 调用输入/返回/事件，前后余额、储备和供应；
- 手续费、报价、实际输出、sqrt(k)、舍入差异和失败原因。

| 结果 | 条件 | 是否可部署 |
| --- | --- | --- |
| 通过 | 全部依赖行为满足约束 | 是 |
| 有记录的差异 | 差异不影响协议结果且证据完整 | 是 |
| 阻断 | 接口、状态、数值、回滚或证据不满足 | 否 |

一个 profile 的结果不能替代另一个。Compatibility 可保留最小参考接口和夹具，但不得被业务仓库导入或反向修改业务规格；结果和部署配置同步记录。

## 实现约束

- 每个网络 profile 独立记录权威地址、固定区块和验证来源；不同 profile 的结果不能互相替代。
- 优先使用固定区块 fork 和只读调用；需要写交易时仅使用专用测试账户，不操作真实用户资金。
- 只有不影响 Stake 余额、份额、储备、报价、`sqrt(k)` 或回滚语义的差异可以记录为兼容差异；其他差异阻断接入。
- 未完成验证的 profile 不得进入 Core、Action 或 Script 部署配置。
