# action/ 状态变量变更审查 · 2026-11

> 基线 `action@0c1d1e2`（`fix(deploy): pin ActionTarget init as the first post-deploy transaction`，工作树干净）。`src/` 自 `e849e36` 无实质变化，行号相对上一稿未位移；本卷所有 `:NNN` 引用在该提交上可原样定位。错误名按落地 `action@4866cb8` 对齐（量纲拆分后的 `ZeroEffectiveJoinAmount` / `ZeroFinalScore` / `ZeroRewardWeight` 及轮级两错），行号仍按基线；未涉及改名的行仍按基线 `0c1d1e2` 表述。
> 范围：`action/src/` **全部 14 个源文件、5,662 行**（另有 `src/interfaces/` 11 个文件、1,564 行，无状态，不单独立卷）。
> 判据：只判**代码自身的状态一致性** —— 某变量的一次写入是否有守卫、是否与联动变量同笔、是否排在外部调用之前、谁能触发、失败时是否整笔回滚、历史轮会不会被回写。规格文档仅用于核对口径，**不作判据**。
> 与既有审查的关系：`action-api-auth-2026-11` 审「谁能调」，`action-events-audit-2026-11` 审「发了什么」，本卷审「写了什么」。三卷的编号互不重叠，重合项只在 §6 做复核标注，不重复论证。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。本卷**未新增 PoC**，全部为静态审查；E2 只用于「不下溢 / 不越界 / 等值」这类可手工验算的结论。

## 1. 方法与边界

1. **先枚举，再审逻辑**：用赋值 / `delete` / `++` / `--` / `.push` / `.pop` / 库写入（`.add` / `.remove` / `.record` / `.increase` / `.decrease`）七类模式对 14 个文件做全量扫描，逐处归属到状态变量。扫描结果与人工逐行阅读逐条对齐。
2. **每个变量四问**：谁能写（鉴权）→ 写之前校验了什么（守卫）→ 同一笔里还写了谁（联动）→ 写在前还是外部调用在前（顺序）。
3. **不把「有事件」当正确性证据**：事件只用于对账，不作为写入合法的依据。
4. **不可达路径单独标注**：静态存在但无入口可达的写入（如 `_increaseAmount` 的 `quota − invested` 下溢分支）不计入风险，只计入覆盖说明与 §7 的「不是缺陷」。
5. **规格授权的行为不当缺陷**：规格明文要求的宽松面（结算读当前治理票、配置懒继承、`joinedAmountBy*` 无按轮历史）只在 §7 记录其可观测后果，不计入发现。

### 1.1 存储原语的写入语义（14 个文件共用）

| 库 | 关键语义 | 对本卷的影响 |
| --- | --- | --- |
| `OrderedHistoryIndex.record(key)` | 仅当 `key > keys[last]` 时追加；`key == keys[last]` 走 `assert`（通过，覆写同轮值）；`key < keys[last]` 也走 `assert`（Panic 0x01） | 所有按轮账本必须**单调不减**；同轮多次写只保留最终值（规格 `05:56` 明确要求） |
| `RoundHistoryUint256.value(round)` | 有精确记录取记录，否则取「不大于该轮」的最近记录 | 轮次账本是**懒继承**，因此「无写入 = 沿用上一轮」；这也意味着「本轮没写」与「本轮写了 0」必须靠 `index.contains(round)` 区分 |
| `RoundHistoryUint256.increase/decrease` | `record(round, value(round) ± delta)` | 减量必须 ≤ 该轮时点存量，否则整笔回滚 |
| `RoundHistoryUint256Set.add/remove` | 判存在用 `indexPlusOneHistory[value].latestValue()`（**最新值**，不是 `round` 时点值）；`remove` 是 swap-and-pop | 「当前集合」与「按轮集合」共用一份存储；写入轮必须单调，否则 `assert` 失败 |
| `Uint256Set.add/remove` | 同上，但无轮次 | 当前态集合（`joined*` 族、`activeApplicationIds`、`quotaMemberIds*`） |

## 2. 状态总表

