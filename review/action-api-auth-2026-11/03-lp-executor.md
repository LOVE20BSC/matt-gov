# LpExecutor 接口调用权限审查

> 对象 `action/src/LpExecutor.sol`（533 行）+ 继承的 `action/src/ExecutorBase.sol`（140 行）
> 接口 `action/src/interfaces/ILpExecutor.sol`（109 行，`is IActionExecutor`）
> 基线 `action@e849e36`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.4（退出顺序）、§4.2；`specs/action/04-lp-executor.md`、`specs/action/07-minting.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 25（写 8 / 读 17） |
| 鉴权 modifier | 3（`onlyMemberOwner`、`onlyActionTarget`、`nonReentrant`） |
| 无许可写入口 | 0 |
| 发现 | 4 条 Info；另有 2 条正面结论 |
| 接口对账 | 25 vs 25，**0 差异** |

一句话：**三个成员入口（`join`/`withdraw`/`exit`）与两个结算入口全部 `nonReentrant` + `onlyMemberOwner`，且鉴权先于参数有负例钉死；三个回调只认 ActionTarget。没有越权面。唯一值得登记的是「行动归属本 Executor」这条判定不是显式写的，而是由 `registerJoinState` 与零地址转账回滚间接兜住的。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| `memberId` 当前持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `join`、`withdraw`、`exit`、`mintMemberReward`、`mintMemberRewards` |
| ActionTarget | `msg.sender == ACTION_TARGET_ADDRESS` | `onProposalCreated`、`onProposalSubmitted`、`onProposalVoted` |
| 无 | — | 17 个只读入口 |

本合约不持有任何「管理员」角色：没有 owner、没有 pause、没有参数 setter。行动的三项配置（`joinTokenAddress`、`govRatioMultiplier`、`minGovRatio`）只在创建回调里写一次，此后再无写入口——`govRatioMultiplier` 与 `minGovRatio` 甚至连 setter 都没有。

## 三、入口清单

### 写入口（8）

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `join(address,uint256,uint256,uint256)` | `memberId` 持有人 | `nonReentrant onlyMemberOwner` `L144-149` | 是 | `LpJoined` |
| `withdraw(address,uint256,uint256,uint256)` | `memberId` 持有人 | 同上 `L193-198` | 是 | `LpWithdrawn`（全额另发 `LpExited`） |
| `exit(address,uint256,uint256)` | `memberId` 持有人 | 同上 `L238-241` | 是 | `LpWithdrawn` + `LpExited` |
| `mintMemberReward(address,uint256,uint256,uint256)` | `memberId` 持有人 | `ExecutorBase:51` | 是 | `MemberRewardMinted` |
| `mintMemberRewards(address,uint256[],uint256[],uint256)` | `memberId` 持有人 | `ExecutorBase:60` | 是 | 逐条 `MemberRewardMinted` |
| `onProposalCreated(address,uint256,bytes[])` | ActionTarget | `onlyActionTarget` `L89-93` | 是 | `LpActionCreated` |
| `onProposalSubmitted(address,uint256,uint256,bytes[])` | ActionTarget | `ExecutorBase:43`（空实现） | 是 | 无 |
| `onProposalVoted(address,uint256,uint256,uint256,uint256,bytes[])` | ActionTarget | `onlyActionTarget` `L132-137` | 是 | 无（只校验项数） |

### 只读入口（17）

依赖 getter 5：`ACTION_TARGET_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`PAIR_FACTORY_ADDRESS`。

行动配置 3：`joinTokenAddress`、`govRatioMultiplier`、`minGovRatio`。

Round 3：`currentVoteRound`、`currentJoinRound`、`currentMintRound`。

参与量与扣减 5：`joinedAmountByActionId`、`joinedAmountByMemberId`、`deduction`、`deductionByRound`、`govRatio`。

结算 2：`memberReward`、`govRatio`（含 `minted` 标志）。

读面边界：`joinedAmountByActionId` / `joinedAmountByMemberId` 对 `round > _joinRound()` 返回 0 不回滚（`L394`、`L406`）；`memberReward` 对未创建/超窗口的轮次返回 `(0,0,false)`（`L388`）；`govRatio` 已铸造时返回冻结值、未铸造时按当前 Phase 现算（`L366-371`）。三者都不回滚。

