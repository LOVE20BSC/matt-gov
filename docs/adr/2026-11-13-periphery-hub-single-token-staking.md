# ADR: 单币流动性质押的仓库归属与 Stake / Hub 职责重划

## 状态

已接受 (2026-11-13)

## 背景

### 触发问题

`tools/src/UniswapV2Zap.sol` 是一个可独立部署的合约：接收单币或原生币，内部 swap 出另一半，经 Router 加池并把 LP 交给 `to`。它不依赖任何 LOVE20 协议合约，只依赖外部 Uniswap V2 兼容 DEX 的 Router / Factory / Pair / WETH 地址。

BSC 版需要一个「单笔完成流动性质押」的便捷入口：用户只给一种币，链上自动换出另一半并完成 [Stake.stakeLiquidity](../specs/core/04-stake.md) 的记账。这段编排逻辑与 Zap 的 swap/折算数学高度重合。问题因此变成：Zap 应该放哪个仓库，以及与之配套的单币质押入口放在哪里。

### 既有事实

- [repositories.md](../repositories.md) 已规划 `periphery` 仓库：依赖协议已部署合约、可随时替换的聚合查看与便捷交互，例子一栏即为 `viewer`、`hub`；旧仓 `LOVE20TKM/periphery/src/LOVE20Hub.sol` 正是这一角色，其 `stakeLiquidity(..., address to)` 承担入池最优量折算与滑点校验。
- [CHANGES-core.md](../specs/CHANGES-core.md) 记录 BSC 改造时把旧 Hub 的折算与滑点校验并进 `stakeLiquidity`，新增 `slippage` 参数。当时的背景是旧 periphery 不迁移、Hub 不再存在。
- `Stake.stakeLiquidity` 当前带 `onlyMemberOwner(memberId)` 修饰符（[Stake.sol](../../../core/src/Stake.sol)），校验 `ownerOf(memberId) == msg.sender`；`_pull` 直接从 `msg.sender` 拉双币。因此在 EVM 的 `msg.sender` 语义下，**任何中间合约编排的单笔质押都会撞 `NotMemberOwner`**——Hub 调 Stake 时 Stake 看到的调用者是 Hub。
- [01-common-rules.md](../specs/core/01-common-rules.md) 把「处分成员资产须校验 ownerOf」定为通用规则，但同时已留例外：`mergeStake` 只校验源 memberId，目标侧仅 `ownerOf(targetMemberId)` 验存在，不比较 `msg.sender`（[04-stake.md](../specs/core/04-stake.md) §融合）。**「向他人 memberId 单向增加质押」这一能力在当前协议里已经开放**。
- `Stake._optimalAmounts` 折算后 `_pull` **只拉折算后的量**，剩余从未进入 Stake；折算保留一侧全额、削减另一侧，因此只可能一侧有剩余，或比例一致时两侧都无剩余。

### 关键论证：放宽鉴权不引入新的攻击面

若放开 `stakeLiquidity` 的 owner 校验，最直接的担忧是第三方用 dust 抢先给某个 `memberId` 开仓、把 `promisedWaitingPhases` 钉成 MAX（`stakeLiquidity` 有单调不减约束，owner 之后无法下调）。

但这一攻击**今天就能经 `mergeStake` 完成**：任何人用自己的 MAX 等待期仓位融合到任意 memberId，空目标继承源等待期，且目标侧不要求持有 NFT。该仓位同样可通过 `mergeStake` 移走、`withdraw` 清理，`firstGovVoteRound` 随之归零（社区级标记除外，它不参与任何资格判定）。

因此放开 `stakeLiquidity` 只是把一条**已经开放的能力**从「融合」推广到「直接质押」，没有引入新的 griefing 类别。剩余可观测性缺口由事件字段补齐（见下）。

## 决策

### 一、仓库定位

1. **取消独立 `UniswapV2Zap` 合约**：其逻辑并入 `periphery` 仓库的 `LOVE20Hub`，不再作为单独部署的合约存在。`tools` 收缩为「不依赖任何其他已部署合约、功能单一」的纯工具集合，只剩 `BatchTransfer`。
2. **`LOVE20Hub` 覆盖 `UniswapV2Zap` 现有的全部能力**，由单币质押、单币组 LP、配对报价三类入口承接，不因 Zap 取消而丢失任何功能：
   - `zapToken` / `zapNativeToken` 的「单币 → 经 Router 加池 → LP 交给 `to`」→ Hub 的组 LP 入口（ERC20 与原生币两分支，LP 发给调用者或指定接收方）；
   - `quoteZapToken` / `quoteZapNativeToken` 的 view 报价 → Hub 的报价入口；
   - `TokenZapped` / `NativeTokenZapped` 事件 → Hub 自有事件（按 [event-standards.md](../event-standards.md) 改名与拆族）。
   质押类入口在组 LP 之上再追加一笔 `stakeLiquidity` 记账，因此「组 LP」是「单币质押」的子步骤，两者共用同一套 swap / 折算 / 退款实现，数学只存在一份。
