# 仓库迁移矩阵与依赖边界

Type: grilling
Status: resolved
Blocked by:

## Question

形成 LOVE20TKM 每个仓库到 LOVE20BSC 的最终矩阵：保留、合并、删除、归档或新建；确定 `core` 合并 Member 身份基础设施后的目录和部署边界，`extension`/`extension-group`/`group-chat`/`periphery`/`script`/`docs`/`chat`/`batch-transfer`/`love20-anvil` 的目标仓库、依赖方向、命名和迁移顺序；确认旧组织只读/归档时机及旧 URL、CI、密钥、webhook 清理标准。

## Comments

> 本节保留了历史迁移讨论和旧仓库名称；实现只以本票据 `Answer` 及地图 `Decisions so far` 为准。

用户确认迁移范围规则：只迁移 `LOVE20TKM` 中已经部署到 `thinkium70001_public` 网络的合约代码；未在该网络部署的合约代码不纳入本次 LOVE20BSC 迁移。

用户确认：迁移资格以 `thinkium70001_public` 对应地址在链上确实存在合约代码为准；部署参数、脚本或本地 artifact 只能作为辅助证据，不能单独证明已部署。

用户确认：同一仓库按合约级裁剪；只迁移已部署合约及其必要依赖，未部署的实验合约、旧版本和仅测试代码不因同仓库存在而自动迁移。

用户确认：`interface-test`、部署 `script`、`periphery`、`love20-anvil` 和 `docs` 都列入 LOVE20BSC 迁移范围，迁移后按 BSC 新协议统一更新；不再要求这些配套代码逐文件证明直接服务于某个已部署合约。链上部署规则仍只约束旧合约代码的迁移来源。

用户确认：上述配套代码库整体迁移，再按 BSC 新协议清理无关或废弃内容。

用户确认代码库分层：`core` 独立维护底层治理框架、发射次数/子币创建基础设施、`MemberNFT` 和 `LOVE20Phase`；提案扩展按业务框架拆分代码库。当前只建设社群行动业务，因此由 `action` 统一维护 `ActionTarget` 和常用行动执行合约。公平发射后的复杂分配机制本阶段暂不创建 `launch` 代码库，未来需求明确后再独立建立。

用户确认：`ActionTarget` 内部是否再拆分执行器、验证器或分配器属于社群行动业务内部结构；代码库层面统一由 `action` 维护。未来出现并列提案扩展类型时，再按业务框架拆分新的代码库。

用户确认：旧 `extension`、`extension-group` 归并到 `action`，按新的 `ActionTarget` 和行动执行模型重写；旧 `extension-lp` 只迁移 V2 的 LP 业务，重写为 `action` 内的 LP 行动执行合约。V1 LP 实现、旧 LP 工厂和其他旧扩展工厂不迁移，不保留独立的 `extension` 系列代码库。

用户确认：`periphery`、`script`、`interface-test`、`love20-anvil`、`docs` 继续保持独立代码库，不并入 `core` 或 `action`。

用户确认：`group-chat` 保持独立代码库，只依赖新的 `core` 身份接口和部署地址，不并入 `action`。

用户确认：`batch-transfer` 作为相对独立的工具代码库单独迁移，不并入 `core` 或 `action`。

用户确认：`interface` 与 `interface-test` 都迁移到新组织，但日常只修改 `interface-test`；验收后手动同步到 `interface` 正式发布，两者不合并。

用户确认：迁移阶段不创建独立 `launch` 代码库；旧 `burn` 不迁移，旧 `core` 中与发射相关的必要能力按 BSC 规则重写进新 `core`，发射次数直接附加到 MemberNFT 的 `tokenAddress + memberId` 账本并支持部分融合。未来若需要复杂分配机制，再另建 `launch`。

用户确认：`v2-periphery` 不迁移；它没有 `thinkium70001_public` 部署地址，且来源为 Uniswap 官方仓库，继续作为外部依赖。BSC 使用与 Uniswap V2 兼容的 PancakeSwap；不把依赖表述写死为某个 PancakeSwap 版本，接入前必须验证其接口和关键内部行为。

补充核对结论：PancakeSwap 的 Uniswap V2 fork 不能默认视为源码逐字相同。以官方 [PancakePair](https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakePair.sol) 与 [UniswapV2Pair](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol) 源码为例，`swap` 的手续费校验常量可能使用 `1000/2`，而 Uniswap V2 参考实现使用 `1000/3`；目标链实际部署版本也可能不同。但本次兼容性验收关注的是 `Stake` 所依赖的功能和数值结果，不要求无关实现细节逐字一致。必须以目标链具体 Factory/Router/Pair 地址、已验证源码和 runtime bytecode 为准，验证 LP 份额、手续费结算、路由报价、储备更新和失败回滚；只有差异会导致这些结果错误时，才阻断直接接入并改用适配层或停止集成。

