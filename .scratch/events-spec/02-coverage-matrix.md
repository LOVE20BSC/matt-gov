# LOVE20BSC 事件统一规范 · 领域对象覆盖矩阵

日期：2026-10-26  
状态：已确认（2026-10-26）  
配套：`01-gap-table.md`（逐事件去留）、`matt-gov/docs/event-standards.md`（规范正文，已写）  
范围：`core`、`action`、`group-chat` 生产合约；`libs` 无事件；`dex` 排除。

---

## 0. 根键与链路

| 域 | 根键 | 父链 | 链路事件 | 说明 |
|---|---|---|---|---|
| core / action | `tokenAddress` | `round` → `memberId` / `proposalId` / `actionId` / `groupId` | — | 所有 core/action 事件以 token 为根 |
| group-chat | `groupId` | `senderId` / `messageId` / `adminId` / `delegateId` / `targetSenderId` | `TokenGroupActivated(tokenAddress, groupId, operator)`、`TokenActionGroupActivated(tokenAddress, actionId, groupId, operator)` | groupId 全局递增、不复用；群名/所有者在 core `MemberMinted` |
| 跨域群对象 | `groupId` | token → action → group | 三个发射者：core `MemberMinted`（名称/所有者）、action `GroupActivated`（组配置/激活）、group-chat `GroupChatActivated` + 两条 `Token*GroupActivated`（聊天配置/链路） | 同一 group 对象跨三仓，必须用 groupId 关联 |

---

## 1. Core 域

| 对象 | 状态迁移 | 目标事件 | 覆盖状态 | 缺口 / 处理 |
|---|---|---|---|---|
| RootToken | 初始供给铸造 | `TokenMinted` | 供应量、持有人 | 构造期铸造即首条日志；与运行期增发按日志位置区分，不可变 `maxSupply` 不进事件 |
| RootToken | 增发 / 销毁 | `TokenMinted` / `TokenBurned` | 供应量、余额 | 标准 `Transfer` 覆盖转账/授权 |
| TokenRegistry | 创世 | `GenesisTokenCreated` | token、parent、distributor、name、symbol | name/symbol ≤96/32（init 与发起同源） |
| TokenRegistry | 发起子币 | `TokenLaunched` + `LaunchCountConsumed` | token、parent、launcher、distributor、mode、成员余额 | 扣减发 `LaunchCountConsumed`（含后置余量）；一次发射固定消耗一次，`count` 已删 |
| TokenRegistry | 发放/合并额度 | `LaunchCountAdded` / `LaunchCountMerged` | 成员余额、发行总量 | 增 `memberRemaining`/`issuedCount`/双方余额 |
| MemberNFT | 铸造 | `MemberMinted` + core `Transfer` | memberId、owner、cost、name、normalizedName | — |
| MemberNFT | 转移/授权 | 标准 `Transfer` / `Approval` / `ApprovalForAll` | owner、余额 | 不借用标准事件表达协议语义；持有人集合由此折叠 |
| MemberNFT | 持有人集合 | 删除 `HolderAdded/Removed`（已确认） | 集合、totalHolders | 由 `Transfer` 折叠；O1 |
| LaunchCredit | 治理奖励转 launch credit | 派生 | credit 余额 | `GovRewardMinted` + `LaunchCountAdded` + 不变量推导（§01 §7） |
| Phase | 同步观测 | `PhaseSynchronized` | phase、phaseBlocks | 观测数组为内部计时缓存；删除块高/时间戳/adjusted |
| Phase | 调整段长 | `PhaseAdjusted` | old/new phaseBlocks、effectivePhase | 新段 startBlock 由日志块高推导 |
| StakePosition | 加流动性 | `LiquidityStaked` | 金额、shares、govVotes、全局 total | 增 `totalLiquidityShares` 与 `totalValidGovVotes`；LP 基准为派生缓存 |
| StakePosition | 加 boost | `BoostStaked` | boostShares、govVotes、全局 total | 增 `totalBoostShares`/`totalValidBoostShares`/`totalValidGovVotes`；删恒等的 `boostSharesAdded` |
| StakePosition | 发起解锁 | `Unstaked` | unlockRound、govVotes、两个全局 total | `unlockRequestPhase = round`，文档化；增 `totalValidBoostShares`/`totalValidGovVotes` |
| StakePosition | 提取 | `StakeWithdrawn` | 金额、LP 派发、shares、全局 total | 增 `lpBurned`/`lpToMember`/两个 total；票权已清零故不带 `totalValidGovVotes` |
| StakePosition | 手续费结算 | `FeesSettled` | realized fee、两类 burn、累计 burn | 增 `totalBurnedToken`/`totalParentTokenBurned`；零手续费路径只写派生缓存，不发事件 |
| StakePosition | 合并 | `StakesMerged` | source 清空、target 后置 shares/govVotes、全局票权 | 增 `prevSource*`（融合前源状态）、`totalValidGovVotes`；indexed 对齐 |
| Proposal | 创建 | `ProposalCreated` | proposalId、authorId、target、targetMode、targetData、title、details | 已带 `targetData`；title/details 1024B、targetData 16 KiB/16 项 |
| Proposal | 提交 | `ProposalSubmitted` | round、submitter、proposalId | — |
| Proposal | 执行 | 无独立状态/事件 | — | 执行经 target 回调；不在本矩阵承诺 |
| Vote | 投票 | `VoteCast` | voter、proposal、voteAmount、boost 快照、全局 boost | 增 `voterBoost`/`totalVoterBoost` |
| RewardRound | 准备奖池 | `RewardPrepared` | gov/proposal 奖池、eligibleProposalVoteAmount、累计 reserved/burned | 零票分支同 schema |
| RewardRound | 治理奖励 | `GovRewardMinted` + `RewardBurned` | vote/boost/burn、累计 burned | 增 `burnReward`（与 `RewardBurned(BoostOverflow)` 同值，有意冗余，见 07-mint §事件） |
| RewardRound | 提案奖励 | `ProposalRewardMinted` | recipient、amount | — |
| RewardRound | 取消池燃烧 | `RewardBurned` | amount、reason | — |

