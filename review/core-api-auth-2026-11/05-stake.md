# Stake 接口调用权限审查

> 对象 `core/src/Stake.sol`（911 行）
> 接口 `core/src/interfaces/IStake.sol`（245 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/04-stake.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 31（写 7 / 读 24） |
| 带鉴权 modifier | 5（`onlyMemberOwner`） |
| 无许可写入口 | 2（`init`、`settleFees`） |
| 发现 | 3 条：Low 1 / Info 2，另有 3 条正面结论 |
| 接口对账 | 31 vs 31，**0 差异** |

一句话：**托管全仓全部资产的合约，权限面却最规整——5 个成员入口全部 `onlyMemberOwner` 且为首道判定，`settleFees` 是规格明示的无许可入口且只能「按时结算、不能加速、不能转移」。唯一的实质问题是 `withdraw` 的 `delete _memberStake` 落在两次外部调用之后，安全性依赖「登记代币无回调」这一外部前提。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 成员 NFT 持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `stakeLiquidity`、`stakeBoost`、`unstake`、`withdraw`、`mergeStake`（源） |
| 任何地址 | 无；只受「每社区每 Phase 一次 + 达到阈值」约束 | `settleFees` |
| 无 | `if (initialized) revert` | `init` |
| 无 | — | 24 个只读入口 |

`01-common-rules.md` 的两条规则在本合约的落点：

- **处分成员资产/权益 → 校验 `ownerOf`**：`stakeLiquidity`（拉取代币）、`stakeBoost`（拉取代币）、`unstake`（清零票权与加速）、`withdraw`（转出 LP/双币/boost）、`mergeStake`（搬移全部质押）。
- **单向融合只验源**：`mergeStake` 的 `targetMemberId` 只做 `ownerOf` 存在性检查（`L287`），不要求调用者持有目标。

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `init(9 参数)` | 无（一次性） | `if (initialized) revert` | 是 | **无** |
| `settleFees(address)` | 任何地址 | 无 | — | `FeesSettled`（实际结算时）、`FeeReclassified`（重分类时） |
| `stakeLiquidity(address,uint256,uint256,uint256,uint256,uint256)` | `memberId` 持有人 | `onlyMemberOwner(memberId)` `L105` | 是 | `LiquidityStaked`（+`FeeReclassified`） |
| `stakeBoost(address,uint256,uint256,uint256)` | `memberId` 持有人 | 同上 | 是 | `BoostStaked` |
| `unstake(address,uint256)` | `memberId` 持有人 | 同上 | 是 | `Unstaked` |
| `withdraw(address,uint256)` | `memberId` 持有人 | 同上 | 是 | `StakeWithdrawn`（+`FeesSettled`） |
| `mergeStake(address,uint256,uint256)` | `sourceMemberId` 持有人 | `onlyMemberOwner(sourceMemberId)` | 是 | `StakesMerged` |

### 只读入口（24）

配置 getter 10：`initialized`、`PHASE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`VOTE_ADDRESS`、`LAUNCH_ADDRESS`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS`、`PROMISED_WAITING_PHASES_MIN`、`PROMISED_WAITING_PHASES_MAX`、`FEE_SETTLEMENT_RATIO`。

查询 14：`pairAddress`、`totalBurnedToken`、`totalParentTokenBurned`、`validGovVotes`、`totalValidGovVotes`、`totalValidGovVotesAdded`、`totalValidGovVotesRemoved`、`memberStake`、`totalStake`、`canWithdraw`、`validBoostShares`、`totalValidBoostShares`、`totalValidBoostSharesAdded`、`totalValidBoostSharesRemoved`。

读面边界：`validGovVotes` / `validBoostShares` / `totalValid*` 系列对未开始的 round 回滚 `RoundNotStarted(requestedRound, currentRound)`（`_checkRoundStarted`）；`memberStake` 与 `totalStake` 会在读时按当前 Pair 储备做一次 `_previewReclassification`（纯 view，不写状态）。

## 四、逐入口判定

### `init` — 绑定六个依赖与三个参数

