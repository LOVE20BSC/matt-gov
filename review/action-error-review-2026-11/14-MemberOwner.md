# `action/MemberOwner.sol` 错误赋值与发送专项 Review

> 基线：`action@916e146`（2026-11-05），行号按该提交。
> 判据：`matt-gov/docs/error-standards.md` §1 / §7；行为口径：`matt-gov/docs/specs/action/05-group-action-executor.md`（群身份解析）。
> 范围：`src/MemberOwner.sol`（26 行）。本文件只含 `ownerOrZero(address, uint256)` 一个 `internal view` 函数。

## 1. 结论

- **0 个错误声明 / 0 个 `revert <Error>(` 站点**：本库不声明领域错误。它只有一个失败出口——`assembly` 的**原样 rethrow**（`revert(add(err, 0x20), mload(err))`），以及把 `ERC721NonexistentToken` 归一为 `address(0)`。
- 这是全仓唯一用 `assembly` 抛出的位置。`check_errors.py` 的裸 `revert` 检查针对 `revert;` 与 `revert <Error>(`，不覆盖 `revert(offset, size)`，因此它既不进错误目录、也不被门禁拦下；**这正是它需要单独登记的原因**。
- 归一化的语义正确：只有 `err.length >= 4 && bytes4(err) == ERC721NonexistentToken.selector` 才返回 0，其余（含空 revert、短 revert、其它 selector）全部原样冒泡。
- 无 Medium / Low；2 条 Info（透传登记 + 归一化的条件边界）。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 0 |
| revert 站点 | 0（1 处原样 rethrow，不进错误目录） |
| 未声明 revert | 0 |
| 无站点声明 | 0 |
| Medium / Low / Info | 0 / 0 / 2 |

## 2. 错误清单

本文件无错误声明。失败出口只有一个，且不携带本模块的 selector：

| 出口 | 形态 | 触发条件 |
| --- | --- | --- |
| 归一为 `address(0)` | 不 revert | `ownerOf` 回 `ERC721NonexistentToken`（`err.length >= 4` 且 selector 匹配） |
| 原样 rethrow | `revert(add(err, 0x20), mload(err))` | 其余一切失败：空 revert（`err.length == 0`）、短 revert（`1..3` 字节）、其它 selector |

## 3. 逐错误明细

无 `revert <Error>(...)` 站点。两个出口的语义：

### 归一化出口 · 2 个消费方 · 保留

- 位置：`src/MemberOwner.sol:18-20`
- 判据：`err.length >= 4 && bytes4(err) == IERC721Errors.ERC721NonexistentToken.selector`
- 赋值：`return address(0);`
- 消费方：`GroupActionManager.groupOwnerOrRevert`（`06:42-46`，0 → `GroupNotExist(groupId)`）、`GroupServiceExecutor.onlyGroupOwner`（`13:57-60`，0 → `GroupNotExist(groupId)`）。
- 核对：两处都把 0 翻译成本地 `GroupNotExist`，没有把 `address(0)` 当成合法 owner 继续比地址；`// Load-bearing:` 注释（`:10-13`）登记了「若 `ownerOf` 对不存在的 id 返回非零 owner，代码检查会误判为真、视图会对不存在的群报活数据」。

### 原样 rethrow 出口 · 保留

- 位置：`src/MemberOwner.sol:21-23`
- 判据：`else` 分支（`ownerOf` 回滚且 selector 不是 `ERC721NonexistentToken`）
- 赋值：`revert(add(err, 0x20), mload(err))` — 逐字节转发原始 revert data
- 核对：符合 §7「非预期失败 rethrow，不映射成领域错误」；`err.length` 已在下标运算前用 `>= 4` 保护 `bytes4` 转换（`unsafe-typecast` 已用 lint 注释说明）。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 建议 |
| --- | --- | --- | --- | --- | --- |
| E-MO-01 | Info | `src/MemberOwner.sol:21-23` | 原样 rethrow 意味着 `GroupActionManager` / `GroupServiceExecutor` 的群操作**可能携带任意 revert data**（只要 `MemberNFT.ownerOf` 换成非标准实现或其后端出错）。§1 要求「每个模块用一张透传来源表登记可能透传的标准错误」，05/07 都没有登记这条「任意 data」通道；`check_errors.py` 也扫不到这种形态。 | error-standards §1 / §5（透传来源表）/ §7 | 在 05 的「实现约束」补一行：「群身份解析经 `MemberOwner.ownerOrZero`，`ERC721NonexistentToken` 归一为 `GroupNotExist`，其余失败原样冒泡（可能携带任意 revert data）」。 |
| E-MO-02 | Info | `src/MemberOwner.sol:18-20` | 归一化只认 selector、不认来源合约。若 `memberNFTAddress` 被配成一个「恰好也用 `ERC721NonexistentToken` 表达其它含义」的合约，该失败会被误判为「身份不存在」→ `GroupNotExist`，把一次依赖故障说成业务状态。 | error-standards §2（一个条件一个错误）/ §7 | 保持现状（依赖是部署期静态不变量，由 `DeployAction` / 21_check 校验）；建议在 05 注明该归一化假设「`ownerOf` 只对不存在的 id 抛该 selector」。 |

### 4.2 已核对项

- 无错误声明、无 `revert <Error>(`、无 `require`、无 `assert`；不 import 任何 `*Errors` 接口，只 import OZ 的 `IERC721Errors` 用于 selector 比较。
- `err.length >= 4` 在 `bytes4(err)` 之前判定，短 revert 不会被截断成错误 selector；`test/MemberOwner.t.sol:66` 的 `testOwnerOrZeroRethrowsShortFailure` 覆盖该分支。
- 空 revert（`err.length == 0`）走 rethrow 分支，`mload(err) == 0` 时 `revert(add(err,0x20), 0)` 等价于无数据回滚；`test/MemberOwner.t.sol:60` 的 `testOwnerOrZeroRethrowsEmptyFailure` 覆盖。
- 非预期失败（自定义 selector）原样冒泡，`test/MemberOwner.t.sol:54` 的 `testOwnerOrZeroRethrowsUnexpectedFailure` 覆盖。
- 归一化路径 `test/MemberOwner.t.sol:49` 的 `testOwnerOrZeroMapsNonexistentToken` 覆盖。
- 两个消费方的判定顺序一致：先「owner == 0 → `GroupNotExist`」，再「owner != msg.sender → `NotGroupOwner`」，符合 §5「身份解析属于鉴权」。

### 4.3 透传错误面

| 通道 | 来源 | 说明 |
| --- | --- | --- |
| 任意 revert data | `IMemberNFT.ownerOf` | 原样 rethrow；不是本模块的 selector，不进 `IGroupActionManagerErrors` / `IGroupServiceExecutorErrors` |
| `ERC721NonexistentToken` | `IMemberNFT.ownerOf` | 被本库**吞掉**并归一为 `GroupNotExist`，不向外透传 |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd action
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
forge test --match-contract MemberOwnerLookupTest -vv
```

> 扫描口径：`revert(offset, size)` 不匹配 `revert <Error>(`，故本文件的 rethrow 不进错误目录；它在错误标准里属于 §7 的「非预期失败 rethrow」，由透传来源表登记。


## 处置（W1 窗口，2026-11-05）

| 编号 | 级别 | 落点 |
| --- | --- | --- |
| E-MO-01 | Info | 已裁决（X-06 登记）：05 补透传面：`MemberOwner` 对 `ownerOf` 原样 rethrow，群操作可携带任意 revert data。 |
| E-MO-02 | Info | 已裁决（X-09 文档）：05 登记归一化只认 selector、不认来源合约的风险。 |
