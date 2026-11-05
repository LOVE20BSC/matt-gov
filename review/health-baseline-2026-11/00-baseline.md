# 全仓健康基线快照（2026-11）

- 采集时间：2026-11-05（Asia/Shanghai）
- 采集方式：只读。未修改任何受版本控制的文件，未提交、未推送、未改动 `foundry.lock` 与子模块指针；仅生成本文件。
- 工具链：`forge 1.8.1`（commit `982849d3140c01fd3b72905759581a132df7aa98`），`solc 0.8.37`，`evm_version = osaka`，optimizer 200 runs，`bytecode_hash = none`，`cbor_metadata = false`。
- 构建产物写入各仓已忽略的 `out/`、`cache/`，不计入版本控制。

## 1. 结论

**全绿。** 三仓 `forge build --force --deny warnings` 均成功、`forge lint` 均 0 发现、测试 513 / 477 / 158 全部通过；全部检查脚本 0 违规；四仓工作树干净且与远端 `origin/main` 完全同步（0 ahead / 0 behind）。与任务给定的已知基线**没有任何数值偏离**。唯一需要持续关注的是 `GroupActionExecutor` 的 2,451 B 运行时代码余量。

## 2. 三仓门禁

| 仓 | build --force --deny warnings | solc 告警（项目 / lib） | foundry 预处理 WARN | forge lint 发现 | 测试 passed / failed / skipped | 套件数 |
|---|---|---|---|---|---|---|
| core | 成功（exit 0） | 0 / 0 | 1 块（7 条 solar 诊断） | 0 | 513 / 0 / 0 | 21 |
| action | 成功（exit 0） | 0 / 0 | 1 块（7 条 solar 诊断） | 0 | 477 / 0 / 0 | 35 |
| group-chat | 成功（exit 0） | 0 / 0 | 1 块（1 条 solar 诊断） | 0 | 158 / 0 / 0 | 13 |

关于「1 块 WARN」的说明：

- 来源是 `forge` 内部的 `DynamicTestLinkingPreprocessor::preprocess`（solar 解析器）日志，不是 solc 告警，`--deny warnings` 不会拦截，也不影响编译产物。
- 诊断内容固定为两类：(a) `lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol` 中 6 个 ERC20 错误的「already declared」（core/action 各 6 条，group-chat 不触发）；(b) `MemberNFT.sol` 的 `ERC721(...)` 继承写法被解析为「expected base class or modifier, found abstract contract」（core 指向 `src/MemberNFT.sol:48`，action/group-chat 指向各自的 `lib/.../core/src/MemberNFT.sol:48`）。
- 结论：属于 lib/ 依赖与 foundry 解析器的既有噪声，三仓一致；项目自身 solc 告警为 0。

`forge fmt --check` 仅作参考、不作门禁（项目规范明确不以 fmt 为基准）：

| 仓 | 涉及文件数 | 删除行 | 新增行 | 变更行合计 |
|---|---|---|---|---|
| core | 40 | 1,892 | 1,225 | 3,117 |
| action | 62 | 2,686 | 1,454 | 4,140 |
| group-chat | 30 | 413 | 236 | 649 |

## 3. 体积（runtime 字节 / EIP-170 余量）

口径：`forge build --sizes` 输出中的 concrete contract；余量 = 24,576 − runtime。抽象合约（`ExecutorBase`、`ManagerBase`、`TokenScopeManagerBase`、`TokenActionScopeManagerBase`、`TokenManagerBase`）与库（`ActionRoundAxis`、`GroupRecipients`、`GroupServiceStorage`、`GroupActionJoin`、`MemberOwner`、`LpRoundAxis`、`GroupActionManager`、`GroupActionStorage`、`GroupServiceRoundAxis`、`GroupActionRoundAxis`、`GroupActionVerify` 等）均未出现在 sizes 输出中，故不入表。以下仅统计各仓 `src/` 内自有可部署合约；测试专用 mock/harness 见 §3.4。

### 3.1 core（8 个）

| 合约 | Runtime (B) | 余量 (B) | Initcode (B) | Initcode 余量 (B) |
|---|---|---|---|---|
| LOVE20Token | 2,454 | 22,122 | 3,997 | 45,155 |
| Launch | 12,292 | 12,284 | 12,320 | 36,832 |
| MemberNFT | 11,510 | 13,066 | 12,185 | 36,967 |
| Mint | 10,353 | 14,223 | 10,381 | 38,771 |
| Phase | 3,951 | 20,625 | 4,572 | 44,580 |
| Stake | 14,658 | 9,918 | 14,686 | 34,466 |
| Submit | 10,876 | 13,700 | 10,904 | 38,248 |
| Vote | 6,610 | 17,966 | 6,638 | 42,514 |

### 3.2 action（4 个）

| 合约 | Runtime (B) | 余量 (B) | Initcode (B) | Initcode 余量 (B) |
|---|---|---|---|---|
| ActionTarget | 11,235 | 13,341 | 11,263 | 37,889 |
| GroupActionExecutor | 22,125 | 2,451 | 23,450 | 25,702 |
| GroupServiceExecutor | 18,727 | 5,849 | 19,990 | 29,162 |
| LpExecutor | 14,043 | 10,533 | 15,012 | 34,140 |