固定 `PHASE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`VOTE_ADDRESS`、`LAUNCH_ADDRESS`、`ROUTER_ADDRESS`、`PAIR_FACTORY_ADDRESS`、`PROMISED_WAITING_PHASES_MIN/MAX`、`FEE_SETTLEMENT_RATIO`。无调用者限制、无代码校验，与 §5.7 的分工一致（依赖代码由部署脚本校验）。

权限后果按严重度排序：

1. `MEMBER_NFT_ADDRESS` 错绑 ⇒ 5 个成员入口的鉴权根被替换；
2. `ROUTER_ADDRESS` 错绑/恶意 ⇒ `_swapParentTokenForToken` 会把父币 `forceApprove` 给它并调用 `swapExactTokensForTokens`，即**合约对 Router 无限授权**；
3. `FEE_SETTLEMENT_RATIO` 错设 ⇒ 单笔结算单位失真（规格要求 `<=` 池费率，由 `DeployCore` 广播前校验）；
4. `PROMISED_WAITING_PHASES_MIN/MAX` 错设 ⇒ 解锁等待期区间失真。

部署脚本 `DeployCore.s.sol:253` 调用、`L383-384` 核对 `PHASE_ADDRESS`/`MEMBER_NFT_ADDRESS`；`21_check.sh` 独立复核。

### `settleFees` — 无许可，但只能「按时、按阈值、单向销毁」

- 任何地址可调，符合 `04-stake.md`「任何人可调用 `settleFees(tokenAddress)` 单独结算手续费」。
- 四道闸门共同限制权限后果：
  1. `_checkToken`：只接受 Launch 已登记代币；
  2. `feeLp >= settlementUnit`（`floor(pairTotalSupply × FEE_SETTLEMENT_RATIO / 1e18)`）：未达阈值直接返回，不写状态；
  3. `_lastSettlePhase[token] != round`：每社区每 Phase 最多一次；
  4. `_canBurn`：LP 太小、两侧任一储备取整为零时跳过，避免 `pair.burn` 回滚。
- 触发后只做「把 LP 送进 Pair → `burn` → 把父币换成代币 → `burn` 代币」，三种资产都流向销毁或 Pair，**没有一条路径把资产转给调用者**。因此无许可不构成提取面。
- 反向限制：任何人都**不能加速**结算（每 Phase 一次已是最快），也不能跳过阈值。这使 `settleFees` 成为「只能推进已到期流程」的无许可入口，与 `Phase.sync` 同类。

### `stakeLiquidity` / `stakeBoost` — 拉取自己的资产

- 两者都先用 `onlyMemberOwner` 判身份，再判金额/等待期/代币登记/无解锁申请/等待期不下降。
- `_pull` 从 `msg.sender` 划转（不是从 `memberId` 的 owner——两者相同，因为鉴权已保证），因此不存在「用 A 的授权拉 B 的币」。
- `stakeBoost` 额外要求已有 `liquidityShares`（`_checkStakedLiquidity`），即「先有流动性质押才能加加速质押」。
- `stakeBoost` 允许在同一笔内提升 `promisedWaitingPhases` 并按差额补记票权（`L159-164`）；只允许升不允许降（`PromisedWaitingPhasesDecreased`）。

### `unstake` — 只锁「本轮已用票权」的成员

- 校验：无解锁申请 → 有质押 → **本轮未投票且未推举**（`_hasUsedStakeRights`）。
- `_hasUsedStakeRights` 读两处：`Vote.voteAmountByMemberId` 与 `Submit.proposalIdBySubmitterId`（后者经 `Vote.SUBMIT_ADDRESS()` 取得地址）。这是一条**跨合约信任链**：`VOTE_ADDRESS`（本合约 init 固定）→ `Vote.SUBMIT_ADDRESS()`（Vote init 固定）→ Submit。
- 语义：已经用本轮票权影响过治理的成员，不能在同一轮撤出质押；下一轮可以。
- 清零两类历史：`_validGovVotesByMember` 减 `govVotes`、`_validBoostSharesByMember` 减 `boostShares`；`unlockRequestPhase` 记为当前轮。资产不动。

### `withdraw` — 等待期到后一次性清空

- 四道校验：已申请解锁 → 有质押 → `round > unlockRequestPhase + promisedWaitingPhases` → 计算 LP。
- 顺序（`L244-276`）：`_withdrawLiquidity`（内含 `_settleFees`、`pair.burn`/`_push(pair, msg.sender, lp)`）→ `_push(boostShares)` → `delete _memberStake` → 发事件。
- 权限面正确：`msg.sender` 是当前持有人，资产与 boost 都退给 `msg.sender`；`delete` 后同一 `memberId` 的质押归零。
- **CEI 的字面例外**：`delete` 在两次外部调用之后（见 STK-01）。

### `mergeStake` — 单向融合，目标不可拒绝

- 只校验源所有权；目标做存在性检查。
- 保护目标：`target` 非空且 `target.promisedWaitingPhases < source.promisedWaitingPhases` 时回滚 `TargetPromisedWaitingPhasesTooShort`（`L544-548`）——**不会降低**目标的等待期承诺。
- 源被 `delete`（`_mergeIntoTarget` 末尾），不可撤回；源的票权记减、目标记增；boost 历史按源→目标搬移。
- 判定：符合「单向融合只增加目标状态」。副作用是「可以把全部质押送给任意存在的 `memberId` 且不可撤回」，但这需要源持有人主动签名，属自担风险。

## 五、发现

### STK-01（Low）`withdraw` 的 `delete _memberStake` 在两次外部调用之后，安全性依赖「登记代币无回调」

- 证据（`L244-258`）：

```solidity
// L244-249：外部调用 pair.burn / ERC20.transfer
(tokenAmountForLiquidity, parentTokenAmountForLiquidity,
 withdrawableLpBurned, withdrawableLpToMember) = _withdrawLiquidity(tokenAddress, pair, round, liquidityShares);
