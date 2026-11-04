# GroupActionManager · 状态变量变更审查

> `action/src/GroupActionManager.sol`，506 行（修复提交后 513 行），`action@0c1d1e2`。
> 职责：行动配置（创建回调写一次）、链群激活/停用（当前态 + 5 个计数器 + 4 组索引）、群配置与描述快照。**全仓唯一维护「资金托管 + 计数器」成对增减的模块**：一次 `activateGroup` 同时改 3 个金额计数器与 4 个集合。
> 本卷只审状态写入，鉴权见 `action-api-auth-2026-11` 的 `07-group-action-manager.md`，事件见 `action-events-audit-2026-11` 的 `03-group-action-manager.md`。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局（本库写入的 Layout 字段）

### A. 行动配置（创建回调写一次，永不改）

| # | 字段 | 写点 | 语义 |
| --- | --- | --- | --- |
| A1 | `joinTokenAddressByActionId` | `onProposalCreated:85` | 参与代币 |
| A2 | `activationStakeAmountByActionId` | `:88` | 激活押金（**退押金的唯一来源**） |
| A3 | `maxJoinAmountRatioByActionId` | `:89` | 行动级加入上限比例 |
| A4 | `activationMinGovRatioByActionId` | `:90` | 激活时的治理票占比下限（0 = 关闭） |
| A5 | `verifierStakeAmountByActionId` | `:91` | 验证者押金（Verify 读） |
| A6 | `verificationKeysByActionId` | `:119` | 验证模板 keys（可选 `targetData[6]`） |
| A7 | `verificationDescriptionsByActionId` | `:120` | 验证模板说明 |
| A8 | `createdRoundByActionId` | `:123` | 创建轮（0 = 未创建哨兵） |

### B. 群当前态（可反复切换）

| # | 字段 | 写点 |
| --- | --- | --- |
| B1 | `groupState`（`config` / `active` / `activatedRound` / `deactivatedRound`） | `activateGroup:151-154`、`deactivateGroup:193-194`、`setGroupConfig:239` |
| B2 | `descriptionHistoryByGroupId`（按轮） | `activateGroup:155`、`setGroupConfig:240` |

### C. 三个金额计数器（成对增减）

| # | 字段 | 维度 | 加 | 减 |
| --- | --- | --- | --- | --- |
| C1 | `stakedByActionId` | token + action | `:159` | `:197` |
| C2 | `totalStaked` | token（社区） | `:160` | `:198` |
| C3 | `stakedByMemberId` | token + **groupId** | `:161` | `:199` |

### D. 四组当前态索引

| # | 字段 | 语义 | 加 | 减 |
| --- | --- | --- | --- | --- |
| D1 | `activeGroupIdsByActionId` | 该行动当前激活的群 | `:158` | `:196` |
| D2 | `tokenAddressesByGroupId` | 该群有激活行动的社区 | `:162` | `:202`（仅当该群在该社区已无行动） |
| D3 | `actionIdsByGroupId` | 该社区该群当前激活的行动 | `:163` | `:200` |
| D4 | `activeActionIds` | 该社区至少有一个激活群的行动 | `:164` | `:205`（仅当该行动已无激活群） |

## 2. 逐变量变更逻辑

### 2.1 `onProposalCreated`（`:50-126`）——8 个配置槽

| 顺序 | 位置 | 语句 | 守卫 |
| --- | --- | --- | --- |
| 1 | `:57-62` | `targetData.length` 在 `[6, 7]` | `TargetDataLengthMismatch(6 或 7, len)` |
| 2 | `:63-68` | 第 1～5 项各 32 字节 | `InvalidTargetDataShape` |
| 3 | `:70-77` | `joinTokenAddress != 0` | `ZeroJoinTokenAddress` |
| 4 | `:78-83` | 两个比例 `<= 1e18` | `InvalidMaxJoinAmountRatio` / `InvalidActivationMinGovRatio` |
| 5 | `:85-91` | 写 A1～A5 | — |
| 6 | `:93-121` | 可选 `targetData[6]`：等长、≤16 项、每项 ≤1024 字节 → 写 A6/A7 | 四个错误 |
| 7 | `:123` | 写 A8 = `currentPhase()` | — |
| 8 | `:125` | `GroupActionCreated` | — |

第 3 步只判非零，**不判代码、不判 `totalSupply()` 可调**——见 M-GAM-01。

