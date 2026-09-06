# LOVE20BSC 协议概览

LOVE20 是基于可验证共识行动的持续铸币协议。它通过 MemberNFT 统一身份、治理投票分配 Proposal 激励，并由不同 Executor 处理 LP、链群和服务行动。

## 协议分层

| 层 | 负责内容 |
| --- | --- |
| Token Tree | WBNB → 首个 LOVE20 代币 → 子币 |
| Core | MemberNFT、Stake、Phase、Submit、Vote、Mint、Launch |
| Action | ActionTarget、LP、Group Action、Service Executor |
| Group Chat | 群聊配置、消息、资格和 Group Chat Delegate |

具体规则只看对应模块规格；本文件不定义 ABI、默认参数或新的边界。

## 四个核心概念

- **MemberNFT**：业务状态绑定 `memberId`；NFT 转移改变控制者，不改写历史，未结算权益由新持有人操作。
- **Phase / Round**：Phase 是无语义时间片；Core 将 Phase N 解释为治理 Round N，Action 各 Executor 自行映射阶段。具体映射见 [Core Phase](core/03-phase.md) 和 [Action 阶段](action/02-phase-model.md)。
- **Governance Reward / Proposal Reward**：Mint 在 Round 结束后准备并冻结本轮池；投票和加速激励按治理规则结算，Proposal 激励按达标 Proposal 分配。
- **Action / Chat**：Action 负责可验证的链上行动；Group Chat 只负责沟通、资格和消息索引，不持有行动资产。

## 最小流程

1. `Launch.init` 绑定依赖并创建首个代币，首批代币发送到外部 Airdrop。
2. 用户领取或取得首币后铸造 MemberNFT。
3. MemberNFT 持有人质押、创建/推举 Proposal 并投票。
4. Round 结束后，Mint 只准备一次；Target 或成员按冻结结果铸造激励。
5. Action Executor 在自己的阶段开放参与、验证和行动激励结算。
6. Group Chat 使用 MemberNFT 身份发言，资格和黑名单由规则模块判断。

## 入口

- [Core](core/README.md)
- [Action](action/README.md)
- [Group Chat](group-chat/README.md)
- [Compatibility](compatibility.md)
- [组织上下文](../../CONTEXT.md)
- [组织验收](../acceptance.md)
- [规格撰写指南](../spec-writing-guide.md)
- [文档审查指南](../review-guide.md)

历史差异见 `CHANGES-*.md`；历史票据不是当前规范。
