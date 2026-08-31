# LOVE20BSC 规格文档结构

本文件定义 BSC 版各代码库规格文档的组织方式。各代码库的 `SPEC.md` 是该代码库当前行为的规范入口；本文件只维护跨仓库的文档边界，不重复协议细节。

在 `core`、`action`、`group-chat` 代码库正式创建前，规格暂存于本仓库的 `docs/specs/`：`core.md`、`action.md`、`group-chat.md` 分别对应未来代码库根目录的 `SPEC.md`。代码库创建后，将对应文件原样移入目标代码库并在本仓库保留迁移记录；不得在两个位置长期维护两份可能分叉的规范。

## 规范层级

1. **代码库规格**：由目标代码库根目录的 `SPEC.md` 维护本代码库的当前职责、状态模型、公开接口、公式、错误/事件、依赖和验收场景。
2. **组织约束**：由本仓库的 `CONTEXT.md`、`docs/repositories.md` 和 `docs/acceptance.md` 维护共享术语、仓库边界、依赖方向和跨仓库验收要求。
3. **迁移依据**：`.scratch/bsc-protocol-migration/` 保存决策过程、旧代码来源和迁移证据，属于非规范材料。实现者不需要阅读旧仓库才能理解 BSC 规格。

## 代码库规格范围

| 代码库 | 规格入口 | 规格内容 |
| --- | --- | --- |
| `core` | 创建前 `matt-gov/docs/specs/core.md`；创建后 `core/SPEC.md` | `Stake`、`Submit`、`Vote`、`Mint`、`MemberNFT`、`Phase`、基础子币发射和跨层回调边界 |
| `action` | 创建前 `matt-gov/docs/specs/action.md`；创建后 `action/SPEC.md` | `ActionTarget`、`ActionRound`、LP 行动、链群行动、链群服务行动及行动层激励 |
| `group-chat` | 创建前 `matt-gov/docs/specs/group-chat.md`；创建后 `group-chat/SPEC.md` | 群聊业务和 **Group Chat Delegate** |

`launch` 本阶段不创建，因此暂不建立 `launch/SPEC.md`。`compatibility`、`periphery`、`script`、`love20-anvil`、`interface-test`、`interface`、`batch-transfer` 和 `docs` 使用各自的 `README.md`、部署说明或测试说明，不承担协议规格入口职责。

## `SPEC.md` 最小章节

每个协议代码库的 `SPEC.md` 至少包含：

- 范围与非目标
- 依赖和跨仓库接口
- 参与主体与权限
- 状态模型和不变量
- 公共写接口与只读接口
- 计算公式、单位和舍入规则
- 事件与错误
- 关键流程和失败原子性
- 验收场景

`action/SPEC.md` 应在同一文件内分别说明 `ActionTarget`、LP 行动、链群行动和链群服务行动；不要求所有执行合约共享相同的业务接口，但必须遵守 `ActionTarget` 和 `ActionRound` 的公共边界。

`compatibility` 的测试说明至少应记录：本地 Uniswap V2/WETH9 参考实现、目标网络外部地址、接口调用结果、储备和供应量变化、手续费/兑换报价差异、测试区块和提交。兼容性测试仓库不得被业务仓库反向导入。

## 更新规则

- 规格只描述当前 BSC 设计，不以旧代码作为理解前置条件。
- 代码行为变化和对应 `SPEC.md` 更新必须在同一提交中完成。
- 跨仓库接口变化必须同步更新受影响代码库的规格，并在 `matt-gov` 记录依赖关系和验收影响。
- `.scratch` 中的历史讨论可以引用旧名称，但当前实现只以代码库 `SPEC.md`、组织约束和票据 `Answer` 为准。
