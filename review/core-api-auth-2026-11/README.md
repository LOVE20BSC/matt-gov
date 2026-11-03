# core/ 接口调用权限专项审查 · 2026-11

> 范围 `core/src/` 全部 8 个实现合约（3,050 行）+ 10 个自有接口，逐函数判定「谁能调、凭什么、能不能绕过」。
> 基线 `core@6fdd0f1`（工作树仅有未跟踪的 `test/audit/`，`src/` 干净）。
> 判据 `docs/dev-standards.md` §5.5（调用者校验）、§4.2（事件）、§5.4（初始化）；`docs/specs/core/01-common-rules.md`（主体与权限）。
> 产出：每个合约一份报告，共 8 份；本页是索引与横向结论。

## 一、一页结论

| 项 | 数值 |
| --- | --- |
| 合约 | 8 |
| ABI 函数合计 | 183（写 33 / 读 150） |
| 带鉴权 modifier 的写入口 | **15** |
| 无鉴权写入口 | 18（`init` 6 + OZ 标准 8 + 业务无许可 4） |
| 鉴权 modifier 定义 | 8 个（`Launch` 2、`Mint` 2，其余各 1） |
| 登记项 | 29（Medium 3 / Low 5 / Info 21） |
| 其中新增（不含既有审查已登记） | 26（Low 5 / Info 21） |
| 正面结论（不编号为发现） | 13 |
| 接口对账 | 8 个合约全部 **0 差异**（函数集、签名、mutability 全等） |
| 鉴权位置检查 | `check_caller_auth.py core/src` → `violations: 0` |

**最需要看的四条**

1. **鉴权面没有一处漏挂 modifier。** 33 个写入口里，15 个业务受限入口全部是 `only*` modifier 且为函数体首道判定；18 个无鉴权入口逐一有据：6 个 `init` 是规范明示的一次性入口，8 个是 OZ 标准 ERC20/ERC721 语义，4 个是「只能处分自己 / 只能推进已到期流程」的业务无许可入口。**没有找到「本应鉴权却没鉴权」的函数。**
2. **真正的风险集中在 6 个 `init`，而不在业务入口。** 它们无调用者限制（规范要求如此），但其中两个的权限后果是「换掉鉴权根」而非「换掉参数」：`Launch.init` 决定 `MEMBER_NFT_ADDRESS`（5 个合约的鉴权函数）、`MemberNFT.init` 决定身份定价源；`Stake.init` 则换掉资产出口的信任根（`ROUTER_ADDRESS` 会获得父币的 `forceApprove`）。这三处与既有审查的 DEP-01 同源，本报告不重复计数。
3. **两处「权限主体不是人」的设计需要被显式记录**：`Mint.mintProposalReward` 认的是**提案 target 地址**（可为 EOA、可与提案内容无关、不要求提案被执行）；`Launch.launchToken` 会把 `memberId` 交给**任意 distributor 合约**。两者都不是漏洞，但都是「授权主体可以把权益导向任意地址」的载体。
4. **`Stake.withdraw` 的 `delete` 落在两次外部调用之后**（STK-01）。当前不可利用，因为登记代币与 Pair 都没有接收回调；但这是全仓唯一一处 CEI 顺序不成立的地方，且安全性依赖外部前提而非合约内保证。把 `delete` 前移到 `_withdrawLiquidity` 之前即可消除，不改任何计算结果。

## 二、全局权限矩阵

| 合约 | 成员 NFT 持有人 | 指定合约 | 提案 target | 任何地址 |
| --- | --- | --- | --- | --- |
| `LOVE20Token` | — | `mint`（`MINTER`） | — | `burn`（仅自身余额） |
| `Launch` | `launchToken`、`mergeLaunchCount` | `addLaunchCount`（`MINT_ADDRESS`） | — | `init` |
| `MemberNFT` | — | — | — | `init`、`mint`、OZ 5 个 |
| `Phase` | — | — | — | `sync` |
| `Stake` | `stakeLiquidity`、`stakeBoost`、`unstake`、`withdraw`、`mergeStake` | — | — | `init`、`settleFees` |
| `Submit` | `submitNewProposal`、`submit` | — | — | `init` |
| `Vote` | `vote` | — | — | `init` |
| `Mint` | `mintGovReward`、`mintGovRewards` | — | `mintProposalReward` | `init` |

