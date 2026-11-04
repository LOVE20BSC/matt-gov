# GroupActionManager（库）事件赋值与发射审查

> 对象 `action/src/GroupActionManager.sol`（506 行，`library`，经 `delegatecall` 由 `GroupActionExecutor` 调用）
> 声明 `action/src/interfaces/IGroupActionManager.sol`（`IGroupActionManagerEvents`，L12-48）、`action/src/interfaces/IGroupActionExecutor.sol`（`IGroupActionExecutorEvents.GroupActionCreated`，L10-22）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 `docs/event-standards.md` v1.1、`docs/specs/action/05-group-action-executor.md`（群配置与事件段落）

## 一、结论

| 项 | 数值 |
| --- | --- |
| 协议事件 | 4 |
| 发射点 | 4（一对一） |
| 状态写入面（受事件覆盖） | 15 |
| P0 / P1 / P2 / P3 | 0 / 0 / 0 / 2 |
| 放行 | 可放行；2 项 P3 分别是「聚合量缺后置锚点」与「`deactivatedRound` 归零无字段」 |

本库承担 action 层的配置事实：创建时的行动级配置（`GroupActionCreated`）与群的三态迁移（`GroupActivated` / `GroupDeactivated` / `GroupConfigChanged`）。四类事件与四个写入口严格一一对应，没有「一个入口发多条」或「一条事件被两个入口复用」的情形，是本仓事件结构最干净的一个模块。

## 二、事件与发射点总览

| 事件 | indexed | 发射点 | 前置写入 | 紧随其后的动作 |
| --- | --- | --- | --- | --- |
| `GroupActionCreated` | `tokenAddress`, `actionId` | `_emitGroupActionCreated:438`（由 `onProposalCreated:125` 调用） | 五处配置 `:85-91`、schema 两处 `:119-120`、`createdRoundByActionId:123` | 返回 Executor → 返回 ActionTarget → 返回 Core `Submit` |
| `GroupActivated` | `tokenAddress`, `actionId`, `groupId` | `_emitGroupActivated:493`（由 `activateGroup:170` 调用） | `groupState` 四字段 `:151-154`、描述快照 `:155`、六组索引 `:158-164`、质押聚合 `:159-161` | 无（本笔结束） |
| `GroupDeactivated` | 同上 | `deactivateGroup:212` | `groupState` 两字段 `:193-194`、索引与质押聚合 `:196-206` | 无 |
| `GroupConfigChanged` | 同上 | `_emitGroupConfigChanged:459`（由 `setGroupConfig:242` 调用） | `group.config:239`、描述快照 `:240` | 无 |

族归属：`GroupActionCreated` → `action.config`；其余三条 → `action.group`。

## 三、逐事件赋值链

### 3.1 `GroupActionCreated`

```
event GroupActionCreated(
    address indexed tokenAddress,
    uint256 indexed actionId,
    address joinTokenAddress,
    uint256 activationStakeAmount,
    uint256 maxJoinAmountRatio,
    uint256 activationMinGovRatio,
    uint256 verifierStakeAmount,
    string[] verificationKeys,
    string[] verificationDescriptions
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` | 入参 `:439` | 根键 |
| `actionId` | 入参 `:440` | 父对象 id |
| `joinTokenAddress` | `abi.decode(targetData[1], (address))` `:70` → 存储 `:85` → 回读 `:441` | 已过零地址校验 `:75-77` |
| `activationStakeAmount` | `targetData[2]` `:71` → `:88` → `:442` | 无上界校验；只能写一次（`// Load-bearing:` `:86-87`） |
| `maxJoinAmountRatio` | `targetData[3]` `:72` → `:89` → `:443` | `<= 1e18`（`:78-80`） |
| `activationMinGovRatio` | `targetData[4]` `:73` → `:90` → `:444` | `<= 1e18`（`:81-83`） |
| `verifierStakeAmount` | `targetData[5]` `:74` → `:91` → `:445` | `0` 表示申请不要求押金 |
| `verificationKeys` | `abi.decode(targetData[6])` `:94` → `:119` → `:446` | 仅当 `targetData.length == 7`；否则为空数组 |
| `verificationDescriptions` | 同上 `:94` → `:120` → `:447` | 与 keys 等长（`:95-97`），≤16 项（`:98-102`），每项 ≤1024 字节（`:103-118`） |