用户确认：旧网络虽已部署，但被 BSC 新协议明确删除或替代的 `SL/ST`、核心 `LOVE20Verify`、`Random`、旧 `Join` 等合约不迁移；`core` 只保留并重写新的 `Stake`、`Submit`、`Vote`、`Mint`、发射、`MemberNFT` 和 `Phase`。`GroupVerify` 属于 `action` 内部的链群验证组件，是否独立仅由字节码限制决定。

用户补充确认：`LOVE20TokenFactory` 保留在 `core`，作为子币部署的技术拆分，可能用于规避组合后的合约体积或部署限制；这不改变删除旧扩展业务工厂的决定。

## Answer

已确认 `GroupVerify` 与 **Group Chat Delegate** 的边界：

- 旧 `GroupVerify` 因部署字节码超限而独立拆出；BSC 将其作为 `action` 内部的技术拆分处理：合并后若仍超过部署限制则保留独立合约，否则可合并。无论是否拆分，均不再按群设置验证委托，移除 `setGroupDelegate`、`delegateByGroupId` 以及基于群级 delegate 的 `canVerify` 授权；链群行动只认本轮按排名锁定的公共验证者 `memberId`，由其当前 `MemberNFT` 持有人直接完成验证。
- `group-chat` 的委托逻辑保留，但统一命名为 **Group Chat Delegate**，只在 `group-chat` 代码库内生效。它可以被 `GroupChat`、`GroupAdmin`、`GroupMember`、`GroupBanList` 等 Chat 组件使用，用于 Chat 内部管理和运营权限。
- **Group Chat Delegate** 不进入 `core` 的通用身份或权限模型，不被 `action`、未来的 `launch` 或其他业务代码库使用，也不影响 `MemberNFT` 所有权、行动参与或公共验证者资格。
- 旧 `group/src/GroupDelegate.sol` 不作为全局权限合约迁入 `core`；BSC 版在 `group-chat` 内只重写或迁入 Chat 所需的委托逻辑，实现和文档统一使用 **Group Chat Delegate**。
- `LOVE20TokenFactory` 是 `core` 的技术工厂例外：保留用于子币部署拆分，不创建 `ActionExecutor` 或其他业务扩展实例；旧 `Extension*Factory`、群行动工厂和 LP 扩展工厂仍不迁移，外部 DEX Factory 只保留接口调用。
- 旧 `extension-lp` 的 V2 LP 业务迁移到 `action`，作为 LP 行动执行合约按 BSC 版 `ActionTarget`、`MemberNFT`、Proposal 激励和 PancakeSwap 兼容接口重写；V1 LP 实现及 V1/V2 旧工厂部署方式均不迁移。
- `core` 对 PancakeSwap 只依赖外部 `Factory`、`Pair`、`Router` 接口。接入门槛不是仅检查 ABI 编译通过：必须在目标链和 Anvil 夹具中逐项核对 `getPair/createPair`、Pair 的 `token0/token1/getReserves/totalSupply/mint/burn/swap` 返回值与状态更新、Router 的 `getAmountsOut/swapExactTokensForTokens` 路径和 `amountOutMin` 语义、手续费口径以及失败回滚行为，并证明 `Stake` 的功能和数值结果正确；若差异影响这些结果，才不得直接接入 `Stake`，改为适配层或停止集成。
- 已知差异必须显式处理：PancakeSwap fork 的 `swap` 手续费常量可能与 Uniswap V2 不同（例如 `1000/2` 对比 `1000/3`）。因此“接口一致”不是充分条件，也不要求无关内部代码完全相同；必须证明 `Stake` 的实际结算、兑换和 LP 数值结果正确。若差异不影响结果，可直接接入并记录目标版本；若影响结果，必须按实际语义改写适配层或停止集成，不能硬编码 Uniswap V2 费率。
- 旧 `group` 仓库只按合约级迁移已部署且仍需要的 `LOVE20Group`：并入 `core` 后重命名为 `LOVE20Member`（`MemberNFT`），名称唯一性语义保留，最大长度改为 32 个 UTF-8 字节。`GroupDefaults` 只是地址到默认 NFT 的便利映射，BSC 版不迁移、不部署；不新增独立的 `group` 代码库。`GroupDelegate` 不进入 `core`，Chat 所需的最小委托逻辑只在 `group-chat` 内实现。
- 链群业务中的 `groupId` 是 `MemberNFT` 的业务标识，不是第二套 `GroupNFT` 身份。`action` 和 `group-chat` 均依赖 `core` 的 Member 接口。
- 当前 `group-chat` 使用一个 `GroupChat` 合约按 `groupId` 管理多个群，没有按群部署独立合约的 `GroupChatFactory`；除非未来改变为“一群一合约”，否则不新增该工厂。
