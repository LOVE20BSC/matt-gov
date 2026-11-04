# GroupActionStorage · 状态变量变更审查

> `action/src/GroupActionStorage.sol`，190 行（修复提交后 188 行，58 字段 → 57 字段），`action@0c1d1e2`。
> 职责：链群行动的**唯一状态根**。58 个字段全部收进一个 `Layout` struct，`GroupActionExecutor` 只声明 `GroupActionStorage.Layout internal _layout`，三个业务库都收同一个 `Layout storage self`。本文件不含任何写入逻辑（只有一个 `view` helper），但**字段顺序就是存储布局**，因此它是全仓唯一「改一行就移动所有槽位」的文件。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

6 个编译期常量 + 58 个字段。字段按「业务模块」分组列出，但**声明顺序**是单一序列（第 1 个字段紧跟 `SPLITS`）。

### 常量（不进存储）

| 常量 | 值 | 语义 | 消费方 |
| --- | --- | --- | --- |
| `PRECISION` | `1e18` | 比例精度 | Manager / Join / Verify |
| `MAX_ORIGIN_SCORE` | `100` | 原始分上限 | Verify |
| `MAX_VERIFICATION_BATCH` | `100` | 单批验证项数 | Verify |
| `MAX_DESCRIPTION_BYTES` | `1024` | 群描述 / 申请说明 | Manager / Verify |
| `MAX_VERIFICATION_ENTRIES` | `16` | 验证模板项数 | Manager / Join |
| `MAX_VERIFICATION_TEXT_BYTES` | `1024` | 单条验证文本 | Manager / Join |

### A. 行动配置（8，写一次）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 1 | `SPLITS` | — | 验证阶段分割线（容量 = `len + 1`） | 构造器 |
| 2 | `joinTokenAddressByActionId` | t+a | 参与代币 | Manager |
| 3 | `activationStakeAmountByActionId` | t+a | 激活押金（退押金的唯一来源） | Manager |
| 4 | `maxJoinAmountRatioByActionId` | t+a | 行动级上限比例 | Manager |
| 5 | `activationMinGovRatioByActionId` | t+a | 激活治理票下限（0 = 关） | Manager |
| 6 | `verifierStakeAmountByActionId` | t+a | 验证者押金 | Manager |
| 7 | `createdRoundByActionId` | t+a | 创建轮（0 = 未创建） | Manager |
| 8 | `verificationKeysByActionId` | t+a | 验证模板 keys | Manager |
| 9 | `verificationDescriptionsByActionId` | t+a | 验证模板说明 | Manager |

（`SPLITS` 与 8 个配置槽，共 9 项；配置槽中 `createdRoundByActionId` 兼作存在性哨兵。）

### B. 群当前态与索引（9）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 10 | `groupState` | t+a+g | `config` / `active` / `activatedRound` / `deactivatedRound` | Manager |
| 11 | `activeGroupIdsByActionId` | t+a | 该行动当前激活的群 | Manager |
| 12 | `descriptionHistoryByGroupId` | t+a+g（按轮） | 描述快照 | Manager |
| 13 | `stakedByActionId` | t+a | 该行动押金合计 | Manager |
| 14 | `totalStaked` | t | 社区押金合计 | Manager |
| 15 | `stakedByMemberId` | t+**g** | 该群全部激活行动的押金合计 | Manager |
| 16 | `tokenAddressesByGroupId` | g | 该群有激活行动的社区 | Manager |
| 17 | `actionIdsByGroupId` | t+g | 该社区该群激活的行动 | Manager |
| 18 | `activeActionIds` | t | 该社区有激活群的行动 | Manager |

