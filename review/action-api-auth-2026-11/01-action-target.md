# ActionTarget 接口调用权限审查

> 对象 `action/src/ActionTarget.sol`（531 行）
> 接口 `action/src/interfaces/IActionTarget.sol`（186 行，`is IProposalTarget`）
> 基线 `action@e849e36`（工作树干净）；审查日期 2026-11-03
> 判据 dev-standards §5.5（调用者校验）、§5.4（`init`）、§5.7（校验分层）、§4.2（事件）；`specs/action/01-action-target.md`、`specs/action/07-minting.md`

## 一、结论

| 项 | 数值 |
| --- | --- |
| ABI 函数 | 24（写 8 / 读 16） |
| 鉴权 modifier | 4（`onlyBoundExecutor`、`onlySubmit`、`onlyVote`、`onlyMemberOwner`） |
| 无许可写入口 | 1（`init`） |
| 发现 | 5 条：Medium 1（同源）/ Low 1 / Info 3；另有 2 条正面结论 |
| 接口对账 | 24 vs 24，**0 差异** |

一句话：**这是全仓权限的汇聚点——三个 Executor 的写入权、Core 的三类回调、成员的兜底清理，全部在这里被判定；8 个写入口里 7 个挂了 modifier 且都是首道判定，唯一无许可的 `init` 是规范明示的一次性入口。真正的风险不在业务入口，而在 `init` 抢跑会把 4 个鉴权根一次性换掉。**

## 二、权限模型

| 权限主体 | 判定 | 覆盖入口 |
| --- | --- | --- |
| 已绑定 Executor | `_executorByActionId[token][id] != 0 && == msg.sender` | `registerJoinState`、`clearJoinState`、`mintActionReward` |
| Core `Submit` | `msg.sender == SUBMIT_ADDRESS` | `onProposalCreated`、`onProposalSubmitted` |
| Core `Vote` | `msg.sender == VOTE_ADDRESS` | `onProposalVoted` |
| `memberId` 当前持有人 | `IMemberNFT(MEMBER_NFT_ADDRESS).ownerOf(memberId) == msg.sender` | `forceClearJoinState` |
| 任何地址 | 只判 `initialized` | `init` |
| 无 | — | 16 个只读入口 |

`_isBoundExecutor`（`L98`）是唯一需要「非零 + 相等」双条件的判据：

```solidity
address bound = _executorByActionId[tokenAddress][actionId];
return bound != address(0) && bound == msg.sender;
```

先判 `bound != 0` 是必需的——未绑定行动的所有者是零地址，只写 `bound == msg.sender` 会让「任何地址调用未绑定行动」变成「零地址调用」，虽然实际仍不成立，但依赖 `msg.sender != 0` 这个 EVM 保证而非合约语义。这条与 core 侧 `ownerOrDelegateIdOf` 的 0 哨兵陷阱同型，此处写法正确。

## 三、入口清单

### 写入口（8）

| 函数 | 权限主体 | 鉴权实现 | 首道判定 | 事件 |
| --- | --- | --- | --- | --- |
| `init(address)` | 无（一次性） | `if (initialized) revert AlreadyInitialized` | 是 | **无** |
| `registerJoinState(address,uint256,uint256)` | 已绑定 Executor | `onlyBoundExecutor` `L113` | 是 | `JoinStateRegistered` |
| `clearJoinState(address,uint256,uint256)` | 已绑定 Executor | `onlyBoundExecutor` `L144` | 是 | `JoinStateCleared(forced=false)` |
| `forceClearJoinState(address,uint256,uint256)` | `memberId` 持有人 | `onlyMemberOwner` `L171` | 是 | `JoinStateCleared(forced=true)` |
| `mintActionReward(address,uint256,uint256)` | 已绑定 Executor | `onlyBoundExecutor` `L264` | 是 | `ActionRewardMinted` |
| `onProposalCreated(address,uint256,bytes[])` | Core `Submit` | `onlySubmit` `L423` | 是 | `ActionRegistered` |
| `onProposalSubmitted(address,uint256,uint256,bytes[])` | Core `Submit` | `onlySubmit` `L471` | 是 | 无（转发） |
| `onProposalVoted(address,uint256,uint256,uint256,uint256,bytes[])` | Core `Vote` | `onlyVote` `L500` | 是 | 无（转发） |

