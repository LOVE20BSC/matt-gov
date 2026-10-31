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
4. **同一合约内，函数名、参数名、状态变量名不得重名**。Solidity 对参数遮蔽函数名报 8760，`deny = "warnings"` 下直接编译失败。冲突时改**参数**而不是函数名：函数名是 ABI，参数名只是源码与 ABI JSON 里的字段。例：`memberName(uint256 tokenId)` 给 `memberId(string name)` 让位——`MemberNFT` 是 ERC-721，`ownerOf`/`tokenURI` 的参数本来就叫 `tokenId`。**例外一**：若该参数名同时是结构体字段或事件字段（§十一 四处同源），改**函数名**而不是参数名——此时参数名也是 ABI，改它会让入参/结构体/事件三处一起失配，代价更大。**例外二（读取 getter）**：冲突方是同合约的**读取 getter**、而该参数名同时被 §十一 绑定时，例外一与「getter 是既有 ABI」互相抵触，按「谁进 selector」裁决——函数名进 selector，参数名只进 ABI JSON 字段，所以**改参数名**（加 §十 的实体后缀），getter 不动。例：`scopeSource` 同时是 `ChatConfig.scopeSource`、`ChatInfo.scopeSource`、`GroupChatActivated.scopeSource` 与 getter `scopeSource(uint256)` 的名字，`activateChat` 与 `setScopeSource` 的入参统一改 `scopeSourceAddress`，`banSource` / `beforePostPlugin` / `afterPostPlugin` 同理；§十一 的四处同源在这一层让步（入参带 `Address`、字段与事件保留角色名），见 §十一 的登记例外。
5. **不用单字母或缩写式语义前缀**。`gGroupIds` 的 `g`（global）没有信息量，改写成名词 `joinedGroupIds`；布局结构体 `s` 改 `_layout`（§8.5）。

### 3.1 冻结值为什么全大写

`Mint.VOTE_ADDRESS` 在 `init` 后不可更改，`GroupChat.scopeSource` 可由群主 `setScopeSource` 更改。两者都是「某个合约的地址依赖」，但一个全大写、一个 camelCase——区别就是会不会变。若不用大小写编码，两者在 ABI 上完全同形，集成方必须读源码才能区分。本协议的安全模型建立在"哪些值部署后不再变"之上，这个区别必须在名字里可见，所以：**部署后冻结 = 全大写**，与它是 `constant`、`immutable` 还是 `init` 写入的存储无关。

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
- **守卫用 `_check<宾语>`，取值型读辅助用 `_xxxOrRevert`**：两个族，判据是「调用的目的是什么」。
  - **守卫（`_check<宾语>`）**：三条同时成立——①`view`/`pure`，成功路径没有写入；②不满足就 revert；③**存在意义是拦截**，调用方关心的是「过了没有」，不是「拿到了什么」。宾语是被校验的对象（`_checkToken`、`_checkSlippage`、`_checkExistingProposal`、`_checkAdminIdList`），与 OZ 的 `_checkOwner` / `_checkRole` 同一惯例。校验通过后返回**判定过程中已经算出的值**可以接受：`_checkActiveRound` 返回判定所依据的当前轮、`_checkApplicationWindow` 返回申请生效轮、`_checkName` 返回入参的规范化结果——判据是「把这个返回值去掉，调用方是否要重算同一件事」：要重算就是合理副产物，不要重算就该删掉返回值。
  - **取值型（`_xxxOrRevert`）**：存在意义是**取一个值**，revert 只是「取不到」的分支（`_groupOwnerOrRevert`、`_sourceOrRevert`、`_voteWeightOrRevert`、`_totalVoteWeightOrRevert`）。名字的主语是返回值，不改 `_check*`：`_checkSource` 读不出「调用方要拿 source」。
  - 两族的边界就是①③：`_join`/`_post`/`_setRecipients` 这类业务函数也会 revert，但不是守卫（成功路径有写入）；`_ownerOrRevert` 这类取值辅助不是守卫（成功路径的产物是值）。
- 宾语用词：存在性统一 `_checkExisting<名词>`（`_checkExistingProposal`、`_checkExistingGroup`、`_checkExistingAction`）；集合入参沿用 `<名词>IdList`（`_checkAdminIdList`；同文件的 `_checkAdminIdsLimit` 按集合 getter `adminIds()` 取词干，两者分工不同）；**同一判据只用一个宾语**——取错误载荷里的词（`ZeroTargetSenderId` → `_checkTargetSenderId`），不按各调用点的入参名分叉。函数名不嵌错误名——`_ownerOrRevertGroupNotExist` 已改 `_groupOwnerOrRevert`（宾语是业务对象 `group`，不是错误名）。
- 不用 `_require*`——`require` 的宾语应是「必须成立的条件」，接名词会被读成「需要该对象」（`_requireSlippage` 读作"需要滑点"）。也不用 `_validate*`：它与 `_check*` 是同一形态的两族前缀，任何判据都划不开，2026-11-01 已全部并入 `_check*`。`check*` 的禁用只针对**返回 bool 的公开判断**（§4.2），不针对这类守卫。

### 4.2 读函数