### C. 参与按轮账本（10）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 19 | `joinedRoundHistoryByMemberId` | t+a+m | 当前这次加入的轮（退出写 0） | Join |
| 20 | `groupHistoryByMemberId` | t+a+m | 当前所属群（退出写 0） | Join |
| 21 | `ownAmountHistoryByMemberId` | t+a+m | 自有余额 | Join |
| 22 | `providerAmountHistoryByMemberId` | t+a+m | 全部 Provider 已投入合计 | Join |
| 23 | `providerIdsByMemberId` | t+a+m | 有余额的 Provider 集合（按轮） | Join |
| 24 | `providerAmountByMemberIdByProviderId` | t+a+m+p | 单 Provider 已投入 | Join |
| 25 | `memberIdsByGroupId` | t+a+g | 按轮成员集合（**顺序即验证游标**） | Join |
| 26 | `groupIdsByRound` | t+a | 该轮有成员的群集合 | Join |
| 27 | `joinedAmountByGroupId` | t+a+g | 群总参与量 | Join |
| 28 | `joinedAmountByActionId` | t+a | 行动总参与量 | Join |

### D. Provider 额度（2）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 29 | `quotaMemberIdsByGroupIdByProviderId` | t+a+g+p | 有未结清额度的成员 | Join |
| 30 | `quotaAmountByGroupIdByProviderIdByMemberId` | t+a+g+p+m | 授权额度（当前值，无历史） | Join |

### E. 归属计数与集合（7，当前态）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 31 | `membershipCountByGroupIdByMemberId` | g+m | 该 (g,m) 当前归属的 (token, action) 数 | Join |
| 32 | `membershipCountByTokenAddress` | g+m+t | 该 (g,m) 在该 token 下的 action 数 | Join |
| 33 | `joinedTokenAddressesByGroupIdByMemberId` | g+m | 该成员在该群涉及的社区 | Join |
| 34 | `joinedGroupIds` | — | 当前有成员的群 | Join |
| 35 | `joinedGroupIdsByMemberId` | m | 该成员当前归属的群 | Join |
| 36 | `joinedMemberIds` | — | 当前有归属的成员 | Join |
| 37 | `joinedMemberIdsByGroupId` | g | 该群当前成员 | Join |

### F. 验证结果（7，按轮只增）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 38 | `originScoreDeductionByMemberId` | t+a+r+m | 扣分（0 = 满分或未验证） | Verify |
| 39 | `verifiedMemberCountByGroupId` | t+a+r+g | 已验证游标（前缀长度） | Verify |
| 40 | `verifiedGroupCountByRound` | t+a+r | 已完成群数 | Verify |
| 41 | `roundVerified` | t+a+r | 整轮已验证（单向锁存） | Verify |
| 42 | `finalScoreByGroupId` | t+a+r+g | 群最终分累计 | Verify |
| 43 | `totalFinalScore` | t+a+r | 轮最终分累计 | Verify |
| 44 | `lockedVerifierId` | t+a+r | 锁定验证者（0 = 未锁） | Verify |

### G. 验证者申请（7）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 45 | `applicationIdCount` | t+a | 已分配申请 id（单调） | Verify |
| 46 | `applicationVerifierId` | t+a+app | 申请 → 验证者（写一次） | Verify |
| 47 | `applicationDescription` | t+a+app | 申请说明（写一次） | Verify |
| 48 | `applicationIdHistory` | t+a+v | 该验证者在该轮的有效申请 | Verify |
| 49 | `currentApplicationId` | t+a+v | 当前申请（0 = 无） | Verify |
| 50 | `activeApplicationIds` | t+a | 当前有效申请集合 | Verify |
| 51 | `rankedApplicationIds` | t+a+r | 该轮排名（容量 `SPLITS+1`） | Verify |

### H. 投票记账（3）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 52 | `voteAmountByApplicationId` | t+a+r+app | 该申请在该轮的票（只增） | Verify |
| 53 | `voterIdsByApplicationId` | 同上 | 投票人名册（只增） | Verify |
| 54 | `voteAmountByApplicationIdByVoterId` | 再加 v | 单投票人累计票 | Verify |

### I. 验证信息值与结算（4）

| # | 字段 | 键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 55 | `verificationValueHistory` | t+a+m+idx | 成员验证值（按 schema 下标） | Join |
| 56 | `memberMinted` | t+a+r+m | 已结算 | Executor |
| 57 | `memberMintedReward` | 同上 | 已铸数量 | Executor |
| 58 | `memberBurnedReward` | 同上 | 已销毁数量（**恒为 0**） | 无（修复提交已删除该字段，A-12） |

