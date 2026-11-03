# 支撑库（存储 / 轮次轴 / 成员所有权）接口调用权限审查

> 对象：
> `action/src/GroupActionStorage.sol`（190 行，`library`）
> `action/src/GroupServiceStorage.sol`（80 行，`library`）
> `action/src/GroupActionRoundAxis.sol`（21 行，`library`）
> `action/src/LpRoundAxis.sol`（16 行，`library`）
> `action/src/MemberOwner.sol`（26 行，`library`）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 dev-standards §5.3（注释）、§5.5（鉴权位置）、§3.3（24KB 拆分）；`specs/action/02-phase-model.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| `external` / `public` 函数 | **0**（五个文件全部只有 `internal` 成员） |
| 鉴权代码 | 0 |
| 发现 | 2 条 Info；另有 2 条正面结论 |
| ABI | 无（不单独部署为可调用合约） |

一句话：**这五个文件不含任何 ABI 入口，因此没有「谁能调」的问题；它们的权限意义在别处——`MemberOwner.ownerOrZero` 是四处群主鉴权的唯一判据函数，两个轮次轴决定写入落在哪一轮（因而决定「能写哪一轮的状态」这条边界）。**

## 二、逐个文件的权限相关性

### `MemberOwner` — 四处鉴权判定的共同底座

```solidity
function ownerOrZero(address memberNFTAddress, uint256 memberId) internal view returns (address) {
    try IMemberNFT(memberNFTAddress).ownerOf(memberId) returns (address owner) {
        return owner;
    } catch (bytes memory err) {
        if (err.length >= 4 && bytes4(err) == IERC721Errors.ERC721NonexistentToken.selector) {
            return address(0);
        }
        assembly ("memory-safe") { revert(add(err, 0x20), mload(err)) }
    }
}
```

被两处使用，都是**鉴权**：

| 调用点 | 用途 |
| --- | --- |
| `GroupActionManager.groupOwnerOrRevert`（`L42`） | `onlyGroupOwner` 的判据；零 → `GroupNotExist` |
| `GroupServiceExecutor.onlyGroupOwner`（`L57`） | 同上；零 → `GroupNotExist` |

权限含义：**它把「NFT 不存在」与「NFT 存在但不是你」变成两个可区分的返回值（零 / 非零），从而使上层能把两个错误分开抛。** 若不吞 `ERC721NonexistentToken`，上层只能拿到一个泛化的 revert，无法区分「群 id 打错」与「用错钱包」——而 §5.5 要求「非授权方只拿到鉴权错误」，这条要求的前提是「存在性」可以被单独表达。

见 **SUP-01**。

### `GroupActionRoundAxis` / `LpRoundAxis` — 决定写入落在哪一轮

| 库 | 函数 | 公式 | 消费方 |
| --- | --- | --- | --- |
| `GroupActionRoundAxis` | `joinRound` | `phase < 2 ? 0 : phase - 1` | `GroupActionManager.currentJoinRound`、`GroupActionJoin`、`GroupActionExecutor._joinRound`、`GroupServiceExecutor._joinRound` |
| | `verifyRound` | `phase < 3 ? 0 : phase - 2` | `GroupActionVerify.currentVerifyRound` |
| | `mintRound` | `phase < 4 ? 0 : phase - 3` | `GroupActionExecutor._mintRound`、`GroupServiceExecutor._mintRound` |
| `LpRoundAxis` | `joinRound` | `phase < 2 ? 0 : phase - 1` | `LpExecutor._joinRound` |
| | `mintRound` | `phase < 3 ? 0 : phase - 2` | `LpExecutor._mintRound` |

两个库都**只做纯换算，不 import 错误接口**（规格明文要求）。未开始守卫在消费方：值为 0 时由 `ExecutorBase` 的 Round getter 或 `GroupActionManager.currentJoinRound` / `GroupActionVerify.currentVerifyRound` 抛 `RoundNotStarted(1, 0)`。

权限相关性：这些函数决定**每一次写操作落在哪个 `round` 键上**。因此它们间接定义了「能写哪一轮」这条边界：

- 加入类写入口只写 `currentJoinRound()`，因此不能写未来轮；
- 验证类写入口只写 `currentVerifyRound()`，因此不能写未到验证阶段的轮；
- 结算类写入口接受 `[createdRound, currentMintRound]` 的任意轮，因此**可以写历史轮**（这是唯一允许回写历史的入口族，且由 `memberMinted` 去重）。

这条边界不是鉴权（不判 `msg.sender`），但它是「一个地址能改哪些轮的状态」的另一半答案。见 **SUP-02**。

### `GroupActionStorage` / `GroupServiceStorage` — 状态与常量，零逻辑

两个库只声明 `Layout` 结构体、`Protocol` 结构体、常量与三个 `internal` 读函数：

| 成员 | 性质 |
| --- | --- |
| `GroupActionStorage.PRECISION` / `MAX_ORIGIN_SCORE` / `MAX_VERIFICATION_BATCH` / `MAX_DESCRIPTION_BYTES` / `MAX_VERIFICATION_ENTRIES` / `MAX_VERIFICATION_TEXT_BYTES` | 编译期常量，无 getter |
| `GroupActionStorage.memberAmountAt` | 唯一的共享读（`own + provider`），`GroupActionVerify` 与 Executor 各用一次 |
| `GroupServiceStorage.PRECISION` / `DEFAULT_MAX_RECIPIENTS` / `MAX_REMARK_BYTES` | 编译期常量 |
| `GroupServiceStorage.cachedDenominator` / `cacheDenominator` | 分母缓存的读写 |
| `GroupServiceStorage.groupReward` | 委托 `GroupActionExecutor.generatedActionRewardByGroupId` |

无鉴权、无 ABI、无外部调用（除 `groupReward` 的一次只读外呼）。见 **SUP-03**。

## 三、发现

### SUP-01（Info）`ownerOrZero` 只吞 `ERC721NonexistentToken`，其余一律原样 rethrow

- 证据：`L12-25`，catch 分支只识别一个 selector，其他错误用 `assembly` 原样抛出。
- 判定：这是正确的「窄 catch」。若改成宽泛 catch（吞掉全部），MemberNFT 的任何故障都会表现为「群不存在」，把故障变成静默的错误结论——正是 §5.2.2「固定依赖禁止宽泛 catch」要防的情形。
- 补充：`err.length >= 4` 的守卫是必要的（空 revert data 时 `bytes4(err)` 会越界读），且注释写明「casting to bytes4 is safe: the length check guarantees the first four bytes exist」。
- 建议：无。作为正面样本记录——这是全仓唯一一处 `try/catch` 外部调用，写法符合规范。

### SUP-02（Info）`GroupActionRoundAxis.joinRound` 与 `LpRoundAxis.joinRound` 是逐字节相同的两份

- 证据：两个函数体完全一致（`phase < 2 ? 0 : phase - 1`）。
- 规格口径：`02-phase-model.md` 明确要求「`phase → round` 换算只留在 `GroupActionRoundAxis`（join/verify/mint）与 `LpRoundAxis`（join/mint）两个纯换算库」。所以这是规格要求的分裂，不是重复代码事故——LP 是三阶段（无 verify），GroupAction 是四阶段，两条轴的语义不同，只是 `join` 恰好同式。
- 风险：若将来修改加入轮的偏移（例如把加入从 `phase - 1` 改为 `phase - 2`），必须同时改两处，而两处没有编译期关联。`GroupServiceExecutor._joinRound` 的注释已经点出这条风险：「this must stay equal to ActionTarget's own join round (phase - 1)… if the two drift, the reported round and the recorded snapshot disagree without any revert」——而 `ActionTarget._joinRound()` 是**第三处**同样的算式（`ActionTarget.sol:382-385`）。
- 建议：加一条测试断言「`ActionTarget._joinRound() == LpRoundAxis.joinRound(phase) == GroupActionRoundAxis.joinRound(phase)`」对若干 phase 成立，把这条隐式等式变成可执行的约束。

### SUP-03（正面结论）两个 Layout 库不含任何鉴权与 ABI 入口

- 证据：五个文件里 `function` 全部是 `internal`（`memberAmountAt`、`cachedDenominator`、`cacheDenominator`、`groupReward`、`ownerOrZero`、五个轴函数），没有一个 `external`/`public`。
- 判定：状态布局与常量不产生攻击面。所有写权限都落在业务库（`GroupActionJoin` / `GroupActionVerify` / `GroupActionManager` / `GroupRecipients`）与 Executor 上，本组文件只提供类型与算式。

### SUP-04（正面结论）`Load-bearing:` 注释覆盖了本组文件里全部「破坏后静默出错」的假设

- 证据：`GroupActionStorage` 五处（`L120-123` 位置化已验证推导、`L128-130` 群计数收敛、`L147-149` 按轮申请解析、`L171-172` 名册只追加）、`GroupServiceStorage` 一处（`L65-68` 分母缓存配对）、`MemberOwner` 一处（`L8-11` 零值语义）。
- 判定：§5.3 要求「承重不变式——被破坏时不回滚、而是给出静默错误结果所依赖的假设」必须就近标注。本组六处都符合：破坏后都不会 revert，而是给出错误的分数/分母/归属。这是全仓注释质量的正面样本。

## 四、核对证据

```text
$ grep -c "external\|public" action/src/{GroupActionStorage,GroupServiceStorage,GroupActionRoundAxis,LpRoundAxis,MemberOwner}.sol
（无匹配：五个文件均只有 internal 成员）