## 四、逐入口判定

### `join` — 拉取自己的 LP

顺序（`L144-190`）：鉴权 → `amount != 0` → `currentJoinRound()`（未开始则 `RoundNotStarted`）→ 首次加入判定 → `minGovRatio` 门槛 → 时间扣减落账 → 五处账本写入 → 首次加入时 `registerJoinState` → `safeTransferFrom(msg.sender, this, amount)` → `LpJoined`。

三处值得记录的权限性质：

1. **付款方固定是 `msg.sender`**（`L181`），不是 `memberId` 的持有人——两者相同，因为鉴权已保证。因此不存在「用 A 的 ERC20 授权拉 B 的币」。
2. **首次加入才判 `minGovRatio`**（`L157-163`）。追加不重复判，符合规格「首次加入满足 `minGovRatio`」。
3. **`registerJoinState` 兼作「这个行动属于本 Executor」的校验**（见 LP-03）。

`join` 没有金额上限：规格未设，`maxJoinAmountRatio` 只存在于 GroupAction 侧。LP 的准入只由 `minGovRatio` 与 Pair 登记决定。

### `withdraw` — 部分或全额，全额即退出

顺序（`L193-235`）：鉴权 → `amount != 0` → `amount <= joinedAmount` → 全额分支走 `_clearJoinState`，部分分支按比例减扣减 → `safeTransfer` → `LpWithdrawn` → 全额时 `clearJoinState` + `LpExited`。

- 全额撤回与 `exit` 走同一条清仓路径，事件也按事实拆成两条（`LpWithdrawn` 记金额、`LpExited` 记生命周期），符合 `04-lp-executor.md` 的固定顺序：清自身状态 → 退款转账 → `LpWithdrawn` → `clearJoinState` → `LpExited`。
- 部分撤回只发 `LpWithdrawn`，不改加入态——这是「撤回不改变加入状态」的落点，也是 ActionTarget 不发 `*Withdrawn` 的原因。

### `exit` — 全部结清

顺序（`L238-263`）与 `withdraw` 的全额分支一致，唯一差异是 `memberJoinedAmount == 0` 时回滚 `NotJoined` 而不是 `WithdrawAmountExceeded`。

### `mintMemberReward` / `mintMemberRewards`

实现在 `_mintMemberReward`（`L480-532`）：`_checkMintWindow` → 读有效参与总量 → 必要时 `ActionTarget.mintActionReward` → `_calculateReward` → 零额则 `MemberActionRewardUnavailable` → 置位 → `burn` + `transfer(msg.sender)` → 事件。

- **收款方固定是 `msg.sender`**（`L521`），与鉴权主体一致。
- 结算的 `round` 允许是历史轮（`1 <= round <= currentMintRound`），但必须 `>= createdRound`——两个边界都由 `_checkMintWindow` 给。
- 同一 `(actionId, round, memberId)` 只能结算一次（`_memberMinted`），重复由 `_checkMintWindow` 的 `alreadyMinted` 参数拒绝。

### 三个回调

| 回调 | 校验 | 权限后果 |
| --- | --- | --- |
| `onProposalCreated` | 项数恰 4 → 每项 32 字节 → `joinTokenAddress != 0` → Pair 登记 → `minGovRatio <= 1e18` | 写入三项配置 + `createdRound`，此后不可改 |
| `onProposalVoted` | `targetData.length <= 1` | 无状态写入（LP 无验证阶段，投票不带业务项） |
| `onProposalSubmitted` | 仅 `onlyActionTarget` | 无状态写入 |

## 五、发现

### LP-01（Info）未创建行动的 `join` 报 ActionTarget 的 `UnauthorizedExecutor`，不是 `ActionNotCreated`