补充：action 的 sizes 输出还包含 8 个来自 `lib/core` 的依赖合约（`LOVE20Token` 2,454、`Launch` 12,292、`MemberNFT` 11,510、`Mint` 10,353、`Phase` 3,951、`Stake` 14,658、`Submit` 10,876、`Vote` 6,610），数值与 core 侧完全一致，不计入 action 自有统计。

### 3.3 group-chat（12 个）

| 合约 | Runtime (B) | 余量 (B) | Initcode (B) | Initcode 余量 (B) |
|---|---|---|---|---|
| AdminBanSource | 373 | 24,203 | 504 | 48,648 |
| GovVotedBanSource | 7,568 | 17,008 | 7,793 | 41,359 |
| GroupAdmin | 3,904 | 20,672 | 4,108 | 45,044 |
| GroupChat | 14,127 | 10,449 | 14,498 | 34,654 |
| GroupChatBanList | 4,274 | 20,302 | 4,551 | 44,601 |
| GroupJoinScopeSource | 587 | 23,989 | 776 | 48,376 |
| GroupMember | 3,182 | 21,394 | 3,466 | 45,686 |
| GroupMemberScope | 373 | 24,203 | 504 | 48,648 |
| TokenActionGovManager | 10,361 | 14,215 | 11,727 | 37,425 |
| TokenActionMainManager | 10,536 | 14,040 | 11,909 | 37,243 |
| TokenGovManager | 7,727 | 16,849 | 8,902 | 40,250 |
| TokenMainManager | 8,564 | 16,012 | 9,749 | 39,403 |

补充：`MemberNFT` 11,510 来自 `lib/action/lib/core`，属依赖合约，不计入本仓自有统计。

### 3.4 测试专用条目（不计入可部署统计）

| 仓 | sizes 条目总数 | 自有可部署 | 依赖合约 | 测试专用 mock/harness |
|---|---|---|---|---|
| core | 54 | 8 | 0 | 46 |
| action | 65 | 4 | 8 | 53 |
| group-chat | 37 | 12 | 1 | 24 |

测试专用条目（`Mock*`、`*Harness`、`TestBase`、`Caller`、`FakeToken`、`RealV2*`、`StressPairFactory` 等）体积均远低于 EIP-170，无需逐行跟踪；需要时用同一命令 `forge build --sizes` 可复现完整清单。

## 4. 检查脚本

| 脚本 | 命令 | 关键计数 | violations / mismatches | exit |
|---|---|---|---|---|
| check-events（core） | `python3 core/script/events/check-events.py` | 28 events / 23 families；manifest、decl、emit、keys 全 OK | 0 | 0 |
| check-events（action） | `python3 action/script/events/check-events.py` | 34 events / 32 families；50 个 `expectEmit` 全部带 emitter | 0 | 0 |
| check-events（group-chat） | `python3 group-chat/script/events/check-events.py` | 19 events / 17 families；manifest、decl、emit、keys 全 OK | 0 | 0 |
| check_errors | `python3 matt-gov/script/check_errors.py --check` | declarations 239 / signatures 199 / unique 188 | 0 | 0 |
| check_error_tests（core） | `python3 matt-gov/script/check_error_tests.py core` | errors 76 / untested 0 | 0 | 0 |
| check_error_tests（action） | `python3 matt-gov/script/check_error_tests.py action` | errors 90 / untested 0 | 0 | 0 |
| check_error_tests（group-chat） | `python3 matt-gov/script/check_error_tests.py group-chat` | errors 33 / untested 0 | 0 | 0 |
| check_doc_payloads | `python3 matt-gov/script/check_doc_payloads.py` | errors declared 188 / refs checked 204 | 0 | 0 |
| check_caller_auth（core） | `python3 matt-gov/script/check_caller_auth.py core/src` | — | 0 | 0 |
| check_caller_auth（action） | `python3 matt-gov/script/check_caller_auth.py action/src` | — | 0 | 0 |
| check_caller_auth（group-chat） | `python3 matt-gov/script/check_caller_auth.py group-chat/src` | — | 0 | 0 |
| check_naming（附加） | `python3 matt-gov/script/check_naming.py --check` | 0 known / 0 new | 0 | 0 |

口径说明：任务指定的 `matt-gov/script/check_events.py` 在本仓不存在；事件检查脚本实际按仓放在 `<repo>/script/events/check-events.py`，上表按实际位置执行。`check_caller_auth.py` 同时指向三仓 `src` 的合并运行结果同样为 0 违规。

## 5. Git 与指针

### 5.1 四仓状态

| 仓 | 分支 | HEAD | 标题 | `git status --short` | ahead / behind | 远端 |
|---|---|---|---|---|---|---|
| core | main | 6042652 | refactor(core): name precision and index literals | 空 | 0 / 0 | origin/main |
| action | main | 9221df8 | test(action): cover verifier id shape check | 空 | 0 / 0 | origin/main |
| group-chat | main | f75b2f5 | refactor(group-chat): rename SenderBanChanged to AdminSenderBanChanged | 空 | 0 / 0 | origin/main |
| matt-gov | main | 9e1d053 | docs(group-chat): 事件改名 AdminSenderBanChanged | 空 | 0 / 0 | origin/main |