| 合约 | 行数 | 自有存储变量 | 部署后可变的部分 | 写入函数（去重） |
| --- | --- | --- | --- | --- |
| `ActionTarget` | 531 | 13（6 配置 + 7 账本） | 全部 13 个 | `init`、`registerJoinState`、`clearJoinState`、`forceClearJoinState`、`onProposalCreated` |
| `ExecutorBase` | 140 | 4 immutable | **无** | 构造器 |
| `LpExecutor` | 533 | 1 const + 1 immutable + 14 账本 | 14 个账本 | 构造器、`onProposalCreated`、`join`、`withdraw`、`exit`、`_mintMemberReward` |
| `GroupActionExecutor` | 750 | 1 `Layout`（58 字段）+ 1 immutable | 58 个 Layout 字段 | 构造器（`SPLITS`）+ 21 个入口（19 个经库）+ `_mintMemberReward` |
| `GroupActionJoin` | 849 | 0（写 20 个 Layout 字段） | — | `join`、`withdraw`、`exit`、`addProviderQuota`、`removeProviderQuota`、`withdrawProviderQuota` |
| `GroupActionVerify` | 853 | 0（写 17 个 Layout 字段） | — | `submitOriginScores`、`submitVerifierApplication`、`cancelVerifierApplication`、`onProposalVoted` |
| `GroupActionManager` | 506 | 0（写 17 个 Layout 字段） | — | `onProposalCreated`、`activateGroup`、`deactivateGroup`、`setGroupConfig` |
| `GroupServiceExecutor` | 800 | 2 const + 3 immutable + 1 `Layout`（14 字段） | 10 个 Layout 字段 | 构造器、`onProposalCreated`、`_mintMemberReward` |
| `GroupRecipients` | 367 | 0（写 4 个 Layout 字段） | — | `setRecipients` |
| `GroupActionStorage` | 190 | 58 字段（声明）+ 6 常量 | 由上述三个库写 | 无（只有 `view` helper） |
| `GroupServiceStorage` | 80 | 14 字段（声明）+ 3 常量 | 由 Executor / Recipients 写 | 无（只有 2 个 helper） |
| `GroupActionRoundAxis` | 21 | 0 | — | 无 |
| `LpRoundAxis` | 16 | 0 | — | 无 |
| `MemberOwner` | 26 | 0 | — | 无 |

**合计**：14 个文件 5,662 行；可部署合约 4 个（`ActionTarget` + 3 个 Executor）；业务库 4 个（Join / Verify / Manager / Recipients）；纯声明或纯换算 6 个（2 个 Storage、2 个 Axis、`MemberOwner`、`ExecutorBase`）。

> 上表是基线 `0c1d1e2` 的快照。处置后的代码另有 `ActionRoundAxis.sol`（11 行，中立轴库）与 `GroupServiceRoundAxis.sol`（11 行，服务铸币轴），不计入本卷 14 文件口径；`GroupActionStorage` 190 → 188 行、58 → 57 字段，`GroupActionExecutor` 750 → 745 行，`GroupServiceExecutor` 800 → 792 行，`LpExecutor` 533 → 529 行。

三个数字值得单独记：

| 项 | 值 |
| --- | --- |
| 全仓可变的 Layout 字段 | **72**（GroupAction 58 + GroupService 14） |
| 其中「只写一次」的配置槽 | 13（GroupAction 8 + GroupService 4 + `SPLITS`） |
| 其中「只增不删」的账本 | 21（历史轮账本、申请 id、投票名册、行动注册表） |

## 3. 写权限矩阵（谁能推动哪本账）

「触发者」是链上可达的最小权限，不含部署脚本。鉴权细节见 `action-api-auth-2026-11`，这里只回答「谁能让状态动」。

| 账本 | 触发者 | 入口 | 说明 |
| --- | --- | --- | --- |
| `ActionTarget` 5 个配置槽 | **任何人**（一次性） | `init` | 鉴权根，抢跑后果见 `AT-01` |
| `ActionTarget._executorByActionId` / `_actionIds` / `_actionIdsByExecutor` | 仅 Core `Submit` | `onProposalCreated` | 写一次，永不改 |
| `ActionTarget` 三本加入账 | 已绑定 Executor | `registerJoinState` / `clearJoinState` | 当前态 + 按轮集合 |
| `ActionTarget` 三本加入账（强制清理） | 该 `memberId` 的 NFT 持有人 | `forceClearJoinState` | 与正常清理写同样的三个槽（M-AT-02） |
| `LpExecutor` 4 个配置槽 | 仅 `ActionTarget` | `onProposalCreated` | 写一次 |
| `LpExecutor` 14 本账 | 该 `memberId` 的 NFT 持有人 | `join` / `withdraw` / `exit` / `mintMemberReward(s)` | 加入与撤回写当前加入轮；结算写 `_memberMinted` 族 |
| `GroupAction` 8 个配置槽 | 仅 `ActionTarget` | `onProposalCreated` | 写一次 |
| `GroupAction` 参与账（20 个字段） | 该 `memberId` 的 NFT 持有人（Provider 额度面是该 `providerId` 的持有人） | `join` / `withdraw` / `exit` / Provider 五件 | 只写当前加入轮 |
| `GroupAction` 验证结果（7 个字段） | 该 `verifierId` 的 NFT 持有人（且必须锁定或榜内） | `submitOriginScores` | 只写 `phase − 2` 轮 |
| `GroupAction` 申请（6 个字段） | 该 `verifierId` 的 NFT 持有人 | `submitVerifierApplication` / `cancelVerifierApplication` | 常设，按提交轮写历史 |
| `GroupAction` 投票记账（4 个字段） | 仅 Core `Vote` | `onProposalVoted` | 只写投票轮 |
| `GroupAction` 群状态（9 个字段） | 该 `groupId` 的 NFT 持有人 | `activateGroup` / `deactivateGroup` / `setGroupConfig` | 当前态 + 押金计数器 |
| `GroupAction` 结算（3 个字段） | 该 `memberId` 的 NFT 持有人 | `mintMemberReward(s)` | 一次一份 |
| `GroupService` 4 个配置槽 | 仅 `ActionTarget` | `onProposalCreated` | 写一次 |
| `GroupService` 分母缓存 | **任何成员**（首个结算者） | `_mintMemberReward`（经 `cacheDenominator`） | 每 `(行动代币, 轮)` 一次 |
| `GroupService` 5 个结算字段 | 该 `memberId` 的 NFT 持有人 | `mintMemberReward(s)` | 一次一份 |
| `GroupService` 二次分配（4 个字段） | 该 `groupId` 的 NFT 持有人 | `setRecipients` | 只写当前验证轮 |
| `GroupService` 加入态 | 该 `memberId` 的 NFT 持有人 | `join` / `exit` | **不写本合约**，只写 `ActionTarget` |