- 证据：`join` 没有 `createdRound != 0` 的前置判定；对未创建行动，`_joinTokenAddressByActionId` 为 0，函数一路走到 `registerJoinState`（`L178`），由 ActionTarget 的 `onlyBoundExecutor` 回滚 `UnauthorizedExecutor(tokenAddress, actionId)`。
- 与规格的偏差：`04-lp-executor.md` 的错误表把「行动未创建（`createdRound == 0`）→ `ActionNotCreated(tokenAddress, actionId)`」列在 LP 名下，但 LP 只在结算路径（`_checkMintWindow`）产生该错误，`join` 路径不产生。
- 后果：链下若按 `ActionNotCreated` 分类「行动不存在」，`join` 的失败会被归到「调用者无权限」，两者含义完全不同。
- 建议：二选一——要么在 `join` 入口加 `createdRound != 0` 判定（一次 SLOAD，与 GroupAction 的 `activateGroup` 同型），要么在规格错误表里给该行加「仅结算路径」的限定。

### LP-02（Info）退出路径强依赖 `ActionTarget.clearJoinState` 成功，而后者内部读 `Phase.currentPhase()`

- 证据：`withdraw` 的全额分支（`L227`）与 `exit`（`L255`）都在退款之后调用 `IActionTarget.clearJoinState`；ActionTarget 侧该函数调用 `_joinRound()` → `IPhase(PHASE_ADDRESS).currentPhase()`（`ActionTarget.sol:382-385`）。
- 后果：`Phase` 或 `ActionTarget` 不可用时，LP 的**全部资产出口**（`withdraw` 全额、`exit`）同时被阻断——退款在同一笔里，回滚会一起撤销。资产不会丢，但会锁。
- 为什么不是缺陷：加入态的唯一所有者是 ActionTarget（`00-components.md` 明文），退出必须清注册表，这个依赖是设计的一部分。记录它是因为这是本合约唯一一条「外部合约可用性决定资金可取出性」的路径，与 core 审查的 STK-03（`unstake` 依赖 `Vote.SUBMIT_ADDRESS()`）同型。
- 建议：在 `04-lp-executor.md` 的「部分撤回与退出」段落补一句该依赖，便于运维在 Phase 故障时优先恢复 Phase 而不是排查 LP。

### LP-03（Info）「行动属于本 Executor」没有显式判定，靠 `registerJoinState` 与零地址转账回滚间接兜住

- 证据：`join` 全程不校验 `_joinTokenAddressByActionId[tokenAddress][actionId] != 0`，也不校验该行动是否由本 Executor 创建。实际防线有两层：
  1. **首次加入**：`registerJoinState` 由 ActionTarget 判 `_executorByActionId == msg.sender`，行动不属于本 Executor 时回滚 `UnauthorizedExecutor`（`L178`）。
  2. **非首次加入**：跳过 `registerJoinState`（`L177`），直接走到 `safeTransferFrom(_joinTokenAddressByActionId[...] == address(0))` → SafeERC20 对无代码地址回滚（`L181`）。
- 为什么当前成立：`isJoined` 为真 ⟹ 某次 `registerJoinState` 成功 ⟹ 调用者是该行动绑定的 Executor；绑定在创建时固定、`AlreadyCreated` 拒绝重绑。因此「`isJoined` 为真」蕴含「是本 Executor 注册的」。
- 为什么仍要记录：这条安全性是**推理结论**而非合约内断言。任何一处改动都会让它失效——例如把 `registerJoinState` 挪到转账之后、给 `_joinTokenAddressByActionId` 加零值兜底、或在 `isFirstJoin` 判定里改用本地账本。届时 `LpExecutor` 会为「属于别的 Executor 的行动」记账并拉走 LP，形成跨 Executor 的账本污染（不是越权提款，但会让 `withdraw` 按本合约的账本退币）。
- 建议：在 `join` 的首次校验段加一条显式判定，或在 `04-lp-executor.md` 写明「非首次加入不重复校验行动归属，依赖首次加入的 `registerJoinState`」。

### LP-04（Info）`onProposalCreated` 无本地 `AlreadyCreated` 守卫