### 5.2 子模块指针链与 `foundry.lock`

| 关系 | gitlink 值 | 对应仓 HEAD / lock rev | 一致性 |
|---|---|---|---|
| action → `lib/core` | `60426521fe8d7ff35deee9f8c718acd118caae59` | core HEAD `6042652`；`action/foundry.lock` 的 `lib/core.rev` 同值 | 一致 |
| group-chat → `lib/action` | `9221df8fdecae379d8b7692050a3a1133325e226` | action HEAD `9221df8`；`group-chat/foundry.lock` 的 `lib/action.rev` 同值 | 一致 |
| group-chat/`lib/action` → `lib/core` | `60426521fe8d7ff35deee9f8c718acd118caae59` | core HEAD `6042652`；嵌套 `foundry.lock` 的 `lib/core.rev` 同值 | 一致 |
| core → `lib/forge-std` / `lib/libs` / `lib/openzeppelin-contracts` | `bf647bd6…` (v1.16.2) / `3e41f246…` / `5fd1781b…` (v5.6.1) | `core/foundry.lock` 三项 rev 均同值 | 一致 |

补充：`matt-gov` 无子模块、无 `foundry.lock`。四仓 `git submodule status` 均无 `-`/`+` 前缀，代表子模块工作区与指针一致且干净。

## 6. 与已知基线的差异

**无差异。** 给定基线逐项复核结果：

| 基线项 | 给定基线 | 实测 | 结果 |
|---|---|---|---|
| 测试数 core / action / group-chat | 513 / 477 / 158 | 513 / 477 / 158 | 一致 |
| sizes `ActionTarget` | 11,235 | 11,235 | 一致 |
| sizes `GroupActionExecutor` | 22,125（余 2,451） | 22,125（余 2,451） | 一致 |
| sizes `GroupServiceExecutor` / `LpExecutor` | 18,727 / 14,043 | 18,727 / 14,043 | 一致 |
| sizes `GroupChat` / `GroupMember` / `GroupAdmin` / `GroupChatBanList` / `GovVotedBanSource` | 14,127 / 3,182 / 3,904 / 4,274 / 7,568 | 同左 | 一致 |
| check_errors | 239 / 199 / 188 / 0 | 239 / 199 / 188 / 0 | 一致 |
| check_error_tests group-chat | 33 / 0 未测 | 33 / 0 未测 | 一致 |
| check_doc_payloads | 188 / 204 / 0 | 188 / 204 / 0 | 一致 |
| check_caller_auth | 0 | 0 | 一致 |
| check_events group-chat | 19 events / 17 families | 19 events / 17 families | 一致 |

非数值性变化（不影响上述基线，仅作口径说明）：`group-chat` 在 events 卷之后还有两笔已推送提交 —— `c2b9987` 给 `GovSenderBanChanged` 增加 `totalVoteWeight` 字段、`f75b2f5` 将 `SenderBanChanged` 改名为 `AdminSenderBanChanged`（`matt-gov` 对应 `9e1d053`）。事件计数、测试数、体积均未因此变化。

## 7. 风险提示

1. **`GroupActionExecutor` 余量 2,451 B**：全仓生产合约中最紧，约为 EIP-170 上限的 10%。历史上「两个回调搬回执行器」会超限，任何新增逻辑都需要先做体积估算。次紧的是 `GroupServiceExecutor` 5,849 B、`Stake` 9,918 B、`GroupChat` 10,449 B。
2. **非零的 foundry 预处理 WARN**：三仓各 1 块（core/action 各 7 条 solar 诊断，group-chat 1 条），全部来自 `lib/` 与解析器既有行为，非 solc 告警；不影响 `--deny warnings` 的通过判定，但会在 CI 日志中持续出现，若未来 CI 将 stderr 视为失败需要单独收敛。
3. **`check_caller_auth` 的口径边界**：脚本只检查 `msg.sender` 比较是否位于 `only*` 修饰器内，无法覆盖「无 `msg.sender` 比较的无鉴权写入」。`group-chat/src/sources/ban/GovVotedBanSource.sol:62` 的 `refreshVoteByTargetSenderId` 仍属此类，0 违规不代表该路径已鉴权，需继续靠人工核对。
4. **`forge fmt --check` 漂移较大**（core 3,117 / action 4,140 / group-chat 649 行变更）：项目规范明确不以 fmt 为门禁，此处仅记录参考值，不要据此在无关改动中批量格式化。
5. **测试专用 mock/harness 未计入可部署统计**：core 46、action 53、group-chat 24 个条目属于测试代码，其体积变化不应触发部署侧告警，反之也不应被当作生产余量。
6. **四仓均已推送**：0 ahead / 0 behind，工作树干净，本快照可作为后续对照的最新起点。
