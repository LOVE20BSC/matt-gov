# action/ 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/**`。
> 范围：`action/src/` 的 14 个实现文件 + `src/interfaces/` 的 9 个 `I<Name>Errors`。
> 处置：本轮是错误卷的落地窗口（W1）。五条裁决按「改 ABI」执行，四处校验顺序按默认序重排，其余 35 条按卷内方向落地（改 ABI / 改规格 / 登记）。改动范围限错误声明、载荷、错误表、`registry/errors.{json,md}` 与测试载荷；函数签名与事件不动。逐条落点见各分卷的「处置」节。

## 1. 任务与口径

对每个合约的**每个自定义错误**，穷举合约内所有 revert 站点（“发送”），记录站点判据与载荷实参（“赋值”），再按 error-standards 检查：声明归属、一条件一错误、命名、载荷、校验顺序、可达性、透传面与测试覆盖。

“赋值”指 revert 时写入 payload 的表达式；“发送”指 `revert <Error>(...)` 站点。`assert`（Panic）、裸 `require`、`assembly` 原样 rethrow 不计入错误目录，另在各合约报告的「已核对项 / 透传错误面」中说明。

库函数经 `delegatecall` 执行，`msg.sender` 与 storage 与 Executor 一致；站点按**源码文件**归属，不按调用链归属（例如 `GroupActionJoin` 的站点记在 `07`，不记在 `09`）。

## 2. 总览（916e146 基线 → W1 落地后）

| 合约 | 声明 | 站点 | Medium | Low | Info | 报告 |
| --- | --- | --- | --- | --- | --- | --- |
| `ActionTarget.sol` | 15 | 20 | 0 | 0 | 3 | [01](01-ActionTarget.md) |
| `ExecutorBase.sol` | 12 | 11 | 0 | 0 | 2 | [02](02-ExecutorBase.md) |
| `LpExecutor.sol` | 10 | 16 | 0 | 0 | 4 | [03](03-LpExecutor.md) |
| `LpRoundAxis.sol` | 0 | 0 | 0 | 0 | 1 | [04](04-LpRoundAxis.md) |
| `GroupActionStorage.sol` | 0 | 0 | 0 | 0 | 1 | [05](05-GroupActionStorage.md) |
| `GroupActionManager.sol` | 12 | 25 | 0 | 4 | 1 | [06](06-GroupActionManager.md) |
| `GroupActionJoin.sol` | 17 | 27 | 0 | 1 | 4 | [07](07-GroupActionJoin.md) |
| `GroupActionVerify.sol` | 11 | 19 | 0 | 2 | 3 | [08](08-GroupActionVerify.md) |
| `GroupActionExecutor.sol` | 9 | 4 | 0 | 0 | 2 | [09](09-GroupActionExecutor.md) |
| `GroupActionRoundAxis.sol` | 0 | 0 | 0 | 0 | 1 | [10](10-GroupActionRoundAxis.md) |
| `GroupRecipients.sol` | 8 | 8 | 0 | 0 | 3 | [11](11-GroupRecipients.md) |
| `GroupServiceStorage.sol` | 0 | 0 | 0 | 0 | 1 | [12](12-GroupServiceStorage.md) |
| `GroupServiceExecutor.sol` | 11 | 16 | 0 | 1 | 4 | [13](13-GroupServiceExecutor.md) |
| `MemberOwner.sol` | 0 | 0 | 0 | 0 | 2 | [14](14-MemberOwner.md) |
| **合计** | **105** | **146** | **0** | **8** | **32** | 14 份 |

> 「声明」按**本地接口**计数（`I<Name>Errors`），不含跨模块复用，跨接口同名同签名各计一次；「站点」按源码文件内的 `revert <Error>(` 计数。基线为 97 声明 / 83 唯一签名 / 133 站点；W1 后 105 声明、`registry/errors.md` 报 238 声明 / 198 签名记录 / 186 唯一签名（含 core 与 group-chat，口径见附 A.2）。
> 严重度分布维持原口径 **0 Medium / 8 Low / 32 Info**：8 条 Low 中 5 条经 W1 改 ABI 消除（E-GAM-01/04、E-GAJ-01、E-GAV-01、E-LP-01+E-GSE-04），2 条按默认序重排消除（E-GAM-02/03 与 E-GAV-02），1 条删除不可达站点消除（E-GSE-01）。无升级/降级。

## 3. 横切结论

### X-01 覆盖完整，无未声明错误、无死声明

97 条声明全部至少有一个站点，133 个站点全部命中本地接口的声明；`check_errors.py --check` 0 violations，`check_error_tests.py` action 83 errors / 0 untested。无裸 `require`、无裸 `revert;`、无 `assert`。同名同签名跨模块重复声明 9 组（`InvalidTargetDataShape`×4、`TargetDataLengthMismatch`×4、`NotJoined`×3、`NotMemberOwner`×2、`NotGroupOwner`×2、`GroupNotExist`×2、`ZeroJoinTokenAddress`×2、`ZeroParticipationAmount`×2、`WithdrawAmountExceeded`×2），符合 §1「本地声明、selector 相同、不跨仓导入」。