### 只读入口（16）

配置 getter 6：`initialized`、`MEMBER_NFT_ADDRESS`、`SUBMIT_ADDRESS`、`VOTE_ADDRESS`、`MINT_ADDRESS`、`PHASE_ADDRESS`。

加入态查询 6：`isJoined`、`isJoinedByRound`、`joinedRounds`、`actionIdsByMemberId`、`memberIdsByActionId`、`executorByActionId`。

索引与激励 4：`actionReward`、`actionIdsByExecutor`、`actions`、`votedActions`。

读面边界：`isJoinedByRound` 与 `memberIdsByActionId` 对 `round > _joinRound()` 直接返回 false / 空数组（`L212`、`L257`），不回滚；`actionReward` 对未绑定行动返回 `(0,false)` 不委托 Mint（`L290`）；`votedActions` 内部以 `limit = type(uint256).max` 全量读 Vote（`L399`），是本合约唯一一次无界内部读取。

## 四、逐入口判定

### `init` — 一次性，但换掉的是四个鉴权根

`init(mintAddress)` 只判 `initialized`，无调用者限制（§5.4）。它从 Mint 派生四项：

| 派生值 | 决定什么 | 错绑/抢跑的后果 |
| --- | --- | --- |
| `SUBMIT_ADDRESS` | `onProposalCreated`/`onProposalSubmitted` 的唯一合法调用者 | 伪造「提案已创建」，可为任意 `(token, proposalId)` 绑定任意 Executor |
| `VOTE_ADDRESS` | `onProposalVoted` 的唯一合法调用者 | 伪造投票回调，篡改验证者票数与排名 |
| `MEMBER_NFT_ADDRESS` | `forceClearJoinState` 的鉴权函数 | 任意地址可清理任意成员的加入态 |
| `PHASE_ADDRESS` | `_currentRound()` / `_joinRound()` | 加入轮与创建轮全部失真 |
| `MINT_ADDRESS` | 行动级铸造的唯一出口 | 铸造流向攻击者控制的合约 |

四项都在 `init` 内各读一次并缓存（`L57-67`），运行期不再判初始化——符合 §5.4「初始化只在部署阶段校验」。兜底在 `DeployAction.s.sol` 广播前与 `21_check.sh` 部署后。见 **AT-01**。

### `registerJoinState` — 唯一写入加入态的入口

- 鉴权：`onlyBoundExecutor`；未绑定行动的**任何**调用者都拒绝（含零地址绑定）。
- 首道业务校验：`currentRound <= createdRound` → `JoinNotOpen`（`L120`）。加入在投票后一个阶段开放，与 `JoinStateRegistered.round = currentRound - 1` 同源。
- 幂等：`contains(memberId)` 为真时直接 `return`，不改状态、不发重复事件（`L123`）。
- 无 `createdRound == 0` 分支：`createdRound` 与 `_executorByActionId` 在同一笔 `onProposalCreated` 内成对写入（`L450-453`），因此「已绑定但未创建」不可达。这一点使 `JoinNotOpen` 的载荷里 `createdRound` 恒非零，链下无需处理哨兵值。

### `clearJoinState` / `forceClearJoinState` — 同一份清理，两个权限主体

两者清理逻辑逐行相同（`remove` 三处状态 + 发 `JoinStateCleared`），差异只在权限主体与 `forced` 字段：

| 入口 | 主体 | 是否要求已加入 | 是否回调 Executor |
| --- | --- | --- | --- |
| `clearJoinState` | 已绑定 Executor | 否（不在则 `return`） | — |
| `forceClearJoinState` | `memberId` 持有人 | 否（不在则 `return`） | **否**（设计如此） |

`forceClearJoinState` 不回调 Executor 是规格明文要求（`01-action-target.md`「forceClearJoinState」节）：调用它本身意味着 Executor 已不可信。后果是注册表与 Executor 仓位会短暂不一致，需要索引器把两者当两个对象——规格已写明，本报告只登记「这条不回调是权限设计，不是遗漏」。