## 2. 逐变量变更逻辑

本文件只有两段可执行代码。

### 2.1 `Layout` 的字段顺序即存储槽位

| 位置 | 语句 | 说明 |
| --- | --- | --- |
| `:41` | `uint256[] SPLITS;` | 占 1 个槽（length）+ 数据区；**第一个字段** |
| `:44-58` | 8 个配置 mapping | 每个 mapping 占 1 个槽（内容为 keccak 派生） |
| `:61-176` | 其余 50 个字段 | 同上，全部是 mapping |

因为每个字段都是 mapping（或含 mapping 的 struct），**字段本身只占一个「槽位序号」**，元素存在 `keccak(key . slot)`。因此：

- 在**末尾追加**字段：安全（已有槽位序号不变）；
- 在**中间插入**字段：其后所有字段的槽位序号 +1，全部元素「搬家」，等价于清空；
- **删除**字段：其后全部前移，同样等于清空。

规格 `05:127-129` 已明说「Layout 变更即重新部署；若已有部署，只能尾部追加」。本仓无生产部署，因此这条约束当前是「零成本」。

### 2.2 `memberAmountAt`（`:180-189`）

```solidity
return self.ownAmountHistoryByMemberId[t][a][m].value(round)
     + self.providerAmountHistoryByMemberId[t][a][m].value(round);
```

唯一 helper。两个 `value(round)` 各自懒继承，相加即「该成员在该轮的总参与量」。消费方：`GroupActionVerify.finalScore`（`06:107`）与 `_scoreMember`（`06:477`）。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| T1 | 每个字段只有一个业务库写 | ✅ | 见 §1 的「写者」列；跨库共享的只有「读」 |
| T2 | 58 个字段全部是 mapping 或含 mapping 的 struct | ✅ | 唯一的非 mapping 是 `SPLITS`（`uint256[]`） |
| T3 | `SPLITS` 部署后不变 | ✅ | 唯一写点是 `GroupActionExecutor` 构造器 |
| T4 | `memberAmountAt` 的两个分量同轮同键 | ✅ | 同一个 `round` 与同一个 `(t,a,m)` |
| T5 | 所有按轮账本的写入轮单调不减 | ✅ | 三个写者都只写 `currentJoinRound()`（Join）或 `currentVerifyRound()`（Verify）或 `currentPhase()`（申请/投票） |

## 4. 发现

### M-STG-01 · `SPLITS` 是唯一影响状态机形状的配置，且合约侧零校验

| 字段 | 值 |
| --- | --- |
| 位置 | `:41`、`GroupActionExecutor:33`、`GroupActionVerify:590`、`:557` |
| 级别 | Info |
| 证据 | E1 |

`SPLITS` 同时决定两件事：

| 用途 | 表达式 | 若取值异常 |
| --- | --- | --- |
| 排名容量 | `capacity = SPLITS.length + 1`（`06:590`） | 空数组 → 容量 1，只有第 1 名可验证 |
| 名次开放时刻 | `ceil(phaseBlocks * SPLITS[rank−1] / 1e18)`（`06:557`） | 非递增 → **名次越靠后越早开放**，第 1 名仍最早，但第 3 名可能早于第 2 名 |

规格 `05:7` 把校验划给部署脚本（`DeployAction` 广播前校验「每项 `0 < split < 1e18` 且严格递增」），合约不重复校验，`21_check.sh` 复核。本卷确认：**如果 `SPLITS` 非递增，合约不会回滚，只会让开放顺序与名次顺序不一致**——这不是资金风险（每个验证者仍只能提交自己那一轮的分数），但它让「第 k 名先开放」这条规则失效，而失效是静默的。

`SPLITS` 是 Layout 的第 1 个字段，因此它也是唯一一个「改动会影响所有后续槽位」的非 mapping 字段。

### M-STG-02 · 58 个字段里只有 4 处 `Load-bearing` 注释，其中 2 处的前提落在别的文件里

