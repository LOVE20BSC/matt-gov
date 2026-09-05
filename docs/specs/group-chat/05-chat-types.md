# Chat 类型和资格规则

本文档定义五类 Chat 类型及其发言资格和黑名单规则。

---

## 1. 五类 Chat 类型

**参考实现**：`LOVE20TKM/group-chat/Managers`、`ScopeSource`

`GroupChat` 不把群聊类型写死在核心状态，类型由 Manager、scope source、ban source 和插件组合实现。

| 类型 | 发言资格 | 黑名单 |
| --- | --- | --- |
| 代币社区 Chat | 持有社区代币余额大于 `0`、拥有有效治理票或当前已登记参与该社区至少一个行动 | 治理票加权黑名单 |
| 代币治理 Chat | 拥有该代币有效治理票 | 治理票加权黑名单 |
| 代币行动 Chat | 最近 `RECENT_ROUNDS` 轮给行动投过票，或当前已在 ActionTarget 登记参与该行动 | 行动投票权重黑名单 |
| 代币行动治理 Chat | 最近 `RECENT_ROUNDS` 轮给行动投过票 | 行动投票权重黑名单 |
| 群组 Chat | 被群管理员列入成员，或当前参与至少一个归属该群组的 Group Action | 管理员黑名单 |

**代币行动 Chat vs 代币行动治理 Chat 资格差异**：
- **代币行动 Chat**：包含"当前已在 ActionTarget 登记参与该行动"，允许新加入的行动参与者（尚未投票但已登记）立即发言
- **代币行动治理 Chat**：仅限"最近 RECENT_ROUNDS 轮给行动投过票"，强调投票参与历史，排除未投票的新参与者
- **设计理由**：行动 Chat 面向行动执行和协作，需要包容新参与者；行动治理 Chat 面向投票治理讨论，仅限有投票历史的成员

**黑名单类型说明**：
- **治理票加权黑名单**（代币社区/治理 Chat）：使用该代币社区当前有效治理票作为投票权重
- **行动投票权重黑名单**（代币行动/行动治理 Chat）：使用该行动 Proposal 创建的治理 Round 中的历史投票数作为权重（详见第 3 节）
- **管理员黑名单**（群组 Chat）：由群组管理员直接维护

---

## 2. 资格实现细节

**持币资格**：
```text
token.balanceOf(MemberNFT.ownerOf(senderId)) > 0
```
持有任意非零余额即可。

**治理票、投票和参与**：
- 治理票、Proposal 投票和行动参与直接按 `memberId` 查询
- `RECENT_ROUNDS` 在各 ScopeSource 部署时通过构造参数设置，所有 ScopeSource 应使用统一值
- 推荐值：3（检查最近 3 个治理 Round）

**RECENT_ROUNDS 的时间基准**：
当前 Core 治理 Round（即 `Phase.currentPhase()` 返回值，Phase 与治理 Round 一对一映射）向前数 `RECENT_ROUNDS` 轮。

示例（假设 RECENT_ROUNDS = 3）：
- 当前 Phase = 10（即治理 Round 10）
- 检查 memberId 在治理 Round 10, 9, 8 是否投过票
- 任一 Round 有投票记录即符合资格

注意：
- 使用 Core 治理 Round 作为基准，而非行动的执行 Round
- 这确保了跨行动的资格判断一致性

**ActionTarget 参与登记与群组 Chat 资格差异**：

forceExit 对 Chat 资格的影响：
- **代币社区/行动 Chat**：立即失去资格（依赖 ActionTarget 登记，forceExit 清除登记）
- **群组 Chat**：不失去资格（依赖群组 Executor 归属，forceExit 不修改归属；归属只在群组 Executor 的正常退出流程中更新）

---

## 3. 治理投票黑名单

**参考实现**：`LOVE20TKM/group-chat/GovBanSource`

治理投票黑名单按 `groupId + targetSenderId + voterId` 记录支持/反对票，并从 `voterId` 对应的治理状态读取权重。

**权重查询**（按 Chat 类型区分）：

**代币社区 Chat、代币治理 Chat**：
- `voteWeightOf(groupId, voterId)` = 该代币社区中 `voterId` 当前有效治理票
- `totalVoteWeight(groupId)` = 该代币社区当前总有效治理票

**代币行动 Chat、代币行动治理 Chat**：
- `voteWeightOf(groupId, voterId)` = 该行动 Proposal 创建的治理 Round 中 `voterId` 的累计投票数
- `totalVoteWeight(groupId)` = 该行动 Proposal 创建的治理 Round 中的总投票数

注意：行动 Chat 的权重基准是行动 Proposal 的投票数，而非代币社区的治理票总数。行动 Proposal 只在创建的治理 Round 接受投票，后续 Round 的黑名单投票使用该历史投票数据作为权重基准。

**进入黑名单条件**（固定常量）：
```text
supportWeight > opposeWeight × 10
supportWeight × 1e18 >= totalVoteWeight × 3e15
```

**黑名单投票时间窗口**：
- 代币社区/治理 Chat：任何时候都可以投票（使用当前治理票作为权重）
- 代币行动/行动治理 Chat：任何时候都可以投票，但权重固定使用行动 Proposal 创建 Round 的历史投票数据

每次投票、反对、撤票或刷新后同步该目标的黑名单状态。

---

## 4. 群成员和管理员

**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

群聊可以维护 `groupId -> memberId` 成员集合，并提供批量新增、移除、存在性判断和分页查询。只有群 owner、有效 Group Chat Delegate 或有效群管理员可以修改成员集合。

管理员集合同样使用 MemberNFT。管理员执行操作时显式提供 `adminId`，不通过钱包地址的默认 NFT 映射推导。
