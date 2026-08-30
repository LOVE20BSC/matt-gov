# LOVE20BSC 协议与组织迁移地图

## Destination

形成 LOVE20BSC 新组织的可执行迁移与协议改造规格：明确 LOVE20TKM 旧仓库到新仓库的保留、合并、删除或新建方案，锁定 BSC 版协议核心行为、部署、前端、文档和验收边界，直到剩余决策都可以交给后续实现任务。

本地图阶段只解决决策，不直接实现代码。

## Notes

- 领域：LOVE20 BSC 协议、合约组织迁移、独立 BSC 前端和跨仓库测试。
- 技能：`wayfinder`、`domain-modeling`、`grilling`；进入实现阶段再按仓库使用 LOVE20 合约、集成、前端和发布技能。
- Issue tracker：Wayfinder 继续使用本仓库 `.scratch/` 下的本地 Markdown tracker；仓库远程已配置为 GitHub `LOVE20BSC/matt-gov`。
- 已确认基线：BSC 是独立协议代际，不兼容旧合约存储、地址和历史状态；统一参与主体为 `LOVE20Member`；`memberId` 是核心业务主键；不部署地址到默认 NFT 的链上映射；治理质押不再产生 SL/ST 凭证，资产随 Member NFT 整体转移；`core` 负责基础子币发射流程，发射次数按 `tokenAddress + memberId` 记录并支持部分融合；`LOVE20MemberMarket` 不迁移；Burn 不参与；`batch-transfer` 独立迁移；`love20-anvil` 保留为集成测试编排器；前端开发只改 `interface-test`，测试完成后再人工同步到 `interface` 正式发布。
- 迁移硬约束：`LOVE20TKM` 全部代码库在整个迁移期间只读，仅用于源码、提交历史和 `thinkium70001_public` 链上部署证据；任何 BSC 改造、清理、提交和推送只发生在 `LOVE20BSC` 新仓库。

## Decisions so far

<!-- 只列已关闭的子票据；当前已在启动讨论中确认的基线见 Notes。 -->

