# GroupServiceStorage · 状态变量变更审查

> `action/src/GroupServiceStorage.sol`，80 行，`action@0c1d1e2`。
> 职责：服务行动的唯一状态根。14 个字段全部是 mapping，3 个编译期常量，外加两个 helper（`cachedDenominator` / `cacheDenominator`）与一个转发（`groupReward`）。
> 与 `GroupActionStorage` 的最大差别：这里的键有**两种主键口径**——配置与结算按「服务代币 + 服务行动」，分母缓存按「行动代币 + 轮」。这是本文件最需要盯的地方。
> 证据分级：**E3** 测试复现 / **E2** 精确算术或字节推导 / **E1** 静态可判定。

## 1. 状态布局

### 常量

| 常量 | 值 | 语义 | 消费方 |
| --- | --- | --- | --- |
| `PRECISION` | `1e18` | 比例精度 | Recipients；Executor 暴露为 `public constant` |
| `DEFAULT_MAX_RECIPIENTS` | `10` | 二次分配接收者上限 | Recipients；Executor 暴露为 `public constant` |
| `MAX_REMARK_BYTES` | `256` | 单条备注上限 | Recipients |

### 字段

| # | 字段 | 主键 | 语义 | 写者 |
| --- | --- | --- | --- | --- |
| 1 | `actionTokenAddressByActionId` | **服务代币** + 服务行动 | 绑定的源行动代币 | Executor |
| 2 | `govRatioMultiplierByActionId` | 服务代币 + 服务行动 | owner 上限乘数（0 = 关） | Executor |
| 3 | `publicVerifierRatioByActionId` | 服务代币 + 服务行动 | 公共验证者分成（≤ 1e18） | Executor |
| 4 | `createdRoundByActionId` | 服务代币 + 服务行动 | 创建轮（0 = 未创建） | Executor |
| 5 | `totalGroupActionRewardByRound` | **行动代币** + 轮 | 分母缓存（0 = 未缓存） | Executor（经 helper） |
| 6 | `memberMinted` | 服务代币 + 服务行动 + 轮 + 成员 | 已结算 | Executor |
| 7 | `verifierRewardByMemberId` | 同上 | 验证者份额 | Executor |
| 8 | `ownerBurnedByMemberId` | 同上 | owner 超限销毁 | Executor |
| 9 | `ownerDistributedByMemberId` | 同上 | 二次分配实际转出 | Executor |
| 10 | `ownerRemainingByMemberId` | 同上 | owner 自留 | Executor |
| 11 | `recipientIdsHistory` | 源代币 + 源行动 + 群（按轮） | 接收者列表 | Recipients |
| 12 | `ratiosHistory` | 同上 | 比例 | Recipients |
| 13 | `remarksHistory` | 同上 | 备注 | Recipients |
| 14 | `actionIdsWithRecipients` | 源代币 + 群（按轮） | 该轮有配置的源行动 | Recipients |

字段 1-4 与 6-10 用服务代币作第一维；字段 5 与 11-14 用**源/行动代币**作第一维。同一个 struct 里两种第一维，是本文件唯一的认知负担来源。

## 2. 逐变量变更逻辑

### 2.1 四个配置槽（Executor `onProposalCreated:425-428`）

| 顺序 | 槽 | 守卫 |
| --- | --- | --- |
| 1 | `actionTokenAddressByActionId` | 非零（`:412`）+ 父子关系（`:418-423`） |
| 2 | `govRatioMultiplierByActionId` | **无上界** |
| 3 | `publicVerifierRatioByActionId` | `<= 1e18`（`:415`） |
| 4 | `createdRoundByActionId` | 写 `currentPhase()` |

四个槽同笔写，`createdRound` 在最后——与 `GroupActionManager:123` 同型。

### 2.2 分母缓存的两个 helper（`:48-63`）

| 函数 | 语句 | 语义 |
| --- | --- | --- |
| `cachedDenominator(self, actionTokenAddress, round)` | `return totalGroupActionRewardByRound[t][r]` | 0 = 未缓存 |
| `cacheDenominator(self, actionTokenAddress, round, value)` | `totalGroupActionRewardByRound[t][r] = value` | **无幂等守卫**，覆盖写 |

`cacheDenominator` 是唯一没有「是否已写」判定的写入 helper：调用方（`GroupServiceExecutor:737-742`）用 `cached == 0 && isRewardPrepared(...)` 双重前置保证只写一次。helper 自身不防重复。

### 2.3 五个结算槽（Executor `:744-770`）

| 槽 | 写点 | 值 |
| --- | --- | --- |
| `memberMinted` | `:744` | `true` |
| `verifierRewardByMemberId` | `:745` | `settlement.verifierReward` |
| `ownerBurnedByMemberId` | `:746` | `settlement.ownerBurned` |
| `ownerDistributedByMemberId` | `:769` | `distribute` 的实际返回值 |
| `ownerRemainingByMemberId` | `:770` | `ownerReward − distributed` |

