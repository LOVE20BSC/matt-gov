# LOVE20BSC 仓库清单

组织级清单只记录仓库边界、主要依赖和当前状态；具体实现说明与测试命令放在对应仓库的 `README.md`。

## 旧代码基线

所有迁移规格引用的旧代码提交集中定义在这里。正文只写 `LOVE20TKM/<repo>/<path>`；审查时按下表补足提交哈希。除非本表更新，正文中的旧代码来源版本不变。

| 旧仓库 | 固定提交 |
| --- | --- |
| `LOVE20TKM/core` | `0e3efcc13a7b9e202033f62e4858795bf43b557e` |
| `LOVE20TKM/extension` | `92684fa3ad42a881bba883bc8458c80faf2bc4f2` |
| `LOVE20TKM/extension-group` | `37cf53e0544f4bb03b0625448175ae9638f82dc3` |
| `LOVE20TKM/extension-lp` | `e05c8770aa2ecbd63d0bc685b560bb41634d8875` |
| `LOVE20TKM/group` | `2eb6d6c8d48bf6dd382efa5887124a2c3c722fd9` |
| `LOVE20TKM/group-chat` | `ce21ea8f29b3750421876ae649fa7d919fe42cff` |
| `LOVE20TKM/burn` | `a7f9aefe7194feaf1582acaa0c9dbffee7026391` |

| 仓库 | 定位 | 主要依赖 | 当前状态 |
| --- | --- | --- | --- |
| `matt-gov` | 组织治理、迁移决策和验收记录 | 无 | 活跃 |
| `core` | 核心治理、`MemberNFT`、`Phase` 和基础子币发射能力 | `libs`、OpenZeppelin Contracts、外部 Uniswap V2 兼容 DEX 的 `Factory`/`Pair`/`Router` 接口 | 活跃；核心合约、接口与测试均已提交 |
| `libs` | 跨仓库共享的 Solidity 原语（有序历史索引、集合、按轮历史与分页） | 无 | 活跃；由 `core` 固定为子模块，`action`、`group-chat` 经上游嵌套依赖使用 |
| `compatibility` | 外部 WETH 与 Uniswap V2 兼容 DEX 测试 | 外部 WETH、Factory、Pair、Router 和本地 Uniswap V2 参考实现 | 进行中；PancakeSwap 兼容性验证已完成（BSC 主网与测试网），Git 仓库待建 |
| `dex` | 独立部署的 Uniswap V2（`Factory`、`Pair`、`Router02`），上游源码零修改、永久关闭协议抽成 | 固定提交的上游 Uniswap `v2-core`/`v2-periphery`/`solidity-lib` 子模块 | 活跃 |
| `action` | `ActionTarget`、LP、GroupAction 和 GroupService Executor | `core`（`libs`、OpenZeppelin 经 `core` 传递） | 活跃；ActionTarget、LP、GroupAction、GroupService 均已迁移并完成测试 |
| `group-chat` | 群聊业务 | `action`（`core`、`libs`、OpenZeppelin 经 `action` 传递） | 活跃；群聊业务已实现并提交 |
| `interface-test` | BSC 前端开发、集成和验收 | `core`、`action`、`group-chat` | 规划中；日常修改入口 |
| `interface` | BSC 前端正式发布 | 验收后的 `interface-test` | 规划中；只接受人工同步 |
| `periphery` | 跨仓库调用与外围适配：依赖协议已部署合约、可随时替换的聚合查看与便捷交互 | `core` | 规划中 |
| `script` | 部署、地址和发布脚本 | 各可部署业务仓库 | 规划中 |
| `love20-anvil` | 本地区块链集成测试编排 | `core`、`action`、`group-chat`、`tools` | 规划中 |
| `docs` | BSC 版协议对外公开文档 | 各业务仓库 | 活跃；公开仓库与文档站已启用 |
| `tools` | 不依赖协议部署合约、功能单一的独立工具合约 | 无（外部 DEX 接口在仓内自声明） | 活跃；`BatchTransfer`、`UniswapV2Zap` 已迁移并通过测试 |