### X-02 没有 Medium：不存在入口砖化路径

所有站点都在会整笔回滚的交易内。四处「交互后判定」都不留残留：

| 站点 | 交互 | 回滚后状态 |
| --- | --- | --- |
| `LpExecutor:507` | `mintActionReward` → Mint 铸造 + 预留 | 整笔回滚，Mint 的 `_proposalMinted` / `_totalRewardReserved` 一并撤销 |
| `GroupActionExecutor:729` | 同上 | 同上 |
| `GroupServiceExecutor:720` / `:730` | 同上（`:730` 不可达，见 X-08） | 同上 |
| `GroupRecipients` 的 `ownerOf` / `safeTransfer`（循环内） | 逐接收人转账 | 整笔回滚，已发的转账与事件一并撤销；`MemberNFT` 无销毁入口，`ownerOf` 不会因 NFT 消失而失败 |

因此本次无 High/Critical；8 条 Low 全部是「与强制条款冲突」或「不可达 / 不可定位」，不涉及资金归属。

### X-03 「一错多因 / 一名多义」四处：3 条已裁、1 条本非缺陷

| 位置 | 原形态 | 处置 | 报告 |
| --- | --- | --- | --- |
| `GroupNotExist(0)`（4 站点） | 「参数为零」与「群不存在」共用 selector | **已裁**：新增 `ZeroGroupId()`，4 个站点全换；规格 03 从「两者归一」改为分开，05 错误表同步（**规格让步**） | E-GAJ-01（Low） |
| `TargetDataLengthMismatch(6\|7, actual)` | `expected` 同时承担下界与上界 | **已裁**：拆为 `InsufficientTargetDataItems(count, minCount)` / `TooManyTargetDataItems(count, maxCount)`；按实际站点同步 4 份接口（`IActionTarget` 只保留下界，因为它没有上界站点），全部站点改写；规格 07 让步 | E-GAM-01（Low） |
| `ActionMaxJoinAmountExceeded(…, 0)` | 「额度用完」与「本轮不可加入」（无票 / 比例 0）同形 | **本非缺陷**：上限载荷固定为 `0`，成因差异可由 `maxJoinAmount` 与治理票视图推导；按 X-09 在 03 登记 | E-GAJ-02（Info） |
| `MemberActionRewardUnavailable` | 结果条件，三种（LP/GroupAction）到五种（Service）成因 | **已裁**：按 core `E-MNT-02` 三分法拆为 `MemberHasNoVote` / `MemberRewardPoolEmpty` / `MemberRewardRoundedToZero`；命名与载荷和 core 一致；同时删除 `GroupServiceExecutor` 不可达站点 | E-LP-01 / E-GSE-04（Info） |

两处**规格让步**（`GroupNotExist(0)` 与 `TargetDataLengthMismatch`）已随 W1 改规格，冲突消除。action 侧三分的三个错误与 core `IMintErrors` 同名同签名（不含 `actionId`），受协议级「一名一签名」约束；执行器本身已按行动隔离，额外字段会在 `check_errors.py` 报「同名多签名」。

### X-04 校验顺序：按默认序重排，非缺陷判定

§5 固定为「鉴权 → 参数 → 存在性 → 状态/资格 → 账本/交互 → 不变量」，并允许模块自定义但**必须写明理由**。本轮六处全部选择「按默认序重排」，并为每处补了断言新顺序的测试：

| 入口 | 重排后的顺序 | 新增/调整的断言 | 报告 |
| --- | --- | --- | --- |
| `GroupActionManager.activateGroup` | 鉴权 → **参数** → 存在性 → 状态 → 轮次 → 资格 | `testActivateGroupChecksRoundBeforeEligibility`（phase 1 + 已创建行动 → `RoundNotStarted(1, 0)`）；`testActivateGroupReverts` 增「已激活 + 零 minJoinAmount → `ZeroMinJoinAmount`」 | E-GAM-02（Low） |
| `GroupActionManager.setGroupConfig` | 鉴权 → **参数** → 状态 | `testUpdateGroupConfigAndReverts` 增「未激活群 + 零配置 → `ZeroMinJoinAmount`」 | E-GAM-03（Low） |
| `GroupActionVerify._checkApplicationSubmission` | 轮次 → **参数** → 存在性 → 资格 | `testApplicationChecksDescriptionBeforeActionExistence`（未创建行动 + 1025 字节描述 → `DescriptionTooLong(1025, 1024)`） | E-GAV-02（Low） |
| `GroupRecipients._setRecipients` | **参数** → 存在性 → 状态 | `testSetRecipientsRejectsUnknownSourceAction` 追加「重复成员 + 未知源 → `DuplicateMemberId`」 | E-GR-02（Info） |
| `GroupActionVerify._submitOriginScores` | 批级参数 → 状态 → 逐元素参数 | 锁定后另一验证者提交超限分数 → `ScoreLimitExceeded(0, 101, 100)` | E-GAV-03（Info） |
| `GroupServiceExecutor.join` / `exit` | join：轮次 → 存在性 → 已加入 → 资格；exit：**轮次** → 已加入 | `testJoinRejectsUncreatedActionBeforeQualification`（`ActionNotCreated`）；`testExitChecksTheRoundBeforeTheJoinState`（phase 1 未加入 → `RoundNotStarted(1, 0)`） | E-GSE-02 / E-GSE-03（Info） |