**唯一的无许可业务写**：`GroupService` 的分母缓存（`cacheDenominator`）由「第一个结算该轮的人」写，内容只取决于 `(行动代币, 轮)` 的账本，不由调用者决定——与 core `Phase.sync` 的「谁先同步谁决定观测点」同型，但这里的值是完全确定的，没有选择空间。

## 4. 发现汇总

### 4.1 全量索引

| ID | 级别 | 合约 | 一句话 | 证据 |
| --- | --- | --- | --- | --- |
| `M-GAM-01` | **Low** | GroupActionManager | 创建回调只校验 `joinTokenAddress != 0`，`_maxJoinAmount` 无条件读 `totalSupply()`；打错地址使行动永久不可加入且 `maxJoinAmount()` 视图回滚 | E1 |
| `M-AT-01` | Info | ActionTarget | `joinedRounds` 是当前态、`isJoinedByRound` 是历史态，对已退出成员给出相反答案 | E1 |
| `M-AT-02` | Info | ActionTarget | 强制清理与正常清理写同样三个槽，`forced` 只存在于事件 | E1 |
| `M-AT-03` | Info | ActionTarget | 三本注册表只增不删，没有行动注销路径 | E1 |
| `M-EB-01` | Info | ExecutorBase | 铸币阶段未开始：内部报 `RoundAfterMintWindow(round, 0)`，ABI getter 报 `RoundNotStarted(1, 0)` | E1 |
| `M-EB-02` | Info | ExecutorBase | 四个 immutable 依赖「`ActionTarget.init` 先执行」，该约束只由解码失败表达 | E1 |
| `M-EB-03` | Info | ExecutorBase | `mintMemberRewards` 无批量上限，循环内可能逐项触发外部铸币 | E1 |
| `M-LP-01` | Info | LpExecutor | 两个加入日志数组只增不减、不随撤回缩放，`deduction()` 无界增长 | E1 |
| `M-LP-02` | Info | LpExecutor | `memberReward` 把四种「不能结算」压成同一个 `(0,0,false)`，写面却有四个错误 | E1 |
| `M-LP-03` | Info | LpExecutor | `totalEffectiveAmount == 0` 与「激励为零」共用 `MemberRewardPoolEmpty` | E1 |
| `M-LP-04` | Info | LpExecutor | `deduction()` 的三个返回值不足以自校验（缺 `phaseStart` / `phaseBlocks`） | E2 |
| `M-GAE-01` | Info | GroupActionExecutor | `memberBurnedReward` 是死槽，`burnAmount` 恒为 0，事件的 `burnAmount` 永远为 0（**已裁决：删除槽位**） | E1 |
| `M-GAE-02` | Info | GroupActionExecutor | 同一个「创建轮」在 ActionTarget 与三个 Executor 里各存一份，无交叉断言 | E1 |
| `M-GAE-03` | Info | GroupActionExecutor | 1 wei 级份额永久不可领取，且与「未验证」在视图上不可区分 | E2 |
| `M-GAE-04` | Info | GroupActionExecutor | 首次结算后整笔激励进入合约余额，未领取部分没有回收路径 | E1 |
| `M-GAJ-01` | Info | GroupActionJoin | 两级归属计数用 `++`/`--` 且无零值守卫，成对性只由三个写点的组合保证 | E1 |
| `M-GAJ-02` | Info | GroupActionJoin | `join` 先写外部注册表、后写本地账本，与 `LpExecutor.join` 顺序相反 | E1 |
| `M-GAJ-03` | Info | GroupActionJoin | 验证信息值按 schema 下标绑定，链下传错顺序会静默错配 | E1 |
| `M-GAJ-04` | Info | GroupActionJoin | `joinedRound` 会被「退出后重新加入」覆写，首次加入轮不可从状态读出 | E1 |
| `M-GAJ-05` | Info | GroupActionJoin | `_quotaUsedAt` 以当前所属群判定已用额度，换群后旧额度突然显示为全额可用 | E1 |
| `M-GAJ-06` | Info | GroupActionJoin | `removeProviderQuota` 与 `withdrawProviderQuota` 批量语义不对称，前者对重复 id 整批回滚 | E1 |
| `M-GAJ-07` | Info | GroupActionJoin | `_restoreProviders` 遍历快照时删集合元素，依赖 `values()` 先物化 | E1 |
| `M-GAV-01` | Info | GroupActionVerify | 替换/撤销申请后旧申请的票与名册仍留在状态里，该轮各申请票数之和可大于实际投票数 | E1 |
| `M-GAV-02` | Info | GroupActionVerify | 满分不写扣分槽，「已验证」不能用扣分槽判断 | E1 |
| `M-GAV-03` | Info | GroupActionVerify | 申请 id 单调、旧申请说明永久保留，`applicationIdCount` 无上限 | E1 |
| `M-GAV-04` | Info | GroupActionVerify | `lockedVerifierId` 无超时、无接管，锁定者失联则整轮零激励 | E1 |
| `M-GAV-05` | Info | GroupActionVerify | `roundVerified` 的成立条件依赖「验证轮集合冻结」，该前提不在本库内可验证 | E1 |
| `M-GAV-06` | Info | GroupActionVerify | 榜外申请不可枚举：有票但未上榜的申请只能按 id 猜 | E1 |
| `M-GAV-07` | Info | GroupActionVerify | `onProposalVoted` 对「没有验证者项」静默返回，投票成功但不记任何验证者票 | E1 |
| `M-GAM-02` | Info | GroupActionManager | `_checkActivationMinGovRatio` 是全仓唯一一处手写比例乘法，溢出形态是 Panic | E2 |
| `M-GAM-03` | Info | GroupActionManager | `setGroupConfig` 立即影响进行中的加入轮，四项群配置没有按轮历史 | E1 |
| `M-GAM-04` | Info | GroupActionManager | `activatedRound` / `deactivatedRound` 的链上用途只有一处相等判定 | E1 |
| `M-GAM-05` | Info | GroupActionManager | 三个质押计数器维度不同却同族命名，`stakedByMemberId` 实际按 `groupId` 聚合 | E1 |
| `M-GSE-01` | Info | GroupServiceExecutor | 结算金额依赖领取时点的治理票，`(代币, 行动, 轮, 成员)` 不能唯一确定结果 | E2 |
| `M-GSE-02` | Info | GroupServiceExecutor | 缓存值在 `mintActionReward` 之前算出、之后写入，等值依赖「准备后 `A[a]` 冻结」 | E2 |
| `M-GSE-03` | Info | GroupServiceExecutor | 零分母轮次永不写缓存，每次尝试都重新枚举全部入榜行动 | E1 |
| `M-GSE-04` | Info | GroupServiceExecutor | 服务代币必须支持 `burn(uint256)`，合约不校验；上限绑定时才暴露 | E1 |
| `M-GSE-05` | Info | GroupServiceExecutor | `joinedAmountBy*` 的 `round` 参数不参与计算，与同名读面语义不同 | E1 |
| `M-GRC-01` | Info | GroupRecipients | `RecipientsChanged.prev*` 是懒继承后的有效值，不是本轮原值 | E1 |
| `M-GRC-02` | Info | GroupRecipients | 配置懒继承使「配一次永久生效」，集合无法区分「本轮配过」与「继承来的」 | E1 |
| `M-GRC-03` | Info | GroupRecipients | `distribute` 循环无界，群主可放大其成员的结算 gas | E1 |
| `M-GRC-04` | Info | GroupRecipients | 配置不校验群激活/参与，任意群主可污染全局配置面 | E1 |
| `M-STG-01` | Info | GroupActionStorage | `SPLITS` 是唯一影响状态机形状的配置，合约侧零校验 | E1 |
| `M-STG-02` | Info | GroupActionStorage | 58 个字段只有 4 处 `Load-bearing`，其中 2 处的前提落在别的文件里；另 3 处承重前提未登记 | E1 |
| `M-STG-03` | Info | GroupActionStorage | `PRECISION` 三处独立定义、无编译期绑定 | E1 |
| `M-STG-04` | Info | GroupActionStorage | `memberBurnedReward` 是死槽（与 `M-GAE-01` 同一事实，从布局侧确认；**已裁决：删除槽位**） | E1 |
| `M-GSS-01` | Info | GroupServiceStorage | 分母缓存用 `0` 兼作「未缓存」，无法缓存合法的零分母 | E1 |
| `M-GSS-02` | Info | GroupServiceStorage | `cacheDenominator` 自身无幂等守卫，唯一性靠调用方前置条件 | E1 |
| `M-GSS-03` | Info | GroupServiceStorage | 同一 Layout 两种第一维，同一概念三个名字（含误导性的 `joinTokenAddress`） | E1 |
| `M-GSS-04` | Info | GroupServiceStorage | 五个结算槽未打包，一次结算写 6 个独立 mapping 槽 | E1 |
| `M-AXS-01` | Info | GroupActionRoundAxis | `phase − 1` 在轴库之外还有一份字面副本（`ActionTarget`），漂移时静默失败 | E1 |
| `M-AXS-02` | Info | GroupActionRoundAxis | 返回 0 的哨兵在消费方有守卫式与透传式两种处理，同一条件两种错误 | E1 |
| `M-AXS-03` | Info | LpRoundAxis | LP 的 `mintRound` 比 GroupAction 早一轮，但共用同一个 `_checkMintWindow` | E1 |
| `M-AXS-04` | Info | LpRoundAxis | 两个轴库的 `joinRound` 逐字节相同，改一处不会触发编译错误 | E1 |
| `M-MOS-01` | Info | MemberOwner | 只识别 `ERC721NonexistentToken` 一个 selector，其他「不存在」形态透传 | E1 |
| `M-MOS-02` | Info | MemberOwner | 群身份用容错查表、成员身份用严格查表，两种错误契约并存 | E1 |