- 名词开头，不加 `get`。
- 判断用谓词（§五），不用 `check*`——本条只约束返回 bool 的判断；`internal`/`private` 的守卫用 `_check*`、取值型用 `_xxxOrRevert`（§4.1）。`verify*` 保留给"执行验证"这个动作，不用来判断。
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
| 读（按 id 数组） | `By<Key>Ids` | `proposalInfosByProposalIds`、`voteAmountsByVerifierIds` |
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
- **Key 必须与某个入参同名**：`messagesBySenderId(groupId, senderId, …)`、`proposalIdBySubmitterId(…, submitterId)`、`voteWeightsBySenderIdsByVoterId(…, voterId)`、`votesByMemberIdByProposalId(…, memberId, proposalId)`。`Id`/`Ids` 是类型标记，不是可省后缀——写成 `BySender` 只省四个字符，却让读者无法判断 Key 是 id 还是 address（旧仓的 address 主体路径恰叫 `sender`）。匹配是单向的：`BySenderId` 配入参 `targetSenderId` 不合格（`SenderId` 不是 `targetSenderId`），反过来 `ByTargetSenderId` 合格。
- **筛选条件没有入参时不能用 `By`**：`messagesByMentionAll(groupId, …)` 的 mention-all 是固定条件、不对应任何入参，改形容词前缀 `mentionAllMessages` / `mentionAllMessageIds`。
- 多键按入参顺序书写：`votesByMemberIdByProposalId(tokenAddress, round, memberId, proposalId)`。
- `By<Key>Ids` 表示该键是 id 数组：`proposalInfosByProposalIds`、`voteAmountsByMemberIdByProposalIds`、`chatInfosByGroupIds`。**不设无键的 `ByIds`**——它不指名 Key，违反 P2。试探两端都不成立：若主键真的不言自明，那连 `Ids` 都不必写；可函数名又必须区分「按 id 批量」与「分页」两种读法，不写就看不出入参是数组。
- 作用域键（`tokenAddress`、`groupId`、`chatId`）是定位不是筛选，不进名字（`messages(groupId, offset, limit, reverse)`、`actions(tokenAddress, offset, limit, reverse)`）。
- **双向索引成对出现时，两侧都是键，都要写进名字**：`tokenAddressByGroupId` / `groupIdByTokenAddress`、`actionByGroupId` / `groupIdByActionId`。它们不是「始终存在的上下文」——每一侧都是唯一能定位结果的那把键，省略任一侧都会让读者无法预测反向查询叫什么。
- **入参与同名读取函数冲突时**（`adminIds()`、`memberIds()`、`groupIds()`、`rounds()` 这类集合 getter 占用了最自然的名字），按 §3 硬约束 4 改参数而不是函数名；改写形态是**封闭集合**：写方向用 `<noun>List`、判断用 `checked`、读入参用 `requested`。例：`addAdmins(…, adminIdList)`、`removeMemberIds(…, memberIdList)`、`isMemberIdBatch(…, checkedMemberIds)`、`chatInfosByGroupIds(requestedGroupIds)`。
  - 写方向不用 `added` / `removed`：方向已由函数名给出，`addAdmins(addedAdminIds)` 读作「把已加的管理员 id 加进去」，既重复又没说明是数组。`List` 只声明「这是数组」，且与内部双向辅助同名（`_setMemberIds(…, memberIdList, listed)`），内外一套词。`adminIdList` / `memberIdList` 与集合 getter（`adminIds` / `memberIds`）不同名，不触发同名声明。
- Key 取入参名去掉用途前缀后的词干：`roundInfosByRounds(…, requestedRounds)`、`chatInfosByGroupIds(…, requestedGroupIds)`、`proposalInfosByProposalIds(…, requestedProposalIds)`。`Ids` 只在载荷确实是 id 数组时使用：轮次是纪元键不是 id，`roundInfosByRoundIds` 不合格。
- 同一内部辅助函数同时服务增删两个方向时（`_checkAdminIdList`、`_setMemberIds`），入参用 `<noun>List`（`adminIdList`、`memberIdList`），与 §十一 返回值同名冲突时的逃生口一致。

### 7.4 聚合

- 基数用 `Count`，且必须在末尾：`RoundSpan.messageCount`、`MessagePosted.mentionedSenderCount`。**函数级不设独立计数入口**：集合总数由分页返回的 `totalCount` 承担（§7.5），`limit = 0` 即取基数；同一集合的「分页 + Count」是两条读取路径。
- 可加量总和用 `total` 前缀，且只用于**社区级**：`totalStaked`、`totalValidGovVotes`。成员级聚合用 `ByMemberId`：`stakedByMemberId`，不得写 `totalStakedByMemberId`。

### 7.5 分页

分页不进名字：不加 `Paginated`/`Paged`/`Page`/`List`。`(offset, limit, reverse)` 是唯一标记。分页同时返回集合真实总数并具名（`dev-standards §4.3(3)`）：同一集合不再另设 `*Count` 入口，`limit = 0` 即取基数。`totalCount` 只约束**对外 ABI 面**（`external`/`public`）：库与内部辅助返回 `(列表, total)` 即可（`Pagination.paginate*`、`Uint256Set.values`、`GroupActionVerify._applicationVoters`），调用方按位置解构，名字不进 ABI JSON；对外入口包装这些辅助时，返回名一律写 `totalCount`。

### 7.6 单条与集合

- 单数名词 = 单条（`message`），复数 = 集合（`messages`）。
- 不得用只差一个字母的两个名字返回**不同种类**的东西。`proposal()` 返回记录、`proposals()` 返回 id 数组是反例；同种类时，单复数对是合法的系统区分。

### 7.7 不用 Of

