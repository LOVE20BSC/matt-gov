# LOVE20BSC 规格文档结构

本文件定义 BSC 版各代码库规格文档的组织方式。各代码库 `docs/specs/` 目录内的拆分文件是当前行为的规范入口；本文件只维护跨仓库的文档边界，不重复协议细节。

在 `core`、`action`、`group-chat`、`compatibility` 代码库正式创建前，规格暂存于本仓库的 `docs/specs/<repo>/`（目录内拆分文件及其 `README.md` 入口）。代码库创建后，将该目录原样迁移到目标代码库并保留拆分结构；本仓库只保留迁移记录，不再维护第二份规范。

## 规范层级

1. **代码库规格**：由目标代码库 `docs/specs/` 目录内的拆分文件维护本代码库的当前职责、状态模型、公开接口、公式、错误/事件、依赖和验收场景。
2. **组织约束**：由本仓库的 `CONTEXT.md`、`docs/repositories.md` 和 `docs/acceptance.md` 维护共享术语、仓库边界、依赖方向和跨仓库验收要求。
3. **迁移依据**：`.scratch/bsc-protocol-migration/` 保存决策过程、旧代码来源和迁移证据，属于非规范材料。实现者不需要阅读旧仓库才能理解 BSC 规格。

## 代码库规格范围

| 代码库 | 规格入口 | 规格内容 |
| --- | --- | --- |
| `core` | 创建前 `matt-gov/docs/specs/core/`；创建后 `core/docs/specs/` | `Stake`、`Submit`、`Vote`、`Mint`、`MemberNFT`、`Phase`、基础子币发射和跨层回调边界 |
| `action` | 创建前 `matt-gov/docs/specs/action/`；创建后 `action/docs/specs/` | `ActionTarget`、`ActionRound`、LP 行动、链群行动、链群服务行动及行动层激励 |
| `group-chat` | 创建前 `matt-gov/docs/specs/group-chat/`；创建后 `group-chat/docs/specs/` | 群聊业务和 **Group Chat Delegate** |
| `compatibility` | 创建前 `matt-gov/docs/specs/compatibility.md`；创建后 `compatibility/SPEC.md` | WBNB/WETH9、PancakeSwap 与 Uniswap V2 参考实现的接口、行为、数值和 `Stake` 场景兼容性 |

`launch` 本阶段不创建独立代码库；Launch 合约属于 `core`，首个代币启动也由 `core/07-launch.md` 规定。`periphery`、`script`、`love20-anvil`、`interface-test`、`interface`、`batch-transfer` 和 `docs` 使用各自的 `README.md`、部署说明或测试说明，不承担协议规格入口职责。`compatibility` 使用独立的 `SPEC.md`，因为它有固定的测试边界、判定标准和跨仓库发布门槛，但仍不提供生产运行时依赖。

## 规格最小章节

所有合约的一次性初始化入口统一命名为 `init(...)`；`Launch.init(...)` 同时完成依赖绑定和首个代币部署，不提供单独的首币启动入口。

每个协议代码库的拆分规格至少包含：

- 范围与非目标
- 依赖和跨仓库接口
- 参与主体与权限
- 状态模型和不变量
- 公共写接口与只读接口
- 计算公式、单位和舍入规则
- 事件与错误
- 关键流程和失败原子性
- 验收场景

`action/docs/specs/` 应分别说明 `ActionTarget`、LP 行动、链群行动和链群服务行动；不要求所有执行合约共享相同的业务接口，但必须遵守 `ActionTarget` 和 `ActionRound` 的公共边界。

`compatibility/SPEC.md` 至少应记录：本地 Uniswap V2/WETH9 参考实现、目标网络外部地址、接口调用结果、储备和供应量变化、手续费/兑换报价差异、测试区块和提交。兼容性测试仓库不得被业务仓库反向导入。

## 规格迁移与修改流程

### 迁移前（代码库未创建）
- 规格维护在 `matt-gov/docs/specs/<repo>/`
- 所有修改在该目录内完成并提交到 matt-gov

### 迁移时（代码库首次创建）
- 将 `matt-gov/docs/specs/<repo>/` 原样复制到 `<repo>/docs/specs/`，保留拆分结构
- 在 matt-gov 中添加迁移记录（不再保留第二份可编辑规范）：
  ```markdown
  # 已迁移到 <repo>/docs/specs/
  迁移日期：YYYY-MM-DD
  目标提交：<repo>@<commit-hash>
  ```

### 迁移后（代码库已存在）
- 规格修改在 `<repo>/docs/specs/` 完成
- 跨仓库接口变更时：
  1. 在发起变更的仓库提交修改并更新其拆分规格
  2. 在受影响的仓库提交对应修改并更新其拆分规格
  3. 在 matt-gov 的 `docs/repositories.md` 追加变更记录
  4. PR 描述必须列出所有受影响的仓库和对应提交

### 验收门槛
跨仓库接口变更的 PR 必须满足：
- 所有受影响仓库的拆分规格已同步更新
- matt-gov 的 repositories.md 已记录变更
- 相关集成测试通过（如 love20-anvil）

## 更新规则

- 规格只描述当前 BSC 设计，不以旧代码作为理解前置条件。
- 代码行为变化和对应 `docs/specs/` 拆分规格更新必须在同一提交中完成。
- 跨仓库接口变化必须同步更新受影响代码库的规格，并在 `matt-gov` 记录依赖关系和验收影响。
- `.scratch` 中的历史讨论可以引用旧名称；票据 `Answer` 和地图只保存决策来源，不是实现规范。当前实现只以目标代码库当前 `docs/specs/` 拆分规格和本仓库组织约束为准。