**变更前后的可观测错误差异**（同输入下先看到哪个错误）：

| 场景 | 重排前 | 重排后 |
| --- | --- | --- |
| 阶段未开始 + 有治理下限 + 激活 | `NoGovVotes` | `RoundNotStarted(1, 0)` |
| 已激活群 + 非法配置 | `GroupAlreadyActivated` | 配置错误（`ZeroMinJoinAmount` 等） |
| 未创建行动 + 超长说明 + 无票申请 | `ZeroVerifyVotes` | `DescriptionTooLong` →（通过后）`ActionNotCreated` |
| 未知源行动 + 重复成员 | `UnknownSourceAction` | `DuplicateMemberId` |
| 已锁定 + 越界分数 | `ScoreCountExceeded` / 逐元素 `ScoreLimitExceeded` | `RoundVerifierLocked` → 批级 → `ScoreCountExceeded` |
| phase 1 未加入即 `exit` | `NotJoined` | `RoundNotStarted(1, 0)` |
| 未创建行动 + 不合格成员 `join` | `NotQualified` | `ActionNotCreated` |

### X-05 无 selector 的失败形态与静默失败

| 位置 | 形态 | 可观测后果 | 报告 |
| --- | --- | --- | --- |
| `GroupActionManager:94` `abi.decode(targetData[6], (string[], string[]))` | 畸形数据 → **空 revert（0 字节）** | 创建回调没有任何 selector 可判；已实测（solc 0.8.37 下 `abi.decode` 失败回 `0x`） | 06 §4.3 / X-05 |
| `MemberOwner:21-23` | `assembly` 原样 rethrow | 群操作可能携带任意 revert data | E-MO-01（Info） |
| `MemberOwner:18-20` | 吞掉 `ERC721NonexistentToken` 并归一为 0 | 依赖故障可能被说成「群不存在」 | E-MO-02（Info） |
| `GroupActionVerify._markGroupVerified` | `verifiedGroups` 越过群数时**不置位** `roundVerified` | 该轮永久不可结算且不 revert | 08 §4.2 / 05 §4.2 |
| `GroupServiceStorage.cacheDenominator` | 缓存写侧判据是唯一防线 | 判据漂移会让第二人超额领取且不 revert | E-GSS-01（Info） |

前三项在 05/07 的透传登记表里都没有位置；`targetData[6]` 的形状校验只覆盖第 1～5 项（规格 05 明文如此），第 6 项完全交给 `abi.decode` 自己的空 revert。

### X-06 透传面登记不全

07 的透传登记只列了 `ERC721NonexistentToken` 与 `SafeERC20FailedOperation`。实测可达但未登记的通道：

| 通道 | 来源 | 可达入口 |
| --- | --- | --- |
| `ReentrancyGuardReentrantCall` | OZ `ReentrancyGuard` | 所有带 `nonReentrant` 的写入口 |
| `AddressEmptyCode` | OZ `Address`（`SafeERC20` 内部） | 所有 `safeTransfer(From)` |
| 任意 revert data | `MemberOwner` 的 `assembly` rethrow | 群管理、Service 的群 owner 入口 |
| `RoundNotEnded` / `ProposalBelowThreshold` / `ProposalPoolEmpty` / `ProposalRewardRoundedToZero` / `ZeroRecipientAddress` | `Mint.mintProposalReward` | 三个 Executor 的成员结算 |

`ProposalRewardAlreadyMinted` 已登记，其余 5 个 Mint 侧 selector 未登记。

### X-07 命名与载荷口径：2 条改 ABI、5 条文档口径

