# GroupRecipients（库）接口调用权限审查

> 对象 `action/src/GroupRecipients.sol`（367 行，`library`，经 `delegatecall` 由 `GroupServiceExecutor` 调用）
> 接口 `action/src/interfaces/IGroupRecipients.sol`（94 行）
> 基线 `action@8478619`（`src/` 自 `e849e36` 无实质变化，行号未位移）；审查日期 2026-11-03
> 判据 dev-standards §5.5、§5.2.2、§4.2（事件）；`specs/action/06-service-executor.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| `external` 函数 | 6（写 2 / 读 4） |
| 带鉴权 modifier | **0** |
| 无许可写入口 | 2（`setRecipients` 鉴权在 Executor；`distribute` 无鉴权但仅供内部结算） |
| 发现 | 3 条 Info；另有 2 条正面结论（另撤回 1 条原判 Info，见 GRC-01） |
| 接口对账 | 由 `GroupServiceExecutor` 侧统一对账（35 vs 35，0 差异） |

一句话：**这是全仓唯一一个「写函数既无 modifier 也无锁」的库，但两条写函数的鉴权与调用时机都在 Executor 上：`setRecipients` 由 `onlyGroupOwner` 把关，`distribute` 只在结算路径里被调。** 本库的两个关键依赖（MemberNFT、GroupActionExecutor）是 `protocol` 入参而非 `immutable`，这一点值得作为纵深防御记录；但「库地址可被直接调用并伪造事件」的原判已被字节码实测否定（编译器自地址守卫，见 GRC-01 的撤回说明）。

## 二、权限模型

| 入口 | 权限主体 | 判定位置 |
| --- | --- | --- |
| `setRecipients` | `groupId` 持有人 | **本库无判定**，由 `GroupServiceExecutor.onlyGroupOwner(groupId)`（`GroupServiceExecutor.sol:56`、`L308`）承担 |
| `distribute` | 无（内部结算路径） | 无判定；唯一调用点是 `GroupServiceExecutor._mintMemberReward`（`L756`），后者在 `onlyMemberOwner` + `nonReentrant` 之下 |

本库**没有任何鉴权代码**。它假定调用方已经判完身份——`protocol.memberNFTAddress` 只在两处用到：`_checkRecipients` 的存在性检查（`ownerOf(recipientId)`）与 `_distributeToRecipients` 的付款对象（`ownerOf(recipientIds[j])`），都不是鉴权。

## 三、入口清单

### 写入口（2）

| 函数 | 权限主体 | 资金方向 | 事件 |
| --- | --- | --- | --- |
| `setRecipients(address,uint256,uint256,uint256[],uint256[],string[])` | `groupId` 持有人（Executor 侧） | 无 | `RecipientsChanged`（新→旧全量） |
| `distribute(address,address,uint256,uint256,uint256,uint256,uint256)` | 无（结算内部） | 逐接收者 `safeTransfer` | 逐接收者 `RecipientPaid` |

### 只读入口（4）

`recipients`、`actionIdsWithRecipients`、`distribution`、`projectedDistribution`。

`distribution` 是**任意金额试算**（`groupReward` 由调用方给），不做余额检查、不写状态；`projectedDistribution` 是「按当前配置预估会分出去多少」，供 `serviceRewardByMemberId` 的 `ownerDistributed` 投影使用。

## 四、逐入口判定

### `setRecipients` — 七个校验，顺序有两处偏离

`_setRecipients`（`L70-118`）与 `_checkRecipients`（`L301-340`）合起来的判定顺序：

| # | 校验 | 错误 | 类别 |
| --- | --- | --- | --- |
| 1 | 源行动由 `GroupActionExecutor` 创建（`joinTokenAddress != 0`） | `UnknownSourceAction` | **存在性** |
| 2 | 三数组等长 | `RecipientArrayLengthMismatch` | 参数 |
| 3 | 项数 ≤ 10 | `TooManyRecipients` | 参数 |
| 4 | 逐项：`recipientId != groupId` | `RecipientIsGroupId` | 参数 |
| 5 | 逐项：比例非零 | `ZeroRecipientRatio` | 参数 |
| 6 | 逐项：`remark ≤ 256` 字节 | `RemarkTooLong` | 参数 |
| 7 | 逐项：不重复 | `DuplicateMemberId` | 参数 |
| 8 | 逐项：`ownerOf(recipientId)` 存在 | `ERC721NonexistentToken`（透传） | 存在性 |
| 9 | `Σratio ≤ 1e18` | `DistributionOverflow` | 参数 |

两处偏离 §5.2.2（「鉴权 → 参数 → 存在性 → 状态/资格」）：

- **第 1 步的存在性排在全部参数校验之前**（见 GRC-02）；
- **第 8 步的存在性夹在第 7 步之后、第 9 步之前**（数组长度类参数在前、逐项存在性居中、总和在后）。

判定：都不是安全缺陷（无鉴权差异、无信息泄漏），但错误分类不稳定——同一个「数组不等长 + 源行动不存在」的调用会先报 `UnknownSourceAction`。

**轮次不由本库校验**（见 GRC-03）：`round` 是入参，`GroupServiceExecutor` 传的是 `currentVerifyRound()`，因此只能写当前验证轮。

### `distribute` — 只在结算路径里被调

顺序（`L168-196`）：`ownerReward == 0 || ownerWeight == 0` 直接返回 0 → 读该轮该群的已配置源行动列表 → 逐个算 `ownerSlice` → 逐个 `_distributeToRecipients`（逐接收者 `mulDiv` + `safeTransfer(ownerOf(id))` + `RecipientPaid`）。

- **两个早退**：owner 份额为零或权重为零时不分（避免 `mulDiv` 除零）。
- **只遍历「本轮配置过的源行动」**：`actionIdsWithRecipients[sourceTokenAddress][groupId].valuesByRound(round, 0, max, false)`。未配置的行动整份切片留在 owner 手里。
- **不做余额检查**：`distribute` 假定调用方已把 `ownerReward` 从服务代币池里留出来。调用方是 `_mintMemberReward`，它先 `mintActionReward` 拿到整笔、再算 `remaining = ownerReward - distributed`，所以「Σ转账 ≤ ownerReward」由 `_calculateRecipientAmounts` 的向下取整保证（见 GRC-06）。

### 四个只读入口

`recipients` 按 `round` 读三份历史（懒继承到不晚于该轮的最近记录）；`actionIdsWithRecipients` 是标准分页（swap-and-pop 删除，`offset` 不保证跨调用稳定，规格已写明）；`distribution` 是纯函数式试算；`projectedDistribution` 与 `distribute` 同构但不转账。

## 五、发现

### GRC-02（Info）`setRecipients` 的存在性校验排在参数校验之前

- 证据：`_setRecipients` 第一步就是 `UnknownSourceAction`（`L82-87`），之后才进 `_checkRecipients` 的数组校验（`L89`）。
- §5.2.2 的顺序是「鉴权 → 参数 → 存在性 → 状态/资格」。这里存在性在前。
- 后果：链下无法用「先修参数再重试」的固定策略——参数错与源行动错会交错出现。
- 建议：把 `_checkRecipients` 提到 `UnknownSourceAction` 之前（纯顺序调整，不改任何计算结果），或在规格里登记这条顺序。

### GRC-03（Info）库不校验轮次：写哪一轮完全由调用方传入

- 证据：`setRecipients(self, protocol, uint256 round, ...)`（`L48-58`），`round` 是裸入参，库内无任何「必须是当前轮」的判定。
- 当前防线：唯一调用方 `GroupServiceExecutor.setRecipients` 传 `currentVerifyRound()`（`GroupServiceExecutor.sol:312`），因此只能写当前验证轮，历史轮不可回写、未来轮不可预写。
- 风险形状：这条约束是「调用方传对」而非「库拒绝错」。若将来有第二个调用方（例如补录工具、迁移脚本）直接调库，可以任意改写历史轮配置——而历史轮配置是**已结算金额的组成部分**（`distribute` 按结算轮的配置付款），改写会让视图与已发生的转账不一致。
- 建议：在库的签名注释或规格里写明「`round` 必须由调用方保证是当前验证轮」，或把 `currentVerifyRound()` 的求值移进库内（需要 `phaseAddress`，`Protocol` 里没有）。

### GRC-04（Info）`setRecipients` 在库内无 modifier，鉴权完全外置

- 证据：`L48-58`，签名后直接进 `_setRecipients`，无 `only*`。
- 与 `GroupActionJoin`（6 个写入口全带库内 `onlyMemberOwner`）、`GroupActionManager`（3 个带库内 `onlyGroupOwner`）、`GroupActionVerify`（3 个带库内 `onlyMemberOwner`）对比，本库是唯一一个**一条鉴权都不写**的库。
- 判定：当前安全（唯一调用方已判 `onlyGroupOwner`），但四个库的鉴权分布不一致，评审时容易漏看。建议在 `06-service-executor.md` 的库表里给本库加一列「鉴权位置：调用方」。

### GRC-05（正面结论）配置面九项校验完整，没有留下「配了但不合法」的状态

- 证据：三数组等长 + 项数上限 10 + `recipientId != groupId` + 比例非零 + `remark ≤ 256` + 去重 + NFT 存在 + `Σratio ≤ 1e18` + 源行动存在。
- 判定：九项覆盖了「形状、规模、主体、数值、文本、唯一性、存在性、总量、作用域」八个维度。特别是 `Σratio ≤ 1e18` 让「100% 分配合法、超过即拒」成立，不留「配置合法但结算时下溢」的路径。`DistributionOverflow` 的载荷 `(configured, available)` 也给了链下定位所需的两端值。

### GRC-06（正面结论）向下取整使「Σ转账 ≤ 切片」成为结构性结论，而不是靠检查

- 证据：`_calculateRecipientAmounts`（`L342-353`）：`amounts[i] = mulDiv(groupReward, ratios[i], PRECISION)`，`distributed` 是逐项之和；`distribution` 里 `ownerAmount = groupReward - distributed`（`L165`）。
- 判定：因为每项都向下取整，`Σ amounts[i] ≤ groupReward × Σ ratios[i] / 1e18 ≤ groupReward`，所以 `ownerAmount ≥ 0` 恒成立，不需要任何下溢检查。规格把 `Σ 转账 + 销毁 ≤ serviceReward` 列为承重不变量，本库的取整方式使这条不变式在算术层面自动成立。

### 已撤除的结论（GRC-01，原判 Info）`setRecipients` 无法被直接调用，库地址不会发出 `RecipientsChanged`

本报告初版把「直接调用 `setRecipients` 即可让 `GroupRecipients` 库地址发出伪造的 `RecipientsChanged`」列为 Info，理由是 4 个业务库以 `public` 库部署（`11_deploy.sh` 从 broadcast 产物提取 4 个库地址）、`external` 函数会进库自身的 ABI 分发器、而本入口的两条守卫（`UnknownSourceAction` 与 `ownerOf`）全部可被自造的 `protocol` 满足。**这条推断被字节码与运行实测否定，已撤除。** 记录在此以便审计链完整。

- 机制：Solidity 为含 `external` 函数的库在 dispatcher 前置**自地址守卫**。`GroupRecipients` 的 `deployedBytecode` 开头是 `PUSH20 <自身地址> ADDRESS EQ`（`out/GroupRecipients.sol/GroupRecipients.json` 里该 20 字节是链接期占位 `0x00…00`；`GroupServiceExecutor` 的 `linkReferences` 在 7 个偏移上引用本库），部署时由链接器填入真实地址。
- 直接 `CALL` 时 `ADDRESS() == 自身地址` 成立 → 在函数体执行前 revert，`returndata = 0x`、`logs = 0`。**分发器层就挡住了**：初版逐条列举的那三条守卫（`UnknownSourceAction`、三数组校验、`ownerOf` 存在性）根本不会被求值。
- 因此库的 `emit` 只有两条可达路径，两条的 emitter 都等于调用合约：`internal`（编译期内联，库无独立地址）与 `external` / `public`（只能 `DELEGATECALL`）。`RecipientsChanged` 的运行时 emitter 恒为 `GroupServiceExecutor`。
- 唯一能让库代码在非调用者地址发事件的方式是把库运行时码 COPY 到新地址部署（守卫比较的是硬编码的原地址，副本地址不等 → 放行），但 emitter 是副本地址、不是协议地址，不污染协议事件流。

仍然成立的部分（作为**纵深防御**记录，不是缺陷）：本库两条关键依赖是 `protocol` 入参而非 `immutable`，若将来库改为 `internal`、或编译器移除该守卫，就只剩「守卫读 `Layout`」这一道（本库两条守卫都不读 `Layout`）。建议在 `06-service-executor.md` 里保留一句「`RecipientsChanged` 的折叠以 emitter 为 `GroupServiceExecutor` 为前提」。

与本次撤回同源的还有 `GroupActionManager.onProposalCreated`（见 `07` 的 GAM-01 附注与 README G-03），三处一并更正。

## 六、核对证据

```text
$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0    # 本库无 msg.sender 判定，检查器无对象可报

