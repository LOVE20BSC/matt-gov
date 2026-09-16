# Submit 接口审查报告

**日期**：2026-09-15  
**审查范围**：[ISubmit.sol](../../interfaces/core/ISubmit.sol) 接口定稿  
**审查原则**：尽可能保留旧代码接口，除非业务已删除；命名符合新代码规范（Action → Proposal）

---

## ✅ 审查结论：通过

接口已完成全部必要修复与改造，满足 BSC 迁移要求。

---

## 📋 结构与命名定稿

### 结构体

| 新 | 旧 | 状态 |
|--------|-----|------|
| `ProposalHead { id, author, createAtBlock }` | `ActionHead` | 改名+改参（`author` 改 `memberId`） |
| `ProposalBody { title, details, target, targetMode, targetData }` | `ActionBody` | 改名+改参，7 字段 → 5 字段 |
| `ProposalInfo { head, body }` | `ActionInfo` | 改名 |
| `SubmitInfo { submitterId, proposalId }` | `ActionSubmitInfo` | 改名+改参 |
| `enum TargetMode { NoCallback, Callback }` | 无 | 新增 |

- `ProposalBody` 是**创建者提供的全部字段**，既是 `submitNewProposal` 的入参也是 `ProposalInfo` 的组成，不另立 `Params` 结构。
- `title` 非空、`details` 可空、`target` 非零、`targetMode` 二选一、`targetData` 可选且不透明。
- 旧 `ActionBody` 的 `minStake` 删除（BSC 删除统一 Join 模块，门槛逻辑移 Action 层各 Executor），其余行动专属字段由 `targetData` 承载。

### 函数改名

| 新 | 旧 | 说明 |
|--------|-----|------|
| `proposalInfosByIds(proposalIds[])` | `actionInfo()` | 去掉单条入口，改按显式 ID 批量，返回 `ProposalInfo[]` |
| `proposalIdBySubmitter()` | `submitInfoBySubmitter()` | 返回值收为 `proposalId` |
| `submitterIdByProposalId()` | `submitInfo()` | 返回值收为 `submitterId`；与上一条互为逆，两个方向按同样方式改名 |
| `proposalIds()` | `actionsCount()` + `actionsAtIndex()` | 合并为分页，只回 `proposalIdList` |
| `proposalIdsByAuthor()` | `authorActionIdsCount()` + `authorActionIdsAtIndex()` | 合并为分页，只回 `proposalIdList` |
| `submitInfos()` | `actionSubmitsCount()` + `actionSubmitsAtIndex()` | 合并为分页，回完整 `SubmitInfo` 记录 |

`submitNewProposal()`（旧 `submitNewAction`）与 `proposalInfosByIds(proposalIds[])` 为新增/改名，见下。

`submitNewProposal()` 沿用旧代码「创建后立即推举」的语义：旧 `submitNewAction` 内部就是 `_createAction` + `_submitByActionId`，新入口在同一笔内先创建再推举，先发 `ProposalCreated` 后发 `ProposalSubmitted`，回调按同一顺序。两个入口共用「每人每轮一个」「每提案每轮一次」两条名额约束，创建不是免额度的旁路。

## 🔍 读取面分三类

| 类 | 函数 | 用途 |
|--------|------|------|
| 分页 | `proposalIds`、`proposalIdsByAuthor`、`submitInfos` | 按 `(offset, limit, reverse)` 遍历，返回当页与真实总数 |
| 按 id 批量取详情 | `proposalInfosByIds(tokenAddress, proposalIds[])` | 按显式 ID 批量读，返回与入参下标一一对应 |
| 单键 | `isSubmitted`、`proposalIdBySubmitter`、`submitterIdByProposalId` | 按键取布尔或单个标量 |

不设单条详情入口：读一条传单元素数组，不再有只差一个字母、返回值却是两种东西的近名对。

**为什么 `proposalIds` 只回标识而 `submitInfos` 回记录**：判据是页内每一项是否定长。`ProposalBody` 的 `title`/`details`/`targetData` 都不设长度上限，页内成员又由别人决定，一页里落进一条大 `targetData` 就能把整页顶到调用方 gas 上限之上，且无法跳过——只能反复调小 `limit` 试探；`SubmitInfo` 全为 `uint256`，任意一页的体量都与 `limit` 成正比。旧 `actionsAtIndex`/`actionSubmitsAtIndex` 直接在枚举里回完整结构体，这条路被撤掉。

**批量入口为什么不设长度上限**：只读、无状态写，批量大小与返回体量都由调用方自己选，超限只是调用方自己的 out-of-gas，减小批量即可重试，不会把代价转嫁给别人。[复查清单](../../docs/review-guide.md) 的「数组、批量参数和分页参数有最大边界」约束的是合约替调用者执行并写入状态的批量，与该条不冲突。

按显式 ID 批量读时，未分配过的 ID 一律回滚 `ProposalNotFound(proposalId)`，不静默补空：位置对齐是批量查询的语义基础，补空会让调用方无法判断缺失的是哪一项。