3. **`periphery` 承载所有依赖协议已部署合约的外围合约**（`LOVE20Hub`、未来 viewer 等），含「单币做流动性质押」「单币组 LP」等综合快捷操作。理由：这类便捷入口会持续演进（池内单币 → 任意币 + 自动寻路），放 `core` 会把演进绑进底座；放 periphery 才能按 [repositories.md](../repositories.md) 的「可随时替换」定位迭代，且 swap 数学只存在一份。
4. [repositories.md](../repositories.md) 的划分规则**不改判据**（仍是「是否依赖协议已部署合约」），只更新状态与例子：去掉 `tools` 条目里的 `UniswapV2Zap`，`periphery` 由「规划中」推进。清单里的 `love20-anvil` 是旧名、当前工作区并无此目录；本地链编排实际在 `anvil/` 仓库（其 README 说明它编译 `core`/`action`/`group-chat`/`libs`/`dex` 为只读输入）。`anvil/` 目前不引用 Zap 或 tools，本次改动不要求它改代码；若将来接入 Hub，按 Hub 地址接即可。

### 二、core 侧改动

1. **`stakeLiquidity` / `stakeBoost` 放宽鉴权**：只调用 `ownerOf(memberId)` 校验存在（沿用 `mergeStake` 的写法），**不比较 `msg.sender`**。判据是「单向增加不损害目标资产」；`unstake` / `withdraw` / `mergeStake` 源侧仍收紧。
2. **等待期约束**：当该 memberId 已有质押（`liquidityShares != 0 || boostShares != 0`，与 `_mergeIntoTarget` 的 `targetHadPosition` 同判据）时，非 owner 调用必须沿用现有 `promisedWaitingPhases`，不得改写；空仓位允许自由指定（含 MAX）。下调回滚 `PromisedWaitingPhasesDecreased`，非持有人改写回滚独立的 `PromisedWaitingPhasesRewritten(tokenAddress, memberId, requested, current)`——两条判据不同，按错误标准「一条件一错误」不共用 selector。**该约束对中间合约同样成立**：Hub 代用户调用时 `msg.sender` 是 Hub，永不等于 NFT 持有人，因此经 Hub 无法为已有仓位提升等待期；要提升须由持有人直接调 `Stake.stakeLiquidity`，Hub 不提供这条路径。理由：实际交互中首次质押仍由 owner 经 Hub 完成，强制降为 MIN 会逼出「质押 + 调整等待期」两步，拿真实用户成本去防一个已有补救的骚扰。
3. **删除 `slippage`**：`stakeLiquidity` 不再承担滑点职责，只按 Pair 储备把收到的两种币尽可能放进流动性质押，放不下的留在调用者手里。价格保护完全交给 Hub 的 `tokenAmountMin` / `parentTokenAmountMin`（全链路终点口径）。
   - Hub 以**调用前后自身余额差**取 Stake 实际拉走的量，做 `prepared − remaining >= Min` 的事后校验，不在 Hub 里复刻折算公式。
   - 这是 [CHANGES-core.md](../specs/CHANGES-core.md) 所记「旧 Hub 折算与滑点并入 core」的一次反转：periphery 回归后职责还回去，但边界更清楚（core 只折算 + 记账，Hub 管价格与路由）。**该反转只写本 ADR，不写进 `CHANGES-core.md`**——后者只记录与 `LOVE20TKM/core` 的最终差异。