两者都用 `_joinRound()`（`L382`，= `currentPhase - 1`，phase 为 0 时返回 0）作为事件 `round`。`clearJoinState` 没有轮次校验，规格说明理由是「已加入本身蕴含加入轮已开放，且轮次单调不减」。

### `mintActionReward` — 铸造的唯一出口

- 鉴权：`onlyBoundExecutor`，因此不存在「持 A 行动的 Executor 铸 B 行动的激励」。
- 唯一业务校验：`IVote.isProposalIdVoted(tokenAddress, round, actionId)`（`L269`）→ `ProposalNotVoted`。
- 收款方强制为 `bound`（`L273-275`），不由调用者指定——这是本条最重要的权限性质：Executor 只能把激励铸给自己，不能再导向第三方。
- 去重不在本合约：重复调用由 Mint 回滚 `ProposalRewardAlreadyMinted`（`L274` 注释）。
- **不校验 `round` 是否在铸币窗口内**（见 AT-02）。

### 三类回调

| 回调 | 门禁 1 | 门禁 2 | 门禁 3 |
| --- | --- | --- | --- |
| `onProposalCreated` | `onlySubmit` | `targetData[0]` 恰 32 字节 → 有代码 → 握手 `ACTION_TARGET_ADDRESS() == address(this)` | `_executorByActionId != 0` → `AlreadyCreated` |
| `onProposalSubmitted` | `onlySubmit` | `bound != 0` → `UnboundProposal` | `targetData[0] == bound` → `TargetDataExecutorMismatch` |
| `onProposalVoted` | `onlyVote` | `bound != 0` → `UnboundProposal` | `targetData` 非空时 `targetData[0] == bound` |

创建回调的写入顺序是「先写映射与索引 → 发 `ActionRegistered` → 再转发 Executor 的 `onProposalCreated`」（`L450-468`）。先写后转发意味着 Executor 在自己的回调里可以读到已建立的绑定，且 Executor 回调失败时整笔回滚、不留半截注册。这个顺序与 `00-executor-interface.md`「先登记注册表事实，再进入 Executor 的 `onProposalCreated`」一致。

`onProposalCreated` 不校验 `tokenAddress` 是否为已登记 LOVE20 代币——该职责在 Core `Submit`（提案创建时校验代币登记）。本合约只把 `(tokenAddress, proposalId)` 当复合键。

## 五、发现

### AT-01（Medium，与 core DEP-01 同源，不新增计数）`init` 抢跑 = 一次替换四个鉴权根

- 证据（`L51-68`）：无调用者限制，只判 `initialized`；`SUBMIT_ADDRESS`、`VOTE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`、`MINT_ADDRESS` 全部来自 `init` 入参 `mintAddress` 的 getter。
- 后果分级（按严重度）：

  1. **`SUBMIT_ADDRESS` + `VOTE_ADDRESS`**：攻击者成为唯一合法回调者，可对任意 `(token, proposalId)` 伪造创建/推举/投票，从而给任意地址建立 Executor 绑定，并让该 Executor 获得 `registerJoinState`/`clearJoinState`/`mintActionReward` 三项写入权。这是「换掉鉴权根」而非「换掉参数」。
  2. **`MEMBER_NFT_ADDRESS`**：`forceClearJoinState` 的鉴权函数被替换。
  3. **`MINT_ADDRESS`**：行动级铸造流向攻击者控制的合约。
  4. **`PHASE_ADDRESS`**：加入轮/创建轮整体偏移。

- 为什么当前不构成可利用缺陷：§5.4 与 §5.7 明确把「部署期静态不变量」划给部署脚本，`DeployAction.s.sol` 在广播前校验、`21_check.sh` 部署后复核；规范同时明说「不能把『部署后立即初始化』当作防抢跑保证」。本报告只补一条权限后果的描述：**ActionTarget 的 `init` 不是「换参数」，是「换掉全部回调鉴权与成员鉴权」**，其后果量级高于三个 Executor 的构造函数（后者只绑定自己的依赖，不影响他人）。
- 建议：在 `01-action-target.md` 的 `init` 段落显式写出「四项派生值是本合约全部写入口的鉴权根」，并在 `DeployAction.s.sol` 的广播前校验里把「`init` 必须是部署脚本发出的第一笔 ActionTarget 交易」写成断言（当前只校验绑定结果，不校验时序）。

