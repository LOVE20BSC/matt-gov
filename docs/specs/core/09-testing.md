# 事件、错误和验收

本文档定义事件规范、错误条件和验收场景。

---

## 1. 事件

### 1.1 覆盖范围

事件至少覆盖：

- MemberNFT 铸造/转移
- 质押/解锁/提取/融合
- Phase 生成/同步
- Proposal 创建/推举/投票
- 激励准备/铸造/销毁
- 发射额度和次数增加/融合/消耗
- 子币创建/分发
- Pair 手续费结算和销毁

### 1.2 事件主键

事件主键使用 `tokenAddress`、`memberId`、`proposalId`、`round`。

---

## 2. 错误

### 2.1 必须回滚的情况

以下情况必须回滚：

- 无效成员或来源控制者
- 零地址 Target/Distributor
- 非法模式
- KV 长度不等
- Proposal 或推举重复
- 投票超额
- Round 未结束或未准备
- 重复铸造/销毁
- 批量治理激励中存在任一无效 Round
- 待解锁时追加或融合
- 解锁期不足
- 跨社区次数操作
- 发射次数不足或超社区上限
- 外部 Pair/Router 调用失败
- 任何 Target 回调失败

---

## 3. 验收场景

### 3.1 MemberNFT

- NFT 转移后的权限连续性（历史不回写，当前未铸造权益由新持有人继续操作）
- 名称长度 32 bytes 边界
- 铸造费用短名称稀缺性

### 3.2 Phase

- 空阶段和动态校准
- ±10% 内不调整，超出范围时计算新 phaseBlocks
- 首个推举自动 sync()

### 3.3 Stake

- 统一解锁（流动性质押和加速质押同时申请、同时等待、同时提取）
- 向非调用者持有目标 NFT 的融合（只增加，不减少目标状态）
- LP 份额与手续费销毁统计
- PancakeSwap 兼容性
- 加速质押累计值继承机制

### 3.4 Proposal

- 零地址 Target 拒绝
- Callback 原子性

### 3.5 Mint

- Round 级准备与 Proposal 单项铸造
- 治理激励三段结果（voteReward, boostReward, burnReward）
- 批量多轮铸造原子性
- launchCredit 累计和发射次数产生

### 3.6 Launch

- 发射阈值向上取整
- 多阈值跨越
- 社区 maxLaunchCount 上限
- 向非调用者持有目标 NFT 部分融合
- addLaunchCount 权限控制（只能由 Mint 合约调用）

### 3.7 首个代币

- 一次性启动路径原子性
- Airdrop 依赖和分发验证
