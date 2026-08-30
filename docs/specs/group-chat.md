# LOVE20BSC Group Chat 规格

状态：BSC 版实现前冻结的独立规格。

本文档只描述群聊业务。它独立于 `core` 的治理和发射业务，也不要求读者阅读旧代码。

## 1. 范围与非目标

`group-chat` 负责群聊实例、群成员关系、消息或群内业务状态，以及只在本代码库生效的 **Group Chat Delegate**。本仓库可以保留群聊实例工厂，这是群聊自身的业务部署方式。

不包含：

- `Stake`、`Submit`、`Vote`、`Mint`、`LOVE20Phase` 和发射次数；
- `ActionTarget`、LP/链群行动执行合约或链群服务激励；
- 核心 `GroupDelegate`、地址到默认 Member 的映射和第二套 NFT 身份；
- 未部署的独立 P2P `chat` 代码库。P2P Chat 如未来纳入 BSC，另建规格。

## 2. 依赖与身份边界

只依赖 `core` 的 `MemberNFT` 查询和当前持有人授权。群、群管理员、群成员、委托者和消息相关参与主体都使用 `memberId`；钱包地址只作为当前 NFT 控制者和交易调用者。

群本身使用 MemberNFT 作为主体，以 `groupId` 标识。转移群 MemberNFT 只改变当前控制者，不改变群身份、历史消息、成员关系或历史事件归属。

群聊状态不得写入 `core`，也不得被 `action` 或 `launch` 当作治理权限来源。群聊中的权限只在本代码库内部解释。

## 3. Group Chat Delegate

**Group Chat Delegate** 是群聊内部的委托权限记录，作用域至少包含具体群/聊天和被委托的 `memberId`。它只能代表授权 MemberNFT 在 `group-chat` 内执行明确的群聊操作，例如群管理或消息相关操作；不产生治理票、质押权、发射次数、Action 验证权或其他跨仓库权限。

最小不变量：

- 只有当前控制者可以新增、修改或撤销自己的委托；
- 被委托者必须是有效 MemberNFT 的当前控制者，或按实现要求绑定有效 `memberId`；
- 委托不能超出指定群和指定操作集合；
- 群 MemberNFT 转移后，历史委托记录不改写；新的当前控制者按群聊规则继续管理或撤销委托；
- 委托撤销后立即不能用于新操作，已完成的消息和历史事件不回写。

代码和文档中统一使用 `Group Chat Delegate`，不使用容易与未来 P2P Chat 混淆的裸 `delegate` 作为跨仓库概念。

## 4. 业务状态与接口语义

实现应按 `groupId`、成员 `memberId` 和具体聊天实例隔离群成员、权限、消息索引及配置。公开写入口至少覆盖群聊创建/初始化、成员加入或移除、委托设置/撤销和群内业务操作；每个入口都验证调用者是相应 MemberNFT 当前控制者，或是当前有效的 Group Chat Delegate。

群聊实例工厂只能负责创建和登记群聊实例，不得复制 MemberNFT、治理或行动状态。实例创建、成员变更、委托变更、消息/业务操作都应发出可索引事件，事件使用 `groupId`、聊天标识和 `memberId`，不以钱包地址作为主体。

错误路径必须明确回滚：无效 MemberNFT、非当前控制者、过期或撤销的 Group Chat Delegate、越权群/操作、重复成员变更、重复初始化和非法消息状态均不得留下部分写入。

## 5. 与其他代码库的关系

- `core` 只提供 MemberNFT 身份和 owner 校验；不认识 Group Chat Delegate。
- `action` 不把群聊委托当作行动 owner、验证者或服务者；链群行动使用自己的链群 MemberNFT 规则。
- `interface-test` 只与已验收的群聊合约交互，群聊委托入口和提示必须明确显示为群聊范围；测试完成后人工同步到 `interface`。
- `love20-anvil` 可编排群聊实例工厂和最小群聊流程，但不把群聊工厂复制到其他仓库。

## 6. 验收场景

至少覆盖：MemberNFT 创建或转移后的群身份连续性、当前控制者授权、Group Chat Delegate 的新增/修改/撤销和群/操作边界、撤销后立即拒绝、群成员和消息历史不因 NFT 转移而改写、实例工厂创建唯一性、无效身份和越权操作回滚，以及与 `core`/`action` 的隔离。