$ python3 …/evidence/auth_scan.py | grep GroupRecipients
GroupRecipients  写入口 2  带 modifier 0  无 modifier 2
  [NONE] setRecipients  -
  [NONE] distribute     -
```

鉴权负例（经 Executor）：

| 用例 | 位置 |
| --- | --- |
| 非群主 `setRecipients` | `test/GroupServiceRecipients.t.sol:84` |
| 鉴权先于轮次 | `test/GroupServiceRecipients.t.sol:92` |
| 群不存在 | `test/GroupServiceRecipients.t.sol:101` |
| 群主仍受轮次约束 | `test/GroupServiceRecipients.t.sol:109` |
| 源行动未知 | `test/GroupServiceRecipients.t.sol:70` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | `GroupActionExecutor.joinTokenAddress` | `setRecipients` 的源行动存在性判据 |
| 被调 | Core `MemberNFT` | `ownerOf`（接收者存在性 + 付款对象） |
| 被调 | `IERC20` | `safeTransfer`（逐接收者付款） |
| 被调 | `GroupServiceStorage.groupReward` | `ownerSlice` 的群切片权重（再委托 `GroupActionExecutor.generatedActionRewardByGroupId`） |
| 被复用 | `GroupServiceExecutor` | 6 个 `external` 入口全部由它转发 |

## 处置

`GRC-02`～`GRC-04` 的落点见 `README.md` §十（`06-service-executor.md`）；`GRC-01` 已撤回，`GRC-04` 为鉴权位置登记。