$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0
```

`Load-bearing:` 分布：

| 文件 | 行 | 约束的内容 |
| --- | --- | --- |
| `GroupActionStorage.sol` | 120 | 位置化「已验证」推导依赖「成员集合只在加入轮写入」 |
| `GroupActionStorage.sol` | 128 | 群计数收敛依赖「已完成的群不能再次提交」与「集合不含零成员群」 |
| `GroupActionStorage.sol` | 147 | 按轮申请解析必须走历史，不能读 `currentApplicationId` |
| `GroupActionStorage.sol` | 171 | 名册只追加、从不删除，故 `reverse` 即首次投票逆序 |
| `GroupServiceStorage.sol` | 65 | 分母缓存只能与同一份终态账本配对 |
| `MemberOwner.sol` | 8 | 缺失 id 必须返回零，否则代码检查与视图会静默错答 |

## 五、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被读 | Core `MemberNFT.ownerOf` | `MemberOwner.ownerOrZero` 的唯一外呼 |
| 被调 | `GroupActionExecutor.generatedActionRewardByGroupId` | `GroupServiceStorage.groupReward` 的唯一外呼 |
| 被用 | `GroupActionJoin` / `GroupActionVerify` / `GroupActionManager` / `GroupServiceExecutor` | Layout、Protocol、常量与轴函数 |
| 被用 | `ActionTarget` | 自带一份 `_joinRound()`（与两个轴库同式，见 SUP-02） |
