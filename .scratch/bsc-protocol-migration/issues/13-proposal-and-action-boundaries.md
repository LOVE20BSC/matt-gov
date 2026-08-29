# 提案、提案执行与行动扩展边界

Type: grilling
Status: resolved
Blocked by: 12

## Question

将底层治理对象从 `Action` 区分为 `Proposal`，明确提案激励领取地址、初始化 KV、投票 KV 与回调条件，并划定按提案类型实现的 `Target` 命名边界。

## Comments

用户确认：底层治理对象应称为提案。每个提案必须记录一个领取提案激励的地址，但不要求该地址是执行合约；提案初始化附加 KV 和投票附加 KV 只有在该地址是合约地址时，才分别触发初始化回调和投票回调。

用户补充确认：行动类提案统一使用 `LOVE20Action` 作为 `proposalExecutor`。创建提案时，`LOVE20Action` 通过初始化 KV 建立 `proposalId` 与具体行动执行合约的关联并完成行动初始化；初始化成功后，该 `proposalId` 才能称为有效 `actionId`。投票 KV 先到达 `LOVE20Action`，再转发给对应的行动执行合约。

用户修订：行动类提案的目标合约统一称为 `ActionTarget`。它是提案扩展层针对社群行动类型的实现；其内部是否存在 `ActionExecutor` 等进一步组件，属于该业务自身，不作为协议级固定分层。

用户确认：不拆分提案激励接收地址和回调地址。提案使用单一 `proposalTarget` 地址和 `proposalTargetMode` 模式（`RewardOnly` 或 `Callback`）；行动类提案使用 `LOVE20Action + Callback`。

用户确认：提案中的 `verificationRule`、`verificationKeys`、`verificationKeyGuides` 等附加验证信息移出底层 `Proposal`，放入行动初始化 KV；`LOVE20Action` 只负责转发，具体 `ActionExecutor` 自行保存、解释和使用。

用户修订：底层 `Proposal` 保留通用字段 `proposalDetails`；在行动框架中，该字段按行动语义称为 `verificationRule`，不在行动初始化 KV 中重复保存。`verificationKeys` 和 `verificationKeyGuides` 仍通过行动初始化 KV 传递。

## Answer

- **Proposal（提案）**是底层治理框架的对象，由 `Submit` 创建、由 `Vote` 表决，并由 `Mint` 结算提案激励。底层接口和数据使用 `proposalId` 语义。
- **`proposalDetails`（提案详情）**是底层提案的通用详情字段；行动框架将其解释为 `verificationRule`，不重复保存。
- **`proposalTarget`（提案目标地址）**是提案激励接收地址，配合 `proposalTargetMode` 使用。`RewardOnly` 只接收激励、不触发回调；`Callback` 要求目标是合约，并在对应 KV 非空时触发初始化或投票回调。
- 行动类提案固定使用 `proposalTarget = ActionTarget`、`proposalTargetMode = Callback`；`ActionTarget` 接收提案激励并负责行动初始化及投票 KV 的类型内处理或转发。
- `Submit` 和 `Vote` 只负责传递不透明 KV，不解析提案扩展业务。投票回调继续遵循回滚整笔投票交易的规则；初始化回调的具体 ABI 和失败处理另行确定。
- **Action（行动）**是提案扩展层中的一种提案类型，`ActionTarget` 是该类型的目标合约。它通过初始化 KV 建立 `proposalId` 与行动内部业务对象的关系并初始化行动；初始化成功后，该 `proposalId` 才是行动类型中的有效 `actionId`，普通提案没有 `actionId`。
- 行动类提案的投票回调由 `Vote` 传给 `ActionTarget`，后续是否转发给 `ActionExecutor` 或其他内部组件，由 `ActionTarget` 自身决定；行动资产、参与、验证和行动激励二次分配均属于行动类型内部业务。
- `ActionTarget` 领取的提案激励与行动类型内部业务领取的行动激励是两类独立激励；提案激励不因内部二次分配规则而改变。
- `verificationKeys`、`verificationKeyGuides` 等行动专属验证信息属于行动初始化 KV；底层 `proposalDetails` 在行动类型中作为 `verificationRule` 使用。`ActionTarget` 不替内部组件解释这些字段。
- 将来可以在底层核心治理层之上增加其他提案类型的 `Target` 合约，不强行套用 `Action` 命名。
