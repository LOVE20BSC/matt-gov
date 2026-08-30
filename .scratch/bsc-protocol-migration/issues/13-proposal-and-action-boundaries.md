# 提案、提案执行与行动扩展边界

Type: grilling
Status: resolved
Blocked by: 12

## Question

将底层治理对象从 `Action` 区分为 `Proposal`，明确提案激励铸造接收主体、创建/推举/投票 KV 与回调条件，并划定按提案类型实现的 `Target` 命名边界。

## Comments

> 本节保留了历史讨论和被后续决议替换的名称；实现只以本票据 `Answer` 为准。

用户确认：底层治理对象应称为提案。每个提案必须记录一个提案激励铸造接收主体，但不要求该地址是执行合约；Proposal 创建、提案推举和提案投票都支持对应的 Target 回调，只有目标是合约且 `targetMode = Callback` 时才触发。

用户确认：行动类提案统一使用 `ActionTarget` 作为 Proposal Target。创建 Proposal 时，`ActionTarget` 通过创建 KV 建立 `proposalId` 与具体行动执行合约的关联并完成创建回调；`actionId` 只是行动类 Proposal 对其 `proposalId` 的业务别名，数值完全相同。

用户修订：不拆分提案激励接收地址和回调地址。Proposal 使用单一 `target` 地址和 `targetMode` 模式（`RewardOnly` 或 `Callback`）；行动类提案使用 `ActionTarget + Callback`。

用户确认：`verificationKeys`、`verificationKeyGuides` 等行动专属信息放入 Proposal 创建 KV；`ActionTarget` 只负责转发，具体行动执行合约自行保存、解释和使用。底层 `details` 在行动框架中解释为 `verificationRule`。

用户确认：`ActionTarget` 与行动执行合约都支持底层治理框架的 Proposal 创建、推举和投票回调；行动执行合约的“初始化”就是 Proposal 创建回调，核心先回调 `ActionTarget`，再由 `ActionTarget` 向执行合约转发标准上下文与不透明 KV。

用户确认：`title` 是底层 Proposal 的通用字段；行动执行合约通过 `proposalId` 查询 `title` 和 `details`，行动创建 KV 不重复传递 `title`。创建时 `title` 必须非空，`details` 可以为空。

用户确认：`ActionTarget` 通过保留键 `keccak256("executor")` 解析执行合约地址，值按 `abi.encode(executorAddress)` 编码；其余 KV 由行动执行合约自行定义。创建 KV 第 `0` 项固定为该保留项，读取后完整转发，不重新分配数组。

用户确认：Proposal 激励准备参照旧版 `Mint`/行动激励逻辑，只准备并冻结当轮总激励；不逐个预写所有 Proposal 的额度。之后每个 Proposal 由自己的 Proposal Target 按冻结状态单独铸造，且只能成功一次。

用户确认：提案推举由目标代币社区中拥有有效治理权的 MemberNFT 当前持有人执行；同一 Proposal 在同一治理轮次只能被推举一次，同一推举者在同一轮只能推举一个 Proposal。重复或不满足资格的推举在回调前回滚，不触发 `onProposalSubmitted`。

用户确认：BSC 版 `author`、`submitterId` 和 `voterId` 均记录 MemberNFT 的 `memberId`，不记录裸地址；钱包地址只作为当前控制者和交易调用者。

## Answer