**分布：56 条，Low 1（已修复）/ Info 55，无 Critical / High / Medium。**

**处置：1 Low 已修复（`M-GAM-01`）；另 5 条 Info 随修复提交落地（`M-EB-01`、`M-AXS-01`、`M-AXS-04`（`joinRound` 最终收敛）、`M-GAE-01`、`M-STG-04`）；`M-GSE-02` 以规格承载（按 `dev-standards §5.3` 不加源码注释）；其余 49 条为规格补写或口径登记，逐条落点见各分卷末尾的「处置」表。修复提交见 §8 抬头。**

这个分布是结论，不是遗漏：`action/` 的状态写入面被 20+ 处 `Load-bearing` 注释覆盖，且此前已有两轮专项（权限、事件）把「谁能写」「发了什么」挖过一遍。本卷剩下的是**跨文件的时序前提**、**哨兵与懒继承的可观测后果**、**死槽与重复定义**三类，它们的共同特征是不影响单笔交易的正确性，只影响「多轮之后账本还能不能自证」。

### 4.2 按合约分布

| 合约 | Low | Info | 小计 |
| --- | --- | --- | --- |
| `ActionTarget` | 0 | 3 | 3 |
| `ExecutorBase` | 0 | 3 | 3 |
| `LpExecutor` | 0 | 4 | 4 |
| `GroupActionExecutor` | 0 | 4 | 4 |
| `GroupActionJoin` | 0 | 7 | 7 |
| `GroupActionVerify` | 0 | 7 | 7 |
| `GroupActionManager` | 1（已修复） | 4 | 5 |
| `GroupServiceExecutor` | 0 | 5 | 5 |
| `GroupRecipients` | 0 | 4 | 4 |
| `GroupActionStorage` | 0 | 4 | 4 |
| `GroupServiceStorage` | 0 | 4 | 4 |
| 两个 Axis + `MemberOwner` | 0 | 6 | 6 |
| **合计** | **1（已修复）** | **55** | **56** |