### AT-02（Low）`mintActionReward` 不校验铸币窗口，`round` 完全由 Executor 自选

- 证据（`L264-283`）：入参 `round` 只用于 `isProposalIdVoted` 与转发 Mint，本合约不判 `round <= currentMintRound()`，也不判 `round >= createdRound`。
- 实际可达范围由三个 Executor 各自收窄：`LpExecutor._mintMemberReward`、`GroupActionExecutor._mintMemberReward`、`GroupServiceExecutor._mintMemberReward` 都先过 `_checkMintWindow`（`ExecutorBase.sol:107`），要求 `createdRound <= round <= _mintRound()`。所以单看 `action` 仓，越界不可达。
- 仍然登记的原因：本合约是**唯一的铸造入口**，它的入参契约里没有窗口约束，窗口约束是调用方的实现细节。若将来新增一个 Executor（ActionTarget 允许提案绑定任意 Executor，见 AT-03），新实现漏掉 `_checkMintWindow` 就能对任意已结束轮次发起铸造。
- 权限后果的具体形状：Mint 的 `_prepareRewardIfNeeded` 在**准备时点**按 `rewardAvailable(tokenAddress)` 定池（`core/src/Mint.sol:126-128`），因此「谁能决定准备时点」等价于「谁能决定各轮池子的相对大小」。`round` 不设窗口时，这个决定权落在 Executor 手里；设了窗口后仍可决定「过去各轮的准备顺序」，但无法提前准备未来轮次。
- 建议：把 `round` 的窗口约束下沉到 `ActionTarget.mintActionReward`（一次 `IPhase.currentPhase()` 读取），或至少在规格里写明「本入口不校验轮次，窗口由 Executor 负责」，让新实现的作者看得到这条契约。

### AT-03（Info）`onProposalCreated` 只做握手，不校验 Executor 的实现来源

- 证据（`L434-447`）：唯一门槛是「有代码 + `ACTION_TARGET_ADDRESS()` 返回 `address(this)`」。没有注册表、没有白名单、没有实现指纹。
- 后果：提案创建者（任何能提交 Proposal 的成员）可以绑定一个自造合约作为 Executor。该合约随即获得该 `(tokenAddress, actionId)` 上的 `registerJoinState`/`clearJoinState`/`mintActionReward` 三项权限，可以把该行动的整笔激励铸给自己而不分给参与者，也可以随意改写加入态注册表。
- 为什么不是缺陷：行动的资金来自加入者自愿 `join`，而 `targetData[0]` 在提案正文里对投票者可见——「这个行动由哪个 Executor 结算」是投票决策的一部分。这与 core 的 `Mint.mintProposalReward` 认「提案 target 地址」同型：授权主体可以把权益导向任意地址，但主体本身由治理选出。
- 建议：在 `01-action-target.md` 的创建回调段落补一句「Executor 的实现来源不在本合约的校验范围，风险由提案投票承担」，避免集成方误以为存在可信 Executor 名单。

### AT-04（Info）写入口对未绑定行动的错误面不一致

- 三个 Executor 写入入口对未绑定行动一律 `UnauthorizedExecutor(tokenAddress, actionId)`（`_isBoundExecutor` 的 `bound != 0` 分支）。
- 只有 `forceClearJoinState` 对未绑定行动放行（幂等空操作），因为它的权限主体是成员而非 Executor，且规格要求它在 Executor 失效时仍可用。
- 判定：这是有意的差异，不是缺陷。但链下若要区分「行动不存在」与「我不是该行动的 Executor」，`UnauthorizedExecutor` 的载荷里没有区分位——两种情形共用一个 selector。建议在错误目录里把这一条标注为「同时表示未绑定与调用者不匹配」。

