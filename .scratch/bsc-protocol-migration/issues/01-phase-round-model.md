# 四阶段与轮次模型

Type: grilling
Status: resolved
Blocked by:

## Question

锁定投票、行动、验证、铸币四阶段的区块区间和轮次映射。明确“铸币第 N 轮/验证第 N+1 轮/行动第 N+2 轮/投票第 N+3 轮”的规范表达；定义投票阶段首个推举者如何测量上一轮实际区块数、平均窗口和异常阈值；确定目标自然日、默认阶段区块数的调整公式、生效轮次、阶段起始区块/阶段区块数历史记录，以及 APY 使用的时间基准。

## Comments

用户确认：公共时间线合约应按其维护和校准阶段数据的职责命名为 `Phase`；`Round` 保留为轮次概念和查询结果，不作为合约名。

## Answer

> 修订：后续分层讨论重新定义了 `Phase` 的边界，以下公共合约职责以本修订为准。

公共合约命名为 `Phase`。

- `Phase` 是无语义时间片基础设施，维护每个时间片的 `startBlock`、`phaseBlocks`、同步观测数据和动态校准。
- `Phase` 最小公共查询为 `currentPhase()`、`phaseInfo(uint256 phaseNumber)`、`phaseAtBlock(uint256 blockNumber)` 和 `sync()`；不内置 `Vote`、`Action`、`Verify`、`Mint` 等名称，也不直接定义 `Round`。
- `Round` 是上层使用层根据自身阶段组合定义的业务编号，从 `1` 开始；`0` 只表示未设置的存储值。
- 上层使用合约自行把时间片组合成轮次并提供无参数的语义查询；不再通过 `currentRound(Stage)` 把不同层的定义塞进公共合约。
- 部署构造参数固定为 `startBlock`、`initialPhaseBlocks` 和 `targetDays`，三者均必须大于 `0`；第一阶段编号为 `1`，不存在有效的第 `0` 阶段。
- 阶段记录只保存 `startBlock` 与 `phaseBlocks`。同步观测单独按调用顺序记录 `syncBlock`、`syncTimestamp`、调用前后的默认 `phaseBlocks` 和新参数的生效阶段；同步观测时间戳不是阶段起始区块的时间戳，两个概念不能混用。
- 下一阶段的 `startBlock` 等于上一阶段结束后的首个区块，`phaseBlocks` 使用生成该阶段记录时已生效的默认值；已经生成的阶段记录不可回写。
- `Mint N`、`Verify N+1`、`Join N+2`、`Vote N+3` 的四阶段错开关系仅是上层行动模型的约定，不是 `Phase` 的通用不变量；四个阶段同时处于运行中，不表示串行执行顺序。
- `action` 层统一定义 `ActionRound` 的四个业务阶段：投票、加入、验证、铸币。加入阶段包括行动参与、加入、退出和资产状态变化；链群行动执行实际验证，链群服务行动和 LP 行动执行合约的验证阶段为空操作，三者仍使用同一 `ActionRound` 和铸币阶段。统一轮次不代表所有行动都满足铸币条件，`canMint` 仍由具体执行合约判断。
- 设当前 `Phase` 编号为 `p`，`ActionTarget` 的四个阶段查询固定为 `currentRoundMint() = p - 3`、`currentRoundVerify() = p - 2`、`currentRoundJoin() = p - 1`、`currentRoundVote() = p`。这是同一时间点上四个阶段当前对应的轮次标签，不表示交易执行顺序；任一结果小于 `1` 时，该阶段对应的轮次尚未开始，查询回滚而不返回 `0`。`Phase 4` 是四个阶段均有有效轮次的首个时间点。
- 空轮次不逐个写入存储；已记录的阶段直接查询，未记录部分按最近历史锚点及其当时生效的 `phaseBlocks` 推导，不为无交互轮次补写整表。
- 动态校准由任何人可调用的 `sync()` 执行，不限定具体区块；投票阶段首个推举治理者在推举时负责自动调用。每次调用都记录当前 `syncBlock` 与 `syncTimestamp`，即使本次不调整阶段参数也保留观测点。
- 每次同步只检查最近一个满足 `currentBlock - syncBlock >= currentPhaseBlocks` 的观测点；没有满足条件的观测点时只记录本次观测，不改变下一阶段的 `phaseBlocks`。不要求连续三个阶段，也不为中间空阶段补写记录。
- 以选中的观测点到本次同步之间的 `elapsedBlocks` 和 `elapsedSeconds` 估算当前默认阶段的自然时长：`observedPhaseSeconds = elapsedSeconds × currentPhaseBlocks / elapsedBlocks`。该值落在 `targetSeconds = targetDays × 86400` 的 `±10%` 内时保持参数，超出才调整尚未生成阶段的 `phaseBlocks`：`newPhaseBlocks = max(1, elapsedBlocks × targetSeconds / elapsedSeconds)`。`elapsedSeconds == 0` 时跳过调整。
- 如果待调整的下一阶段记录已经生成，本次同步不回写该记录；新参数从之后第一个尚未生成的阶段开始生效，历史阶段参数和观测数据保持不变。
- APY 不进入合约，由前端按部署时设定的目标自然日计算。
- 核心治理层的 Proposal 准备与铸造阶段边界由 `Vote` 按治理轮次对外提供；`Mint` 不重复解释 `Phase` 的无语义时间片。行动扩展层可以使用同一 `Phase`，但其业务轮次判断不传回核心 `Mint`。
