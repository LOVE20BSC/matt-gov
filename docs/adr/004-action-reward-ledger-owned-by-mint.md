# ADR-004: 行动级铸造账本归 Mint 所有

## 状态

已接受 (2026-10-16，2026-10-17 修订)

## 背景

ActionTarget 曾同时持有行动级铸造账本：`_actionReward`（本轮实际铸造金额）与 `_actionMinted`（本轮是否已铸造），并在 `mintActionReward` 内先做本地去重、铸造后回写两者。Mint 侧另有 `_proposalMinted` 与 `_proposalRewardCalculation`，记录的是同一事实。

由此产生三处重复：

1. **两套去重键**：ActionTarget 用 `tokenAddress + actionId + round`，Mint 用 `tokenAddress + round + proposalId`，两者数值相同但键形不同，任一侧改动都要人工对齐。
2. **两套真相**：`actionReward` 在未铸造分支还要回读 Mint 的 `proposalRewardByProposalId` 兜底，等于承认本地账本不完整。
3. **多余写入**：每轮首次铸造多一次布尔 SSTORE（冷写）与一次金额 SSTORE，而这两条状态在 Mint 中已存在且不可分叉。

关键事实：Mint 的 `mintProposalReward` 以 `msg.sender == proposalTarget` 限定调用者，而行动提案的 Target 固定为 ActionTarget，因此 ActionTarget 是该路径上唯一的铸造者——本地状态位在结构上不可能与 Mint 分叉，属纯冗余。

## 决策

**行动级铸造状态与金额的唯一所有者是 Mint。** ActionTarget 不再保存行动级铸造账本：

- 删除 `_actionReward`、`_actionMinted` 两个 mapping。
- `mintActionReward` 只保留「Proposal 已投票」入口校验，不再本地去重、不再回写账本；重复调用由 Mint 回滚。
- `actionReward` 直接委托 `IMint.proposalRewardByProposalId`，ActionTarget 只保留一处收敛：未关联行动 → `(0, false)`。
- 接口删除 `AlreadyMinted(tokenAddress, actionId, round)`：该错误不再可达。

**同一决策的第二半：结算事实只有一份，资金也不该中转。** 既然账本归 Mint，Mint 的入口就不应把「谁收款」编码成调用者身份：

- `mintProposalReward` 增加 `recipient` 入参，由被授权的 Target 指定收款人；支付路径校验 `recipient != address(0)` 并回滚 `InvalidAddress`。Mint 原本的 `mint(target, amount)` 等价于 `mint(msg.sender, amount)`（`msg.sender != target` 已先回滚），因此这是把隐含语义显式化，不引入新的信任假设——Target 本就全额托管这笔钱。
- ActionTarget 把绑定的 Executor 作为 `recipient` 传入，**删除「先铸给 ActionTarget、再 `transfer` 一次」的转发**，随之删除 `TransferFailed` 错误与 `ILOVE20Token` 依赖。
- `RewardBurned` 的 `bytes32 reason` 改为 `BurnReason` enum（`BoostPoolCancelled` / `ProposalPoolCancelled` / `BoostOverflow`），消除魔法字符串哈希；枚举按 `uint8` 编码，事件 topic0 因此变化。

**第三半：销毁机制整个删除。** 判断本来就该由 Executor 做，但进一步复核后，连「执行销毁」这一层也不需要：

- Mint 删除 `burnUnmintedProposalReward`，`mintProposalReward` 只支付、不作废；`BurnReason` 只保留 Mint 自己会计意义上的取消（准备期整池取消与治理溢出），不含任何行动激励作废。
- ActionTarget 删除 `burnRewardIfNeeded`、`burnInfo`、`_burnedReward`/`_rewardBurned` 与行动级 `RewardBurned`，接口删除仅该入口使用的 `InvalidRound(round)`（Executor 侧同名错误保留）；`actionReward` 不再掩零。
- 各 Executor 不提供任何销毁入口：`IActionExecutor` 删除 `needBurnReward`，`LpExecutor`/`GroupActionExecutor`/`GroupServiceExecutor` 三处同名实现一并删除。