- [四阶段与轮次模型](issues/01-phase-round-model.md) — `LOVE20Phase` 只维护无语义时间片；`action` 层统一使用四槽位 `ActionRound`，链群服务和 LP 的 `Verify` 为空操作但轮次和 `Mint` 槽位与链群行动一致。
- [行动 Target 与参与登记边界](issues/02-action-executor-and-join.md) — `ActionTarget` 统一行动提案创建、行动登记和应急清理；关联 `executor` 发起激励铸造，`ActionTarget` 经 `Mint` 接收后转给执行合约，由行动类型内部业务负责后续分配；按执行合约查询返回 `proposalId[]`，无执行合约参数时返回本轮已投票的 `(proposalId, executor)`。
- [公共验证者竞选与验证](issues/03-public-verifier-election.md) — 链群行动执行合约按候选排名和阶段分割线开放验证，首个有效批次永久锁定 `MemberNFT` 验证者；必须完成全部链群快照才产生链群服务相关激励，失联时本轮行动层激励预期为 `0`。
- [链群行动与服务者激励](issues/06-chain-group-economics.md) — 服务行动执行合约沿用旧版范围，按 `actionTokenAddress` 聚合整个代币社区达到投票门槛的链群行动，可用同币或父币 Proposal 激励子币社区；服务加入仅接受链群 owner 或公共验证者候选 `MemberNFT`，创建 KV 保留 `actionTokenAddress` 与 `govRatioMultiplier`，取消工厂但不改变业务公式；完整验证行动按行动权重分摊服务激励，再按各自冻结比例分给公共验证者与链群 owner，统一全精度计算避免旧版舍入下溢，比例使用 `1e18`，100% 二次分配安全收敛且不包含 gas 补偿。
- [BSC 部署与独立前端](issues/10-bsc-frontend-and-deployment.md) — 固定四个 BSC profile、按新仓库重建 Anvil 部署图、隔离地址/ABI/密钥和 `interface-test` 验收；首个代币通过旧 Burn 的公开 Airdrop 作为一次性部署依赖。
- [两层主架构与提案 Target 边界](issues/12-contract-layer-boundaries.md) — 核心治理层与提案扩展层分离；当前社群行动使用 `ActionTarget`，其内部组件不构成协议级第三层，`LOVE20Phase` 作为跨层时间基础设施。
- [提案、提案执行与行动扩展边界](issues/13-proposal-and-action-boundaries.md) — 投票阶段结束后任何地址可一次性准备并冻结轮次级 Proposal 总激励；各 Proposal 由自己的 Target 按冻结状态单独铸造一次，行动类提案由关联 `executor` 经 `ActionTarget` 铸造并交由类型内部业务处理。
- [提案回调 ABI 与操作原子性](issues/14-proposal-callback-abi.md) — Proposal 创建、推举和投票分别触发对应回调；回调传递 `tokenAddress`、`proposalId`、`submitterId`/`voterId`、增量票和 `bytes32[]/bytes[]` KV，任一对应外层操作回调失败则整笔交易回滚。
- [提案目标与零地址激励](issues/15-zero-proposal-target-reward.md) — Proposal Target 必须是非零 EOA 或合约；不为 Proposal 增加零地址自动销毁分支，行动层 `executor == 0` 规则独立保留。
- [迁移执行顺序与旧组织归档](issues/16-migration-order-and-archive.md) — 先冻结链上来源证据，再按 `core`、业务仓库、配套仓库、Anvil/前端、公测、正式发布推进；正式发布验收前旧组织不归档，之后按旧 Thinkium 责任逐仓库只读或归档。
- [Gas 优化范围与性能基线](issues/17-gas-baseline-scope.md) — 首发只阻断无界循环、不可分批和超过目标网络区块 gas 上限 80% 的写交易；按代表性交易记录中位数，不设固定绝对 gas 数值。
- [仓库迁移矩阵与依赖边界](issues/09-repository-migration-matrix.md) — 旧 `LOVE20Group` 并入 `core` 重命名为 `LOVE20Member`，`GroupDefaults` 不迁移；旧 `extension-lp` 仅迁移 V2 LP 业务为 `action` 内的 LP 行动执行合约，V1 不迁移；链群统一使用 `MemberNFT`，**Group Chat Delegate** 仅限 `group-chat` 内部；PancakeSwap 必须先证明 `Stake` 使用场景下的功能和数值结果正确。
- [Matt 文档与组织验收标准](issues/11-matt-docs-and-acceptance.md) — 各仓库采用条件式最低文档标准，组织级仓库状态和跨仓库验收分别维护在 `docs/repositories.md` 与 `docs/acceptance.md`，首个 `core` 真实小任务用 agent 自审验证协作闭环。
- [体验资产与行动撤回](issues/07-experience-and-withdrawal.md) — 体验资产按提供者独立归属，部分撤回以行动快照为边界，行动结束由类型内部业务结算，首版部署 `forceExit` 但由前端隐藏，仅作登记清理兜底。
- [治理质押、融合与资产生命周期](issues/05-stake-fusion-and-lifecycle.md) — 质押按 `memberId` 归属，不再产生 SL/ST 凭证，份额直接由 `Stake` 账本维护；两类质押统一解锁，融合按社区和投票状态隔离，多轮激励独立铸造。
- [MemberNFT 发射次数与子币发射](issues/04-launch-count-and-permit.md) — 治理激励按向上取整阈值原子增加 MemberNFT 的社区发射次数；余数按 `tokenAddress + memberId` 保留，社区累计达到 `maxLaunchCount = X` 后停止新增；次数可部分融合转移，发射消耗次数并把首批代币交给指定 `distributor`。

## Not yet specified


## Out of scope

- Burn/空投业务合约本轮不纳入 BSC 迁移。
- `LOVE20MemberMarket` 未部署且不属于核心依赖，本轮不迁移、不并入 `core`。
- 旧 LOVE20TKM 合约的存储、地址、历史状态兼容和通用跨链迁移。
- 尚未部署的 `chat` 代码库及其 Member NFT 身份模型；本次迁移不纳入，未来部署或纳入 BSC 时另行建票据。
- 测试期间直接修改 `interface`；正式发布只能从验收后的 `interface-test` 手动同步。
- 迁移阶段暂不创建 `launch` 代码库；公平发射后的复杂分配机制待未来需求明确后另行建立。