自有读取函数不用 `Of` 后缀（含中缀：`tokenOfGroup`、`groupIdOfAction` 一律不合格；`N20` 匹配「`Of` 后接大写字母或字符串结尾」，中缀由检查器覆盖）。两种合格写法：

- **单实体属性读**：`<属性名>(<key>)`，键由入参名给出——`memberName(tokenId)`、`scopeSource(groupId)`、`voteWeight(groupId, voterId)`。
- **集合筛选**：`<noun>By<Key>`——`proposalIdsByAuthor`、`messagesBySenderId`。

单实体属性读与同合约的入参同名时（`groupId(tokenAddress)` 会撞 `voteWeight(uint256 groupId, …)` 的入参），退回 `<noun>By<Key>`（`groupIdByTokenAddress(tokenAddress)`）——键仍由入参名给出，理由同 §3 硬约束 4 的例外。

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
| 存储态（可变） | `<X>State` | `AdminState`、`RoundState` |
| 存储态（写入后不变） | `<X>Record` | `MessageRecord`、`VoteRecord` |
| ABI 只读记录 | `<X>Info` | `ChatInfo`、`ProposalInfo` |
| 入参包 | `<X>Params` | `LaunchInitParams` |
| 配置记录 | `<X>Config` | `ChatConfig`、`GroupConfig` |
| 计算中间体 | 名词 | `Distribution`、`Settlement` |

`State` 与 `Record` 的分界是**写入后会不会变**：`RoundState` 的游标随每条消息推进，`AdminState` 的集合随增删变化，都叫 `State`；`MessageRecord` 的 content / round / blockNumber / timestamp 是发言时的快照，之后永不改写，叫 `Record`。把不可变记录叫 `State` 会让读者以为存在状态迁移。

**规格冻结名优先**：被 `docs/specs/` 或 `dev-standards.md` 明文冻结的类型名不按本表改名——`ChatInfo` / `Message` / `RoundSpan`（`specs/group-chat/00-overview.md` 逐字段保留）、`MemberStake` / `TotalStake`（`dev-standards.md` §5.2 成对登记）。本表约束的是**新增**类型，以及未被冻结的存量。`group-chat` 已清完（`ChatConfig` 按本表登记为配置记录、`StoredMessage` → `MessageRecord`）。`core` / `action` 的 `ManagedAction`、`ProposalHead` / `ProposalBody`、`VerifierApplication`、`RecipientTable`、`VoteRecord`、`OriginSubmission`、`RoundActions` 判为可接受：它们是存储态但与该合约的 ABI 记录不同名、不存在歧义，加 `State` 只是噪音，属独立批次。

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
- **对外签名：`round`/`rounds` 在 `memberId`/`verifierId` 之前**：`(tokenAddress, actionId, round, memberId)`、`(tokenAddress, round, memberId)`；批量把与 `actionIds` 配对的 `rounds` 紧接其后、`memberId` 收尾（`(tokenAddress, actionIds, rounds, memberId)`），`recipient` 保持在最后。`groupId` 是作用域键，保持在其前（`recipients(..., groupId, round)`、`messagesByRound(groupId, round)`）；荷载在 `round` 之后（`distribution(..., round, groupReward)`）。分页在 `round` 之后接 `(offset, limit, reverse)`。`isJoinedByRound`、`memberReward`、`mintMemberReward`、`verificationInfosByRound`、`mintGovReward` 与 `joinInfo`、`joinedAmountByMemberId`、`verifierApplication` 同序；同签名的实现与库转发必须一致。库与内部辅助同样遵循：`round` 在 `memberId`/`verifierId` 之前，`self`/作用域键在最前，荷载（金额、验证值数组）与标志（`present`、`latest`、`isFirstJoin`）在主体之后。重排时逐个核对签名——`bool` 返回不会报错，只会静默取错成员。
- 返回值应具名：ABI JSON 里未命名的返回值只能按下标取，SDK 无法生成字段名。数组用复数；与函数同名时用 `<noun>List`。单结构体返回同样具名（`returns (JoinInfo memory info)`、`returns (ChatInfo memory info)`），不因「只有一个返回值」省略。
- **返回值不用裸泛名**：`ids`、`list`、`items` 读不出是哪类东西，按 §7.2 的载荷记号取名（`adminIdList`、`voteAmounts`）。`List` 在这里取「数组」义，与 §7.5 分页禁 `List` 不冲突。
- **登记例外：四个配置槽位的入参带 `Address`、字段与事件保留角色名**（§3 硬约束 4 例外二）：入参写作 `scopeSourceAddress` / `banSourceAddress` / `beforePostPluginAddress` / `afterPostPluginAddress`（`activateChat` 与四个单槽 setter 一致），而 `ChatConfig.scopeSource`、`ChatInfo.scopeSource`、`GroupChatActivated.scopeSource` 等字段与事件字段保持角色名。同槽位的内部辅助（`_setSource` 的 `sourceAddress`、`_setPostPlugin` 的 `pluginAddress`）服务增删两个方向，保留通用名，同 §7.3 的 `<noun>List` 逃生口。

## 十二、类型、接口、枚举、modifier

- 接口 `I<Name>`；事件/错误子接口 `I<Name>Events`/`I<Name>Errors`；基类 `<X>Base`。
- 枚举类型与成员 PascalCase。作为"预检原因"的枚举，成员名 = 对应错误名去掉载荷（`ScopeRejected` ↔ `ScopeRejected(...)`），保证 `reason → error` 是恒等映射。
- modifier 名必须读出授权主体：合约用合约名（`onlyMint`、`onlyVote`、`onlyActionTarget`），角色用角色名（`onlyMemberOwner`、`onlyMinter`、`onlyGroupOwner`）。同一主体只能有一个名字。

