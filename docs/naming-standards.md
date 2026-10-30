# 命名标准（函数与状态变量）

本文件约束 `core`、`action`、`group-chat`、`libs` 的 `src/`。`test/`、`script/` 遵循同一文法但不受门禁；`compatibility` 是测试夹具，`dex` 是上游源码，整体不适用。

本文件是 [`dev-standards.md`](dev-standards.md) §5.2 的细则。§4.3 的命名表由本文件 §七 取代，其余条款（有界性、定长、分页签名、唯一读取路径）继续有效。冲突时以本文件为准。

## 一、为什么单独立标准

合约没有升级路径，ABI 里的每个名字都是永久成本；§5.3 又禁止注释，名字是唯一的就地文档；同一概念横跨三个仓出现，命名漂移会变成每个集成方（SDK、索引器、前端）各自的映射表。

本标准只回答一个问题：**不看实现，能否从名字确定"做什么、作用于谁、单位、会不会变"**。四个问题里任何一个要靠读代码才能回答，名字就不合格。

## 二、五条判据

| # | 判据 | 反例 |
| --- | --- | --- |
| P1 | 词性即读写：动词开头是写，名词是读，`is/has/can/should` 是判断 | core 旧名 `sync()` 写、`syncObservations()` 读，同词根不同词性（已改为 `observations()`） |
| P2 | 键在名里：`By<Key>` 的 Key 与入参同名 | `voteBySenderId(groupId, targetSenderId, …)` |
| P3 | 量纲入名：`Amount`/`Shares`/`Votes`/`Ratio`/`Blocks`/`Round` | `value`、`num`、`amt` |
| P4 | 冻结可见：全大写 = 部署后不变 | `LpExecutor.actionTarget`（init 后冻结）与 `GroupChat.scopeSource`（可 set）同形 |
| P5 | 一词一义：同一概念全仓一个词根 | `Num`/`Count`、`Of`/`By`、`Account`/`MemberId` 并存 |

## 三、词形

| 种类 | 形式 | 例 |
| --- | --- | --- |
| 合约、接口、库、结构体、枚举 | `PascalCase` | `GroupActionExecutor`、`MemberStake` |
| 函数、参数、返回值、局部变量、结构体字段 | `lowerCamelCase` | `stakeLiquidity`、`tokenAddress` |
| 枚举成员 | `PascalCase` | `NoCallback`、`Callback` |
| 编译期常量 | `UPPER_SNAKE_CASE` | `MAX_TITLE_LENGTH`、`PRECISION` |
| 部署后冻结的值 | `UPPER_SNAKE_CASE` | `PHASE_ADDRESS`、`SUBMIT_MIN_RATIO` |
| 运行期可变状态 | `_lowerCamelCase` | `_memberStake`、`_nextTokenId` |
| internal/private 函数 | `_lowerCamelCase` | `_scoreBatch` |
| modifier | `only<Role>` / `non<State>` | `onlyMemberOwner`、`nonReentrant` |

五条硬约束：

1. `_` 只出现在 internal/private 函数与**可变**的非 public 状态变量上。常量、冻结值、public 状态、参数、返回值、结构体字段一律不带 `_`。库（`library`）的内部函数不加 `_`：调用点 `Uint256Set.add(set, x)` 已经表明来源。
2. 除上述两处，标识符里不出现下划线。接口参数不带 `_`（见 §十一）。
3. 只有两种大小写参与语义判断：`lowerCamelCase` 与 `UPPER_SNAKE`。
4. **同一合约内，函数名、参数名、状态变量名不得重名**。Solidity 对参数遮蔽函数名报 8760，`deny = "warnings"` 下直接编译失败。冲突时改**参数**而不是函数名：函数名是 ABI，参数名只是源码与 ABI JSON 里的字段。例：`memberName(uint256 tokenId)` 给 `memberId(string name)` 让位——`MemberNFT` 是 ERC-721，`ownerOf`/`tokenURI` 的参数本来就叫 `tokenId`。
5. **不用单字母或缩写式语义前缀**。`gGroupIds` 的 `g`（global）没有信息量，改写成名词 `joinedGroupIds`；布局结构体 `s` 改 `_layout`（§8.5）。

