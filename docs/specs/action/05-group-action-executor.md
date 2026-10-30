# GroupAction Executor

GroupAction 使用 MemberNFT 身份，`groupId` 是群主体的 `memberId`，不是钱包地址。参与资产见 [共同模型](03-participation.md)，四阶段映射见 [阶段模型](02-phase-model.md)。

## 配置与参与接口

旧 `LOVE20TKM/extension-group/src/GroupManager.sol` / `LOVE20TKM/extension-group/src/GroupJoin.sol` 的 extension 地址改为 `tokenAddress + actionId`；不为每个 Proposal 部署 Executor。部署依赖通过 init 绑定，业务配置由 Proposal 创建回调写入。`init(actionTargetAddress, stakeAddress, splits)` 只收 ActionTarget、Stake 和验证阶段分割线：`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`VOTE_ADDRESS` 从 `stakeAddress` 的 getter 读取一次并缓存；依赖有代码、Stake 派生值与 Mint 派生图交叉一致及分割线合法性由 `DeployAction` 广播前校验：空数组合法，表示不分层、仅投票第一名作为当轮唯一公共验证者；非空时每项 `0 < split < 1e18` 且严格递增。`21_check.sh` 直接读取 Stake 的派生 getter 与 splits 复核，`init` 只防重复初始化并保存配置。分割线是部署期静态配置，由部署脚本校验、21_check 复核，合约不重复校验；`ActionTarget` 允许提案绑定任意 Executor，非脚本部署的 Executor 由其提案方自担配置风险。激励经 `ActionTarget` 读取，不注入 Mint。分割线由 `SPLITS()` 暴露，只读。

参与、群配置和历史查询接口见 [`IGroupActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionExecutor.sol)。

创建 Target Data 沿用旧行动参数，从第 `1` 项起（第 `0` 项是 ActionTarget 保留的 executor）固定为 `targetData[1] = abi.encode(address joinTokenAddress)`、`targetData[2] = abi.encode(uint256 activationStakeAmount)`、`targetData[3] = abi.encode(uint256 maxJoinAmountRatio)`、`targetData[4] = abi.encode(uint256 activationMinGovRatio)`、`targetData[5] = abi.encode(uint256 verifierStakeAmount)`；`joinTokenAddress` 为零回滚 `ZeroJoinTokenAddress()`，两个比例均以 `1e18` 为满值，超出按字段回滚 `InvalidMaxJoinAmountRatio(value)` / `InvalidActivationMinGovRatio(value)`；`verifierStakeAmount = 0` 表示验证者申请不要求押金。配置和激活资格、质押退还及容量计算沿用旧 GroupManager；`maxCapacity = 0` 使用理论容量，`maxJoinAmount/maxAccounts = 0` 不另设群级上限，非零最大加入量不得低于最小加入量；群描述 `GroupConfig.description` 与验证者申请说明同受 1024 字节上限约束，超出回滚 `DescriptionTooLong(length, 1024)`。群描述的按轮快照用 `descriptionByRound(tokenAddress, actionId, round, groupId)` 读取（RoundHistory 懒继承：无记录继承最近历史，从未设置返回空串）。项数少于 `6`（缺少必需配置）回滚 `TargetDataLengthMismatch(6, targetData.length)`，多于 `7`（超出可选验证信息）回滚 `TargetDataLengthMismatch(7, targetData.length)`；第 `1`～`5` 项不是 32 字节回滚 `InvalidTargetDataShape(index, length)`。创建回调成功的同一笔内由本 Executor 发出 `GroupActionCreated`，携带初始配置与验证 schema 全量：`joinTokenAddress`、`activationStakeAmount`、`maxJoinAmountRatio`、`activationMinGovRatio`、`verifierStakeAmount`、`verificationKeys`、`verificationDescriptions`；注册表事实由 ActionTarget 的 `ActionRegistered` 承担。

