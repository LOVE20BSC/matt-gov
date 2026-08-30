# 行动 Target 与参与登记边界

Type: grilling
Status: resolved
Blocked by: 01

## Question

定义行动执行合约的授权与生命周期：执行合约如何负责参与、验证、铸造激励；是否提供内置默认执行合约；Join 如何登记扩展行动；ExtensionCenter 是否只做索引/统一查询；坏掉或失联的执行合约如何被强制退出；行动合法性由链上约束还是治理投票决定；前端可信扩展列表与链上可参与条件如何分工。

## Comments

> 本节保留了历史讨论和被后续决议替换的名称；实现只以本票据 `Answer` 及地图 `Decisions so far` 为准。

用户确认：用户必须可以强制退出，避免错误的行动执行合约长期占用用户的已参与行动列表；`ExtensionCenter` 的参与登记职责并入行动框架合约 `ActionTarget`，不再保留独立中心合约；`ActionTarget` 不引入旧 `Join` 的随机抽取账号及其相关逻辑。

用户补充确认：强制退出必须显式传入 `tokenAddress`，因为 `actionId` 按子币隔离，且退出涉及明确的资产归属。建议接口为 `forceExit(tokenAddress, actionId, memberId)`。

用户确认：行动执行合约可以复用于多个代币社区和多个行动；不再采用为每个行动通过工厂单独创建执行合约的模式。

用户确认：`LOVE20Submit` 应删除旧版随机抽取相关的冗余参数，包括 `maxRandomAccounts` 和 `whiteListAddress`；`executor` 不作为 `Submit` 字段，而是由 `ActionTarget` 从创建 KV 的保留项解析。

用户补充讨论：执行合约字段名直接使用 `executor`；`minStake` 不再由核心行动参数维护；执行合约初始化参数统一放入 Proposal 创建 KV；原 `verificationInfoGuides` 改为与 `verificationKeys` 对应的 `verificationKeyGuides`。

用户确认最终字段方向：行动创建 KV 保留 `executor` 及行动类型专属字段；`title` 和 `verificationRule` 归入底层 Proposal 的 `title`、`details`，删除 `minStake`、`maxRandomAccounts` 和 `whiteListAddress`。

此前关于删除 `LOVE20Mint`、让 `executor` 可选以及重新划分 `Mint` 职责的临时设想已被后续决议覆盖；最终规则以 `LOVE20Mint` 保留、`executor` 必须为非零合约地址，以及本票据 Answer 中的分层与激励边界为准。

用户修正并确认：`LOVE20Mint` 保留；行动激励由该行动的非零合约型 `executor` 业务处理；行动验证不再由核心 `LOVE20Verify` 负责，而由各行动执行合约自行完成；核心删除 `LOVE20Verify` 及随机抽取地址准备逻辑。

该确认同时撤回“必须实现统一 `IActionExecutor` 并由核心反向调用 `join/verify/mint`”的前置设想：`executor` 是非零行动激励授权合约；`ActionTarget` 维护参与登记和强制退出，核心 `LOVE20Verify` 删除，行动验证由执行合约自行完成；`Mint` 保留激励额度、供应上限和铸造授权职责。

早期以 `Vote -> Mint` 或 `Vote -> Action -> Verify -> Mint` 描述层级流程的说法已被后续的无语义时间片方案覆盖：`LOVE20Phase` 不写入这些阶段名称或顺序，各层只按自身业务组合所需的时间片。（行动创建仍必须拒绝零地址 `executor`。）

用户确认：治理激励完全依据 `Stake` 与 `Vote` 计算和铸造，不再依赖 `Verify`；`LOVE20Mint` 在投票结束后的铸造阶段负责治理激励准备与铸造。

用户确认：行动类 Proposal 的激励由关联 `executor` 发起调用 `ActionTarget`，再由 `ActionTarget` 调用 `Mint` 铸造并将实际数量转回 `executor`；`Mint` 不接收 `memberId` 或调用者指定的 `amount`，实际铸造数量作为结果返回。

用户确认：阶段合约获取当前轮次的函数不传入阶段参数，因为底层治理层和上层行动层对阶段的定义不同。共享阶段时间线应提供无参数的命名查询，各层只调用自身需要的阶段查询。

用户进一步修正：阶段是底层治理框架提供的无语义时间片；阶段如何组合成轮次、阶段在不同上层中的名称和含义，由具体使用层定义。`LOVE20Phase` 不应内置 `Vote`、`Action`、`Verify`、`Mint` 等阶段名称，也不应直接承担上层 `Round` 语义。

用户确认：`LOVE20Phase` 只提供无语义的 `currentPhase()`、`phaseInfo(phaseNumber)`、`phaseAtBlock(blockNumber)` 和 `sync()` 等基础查询；各上层自行定义阶段名称、轮次组合和无参数的语义查询。

用户修正：资产托管不属于通用行动框架；参与资产、扩展资产及其返还和行动内分配均由具体行动执行合约自行处理，`ActionTarget` 不接收或持有行动资产。

