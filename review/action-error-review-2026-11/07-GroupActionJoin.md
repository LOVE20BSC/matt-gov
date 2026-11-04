# `action/GroupActionJoin.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/03-participation.md、05-group-action-executor.md、07-minting.md`。
> 范围：`src/GroupActionJoin.sol`（849 行）+ `src/interfaces/IGroupActionJoin.sol` 的 `IGroupActionJoinErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 16 个错误声明 / 27 个发送点（含 4 个跨模块复用）；无未声明 revert、无裸 `require`、无 `assert`。
- `join` / `withdraw` / `exit` / Provider 额度五件的「鉴权 → 参数 → 存在性 → 状态/资格 → 账本 → 交互」骨架成立，转账一律排在账本写入之后。
- `GroupNotExist(0)` 在四处把「`groupId` 参数为零」并入「群身份不存在」；测试已把该行为固化为契约（`test/GroupActionJoin.t.sol:371`），属规格与 §2 的冲突，需裁决。
- `ActionMaxJoinAmountExceeded` 在行动本轮无票 / 比例为 0 / 轮未开始时也会以 `limit = 0` 触发，「超限」一名承载四种成因。
- 1 条 Low + 4 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 16 |
| revert 站点 | 27 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 1 / 4 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `NotMemberOwner` | `NotMemberOwner(uint256)` | IActionExecutorErrors | 1 | 保留 |
| `ZeroParticipationAmount` | `ZeroParticipationAmount()` | IGroupActionJoinErrors | 2 | 保留 |
| `GroupNotExist` | `GroupNotExist(uint256)` | IGroupActionManagerErrors | 4 | 待裁决 |
| `AlreadyInOtherGroup` | `AlreadyInOtherGroup(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `WithdrawAmountExceeded` | `WithdrawAmountExceeded(uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `ZeroQuotaAmount` | `ZeroQuotaAmount(uint256)` | IGroupActionJoinErrors | 2 | 保留 |
| `NotJoined` | `NotJoined(address,uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `QuotaArrayLengthMismatch` | `QuotaArrayLengthMismatch(uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `GroupNotActive` | `GroupNotActive(uint256)` | IGroupActionManagerErrors | 2 | 保留 |
| `QuotaMemberIsProvider` | `QuotaMemberIsProvider(uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `QuotaNotGranted` | `QuotaNotGranted(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 口径调整 |
| `GroupMaxJoinAmountExceeded` | `GroupMaxJoinAmountExceeded(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `GroupAccountsFull` | `GroupAccountsFull(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `BelowMinJoinAmount` | `BelowMinJoinAmount(uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `GroupCapacityExceeded` | `GroupCapacityExceeded(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `ActionMaxJoinAmountExceeded` | `ActionMaxJoinAmountExceeded(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 口径调整 |
| `TooManyVerificationValues` | `TooManyVerificationValues(uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `VerificationInfoLengthMismatch` | `VerificationInfoLengthMismatch(uint256,uint256)` | IGroupActionExecutorErrors | 1 | 保留 |
| `VerificationValueTooLong` | `VerificationValueTooLong(uint256,uint256,uint256)` | IGroupActionJoinErrors | 1 | 保留 |
| `InsufficientProviderQuota` | `InsufficientProviderQuota(uint256,uint256,uint256)` | IGroupActionJoinErrors | 2 | 保留 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `NotMemberOwner` · 1 站点 · 保留

- 声明：`interfaces/IActionExecutor.sol:23`（跨模块复用，本模块不重复声明）
- 签名：`NotMemberOwner(uint256)` · selector `0x33393244`
- 载荷：`uint256 memberId`
- 核对：本地 modifier，与基座同签名；载荷为身份键。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:35` | `modifier onlyMemberOwner` | `IMemberNFT(protocol.memberNFTAddress).ownerOf(memberId) != msg.sender` | `memberId` |

### `ZeroParticipationAmount` · 2 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:67`
- 签名：`ZeroParticipationAmount()` · selector `0x4ae8f898`
- 载荷：无
- 核对：加入与撤回共用；无载荷，符合 §3。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:67` | `function _join` | `amount == 0` | `—` |
| 2 | `GroupActionJoin.sol:127` | `function withdraw` | `amount == 0` | `—` |

### `GroupNotExist` · 4 站点 · 待裁决

- 声明：`interfaces/IGroupActionManager.sol:53`（跨模块复用，本模块不重复声明）
- 签名：`GroupNotExist(uint256)` · selector `0xfeddf96a`
- 载荷：`uint256 groupId`
- 核对：四处为「参数为零」，见 E-GAJ-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:70` | `function _join` | `groupId == 0` | `0` |
| 2 | `GroupActionJoin.sol:171` | `function withdrawProviderQuota` | `groupId == 0` | `0` |
| 3 | `GroupActionJoin.sol:325` | `function _addProviderQuota` | `groupId == 0` | `0` |
| 4 | `GroupActionJoin.sol:376` | `function removeProviderQuota` | `groupId == 0` | `0` |

### `AlreadyInOtherGroup` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:68`
- 签名：`AlreadyInOtherGroup(uint256,uint256,uint256)` · selector `0x246d0493`
- 载荷：`uint256 memberId, uint256 existingGroupId, uint256 requestedGroupId`
- 核对：三字段齐备，能定位冲突双方。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:76` | `function _join` | `joinedGroupId != 0 && joinedGroupId != groupId` | `memberId, joinedGroupId, groupId` |

### `WithdrawAmountExceeded` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:102`
- 签名：`WithdrawAmountExceeded(uint256,uint256)` · selector `0xbffdd230`
- 载荷：`uint256 amount, uint256 joined`
- 核对：`(amount, ownAmount)`；`ownAmount` 只算自有账本，Provider 额度不走此入口。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:133` | `function withdraw` | `amount > ownAmount` | `amount, ownAmount` |

### `ZeroQuotaAmount` · 2 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:111`
- 签名：`ZeroQuotaAmount(uint256)` · selector `0xb88ef067`
- 载荷：`uint256 memberId`
- 核对：载荷为主体键；单条/批量两种语义见 E-GAJ-05。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:168` | `function withdrawProviderQuota` | `amount == 0` | `memberId` |
| 2 | `GroupActionJoin.sol:342` | `function _addProviderQuota` | `amounts[i] == 0` | `memberId` |

### `NotJoined` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:73`
- 签名：`NotJoined(address,uint256,uint256)` · selector `0x847d1a6f`
- 载荷：`address tokenAddress, uint256 actionId, uint256 memberId`
- 核对：条件为「自有与全部 Provider 均为 0」，与 03「总参与量归零才自动退出」同源。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:189` | `function exit` | `ownAmount == 0 && self.providerAmountHistoryByMemberId[tokenAddress][actionId][memberId].latestValue() == 0` | `tokenAddress, actionId, memberId` |

### `QuotaArrayLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:106`
- 签名：`QuotaArrayLengthMismatch(uint256,uint256)` · selector `0x4a0b0bf7`
- 载荷：`uint256 memberIdsLength, uint256 amountsLength`
- 核对：形状错误，两长度入载荷；先于存在性与状态判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:322` | `function _addProviderQuota` | `memberIds.length != amounts.length` | `memberIds.length, amounts.length` |

### `GroupNotActive` · 2 站点 · 保留

- 声明：`interfaces/IGroupActionManager.sol:52`（跨模块复用，本模块不重复声明）
- 签名：`GroupNotActive(uint256)` · selector `0xd28fa9ad`
- 载荷：`uint256 groupId`
- 核对：两站点同条件（`!group.active`），`addProviderQuota` 与 `join` 各一处。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:329` | `function _addProviderQuota` | `!self.groupState[tokenAddress][actionId][groupId].active` | `groupId` |
| 2 | `GroupActionJoin.sol:636` | `function _checkGroupConstraints` | `!group.active` | `groupId` |

### `QuotaMemberIsProvider` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:110`
- 签名：`QuotaMemberIsProvider(uint256)` · selector `0x3791977c`
- 载荷：`uint256 providerId`
- 核对：单字段；条件 `memberId == providerId`，与 03「成员须不同于 Provider」一致。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:339` | `function _addProviderQuota` | `memberId == providerId` | `providerId` |

### `QuotaNotGranted` · 1 站点 · 口径调整

- 声明：`interfaces/IGroupActionJoin.sol:112`
- 签名：`QuotaNotGranted(uint256,uint256,uint256)` · selector `0x6ce01173`
- 载荷：`uint256 groupId, uint256 providerId, uint256 memberId`
- 核对：批量严格模式未写进规格，见 E-GAJ-04。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:447` | `function _removeQuota` | `refundable == 0` | `groupId, providerId, memberId` |

### `GroupMaxJoinAmountExceeded` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:83`
- 签名：`GroupMaxJoinAmountExceeded(uint256,uint256,uint256)` · selector `0xda731d54`
- 载荷：`uint256 memberId, uint256 actual, uint256 limit`
- 核对：`(memberId, actual, limit)`；`actual` 含自有 + Provider + 本次金额。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:643` | `function _checkGroupConstraints` | `group.config.maxJoinAmount != 0 && newTotal > group.config.maxJoinAmount` | `memberId, newTotal, group.config.maxJoinAmount` |

### `GroupAccountsFull` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:93`
- 签名：`GroupAccountsFull(uint256,uint256,uint256)` · selector `0xbf0861bd`
- 载荷：`uint256 groupId, uint256 count, uint256 maxCount`
- 核对：`(groupId, count, maxCount)`；只在首次加入时判定，`maxAccounts == 0` 表示不设上限。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:649` | `function _checkGroupConstraints` | `group.config.maxAccounts != 0 && memberCount >= group.config.maxAccounts` | `groupId, memberCount, group.config.maxAccounts` |

### `BelowMinJoinAmount` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:98`
- 签名：`BelowMinJoinAmount(uint256,uint256)` · selector `0x21bb7f42`
- 载荷：`uint256 actual, uint256 minAmount`
- 核对：`(actual, minAmount)`；只在首次加入时判定，追加不受下限约束（与 05 一致）。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:652` | `function _checkGroupConstraints` | `amount < group.config.minJoinAmount` | `amount, group.config.minJoinAmount` |

### `GroupCapacityExceeded` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:88`
- 签名：`GroupCapacityExceeded(uint256,uint256,uint256)` · selector `0x5b3f94ec`
- 载荷：`uint256 groupId, uint256 actual, uint256 limit`
- 核对：`(groupId, actual, limit)`；`actual` 为群总量加入后值，`maxCapacity == 0` 时不判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:660` | `function _checkGroupConstraints` | `newGroupTotal > group.config.maxCapacity` | `groupId, newGroupTotal, group.config.maxCapacity` |

### `ActionMaxJoinAmountExceeded` · 1 站点 · 口径调整

- 声明：`interfaces/IGroupActionJoin.sol:78`
- 签名：`ActionMaxJoinAmountExceeded(uint256,uint256,uint256)` · selector `0x2de9248d`
- 载荷：`uint256 memberId, uint256 actual, uint256 limit`
- 核对：`limit = 0` 的复合语义见 E-GAJ-02。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:666` | `function _checkGroupConstraints` | `newTotal > actionMaxJoinAmount` | `memberId, newTotal, actionMaxJoinAmount` |

### `TooManyVerificationValues` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:122`
- 签名：`TooManyVerificationValues(uint256,uint256)` · selector `0x4097cdca`
- 载荷：`uint256 count, uint256 maxCount`
- 核对：`(count, maxCount)`；先于「与模板项数不符」判定，规格未规定先后。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:710` | `function _applyVerificationInfos` | `verificationValues.length > GroupActionStorage.MAX_VERIFICATION_ENTRIES` | `verificationValues.length, GroupActionStorage.MAX_VERIFICATION_ENTRIES` |

### `VerificationInfoLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionExecutor.sol:36`（跨模块复用，本模块不重复声明）
- 签名：`VerificationInfoLengthMismatch(uint256,uint256)` · selector `0xe5b734dc`
- 载荷：`uint256 expected, uint256 actual`
- 核对：`(keys.length, verificationValues.length)`；与模板不等长时触发，跨模块复用 Executor 声明。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:715` | `function _applyVerificationInfos` | `verificationValues.length != keys.length` | `keys.length, verificationValues.length` |

### `VerificationValueTooLong` · 1 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:126`
- 签名：`VerificationValueTooLong(uint256,uint256,uint256)` · selector `0x762fe301`
- 载荷：`uint256 index, uint256 length, uint256 maxLength`
- 核对：`(index, length, maxLength)`，能定位第几个值。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:721` | `function _applyVerificationInfos` | `valueLength > GroupActionStorage.MAX_VERIFICATION_TEXT_BYTES` | `i, valueLength, GroupActionStorage.MAX_VERIFICATION_TEXT_BYTES` |

### `InsufficientProviderQuota` · 2 站点 · 保留

- 声明：`interfaces/IGroupActionJoin.sol:117`
- 签名：`InsufficientProviderQuota(uint256,uint256,uint256)` · selector `0xca9ef3f9`
- 载荷：`uint256 providerId, uint256 required, uint256 available`
- 核对：`(providerId, required, available)`；`required` 在前，符合 §4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupActionJoin.sol:745` | `function _increaseAmount` | `amount > available` | `providerId, amount, available` |
| 2 | `GroupActionJoin.sol:829` | `function _withdrawProviderQuota` | `amount > available` | `providerId, amount, available` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GAJ-01 | Low | `src/GroupActionJoin.sol:70`、`:171`、`:325`、`:376` | 四处 `revert GroupNotExist(0)` 的判据都是 `groupId == 0`，即「参数缺省」而非「群身份不存在」。§2 要求一个 selector 只对应一个条件，§3 要求非合约参数的零值用 `Zero<Field>`。后果：调用方无法据 selector 区分「你忘了传 groupId」与「这个群不存在」，而这两件事的处置完全不同（补参数 vs 换群）。四处都传字面量 `0` 而非 `groupId`，虽然等价，但同样不再由判据表达式派生。 | error-standards §2 / §3；规格 03「额度入口的 `groupId == 0` 或群身份不存在回 `GroupNotExist(groupId)`」明文如此（需裁决） | 新增 `ZeroGroupId()` 并在这四处改用它（破坏性 ABI 变更），或在 03/05 写明「`groupId == 0` 归入 `GroupNotExist(0)`，链下按载荷为 0 区分」。 |
| E-GAJ-02 | Info | `src/GroupActionJoin.sol:664-667` | `ActionMaxJoinAmountExceeded(memberId, newTotal, 0)` 会在四种情形下触发：本轮该行动无票、本轮该行动票数为 0 而社区有票、`maxJoinAmountRatio` 配置为 0、以及「额度真的用完」。条件本身单一（`newTotal > limit`），载荷 `limit = 0` 也能区分，但「额度用完」与「本轮不可加入」对前端的文案完全不同，需要再读 `totalVoteAmount` / `voteAmountByProposalId` 才能判断。 | error-standards §2（错误名要说明什么失败了）/ §4（行动价值） | 在 05 的「实现约束」补一句：行动级上限为 `0` 时该轮不可加入，`ActionMaxJoinAmountExceeded` 的 `limit` 为 0 即表示此情形。 |
| E-GAJ-03 | Info | `src/GroupActionJoin.sol:79-81` | `_join` 把 `currentJoinRound()`（可回 `RoundNotStarted`）排在 `_checkGroupConstraints` 之后；而 `phase < 2` 时不可能存在激活群（`activateGroup` 自身要求加入轮 ≥ 1），因此 `join` 路径上 `RoundNotStarted` 不可达，阶段未开始的调用实际回 `GroupNotActive`。语义上更贴切，但这是一处「写了却到不了」的站点。 | error-standards §8（不保留不可达路径） | 无需改实现；建议在 05 的校验顺序表里写明「`join` 以群激活状态为前置，`RoundNotStarted` 在该入口由 `GroupNotActive` 覆盖」。 |
| E-GAJ-04 | Info | `src/GroupActionJoin.sol:444-448` | `_removeQuota` 对「授权额度已为 0」的成员回 `QuotaNotGranted`，即批量收回是**严格模式**（逐项回 `*NotFound`）。§6 要求「批量删除不存在的元素默认 no-op；若模块选择严格模式，必须在规格写明」。03-participation 只写了「空 `memberIds` 在群存在时是空操作」，没写「已收回的成员逐项回滚」，因此一次 `removeProviderQuota` 里混入一个已收回的成员会让整笔回滚。 | error-standards §6（批量删除的 no-op / 严格模式必须写明） | 在 03-participation 的「Provider 额度接口」段补一句：「`removeProviderQuota` 对授权额度已为零的成员回 `QuotaNotGranted`，整批回滚；调用方须先读 `providerQuotas` 过滤」。 |
| E-GAJ-05 | Info | `src/GroupActionJoin.sol:168`、`:342` | `ZeroQuotaAmount(memberId)` 的载荷是主体键而不是失败量（金额恒为 0，无信息），符合 §4「主体键在前」；但同一 selector 在单条入口（`withdrawProviderQuota`）与批量入口（`addProviderQuota` 第 i 个元素）语义不同：前者定位「该成员的额度」，后者定位「第 i 个成员」。规格 03/07 未区分这两种用法。 | error-standards §4（批量：失败元素键或索引） | 在 07 的错误表里注明「`ZeroQuotaAmount` 的 `memberId` 在批量入口指向失败元素，在单条入口指向该成员」。 |

### 4.2 已核对项

- 声明全部在 `IGroupActionJoinErrors`；`NotMemberOwner` / `GroupNotExist` / `GroupNotActive` / `VerificationInfoLengthMismatch` 复用其他本地接口，符合 §1「相同条件允许本地重复声明，不跨仓导入」。
- `join` 的资产来源分流正确：`providerId == 0` 走自有账本并 `safeTransferFrom`，非零走额度账本且不转账（额度已在授予时存入）；两条路径都只在账本更新后发生交互。
- `AlreadyInOtherGroup(memberId, existingGroupId, requestedGroupId)` 的载荷把「谁、现属哪个、想换到哪个」三要素齐备，符合 §4。
- `GroupMaxJoinAmountExceeded` / `ActionMaxJoinAmountExceeded` / `GroupCapacityExceeded` 统一为 `(…, actual, limit)`，`GroupAccountsFull` 用 `(groupId, count, maxCount)`，边界参数均为限定名，符合 §4。
- `BelowMinJoinAmount(actual, minAmount)` 与 `InsufficientProviderQuota(providerId, required, available)` 的字段序符合 §4 的「实际值 → 边界」与「required + available」。
- `_addProviderQuota` 的形状错误（`QuotaArrayLengthMismatch`）先于群存在性/激活状态，符合 §5「参数 → 存在性 → 状态」；空数组的 no-op 排在这些校验之后，符合 §6「no-op 不得先于参数/身份/资格校验」。
- `_finalizeExit` 的调用点（`withdraw` 全额、`exit`、`_revokeQuota` 归零）都保证「自有 + 全部 Provider 归零」才触发，`clearJoinState` 在状态清理之后、`GroupActionExited` 之前，与事件规范 §4.4 一致。
- `_quotaUsedAt` 在成员当前群不等于查询群时返回 0，避免了「换群后旧群额度被算作已用」；该不变式有注释登记（`:486-488`）。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `onlyMemberOwner` 与 `_addProviderQuota` 的成员存在性检查（`ownerOf(memberId)`）；来源 `MemberNFT`。
- `SafeERC20FailedOperation` / `AddressEmptyCode` — `_pullJoinToken`、`withdraw`、`exit`、`addProviderQuota`、`removeProviderQuota`、`_withdrawProviderQuota`；来源 OZ `SafeERC20`。
- `RoundNotStarted` 由 `GroupActionManager.currentJoinRound` 内联抛出（`internal`），站点记在 `GroupActionManager.sol:480`。
- `JoinNotOpen` — `ActionTarget.registerJoinState`；来源 `IActionTargetErrors`。
- `GroupActionExecutor` 的 `nonReentrant` 在包装层，`ReentrancyGuardReentrantCall` 在调用路径上可达。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。`GroupActionJoin.join` 是 `external` 库函数，经 `delegatecall` 执行，`msg.sender` 与 storage 均与 Executor 一致。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GAJ-01 | Low | 已裁决（W1 #3）：新增 `ZeroGroupId()`，4 个 `GroupNotExist(0)` 站点改写；规格 03 从「归一」改为分开，05/07 同步。 |
| E-GAJ-02 | Info | 已裁决（X-09 文档）：03 登记 `ActionMaxJoinAmountExceeded(…, 0)` 的多成因口径。 |
| E-GAJ-03 | Info | 已裁决（文档口径）：保留 `_join` 的守卫顺序，03 登记 `phase < 2` 无激活群、错误先后不变。 |
| E-GAJ-04 | Info | 已裁决（X-09 文档）：03 补 `removeProviderQuota` 严格模式。 |
| E-GAJ-05 | Info | 已裁决（X-09 文档）：03 登记 `ZeroQuotaAmount(memberId)` 单条/批量同载荷。 |
