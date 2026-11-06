# Mint 接口调用权限审查

> 对象 `core/src/Mint.sol`（557 行）
> 接口 `core/src/interfaces/IMint.sol`（138 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/07-mint.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 27（写 4 / 读 23） |
| 带鉴权 modifier | 3（`onlyProposalTarget` ×1、`onlyMemberOwner` ×2） |
| 无许可写入口 | 1（`init`） |
| 发现 | 4 条：Medium 1（与既有 MNT-01 同源，不新增计数）/ Low 1 / Info 2，另有 2 条正面结论 |
| 接口对账 | 27 vs 27，**0 差异** |

一句话：**两个奖励出口对应两种完全不同的权限主体——治理奖励只给「成员 NFT 当前持有人」，提案奖励只给「该提案的 target」。后者是一个由提案内容自由指定、可为 EOA 的地址，且协议不校验提案是否被执行；加上「奖励池没有独立的准备入口」，谁先领谁定池。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 提案 `target` 地址 | `ISubmit(SUBMIT_ADDRESS).proposalTarget(token, proposalId)` 返回的 `target == msg.sender` | `mintProposalReward` |
| 成员 NFT 持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `mintGovReward`、`mintGovRewards` |
| 无 | `if (initialized) revert` | `init` |
| 无 | — | 23 个只读入口 |

两条鉴权语义的差别是本合约的核心：

| | 治理奖励 | 提案奖励 |
| --- | --- | --- |
| 主体 | 身份 NFT 持有人 | 提案 target 地址 |
| 是否可为 EOA | 否（必须是 NFT 持有人，但持有人可是合约） | **是**（`NoCallback` 模式下 target 可为 EOA） |
| 收款地址 | 由领取者任意指定 | 由 target 任意指定 |
| 可领次数 | 每 `(token, round, memberId)` 一次 | 每 `(token, round, proposalId)` 一次 |
| 是否要求提案被执行 | — | **否** |

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `init(8 参数)` | 无（一次性） | `if (initialized) revert` | 是 | **无** |
| `mintProposalReward(address,uint256,uint256,address)` | 提案 target | `onlyProposalTarget(tokenAddress, proposalId)` `L175` | 是 | `ProposalRewardMinted`（+`RewardPrepared`/`RewardBurned`） |
| `mintGovReward(address,uint256,uint256,address)` | `memberId` 持有人 | `onlyMemberOwner(memberId)` `L225` | 是 | `GovRewardMinted`（+`RewardPrepared`/`RewardBurned`） |
| `mintGovRewards(address,uint256[],uint256,address)` | `memberId` 持有人 | 同上 | 是 | 逐轮 `GovRewardMinted` |

### 只读入口（23）