4. **事件字段变更**（`LiquidityStaked` / `BoostStaked`）：
   - 加 `caller`（直接调用者 `msg.sender`）。理由：单笔交易涉及多层合约调用时，日志收据只带发日志的合约地址、`tx.from` 只有顶层 EOA，中间调用者需 `debug_traceTransaction` 才能还原；显式写出使事件流自包含。依据 [event-standards.md](../event-standards.md) §4.3「直接调用者仅在确有必要时另设 `caller`」。
   - 加 `memberOwner`（`ownerOf(memberId)` 在本次写入时点的快照）。与 `caller` / `tx.from` 比对即可判「本人直接质押 / 本人经 Hub / 第三方代付」。
   - 加 `prevPromisedWaitingPhases`（[event-standards.md](../event-standards.md) §6.4 旧值 `prev` 前缀）。**只加这两个事件**：只有 `stakeLiquidity`、`stakeBoost` 会改变等待期；`unstake` / `withdraw` 只读或随记录删除，`StakesMerged` 的目标前置值在空仓时恒为 0、非空仓时恒等于 `targetPromisedWaitingPhases`，可由恒等推导，不补字段。
   - `Unstaked` / `StakeWithdrawn` / `StakesMerged` 不变。
   - **删 `govVotes`（`LiquidityStaked` 独有，`BoostStaked` 保留）**：加完上面三个字段后事件达到 16 个参数，在非 `via_ir` 的标准编译模式（solc 0.8.37 + `optimizer_runs = 200`，见 [dev-standards.md](../dev-standards.md) §3.1）下必定 `Stack too deep`，实测用 memory struct 作唯一载荷再经私有 `_emit` 分离**同样绕不过**，15 个参数才是可 emit 的上限。而 `govVotes` 恒等于同一 payload 内的 `liquidityShares × promisedWaitingPhases`（`Stake._govVotesOf` 的实现），属 [event-standards.md](../event-standards.md) §6.9 的派生缓存，删除不动折叠能力。`BoostStaked` 的 `govVotes` 必须保留：该 payload 里没有 `liquidityShares`（只有 `boostShares`，不产生票权），不可由本事件推导。判定标准是**「能不能从本事件的 payload 推导」**，不是「该字段重要不重要」。
   - 注：`govVotes` 不是本次新增的字段。旧 `LOVE20TKM/core` 首版的 `StakeLiquidity` 即同时携带 `govVotesAdded` 与 `govVotes`，本条的「删」是相对旧接口的真实差异，已登记在 [CHANGES-core.md](../specs/CHANGES-core.md)。
   - 注：`Unstaked` 的 `govVotes` 按同一判据**也是可推导的**（`unstake` 只写 `unlockRequestPhase`，`liquidityShares` 与 `promisedWaitingPhases` 都不变，发射值正是二者的乘积），即它同样是历史冗余。但本条不改 `Unstaked`：本次 ABI 变更的触发点是 `stakeLiquidity` 的鉴权与参数，`Unstaked` 不受影响，顺手改它只会扩大破坏面。该冗余作为已知项记录在此，留给需要动 `Unstaked` 的下一张票处理。
5. **一次性 ABI 变更**：鉴权放宽、删 `slippage`、事件字段三者都动 `stakeLiquidity`，合并为一次提交，避免 selector 变两次。

### 三、periphery / `LOVE20Hub`

1. **依赖注入**：构造函数只接收 `stakeAddress`，从 `IStake` 派生 `ROUTER_ADDRESS` / `PAIR_FACTORY_ADDRESS` / `LAUNCH_ADDRESS` / `MEMBER_NFT_ADDRESS`，再从 Router 派生 WETH；全部 `immutable` + 全大写。不用 `init`、不设 `initialized`。跨仓且部署时已落地的依赖允许构造期读 getter（[dev-standards.md](../dev-standards.md) §5.4 例外），派生结果由部署脚本广播前复核。
2. **两个流动性质押入口，按输入形态拆函数**（不做 boost）：
   - `stakeLiquidityWithToken(SingleTokenStakeParams)`，非 `payable`；
   - `stakeLiquidityWithNative(NativeTokenStakeParams)`，`payable`，金额走 `msg.value`。
   - 拆分理由：`payable` / `transferFrom` 是两条资金入口，避免用零地址哨兵；两个函数各自更瘦（不经 `via_ir`）；退款形态由函数唯一决定，故 **`refundAsNative` 入参删除**（ERC20 分支原样退 ERC20，原生币分支退原生币）。
   - 两个函数**都传 `tokenAddress`**（社区代币）。原生币是**根父币 WETH / WBNB**，不是任何 LOVE20 代币；首币是 `FIRST_TOKEN_ADDRESS`、其父币才是 WETH（[00-protocol-model.md](../specs/core/00-protocol-model.md)）。所以「原生币 → 必然是首币 → 不用传 `tokenAddress`」不成立；只有 `inputTokenAddress` 在原生币分支不需要。