## 十三、对既有规范的修订

| # | 既有条款 | 变更 | 理由 |
| --- | --- | --- | --- |
| 1 | §5.2「init 固定的配置常量用大写」 | 扩展为「部署后冻结的值一律大写」，新增「带参数不得大写」 | §3.1 |
| 2 | §4.3 命名表 | 由 §七 取代：`Count` 末尾、`By<Key>` 同名、`By<Key>Ids`、数值数组 `Amounts`、裸集合名限定 | 键与名必须能机械对账 |
| 3 | `Of` 后缀 | 禁止（ERC 覆写除外） | 不指名键，多键歧义 |
| 4 | `get*` 前缀 | 禁止 | 读函数的名词本身就是载荷 |
| 5 | 接口参数 `_` 后缀 | 禁止 | ABI 参数名是集成方 API |
| 6 | `Data` 后缀 | 禁止 | 不表达任何语义 |
| 7 | `g*` 全局索引前缀 | 禁止，改 `joined*` | 单字母无语义 |
| 8 | `total*` | 限定社区级 | 成员级聚合与社区级聚合混名 |
| 9 | `Num` | 按语义改 `Votes` 或 `Count` | 同一缩写承载两种量纲 |
| 10 | 单 bool 返回 | 带参数必须是谓词；零参 getter 用形容词 | 判断别的主体才需要谓词 |

## 十四、门禁与迁移

2026-10-30 的进度记录包含 delegate 相关名字；这些名字已随 ADR-005 于 2026-10-31 删除，记录保留原样。

