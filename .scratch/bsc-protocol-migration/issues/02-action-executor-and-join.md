# 行动执行地址与 LOVE20Action 边界

Type: grilling
Status: resolved
Blocked by: 01

## Question

定义行动执行地址（合约、EOA 或零地址）的授权与生命周期：执行地址如何负责参与、验证、铸造激励；是否提供内置默认执行合约；Join 如何登记扩展行动；ExtensionCenter 是否只做索引/统一查询；坏掉或失联的执行地址如何被强制退出；行动合法性由链上约束还是治理投票决定；前端可信扩展列表与链上可参与条件如何分工。

## Comments

用户确认：用户必须可以强制退出，避免错误的行动执行合约长期占用用户的已参与行动列表；`ExtensionCenter` 的参与登记职责并入行动框架合约 `LOVE20Action`，不再保留独立中心合约；`LOVE20Action` 删除旧版随机抽取账号及其相关逻辑。

用户补充确认：强制退出必须显式传入 `tokenAddress`，因为 `actionId` 按子币隔离，且退出涉及明确的资产归属。建议接口为 `forceExit(tokenAddress, actionId, memberId)`。

用户确认：行动执行合约可以复用于多个代币社区和多个行动；不再采用为每个行动通过工厂单独创建执行合约的模式。

用户确认：`LOVE20Submit` 应删除旧版随机抽取相关的冗余参数，并以 `actionExecutor` 取代旧的 `whiteListAddress`。

用户补充讨论：执行合约字段名直接使用 `executor`；`minStake` 也不再由核心行动参数维护；行动初始化需要增加按行动传入的 `executorKeys` 和 `executorValues`；原 `verificationInfoGuides` 需要改成与 `verificationKeys` 对应的名称，推荐 `verificationKeyGuides`。

用户确认最终字段方案：`ActionBody` 保留 `executor`、`executorKeys`、`executorValues`、`title`、`verificationRule`、`verificationKeys`、`verificationKeyGuides`；删除 `minStake`、`maxRandomAccounts` 和 `whiteListAddress`。

用户提出新的分层模型：`Stake`、`Submit`、`Vote` 构成底层治理框架；只有行动执行合约需要行动参与、验证和行动者激励时，才进入上层行动流程；治理激励可在投票阶段结束后结算，`LOVE20Mint` 可能删除。该模型与“每个行动必须指定执行合约”的既有结论存在冲突，待确认执行合约是否可选，以及奖励预留、供应上限和发射资格等原 `Mint` 职责的归属。

用户修正并确认：`LOVE20Mint` 保留；行动激励只能由该行动的 `executor` 铸造，`executor` 可以是合约地址或 EOA；`executor == address(0)` 表示行动激励无人可铸，`Mint` 必须保留对应销毁路径，或在准备本轮激励时直接销毁该行动的行动激励；行动验证不再由核心 `LOVE20Verify` 负责，而由各行动执行地址自行完成；核心删除 `LOVE20Verify` 及随机抽取地址准备逻辑。

该确认同时撤回“必须实现统一 `IActionExecutor` 并由核心反向调用 `join/verify/mint`”的前置设想：`executor` 是行动激励授权地址，可以是合约或 EOA；`Join` 维护参与登记和强制退出，`Verify` 删除，行动验证由执行地址自行完成；`Mint` 保留奖励额度、供应上限和铸造授权职责。

用户进一步确认：`executor == address(0)` 的行动奖励在 `Mint.prepareReward` 时自动记为已销毁；`LOVE20Mint` 属于底层治理框架，底层只消费 `Vote -> Mint` 两个阶段；上层行动参与者消费 `Vote -> Action -> Verify -> Mint` 四个阶段。四阶段时间线可以统一维护，但各层只使用自身需要的阶段。

用户确认：治理激励完全依据 `Stake` 与 `Vote` 计算和领取，不再依赖 `Verify`；`LOVE20Mint` 在投票结束后的铸造阶段负责治理激励准备与领取。

用户确认：行动执行地址一次性领取某行动某轮的全部行动激励，`Mint` 不接收 `memberId` 或 `amount`，而是将实际铸造数量作为返回值；执行地址再在自身逻辑中二次分配。

用户确认：阶段合约获取当前轮次的函数不传入阶段参数，因为底层治理层和上层行动层对阶段的定义不同。共享阶段时间线应提供无参数的命名查询，各层只调用自身需要的阶段查询。