**验证信息**：由 [`IGroupActionVerify.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionVerify.sol) 继承 [`IVerificationInfo`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IVerificationInfo.sol)，`IGroupActionExecutor` 再继承 `IGroupActionVerify`。验证信息分为两层：

- **Action 级别模板**：由行动创建者在提交提案时定义，通过 `verificationSchema(tokenAddress, actionId)` 查询，返回 `(keys[], descriptions[])`，说明加入者需要提交哪些验证字段（如 `["twitter_handle", "tweet_url"]`）及其含义（如 `["你的推特账号", "转发推文链接"]`）。
- **Member 级别实例**：由成员在加入行动时提交具体值，通过 `verificationValue(tokenAddress, actionId, memberId, key)` 查询单个字段值，`verificationInfos(tokenAddress, actionId, memberId)` 查询所有字段当前值，`verificationInfosByRound(tokenAddress, actionId, memberId, round)` 查询指定 round 的历史快照。

验证信息模板的 keys 和 descriptions 在 Proposal 创建回调时通过可选 `targetData[6] = abi.encode(string[] keys, string[] descriptions)` 传入，后续不可修改；两数组不等长回滚 `VerificationInfoLengthMismatch(keys.length, descriptions.length)`。成员提交的验证信息值在加入时写入，项数与模板 keys 不符同样回滚 `VerificationInfoLengthMismatch(keys.length, verificationValues.length)`，值项数超过 `16` 回滚 `TooManyVerificationValues(count, 16)`、单个值超过 `1024` 字节回滚 `VerificationValueTooLong(index, length, 1024)`；模板 schema 超过 16 项回滚 `TooManyVerificationEntries(count, maxCount)`、key/description 超过 1024 字节分别回滚 `VerificationKeyTooLong(index, length, maxLength)`/`VerificationDescriptionTooLong(index, length, maxLength)`；每次修改参与量时可更新。schema 作为 `targetData[6]` 还要受 `Submit` 的 `targetData` 总量 16 KiB 约束（见 [提交](../core/05-submit.md)），因此「16 项 ×1024 字节」只是事件字段上界，链上创建路径可达的最坏值更低。追加参与量时若不提交验证值（`verificationValues` 为空数组），`GroupActionJoined.verificationValues` 为空数组，含义是**本次无新值**、既有值保持不变，折叠不得清空。

管理操作要求持有 groupId；自有参与操作要求持有 memberId。`activateGroup` 只接受本 Executor 已创建的行动（`createdRound != 0`）：创建回调之前 `activationStakeAmount` 仍为零、gov-ratio 下限未设，放行会让群零押金入场并绕开下限；未创建时回滚 `ActionNotCreated(tokenAddress, actionId)`。`groupId` 即群主体的 memberId，同一成员在同一行动上至多激活一个链群：行动内是否激活用 `isGroupActive(tokenAddress, actionId, groupId)` 直查，不设行动维度的按 owner 激活列表与质押查询。跨行动的社区级判定与聚合保留（主体为 memberId，与全员身份模型一致）：`hasActiveGroups(tokenAddress, memberId)` 一次判定该成员（自身作为链群主体）在该社区是否存在激活行动（GroupService 加入资格判据），`stakedByMemberId(tokenAddress, memberId)` 返回其全部激活链群的累计质押（各行动 `activationStakeAmount(tokenAddress, actionId)` 可能不同且激活行动数未知，不展开为按行动遍历）。同一行动中成员只能归属一个 Group，追加不得改群；换群须先正常退出。`join` 的资产来源由 `providerId` 决定：`0` 表示成员自有代币，非零表示从该 Provider 已存入合约的额度中扣减。同一成员可在同一行动上混合多个来源，重复 `join` 按来源分别追加；`joinInfo`（含 `joinedAmount` 与 `ownAmount`/`providerAmount` 聚合）、`joinedAmountByMemberId` 与 `joinedAmountByGroupId` 都包含全部来源。`withdraw` 只减少自有账本，`withdrawProviderQuota` 只撤回指定链群内该 Provider 的未使用额度（可部分），两者不互相抵扣；成员总参与量（自有 + 全部 Provider）归零时自动退出（自有 `withdraw` 或 `removeProviderQuota` 触发）。`withdrawProviderQuota` 由该 Provider 当前持有人调用，代币返还该 Provider 当前持有人；Provider 身份不授予成员 `exit` 或额度管理权限。成员调用 `exit` 时结清全部来源：自有资产返还成员，Provider 来源恢复为该 Provider 对该成员的可用额度、不转出合约（Provider 仍可用 `removeProviderQuota` 取回）。代币量只由 `GroupActionJoined` 与 `GroupActionWithdrawn` 承载：`exit` 对自有金额发一条 `GroupActionWithdrawn`（`providerId = 0`），对每个有余额的 Provider 发一条 `ProviderQuotaRestored`；`GroupActionExited` 只表示退出状态（带链群 `groupId`）、不带金额。无参与记录返回零元组，历史集合无记录返回空数组。

## 当前归属与索引

事实关系为 `tokenAddress + actionId + groupId + memberId`。跨本 Executor 的全部社区与行动维护一小组**由参与事实驱动**的索引（`joined*` 记号即指这一族：只有真的有人参与过才会入榜），读取按 [集合读取函数的设计原则](../../dev-standards.md#43-集合读取函数) 收敛，不为每个维度组合维护全量索引：

| 查询 | 语义 |
| --- | --- |
| `isGroupMember(groupId, memberId)` | 该成员当前是否归属该链群（跨全部社区与行动聚合），Group Chat 的链上判据 |
| `joinedGroupIds` | 当前有归属成员的链群 |
| `joinedGroupIdsByMemberId` | 某成员当前归属的链群 |
| `joinedTokenAddressesByGroupIdByMemberId` | 某成员在某链群下的归属涉及哪些社区 |
| `joinedMemberIds` | 当前有归属的成员 |
| `joinedMemberIdsByGroupId` | 某链群当前的成员 |

五条 `joined*` 都用标准分页 `(offset, limit, reverse) → (列表, 真实总数)`：越界返回空数组与真实总数、不回滚；`limit` 超剩余按剩余返回；`reverse` 从新到旧。`reverse` 只承诺逆序遍历当前存储顺序，不承诺等于插入顺序——集合用 swap-and-pop 删除，同一 `offset` 的返回内容不保证跨调用稳定，调用方不得跨调用缓存 `offset`，也不得按「先拉首页再增量补页」拼接。`isGroupMember` 与 `joinedTokenAddressesByGroupIdByMemberId` 是同一份存储上的两个读入口：前者是存在性布尔，后者取完整取值。

加入/退出同步维护这些集合与归属计数，不依赖扫描事件；成员在全部社区、全部行动下对同一 `groupId` 的归属计数归零后 `isGroupMember` 才返回假，退出一个行动不影响其他关系。`ActionTarget.forceClearJoinState` 不修改这些索引。

## Round 历史

**加入窗口从创建轮之后开始，并对之后每一轮都开放**：`join` 只写当前加入轮（`currentJoinRound()`），不校验「本轮是否等于创建轮」；下界由 `ActionTarget.registerJoinState` 的 `JoinNotOpen` 兜住（当前投票轮必须大于创建轮）。因此同一个行动可以在多个轮次各自聚集一批参与，每轮的参与、验证与激励互不影响。

加入阶段每笔加入、追加、部分撤回及退出（含 Provider 额度来源的加入），都更新当轮参与记录。同一 Round 多次操作只保留该轮最终值，不新增多个版本；无人交互的 Round 继承最近历史，不逐轮复制或同步。同一批历史同时给出两条**按轮读取**：`groupIdsByRound(tokenAddress, actionId, round, offset, limit, reverse)` 是该轮有参与成员的链群，验证者据此逐个验证链群；`memberIdsByGroupId(tokenAddress, actionId, round, groupId, offset, limit, reverse)` 是该轮某链群的成员历史顺序。两者与 `joined*` 同用标准分页签名，越界返回空数组与真实总数。

加入结束后不得回写目标 Round。验证直接读取该轮 Group 和成员历史，不需要前置准备交易；验证集合只由目标 Round 历史决定，与验证阶段链群当前的激活状态无关——加入轮结束后停用、恢复或新增链群都不改变该轮验证集合。该轮集合在加入阶段结束后不再写入，因此按 `offset` 连续翻页等价于连续游标；验证按历史成员顺序使用连续游标，不能重复、跳过或乱序。

原存储示意为 `mapping(round => mapping(groupId => mapping(memberId => ParticipationData)))`；外层仍须隔离 token 和 action。沿用旧 RoundHistory 语义：无记录表示继承最近历史，退出通过显式记录零值形成终止点，不能直接删除历史记录。

## 验证者申请与排名

验证者席位申请是**常设登记**：成员在行动创建轮及之后的任意轮次提交一次申请，该申请从提交轮起对之后每一轮都有效，不必逐轮重新申请。排名按**当轮** `voteAmount` 降序、`applicationId` 升序，平票时较早申请优先。验证者只在收到新投票时才按规则进入或更新当前排名；替换或撤销申请时，旧申请从**当前轮**排名中移除，不由榜外申请自动补位。

**行动可跨轮复用，申请常设、计票按轮**：Proposal 在创建轮之后的任意轮次都可以再次推举、投票、加入、验证与结算，每一轮是一条独立的流水线。为此：

- **票数按轮隔离**：`voteAmountByApplicationId[tokenAddress][actionId][round][applicationId]` 只存该轮票数，排名与一切查询都读该值。不存在跨轮累计值——把不同轮的票加在一起既没有语义（选民集合不同），也会让旧申请压过当轮新申请而不回滚。
- **申请常设**：`submitVerifierApplication` 在行动创建轮及之后的任意轮次可用，申请自提交轮起生效并对之后每一轮持续有效。同一成员在同一行动只有一条当前申请；**修改申请等价于撤销后重新申请**——旧 ID 失效、新 ID 单调递增且从零计票，当前轮排名里的旧项被移除。
- **按轮查询**：`verifierApplication(tokenAddress, actionId, round, verifierId)` 回答「该成员在该轮以哪份申请站台」。该映射用 `RoundHistoryUint256` 按 `[tokenAddress][actionId][verifierId]` 记录：申请时在提交轮写入当时的 `applicationId`，撤销时在该轮写入显式零值，读取按 RoundHistory 的懒继承语义取「不晚于该轮的最近记录」。因此第 3 轮申请、第 5 轮才修改时，查第 4 轮仍返回**第 3 轮那份申请及其说明**；修改只影响修改轮及之后，从不回写历史。无记录返回零值结构体。**票数仍按轮读取**：`votesByVerifierIds` 先用同一份历史解析该轮生效的申请，再读该申请在该轮的票，与 `topVerifiers` 一致，不因后续修改申请而改变。
- **验证按当轮排名**：`submitOriginScores` 只作用于当前验证轮，从该轮的排名里选锁定验证者，验证者身份按该轮的历史解析——投票轮之后替换或撤销申请只改变后续轮次，**不收回该轮已得到的验证资格**（仍在榜内即可锁定，已锁定即可继续提交）；某验证者在该轮没有申请或没有票，就不在榜内，无法锁定。

验证者、验证和激励查询接口见 [`IGroupActionExecutor.sol`](https://github.com/LOVE20BSC/action/blob/main/src/interfaces/IGroupActionExecutor.sol)。

申请者须持有 verifierId 且有该社区有效治理票（无票回滚 `ZeroVerifyVotes(tokenAddress, verifierId)`）；`description` 以字节计不超过 1024，超出回滚 `DescriptionTooLong(length, 1024)`。公共验证者比例 `publicVerifierRatio` 不再属于申请流程，移至 GroupService 按服务 Proposal 绑定（见 [Service Executor](06-service-executor.md)）。`submitVerifierApplication` 新建或替换当前申请：旧 ID 失效，新 ID 单调递增且从零计票，并在提交轮写入历史；未创建的行动（`createdRound == 0`）回滚 `ActionNotCreated(tokenAddress, actionId)`。`cancelVerifierApplication` 撤销当前申请、当前轮榜内项，并在该轮写入零值终止点；不扫描榜外补位，押金随之全额退还。`verifierApplication(tokenAddress, actionId, round, verifierId)` 按 RoundHistory 懒继承回答「该轮以哪份申请站台」，无记录时返回零值结构体（`applicationId = 0`）。当前有效申请（已取消的不算）按标准分页读取：`verifierApplications` 直接回申请记录与总数，这是本接口唯一直接回含变长字段记录体的分页查询——申请记录带变长 `description`（结构体仅含 `applicationId`、`verifierId`、`description`），按集合读取原则本应只回 id 再加按 id 批量，但该查询的消费方只有链下展示；若日后出现链上调用方，须改为「只回 id + 按 id 批量」。`topVerifiers` 按票数高到低返回榜内 `verifierIds[]` 与对应 `voteAmounts[]` 两个定长数组（下标对齐；榜的容量是前 `n` 名，元素与成员一一对应），榜内成员的申请说明用 `verifierApplication` 另取；当轮任意验证者的票数用 `votesByVerifierIds(tokenAddress, actionId, round, verifierIds[])` 按下标对齐批量读取，无票回 `0`、不回滚。单个验证者的投票名册有两个分页入口：`applicationVoters(tokenAddress, actionId, round, applicationId, offset, limit, reverse)` 按申请 id 直读，`applicationVotersByVerifierId(tokenAddress, actionId, round, verifierId, offset, limit, reverse)` 先用该轮申请历史解析出申请再读同一份集合（该轮没有该成员的申请即返回空数组与 `0`，不回滚）。两者都回 `(voterIds[], voteAmounts[], total)`：下标对齐，`voteAmounts` 是该投票人对该申请在该轮的累计票，`total` 是名册人数；只取总数传 `limit = 0`，不另设计数入口。名册只追加、从不删除，因此 `reverse` 即首次投票的逆序；不变式是 `voteAmountByApplicationId == Σ voteAmounts`，且与 `topVerifiers` 给出的该申请票数恒等。名册以 `(round, applicationId)` 为键，同一轮内替换申请时 `RoundHistoryUint256` 在该轮覆写为新 `applicationId`，因此按 `verifierId` 查该轮只会解析到替换后的新申请（名册从空开始），旧申请的票与名册只能按 `applicationId` 查——与「替换等价于撤销后重新申请、新 ID 从零计票」同源。名册规模由投票人数决定（无界），因此只提供分页、不提供全量读取；页内成员是两个 `uint256`，定长。其余索引与列表查询按标准分页语义越界返回空数组与真实总数、不回滚。

**验证者押金**：行动创建时按 `targetData[5]` 配置 `verifierStakeAmount`，由 `verifierStakeAmount(tokenAddress, actionId)` 读取。配置非零时，成员在该行动上**首次**申请时把该数量的行动代币从当前持有人转入 Executor；此后的修改（等价于撤销后重新申请）既不退还也不再划转，余额或授权不足时整笔回滚、不留下申请。只有 `cancelVerifierApplication` 才把押金全额退还给该 verifierId 的当前持有人——因此「已质押」与「持有当前申请」是同一件事，`verifierStake(tokenAddress, actionId, verifierId)` 在持有当前申请时返回配置额、否则返回 0。押金只担保「持有当前申请」：撤销即退款，**即使该成员已在本轮排名内或已锁定**——验证资格由当轮的排名决定（见上文「验证按当轮排名」），与是否仍持有申请无关。押金与链群激活质押相互独立：不计入 `staked`/`totalStaked`/`stakedByMemberId`，不影响 `hasActiveGroups`，也不构成 GroupService 的加入量。押金划转由 `VerifierStakeDeposited`/`VerifierStakeRefunded` 带金额留痕；`VerifierApplicationSubmitted` 承载状态并带 `description`、被替换的 `previousApplicationId` 与 `hasPreviousApplication`，`VerifierApplicationCancelled` 只带 `applicationId`，两者都不带金额。

投票 Target Data 为空表示不指定验证者；非空时第 `0` 项为已绑定 Executor（ActionTarget 转发门禁），本 Executor 的业务项从第 `1` 项起：`targetData[1] = abi.encode(uint256 verifierId)`，对应当轮有效申请，项数多于 `2` 回滚 `TargetDataLengthMismatch(2, targetData.length)`，第 `1` 项不是 32 字节回滚 `InvalidTargetDataShape(1, length)`。每次回调只把全部治理票增量记给该验证者在**该轮**的申请并维护排名；「该轮 → 成员 → 申请」的关联由 `submitVerifierApplication` 维护；回调不校验轮次——`Vote` 传的是它自己的 `currentRound()`（即当轮），而提案只能在其创建轮或之后被投票，因此 `round` 恒不早于创建轮；验证者没有当前申请则回滚 `NoActiveApplication(verifierId)`。该字段为空时不增加验证者票，本次票数为零时既不记票也不记名册。排名增量维护，只保存可开放的前 n 名；榜满时榜外验证者必须票数严格超过末位才替换，不因修改旧申请自动转移票数。记账的同一次写入里把该投票人并入该验证者在该轮的名册：名册按 `(round, applicationId)` 隔离，投票人去重，同一人对同一验证者多次投票只占一行、金额累加——首次投票是该人三笔冷写（集合槽、去重索引槽、金额槽），重复投票只加金额。每次记账发出 `ApplicationVoteRecorded`，带 `voterId`、`applicationId`、`verifierId`、本次 `voteAmountAdded` 与该申请在该轮的 `voteAmountTotal`（后置累计）；投票人不省略也不靠同交易内的 `VoteCast` 关联，投票名册由此事件流可直接折叠。

`submitOriginScores` 只作用于当前验证轮（不收 `round` 入参）；调用者持有 verifierId，批次数组非空，每项不超过 100、单批项数超过协议上界 100 回滚 `VerificationBatchTooLarge(count, 100)`，原始分超过 100 回滚 `ScoreLimitExceeded(index, score, 100)`，`startIndex` 等于该群已验证数量且不能超出历史成员数（越界回滚 `ScoreCountExceeded(startIndex, count, memberCount)`）。验证者无当前申请回 `NoActiveApplication(verifierId)`；有申请但未进入当轮排名回 `VerifierNotRanked(verifierId, round)`，分割窗口未开回 `VerifierNotOpen(verifierId, round)`。全部校验成功才锁定和计分；同一成员记录只消费一次。未验证的分数查询返回 `(0, false)`，与已验证零分区分。提交成功后发 `OriginScoresSubmitted`，除本轮分数数组外还带该轮跨群后置累计 `totalFinalScore`、`verifiedGroupCount`、整轮的 `roundVerified` 与本批次是否推满该群游标的 `groupVerified`（该群 `verifiedMemberCount` 追平该群该轮成员数）；首个有效批次锁定验证者时发 `VerifierLocked`，indexed 为 `tokenAddress`、`actionId`、`verifierId`。

存储记「扣分」而非原始分：已验证成员仅当原始分低于 100 时写一次 `100 − 原始分` 的冷槽，满分零写入（沿用旧 `GroupVerify.sol` 的 gas 记法）；「已验证」不占存储位，由成员在目标 Round 群集合中的位置早于该群已验证游标推导——该推导依赖前文「加入结束后不得回写目标 Round」：目标轮集合快照冻结后，已验证游标前缀与实际计分集合恒等。查询接口仍按 `(score, verified)` 返回；读路径由单槽读取变为按轮点查（群归属、已验证游标、集合定位与扣分读取），精确命中为 O(1)，未命中回退到最近已记录轮（二分），结算路径经库调用复用同一解码。每组的轮级累计量用累加器，不按成员二次写。原始分上限 100 仍由 `ScoreLimitExceeded(index, score, 100)` 在写入前显式校验，减法记法的下溢不是校验手段。

第 1 名在验证阶段起点开放，后续排名按下式开放：

```text
openOffset = ceil(verifyPhaseBlocks * SPLITS[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

`SPLITS[0]` 对应第 2 名。`block.number >= openBlock` 才开放，不能因取整提前。读取方用 `SPLITS()` 与 `IPhase.phaseInfo(round + 2)` 的 `(startBlock, phaseBlocks)` 自行计算各名次的开放区块；可开放人数为 `SPLITS().length + 1`，第 1 名在验证阶段起点即可提交。`SPLITS()` 为空数组时不分层，只有第 1 名作为当轮唯一公共验证者。

首个有效验证批次永久锁定验证者 MemberNFT；NFT 转移后新持有人续验，不能由未经授权的验证者接管。需完成目标 Round 的全部 Group 验证；无验证者入榜或锁定者失联、未完成时，行动层激励为零，底层 Proposal 激励仍可独立铸造或销毁。`generatedActionRewardByGroupId` 与一切行动层分配查询按轮次读取，目标轮未完成验证时返回 0，不因部分批次已计入而返回正值；GroupService 与 GroupAction 阶段划分相同，其读取的轮次已经完成验证，正常不会命中该分支。相关验收见 [组织验收](../../acceptance.md#公共验证者与-round-历史)。

## 行动激励

公共验证者按同一规则记录原始分和最终分。每条冻结成员记录只计入一次，不允许对同一份参与量重复评分。

```text
finalScore(memberId) = participationAmount(memberId) * originScore(memberId)
totalFinalScore = sum(finalScore across all groups)
memberReward(memberId) = floor(proposalReward * finalScore(memberId) / totalFinalScore)
```

所有 Group 使用同一原始得分和最终得分规则；按目标 Round 已确认参与数据汇总全行动的 `totalFinalScore` 后直接分配。`totalFinalScore` 为零时不除零，行动层激励为零；群 owner 的聚合份额由其成员最终激励之和得到，不在 Group 内再次按比例分配。成员结算无可分配量（目标轮未完成验证、`finalScore` 为零或行动激励为零）时回滚 `MemberActionRewardUnavailable(tokenAddress, actionId, memberId, round)`，不置位已结算、不发事件，验证完成后可重试。

Executor 先按 [统一铸造链路](07-minting.md#铸造链路) 取得整笔激励，再内部分配。

## 实现约束

- 退出零值与无记录继续使用旧 RoundHistory 的显式记录语义；不得通过清空 mapping 伪造退出。
- 可开放名次数为 `n = SPLITS.length + 1`，不是本轮总申请人数。分割线严格递增且在 `(0, 1e18)` 内，空数组只开放第 1 名。投票结束后排名自然冻结，不增加冻结交易。
- 验证者席位竞选是 BSC 新逻辑；旧 `LOVE20TKM/extension-group/src/GroupVerify.sol` 的 `submitOriginScores` 仅作为连续批次和原始分校验的参考，不是该机制来源。
- 链群身份不存在的错误落点：群管理、`join`、`addProviderQuota`、`removeProviderQuota` 回滚 `GroupNotExist(groupId)`。链群未激活的错误落点：`deactivateGroup`、`updateGroupConfig`、`join`、`addProviderQuota` 回滚 `GroupNotActive(groupId)`。验证路径不检查链群当前激活状态。
- 行动存在性判定（`createdRound == 0`）统一回滚 `ActionNotCreated(tokenAddress, actionId)`：`activateGroup`、`submitVerifierApplication` 与成员结算的第一段守卫都用它；成员结算的第二段仍按轮次判，`round < createdRound` 归 `RoundBeforeActionCreated(round, createdRound)`（见[铸造](07-minting.md#铸造链路)的错误表）。
- Provider 额度的授予、调整与枚举见 [共同模型](03-participation.md#provider-额度接口)；额度授予即存入合约，`join` 只按使用量消耗可用额度（授权额度只由 Provider 动作变动）、不再转移代币；划转量由 `ProviderQuotaAdded`/`ProviderQuotaRemoved` 逐成员发出，`withdrawProviderQuota` 按链群撤回未使用额度（可部分）并发 `ProviderQuotaRemoved`，成员参与量不变；`removeProviderQuota` 收回整笔授权：已投入部分同额减少参与量并发 `GroupActionWithdrawn`，授权额度清零（`ProviderQuotaRemoved.quotaTotal = 0`）。
- 三个协议级上界是**编译期常量**，不进 `init`、不设 getter：原始分上限 100（`ScoreLimitExceeded(index, score, 100)`）、单个验证批次项数上限 100（`VerificationBatchTooLarge(count, 100)`）、描述字段 1024 字节（`DescriptionTooLong(length, 1024)`）。它们对所有部署、所有社区、所有行动一致，属协议语义的一部分；本协议没有管理员身份（`init` 不保存部署者、不授予特权），做成配置项同样写入即不可改，只会增加部署参数与错配面。
- 参与代币量只由 `GroupActionJoined` 与 `GroupActionWithdrawn` 记录（Provider 额度恢复另发 `ProviderQuotaRestored`）：`GroupActionJoined` 带 `amount`、来源键 `providerId` 与 `verificationValues`；`GroupActionWithdrawn` 自有撤回为 `providerId = 0`，Provider 撤回带其 `providerId`；`GroupActionExited` 带 `groupId`、不带金额。
- 群配置事件：`activateGroup` 发 `GroupActivated`，携带激活押金 `stakeAmount` 与 4 项初始群级配置（`maxCapacity`、`minJoinAmount`、`maxJoinAmount`、`maxAccounts`）及 `description`；`updateGroupConfig` 发 `GroupConfigChanged`，按新组→旧组携带上述 4 项与 `description` / `prevDescription`；`deactivateGroup` 发 `GroupDeactivated`。旧值不是布尔取反可推，必须逐项携带。
- 代币划转按资金类别各自留痕：参与量走 `GroupActionJoined`/`GroupActionWithdrawn`，Provider 额度恢复走 `ProviderQuotaRestored`，链群激活质押走 `GroupActivated`/`GroupDeactivated`，验证者押金走 `VerifierStakeDeposited`/`VerifierStakeRefunded`；状态类事件不带金额。

## 部署体积与拆分

Executor 是单例，全部逻辑落在一个地址上会超过 EIP-170 的 24,576 字节上限（旧实现实测 39,241 字节），因此把实现体拆进 `action/src/` 的 `public` 库、按业务模块各成一个库，经 delegatecall 执行；部署地址、ABI 与状态都不变。

**状态只有一份，由一个根 Layout 承载。** 全部状态收进 `GroupActionStorage.Layout` 一个 struct，Executor 只声明 `GroupActionStorage.Layout internal _layout`；库函数一律只收一个 `GroupActionStorage.Layout storage self` 加业务参数。状态变量增减只改 Layout，不改任何库的函数签名；多个库共享同一个 Layout，天然读写同一份存储，不出现「这个库要传哪几个变量」的问题。

**Layout 变更即重新部署**：字段的插入、删除或重排都会移动后续槽位。本仓无生产部署，Layout 变更后必须整体重新部署；若已有部署，只能把新字段追加到结构体末尾，不能把「本仓这次只是追加」当成通用规则。

**库按业务模块划分**，一个业务一个库、一个库一个接口文件，不按调用热度：

| 库 | 接口文件 | 对应旧文件 | 内容 |
| --- | --- | --- | --- |
| `GroupActionVerify` | `IGroupActionVerify.sol`（`is IVerificationInfo`） | `GroupVerify.sol` | 验证提交与连续游标、扣分写入（满分免写）与位置化已验证推导、`finalScore`/`totalFinalScore` 汇总、验证者申请/撤销（含押金划转与退还）与排名查询、验证信息查询、投票回调的票数记账、投票名册与排名 |
| `GroupActionJoin` | `IGroupActionJoin.sol` | `GroupJoin.sol` | `join`、`withdraw`、`exit`、Provider 额度五件、Round 历史读写、参与索引与归属计数维护、成员验证信息值写入、`joinInfo`、`joinedAmountByGroupId` |
| `GroupActionManager` | `IGroupActionManager.sol` | `GroupManager.sol` | `activateGroup`、`deactivateGroup`、`updateGroupConfig`、`groupState`，以及创建回调写入行动配置、验证信息模板与创建轮；群集合/质押/描述快照查询（`activeGroupIds` 族、`staked` 族、`tokenAddressesByGroupId`、`actionIdsWithActiveGroups`、`descriptionByRound`、`hasActiveGroups`、`maxJoinAmount`——实现即在此；沿用旧 GroupManager 口径（`hasActiveGroups` 判定成员自身作为链群主体在社区是否存在激活行动），按当前加入轮读取行动票占比与 joinToken 当前 `totalSupply`）；推举回调当前只校验调用者，无状态写入 |

成员级激励铸造不单独成库：它只有约 1.6KB，且成员结算三件（`mintMemberReward`/`mintMemberRewards`/`memberReward`）声明在基座 `IActionExecutor`，留在 Executor 实现即可，也省掉每笔结算的跨库开销。

`IGroupActionExecutor` 自身声明 Executor 本地实现的成员（依赖 getter、`init`、`currentVerifyRound`、行动层激励查询两件——`generatedActionReward` 与 `generatedActionRewardByGroupId`——与成员结算四件）、包不进行动配置与创建回调的错误，其余全部经上表三个模块接口继承；`GroupConfig` 声明在 `IGroupActionManager.sol`，`VerifierApplication` 声明在 `IGroupActionVerify.sol`。

**库不能继承接口**（Solidity 不允许），所以「接口文件 ↔ 库」是**声明归属的映射**，编译期唯一强制的契约是 Executor 继承全部接口、其包装函数再调用对应库：接口签名漂移在 Executor 编译不过，库侧签名漂移则在该调用点编译不过。

**共享状态与共享规则都只留一份，运行时依赖图保持星型**：跨模块共享的状态通过同一个根 Layout 直接读写（创建回调写验证信息模板、验证写分数、分配读分数），库之间不产生 DELEGATECALL、没有循环依赖——判据是各业务库的 `linkReferences` 不含其他业务库；源级依赖只允许指向规则属主模块、单向、不成环。跨模块的**规则**按属主落位——有单一属主的（`maxJoinAmount` 属 `GroupActionManager`）实现留在属主模块，其他模块以 `internal` 函数**编译期内联**复用，当前唯一一条源级依赖是 `GroupActionJoin` → `GroupActionManager`；无属主且被两个以上模块消费的留在 `GroupActionStorage`，即 `currentJoinRound`（`GroupActionJoin`、`GroupActionManager`）、`memberAmountAt`（`GroupActionVerify`、Executor 本地）与只由 Executor 基座查询使用的 `joinRound`；`requireMemberOwner` 已按 §5.5 改为各库本地的 `onlyMemberOwner` modifier。属主模块持有的规则不进 `GroupActionStorage`。

**除业务库之外留在 Executor 的两类**：一是**会被其他合约链上调用的接口**——`IGroupActionIndexes` 的查询（Group Chat 链上读 `isGroupMember`；五条 `joined*` 分页查询随业务库走）、行动层激励查询两件（Group Service 读取：一件取行动总额做分母，一件取群切片做权重）与基座 `IActionExecutor` 的 Round、参与量查询：这类函数本身很便宜，跨库会让一次读取的固定开销（约 2,600 gas 冷访问）翻倍；只被钱包与前端读取的查询走 `eth_call`、不计 gas，随业务库走。二是**成员级激励铸造**（见上表下方说明）。

「留在 Executor」指**实现**留在 Executor：写成转发库的薄壳没有意义，仍要付跨库开销。

两条硬规则：库调用不得出现在循环体内——成员批量结算与验证批次的循环必须整体位于同一侧，不得按元素跨库；库只承载逻辑，不声明状态变量。

验证是本协议 gas 占比最高的路径（每轮、每群、每成员都要处理一次分数），优化优先级高于其余部分：每个成员每轮至多一次新的冷写入（非满分写扣分、满分零写入），批次内其余状态用轮级累加器；跨库跳转只落在冷路径上，一次批量提交的跨库开销相对批量本身可忽略。

部署脚本按「先部署各库、再链接部署 Executor」执行，库地址与链接关系记入 `script/network/<net>/`；`forge build --sizes` 的 24,576 上限纳入实现门禁。实现对账时按库分别核对 runtime 上限，任一库超限则继续按业务边界细分。

验收见 [Action 验收](08-testing.md)。