- 检查器：`python3 matt-gov/script/check_naming.py` 输出违规；`--check` 对比基线，只拦新增；`--update-baseline` 仅在批量改名落地后重写。
- 基线：`matt-gov/registry/naming-baseline.txt`，当前 **0 条**（按文件×符号记录，接口与实现各记一条；`core`、`action`、`group-chat` 均已清零）。2026-10-30 由符号粒度改为文件×符号并一次性重写；此后**只减不增**。
- 迁移按依赖顺序 `libs → core → action → group-chat`，每仓一次提交，`forge test` 全绿。改名落地时同批更新 `CONTEXT.md`（§GroupAction 参与归属）、`docs/specs/` 中引用旧名的条目与 `CHANGES-*.md` 对账表。
- 进度：`core` 的 23 条机器规则已清零（2026-10-30，473 个用例全绿）；本批同时修正了构造函数参数、局部变量与本次改名涉及的映射名。`action` 已于 2026-10-30 清零（当前 469 个用例全绿，2026-10-31 新增 `test_ZeroBoundaries` 与两条轮次守卫用例），同批人工核对落实：`s` 根布局改 `_layout`（库参数 `self`）、`init` 冻结依赖改 `ACTION_TARGET_ADDRESS`/`GROUP_ACTION_EXECUTOR_ADDRESS` 等全大写 getter、`providerQuota*` 等写入口改动词首位、`_` 后缀参数与局部变量去掉后缀、`RecipientPaidArgs` 改 `RecipientPaidParams`、`MemberOwner.ofOrZero` 改 `ownerOrZero`、LpExecutor 的 `_deduction`/`_joinBlocks`/`_joinAmounts`/`_createdRound` 等映射名按 §8.3 补齐键；`votes` 返回数组与按申请账本按 §9 改为 `voteAmount(s)`；Layout 的冻结字段改全大写（N17 增加 Layout 冻结字段例外）、`groupIds`/`actionIds` 函数改 `groupIdsByRound`/`actionIdsWithActiveGroups`、`totalJoinedAmount*` 改 `joinedAmountByActionId`/`joinedAmountByGroupId`、事件票数字段改 `voteAmountAdded`/`voteAmountTotal`、`applicationIdCounter` 改 `applicationIdCount`；基座计价代币 getter 统一为 `joinTokenAddress`（GroupService 的 `actionTokenAddress` 为单点例外）、`joinInfo` 返回 `joinedAmount`（2026-10-31 改为 `JoinInfo` 记录并删去该派生总量，见 `CHANGES-action.md`）、基座 action 级累计量改 `joinedAmountByActionId`。
- `group-chat` 已于 2026-10-30 清零（当时 172 个用例全绿；`faa89cf` 删除群内委托套件后为 152），同批落实：
  - **P0 语义错误**：`postingAllowed(groupId)` → `isPostingAllowed(groupId)`（N04）；`voteBySenderId` / `clearVoteBySenderId` / `refreshVoteBySenderId` 改 `voteByTargetSenderId` / `clearVoteByTargetSenderId` / `refreshVoteByTargetSenderId`（N05）。**入参保持 `targetSenderId`**：它同时是 `SenderBanVoteCast.targetSenderId`（由 event-standards §6.1 的 `gc.ban-vote` 槽位冻结）与 `TargetState` 的内部键，按 §3 硬约束 4 的例外让**函数名**让位，而不是改入参——否则 §十一 的四处同源会断。
  - **P1 一致性**：`GroupChatBanList` 的 `_groupAddress` / `_groupDelegateAddress` 与 `GroupMember` 的 `_groupDelegateAddress` 改全大写 immutable `GROUP_ADDRESS` / `GROUP_DELEGATE_ADDRESS`（N10）；`ManagedAction.token` → `tokenAddress`（N14）；`delegateIdOf` / `delegateIdsOf` → `effectiveDelegateId` / `effectiveDelegateIdsByGroupIds`（`delegateId(groupId)` 会与 `setDelegateId` 的入参 `delegateId` 撞 solc 8760，按 §3 硬约束 4 的例外让函数名让位）、`ownerOrDelegateIdOf` → `ownerOrDelegateId`、`voteWeightOf` → `voteWeight`（N20）。
  - **P2 卫生**：四处 `_states` 按 §8.3 改 `_adminState` / `_chatState` / `_memberState` / `_chatState`（N11）；接口入参去 `_` 后缀（N12）。
  - **去后缀的连带改名**：入参去 `_` 后与同名 getter 撞，批量入参按 §7.3 改写为 `adminIdList` / `memberIdList`（写方向，与内部双向辅助同名）、`checkedMemberIds`（判断）、`requestedGroupIds` / `requestedRounds` / `requestedProposalIds`（读入参）；`roundInfos` 的载荷是轮次而非 id，按 §7.3 改 `roundInfosByRounds`，不套 `Ids`；`activateChat` 的四个槽位入参改 `scopeSourceAddress` / `banSourceAddress` / `beforePostPluginAddress` / `afterPostPluginAddress`（避开 `scopeSource()` 等 getter，同时满足 §十 的实体地址后缀）。
  - **同批人工核对**：全部构造函数入参去 `_` 后缀；`GroupChat` 局部 `message_` 改 `storedMessage`、重入锁 `_entered` 改 `_reentrancyStatus`（§8.4）；`ownerOrDelegateId` 的入参 `account` 改 `operatorAddress`。
  - **地址后缀**（§十，core / action 早已按此扫过）：构造函数入参与对应 getter 对齐为 `groupAdminAddress` / `groupDelegateAddress` / `groupChatAddress` / `banSourceAddress` / `beforePostPluginAddress` / `afterPostPluginAddress` / `actionTargetAddress` / `groupBanListAddress` / `groupMemberAddress` / `groupActionExecutorAddress`；Manager 的 `address token` 入参与局部变量改 `tokenAddress`，`actionByGroupId` 的返回名同步。
  - **中缀 `Of` 收口**（§7.7；当时 N20 只匹配结尾 `Of`，这批靠人工，第三轮已收紧检查器）：`tokenOfGroup` / `groupIdOfToken` / `actionOfGroup` / `groupIdOfAction` / `groupIdsOfActions` / `actionsOfGroups` → `tokenAddressByGroupId` / `groupIdByTokenAddress` / `actionByGroupId` / `groupIdByActionId` / `groupIdsByActionIds` / `actionsByGroupIds`；`actionsByToken` / `actionsByTokenCount` 的 `Token` 在 `token`→`tokenAddress` 后不再与入参同名，按 §7.3 的作用域键规则改为 `actions`（`tokenAddress` 是定位不是筛选），其 Count 入口在同批分页收口中删除。成对映射同步按 §8.3 补齐键：`_tokenOfGroup` / `_groupIdOfToken` / `_actionOfGroup` / `_groupIdOfAction` → `_tokenAddressByGroupId` / `_groupIdByTokenAddress` / `_managedActionByGroupId` / `_groupIdByActionId`。
  - **第三轮（review 后的收口）**：`N20` 由「结尾 `Of`」收紧为「含中缀 `Of`」，内部辅助同步改名（`_ownerOfOrRevertGroupNotExist` → `_ownerOrRevertGroupNotExist`、`_groupOwnerOfOrRevert` → `_groupOwnerOrRevert`、`_memberOwnerOfOrZero` → `_memberOwnerOrZero`）；`N05` 由「只查 `Id|Ids|Address|Addresses` 结尾的 Key」收紧为「全部 Key」，并补用途前缀词干规则（写方向 `<noun>List`、`checked`、`requested`），全仓 0 违规——这轮抓出并修掉 `messagesByMention*` / `messagesByMentionAll*` 六个函数：前三个改 `messagesByMentionedSenderId` / `messageIdsByMentionedSenderId`（Key 取 `mentionedSenderId`），后三个因条件没有入参改形容词前缀 `mentionAllMessages` / `mentionAllMessageIds`。
  - **冻结值补 public**：`GroupChatBanList.GROUP_ADDRESS` / `GROUP_DELEGATE_ADDRESS`、`GroupMember.GROUP_DELEGATE_ADDRESS` 由 `internal` 改 `public` 并进接口——与同仓其余四个合约一致，`21_check.sh` 补三条绑定校验。
  - **集合查询统一分页签名**：18 个分页入口全部改为 `(offset, limit, reverse) → (列表, totalCount)` 且返回值具名，删除 15 个 `*Count`——包括旧 ABI 保留的 11 个。判据是「同一集合只留一条完整读取路径」：`delegatedGroupIds` 已经返回 `totalCount`，旁边却仍留 `delegatedGroupIdsCount`，同一集合两条计数路径；其余 12 个分页不带 `totalCount`，调用方只能先 count 再翻页，两次调用之间状态可变。`limit = 0` 是唯一计数入口。`memberIds` / `senderIdBanList` / `delegatedGroupIds` / `votedSenderIds` / `votersBySenderId` 补 `reverse`：`Uint256Set` 删除是 swap-and-pop，`reverse` 只承诺逆序遍历当前存储顺序，规格写明 offset 不跨调用稳定。
  - **`MessageState` → `MessageRecord`**：消息的 content / round / blockNumber / timestamp 是发言时快照，写入后永不改写；`State` 会被读成「存在状态迁移」，与 `RoundState`（游标推进）、`AdminState`（集合增删）混为一谈。`Record` 与 `action` 的 `VoteRecord` 同义，按 §8.6 新增的判据改名。
  - **取消无键 `ByIds`**：`proposalInfosByIds` → `proposalInfosByProposalIds`（入参同批从裸 `ids` 改 `requestedProposalIds`，`proposalIds()` 分页 getter 占用了最自然的名字）、`voteAmountsByMemberIdByIds` → `voteAmountsByMemberIdByProposalIds`、`chatInfosByIds` → `chatInfosByGroupIds`。`ByIds` 不指名 Key，违反 P2：若主键不言自明则 `Ids` 也可省，若不言自明则 `Ids` 不够；而函数名又必须区分「按 id 批量」与「分页」，所以只能写明 Key。检查器 N05 同批删掉 `ByIds` 特例分支，规则收成一条：每个 `By<Key>` 的 Key 必须等于入参名或入参名去掉用途前缀。
  - **`By<Key>` 收口为全等匹配**：`messagesBySender` / `messageIdsBySender` / `messagesByMentionedSender` / `messageIdsByMentionedSender` / `voteWeightsBySenderIdsByVoter` → `messagesBySenderId` / `messageIdsBySenderId` / `messagesByMentionedSenderId` / `messageIdsByMentionedSenderId` / `voteWeightsBySenderIdsByVoterId`；`core` 的 `proposalIdBySubmitter` → `proposalIdBySubmitterId`，`action` 的 `rewardByRecipient` / `serviceRewardByMember` → `rewardByRecipientId` / `serviceRewardByMemberId`。`N05` 同批去掉 `Id`/`Ids` 类型后缀豁免，只保留用途前缀——`Id` 是类型标记，`BySender` 省四个字符却让读者分不清 Key 是 id 还是 address（旧仓 address 主体路径恰叫 `sender`）。全仓 0 违规。
  - **检查器口径修正**：`ENTITY_NAMES` 去掉 `owner` / `recipient`——§十 明确这两个是角色地址、保留角色名，`ChatInfo.owner` 因此不再算 N14 违规（与事件族 `gc.management` 的 `owner` 槽位一致）。该修正对 `core` / `action` / `libs` 同样生效，当前三仓无符号依赖被去掉的两项。