| 字段 | 值 |
| --- | --- |
| 位置 | `:118-124`（`originScoreDeductionByMemberId`）、`:126-131`（`verifiedGroupCountByRound`）、`:146-150`（`applicationIdHistory`）、`:170-174`（`voterIdsByApplicationId`） |
| 级别 | Info |
| 证据 | E1 |

四处注释的写法与覆盖面：

| 字段 | 注释内容 | 前提所在 |
| --- | --- | --- |
| `originScoreDeductionByMemberId` | 「已验证性靠位置前缀；该集合只在 `phase−1` 写，晚写会移动前缀」 | 前提在 `GroupActionJoin`（写）+ `GroupActionVerify`（读） |
| `verifiedGroupCountByRound` | 「计数能追平群数，因为已完成的群不能再次提交」 | 前提在 `GroupActionVerify:719` |
| `applicationIdHistory` | 「按轮查找必须走这个历史，不能读 `currentApplicationId`」 | 自洽 |
| `voterIdsByApplicationId` | 「只增不删，因此 `reverse` 即首次投票逆序」 | 自洽 |

后两条是自洽的（读与写都在 Verify）。前两条的**前提在另一个文件里**：`originScoreDeduction` 的「只在 `phase−1` 写」由 `GroupActionJoin._registerMembership` 保证，`verifiedGroupCount` 的「不能再次提交」由 `GroupActionVerify._submitOriginScores` 保证。注释写在 Layout、守卫写在别处，改 Join 的人不会看到这条注释（见 `06-group-action-verify.md` 的 M-GAV-05）。

另外三处**没有注释但同样是承重的**：

| 字段 | 承重前提 | 破坏后的形态 |
| --- | --- | --- |
| `membershipCountByGroupIdByMemberId` | 每次 `_registerMembership` 恰有一次 `_finalizeExit` | `--` 下溢成 `2^256−1`，`isGroupMember` 永真（M-GAJ-01） |
| `joinedAmountByGroupId` | 成员侧与群侧同增同减 | 群容量上限失真（静默） |
| `stakedByMemberId` | `activationStakeAmountByActionId` 只写一次 | 退押金金额错（可能从其他群的质押里退） |

建议：把这三条补成 `// Load-bearing:` 注释，或在规格的 Layout 章节列一张「承重字段清单」。

**处置（规格承载，不加源码注释）**：按 `dev-standards §5.3`「代码默认不写注释」，不在 `src/` 加注释；改为在 [`05-group-action-executor.md`](../../docs/specs/action/05-group-action-executor.md) 的「状态口径」列出这三条承重字段与破坏后的表现。

### M-STG-03 · `PRECISION` 在两个 Storage 库与 `LpExecutor` 各定义一次，三份同为 `1e18` 但无编译期绑定

| 字段 | 值 |
| --- | --- |
| 位置 | `:18`、`GroupServiceStorage:10`、`LpExecutor:22` |
| 级别 | Info |
| 证据 | E1 |

三处独立定义：

| 位置 | 可见性 | 消费方 |
| --- | --- | --- |
| `GroupActionStorage.PRECISION` | library constant | Manager / Join / Verify |
| `GroupServiceStorage.PRECISION` | library constant | Recipients；`GroupServiceExecutor` 暴露为 `public constant` |
| `LpExecutor.PRECISION` | `private constant` | LpExecutor |

三者都是 `1e18`，但没有任何编译期断言把它们绑在一起。`GroupRecipients` 用的是 `GroupServiceStorage.PRECISION`（`:350`），而它计算的 `ratios` 来自群主输入、与 GroupAction 侧的比例无关，因此当前没有混用风险。风险在于「将来有人只改一处」。

同类问题：`MAX_DESCRIPTION_BYTES`（1024，GroupActionStorage）与 `MAX_REMARK_BYTES`（256，GroupServiceStorage）都是「字节上限」，但语义不同（群描述 / 申请说明 vs 二次分配备注），同名不同值容易被误当同一常量。

### M-STG-04 · `memberBurnedReward` 是死槽（与 `M-GAE-01` 同一事实，从布局侧确认）

| 字段 | 值 |
| --- | --- |
| 位置 | `:167-168` |
| 级别 | Info |
| 证据 | E1 |