命名记号三条：数组返回值在名字里体现载荷（`Ids` 轻量标识、`Infos` 记录本体，裸集合名不用于返回数组的函数）；筛选条件进名字（默认全量不标记、`By<key>` 按键、`ByIds` 显式 ID 数组）；是否分页不进名字，由入参 `(offset, limit, reverse)` 决定。

单键查询三条：`isSubmitted` 与两条方向单键 `proposalIdBySubmitter` / `submitterIdByProposalId`。后两条是旧 `submitInfoBySubmitter` / `submitInfo` 各改名而来——`(tokenAddress, round)` 下的推举记录是 `(proposalId, submitterId)` 对，且「每人每轮一个」「每提案每轮一次」使两种键都是唯一键，旧接口的两个方向本就互为镜像，故按同样方式改名、返回值都由 `ActionSubmitInfo` 收为单个标量（`0` = 本轮未推举）。`submitInfos` 的分页是集合的完整读取路径，两条单键是两个方向的定点通道。`isSubmitted` 保留是因为它是旧接口同名同参的保留成员——它与 `submitterIdByProposalId` 同键但给出两个不同的值（存在性 vs 取值），不构成重复，如同 `IMemberNFT.isNameUsed` 与 `idOf`。

## 🔢 Selector 清单

**保留（8 个）**：
```
stakeAddress()                          → 0x85107367
SUBMIT_MIN_PER_THOUSAND()               → 0xd6d15727
currentRound()                          → 0x8a19c8bc
isSubmitted(address,uint256,uint256)    → 0x2bed3c29
AlreadyInitialized()                    → 0x0dc149f0
CannotSubmitAction()                    → 0xaec0699e
AlreadySubmitted()                      → 0x9fbfc589
OnlyOneSubmitPerRound()                 → 0x9fb13b87
```

**新增与改名 selector（21 个）**：
```
# 新增错误（7 个）
EmptyString(string)                     → 0x62a65aec
ZeroAmount(string)                      → 0x3b3e6350
InvalidAmount()                         → 0x2c5211c6
InvalidAddress()                        → 0xe6c4247b
InvalidTargetMode()                     → 0x2589e3a0
RoundNotStarted()                       → 0x8e9c6e1c
NotMemberOwner(uint256)                 → 0x33393244

# 改名错误（1 个，旧 ActionIdNotExist() 并加参）
ProposalNotFound(uint256)               → 0x428d06a9

# 新增 Getter 与 init（4 个）
initialized()                           → 0x158ef93e
phaseAddress()                          → 0x1bd70981
memberNFTAddress()                      → 0xceecabf5
init(address,address,address,uint256)   → 0x46639dba

# 改参与改名（3 个）
canSubmit(address,uint256)              → 0x74abd30d
submitNewProposal(address,uint256,(string,string,address,uint8,bytes[])) → 0xa59abdc8
submit(address,uint256,uint256)         → 0xb57c0be4

# 查询（6 个）
proposalInfosByIds(address,uint256[])                      → 0x58f1444e
proposalIds(address,uint256,uint256,bool)                  → 0xbc7a7809
proposalIdsByAuthor(address,uint256,uint256,uint256,bool)  → 0xc252fb35
submitInfos(address,uint256,uint256,uint256,bool)          → 0x4d8331da
proposalIdBySubmitter(address,uint256,uint256)             → 0x376a6055
submitterIdByProposalId(address,uint256,uint256)           → 0xb14e8f00
```

**事件（2 个）**：
```
ProposalCreated(address,uint256,uint256,string,string,address,uint8)  → 0xfb8b1d44
ProposalSubmitted(address,uint256,uint256,uint256)                    → 0x81d08274
```

**删除（7 个）**：
```
proposalsCount(address)                            → 已删除
proposalsAtIndex(address,uint256)                  → 已删除
proposalsByAuthorCount(address,uint256)            → 已删除
proposalsByAuthorAtIndex(address,uint256,uint256)  → 已删除
submissionsCount(address,uint256)                  → 已删除
submissionAtIndex(address,uint256,uint256)         → 已删除
IndexOutOfBounds(uint256)                          → 已删除
```

## 📝 规格文档同步

- [05-submit.md](../../docs/specs/core/05-submit.md)：数据表按 `ProposalInfo{head, body}` 重组；新增「接口」读面三类表与「按 id 批量取详情」小节；分页表改名并写明「分页返回值随页内是否定长」的理由
- [CHANGES-core.md](../../docs/specs/CHANGES-core.md)：Submit 节记录结构体重组、改名、读面三类与理由
- [migration-standards.md](../../docs/migration-standards.md)：新增「集合读取函数的设计原则」小节，沉淀本次确定的有界/定长/命名判据；单键部分记明「存在性布尔与取值是两个不同的值，同键并存不算重复」
- [CONTEXT.md](../../CONTEXT.md)：Proposal 记录命名改为 `ProposalInfo { ProposalHead head, ProposalBody body }`
- [review-guide.md](../../docs/review-guide.md)：批量边界一条补上「只读按显式 ID 取详情可豁免，但须写明理由」

---

**审查人**：Kiro AI  
**状态**：✅ 通过
