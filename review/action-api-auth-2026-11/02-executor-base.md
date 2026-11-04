# ExecutorBase 接口调用权限审查

> 对象 `action/src/ExecutorBase.sol`（140 行，`abstract contract`）
> 接口 `action/src/interfaces/IActionExecutor.sol`（102 行，`is IProposalTarget`）
> 基线 `action@8478619`（`src/` 自 `e849e36` 无实质变化，行号未位移）；审查日期 2026-11-03
> 判据 dev-standards §5.5（modifier 的唯一定义位置）、§5.2.2（失败顺序）、§4.3（集合读取）；`specs/action/00-executor-interface.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数（被三个 Executor 继承） | 3 写 + 4 读 |
| 鉴权 modifier | 2（`onlyMemberOwner`、`onlyActionTarget`） |
| 无许可写入口 | 0 |
| 发现 | 2 条 Info；另有 2 条正面结论 |
| 接口对账 | 由三个 Executor 各自 0 差异（本合约不单独部署，无独立 ABI） |

一句话：**这是全仓唯一被允许承载共享 modifier 的地方，两个鉴权面（成员持有人、ActionTarget）都在这里写一次，三个 Executor 不再留副本；三个继承的写入口全部 `nonReentrant` + `onlyMemberOwner`，顺序符合 §5.5。唯一的实质问题是没有。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| `memberId` 当前持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `mintMemberReward`、`mintMemberRewards` |
| ActionTarget | `msg.sender == ACTION_TARGET_ADDRESS` | `onProposalSubmitted` |
| 无 | — | `currentVoteRound`、`currentJoinRound`、`currentMintRound` 与四个依赖 getter |

`ACTION_TARGET_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS` 都是 `immutable`，在构造函数内一次解析（`L19-26`）：

```solidity
STAKE_ADDRESS = IVote(IActionTarget(actionTargetAddress).VOTE_ADDRESS()).STAKE_ADDRESS();
MEMBER_NFT_ADDRESS = IStake(STAKE_ADDRESS).MEMBER_NFT_ADDRESS();
PHASE_ADDRESS = IStake(STAKE_ADDRESS).PHASE_ADDRESS();
```

这条派生链有明确的权限含义：**三个 Executor 的成员鉴权函数（`MEMBER_NFT_ADDRESS`）不是由部署者直接给的，而是从「ActionTarget → Vote → Stake」反查出来的。** 因此一个 Executor 不可能被接成一个「与它的 ActionTarget 不一致的 Stake」，代码里有 `Load-bearing:` 注释标明这一点。反过来，如果部署者把 `actionTargetAddress` 指到一个伪造的 ActionTarget，整条链都会指向伪造合约——但那只影响这个 Executor 自己，不影响真实 ActionTarget（见 `04-group-action-executor.md` 的构造函数段）。

## 三、入口清单

### 写入口（3，均被三个 Executor 继承）

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `onProposalSubmitted(address,uint256,uint256,bytes[])` | ActionTarget | `onlyActionTarget` `L43` | 是 | 无（空实现） |
| `mintMemberReward(address,uint256,uint256,uint256)` | `memberId` 持有人 | `nonReentrant onlyMemberOwner` `L51` | 是 | `MemberRewardMinted`（子类实现） |
| `mintMemberRewards(address,uint256[],uint256[],uint256)` | `memberId` 持有人 | `nonReentrant onlyMemberOwner` `L60` | 是 | 逐条 `MemberRewardMinted` |

### 只读入口（4 + 4 个 immutable getter）

`currentVoteRound`、`currentJoinRound`、`currentMintRound` 三个 Round 查询，以及 `ACTION_TARGET_ADDRESS`、`STAKE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS` 四个自动 getter。

三个 Round 查询的未开始行为一致：推导值为 0 时回滚 `RoundNotStarted(1, 0)`（`L83-105`）。这是**读入口会回滚**的少数情形之一，链下必须按「可能 revert」处理。

## 四、逐入口判定

### `mintMemberReward` / `mintMemberRewards` — 成员级结算的两个入口

- 两者都是 `nonReentrant` 在最左、`onlyMemberOwner` 紧随其后（§5.5 强制顺序）。
- 单条：`public`，直接转调 `_mintMemberReward`（`L57`）。
- 批量：先判 `actionIds.length == rounds.length` → `BatchLengthMismatch`（`L72-74`），再逐元素调 `_mintMemberReward`（`L78-80`）。空数组在鉴权通过后返回两个空数组、不改状态——符合规格「空数组在鉴权通过后返回空结果」。
- 批量没有长度上限：规格明说「成本由调用方自付，区块 gas 为自然上界（与 core `mintGovRewards` 同型）」。这是写入口里少见的「不设上限」豁免，理由成立（成本只落在调用者自己身上，且每笔结算都要拉取整笔激励，第三方无法被迫承担）。
- 批量语义：任一元素失败整笔回滚（Solidity 事务语义天然满足），下标对齐不补空。`RewardAlreadyMinted` 会让重复元素失败，因此「重复传同一个 `(actionId, round)`」不可幂等——链下批量前须自行去重。

### `onProposalSubmitted` — 空实现，但带鉴权

```solidity
function onProposalSubmitted(...) external virtual override onlyActionTarget {}
```

- 三个 Executor 都不覆写，所以它在三个合约里的行为都是「校验调用者是 ActionTarget 后什么都不做」。
- 与规格一致：`05-group-action-executor.md` 写「推举回调当前只校验调用者，无状态写入」。
- 但它是 ABI 上的一个写入口，且不产生任何状态变化、不发事件。§4.2 允许「确无观测价值的写函数」例外，须在对账文档写明理由——此处理由（推举不改变 Action 层状态）只在模块规格里，未在接口或事件对账文档中登记。见 **EB-01**。

### 三个 Round 查询 — 未开始即回滚

| 入口 | 推导 | 未开始条件 |
| --- | --- | --- |
| `currentVoteRound` | `phase` | `phase < 1` |
| `currentJoinRound` | `phase - 1` | `phase < 2` |
| `currentMintRound` | 由子类 `_mintRound()` 决定 | 推导值为 0 |

`currentJoinRound` 是 `public`（子类内部也会调），另两个是 `external`。这是可见性差异而非权限差异：三者都无调用者限制。

注意 `currentVoteRound` 直接返回 `phase` 而 `currentJoinRound` 走 `_joinRound()`（虚函数，子类实现）。LpExecutor 与 GroupAction 系列的 `_joinRound()` 都调 `GroupActionRoundAxis.joinRound` / `LpRoundAxis.joinRound`，两者是逐字节相同的两份实现（见 `10-support-libraries.md` SUP-02）。

## 五、发现

### EB-01（Info）`mintMemberReward` 声明为 `public` 但无内部调用，可收窄为 `external`

- 证据：`ExecutorBase.sol:51` 是 `public`；`mintMemberRewards` 调的是 `_mintMemberReward`（`L79`），不是 `mintMemberReward`。三个子类也没有内部调用它。
- 判定：改 `external` 不改 ABI、不改行为、不改 gas（外部调用路径不变），只收窄可见性。与 core 审查的 MNT-04/G-07 同类，属可选的接口面整理。

### EB-02（Info）`onProposalSubmitted` 的「无事件」例外未在事件对账文档登记

- 证据：`L43-48`，空函数体、无 `emit`。
- §4.2 要求「确无观测价值的写函数（如 `init`）为例外，须在对账文档写明理由」。`init` 有登记，`onProposalSubmitted` 没有。
- 判定：不构成缺陷（规格正文已说明推举回调无状态写入），只是登记位置不完整。建议在 `07-minting.md` 的事件段或 `01-action-target.md` 的「与 ActionTarget 的事件分层」里补一行。

### EB-03（正面结论）共享 modifier 只在基类写一次，符合 §5.5 的唯一例外

- 证据：`onlyMemberOwner`（`L29`）与 `onlyActionTarget`（`L36`）只在本文件出现一次；三个 Executor 全部复用，没有副本。
- §5.5 允许的唯一例外是「modifier 定义在合约自身，或它继承的**唯一**抽象基类里」，并要求基类同时承载该鉴权面的其余成员。本基类承载了 `mintMemberReward`/`mintMemberRewards`（成员鉴权面）与 `onProposalSubmitted`（ActionTarget 鉴权面），满足「基类必须同时承载该鉴权面的其余成员」。
- 判定：这是全仓 modifier 复用的正确样本。对照 `GroupActionExecutor` 把 12 个写入口的鉴权放进库里（见 `04-group-action-executor.md` GAE-01），可以清楚看出「§5.5 允许的复用」与「24KB 拆分导致的复用」是两件事。

### EB-04（正面结论）两个 modifier 都自己判调用者、有 revert、以 `_;` 收尾

- 证据：`L29-34`、`L36-41`，与 `check_caller_auth.py` 的三条形状要求逐条对应（`violations: 0`）。
- 判定：modifier 只做判定，不写状态、不发起状态变更外呼；`onlyMemberOwner` 里的 `ownerOf` 是允许的只读鉴权查询。

## 六、核对证据

```text
$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0

