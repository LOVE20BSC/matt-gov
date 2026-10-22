# Group Chat 验收

本表是实现必须覆盖的最小场景，运行证据按 [组织验收](../../acceptance.md) 记录。

| 范围 | 场景 | 预期 |
| --- | --- | --- |
| 核心 | 一 NFT 一 Chat、激活、转移 | owner 实时变化，历史不回写 |
| 身份 | 默认映射、地址发言、地址黑名单/投票 | ABI、状态、索引和专属事件完全删除，不仅是运行时拒绝 |
| 身份 | 缺失成员/管理员/delegate | post 缺失 senderId → `ERC721NonexistentToken`；非 owner → `SenderNotMemberOwner`；delegate 写入口/`setDelegateId` 目标缺失 delegateId → `ERC721NonexistentToken`；非 owner → `SenderNotDelegateOwner`；`GroupMember`/`GroupAdmin` 缺失成员/管理员 → `ERC721NonexistentToken`；delegate 查询缺失 delegate → false/0/空；GovVoted voter 非 owner → `NotMemberOwner(voterId)`；缺失群仍 `GroupNotExist` |
| Delegate | 设置、撤销、快照失效/恢复 | 只管理 Chat，不冒充 sender |
| 发言 | 鉴权先于群状态、scope/ban、before/after | 非持有人先回鉴权错误；before 回滚，after 失败保留消息 |
| 消息 | 提及、mentionAll、引用、ID | 规则和索引一致 |
| 查询 | Round、sender、mention、分页 | 空值、越界和 reverse 符合最终 ABI |
| 查询 | Phase 重新标定后的历史消息 Round | 旧消息 round 与分轮索引不变，新帖按新参数计算（`testT050B`） |
| 类型 | 五类资格和黑名单权重 | 使用对应 memberId 和快照来源 |
| 群组 | 成员名单、Executor 归属、forceExit | 最后关系退出才失去归属，forceExit 不改归属 |
| Manager | 激活付款、费用不一致、NFT 接收、重复激活 | 调用者支付，Manager 持有；失败整体回滚；一个 Manager 管理多个 Chat |
| Manager | 转出 NFT、approve、重配、付费者接管 | 不新增这些入口，普通 owner Chat 不受此限制 |
| 群内委托 | 管理管理员、成员、人工黑名单；调用 Core/Action/Launch | 保留原群内权限，但委托不能授权任何群外业务 |
| 黑名单 | 当前行动 Vote Round、全社区分母、权重归零刷新 | 不使用创建 Round；保留 settledWeight、改票/撤票/刷新与 stateVersion |
| 黑名单 | 管理员身份不绕过封禁 | admin 的成员 NFT 被 ban 后发言回 `BanRejected`；以群 NFT 发言仍可（`testT121B`） |
| 持币 | 首币余额 0、1、2 个最小单位 | 0 不满足持币分支，1、2 满足；其他资格分支照常 |

以 [源码基线](README.md#已核对来源) 做保留行为的差异回归；身份映射与已确认 BSC 依赖是唯一允许差异。旧测试因调用 ABI 变化而适配，不重新定义支付、消息、分页或失败处理。上表由 `group-chat` 的 `forge test` 套件覆盖，链上运行证据按 [组织验收](../../acceptance.md) 记录。