3. **参数**：只留 `tokenAmountMin`、`parentTokenAmountMin`、`deadline`（外加 `tokenAddress`、`inputTokenAddress`、`inputTokenAmount`、`promisedWaitingPhases`、`memberId` 等业务参数）。**Hub 入参无 `slippage`**：core 已删。Min 语义是「最终至少有多少社区币 / 父币进入流动性质押」，不是 swap 段的 `amountOutMin`；校验点前移到 Hub 调 core 之前。
4. **事件**：自建 `periphery.hub` 族并登记（[event-standards.md](../event-standards.md) §6.1），事件名按 `<Object><PastParticiple>` 完成时态 + 域前缀，质押与组 LP 各按事实拆名。三个 indexed 槽：`tokenAddress`（根键）/ `memberId`（主对象 id）/ `caller`（actor）。
   - 只记 Hub 这一层的编排事实，**不复制 core 的份额 / 票权 / 等待期 / 各种 `total*`**——那些由 `LiquidityStaked` 提供，同一 tx hash 串起两层日志。
   - 字段用前缀写法统一：`preparedTokenAmount` / `preparedParentTokenAmount` / `remainingTokenAmount` / `remainingParentTokenAmount`。
   - WETH 退款统一按 WBNB 量纲记 `remainingParentTokenAmount`，形态不进事件（事件区分不出、也不该区分，只是用户感受）。`prepared − remaining` 恒等于 core 的实际入池量，写成验收断言而非加派生字段。
   - 不加 `inputTokenSymbol`（[event-standards.md](../event-standards.md) §6.4：机器可读的值不得用 `string`，资产标识一律用 address）；不加路由 / Router 地址（不可变部署参数不进事件；单币场景 path 可推导；多跳路由单发子事件，不预留空字段）。
5. **组 LP 与报价（承接 Zap 的其余能力）**：
   - 组 LP 入口按输入形态同样拆 ERC20 / 原生币两支，LP 交给 `to`（不经 `stakeLiquidity`，不产生质押记账）。它与质押入口共用 swap / 折算 / 退款实现。
   - 报价入口覆盖 `quoteZapToken` / `quoteZapNativeToken` 的能力：给定输入币与数量，返回备齐的双币量、是否将 swap、swap 方向与数量、预期 LP；`quoteSingleTokenStake` 在此之上额外给出四个 prepared/remaining 量供质押场景使用。报价均为纯 view，不带 `memberId` / `promisedWaitingPhases`。
   - 组 LP 的事件同样归 `periphery.hub` 族，与质押事件按事实拆名；Zap 的 `TokenZapped` / `NativeTokenZapped` 不保留原名。
6. **最小外部接口**：Zap 取消后，`tools/src/interfaces/` 里的 `IUniswapV2Factory` / `IUniswapV2Pair` / `IUniswapV2Router02` / `IWrappedNative` 迁入 periphery（按 [dev-standards.md](../dev-standards.md) §4.1 不在两仓维护副本），tools 只留 `IBatchTransfer.sol` 与 `IERC20Minimal.sol`。

### 四、`one_click_deploy` 的组织级规则（独立一节）

**判据改为「该仓库的已部署合约集合是否冻结」**，不再无条件要求 `one_click_deploy.sh`：

- 集合冻结（迁移验收完成、后续只修 bug 不新增合约）→ 允许全仓统一 `one_click_deploy.sh`；即便允许，后续真的新增合约时仍按 [dev-standards.md](../dev-standards.md) §6.1 另加 `one_click_deploy_<x>.sh` 作为逃生口。
- 集合未冻结 / 按设计会持续新增独立合约 → 只按模块给 `one_click_deploy_<x>.sh`，**不设全仓入口**。理由：统一入口要么重复部署先前已部署的合约，要么无法覆盖后来新增的合约。
- 据此 `periphery`、`tools` 不设统一入口；`core`、`action`、`group-chat`、`dex` 是否允许由各自「合约集合是否冻结」的验收结论判定，**不在本 ADR 里按仓库名单钉死**（`dex` 的 README 已预留新增路径，`core` 的 `launch` 是另建仓库而非 core 内新增）。
- 同步修订 [dev-standards.md](../dev-standards.md) §6.1 的「`one_click_deploy.sh` 必需」与 [repositories.md](../repositories.md) 只给 `tools` 开特例的写法。

## 被否决的方案

