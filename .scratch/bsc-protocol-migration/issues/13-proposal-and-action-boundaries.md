# 提案、提案执行与行动扩展边界

Type: grilling
Status: resolved
Blocked by: 12

## Question

将底层治理对象从 `Action` 区分为 `Proposal`，明确提案激励领取地址、初始化 KV、投票 KV 与回调条件，并划定上层 `Action` 扩展框架的命名边界。

## Comments

用户确认：底层治理对象应称为提案。每个提案必须记录一个领取提案激励的地址，但不要求该地址是执行合约；提案初始化附加 KV 和投票附加 KV 只有在该地址是合约地址时，才分别触发初始化回调和投票回调。

用户补充确认：行动类提案统一使用 `LOVE20Action` 作为 `proposalExecutor`。创建提案时，`LOVE20Action` 通过初始化 KV 建立 `proposalId` 与具体行动执行合约的关联并完成行动初始化；初始化成功后，该 `proposalId` 才能称为有效 `actionId`。投票 KV 先到达 `LOVE20Action`，再转发给对应的行动执行合约。

## Answer

- **Proposal（提案）**是底层治理框架的对象，由 `Submit` 创建、由 `Vote` 表决，并由 `Mint` 结算提案激励。底层接口和数据使用 `proposalId` 语义。
- **`proposalExecutor`（提案执行地址）**是提案激励领取地址，可以是 EOA 或合约地址。它不是因为名字叫 executor 就必须实现合约接口。
- 当 `proposalExecutor` 是合约地址且附带非空初始化 KV 时，创建提案时触发初始化回调；当它是合约地址且某次投票附带非空 KV 时，投票时触发投票回调。EOA 不触发任何回调；没有 KV 时也不触发回调。
- `Submit` 和 `Vote` 只负责传递不透明 KV，不解析提案扩展业务。投票回调继续遵循回滚整笔投票交易的规则；初始化回调的具体 ABI 和失败处理另行确定。
- **Action（行动）**和 **ActionExecutor（行动执行合约）**是底层 `Proposal`/`proposalExecutor` 在行动扩展中的概念映射。行动类提案统一将 `proposalExecutor` 设置为 `LOVE20Action`；它通过初始化 KV 建立 `proposalId` 与具体 `ActionExecutor` 的关系并初始化行动。初始化成功后，该 `proposalId` 才是行动框架中的有效 `actionId`；普通提案没有 `actionId`。
- 行动类提案的投票回调先由 `Vote` 传给 `LOVE20Action`，再由 `LOVE20Action` 按已建立的映射将 KV 原样转发给对应的 `ActionExecutor`；行动资产、参与、验证和行动激励二次分配仍由具体行动执行层自行定义。
- `LOVE20Action` 领取的提案激励与具体 `ActionExecutor` 领取的行动激励是两类独立激励；提案激励是否由 `LOVE20Action` 转发给具体执行合约另行确定。
- 将来可以在底层治理框架之上增加与行动框架并列的其他业务扩展框架，不强行套用 `Action` 命名。
