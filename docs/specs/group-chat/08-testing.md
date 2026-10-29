# Group Chat 验收

本表是实现必须覆盖的最小场景，运行证据按 [组织验收](../../acceptance.md) 记录。

| 范围 | 场景 | 预期 |
| --- | --- | --- |
| 核心 | 一 NFT 一 Chat、激活、转移 | owner 实时变化，历史不回写 |
| 身份 | 默认映射、地址发言、地址黑名单/投票 | ABI、状态、索引和专属事件完全删除，不仅是运行时拒绝 |
| 身份 | 缺失成员/管理员/delegate | post 缺失 senderId → `ERC721NonexistentToken`；非 owner → `NotMemberOwner(senderId)`；delegate 写入口/`setDelegateId` 目标缺失 delegateId → `ERC721NonexistentToken`；非 owner → `NotMemberOwner(delegateId)`；`GroupMember`/`GroupAdmin` 缺失成员/管理员 → `ERC721NonexistentToken`；delegate 查询缺失 delegate → false/0/空；GovVoted voter 非 owner → `NotMemberOwner(voterId)`；缺失群 → `GroupNotExist(groupId)` |
| 身份 | 群权限、重复 ID、delegate 自指 | 群 owner 非 owner → `NotGroupOwner(groupId)`；owner/delegate/admin 复合鉴权 → `NotGroupOperator(groupId, operatorId)`；数组内重复成员 → `DuplicateMemberId(memberId)`；`delegateId == groupId` → `DelegateIsSelfGroup(groupId)`；接受开关关闭的目标 → `DelegateNotAcceptingNewDelegations(delegateId)`，且先校验自指/存在/开关再判断幂等 |
| Delegate | 设置、撤销、快照失效/恢复 | 只管理 Chat，不冒充 sender；接受开关默认关闭、只约束新指定，关闭后既有委托继续生效，撤销永远允许；开关按 memberId 继承、不随 delegate NFT 转移变化（新持有人可开关，旧持有人不可），转移后重新设回仍要求开关为开；委托因 delegate NFT 转移失效后再清空，`prevDelegateId` 与两个 `prev*Snapshot` 同取原始值，`delegatedGroupIds` 的移除可重建；`isDelegationAcceptanceEnabled` 缺失 delegate 返回 false |
| 发言 | 鉴权先于群状态、scope/ban、before/after | 非持有人先回鉴权错误；未激活的合法持有者回 `ChatNotActivated(groupId)`；scope/ban 拒绝回带 `groupId`/`senderId`/`source` 的 `ScopeRejected`/`BanRejected`；源失败回带 `groupId`/`source` 的 `ScopeSourceFailed`/`BanSourceFailed`；before 回滚，after 失败保留消息并发出 `errorHash`/`errorLength`/`errorSelector`，重入的内部失败 `Reentrant` 由该 selector 断言 |
| 消息 | 提及、mentionAll、引用、ID | 规则和索引一致 |
| 查询 | Round、sender、mention、分页 | 空值、越界和 reverse 符合最终 ABI；单条缺失消息回 `MessageNotFound(groupId, messageId)` |
| 预检查 | `canPost` 原因枚举 | 返回 `PostRejectionReason`，缺失 sender 为 `SenderNotExist`，不以 selector 作数据 |
| 部署期 | 构造参数与依赖绑定 | 依赖有代码、`Phase.ORIGIN_PHASE_BLOCKS() > 0`、`MAX_NAME_LENGTH` 名称空间下限（广播前按「当前最长类型码 2 字节 + 9」预检 11，`testT181` 锁定该假设与四个 Manager 的实际 `TYPE_CODE()` 一致）、参数范围、MemberNFT 根代币与 `LOVE20_TOKEN_ADDRESS` 一致、`ActionTarget` 根绑定及 submit/vote/stake/launch 与 core 一致，均由部署脚本广播前校验；`21_check.sh` 部署后按各 Manager 的 `TYPE_CODE()` 复核名称空间及其余绑定，失败时一键入口回滚地址文件；广播前校验失败则不广播 |
| 查询 | Phase 重新标定后的历史消息 Round | 旧消息 round 与分轮索引不变，新帖按新参数计算（`testT050B`） |
| 类型 | 五类资格和黑名单权重 | 使用对应 memberId 和快照来源 |
| 群组 | 成员名单、Executor 归属、forceClearJoinState | 最后关系退出才失去归属；forceClearJoinState 只清 ActionTarget 注册表，不改群归属与 Executor 仓位 |
| Manager | 激活付款、费用不一致、NFT 接收、重复激活 | 调用者支付，Manager 持有；失败整体回滚；一个 Manager 管理多个 Chat；构造参数与依赖由部署脚本校验，合约不检查 |
| Manager | 转出 NFT、approve、重配、付费者接管 | 不新增这些入口，普通 owner Chat 不受此限制 |
| 群内委托 | 管理管理员、成员、人工黑名单；调用 Core/Action/Launch | 保留原群内权限，但委托不能授权任何群外业务 |
| 黑名单 | 当前行动 Vote Round、全社区分母、权重归零刷新 | 不使用创建 Round；保留 settledWeight、改票/撤票/刷新；未翻名单时只有投票事件 |
| 黑名单 | 社区权重按当前 Round 读取 | 两类 token Manager 与两类 action Manager 的 `voteWeightOf` / `totalVoteWeight` 都取 `IPhase.currentPhase()` 对应的票权，不取行动总票数或创建 Round；Manager 的 `PHASE_ADDRESS` 在构造时从 `IStake.phaseAddress()` 派生，`21_check.sh` 复核 `Stake.phaseAddress == PHASE_ADDRESS` |
| 黑名单 | 管理员身份不绕过封禁 | admin 的成员 NFT 被 ban 后发言回 `BanRejected(groupId, senderId, source)`；以群 NFT 发言仍可（`testT121B`） |
| 持币 | 首币余额 0、1、2 个最小单位 | 0 不满足持币分支，1、2 满足；其他资格分支照常 |

以 [源码基线](README.md#已核对来源) 做保留行为的差异回归；身份映射、已确认 BSC 依赖、托管群命名 v2（[Manager](06-manager.md)）和构造校验分层（dev-standards §5.7）是允许差异。旧测试因调用 ABI 变化而适配，不重新定义支付、消息、分页或失败处理。`forge test` 覆盖运行期行为；部署期静态校验由 `DeployGroupChat.t.sol` 与 `deploy_scripts_test.py` 覆盖；链上运行证据按 [组织验收](../../acceptance.md) 记录。
