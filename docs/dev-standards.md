# LOVE20BSC 合约开发规范

适用于 LOVE20BSC 的全部合约开发工作——**新合约开发与既有代码迁移都遵循本文件**。迁移专属的流程与约束见 [代码迁移规范](migration-standards.md)。

## 一、提交与推送

- 消息一律英文，遵循 [Conventional Commits](https://www.conventionalcommits.org/)：`type(scope): description`。
  - `type`：`feat` / `fix` / `refactor` / `test` / `docs` / `chore`。
  - `scope`：模块小写名（`mint`、`vote`、`phase`）。
  - `description`：祈使句、首字母小写、不加句号。
  - 自生效后新提交适用；历史提交不改写。
- 不用额外的样式提交、临时修复提交或 revert 提交污染历史；发现问题在对应提交完成前 amend。
- 已纳入 Git 的文件保留路径连续性；路径变化用 `git mv`，不要删除后重建。
- 文件同时有较大内容改动、导致 Git 无法按默认相似度识别重命名时：先单独提交只含 `git mv` 的重命名，再在下一提交改内容。该拆分只用于确有重命名识别需要的文件，不用于制造样式提交。
- 推送前先 `git log origin/main..main` 确认将发布的提交范围——快进推送会把本地积压的提交一并发布。历史被重写过的分支用 `git push --force-with-lease=<ref>:<重新 fetch 得到的完整 SHA>`，不用裸 `--force`。

## 二、审查证据

开始修改前说明：本步目标、涉及接口、明确不改的内容、验证方式。

提交前至少检查：

- 编译与已有测试通过；
- 成功、边界、失败回滚路径有测试或明确的最小验证；
- 接口变更已落到本代码库的 `src/interfaces/`，ABI 与声明一致；
- 工作树干净，提交只含本步内容。

不得把"能编译"当作完成。

## 三、技术基线

### 3.1 工具链

- **Solidity `0.8.37`**；自有合约、接口、测试用精确 pragma `=0.8.37`。
- **Foundry `1.8.1`+**，`foundry.toml` 显式 `evm_version = "osaka"`。显式锁定 EVM 目标以防未来默认变化；部署前仍需在目标 BSC 网络与测试环境验证。
- **不使用 `via_ir`**：显著增加编译时间、影响调试、与覆盖率工具不兼容；标准优化器（`optimizer = true` + `optimizer_runs = 200`）已足够。合约与测试必须在标准编译模式下通过；遇"Stack too deep"优先重构（拆函数、减局部变量、用 struct），不得靠 IR 绕过。

### 3.2 依赖管理

- **单链依赖**：每仓只声明直接上游的生产子模块（如 `core` 依赖 `libs`/OpenZeppelin，`action` 依赖 `core`，`group-chat` 依赖 `action`）；`forge-std` 作为测试与脚本工具链各仓直接声明。不得重复引入传递依赖；`remappings.txt` 仍列出实际 import 所需的传递别名。
- **导入约定**：跨仓 import 统一 `@` 前缀（如 `@core/interfaces/...`、`@libs/...`、`@openzeppelin/contracts/...`、`@forge-std/...`），本地相对导入不加；别名指向包的源码入口。`@forge-std/` 是本地约定，与 Foundry 示例写法不同。
- **显式 remappings**：各仓提交 `remappings.txt`，`foundry.toml` 设 `auto_detect_remappings = false`；别名只追加不重指，每条必须有实际 import 命中。不得与同路径 vendored OZ 源码并存。
- **版本凭证**：子模块 gitlink 与 `foundry.lock` 是唯一版本凭证且必须一致；lock 只记录直接子模块，传递版本由上游 commit 固定。具体版本不在文档登记；部署记录保存实际 commit 与字节码 hash。
- **升级**：被依赖方先推送；消费方 fetch/checkout 后同步 gitlink 与 lock，并跑完整 `forge build` 与测试，不得只用“编译通过”当兼容性证明。升级单独提交，不用 `forge update <path>`；外部库主版本变化还须记录行为差异，上游 `lib/` 布局变化必须同步下游 remappings。
- **双版本**：默认不并行保留；确需并行时用新别名（如 `@libs-v2/`）并隔离源码。

### 3.3 单合约 24KB 拆分

EIP-170 限制部署字节码 ≤ 24,576 字节。超过时：

- 按**业务模块**把实现体拆进 `public` 库（经 DELEGATECALL 执行，库自身同受上限），保留原合约的地址、ABI 与状态。
- 不得靠删减已定稿 ABI 或调整 `optimizer_runs` 绕过。
- 库函数直接接收 `storage` 指针读写调用方状态：**状态集中在一个根 Layout struct**，库函数只收该 struct 的 storage 指针 + 业务参数；状态增减不改库函数签名。
- 拆分边界：
  - 业务模块各自成库；
  - **会被其他合约链上调用的接口，实现留在主合约**（跨库固定开销会让一次读取翻倍）；
  - 只被钱包/前端读取的查询随业务库走（经 `eth_call` 不计 gas）。
- 库调用不得出现在循环体内。
- 含业务语义的库放业务仓 `src/`；无业务语义的通用库按「复用优先」放 `libs`。
- `forge build --sizes` 上限纳入实现门禁。

## 四、接口规范

适用于 core 与各扩展层接口的新增、改名成员。

### 4.1 接口文件与声明

- 自有函数、事件和错误的 ABI 唯一来源是**本代码库的 `src/interfaces/`**；不在其他仓库或文档里维护副本，避免两处漂移。
- **事件统一声明在 `I<Name>Events` 子接口**；`I<Name>Errors` 子接口按需拆分，两者相对顺序自定。
- 标准依赖接口属于独立的继承边界：标准 API 由目标依赖（如 OZ）提供，不在本代码库重复声明；接口可用 `is` 继承同一标准依赖接口补齐标准 API，该继承不视为自有声明。
- **接口文件不写 NatSpec**：`interfaces/` 只声明 ABI，语义、校验顺序、返回值约定和分页语义写在模块规格与对账文档里；接口体保持连续声明，不用 `///`、不用空行划注释块（`ILaunch`、`IMint`、`IPhase`、`IStake`、`IVote` 均无注释）。仅当信息落不进规格时才留一行 `@dev`，如 `ILOVE20Token`/`IMemberNFT` 标注"实现继承 OpenZeppelin 的 ERC20 / ERC721Enumerable"，供 ABI 对账区分自有声明与完整 ABI。空行只用于语义分组（分隔函数与内联 `error`、写操作与配置 getter）。

### 4.2 事件设计

作为接口 Review 的核对项。

- **每个外部可调用的状态变更函数都应有对应事件**：链下只能从事件流观测状态变更，写函数无事件就不可索引。只读函数不要求事件；确无观测价值的写函数（如 `init`）为例外，须在对账文档写明理由。
- **事件名用完成时态**：陈述已发生的变更，用过去式（`GroupActionJoined`、`StakeWithdrawn`、`VerifierLocked`），不用动词原形或动名词。
- **对称操作用对称事件名**：互为逆操作的写函数共用同一词干——一侧 `xxxAdded`，另一侧应为 `xxxRemoved`/`xxxDeleted`，不得一侧 `Added`、另一侧改用其他词干（如 `Revoked`）。

### 4.3 集合读取函数

**先定形态，再定名字。**

**1. 只有有界集合才提供全量读取。**

- 有界：规模由常量或固定配置决定（社区总数、管理组名单）。
- 无界：规模由外部输入决定（成员数、提案数、推举记录数、消息数）——只给分页。
- 同一集合不同时给全量与分页两版；全量那条在规模变大后会耗尽调用方 gas，进了 ABI 又删不掉。

**2. 分页只回定长数据。** 页内成员由别人决定，只有每项定长，一页体量才随 `limit` 增长。

| 页内成员                             | 分页返回                                                    |
| -------------------------------- | ------------------------------------------------------- |
| 全部定长（`uint256`/`address`/`bool`） | 直接回记录本体（`submitInfos`）                                  |
| 含变长成员（`string`、`bytes`、动态数组）     | 只回 id，本体另设按 id 批量（`proposalIds` + `proposalInfosByIds`） |

分页若回含 `string`/`bytes` 的结构体，一条大记录就能把整页顶过调用方 gas 上限，且跳不过去——只能反复调小 `limit` 试探。

**3. 分页签名固定。** `(uint256 offset, uint256 limit, bool reverse)` → `(列表, 真实总数)`；参数顺序「作用域键 → offset → limit → reverse」。语义同 `IPhase.syncObservations`：

- 越界返回空数组与真实总数、不回滚；
- `limit` 超剩余按剩余返回；
- `reverse` 从新到旧。

不另设计数入口，只取总数传 `limit = 0`。

**4. `reverse` 的语义随存储序而定。** 分页只承诺「逆序遍历当前存储顺序」，不承诺该顺序等于插入顺序。用 swap-and-pop 删除（末位搬到被删位置）的集合，同一集合、同一 `offset` 的返回内容**不保证跨调用稳定**，`reverse` 也不等于「新到旧」。这类集合必须在模块规格里明写该契约，并写明调用方不得跨调用缓存 `offset`、不得按「先拉首页再增量补页」拼接。只有追加写入、从不删除的集合才能声明「`reverse` 即插入逆序」。稳定顺序需额外索引或墓碑存储，属模块级取舍，本原则不统一规定。

**5. 命名 = 载荷 + 条件。**

| 返回值 / 条件 | 记号          | 例                                        |
| -------- | ----------- | ---------------------------------------- |
| 轻量标识数组   | `<复数>Ids`   | `proposalIds`、`votedSenderIds`           |
| 记录数组     | `<复数>Infos` | `submitInfos`、`chatInfos`                |
| 实体地址数组   | 裸集合名        | `tokens`、`childTokens`、`holders`         |
| 标量       | 不加后缀        | `isSubmitted`、`proposalIdBySubmitter`    |
| 按键筛选     | `By<key>`   | `proposalIdsByAuthor`、`messagesBySender` |
| 显式 ID 数组 | `ByIds`     | `proposalInfosByIds`                     |

- 裸集合名只用于元素本身是实体地址的数组（地址即标识，名称/符号由该地址自己的合约提供；`Ids`/`Infos` 在此不承担区分作用，加了反而混淆）。元素是整数标识或记录时必须带后缀。
- **是否分页不进名字**——由入参 `(offset, limit, reverse)` 决定，不加 `Paginated`/`Paged`/`Page`/`List`，也不为同一集合另设无窗口重载。
- 作用域键（`tokenAddress`、`groupId`）是定位不是筛选，不进名字。

**6. 集合只留一条完整读取路径**（分页或按 id 批量）。按键取单值的函数是叠加其上的，仅在以下情况才留：

| 理由                                | 例                                                   |
| --------------------------------- | --------------------------------------------------- |
| 用的是集合定位键之外的新键，否则只能扫全表             | `tokenAddressBySymbol`                              |
| 该键上还没有能取值的入口                      | `submitterIdByProposalId`                           |
| 该键已有取值入口，但取回整条记录的代价与调用方实际所需字段不成比例 | `proposalTarget`（Vote 每笔只取 `target` 与 `targetMode`） |

第三种必须**先量后加**：写进接口前用最小 mock 测出两条读法的差额，确认省下的开销与该入口自身的写入开销同量级（`Vote` 上实测每笔 3 万～9 万 gas，随 Proposal 正文大小增长），而不是拿"少读几个字段"当理由。省下若只有几十 gas 级，仍按前两种情况判定。差额与测量方式随接口变更一并入库。

存在性布尔与取值是两个不同的值，同键并存不算重复（`isNameUsed` 与 `idOf`、`isSubmitted` 与 `submitterIdByProposalId`）；真正的重复是同一把键、同一个值再暴露一次。**删除一个入口前，先确认它所依赖的另一个入口在同一批变更后仍成立。**

读一条传单元素数组，不另设单条入口——否则是集合的第二条路径，还会造出只差一个字母、返回值却是两种东西的近名对（旧 `proposal()` 与 `proposals()`）。第 6 条「先量后加」是例外：它不为同一集合开第二条读取路径，只是把高频调用方只需的字段单独取值。

**7. 按显式 ID 数组的批量入口（`ByIds`）三条要求：**

- **下标对齐**：返回数组长度等于入参长度，第 `i` 项对应第 `i` 个 id；不做「只回存在的那几条」，否则调用方无从得知缺哪个。
- **无效即整笔回滚、不补空**：任何 id 不可用就回滚（`proposalInfosByIds` 给 `ProposalNotFound`）。这条只管数组——标量没有位置语义，`proposalIdBySubmitter` 与 `submitterIdByProposalId` 回 `0` 表示「本轮未推举」是合法的。
- **只读且不写状态的不设长度上限**：上限是为防「调用方传大数组、让合约替它在本笔里干活」的 gas 转嫁；只读没有这条路径，超限只是调用方自己 out-of-gas，上限由区块 gas 自然给出。决定成本的是单条体量而非条数——`proposalInfosByIds` 回含可能较大的 `title`/`details`/`targetData`（各有上限）的记录，所以能按 id 批量读、却不能进分页。写状态或成本会落在第三方的批量不适用本豁免，必须有明确上限并写明来源。

审查时按本节核对，并在报告里写明该集合的**有界性判据**与**页内成员是否定长**。

## 五、实现规范

### 5.1 声明与格式

- 多参数声明一律每行一个参数（含 `init`、`join` 这类短签名）；
- 超长继承子句按仓库现有拆分接口的写法换行；
- 内部成员收在文件末尾；
- 新增成员就近插入语义邻居；
- 为此增加的行数可以接受；
- 事件声明与发射写法一致：`event E(` 与 `);` 各自成行，每个参数独占一行，单字段事件同样拆行（`emit` 侧见下条）；
- 事件一律以具名参数（kv）形式发射：`emit E({field: value})`，禁止位置参数（含测试与 mock）；每个参数独占一行（`emit E({` 与 `});` 各自成行）；键名与顺序规则见 [`event-standards.md`](event-standards.md) §6.1、§6.11；`dex` 上游源码除外（§9）。
- 格式不以 `forge fmt` 为基准：其默认风格（短参数表折行、`,)` 不加空格）与本规范相反，仓库无 `[fmt]` 配置，`forge fmt --check` 不作为门禁；以本规范与就近代码为准。

### 5.2 命名与状态

- 由构造函数或 `init` 固定的配置常量：状态变量本身用大写 `public` 命名、直接提供同名自动 getter；不得用小写状态变量再额外包装大写 getter。
- 账本与映射状态不写成 `public`：自动 getter 的 JSON ABI 入参没有字段名，与冻结接口声明的 `tokenAddress`/`memberId`/`symbol` 不一致。改用 `internal` 状态 + 显式 getter 函数，函数名、参数名与返回形态与冻结接口逐字段对齐，selector 不变。
- `init` 的参数名与对应 getter、参数表一致；实现侧同名会与状态变量相互遮蔽（solc 2519 警告在"警告即失败"门禁下不可忽略），允许参数名后加 `_`（同一函数内保持一致）。冻结接口、参数表与差异文档始终写无后缀名；该差异只影响实现产物 JSON 的参数名，不影响 selector、ABI 成员与文档口径。
- 错误名、参数与 selector 不轻改；只有无法表达语义、产生歧义或造成安全问题时才修改。
- Core 统一使用 `Proposal`；Action 层对已绑定 Executor 的 Proposal ID 统一以 Action ID 称呼——通用别名 `actionId`，带业务前缀时用 `<业务名>ActionId`（如服务提案的 `serviceActionId`）；未绑定场景（如 `UnboundProposal`）保留 `proposalId`。
- 按成员身份筛选的接口统一用 `ByMemberId`，不再用 `ByAccount`。
- **社区级聚合一律用 `total*`，不用 `global*`**。成对命名：`stakeData` / `totalStakeData`、`validGovVotes` / `totalValidGovVotes`、`validBoostShares` / `totalValidBoostShares`；结构体 `MemberStake` / `TotalStake`。事件与结构体里的聚合字段同样是 `total*`（`totalLiquidityShares`、`totalVotes`、`totalVoterBoost`），因此 getter 与它喂给的事件字段同名，折叠对账时可直接按名字配对（`totalValidGovVotes()` ≡ `LiquidityStaked.totalValidGovVotes`）。只在社区级存在的累计计数器同样是 `total*`（`totalBurnedToken`、`totalParentTokenBurned`、`MemberNFT.totalBurnedForMint`）。`total*` 是**时点存量**；需要按轮给出社区流量时，拆成 `total*Added` / `total*Removed` 两条**累计**账本，`total*` 恒等于二者之差——不单独维护，也不引入第三种口径。两条账本只在社区净额变化时写：成员之间的搬运净额为零，各记一笔会把差值抬成两倍。
- **比例参数统一 `1e18` 精度**：以 `1e18` 表示 100%；纯比值（如 `withdrawable : fee`）以 `1e18` 表示 1:1。命名用 `*_RATIO` / `*_THRESHOLD`；不得再用千分比、百分比、万分比等刻度。阈值比较一律交叉相乘（如 `a * 1e18 >= b * threshold`），避免先除后比引入截断；当交叉相乘可能溢出时，改用 `Math.mulDiv` 计算 `ceil` 门槛后再比较（数学等价）。历史 `*_PER_THOUSAND` 属旧命名，随该模块下一次接口变更改为 `*_RATIO` 并重定标，不为改名单开提交；新接口不得沿用。
- **除数不是比例**：手续费结算分母、身份费用除数等「分母」参数按语义命名，保持整数分母，不折算成 `1e18`。判断标准是语义（是否为比值或占比），不是它在公式里是否位于分母位置。
- **基类用 `<X>Base` 后缀**：`ExecutorBase`、`CompatBase`、`ActionTargetTestBase`、`ManagerBase`／`TokenManagerBase`／`TokenScopeManagerBase`／`TokenActionScopeManagerBase`（接口随之 `I<X>Base`，错误子面 `I<X>BaseErrors`）。读作「X 的基类」；`Base<X>` 会读成「基础的 X」，不采用。迁移模块同样按此改名：规格的「核对来源」继续写旧仓路径（前缀「旧」），不改写成旧仓里的新名。

#### 5.2.1 身份错误（groupId / memberId）

`groupId` 与 `memberId` 是同一 MemberNFT 标识的不同角色。

- **一主体一义**：同一 selector 不得表示两种主体或两种条件。
- **分层**：身份不存在、未激活、资格不满足是三种不同失败，不得互相替代；不要求身份存在的入口必须在模块规格说明其未知 ID 行为。
- **一名一义**：一种条件只保留一个名字。跨仓允许角色别名，但必须全仓统一登记，不能一个仓一个名字。错误名描述失败的客观状态，不用 `Only*` 表达访问规则，不用 `Invalid*` 笼统代替零值或不存在。
- **载荷**：要求身份存在的入口，错误带主体 ID；批量错误带失败元素 ID。零值按不存在处理，不新增按模块的零值身份错误；模块规格明确把 `0` 作为撤销/未设置哨兵的入口除外。
- **读一致**：谓词查询（`is*`、`can*`、`joinInfo`）缺失成员或 delegate 返回 false/0/空；记录/枚举查询的缺失行为按模块规格统一，同一查询族不得一半回滚一半返回空。同一条件不得因读/写入口不同而回不同错误。

具体签名、载荷模板与命名清单见 [`error-standards.md`](error-standards.md)，不在本规范展开。

#### 5.2.2 错误与回滚（通用）

错误是公开 ABI。每个合约/模块自己拥有错误；规范不维护中心错误表，也不存在“新增合约要改老文件”的扩展点。

- **本地所有权**：每个合约/模块在自己的本地接口文件中声明 `I<Name>Errors`（通常是 `src/interfaces/I<Name>Errors.sol`，也可与主接口同文件）；实现文件不声明错误；不得从其他仓导入错误定义。新增合约只新增文件，不改任何既有错误声明。
- **一条件一错误**：一个 selector 只对应一个条件、一个主体；禁止别名与重载。具体错误名优先于通用字段码，不使用中心 `Field`/错误枚举。
- **命名**：具体、可读，按 `<Subject><State>` / `Zero<Field>` / `Invalid<Field>` / `<Subject>Exceeded` / `Too<Size>` / `Insufficient*` / `Not<Role>Owner|Operator` / `Already<State>` / `*NotContract` / `*Unavailable` / `*Rejected`。数值上限统一 `*Exceeded`；禁止 `Exceeds...` 前缀、`Exceed<Verb>` 动词式名和 `*LimitReached`；尺寸类统一 `Too<Size>`。合约内必填依赖（含 `init`）只保留 `*NotContract(address)`（字段级或模块级 `DependencyNotContract`；零地址是同一条件），`Zero<Field>` 仅用于非合约参数；部署期静态校验按 §5.7 归部署脚本，不产生合约错误。新增错误禁用 `Only*`、`Must*`、`Cannot*`；`Invalid*` 只用于值本身非法。
- **载荷**：主体键在前，条件值在后；上限带 `actual/limit`，额度带 `required/available`，外部失败带 `source`；批量带失败元素键或索引；固定大小，禁止字符串与动态数组。
- **回滚**：禁止裸 `require`、`revert()`、`revert("...")`；`assert` 只用于不可达不变量（L0 Panic，不进错误目录）。
- **顺序**：鉴权 → 参数 → 存在性 → 状态/资格 → 账本/交互；先命中先回滚。身份解析属于鉴权的一部分；鉴权前不得泄露激活、配置或资格。
- **写语义**：只有 Set（幂等、校验后 no-op、无事件）与 Transition（必须变更或回 `Already*`）；批量一律原子；no-op 不得先于校验。
- **外部边界**：协议固定依赖按读一致处理预期缺失、意外失败 rethrow；用户配置/绑定依赖以“有代码”为条件，零地址不单独成错误，失败带 `source`；调用方任意输入失败归 invalid。固定依赖禁止宽泛 catch；只转译预期 selector，其余 rethrow。不可信输入（插件、外部规则源、任意加入代币）的宽泛 catch 例外与登记要求见 [`error-standards.md` §七](error-standards.md)。事件中的外部错误数据必须有界。
- **ABI**：标准错误由产生者接口/合约拥有；上层透传不重复继承，只在失败契约登记来源 ABI；白名单例外需逐项审查。错误签名是公开 API，major 内不变；不保留 deprecated、别名或死声明。错误 selector 不得作为业务返回值。
- **测试与目录**：每个可达错误有 selector + 载荷断言；每个多条件入口有优先级测试；批量有元素定位测试。错误目录由扫描 `src/interfaces` 与实现生成，不是中心源文件；新增合约自动进入目录。

新增合约流程：新增 `I<Name>Errors.sol` + 实现 + 测试 → 跑错误目录/检查器；不改任何既有错误文件。相同条件可在本地重复声明（selector 相同），目录按签名归组；不要求抽到共享文件。详细规则、载荷模板、外部边界矩阵与测试矩阵见 [`error-standards.md`](error-standards.md)。

### 5.3 注释

- **代码默认不写注释**：命名即文档，代码能表达的不写注释；语义、不变式与返回约定写在模块规格与对账文档。
- 两个例外：
  1. 映射的键含义无法由类型与命名自解释时（单层、多层皆然），用注释逐层写明；
  2. **承重不变式**——被破坏时不回滚、而是给出静默错误结果所依赖的假设（例：位置化「已验证」推导要求成员集合只在加入轮写入、验证固定跑 `phase−2`），就近写在它约束的代码处，因为改这段代码的人未必读规格。
- 设计理由、取舍与政策写规格，不属例外。`forge-lint` 抑制指令不属于注释，按需保留。

### 5.4 `init`

- 一律不设调用者限制；合约不保存部署者地址，也不授予部署者特权；合约侧只有 `init` 判断自身是否已初始化（防重复初始化）。
- 部署是否成功由发布前 check 脚本核对实际绑定结果判定，任何不一致即重新部署；不能把"部署后立即初始化"当作防抢跑保证。
- **初始化是否完成只在部署阶段校验**：check 脚本逐项核对每个合约的实际绑定与派生结果——依赖地址有代码、派生的配置非零、关键状态等于预期；不一致即重新部署。合约业务逻辑默认**部署期固定的依赖**已完成初始化，运行期不判这些依赖是否初始化、不为其零值或无代码另设分支与错误：这类防御会把部署遗漏变成静默的错误结果，而不是在部署时暴露。调用方入参、可选配置（零值表示不启用）的校验属业务校验，不在此列。
- **参数尽可能少**：能由入参地址的 getter 派生的依赖，不再作为 `init` 入参；在 `init` 内读取一次并缓存，派生值同样校验非零；被派生依赖须先完成初始化。例：`ActionTarget` 从 `Vote` 派生 `phaseAddress`，`LpExecutor` 从 `Stake` 派生 `memberNFTAddress`、`phaseAddress`、`pairFactoryAddress`。

### 5.5 调用者校验

**写函数的调用者校验一律写成 modifier，且是函数体的第一道判定。只判「谁可以调」。**

- 顺序：鉴权 → 参数 → 存在性 → 业务 → 账本。非授权方只拿到鉴权错误，不能借错误差异探测内部状态。
- modifier 定义在合约自身，或它继承的**唯一**抽象基类里：同一鉴权面被多个合约共用时只在基类写一次，不在各派生合约留副本（Solidity 不能跨文件引用 modifier）。**仅为消除 modifier 副本不新建基类** —— 基类必须同时承载该鉴权面的其余成员（入口函数、轮次 getter 等）；十来行的判定留在原处，就近可读优先。无论写在哪，都必须自己判调用者（`msg.sender` 或 `_is*` 谓词）、有 revert、以 `_;` 收尾，由 `script/check_caller_auth.sh` 校验；错误名按各合约自己的 `I<Name>Errors` 取，允许不同。
- 一个 modifier 只判一件事；revert 用 `I<Name>Errors` 已声明的自定义错误。
- 只做判定：不写状态、不发起改变状态的外部调用；鉴权所需的只读查询（`ownerOf`、`ownerOrDelegateIdOf`、`isAdminId`、`proposalTarget` 等）允许，且只能用于判定。接收方回调（`onERC721Received`）不属于调用者鉴权，脚本按名称豁免。
- modifier 形参占栈：参数多的函数若因此 stack too deep，把函数体拆进私有 `_<name>(...)`，外部函数只留 modifier + 转调（`GroupActionJoin`、`GroupRecipients` 已如此处理），不得改用 `via_ir` 或退回函数体内联判定。
- 多个 modifier 时 `nonReentrant` 必须最左（`non-reentrant-not-first` 强制），鉴权紧随其后。
- 判定值函数体还要用（owner 快照、事件）时仍写 modifier，函数体再读一次；多分支判定可委托给 `_is<X>()` 布尔谓词（`_isOperator`、`_isBoundExecutor`），错误仍在 modifier 里抛。业务状态校验（如 `activated`）不进鉴权判定，作为函数体首条紧跟其后。
- 无调用者限制的写函数在规格里写明，不靠「没挂 modifier」隐式表达。只读函数不适用；`init` 见 5.4。

### 5.6 复用

- 动手前先检查目标仓库已固定的依赖与 LOVE20BSC 共享库；已有实现满足语义时直接复用并固定版本，不得重复复制。
- **不含业务逻辑、可跨仓库复用的实现一律放入 `LOVE20BSC/libs`**；只有含业务语义、不具跨仓库复用价值的实现才留在业务仓库，并在对账中写明理由。
- 新增或修改共享库必须先在 `libs` 提交并推送，再同步各消费仓库的 gitlink 与 `foundry.lock`。

### 5.7 校验分层

按失效时机决定校验位置：部署期静态配置下沉到部署脚本，运行期业务判断留在合约，源码级约束交给测试/CI。

- **部署期静态不变量**：构造参数、部署期固定的依赖配置、不可变地址关系、依赖是否有代码、编译期常量。由部署脚本在**广播前**校验；`2x` check 只做部署后复核与绑定验证，不能替代广播前检查。静态检查集中在 Solidity 部署脚本的广播前阶段，shell 只做编排，业务合约只做运行期判定。
- **运行期业务不变量**：调用方入参、状态依赖、权限/资格/额度/内容/存在性。必须留在合约；部署脚本看不到未来调用，不能代替。
- **源码级不变量**：类型码/枚举范围、接口一致性、抽象实现非空。由测试或 CI 覆盖，不写运行时分支。

约束：

- 每项静态不变量必须在部署脚本有对应检查，并在模块规格登记该不变量与校验位置；不要形成“合约 + `1x` deploy + `2x` check”三处重复——`1x` 广播前是主校验，`2x` 是部署后复核。
- 部署脚本是静态配置校验的信任边界，仅适用于协议自控部署；手工或第三方绕过脚本的部署不受保护。若将来出现 permissionless 部署路径，静态不变量必须回到合约或工厂内。
- 目标是职责清晰，不以减码为主要理由；24KB 有余量时，运行期输入/状态检查不得因减码删除。
- 模块规格分别列出部署期、运行期、源码级不变量；部署 README 与参数文件同步。与 5.4 的“初始化只在部署阶段校验”同向；Solidity 脚本与 shell 的内部分工见 6.3。

## 六、部署脚本组织

统一结构（示例见 `action/`）：

```
script/
├── deploy/                        # 部署脚本实现
│   ├── one_click_deploy.sh        # 一键部署入口（必需，纯编排）
│   ├── one_click_deploy_<x>.sh    # 新增合约/模块的独立入口（按需）
│   ├── 11_deploy.sh               # 合约部署与初始化（自载入部署输入）
│   ├── 21_check.sh                # 部署与初始化正确性校验（自载入校验文件）
│   ├── 31_verify.sh               # 合约开源验证（自载入网络与地址文件）
│   ├── Deploy<Xxx>.s.sol          # Foundry 部署、初始化与部署期校验
│   └── Check<Xxx>.s.sol           # 可选：21_check 调用的只读绑定检查
└── network/
    ├── anvil31337_dev/            # 本地 anvil · dev
    └── <链名><链id>_<部署类型>/    # 其它网络按需新建，见 6.2
```

### 6.1 deploy 脚本

- **`one_click_deploy.sh` 必需**：一键部署本代码库的全部合约。后续新增合约/模块时额外增加 `one_click_deploy_xxx.sh`（只部署该部分）。
- **步骤脚本只做自己那一步、互不调用**（`11_deploy.sh` 不得调用 `21_check.sh`）；顺序编排与失败处理（如校验失败不得覆盖上次已保存的地址）只放在 `one_click_deploy.sh` 一类入口脚本里。
- **步骤脚本自包含**：统一 `<step>.sh <network>` 一种调用形态，网络目录校验、配置存在性检查、文件载入、链 ID 核对都在步骤内完成；不依赖调用方预载环境，也没有文件互相 source。入口脚本不 source 任何文件，只做编排。共享 `00_init.sh` 一类的环境初始化文件不再单设，其职责并入 `11_deploy.sh`。
- **步骤编号**：deploy 步骤以 `1` 开头、check 以 `2` 开头、verify 以 `3` 开头，第二位为模块序号——`1x` 部署、`2x` 校验、`3x` 验证同属模块 `x`（如 `dex`：WETH 模块 `11_deploy_weth`/`21_check_weth`/`31_verify_weth`，UniswapV2 模块 `12_deploy_uniswapv2`/`22_check_uniswapv2`/`32_verify`；单模块仓库即 `11`/`21`/`31`）。无可验证合约的模块不设 verify 步骤。
- 新增合约/模块 = 一套自包含脚本（`one_click_deploy_<x>.sh` + 自己的步骤脚本 + 自己的参数文件），各模块的部署输入互不要求存在——部署模块 A 不会因模块 B 的参数缺失或变动而失败。
- **账户签名统一走 keystore**：`.account` 是必需文件，提供 `KEYSTORE_ACCOUNT` 与 `ACCOUNT_ADDRESS`；不按链 ID 提供 `--unlocked` 回退，本地链与公共网络同一签名路径。
- **keystore 密码口径**：`KEYSTORE_PASSWORD` 非空时直接用于解锁，部署全程无交互；留空或未配时由 macOS `osascript` 弹窗读取（全程仅一次）；非 macOS 环境没有 `osascript`，必须预设 `KEYSTORE_PASSWORD`，脚本在缺失时明确报错，不静默退出。**入口脚本不继承调用方环境变量里的密码**：`one_click_deploy.sh` 先重置 `KEYSTORE_PASSWORD` 再读 `.account`、最后才交互，避免上次运行的残留值被静默复用；因此 `KEYSTORE_PASSWORD=xxx ./one_click_deploy.sh <net>` 不生效，非交互场景请把密码写进 `.account`。
- **密码不得进入进程参数**：`forge script --password` 会把明文放进 `/proc/<pid>/cmdline`（权限 0444，本机所有用户可读）；改用 `--password-file` 指向权限 600 的临时文件，广播结束或脚本退出时删除。环境变量（`/proc/<pid>/environ`，0400）只对同一用户可读，而 `.account` 本身就是明文密码、同一用户已能直接读取，因此作为环境变量传递不增加泄露面。部署回归测试须断言 `--password` 不出现在 forge 参数里。
- **被依赖方地址由 `.s.sol` 在广播前校验**：从配置文件读入的被依赖方地址（如 `FACTORY_ADDRESS`/`ROUTER_ADDRESS`、`MINT_ADDRESS`/`STAKE_ADDRESS`、已配置的 `WETH_ADDRESS`）由 `Deploy<X>.s.sol` 在 `startBroadcast()` 前校验代码与地址关系；脚本内派生的值（如 `Router.WETH()`）同样在广播前校验。`11_deploy.sh` 只保留编排所需的文件、链 ID、账户和密码检查；存量脚本的 `cast code` 快速失败逐步删除，不作为长期第二份校验。
- **键集合断言**：每个 check 步骤（`2x`）断言其地址文件的键集合等于期望合约集合（逐一对应、无多无缺）。键名漏改会让后续变量静默为空，逐项链上调用要到很后面才以难以定位的形式失败；显式断言把「漏改」变成即时失败。
- 下列职责**各自独立成文件**，由 `one_click_deploy.sh` 统一调用，也可按实际情况单独执行其中任一文件：

| 文件             | 职责                         |
| -------------- | -------------------------- |
| `11_deploy.sh` | 合约部署与初始化；自载入部署输入（`network.params`、被依赖方地址、本模块参数、账户），写入本库地址文件 |
| `21_check.sh`  | 校验部署与初始化是否正确（只读、可重复运行）；自载入校验文件，含上次部署写入的地址文件 |
| `31_verify.sh` | 合约开源验证（链支持开源验证时才需要）；自载入网络与地址文件 |

- 支持开源验证的链**必须包含验证环节**（`31_verify.sh`）；不支持的链上该步骤应跳过并返回成功，不视为失败，否则本地链与未接入浏览器的链无法一键跑通。
- **部署脚本改动先在本地链端到端验证再提交**：按依赖顺序先部署被依赖的代码库（如 `core` 依赖 `dex`），再跑本库入口脚本，确认校验步骤全部通过、工作区无残留改动；只有回归测试或"能编译"不算验证。

### 6.2 network 配置

- 目录命名 **`<链名><链id>_<部署类型>`**（例：`anvil31337_dev`、`bsc97_dev`、`bsc56_public`；均为示例名，按需新建）。
- `<部署类型>` 三种：`dev`（开发者内测）、`public_test`（社区公测）、`public`（正式部署）。
- **`dev` 用于 anvil 与测试网；`public_test`、`public` 只用于主网。**

每个网络目录含四个配置文件：

| 文件                        | 内容                                                             |
| ------------------------- | -------------------------------------------------------------- |
| `.account`                | `KEYSTORE_ACCOUNT`（keystore 路径或账户标识）、`ACCOUNT_ADDRESS`（部署账户地址）、`KEYSTORE_PASSWORD`（可选，口径见 6.1）；不含私钥，签名统一走 keystore |
| `network.params`          | `CHAIN_ID`、`RPC_URL`                                           |
| `<代码库名>.params`           | 构造函数或 `init` 所需的全部参数；参数名与接口声明一致                                |
| `addresses.<代码库名>.params` | 已部署的链上地址记录，供后续脚本引用与验证；代码库按模块拆分部署时，一个模块一个 `addresses.<模块名>.params`（如 `addresses.weth.params`、`addresses.uniswapv2.params`） |

- 配置键统一 **`UPPER_SNAKE_CASE`**：大写英文单词，多词用 `_` 分隔；`NFT`、`LP`、`URL`、`ID`、`RPC` 等缩写视为一个词。地址键以 `_ADDRESS` 结尾，例如 `ACTION_TARGET_ADDRESS`、`GROUP_ACTION_EXECUTOR_ADDRESS`、`MEMBER_NFT_ADDRESS`、`LP_EXECUTOR_ADDRESS`；不写 `ACTIONTARGET_ADDRESS`、`MEMBERNFT_ADDRESS`。禁止首尾或连续下划线；数字随所属单词（`LOVE20_TOKEN_ADDRESS`）。
- 生产方与消费方必须使用同一键名；跨库地址文件应可直接复制，不得在复制时手工映射。键名是部署接口的一部分，改名须同步生产方、消费方、配置模板、README 与部署回归测试。
- 该规则只约束部署配置与环境变量键，不改变 Solidity ABI、getter 或合约内 immutable 的命名。
- **参数文件的键必须显式写出，不靠默认值兜底**：`<代码库名>.params` 里每个键都要出现，空态用显式哨兵值表达（零地址=不挂载/本地部署、空串=未配置），不省略键。`Deploy<X>.s.sol` 用 `vm.envUint`/`vm.envAddress`/`vm.envString` 读取业务参数，缺键在广播前 revert 并指出键名；只有「可选依赖的缺省即为合法终态、且该值有独立互斥校验」时才允许 `vm.envOr`，默认值须与显式哨兵值同义。
- **参数只来自文件**：`<代码库名>.params` 是唯一取值来源。文件里的键由载入器 `export`，必然覆盖调用方的同名变量；键必须齐全（上一条），所以 `.s.sol` 的 `vm.env*` 不会读到「文件缺键、环境补位」的取值。但在 shell 里直接读参数值的步骤（取密码前的键存在性检查、`2x` 对账）仍需在载入前 `unset` 相关键 —— `${VAR:-}` 不因文件完整而免疫，继承值会让缺键检查与对账一起退化为自证。取值合法性仍只由 `.s.sol` 判定。
- **同一个值只能有一个来源**：复核步骤（`2x`）用参数文件里的原始值对账，不得再套一层与部署侧相同的默认值展开——两侧共用同一个默认值时，缺键会让期望值与链上值同时变成默认值，复核退化为自证。
- `.account` 含敏感信息，必须加入 `.gitignore`；其余三个提交进 Git。
- 部署脚本从这些文件读配置，不得硬编码网络参数或地址。网络切换只切 `network/` 子目录，不改脚本。
- **跨库依赖地址**：A 依赖 B 已部署合约时，把 B 的各模块 `addresses.<模块名>.params` 复制到 `A/script/network/<net>/`，与 `addresses.<A>.params` 并列，不在 A 的配置文件里重复记录 B 的地址（如 `core` 依赖 `dex` 时只复制 UniswapV2 模块的 `addresses.uniswapv2.params`；根父币由 `Router.WETH()` 读取，无需复制 WETH 模块文件）。这样 B 重新部署后，A 只需复制新地址文件即可同步，避免手工转抄与多处漂移。
- 部署脚本按依赖顺序 `source` 各 `addresses.*.params`：先被依赖方，再本库。
- 可在依赖地址文件顶部注释记录来源提交或部署时间，便于版本追踪与对账。

### 6.3 Solidity 脚本与 shell 边界

目标：每个部署期不变量只有一个主校验点；Solidity 表达“部署什么、必须满足什么”，shell 表达“如何安全执行和收尾”。

- **`Deploy<X>.s.sol`**：`_loadConfig`、广播前 `_validateConfig`、`_deploy`、部署后 `_validateDeployment`；`run` 在 `startBroadcast()` 前完成全部静态校验，在 `stopBroadcast()` 后校验完整绑定图。不处理 keystore、密码、环境文件加载或最终地址文件。
- **`11_deploy.sh`**：只做自包含加载、链 ID/账户/密码临时文件、调用 forge、地址文件原子写入、失败日志与恢复。不复制 `.s.sol` 的参数/依赖/绑定校验；`cast` 仅用于编排所需检查（文件、链、账户）。
- **`21_check.sh`**：独立、只读、可重复运行；从链上重新读取，不导入部署脚本的私有逻辑。字节码/库比对留在 shell；绑定检查可调用只读 `Check<X>.s.sol`。`2x` 是独立复核，不是 `1x` 的复制。
- **地址清单**：`.s.sol` 输出 `KEY=VALUE` 或写临时文件；`11_deploy.sh` 在全部校验通过后原子替换最终文件。广播前失败不触碰旧文件；广播后失败保留日志与 broadcast 产物。
- **权限开放路径**：用户/工厂可直接部署或初始化的合约，静态校验仍按 5.7 留在合约或工厂内，shell/Solidity 部署脚本只作额外保护。
- **测试**：每个 `_validateConfig` 不变量至少一个负向测试；`_validateDeployment` 覆盖正向绑定图；shell 回归覆盖密码、原子文件和失败恢复；全栈 E2E 覆盖 `2x`。

不为消除 lint 警告而全仓禁用 lint；只对静态校验移除的构造/init 行做窄范围抑制。
