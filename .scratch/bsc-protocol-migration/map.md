# LOVE20BSC 协议与组织迁移地图

## Destination

形成 LOVE20BSC 新组织的可执行迁移与协议改造规格：明确 LOVE20TKM 旧仓库到新仓库的保留、合并、删除或新建方案，锁定 BSC 版协议核心行为、部署、前端、文档和验收边界，直到剩余决策都可以交给后续实现任务。

本地图阶段只解决决策，不直接实现代码。

## Notes

- 领域：LOVE20 BSC 协议、合约组织迁移、独立 BSC 前端和跨仓库测试。
- 技能：`domain-modeling`、`grilling`、`setup-matt-pocock-skills`、`grill-with-docs`；进入实现阶段再按仓库使用 LOVE20 合约、集成、前端和发布技能。
- Issue tracker：Wayfinder 继续使用本仓库 `.scratch/` 下的本地 Markdown tracker；仓库远程已配置为 GitHub `LOVE20BSC/matt-gov`。
- 已确认基线：BSC 是独立协议代际，不兼容旧合约存储、地址和历史状态；统一参与主体为 `LOVE20Member`；`memberId` 是核心业务主键；保留 `LOVE20MemberDefaults`；治理质押不再产生 SL/ST 凭证，资产随 Member NFT 整体转移；`LOVE20LaunchNFT` 发射后永久锁定到子币合约，Token ID 递增且永不复用，枚举包含已使用 NFT；`LOVE20MemberMarket` 不迁移；Burn 不参与；`batch-transfer` 独立迁移；`love20-anvil` 保留为集成测试编排器；前端开发只改 `interface-test`，测试完成后再人工同步到 `interface` 正式发布。

## Decisions so far

<!-- 只列已关闭的子票据；当前已在启动讨论中确认的基线见 Notes。 -->

- [四阶段与轮次模型](issues/01-phase-round-model.md) — `LOVE20Phase` 只维护无语义时间片；轮次和阶段名称由各上层使用层自行组合定义。
- [行动 Target 与参与登记边界](issues/02-action-executor-and-join.md) — `ActionTarget` 统一行动提案初始化、行动登记和应急清理；行动类型内部业务负责资产和具体逻辑，零地址行动额度在准备奖励时归本行动自动销毁。
- [两层主架构与提案 Target 边界](issues/12-contract-layer-boundaries.md) — 核心治理层与提案扩展层分离；当前社群行动使用 `ActionTarget`，其内部组件不构成协议级第三层，`LOVE20Phase` 作为跨层时间基础设施。
- [提案、提案执行与行动扩展边界](issues/13-proposal-and-action-boundaries.md) — 行动类提案使用 `proposalTarget + proposalTargetMode`，经 `ActionTarget` 初始化并交由类型内部业务处理；`proposalDetails` 在行动类型中作为 `verificationRule`，其他验证字段通过初始化 KV 传递。
- [仓库迁移矩阵与依赖边界](issues/09-repository-migration-matrix.md) — 公共验证者取代 `GroupVerify` 的群级 delegate；`group-chat` delegate 仅限 Chat 内部；`LOVE20TokenFactory` 作为 `core` 子币部署的技术拆分保留，业务扩展工厂删除。

## Not yet specified

- 公共验证者候选资格、排名起始时间、分批验证、首次提交锁定和治理监督规则。
- 治理激励额度如何触发 `LOVE20LaunchNFT`，以及去中心化/中心化发射的授权边界。
- 无 SL/ST 后治理质押、解锁、融合、行动部分撤回、体验资产和多轮铸造的完整状态模型。
- 执行合约自行托管资产后的应急 `forceExit` 开放时机和清理边界；正常资产退出不属于通用框架。
- 提案初始化回调与投票回调的最终 ABI，以及初始化回调失败时是否回滚提案创建。
- `proposalTarget` 为零地址时的提案激励处理规则。
- 链群行动服务者分配、gas 补偿、二次分配溢出保护和验证者角色拆分。
- 旧组织只读/归档时机、迁移执行顺序、Anvil 部署图和 Matt 文档最低标准。
- BSC 网络、初始空投、ABI/地址配置、独立主题和正式发布验收。
- gas 优化范围和是否需要独立性能基线。

## Out of scope

- Burn/空投业务合约本轮不纳入 BSC 迁移。
- `LOVE20MemberMarket` 未部署且不属于核心依赖，本轮不迁移、不并入 `core`。
- 旧 LOVE20TKM 合约的存储、地址、历史状态兼容和通用跨链迁移。
- 尚未部署的 `chat` 代码库及其 Member NFT 身份模型；本次迁移不纳入，未来部署或纳入 BSC 时另行建票据。
- 测试期间直接修改 `interface`；正式发布只能从验收后的 `interface-test` 手动同步。
