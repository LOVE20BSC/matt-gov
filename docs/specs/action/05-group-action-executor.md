# GroupAction Executor

GroupAction 使用 MemberNFT 身份，`groupId` 是群主体的 `memberId`，不是钱包地址。参与资产见 [共同模型](03-participation.md)，四阶段映射见 [阶段模型](02-phase-model.md)。

## 配置与参与接口

旧 `LOVE20TKM/extension-group/src/GroupManager.sol` / `LOVE20TKM/extension-group/src/GroupJoin.sol` 的 extension 地址改为 `tokenAddress + actionId`；不为每个 Proposal 部署 Executor。部署依赖通过 init 绑定，业务配置由 Proposal 创建回调写入。`init(actionTargetAddress, stakeAddress, splits)` 只收 ActionTarget、Stake 和验证阶段分割线：`memberNFTAddress`、`phaseAddress`、`voteAddress` 在 init 内从 `stakeAddress` 的 getter 读取一次并缓存，任一为零回滚 `InvalidAddress`；激励经 `ActionTarget` 读取，不注入 Mint。分割线由 `SPLITS()` 暴露，只读。

参与、群配置和历史查询接口见 [`IGroupActionExecutor.sol`](../../../interfaces/action/IGroupActionExecutor.sol)。

创建 Target Data 沿用旧行动参数，从第 `1` 项起（第 `0` 项是 ActionTarget 保留的 executor）固定为 `targetData[1] = abi.encode(address joinTokenAddress)`、`targetData[2] = abi.encode(uint256 activationStakeAmount)`、`targetData[3] = abi.encode(uint256 maxJoinAmountRatio)`、`targetData[4] = abi.encode(uint256 activationMinGovRatio)`。配置和激活资格、质押退还及容量计算沿用旧 GroupManager；`maxCapacity = 0` 使用理论容量，`maxJoinAmount/maxAccounts = 0` 不另设群级上限，非零最大加入量不得低于最小加入量；群描述 `GroupConfig.description` 与候选人申请说明同受 1024 字节上限约束，超出回滚 `DescriptionTooLong`。项数超出约定项回滚 `InvalidTargetDataLength`。

**验证信息**：由 [`IGroupActionVerify.sol`](../../../interfaces/action/IGroupActionVerify.sol) 继承 [`IVerificationInfo`](../../../interfaces/action/IVerificationInfo.sol)，`IGroupActionExecutor` 再继承 `IGroupActionVerify`。验证信息分为两层：

- **Action 级别模板**：由行动创建者在提交提案时定义，通过 `verificationSchema(tokenAddress, actionId)` 查询，返回 `(keys[], descriptions[])`，说明加入者需要提交哪些验证字段（如 `["twitter_handle", "tweet_url"]`）及其含义（如 `["你的推特账号", "转发推文链接"]`）。
- **Member 级别实例**：由成员在加入行动时提交具体值，通过 `verificationValue(tokenAddress, actionId, memberId, key)` 查询单个字段值，`verificationInfos(tokenAddress, actionId, memberId)` 查询所有字段当前值，`verificationInfosByRound(tokenAddress, actionId, memberId, round)` 查询指定 round 的历史快照。

验证信息模板的 keys 和 descriptions 在 Proposal 创建回调时通过可选 `targetData[5] = abi.encode(string[] keys, string[] descriptions)` 传入，后续不可修改；两数组不等长回滚 `VerificationInfoLengthMismatch`。成员提交的验证信息值在加入时写入，项数与模板 keys 不符同样回滚 `VerificationInfoLengthMismatch`，每次修改参与量时可更新。