**理由**：三个「不可分配」判据里有两支与「本行动有没有人参与」无关——`GroupActionExecutor` 是**验证者没出勤**（验证者按票数排名、按名次顺序开放，不是 permissionless），`GroupServiceExecutor` 取决于**别的**行动有没有产出；`LpExecutor` 则是「本轮有效参与量为零」（没人加入，或全部被扣减/退出）。三者共同的含义是「本轮没有任何有效分配路径」，属于罕见情形。

**代价的准确表述**：不销毁**不会**把币锁在 Executor 里——那些币从未铸出。真实影响是那笔预留永久留在 `reservedAvailable`，使 `rewardAvailable` 永久低 A，之后每一轮的 `govRewardAmount`/`proposalRewardAmount` 都按这个更小的值算，即**发行量永久低于上限**（总量层面的少发，不是局部锁定；预留按固定比例算、`available` 几何衰减，不会下溢）。

**为什么不保留**：销毁入口是一条 permissionless 的状态变更路径，而它的失败模式**不对称**——`needBurnReward` 一旦假阳性就**销毁本该发给成员的激励**，不可逆；「少发」只是发行量偏低。少发严格比误销毁安全。另外每个新 Executor 都要重实现一遍判据，是「可选能力」的坑。

**没有「无判据回收」的中间路**：只有 Executor 知道那一轮是否**还有可能**被分配（一个懒惰但合法的结算可以在铸造窗口之后才发生），所以 Mint/ActionTarget 无法自动回收。二选一：Executor 判据回收，或不回收——本轮选了后者。

## 后果

### 正面影响

1. **单一真相**：行动级结算状态只在 Mint 存在，去重键只剩一套；Mint、ActionTarget、Executor 三层都不再有**行动级**销毁概念，各自只做一件事（支付、路由、分配）。成员级与 owner 超额销毁不受影响，仍在各 Executor 内。
2. **省存储与 gas**：每次首轮结算少两次 SSTORE（含一次冷写布尔位）；每次行动轮结算少一次 ERC20 转账（实测 `testFuzzMintRoundIndependence` 两轮结算 μ 从 868,325 降到 806,258，约省 31k/轮）。
3. **职责更清晰**：ActionTarget 只负责「映射、回调、加入态、行动索引」与一处语义收敛，不复制 Core 的账本、不做资金中转，也没有任何销毁概念。
4. **错误与事件可读**：`reason` 由哈希字面量变为具名枚举，索引方不必猜原文。

### 负面影响

1. **错误信息降级**：重复结算从 `AlreadyMinted(tokenAddress, actionId, round)` 变为 Mint 的 `AlreadyMinted()`，丢失参数；调用方与索引需回落到 `ActionRewardMinted` 事件或 `actionReward` 查询定位具体行动与轮次。
2. **不可分配的激励永久占住预留**：`rewardAvailable` 永久少 A，之后每一轮的 `govRewardAmount`/`proposalRewardAmount` 都按这个更小的值算，发行量永久低于上限。这是总量层面的少发，不是局部锁定——那些币从未铸出。`available` 按固定比例衰减，不会下溢。
3. **不可分配的轮次没有专门的观测入口**：既不铸也不销毁，其状态就是「永久未结算」——`actionReward` 一直返回 `(理论数量, false)`，`ActionRewardMinted` 只覆盖真正发放的激励，索引方据此区分「已发放」与「无分配路径」。
4. **存储布局变化**：删除两个 mapping 会使其后声明的槽位前移 2。本仓库仅有本地链 31337 的广播记录、无生产部署，故可安全变更；若已部署，须先迁移或改为在结构体末尾追加。
5. **ABI 破坏性变更**：`mintProposalReward` 与 `mintGovReward`/`mintGovRewards` 签名变化（三者均增加 `recipient`）、`burnUnmintedProposalReward` 与 ActionTarget 的 `burnRewardIfNeeded`/`burnInfo` 移除、`IActionExecutor` 删除 `needBurnReward` 且不新增任何销毁接口、`RewardBurned` 的 topic0 与 `ProposalRewardMinted` 的参数名变化。无生产部署，故只影响同批更新的调用方与索引。

## 相关文档

- [ActionTarget 规格](../specs/action/01-action-target.md)
- [行动铸造、事件与错误](../specs/action/07-minting.md)
- [Core Mint 规格](../specs/core/07-mint.md)
- [ADR-003: ActionTarget 接口简化设计](003-action-target-interface-simplification.md)
