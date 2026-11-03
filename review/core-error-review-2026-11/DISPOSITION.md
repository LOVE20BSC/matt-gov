# 错误专项 Review 处置记录（2026-11-03）

> 报告基线：`core@6fdd0f1`。本轮修复在 `core@f4f8d34` 的工作树上完成，未提交。
> 各合约报告中的行号保留 6fdd0f1 快照；当前行号以工作树为准。

## 一、逐条决定

| ID | 决定 | 落地 |
| --- | --- | --- |
| E-NFT-01 | **忽略** | 幂运算上界交给配置参数负责人决定，合约与部署脚本不改 |
| E-STK-01 | **已修（补写前提）** | `ZeroLiquidityMinted` 保留，作为将来接入“返回 0 的兼容 V2 Pair”的防御性错误；04-stake 本轮补写该前提 |
| E-LAU-02 | **已修（补写前提）** | `PairCreationFailed` 保留，同上；08-launch 本轮补写正常路径与“返回零地址的兼容工厂”前提 |
| E-STK-02 | 已修 | `SourceAndTargetMemberIdsMustBeDifferent` → `SourceEqualsTarget(uint256)` |
| E-STK-03 | 已修 | `InsufficientWaitingPhases` → `UnlockRoundNotReached` |
| E-STK-05 | 已修 | `NotAllowedToStakeAtRoundZero` → `StakeNotStarted` |
| E-STK-06 | 已修 | 规格参数名 `requiredRound` → `requestedRound`（00/04/06/09） |
| E-MNT-01 | 已修 | `ProposalRewardUnavailable` 拆为 `ProposalBelowThreshold` / `ProposalPoolEmpty` / `ProposalRewardRoundedToZero`；判定顺序为门槛 → 池值为零 → 取整为零，与治理侧的「未投票 → 池空 → 取整为零」同向 |
| E-MNT-02 | 已修 | `MemberRewardUnavailable` 拆为 `MemberHasNoVote` / `MemberRewardPoolEmpty` / `MemberRewardRoundedToZero` |
| E-MNT-03 | 已修 | 07-mint 增加“透传来源”表（Submit / MemberNFT / LOVE20Token / Launch） |
| E-LAU-01 | 已修 | `InsufficientLaunchCount` 载荷顺序改为 `(memberId, required, available)` |
| E-LAU-03 | 已修 | `SourceAndTargetMemberIdsMustBeDifferent` → `SourceEqualsTarget(uint256)` |
| E-LAU-04 | 已修 | 08-launch 的 init 表与“透传来源”表登记 LOVE20Token 构造错误 |
| E-SUB-01 | 已修 | `ProposalNotFound` 增加 `tokenAddress` |
| E-SUB-04 | 已修 | Mint / Vote 的透传来源表登记 `ProposalNotFound` |
| E-VOT-01 | 已修 | `_vote` 先读 `proposalTarget` 判存在（未分配 ID 透传 `ProposalNotFound`），再判本轮推举 |
| E-VOT-02 | 已修 | `ZeroVoteAmount` 增加 `tokenAddress`、`round` |
| E-VOT-03 | 已修 | `vote` 改为形状 → 资格；`_vote` 改为零票 → 存在性 → 推举状态；06-vote 同步 |
| E-NFT-03 | 已修 | 02-member-nft 增加 `mint` 校验顺序表 |
| E-NFT-04 | 已修 | 02-member-nft 增加“透传来源”表 |
| E-NFT-05 | 已修 | 02-member-nft 登记未初始化时空 revert（0x）的失败形态 |
| E-TOK-01 | 已修 | `InvalidInitialSupply` → `MaxSupplyBelowInitialSupply` |
| E-MNT-04 | 保留 | `RoundNotEnded` 载荷不变；Info，未纳入本次改动 |
| E-MNT-06 | 保留 | 下溢 Panic 的文档登记；Info，未纳入本次改动 |
| E-STK-04 | 保留 | `TargetPromisedWaitingPhasesTooShort` 命名；Info，未纳入本次改动 |
| E-LAU-05 | 保留 | 入口级可达性列；Info，未纳入本次改动 |
| E-LAU-06 | 保留 | Callback 适用性说明；Info，未纳入本次改动 |
| E-VOT-04 | 保留 | 加速快照先写后判额度；Info，未纳入本次改动 |
| E-VOT-05 | 保留 | 同批重复 proposalId 的文档说明；Info，未纳入本次改动 |
| E-TOK-02 | 保留 | OZ `ERC20InvalidReceiver` 透传说明；Info，未纳入本次改动 |
| E-TOK-03 | 保留 | OZ `ERC20InsufficientBalance` 透传说明；Info，未纳入本次改动 |
| E-PHS-01 | 保留 | `phaseAtBlock` 的 0 哨兵说明；Info，未纳入本次改动 |
| E-PHS-02 | 保留 | `phaseInfo` 可外推未来 Phase；Info，未纳入本次改动 |
| E-MNT-05 | **撤回** | 07-mint:130 已写明空批次合法 no-op，原报告漏读 |
| E-SUB-02 | **撤回** | 05-submit:108 已写明创建与推举同笔原子，原报告漏读 |
| E-SUB-03 | **撤回** | 05-submit:98 已定义 `requiredVotes == 0` 的边界；`SUBMIT_MIN_RATIO == 0` 由部署门禁禁止 |
| E-STK-07 | **撤回** | 04-stake:142 已写明零额提取跳过转账、仍清仓位并发零额事件 |
| E-NFT-02 | **撤回** | 02-member-nft:56 已写明 `Test` 前缀计入 `byteLength`，`NameTooLong` 的 `length` 即该值 |