用户进一步修正：阶段是底层治理框架提供的无语义时间片；阶段如何组合成轮次、阶段在不同上层中的名称和含义，由具体使用层定义。`LOVE20Phase` 不应内置 `Vote`、`Action`、`Verify`、`Mint` 等阶段名称，也不应直接承担上层 `Round` 语义。

用户确认：`LOVE20Phase` 只提供无语义的 `currentPhase()`、`phaseInfo(phaseNumber)`、`phaseAtBlock(blockNumber)` 和 `sync()` 等基础查询；各上层自行定义阶段名称、轮次组合和无参数的语义查询。

用户确认：`LOVE20Mint.mintActionReward(tokenAddress, round, actionId)` 由该行动的 `executor` 一次性领取全部行动激励，返回实际铸造数量；不接收 `memberId` 或 `amount`，执行地址自行二次分配。

用户补充确认：`executor == address(0)` 并不表示该行动没有行动激励，也不将额度分配给其他行动；该行动仍按本轮规则获得自己的行动激励额度，`Mint.prepareReward` 时将该额度自动销毁。

用户修正：资产托管不属于通用行动框架；参与资产、扩展资产及其返还和行动内分配均由具体行动执行合约自行处理，`LOVE20Action` 不接收或持有行动资产。

用户补充确认：`forceExit` 只在执行合约失效等无法正常退出的情况下作为最后兜底，用于清理已参与行动列表；它绕过执行合约，可能导致资产无法返还。正常加入、退出和资产取回都必须通过行动执行合约完成，前端默认不提供该入口，首版不开放，后续确有需要再启用。

用户确认：行动类提案统一使用 `LOVE20Action` 作为 `proposalExecutor`；提案创建时由初始化 KV 建立 `proposalId` 与具体行动执行合约的关联，初始化成功后该 `proposalId` 才作为有效 `actionId` 使用；投票 KV 由 `LOVE20Action` 转发给对应行动执行合约。

用户修订：提案激励接收地址和回调地址合并为单一 `proposalTarget`，并用 `proposalTargetMode` 区分 `RewardOnly` 与 `Callback`；行动类提案使用 `LOVE20Action + Callback`。

用户修订：`verificationRule`、`verificationKeys`、`verificationKeyGuides` 等附加验证信息不再作为底层提案固定字段，而通过行动初始化 KV 交给 `LOVE20Action` 转发，由具体行动执行合约保存和解释。

用户修订：底层提案保留通用 `proposalDetails` 字段；行动框架将其称为 `verificationRule`，不通过初始化 KV 重复传递。`verificationKeys` 和 `verificationKeyGuides` 等行动专属字段仍通过初始化 KV 交给具体执行合约。

## Answer

- 行动初始化通过 KV 保存 `executor`、`executorKeys`、`executorValues`、`title` 及具体执行合约需要的行动专属验证信息；底层 `proposalDetails` 在行动框架中作为 `verificationRule` 使用，不重复放入 KV。`verificationKeys` 和 `verificationKeyGuides` 等字段由具体 `ActionExecutor` 自行保存和解释。`executor` 可以是合约地址或 EOA；不要求统一 `IActionExecutor` 接口，也不为每个行动通过工厂创建执行合约，不提供核心默认执行合约。
- `executor` 是该行动激励的唯一铸造授权地址。`LOVE20Mint.mintActionReward(tokenAddress, round, actionId)` 由它一次性领取该行动该轮的全部行动激励，返回实际铸造数量，不接收 `memberId` 或 `amount`，后续分配由执行地址自行完成。
- `executor == address(0)` 仍按本轮规则为该行动计算并保留行动激励额度；额度不转给其他行动，也不存在可领取者。`LOVE20Mint.prepareReward` 准备该轮奖励时直接将这笔本行动额度记为已销毁/已消费，并保留重复铸造保护和供应上限核算。
- `LOVE20Action` 合并原 `ExtensionCenter` 的参与登记职责，删除随机抽取地址及相关逻辑。链上只维护行动当前可参与状态、参与关系和执行地址登记；参与资产由执行地址处理，行动参与与验证规则也由执行地址实现，核心不再保留 `LOVE20Verify`。行动合法性由治理投票决定，前端只与可信扩展交互。
- `LOVE20Action.forceExit(tokenAddress, actionId, memberId)` 是执行合约失效时的最后兜底，仅清理通用参与登记，不调用执行合约，也不承诺返还任何资产；正常加入、退出和资产取回均由具体行动执行合约负责。前端首版不提供该入口，后续按需要开放。
- `LOVE20Submit` 删除 `minStake`、`maxRandomAccounts` 和 `whiteListAddress` 等旧参数；行动参与门槛由执行地址决定。