管理操作要求持有 groupId；自有参与操作要求持有 memberId。同一行动中成员只能归属一个 Group，追加不得改群；换群须先正常退出。`join` 的资产来源由 `providerMemberId` 决定：`0` 表示成员自有代币，非零表示从该 Provider 已存入合约的额度中扣减。同一成员可在同一行动上混合多个来源，重复 `join` 按来源分别追加；`joinInfo`、`amount` 查询、`joinedAmountByMemberId` 与 `totalJoinedAmountByGroupId` 都包含全部来源。`withdraw` 只减少自有账本，`providerWithdraw` 只减少指定 Provider 账本，两者不互相抵扣；成员总参与量（自有 + 全部 Provider）归零时自动退出。`providerWithdraw` 由该 Provider 当前持有人调用，代币始终返还该 Provider 当前持有人；Provider 身份不授予成员 `exit`、额度管理或撤回 Provider 已投入部分的权限。成员调用 `exit` 时结清全部来源：自有资产返还成员，Provider 来源恢复为该 Provider 对该成员的可用额度、不转出合约（Provider 仍可用 `providerQuotaRemove` 取回）。代币量只由 `Joined` 与 `Withdrawn` 承载：`exit` 按来源逐条发出 `Withdrawn`（自有来源为 `0`，每个有余额的 Provider 一条），`Exited` 只表示退出状态、不带金额。无参与记录返回零元组，历史集合无记录返回空数组。

## 当前归属与索引