payload 全部从**存储回读**而非直接使用局部变量（`:441-447` 逐项读 `self.*`）。这一点比直接用 calldata 更稳：事件值与 `joinTokenAddress()` / `activationStakeAmount()` / `verificationSchema()` 三个 view 天然同源，不可能出现「事件报了 A、存储存了 B」。

事件不带 `round`：创建轮由同笔 `ActionTarget.ActionRegistered.round` 承载，`createdRoundByActionId`（`:123`）与该字段同值（见 `01-action-target.md` AT-3）。这是有意的跨事件分工，不是遗漏——`action.config` 族的槽位表本身没有 `round` 槽。

### 3.2 `GroupActivated`

```
event GroupActivated(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 round,
    uint256 indexed groupId,
    uint256 stakeAmount,
    uint256 maxCapacity,
    uint256 minJoinAmount,
    uint256 maxJoinAmount,
    uint256 maxAccounts,
    string description
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `groupId` | 入参 `:494-497` | 根键 → 父 id → 本对象 id |
| `round` | `currentJoinRound(protocol.phaseAddress)` `:149` | 激活轮（= `activatedRound`），非 indexed |
| `stakeAmount` | `activationStakeAmountByActionId` `:157` | 行动级配置的只读副本；`:166-168` 按此额 `safeTransferFrom` |
| `maxCapacity` / `minJoinAmount` / `maxJoinAmount` / `maxAccounts` | `config` `:499-502` | 已过 `_checkGroupConfig` `:146`（`minJoinAmount != 0`、非零 `maxJoinAmount >= minJoinAmount`、描述 ≤1024） |
| `description` | `config.description` `:503` | ≤1024 字节（`:399-404`） |

这是**初始化型事件**：不带旧值（§3.6），携带群配置全量。同一 `groupId` 在同一行动上再次激活时重发本事件，此时语义变为「可逆迁移的逆方向」，payload 仍是全量新配置——§3.1 的快照型条款覆盖这种形态（未变化字段也带）。

`activateGroup` 的前置判定顺序是：`onlyGroupOwner:136` → `createdRound != 0` `:137-139` → `group.active == false` `:142-144` → 配置合法 `:146` → 治理占比下限 `:147`。五道判定全部早于任何写入，所以失败不留日志。

### 3.3 `GroupDeactivated`

```
event GroupDeactivated(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 round,
    uint256 indexed groupId,
    uint256 stakeAmount
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `groupId` | 入参 `:213-216` | 同 3.2 |
| `round` | `currentJoinRound(...)` `:186` | 停用轮（= `deactivatedRound`） |
| `stakeAmount` | `activationStakeAmountByActionId` `:191` | 与 `GroupActivated.stakeAmount` 恒等（该配置只能写一次），`:208-210` 按此额退回 |

`round == group.activatedRound` 时回滚 `DeactivationLockedInActivatedRound:187-189`，因此停用轮恒大于激活轮；但**同一轮内「停用后立即重新激活」是允许的**（重新激活后 `activatedRound` 被改成该轮，再停用才被拦），由此产生 `GroupActivated(R) → GroupDeactivated(R) → GroupActivated(R)` 的同轮三连（见 GAM-EV-2）。

事件不带 `deactivatedRound` 之外的状态，也不带配置：配置由最近的 `GroupActivated` / `GroupConfigChanged` 折叠得到，停用不改配置。

### 3.4 `GroupConfigChanged`

```
event GroupConfigChanged(
    address indexed tokenAddress,
    uint256 indexed actionId,
    uint256 round,
    uint256 indexed groupId,
    uint256 maxCapacity,
    uint256 minJoinAmount,
    uint256 maxJoinAmount,
    uint256 maxAccounts,
    string description,
    uint256 prevMaxCapacity,
    uint256 prevMinJoinAmount,
    uint256 prevMaxJoinAmount,
    uint256 prevMaxAccounts,
    string prevDescription
);
```

| 字段 | 赋值来源（源码行） | 说明 |
| --- | --- | --- |
| `tokenAddress` / `actionId` / `groupId` | 入参 `:460-463` | 同 3.2 |
| `round` | `currentJoinRound(...)` `:238` | 变更发生的加入轮；同时是描述快照的键 |
| `maxCapacity` … `maxAccounts` | `config` `:464-467` | 新值组 |
| `description` | `config.description` `:468` | 新值 |
| `prevMaxCapacity` … `prevMaxAccounts` | `previousConfig` `:469-472` | `previousConfig = group.config` `:236`，在 `:239` 覆写**之前**取的 memory 副本 |
| `prevDescription` | `previousConfig.description` `:473` | 同上 |

新值组 → 旧值组，组内槽位一致（§6.7）。旧值不是布尔取反可推，逐项携带。`_checkGroupConfig`（`:234`）在取旧值之前，因此非法配置不会产生任何日志。

同一加入轮内多次 `setGroupConfig` 时，事件逐条给出 `A→B`、`B→C`，而 `descriptionByRound(R)` 只保留 C（`:240` 覆写同键）。这与 §3.4「同一 Round 多次操作只保留该轮最终值，事件仍按发生顺序逐条记录」一致。

## 四、状态写入与事件覆盖对照

| 状态 | 写入点 | 承载事件 | 折叠口径 |
| --- | --- | --- | --- |
| `joinTokenAddressByActionId` 等 5 项行动配置 | `:85-91` | `GroupActionCreated`（5 个数值/地址字段） | 只写一次 |
| `verificationKeysByActionId` / `verificationDescriptionsByActionId` | `:119-120` | `GroupActionCreated` 两个数组 | 只写一次 |
| `createdRoundByActionId` | `:123` | `ActionRegistered.round`（跨合约） | 同值，见 AT-3 |
| `groupState.config` | `:151`、`:239` | `GroupActivated` / `GroupConfigChanged` | 全量快照，后写覆盖 |
| `groupState.active` | `:152`、`:193` | `GroupActivated`（true）/ `GroupDeactivated`（false） | 取最后一条 |
| `groupState.activatedRound` | `:153` | `GroupActivated.round` | 取最后一条 |
| `groupState.deactivatedRound` | `:154`（置 0）、`:194` | `GroupDeactivated.round`；置 0 由 §7.2 重置规则推导 | 见 GAM-EV-2 |
| `descriptionHistoryByGroupId` | `:155`、`:240` | `GroupActivated.description` / `GroupConfigChanged.description` | 按轮快照，同轮覆写 |
| `activeGroupIdsByActionId` | `add:158` / `remove:196` | `GroupActivated` / `GroupDeactivated` | 派生索引 |
| `stakedByActionId` | `+=:159` / `-=:197` | 同上（增量） | 见 GAM-EV-1 |
| `totalStaked` | `+=:160` / `-=:198` | 同上（增量） | 见 GAM-EV-1 |
| `stakedByMemberId` | `+=:161` / `-=:199` | 同上（增量） | 见 GAM-EV-1 |
| `tokenAddressesByGroupId` | `add:162` / `remove:202` | 同上 | 派生索引（条件删除） |
| `actionIdsByGroupId` | `add:163` / `remove:200` | 同上 | 派生索引 |
| `activeActionIds` | `add:164` / `remove:205` | 同上 | 派生索引（条件删除） |

15 个写入面全部有事件覆盖。六个索引是纯派生（`GroupActivated`/`GroupDeactivated` 的 `(token, action, group)` 三元组足够），符合 §6.9。

## 五、规范对照

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 根键首字段（§6.1） | 通过 | 4 个事件均以 `tokenAddress` 开头 |
| 族槽位 `action.config` | 通过 | 根键 → `actionId` → 配置地址 → 配置数值 ×4 → 文本数组 ×2 |
| 族槽位 `action.group` | 通过 | 根键 → `actionId` → `round` → `groupId` → 配置值 → 旧值 |
| indexed ≤ 3 且族内一致（§6.3） | 通过 | `action.group` 三事件同为 `tokenAddress`/`actionId`/`groupId`，`round` 一致降级 |
| 初始化事件不带旧值（§3.6） | 通过 | `GroupActionCreated`、`GroupActivated` 无旧值；`GroupConfigChanged` 带旧值 |
| 状态写入后 emit（§3.4.3） | 通过 | 4 个发射点全部在写入之后 |
| 资金先于事件（§6.5） | 通过 | `activateGroup` 的 `safeTransferFrom:166` 早于 `:170`；`deactivateGroup` 的 `safeTransfer:208` 早于 `:212` |
| 动态字段上限（§6.8） | 通过 | `description` ≤1024（`:399-404`）；`verificationKeys`/`Descriptions` ≤16 项、每项 ≤1024 |
| 声明与发射写法（§6.11） | 通过 | `check-events.py` 全绿 |
| 测试断言（§8.1） | 通过 | `GroupActionEvents.t.sol:412` 三事件逐字段；`:894` 描述上限；`:374` 可逆迁移 |

## 六、发现

### GAM-EV-1（P3，已裁决：不新增事件字段）三个质押聚合量只在改变点携带增量，没有后置总量锚点

> **处置（2026-11-04，已裁决）**：保持两个事件签名不变，在 `05-group-action-executor.md` 与 `event-standards.md` §7.2 书面登记「本族三个聚合量按增量折叠、不设后置锚点」，理由是激活质押属低频两点族（每群一次写入 + 低频停用/重启），与 core `Stake` 的高频每轮聚合不同。落点：`05-group-action-executor.md`「群配置事件」段、`event-standards.md` §7.2。

- 证据：`GroupActivated.stakeAmount`（`:498`）与 `GroupDeactivated.stakeAmount`（`:217`）只给本次增减额；`stakedByActionId`（`:159`/`:197`）、`totalStaked`（`:160`/`:198`）、`stakedByMemberId`（`:161`/`:199`）三个聚合被这两个事件同时改变，但事件里没有它们的后置值。
- 问题：§3.1 明确「一个聚合量被多个事件改变时，**每个改变点都应当携带后置总量**；只在一部分改变点携带属于族内漂移」。本族是「两个改变点、两处都不携带」，与 core `Stake` 的做法（`totalValidGovVotes` / `totalLiquidityShares` 在每个改变点都带后置值，§8.1 第 8 条逐项枚举）不一致。
- 影响：`staked(token, actionId)`、`totalStaked(token)`、`stakedByMemberId(token, memberId)` 三个 view 只能靠消费方自己维护累加器；一旦漏掉一条事件（或把 `GroupActivated` 的重复激活当成首次激活），三个 view 全部漂移且链上无任何交叉校验点。`GroupServiceExecutor` 直接依赖 `totalStaked` 作为 `joinedAmountByActionId` 的返回值（`GroupServiceExecutor:190-192`），漂移会传导到服务层展示。
- 建议：二选一——在 `GroupActivated` / `GroupDeactivated` 各加 `stakedTotal`（行动级）与 `stakedTotalByToken`（社区级）两个后置值；或在 `05-group-action-executor.md` 的「群配置事件」段落书面登记「本族的聚合量按增量折叠，不设后置锚点」，并说明与 core `Stake` 的差异理由（激活质押是低频、单点写入，`activationStakeAmount` 只写一次，因此增量折叠不会因配置变更而失配）。

### GAM-EV-2（P3，已裁决：不新增事件字段）`deactivatedRound` 的「归零」只能由 §7.2 的重置规则推导，事件里没有该字段

> **处置（2026-11-04，已裁决）**：保持 `GroupActivated` 字段不变，在 `event-standards.md` §7.2 补折叠规则：「`deactivatedRound` 取最后一条 `GroupDeactivated.round`；其后出现 `GroupActivated` 即按清零语义取 0」。落点：`event-standards.md` §7.2、`05-group-action-executor.md`「群配置事件」段。

- 证据：`activateGroup` 在 `:154` 把 `deactivatedRound` 置 0，但 `GroupActivated` 的 payload 只有 `round`（= `activatedRound`）。同一加入轮内「停用 → 重新激活」是可达的：`deactivateGroup` 只拦 `round == activatedRound`（`:187-189`），重新激活后 `activatedRound` 才被改成该轮，所以 `GroupActivated(2) → GroupDeactivated(3) → GroupActivated(3)` 是一条合法日志序列。
- 问题：`groupState()` 返回 `(config, active, activatedRound, deactivatedRound)`，在最后一条 `GroupActivated(3)` 之后 `deactivatedRound == 0`，但事件流里 `GroupDeactivated(round=3)` 仍然存在。消费方若按「`deactivatedRound` = 最后一条 `GroupDeactivated.round`」折叠，会得到 3 而非 0。
- 影响：`groupState` 的第四个返回值与事件折叠结果不一致，且没有任何链上校验会发现；依赖 `deactivatedRound != 0` 判断「该群是否曾经停用」的消费方会误判。
- 建议：在 §7.2 已有的「`activateGroup` 允许重新激活并把 `deactivatedRound` 重置为 0」一句后面补一句「因此 `deactivatedRound` 的折叠规则是『最后一条 `GroupActivated` 之后清零，否则取最后一条 `GroupDeactivated.round`』」；或让 `GroupActivated` 携带 `deactivatedRound: 0`（快照型字段，与 `AdminChanged` 带整组快照同型）。

### 已撤除的结论（GAM-EV-3，原判 P2）库地址不可被直接 `CALL`，`GroupActionCreated` 的 emitter 唯一

本报告初版曾把「`GroupActionCreated` 可从库地址直接伪造」列为 P2，理由是 `onProposalCreated` 是 `external` 且无 modifier、五道守卫全部来自入参、`GroupActionManager` 又是部署后有独立地址的 `public library`。**这条推断被字节码与运行实测否定，已撤除。** 记录在此以便审计链完整。

机制：Solidity 为含 `external` 函数的库在 dispatcher 前置**自地址守卫**。四个业务库的 `deployedBytecode` 开头完全同型：

```text
73 <20 字节库地址> 30 14 ...
↑PUSH20            ↑ADDRESS ↑EQ
```

`out/GroupActionManager.sol/GroupActionManager.json` 里这 20 字节是链接期占位 `0x00…00`（本仓 `GroupActionExecutor` 的 `linkReferences` 在 16 个偏移上引用 `GroupActionManager`），部署时由链接器填入库的真实地址。直接 `CALL` 时 `ADDRESS() == 自身地址` 成立 → 立即 revert，`returndata = 0x`、`logs = 0`。

因此库的 `emit` 只有两条可达路径，两条的 emitter 都等于调用合约：

| 可见性 | 调用形态 | emitter |
| --- | --- | --- |
| `internal` | 编译期内联，库无独立地址 | 调用合约 |
| `external` / `public` | 只能 `DELEGATECALL` | 调用合约 |

「直接 `CALL` 库地址」这条第三条路被编译器堵死。`GroupActionCreated` 的运行时 emitter 恒为 `GroupActionExecutor`，§4.1 成立。

残余价值（不是事件缺陷）：`onProposalCreated` 的守卫全部来自入参、没有一条读 `Layout`，这一点仍值得作为**纵深防御**记录——事件唯一性目前同时依赖「编译器守卫」与「ActionTarget 的 `AlreadyCreated`」两道，若将来编译器行为变化或库改为 `internal`，就只剩后者。这属接口权限视角，见 `action-api-auth-2026-11/07-group-action-manager.md` GAM-01。

### 正面结论（不计入发现）

- `GroupActionCreated` 的 8 个字段全部从存储回读（`:441-447`），与三个 view 天然同源，不存在「事件值与存储不一致」的可能。
- `GroupConfigChanged` 的旧值取自 `:236` 的 memory 副本，位置在 `:239` 覆写之前，不会出现「新旧同值」。
- `activateGroup` / `deactivateGroup` 的资金步（`:166-168` / `:208-210`）都早于 emit，符合 §6.5 与 §4.4 的「转账后立即 emit」方向。
- 五道/三道前置判定全部早于写入，失败零日志。

## 七、测试断言对照

| 事件 | 用例 | 覆盖内容 |
| --- | --- | --- |
| `GroupActionCreated` | `GroupActionEvents.t.sol:23` | 8 字段全量（含两个空数组） |
| `GroupActionCreated` | `:54` | 验证 schema 非空时的两项数组逐项 |
| `GroupActionCreated` | `:758` | 16 项 keys 边界 |
| `GroupActivated` | `:412` | 10 字段；`round = 2`、`stakeAmount = ACTIVATION_STAKE` |
| `GroupActivated` | `:894` | 1024 字节描述边界 |
| `GroupDeactivated` | `:412` | 5 字段；`round = 3` |
| `GroupDeactivated` | `:374` | 可逆：停用后再激活并重置 `deactivatedRound` |
| `GroupConfigChanged` | `:412` | 14 字段；新旧组逐项区分（`maxCapacity 0→500e18`、`minJoinAmount 1e18→2e18`、`description group→v2`） |

缺一条：没有用例断言「同一加入轮内 停用 → 重新激活」后的 `groupState().deactivatedRound == 0`（GAM-EV-2 的复现路径）。建议补一条，同时断言三条日志的 `round` 全为该轮。