用户补充确认：`forceExit` 首版即部署，只在执行合约失效等无法正常退出的情况下作为最后兜底，用于清理已参与行动列表；它绕过执行合约，可能导致资产无法返还。仅当前 `MemberNFT` 持有人可以调用并发出清理事件。正常加入、退出和资产取回都必须通过行动执行合约完成，前端首版隐藏该入口，后续确有需要再启用。

用户确认：行动类提案统一使用 `ActionTarget` 作为 Proposal Target；Proposal 创建回调通过 KV 建立 `proposalId` 与具体行动执行合约的关联；`actionId` 只是对应行动类 Proposal 的 `proposalId` 业务别名，数值完全相同；投票 KV 由 `ActionTarget` 转发给对应行动执行合约。

用户修订：提案激励接收地址和回调地址合并为单一 `target`，并用 `targetMode` 区分 `RewardOnly` 与 `Callback`；行动类提案使用 `ActionTarget + Callback`。

用户修订：`verificationKeys`、`verificationKeyGuides` 等行动专属验证信息通过 Proposal 创建 KV 交给 `ActionTarget` 转发，由具体行动执行合约保存和解释；`verificationRule` 最终归入底层 `details`。

用户修订：底层提案保留通用 `details` 字段；行动框架将其称为 `verificationRule`，不通过创建 KV 重复传递。`verificationKeys` 和 `verificationKeyGuides` 等行动专属字段仍通过创建 KV 交给具体执行合约。

用户确认：`ActionTarget` 和行动执行合约都支持底层治理框架传导的提案创建、提案推举和提案投票回调；行动执行合约的“初始化”就是 Proposal 创建回调，核心先回调 `ActionTarget`，`ActionTarget` 再将标准上下文和不透明 KV 转发给行动执行合约。

用户确认：行动类 Proposal 的 `target` 固定为 `ActionTarget`；核心治理框架不直接回调行动执行合约，执行合约不得绕过 `ActionTarget` 成为 Proposal 目标。

用户修正：`executor == address(0)` 不属于合法行动配置，`ActionTarget` 处理 Proposal 创建回调时必须拒绝零地址；不再保留行动激励自动销毁的零地址路径。

用户确认：`title` 是底层 Proposal 的通用字段。行动执行合约的创建回调可以通过 `proposalId` 查询 Proposal 的 `title` 和 `details`，创建 KV 不再重复传递 `title`。

用户确认：ActionTarget 通过保留键 `keccak256("executor")` 识别执行合约地址，值按 `abi.encode(executorAddress)` 编码；其他 KV 由行动执行合约自行定义和解码。

用户确认：为节省 Gas，创建 KV 的第 `0` 项固定为 `keccak256("executor")`，`ActionTarget` 只读取该项并校验执行合约代码存在，然后把完整 KV 原样转发给执行合约，不创建去掉第 `0` 项的新数组；投票回调不携带 executor KV，直接使用已保存的 `tokenAddress + proposalId -> executor` 映射。

用户补充确认：`ActionTarget` 提供两类只读查询：传入 `executor + 治理轮次` 时返回该执行合约关联的 `proposalId[]`，供业务聚合；不传入 `executor` 时返回本轮所有有投票且已关联执行合约的 `(proposalId, executor)`，供前端社区行动列表展示。两类查询都先从 `Vote` 取得本轮有投票的 Proposal ID，再逐个按 ID 读取 `ActionTarget` 保存的执行合约映射并筛选，不新增独立反向索引；查询按单轮一次性返回完整结果，不单独设计分页。

## Answer

