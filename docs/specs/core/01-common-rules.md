# 通用规则

## 主体与权限

- 业务主键为 MemberNFT 的 `memberId`；`author`、`submitterId`、`voterId` 均记录该身份，钱包地址仅作控制者或调用者。
- **减少 / 处分收敛，单向增加开放。** 处分、削减、迁移成员资产、权益或业务状态（解锁、提取、融合源侧、投票、推举、领取激励）一律校验 `MemberNFT.ownerOf(memberId) == msg.sender`；只向某个 `memberId` **单向增加**资产或权益的入口不要求调用者持有该 NFT，但必须调用 `ownerOf(memberId)` 校验存在（不存在时由 `MemberNFT` 回滚 `ERC721NonexistentToken`）。当前开放的单向增加只有三处：`Stake.stakeLiquidity`、`Stake.stakeBoost`、`Stake.mergeStake` 的目标侧（见下方「无许可增项」）。
- NFT 转移不改写历史质押、投票、发射、快照、已结算激励或事件。当前质押、未铸造激励、未用发射次数和解锁提取权由新持有人控制，解锁倒计时不重置。
- Proposal Target 和首批代币 distributor 是明确的地址型角色；群聊权限属于 Group Chat 内部事务，见 [组织上下文](../../../CONTEXT.md)。
- ERC721 的 `approve`/`setApprovalForAll` 只授予转移权，不授予业务权：所有**减少 / 处分**类成员入口一律校验 `ownerOf(memberId) == msg.sender`，被授权方不能代为解锁、提取、投票、推举或领取激励。多签或托管合约须以自身地址作为调用者。单向增加类入口按上一条处理，被授权方同样不能借 `approve` 获得处分权——它本来就只能增加。
- `memberId` 不存在时，`ownerOf` 直接回滚 `ERC721NonexistentToken(memberId)`，不会落到各合约的 `NotMemberOwner`。该错误对任意调用者可见，但 `memberId` 由 ERC721Enumerable 公开可枚举，不构成信息泄漏；链下按「不存在 → OZ 错误，非持有人 → `NotMemberOwner`」分类。**只验存在的入口（`stakeLiquidity` / `stakeBoost` / `mergeStake` 目标侧）不会产生 `NotMemberOwner`，其不存在分支只有 `ERC721NonexistentToken`。**
- 跨合约读取会把上游错误原样穿透：`Mint.mintProposalReward` 对不存在的提案回滚 `Submit.ProposalNotFound(tokenAddress, proposalId)`，`Stake` 对无代码或返回空数据的依赖得到空 revert。链下分类须同时识别本合约错误与上游来源。
- 未由 Launch 登记的代币没有质押入口（`Stake` 的写入口统一 `_checkToken`），因此其治理票权与加速份额恒为 `0`；`Submit`、`Vote` 不对 `tokenAddress` 做登记校验，由这条不变量兜底成 `NoGovVotes` / `NoVotingPower`。