### 3.1 冻结值为什么全大写

`Mint.VOTE_ADDRESS` 在 `init` 后不可更改，`GroupChat.scopeSource` 可由群主或委托人 `setScopeSource` 更改。两者都是「某个合约的地址依赖」，但一个全大写、一个 camelCase——区别就是会不会变。若不用大小写编码，两者在 ABI 上完全同形，集成方必须读源码才能区分。本协议的安全模型建立在"哪些值部署后不再变"之上，这个区别必须在名字里可见，所以：**部署后冻结 = 全大写**，与它是 `constant`、`immutable` 还是 `init` 写入的存储无关。

这与 OZ 惯例（immutable 用 camelCase）不同，是有意偏离：OZ 面向可升级/可治理合约，冻结与否不是主要矛盾；本协议没有升级路径，冻结与否是主要矛盾。`dev-standards.md` §5.2 已经为 init 固定的配置常量选了大写，本条把它推广成一条轴，而不是引入新约定。

配套约束（防止信号被滥用）：

- **带参数的函数不得全大写**。`GOV_RATIO_MULTIPLIER(tokenAddress, groupId)` 的返回值随入参变化，全大写是撒谎，必须改为 `govRatioMultiplier`。
- **冻结值 getter 必须零参**。需要键才能取到的值不是冻结值，是配置。
- 冻结值只能有一个写入口（构造函数或 `init`）。出现第二个写入口即降级为可变状态，改 camelCase。

## 四、函数文法

```
写    <verb><Object>[<Objects>]
读    <object>[<Kind>][By<Key>]*
判断  is|has|can|should<State>
回调  on<Event> | before<Event> | after<Event>
```

### 4.1 写函数

| 语义 | 动词 | 反义 |
| --- | --- | --- |
| 集合增删 | `add` / `remove` | |
| 标量设置 | `set` / `clear` | |
| 生命周期 | `activate` / `deactivate` | |
| 参与 | `join` / `exit` | |
| 质押 | `stake` / `unstake` | |
| 铸造销毁 | `mint` / `burn` | |
| 资产进出 | `deposit` / `withdraw` | |
| 提案 | `submit` / `cancel` | |
| 记录 | `record` | |
| 结算 | `settle` | |
| 同步 | `sync` | |
| 合并 | `merge` | |

- 动词必须在首位。`providerQuotaAdd` → `addProviderQuota`，`providerQuotaWithdraw` → `withdrawProviderQuota`。
- 禁止 `get`/`fetch`/`query`/`read`/`load`/`do`/`handle`/`process`/`manage` 开头。`getDistribution` → `distribution`。
- 一个函数只做一个动作，禁止 `And` 连接（`stakeAndVote`）。
- 名字里不出现 `Try`/`Maybe`/`IfNeeded` 表达控制流；控制流写在实现里（`_prepareRewardIfNeeded` 是私有函数，可以保留，但公开 ABI 不得出现）。

### 4.2 读函数

- 名词开头，不加 `get`。
- 判断用谓词（§五），不用 `check*`；`verify*` 保留给"执行验证"这个动作，不用来判断。
- 同一集合的全量与分页不另起名，由入参决定（§7.5）。

### 4.3 回调

- `on*` 只用于外部协议规定的回调：`onProposalCreated`、`onERC721Received`、`onTokenLaunched`。
- `before*`/`after*` 只用于插件钩子：`beforePost`、`afterPost`。
- 不得用 `handle*`/`process*` 命名回调。

### 4.4 判断

返回**单个** bool 且**带参数**的函数必须是 `is/has/can/should` 开头：判断对象在参数里，名字要说明在判断什么。零参 bool getter 是状态读取，用形容词或过去分词（`initialized`），不套 `is`。返回 tuple 的函数不算——`actionReward` 返回 `(amount, minted)`，是读，不是判断。

