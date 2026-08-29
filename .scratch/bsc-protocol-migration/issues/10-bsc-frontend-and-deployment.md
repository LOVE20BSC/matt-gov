# BSC 部署与独立前端

Type: grilling
Status: claimed
Blocked by: 01, 04, 09

## Question

定义 BSC 目标网络、初始空投合约及领取边界、部署账号和密码弹窗流程、地址/ABI 产物格式、`love20-anvil` 的 BSC 部署图；确定 `interface-test` 的独立主题、页面与读写适配，测试通过后同步到 `interface` 的正式发布流程和验收证据。

## Comments

用户确认 BSC 部署使用四个网络 profile：`anvil`（chain ID 31337）、`bsc97_dev`（BSC Testnet，chain ID 97）、`bsc56_public_test`（BSC 主网公测实例）和 `bsc56_public`（BSC 主网正式实例）。两个 chain ID 56 profile 使用完全独立的合约地址、配置、代币符号和前端环境。

用户补充确认：所有代币发射都必须填写首批代币接收地址，协议首次部署产生的首个代币也遵循同一规则。BSC 正式部署时，首个代币的 `distributionTarget` 使用旧 `LOVE20TKM/burn` 代码库部署的 `Airdrop` 合约，由该合约负责 Merkle 快照领取和初始分配；发射核心只负责将首批代币发送到该地址，不把 Burn 业务迁入 `LOVE20BSC`。这属于正式部署阶段的一次性部署依赖，不改变 Burn 代码库不迁移的范围边界。