一致的判据只有一条：**处分成员资产、权益或业务状态时校验 `MemberNFT.ownerOf(memberId) == msg.sender`**（`01-common-rules.md`）。全仓 15 个受限入口里 12 个用这条；另 2 个是协议内部授权（`LOVE20Token.mint` 的 `MINTER`、`Launch.addLaunchCount` 的 `MINT_ADDRESS`），1 个是提案 target（`Mint.mintProposalReward`）。

## 三、33 个写入口的全量分类

### A. 成员 NFT 持有人（12）

| 合约 | 入口 | 鉴权 | 失败错误 |
| --- | --- | --- | --- |
| `Launch` | `launchToken` | `onlyMemberOwner(memberId)` | `NotMemberOwner` |
| `Launch` | `mergeLaunchCount` | `onlyMemberOwner(sourceMemberId)` | `NotMemberOwner` |
| `Stake` | `stakeLiquidity` | `onlyMemberOwner(memberId)` | `NotMemberOwner` |
| `Stake` | `stakeBoost` | 同上 | 同上 |
| `Stake` | `unstake` | 同上 | 同上 |
| `Stake` | `withdraw` | 同上 | 同上 |
| `Stake` | `mergeStake` | `onlyMemberOwner(sourceMemberId)` | 同上 |
| `Submit` | `submitNewProposal` | `onlyMemberOwner(memberId)` | 同上 |
| `Submit` | `submit` | 同上 | 同上 |
| `Vote` | `vote` | 同上 | 同上 |
| `Mint` | `mintGovReward` | 同上 | 同上 |
| `Mint` | `mintGovRewards` | 同上 | 同上 |

### B. 指定合约（2）

| 合约 | 入口 | 鉴权 | 主体来源 |
| --- | --- | --- | --- |
| `LOVE20Token` | `mint` | `onlyMinter` | 构造参数 `minter`，无 setter |
| `Launch` | `addLaunchCount` | `onlyMint` | `init` 参数 `mintAddress`，无 setter |

### C. 提案 target（1）

| 合约 | 入口 | 鉴权 | 主体来源 |
| --- | --- | --- | --- |
| `Mint` | `mintProposalReward` | `onlyProposalTarget(tokenAddress, proposalId)` | `Submit.proposalTarget` 动态解析，可为 EOA |

### D. 一次性初始化（6）

`Launch.init`、`MemberNFT.init`、`Stake.init`、`Submit.init`、`Vote.init`、`Mint.init`。全部只判 `initialized`，无调用者限制（`01-common-rules.md` 明示）。`Phase` 与 `LOVE20Token` 用构造器，无此入口。

### E. OZ 标准（8）

`LOVE20Token`：`transfer`、`approve`、`transferFrom`。
`MemberNFT`：`approve`、`setApprovalForAll`、`transferFrom`、`safeTransferFrom` ×2。
权限由 OZ 5.6.1 决定，本仓未覆写。

### F. 业务无许可（4）

| 合约 | 入口 | 为什么可以无许可 | 调用者的自由度 |
| --- | --- | --- | --- |
| `LOVE20Token` | `burn` | 只能烧 `msg.sender` 自己的余额 | 无（无 recipient 参数） |
| `MemberNFT` | `mint` | 任何人都能买身份，付费给协议（销毁） | 只能给自己铸、只能选名字 |
| `Phase` | `sync` | 每 Phase 一次、只按真实块/时间差计算 | 只能决定采样时点 |
| `Stake` | `settleFees` | 每 Phase 一次、必须达阈值、资产只流向 Pair 与销毁 | 无（无 recipient、无金额参数） |

