# 首个代币部署

本文档定义首个代币的部署流程和 Airdrop 依赖。

---

## 1. 启动路径

### 1.1 原子启动

首个代币在部署 Core 合约时内部原子完成创建，不需要部署后再调用。`Launch` 仍是 `TokenFactory` 的唯一调用者。

**启动交易必须原子完成**：

1. Core 合约部署
2. 内部创建首个代币
3. 协议代币登记
4. 核心 `minter` 设置
5. 首批代币铸造并发送到 Airdrop 合约
6. 通过 PancakeSwap Factory 创建首个代币/WBNB Pair

任一步失败则整个启动回滚。启动成功后该路径永久关闭，不能创建第二个首个代币或改写其父币和分发结果。

### 1.2 MemberNFT 铸造时序

- MemberNFT 合约在启动时部署，但不自动铸造任何 NFT
- 用户需要从 Airdrop 合约领取首个 LOVE20 代币后，才能调用 `MemberNFT.mint()` 支付铸造费用来铸造 MemberNFT
- 铸造费用基于首个代币的未铸造量计算（见 `02-member-nft.md` 第 3 节）

---

## 2. Airdrop 依赖

### 2.1 部署主体和时序

- Airdrop 合约由 **`LOVE20TKM/burn` 代码库** 负责，在 **Burn 活动结束后** 单独部署到 BSC
- Burn 业务合约**不迁移**到 LOVE20BSC 组织
- Airdrop 合约地址作为 BSC 新协议首个代币的 `distributor` 外部依赖
- `LOVE20TKM/burn` 仓库保持只读，只作为 Airdrop 合约的来源和部署依据

### 2.2 BSC 首个代币的初始分发来源

1. Airdrop 合约记录旧协议（Thinkium）参与者通过销毁活动获得的份额
2. Core 合约部署时，首个代币铸造后直接发送到已部署的 Airdrop 合约地址
3. 参与者按份额从 Airdrop 合约领取

### 2.3 Airdrop 合约特性

- 支持任意 ERC20 代币的分发，不绑定特定代币
- 份额按代币独立记录：某代币领取后该份额即消耗，即使该代币后续余额增加也不能重复领取
- 未领取份额对应的代币余额归属于剩余未领取者

### 2.4 来源可追溯性

部署记录必须公开指向 `LOVE20TKM/burn` 的：

- [`Airdrop.sol`](https://github.com/LOVE20TKM/burn/blob/main/src/Airdrop.sol) — 合约源码
- [`DeployAirdrop.s.sol`](https://github.com/LOVE20TKM/burn/blob/main/script/DeployAirdrop.s.sol) — 部署脚本
- [`airdrop-design.md`](https://github.com/LOVE20TKM/burn/blob/main/docs/airdrop-design.md) — 设计文档
- 实际使用的 Burn 提交哈希、来源区块、Merkle Root 和已部署的 Airdrop 地址

这使任何人都可以验证首个代币分发的合法性和公平性。