---

## 2. Action 域

| 对象 | 状态迁移 | 目标事件 | 覆盖状态 | 缺口 / 处理 |
|---|---|---|---|---|
| ActionRegistry | 注册/绑定 executor | `ActionRegistered` | tokenAddress、actionId、round、executor | 注册先于 `onProposalCreated` 回调 |
| ActionConfig | GroupAction 初始化 | `GroupActionCreated` | joinToken、activationStake、maxJoinAmountRatio、activationMinGovRatio、verifierStake、verification schema | 初始配置全量；schema ≤16 项且受 targetData 16 KiB 约束 |
| ActionConfig | Service 初始化 | `ServiceActionCreated` | actionToken、govRatioMultiplier、ratioForPublicVerifier | 初始配置全量 |
| ActionConfig | LP 初始化 | `LpActionCreated` | joinToken、govRatioMultiplier、minGovRatio | 初始配置全量 |
| GroupConfig | 激活 | `GroupActivated` | active、activatedRound、config 5 字段、stake、索引 | 增初始 config；actor=群主（groupId 隐含） |
| GroupConfig | 停用 | `GroupDeactivated` | active、deactivatedRound、索引 | 可逆：`activateGroup` 会把 `deactivatedRound` 重置为 0，不是终态 |
| GroupConfig | 更新配置 | `GroupConfigChanged` | config 5 字段 + description 旧/新 | 增旧值；体积见 O7 |
| JoinState | 注册/清除（注册表） | `JoinStateRegistered` / `JoinStateCleared` | 三张 ActionTarget 索引 | 与 executor 的 join/exit 是两条事实；`forceClearJoinState`（原 `forceExit`）是 owner 兜底，只清注册表、不回调 executor |
| JoinState | 加入 | `GroupActionJoined` | 加入轮、组、金额、provider、verificationValues | 含 verificationValues（≤16×1024）；空数组＝本次无新值 |
| JoinState | 提取/退出 | `GroupActionWithdrawn` / `GroupActionExited` | 金额、组、退出轮 | — |
| ProviderQuota | 配额增加/移除 | `ProviderQuotaAdded` / `ProviderQuotaRemoved` | quota、provider 索引 | 两条事件都带 `quotaTotal`（后置授权额度），`providerQuotaWithdraw` 的 `Removed` 不隐含归零（可部分撤回）；`providerQuotaWithdraw` 按链群只撤回未使用额度、参与量不变；`providerQuotaRemove` 收回整笔授权：已投入部分发 `GroupActionWithdrawn`、授权清零发 `ProviderQuotaRemoved`（`quotaTotal = 0`）；`used` 由参与族 `GroupActionJoined`/`GroupActionWithdrawn` + `ProviderQuotaRestored` 折叠，且只计成员当前所属链群（旧群行恒 0）；块高用日志元数据 |
| ProviderQuota | 退出恢复 | `ProviderQuotaRestored`（新增） | provider、member、amount | 替代 `Withdrawn` 复用；只恢复可用额度、不转账 |
| Verification | 申请/取消/替换 | `VerifierApplicationSubmitted` / `VerifierApplicationCancelled` | application、description、previousApplication、hasPreviousApplication | 增 description/previousApplicationId/hasPreviousApplication |
| Verification | 质押/退款 | `VerifierStakeDeposited` / `VerifierStakeRefunded` | stake、member | — |
| Verification | 提交原始分 | `OriginScoresSubmitted` | scores、锁定 verifier、累计 final/total/verifiedGroupCount、roundVerified、groupVerified | 增累计字段；逐成员 finalScore 可折叠；`groupVerified` 只标本批是否收尾该群，与整轮 `roundVerified` 分开 |
| Verification | 投票（提案对验证者） | `ApplicationVoteRecorded`（新增） | voter、application、verifier、votesAdded、totalVotes | 排名与投票名册都由票数折叠 |
| Verification | 锁定 | `VerifierLocked` | verifierId | indexed 对齐 |
| RecipientTable | 设置表 | `RecipientTableChanged` | 旧/新 recipientIds、ratios、remarks | 旧+新；三数组加限 |
| RecipientTable | 分发 | `RecipientPaid` | 每收款人 amount、sourceTokenAddress | — |
| ServiceReward | 成员奖励 | `MemberRewardMinted` + `ServiceRewardsDistributed` | minted entitlement、burn、verifier/owner 拆分 | 共享类语义见 O3；denominator 为派生缓存 |
| ActionReward | 行动奖励 | `ActionRewardMinted` | round、amount | — |
| LpReward | 成员奖励 | `MemberRewardMinted` | minted、burn | `_govRatioAtMint` 为派生缓存（O10），不进事件 |