事实关系为 `tokenAddress + actionId + groupId + memberId`。跨本 Executor 的全部社区与行动维护一小组**由参与事实驱动**的索引（`g*` 记号即指这一族：只有真的有人参与过才会入榜），读取按 [集合读取函数的设计原则](../../migration-standards.md#集合读取函数的设计原则) 收敛，不为每个维度组合维护全量索引：

| 查询 | 语义 |
| --- | --- |
| `isGroupMember(groupId, memberId)` | 该成员当前是否归属该链群（跨全部社区与行动聚合），Group Chat 的链上判据 |
| `gGroupIds` | 当前有归属成员的链群 |
| `gGroupIdsByMemberId` | 某成员当前归属的链群 |
| `gTokenAddressesByGroupIdByMemberId` | 某成员在某链群下的归属涉及哪些社区 |
| `gMemberIds` | 当前有归属的成员 |
| `gMemberIdsByGroupId` | 某链群当前的成员 |

五条 `g*` 都用标准分页 `(offset, limit, reverse) → (列表, 真实总数)`：越界返回空数组与真实总数、不回滚；`limit` 超剩余按剩余返回；`reverse` 从新到旧。`reverse` 只承诺逆序遍历当前存储顺序，不承诺等于插入顺序——集合用 swap-and-pop 删除，同一 `offset` 的返回内容不保证跨调用稳定，调用方不得跨调用缓存 `offset`，也不得按「先拉首页再增量补页」拼接。`isGroupMember` 与 `gTokenAddressesByGroupIdByMemberId` 是同一份存储上的两个读入口：前者是存在性布尔，后者取完整取值。

加入/退出同步维护这些集合与归属计数，不依赖扫描事件；成员在全部社区、全部行动下对同一 `groupId` 的归属计数归零后 `isGroupMember` 才返回假，退出一个行动不影响其他关系。`ActionTarget.forceExit` 不修改这些索引。

## Round 历史

加入阶段每笔加入、追加、部分撤回及退出（含 Provider 额度来源的加入），都更新当轮参与记录。同一 Round 多次操作只保留该轮最终值，不新增多个版本；无人交互的 Round 继承最近历史，不逐轮复制或同步。同一批历史同时给出两条**按轮读取**：`groupIds(tokenAddress, actionId, round, offset, limit, reverse)` 是该轮有参与成员的链群，`memberIdsByGroupId(tokenAddress, actionId, round, groupId, offset, limit, reverse)` 是该轮某链群的成员历史顺序；两者与 `g*` 同用标准分页签名，越界返回空数组与真实总数。

加入结束后不得回写目标 Round。验证直接读取该轮 Group 和成员历史，不需要前置准备交易；验证集合只由目标 Round 历史决定，与验证阶段链群当前的激活状态无关——加入轮结束后停用、恢复或新增链群都不改变该轮验证集合。该轮集合在加入阶段结束后不再写入，因此按 `offset` 连续翻页等价于连续游标；验证按历史成员顺序使用连续游标，不能重复、跳过或乱序。

原存储示意为 `mapping(round => mapping(groupId => mapping(memberId => ParticipationData)))`；外层仍须隔离 token 和 action。沿用旧 RoundHistory 语义：无记录表示继承最近历史，退出通过显式记录零值形成终止点，不能直接删除历史记录。

## 候选与验证

候选只在投票阶段新增、撤销或修改；排序按 `votes` 降序、`applicationId` 升序，平票时较早申请优先。候选只在收到新投票时才按规则进入或更新当前排名；替换或撤销申请时，旧申请从当前排名中移除，其票数只保留供历史查询，不由榜外申请自动补位。

验证者、验证和激励查询接口见 [`IGroupActionExecutor.sol`](../../../interfaces/action/IGroupActionExecutor.sol)。

申请者须持有 memberId 且有该社区有效治理票；比例范围 `0..1e18`；`description` 以字节计不超过 1024，超出回滚 `DescriptionTooLong`。apply 新建或替换当前申请：旧 ID 失效但保留票数，新 ID 单调递增且从零计票。取消只移除当前关联和榜内项，不扫描榜外补位。不存在申请查询回滚；无当前申请 ID 返回 0。申请与撤销以创建轮为作用域（`currentPhase() != createdRound` 回滚 `InvalidRound`）；行动只在其创建轮产出参与与激励，该模型下创建轮即当前投票轮。完整申请记录按轮读取：`verifierApplications` 用标准分页签名直接回该轮全部申请记录与总数。这是本接口唯一直接回含变长字段记录体的分页查询——申请记录带变长 `description`，按集合读取原则本应只回 id 再加按 id 批量，但该查询的消费方只有链下展示，且按 id 批量入口会与它构成同一集合的第二条路径；若日后出现链上调用方，须改为「只回 id + 按 id 批量」。`currentApplicationId` 返回该成员当前关联的申请（无则 0）；`topVerifiers` 按排名顺序返回当前榜上的**完整申请记录**——榜的容量是前 `n + 1`（有界），元素与成员一一对应（每个成员至多一个当前申请），记录里已含 `memberId`、`applicationId`、`description`、`ratioForPublicVerifier` 与 `votes`，读取方一次调用即可拿到名单及其票数、比例与说明。其余索引与列表查询按标准分页语义越界返回空数组与真实总数、不回滚。

投票 Target Data 为空表示不指定候选；非空时第 `0` 项为已绑定 Executor（ActionTarget 转发门禁），本 Executor 的业务项从第 `1` 项起：`targetData[1] = abi.encode(uint256 candidateMemberId)`，对应当前有效 applicationId，项数多于 `2` 回滚 `InvalidTargetDataLength`。每次回调将全部治理票增量记给该候选。候选字段为空时不增加候选票，有字段但申请已失效则回滚。排名增量维护，只保存可开放的前 n 名；榜满时榜外候选必须票数严格超过末位才替换，不因修改旧申请自动转移票数。

`submitOriginScores` 仅接受当前验证 Round；调用者持有 verifierMemberId，批次数组非空，每项不超过 100，`startIndex` 等于该群已验证数量且不能超出历史成员数。全部校验成功才锁定和计分；同一成员记录只消费一次。未验证的分数查询返回 `(0, false)`，与已验证零分区分。

原始分与「已验证」标志合并写入同一个存储槽（原始分上限 100，高位作标志位），使每个成员每轮只产生一次新的冷写入；查询接口仍按 `(score, verified)` 返回。每组的轮级累计量用累加器，不按成员二次写。

第 1 名在验证阶段起点开放，后续排名按下式开放：

```text
openOffset = ceil(verifyPhaseBlocks * splits[rank - 2] / 1e18)
openBlock = verifyPhaseStartBlock + openOffset
```

`splits[0]` 对应第 2 名。`block.number >= openBlock` 才开放，不能因取整提前。读取方用 `SPLITS()` 与 `IPhase.phaseInfo(round + 2)` 的 `(startBlock, phaseBlocks)` 自行计算各名次的开放区块；可开放人数为 `SPLITS().length + 1`，第 1 名在验证阶段起点即可提交。

首个有效验证批次永久锁定验证者 MemberNFT；NFT 转移后新持有人续验，不能由未经授权候选接管。需完成目标 Round 的全部 Group 验证；无候选或锁定者失联、未完成时，行动层激励为零，底层 Proposal 激励仍可独立铸造或销毁。`generatedActionRewardByGroupId` 与一切行动层分配查询按轮次读取，目标轮未完成验证时返回 0，不因部分批次已计入而返回正值；GroupService 与 GroupAction 阶段划分相同，其读取的轮次已经完成验证，正常不会命中该分支。相关验收见 [组织验收](../../acceptance.md#公共验证者与-round-历史)。

## 行动激励

公共验证者按同一规则记录原始分和最终分。每条冻结成员记录只计入一次，不允许对同一份参与量重复评分。

```text
finalScore(memberId) = participationAmount(memberId) * originScore(memberId)
totalFinalScore = sum(finalScore across all groups)
memberReward(memberId) = floor(proposalReward * finalScore(memberId) / totalFinalScore)
```

所有 Group 使用同一原始得分和最终得分规则；按目标 Round 已确认参与数据汇总全行动的 `totalFinalScore` 后直接分配。`totalFinalScore` 为零时不除零，行动层激励为零；群 owner 的聚合份额由其成员最终激励之和得到，不在 Group 内再次按比例分配。

Executor 先按 [统一铸造链路](07-minting.md#铸造链路) 取得整笔激励，再内部分配。

## 实现约束

- 退出零值与无记录继续使用旧 RoundHistory 的显式记录语义；不得通过清空 mapping 伪造退出。
- `candidateCount = n` 表示最大可开放排名数，不是本轮总申请人数；`n = splits.length + 1`。分割线严格递增且在 `(0, 1e18)` 内，空数组只开放第 1 名。投票结束后排名自然冻结，不增加冻结交易。
- 候选竞选是 BSC 新逻辑；旧 `LOVE20TKM/extension-group/src/GroupVerify.sol` 的 `submitOriginScores` 仅作为连续批次和原始分校验的参考，不是候选机制来源。
- 链群未激活的错误落点：`deactivateGroup`、`updateGroupInfo` 回滚 `GroupNotActive`；`join`、`providerQuotaAdd` 回滚 `CannotJoinInactiveGroup`。验证路径不检查链群当前激活状态。
- Provider 额度的授予、调整与枚举见 [共同模型](03-participation.md#provider-额度接口)；额度授予即存入合约，`join` 只按使用量扣减额度、不再转移代币。
- 三个协议级上界是**编译期常量**，不进 `init`、不设 getter：原始分上限 100、单个验证批次项数上限 100、描述字段 1024 字节（`DescriptionTooLong`）。它们对所有部署、所有社区、所有行动一致，属协议语义的一部分；本协议没有管理员身份（`init` 不保存部署者、不授予特权），做成配置项同样写入即不可改，只会增加部署参数与错配面。
- 代币量只由 `Joined` 与 `Withdrawn` 记录：`Joined` 带 `amount` 与来源键 `providerMemberId`，`Withdrawn` 带 `amount` 与来源键，`Exited` 不带金额。

## 部署体积与拆分

Executor 是单例，全部逻辑落在一个地址上会超过 EIP-170 的 24,576 字节上限（旧实现实测 39,241 字节），因此把实现体拆进 `action/src/` 的 `public` 库、按业务模块各成一个库，经 delegatecall 执行；部署地址、ABI 与状态都不变。

**状态只有一份，由一个根 Layout 承载。** 全部状态收进 `GroupActionStorage.Layout` 一个 struct，Executor 只声明 `GroupActionStorage.Layout internal s`；库函数一律只收一个 `GroupActionStorage.Layout storage s` 加业务参数。状态变量增减只改 Layout，不改任何库的函数签名；多个库共享同一个 Layout，天然读写同一份存储，不出现「这个库要传哪几个变量」的问题。

**库按业务模块划分**，一个业务一个库、一个库一个接口文件，不按调用热度：

| 库 | 接口文件 | 对应旧文件 | 内容 |
| --- | --- | --- | --- |
| `GroupActionVerify` | `IGroupActionVerify.sol`（`is IVerificationInfo`） | `GroupVerify.sol` | 验证提交与连续游标、原始分与「已验证」标志合槽写入、`finalScore`/`totalFinalScore` 汇总、验证者申请/撤销与排名查询、验证信息查询、投票回调的候选记账 |
| `GroupActionJoin` | `IGroupActionJoin.sol` | `GroupJoin.sol` | `join`、`withdraw`、`exit`、Provider 额度六件、Round 历史读写、参与索引与归属计数维护、成员验证信息值写入、`joinInfo`、`totalJoinedAmountByGroupId` |
| `GroupActionManager` | `IGroupActionManager.sol` | `GroupManager.sol` | `activateGroup`、`deactivateGroup`、`updateGroupInfo`、`groupInfo`，以及创建回调写入行动配置、验证信息模板与创建轮；推举回调当前只校验调用者，无状态写入 |

成员级激励铸造不单独成库：它只有约 1.6KB，且成员结算三件（`mintMemberReward`/`mintMemberRewards`/`memberReward`）声明在基座 `IActionExecutor`，留在 Executor 实现即可，也省掉每笔结算的跨库开销。

`IGroupActionExecutor` 自身声明 Executor 本地实现的成员（依赖 getter、`init`、`currentVerifyRound`、`generatedActionRewardByGroupId` 与成员结算四件）、包不进行动配置与创建回调的错误，其余全部经上表三个模块接口继承；`GroupConfig` 声明在 `IGroupActionManager.sol`，`VerifierApplication` 声明在 `IGroupActionVerify.sol`。

**库不能继承接口**（Solidity 不允许），所以「接口文件 ↔ 库」是**声明归属的映射**，编译期唯一强制的契约是 Executor 继承全部接口、其包装函数再调用对应库：接口签名漂移在 Executor 编译不过，库侧签名漂移则在该调用点编译不过。

**库之间不互相调用**：跨模块共享的状态通过同一个根 Layout 直接读写（创建回调写验证信息模板、验证写分数、分配读分数），不引入库到库的跳转，也没有循环依赖。

**除业务库之外留在 Executor 的两类**：一是**会被其他合约链上调用的接口**——`IGroupActionIndexes` 的查询（Group Chat 链上读 `isGroupMember`；五条 `g*` 分页查询随业务库走）、`generatedActionRewardByGroupId`（Group Service 读取）、`needBurnReward`（ActionTarget 销毁判据）与基座 `IActionExecutor` 的 Round、参与量查询：这类函数本身很便宜，跨库会让一次读取的固定开销（约 2,600 gas 冷访问）翻倍；只被钱包与前端读取的查询走 `eth_call`、不计 gas，随业务库走。二是**成员级激励铸造**（见上表下方说明）。

「留在 Executor」指**实现**留在 Executor：写成转发库的薄壳没有意义，仍要付跨库开销。

两条硬规则：库调用不得出现在循环体内——成员批量结算与验证批次的循环必须整体位于同一侧，不得按元素跨库；库只承载逻辑，不声明状态变量。

验证是本协议 gas 占比最高的路径（每轮、每群、每成员都要写一次分数），优化优先级高于其余部分：每个成员每轮只允许一次新的冷写入（分数与标志合槽），批次内其余状态用轮级累加器；跨库跳转只落在冷路径上，一次批量提交的跨库开销相对批量本身可忽略。

部署脚本按「先部署各库、再链接部署 Executor」执行，库地址与链接关系记入 `script/network/<net>/`；`forge build --sizes` 的 24,576 上限纳入实现门禁。实现对账时按库分别核对 runtime 上限，任一库超限则继续按业务边界细分。

验收见 [Action 验收](08-testing.md)。
