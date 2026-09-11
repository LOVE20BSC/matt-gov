# 三层 ABI 对账收口

本文件是实现前的 ABI 开工门槛。旧代码只读，固定提交见 [`docs/repositories.md`](../../docs/repositories.md#旧代码基线)；新 ABI 以 [`interfaces/`](../../interfaces/) 为唯一来源。逐模块的符号去向见 [`core.md`](core.md)、[`action.md`](action.md) 和 [`group-chat.md`](group-chat.md)。

## 机器统计

统计对象是接口声明条数；旧侧排除 `LOVE20TKM/group-chat/src/interfaces/external/` 和 `LOVE20TKM/core/src/uniswap-v2-core/interfaces/`，新侧包含继承文件中的直接声明，不对同名声明去重。

| 层 | 新文件/接口 | 新函数 | 新事件 | 新错误 |
| --- | ---: | ---: | ---: | ---: |
| Core | 11 / 11 | 152 | 29 | 58 |
| Action | 5 / 5 | 137 | 24 | 72 |
| Group Chat | 12 / 15 | 139 | 23 | 76 |
| **合计** | **28 / 31** | **428** | **76** | **206** |

旧侧按仓库原始接口目录统计如下（去除 `group-chat` 的 external 镜像和 `core` 的 Uniswap V2 外部接口）：

| 旧仓库 | 函数 | 事件 | 错误 |
| --- | ---: | ---: | ---: |
| `LOVE20TKM/core` | 201 | 33 | 83 |
| `LOVE20TKM/extension` | 59 | 13 | 24 |
| `LOVE20TKM/extension-group` | 178 | 12 | 59 |
| `LOVE20TKM/extension-lp` | 6 | 0 | 3 |
| `LOVE20TKM/group` | 69 | 20 | 37 |
| `LOVE20TKM/group-chat` | 142 | 22 | 68 |
| **合计** | **655** | **100** | **274** |

旧侧完整总数与 [`README.md`](README.md#规模对比) 一致。三层新接口的统计按当前文件归属计算；旧接口按仓库列出，具体去向由分层差异表逐项说明。

## 对账状态

| 层 | 函数 | 事件 | 错误 | 结构体/枚举 | 状态 |
| --- | --- | --- | --- | --- | --- |
| Core | 每个旧声明均有保留、改名、改参、删除或新增去向 | 字段级差异已列 | 三个 Submit selector 已保留，其余已列 | `Action*` → `Proposal*`、Stake 账本重构 | **已完成** |
| Action | 单例作用域、`memberId` 化和 17 组索引已列 | Executor 事件已列 | 旧 GroupJoin/Manager/Verify 错误已列 | GroupConfig、VerifierApplication 已列 | 已完成 |
| Group Chat | 地址主体删除、管理器合并和索引保留已列 | 审计地址与 memberId 差异已列 | 三个 scope/ban 适配接口已补回 | ChatInfo、Message、RoundSpan 已列 | 已完成 |

## Submit selector 裁决

`LOVE20TKM/core/src/interfaces/ILOVE20Submit.sol` 的以下旧错误已保留到新接口，触发条件与旧实现一致：

| 旧错误 | 当前情况 | 实现影响 |
| --- | --- | --- |
| `CannotSubmitAction()` | `canSubmit`/`submit` 的门槛或资格不足 | 固定旧 selector |
| `AlreadySubmitted()` | 同一 Proposal 同轮重复推举 | 固定旧 selector |
| `OnlyOneSubmitPerRound()` | 同一成员同轮再次推举 | 固定旧 selector |

本轮裁决：保留 3 个旧 selector，作为 BSC 的专用错误；已同步接口、规格和差异文档。

## 开工判定

- [x] 旧提交已固定，旧仓库未修改。
- [x] 新接口可用 `solc 0.8.17` 全量编译。
- [x] 三层函数、事件、错误均有差异文档和删除理由。
- [x] Submit 三个错误 selector 完成裁决并同步 ABI、规格和差异文档。

三层 ABI 对账已冻结；随后可创建 `core`、`action`、`group-chat` 三个代码库骨架。