写入面最大的两个模块（Join 20 字段、Verify 17 字段）也是发现最密的两卷，合计 14 条，占全部发现的 25%。

## 5. 三条跨合约结论

### 5.1 「创建轮」有四个副本，「加入轮」已收敛为一处定义

| 事实 | 副本 | 漂移后果 |
| --- | --- | --- |
| 创建轮 | `ActionTarget:453`、`GroupActionManager:123`、`LpExecutor:121`、`GroupServiceExecutor:428` | 加入窗口与结算窗口错位一格，两处都不报错（M-GAE-02） |
| 加入轮 `phase − 1` | `ActionRoundAxis:9`（唯一定义） | `ExecutorBase._joinRound():134` 是单一实现点（非 `virtual`），`ActionTarget._joinRound():383` 与 `GroupActionManager:378/485` 直接调 `ActionRoundAxis`；类型轴库已不含 join，无副本（M-AXS-01 已修复 / M-AXS-04 已收敛） |
| 验证轮 `phase − 2` | `GroupActionRoundAxis:7` | 单点，无副本 |
| 铸币轮 | `GroupActionRoundAxis:12`（`phase − 3`）、`GroupServiceRoundAxis:7`（`phase − 3`）、`LpRoundAxis:7`（`phase − 2`） | 三个 Executor 的窗口差一轮，链下按统一 `mintRound` 聚合会错（M-AXS-03） |

创建轮的四个副本都在同一笔里写同一个 `currentPhase()`，所以**当前**恒等；风险是「将来改一处」。

**修复提交后的行号位移**（本卷所有 `:NNN` 仍以 `0c1d1e2` 为准；读修复后源码时按此换算）：`ExecutorBase` 140 → 146（import +1、`:121` 之后 +3、`_joinRound` 由声明改实现 +2）；`GroupActionManager` 506 → 513（`:77` 之后 +7）；`ActionTarget` 531 → 531（`:13` 之后 +1、`:379` 之后回零）；`GroupActionExecutor` 750 → 745（`:735` 之后 −1、三处 `_joinRound` override 删除 −4）；`GroupServiceExecutor` 800 → 792（三处 `_joinRound` override 删除 −4、其余位移 −4）；`LpExecutor` 533 → 529（override 删除 −4）；`GroupActionStorage` 190 → 188（`:167` 之后 −2）；`GroupActionRoundAxis` 21 → 16（join 删除）；`LpRoundAxis` 16 → 11（join 删除）；新增 `ActionRoundAxis` 11 行、`GroupServiceRoundAxis` 11 行；`IGroupActionExecutor.sol` 81 → 82。其余对象行号不变。

### 5.2 三个 Executor 的「同名读面」有四种语义

