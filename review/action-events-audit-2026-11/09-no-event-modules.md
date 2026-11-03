# 无事件模块核查（ExecutorBase / 两个 Storage / 两条 RoundAxis / MemberOwner）

> 对象
> - `action/src/ExecutorBase.sol`（140 行，`abstract contract`）
> - `action/src/GroupActionStorage.sol`（190 行，`library`，纯 `struct` + 常量 + 1 个 `internal view`）
> - `action/src/GroupServiceStorage.sol`（80 行，`library`，纯 `struct` + 常量 + 3 个 `internal`）
> - `action/src/GroupActionRoundAxis.sol`（21 行，`library`，纯换算）
> - `action/src/LpRoundAxis.sol`（16 行，`library`，纯换算）
> - `action/src/MemberOwner.sol`（26 行，`library`，`try/catch` 包装）
> 基线 `action@e849e36`；审查日期 2026-11-03

## 一、结论

| 模块 | 事件 | 发射点 | 状态变量 | 判定 |
| --- | --- | --- | --- | --- |
| `ExecutorBase` | 0 | 0 | 4 个 `immutable` | 正确：抽象基类，成员结算事件的发射落在三个子类的 `_mintMemberReward` override 里 |
| `GroupActionStorage` | 0 | 0 | 0（只有 `Layout` 定义与常量） | 正确：状态由 `GroupActionExecutor` 声明，事件由状态所有者发射（§4.1） |
| `GroupServiceStorage` | 0 | 0 | 0（同上） | 正确 |
| `GroupActionRoundAxis` | 0 | 0 | 0 | 正确：`02-phase-model.md` 明确「轴库只做 `phase → round` 纯换算，不 import 错误接口」 |
| `LpRoundAxis` | 0 | 0 | 0 | 正确 |
| `MemberOwner` | 0 | 0 | 0 | 正确：只把 `ERC721NonexistentToken` 归一为 `address(0)`，不产生业务事实 |

**6 个模块全部「零事件」是正确的**，不是遗漏。本报告记录的是每个模块「为什么可以没有事件」以及「没有事件会带来什么隐含约束」——这些约束在各自的消费方报告里被引用。

## 二、`ExecutorBase`

### 2.1 结构

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `ACTION_TARGET_ADDRESS` / `STAKE_ADDRESS` / `MEMBER_NFT_ADDRESS` / `PHASE_ADDRESS` | `immutable` | 构造时从单一入参 `actionTargetAddress` 逐级反查（`VOTE → STAKE → MEMBER_NFT/PHASE`），`:19-26` |
| `onProposalSubmitted` | `external virtual override onlyActionTarget {}` | 空实现，三个子类都不覆写 |
| `mintMemberReward` | `public nonReentrant onlyMemberOwner` | 转调 `_mintMemberReward` |
| `mintMemberRewards` | `external nonReentrant onlyMemberOwner` | 批量，逐元素转调 `_mintMemberReward` |
| `currentVoteRound` / `currentJoinRound` / `currentMintRound` | `external view` | 三个 ABI 查询入口，`< 1` 回滚 `RoundNotStarted(1, 0)` |
| `_checkMintWindow` | `internal view` | 四段判定：`ActionNotCreated` → `RoundBeforeActionCreated` → `RoundAfterMintWindow` → `RewardAlreadyMinted` |
| `_joinRound` / `_mintRound` / `_mintMemberReward` | `internal virtual` | 由三个子类实现 |

### 2.2 为什么零事件

四个 `immutable` 是部署期静态值（§3.2 豁免），由 `DeployAction` 广播前校验、`21_check.sh` 复核。三个 Round getter 是纯查询，`_checkMintWindow` 只做判定不写状态。唯一的两个写入口 `mintMemberReward` / `mintMemberRewards` 都**不写基类状态**，全部事实由子类的 `_mintMemberReward` 产生并发 `MemberRewardMinted`。

### 2.3 由此产生的隐含约束（对事件契约的影响）

| 约束 | 依据 | 若不成立会怎样 |
| --- | --- | --- |
| 三个子类必须各自实现 `_mintMemberReward` 并在其中 emit `MemberRewardMinted` | `:134-139` 是 `internal virtual` 无实现 | 编译期强制（`virtual` 无默认体），不会漏 |
| 批量入口的事件条数必须等于 `actionIds.length` | `:71-81` 循环逐元素调用 | `BatchLengthMismatch:72-74` 只校验两数组等长；元素级零额会整笔回滚，因此「N 个元素 ⇒ N 条事件或整笔回滚」 |
| `nonReentrant` 锁在基类，经 `delegatecall` 与库共享 | `:56`、`:65` | 三个 Executor 的结算路径共用同一把锁；`GroupActionJoin` / `GroupActionVerify` 的 `nonReentrant` 由 Executor 的包装函数持有（`action-api-auth-2026-11` GAJ-03 已从 CEI 角度讨论） |
| `onlyMemberOwner` 在基类，子类的 `join`/`withdraw`/`exit` 另有自己的 `onlyMemberOwner` | `:29-34` | 两处同名 modifier 语义相同（都是 `ownerOf(memberId) == msg.sender`），不构成两套权限 |

## 三、`GroupActionStorage` / `GroupServiceStorage`

两个文件都只含三样东西：`constant`、`struct`、`internal` 辅助函数。没有任何 `storage` 变量声明——状态由 Executor 的 `_layout` 持有，库函数一律以 `Layout storage self` 作首参。

