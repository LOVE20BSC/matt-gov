# 四阶段与轮次模型

Type: grilling
Status: resolved
Blocked by:

## Question

锁定投票、行动、验证、铸币四阶段的区块区间和轮次映射。明确“铸币第 N 轮/验证第 N+1 轮/行动第 N+2 轮/投票第 N+3 轮”的规范表达；定义投票阶段首个推举者如何测量上一轮实际区块数、平均窗口和异常阈值；确定目标自然日、默认阶段区块数的调整公式、生效轮次、阶段起始区块/阶段区块数历史记录，以及 APY 使用的时间基准。

## Comments

用户确认：公共时间线合约应按其维护和校准阶段数据的职责命名为 `LOVE20Phase`；`Round` 保留为轮次概念和查询结果，不作为合约名。

## Answer

> 修订：后续分层讨论重新定义了 `LOVE20Phase` 的边界，以下公共合约职责以本修订为准。

公共合约命名为 `LOVE20Phase`。

- `LOVE20Phase` 是无语义时间片基础设施，维护每个时间片的 `startBlock`、`phaseBlocks`、同步观测数据和动态校准。
- `LOVE20Phase` 最小公共查询为 `currentPhase()`、`phaseInfo(uint256 phaseNumber)`、`phaseAtBlock(uint256 blockNumber)` 和 `sync()`；不内置 `Vote`、`Action`、`Verify`、`Mint` 等名称，也不直接定义 `Round`。
- `Round` 是上层使用层根据自身阶段组合定义的业务编号，从 `1` 开始；`0` 只表示未设置的存储值。
- 上层使用合约自行把时间片组合成轮次并提供无参数的语义查询；不再通过 `currentRound(Stage)` 把不同层的定义塞进公共合约。
- 部署构造参数固定为 `startBlock`、`initialPhaseBlocks` 和 `targetDays`，三者均必须大于 `0`；第一阶段编号为 `1`，不存在有效的第 `0` 阶段。
- 每条阶段记录至少保存 `startBlock` 与 `phaseBlocks`；生成下一阶段时，另外保存发生同步的 `syncBlock` 与 `syncTimestamp`。同步观测时间戳不是阶段起始区块的时间戳，两个概念不能混用。
- 下一阶段的 `startBlock` 等于上一阶段结束后的首个区块，`phaseBlocks` 使用生成该阶段记录时已生效的默认值；已经生成的阶段记录不可回写。
- `Mint N`、`Verify N+1`、`Action N+2`、`Vote N+3` 的四阶段错开关系仅是上层行动模型的约定，不是 `LOVE20Phase` 的通用不变量；四个阶段同时处于运行中，不表示串行执行顺序。
- 空轮次不逐个写入存储；已记录的阶段直接查询，未记录部分按最近历史锚点及其当时生效的 `phaseBlocks` 推导，不为无交互轮次补写整表。
- 动态校准由任何人可调用的 `sync()` 执行，不限定具体区块；投票阶段首个推举治理者在推举时负责自动调用。每次调用都记录当前 `syncBlock` 与 `syncTimestamp`，即使本次不调整阶段参数也保留观测点。
- 每次同步只检查最近一个满足 `currentBlock - syncBlock >= currentPhaseBlocks` 的观测点；没有满足条件的观测点时只记录本次观测，不改变下一阶段的 `phaseBlocks`。不要求连续三个阶段，也不为中间空阶段补写记录。
- 以选中的观测点到本次同步之间的区块数和时间戳差计算实际出块速度；实际时长落在目标自然日的 `±10%` 内则保持参数，超出才按比例调整尚未生成阶段的 `phaseBlocks`：`newPhaseBlocks = elapsedBlocks × targetSeconds / elapsedSeconds`，其中 `targetSeconds = targetDays × 86400`，结果至少为 `1`。`elapsedSeconds == 0` 时跳过调整。
- 如果待调整的下一阶段记录已经生成，本次同步不回写该记录；新参数从之后第一个尚未生成的阶段开始生效，历史阶段参数和观测数据保持不变。
- APY 不进入合约，由前端按部署时设定的目标自然日计算。
- 核心治理层的 Proposal 准备与铸造阶段边界由 `Vote` 按治理轮次对外提供；`Mint` 不重复解释 `LOVE20Phase` 的无语义时间片。行动扩展层可以使用同一 `LOVE20Phase`，但其业务轮次判断不传回核心 `Mint`。
