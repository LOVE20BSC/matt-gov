# 行动参与

## 资产来源与身份

参与资产按来源记账，主体统一使用 `memberId`；钱包仅为当前控制者：

| 来源 | 归属及记账 |
| --- | --- |
| 自有资产 | 参与成员自己的代币，归其 MemberNFT；来源键 `providerId = 0` |
| Provider 额度资产 | Provider MemberNFT 提供，归 Provider；按 `tokenAddress + actionId + memberId + providerId` 独立记账 |

`join` 的资产来源由 `providerId` 决定：`0` 表示成员自有代币，非零表示从该 Provider 已存入合约的额度中扣减。同一成员可在同一行动上混合多个来源，重复 `join` 按来源分别追加；成员总参与量、行动总参与量和链群总参与量都包含全部来源。

Provider 提供的是额度：Provider 授予、追加或收回额度，成员在额度内自行决定使用多少（部分或全部）。额度授予即存入合约，只有被 `join` 使用的部分才进入行动，未使用的额度始终留在合约内可退还给 Provider。

合约内的 Provider 资金只有**可用额度**与**已投入**两种状态，成员侧动作只在两者之间移动，不转出合约：`exit` 把该 Provider 的已投入恢复为可用额度，`providerWithdraw` 把已投入退回 Provider 当前持有人。只有 Provider 自己的 `providerQuotaRemove` 把可用额度转出合约。

可复用的行动轮次状态至少按 `tokenAddress + actionId + round` 隔离；NFT 转移不改写投票、快照、验证或已结算结果。

## 撤回与退出

- 自有资产与各 Provider 额度资产可同时存在，撤回只能撤回自己那份：`withdraw` 只减少自有账本，由成员当前持有人调用；`providerWithdraw` 只减少指定 Provider 账本，由该 Provider 当前持有人调用。两者不互相抵扣，也不影响其他来源；成员总参与量（自有 + 全部 Provider）归零时才自动退出行动。LP 的部分撤回规则见 [LP Executor](04-lp-executor.md#部分撤回)。
- `providerWithdraw` 代币始终返还该 Provider 当前持有人；撤回后成员总参与量为零时，合约自动完成成员退出、清除群归属并调用 `ActionTarget.clearJoinState`，否则成员保持加入。
- 成员 `exit` 结清全部来源：自有资产返还成员当前持有人；Provider 来源**不转出合约**，按资金归属恢复为该 Provider 对该成员的可用额度（已投入 → 可用额度），成员日后可用同一额度再次加入，Provider 仍可随时用 `providerQuotaRemove` 取回。代币量只由 `Joined` 与 `Withdrawn` 承载：`exit` 按来源逐条发出 `Withdrawn`（自有来源 `providerId = 0`，每个有余额的 Provider 各一条且带其 `providerId`），`Exited` 只表示成员退出这一状态变化（带链群 `groupId`），不带金额；单笔 `withdraw` / `providerWithdraw` 只影响一个来源，各发一条 `Withdrawn`。
- 加入阶段内撤回更新当轮参与权；阶段结束后不得回写该 Round 历史。
- 正常加入/退出与应急清理见 [ActionTarget](01-action-target.md)，资金处理由 Executor 完成。

## Provider 额度接口

以下属于 GroupAction Executor，沿用旧 `LOVE20TKM/extension-group/src/GroupJoin.sol` 的名单与 Provider 授权逻辑，语义改为 Provider 额度；不强制 LP 实现 Provider 额度业务。

Provider 额度接口见 [`IGroupActionJoin.sol`](../../../interfaces/action/IGroupActionJoin.sol)。

额度按 `tokenAddress + actionId + groupId + providerId + memberId` 记录，只有 Provider 当前持有人可改；成员身份须存在且不同于 Provider，两个数组等长，额度为正；同一成员重复授予是追加额度，不再回滚。批量接口没有协议固定长度上限，调用方按区块 Gas 分批操作，单笔失败整笔回滚。

额度授予即存入合约：`providerQuotaAdd` 在登记额度的同时把对应代币从 Provider 当前持有人转入合约托管；`providerQuotaRemove` 只退还尚未被 `join` 使用的额度；两笔划转按成员逐条发出 `ProviderQuotaAdded` / `ProviderQuotaRemoved`（单成员单条日志，金额与账本变动一致）。成员 `join` 使用额度时只扣减可用额度、不再转移代币；`providerWithdraw` 把已投入的部分从合约转回该 Provider 当前持有人。托管资金不按来源隔离存放，额度和已投入部分都由 Executor 按来源账本核算。

`providerWithdraw` 金额须满足 `0 < amount <= 该 Provider 已投入量`，不影响自有或其他 Provider 账本。Provider 身份不授予成员 `exit` 权限，也不授予成员撤回 Provider 额度或 Provider 已投入部分的权限。历史零值按 RoundHistory 记录；无历史额度返回 0，空名单返回等长空数组。`providerQuota` 按标准分页返回某 Provider 在某个链群的额度表（成员、额度、登记区块与真实总数），`providerAmountsByMemberId` 按标准分页返回某成员在 `round` 轮有余额的来源及其金额（RoundHistory 懒继承：无记录继承最近历史）；成员聚合量（总量与 `ownAmount`/`providerAmount`）由 `joinInfo` 返回。

验收见 [Action 验收](08-testing.md)。