| 问题 | 位置 | 处置 | 级别 |
| --- | --- | --- | --- |
| `VerifierAlreadyLocked` 名称读作「该验证者已锁定」，条件是「已被他人锁定」，载荷不含被拒的 `verifierId` | `GroupActionVerify:707` | **改 ABI**：`RoundVerifierLocked(tokenAddress, actionId, round, lockedVerifierId)`，1 站点 1 接口，规格 07/05 同步 | Low（E-GAV-01） |
| `InvalidMinJoinAmount` 承载零值（§3 要求 `Zero<Field>`），载荷恒为 0 | `GroupActionManager` | **改 ABI**：`ZeroMinJoinAmount()`，1 站点 1 接口，规格 07 同步 | Low（E-GAM-04） |
| `ProposalNotVoted` 声明参数名 `proposalId`，实参是 `actionId` | `IActionTarget` | 文档口径：声明参数名改为 `actionId`（selector 不变） | Info（E-AT-03） |
| `TargetDataLengthMismatch(1, 0)` 的 `actual` 是字面量而非判据表达式 | `ActionTarget:429`、`:482` | 文档口径：随 E-GAM-01 拆分，两站点改写为 `InsufficientTargetDataItems(targetData.length, 1)`（字面量消除） | Info（E-AT-01） |
| `ScoreCountExceeded` 第三字段是真实成员数，不是 §4 要求的限定名 | `IGroupActionVerify` | 文档口径：第三参数字段名改为 `maxCount`（selector 不变），规格 07/05 同步 | Info（E-GAV-04） |
| `DistributionOverflow(configured, available)` 用「额度」名承载上限常量 | `IGroupRecipients` | 文档口径：字段名改为 `limit`（selector 不变），规格 07/06 同步 | Info（E-GR-01） |
| `RoundNotStarted(1, phase)` 与 `(1, 0)` 两种写法 | `ExecutorBase:86` | 文档口径：两写法载荷等价（`phase < 1` 时恒为 0），规格 00/07 以 `(1, 0)` 为规范写法，不改 src | Info（E-EB-01） |

全部 8 条 Low 中，7 条（E-GAM-01/02/03/04、E-GAJ-01、E-GAV-01/02）经 W1 消除，1 条（E-GSE-01）随不可达站点删除而消除。X-07 的 7 条里只有前两条改动 selector，其余 5 条只改声明字段名或规格措辞，ABI 选择器不变。

### X-08 两处不可达

- **不可达站点**：`GroupServiceExecutor:730` 的第二处 `MemberActionRewardUnavailable`。`:717` 的 `_settlement` 在 `serviceReward == 0` 时已提前返回；能走到 `:720` 且不回滚意味着 `serviceReward != 0`，而 `mintActionReward` 的返回值与 `actionReward` 的理论值同源（`Mint.mintProposalReward` 直接返回 `_proposalRewardCalculation`，`core/src/Mint.sol:203`），`_applyFormulas` 用相同输入重算必得相同结果（E-GSE-01，Low）。**处置：站点已删除**，唯一覆盖它的 `testMintedZeroAfterARichProjectionReverts`（用 mock 制造矛盾）一并删除。
- **不可达路径**：`GroupActionJoin._join` 的 `RoundNotStarted`。`phase < 2` 时不可能存在激活群（`activateGroup` 自身要求加入轮 ≥ 1），因此该路径先回 `GroupNotActive`（E-GAJ-03，Info）。**处置：保留并登记**于规格 03。

### X-09 规格与门禁缺口：全部闭环

- `check_error_tests.py` 只做「错误名在测试文本中出现」的检查，不证明 selector + 载荷断言。本轮抽查的 14 处 `abi.encodeWithSelector(<Error>.selector, <payload…>)` 全部逐字段对齐；W1 改 ABI 的每处都同步改了 selector 与载荷。
- 05/07 的「透传来源」表已补：`ReentrancyGuardReentrantCall`、`AddressEmptyCode`、`MemberOwner` 任意 revert data、Mint 侧 5 个 selector（X-06）。
- 03 已写 `removeProviderQuota` 的严格模式（E-GAJ-04）、`ActionMaxJoinAmountExceeded` 的 `limit = 0` 语义（E-GAJ-02）。
- 04 已写 `govRatioMultiplier` 无上界（E-LP-02）、`registerJoinState` 的账本先写顺序（E-LP-03）、两入口「无余额」双错误（E-LP-04）。
- 06 已写 `join` 对未创建行动的行为（E-GSE-03）、无 `Σ ratio == 0` 独立错误（E-GR-03）、缓存写入口唯一（E-GSS-01）。
- 00 / 02 / 05 / 06 已补 `E-EB-01`、`E-EB-02`、`E-LRA-01`、`E-GAA-01`、`E-GAM-05`、`E-GAS-01`、`E-GAV-05`、`E-GAE-02`、`E-MO-01/02`、`E-GSE-05` 的口径。

## 4. 方法与边界

