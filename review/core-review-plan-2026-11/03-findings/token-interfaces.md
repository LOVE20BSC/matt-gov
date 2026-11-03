# Token / 接口面

`LOVE20Token` 59 行、2,384 字节；接口面 10 个文件 1,069 行。这一页只有 Info，但有一条**正向验证**值得留档：接口与实现逐条对齐，没有幽灵声明。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| TOK-01 | Info | `burn` 对任何人开放（烧自己的）；两个本可 immutable 的状态变量；全仓无 rescue |
| TOK-02 | Info | 8 组接口与实现的 ABI 面逐条 diff：接口声明的全部实现，无遗漏、无多余函数 |

---

## TOK-01 · 代币面的三个边界

| 字段 | 值 |
| --- | --- |
| 单元 | T1（`LOVE20Token:1-59`） |
| 文件:行 | `LOVE20Token:42-58`、`:8-10` |
| 函数/变量 | `mint` / `burn` / `MINTER` / `PARENT_TOKEN_ADDRESS` / `MAX_SUPPLY` |
| 类别 | 权限 / 加固 |
| 严重度 | Info |
| 攻击者画像 | 任何持有人（只能烧自己的） |
| 前置条件 | 持有代币 |
| 触发序列 | `burn(amount)` → `_burn(msg.sender, amount)`，无权限检查 |
| 影响 | 自愿销毁；不影响他人余额，也不影响 `MAX_SUPPLY − totalSupply` 之外的任何账本 |
| 设计依据 | `Stake` 与 `MemberNFT` 都需要「合约烧自己余额」的能力（`Stake:831`、`MemberNFT:86`），开放 `burn` 是最省接口的做法 |
| 证据等级 | E1 |
| 证据路径 | 静态 |
| 置信度 | 高 |
| 状态 | 已关闭 |

三点具体结论：

1. **`burn` 开放是必要的**，但代价是任何人都能把自己的余额烧掉。因为供应只减不增（`mint` 只有 `MINTER`），这不构成攻击面。
2. **`MINTER` 与 `PARENT_TOKEN_ADDRESS` 在构造函数后再无写入点**，slither 报 `state-variables-that-could-be-declared-immutable`。这是 gas/字节码层面的建议，不是安全性问题；改成 `immutable` 会改变存储布局（`MAX_SUPPLY` 已经是 `immutable`，所以本合约本来就没有依赖存储槽的外部读取）。
3. **全仓没有 rescue / sweep**。转错到 `Stake`、`Launch`、`Vote`、`Submit`、`Mint`、`MemberNFT` 的 ERC20 永久滞留。这是「无后门」的代价，不是缺陷——但部署文档应当写清楚：误转不可找回。

唯一需要小心的是第 3 点在 `Stake` 上的具体形态：合约余额被 `Boost 押金` 占用，任何「按余额退款」的实现都会侵占押金。当前实现按 `member.boostShares` 记账（不从余额反推），所以即使有人误转，押金也不会被当成分红。这条在 `STK-03` 的测试里被间接验证（结算后 `balanceOf(stake) ≥ Σ boostShares`）。

---

## TOK-02 · 接口与实现的 ABI 面闭合

| 字段 | 值 |
| --- | --- |
| 单元 | T1（`interfaces/**`） |
| 文件:行 | `src/interfaces/*.sol` 全量 vs `out/*.json` |
| 函数/变量 | 8 组：`IStake`、`IMint`、`ILaunch`、`IMemberNFT`、`ISubmit`、`IVote`、`IPhase`、`ILOVE20Token` |
| 类别 | 接口一致性 |
| 严重度 | Info |
| 攻击者画像 | 无（集成方） |
| 前置条件 | — |
| 触发序列 | 取 `out/<C>.sol/<C>.json` 与 `out/<I>.sol/<I>.json`，按 `(type, name, inputs, outputs, stateMutability)` 归一化后做双向差集 |
| 影响 | 无：**接口声明的每一条都在实现里** |
| 设计依据 | core 仓的接口是唯一来源（下游 `action`/`group-chat` 直接引用） |
| 证据等级 | E1（可复现的命令见下） |
| 证据路径 | `06-tool-crosscheck.md` 的 ABI 对账节 |
| 置信度 | 高 |
| 状态 | 已关闭 |

### 结果

| 合约 | 接口条目 | 实现条目 | 接口有实现无 | 实现有接口无 |
| --- | --- | --- | --- | --- |
| `Stake` / `IStake` | 57 | 58 | **0** | `SafeERC20FailedOperation`（OZ 库错误） |
| `Mint` / `IMint` | 40 | 40 | **0** | **0** |
| `Launch` / `ILaunch` | 49 | 49 | **0** | **0** |
| `MemberNFT` / `IMemberNFT` | 40 | 52 | **0** | constructor + 10 个 OZ `ERC721*` 错误 + `SafeERC20FailedOperation` |
| `Submit` / `ISubmit` | 39 | 39 | **0** | **0** |
| `Vote` / `IVote` | 32 | 32 | **0** | **0** |
| `Phase` / `IPhase` | 14 | 15 | **0** | constructor |
| `LOVE20Token` / `ILOVE20Token` | 30 | 31 | **0** | constructor |

「实现有接口无」的额外条目全部是构造函数与 OZ 继承来的错误类型，不需要出现在接口里；`SafeERC20FailedOperation` 通过 `using SafeERC20 for IERC20` 进入 ABI，属于库的传播，不影响调用方。

**没有找到「接口声明了但实现没有」的条目**——这是最容易在下游集成时炸的一类问题（下游按接口编码，实现缺函数时调用直接落到 fallback 或 revert），本轮为零。

### 命名口径的抽查

计划 §4.1 要求按 `(type,name,inputs,outputs,stateMutability)` 排序 diff，顺带核对了三条项目口径：

| 口径 | 抽查结果 |
| --- | --- |
| 分页统一 `(offset, limit, reverse) → (列表, totalCount)` | `Launch.tokens:214`、`Launch.childTokens:222`、`Submit.proposalIds:142`、`Submit.submitInfos:184`、`Vote.votedProposalIds:153`、`Vote.voterIdsByProposalId:161`、`MemberNFT.holders:148`、`Phase.observations:73` —— 8/8 一致 |
| 不设独立 `*Count` 入口 | 无 `*Count()` 形式的分页入口；`totalCount` 只作为返回值出现 |
| `By<Key>` 与入参同名 | `proposalInfosByProposalIds(requestedProposalIds)`（`Submit:172`）、`voteAmountsByMemberIdByProposalIds(proposalIds)`（`Vote:188`）—— 2/2 一致 |
| `round`/`rounds` 在 `memberId` 之前 | `mintGovReward(token, round, memberId, recipient)`、`mintGovRewards(token, rounds, memberId, recipient)` —— 2/2 一致 |
