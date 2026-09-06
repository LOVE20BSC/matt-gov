# 行动参与

## 资产与身份

| 资产 | 归属及记账 |
| --- | --- |
| 自有资产 | 参与成员自己的代币，归其 MemberNFT |
| 体验资产 | Provider MemberNFT 提供，归 Provider；按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账 |

业务使用 `memberId`，钱包仅为当前控制者。可复用的行动轮次状态至少按 `tokenAddress + actionId + round` 隔离；NFT 转移不改写投票、快照、验证或已结算结果。

## 撤回与退出

- 自有与体验资产可同时存在，部分撤回仅减少指定账本，不互相抵扣。
- 体验成员退出或 Provider 代其退出时，体验资产归还 Provider。
- Provider 可部分或全部撤回体验资产；撤回后总参与量为零则退出行动，否则保留参与。
- 加入阶段内撤回更新当轮参与权；阶段结束后不得回写该 Round 历史。
- 正常登记与应急清理见 [ActionTarget](01-action-target.md)，资金处理由 Executor 完成。

验收见 [Action 验收](08-testing.md)。
