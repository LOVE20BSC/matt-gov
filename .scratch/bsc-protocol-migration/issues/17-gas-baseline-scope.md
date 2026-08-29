# Gas 优化范围与性能基线

Type: grilling
Status: resolved
Blocked by: 16

## Question

确定 BSC 版首发前必须完成的 gas 优化范围、代表性交易集合和可接受基线；区分影响安全或单笔交易可执行性的必做优化，与上线后基于真实数据再处理的次要优化，避免在协议规格阶段为所有函数设定无依据的目标值。

## Comments

旧 `LOVE20TKM` 的 gas/ptest 主要测量 Fenwick、Join、Withdraw 和 Verify 的规模曲线；BSC 版删除了随机抽取与核心 Verify，不能把旧测试文件或旧绝对数值直接当作新协议门槛。

## Answer

### 首发前必做

- 所有用户可控数组和集合操作都必须有显式批量边界与游标；禁止在单笔交易中遍历全部 `MemberNFT`、群、参与者、投票或历史事件。
- `Vote` 批量投票、`ActionTarget` 初始化/投票 KV、链群验证批次、奖励领取、`MemberNFT` 融合与部分撤回必须在最大合法输入下可执行；失败应是明确校验或回滚，不得因 gas 耗尽留下半完成状态。
- 核心状态更新遵守既定原子性：回调失败、奖励重复结算、链群服务累计分配超预算等路径不能通过“省 gas”绕过校验。
- 事件和返回值只保留前端、索引和审计需要的字段；不为 gas 优化牺牲历史可追溯性或安全边界。

### 最小基线交易集

`core`：首次质押、追加质押、申请解锁、提取、融合、创建 Proposal、单笔投票、批量投票、准备奖励、治理激励领取、行动激励领取、LaunchNFT 铸造与发射、`LOVE20Phase.sync`。

`action`：行动初始化回调、正常加入、部分撤回、正常退出、兜底 `forceExit`（默认关闭时只测 revert）、链群验证首批/中间/末批、完整服务激励领取与 100% 二次分配。

`launch`/`batch-transfer`：首批分配 `RewardOnly` 与 `Callback` 两路径、批量转账 1/50/配置上限三个规模。

### 记录方式

- 在同一 compiler、optimizer、网络 profile 和等价状态下记录每个交易的 `gasUsed`、calldata 大小、输入规模和结果；同一用例重复 3 次，报告中位数。
- 每个批量接口同时记录“最大成功批量”和“首次超出限制的批量”，并保存失败原因。基线脚本读取目标网络最新区块的 `gasLimit`，要求代表性交易 `gasUsed <= gasLimit * 80%`；不把某次 BSC 绝对 gas 数值写死进协议。
- 首发只阻断超过该可执行性门槛或存在无界循环/状态不一致风险的用例；低频查询、只读 viewer 和部署字节码大小优化留到真实数据出现后再处理。

### 验收边界

`core` 与 `action` 通过 targeted unit/boundary/integration 测试和 gas 基线；`love20-anvil` 跑完整最小流程；`bsc97_dev` 与 `bsc56_public_test` 至少复测代表性写交易。未完成真实 BSC 正式部署前，不宣称 gas 已达到最终生产水平。
