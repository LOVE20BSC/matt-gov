# LOVE20BSC 领域上下文

协议的公开说明和正式术语见 [LOVE20BSC 协议文档](https://github.com/LOVE20BSC/docs/blob/main/index.md)和[术语表](https://github.com/LOVE20BSC/docs/blob/main/GLOSSARY.md)（本地 `../docs/`）。本文件补充跨仓库领域关系，行为细节查[开发规格](docs/specs/README.md)，迁移票据用于查决策过程和证据。

## 参与主体

- **MemberNFT**：BSC 版统一的业务参与主体。`memberId` 是主体身份，钱包地址只是当前控制者或交易调用者；除明确的技术性特殊情况外，业务不以裸地址作为主体。
- **成员与治理状态**：治理质押、解锁状态和治理权归属于 `memberId`。转移 MemberNFT 只改变当前控制者，不改变主体身份、历史记录或既有归属。
- **链群主体**：链群使用 MemberNFT 作为主体，以 `groupId` 作为业务标识；不存在第二套 GroupNFT 身份。链群 owner 指该链群 MemberNFT，不是钱包地址。
- **质押类型**：流动性质押产生治理权；加速质押不单独产生治理资格，只参与治理激励分配。两类质押可以同时存在，并共享解锁生命周期。
- **历史与铸造激励**：按 `memberId` 记录的未铸造治理激励，只能由当前 `MemberNFT` 持有人触发铸造；Proposal/行动激励由对应的 Proposal Target 或行动 Executor 按授权流程铸造。NFT 转移不回写历史投票、快照、已结算激励或事件。

## 质押与发射

- **治理质押账本**：BSC 版不使用独立的 SL/ST 质押凭证；质押份额和可赎回状态属于核心 `Stake` 账本。
- **治理权与治理票**：治理权（governance power）是流动性质押份额与承诺解锁期的乘积，只统计未申请解锁的仓位，决定每一轮能投出的票数；治理票（votes）是每一轮由治理权决定的可投票数。两者不是同一个词，不用「治理票数」指资格。核心查询口径是成员级 `Stake.govVotes` 与社区级 `Stake.totalGovVotes`，申请解锁当轮起该成员治理权清零。社区总治理权是有效治理权之和，不含已申请解锁、待提取的份额，因此**不等于**流动性质押份额总量。
- **统一解锁**：流动性质押和加速质押不能分别解锁；等待期按底层 `Phase`（阶段）理解，不使用上层业务 `Round` 计数。
- **质押融合**：按 `tokenAddress` 社区隔离；来源 MemberNFT 在当前治理 Round 已推举或投票后不能再融合，上一 Round 的使用不影响下一 Round；已发生的治理、投票和激励历史仍归原 `memberId`。
- **发射次数**：发射权直接记录在 `tokenAddress + memberId` 的 `launchCount` 账本中，并保留未消耗的累计发射额度 `launchCredit`；每次治理激励实际铸造后，按本次铸造前剩余供应量计算并向上取整阈值，达到完整阈值就增加整数次数并扣除对应额度，余数继续累计。每个代币社区累计最多 `X` 次，达到上限后不再新增次数，发射时消耗次数。`X` 为协议初始化的每社区上限。
- **发射次数融合**：同一代币社区内，源 MemberNFT 可向目标 MemberNFT 原子转移部分整数次数；调用者只需控制来源 MemberNFT，不要求控制目标 MemberNFT，且不能跨社区或回写历史发射记录。它与质押融合是两个独立操作。
- **发射分配**：发射者必须指定非零的首批代币 `distributor`；中心化或去中心化只描述 `distributor` 后续分配方式，不是发射调用权限。零地址不表示销毁或丢弃。

## Phase 与 Round

用词见[阶段与轮次词条](https://github.com/LOVE20BSC/docs/blob/main/GLOSSARY.md#phase)。共同的阶段与治理轮规则见 [Core 规格](docs/specs/core/03-phase.md)，行动轮次的阶段安排见 [Action 规格](docs/specs/action/02-phase-model.md)。

## Proposal 与 Target

- **Proposal（提案）** 由 `Submit` 创建和推举，由 `Vote` 表决，由 `Mint` 铸造提案激励。提案正文保存创建者提供的 `creationData`，作者以 MemberNFT 的 `memberId` 标识。详见[推举规格](docs/specs/core/05-submit.md)。
- **Proposal Target**：Proposal 的激励铸造接收主体。Target 可以是普通地址或合约；合约型 Target 是否接收回调由 `targetMode` 决定。代币由协议按规则铸造，不表述为某人发放代币。
- **ActionTarget**：当前社群行动提案类型的 Proposal Target。它把 Proposal 与行动执行合约关联，并提供该提案类型的通用加入/退出状态和应急清理边界。
- **行动执行合约**：由 `ActionTarget` 关联的业务合约，负责具体行动的参与、验证、资产处理和行动激励分配。`executor` 不属于底层治理框架的通用业务角色。
- **GroupAction 参与归属**：GroupAction Executor 以 `tokenAddress + actionId + groupId + memberId` 的当前有效关系为事实来源，跨其所有代币社区和行动维护归属计数；集合读取收敛为 `isGroupMember(groupId, memberId)` 与五条标准分页索引（`joinedGroupIds`、`joinedGroupIdsByMemberId`、`joinedTokenAddressesByGroupIdByMemberId`、`joinedMemberIds`、`joinedMemberIdsByGroupId`），按轮历史另有两读（`groupIdsByRound`、`memberIdsByGroupId`）。Group Chat 通过 `isGroupMember` 判断归属；ActionTarget 的强制退出不修改这些业务索引。
- **proposalId 与 actionId**：`proposalId` 是所有 Proposal 的统一 ID；只有部分行动类 Proposal 使用 `actionId` 作为业务别名，二者数值完全相同，`actionId` 是 `proposalId` 的子集，不创建第二个 ID。
- **回调数据** 由接收回调的合约定义业务格式。创建、推举和投票分别传入自己的数据，首次推举也使用本次推举提供的数据。[Core 回调约定](docs/specs/core/01-common-rules.md#回调接口) · [ActionTarget 的 Executor 编码](docs/specs/action/01-action-target.md#创建与回调)

## 架构与仓库关系

- **核心治理层**：`core` 提供 `Stake`、`Submit`、`Vote`、`Mint`、`MemberNFT`、`Phase` 和基础子币发射能力（包括发射次数账本、次数融合/消耗和子币创建）等通用能力。核心治理激励不依赖具体提案扩展的业务结果。
- **提案扩展层**：按 Proposal 类型实现 Target。当前社群行动类型由 `action` 代码库维护，包含由旧 `LOVE20TKM/extension-lp` V2 重写而来的 LP Executor、GroupAction Executor 和 GroupService Executor；其内部是否拆分执行器、验证器或分配器属于该业务自身。
- **发射分配层**：公平发射后的复杂分配机制本阶段不创建 `launch` 代码库；未来需求明确后再作为独立扩展建立，不影响 `core` 的发射基础能力。
- **群聊边界**：`group-chat` 保留旧群聊功能和业务行为，仅删除地址主体平行路径与群内 NFT 委托并适配 MemberNFT/Core/Action。群聊授权只认 NFT 当前持有人，不存在 `GroupChatDelegate` 或 `GROUP_DELEGATE_ADDRESS`；需要代理时由上层托管合约完成，见 [ADR-005](docs/adr/005-remove-group-chat-delegation.md)。付款地址、owner 快照和审计地址不属于要删除的业务身份。
- **配套仓库**：`compatibility` 专门验证外部 WBNB/WETH9 与 Uniswap V2 兼容的 PancakeSwap 依赖的接口和实际行为；`periphery`、`script`、`love20-anvil`、`interface-test`、`interface`、`tools` 和 `docs` 是外围、部署、集成测试、前端或文档仓库，不改变核心领域关系。`compatibility` 不属于任何生产合约的运行时依赖。