---

## 3. Group-chat 域

| 对象 | 状态迁移 | 目标事件 | 覆盖状态 | 缺口 / 处理 |
|---|---|---|---|---|
| ChatConfig | 首次激活 | `GroupChatActivated` | active、postingAllowed、sources、plugins、first* | 增初始 config；块高/时间戳用日志元数据 |
| ChatConfig | 开关发言 | `PostingAllowedChanged` | postingAllowed | 布尔旧值可推 |
| ChatConfig | 换 scope/ban source | `ScopeSourceChanged` / `BanSourceChanged` | 新/旧地址 | 已有 prev |
| ChatConfig | 换插件 | `BeforePostPluginChanged` / `AfterPostPluginChanged` | 新/旧地址 | 已有 prev |
| Message | 发消息 | `MessagePosted` | 消息正文、引用、mentionAll、提及条数、sender、round、messageId | 增 content/quoted/hasQuote/mentionAll/mentionedSenderCount；indexed 调整 |
| Message | 提及 | `SenderMentioned` | 被提及 sender、messageId | 每提及一条 |
| Message | afterPost 失败 | `AfterPostPluginFailed` | plugin、messageId、error 指纹 | 捕获型失败事实 |
| AdminSet | 增加/刷新/移除 | `AdminChanged` | adminId、listed、两个 owner 快照旧/新 | 合并 `SetAdminSnapshot`；转移失效由 core `Transfer` 推导 |
| MemberSet | 成员增删 | `MemberStatusChanged` | memberId、listed | 布尔旧值可推 |
| BanSet | 管理员封禁 | `SenderBanChanged` | targetSenderId、listed、operator | 旧值可推 |
| BanSet | 投票 | `SenderBanVoteCast` | supportBan、settledWeight、累计 support/oppose | 旧方向由上一条事件推 |
| BanSet | 投票结果封禁 | `GovSenderBanChanged` | targetSenderId、listed | 每次已结算变更由本条或上一条投票事件携带 |
| Delegation | 设置 delegate | `DelegateChanged` | delegateId、owner、ownerSnapshot、delegateOwnerSnapshot、prev* | 新快照组→旧快照组 |
| Delegation | 清零 | `DelegationCleared` | delegateId、delegateOwner、prevOwnerSnapshot、prevDelegateOwnerSnapshot | 旧快照随清除事实携带 |
| Delegation | 接受开关 | `DelegationAcceptanceChanged` | delegateId、enabled | 布尔旧值可推；按 memberId 继承，不随 NFT 转移重置 |
| ManagerLink | token → group | `TokenGroupActivated` | tokenAddress、groupId、operator | 链路事件 |
| ManagerLink | token+action → group | `TokenActionGroupActivated` | tokenAddress、actionId、groupId、operator | 链路事件；3 槽给链路键 |
| GroupName | 群名铸造 | core `MemberMinted` | memberId（= groupId）、owner、cost、name、normalizedName | group-chat 无群名事件；跨仓链路见 §0 |

---

## 4. 跨仓折叠不变量（验收用）