例：Phase 10 申请解锁，等待 5 个 Phase；Phase 12 转移 NFT，Phase 16 起由新持有人提取（第 15 个 Phase 仍然太早，口径见 [Stake 解锁与提取](04-stake.md#解锁与提取)）。

## 无许可入口

写入口默认按「主体与权限」校验调用者。以下五个入口不设调用者限制，判据是调用者没有任何指向他人的参数（收款地址、`memberId`、金额），且函数只推进一个已成立的状态转换：

| 入口 | 可做的唯一一件事 | 不能做的 |
| --- | --- | --- |
| `LOVE20Token.burn` | 销毁 `msg.sender` 自己的余额 | 销毁他人余额（无 allowance 语义） |
| `MemberNFT.mint` | 为自己铸造身份，费用从自己划转并销毁 | 替他人铸造、指定他人收款 |
| `Phase.sync` | 每 Phase 一次，按真实块号与时间戳采样 | 伪造块数/时长、回写已生成的 Phase |
| `Stake.settleFees` | 每社区每 Phase 一次，达到阈值时结算并销毁 | 指定收款地址或金额、跳过阈值 |
| `Mint.prepareRewardIfNeeded` | 每 token 每 Round 一次，在轮次结束后按当时 `rewardAvailable` 冻结两池与达标票数 | 在未结束轮次准备、指定收款地址或成员、改变比例、重复准备（已准备时幂等返回） |

新增无许可写入口必须同时满足上述两条判据，并在模块规格写明「谁都能调、为什么无害」；只满足一条的入口应设计鉴权。

## 无许可增项

与「无许可入口」并列的第二类：入口**有**指向他人的参数（`memberId`），但不设调用者限制，因为参数只用于把调用者自己的资产单向加到别人名下，无法减少任何人的资产或权益。

| 入口 | 谁都能调 | 为什么无害 |
| --- | --- | --- |
| [`Stake.stakeLiquidity`](04-stake.md#stakeliquidity) | 任何人可为任意已存在的 `memberId` 增加流动性质押 | 只增加目标的份额与票权；`_pull` 从 `msg.sender` 拉币，花的是调用者的钱；目标已有仓位时不得改写其 `promisedWaitingPhases`（见下条约束） |
| [`Stake.stakeBoost`](04-stake.md#stakeboost) | 同上，为任意已存在的 `memberId` 增加加速质押 | 同上；额外受单人上限 `m_i` 约束，超出即整笔回滚 |
| [`Stake.mergeStake`](04-stake.md#mergestake) 目标侧 | 调用者只需持有**源** NFT，可为任意已存在的目标 `memberId` 接收融合 | 目标侧只增不减（源的份额迁入目标，源被清空）；目标已有仓位时源等待期不得短于目标 |

这三处的共同约束与判据：

- **只调 `ownerOf(memberId)` 校验存在，不比较 `msg.sender`**。写法沿用 `mergeStake`：`// forge-lint: disable-next-item(unused-return)` + `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId);`。不存在时由 `MemberNFT` 回滚 `ERC721NonexistentToken`，不落 `NotMemberOwner`。
- **减少 / 处分仍收紧**：`unstake`、`withdraw`、`mergeStake` 的源侧、投票、推举、领取激励一律要求 `ownerOf(memberId) == msg.sender`。开放面只在「加」这一侧。
- **已有仓位时不得改写等待期**：只有 `stakeLiquidity` / `stakeBoost` 会改变 `promisedWaitingPhases`，判据是目标已有质押（`liquidityShares != 0 || boostShares != 0`，与 `mergeStake` 的 `targetHadPosition` 同判据）。非 owner 调用必须沿用现有值；空仓位允许自由指定（含 `MAX`）。实际交互中首次质押仍由 owner 经 Hub 完成，强制降为 `MIN` 会逼出「质押 + 调整等待期」两步，拿真实用户成本去防一个已有补救的骚扰。
- **不引入新的 griefing 类别**：第三方用 dust 抢先给某个 `memberId` 开仓、把等待期钉成 `MAX` 这一攻击，在开放前就能经 `mergeStake` 完成（用自己的 `MAX` 仓位融合到任意空目标，空目标继承源等待期，且目标侧不要求持有 NFT）。该仓位同样可通过 `mergeStake` 移走、`withdraw` 清理，`firstGovVoteRound` 随之归零（社区级标记除外，它不参与任何资格判定）。放开 `stakeLiquidity` 只是把一条已经开放的能力从「融合」推广到「直接质押」。
- **可观测性由字段补齐**：`LiquidityStaked` / `BoostStaked` 带 `caller`（`msg.sender`）与 `memberOwner`（写入时点的 `ownerOf` 快照），与 `tx.from` 三者比对即可判「本人直接质押 / 本人经 Hub / 第三方代付」。
- **新增单向增加入口必须先登记**：判据是「参数含他人 `memberId`、只增不减、调用者自带资金」。落入本类的入口须在此表登记，并在模块规格写明「谁都能调、为什么无害」以及「已有仓位时的等待期 / 参数约束」。不满足「只增不减」的入口归「主体与权限」，按处分规则校验 `ownerOf == msg.sender`。

## 回调接口

`IProposalTarget`（`onProposalCreated` / `onProposalSubmitted` / `onProposalVoted`）与 `ILaunchDistributor`（`onTokenLaunched`）由 core 调用、由外部实现，core 侧不校验实现方。**实现方必须在每个回调入口的第一道判定校验调用者**：提案回调只接受 `Submit` 或 `Vote`，发射回调只接受 `Launch`。漏掉这一条，任何人都能伪造「已创建 / 已推举 / 已投票 / 已发射」直接改写该实现的状态。

core 不校验是有意分工：core 无法预知实现集合，且回调是通知而非授权。

## 编号与精度

- Phase、治理 Round 和 MemberNFT 从 `1` 开始；`0` 表示未设置或无效。
- Proposal ID 由 Submit 单调分配并保持稳定，不把某个起始值用作通用哨兵。
- 比例参数统一 `1e18` 精度：百分比以 `1e18` 表示 100%，纯比值以 `1e18` 表示 1:1；不使用千分比、百分比、万分比刻度。
- 纯除数（手续费结算分母、身份费用除数等）不是比例，保持整数分母并按语义命名。
- 金额比例分配默认向下取整；发射阈值及明确标为 `ceil` 的式子向上取整。

## 部署与安全

- 依赖注入统一走构造函数，不再保留一次性 `init` 入口；构造函数不设调用者限制，合约不保存部署者地址，也不授予部署者特权。部署成功后依赖地址和配置参数不可替换，无升级管理员或协议级后门。
- 构造函数是硬约定：只保存传入地址与配置，**不得调用同代码仓库、同批部署合约的任何 getter 或函数**。因此地址必须来自部署脚本的预测或既有部署；`Launch` 的 `factory.getPair`/`createPair` 是唯一例外——它调用的是已部署的第三方 UniswapV2 工厂。
- 构造函数不做静态零值校验；部署期静态参数由 `DeployCore` 广播前校验；依赖代码与派生值由 `DeployCore` 部署后校验、`21_check.sh` 独立复核，不匹配即重新部署，见 dev-standards §5.7。
- 部署顺序固定为 `Phase → AirdropDistributor → Launch → MemberNFT → Stake → Submit → Vote → Mint`。前向引用只在四处：`AirdropDistributor` 构造期需要 `Launch` 及其首币地址（首币地址本身是 `Launch` 的第一笔 CREATE，按 `computeCreateAddress(launchAddress, 1)` 预测）、`MemberNFT`、`Vote`、`Mint`，由脚本按部署者 nonce 预测地址，并在对应合约部署后立即核对；`Stake` 的 `VOTE_ADDRESS()` 也在此一并核对。
- 部署是否成功由发布前检查脚本核对实际绑定结果判定，逐项核对依赖地址和全部配置常量，任何不一致即重新部署。
- 构造函数不发**配置**事件，也不发任何以自身名义宣告初始化完成的事件；两处已登记例外都是「构造期即成立的业务事实」，不是初始化完成宣告：`Launch` 构造期创建首币的日志序列（首币构造发 `TokenMinted`、工厂建池发 `PairCreated`、最后 `Launch` 发 `GenesisTokenCreated`，其中 `GenesisTokenCreated` 必须是构造期的最后一条日志），以及 `AirdropDistributor` 构造期为首币写入分发配置后发出的 `AirdropConfigured`——首币固定 `NoCallback`，`Launch` 不会回调它，首币的配置只能在它自己的构造函数内完成，若此时不发事件则该配置没有其它事件覆盖。新增第三处必须先在此登记。
- 写操作遵循检查、更新、交互顺序并防重入；失败不能留下半完成状态。`Stake` 是这条规则的有意例外：它不设重入锁，改以「先完成全部校验、再发起外部调用、并以外部调用实际返回的数量记账」保证一致，理由与边界见 [Stake 实现约束](04-stake.md#实现约束)。

## 编号约束

Proposal ID 从 `1` 开始递增，`0` 永远无效；未创建对象使用显式存在性判断，不把真实业务记录编码为 `0`。
