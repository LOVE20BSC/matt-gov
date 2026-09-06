# 行动参与

## 资产与身份

| 资产 | 归属及记账 |
| --- | --- |
| 自有资产 | 参与成员自己的代币，归其 MemberNFT |
| 体验资产 | Provider MemberNFT 提供，归 Provider；按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账 |

业务使用 `memberId`，钱包仅为当前控制者。可复用的行动轮次状态至少按 `tokenAddress + actionId + round` 隔离；NFT 转移不改写投票、快照、验证或已结算结果。

## 撤回与退出

- 自有与体验资产可同时存在；链群行动支持部分撤回，仅减少指定账本，不互相抵扣。LP 的部分撤回规则见 [LP Executor](04-lp-executor.md#部分撤回)。
- 体验成员退出或 Provider 代其退出时，体验资产归还 Provider。
- Provider 可部分或全部撤回体验资产；撤回后总参与量为零则退出行动，否则保留参与。
- 加入阶段内撤回更新当轮参与权；阶段结束后不得回写该 Round 历史。
- 正常登记与应急清理见 [ActionTarget](01-action-target.md)，资金处理由 Executor 完成。

## 体验参与接口

以下属于链群 Executor，沿用旧 GroupJoin 的待体验名单和 Provider 授权；不强制 LP 实现体验业务。

```solidity
function trialAccountsWaitingAdd(address tokenAddress, uint256 actionId, uint256 groupId,
    uint256 providerMemberId, uint256[] calldata memberIds, uint256[] calldata amounts) external;
function trialAccountsWaitingRemove(address tokenAddress, uint256 actionId, uint256 groupId,
    uint256 providerMemberId, uint256[] calldata memberIds) external;
function trialJoin(address tokenAddress, uint256 actionId, uint256 groupId, uint256 memberId,
    uint256 providerMemberId, string[] calldata verificationInfos) external;
function trialWithdraw(address tokenAddress, uint256 actionId, uint256 memberId,
    uint256 providerMemberId, uint256 amount) external;
function trialExit(address tokenAddress, uint256 actionId, uint256 memberId, uint256 providerMemberId) external;
function trialAccountsWaiting(address tokenAddress, uint256 actionId, uint256 groupId, uint256 providerMemberId)
    external view returns (uint256[] memory memberIds, uint256[] memory amounts, uint256[] memory blockNumbers);
function trialAmount(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId, uint256 providerMemberId)
    external view returns (uint256);
```

待体验名单仅 Provider 当前持有人可改；名单身份须存在且不同于 Provider，两个数组等长，额度为正。trialJoin 由参与成员持有人调用，使用已授权额度并从 Provider 当前持有人转入代币；ERC20 allowance 只授权转账，不替代上述名单授权。

trialWithdraw/trialExit 允许该成员或该 Provider 当前持有人调用，资金始终返还 Provider 当前持有人；部分撤回不得超过对应体验账本。自有/其他 Provider 账本不受影响。全部参与余额归零才清除当前行动登记和归属。历史零值按 RoundHistory 记录；无历史额度返回 0，空名单返回等长空数组。

验收见 [Action 验收](08-testing.md)。