前三个在 `burn` / `distribute` 之前写，后两个在之后写（必须拿到实际转出额）。

### 2.4 二次分配四槽（Recipients `:96-104`）

见 `09-group-recipients.md` §2.1。三本数组历史 + 一个按轮集合，键都是**源代币 + 源行动**（集合少一层 action）。

### 2.5 `groupReward`（`:69-79`）——不是写入，是唯一的外部读转发

```solidity
return IGroupActionExecutor(groupActionExecutorAddress).generatedActionRewardByGroupId(
    actionTokenAddress, actionId, round, groupId
);
```

本文件唯一的外部调用。它把「群切片」的语义集中在 Storage 层，让 Recipients 与 Executor 不必各自拼参数。

## 3. 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| U1 | 字段 1-4 只在创建回调写一次 | ✅ | 唯一写点 + `ActionTarget.AlreadyCreated` |
| U2 | `totalGroupActionRewardByRound[t][r] != 0` ⟹ 该轮已准备 | ✅ | 唯一写点前置 `isRewardPrepared` |
| U3 | `totalGroupActionRewardByRound` 的键是**行动代币** | ✅ | 唯一写点用 `settlement.actionTokenAddress`（`:738`） |
| U4 | 五个结算槽同键同笔 | ✅ | 同一 `(tokenAddress, actionId, round, memberId)` |
| U5 | `ownerDistributed + ownerRemaining == ownerReward` | ✅ | `:768` 直接定义 |
| U6 | 二次分配四槽的键不含服务代币 | ✅ | 键为 `sourceTokenAddress + sourceActionId + groupId`，同一配置被多个服务行动复用（`06:85`） |

## 4. 发现

### M-GSS-01 · 分母缓存用 `0` 兼作「未缓存」，因此无法缓存合法的零分母

| 字段 | 值 |
| --- | --- |
| 位置 | `:28-29`（注释「0 = not cached」）、`:48-54` |
| 级别 | Info |
| 证据 | E1 |

`cachedDenominator` 返回 0 有两种含义：未缓存 / 缓存值为 0。而 `_settlement` 在 `denominator == 0` 时早退（`08:501-504`），`_mintMemberReward` 随后回滚且不写缓存，所以「缓存值为 0」永远不会发生。

这个设计是自洽的，但代价是 M-GSE-03 描述的「零分母轮次每次都重算」：只要某轮的分母真为 0（该轮所有入榜行动都未完成验证或无参与），每次结算尝试都要重新枚举一次 `votedActions`，然后回滚。

修法（不改语义）：把字段改成 `mapping(address => mapping(uint256 => uint256))` + 一个独立的 `mapping(address => mapping(uint256 => bool)) cached`，或用一个哨兵值 `type(uint256).max` 表示「已缓存为 0」。前者多一个字段（Layout 变更），后者零成本但要保证 `type(uint256).max` 不可能是合法分母。

### M-GSS-02 · `cacheDenominator` 自身无幂等守卫，唯一性靠调用方的前置条件

| 字段 | 值 |
| --- | --- |
| 位置 | `:56-63` |
| 级别 | Info |
| 证据 | E1 |

helper 直接赋值，不检查 `cached == 0`。调用点（`GroupServiceExecutor:737-742`）用 `cached == 0 && isRewardPrepared(...)` 保证只写一次，因此当前安全。

但这是一个「helper 语义弱于调用点假设」的典型：任何人新增一个 `cacheDenominator` 调用，只要忘了前置判断，就会把已冻结的分母覆盖成实时值——而那正是规格 `06:38` 用一整段论证过的「冻结分母 + 活权重 = 超额支付」的错误。规格把这条约束写在 Executor 的注释里（`GroupServiceStorage:65-68` 的 `Load-bearing` 讲的是键的选择，不是幂等性）。

建议：把幂等判断下沉到 helper（`if (self.totalGroupActionRewardByRound[t][r] != 0) return;`），或把 helper 改名为 `cacheDenominatorOnce`。

### M-GSS-03 · 同一个 Layout 里两种第一维（服务代币 / 行动代币），且同一概念有三个名字

| 字段 | 值 |
| --- | --- |
| 位置 | `:21-27`（服务代币）vs `:29`、`:39-45`（行动代币）；命名 `actionTokenAddress` / `sourceTokenAddress` / `joinTokenAddress` |
| 级别 | Info |
| 证据 | E1 |

| 名字 | 出现位置 | 实际含义 |
| --- | --- | --- |
| `actionTokenAddress` | Storage 字段名、`cachedDenominator` 形参、`GroupServiceExecutor.actionTokenAddress()` getter | 源行动代币 |
| `sourceTokenAddress` | `GroupServiceExecutor.totalGroupActionReward` 形参、`setRecipients` 形参 | 同一个东西（改名原因：与同名 getter 冲突，见 `06:56`） |
| `joinTokenAddress` | `GroupServiceExecutor.joinTokenAddress()` getter | **还是同一个东西** |