**共同判据**：调用者没有任何可以「指向他人」的参数（recipient / memberId / 金额），且函数只推进一个已经成立的状态转换。这四条可以提炼成通则（见 G-03）。

## 四、跨合约信任图

```text
                       ┌─────────────┐
                       │  MemberNFT  │  ownerOf()  ← 12 个成员入口的鉴权函数
                       └──────┬──────┘
          ┌───────────┬───────┼────────┬──────────┐
          │           │       │        │          │
       Launch       Stake   Submit    Vote       Mint
          │           │       │        │          │
          │           │       └────────┴──────────┤
          │           │        读票权 / 推举状态    │
          │           └──── 读票权 / 加速快照 ─────┘
          │
          ├── createPair / getPair ──→ UniswapV2Factory
          ├── new LOVE20Token ───────→ LOVE20Token(MINTER = Mint)
          ├── MemberNFT.init ────────→ MemberNFT（初始化代理）
          └── onTokenLaunched ───────→ ILaunchDistributor（实现方校验调用者）

       Mint ── addLaunchCount ──→ Launch（onlyMint）
       Mint ── mint ────────────→ LOVE20Token（onlyMinter）
       Mint ── proposalTarget ──→ Submit（鉴权源）
       Stake ─ swap/burn ───────→ Router / Pair / LOVE20Token
```

**三条闭合的授权链**（部署期绑定，运行期不可换）：

| 授权方 | 被授权方 | 绑定位置 | 若错绑的后果 |
| --- | --- | --- | --- |
| `LOVE20Token.MINTER` | Mint | 构造参数（`Launch._createToken`） | 代币无人可铸，奖励停摆 |
| `Launch.MINT_ADDRESS` | Mint | `Launch.init` | 发射次数无法增加 |
| `Submit.proposalTarget` | 提案 target | 每提案动态 | 提案奖励被非预期地址领走 |

## 五、共性问题

### G-01（Medium，与 DEP-01 同源，不新增计数）6 个 `init` 的抢跑面，其中两处直接换掉鉴权根

- `Launch.init` → `MEMBER_NFT_ADDRESS`：**5 个合约的成员鉴权函数被决定**；同时决定首币参数与 `MINT_ADDRESS`。
- `MemberNFT.init` → `LOVE20_TOKEN_ADDRESS`：身份定价源与名称前缀；还会阻断 `Launch.init`（后者代调 `init`）。
- `Stake.init` → `ROUTER_ADDRESS`：换掉的是**资产出口**的信任根——合约会对 Router 做父币 `forceApprove`，恶意 Router 可直接划走；而非鉴权根。
- `Submit.init` / `Vote.init` / `Mint.init` → 决定依赖地址与比例参数（`SUBMIT_MIN_RATIO`、奖励三比例），后果是「治理门槛与分配比例被决定」，不改变鉴权根。
- 兜底全在部署期：`DeployCore.s.sol` 的绑定检查段（`L342`、`L365-366`、`L383-384`、`L403-405`、`L410-413`）+ `21_check.sh` 独立复核。规范 §5.4/§5.7 明确把这条划给部署脚本，合约侧不校验是**符合分工**的。
- 报告中的落点：`02-launch.md` LCH-01、`03-membernft.md` NFT-01、`05-stake.md`（`init` 段）、`08-mint.md` MNT-05。

### G-02（Info）业务层不认 ERC721 授权，`approve`/`setApprovalForAll` 的受托方不能代为操作

- 12 个成员入口一律 `ownerOf(memberId) == msg.sender`，不使用 `isApprovedForAll`/`getApproved`。
- 后果：被授权方只能转移 NFT（连同解锁倒计时、未领奖励、发射次数一起转移），不能代为 stake/vote/submit/claim。多签或托管合约必须自己作为 `msg.sender` 调用。
- 规格已写死这条（`01-common-rules.md`「钱包地址仅作控制者或调用者」），但接口不写 NatSpec（§4.1），集成方只能从规格得知。建议在 `01-common-rules.md` 补一句「ERC721 授权不延伸到业务入口」。
- 落点：`03-membernft.md` 第四节「OZ 标准入口 — 授权只覆盖转移，不覆盖业务」。