| 方案 | 否决理由 |
| --- | --- |
| Zap 留在 `tools`，Hub 按已部署地址调它 | 要部署两个合约、要地址文件与跨合约 approve/退款，`to = address(this)` 再转交 LP；一条只有单个 adapter 的 seam 不值得存在 |
| Zap 搬进 `core` / `libs` / 新建仓库 / `dex` | 见背景与 [repositories.md](../repositories.md)：Zap 不依赖协议合约；`libs` 是无业务语义的 internal 原语库；新建仓库成本无收益；`dex` 钉死上游 solc 0.5/0.6 与逐字节一致的字节码 |
| 单币质押逻辑直接进 `Stake`（方案 D） | 不动鉴权、零安全面，但把会持续演进的便捷/路由逻辑绑进底座，且固定死「池内单币」这一形态，违背 periphery 可替换的定位 |
| NFT 托管 / 改 core 加 Hub 白名单 | 前者把整个身份交出去换一次质押（[ADR-005](005-remove-group-chat-delegation.md) 明确为独立产品取舍）；后者推翻「单一鉴权不变式」 |
| 保留 `refundAsNative` 入参 | 函数按输入形态拆分后退款形态唯一确定，该入参的运行时歧义从根上消失 |
| 事件用 `inputTokenSymbol` 做标识 | 外部已知代币可撞名、任意 ERC20 可伪造 `symbol()`；机器可读值不得用 `string` |
| Hub 事件复制份额/票权/等待期变化 | 造成同一聚合量两处对账源（[event-standards.md](../event-standards.md) §3.1 族内漂移）；core 事件已有，链下按 tx hash 串联 |

## 按仓库拆分的工作项（供并行子 Agent 认领）

各工作项写范围互不重叠；`matt-gov` 文档项与 `core` 代码项存在事实依赖（文档须反映最终 ABI），建议先定稿本文档再分发。

| # | 仓库 | 写范围 | 内容 | 依赖 |
| --- | --- | --- | --- | --- |
| A | `matt-gov` | `docs/adr/`、`docs/repositories.md`、`docs/dev-standards.md`、`docs/event-standards.md`、`docs/specs/core/01-common-rules.md`、`docs/specs/core/04-stake.md`、`docs/specs/core/09-testing.md`、`docs/acceptance.md`、`docs/specs/CHANGES-core.md`、`registry/errors.*` | 本 ADR；仓库清单状态与例子；§6.1 部署规则；新增 `periphery.hub` 族与 `core.stake` 族字段变更；通用鉴权规则（处分收紧 / 单向增加放开，含「新增无许可写入口须说明谁都能调、为什么无害」的新类别）；04-stake 鉴权表删 `NotMemberOwner` 行、删滑点段与拒绝条件第 10 行、事件表补字段；覆盖矩阵与验收；`CHANGES-core.md` **只更新与旧仓的最终差异**（`stakeLiquidity` 不再有 `slippage`、错误集合去掉 `SlippageExceeded`），不记中间迭代；错误登记刷新 | 无（先做） |
| B | `core` | `src/Stake.sol`、`src/interfaces/IStake.sol`、`test/**`、`script/**` | 删 `slippage` 参数 / `SLIPPAGE_PRECISION` / `_checkSlippage` / `SlippageExceeded`；`_optimalAmounts` 变纯折算；`stakeLiquidity`/`stakeBoost` 只验 `ownerOf` 存在、已有仓位沿用等待期；两事件加 `caller`/`memberOwner`/`prevPromisedWaitingPhases`；全部调用点、mock、约 25 处测试常量与 Slippage Tests 段重写、部署脚本参数校验 | A（ABI 定稿） |
| C | `compatibility` | `test/CompatibilityProbe.t.sol`、`test/CoreAuditFindings.t.sol` 等 7 处 | `stakeLiquidity` 调用去掉 `slippage` 实参，`SLIPPAGE` 常量删除；重跑 fork 探针 | B（selector 变更） |
| D | `tools` | `src/UniswapV2Zap.sol`、`src/interfaces/IUniswapV2Zap.sol` 等 5 个最小外部接口、`test/UniswapV2Zap.t.sol`、`test/mocks/ZapMocks.sol`、`test/DeployUniswapV2Zap.t.sol`、`script/deploy/*uniswap_v2_zap*`、`script/network/**/*uniswap-v2-zap*`、`broadcast/DeployUniswapV2Zap.s.sol/`、`foundry.toml`、`README.md` | 删除 Zap 全部实现、接口、测试、部署脚本、广播记录、参数文件、lint 理由段；最小外部接口移交 periphery；README 改为「只放零依赖纯工具」 | 无（可与 A 并行） |
| E | `periphery`（新建） | 整仓 | 仓库骨架（`foundry.toml` / `remappings.txt` / `.gitmodules`：`lib/core` + `lib/forge-std`，参照 `action`）；`src/interfaces/ILOVE20Hub.sol`（Events / Errors / 主接口 / 入参结构体）；`src/LOVE20Hub.sol` 实现，覆盖 Zap 全部能力（组 LP、单币质押、报价，各按 ERC20 / 原生币拆分支）；`script/events/events-baseline.txt` + `event-families.txt` + `check-events.py`；按模块拆分的部署脚本（不设全仓统一入口）；测试（含 mock 真实 V2 数学、退款、Min 事后校验、原生币分支、组 LP 与报价） | A（接口定稿）+ B（core 新 ABI） |