### 4.5 禁止重载

同一合约内不得出现同名 external/public 函数。重载让 SDK 必须按完整签名消歧，让索引器无法只按函数名过滤，也让 selector 碰撞从"理论风险"变成"必须逐个核对"。本协议当前零重载，保持零。

## 五、布尔

| 位置 | 形式 | 例 |
| --- | --- | --- |
| 带参数的 bool 函数（判断别的主体） | 谓词 | `isJoined`、`hasActiveGroups`、`canVote` |
| 零参 bool getter / bool 状态变量 | 形容词或过去分词 | `initialized`、`activated` |
| 结构体字段 / 返回值 / 参数 | 形容词或过去分词 | `postingAllowed`、`mentionAll` |

谓词用于判断**别的主体**是否满足条件，判断对象在参数里；读取合约自身状态时，名字与声明同处一处，再加 `is` 是重复。

禁止否定式：`isNotActive` → `isActive`，`notPaused` → `isPaused`。

## 六、批量

| 位置 | 形式 | 例 |
| --- | --- | --- |
| 写 | 宾语复数 | `addAdmins`、`mintGovRewards`、`setRecipients` |
| 读（按 id 数组） | `ByIds` 或 `By<Key>Ids` | `proposalInfosByIds`、`votesByVerifierIds` |
| 判断 | `Batch` 后缀 | `isMemberIdBatch`、`isSenderIdBannedBatch` |

- 写函数不用 `Batch` 后缀（`mintGovRewardBatch` ✗）。批量已经是常态，`Batch` 只用来消解谓词的歧义：`isMemberIds` 会被读成"这些是不是成员 id"。
- 判断不用复数（`isMemberIds` ✗）。

## 七、读函数的载荷、键与聚合

### 7.1 文法

`<noun><Kind?><By<Key>>*<Count?>`

### 7.2 Kind

| 元素 | 后缀 |
| --- | --- |
| 记录 | `Infos` |
| 整数 id | `Ids` |
| 数值 | `Amounts` |
| 地址 | `Addresses`；元素本身就是实体地址时用裸集合名（`tokens`、`holders`） |

### 7.3 `By<Key>`

- Key 必须与某个入参同名（首字母大写）。`voteBySenderId(groupId, targetSenderId, …)` 不合格：键是 `SenderId`，入参是 `targetSenderId`。
- 多键按入参顺序书写：`votesByMemberIdByProposalId(tokenAddress, round, memberId, proposalId)`。
- `By<Key>Ids` 表示该键是 id 数组；`ByIds` 表示"按调用方给的 id 数组批量取"（`proposalInfosByIds`、`voteAmountsByMemberIdByIds`）。
- 作用域键（`tokenAddress`、`groupId`、`chatId`）是定位不是筛选，不进名字。

### 7.4 聚合

- 基数用 `Count`，且必须在末尾：`messagesByMentionCount`、`memberIdsCount`。
- 可加量总和用 `total` 前缀，且只用于**社区级**：`totalStaked`、`totalValidGovVotes`。成员级聚合用 `ByMemberId`：`stakedByMemberId`，不得写 `totalStakedByMemberId`。

### 7.5 分页

分页不进名字：不加 `Paginated`/`Paged`/`Page`/`List`。`(offset, limit, reverse)` 是唯一标记。

### 7.6 单条与集合

- 单数名词 = 单条（`message`），复数 = 集合（`messages`）。
- 不得用只差一个字母的两个名字返回**不同种类**的东西。`proposal()` 返回记录、`proposals()` 返回 id 数组是反例；同种类时，单复数对是合法的系统区分。

### 7.7 不用 Of

自有读取函数不用 `Of` 后缀。两种合格写法：

- **单实体属性读**：`<属性名>(<key>)`，键由入参名给出——`memberName(tokenId)`、`delegateId(groupId)`、`voteWeight(groupId, voterId)`。
- **集合筛选**：`<noun>By<Key>`——`proposalIdsByAuthor`、`messagesBySender`。