### G-03（Info）四个业务无许可入口缺一条通则

`LOVE20Token.burn`、`MemberNFT.mint`、`Phase.sync`、`Stake.settleFees` 的「为什么不需要鉴权」目前分散在四个模块规格里，判据其实可以统一为两条：

1. 调用者没有任何指向他人的参数（无 recipient / memberId / 金额）；
2. 函数只推进一个已成立的状态转换，或只处分调用者自己的资产。

建议在 `01-common-rules.md` 增「无许可入口」一节，列全这四处并写明上述判据。这样新增无许可入口时有可核对的规则，而不是逐个论证。

### G-04（Info）5 个 `init` 无事件，规格未写明理由

`MemberNFT.init`、`Stake.init`、`Submit.init`、`Vote.init`、`Mint.init` 都不发事件（`Launch.init` 发 `GenesisTokenCreated`，因为首币创建是业务事件）。§4.2 允许 `init` 例外，但要求「在对账文档写明理由」。建议在各模块规格的 `init` 段落统一补一句「绑定结果由部署 check 与 `initialized()` 观测，故不发事件」。

### G-05（Info）`memberId` 不存在时的错误不是 `NotMemberOwner`，而是 OZ 的 `ERC721NonexistentToken`

- 所有 `ownerOf(memberId)` 鉴权在 `memberId` 未铸造时由 OZ revert，选择器不是本合约的 `NotMemberOwner`。
- 与 §5.5「非授权方只拿到鉴权错误」字面冲突，但 `memberId` 由 ERC721Enumerable 公开可枚举，无信息增量。
- `06-vote.md` 已单独声明这条；其余四处（`Launch`、`Stake`、`Submit`、`Mint`）未声明。建议提升到 `01-common-rules.md` 一次说清。
- 落点：`02-launch.md` LCH-03、`06-submit.md` SUB-04。

### G-06（Info）跨合约错误穿透

`Mint.onlyProposalTarget` 对不存在的提案拿到的是 `Submit.ProposalNotFound`；`Stake._hasUsedStakeRights` 依赖 `Vote.SUBMIT_ADDRESS()`，Vote 未初始化时是空 revert。链下分类需要同时识别「本合约错误」与「上游穿透错误」。建议在各合约错误表里标出「可能来自上游」的行。

### G-07（Info）`Mint.mintGovReward` 可收窄为 `external`

`public` 但无内部调用（`mintGovRewards` 调的是私有实现 `_mintGovReward`）。改 `external` 不改 ABI、不改行为，只收窄可见性。属可选的接口面整理。

### G-08（接口契约）两个回调接口的鉴权责任完全在实现方

core 有两个**没有实现**的接口，它们只被 core 调用，不被 core 实现：

| 接口 | 调用方 | 实现方必须校验 | 已核落的实现 |
| --- | --- | --- | --- |
| `ILaunchDistributor.onTokenLaunched` | `Launch.launchToken`（`L150`） | `msg.sender == Launch` | 本仓库无实现；`action` 仓未见该接口 |
| `IProposalTarget.onProposalCreated` / `onProposalSubmitted` | `Submit._callProposalCreated` / `_callProposalSubmitted` | `msg.sender == Submit` | `action/ActionTarget.sol:423`、`471` 的 `onlySubmit` |
| `IProposalTarget.onProposalVoted` | `Vote._vote`（`L286`） | `msg.sender == Vote` | `action/ActionTarget.sol:500` 的 `onlyVote` |

core 侧不校验是正确分工（core 不可能知道有哪些实现），但这意味着**任何一个新实现的 target 只要漏掉 `msg.sender` 校验，任何人都能伪造「提案已创建/已推举/已投票」的回调，直接篡改该 target 的业务状态**——这与 core 内任何权限缺陷同级。