`docs` 是公开仓库 [LOVE20BSC/docs](https://github.com/LOVE20BSC/docs)，文档站入口为 [love20bsc.github.io/docs](https://love20bsc.github.io/docs/)。它只收录定稿的对外内容；协议行为与合约接口仍分别以 `matt-gov/docs/specs` 和 `core/src/interfaces` 为准。

`launch` 本阶段暂不创建。`core` 负责基础子币发射流程，包括发射次数账本、次数融合、次数消耗和子币创建；公平发射后的复杂分配机制未来需求明确后再另建独立代码库。

`compatibility` 只保存外部依赖兼容性测试、参考实现夹具、目标网络地址清单和测试证据，不提供生产合约，也不作为 `core` 的运行时依赖。它验证接口和实际状态/数值行为，尤其是 WETH、Uniswap V2 兼容 DEX（如 PancakeSwap）的 Factory/Pair/Router 与 Uniswap V2 参考实现的差异；测试通过后才允许把对应外部地址用于 BSC 部署。

### 外围仓库的划分规则

新增合约归属哪个仓库，按它**是否依赖协议已部署的合约**判断，这条规则决定仓库边界而不是按合约功能命名：

| 类别 | 判据 | 依赖 | 例子 |
| --- | --- | --- | --- |
| `periphery` | 依赖协议已部署的合约，可随时替换，提供聚合查看或便捷交互 | `core` | viewer、hub |
| `tools` | **不**依赖协议已部署的合约，功能单一 | 无 | `UniswapV2Zap`、`BatchTransfer` |
| 业务库 | 功能复杂、多合约协作，一库一仓 | `core`、`action` | `group-chat` |

判据的关键后果：`tools` 的合约**不随协议升级而返工**，所以先建、先稳定；`periphery` 的合约读取协议状态，必须等它依赖的接口定稿后再建。「可随时重新部署」不构成归入外围的理由——读写协议状态的合约即便能重新部署，旧地址仍然在写协议状态，这类合约按普通协议组件处理，不按外围处理。

`tools` 内各工具互相独立，因此**不设全仓统一的一键部署入口**：一个全局入口要么重复部署先前已部署的工具，要么无法覆盖后来新增的工具，两种结果都是错的。每个工具自带 `one_click_deploy_<tool>.sh` 与自己的参数文件、地址文件、`NN_*_<tool>.sh` 步骤脚本，编号在仓内按工具分段（`11`/`21`/`31`、`12`/`22`/`32`）。

旧 `LOVE20TKM/extension`、`LOVE20TKM/extension-group` 的业务迁入 `action`；旧 `LOVE20TKM/extension-lp` 仅迁移 V2 LP 业务，重写为 `action` 内的 LP 行动执行合约，V1 LP 实现及旧 LP 工厂不迁移。`burn`、未部署的 `chat` 和外部 `v2-periphery` 不在本组织清单中。首币的 `distributor` 为本仓库的 `core/src/distributor/AirdropDistributor.sol`。首币空投的份额数据来源于旧 `LOVE20TKM/burn` 记录在链上的销毁活动结果（来源链 ID、来源区块、来源地址与份额快照）；部署记录必须公开记录实际使用的来源链、来源区块、Merkle Root 与首币地址，使任何人可独立复算。

旧 `LOVE20TKM/group` 仓库中已部署且仍需要的 `LOVE20Group` 只迁移合约级实现，并入 `core` 后重命名为 `MemberNFT`；旧 `LOVE20Group` 是成员身份 NFT，不是“群”的 NFT，改名即为消除该误解——链群以 `groupId` 为业务标识，不存在第二套 GroupNFT 身份。`GroupDefaults` 属于地址到默认 NFT 的便利映射，BSC 版不迁移、不部署；不新增独立的 `group` 代码库。旧 `GroupDelegate` 不进入 `core`，也不进入 BSC 版：群聊授权只认 NFT 当前持有人，代理需求留给上层托管合约，见 [ADR-005](adr/005-remove-group-chat-delegation.md)。