- **Proposal（提案）**：底层治理框架对象，由 `Submit` 创建、由 `Vote` 表决、由 `Mint` 铸造提案激励。标准头部和主体命名为 `ProposalHead` / `ProposalBody`，替代旧 `ActionHead` / `ActionBody`；`ProposalHead` 至少包含 `id`、`author`、`createAtBlock`，`ProposalBody` 至少包含 `title`、`details`；创建者字段使用旧代码命名 `author`，但 BSC 值记录创建 Proposal 的 MemberNFT/memberId，不再以地址作为业务主体；统一 ID 为 `proposalId`。
- **`details`（提案详情）**：底层 Proposal 的通用详情字段；行动框架把它解释为 `verificationRule`，不在行动创建 KV 中重复保存。
- **Proposal 激励准备**：投票阶段结束后，任何地址均可调用 `prepareProposalRewards(tokenAddress, round)` 一次。该调用只按旧版 `Mint` 逻辑准备并冻结 `tokenAddress + round` 的轮次级总激励池，不枚举、不预写每个 `proposalId` 的额度。重复调用不得重算、改写或重复增加预留；未准备或投票阶段尚未结束时不得铸造。每个 Proposal 的额度在其 Target 铸造时按冻结状态单独计算并记录一次性铸造状态。
- **投票阶段边界**：`Mint` 不直接解释 `LOVE20Phase` 的时间片；指定治理轮次是否可准备和铸造，由核心 `Vote` 按治理轮次规则提供唯一判断。
- **提案推举规则**：推举者必须是目标代币社区中拥有有效治理权的 MemberNFT 当前持有人；同一 Proposal 每轮最多一次，同一推举者每轮最多一个 Proposal。校验失败或重复推举均在回调前回滚。
- **ActionTarget 创建边界**：通用 `Callback` 允许空 KV，但行动类 Proposal 的创建 KV 第 `0` 项必须存在且是 `executor` 保留项；`executor` 必须是非零合约地址。只允许 executor 项而无其他行动参数仍可创建，具体校验由执行合约决定。`ActionTarget` 以 `tokenAddress + proposalId` 为唯一主键，同一创建回调重复到达必须回滚；创建回调成功后，该 Proposal 才可在行动业务中使用 `actionId` 别名。
- **`target`（Proposal Target）**：提案激励铸造接收主体，配合 `targetMode` 使用。`RewardOnly` 只接收铸造激励、不触发回调且 KV 必须为空；`Callback` 要求目标是合约并始终触发创建、推举或投票回调，KV 为空时传递空数组。
- **行动类 Proposal**：固定使用 `target = ActionTarget`、`targetMode = Callback`。核心在创建、推举和投票三个时点回调 `ActionTarget`；创建时由其读取 KV 第 `0` 项的 `keccak256("executor")` 并保存 `tokenAddress + proposalId -> executor` 映射，推举和投票时使用该映射转发对应 KV，不重复携带 executor 项。Proposal 不直接指定行动执行合约。
- **回调边界**：核心创建、推举和投票入口只传递标准 Proposal 上下文及不透明 KV，不解析提案扩展业务。三类回调采用[提案回调 ABI 与操作原子性](14-proposal-callback-abi.md)的最小接口；推举回调标准传递 `submitterId`，投票回调标准传递 `voterId` 和治理票增量，任一回调失败都回滚对应外层整笔交易。若创建与推举在同一笔交易完成，固定先执行 `onProposalCreated`，再执行 `onProposalSubmitted`。
- **Action（行动）**：Proposal 扩展层的一种提案类型，`ActionTarget` 是其目标合约。行动执行合约负责具体行动的参与、验证、资产处理和行动层激励分配；这些业务不进入核心治理框架。
- **actionId 别名**：只有部分行动类 Proposal 使用 `actionId`；其值与对应 `proposalId` 完全相同，`actionId` 是 `proposalId` 的子集，不创建第二个 ID，也不做转换。普通 Proposal 不使用 `actionId`。
- **Proposal 激励分配与铸造**：只有一份 Proposal 激励，直接承接旧版 `Mint.actionReward` 的激励池和最低投票资格逻辑。通过门槛的 Proposal 按核心 `Vote` 记录的投票数占比分配，分母只统计合格 Proposal 的投票总数，不依赖 `LOVE20Verify` 或任何提案扩展。未通过门槛的 Proposal 不参与分配，未分配部分按核心激励池既有状态处理。Proposal Target 是唯一的 Mint 铸造接收主体，同一 Proposal 只能成功一次。
- **行动铸造链路**：行动类 Proposal 仅允许关联 `executor` 发起 `ActionTarget` 的铸造入口；`ActionTarget` 以自身身份调用 `Mint`，由 `Mint` 把激励铸给 `ActionTarget` 并返回实际数量，随后在同一笔交易中全部转给 `executor`，由执行合约进行行动业务二次分配。其他地址不能代铸，任一步失败都回滚。公共验证未完成时，链群行动执行合约可以销毁已取得的 Proposal 激励，但不进行行动层分配。
- **查询**：Proposal 激励查询不新增激励枚举或事件索引依赖；先由 `Vote` 返回指定社区和轮次内实际有投票的 Proposal，再按 `tokenAddress + round + proposalId` 查询 `Mint` 激励状态。无投票 Proposal 不在查询集合中。
- **扩展边界**：未来可在核心治理层之上增加其他提案类型的 `Target` 合约，不强行套用 `Action` 命名。