建议：把这条写成 `01-common-rules.md` 的 MUST（「实现 `IProposalTarget` / `ILaunchDistributor` 的合约，每个回调入口的第一道判定必须是调用方地址校验」），并在 `IProposalTarget`/`ILaunchDistributor` 的实现侧测试里各放一条「非 core 调用必须回滚」的负例。

## 六、发现索引

### 按级别

| 级别 | 编号 | 一句话 |
| --- | --- | --- |
| Medium（同源重复） | LCH-01 | `Launch.init` 抢跑 = 替换 5 个合约的鉴权根 |
| Medium（同源重复） | NFT-01 | `MemberNFT.init` 抢跑 = 夺取定价权并阻断 Launch |
| Medium（同源重复） | MNT-01 | 奖励池无独立准备入口，首个领取者定池 |
| Low | LCH-02 | `launchToken` 无重入锁，distributor 回调可再次发射（不越权） |
| Low | NFT-02 | `MemberNFT.init` 未校验首币有代码 |
| Low | PHS-01 | `sync` 无许可 + 单次配额，抢跑者可决定本轮是否校准 |
| Low | STK-01 | `withdraw` 的 `delete` 在外部调用之后，安全性依赖代币无回调 |
| Low | MNT-02 | 提案奖励与「提案是否被执行」解耦 |
| Info | TOK-01 | `MINTER`/`PARENT_TOKEN_ADDRESS` 未用 `immutable` |
| Info | TOK-02 | `burn` 的无许可边界应写进规格 |
| Info | TOK-03 | `NotMinter` 不带剩余额度（正面样本） |
| Info | LCH-03 | 目标 `memberId` 不存在时抛 OZ 错误 |
| Info | LCH-04 | `MINT_ADDRESS` 与代币 `MINTER` 无交叉校验 |
| Info | NFT-03 | `mint` 无锁但 CEI 成立 |
| Info | NFT-04 | `normalizeName` 只折叠 ASCII，接口无声明 |
| Info | NFT-05 | `init` 无事件且未写理由 |
| Info | PHS-02 | `sync` 静默返回不发事件，且 `_lastSyncPhase` 无 getter |
| Info | STK-02 | `stakeBoost` 未显式拒绝 Round 0（靠间接条件不可达） |
| Info | STK-03 | `_hasUsedStakeRights` 的信任链经过 `Vote.SUBMIT_ADDRESS()` |
| Info | SUB-01 | `submit` 可推举他人提案，接口层无提示 |
| Info | SUB-02 | `ProposalBody.target` 是未来提案奖励的收款权载体 |
| Info | SUB-03 | 回调可重入，但被 `MemberAlreadySubmitted` 拒绝 |
| Info | SUB-04 | `Mint` 的存在性错误穿透（同 G-06） |
| Info | VOT-01 | `vote` 无锁但重入不突破票上限 |
| Info | VOT-02 | 不校验 `tokenAddress` 登记，靠 Stake 返回 0 兜底 |
| Info | VOT-03 | `voterBoost` 快照与解锁的时序由 Stake 兜住 |
| Info | MNT-03 | `recipient` 任意 + NFT 可转移 = 临时持有人可截取 |
| Info | MNT-04 | `mintGovReward` 可收窄为 `external`（同 G-07） |
| Info | MNT-05 | `init` 从 Vote 派生 `PHASE_ADDRESS`，顺序错则永久不可用 |

### 正面结论（13，不编号为发现）

| 编号 | 内容 |
| --- | --- |
| LCH-05 | 发射次数的三个写入口互不重叠，没有第四个改写路径 |
| PHS-03 | `Phase` 用构造器，无抢跑面 |
| PHS-04 | `assert` 兜住内部索引不变量 |
| STK-04 | 5 个成员入口的鉴权全部首道，且有「先鉴权后参数」负例 |
| STK-05 | `settleFees` 四道闸门使无许可不产生提取面 |
| STK-06 | `_realizeFees` 在外部调用前写 `_lastSettlePhase`，堵住 Router 重入 |
| SUB-05 | 鉴权先于存在性有独立负例 |
| SUB-06 | 票权门槛读当前轮，历史轮不可补推 |
| VOT-04 | 鉴权先于票上限有负例（两个错误都可报时报鉴权） |
| VOT-05 | 票上限每批只读一次 |
| VOT-06 | `Vote.init` 无外部依赖，无隐式顺序约束 |
| MNT-06 | `onlyProposalTarget` 的错误载荷不泄漏额外信息 |
| MNT-07 | 发射次数的产生只有一条权限链 |