| 文件 | 常量 | 辅助函数 | 事件 |
| --- | --- | --- | --- |
| `GroupActionStorage` | `PRECISION = 1e18`、`MAX_ORIGIN_SCORE = 100`、`MAX_VERIFICATION_BATCH = 100`、`MAX_DESCRIPTION_BYTES = 1024`、`MAX_VERIFICATION_ENTRIES = 16`、`MAX_VERIFICATION_TEXT_BYTES = 1024` | `memberAmountAt`（自有 + Provider 聚合） | 0 |
| `GroupServiceStorage` | `PRECISION = 1e18`、`DEFAULT_MAX_RECIPIENTS = 10`、`MAX_REMARK_BYTES = 256` | `cachedDenominator`、`cacheDenominator`、`groupReward` | 0 |

这些常量全部是 §6.8 动态字段上限的链上强制来源：`MAX_DESCRIPTION_BYTES` 守住 `GroupActivated.description` / `GroupConfigChanged.description` / `VerifierApplicationSubmitted.description` 的 1024 字节；`MAX_VERIFICATION_ENTRIES` / `MAX_VERIFICATION_TEXT_BYTES` 守住 `GroupActionCreated` 的两个数组；`MAX_VERIFICATION_BATCH` 守住 `OriginScoresSubmitted.scores`；`DEFAULT_MAX_RECIPIENTS` / `MAX_REMARK_BYTES` 守住 `RecipientsChanged` 的三组数组。**常量在这里、事件在上层**，因此 §6.8 的「上限必须由链上强制常量守护」这条，核对时要在本文件找常量、在对应事件报告里找校验点。

`GroupServiceStorage.groupReward`（`:69-77`）带 `// Load-bearing:` 注释（`:65-68`），说明「缓存的分母只能与同一账本的权重配对」——这条约束直接决定 `ServiceRewardsDistributed` 的金额正确性，但它是状态读取规则，不产生事件。

## 四、`GroupActionRoundAxis` / `LpRoundAxis`

两条轴都是「`phase → round` 纯换算」，无 `import` 错误接口、无状态、无事件：

| 轴 | `joinRound` | `verifyRound` | `mintRound` |
| --- | --- | --- | --- |
| `GroupActionRoundAxis` | `phase < 2 ? 0 : phase − 1` | `phase < 3 ? 0 : phase − 2` | `phase < 4 ? 0 : phase − 3` |
| `LpRoundAxis` | `phase < 2 ? 0 : phase − 1` | —（LP 无验证阶段） | `phase < 3 ? 0 : phase − 2` |

`< 1` 的守卫不在这里，而在消费方：`ExecutorBase.currentJoinRound` / `currentMintRound`、`GroupActionManager.currentJoinRound`（`:477-483`）、`GroupActionVerify.currentVerifyRound`（`:521-527`）。两条路径回滚同一载荷 `RoundNotStarted(1, 0)`。

**对事件的影响**：所有事件的 `round` 字段都直接或间接来自这两条轴，因此「同一笔交易里所有事件的 `round` 必须落在同一个 phase 快照上」这条不变式由「轴是纯函数 + 同 tx 内 `block.number` 不变」共同保证。`GroupActionExecutor` 与 `GroupServiceExecutor` 的 `mintRound` 不同（`phase − 3` vs 同值）而 `LpExecutor` 是 `phase − 2`，这是 `LPE-EV-3` 讨论的共享类相位偏移问题。

## 五、`MemberOwner`

26 行，只有一个函数 `ownerOrZero(memberNFTAddress, memberId)`：`try ownerOf` 成功返回 owner，捕获 `ERC721NonexistentToken` 返回 `address(0)`，其他错误原样 `revert`（`assembly` 重抛）。

无事件是正确的：它不产生业务事实，只把「NFT 不存在」这一标准错误归一为「零地址」这一调用方约定。

**对事件契约的影响**：三个调用方把这个 `address(0)` 变成不同结果——

| 调用方 | 零地址的后果 | 产生的事件 |
| --- | --- | --- |
| `GroupActionManager.groupOwnerOrRevert`（`:38-47`） | 回滚 `GroupNotExist(groupId)` | 无（`GroupActivated` 等不发） |
| `GroupServiceExecutor.onlyGroupOwner`（`:56-65`） | 回滚 `GroupNotExist(groupId)` | 无（`RecipientsChanged` 不发） |
| `GroupServiceExecutor.onlyGroupOwner`（owner ≠ msg.sender 分支） | 回滚 `NotGroupOwner(groupId)` | 无 |

因此「`groupId` 不存在」与「`groupId` 存在但调用者不是持有人」在错误层可区分，但在**事件层都表现为零日志**——消费方不能从「没有事件」推断原因，只能从 revert 数据推断。`MemberOwner` 的 `// Load-bearing:` 注释（`:7-12`）正是在说明这一点：如果 `ownerOf` 对不存在的 id 返回非零地址，`GroupNotExist` 会被静默跳过，`RecipientsChanged` 会被发给一个不存在的群。

## 六、发现

本组 6 个模块 **0 条发现**。三条值得记录的正面结论：

1. **零事件不是遗漏**：4 个模块无状态、2 个模块是纯换算/包装，状态与事件都在状态所有者侧，§4.1 的「一条事实一个发射者」在结构上成立。
2. **常量与校验分离但可对账**：§6.8 的六组上限常量集中在两个 Storage 文件，校验点分散在 `GroupActionManager` / `GroupActionJoin` / `GroupActionVerify` / `GroupRecipients`；本次审查逐条核对了「常量 → 校验点 → 事件字段」三段，六组全部有链上强制点（详见 `README.md` 第六节的上限矩阵）。
3. **`MemberOwner` 的错误归一决定了三条事件的「零日志」语义**：`GroupNotExist` / `NotGroupOwner` 都不发事件，消费方须以 revert 数据而非日志判断失败原因。