modifier 形状（本文件）
onlyMemberOwner   sender=yes revert=yes ends=_;  L29
onlyActionTarget  sender=yes revert=yes ends=_;  L36
```

鉴权负例（经子类覆盖）：

| 用例 | 位置 |
| --- | --- |
| 非持有人 `mintMemberReward` | `test/LpExecutor.t.sol:840` `testMintMemberRewardRequiresMemberOwner` |
| 鉴权先于轮次 | `test/LpExecutor.t.sol:847` `testMintMemberRewardChecksOwnerBeforeRound` |
| 批量长度不等（鉴权后） | `test/LpExecutor.t.sol:992` `testMintMemberRewardsRejectsLengthMismatch` |
| 非 ActionTarget 调推举回调 | `test/LpExecutor.t.sol:215` `testSubmittedCallbackGatesCaller` |
| 鉴权先于行动存在性 | `test/GroupActionExecutor.t.sol:335` `testMintChecksOwnerBeforeActionExistence` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被继承 | `LpExecutor`、`GroupActionExecutor`、`GroupServiceExecutor` | 两个 modifier + 3 个写入口 + 4 个读入口 |
| 读 | Core `MemberNFT.ownerOf` | 成员鉴权函数（由 Stake 派生） |
| 读 | Core `Phase.currentPhase` | 三个 Round 查询的唯一来源 |
| 读 | Core `Vote.STAKE_ADDRESS`、`Stake.MEMBER_NFT_ADDRESS` / `PHASE_ADDRESS` | 构造期一次性派生 |
| 调 | 子类 `_joinRound()` / `_mintRound()` / `_mintMemberReward()` | 三处虚函数，权限判定全部在基类 |

## 处置

`EB-01`、`EB-02` 的落点见 `README.md` §十（`00-executor-interface.md` 的可见性说明与 `07-minting.md` 的推举转发例外）。