- Proposal 创建时，创建 KV 的第 `0` 项必须是保留键 `keccak256("executor")`，值为 `abi.encode(executorAddress)`；其余 KV 由行动类型内部定义。`ActionTarget` 只读取第 `0` 项并校验非零合约型 `executor`，保存映射后将完整 KV 原样转发给该执行合约，不复制或过滤数组。`title` 和 `details` 是底层 Proposal 通用字段，行动类型将后者解释为 `verificationRule`，执行合约按 `proposalId` 查询，不在 KV 中重复传递。推举和投票回调使用已保存的执行合约映射，不携带 executor KV；`verificationKeys` 和 `verificationKeyGuides` 等字段由行动类型内部业务自行保存和解释；不要求统一 `IActionExecutor` 接口，也不为每个行动通过工厂创建业务组件，不提供核心默认执行合约。
- 行动类 Proposal 的 `target` 固定为 `ActionTarget`。`ActionTarget` 实现底层治理框架的 Proposal 创建、推举和投票回调，以 `tokenAddress + proposalId` 保存行动映射；同一复合键重复创建回调直接回滚。它解析创建 KV 中的 `executor`，要求其为非零合约地址，并将三个时点的标准上下文和 KV 转发给该行动执行合约；执行合约的对应回调只允许 `ActionTarget` 调用。
- 新版只保留一份 Proposal 激励，分配单位由旧版 `Mint.actionReward` 的 `actionId` 泛化为 `proposalId`。投票阶段结束后，`LOVE20Mint` 只按 `tokenAddress + round` 准备并冻结轮次级总激励状态，不逐个预写 Proposal 额度；每个 Proposal 由自己的 Proposal Target 在铸造时根据该轮已冻结的 `Vote` 状态计算并铸造。通过门槛的 Proposal 之间按核心 `Vote` 记录的投票数占比分配，分母只统计合格 Proposal 的投票总数，不依赖行动执行层或 `LOVE20Verify`。未通过门槛的 Proposal 不参与分配，未分配部分按核心激励池既有的预留、铸造和销毁状态处理。
- 治理激励沿用旧版 `Mint` 的三段结果 `(verifyReward, boostReward, burnReward)`：同一轮允许同一 `MemberNFT` 多次投票，每次只记录本次新增治理票数；验证激励按本轮累计治理票数占所有投票人治理票总数的比例计算。加速质押按投票时快照做增量记账，只有后续同轮再次投票时才补记超过已记录值的差额，质押增加但没有后续投票时不单独记账，未增加时不重复计入；理论加速激励按各成员累计已记录质押量占所有投票人累计已记录质押总量的比例计算。实际加速激励为 `min(理论加速激励, 验证激励 × MAX_GOV_BOOST_REWARD_MULTIPLIER)`，溢出激励为理论值减实际值。验证激励和实际加速激励一并铸造为治理激励，溢出激励销毁。
- Proposal Target 是该 Proposal 唯一被 `Mint` 授权铸造并临时接收激励的主体。`LOVE20Mint.mintProposalReward(tokenAddress, round, proposalId)` 只能由已记录的 `target` 调用，实际代币由协议铸造给该地址并返回数量，且同一提案只能成功一次；不允许其他地址代铸，也不再存在独立的 `mintActionReward` 激励池。对于行动类 Proposal，`ActionTarget` 的铸造入口只接受关联的 `executor` 调用；`ActionTarget` 再以自身身份调用 `Mint`，并在同一笔交易中将实际铸造数量全部转给该 `executor`，不得把激励留在 `ActionTarget`。
- Proposal 激励查询不维护独立激励枚举或事件索引依赖；先从 `Vote` 查询指定社区和轮次内实际有投票的 Proposal 列表，再按 `tokenAddress + round + proposalId` 查询 `Mint` 的激励状态。无投票 Proposal 不进入该查询集合。
- 对行动类 Proposal，关联的 `executor` 发起调用 `ActionTarget` 的铸造入口，其他地址不能代铸；`ActionTarget` 作为 `target` 调用 `Mint`，由 `Mint` 将激励铸给 `ActionTarget` 并返回实际数量，随后 `ActionTarget` 在同一笔交易中将全部数量转回该 `executor`，由 `executor` 再按行动内部规则二次分配。任一步失败都回滚，激励不得留在 `ActionTarget`；`executor` 不直接调用核心 `Mint` 铸造。零地址 `executor` 在行动创建时直接回滚。
- `ActionTarget` 合并原 `ExtensionCenter` 的参与登记职责，不引入旧 `Join` 的随机抽取地址及相关逻辑。链上只维护行动当前可参与状态、参与关系和业务组件登记；参与资产由行动类型内部业务处理，行动参与与验证规则也由内部业务实现，核心不再保留 `LOVE20Verify`。行动合法性由治理投票决定，前端只与可信扩展交互。
- `ActionTarget.forceExit(tokenAddress, actionId, memberId)` 首版即部署，作为行动类型内部业务失效时的最后兜底；仅允许当前 `MemberNFT` 持有人调用，只清理通用参与登记并发出事件，不调用内部业务，也不承诺返还任何资产。正常加入、退出和资产取回均由行动类型内部业务负责，前端首版隐藏该入口，后续按需要开放。
- `LOVE20Submit` 删除 `minStake`、`maxRandomAccounts` 和 `whiteListAddress` 等旧参数；`executor` 仅由 `ActionTarget` 从创建 KV 解析，行动参与门槛由执行合约自行决定。
- `ActionTarget` 提供两类按 `tokenAddress + 治理轮次` 的完整只读查询：传入 `executor` 时返回该执行合约关联的 `proposalId[]`；不传入 `executor` 时返回本轮所有已投票且已关联执行合约的 `(proposalId, executor)`，供前端社区行动页面展示。两类查询都先读取 `Vote` 的本轮有投票 Proposal ID，再逐个按 ID 读取执行合约映射并筛选；不新增独立反向索引，也不在 `ActionTarget` 内计算投票门槛。若后续全量服务激励铸造超过目标网络的 Gas 基线，应拆分铸造/结算状态，而不是只给该查询增加分页。
- `action` 层所有执行合约共用 `ActionRound` 的 `Vote`、`Action`、`Verify`、`Mint` 四个时间槽位，以便前端和服务行动使用统一轮次；链群行动执行实际验证，链群服务和 LP 执行合约的 `Verify` 槽位为空操作，不创建独立验证业务。具体执行合约仍自行判断当前 Proposal 是否满足 `canMint`，统一轮次不等于统一铸币资格。
