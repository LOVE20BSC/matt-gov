# LOVE20BSC 领域上下文

本文件只维护跨仓库共享的领域术语和关系。合约接口、公式、KV 编码、部署参数和代码库内验收场景以对应代码库规格为准；代码库创建前以 `docs/specs/` 中的对应规格为准。迁移票据只保存决策过程和来源证据，不是当前规范。

**术语约定**：BSC 版中文继续使用“激励”和“铸造激励”，英文合约、接口和状态统一使用 `Reward` 及其派生名称。`Reward` 表示协议按规则准备的激励额度，可被预留、铸造、分配或销毁，不仅指已经到账的金额。

## 参与主体

- **MemberNFT**：BSC 版统一的业务参与主体。`memberId` 是主体身份，钱包地址只是当前控制者或交易调用者；除明确的技术性特殊情况外，业务不以裸地址作为主体。
- **成员与治理状态**：治理质押、解锁状态和治理权归属于 `memberId`。转移 MemberNFT 只改变当前控制者，不改变主体身份、历史记录或既有归属。
- **链群主体**：链群使用 MemberNFT 作为主体，以 `groupId` 作为业务标识；不存在第二套 GroupNFT 身份。链群 owner 指该链群 MemberNFT，不是钱包地址。
- **质押类型**：流动性质押产生治理权；加速质押不单独产生治理资格，只参与治理激励分配。两类质押可以同时存在，并共享解锁生命周期。
- **历史与铸造激励**：按 `memberId` 记录的未铸造治理激励，只能由当前 `MemberNFT` 持有人触发铸造；Proposal/行动激励由对应的 Proposal Target 或行动 Executor 按授权流程铸造。NFT 转移不回写历史投票、快照、已结算激励或事件。

## 质押与发射

- **治理质押账本**：BSC 版不使用独立的 SL/ST 质押凭证；质押份额和可赎回状态属于核心 `Stake` 账本。
- **统一解锁**：流动性质押和加速质押不能分别解锁；等待期按底层 `Phase` 时间片理解，不使用上层业务 `Round` 计数。
- **质押融合**：按 `tokenAddress` 社区隔离，只处理尚未使用的当前质押状态；已发生的治理、投票和激励历史仍归原 `memberId`。
- **发射次数**：发射权直接记录在 `tokenAddress + memberId` 的 `launchCount` 账本中，并保留未消耗的累计发射额度 `launchCredit`；每次治理激励实际铸造后，按本次铸造前剩余供应量计算并向上取整阈值，达到完整阈值就增加整数次数并扣除对应额度，余数继续累计。每个代币社区累计最多 `X` 次，达到上限后不再新增次数，发射时消耗次数。`X` 为协议初始化的每社区上限。
- **发射次数融合**：同一代币社区内，源 MemberNFT 可向目标 MemberNFT 原子转移部分整数次数；调用者只需控制来源 MemberNFT，不要求控制目标 MemberNFT，且不能跨社区或回写历史发射记录。它与质押融合是两个独立操作。
- **发射分配**：发射者必须指定非零的首批代币 `distributor`；中心化或去中心化只描述 `distributor` 后续分配方式，不是发射调用权限。零地址不表示销毁或丢弃。

## Phase 与 Round

- **Phase**：底层时间线中的无语义时间片，不命名投票、行动、验证或铸币阶段，也不定义业务轮次。
- **Round**：上层业务将 Phase 组合后形成的轮次编号，从 `1` 开始；不同层的同名或同号 Round 不表示相等。
- **ActionRound**：`action` 层统一使用的四阶段轮次。当前 `Phase = p` 时，铸币、验证、加入、投票阶段当前对应的 Round 分别为 `p-3`、`p-2`、`p-1`、`p`；结果小于 `1` 表示该阶段对应的轮次尚未开始，查询回滚而不返回 `0`。加入阶段包括行动参与、加入、退出和资产状态变化。链群行动、链群服务行动和 LP 行动共享轮次，链群服务和 LP 的验证阶段为空操作。是否满足铸币条件仍由具体执行合约判断。
- **治理 Round**：核心 `Submit` 和 `Vote` 把 `Phase N` 解释为治理 `Round N`；该 Phase 结束后，Round N 的核心激励可以准备和铸造。