- 检查器只看声明形态，不能判断"是否有第二个写入口"。构造函数或 `init` 写入的 public 状态需人工判定是否冻结；判定为冻结即按 §3.1 改全大写。N17 的 Layout 例外同样只看 struct 名（`Layout`/`*Layout`），不判断字段是否冻结；Layout 内新增字段需人工核对，只有部署后冻结的字段才能用 UPPER_SNAKE。
- 构造参数、局部变量、事件字段与 §8.3 的存量映射名不在检查器范围内，按 §十五 清单人工核对。**P2 现在有机械校验**：N05 覆盖全部 Key，只允许用途前缀（写方向 `<noun>List` / `checked` / `requested`）取词干，其余 `By<Key>` 一律要求与入参同名，全仓 0 违规。
- **§8.3 存量映射名**：`group-chat` 已按 §8.3 清完（`_chatConfig`、`_messagesByGroupId`、`_messageIndexesByGroupIdBySenderId`、`_messageIndexesByGroupIdByMentionedSenderId`、`_mentionAllMessageIndexesByGroupId`、`_senderIdsByGroupId`、`_roundStateByGroupIdByRound`、`_roundsByGroupId`、`_delegateState`、`_delegationAcceptanceEnabledByDelegateId`）。`core` / `action` 不清：这两仓的映射绝大多数是「按 `tokenAddress` 取标量」的单键表，而 `tokenAddress` 按 §7.3 是**作用域键、不进名字**，再加 `ByTokenAddress` 是噪音；`_validGovVotesByMember` / `_lastSettlePhase` 两处同样按词干规则与作用域键规则判为可接受。判据本身无法机械化（"读者能否从名字说出键"），故不入检查器。
- **test/ 的 `_` 后缀**：§一 明确 test/ 不受门禁。本批清掉了所有非冲突项（`originBlocks_`、`phaseBlocks_`、`groupAddress_`、`chat_`、`groupDelegate_`、`reenterGroupId_`、`reenterSenderId_`、`maxGroupNameLength_`、`nameUsed_`、`actualCost_`、`mockVoteWeight_`、`postAllowed_` 等，含 `test/utils/TestBase` 新增的 27 个读取辅助）；剩下的 43 处是**参数与 mock/夹具自身状态变量同名**（`groupId` / `senderId` / `adminId` / `allowed` / `banned` / `postingAllowed` / `mintCost` / `symbol` / `memberNFTAddress` / `phaseAddress` / `voteWeight`），按 §3 硬约束 4 只能让参数让位，去掉 `_` 会撞 8760。另有 8 处 `tm_` / `am_` 是**群名类型码字符串**（`type[_payload]_random` 的格式字符），不是标识符，不改。
- **`N04` 收紧到具名返回（2026-10-31）**：检查器原先只匹配未命名的 `returns (bool)`，`returns (bool joined)` 从规则下漏过。现按「单个 `bool` + 可选返回名」判定，与 §十五 的「单 bool 返回是谓词；tuple 内的 bool 不受限」对齐。同批删除 `GroupServiceExecutor.joinInfo`——服务侧唯一一处具名单 bool 带参返回（一行转发 `ActionTarget.isJoinedByRound`，服务没有独立加入状态），且与 `GroupActionExecutor.joinInfo` 同 selector、不同返回形态。删除后四仓 0 违规，基线仍 0 条。
- **状态变量 ↔ getter 对账（2026-10-31）**：四仓 `src/` 共 216 个状态变量（core 120 / action 38 / group-chat 58；`libs` 无），逐个与直接返回它的 `view`/`pure` 函数配对：38 个有同名 getter，71 个走派生读，107 个只被写路径使用。派生读中 69 处合法（§7.7 单实体属性读、§7.3 作用域键省略、§7.2 Kind、聚合读、子集读、§十 分层、谓词），修掉两处状态变量名与 getter 对不上的存量：
  - `MemberNFT._allHolders` → `_holders`：getter 是 `holders()`，§8.4 早已点名「`_allHolders` 的 `all` 是噪音」，属唯一残留。`internal`，ABI 不变。
  - `Submit._authorProposalIds` → `_proposalIdsByAuthor`：getter 是 `proposalIdsByAuthor()`，§8.3 的合格形态是 `<value>By<Key>`，原名把键放在了值前面。`internal`，ABI 不变。