| 读面 | `LpExecutor` | `GroupActionExecutor` | `GroupServiceExecutor` |
| --- | --- | --- | --- |
| `joinedAmountByActionId(t, a, r)` | 按轮历史 | 按轮历史 | 当前 `totalStaked`（`r` 只作上界） |
| `joinedAmountByMemberId(t, a, r, m)` | 按轮历史 | 按轮历史 | 当前 `stakedByMemberId` |
| `memberReward(t, a, r, m)` | 三元组（含 `minted`） | 三元组 | 三元组 |
| `joinTokenAddress(t, a)` | LP 代币 | 参与代币 | **源行动代币** |
| `mintMemberReward` 的窗口 | `phase − 2` | `phase − 3` | `phase − 3` |

前四行都是规格授权的（`06:56`、`02:6`），但它们意味着「按接口名统一适配三个 Executor」在链下会得到四种不同的答案（M-GSE-05、M-GSS-03）。

### 5.3 「已铸未分配」与「未铸未结算」是同一种资金状态的两种形态

| 形态 | 位置 | 状态表现 | 是否可回收 |
| --- | --- | --- | --- |
| 未铸未结算 | core `Mint.rewardReserved` | `actionReward` 返回 `(理论值, false)`，预留不释放 | ❌（ADR-004） |
| 已铸未领取 | 三个 Executor 的代币余额 | `memberMinted == false`，余额在合约里 | ❌（无 sweep） |
| 已结算但份额 < 1 wei | `memberMinted == false`（回滚） | 每次重试都回滚 `MemberRewardRoundedToZero` | ❌（M-GAE-03） |
| 治理上限销毁 | `ownerBurnedByMemberId` / `_burnedRewardByMemberId` | 已 `burn` | ✅（已销毁） |

ADR-004 只覆盖第一行。第二、三行是同一现象的另外两种形态，本卷在 `04-group-action-executor.md` 的 M-GAE-04 与 `03-lp-executor.md` 的 §2.5 各记了一处。

## 6. 与既有审查的交叉核对

只列与状态写入直接相关、且本卷逐行复核后仍成立的项；括号内为既有编号。

| 级别 | 项 | 状态视角的复核点 |
| --- | --- | --- |
| **Medium** | `ActionTarget.init` 抢跑换掉四个鉴权根（`AT-01`） | 本卷确认这 5 个槽是**全部写入口的鉴权根**（§3 矩阵第 1 行），且 `init` 是唯一的无许可写；未修复 |
| Low | `mintActionReward` 不校验铸币窗口（`AT-02`） | `ActionTarget` 不写状态，`Mint._proposalMinted` 是唯一幂等点；窗口错误由 `Mint` 给出，非本仓可修 |
| Low | 未创建行动的 `join` 报 `UnauthorizedExecutor` / `GroupNotActive`（`LP-01` / `GAJ-02`） | `LpExecutor.join` 先写本地三本账再调 `registerJoinState`（`M-LP-01` 附近），失败整笔回滚；错误名仍不一致 |
| Info | `activationStakeAmountByActionId` 的单写由 `ActionTarget` 保证（`GAE-02`） | 本卷补状态后果：一旦覆写，`deactivateGroup` 会把差额从其他群的质押里退（`07` §2.3 第 4 步） |
| Info | `hasActiveGroups(token, memberId)` 的第二参数实际是 `groupId`（`GAM-05`） | 本卷补金额侧：`stakedByMemberId` 同样按 `groupId` 聚合（`M-GAM-05`） |
| Info | `setRecipients` 的存在性校验排在参数校验之前（`GRC-02`） | 本卷确认该顺序不影响状态：存在性失败不写任何槽 |
| Info | 库不校验轮次，写哪一轮由调用方传入（`GRC-03`） | `GroupServiceExecutor` 传 `currentVerifyRound()`，因此库侧的「不校验」当前不可利用 |
| Info | 两个轴库 `joinRound` 逐字节相同，`ActionTarget` 有第三份同式（`SUP-02`） | 本卷补漂移后果（`M-AXS-01`）；处置后 join 轴只在 `ActionRoundAxis` 定义一次，类型轴库不含 join（`M-AXS-04` 已收敛） |
| Info | 三处「付款对象是结算时的 NFT 持有人」（`GSE-04` / `GAE-04`） | 本卷未重复论证，三处均按「资产随身份走」认定 |

本卷**新增 56 条**，与既有编号零重叠。三卷合计：权限 38 + 事件 24 + 状态 56 = 118 条，其中 Medium 2、Low 3、Info 113。

## 7. 判定为「不是缺陷」的十处疑点

逐条给出为什么不算，便于后续审查不再重复提出。