- **静态穷举**：脚本按 `revert <Qualified.Name>(` 扫描 9 个实现文件（含 `interfaces/` 的 9 个错误接口），按括号平衡提取实参，按最近的 `if` 提取判据，再与声明双向对账（W1 后 105 声明 / 146 站点 / 0 缺口 / 0 死声明）。
- **语义实测**：`try/catch` 中 success 块 revert 是否被同一 `catch` 捕获、`abi.decode` 失败的 revert 数据形态，各用一个最小 foundry 工程（`/tmp/tctest`，solc 0.8.37）实测，结论写在 01 §4.2 与 X-05。
- **门禁**：`forge build --deny warnings` / `forge lint` 通过；`forge test --summary` **473 passed / 0 failed / 0 skipped**（35 个 suite）；`check_errors.py --check` 0 violations；`check_error_tests.py action` 全覆盖；`check_events.py`、`check_caller_auth.py action/src`、`check_doc_payloads.py`、`check_naming.py --check` 通过。
- **行为核对**：01/03/06/07/08/11/13 的校验顺序表逐条对照实现；02 的轮次映射对照 02-phase-model 的表格。
- **边界**：W1 只改错误 ABI、载荷、错误表、registry 与测试载荷，不改函数签名与事件；行号以 `916e146` 为基线、按本轮 HEAD 复核。`test/audit/` 与 `test/integration/` 计入测试总数。
- finding ID 统一 `E-<合约缩写>-NN`（`AT` / `EB` / `LP` / `LRA` / `GAS` / `GAM` / `GAJ` / `GAV` / `GAE` / `GAA` / `GR` / `GSS` / `GSE` / `MO`），与同目录其他专项（`action-api-auth-2026-11/` 的 `AT-01`、`action-events-audit-2026-11/` 的 `EV-xx`）区分。

## 5. 文件

| 文件 | 内容 |
| --- | --- |
| `README.md` | 任务、总览、横切结论、方法、selector 索引 |
| `01-ActionTarget.md` | ActionTarget 的逐错误明细与 findings |
| `02-ExecutorBase.md` | ExecutorBase 的逐错误明细与 findings |
| `03-LpExecutor.md` | LpExecutor 的逐错误明细与 findings |
| `04-LpRoundAxis.md` | LpRoundAxis（无错误声明）的失败形态核对 |
| `05-GroupActionStorage.md` | GroupActionStorage（无错误声明）的常量与不变式核对 |
| `06-GroupActionManager.md` | GroupActionManager 的逐错误明细与 findings |
| `07-GroupActionJoin.md` | GroupActionJoin 的逐错误明细与 findings |
| `08-GroupActionVerify.md` | GroupActionVerify 的逐错误明细与 findings |
| `09-GroupActionExecutor.md` | GroupActionExecutor 的逐错误明细与 findings |
| `10-GroupActionRoundAxis.md` | GroupActionRoundAxis（无错误声明）的失败形态核对 |
| `11-GroupRecipients.md` | GroupRecipients 的逐错误明细与 findings |
| `12-GroupServiceStorage.md` | GroupServiceStorage（无错误声明）的常量与不变式核对 |
| `13-GroupServiceExecutor.md` | GroupServiceExecutor 的逐错误明细与 findings |
| `14-MemberOwner.md` | MemberOwner 的两个失败出口（归一化 / 原样 rethrow） |

> 严重度口径：`Medium` = 在通过现有部署门禁的配置下可使一个入口永久不可用；`Low` = 与 error-standards 的强制条款冲突，或错误在生产不可达/不可定位，需要改 ABI 或规格；`Info` = 口径、文档与一致性，无行为风险。

## 附 A：错误 selector 索引（b2b1a5a 基线快照）

> 下表保留 `b2b1a5a` 基线，用于对照；W1 变更后的完整索引以 `matt-gov/registry/errors.{json,md}` 为准（238 声明 / 198 签名记录 / 186 唯一签名，含 core 与 group-chat）。本轮新增与替换的 selector 见附 A.2。