`Of` 不指名键；`Of` 与 `By` 并存时（core 旧名 `stakedAmountOfVotersByMemberId`，已改为 `voterBoost`）连作者都要读实现才能确认键是哪一个。ERC 标准覆写（`ownerOf`）保留。

## 八、状态变量

### 8.1 三类

| 类 | 形式 | 例 |
| --- | --- | --- |
| 编译期常量 | `UPPER_SNAKE` | `MAX_TITLE_LENGTH`、`PRECISION` |
| 部署后冻结 | `UPPER_SNAKE` | `PHASE_ADDRESS`、`SUBMIT_MIN_RATIO`、`MAX_SUPPLY` |
| 运行期状态 | `_lowerCamelCase` | `_memberStake`、`_votesByMemberId` |

### 8.2 可见性

- 冻结值可以 `public`，自动 getter 即接口。
- 零参可变状态可以 `public`（getter 没有入参，不存在 ABI 字段名问题）。
- **带键的状态一律 `internal` + 显式 getter**。沿用 §5.2：自动 getter 的 ABI 入参没有字段名，与冻结接口的 `tokenAddress`/`memberId` 对不上。

### 8.3 映射

判据：**读者能否从名字说出键**。两个合格形态：

- `<value>By<Key>`：`_votesByMemberIdByProposalId`、`_voterIdsByProposalId`；`_pairAddress` → `_pairAddressByTokenAddress`。
- `<subject><State>`：值是该主体的完整记录时，键即主体，可省 `By`——`_memberStake[tokenAddress][memberId]`、`_adminState[groupId]`。

不合格的是"值名既不含主体也不含键"：`_deduction`、`_createdRound`、`_joinBlocks`。标量或数组值一律写 `By`（`_joinAmounts` → `_joinAmountsByMemberId`、`_voterBoost` → `_voterBoostByMemberId`）。

禁止裸名：`_states` → `_adminState`，`_data`/`_info` 按同样方式补主体。

### 8.4 集合与计数

- 数组用复数：`_tokens`、`_holders`。`_allHolders` 的 `all` 是噪音。
- 计数用 `<noun>Count`：`_mintedCount`。禁止 `_entered` 这类无语义名；重入锁写 `_reentrancyStatus`。

### 8.5 布局

24KB 拆分用的根布局 struct 统一 `_layout`，禁止单字母 `s`；库函数的 storage 参数用 `self`（参数不带 `_`，`layout` 会触发 6335 未来关键字警告）。

Layout 中**部署后冻结的字段**按 §3.1 用 `UPPER_SNAKE`（`ACTION_TARGET_ADDRESS`、`STAKE_ADDRESS`、`SPLITS`），其余可变字段用 `lowerCamelCase`；`initialized` 是初始化完成标志（§4.4 的零参 bool getter），保持 `lowerCamelCase`。

### 8.6 结构体类型

| 用途 | 形式 | 例 |
| --- | --- | --- |
| 存储态 | `<X>State` | `AdminState`、`RoundState` |
| ABI 只读记录 | `<X>Info` | `ChatInfo`、`ProposalInfo` |
| 入参包 | `<X>Params` | `LaunchInitParams` |
| 计算中间体 | 名词 | `Distribution`、`Settlement` |

禁止 `Data`/`Args` 后缀：`stakeData` → `memberStake`，`totalStakeData` → `totalStake`，`RecipientPaidArgs` → `RecipientPaidParams`。

## 九、量纲

