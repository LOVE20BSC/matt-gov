# 通用规则

## 主体与权限

- 业务主键为 MemberNFT 的 `memberId`；`author`、`submitterId`、`voterId` 均记录该身份，钱包地址仅作控制者或调用者。
- 处分成员资产、权益或业务状态时校验 `MemberNFT.ownerOf(memberId) == msg.sender`。单向融合只增加目标状态，不要求调用者持有目标 NFT。
- NFT 转移不改写历史质押、投票、发射、快照、已结算激励或事件。当前质押、未铸造激励、未用发射次数和解锁提取权由新持有人控制，解锁倒计时不重置。
- Proposal Target 和首批代币 distributor 是明确的地址型角色；群聊权限属于 Group Chat 内部事务，见 [组织上下文](../../../CONTEXT.md)。
- ERC721 的 `approve`/`setApprovalForAll` 只授予转移权，不授予业务权：所有成员入口一律校验 `ownerOf(memberId) == msg.sender`，被授权方不能代为质押、投票、推举或领取激励。多签或托管合约须以自身地址作为调用者。
- `memberId` 不存在时，`ownerOf` 直接回滚 `ERC721NonexistentToken(memberId)`，不会落到各合约的 `NotMemberOwner`。该错误对任意调用者可见，但 `memberId` 由 ERC721Enumerable 公开可枚举，不构成信息泄漏；链下按「不存在 → OZ 错误，非持有人 → `NotMemberOwner`」分类。
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
- 部署顺序固定为 `Phase → Launch → MemberNFT → Stake → Submit → Vote → Mint`。前向引用只在三处：`MemberNFT`、`Vote`、`Mint`，由脚本按部署者 nonce 预测地址，并在对应合约部署后立即核对；`Stake` 的 `VOTE_ADDRESS()` 也在此一并核对。
- 部署是否成功由发布前检查脚本核对实际绑定结果判定，逐项核对依赖地址和全部配置常量，任何不一致即重新部署。
- 构造函数不发**配置**事件，也不发任何以自身名义宣告初始化完成的事件；`Launch` 构造期创建首币是唯一例外，它的日志序列是业务日志——首币构造发 `TokenMinted`、工厂建池发 `PairCreated`、最后 `Launch` 发 `GenesisTokenCreated`，其中 `GenesisTokenCreated` 必须是构造期的最后一条日志。
- 写操作遵循检查、更新、交互顺序并防重入；失败不能留下半完成状态。`Stake` 是这条规则的有意例外：它不设重入锁，改以「先完成全部校验、再发起外部调用、并以外部调用实际返回的数量记账」保证一致，理由与边界见 [Stake 实现约束](04-stake.md#实现约束)。

## 编号约束

Proposal ID 从 `1` 开始递增，`0` 永远无效；未创建对象使用显式存在性判断，不把真实业务记录编码为 `0`。
