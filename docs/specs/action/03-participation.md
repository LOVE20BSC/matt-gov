# 行动参与

## 资产与身份

| 资产 | 归属及记账 |
| --- | --- |
| 自有资产 | 参与成员自己的代币，归其 MemberNFT |
| 体验资产 | Provider MemberNFT 提供，归 Provider；按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账 |

业务使用 `memberId`，钱包仅为当前控制者。可复用的行动轮次状态至少按 `tokenAddress + actionId + round` 隔离；NFT 转移不改写投票、快照、验证或已结算结果。

## 撤回与退出

- 自有与体验资产可同时存在；GroupAction 支持自有资产部分撤回，仅减少自有账本，不与体验资产互相抵扣。自有资产归零且体验资产也为零时，自动退出行动。LP 的部分撤回规则见 [LP Executor](04-lp-executor.md#部分撤回)。
- 成员正常退出时，体验资产归还各 Provider。
- Provider 只能撤回自己提供的体验代币，不能代成员调用退出；撤回后该成员的总参与量为零时，合约自动完成该成员的退出，否则成员保持加入。
- 加入阶段内撤回更新当轮参与权；阶段结束后不得回写该 Round 历史。
- 正常加入/退出与应急清理见 [ActionTarget](01-action-target.md)，资金处理由 Executor 完成。

## 体验参与接口

以下属于 GroupAction Executor，沿用旧 `LOVE20TKM/extension-group/src/GroupJoin.sol` 的待体验名单和 Provider 授权；不强制 LP 实现体验业务。

体验参与接口见 [`IGroupActionExecutor.sol`](../../../interfaces/action/IGroupActionExecutor.sol)。

待体验名单仅 Provider 当前持有人可改；名单身份须存在且不同于 Provider，两个数组等长，额度为正。批量接口没有协议固定长度上限，调用方按区块 Gas 分批操作，单笔失败整笔回滚。trialJoin 由参与成员持有人调用，使用已授权额度并从 Provider 当前持有人转入代币；ERC20 allowance 只授权转账，不替代上述名单授权。

trialWithdraw 允许成员或对应 Provider 的当前持有人调用；金额须满足 `0 < amount <= 对应体验余额`，代币始终返还该 Provider 当前持有人，不影响自有或其他 Provider 账本。Provider 身份不授予成员 `exit` 权限。撤回后总参与量归零时，Executor 自动完成成员退出、清除群归属并调用 ActionTarget.exit；否则保留加入状态。成员正常 `exit` 时，自有资产返还成员当前持有人，全部体验资产返还各 Provider 当前持有人。历史零值按 RoundHistory 记录；无历史额度返回 0，空名单返回等长空数组。

验收见 [Action 验收](08-testing.md)。
