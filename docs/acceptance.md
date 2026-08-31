# LOVE20BSC 跨仓库验收标准

本文件只记录组织级验收维度和证据要求；具体命令由各仓库 `README.md` 提供。

## 验收维度

- **可启动**：按各仓库 README 的前置条件和命令，能在干净工作区启动或运行。
- **可定位**：新人和 AI 能从 README、`AGENTS.md`、`CONTEXT.md`（如有）定位核心模块、入口和测试。
- **可集成**：`love20-anvil` 能按部署脚本启动本地链，并完成核心仓库与业务仓库的最小集成路径。
- **可发布**：地址、ABI、网络配置和前端环境变量来源明确；`interface-test` 验收后才能同步到 `interface`。
- **可自审**：负责 agent 在提交前完成第二遍自审，至少检查 diff、测试结果、跨仓库接口和文档同步；不要求外部 reviewer 才能通过。
- **无遗留**：代码、脚本、依赖和文档中不保留本次协议已删除或移出范围的旧组件，除非迁移票据明确标记为历史说明。
- **历史命名隔离**：迁移票据中的旧名称、旧 ABI 和旧实现事实必须明确标为历史讨论；实现只引用票据 `Answer`、地图决策和当前 `CONTEXT.md`。
- **可追溯**：每项通过或失败都有命令、提交、日志或截图等最小证据，并能关联到对应仓库和提交。
- **Proposal 激励闭环**：覆盖投票阶段结束前后准备、准备只写轮次级总状态且不逐个预写 Proposal、重复准备不改写、非 Target 铸造拒绝、各 Proposal Target 按冻结状态单独计算并铸造且单 Proposal 只能成功一次、行动类 `ActionTarget -> Mint -> executor` 转发，以及铸造失败整笔回滚。
- **LP 行动执行合约**：覆盖旧 `extension-lp` V2 业务在 `action` 中的重写路径，包括 MemberNFT 参与、部分撤回、LP 手续费结算、行动激励铸造和失败回滚；不验收或迁移 V1 LP 实现。
- **行动公式零值边界**：覆盖 LP 时间扣减封顶、`totalEffectiveAmount`/`totalGovVotes` 为零、链群 `totalVotes`/`totalGroupScore`/`groupScore` 为零时不除零且行动层激励为零，并验证底层 Proposal 激励仍可独立处理。
- **治理融合与激励铸造**：覆盖调用者只控制来源 MemberNFT 时，可以把指定社区的治理质押单向融合进他人持有的有效目标 MemberNFT；目标既有资产不能减少。覆盖同一成员单轮铸造、显式 Round 数组的批量多轮铸造、逐轮三类结果和任一 Round 失败时整笔回滚。
- **MemberNFT 发射次数边界**：覆盖本次铸造前剩余供应量的阈值向上取整、治理激励累计进入 `launchCredit`、一次治理激励跨过多个完整阈值、整数除法余数继续累计、每个社区达到 `maxLaunchCount = X` 后停止新增次数、调用者只控制来源 MemberNFT 时向他人持有的目标 MemberNFT 部分融合整数次数但不转移 `launchCredit`、源次数扣减/目标次数增加的原子性，以及次数消耗后不能再次发射。
- **子币发射分发边界**：覆盖非零 `distributor`、`RewardOnly`/`Callback` 两种分配模式、KV 长度校验、回调失败回滚、首次代币使用 Airdrop 目标，以及保留代币没有本地发射次数。
- **MemberNFT 转移归属**：覆盖转移前后质押、解锁倒计时、治理激励和行动内部未铸造激励均由当前持有人继续操作；旧持有人不能代铸，历史投票、快照、已结算激励和事件不回写。
- **MemberNFT 铸造和统计**：覆盖 `LOVE20 Member NFT`/`Member` 元数据、从 `1` 开始且不复用的 ID、名称 `32 bytes` 上限、UTF-8 与不可见字符校验、ASCII 大小写不敏感唯一性、短名称费用和原子销毁，以及标准 ERC721Enumerable 查询和自转账不会破坏可选的持有人统计。
- **Group Chat MemberNFT 主体**：覆盖四类 typed Manager、普通 owner 管理型 Chat、规则槽位、插件、消息与分页行为；覆盖成员、管理员、委托、发言、提及、黑名单目标和黑名单投票者均按 `memberId` 运行，并确认不存在默认 MemberNFT 映射、默认身份发言入口、地址黑名单/投票/查询或其他地址主体接口。治理黑名单覆盖代币治理票与行动 Proposal 投票两类票权、全社区治理票分母、支持票严格超过反对票 `10` 倍且达到 `0.3%` 的双阈值、撤票和任何人刷新。链群 Chat 覆盖纯成员名单和“成员名单或链群 Executor 当前归属”标准资格源，验证归属查询跨该 Executor 服务的所有社区和行动、最后一次正常退出使资格失效，并确认 ActionTarget 的 `forceExit` 不修改 Executor 的链群归属。owner 快照及消息/事件调用地址只用于 NFT 转移有效性和审计，不得成为业务主体。
- **Target 组合与幂等性**：覆盖 `RewardOnly`/`Callback` 与 EOA/合约的合法组合、Callback + EOA 拒绝、缺少 executor 保留项的行动创建 KV 拒绝、仅 executor 项可创建，以及同一 `tokenAddress + proposalId` 重复创建回调回滚。
- **ActionTarget / Executor 状态边界**：覆盖仅关联 Executor 可登记/正常清除、当前 MemberNFT 持有人可 `forceExit`、强制退出后 ActionTarget 当前参与查询清除而 Executor 资产及链群归属状态不回写，以及不通过旧 Executor 状态自动恢复登记。
- **Proposal Target 回调**：覆盖 Proposal 创建、提案推举、提案投票三类回调；覆盖 `submitterId`、`voterId`、增量票和 KV 透传，以及回调失败时对应外层交易整体回滚。
- **公共验证者失联**：覆盖首个验证批次永久锁定后验证者停止提交时，本轮行动层激励保持为 `0`，底层 Proposal 激励仍可按规则铸造或销毁，且不允许未经授权的其他候选人接管。
- **Phase 与候选边界**：覆盖每轮起始区块和阶段区块数历史记录、最近观测点的 `±10%` 动态校准及历史不可回写；覆盖无候选人、候选票为零、平票按 `applicationId` 排序、申请版本切换、排名锁定、分割线按排名映射、开放区块向上取整和阈值区块包含判断。
- **ActionRound 统一性**：覆盖 `Phase 1..3` 对尚未开始槽位回滚且不返回 `0`、`Phase 4` 首次形成四个有效槽位，以及 LP、链群行动和链群服务行动共用 `Vote`/`Join`/`Verify`/`Mint` 四个时间槽位；链群服务和 LP 的 `Verify` 为空操作但仍使用统一轮次，且各执行合约独立判断 `canMint`。
- **LP 兼容性**：覆盖目标 PancakeSwap Factory/Pair/Router 在 `Stake` 场景下的 LP 份额、手续费结算、兑换报价、储备更新和失败回滚；不得仅以 ABI 可编译作为兼容性结论。
- **外部依赖兼容性**：`compatibility` 必须分别对本地 Uniswap V2/WETH9 参考实现和目标网络 WBNB、PancakeSwap Factory/Pair/Router 执行测试，覆盖接口返回值、Pair 创建和 LP 铸造/销毁、Swap 手续费与储备变化、Router 报价和实际输出、Token 顺序、失败回滚及协议计算所需的 `sqrt(k)` 数据；测试记录目标链、合约地址、区块高度和提交，任何未验证的外部地址不得进入 BSC 部署配置。

## 证据记录

每次 BSC 发布或候选发布，在本文件追加一条记录，至少包含：日期、目标网络、涉及仓库和提交、执行命令、结果、失败项及后续处理票据。