### 2.2 `activateGroup`（`:129-171`）——9 个字段

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:136` | `onlyGroupOwner(groupId)` | `ownerOrZero` → `GroupNotExist` / `NotGroupOwner` |
| 2 | `:137-139` | `createdRoundByActionId != 0` | `ActionNotCreated` |
| 3 | `:141-144` | `!group.active` | `GroupAlreadyActivated` |
| 4 | `:146` | `_checkGroupConfig(config)` | 见 2.5 |
| 5 | `:147` | `_checkActivationMinGovRatio` | 见 2.6 |
| 6 | `:149` | `round = currentJoinRound()` | `phase < 2` 回滚 |
| 7 | `:151-154` | 写 B1（config / active / activatedRound / deactivatedRound = 0） | — |
| 8 | `:155` | B2 `record(round, description)` | — |
| 9 | `:157` | `stakeAmount = activationStakeAmountByActionId` | **每次现读，不在群状态里存** |
| 10 | `:158-164` | 6 个集合/计数器同笔增减 | 见 §1 C/D |
| 11 | `:166-168` | `stakeAmount != 0` → `safeTransferFrom(msg.sender, this, stakeAmount)` | 在全部状态写之后 |
| 12 | `:170` | `GroupActivated` | — |

第 9 步是**「退押金金额不落群状态」**的根源：`deactivateGroup` 也现读同一个 A2。两者相等的前提是 A2 只写一次（`Load-bearing` 注释 `:86-87`）。

### 2.3 `deactivateGroup`（`:174-219`）

| 顺序 | 位置 | 语句 | 说明 |
| --- | --- | --- | --- |
| 1 | `:180` | `onlyGroupOwner` | — |
| 2 | `:182-184` | `group.active` | `GroupNotActive` |
| 3 | `:186-189` | `round != group.activatedRound` | `DeactivationLockedInActivatedRound`（同轮不可停用） |
| 4 | `:191` | `stakeAmount = activationStakeAmountByActionId` | 与激活同源 |
| 5 | `:193-194` | `group.active = false`；`deactivatedRound = round` | — |
| 6 | `:196-206` | 6 个集合/计数器反向 | D2/D4 有条件移除 |
| 7 | `:208-210` | `safeTransfer(msg.sender, stakeAmount)` | 退给**当前**群主 |
| 8 | `:212-218` | `GroupDeactivated` | — |

第 3 步使「激活当轮不能停用」，因此当轮的押金无法在同轮撤回——`GAM-03` 已从权限视角登记，本卷补状态视角：`activatedRound` 的**唯一链上用途**就是这一次相等判定（见 M-GAM-04）。

### 2.4 `setGroupConfig`（`:221-243`）

| 顺序 | 位置 | 语句 |
| --- | --- | --- |
| 1 | `:228` | `onlyGroupOwner` |
| 2 | `:230-232` | `group.active` → `GroupNotActive` |
| 3 | `:234` | `_checkGroupConfig(config)` |
| 4 | `:236` | `previousConfig = group.config`（供事件） |
| 5 | `:238-240` | `round = currentJoinRound()`；写 B1.config；B2 `record(round, description)` |
| 6 | `:242` | `GroupConfigChanged`（新组 + 旧组全量） |

**不重新校验 `activationMinGovRatio`**：配置可以在治理票占比跌破下限后继续修改。这是设计（下限只约束入场）。

### 2.5 `_checkGroupConfig`（`:392-405`）

| 判据 | 错误 |
| --- | --- |
| `minJoinAmount != 0` | `InvalidMinJoinAmount(0)` |
| `maxJoinAmount == 0` 或 `maxJoinAmount >= minJoinAmount` | `InvalidMaxJoinAmount` |
| `description` ≤ 1024 字节 | `DescriptionTooLong` |

`maxCapacity == 0` 与 `maxAccounts == 0` 合法，表示不设限。

### 2.6 `_checkActivationMinGovRatio`（`:407-431`）

| 顺序 | 位置 | 语句 |
| --- | --- | --- |
| 1 | `:414-417` | `minGovRatio == 0` → 直接放行 |
| 2 | `:420-424` | `totalValidGovVotes(token, currentPhase)`；为 0 → `NoGovVotes` |
| 3 | `:426` | `ownerGovVotes = validGovVotes(token, currentPhase, groupId)` |
| 4 | `:427` | `actualRatio = (ownerGovVotes * PRECISION) / totalGovVotes` |
| 5 | `:428-430` | `actualRatio < minGovRatio` → `InsufficientActivationMinGovRatio` |

第 4 步是全仓唯一一处手写比例乘法（见 M-GAM-02）。

### 2.7 `_maxJoinAmount`（`:365-390`）——只读，但决定 `join` 能否发生

```text
round = joinRound();  round == 0 → 0
totalVoteAmount = Vote.totalVoteAmount(token, round);  == 0 → 0
actionVoteAmount = Vote.voteAmountByProposalId(token, round, actionId);  == 0 → 0
totalMinted = IERC20(joinTokenAddress).totalSupply()        ← 无代码/无 totalSupply 即回滚
baseAmount = totalMinted × maxJoinAmountRatio / 1e18
return baseAmount × actionVoteAmount / totalVoteAmount
```

三段早退保证「行动本轮没被投票 ⟹ 上限为 0 ⟹ 任何 `join` 都回滚 `ActionMaxJoinAmountExceeded`」。这是「行动必须每轮重新被投票才能继续加入」的实现。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| M1 | `stakedByActionId[t][a] == Σ_{g 激活} activationStakeAmountByActionId[t][a]` | ✅ | 加/减同源同值（`:157` 与 `:191` 读同一槽） |
| M2 | `totalStaked[t] == Σ_a stakedByActionId[t][a]` | ✅ | 与 M1 同笔 |
| M3 | `stakedByMemberId[t][g] == Σ_{a: 该群激活} activationStakeAmountByActionId[t][a]` | ✅ | 与 M1 同笔 |
| M4 | `activeGroupIdsByActionId[t][a].contains(g)` ⟺ `groupState[t][a][g].active` | ✅ | 唯一两个写点（`:158`/`:196`）与 B1 的 `active` 同笔 |
| M5 | `actionIdsByGroupId[t][g].contains(a)` ⟺ `groupState[t][a][g].active` | ✅ | 同上 |
| M6 | `tokenAddressesByGroupId[g].contains(t)` ⟺ `∃a: groupState[t][a][g].active` | ✅ | `:202` 的移除条件是「该群在该社区已无行动」 |
| M7 | `activeActionIds[t].contains(a)` ⟺ `∃g: groupState[t][a][g].active` | ✅ | `:205` 的移除条件是「该行动已无激活群」 |
| M8 | `group.activatedRound != 0` ⟺ `group.active` 曾经为真 | ⚠️ 部分 | `activateGroup` 写 `activatedRound`，`deactivateGroup` 不重置它；因此「曾激活过的群」与「当前激活的群」只能靠 `active` 区分 |
| M9 | `createdRoundByActionId != 0` ⟹ A1～A5 已写 | ✅ | 第 5 步与第 7 步同笔，第 7 步在最后 |

## 4. 发现

### M-GAM-01 · 创建回调只校验 `joinTokenAddress != 0`，不校验代码与 `totalSupply()`；打错地址会让行动永久不可加入且视图回滚

| 字段 | 值 |
| --- | --- |
| 位置 | `:75-77`（唯一校验）、`:383`（`totalSupply()`）、`GroupActionJoin:664`（`join` 调用 `_maxJoinAmount`） |
| 级别 | **Low** |
| 证据 | E1 |

`_maxJoinAmount` 在 `:383` 无条件执行 `IERC20(joinTokenAddress).totalSupply()`。`joinTokenAddress` 只经过「非零」一项校验（`:75`），因此：

- 若指向一个 EOA 或没有 `totalSupply()` 的合约，Solidity 的 `extcodesize` 检查/返回数据解码会让 `_maxJoinAmount` **回滚**；
- `join` 在 `_checkGroupConstraints:664` 调它，因此**该行动的每一次加入都回滚**，且错误不是 `ActionMaxJoinAmountExceeded` 而是底层解码失败；
- `maxJoinAmount(token, action)` 这个**只读入口也会回滚**，违反「读面越界返回零值、不回滚」的仓内惯例（对照 `GroupServiceExecutor.joinedAmountByActionId` 的 `round > _joinRound() → 0`）。

对照 `LpExecutor.onProposalCreated`：它用 `_isRegisteredPair`（`:450-478`）做三重校验（`code.length`、`token0()/token1()` 可调、`factory.getPair` 相等），因此 LP 行动不可能进入「joinToken 不可用」的状态。GroupAction 侧没有对应校验，两者的严格程度不对称。

修复成本：在 `onProposalCreated` 里加一次 `try IERC20(joinTokenAddress).totalSupply() returns (uint256) {} catch { revert }`，或直接判 `joinTokenAddress.code.length != 0`。前者还能顺带挡住「有代码但没有 `totalSupply`」的合约。改 ABI 风险为零（只加一个 revert 分支）。

**处置（已修复）**：两条都做了——先判 `joinTokenAddress.code.length == 0`，再 `try IERC20(joinTokenAddress).totalSupply() {} catch`，两条失败路径统一回滚新错误 `InvalidJoinTokenAddress(address)`。新增测试 `testJoinTokenWithoutTotalSupplyIsRejected` 断言：创建回调对零代码地址回滚，且该 action 的 `maxJoinAmount()` 视图返回 `0` 而不是回滚。修复后 `GroupActionManager` 506 → 513 行，`:77` 之后的引用后移 7 行。

### M-GAM-02 · `_checkActivationMinGovRatio` 是全仓唯一一处手写比例乘法

| 字段 | 值 |
| --- | --- |
| 位置 | `:427` |
| 级别 | Info |
| 证据 | E2 |

`actualRatio = (ownerGovVotes * PRECISION) / totalGovVotes`。仓内其他五处比例计算全部用 `Math.mulDiv`：

| 位置 | 写法 |
| --- | --- |
| `GroupActionManager:384` | `Math.mulDiv(totalMinted, ratio, PRECISION)` |
| `GroupActionManager:389` | `Math.mulDiv(baseAmount, actionVoteAmount, totalVoteAmount)` |
| `GroupServiceExecutor:539` | `Math.mulDiv(validGovVotes, PRECISION, totalValidGovVotes)` |
| `LpExecutor:307` | `Math.mulDiv(effectiveAmount, PRECISION, totalEffectiveAmount)` |
| `LpExecutor:357` | `Math.mulDiv(memberGovVotes, PRECISION, totalValidGovVotes)` |

溢出条件是 `ownerGovVotes > 2^256 / 1e18 ≈ 1.15e59`。治理票的数量级是代币最小单位（典型 `1e27`），因此实际不可达；但**失败形态是 Panic 0x11**，会让 `activateGroup` 对极端供应量的社区永久不可用，且错误无法被链下分类。改一行 `Math.mulDiv(ownerGovVotes, PRECISION, totalGovVotes)` 即与其他五处对齐。

### M-GAM-03 · `setGroupConfig` 立即影响进行中的加入轮

| 字段 | 值 |
| --- | --- |
| 位置 | `:239`（写 `group.config`）、`GroupActionJoin:634`（`_checkGroupConstraints` 现读） |
| 级别 | Info |
| 证据 | E1 |

`group.config` 是**当前态**，`_checkGroupConstraints` 每次 `join` 都现读它，不做按轮快照。因此群主可以在加入轮中途：

- 提高 `minJoinAmount` / `maxJoinAmount` → 后续加入被拒；
- 提高 `maxCapacity` → 本轮已满的群重新开放；
- 提高 `maxAccounts` → 已满员的群重新收人；
- 修改 `description` → 只影响 `descriptionHistoryByGroupId` 的当轮快照（这一项有按轮历史）。

配置项里**只有 `description` 有按轮历史**（B2），其余四项没有。这不是缺陷（群主本来就有权改自己群的规则），但它意味着「本轮规则」在链上不可回溯——链下要还原「某笔 join 当时适用的 `maxCapacity`」必须回放 `GroupConfigChanged`，不能用 `groupState`。

### M-GAM-04 · `activatedRound` / `deactivatedRound` 的链上用途只有一处相等判定

| 字段 | 值 |
| --- | --- |
| 位置 | `:153`、`:194`、`:187` |
| 级别 | Info |
| 证据 | E1 |

两个字段的写入点清晰（激活写 `activatedRound` 与 `deactivatedRound = 0`，停用写 `deactivatedRound`），但**链上唯一读取**是 `:187` 的 `round == group.activatedRound`（同轮不可停用）。`deactivatedRound` 没有任何链上读取，`activatedRound` 除了这一次判定也只通过 `groupState()` 暴露给链下。

后果：

1. `deactivatedRound` 是纯信息字段，占一个槽位的三个字段之一（`GroupState` 里 `config` + `bool` + 两个 `uint256`）；
2. 反复激活/停用会把 `activatedRound` 覆盖为最新一次，**首次激活轮不可从状态读出**——与 `M-GAJ-04` 的 `joinedRound` 是同一类问题。

### M-GAM-05 · 三个质押计数器的维度不同却同族命名

| 字段 | 值 |
| --- | --- |
| 位置 | `:157-161`、`:303-324` |
| 级别 | Info |
| 证据 | E1 |

| getter | 实际维度 | 名字暗示的维度 |
| --- | --- | --- |
| `staked(tokenAddress, actionId)` | token + action | 同 |
| `totalStaked(tokenAddress)` | token（社区） | 同 |
| `stakedByMemberId(tokenAddress, memberId)` | token + **groupId** | 「成员」但实际是「该成员的链群」 |

第三者的第二个参数在实现里是 `groupId`（`:161`、`:199`），因为「链群主体」与「成员」是同一个 `memberId` 空间。`GAM-05`（api-auth）已登记 `hasActiveGroups(tokenAddress, memberId)` 的同款问题；本卷补的是**金额语义**：`stakedByMemberId` 返回的是「该成员作为群主、其全部激活群的押金合计」，而不是「该成员自己质押的金额」——后者在 core `Stake` 里是另一个概念。同名不同义，链下容易把它当成 `Stake.staked` 的对应物。

## 5. 已核对为正确的点

- 三个金额计数器与四个集合的增减严格成对（M1～M7），且全部在 `safeTransferFrom` / `safeTransfer` **之前**写入，CEI 成立。
- `deactivateGroup` 的 D2/D4 条件移除判据用「集合当前是否为空」（`:201`、`:204`），不是「本次移除的是最后一个」——两者等价且更稳（不依赖移除顺序）。
- `activateGroup` 的 `deactivatedRound = 0` 重置（`:154`）保证「重新激活」后不会残留上一次的停用轮。
- `_checkGroupConfig` 允许 `maxCapacity == 0` / `maxAccounts == 0`（不设限）与 `maxJoinAmount == 0`（不设上限），三种「零 = 关闭」的语义一致。
- `_checkActivationMinGovRatio` 在 `minGovRatio == 0` 时**完全不读 Stake**（`:415-417`），省掉两次外部调用；关闭下限是零成本的。
- `onProposalCreated` 的 `targetData[6]` 是可选分支：不传时 A6/A7 保持空数组，`_applyVerificationInfos` 随后要求 `verificationValues.length == 0`，两侧口径一致。
- `descriptionHistoryByGroupId` 在激活与改配置两个写点都 `record(currentJoinRound())`，轮次单调，不会出现「激活在轮 5、描述在轮 4」。
- `_maxJoinAmount` 的三段早退（round / totalVote / actionVote 为 0）保证分母非零，不会除零。

## 6. 覆盖缺口

- 未测 `_maxJoinAmount` 在 `joinTokenAddress` 是一个「`totalSupply()` 返回 0」的合法合约时的行为（结论：上限 0，任何 join 回滚 `ActionMaxJoinAmountExceeded`；未跑用例）。
- 未复核 `GroupState` 的 struct 打包（`GroupConfig` 含动态 `string`，因此 `config` 是 storage 指针；`bool` 与两个 `uint256` 是否同槽未实测）。
- 未审 `activateGroup` 在 `stakeAmount != 0` 但群主余额不足时的失败形态（`safeTransferFrom` 回滚，状态全部撤销）。
- 未审 `setGroupConfig` 的 `previousConfig` 在事件里的完整性（见 `action-events-audit-2026-11` 的 `03-group-action-manager.md`）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GAM-01` | 已修复 | `code.length` + `try totalSupply()` 双守卫，统一回滚 `InvalidJoinTokenAddress`；测试见 `test/GroupActionManager.t.sol` |
| `M-GAM-02` | 口径登记 | 溢出阈值 `1.15e59` 不可达，失败形态 Panic 0x11 已知；本次不改源码，登记于卷头 §8 第 4 项 |
| `M-GAM-03` | 设计保留 | 配置即时生效是设计选择，05 规格已按「按当前配置」描述，不改源码 |
| `M-GAM-04` | 规格补写 | `05-group-action-executor.md` 的「状态口径」：`activatedRound` / `deactivatedRound` 只用于一处相等判定，不承担时间线查询 |
| `M-GAM-05` | 规格补写 | `05-group-action-executor.md` 与 `03-participation.md`：三个计数器维度不同（自身投入 / Provider 额度 / 可用额度），不可互相换算 |