- **`votesByVerifierIds` → `voteAmountsByVerifierIds`（2026-10-31）**：§6 与 §7.3 曾把它当作 `By<Key>Ids` 的正例，但 §9 禁止裸 `votes` 表示投出的票数（分不清标量与数组），而该函数的返回值本来就叫 `voteAmounts`、状态变量也叫 `voteAmountByApplicationId`——规范内部冲突，按 §9 收口。`GroupActionVerify` 库函数、`GroupActionExecutor` 转发、接口、测试、`specs/action/05`、`specs/action/08` 与 §6 的例子同批改写。**破坏性 ABI 变更**，旧 selector 不可复用；入参 `verifierIds` 不变，`By<Key>Ids` 的 Key 仍与入参同名。
- **事件名 ↔ 函数名同词干收口（2026-10-31）**：逐个核对 81 个 `emit` 点，修掉两处配置写入口与事件名不一致的存量：
  - `updateGroupConfig` → `setGroupConfig`：同类「配置写入」只有一个 `setRecipients`，它已是 `set<配置对象>` 且与 getter `recipients()` 同词干；生命周期（`activateGroup` / `deactivateGroup`）与额度（`addProviderQuota` / `removeProviderQuota` / `withdrawProviderQuota`）按 §4.1 动词表各自成类，不参与本条。事件 `GroupConfigChanged` 不变。`IGroupActionManager`、`GroupActionManager`、`GroupActionExecutor` 转发与两个测试同批改写，**破坏性 ABI 变更**。
  - `RecipientTableChanged` → `RecipientsChanged`：函数与 getter 都是 `setRecipients`/`recipients`，只有事件用了库内部结构体名 `RecipientTable`，事件宾语与函数不一致；payload 与 `action.recipients` 族槽位不变，**topic0 变化**。`setRecipients` 函数名保留。
  - 未改但已登记：`withdrawProviderQuota` 与 `removeProviderQuota` 共用 `ProviderQuotaRemoved`（事件建模「授权额度减少」维度，见 `REVIEW_UNCOMMITTED_2026-10-30.md`）；`mintMemberReward` 另发 `ServiceRewardsDistributed`（一个入口两个事实）。两者不满足「事件名 = 函数词干」，属有意例外。
  - 检查器缺口：`check_naming.py` 不扫事件，`check-events.py` 只查族/槽位/写法/ABI 基线；「事件名 ↔ 发射函数名」仍靠人工核对。
