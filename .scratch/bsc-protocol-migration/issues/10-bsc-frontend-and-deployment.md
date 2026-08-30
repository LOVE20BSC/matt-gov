# BSC 部署与独立前端

Type: grilling
Status: resolved
Blocked by: 01, 04, 09

## Question

定义 BSC 目标网络、初始空投合约及使用边界、部署账号和密码弹窗流程、地址/ABI 产物格式、`love20-anvil` 的 BSC 部署图；确定 `interface-test` 的独立主题、页面与读写适配，测试通过后同步到 `interface` 的正式发布流程和验收证据。

## Comments

用户确认 BSC 部署使用四个网络 profile：`anvil`（chain ID 31337）、`bsc97_dev`（BSC Testnet，chain ID 97）、`bsc56_public_test`（BSC 主网公测实例）和 `bsc56_public`（BSC 主网正式实例）。两个 chain ID 56 profile 使用完全独立的合约地址、配置、代币符号和前端环境。

用户补充确认：所有代币发射都必须填写首批代币接收地址，协议首次部署产生的首个代币也遵循同一规则。BSC 正式部署时，首个代币的 `distributor` 使用旧 `LOVE20TKM/burn` 代码库部署的 `Airdrop` 合约，由该合约负责 Merkle 快照领取和初始分配；发射核心只负责将首批代币发送到该地址，不把 Burn 业务迁入 `LOVE20BSC`。这属于正式部署阶段的一次性部署依赖，不改变 Burn 代码库不迁移的范围边界。

部署文档必须保留可公开核验的来源链接：[`LOVE20TKM/burn`](https://github.com/LOVE20TKM/burn)、[`Airdrop.sol`](https://github.com/LOVE20TKM/burn/blob/main/src/Airdrop.sol)、[`DeployAirdrop.s.sol`](https://github.com/LOVE20TKM/burn/blob/main/script/DeployAirdrop.s.sol) 和 [`airdrop-design.md`](https://github.com/LOVE20TKM/burn/blob/main/docs/airdrop-design.md)。部署记录还需写明实际使用的 Burn 提交、来源区块、Merkle Root 和已部署 Airdrop 地址。

从旧仓库核对出的迁移约束：各业务仓库继续在 `script/network/<profile>/` 下维护网络参数、账号占位文件和 `address*.params`，`love20-anvil` 只汇总本次部署状态并生成前端环境文件；ABI 产物来自当前 BSC 仓库的 Foundry 输出，不复用旧协议 ABI。公开网络部署继续使用 Foundry keystore，密码只通过交互式弹窗/输入提供，任何密码、Token 或私钥不得提交到新组织。旧 `love20-anvil/config/deployer.json` 中的 Anvil 私钥仅是本地测试遗留，不能迁入 BSC 部署配置。

旧 `love20-anvil` 的默认图包含 `burn`、`random`、`verify`、扩展工厂和群级 delegate 等已被本次协议移除或收窄的节点；BSC 版必须按新 `core`、`action`、`group-chat` 等实际仓库重建部署图，不能原样复制旧图。首个代币使用的 Airdrop 不纳入 Anvil 默认部署图；公测和正式部署时均由旧 `burn` 代码库单独部署到 BSC，再将地址作为外部目标注入。

## Answer

- **网络 profile**：固定使用 `anvil`（chain ID `31337`）、`bsc97_dev`（BSC Testnet，chain ID `97`）、`bsc56_public_test`（BSC 主网公测实例）和 `bsc56_public`（BSC 主网正式实例）。两个 chain ID `56` profile 必须使用完全独立的地址、配置、代币符号和前端环境；`bsc97_testnet` 不作为名称。
- **部署图**：`love20-anvil` 只编排 BSC 版实际仓库的部署脚本，至少覆盖 `core`、`action`、`group-chat` 和 `batch-transfer`；依赖顺序由新仓库的真实地址输入决定。旧 `burn`、`random`、`verify`、群级 delegate 和业务工厂节点不复制。首个代币的 Airdrop 不进入默认部署图，由旧 `burn` 代码库单独部署到 BSC 后，在公测和正式部署脚本中作为外部目标地址注入；不把 Burn 业务迁入新组织。公平发射后的复杂分配机制本阶段不创建 `launch` 代码库。
- **地址与 ABI**：每个可部署仓库在 `script/network/<profile>/` 维护 `network.params`、账号占位文件和 `address*.params`；Foundry 编译产物是 ABI 的唯一来源，`love20-anvil` 仅汇总地址与产物生成 `state/addresses.json` 和前端环境文件。不同 profile 不共享地址文件。
- **账号与密钥**：Anvil 使用公开默认账号只限本地测试；公开网络使用各仓库现有 Foundry keystore 流程。密码、Token 和私钥只能通过弹窗或交互式输入，不写入仓库、`.env`、地址文件或部署日志。
- **首个代币空投**：所有发射（包括首个代币）都填写 `distributor`。正式 BSC 部署将其设置为旧 [`LOVE20TKM/burn`](https://github.com/LOVE20TKM/burn) 的 [`Airdrop.sol`](https://github.com/LOVE20TKM/burn/blob/main/src/Airdrop.sol) 部署地址；发布记录固定保存 Burn 提交、来源区块、Merkle Root、Airdrop 地址、首个代币地址和实际网络。空投合约的快照与领取规则沿用其公开设计文档，不由 BSC 核心重复实现。
- **独立前端**：BSC 前端只在 `interface-test` 开发和验收，使用独立 BSC 主题、网络配置、地址和 ABI；前端只与已验收的可信 `Target`/执行合约交互，不根据任意扩展地址动态信任业务。`interface-test` 通过本地 Anvil 和 BSC 公测 profile 验收后，人工同步到 `interface` 正式发布，测试期间不修改 `interface`。
- **验收证据**：每个候选发布必须记录目标 profile、各仓库提交、部署命令、地址/ABI 产物、链上代码存在性、首个代币接收目标和前端读写结果；公测和正式部署使用同一部署脚本，仅替换网络与独立配置。旧组织只读/归档时机和 gas 优化不作为本票据的前置条件。
