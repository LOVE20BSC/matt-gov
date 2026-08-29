# BSC 部署与独立前端

Type: grilling
Status: claimed
Blocked by: 01, 04, 09

## Question

定义 BSC 目标网络、初始空投合约及领取边界、部署账号和密码弹窗流程、地址/ABI 产物格式、`love20-anvil` 的 BSC 部署图；确定 `interface-test` 的独立主题、页面与读写适配，测试通过后同步到 `interface` 的正式发布流程和验收证据。

## Comments

用户确认 BSC 部署使用四个网络 profile：`anvil`（chain ID 31337）、`bsc97_dev`（BSC Testnet，chain ID 97）、`bsc56_public_test`（BSC 主网公测实例）和 `bsc56_public`（BSC 主网正式实例）。两个 chain ID 56 profile 使用完全独立的合约地址、配置、代币符号和前端环境。
