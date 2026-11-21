# 空投铸造

> 早期技术草稿，保留条款编号供追溯。现行开发规格见[首批代币空投分发](../core/10-airdrop-distributor.md)。

`AirdropDistributor` 接收首批代币，按 Merkle 快照向各钱包分配对应的空投份额。同一分发器可为首币及其他已接入的社区代币分别维护空投。

<a id="AD-01"></a>

## AD-01 配置来源

**级别**：必须

**入口**：构造函数（首币）、`onTokenLaunched(tokenAddress, …, launcherMemberId, distributorData)`

- 首币在构造期完成配置，`launcherMemberId` 为 `0`，并按 [AD-07](#AD-07) 写入快照 URI。
- 子币由 `Launch` 在创建、首批供应到账、登记与次数扣减之后回调一次。`onTokenLaunched` 仅 `LAUNCH_ADDRESS` 可调用。
- `distributorData` 必须只有一个 64 字节的元素，解码为 `(bytes32 merkleRoot, uint256 claimDelayRounds)`。
- 每个 `tokenAddress` 只能配置一次。

**失败**：`NotLaunchContract`、`InvalidDistributorDataCount`、`InvalidDistributorDataLength`、`TokenAlreadyConfigured`、`ZeroMerkleRoot`、`ClaimDelayRoundsExceeded`。

<a id="AD-02"></a>

## AD-02 可铸造轮次

**级别**：必须

```text
baseRound = currentPhase() == 0 ? 1 : currentPhase()
claimableFromRound = baseRound + claimDelayRounds
```

等待阶段数 `claimDelayRounds` 的范围为 `0` 到 `1000`，按[协议阶段](02-time.md#TM-01)计。等待 `0` 时，从配置所在阶段开始可铸造。创世前配置时，最早从阶段 1 开始。`claimableFromRound` 在配置时确定，阶段校准后仍保持原值。

<a id="AD-03"></a>

## AD-03 份额与分母

**级别**：必须

`TOTAL_SHARE` 固定为 `10^18`。完整快照中各钱包的正份额之和必须精确等于这个值。

链下生成器负责校验份额总和并补足取整尾差。合约只校验提交钱包的份额与 Merkle 证明。

<a id="AD-04"></a>

## AD-04 铸造金额

**级别**：必须

```text
remainingShare = TOTAL_SHARE - totalClaimedShare
amount = floor(balanceOf(this) * share / remainingShare)
```

`balanceOf(this)` 取交易执行时的池余额。按完整乘积除以剩余份额后向下取整。钱包份额等于剩余份额时，钱包取得池中全部余额。

例如池中有 101 个最小单位，钱包持有总份额的 40%，此前无人铸造。交易应转出 40 个最小单位，池中剩 61 个最小单位，剩余份额为总份额的 60%。

`claimableAmount` 是读取时的预估。返回 `0` 也可能表示尚未到轮次、已经铸造或资格校验未通过。实际金额见 [AD-06](#AD-06)。

<a id="AD-05"></a>

## AD-05 claim 的失败顺序

**级别**：必须

**入口**：`claim(address tokenAddress, uint256 share, bytes32[] proof)`

失败判定按下列顺序执行，先命中的先回滚，顺序属于公开契约：

| 步 | 条件 | 错误 |
| --- | --- | --- |
| 1 | `merkleRoot == 0`（该代币未配置） | `TokenNotConfigured(tokenAddress)` |
| 2 | `currentPhase() < claimableFromRound` | `ClaimRoundNotReached(tokenAddress, currentRound, claimableFromRound)` |
| 3 | 该地址已铸造过 | `AirdropAlreadyClaimed(tokenAddress, claimer)` |
| 4 | `share == 0` | `InvalidProof()` |
| 5 | `share > remainingShare` | `ShareExceedsRemaining(share, remainingShare)` |
| 6 | Merkle 证明校验失败 | `InvalidProof()` |
| 7 | 代币转账失败 | 整笔回滚。转账返回 `false` 等被 `SafeERC20` 判为失败的返回结果时，抛出 `SafeERC20FailedOperation(tokenAddress)`。代币的 `transfer` 自行回滚时，原样传递回滚数据。 |

例如空投在阶段 4 配置并等待 1 个阶段。有资格的钱包在阶段 4 调用 `claim` 会以 `ClaimRoundNotReached` 回滚。在阶段 5，该钱包满足其他校验时可成功铸造。

<a id="AD-06"></a>

## AD-06 只付给调用者

**级别**：必须

`claim` 用调用钱包的地址和份额核验快照证明，从空投池把已有代币转给该钱包。每个钱包对同一代币只能成功铸造一次。

成功后记录铸造状态和实际金额，累计已使用的份额与已转出的金额。`AirdropClaimed.amount` 与 `claimedAmount` 返回的值一致。事件的 `remainingShare` 是这笔交易扣除份额后的余量，最后一份用完时为 `0`。

<a id="AD-07"></a>

## AD-07 快照 URI

**级别**：必须

`snapshotUri` 用于发现完整快照文件。空投校验使用 [AD-05](#AD-05) 所列条件。

- 写入时长度必须在 `1` 到 `256` 字节之间。
- 首币在构造期写入并固定。
- 子币的 URI 初始为空，由 `launcherMemberId` 对应身份的当前持有人更新。
- 更新发出 `AirdropSnapshotUriUpdated`，携带新值与旧值。

使用方应比对文件声明的 Merkle 根与链上配置，再校验钱包对应的证明。

<a id="AD-08"></a>

## AD-08 单笔空投范围

每次 `claim` 处理一个代币，成功时一次用完该钱包在这份快照中的份额。

## 不承诺事项

- 快照的来源链、取样区块以及链下如何选择地址和分配份额。份额总量仍须符合 [AD-03](#AD-03)。
- 读取时的预估金额在交易执行时保持相同。
- 空投截止时间或剩余池余额的取回入口。
- 调用的 Gas 消耗以及代币合约自身回滚数据的格式。错误传递遵守 [AD-05](#AD-05)。

## 验收

| 条款 | 测试 |
| --- | --- |
| AD-01、AD-02 | `core/test/AirdropDistributor.t.sol` |
| AD-03、AD-04 | `core/test/AirdropDistributorEdgeCases.t.sol` |
| AD-05、AD-06、AD-08 | `core/test/AirdropDistributor.t.sol`、`core/test/AirdropDistributorEdgeCases.t.sol` |
| AD-07 | `core/test/AirdropDistributor.t.sol`、`core/test/AirdropDistributorEvents.t.sol` |