## 七、与既有审查的关系

仓库里已有 `review/core-review-plan-2026-11/`（分层安全审查，22 条登记项）。本次不重复计数：

| 本报告编号 | 既有编号 | 关系 |
| --- | --- | --- |
| LCH-01、NFT-01 | DEP-01 | 同一根因（`init` 无调用者限制）；本报告只补「权限后果 = 鉴权根被替换」 |
| MNT-01 | MNT-01 | 同一现象（池子由首个 mint 时点决定）；本报告只补「权限上没有中立触发者」 |

本次**新增** 26 条（Low 5 / Info 21），全部是权限面、接口面与文档口径的问题，不含资金安全结论。

## 八、方法与复现

```bash
export PATH="$HOME/.foundry/bin:$PATH"

# 1. 鉴权位置与 modifier 形状（dev-standards §5.5）
cd /Users/BigPolarBear/Documents/github/LOVE20BSC
python3 matt-gov/script/check_caller_auth.py core/src
# → violations: 0

# 2. ABI 对账：实现 vs 自有接口（函数集、签名、mutability）
cd core
for c in LOVE20Token:ILOVE20Token Launch:ILaunch MemberNFT:IMemberNFT Phase:IPhase \
         Stake:IStake Submit:ISubmit Vote:IVote Mint:IMint; do
  impl=${c%%:*}; iface=${c##*:}
  diff <(forge inspect $impl abi --json | jq -S '[.[]|select(.type=="function")|{name,inputs:[.inputs[].type],stateMutability}]|sort_by(.name)') \
       <(forge inspect $iface abi --json | jq -S '[.[]|select(.type=="function")|{name,inputs:[.inputs[].type],stateMutability}]|sort_by(.name)') \
    && echo "$impl OK"
done
# → 8 个合约全部 OK（0 差异）

# 3. 函数清单与 modifier（本报告所有表格的来源）
python3 matt-gov/review/core-api-auth-2026-11/evidence/auth_scan.py
# 完整输出见 evidence/output.txt
```

补充说明：

- 本报告只做静态审查，未运行新的 PoC；资金安全结论以既有审查为准。
- 读面（150 个只读入口）逐条确认「无权限、无事件要求」，未逐条列分析；例外是带存在性断言的 `proposalRewardByProposalId` / `govRewardByMemberId` / `proposalTarget` / `proposalInfosByProposalIds`，已在对应报告标注。
- `check_caller_auth.py` 只校验「调用者校验是否写在 `only*` modifier 里」，不证明「每个写入口都有鉴权来源」——后者由本报告的人工逐入口判定补齐（33 个写入口全覆盖）。

## 九、目录

```text
README.md              本页：横向结论、全局矩阵、共性、索引
01-love20token.md      LOVE20Token（5 写 / 14 ABI）
02-launch.md           Launch（4 写 / 25 ABI）
03-membernft.md        MemberNFT（7 写 / 31 ABI）
04-phase.md            Phase（1 写 / 11 ABI）
05-stake.md            Stake（7 写 / 31 ABI）
06-submit.md           Submit（3 写 / 22 ABI）
07-vote.md             Vote（2 写 / 22 ABI）
08-mint.md             Mint（4 写 / 27 ABI）
evidence/
  auth_scan.py         函数与 modifier 静态提取（生成各报告的入口表）
  abi_diff.py          实现 ABI 与接口 ABI 的逐签名对账
  output.txt           上述两个脚本 + check_caller_auth 的实际输出
```