第 58 个字段 `memberBurnedReward` 的唯一写点是 `GroupActionExecutor:735`，写入的值来自 `burnAmount`，而该变量在 `GroupActionExecutor` 内无任何赋值（恒为 0）。因此这个 4 层嵌套 mapping 永远读到 0。

`GroupServiceStorage` 的同名字段（`ownerBurnedByMemberId`）有真实写入（治理上限触发时），因此**两个 Layout 的同位置字段一个有值一个恒零**，读代码的人容易混淆。

**处置（已裁决：删除槽位）**：A-12 采纳「删除死槽」。修复提交删除了该字段与唯一写入点，Layout 从 58 字段降到 57 字段，`GroupActionStorage.sol` 190 → 188 行。`forge inspect GroupActionExecutor storage-layout` 实测：`memberBurnedReward` 消失，其后的 `voterIdsByApplicationId` 从槽 58 → 57、`voteAmountByApplicationIdByVoterId` 从槽 59 → 58；前 57 个字段的槽位与偏移全部不变。`GroupServiceStorage.ownerBurnedByMemberId` 不受影响（两者本就不是同一存储槽）。

## 5. 已核对为正确的点

- 58 个字段的键维度与访问模式一致：所有 `(t,a,·)` 前缀的字段都能被 `(token, action)` 定位，没有「少一层 token 隔离」的字段（对比旧实现的 `mapping(round => mapping(groupId => ...))` 缺 token 隔离）。
- `memberIdsByGroupId` 的 `RoundHistoryUint256Set` 是「顺序即验证游标」的唯一依赖，且它的 `slotHistory` / `indexPlusOneHistory` 都是按轮历史，因此历史轮的顺序不会被后续 swap-and-pop 破坏。
- `groupIdsByRound` 与 `memberIdsByGroupId` 都是按轮集合，`countByRound` 与 `valuesByRound` 用同一份 `countHistory`，因此「群数」与「群列表」不会不一致。
- `providerAmountByMemberIdByProviderId` 是唯一「不带 group 维度的参与量」，其注释（`:86` 附近的 `providerAmountHistoryByMemberId`）与 `_quotaUsedAt` 的 group 判定配合，构成「已用额度」的推导基础。
- `verificationValueHistory` 的键是 schema 下标（`uint256`）而不是 key 字符串，因此读路径（`verificationValue(memberId, key)`）必须先线性查 keys 再按下标读——这条链在 `GroupActionVerify:344-351` 完整。
- `SPLITS` 放在第一个字段不影响其他 mapping 的槽位稳定性（mapping 的槽位由声明序号决定，`SPLITS` 之前没有字段），因此「追加到末尾」这条规则对当前布局是成立的。

## 6. 覆盖缺口

- 已补做 `forge inspect GroupActionExecutor storage-layout` 实测（A-12 修复前后对比，见 M-STG-04）；修复前 58 个字段全部是 mapping，无同槽打包。
- 未审 `GroupState` 的 `GroupConfig`（含动态 `string`）在 struct 内的实际布局。
- 未审 Layout 的「尾部追加」规则在 `SPLITS` 为动态数组时的边界（在 `SPLITS` 与第一个 mapping 之间插入字段会移动所有 mapping，本卷按「只能在末尾追加」表述）。
- 未审 6 个常量的取值是否与规格一致（`MAX_*` 的数值来自 `05:118`，本卷按源码认定）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-STG-01` | 规格补写 | [`05-group-action-executor.md`](../../docs/specs/action/05-group-action-executor.md) 的「状态口径」：`SPLITS` 的合法性由部署脚本校验、`21_check.sh` 复核，合约侧零校验 |
| `M-STG-02` | 规格承载（不加源码注释） | 同上：三条承重字段清单写入规格；按 `dev-standards §5.3` 不在 `src/` 加注释 |
| `M-STG-03` | 口径登记 | 三份 `PRECISION` 同为 `1e18`、无编译期绑定；不改源码 |
| `M-STG-04` | 已裁决：删除槽位（A-12）+ 已修复 | 字段与唯一写入点删除，Layout 57 字段；实测槽位差异见本条 |