**本地链编排**：工作区里的 `anvil/` 仓库是实际的本地区块链编排（把 `core`/`action`/`group-chat`/`libs`/`dex` 作只读输入编译部署），当前不引用 Zap 或 `tools`，本次改动**不要求它改代码**；若将来接入 Hub，按 Hub 地址接即可。组织清单里的 `love20-anvil` 是旧名、工作区并无此目录，不单列工作项。

**跨仓顺序**：A → B → C / E；D 可与 A 并行；E 必须在 B 之后（Hub 调新 ABI）。所有改动完成后统一跑各仓 `forge build --deny warnings`、`forge test`、`forge lint` 与 `check-events.py`。

## 后果

### 正面

1. 单币质押一笔交易完成，无中间合约地址耦合、无 LP 转交、无二次退款；演进面收敛在 periphery，core 保持稳定的记账底座。
2. `tools` 与 `periphery` 的边界变成一条编译期事实（是否 `import @core/`），不再靠人判断「算不算外围」。
3. swap / 折算数学只存在 Hub 一份；core 不再承担价格保护，接口更宽容、更适合被合约调用。
4. 事件流自包含（两层 `caller` + `memberOwner`），链下无需 `debug_traceTransaction` 即可还原调用链与判断代付。

### 负面 / 成本

1. **破坏性 ABI 变更**：`stakeLiquidity` selector 变、`SlippageExceeded` 删除、两个事件 topic0 变；`core` / `compatibility` / `periphery` / 前端 / 索引方需同步。
2. 「`actor ↔ memberId` 只有一条路径」的收敛结论（[ADR-005](005-remove-group-chat-delegation.md)）需加例外注记：群聊授权仍单一，质押增项开放。
3. 绕过 Hub 直接调 `stakeLiquidity` 且双币比例失衡时不再 revert，只是静默少押、剩余留在自己钱包——资产无损，但少了偏离提醒。现有集成测试几乎全用 100% 容差，此变化影响面小。
4. 独立 Zap 合约不再部署：组 LP 与报价能力迁入 Hub，调用方改为与 Hub 交互（Hub 依赖 core 的已部署地址，不再是零依赖的通用工具）。这是「外围可替换」定位的代价，但能力面不缩减。
5. `core.stake` 族表、两份事件表、错误登记、兼容性探针约 7 处、tools 整套部署资产与 79 条错误登记需逐一清理。

## 待建仓时定（不在本 ADR 钉死）

- `periphery.hub` 事件的确切命名与 `caller` / `memberOwner` 是否 indexed（三槽已被根键 / 主对象 id / actor 占满，倾向 payload）。
- `quoteSingleTokenStake` 是否附带建议 Min 值供前端填写。
- `core`、`action`、`group-chat`、`dex` 各自的「合约集合是否冻结」验收结论。

## 相关文档

- [repositories.md](../repositories.md) · [dev-standards.md](../dev-standards.md) · [event-standards.md](../event-standards.md) · [naming-standards.md](../naming-standards.md)
- [01-common-rules.md](../specs/core/01-common-rules.md) · [04-stake.md](../specs/core/04-stake.md) · [CHANGES-core.md](../specs/CHANGES-core.md) · [00-protocol-model.md](../specs/core/00-protocol-model.md)
- [ADR-005 移除群聊内 NFT 委托](005-remove-group-chat-delegation.md)
- 旧仓只读参考：`LOVE20TKM/periphery/src/LOVE20Hub.sol`、`LOVE20TKM/periphery/src/interfaces/ILOVE20Hub.sol`
