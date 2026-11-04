# GroupActionRoundAxis · 状态变量变更审查

> `action/src/GroupActionRoundAxis.sol`，**修复后 16 行**（基线 21 行，join 已移出），`action@0c1d1e2`。
> 职责：`phase → round` 的类型专属换算，两个函数（verify / mint）。`joinRound` 已删除，加入轮统一由中立库 `ActionRoundAxis` 定义、`ExecutorBase._joinRound()` 单一实现。**无状态、无存储、无事件、无错误**，因此本卷的审查对象不是「写什么」，而是「返回 0 这个哨兵被谁怎么用」。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

无。文件内没有状态变量、常量、struct 或 mapping。

| 函数 | 签名 | 返回 | 说明 |
| --- | --- | --- | --- |
| `verifyRound` | `(address phaseAddress) → uint256` | `phase < 3 ? 0 : phase − 2` | 验证轮 |
| `mintRound` | `(address phaseAddress) → uint256` | `phase < 4 ? 0 : phase − 3` | 铸币轮 |

两个函数都是 `internal view`，编译期内联到调用方，不产生跨合约调用（`02-phase-model.md:24-26` 明确「轴库只做纯换算，未开始守卫不在轴库里」）。

## 2. 逐变量变更逻辑

无状态写入。唯一的外部读是 `IPhase(phaseAddress).currentPhase()`，每函数一次。

| 函数 | 外部读 | 返回值域 |
| --- | --- | --- |
| `verifyRound` | `currentPhase()` | `{0} ∪ [1, ∞)` |
| `mintRound` | 同上 | `{0} ∪ [1, ∞)` |

**0 是「阶段未开始」的哨兵**，两个函数都用它（join 的同一哨兵在 `ActionRoundAxis`）。因此「返回 0」与「返回一个合法的轮次」在类型上不可区分，每个调用方必须自己判。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| X1 | `ActionRoundAxis.joinRound(p) == verifyRound(p) + 1 == mintRound(p) + 2`（三者都非 0 时） | ✅ | 三个偏移同源于 `currentPhase()`，join 定义在中立库 |
| X2 | 三个函数对同一 `p` 单调不减 | ✅ | `currentPhase()` 单调不减（`Phase.phaseAtBlock` 的段内整除） |
| X3 | 返回 0 ⟺ 阶段未开始 | ✅ | 唯一的 `phase < k` 分支 |
| X4 | 函数本身不回滚 | ✅ | 无 require / 无外部调用的返回值解码（`currentPhase()` 返回 `uint256`，解码不会失败） |

## 4. 发现

### M-AXS-01 · `phase − 1` 在轴库之外还有一份字面副本（`ActionTarget`），「轴库只做纯换算」这条分层对加入轮不成立

| 字段 | 值 |
| --- | --- |
| 位置 | 修复前：`GroupActionRoundAxis:7-10`、`LpRoundAxis:7-10`、`ActionTarget:378-385`；修复后：`ActionRoundAxis:9`（唯一） |
| 级别 | Info |
| 证据 | E1 |

三个偏移的**字面副本**分布：

| 偏移 | 定义（唯一） | 消费方 |
| --- | --- | --- |
| `phase − 1`（join） | **`ActionRoundAxis:9`** | `ExecutorBase._joinRound():134`（单一实现，非 virtual）、`ActionTarget._joinRound():383`、`GroupActionManager:378/485` |
| `phase − 2`（verify） | `GroupActionRoundAxis:7` | `GroupActionVerify` / `GroupServiceExecutor`（内联复用） |
| `phase − 3`（mint） | `GroupActionRoundAxis:12`、`GroupServiceRoundAxis:7` | GroupAction / GroupService 各自 |
| `phase − 2`（LP mint） | `LpRoundAxis:7` | `LpExecutor:442` |

`ActionTarget._joinRound()` 曾是第三份 `phase − 1`，且不在任何轴库里——`ActionTarget` 当时只 import `IPhase`。修复前后果：

1. **`ActionTarget` 用自己的公式给加入快照定轮**（修复前 `registerJoinState:127` 的 `currentRound - 1`、`clearJoinState:153` 的 `_joinRound()`），而三个 Executor 用轴库的公式给同一个快照**查询**轮次（`GroupActionExecutor.joinedAmountByActionId:618`、`GroupServiceExecutor:694-696`）。
2. 两处公式修复前逐字相同（`phase < 2 ? 0 : phase - 1` vs `currentRound == 0 ? 0 : currentRound - 1`），但没有任何编译期或测试期断言绑定它们。
3. 若将来只改一处（例如把加入轮改成 `phase`），`ActionTarget` 会按旧轮写入、Executor 按新轮查询，`isJoinedByRound` 恒 false，服务结算**静默跳过所有成员**——不报错。

`GroupServiceExecutor:690-693` 修复前用 `Load-bearing` 注释登记了这条约束（「必须与 ActionTarget 的加入轮相等」），但注释在 Executor、副本在 `ActionTarget`、第三份在轴库。修复后三处全部消失：`ActionTarget:128` 改为 `_joinRound()`，`ExecutorBase:134` 是唯一实现，`GroupServiceExecutor` 的 join override 与注释一并删除。`SUP-02`（api-auth）曾登记「两个轴库的 `joinRound` 逐字节相同，且 `ActionTarget` 有第三份同式」，本卷补的是**状态后果**：三份副本中任何一份漂移，失败形态是静默的，不是回滚。

