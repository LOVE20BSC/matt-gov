# `action/GroupRecipients.sol` 错误赋值与发送专项 Review

> 基线：`action@2014788`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/action/06-service-executor.md（二次分配）`。
> 范围：`src/GroupRecipients.sol`（367 行）+ `src/interfaces/IGroupRecipients.sol` 的 `IGroupRecipientsErrors`。
> 口径：「赋值」= revert 时写入 payload 的表达式；「发送」= `revert <Error>(...)` 站点。纯 `assert` / 裸 `require` 另行核对。

## 1. 结论

- 8 个错误声明 / 8 个发送点，一一对应；无未声明 revert、无裸 `require`、无 `assert`。
- 形状错误（三数组等长、条数上限）先于逐元素判定，逐元素判定覆盖「等于 groupId / 比例为零 / 备注超长 / 重复 / NFT 有效」，符合 §6 的批量原子性。
- `UnknownSourceAction` 排在数组形状之前，§5 的「参数 → 存在性」被倒置；规格 06 的叙述顺序与实现同向。
- `DistributionOverflow(configured, available)` 用「额度」语义的字段名承载上限常量 `1e18`。
- 无 Medium / Low；3 条 Info。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 8 |
| revert 站点 | 8 |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 3 |

## 2. 错误清单

| 错误 | 签名 | 声明 | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `UnknownSourceAction` | `UnknownSourceAction(address,uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `RecipientArrayLengthMismatch` | `RecipientArrayLengthMismatch(uint256,uint256,uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `TooManyRecipients` | `TooManyRecipients(uint256,uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `RecipientIsGroupId` | `RecipientIsGroupId(uint256,uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `ZeroRecipientRatio` | `ZeroRecipientRatio(uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `RemarkTooLong` | `RemarkTooLong(uint256,uint256,uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `DuplicateMemberId` | `DuplicateMemberId(uint256)` | IGroupRecipientsErrors | 1 | 保留 |
| `DistributionOverflow` | `DistributionOverflow(uint256,uint256)` | IGroupRecipientsErrors | 1 | 口径调整 |

## 3. 逐错误明细

> 每个错误列出声明、载荷实参、全部发送点与判据；「实参赋值」列就是 revert 时写入 payload 的表达式。

### `UnknownSourceAction` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:24`
- 签名：`UnknownSourceAction(address,uint256)` · selector `0x6ea46b42`
- 载荷：`address sourceTokenAddress, uint256 sourceActionId`
- 核对：`(sourceTokenAddress, sourceActionId)`；条件是「本 Executor 未创建该源行动」，用 `joinTokenAddress == 0` 判定。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:86` | `function _setRecipients` | `IGroupActionExecutor(protocol.groupActionExecutorAddress).joinTokenAddress(sourceTokenAddress, sourceActionId) == address(0)` | `sourceTokenAddress, sourceActionId` |

### `RecipientArrayLengthMismatch` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:33`
- 签名：`RecipientArrayLengthMismatch(uint256,uint256,uint256)` · selector `0xaae80407`
- 载荷：`uint256 recipientIdsLength, uint256 ratiosLength, uint256 remarksLength`
- 核对：三长度入载荷，符合 §4 的批量形状。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:308` | `function _checkRecipients` | `length != table.ratios.length \|\| length != table.remarks.length` | `length, table.ratios.length, table.remarks.length` |

### `TooManyRecipients` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:28`
- 签名：`TooManyRecipients(uint256,uint256)` · selector `0x3971ddf8`
- 载荷：`uint256 count, uint256 maxCount`
- 核对：`(count, maxCount)`；10 为协议级编译期常量。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:313` | `function _checkRecipients` | `length > GroupServiceStorage.DEFAULT_MAX_RECIPIENTS` | `length, GroupServiceStorage.DEFAULT_MAX_RECIPIENTS` |

### `RecipientIsGroupId` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:39`
- 签名：`RecipientIsGroupId(uint256,uint256)` · selector `0x6f819480`
- 载荷：`uint256 groupId, uint256 recipientId`
- 核对：`(groupId, recipientId)`；两字段同单位（memberId），符合 §4。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:320` | `function _checkRecipients` | `recipientId == groupId` | `groupId, recipientId` |

### `ZeroRecipientRatio` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:32`
- 签名：`ZeroRecipientRatio(uint256)` · selector `0x4a3b43a3`
- 载荷：`uint256 recipientId`
- 核对：单字段接收人键；条件为该接收人比例为 0。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:323` | `function _checkRecipients` | `table.ratios[i] == 0` | `recipientId` |

### `RemarkTooLong` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:43`
- 签名：`RemarkTooLong(uint256,uint256,uint256)` · selector `0x56fa372b`
- 载荷：`uint256 index, uint256 length, uint256 maxLength`
- 核对：`(index, length, maxLength)`；能定位第几条备注。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:327` | `function _checkRecipients` | `remarkLength > GroupServiceStorage.MAX_REMARK_BYTES` | `i, remarkLength, GroupServiceStorage.MAX_REMARK_BYTES` |

### `DuplicateMemberId` · 1 站点 · 保留

- 声明：`interfaces/IGroupRecipients.sol:38`
- 签名：`DuplicateMemberId(uint256)` · selector `0x1a494813`
- 载荷：`uint256 memberId`
- 核对：单字段；O(n²) 去重，n ≤ 10。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:331` | `function _checkRecipients` | `table.recipientIds[j] == recipientId` | `recipientId` |

### `DistributionOverflow` · 1 站点 · 口径调整

- 声明：`interfaces/IGroupRecipients.sol:20`
- 签名：`DistributionOverflow(uint256,uint256)` · selector `0x81281d08`
- 载荷：`uint256 configured, uint256 available`
- 核对：`available` 字段名与语义错位，见 E-GR-01。

| # | 位置 | 函数 | 判据 | 实参赋值 |
| --- | --- | --- | --- | --- |
| 1 | `GroupRecipients.sol:338` | `function _checkRecipients` | `totalRatios > GroupServiceStorage.PRECISION` | `totalRatios, GroupServiceStorage.PRECISION` |

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-GR-01 | Info | `src/GroupRecipients.sol:337-339` | `DistributionOverflow(configured, available)` 的 `available` 实际是精度常量 `1e18`（比例上限），不是「可用额度」。§4 规定上限用 `actual + limit`、额度用 `required + available`，此处字段名把上限伪装成了额度。 | error-standards §4（上限：`actual + limit`） | 参数名改为 `(uint256 configured, uint256 limit)`（selector 不变），与同族的 `TooManyRecipients(count, maxCount)` 对齐。 |
| E-GR-02 | Info | `src/GroupRecipients.sol:82-89` | `_setRecipients` 先判源行动是否存在（`UnknownSourceAction`），再判三数组形状（`RecipientArrayLengthMismatch`）。§5 的顺序是「参数 → 存在性」。后果：对一个不存在的源行动提交长度不等的数组，回的是 `UnknownSourceAction`，调用方要先修正源行动才能发现数组问题。 | error-standards §5 | 把 `_checkRecipients` 的「等长 + 条数」两段提到 `UnknownSourceAction` 之前（逐元素部分仍可留在后面），或在 06 里写明该顺序的理由。 |
| E-GR-03 | Info | `src/GroupRecipients.sol:316-339` | 没有「比例之和为零」的独立错误：全空表被定义为「显式清空」（合法），非空表因每项比例必须 > 0 而和 ≥ 1。因此 `Σ ratio == 0` 只能由空表达成，语义自洽；但 06 只写了「全部传空表示显式清空」，未写「非空表的比例和必 ≥ 1」这条推论，读规格的人容易以为存在「和为零」的拒绝路径。 | error-standards §2 / §6（no-op 与显式清空的区分） | 在 06 的「二次分配」段补一句：「非空表的每项比例为正，故比例和恒 ≥ 1；`DistributionOverflow` 只覆盖 `> 1e18`」。 |

### 4.2 已核对项

- 声明全部在 `IGroupRecipientsErrors`，实现零声明；`IGroupServiceExecutor` 继承该接口，错误在 Service 的 ABI 上可见。
- `RecipientArrayLengthMismatch(recipientIdsLength, ratiosLength, remarksLength)` 三个长度都进载荷，能定位哪一侧不等长，符合 §4。
- `TooManyRecipients(count, maxCount)`、`RemarkTooLong(index, length, maxLength)`、`ZeroRecipientRatio(recipientId)`、`DuplicateMemberId(memberId)`、`RecipientIsGroupId(groupId, recipientId)` 的载荷均为定长标量且能定位失败元素，符合 §4。
- 接收人 NFT 的有效性由 `IMemberNFT.ownerOf(recipientId)` 表达，不占本模块 selector（符合 §1「标准错误由产生者拥有」）；`MemberNFT` 无销毁入口，因此结算时再读 `ownerOf` 不会因 NFT 消失而回滚。
- `distribution` / `_calculateRecipientAmounts` 的逐项 `mulDiv` 向下取整，`Σ amounts ≤ groupReward`，`ownerAmount = groupReward - distributed` 不下溢；与 06「`Σ 转账 + 销毁 ≤ serviceReward` 为承重不变量」一致。
- `setRecipients` 的鉴权与轮次校验在 Service 侧（`onlyGroupOwner` 先于 `currentVerifyRound`），符合 06「鉴权先于轮次校验」。

### 4.3 透传错误面

- `ERC721NonexistentToken` — `_checkRecipients` 与 `_distributeToRecipients` 的 `ownerOf(recipientId)`；来源 `MemberNFT`。前者在配置期、后者在结算期，两条路径都可能抛出。
- `SafeERC20FailedOperation` — 逐接收人 `safeTransfer`；来源 OZ。
- `RoundNotStarted` — Service 侧 `currentVerifyRound()` 在调用本库之前抛出。

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py
forge test
```

> 扫描口径：同 01。`_distributeToRecipients` 的循环内 `ownerOf` / `safeTransfer` 失败整笔回滚（含已发出的转账与事件）。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-GR-01 | Info | 已裁决（文档口径）：`DistributionOverflow` 字段 `available` → `limit`，selector 不变；规格 07/06 同步。 |
| E-GR-02 | Info | 已裁决（X-04 重排）：`_checkRecipients` 先于 `UnknownSourceAction`；`testSetRecipientsRejectsUnknownSourceAction` 追加 `DuplicateMemberId` 断言。 |
| E-GR-03 | Info | 已裁决（X-09 文档）：06 登记「无 `Σ ratio == 0` 独立错误」的自洽理由。 |
