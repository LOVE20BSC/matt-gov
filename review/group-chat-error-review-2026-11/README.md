# `group-chat/src` 错误赋值与发送 Review（2026-11）

> 基线：`group-chat@72d7226`（2026-11-03）。`GovVotedBanSource`、`TokenManagerBase`、`TokenActionScopeManagerBase` 的行号按该提交；`TokenActionScopeManagerBase:145/:148` 为 state 卷 `TAM-01` 之后的当前行号。
> 判据：`matt-gov/docs/error-standards.md`、`matt-gov/docs/dev-standards.md`。
> 范围：仅 `group-chat/src`；core / action 的错误卷此前已单独处理，不跨仓。
> 声明口径：覆盖 8 个实现模块、7 个声明接口；`GOV_VOTED_BAN_SOURCE` 与 `TOKEN_MANAGER_BASE` 的声明均 local-first。

## 全局计数

**本卷组共 31 条 = Low 3 / Info 28。** 其中：

- 既有 5 份文本实际 24 条（GroupChat 8 + GroupMember 3 + GroupAdmin 3 + GroupChatBanList 4 + ManagerBase 6）；
- 新补 3 个模块 6 条（GovVotedBanSource 3 + TokenActionScopeManagerBase 1 + TokenManagerBase 2）；
- 跨卷关闭项 1 条（`ActionNotExist` 语义复用，已由 state 卷 `TAM-01` 关闭，不新生成 ID）。

按处置分类：

| 处置 | 条数 | 说明 |
| --- | --- | --- |
| 需裁决 | 2 | `E-MB-01`（已按方案 A 落地）、`E-BL-01`（已按方案 A 落地） |
| 可直接登记 | 19 | 见各卷「已登记」行；落点已写入 `docs/specs/group-chat/` |
| 可不处理 | 5 | `E-GC-03`、`E-GC-05`、`E-GC-06`、`E-GVB-03`、`E-TMB-01`，均为已知边界 |
| 已由其他卷关闭 | 5 | `E-GC-01`、`E-GM-02`、`E-GA-02`、`E-BL-03`、`ActionNotExist` 复用 |

## 卷清单

| 文件 | 覆盖 | 声明 / 站点 | 条数 |
| --- | --- | --- | --- |
| [GroupChat.md](GroupChat.md) | `GroupChat.sol` | 22 / 22 | 8（2 Low / 6 Info） |
| [GroupMember.md](GroupMember.md) | `GroupMember.sol` | 3 / 3 | 3（0 / 3） |
| [GroupAdmin.md](GroupAdmin.md) | `GroupAdmin.sol` | 4 / 4 | 3（0 / 3） |
| [GroupChatBanList.md](GroupChatBanList.md) | `GroupChatBanList.sol` | 4 / 4 | 4（0 / 4） |
| [ManagerBase.md](ManagerBase.md) | `ManagerBase.sol` | 4 / 3 本站点 + 1 派生站点 | 6（1 Low / 5 Info） |
| [GovVotedBanSource.md](GovVotedBanSource.md) | `GovVotedBanSource.sol` | 7 / 10 | 3（0 / 3） |
| [TokenActionScopeManagerBase.md](TokenActionScopeManagerBase.md) | `TokenActionScopeManagerBase.sol` | 1 / 2 | 1（0 / 1） |
| [TokenManagerBase.md](TokenManagerBase.md) | `TokenManagerBase.sol` | 1 / 1 | 2（0 / 2） |

## 已拍板裁决

- `E-MB-01` → 方案 A：删除 `ManagerMintCostChanged` 声明与 `actual == expected` 比较（`mint` 实付返回值直接丢弃），不变量移到测试——`testT161` 走真实 `MemberNFT` 路径断言 LOVE20 实扣 == `calculateMintCost` 报价。理由：不变量在协议内不可达，误配属部署期风险（部署脚本已校验 MemberNFT 一致性），测试覆盖更合适且省字节。
- `E-BL-01` → 方案 A：保持 ABI，仅在 05-chat-types 与 07-events-errors 登记「按入参顺序第一个零值、无载荷、定位靠回放」。

## 计数差异说明

- GroupChat 自报 2 Low / 5 Info = 7，实际 8：`E-GC-02` 表内误标 Info（正文判 Low），且“配置入口状态先于依赖参数”原先无 ID，已补为 `E-GC-08`。
- ManagerBase 自报 1 Low / 4 Info = 5，实际 6：`E-MB-06` 未进入正文与汇总。
- 因此 22（自报）→ 23（有 ID）→ 24（正文实际）；23 这个旧口径只数了有 ID 的条目。
- 全局量级：Phase 1 头条「31 = Low 2 / Info 29」是 `E-GC-02` 仍按旧表记 Info 时的口径；按裁决统一为 Low 后，逐卷求和为 Low 2（GroupChat）+ 1（ManagerBase）= **3**，Info 28，合计仍 31，与各卷表格逐条一致。