| 词 | 含义 | 禁止 |
| --- | --- | --- |
| `Amount` | 代币数量（最小单位） | `value`、`qty`、`amt` |
| `Shares` | LP / boost 份额 | `balance`（余额另有其义） |
| `VoteAmount` / `VoteAmounts` | 投出的票数；单值 / 数组 | 裸 `votes`（分不清标量与数组） |
| `Votes` | 票权（投票资格的量） | `power`、`num` |
| `Weight` | 权重（非票数） | — |
| `Ratio` | 1e18 定点比例 | `rate`、`percent`、`bps`、`perThousand` |
| `Blocks` | 区块数 | — |
| `Phase` | 时间片 | `round` |
| `Round` | 治理轮 | `epoch`、`period` |
| `Timestamp` | 秒级时间戳 | `time` |
| `Count` | 基数 | `num`、`length` |
| `Index` | 序号 | `idx` |

`Phase` 与 `Round` 是本协议最容易写错的一对：`Phase` 是出块时间片（`currentPhase`、`promisedWaitingPhases`），`Round` 是治理轮（`currentRound`、`round`）。两者不互为别名，也不得用 `period`/`epoch` 代替任何一个。

## 十、跨仓术语

| 概念 | 唯一写法 | 禁用 |
| --- | --- | --- |
| 社区代币地址 | `tokenAddress` | `token`（`address` 类型时）、`tokenAddr`、`erc20` |
| 成员身份 | `memberId` | `account`、`user`、`id` |
| 链群 | `groupId` | `group`（`uint256` 类型时） |
| 行动 | `actionId` | `action`、绑定后的 `proposalId` |
| 提案（未绑定） | `proposalId` | `actionId` |
| 发言者 | `senderId`（仅群聊域） | 群聊域外的 `senderId` |
| 操作者 | `operatorId` | `caller`、`msgSender` |
| 接收人 | `recipientId` | `to`、`receiver` |
| 验证人 | `verifierId` | `validator` |
| 提供者 | `providerId` | `sponsor` |

`address` 类型的**实体**参数/字段必须带 `Address` 后缀（`tokenAddress`、`pairAddress`）；角色与流向地址保留角色名（`recipient`、`distributor`、`owner`、`from`、`to`）。`address token`、`uint256 member` 一律不合格；`uint256` 身份必须带 `Id` 后缀。

`MemberNFT` 同时是 ERC-721 与协议身份入口，按语义分层：NFT 语义的入口用 `tokenId`（`ownerOf`、`tokenURI`、`memberName`、`mint` 的返回值），协议语义的入口用 `memberId`（事件字段、`memberId(string name)` 的返回值）。两者是同一个数值；分层是为了不与继承来的 ERC-721 参数名冲突（§3 硬约束 4）。

## 十一、参数与返回值

- 参数名 = 结构体字段名 = 事件字段名 = getter 参数名，四处同源。改名必须四处同改（[`event-standards.md`](event-standards.md) §6.1 已强制键名）。
- 接口与实现参数都不带 `_`。实现侧若与状态变量同名，改参数名；冻结值按 §八 大写、可变状态在 `_` 命名空间，正常不会冲突。
- 返回值应具名：ABI JSON 里未命名的返回值只能按下标取，SDK 无法生成字段名。数组用复数；与函数同名时用 `<noun>List`。

## 十二、类型、接口、枚举、modifier

- 接口 `I<Name>`；事件/错误子接口 `I<Name>Events`/`I<Name>Errors`；基类 `<X>Base`。
- 枚举类型与成员 PascalCase。作为"预检原因"的枚举，成员名 = 对应错误名去掉载荷（`ScopeRejected` ↔ `ScopeRejected(...)`），保证 `reason → error` 是恒等映射。
- modifier 名必须读出授权主体：合约用合约名（`onlyMint`、`onlyVote`、`onlyActionTarget`），角色用角色名（`onlyMemberOwner`、`onlyMinter`、`onlyGroupOwner`）。同一主体只能有一个名字。

## 十三、对既有规范的修订