## Proposal 与 Target

- **Proposal**：底层治理对象，由 `Submit` 创建、由 `Submit` 推举、由 `Vote` 表决、由 `Mint` 铸造提案激励。Proposal 的标准头部/主体命名为 `ProposalHead` / `ProposalBody`，分别替代旧 `ActionHead` / `ActionBody`；头部至少包含 `id`、`author`、`createAtBlock`，主体至少包含 `title`、`details`；创建者字段使用旧代码命名 `author`，但 BSC 值记录创建 Proposal 的 MemberNFT/memberId，不再以地址作为业务主体。
- **Proposal Target**：Proposal 的激励铸造接收主体。Target 可以是普通地址或合约；合约型 Target 是否接收回调由 `targetMode` 决定。代币由协议按规则铸造，不表述为某人发放代币。
- **ActionTarget**：当前社群行动提案类型的 Proposal Target。它把 Proposal 与行动执行合约关联，并提供该提案类型的通用参与登记和应急清理边界。
- **行动执行合约**：由 `ActionTarget` 关联的业务合约，负责具体行动的参与、验证、资产处理和行动层激励分配。`executor` 不属于底层治理框架的通用业务角色。
- **链群参与归属**：链群行动执行合约以 `tokenAddress + actionId + groupId + memberId` 的当前有效关系为事实来源，维护跨其所有代币社区和行动的 17 组可枚举 `g*` 全局索引；每组提供全量数组、`Count` 和 `AtIndex` 查询。链群 Chat 通过 `gTokenAddressesByGroupIdByMemberIdCount(groupId, memberId) > 0` 判断归属；ActionTarget 的强制退出不修改这些业务索引。
- **proposalId 与 actionId**：`proposalId` 是所有 Proposal 的统一 ID；只有部分行动类 Proposal 使用 `actionId` 作为业务别名，二者数值完全相同，`actionId` 是 `proposalId` 的子集，不创建第二个 ID。
- **回调与 KV**：Proposal 创建、提案推举和提案投票分别触发对应 Target 回调；回调名称为 `onProposalCreated`、`onProposalSubmitted`、`onProposalVoted`；推举回调使用 `submitterId`，投票回调使用 `voterId` 和本次增量票数；核心只传递标准 Proposal 上下文和不透明 KV，不解释提案扩展业务；具体字段由对应 Target 或行动执行合约定义。

## 架构与仓库关系

- **核心治理层**：`core` 提供 `Stake`、`Submit`、`Vote`、`Mint`、`MemberNFT`、`Phase` 和基础子币发射能力（包括发射次数账本、次数融合/消耗和子币创建）等通用能力。核心治理激励不依赖具体提案扩展的业务结果。
- **提案扩展层**：按 Proposal 类型实现 Target。当前社群行动类型由 `action` 代码库维护，包含由旧 `extension-lp` V2 重写而来的 LP 行动执行合约、链群行动执行合约和链群服务行动执行合约；其内部是否拆分执行器、验证器或分配器属于该业务自身。
- **发射分配层**：公平发射后的复杂分配机制本阶段不创建 `launch` 代码库；未来需求明确后再作为独立扩展建立，不影响 `core` 的发射基础能力。
- **群聊边界**：`group-chat` 独立维护群聊业务，其中的权限委托统一称为 **Group Chat Delegate**，只在该代码库内生效，不进入核心身份、行动或发射权限模型。
- **配套仓库**：`compatibility` 专门验证外部 WBNB/WETH9 与 Uniswap V2 兼容的 PancakeSwap 依赖的接口和实际行为；`periphery`、`script`、`love20-anvil`、`interface-test`、`interface`、`batch-transfer` 和 `docs` 是外围、部署、集成测试、前端或文档仓库，不改变核心领域关系。`compatibility` 不属于任何生产合约的运行时依赖。