- 证据：`L89-130` 无条件覆写 `_joinTokenAddressByActionId` / `_govRatioMultiplierByActionId` / `_minGovRatioByActionId` / `_createdRoundByActionId`。
- 唯一性完全由 ActionTarget 的 `_executorByActionId != 0 → AlreadyCreated`（`ActionTarget.sol:445`）保证。`ACTION_TARGET_ADDRESS` 是 `immutable`，且 ActionTarget 无重绑入口，所以当前不可达。
- 判定：与 GroupAction 的 `activationStakeAmountByActionId` 同型（见 `04-group-action-executor.md` GAE-02），但 LP 的后果轻——四项配置重复覆写不会造成资金错算，只会让 `createdRound` 被刷新。登记为「配置写入的唯一性由外部合约保证」。

### LP-05（正面结论）三个成员入口的鉴权全部是首道判定，且有「鉴权先于参数」负例

- 证据：`test/LpExecutor.t.sol:314 testJoinRequiresMemberOwner`、`:321 testJoinChecksOwnerBeforeAmount`（金额为 0 时仍报 `NotMemberOwner`）、`:529 testWithdrawRequiresMemberOwner`、`:583 testExitRequiresOwnerBeforeJoinedCheck`（未加入时仍报 `NotMemberOwner`）、`:840`、`:847`。
- 判定：§5.5「非授权方只拿到鉴权错误，不能借错误差异探测内部状态」在本合约被完整覆盖——连「该行动是否已创建」「该成员是否已加入」都无法通过错误差异探测。

### LP-06（正面结论）清仓路径的 CEI 与事件顺序逐条对齐 §4.4

- 证据：`_clearJoinState`（`L266-279`）先写全部状态，`safeTransfer` 在（`L222`、`L251`），`LpWithdrawn` 紧随，`clearJoinState` 再后，`LpExited` 最后（`L228-233`、`L257-262`）。
- 判定：`LpExited` 是无金额终态标记且最后发，`JoinStateCleared` 早于它；`LpWithdrawn` 带金额、早于 `JoinStateCleared`——与 `event-standards.md` §4.4 的「清自身状态 → 退款 → `clearJoinState` → `*Exited`」完全一致。`withdraw` 的部分撤回分支不发 `LpExited`，符合「部分撤回不改变加入状态」。

## 六、核对证据

```text
$ forge inspect LpExecutor abi --json | jq '[.[]|select(.type=="function")]|length'
25    # 写 8 / 读 17
$ forge inspect LpExecutor abi  vs  ILpExecutor
0 差异

$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 非 ActionTarget 调创建回调 | `test/LpExecutor.t.sol:81` |
| 非 ActionTarget 调推举回调 | `test/LpExecutor.t.sol:215` |
| 非 ActionTarget 调投票回调 + 项数 | `test/LpExecutor.t.sol:236` |
| 非持有人 `join` | `test/LpExecutor.t.sol:314` |
| 鉴权先于金额（`join`） | `test/LpExecutor.t.sol:321` |
| 非持有人 `withdraw` | `test/LpExecutor.t.sol:529` |
| 鉴权先于「已加入」（`exit`） | `test/LpExecutor.t.sol:583` |
| 非持有人 `mintMemberReward` | `test/LpExecutor.t.sol:840` |
| 鉴权先于轮次（`mintMemberReward`） | `test/LpExecutor.t.sol:847` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | ActionTarget | `registerJoinState`（首次加入）、`clearJoinState`（全额撤回/`exit`）、`mintActionReward`（结算）、`actionReward`（读） |
| 被调 | Core `Phase` | `currentPhase`、`phaseInfo`（时间权重） |
| 被调 | Core `Stake` | `validGovVotes`、`totalValidGovVotes`（治理上限） |
| 被调 | Core `MemberNFT` | `ownerOf`（5 个入口的鉴权函数） |
| 被调 | UniswapV2 `Factory` / `Pair` | `getPair`、`token0`/`token1`（创建回调的 Pair 登记校验） |
| 被调 | `LOVE20Token` / `IERC20` | `burn`（销毁部分）、`safeTransfer`/`safeTransferFrom`（资产进出口） |
| 被调 | 三个 Executor 共享 | `ExecutorBase` 的两个 modifier 与两个结算入口 |
