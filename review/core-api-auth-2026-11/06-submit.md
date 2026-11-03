# Submit 接口调用权限审查

> 对象 `core/src/Submit.sol`（339 行）
> 接口 `core/src/interfaces/ISubmit.sol`（176 行）
> 基线 `core@6fdd0f1`；审查日期 2026-11-03
> 判据 dev-standards §5.5、§4.2；`specs/core/01-common-rules.md`、`specs/core/05-submit.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 22（写 3 / 读 19） |
| 带鉴权 modifier | 2（`onlyMemberOwner`） |
| 无许可写入口 | 1（`init`） |
| 发现 | 4 条：全部 Info，另有 2 条正面结论 |
| 接口对账 | 22 vs 22，**0 差异** |

一句话：**两个业务写入口都是 `onlyMemberOwner` 首道判定，权限链干净；真正的权限设计点是 `submit` 允许推举**他人**的提案（花自己的票权），以及 `ProposalBody.target` 直接把「未来提案奖励的领取权」授予任意地址。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 成员 NFT 持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `submitNewProposal`、`submit` |
| 无 | `if (initialized) revert` | `init` |
| 无 | — | 19 个只读入口 |

资格校验与身份校验分离：`onlyMemberOwner` 判「你是不是这个 `memberId` 的主人」，`_checkSubmitPower` 判「你有没有足够的当前轮票权」。两者是「与」关系，顺序是鉴权在前、资格在后。

## 三、入口清单

### 写入口

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `init(address,address,address,uint256)` | 无（一次性） | `if (initialized) revert` | 是 | **无** |
| `submitNewProposal(address,uint256,ProposalBody)` | `memberId` 持有人 | `onlyMemberOwner(memberId)` `L98` | 是 | `ProposalCreated` → `ProposalSubmitted` |
| `submit(address,uint256,uint256)` | `memberId` 持有人 | 同上 | 是 | `ProposalSubmitted` |

### 只读入口（19）

配置 getter 9：`STAKE_ADDRESS`、`PHASE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`SUBMIT_MIN_RATIO`、`MAX_TITLE_LENGTH`、`MAX_DETAILS_LENGTH`、`MAX_TARGET_DATA_BYTES`、`MAX_TARGET_DATA_COUNT`、`initialized`。

查询 10：`currentRound`、`canSubmit`、`isSubmitted`、`proposalIds`、`proposalIdsByAuthor`、`proposalTarget`、`proposalInfosByProposalIds`、`submitInfos`、`proposalIdBySubmitterId`、`submitterIdByProposalId`。

读面边界：`proposalTarget` / `proposalInfosByProposalIds` 对未分配 ID 回滚 `ProposalNotFound(proposalId)`；`proposalIds` / `submitInfos` 分页语义与 `Phase.observations` 一致。

## 四、逐入口判定

### `submitNewProposal` — 创建与推举一笔完成

- 校验顺序：`onlyMemberOwner` → 提案体（标题非空/长度、Target Data 数量与字节上限、target 非零、Callback 模式要求 target 有代码）→ 票权门槛 → 创建 → 推举 → 创建回调 → 推举回调。
- 权限边界：`memberId` 的所有权决定「以谁的名义创建」；`_checkSubmitPower` 决定「能不能花掉本轮名额」。**两者用同一个 `memberId`**，不能以 A 的身份创建、用 B 的票权。
- 票权门槛：`validGovVotes(token, currentRound, memberId) >= ceil(totalValidGovVotes × SUBMIT_MIN_RATIO / 1e18)`，且 `totalValidGovVotes != 0`（否则 `NoGovVotes`）。读的是 Stake 的当前轮账本，不是历史快照。
- 名额：`_submits[token][round]` 长度上限 `SUBMIT_ROUND_LIMIT = 1000`；同一 `memberId` 每轮只能推举一次（`MemberAlreadySubmitted`）；同一 `proposalId` 每轮只能被推举一次（`ProposalAlreadySubmitted`）。

### `submit` — 推举别人的提案

- 只校验调用者的 `memberId` 所有权与票权，**不校验 `proposalId` 的作者是否是 `memberId`**。
- 这是规格明示的设计（`05-submit.md`：「推举者可以是作者以外的人」）。权限上的含义是：任何满足票权门槛的成员，都可以选择把本轮唯一的名额花在任意一个已存在的提案上。被推举者不需要同意，也无法拒绝。
- 反过来的限制同样重要：提案作者**不能**自己重复推举（`MemberAlreadySubmitted`），也**不能**替别人推举（`onlyMemberOwner`）。所以「名额」的主体始终是签名者本人。

### 回调出口

`_callProposalCreated` 与 `_callProposalSubmitted` 在推举状态写完之后调用（`L115-117`），`Callback` 模式才触发。回调目标 `ProposalBody.target` 由提案创建者指定，`NoCallback` 时可为 EOA，`Callback` 时要求有代码。

`onProposalCreated(tokenAddress, proposalId, targetData)` 与 `onProposalSubmitted(tokenAddress, proposalId, memberId, targetData)` 的**调用者校验责任在实现方**：core 侧不校验 target 是否信任 Submit。本仓接口 `IProposalTarget` 只声明签名，`action/ActionTarget.sol:423/471` 用 `onlySubmit` 校验，责任落位正确（见 README §四「回调契约」）。

## 五、发现

### SUB-01（Info）`submit` 的「推举他人提案」应在接口层留一句语义