修复方向：抽出中立库 `ActionRoundAxis`，让 `ActionTarget` 与两个类型轴库共同委托（底座共用合约不依赖带业务类型名字的库），或把 `phase − 1` 收进 `IPhase` 的 helper（会改 core）。

**处置（已修复，最终形态）**：`joinRound` 只在 `ActionRoundAxis:9` 定义一次。`ExecutorBase._joinRound():134` 去掉 `virtual`、改为单一实现；`GroupActionExecutor` / `GroupServiceExecutor` / `LpExecutor` 三处 override 删除。`ActionTarget` import 由 `GroupActionRoundAxis` 换为 `ActionRoundAxis`，`registerJoinState:128` 的内联 `currentRound - 1` 改为 `_joinRound()`，与 `clearJoinState` / `forceClearJoinState` 共用同一实现。`GroupActionManager:378`（`_maxJoinAmount`）与 `:485`（`currentJoinRound`）直接调 `ActionRoundAxis`。两个类型轴库删除 `joinRound`，`GroupActionRoundAxis` 21 → 16 行、`LpRoundAxis` 16 → 11 行，`ActionTarget.sol` 与 `GroupServiceExecutor.sol` 内均不再出现 `GroupActionRoundAxis`。

### M-AXS-02 · 返回 0 的哨兵在消费方有两种处理，同一条件产生两种错误

| 字段 | 值 |
| --- | --- |
| 位置 | `GroupActionVerify:521-527`（守卫）、`GroupActionManager:477-483`（守卫）、`ExecutorBase:130-132`（不守卫） |
| 级别 | Info |
| 证据 | E1 |

三个消费者对同一个「返回 0」的处理不同：

| 消费方 | 处理 | 结果 |
| --- | --- | --- |
| `GroupActionVerify.currentVerifyRound` | `round == 0` → revert | `RoundNotStarted(1, 0)` |
| `GroupActionManager.currentJoinRound` | `round == 0` → revert | `RoundNotStarted(1, 0)` |
| `GroupActionExecutor._joinRound` / `_mintRound` | **原样返回 0** | 加入面由调用方比较；铸币面已在 `ExecutorBase._checkMintWindow` 统一为 `RoundNotStarted(1, 0)`（M-EB-01 已修复） |
| `LpExecutor._joinRound` / `_mintRound` | 同上 | 同上 |

前两者是「守卫式」，后两者是「透传式」。透传式导致 `ExecutorBase._checkMintWindow` 在阶段未开始时给出 `RoundAfterMintWindow(round, 0)` 而不是 `RoundNotStarted`——该差异已在 M-EB-01 的修复中消除（铸币面改守卫，加入面保持透传）。

`02-phase-model.md:26` 把这种差异写成「未开始守卫由消费方承担」，但没写「两种承担方式的错误不同」；已在 02 规格的「状态口径」补写。

## 5. 已核对为正确的点

- 三个函数都只做一次 `currentPhase()` 读 + 一次比较 + 一次减法，没有外部调用、没有状态、没有 `try/catch`，因此不会引入重入或 gas 意外。
- `phase < k ? 0 : phase - k` 的写法保证减法不下溢（`phase >= k` 时才减）。
- 返回 0 而不是回滚，使 `GroupActionExecutor.joinedAmountByActionId` 这类读面能对「未来轮」返回 0 而不抛错（`:618-620`），符合「读面越界返回零值」的惯例。
- `verifyRound` 只在 GroupAction 侧存在（LP 无验证阶段），没有虚构一个 LP 的验证轮——规格 `02:6` 明确要求「LP 不提供虚构的验证接口」。
- 三个函数都是 `internal`，因此不进入任何 ABI，也不产生独立的部署地址（对比 `GroupActionStorage` 这类 public 库）。

## 6. 覆盖缺口

- 未验证 `Phase.currentPhase()` 在 `ORIGIN_BLOCKS` 之前的返回（按 `Phase.phaseAtBlock` 应为 0，`currentPhaseBlocks` 与 `phaseInfo(0)` 才回滚）；本卷按「返回 0」认定，因此轴库的 `phase < k` 分支在冷启动期是可达的。
- 未审 `currentPhase()` 在 `Phase` 未部署或地址错误时的行为（`STATICCALL` 到空地址返回空 → 解码失败 → 回滚；轴库无 `try/catch`）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-AXS-01` | 已修复 | `joinRound` 只在 `ActionRoundAxis:9` 定义；`ExecutorBase._joinRound():134` 单一实现（非 virtual），`ActionTarget:128` 的内联副本改为 `_joinRound()`，三个 Executor override 与三处类型轴 join 全部删除；见本条 |
| `M-AXS-02` | 规格补写 | [`02-phase-model.md`](../../docs/specs/action/02-phase-model.md) 的「轴库与哨兵」：0 哨兵的守卫式/透传式两种承担方式与对应错误 |