| # | 既有条款 | 变更 | 理由 |
| --- | --- | --- | --- |
| 1 | §5.2「init 固定的配置常量用大写」 | 扩展为「部署后冻结的值一律大写」，新增「带参数不得大写」 | §3.1 |
| 2 | §4.3 命名表 | 由 §七 取代：`Count` 末尾、`By<Key>` 同名、`ByIds`、数值数组 `Amounts`、裸集合名限定 | 键与名必须能机械对账 |
| 3 | `Of` 后缀 | 禁止（ERC 覆写除外） | 不指名键，多键歧义 |
| 4 | `get*` 前缀 | 禁止 | 读函数的名词本身就是载荷 |
| 5 | 接口参数 `_` 后缀 | 禁止 | ABI 参数名是集成方 API |
| 6 | `Data` 后缀 | 禁止 | 不表达任何语义 |
| 7 | `g*` 全局索引前缀 | 禁止，改 `joined*` | 单字母无语义 |
| 8 | `total*` | 限定社区级 | 成员级聚合与社区级聚合混名 |
| 9 | `Num` | 按语义改 `Votes` 或 `Count` | 同一缩写承载两种量纲 |
| 10 | 单 bool 返回 | 带参数必须是谓词；零参 getter 用形容词 | 判断别的主体才需要谓词 |

## 十四、门禁与迁移

- 检查器：`python3 matt-gov/script/check_naming.py` 输出违规；`--check` 对比基线，只拦新增；`--update-baseline` 仅在批量改名落地后重写。
- 基线：`matt-gov/registry/naming-baseline.txt`，当前 35 条（按文件×符号记录，接口与实现各记一条；`core`、`action` 已清零，剩余 `group-chat`）。2026-10-30 由符号粒度改为文件×符号并一次性重写；此后**只减不增**。
- 迁移按依赖顺序 `libs → core → action → group-chat`，每仓一次提交，`forge test` 全绿。改名落地时同批更新 `CONTEXT.md`（§GroupAction 参与归属）、`docs/specs/` 中引用旧名的条目与 `CHANGES-*.md` 对账表。
- 进度：`core` 的 23 条机器规则已清零（2026-10-30，473 个用例全绿）；本批同时修正了构造函数参数、局部变量与本次改名涉及的映射名。`action` 已于 2026-10-30 清零（467 个用例全绿），同批人工核对落实：`s` 根布局改 `_layout`（库参数 `self`）、`init` 冻结依赖改 `ACTION_TARGET_ADDRESS`/`GROUP_ACTION_EXECUTOR_ADDRESS` 等全大写 getter、`providerQuota*` 等写入口改动词首位、`_` 后缀参数与局部变量去掉后缀、`RecipientPaidArgs` 改 `RecipientPaidParams`、`MemberOwner.ofOrZero` 改 `ownerOrZero`、LpExecutor 的 `_deduction`/`_joinBlocks`/`_joinAmounts`/`_createdRound` 等映射名按 §8.3 补齐键；`votes` 返回数组与按申请账本按 §9 改为 `voteAmount(s)`；Layout 的冻结字段改全大写（N17 增加 Layout 冻结字段例外）、`groupIds`/`actionIds` 函数改 `groupIdsByRound`/`actionIdsWithActiveGroups`、`totalJoinedAmount*` 改 `joinedAmountByActionId`/`joinedAmountByGroupId`、事件票数字段改 `voteAmountAdded`/`voteAmountTotal`、`applicationIdCounter` 改 `applicationIdCount`；基座计价代币 getter 统一为 `joinTokenAddress`（GroupService 的 `actionTokenAddress` 为单点例外）、`joinInfo` 返回 `joinedAmount`、基座 action 级累计量改 `joinedAmountByActionId`。`group-chat` 已 bump 到 action `9e7b4b2`（2026-10-30），自身命名批次待做。
- 剩余分批（`group-chat`；条数按基线条目计（文件×符号），括号内为唯一符号数）：
  - **P0 语义错误**（ABI 会误导集成方）：`N04`/`N05`，8 条（4 个符号）。
  - **P1 一致性**：`N10`/`N14`/`N20`，14 条（8 个符号）。
  - **P2 卫生**：`N11`/`N12`，13 条（10 个符号）。