- 证据：`submit` 只做 `_checkExistingProposal` + `_checkSubmitPower`（`L121-130`），不比较 `_proposals[token][proposalId-1].head.author` 与 `memberId`。
- 判定：设计如此，且 `05-submit.md` 已写明。但接口文件不写 NatSpec（§4.1），链上集成方若假设「submit 只能推举自己的提案」会误判错误面（实际不会报错，会成功）。
- 建议：不改代码；在 `05-submit.md` 的「两个写入口」段落把「推举者可以是作者以外的人」提到接口摘要位置，或在 `docs/specs/core/README.md` 的入口索引里标注。

### SUB-02（Info）`ProposalBody.target` 决定未来提案奖励的领取权，且与提案内容无绑定

- 证据：`_createProposal` 存 `body.target`（`L256-265`）；`Mint.onlyProposalTarget` 用 `ISubmit.proposalTarget(token, proposalId)` 取回的 `target` 做鉴权（`Mint.sol:175-184`）。
- 含义：提案创建者可以把 `target` 设为任意地址（`NoCallback` 时可为 EOA），该地址在该提案票数达标后即可调用 `mintProposalReward` 领取提案奖励，并指定任意 `recipient`。**协议不校验 target 是否与提案主题相关，也不校验提案是否被执行。**
- 判定：这是「提案激励按票数分配」的设计结果，不是权限缺陷；但它使 `target` 成为一个**可自由指定的收款权载体**。投票者若只按标题投票，等于把一个收款权授予了创建者指定的人。
- 建议：在 `05-submit.md` 的 `ProposalBody` 表格里为 `target` 补一句「同时是提案奖励的唯一领取主体」；`07-mint.md` 的 `mintProposalReward` 段落已写「提案 Target 是地址型角色」，两处口径应互引。

### SUB-03（Info）回调可重入，但同一 `memberId` 的重入必然被 `MemberAlreadySubmitted` 拒绝

- 证据：`_submitByProposalId` 写完后才调 `_callProposalCreated` / `_callProposalSubmitted`（`L113-117`）；推举状态包含 `_submitInfoBySubmitterId[token][round][memberId]`。
- 判定：target 回调里重入 `submitNewProposal` 时 `msg.sender` 不变、`memberId` 相同，第一次推举已写入，第二次必然回滚 `MemberAlreadySubmitted`。若回调合约持有**另一个** `memberId`，那是它自己的身份，属合法调用。
- 结论：无 `nonReentrant` 但不可重入成功，与 `Vote.vote` 的结构相同（见 07-vote.md）。

### SUB-04（Info）跨合约错误面：`Mint.onlyProposalTarget` 对不存在的提案抛 `ProposalNotFound`

- 证据：`Mint.onlyProposalTarget` 调 `ISubmit.proposalTarget`（`Mint.sol:179`），后者对未分配 ID 回滚 `ProposalNotFound(proposalId)`（`Submit.sol:270-275`）。
- 影响：任何人调用 `Mint.mintProposalReward` 时，若 `proposalId` 不存在，拿到的是 `ProposalNotFound` 而不是 `NotProposalTarget`。错误选择器跨合约「穿透」，链下分类需同时识别两种来源。
- 判定：不构成信息泄漏（`proposalInfosByProposalIds` 本就公开），但违反 §5.5「非授权方只拿到鉴权错误」的字面要求。建议在 `01-common-rules.md` 统一声明「跨合约读取的存在性错误会穿透到调用方」，或在 `07-mint.md` 的错误表里补这一行。

### SUB-05（正面结论）鉴权先于存在性有负例钉死

- 证据：`test/Submit.t.sol:298-299` 的 `testSubmitChecksAuthBeforeProposalExistence` 断言：`proposalId` 不存在时，非持有人拿到的是 `NotMemberOwner(2)`。
- 判定：这是 §5.5 顺序要求的直接验证。`Launch`、`Stake`、`Submit` 三处都有「鉴权先于参数/存在性」的独立用例，其中本合约这条最直接地把「提案不存在」作为被遮蔽的条件。

### SUB-06（正面结论）票权门槛读当前轮，历史轮不可补推

- 证据：`_submitPower` 用 `currentRound()`（`L78`），`validGovVotes` 对未开始轮回滚 `RoundNotStarted`。
- 判定：无法用历史票权推举当前轮提案，也无法预支未来轮票权。权限与轮次绑定。

## 六、核对证据

```text
$ forge inspect Submit abi --json              # 22 functions；impl-only 0 / iface-only 0
$ python3 matt-gov/script/check_caller_auth.py core/src
violations: 0
```

鉴权负例：`test/Submit.t.sol:243`、`275`（`submitNewProposal` / `submit` 非持有人）、`299`（鉴权先于存在性）、`515`（转移后原持有人）。

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 读 | `Phase.currentPhase` | `currentRound()` |
| 读 | `MemberNFT.ownerOf` | 鉴权函数 |
| 读 | `Stake.validGovVotes` / `totalValidGovVotes` | 票权门槛 |
| 写 | `Phase.sync()` | 每轮首个推举自动同步一次（`L321`） |
| 写 | `IProposalTarget.onProposalCreated` / `onProposalSubmitted` | 回调出口；实现方须校验 `msg.sender == Submit` |
| 被读 | `Mint.onlyProposalTarget` → `Submit.proposalTarget` | **Mint 的提案奖励鉴权以本合约为唯一来源** |
| 被读 | `Vote._vote` → `Submit.isSubmitted` | 投票前置条件 |
| 被读 | `Stake._hasUsedStakeRights` → `proposalIdBySubmitterId` | 解锁前置条件 |