配置 getter 10：`VOTE_ADDRESS`、`SUBMIT_ADDRESS`、`LAUNCH_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`PROPOSAL_REWARD_MIN_VOTE_RATIO`、`ROUND_REWARD_GOV_RATIO`、`ROUND_REWARD_PROPOSAL_RATIO`、`MAX_GOV_BOOST_REWARD_MULTIPLIER`、`initialized`。

查询 13：`rewardReserved`、`rewardMinted`、`rewardBurned`、`govReward`、`proposalReward`、`eligibleProposalVoteAmount`、`isRewardPrepared`、`launchCredit`、`proposalRewardByProposalId`、`govRewardByMemberId`、`isProposalIdWithReward`、`rewardAvailable`、`reservedAvailable`。

其中 `proposalRewardByProposalId` 与 `govRewardByMemberId` 会先做一次存在性断言（分别调 `Submit.proposalTarget`、`MemberNFT.ownerOf`），因此对不存在的对象回滚上游错误而不是返回 0。

## 四、逐入口判定

### `init` — 读一个可能还没初始化的依赖

- 固定 `VOTE_ADDRESS`/`SUBMIT_ADDRESS`/`LAUNCH_ADDRESS`/`MEMBER_NFT_ADDRESS` 与四个比例参数。
- 唯一的派生：`address phaseAddress = IVote(voteAddress).PHASE_ADDRESS();`（`L87`），即 **PHASE_ADDRESS 不是入参，而是从 Vote 读出来的**。
- 后果：若 `Vote` 尚未初始化，`PHASE_ADDRESS` 读出 0；`init` 仍会成功（`initialized = true`），此后 `_isRoundEnded` 调 `IPhase(0).currentPhase()` 空 revert，**奖励永久不可用且无法重初始化**。
- 部署脚本的顺序正确（`Vote.init` 在 `DeployCore.s.sol:271`，`Mint.init` 在 `L275`），且 `L366` 核对 `mint.PHASE_ADDRESS() == addrs.phase`。合约层没有 `!= address(0)` 的断言（见 MNT-05）。

### `mintProposalReward` — 权限主体是「提案 target」，不是协议合约

- `onlyProposalTarget` 读 `Submit.proposalTarget(token, proposalId)` 返回的 `(target, targetMode)`，只比较 `msg.sender != target`。
- 权限含义：
  1. **target 可为 EOA**（`NoCallback` 模式不要求代码），因此「一个普通地址」就能成为提案奖励的领取主体；
  2. target 由提案创建者在 `ProposalBody` 里指定，**创建者可以把收款权指向自己控制的任意地址**；
  3. 协议**不校验提案是否被执行**，只校验票数是否达到 `PROPOSAL_REWARD_MIN_VOTE_RATIO`（在 `_proposalRewardCalculation` 内）；
  4. `recipient` 由 target 指定，可为任意地址（含零地址检查，零则 `ZeroRecipientAddress`）。
- 结论：这是「按票分配、target 领奖」的设计，不是越权；但它使 `target` 成为一个**可自由转让的收款权载体**，与提案内容无绑定（见 SUB-02）。

### `mintGovReward` / `mintGovRewards` — 只给当前持有人

- `onlyMemberOwner(memberId)` 首道判定；`recipient` 任意（零地址回滚）。
- 权限含义：**奖励的领取权随 NFT 当前所有权**。NFT 转移后，新持有人可以领取历史轮次尚未铸造的奖励，并可指定任意 `recipient`。这与 `01-common-rules.md`「当前质押、未铸造激励、未用发射次数和解锁提取权由新持有人控制」一致。
- 批量版逐轮调用同一个私有实现；任一轮失败整批回滚（`MemberRewardAlreadyMinted` / `MemberRewardUnavailable` 等）。
- 空数组合法：`onlyMemberOwner` 仍会执行（`test/Mint.t.sol:145-148` 断言空批也先判所有权）。

### 奖励池的准备：internal helper 与对外无鉴权入口并存

`_prepareRewardIfNeeded` 是 `internal`，三个入口共用它：两个 mint 入口，以及对外无鉴权的 `prepareRewardIfNeeded`（`core@1411edb` 起）。含义：

- 任何人都可以「只准备不领取」，在轮次结束后由任意地址先把池子定下来；
- 池子大小在**第一次准备该轮**时按当时的 `rewardAvailable()` 确定（`Math.mulDiv(available, RATIO, 1e18)`）；
- 由于 `rewardAvailable` 随全协议的铸造/销毁变化，**先准备的人与后准备的人看到的池子不同**；
- 谁先调用准备，谁就有「抢先定池」的能力：不再只限于治理奖励的持有人与提案 target。

### `_updateLaunchCredit` — 奖励到发射次数的唯一通道

- 只在 `_mintGovReward` 内、`mintAmount > 0` 时调用（`L532`）。
- 读 `Launch.issuedLaunchCount` / `MAX_LAUNCH_COUNT` / `LAUNCH_COUNT_THRESHOLD_RATIO`，累计 `_launchCredit`，达阈值后调 `Launch.addLaunchCount`。
- 权限链闭合：`Launch.addLaunchCount` 只认 `MINT_ADDRESS`，而本合约就是 `MINT_ADDRESS`。没有第三个合约能写入发射次数。

## 五、发现

### MNT-01（Medium，与既有 MNT-01 同源，不新增计数）奖励池无独立准备入口，池子大小由首个领取者定

- 证据：`_prepareRewardIfNeeded` 为 `internal`（`L104`），唯一调用点是 `mintProposalReward`（`L196`）与 `_mintGovReward`（`L510`）；池子在 `L126-130` 按当时 `rewardAvailable(tokenAddress)` 计算并写入 `_rewardReserved`。
- 权限含义：**没有中立触发者**。规格 `07-mint.md` 把「准备」描述为领取的前置步骤，但链上没有「只准备」的入口，所以「本轮池子多大」这件事在权限上只归「第一个来领的人」。治理奖励持有人可以在轮次刚结束时立刻领取，把池子定在较高水位；提案 target 也可以。后领者只能分剩余。
- 兜底：`_proposalRewardCalculation` 与 `_govRewardCalculation` 在 `!_isRewardPrepared` 时有 fallback，用当前 `rewardAvailable` 现算，因此不会 revert；但 fallback 只影响**读**，真正落账还是由第一个 mint 写入。
- 判定：与既有审查的 MNT-01（每轮奖池由首个 mint 时点决定）同源，不新增计数。权限侧补充：**该问题无法通过「限制某个角色」修复，只能通过增加中立入口或把池子锚定到轮次结束的块**。
- 建议：若要修，最小改动是给 `_prepareRewardIfNeeded` 加一个无许可入口（例如 `prepareReward(tokenAddress, round)`），让任何人都能在轮次结束后、任何人领取之前把池子定下来；代价是多一个写入口与一次事件。

### MNT-02（Low）提案奖励与「提案是否被执行」解耦

- 证据：`mintProposalReward` 只校验 target 身份与票数门槛（`_proposalRewardCalculation` 内 `proposalVoteAmount >= minVoteAmount`），不读任何执行状态；`IProposalTarget` 的三个回调都是可选的通知，不是执行证明。
- 影响：一个 `NoCallback` 提案，只要票数达到 `PROPOSAL_REWARD_MIN_VOTE_RATIO`，其 target（可为 EOA）就能领走提案池中按票数分到的部分。投票者投的是「内容」，拿到钱的是「target」，两者之间没有链上约束。
- 判定：这是「激励按票分配」的设计结果，不是实现缺陷；但它是**权限面与业务语义的落差**：target 的领取权不依赖它做过任何事。
- 建议：在 `07-mint.md` 的 `mintProposalReward` 段落明确写「领取权仅由票数与 target 地址决定，与提案执行结果无关」，避免集成方误以为 target 必须是执行者。

### MNT-03（Info）`recipient` 任意 + NFT 可转移 = 临时持有人可截取历史未领奖励

- 证据：`_mintGovReward` 只校验 `msg.sender == ownerOf(memberId)`，`recipient` 只判非零（`L506-508`）。
- 影响：任何时点持有该 NFT 的地址，都可以把任意历史轮的未领治理奖励发到任意地址。租借、闪电持有、场外约定都会产生「谁持有谁领」的争议。
- 判定：规格明示（「未铸造激励由新持有人控制」），属设计。记录为**权限随资产转移**的典型样本，与 `Stake` 的解锁提取权同构。

### MNT-04（Info）`mintGovReward` 声明为 `public` 但无内部调用

- 证据：`L232` 为 `public`；`mintGovRewards` 调的是私有实现 `_mintGovReward`（`L238`、`L258`），没有内部调用 `mintGovReward`。
- 影响：`public` 允许合约内部直接调用，但本合约没有这样的调用点；改为 `external` 不改变 ABI、不改变行为，只是收窄可见性。
- 判定：不影响权限；属接口面最小化的可选整理项。

### MNT-05（Info）`init` 从 Vote 派生 `PHASE_ADDRESS`，顺序错则永久不可用

- 证据：`L87` `address phaseAddress = IVote(voteAddress).PHASE_ADDRESS();`；`L93` 写入；无 `!= address(0)` 断言。
- 影响：Vote 未初始化时读出 0，`init` 仍成功，`_isRoundEnded` 此后空 revert，奖励永久不可用。
- 兜底：部署顺序（`Vote.init` 先于 `Mint.init`）与 `DeployCore.s.sol:366` 的 `mint.PHASE_ADDRESS() == addrs.phase` 检查。
- 判定：符合 §5.7 的分工（依赖派生值由部署脚本校验），但这是全仓唯一「`init` 读取另一个可未初始化合约的状态」的地方，建议在 `07-mint.md` 的初始化段落显式写出这条顺序约束，而不是只写在部署 README 里。

### MNT-06（正面结论）`onlyProposalTarget` 的错误载荷不泄漏额外信息

- 证据：`NotProposalTarget(address caller, address expectedTarget)`；而 `Submit.proposalTarget` 本就是公开读函数。
- 判定：把 `expectedTarget` 带进错误不构成信息增量，反而方便链下定位。与 `NotMinter`（只带 caller、不带 MINTER）是两种取舍，都合理。

### MNT-07（正面结论）`_updateLaunchCredit` 的权限链只有一条

- 证据：`_updateLaunchCredit` 为 `internal`，唯一调用点 `L532`（`_mintGovReward` 内、`mintAmount > 0`）；`Launch.addLaunchCount` 只认 `MINT_ADDRESS`。
- 判定：发射次数的「产生」只能由治理奖励的实际铸造触发，没有第二个入口，也没有「手工加次数」的管理函数。

## 六、核对证据

```text
$ forge inspect Mint abi --json                # 27 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