- 检查器只看声明形态，不能判断"是否有第二个写入口"。构造函数或 `init` 写入的 public 状态需人工判定是否冻结；判定为冻结即按 §3.1 改全大写。N17 的 Layout 例外同样只看 struct 名（`Layout`/`*Layout`），不判断字段是否冻结；Layout 内新增字段需人工核对，只有部署后冻结的字段才能用 UPPER_SNAKE。
- 构造参数、局部变量、事件字段与 §8.3 的存量映射名不在检查器范围内，按 §十五 清单人工核对。

## 十五、审查清单

- [ ] 新函数名能在 §四 的文法里解析（写/读/判断/回调）。
- [ ] `By<Key>` 的 Key 与入参同名。
- [ ] 单 bool 返回是谓词；tuple 内的 bool 不受限。
- [ ] 冻结值全大写、零参、只有一个写入口。
- [ ] 可变状态带 `_` 前缀且 `internal`。
- [ ] 参数名与事件字段、getter、结构体字段一致。
- [ ] 构造参数与局部变量为 lowerCamelCase，且不带 `_`。
- [ ] `address` 实体参数/字段带 `Address` 后缀；角色地址用角色名。
- [ ] 没有 `get`/`num`/`amt`/`addr`/`Data`/`Of` 等禁用词。
- [ ] `check_naming.py --check` 无新增。

## 附录 A：剩余 P0 改名表

`core` / `action` 已完成，下表只列 `group-chat` 的 P0 项。

| 现名 | 新名 | 规则 |
| --- | --- | --- |
| `postingAllowed(chatId)` | `isPostingAllowed(chatId)` | N04 |
| `voteBySenderId(groupId, targetSenderId, …)` | `voteBySenderId(groupId, senderId, …)` | N05 |
| `clearVoteBySenderId` / `refreshVoteBySenderId` | 同上，入参改 `senderId` | N05 |

## 附录 B：检查器规则编号

| 编号 | 规则 | 作用域 |
| --- | --- | --- |
| `N01` | 函数名 lowerCamelCase（冻结值 getter 除外） | 全部函数 |
| `N02` | 禁用动词前缀 | 全部函数 |
| `N03` | 带参数的函数不得全大写 | external/public |
| `N04` | 带参数的 bool 返回必须是谓词 | external/public |
| `N05` | `By<Key>` 的 Key 必须有同名入参 | external/public |
| `N06` | `Count` 必须在末尾 | external/public |
| `N07` | 禁用词（`num`/`amt`/`addr`/`tmp` 等） | 全部标识符 |
| `N08` | 状态变量 `_` 前缀与可见性匹配 | 状态变量 |
| `N09` | 常量 UPPER_SNAKE 且无 `_` 前缀 | 状态变量 |
| `N10` | immutable UPPER_SNAKE 且无 `_` 前缀 | 状态变量 |
| `N11` | 名字不得过短或为裸 `state`/`data`/`info` | 函数、状态变量 |
| `N12` | 接口参数不带 `_` 后缀 | 接口 |
| `N13` | 禁 `Data` 后缀 | 函数、状态变量 |
| `N14` | `address` 实体字段必须带 `Address` 后缀（参数按 §十 人工核对） | 结构体字段 |
| `N15` | 接口名 `I` + PascalCase | 接口 |
| `N16` | 枚举成员 PascalCase | 枚举 |
| `N17` | 结构体字段 lowerCamelCase（Layout 的冻结字段可 UPPER_SNAKE，冻结判定人工） | 结构体 |
| `N18` | modifier `only<Role>` / `non<State>` | modifier |
| `N19` | internal/private 函数带 `_`，public/external 不带 | 函数 |
| `N20` | 禁 `Of` 后缀（ERC 覆写除外） | external/public |
| `N21` | `total*` 只用于社区级聚合 | external/public |
| `N22` | 禁单字母语义前缀 `g` | 全部函数 |
| `N23` | 禁止外部函数重载 | external/public |