| # | 疑点 | 结论 |
| --- | --- | --- |
| 1 | `createdRound == 0` 兼作「未创建」，若行动在 Phase 0 创建就永久不可用 | **不可达**：`Submit._submitByProposalId` 在 `_callProposalCreated` 之前调 `Phase.sync()`，`phase == 0` 时 `sync` 回滚 `PhaseNotStarted`，因此创建回调不可能在 Phase 0 执行 |
| 2 | `_increaseAmount` 的 `quota − invested` 会下溢（Panic 而非业务错误） | **不可达**：`invested` 只在 `amount <= quota − invested` 时增加；`quota` 的两条减路径都保证 `quotaAfter >= invested`（`06` 的 J6 给了完整证明） |
| 3 | 服务结算金额随领取时点的治理票变化 | **规格授权**（`06:77`），记为 M-GSE-01 的可观测后果，不算缺陷 |
| 4 | `GroupServiceExecutor.joinedAmountBy*` 忽略 `round` | **规格授权**（`06:56`「社区激活质押为当前值，没有按轮历史」） |
| 5 | 二次分配配置懒继承（配一次永久生效） | **规格授权**（`06:85`「回退到不晚于该轮的最近配置」） |
| 6 | 部分撤回时 `_deductionByRound` 按比例分摊，不是逐笔缩放 | **规格授权**（`04:59-66` 给了公式与示例） |
| 7 | `lockedVerifierId` 被锁定者失联会拖死整轮 | **规格承认**（`05:94`「锁定者失联、未完成时，行动层激励为零」），记为 M-GAV-04 的可观测后果 |
| 8 | 分母缓存在 `mintActionReward` 之前算出、之后写入 | **等值可证**：准备前后 `rewardAvailable()` 与 `A[a]` 的取值相同，缓存不会失真；时序前提已写入 06 规格（不加源码注释） |
| 9 | `_upsertRank` 榜满时早退但票已入账 | **设计**：规格 `05:79`「榜满时榜外验证者必须票数严格超过末位才替换」；记为 M-GAV-06 的对账缺口 |
| 10 | `_checkOpenVerifier` 的 `phaseInfo(round + 2)` 是否读到外推值 | **不是外推**：`round = currentVerifyRound() = phase − 2`，`round + 2 = phase` 是**当前** Phase，`phaseInfo` 返回精确记录值 |

## 8. 优先处理

按「修一次能消掉多条 / 修完能防住静默失败」排序。修复提交 `action@2014788`（`fix(state): drop dead burn slot, guard join token, unify join axis`）落地了第 1–5 项；第 6 项为文档性修正，已写入 action 规格。

1. **`M-GAM-01`（Low，唯一一条非 Info）— 已修复**：`onProposalCreated` 先判 `joinTokenAddress.code.length == 0`，再 `try IERC20(joinTokenAddress).totalSupply() {} catch`，两者统一回滚 `InvalidJoinTokenAddress`。新增用例 `testJoinTokenWithoutTotalSupplyIsRejected`（创建回滚 + 该 action 的 `maxJoinAmount()` 返回 0 不回滚）。
2. **`M-AXS-01` / `M-AXS-04`（静默失败面）— 已修复（最终形态）**：`joinRound` 只在 `ActionRoundAxis:9` 定义一次。`ExecutorBase._joinRound():134` 是它的**单一实现**（去掉 `virtual`），`GroupActionExecutor` / `GroupServiceExecutor` / `LpExecutor` 三处 override 全部删除；`ActionTarget` 的 `registerJoinState` 也由内联 `currentRound - 1` 改为 `_joinRound()`（`:128`），两者同源；`GroupActionManager:378/485` 直接调 `ActionRoundAxis`；`GroupActionRoundAxis` / `LpRoundAxis` 删除 `joinRound`，只保留类型专属的 verify/mint，`GroupServiceExecutor` 不再引用 `GroupActionRoundAxis`（服务铸币偏移落到 `GroupServiceRoundAxis`）。剩余重复只有按类型本就不同的 `mintRound`，登记为事实而非缺陷。
3. **`M-GAE-01` + `M-STG-04`（删死槽）— 已裁决、已修复**：`memberBurnedReward` 从 Layout 删除、唯一写入点删除、`memberReward` 的 `burnAmount` 固定返回 `0`（签名不变）；`GroupActionStorage` 190 → 188 行、58 → 57 字段。事件卷 `GAE-EV-1` 与 `event-standards §4.2` 的措辞同步为「字段恒 0 且无对应状态槽」。
4. **`M-GSE-02`（时序前提）— 规格承载，不加源码注释**：按 `dev-standards §5.3`「代码默认不写注释」，不在 `_mintMemberReward` 加注释；时序前提写入 [`06-service-executor.md`](../../docs/specs/action/06-service-executor.md) 的「状态口径」。
5. **`M-EB-01`（统一错误）— 已修复**：`_checkMintWindow` 在 `mintRound == 0` 时回滚 `RoundNotStarted(1, 0)`；`LpExecutor.t.sol` 的窗口断言同步更新。
6. **文档性修正（零风险）— 已写入规格**：`M-AT-01`（`joinedRounds` 语义）、`M-GAV-02`（扣分槽零值二义）、`M-GRC-01`（`prev*` 是有效值）、`M-GSS-03`（`joinTokenAddress` 在服务侧的误导）、`M-GAM-05`（`stakedByMemberId` 的维度），以及 05/06 规格的「状态口径」附录。

> 本轮不动的结构项：`GroupActionManager.onProposalCreated` 与 `GroupActionVerify.onProposalVoted` 的函数体留在库内（`GroupActionExecutor` 余量仅 2,454 字节，实测两个回调全内联超限 1,953 字节），评估与结论见 [`action-api-auth-2026-11/README.md`](../action-api-auth-2026-11/README.md) 的「A-3 补记」。