| 声明接口 | 错误 | 签名 | selector |
| --- | --- | --- | --- |
| IActionTargetErrors | `AlreadyInitialized` | `AlreadyInitialized()` | `0x0dc149f0` |
| IActionTargetErrors | `NotSubmit` | `NotSubmit(address)` | `0x3c7708ea` |
| IActionTargetErrors | `NotVote` | `NotVote(address)` | `0x20edde6a` |
| IActionTargetErrors | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| IActionTargetErrors | `UnboundProposal` | `UnboundProposal(address,uint256)` | `0x283a3095` |
| IActionTargetErrors | `UnauthorizedExecutor` | `UnauthorizedExecutor(address,uint256)` | `0x89d3c18e` |
| IActionTargetErrors | `JoinNotOpen` | `JoinNotOpen(address,uint256,uint256,uint256)` | `0x81013803` |
| IActionTargetErrors | `ProposalNotVoted` | `ProposalNotVoted(address,uint256)` | `0x82bbc7fd` |
| IActionTargetErrors | `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | `0x232f36be` |
| IActionTargetErrors | `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | `0x9c2b3988` |
| IActionTargetErrors | `ExecutorNotContract` | `ExecutorNotContract(address)` | `0xa6585817` |
| IActionTargetErrors | `ExecutorTargetMismatch` | `ExecutorTargetMismatch(address,address)` | `0x77523042` |
| IActionTargetErrors | `ExecutorHandshakeFailed` | `ExecutorHandshakeFailed(address)` | `0x4042953c` |
| IActionTargetErrors | `TargetDataExecutorMismatch` | `TargetDataExecutorMismatch(address,address)` | `0xb4d298bc` |
| IActionTargetErrors | `AlreadyCreated` | `AlreadyCreated(address,uint256)` | `0xca699de2` |
| IActionExecutorErrors | `NotActionTarget` | `NotActionTarget(address)` | `0x67b7e647` |
| IActionExecutorErrors | `ActionNotCreated` | `ActionNotCreated(address,uint256)` | `0x36c193ae` |
| IActionExecutorErrors | `NotMemberOwner` | `NotMemberOwner(uint256)` | `0x33393244` |
| IActionExecutorErrors | `RewardAlreadyMinted` | `RewardAlreadyMinted(address,uint256,uint256,uint256)` | `0xf41a3e9f` |
| IActionExecutorErrors | `MemberActionRewardUnavailable` | `MemberActionRewardUnavailable(address,uint256,uint256,uint256)` | `0x4cd933ce` |
| IActionExecutorErrors | `BatchLengthMismatch` | `BatchLengthMismatch(uint256,uint256)` | `0x81b5b207` |
| IActionExecutorErrors | `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | `0xea74f32b` |
| IActionExecutorErrors | `RoundBeforeActionCreated` | `RoundBeforeActionCreated(uint256,uint256)` | `0x1edd1ded` |
| IActionExecutorErrors | `RoundAfterMintWindow` | `RoundAfterMintWindow(uint256,uint256)` | `0x45297019` |
| ILpExecutorErrors | `ZeroJoinTokenAddress` | `ZeroJoinTokenAddress()` | `0x8a1b296f` |
| ILpExecutorErrors | `InvalidJoinTokenFactory` | `InvalidJoinTokenFactory(address,address)` | `0x17318f81` |
| ILpExecutorErrors | `InvalidMinGovRatio` | `InvalidMinGovRatio(uint256)` | `0x30a418eb` |
| ILpExecutorErrors | `InsufficientGovRatio` | `InsufficientGovRatio(uint256,uint256)` | `0x39a246e7` |
| ILpExecutorErrors | `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | `0x232f36be` |
| ILpExecutorErrors | `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | `0x9c2b3988` |
| ILpExecutorErrors | `ZeroParticipationAmount` | `ZeroParticipationAmount()` | `0x4ae8f898` |
| ILpExecutorErrors | `WithdrawAmountExceeded` | `WithdrawAmountExceeded(uint256,uint256)` | `0xbffdd230` |
| ILpExecutorErrors | `NotJoined` | `NotJoined(address,uint256,uint256)` | `0x847d1a6f` |
| IGroupActionManagerErrors | `GroupAlreadyActivated` | `GroupAlreadyActivated(uint256)` | `0xe36ee043` |
| IGroupActionManagerErrors | `GroupNotActive` | `GroupNotActive(uint256)` | `0xd28fa9ad` |
| IGroupActionManagerErrors | `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` |
| IGroupActionManagerErrors | `InvalidMinJoinAmount` | `InvalidMinJoinAmount(uint256)` | `0xedb63d2d` |
| IGroupActionManagerErrors | `InvalidMaxJoinAmount` | `InvalidMaxJoinAmount(uint256,uint256)` | `0x24fbf4de` |
| IGroupActionManagerErrors | `DeactivationLockedInActivatedRound` | `DeactivationLockedInActivatedRound(uint256,uint256)` | `0xb1f4faaf` |
| IGroupActionManagerErrors | `NotGroupOwner` | `NotGroupOwner(uint256)` | `0x54a55079` |
| IGroupActionManagerErrors | `InsufficientActivationMinGovRatio` | `InsufficientActivationMinGovRatio(uint256,uint256,uint256)` | `0xfc04f2b0` |
| IGroupActionManagerErrors | `NoGovVotes` | `NoGovVotes(address)` | `0xa0d4ddef` |
| IGroupActionManagerErrors | `TooManyVerificationEntries` | `TooManyVerificationEntries(uint256,uint256)` | `0x60eec811` |
| IGroupActionManagerErrors | `VerificationKeyTooLong` | `VerificationKeyTooLong(uint256,uint256,uint256)` | `0xcbe7d4ac` |
| IGroupActionManagerErrors | `VerificationDescriptionTooLong` | `VerificationDescriptionTooLong(uint256,uint256,uint256)` | `0xb9e185d5` |
| IGroupActionJoinErrors | `ZeroParticipationAmount` | `ZeroParticipationAmount()` | `0x4ae8f898` |
| IGroupActionJoinErrors | `AlreadyInOtherGroup` | `AlreadyInOtherGroup(uint256,uint256,uint256)` | `0x246d0493` |
| IGroupActionJoinErrors | `NotJoined` | `NotJoined(address,uint256,uint256)` | `0x847d1a6f` |
| IGroupActionJoinErrors | `ActionMaxJoinAmountExceeded` | `ActionMaxJoinAmountExceeded(uint256,uint256,uint256)` | `0x2de9248d` |
| IGroupActionJoinErrors | `GroupMaxJoinAmountExceeded` | `GroupMaxJoinAmountExceeded(uint256,uint256,uint256)` | `0xda731d54` |
| IGroupActionJoinErrors | `GroupCapacityExceeded` | `GroupCapacityExceeded(uint256,uint256,uint256)` | `0x5b3f94ec` |
| IGroupActionJoinErrors | `GroupAccountsFull` | `GroupAccountsFull(uint256,uint256,uint256)` | `0xbf0861bd` |
| IGroupActionJoinErrors | `BelowMinJoinAmount` | `BelowMinJoinAmount(uint256,uint256)` | `0x21bb7f42` |
| IGroupActionJoinErrors | `WithdrawAmountExceeded` | `WithdrawAmountExceeded(uint256,uint256)` | `0xbffdd230` |
| IGroupActionJoinErrors | `QuotaArrayLengthMismatch` | `QuotaArrayLengthMismatch(uint256,uint256)` | `0x4a0b0bf7` |
| IGroupActionJoinErrors | `QuotaMemberIsProvider` | `QuotaMemberIsProvider(uint256)` | `0x3791977c` |
| IGroupActionJoinErrors | `ZeroQuotaAmount` | `ZeroQuotaAmount(uint256)` | `0xb88ef067` |
| IGroupActionJoinErrors | `QuotaNotGranted` | `QuotaNotGranted(uint256,uint256,uint256)` | `0x6ce01173` |
| IGroupActionJoinErrors | `InsufficientProviderQuota` | `InsufficientProviderQuota(uint256,uint256,uint256)` | `0xca9ef3f9` |
| IGroupActionJoinErrors | `TooManyVerificationValues` | `TooManyVerificationValues(uint256,uint256)` | `0x4097cdca` |
| IGroupActionJoinErrors | `VerificationValueTooLong` | `VerificationValueTooLong(uint256,uint256,uint256)` | `0x762fe301` |
| IGroupActionVerifyErrors | `OriginScoresEmpty` | `OriginScoresEmpty()` | `0xaafa066e` |
| IGroupActionVerifyErrors | `VerifierNotRanked` | `VerifierNotRanked(uint256,uint256)` | `0x8e9078b9` |
| IGroupActionVerifyErrors | `VerifierNotOpen` | `VerifierNotOpen(uint256,uint256)` | `0x0ee7919b` |
| IGroupActionVerifyErrors | `ScoreLimitExceeded` | `ScoreLimitExceeded(uint256,uint256,uint256)` | `0x743bbb84` |
| IGroupActionVerifyErrors | `GroupVerificationAlreadyComplete` | `GroupVerificationAlreadyComplete(uint256,uint256)` | `0xec3ddd72` |
| IGroupActionVerifyErrors | `VerificationBatchTooLarge` | `VerificationBatchTooLarge(uint256,uint256)` | `0x3b91a8c8` |
| IGroupActionVerifyErrors | `StartIndexMismatch` | `StartIndexMismatch(uint256,uint256)` | `0xdadbe49c` |
| IGroupActionVerifyErrors | `ScoreCountExceeded` | `ScoreCountExceeded(uint256,uint256,uint256)` | `0xc6f0561d` |
| IGroupActionVerifyErrors | `ZeroVerifyVotes` | `ZeroVerifyVotes(address,uint256)` | `0x131e332f` |
| IGroupActionVerifyErrors | `NoActiveApplication` | `NoActiveApplication(uint256)` | `0xcda5095d` |
| IGroupActionVerifyErrors | `VerifierAlreadyLocked` | `VerifierAlreadyLocked(address,uint256,uint256)` | `0xa4ab638a` |
| IGroupActionExecutorErrors | `ZeroJoinTokenAddress` | `ZeroJoinTokenAddress()` | `0x8a1b296f` |
| IGroupActionExecutorErrors | `InvalidMaxJoinAmountRatio` | `InvalidMaxJoinAmountRatio(uint256)` | `0x1b42d872` |
| IGroupActionExecutorErrors | `InvalidActivationMinGovRatio` | `InvalidActivationMinGovRatio(uint256)` | `0x828ac3ed` |
| IGroupActionExecutorErrors | `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | `0x232f36be` |
| IGroupActionExecutorErrors | `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | `0x9c2b3988` |
| IGroupActionExecutorErrors | `VerificationInfoLengthMismatch` | `VerificationInfoLengthMismatch(uint256,uint256)` | `0xe5b734dc` |
| IGroupActionExecutorErrors | `DescriptionTooLong` | `DescriptionTooLong(uint256,uint256)` | `0x71a24cf3` |
| IGroupRecipientsErrors | `DistributionOverflow` | `DistributionOverflow(uint256,uint256)` | `0x81281d08` |
| IGroupRecipientsErrors | `UnknownSourceAction` | `UnknownSourceAction(address,uint256)` | `0x6ea46b42` |
| IGroupRecipientsErrors | `TooManyRecipients` | `TooManyRecipients(uint256,uint256)` | `0x3971ddf8` |
| IGroupRecipientsErrors | `ZeroRecipientRatio` | `ZeroRecipientRatio(uint256)` | `0x4a3b43a3` |
| IGroupRecipientsErrors | `RecipientArrayLengthMismatch` | `RecipientArrayLengthMismatch(uint256,uint256,uint256)` | `0xaae80407` |
| IGroupRecipientsErrors | `DuplicateMemberId` | `DuplicateMemberId(uint256)` | `0x1a494813` |
| IGroupRecipientsErrors | `RecipientIsGroupId` | `RecipientIsGroupId(uint256,uint256)` | `0x6f819480` |
| IGroupRecipientsErrors | `RemarkTooLong` | `RemarkTooLong(uint256,uint256,uint256)` | `0x56fa372b` |
| IGroupServiceExecutorErrors | `NotQualified` | `NotQualified(address,uint256,uint256)` | `0xd52b235e` |
| IGroupServiceExecutorErrors | `ZeroActionTokenAddress` | `ZeroActionTokenAddress()` | `0x95bf90a9` |
| IGroupServiceExecutorErrors | `InvalidRatioForPublicVerifier` | `InvalidRatioForPublicVerifier(uint256)` | `0x790182dd` |
| IGroupServiceExecutorErrors | `ActionTokenParentMismatch` | `ActionTokenParentMismatch(address,address,address)` | `0x4757480b` |
| IGroupServiceExecutorErrors | `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | `0x232f36be` |
| IGroupServiceExecutorErrors | `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | `0x9c2b3988` |
| IGroupServiceExecutorErrors | `NotJoined` | `NotJoined(address,uint256,uint256)` | `0x847d1a6f` |
| IGroupServiceExecutorErrors | `AlreadyJoined` | `AlreadyJoined(address,uint256,uint256)` | `0x8a8846f7` |
| IGroupServiceExecutorErrors | `GroupNotExist` | `GroupNotExist(uint256)` | `0xfeddf96a` |
| IGroupServiceExecutorErrors | `NotGroupOwner` | `NotGroupOwner(uint256)` | `0x54a55079` |

### 附 A.1 跨本地接口重复声明的 9 个名字

| 错误 | 声明于 |
| --- | --- |
| `GroupNotExist` | IGroupActionManagerErrors、IGroupServiceExecutorErrors |
| `InvalidTargetDataShape` | IActionTargetErrors、IGroupActionExecutorErrors、IGroupServiceExecutorErrors、ILpExecutorErrors |
| `NotGroupOwner` | IGroupActionManagerErrors、IGroupServiceExecutorErrors |
| `NotJoined` | IGroupActionJoinErrors、IGroupServiceExecutorErrors、ILpExecutorErrors |
| `NotMemberOwner` | IActionExecutorErrors、IActionTargetErrors |
| `WithdrawAmountExceeded` | IGroupActionJoinErrors、ILpExecutorErrors |
| `ZeroJoinTokenAddress` | IGroupActionExecutorErrors、ILpExecutorErrors |
| `ZeroParticipationAmount` | IGroupActionJoinErrors、ILpExecutorErrors |

## 附 A.2：W1 变更后的错误签名

| 新签名 | selector | 替代 |
| --- | --- | --- |
| `InsufficientTargetDataItems(uint256,uint256)` | `0xa2e9b41f` | `TargetDataLengthMismatch(uint256,uint256)` 的下界分支 |
| `TooManyTargetDataItems(uint256,uint256)` | `0xa87702a7` | `TargetDataLengthMismatch(uint256,uint256)` 的上界分支 |
| `ZeroMinJoinAmount()` | `0x155083e4` | `InvalidMinJoinAmount(uint256)` |
| `ZeroGroupId()` | `0x32002782` | `GroupNotExist(0)` 的参数缺省分支（`GroupNotExist(uint256)` 保留） |
| `RoundVerifierLocked(address,uint256,uint256,uint256)` | `0x08010030` | `VerifierAlreadyLocked(address,uint256,uint256)` |
| `MemberHasNoVote(address,uint256,uint256)` | `0x8fde7ba3` | `MemberActionRewardUnavailable` 的成员级分支（与 core 同签名） |
| `MemberRewardPoolEmpty(address,uint256)` | `0x86b94627` | `MemberActionRewardUnavailable` 的轮级分支（与 core 同签名） |
| `MemberRewardRoundedToZero(address,uint256,uint256)` | `0xd632d7c1` | `MemberActionRewardUnavailable` 的取整分支（与 core 同签名） |