// L253-256：外部调用 ERC20.transfer
if (boostShares > 0) { _push(tokenAddress, msg.sender, boostShares); }
// L258：清理在两次外部调用之后
delete _memberStake[tokenAddress][memberId];
```

- 后果：在 `pair.burn` 与 boost 转账期间，该 `memberId` 的 `liquidityShares`、`unlockRequestPhase` 仍是旧值。账本 `lastWithdrawableLp` / `totalLiquidityShares` 已在 `_withdrawLiquidity` 内先行扣减，所以重入的第二次 `withdraw` 会按「已扣减后的剩余」再算一次 `lpAmount = liquidityShares × lastWithdrawableLp / totalLiquidityShares`，仍可能再转出一份 LP；随后第二次 `delete` 无效。
- 为什么当前不可利用：`tokenAddress` 必须是 Launch 登记的标准 `LOVE20Token`（`_checkToken`），`pair` 是标准 UniswapV2Pair，两者的转账/`burn` 都不触发接收者回调。`msg.sender` 即使是恶意合约，也收不到回调。
- 为什么仍要记录：这条安全边界是**外部前提**而非合约内保证。规格 `04-stake.md` 明说「`Stake` 是这条规则的有意例外：它不设重入锁，改以先完成全部校验、再发起外部调用、并以外部调用实际返回的数量记账保证一致」——但 `delete` 并不在这个顺序里。若未来允许带回调的代币（ERC777/ERC721）或替换 Pair 实现，这条路径立即变成可重复提取。
- 建议：把 `delete _memberStake[tokenAddress][memberId]` 前移到 `_withdrawLiquidity` 之前。三个需要后用的值（`promisedWaitingPhases`、`liquidityShares`、`boostShares`）已在 `L237-239` 读入 memory，`_withdrawLiquidity` 只读 `_totalStake`，不读 `_memberStake`，前移不改任何计算结果。若不愿改代码，至少应在 `04-stake.md` 写明「不设锁的前提是登记代币与 Pair 均无接收回调」。

### STK-02（Info）`stakeBoost` 未显式拒绝 Round 0

- 证据：`stakeLiquidity` 有 `_checkActiveRound()`（`L123`）→ Round 0 回滚 `NotAllowedToStakeAtRoundZero()`；`stakeBoost` 没有，只取 `_currentRound()`（`L152`）。
- 为何不可达：Round 0 时任何地址的 `liquidityShares` 都是 0（`stakeLiquidity` 在 Round 0 revert），`_checkStakedLiquidity` 会先回滚 `NoStakedLiquidity`。因此 `stakeBoost` 在 Round 0 事实上不可用。
- 判定：不构成缺陷，但这是「靠间接条件不可达」而非显式拒绝。建议在 `04-stake.md` 的 Round 0 边界里补一句，或给 `stakeBoost` 加同一个 `_checkActiveRound()`（成本一次 `currentPhase()` 读取，与 `stakeLiquidity` 一致）。

### STK-03（Info）`_hasUsedStakeRights` 的信任链经过 `Vote.SUBMIT_ADDRESS()`

- 证据：`L510-511`：`IVote(VOTE_ADDRESS).voteAmountByMemberId(...)` 与 `ISubmit(IVote(VOTE_ADDRESS).SUBMIT_ADDRESS()).proposalIdBySubmitterId(...)`。
- 影响：Vote 未初始化时 `SUBMIT_ADDRESS == 0`，对零地址调用带返回值的函数会 revert（空 revert data），`unstake`/`mergeStake` 因此不可用。部署脚本保证 `Vote.init`（`DeployCore.s.sol:271`）在运行期之前完成，`21_check` 复核 `vote.SUBMIT_ADDRESS`。
- 判定：不构成缺陷；记录为「本合约的运行期可用性依赖 Vote 的初始化」，与 `Mint.init` 读 `Vote.PHASE_ADDRESS()` 是同一类隐式顺序依赖（见 08-mint.md 的 MNT-05）。

### STK-04（正面结论）5 个成员入口的鉴权全部是首道判定，且有「先鉴权后参数」的负例钉死

- 证据：`test/Stake.t.sol:1823-1843` 四例分别断言 `stakeLiquidity`、`stakeBoost`、`unstake`、`withdraw` 在金额/代币非法时仍先报 `NotMemberOwner`；`test/Stake.t.sol:1553-1556` 覆盖 `mergeStake` 的非源持有人。
- 判定：§5.5「非授权方只拿到鉴权错误」在本合约被完整覆盖，不留「用参数错误探测状态」的通道。

### STK-05（正面结论）`settleFees` 的四个闸门使无许可不产生提取面

- 证据：`_settleFees`（`L816-835`）与 `_realizeFees`（`L845-885`）。
- 判定：调用者既不能指定收款地址（没有 recipient 参数），也不能指定金额（结算单位由 Pair 供应量与 `FEE_SETTLEMENT_RATIO` 决定），资产只流向 Pair 与销毁。这是「无许可入口不给调用者任何自由度」的正面样本。

### STK-06（正面结论）`_realizeFees` 在外部调用前写入 `_lastSettlePhase`，堵住 Router 重入

- 证据：`_lastSettlePhase[tokenAddress] = round;`（`L851`）位于 `_push(pair, …)`、`_burnLp`、`_swapParentTokenForToken` 之前；重入的 `_settleFees` 会在 `L827` 因 `_lastSettlePhase == round` 直接返回。
- 判定：即使 `ROUTER_ADDRESS` 是恶意合约，同一 Phase 内也无法通过重入重复结算。这是「无锁但幂等闸在前」的正确写法。

## 六、核对证据

```text
$ forge inspect Stake abi --json               # 31 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 非持有人 `stakeLiquidity` | `test/Stake.t.sol:1103-1106` |
| 非源持有人 `mergeStake` | `test/Stake.t.sol:1553-1556` |
| 鉴权先于金额（`stakeLiquidity`） | `test/Stake.t.sol:1823-1825` |
| 鉴权先于金额（`stakeBoost`） | `test/Stake.t.sol:1829-1831` |
| 鉴权先于代币校验（`unstake`） | `test/Stake.t.sol:1835-1837` |
| 鉴权先于代币校验（`withdraw`） | `test/Stake.t.sol:1841-1843` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 读 | `Phase.currentPhase` | 轮次唯一来源 |
| 读 | `MemberNFT.ownerOf` | 5 个入口的鉴权函数 |
| 读 | `Launch.isLOVE20Token` | 代币登记闸门（`_checkToken`） |
| 读 | `Vote.voteAmountByMemberId` / `Vote.SUBMIT_ADDRESS` | `_hasUsedStakeRights` |
| 读 | `ILOVE20Token.PARENT_TOKEN_ADDRESS` | Pair 定位 |
| 写 | `LOVE20Token.burn` | 手续费销毁 |
| 写 | `IUniswapV2Factory.getPair`（首次缓存）、`IUniswapV2Pair.mint/burn`、`IUniswapV2Router02.swapExactTokensForTokens` | 资产出口；Router 获得一次性 `forceApprove` 的父币授权 |
| 写 | `Vote` / `Submit` 的只读调用 | 不写对方状态 |
