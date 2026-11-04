# `action/GroupActionManager.sol` 错误赋值与发送专项 Review

> 基线：`action@2014788`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/05-group-action-executor.md、07-minting.md`。
> 范围：`src/GroupActionManager.sol`（506 行）+ `src/interfaces/IGroupActionManager.sol` 的 `IGroupActionManagerErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 12 个错误声明 / 23 个发送点（含 6 个跨模块复用的基座与 Executor 声明）；无未声明 revert、无裸 `require`、无 `assert`。
- 群激活、停用、配置更新的鉴权都走 `onlyGroupOwner` → `groupOwnerOrRevert`：先解析群身份存在性再比地址，符合 §5「身份解析属于鉴权」。
- `TargetDataLengthMismatch` 被用来同时表达「少于 6 项」与「多于 7 项」两个边界，`expected` 字段一名两义；规格 05/07 明文如此，属规格与 §2 的冲突，需裁决。
- `activateGroup` / `setGroupConfig` 把 config 参数校验放在状态判定之后，§5 的层序被倒置；可观测后果是「已激活群 + 非法配置」与「阶段未开始 + 有治理下限」两种情况报错指向错误原因。
- 4 条 Low（1 条载荷语义、2 条顺序、1 条命名）+ 1 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 12 |
| revert 站点 | 23 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 4 / 1 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotGroupOwner` | `NotGroupOwner(uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `GroupNotExist` | `GroupNotExist(uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `TargetDataLengthMismatch` | `TargetDataLengthMismatch(uint256,uint256)` | IActionTargetErrors | 2 | 待裁决 |
| `InvalidTargetDataShape` | `InvalidTargetDataShape(uint256,uint256)` | IActionTargetErrors | 1 | 保留 |
| `ZeroJoinTokenAddress` | `ZeroJoinTokenAddress()` | IGroupActionExecutorErrors | 1 | 保留 |
| `InvalidMaxJoinAmountRatio` | `InvalidMaxJoinAmountRatio(uint256)` | IGroupActionExecutorErrors | 1 | 保留 |
| `InvalidActivationMinGovRatio` | `InvalidActivationMinGovRatio(uint256)` | IGroupActionExecutorErrors | 1 | 保留 |
| `VerificationInfoLengthMismatch` | `VerificationInfoLengthMismatch(uint256,uint256)` | IGroupActionExecutorErrors | 1 | 保留 |
| `TooManyVerificationEntries` | `TooManyVerificationEntries(uint256,uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `VerificationKeyTooLong` | `VerificationKeyTooLong(uint256,uint256,uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `VerificationDescriptionTooLong` | `VerificationDescriptionTooLong(uint256,uint256,uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `ActionNotCreated` | `ActionNotCreated(address,uint256)` | IActionExecutorErrors | 1 | 保留 |
| `GroupAlreadyActivated` | `GroupAlreadyActivated(uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `GroupNotActive` | `GroupNotActive(uint256)` | IGroupActionManagerErrors | 2 | 保留 |
| `DeactivationLockedInActivatedRound` | `DeactivationLockedInActivatedRound(uint256,uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `InvalidMinJoinAmount` | `InvalidMinJoinAmount(uint256)` | IGroupActionManagerErrors | 1 | 待裁决 |
| `InvalidMaxJoinAmount` | `InvalidMaxJoinAmount(uint256,uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `DescriptionTooLong` | `DescriptionTooLong(uint256,uint256)` | IGroupActionExecutorErrors | 1 | 保留 |
| `NoGovVotes` | `NoGovVotes(address)` | IGroupActionManagerErrors | 1 | 保留 |
| `InsufficientActivationMinGovRatio` | `InsufficientActivationMinGovRatio(uint256,uint256,uint256)` | IGroupActionManagerErrors | 1 | 保留 |
| `RoundNotStarted` | `RoundNotStarted(uint256,uint256)` | IActionExecutorErrors | 1 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `NotGroupOwner` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:63`
- 签名：`NotGroupOwner(uint256)` · selector `0x54a55079`
- 载荷：`uint256 groupId`
- 核对：载荷为群身份键；`onlyGroupOwner` 先解析存在性再比地址，符合 §5「身份解析属于鉴权」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:33` | `modifier onlyGroupOwner` | `groupOwnerOrRevert(protocol, groupId) != msg.sender` | `groupId` |

### `GroupNotExist` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:53`
- 签名：`GroupNotExist(uint256)` · selector `0xfeddf96a`
- 载荷：`uint256 groupId`
- 核对：由 `groupOwnerOrRevert` 统一产生；`ownerOf` 不存在时不会先冒 `ERC721NonexistentToken`，而是被翻译成本错误。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:44` | `function groupOwnerOrRevert` | `owner == address(0)` | `groupId` |

### `TargetDataLengthMismatch` · 2 站点 · 待裁决

- 声明：`interfaces/IActionTarget.sol:57`（跨模块复用，本模块不重复声明）
- 签名：`TargetDataLengthMismatch(uint256,uint256)` · selector `0x232f36be`
- 载荷：`uint256 expected, uint256 actual`
- 核对：区间两端共用同一 selector，见 E-GAM-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:60` | `function onProposalCreated` | `targetData.length < TARGET_DATA_MIN_LENGTH` | `TARGET_DATA_MIN_LENGTH, targetData.length` |
| 2 | `GroupActionManager.sol:63` | `function onProposalCreated` | `targetData.length > TARGET_DATA_MAX_LENGTH` | `TARGET_DATA_MAX_LENGTH, targetData.length` |

### `InvalidTargetDataShape` · 1 站点 · 保留

- 声明：`interfaces/IActionTarget.sol:61`（跨模块复用，本模块不重复声明）
- 签名：`InvalidTargetDataShape(uint256,uint256)` · selector `0x9c2b3988`
- 载荷：`uint256 index, uint256 length`
- 核对：循环 `i = 1..5`，能定位失败项；第 0 项由 ActionTarget 校验。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:66` | `function onProposalCreated` | `targetData[i].length != 32` | `i, targetData[i].length` |

### `ZeroJoinTokenAddress` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:25`（跨模块复用，本模块不重复声明）
- 签名：`ZeroJoinTokenAddress()` · selector `0x8a1b296f`
- 载荷：无
- 核对：`targetData[1]` 为零；非合约参数零值，符合 §3。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:76` | `function onProposalCreated` | `joinTokenAddress == address(0)` | `—` |

### `InvalidMaxJoinAmountRatio` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:26`（跨模块复用，本模块不重复声明）
- 签名：`InvalidMaxJoinAmountRatio(uint256)` · selector `0x1b42d872`
- 载荷：`uint256 value`
- 核对：`> 1e18`；载荷为越界值。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:79` | `function onProposalCreated` | `maxJoinAmountRatio > GroupActionStorage.PRECISION` | `maxJoinAmountRatio` |

### `InvalidActivationMinGovRatio` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:27`（跨模块复用，本模块不重复声明）
- 签名：`InvalidActivationMinGovRatio(uint256)` · selector `0x828ac3ed`
- 载荷：`uint256 value`
- 核对：同上，按字段分别报错，未复用通用 `InvalidRatio`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:82` | `function onProposalCreated` | `activationMinGovRatio > GroupActionStorage.PRECISION` | `activationMinGovRatio` |

### `VerificationInfoLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:36`（跨模块复用，本模块不重复声明）
- 签名：`VerificationInfoLengthMismatch(uint256,uint256)` · selector `0xe5b734dc`
- 载荷：`uint256 expected, uint256 actual`
- 核对：`(keys.length, descriptions.length)`；与 `GroupActionJoin` 的「模板 vs 成员值」复用同一 selector，条件同族（两数组不等长）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:96` | `function onProposalCreated` | `keys.length != descriptions.length` | `keys.length, descriptions.length` |

### `TooManyVerificationEntries` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:70`
- 签名：`TooManyVerificationEntries(uint256,uint256)` · selector `0x60eec811`
- 载荷：`uint256 count, uint256 maxCount`
- 核对：`(count, maxCount)`，`maxCount` 为编译期常量 16。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:99` | `function onProposalCreated` | `keys.length > GroupActionStorage.MAX_VERIFICATION_ENTRIES` | `keys.length, GroupActionStorage.MAX_VERIFICATION_ENTRIES` |

### `VerificationKeyTooLong` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:74`
- 签名：`VerificationKeyTooLong(uint256,uint256,uint256)` · selector `0xcbe7d4ac`
- 载荷：`uint256 index, uint256 length, uint256 maxLength`
- 核对：`(index, length, maxLength)`，能定位第几个 key。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:107` | `function onProposalCreated` | `keyLength > GroupActionStorage.MAX_VERIFICATION_TEXT_BYTES` | `i, keyLength, GroupActionStorage.MAX_VERIFICATION_TEXT_BYTES` |

### `VerificationDescriptionTooLong` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:79`
- 签名：`VerificationDescriptionTooLong(uint256,uint256,uint256)` · selector `0xb9e185d5`
- 载荷：`uint256 index, uint256 length, uint256 maxLength`
- 核对：同上。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:114` | `function onProposalCreated` | `descriptionLength > GroupActionStorage.MAX_VERIFICATION_TEXT_BYTES` | `i, descriptionLength, GroupActionStorage.MAX_VERIFICATION_TEXT_BYTES` |

### `ActionNotCreated` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:19`（跨模块复用，本模块不重复声明）
- 签名：`ActionNotCreated(address,uint256)` · selector `0x36c193ae`
- 载荷：`address tokenAddress, uint256 actionId`
- 核对：`activateGroup` 第一段；规格 05「行动存在性判定统一回滚 `ActionNotCreated`」。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:138` | `function activateGroup` | `self.createdRoundByActionId[tokenAddress][actionId] == 0` | `tokenAddress, actionId` |

### `GroupAlreadyActivated` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:51`
- 签名：`GroupAlreadyActivated(uint256)` · selector `0xe36ee043`
- 载荷：`uint256 groupId`
- 核对：单字段群键；排在参数校验之前，见 E-GAM-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:143` | `function activateGroup` | `group.active` | `groupId` |

### `GroupNotActive` · 2 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:52`
- 签名：`GroupNotActive(uint256)` · selector `0xd28fa9ad`
- 载荷：`uint256 groupId`
- 核对：`deactivateGroup` 与 `setGroupConfig` 共用；条件单一（群未激活）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:183` | `function deactivateGroup` | `!group.active` | `groupId` |
| 2 | `GroupActionManager.sol:231` | `function setGroupConfig` | `!group.active` | `groupId` |

### `DeactivationLockedInActivatedRound` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:59`
- 签名：`DeactivationLockedInActivatedRound(uint256,uint256)` · selector `0xb1f4faaf`
- 载荷：`uint256 groupId, uint256 round`
- 核对：`(groupId, round)`；规则句改为状态句，名称符合 §3 的 `<Subject><State>`。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:188` | `function deactivateGroup` | `round == group.activatedRound` | `groupId, round` |

### `InvalidMinJoinAmount` · 1 站点 · 待裁决

- 声明：`interfaces/IGroupActionManager.sol:54`
- 签名：`InvalidMinJoinAmount(uint256)` · selector `0xedb63d2d`
- 载荷：`uint256 minAmount`
- 核对：条件为零值而非值非法，见 E-GAM-04。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:394` | `function _checkGroupConfig` | `config.minJoinAmount == 0` | `config.minJoinAmount` |

### `InvalidMaxJoinAmount` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:55`
- 签名：`InvalidMaxJoinAmount(uint256,uint256)` · selector `0x24fbf4de`
- 载荷：`uint256 minAmount, uint256 maxAmount`
- 核对：关系条件（`max < min`），载荷两字段同单位，符合 §4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:397` | `function _checkGroupConfig` | `config.maxJoinAmount != 0 && config.maxJoinAmount < config.minJoinAmount` | `config.minJoinAmount, config.maxJoinAmount` |

### `DescriptionTooLong` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:40`（跨模块复用，本模块不重复声明）
- 签名：`DescriptionTooLong(uint256,uint256)` · selector `0x71a24cf3`
- 载荷：`uint256 length, uint256 maxLength`
- 核对：`(length, maxLength)`；1024 为协议级编译期常量。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:401` | `function _checkGroupConfig` | `descriptionLength > GroupActionStorage.MAX_DESCRIPTION_BYTES` | `descriptionLength, GroupActionStorage.MAX_DESCRIPTION_BYTES` |

### `NoGovVotes` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:69`
- 签名：`NoGovVotes(address)` · selector `0xa0d4ddef`
- 载荷：`address tokenAddress`
- 核对：单字段社区键；仅在配置了治理下限时可达，见 E-GAM-05。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:423` | `function _checkActivationMinGovRatio` | `totalGovVotes == 0` | `tokenAddress` |

### `InsufficientActivationMinGovRatio` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:64`
- 签名：`InsufficientActivationMinGovRatio(uint256,uint256,uint256)` · selector `0xfc04f2b0`
- 载荷：`uint256 groupId, uint256 required, uint256 actual`
- 核对：`(groupId, required, actual)`；`required` 为配置下限、`actual` 为现算占比。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:429` | `function _checkActivationMinGovRatio` | `actualRatio < minGovRatio` | `groupId, minGovRatio, actualRatio` |

### `RoundNotStarted` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:40`（跨模块复用，本模块不重复声明）
- 签名：`RoundNotStarted(uint256,uint256)` · selector `0xea74f32b`
- 载荷：`uint256 requiredRound, uint256 currentRound`
- 核对：`(1, 0)` 固定载荷；`currentJoinRound` 是共享实现，`GroupActionJoin` 与 `GroupActionExecutor` 以 `internal` 内联复用，回滚同一载荷（02-phase-model 明文）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionManager.sol:480` | `function currentJoinRound` | `round == 0` | `1, 0` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GAM-01 | Low | `src/GroupActionManager.sol:57-62` | `TargetDataLengthMismatch(6, len)` 与 `TargetDataLengthMismatch(7, len)` 用同一个 selector 表达区间两端：前者 `expected` 是下界、后者是上界。§2 要求「一个 selector 只对应一个条件」，§4 要求「边界参数用限定名」，`expected` 既不是 `minLength` 也不是 `maxLength`。调用方只能靠 `actual` 与两个魔法数比较才能判断该补项还是该删项。 | error-standards §2 / §4；规格 05、07 明文如此（需裁决） | 二选一：(a) 保留 ABI，在 05/07 写明「`expected` 表示被违反的那一侧边界」，并在前端文档标注；(b) 新增 `TooManyTargetDataItems(count, maxCount)` / `InsufficientTargetDataItems(count, minCount)`，属破坏性 ABI 变更。 |
| E-GAM-02 | Low | `src/GroupActionManager.sol:136-149` | `activateGroup` 的判定顺序为 鉴权 → 存在性(`ActionNotCreated`) → 状态(`GroupAlreadyActivated`) → **参数**(`_checkGroupConfig`) → 资格(`_checkActivationMinGovRatio`) → 状态(`RoundNotStarted`)。§5 固定为「鉴权 → 参数 → 存在性 → 状态/资格」，参数被压到状态之后。可观测后果有两处：已激活群 + 非法配置回 `GroupAlreadyActivated`（调用方以为只需换群，实际配置也是错的）；`minGovRatio != 0` 且社区无治理票时，阶段尚未开始的调用回 `NoGovVotes` 而不是 `RoundNotStarted`（错误指向了错误的阻塞原因）。 | error-standards §5（顺序固定；自定义顺序须写明理由） | 把 `_checkGroupConfig(config)` 提到 `GroupAlreadyActivated` 之前（参数层先于状态层）；`currentJoinRound()` 的 `RoundNotStarted` 建议提到 `_checkActivationMinGovRatio` 之前，或在 05 的「实现约束」里写明该顺序及其理由。 |
| E-GAM-03 | Low | `src/GroupActionManager.sol:228-238` | `setGroupConfig` 同样把 `_checkGroupConfig` 放在 `GroupNotActive` 之后，参数层晚于状态层；与 E-GAM-02 同根，但入口不同、需要单独改。 | error-standards §5 | 把 `_checkGroupConfig(config)` 提到 `GroupNotActive` 之前。 |
| E-GAM-04 | Low | `src/GroupActionManager.sol:392-395` | `InvalidMinJoinAmount(config.minJoinAmount)` 的条件是 `minJoinAmount == 0`。§3 明确「`Invalid*` 只用于值本身非法，不用于零值」，零值应回 `Zero<Field>`；且载荷恒为 `0`，按 §4「没有行动价值时省略载荷」本不该带值。core 侧同类问题（`InvalidInitialSupply`）在上一轮 review 中判为 Low。 | error-standards §3 / §4；规格 07 明文如此（需裁决） | 改为 `ZeroMinJoinAmount()`（破坏性 ABI 变更，需集中到一个 breaking 窗口），或在 07 的错误表里登记为例外并写明理由。 |
| E-GAM-05 | Info | `src/GroupActionManager.sol:407-431` | `_checkActivationMinGovRatio` 在 `minGovRatio == 0` 时提前返回，因此 `NoGovVotes` 只在「配置了治理下限」时可达。这是有意的（未配置下限的群不要求社区有票），但 07 的错误表把 `NoGovVotes` 写成「激励代币没有全局治理票，无法计算激活下限」，未写明该前置条件。 | error-standards §5（错误集合须与规格一致） | 在 07 表 `NoGovVotes` 行补「仅当 `activationMinGovRatio != 0` 时可达」。 |

### 4.2 已核对项

- 声明全部在 `IGroupActionManagerErrors`；`ActionNotCreated` / `TargetDataLengthMismatch` / `InvalidTargetDataShape` / `VerificationInfoLengthMismatch` / `DescriptionTooLong` / `RoundNotStarted` 复用基座或 Executor 声明，符合 07 的「执行器专属错误留在各自 `Errors` 子接口」。
- `groupOwnerOrRevert` 把 `ownerOf` 的 `ERC721NonexistentToken` 经 `MemberOwner.ownerOrZero` 翻译为 `address(0)` → `GroupNotExist(groupId)`，其余 revert 原样冒泡；`onlyGroupOwner` 因此对每个群操作先做一次外呼，鉴权顺序正确。
- 创建回调的配置项顺序（项数 → 第 1～5 项形状 → 零地址 → 两个比例）与 05 逐条一致；第 0 项由 ActionTarget 校验，本库从 `i = 1` 起循环，无重复校验也无缺口。
- `InvalidMaxJoinAmount(minAmount, maxAmount)` 的载荷顺序与 §4「amount → minAmount/maxAmount」一致，且只在 `maxJoinAmount != 0` 时判定（`0` 表示不设上限）。
- `InsufficientActivationMinGovRatio(groupId, required, actual)` 的 `required` 在前，`actual` 为当前轮现算的占比；`totalGovVotes == 0` 已在上一段拦截，无除零。
- `DeactivationLockedInActivatedRound(groupId, round)` 的 `round` 是当前加入轮，与 `activatedRound` 同轴；群未激活时先回 `GroupNotActive`，两条件互斥。
- `TooManyVerificationEntries` / `VerificationKeyTooLong` / `VerificationDescriptionTooLong` 的载荷分别为 `(count, maxCount)` 与 `(index, length, maxLength)`，符合 §4 的限定名要求。
- `activateGroup` 的质押划转在全部状态写入之后、事件之前；`deactivateGroup` 的退款在状态清理之后。任一步失败整笔回滚，无残留。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `MemberOwner.ownerOrZero` 内部被翻译为 `GroupNotExist`，不外泄；但同一 helper 对其余 revert 用 `assembly { revert(add(err,0x20), mload(err)) }` 原样冒泡，因此本模块**可能携带任意 revert data**。来源：`MemberNFT`。该透传面在 05/07 均未登记。
- `SafeERC20FailedOperation` / `AddressEmptyCode` — 激活质押与停用退款的 `safeTransfer(From)`；来源 OZ `SafeERC20`。
- `ReentrancyGuardReentrantCall` — 本库自身无 `nonReentrant`，由 `GroupActionExecutor` 的包装函数承担；调用路径上可达。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。`onProposalCreated` 中 `abi.decode(targetData[6], (string[], string[]))` 的失败形态不计站点（无 selector），另见 `09-GroupActionExecutor.md` 与 README 的 X-05。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GAM-01 | Low | 已裁决（W1 #1）：拆 `InsufficientTargetDataItems` / `TooManyTargetDataItems`；`onProposalCreated` 两站点改写；测试 3 处；规格 07 让步同步。 |
| E-GAM-02 | Low | 已裁决（X-04 重排）：`_checkGroupConfig` 提前，`currentJoinRound()` 先于 `_checkActivationMinGovRatio`；新增 `testActivateGroupChecksRoundBeforeEligibility`。 |
| E-GAM-03 | Low | 已裁决（X-04 重排）：`setGroupConfig` 的参数检查先于 `group.active`；新增「未激活 + 零配置 → `ZeroMinJoinAmount`」断言。 |
| E-GAM-04 | Low | 已裁决（W1 #2）：`InvalidMinJoinAmount` → `ZeroMinJoinAmount()`；1 站点 1 接口；测试与规格 07 同步。 |
| E-GAM-05 | Info | 已裁决（X-09 文档）：05 登记 `minGovRatio == 0` 时 `NoGovVotes` 不可达的理由。 |