1. **群对象**：`MemberMinted(memberId = groupId)` + `TokenGroupActivated`/`TokenActionGroupActivated` + `GroupActivated` + `GroupChatActivated` + 后续 `*Changed` 事件，折叠结果必须等于三仓 view 的并集（名称/所有者、组配置、聊天配置、激活轮）。
2. **消息**：`MessagePosted` + `SenderMentioned` 折叠 = 消息正文、引用、mentionAll、sender、round、messageId、提及集合。
3. **管理员有效性**：`AdminChanged`（快照旧/新 + listed） + core ERC721 `Transfer`（owner 变化）折叠 = `isAdminId`。
4. **封禁**：`SenderBanChanged`/`SenderBanVoteCast`/`GovSenderBanChanged` 折叠 = 封禁集合与权重。
5. **质押**：`LiquidityStaked`/`BoostStaked`/`Unstaked`/`StakeWithdrawn`/`FeesSettled`/`StakesMerged` 折叠 = 成员 shares/govVotes/待解锁轮 + 全局 shares/govVotes/有效 boost/累计 burn；LP 基准按 §7 派生。
6. **额度**：`LaunchCountAdded`/`LaunchCountMerged`/`LaunchCountConsumed` 折叠 = 成员余额 + 发行总量（含首 token 的根账本镜像）。
7. **奖励**：`RewardPrepared`/`GovRewardMinted`/`ProposalRewardMinted`/`RewardBurned` 折叠 = 奖池、minted、burned、成员 entitlement；`_launchCredit` 按 §7 派生。
8. **Action 配置**：`ActionRegistered` + 三个 `*ActionCreated` 折叠 = executor 的 action 配置全量；`MemberRewardMinted`/`ServiceRewardsDistributed`/`RecipientPaid` 折叠 = 成员实收与分发。
9. **票据**：`GroupActionJoined`/`Withdrawn`/`Exited` + `JoinStateRegistered/Cleared` + `ProviderQuota*` 折叠 = 加入状态、金额、配额（授权额度取 `quotaTotal`，已用额度 = 成员当前所属链群视角的投资额）、退出轮。
10. **验证**：`OriginScoresSubmitted` + `ApplicationVoteRecorded` + `Verifier*` 折叠 = 原始分、加权分、排名、锁定、申请与质押。
11. **兜底清理**：`JoinStateCleared(forced=true)` 只代表 ActionTarget 注册表清理；不得回调 executor，不要求 executor 事件；executor 仓位由自身退出路径处理。

---

## 5. 明确不承诺 / 业务问题

| 项 | 性质 | 处理 |
|---|---|---|
| `forceExit` 的语义 | 设计边界 | 改判：executor 故障兜底，只清注册表、不回调 executor、不结算资金；重命名 `forceClearJoinState`；`JoinStateCleared(forced=true)` 唯一事件（O9） |
| `LpExecutor.withdraw` 全额提取只发 `LpWithdrawn`，`exit()` 只发 `LpExited` | 生命周期事件不一致 | 纳入事件重构：清仓统一 `LpWithdrawn` + `LpExited`；`exit()` 补 `LpWithdrawn`（O8） |
| `GroupServiceExecutor._mintMemberReward` 的 `mintAmount` ≠ 实收 | 语义需定义 | `mintAmount` = entitlement；实收拆分在 `ServiceRewardsDistributed`（O3） |
| `GroupChatBanList` 解禁时 operator 字段语义 | 旧 operator 状态已删，事件 actor 是执行者 | 规范明确 operator = 本次执行者 |
| NFT 转移导致 admin 失效 | 跨合约派生 | core `Transfer` 折叠；不新增 group-chat 事件 |
| `originScoreDeduction=0` 满分/未提交歧义 | 存储哨兵 | 以 `OriginScoresSubmitted` 是否覆盖该成员/批次区分 |
| LP 基准、`cacheDenominator`、`_govRatioAtMint`、pair 地址、观测历史、`_mintNonce` | 派生缓存 | 不进入事件；§01 §7 给出推导来源 |
| 不可变部署参数（constructor/init） | 非可变状态 | 不进事件；由部署清单/脚本承担来源 |
| 无界存储集合（memberIds、ban 集合、白名单） | 存储无界但事件逐条 | 事件侧无数组，不违反动态字段上限 |
| 消息正文/提案 title/details/remarks/verification schema/values、targetData | 无上限或需新增上限 | Q31(a) 要求补链上上限（O4–O7、O12） |

---

## 6. 复核顺序建议

1. O1–O14 已确认，按 §01 执行（影响字段/事件数量的条目已落表）。
2. 再逐行过 §01 的三张主表（core/action/group-chat）。
3. 最后按 §4 的 10 条折叠不变量写测试与 ABI 基线。
