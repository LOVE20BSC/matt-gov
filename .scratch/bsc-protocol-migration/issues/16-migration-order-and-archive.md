# 迁移执行顺序与旧组织归档

Type: grilling
Status: resolved
Blocked by: 09, 10, 11, 14, 15

## Question

确定 LOVE20TKM 旧仓库证据冻结、LOVE20BSC 各代码库创建与迁移、Anvil/前端验收、BSC 公测和正式发布的执行顺序；明确旧组织何时只读、何时归档，以及迁移失败时如何保留可追溯证据。

## Answer

### 执行顺序

1. **冻结证据，旧组织只读**：按合约逐项核对 `thinkium70001_public` 链上代码，记录旧仓库、源提交、合约地址、部署区块、runtime bytecode hash 和必要依赖。只把已部署合约及其必要依赖列入迁移清单；旧仓库只读，已部署的旧链合约继续运行，不对旧代码做任何改写。
2. **创建并实现 `core`**：从清单筛选核心代码，按 BSC 规则重写 `Stake`、`Submit`、`Vote`、`Mint`、`MemberNFT`、`LOVE20Phase`、发射次数/子币创建基础设施及 `LOVE20TokenFactory`，先完成单元测试和本地部署。
3. **实现业务仓库**：以 `core` 的已确认接口和 Anvil 地址为输入，建立 `action`、`group-chat`；将旧 `extension-lp` 的 V2 LP 业务重写为 `action` 内的 LP 行动执行合约。迁移阶段不创建 `launch`；V1 LP、旧扩展工厂、核心 `LOVE20Verify`、`Random` 等删除项不得回流，`GroupVerify` 仅作为 `action` 内部的可选技术拆分。
4. **接入配套仓库**：更新 `periphery`、`script` 和 `love20-anvil`，重建真实依赖图；首个代币 Airdrop 作为独立外部部署步骤或测试夹具注入，不成为 `core` 的业务节点。`batch-transfer` 独立迁移，可与上述步骤并行。
5. **集成验收**：在 `anvil` 完成核心、发射、行动、群聊和批量转账的最小读写路径；随后在 `bsc97_dev` 和 `bsc56_public_test` 验证部署、地址、ABI、前端网络隔离及关键交易。
6. **前端发布**：只在 `interface-test` 完成 BSC 主题、地址和 ABI 适配；通过公测验收后，将同一变更人工同步到 `interface`，不把 `interface` 作为日常开发分支。
7. **正式发布与记录**：部署 `bsc56_public`，保存各仓库提交、命令、链上代码证明、地址/ABI 产物、首个代币 `distributor` 和前端读写结果。

### 旧组织边界

- 在整个迁移期间，旧组织代码库只读，不编辑、格式化、更新依赖、提交、推送或删除；已部署的 Thinkium 合约继续运行，迁移只通过新仓库提交完成。
- 在 `bsc56_public` 正式发布和验收完成前，旧组织不归档；正式发布后也不自动归档，先按旧 Thinkium 是否仍需维护逐仓库决定。
- 正式发布完成后，将已迁移旧仓库标记为只读并保留公开 URL、部署文档、链上地址和源提交；是否在 GitHub 执行 Archive 作为最后的管理动作，必须确认旧 Thinkium 服务不再需要提交。未迁移或仍有运行责任的仓库继续保留，不因 BSC 发布自动归档。
- 迁移失败或中止时，保留证据冻结提交和新仓库历史，不回滚或清理旧仓库；问题通过对应仓库票据继续处理。

### 证据最小集

每个阶段至少保留：源提交、目标提交、执行命令、网络 profile、地址/ABI 产物、链上代码存在性检查和失败日志。完整记录写入 `docs/acceptance.md`，跨仓库来源映射写入 `matt-gov`，不把密钥或密码写入任何记录。