### AT-05（Info）`votedActions` 的无界内部读取是全仓唯一一处

- 证据（`L399-405`）：`IVote.votedProposalIds(tokenAddress, round, 0, type(uint256).max, false)`。
- 影响面：`votedActions` 本身是只读（`eth_call` 不计 gas），但 `GroupServiceExecutor._votedGroupActions`（`GroupServiceExecutor.sol:648`）在**每次结算**里都走这条路径，成本落在交易上。
- 规模上界：规格称「列表规模上界由 Submit 的每轮提案数上界保证」，但该上界不在 `action` 仓内，本仓无法自证。建议在 `06-service-executor.md` 或 `01-action-target.md` 写明该上界的数值与出处，使「结算成本有界」成为可核对的事实。

### AT-06（正面结论）`_isBoundExecutor` 先判零再比对，避开 0 哨兵陷阱

- 证据（`L98-104`）：`bound != address(0) && bound == msg.sender`。
- 判定：与 core 侧 `ownerOrDelegateIdOf` 曾出现的「0 == 0 放行」缺陷同型，此处写法正确。`ActionTargetEdgeCases.t.sol:165 testUnboundActionWritesRejectedEvenAfterBindingsExist` 用「另一个 Executor 已存在」的场景钉死：`executor` 调用未绑定行动 11 时仍报 `UnauthorizedExecutor`，而绑定者 `second` 调用成功。

### AT-07（正面结论）三类回调构成「调用者 + 绑定 + Target Data」三重门禁

- 创建回调：`onlySubmit` + 握手 + `AlreadyCreated`。
- 推举/投票回调：`onlySubmit`/`onlyVote` + `UnboundProposal` + `targetData[0] == bound`。
- 判定：即使 Core 侧出现缺陷（传错 target 或错 targetData），本合约仍会拒绝——`UnboundProposal` 的存在意义就是「防御 Core 侧缺陷」（规格原话）。`ActionTarget.t.sol:73/158/232` 三个非授权调用者负例分别覆盖三个回调。

## 六、核对证据

```text
$ forge inspect ActionTarget abi --json | jq '[.[]|select(.type=="function")]|length'
24
$ forge inspect ActionTarget abi --json   vs   IActionTarget
0 差异（函数集、签名、返回值、mutability 全等）

$ python3 matt-gov/script/check_caller_auth.py action/src
violations: 0
```

鉴权负例：

| 用例 | 位置 |
| --- | --- |
| 重复 `init` | `test/ActionTarget.t.sol:43` `testInitRejectsSecondCall` |
| 非 `Submit` 调 `onProposalCreated` | `test/ActionTarget.t.sol:73` |
| 非 `Submit` 调 `onProposalSubmitted` | `test/ActionTarget.t.sol:158` |
| 非 `Vote` 调 `onProposalVoted` | `test/ActionTarget.t.sol:232` |
| 非持有人 `forceClearJoinState` | `test/ActionTarget.t.sol:402` |
| NFT 转移后按新持有人判定 | `test/ActionTarget.t.sol:413` |
| 未绑定行动的写入被拒 | `test/ActionTargetEdgeCases.t.sol:165` |

## 七、跨合约位置

| 方向 | 对象 | 关系 |
| --- | --- | --- |
| 被调 | Core `Submit` | `onProposalCreated`/`onProposalSubmitted`（`onlySubmit`） |
| 被调 | Core `Vote` | `onProposalVoted`（`onlyVote`） |
| 调 | 三个 Executor | 三类回调转发；`NotActionTarget` 由 Executor 侧判定 |
| 调 | Core `Mint` | `mintProposalReward`（`onlyProposalTarget` 反向校验本合约为提案 target） |
| 调 | Core `Vote` | `isProposalIdVoted`、`votedProposalIds` |
| 调 | Core `MemberNFT` | `ownerOf`（`forceClearJoinState` 的鉴权函数） |
| 调 | Core `Phase` | `currentPhase`（加入轮与创建轮的唯一来源） |
| 被调 | 三个 Executor | `registerJoinState`/`clearJoinState`/`mintActionReward`（`onlyBoundExecutor`） |