- **守卫统一 `_check*`（2026-11-01）**：三仓 `src/` 的 35 个 `internal`/`private` 守卫统一为 `_check<宾语>`（core 13 / action 7 / group-chat 15），92 个调用点（127 次出现含 35 处定义）。归因：20 个由 `_require*` 改名（core 7 / action 3 / group-chat 10）、11 个由 `_validate*` 并入（core `_checkName` / `_checkProposalBody`；action `_checkGroupConfig` / `_checkActivationMinGovRatio` / `_checkGroupConstraints` / `_checkRecipients`；group-chat `_checkAdminIdList` / `_checkMentionedSenderIds` / `_checkPluginAddress` / `_checkQuotedMessageId` / `_checkSourceAddress`）、4 个自始即 `_check*` 未动（`_checkValidTokenSymbol`、`_checkDistributorMode`、`_checkPromisedWaitingPhases`、`_checkSlippage`）；`src/` 已无 `_validate*`——部署脚本（`script/deploy/` 的 `_validateConfig` / `_validateDeployment` 等）不在本条款范围内，`dev-standards` §6 另有规定。同批的宾语收口：`_checkProposalExists` → `_checkExistingProposal`（存在性统一 `Existing`）、`_checkSenderIdTarget` 与 `_checkTarget` → `_checkTargetSenderId`（同一零值校验只留一个名字，宾语取错误载荷的 `targetSenderId`，不按各自入参分叉）、`_ownerOrRevertGroupNotExist` → `_groupOwnerOrRevert`（与 `GroupAdmin` 同名同义，函数名不再嵌错误名）。判据是逐字读：`require + 名词` 读作「需要该对象」（`_requireSlippage` = 需要滑点），与「校验该对象合法」错位；`check + 宾语` 才是及物的「检查」。§4.1 把新增的守卫条款改写为**两族**——守卫 `_check<宾语>`（`view`/`pure`、不满足即 revert、存在意义是拦截）与取值型 `_xxxOrRevert`（存在意义是取值，revert 只是取不到的分支，`group-chat` 4 个函数名 / 5 处定义（`_groupOwnerOrRevert` 在 `GroupAdmin` 与 `GroupChat` 各一份）/ 16 个调用点保留后缀），并写明「守卫通过后返回判定过程中已经算出的值」与宾语用词；§4.2 澄清 `check*` 的禁用只针对返回 bool 的公开判断；§十五 补一条取值型不入 `_check*`。另两处仅 ABI 元数据（selector 不变）：`ISubmit.submitNewProposal` 入参 `body` → `proposalBody`、`ExecutorBase.onProposalSubmitted` 按 `IProposalTarget` 补四个参数名。全部改动都是 `internal`/`private`，ABI 面不变。同批给 `check_naming.py` 补 **N24**（`_(require|validate)[A-Z]` 即报），把这条从人工核对改为门禁——检查器只收各仓 `src/`，`script/deploy/` 的 `_validateConfig` / `_validateDeployment` 与 `test/` 的 `_requireInitRevert` 等辅助天然在外，无需白名单。
- **私有分页辅助去 `Page`（2026-11-01）**：按 §7.5「分页不进名字」收口五处——`GroupActionJoin._pageProviderIds` → `_providerIds`、`GroupActionVerify._pageMembers` → `_memberIds`、`GovVotedBanSource._votersPage` → `_voters`、`GroupChat._uint256Page` → `_uint256Values`、`GroupChat._messagesPage` → `_messages`；全部 `internal`/`private`，ABI 不变。

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
- [ ] 守卫是 `_check<宾语>`（`view`/`pure`、不满足即 revert、存在意义是拦截），不是 `_require<名词>`，也不是 `_validate<名词>`（`test/`、`script/deploy/` 除外，见 §一 与 `dev-standards` §6）。
- [ ] 取值型读辅助是 `_xxxOrRevert`，没有改成 `_check*`；函数名里不嵌错误名。
- [ ] `check_naming.py --check` 无新增。

## 附录 A：P0 改名表（已全部落地）

`core` / `action` / `group-chat` 三仓均已落地（2026-10-30），下表留作迁移记录。

| 旧名 | 新名 | 规则 |
| --- | --- | --- |
| `postingAllowed(groupId)` | `isPostingAllowed(groupId)` | N04 |
| `voteBySenderId(groupId, targetSenderId, …)` | `voteByTargetSenderId(groupId, targetSenderId, …)` | N05 |
| `clearVoteBySenderId` / `refreshVoteBySenderId` | `clearVoteByTargetSenderId` / `refreshVoteByTargetSenderId`，入参不变 | N05 |

## 附录 B：检查器规则编号

| 编号 | 规则 | 作用域 |
| --- | --- | --- |
| `N01` | 函数名 lowerCamelCase（冻结值 getter 除外） | 全部函数 |
| `N02` | 禁用动词前缀 | 全部函数 |
| `N03` | 带参数的函数不得全大写 | external/public |
| `N04` | 带参数的单个 bool 返回必须是谓词（具名与否同判） | external/public |
| `N05` | `By<Key>` 的 Key 必须与某个入参同名（允许去掉 `added`/`removed`/`checked`/`requested` 用途前缀） | external/public |
| `N06` | `Count` 必须在末尾 | external/public |
| `N07` | 禁用词（`num`/`amt`/`addr`/`tmp` 等） | 全部标识符 |
| `N08` | 状态变量 `_` 前缀与可见性匹配 | 状态变量 |
| `N09` | 常量 UPPER_SNAKE 且无 `_` 前缀 | 状态变量 |
| `N10` | immutable UPPER_SNAKE 且无 `_` 前缀 | 状态变量 |
| `N11` | 名字不得过短或为裸 `state`/`data`/`info` | 函数、状态变量 |
| `N12` | 接口参数不带 `_` 后缀 | 接口 |
| `N13` | 禁 `Data` 后缀 | 函数、状态变量 |
| `N14` | `address` 实体字段必须带 `Address` 后缀；角色地址（`owner`/`recipient`/`distributor`/`operator`）与流向地址（`from`/`to`）按 §十 保留角色名（参数同规则，人工核对） | 结构体字段 |
| `N15` | 接口名 `I` + PascalCase | 接口 |
| `N16` | 枚举成员 PascalCase | 枚举 |
| `N17` | 结构体字段 lowerCamelCase（Layout 的冻结字段可 UPPER_SNAKE，冻结判定人工） | 结构体 |
| `N18` | modifier `only<Role>` / `non<State>` | modifier |
| `N19` | internal/private 函数带 `_`，public/external 不带 | 函数 |
| `N20` | 禁 `Of`（含中缀，ERC 覆写除外） | external/public |
| `N21` | `total*` 只用于社区级聚合 | external/public |
| `N22` | 禁单字母语义前缀 `g` | 全部函数 |
| `N23` | 禁止外部函数重载 | external/public |