## 二、ABI 变更

| 旧 selector / 签名 | 新 selector / 签名 |
| --- | --- |
| `0x1049dc75` `SourceAndTargetMemberIdsMustBeDifferent(uint256,uint256)` | `0xbbef66e9` `SourceEqualsTarget(uint256)` |
| `0xbe9cd064` `NotAllowedToStakeAtRoundZero()` | `0xcd329a46` `StakeNotStarted()` |
| `0x84d77e73` `InsufficientWaitingPhases(uint256,uint256)` | `0x39cb81ec` `UnlockRoundNotReached(uint256,uint256)` |
| `0x9906d24a` `InvalidInitialSupply(uint256,uint256)` | `0xdce94538` `MaxSupplyBelowInitialSupply(uint256,uint256)` |
| `0x428d06a9` `ProposalNotFound(uint256)` | `0x8e1a32af` `ProposalNotFound(address,uint256)` |
| `0x1ccf718a` `ZeroVoteAmount(uint256)` | `0x0164ed89` `ZeroVoteAmount(address,uint256,uint256)` |
| `0x750e6e06` `InsufficientLaunchCount(uint256,uint256,uint256)` | selector 不变；参数顺序改为 `(memberId, required, available)` |
| `0x6b95e12e` `ProposalRewardUnavailable(address,uint256,uint256)` | 删除；新增 `0xbdf55b4f` `ProposalBelowThreshold(address,uint256,uint256,uint256,uint256)`、`0x11b384c6` `ProposalPoolEmpty(address,uint256)`、`0xf6f9f8c8` `ProposalRewardRoundedToZero(address,uint256,uint256)` |
| `0x1392e03a` `MemberRewardUnavailable(address,uint256,uint256)` | 删除；新增 `0x8fde7ba3` `MemberHasNoVote(address,uint256,uint256)`、`0x86b94627` `MemberRewardPoolEmpty(address,uint256)`、`0xd632d7c1` `MemberRewardRoundedToZero(address,uint256,uint256)` |

命名取舍：

- `MaxSupplyBelowInitialSupply` 保留。条件是构造期配置关系（`maxSupply` 低于 `initialSupply`），不是运行期上限被突破；运行期上限已由 `MaxSupplyExceeded` 占位，改称 `InitialSupplyExceeded` 会被读成「初始供应已被突破」，与事实相反。按 `<Subject><State>` 命名，`error-standards.md §三` 的 `<Subject>Exceeded` 不适用。
- 取整类用过去分词 `RoundedToZero`，不用现在式（第三称单数形式与同接口载荷 `round` 在扫描时同形；`Round` 在本协议是专有量纲）。
- 同一入口内的三条新增错误按判定序声明（门槛 → 池 → 取整），与规格失败契约表的行序一致。

## 三、门禁结果

| 项 | 结果 |
| --- | --- |
| `forge build --force --deny warnings` | 通过 |
| `forge lint` | 零输出 |
| `forge test` | 511 passed / 0 failed |
| `check_errors.py --check` | 0 violations（registry 已重生成） |
| `check_doc_payloads.py` | 0 mismatches |
| `check_error_tests.py` | core 0 untested |
| `script/events/check-events.py` | 28 events；families / style / keys OK |
| `test/deploy_scripts_test.py` | 41 checks passed |

## 四、待办

1. `core` 提交后先推 `core`，再在 `action`、`group-chat` 更新子模块指针（先推被引用仓，再推父仓）；当前工作树未提交。
2. `action/lib/core`、`group-chat/**/lib/core` 仍指向旧 core，`action/out`、`group-chat/out` 的 ABI 产物需在指针更新后重建。
3. 部署脚本与 `action` 侧测试需在 core 指针更新后重跑全量。