鉴权负例：

| 用例 | 位置 | 断言 |
| --- | --- | --- |
| 非 target 领提案奖励 | `test/MintCoverage.t.sol:109-112` | `NotProposalTarget(address(this), TARGET)` |
| 同上（边界套件） | `test/MintEdgeCases.t.sol:164-167` | 同上 |
| 非持有人领治理奖励 | `test/Mint.t.sol:328-331` | `NotMemberOwner(1)` |
| 空批也先判所有权 | `test/Mint.t.sol:145-148` | `NotMemberOwner(1)` |
| 真实集成：错误 target 与错误持有人 | `test/integration/MintRealIntegration.t.sol:898-913` | 两个选择器分别断言 |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 读 | `Vote.totalVoteAmount` / `voteAmountByProposalId` / `voteAmountByMemberId` / `voterBoost` / `totalVoterBoost` / `votedProposalIds` | 奖励分配的全部票数来源 |
| 读 | `Submit.proposalTarget` | `onlyProposalTarget` 的鉴权源 |
| 读 | `MemberNFT.ownerOf` | 治理奖励的鉴权源 |
| 读 | `Phase.currentPhase` | `_isRoundEnded` |
| 读 | `Launch.issuedLaunchCount` / `MAX_LAUNCH_COUNT` / `LAUNCH_COUNT_THRESHOLD_RATIO` | 发射额度生成 |
| 写 | `LOVE20Token.mint` | 唯一铸造出口（本合约是 `MINTER`） |
| 写 | `Launch.addLaunchCount` | 唯一加次数出口（本合约是 `MINT_ADDRESS`） |
