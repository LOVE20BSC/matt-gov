# LOVE20BSC 仓库清单

组织级清单只记录仓库边界、主要依赖和当前状态；具体实现说明与测试命令放在对应仓库的 `README.md`。

| 仓库 | 定位 | 主要依赖 | 当前状态 |
| --- | --- | --- | --- |
| `matt-gov` | 组织治理、迁移决策和验收记录 | 无 | 活跃 |
| `core` | 核心治理、`MemberNFT`、`Phase` 和基础子币发射能力 | 外部 PancakeSwap `Factory`/`Pair`/`Router` 接口 | 规划中 |
| `compatibility` | 外部 WBNB/WETH9 与 Uniswap V2 兼容的 PancakeSwap 测试 | 外部 WBNB、Factory、Pair、Router 和本地 Uniswap V2 参考实现 | 规划中 |
| `action` | `ActionTarget`、LP/链群行动及链群服务行动执行合约 | `core` | 规划中 |
| `group-chat` | 群聊业务和 **Group Chat Delegate** | `core`、`action` | 规划中 |
| `interface-test` | BSC 前端开发、集成和验收 | `core`、`action`、`group-chat` | 规划中；日常修改入口 |
| `interface` | BSC 前端正式发布 | 验收后的 `interface-test` | 规划中；只接受人工同步 |
| `periphery` | 跨仓库调用与外围适配 | `core`、`action` | 规划中 |
| `script` | 部署、地址和发布脚本 | 各可部署业务仓库 | 规划中 |
| `love20-anvil` | 本地区块链集成测试编排 | `core`、`action`、`group-chat`、`batch-transfer` | 规划中 |
| `docs` | 面向用户和开发者的协议文档 | 各业务仓库 | 规划中 |
| `batch-transfer` | 独立批量转账工具 | 无 | 规划中 |

`launch` 本阶段暂不创建。`core` 负责基础子币发射流程，包括发射次数账本、次数融合、次数消耗和子币创建；公平发射后的复杂分配机制未来需求明确后再另建独立代码库。

`compatibility` 只保存外部依赖兼容性测试、参考实现夹具、目标网络地址清单和测试证据，不提供生产合约，也不作为 `core` 的运行时依赖。它验证接口和实际状态/数值行为，尤其是 WBNB/WETH9、PancakeSwap Factory/Pair/Router 与 Uniswap V2 参考实现的差异；测试通过后才允许把对应外部地址用于 BSC 部署。

旧 `extension`、`extension-group` 的业务迁入 `action`；旧 `extension-lp` 仅迁移 V2 LP 业务，重写为 `action` 内的 LP 行动执行合约，V1 LP 实现及旧 LP 工厂不迁移。`burn`、未部署的 `chat` 和外部 `v2-periphery` 不在本组织清单中。Burn 业务合约不迁移到 LOVE20BSC 组织，但其空投合约（`Airdrop.sol`）必须在 Burn 活动结束后由旧 [`LOVE20TKM/burn`](https://github.com/LOVE20TKM/burn) 代码库单独部署到 BSC，作为首个代币 `distributor` 的外部依赖；部署记录必须公开指向 [`Airdrop.sol`](https://github.com/LOVE20TKM/burn/blob/main/src/Airdrop.sol)、[`DeployAirdrop.s.sol`](https://github.com/LOVE20TKM/burn/blob/main/script/DeployAirdrop.s.sol)、[`airdrop-design.md`](https://github.com/LOVE20TKM/burn/blob/main/docs/airdrop-design.md)，并记录实际使用的 Burn 提交、来源区块、Merkle Root 和已部署 Airdrop 地址。

旧 `group` 仓库中已部署且仍需要的 `LOVE20Group` 只迁移合约级实现，并入 `core` 后重命名为 `MemberNFT`。`GroupDefaults` 属于地址到默认 NFT 的便利映射，BSC 版不迁移、不部署；不新增独立的 `group` 代码库。旧 `GroupDelegate` 不进入 `core`，Chat 所需的委托逻辑仅在 `group-chat` 内实现，并统一称为 **Group Chat Delegate**。