## 9. 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 无 PoC | 全卷以静态审查为主。56 条中 50 条 E1、5 条 E2；`M-GAM-01` 已升级为 **E3**（`testJoinTokenWithoutTotalSupplyIsRejected` 实测创建回滚且 `maxJoinAmount()` 不回滚）；`M-GAE-03` 仍需构造 `proposalReward * score < totalFinal` 的用例 |
| 门禁 | 已跑并全绿：`forge build --deny warnings`、`forge lint`、`forge test`（35 套件 / 470 用例）、`check-events.py`（34 events / 50 expectEmit）、`check_errors.py --check`（232 声明 / 194 签名 / 0 违规）、`check_error_tests.py action`（84 errors / 0 untested）、`check_caller_auth.py action/src`（0 违规）、`check_doc_payloads.py`（184 errors / 192 refs / 0 失配）、`check_naming.py --check`（0 违规） |
| storage-layout | 已实测：`forge inspect GroupActionExecutor storage-layout` 修复前后对比，确认只少 `memberBurnedReward` 一项，其余前 57 个字段槽位与偏移不变；`ActionTarget` 13 个槽在删死槽与抽/删 join 轴两轮改动后逐项未变 |
| phase 0/1 语义 | `registerJoinState` 改走 `_joinRound()` 后，`testRegisterJoinStateRejectsBeforeJoinOpens`（`ActionTarget.t.sol`）覆盖 phase 0 与 phase 1，均断言 `JoinNotOpen(11, phase, createdRound)`——轴库返回 0 不改变该入口的回滚错误 |
| 未审继承实现 | `ReentrancyGuard` / `SafeERC20` / `Math` / `ERC721` 按 OZ 5.6.1 的公开语义认定，未逐行复核 |
| 未审跨仓 | core 侧账本（`Stake` / `Vote` / `Mint` / `Launch`）的写入不在本卷范围；`group-chat` 经 grep 确认对 `memberBurnedReward` / `memberReward(` 无自有引用，仅 submodule 指针待随同步更新 |
| 未审测试 | 未逐条核对 `test/` 是否覆盖本卷的 56 条（事件审查已指出 `vm.expectEmit` 全部 4 参、不校验 emitter，`GL-EV-1`） |
| 未量化 gas | `M-GRC-03`、`M-GSS-04`、`M-GAV-03` 三条的成本只有结构判断，没有数值 |

## 10. 文档索引

| 文件 | 对象 | 状态写入面 | 发现 |
| --- | --- | --- | --- |
| [`01-action-target.md`](01-action-target.md) | `ActionTarget`（contract） | 13 个变量 / 5 个写入口 | `M-AT-01`～`03` |
| [`02-executor-base.md`](02-executor-base.md) | `ExecutorBase`（abstract） | 4 immutable / 0 可变 | `M-EB-01`～`03` |
| [`03-lp-executor.md`](03-lp-executor.md) | `LpExecutor`（contract） | 14 本账 / 6 个写入口 | `M-LP-01`～`04` |
| [`04-group-action-executor.md`](04-group-action-executor.md) | `GroupActionExecutor`（contract） | 1 Layout + 21 个入口的字段映射 | `M-GAE-01`～`04` |
| [`05-group-action-join.md`](05-group-action-join.md) | `GroupActionJoin`（library） | 20 个 Layout 字段 | `M-GAJ-01`～`07` |
| [`06-group-action-verify.md`](06-group-action-verify.md) | `GroupActionVerify`（library） | 17 个 Layout 字段 | `M-GAV-01`～`07` |
| [`07-group-action-manager.md`](07-group-action-manager.md) | `GroupActionManager`（library） | 17 个 Layout 字段 | `M-GAM-01`～`05` |
| [`08-group-service-executor.md`](08-group-service-executor.md) | `GroupServiceExecutor`（contract） | 10 个 Layout 字段 | `M-GSE-01`～`05` |
| [`09-group-recipients.md`](09-group-recipients.md) | `GroupRecipients`（library） | 4 个 Layout 字段 | `M-GRC-01`～`04` |
| [`10-group-action-storage.md`](10-group-action-storage.md) | `GroupActionStorage`（library） | 58 个字段的声明与写者 | `M-STG-01`～`04` |
| [`11-group-service-storage.md`](11-group-service-storage.md) | `GroupServiceStorage`（library） | 14 个字段的声明与写者 | `M-GSS-01`～`04` |
| [`12-group-action-round-axis.md`](12-group-action-round-axis.md) | `GroupActionRoundAxis`（library） | 无状态 | `M-AXS-01`～`02` |
| [`13-lp-round-axis.md`](13-lp-round-axis.md) | `LpRoundAxis`（library） | 无状态 | `M-AXS-03`～`04` |
| [`14-member-owner.md`](14-member-owner.md) | `MemberOwner`（library） | 无状态 | `M-MOS-01`～`02` |

每个文件的固定结构：**§1 状态布局 → §2 逐变量变更逻辑（按写入函数）→ §3 不变式 → §4 发现 → §5 已核对为正确的点 → §6 覆盖缺口**。§5 是正面结论，不编号为发现。