`joinTokenAddress(serviceToken, serviceActionId)` 返回的是源行动代币，而 `GroupActionExecutor.joinTokenAddress(token, action)` 返回的是「参与代币」——两个合约的同名 getter 回答两个不同的问题。规格 `06:56` 已解释第三个名字的由来（命名标准 §3.4 的参数改名），但没有指出「`joinTokenAddress` 这个 getter 名在服务侧是误导性的」：服务行动并不「加入」源代币，它只是绑定它。

链下按 getter 名做统一适配（例如「joinToken 就是我要 approve 的代币」）会在服务侧 approve 错代币——不过服务侧本来就没有 `join` 金额（`GroupServiceExecutor.join` 只调 `registerJoinState`），所以无资金后果，只是接口语义误导。

### M-GSS-04 · 五个结算槽没有 struct 打包，一次结算要写 6 个独立 mapping 槽

| 字段 | 值 |
| --- | --- |
| 位置 | `:32-36` |
| 级别 | Info |
| 证据 | E1 |

`memberMinted` / `verifierReward` / `ownerBurned` / `ownerDistributed` / `ownerRemaining` 是五个独立 mapping，键完全相同。一次结算要写 5 个冷槽（`memberMinted` + 4 个金额），每次都是一次 `keccak` + 一次 20k gas 的冷写。

若打包成一个 `struct Settlement { bool minted; uint96 ...; }` 的 mapping，一次结算只需 1-2 个冷槽（`bool` 与几个 `uint256` 无法全部塞进 32 字节，但 `minted` + 两个 `uint128` 可以）。这是纯 gas 取舍，不是正确性问题：当前设计的好处是「读单个字段不必解码整条记录」，而 `serviceRewardByMemberId` 一次要读全部 5 个。

规格没有对这条做规定。记录的原因：`GroupActionStorage` 的同位置字段（`memberMinted` / `memberMintedReward`）也是两个独立 mapping（原第三个 `memberBurnedReward` 已在 A-12 中删除），两个 Layout 采用了同一种（未打包的）写法，改动需要同时动两处。

## 5. 已核对为正确的点

- 分母缓存的键与值的轮次口径一致：唯一写点用 `settlement.actionTokenAddress`（行动代币），唯一读点（`totalGroupActionReward` / `_denominator`）也用行动代币（U3）。
- 二次分配四槽的键**不含服务代币**，因此「所有对同一源行动提供激励的服务 Proposal 复用该配置」（规格 `06:85`）在布局层面成立（U6）。
- `createdRoundByActionId` 与 `actionTokenAddressByActionId` 同笔写，且 `createdRound` 在最后（`GroupServiceExecutor:428`），因此「已创建」哨兵成立时配置必然齐全。
- `groupReward` 是唯一的库内外部调用，且只读（`generatedActionRewardByGroupId` 是 `view`），不会引入重入面。
- 三个常量全部是编译期常量，`PRECISION` 与 `DEFAULT_MAX_RECIPIENTS` 被 `GroupServiceExecutor` 以 `public constant` 暴露，`MAX_REMARK_BYTES` 不暴露——与规格 `06:89`「`DEFAULT_MAX_RECIPIENTS` 是协议级编译期常量」一致。
- 14 个字段全部是 mapping，因此「末尾追加」是唯一安全的布局变更方式（与 `GroupActionStorage` 同）。

## 6. 覆盖缺口

- 未做 `forge inspect storage-layout` 实测 14 个字段的槽位序号。
- 未审 `totalGroupActionRewardByRound` 在「同一行动代币被多个服务代币引用」时的共享正确性；按定义 `D` 只依赖 `(actionToken, round)`，共享是必要的，但未构造多服务用例。
- 未审 `MAX_REMARK_BYTES = 256` 与 `GroupActionStorage.MAX_DESCRIPTION_BYTES = 1024` 的取值是否与规格一致（按源码认定）。
- 未审 `GroupServiceExecutor` 暴露 `PRECISION` / `DEFAULT_MAX_RECIPIENTS` 而 `GroupActionExecutor` 不暴露其常量的口径差异（`GSE-01` 已登记）。

## 处置（2026-11）

| 编号 | 处置 | 落点 |
| --- | --- | --- |
| `M-GSS-01` | 规格补写 | [`06-service-executor.md`](../../docs/specs/action/06-service-executor.md) 的「状态口径」：零分母不写缓存，每次重算；与 `M-GSE-03` 同源 |
| `M-GSS-02` | 规格补写 | 同上：`cacheDenominator` 无幂等守卫，唯一性由唯一调用方保证 |
| `M-GSS-03` | 规格补写 | 同上：`joinTokenAddress` / `actionTokenAddress` / `sourceTokenByServiceActionId` 三名同概念，链下不得按 getter 名做统一适配 |
| `M-GSS-04` | 口径登记 | 五个结算槽不打包是 gas 取舍，06 写明；不改源码 |
