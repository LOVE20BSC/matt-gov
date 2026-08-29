# 仓库迁移矩阵与依赖边界

Type: grilling
Status: claimed
Blocked by:

## Question

形成 LOVE20TKM 每个仓库到 LOVE20BSC 的最终矩阵：保留、合并、删除、归档或新建；确定 `core` 合并 Member 身份基础设施后的目录和部署边界，`extension`/`extension-group`/`group-chat`/`periphery`/`script`/`docs`/`chat`/`batch-transfer`/`love20-anvil` 的目标仓库、依赖方向、命名和迁移顺序；确认旧组织只读/归档时机及旧 URL、CI、密钥、webhook 清理标准。

## Comments

用户确认迁移范围规则：只迁移 `LOVE20TKM` 中已经部署到 `thinkium70001_public` 网络的合约代码；未在该网络部署的合约代码不纳入本次 LOVE20BSC 迁移。

用户确认：迁移资格以 `thinkium70001_public` 对应地址在链上确实存在合约代码为准；部署参数、脚本或本地 artifact 只能作为辅助证据，不能单独证明已部署。

用户确认：同一仓库按合约级裁剪；只迁移已部署合约及其必要依赖，未部署的实验合约、旧版本和仅测试代码不因同仓库存在而自动迁移。

用户确认：`interface-test`、部署 `script`、`periphery`、`love20-anvil` 和 `docs` 都列入 LOVE20BSC 迁移范围，迁移后按 BSC 新协议统一更新；不再要求这些配套代码逐文件证明直接服务于某个已部署合约。链上部署规则仍只约束旧合约代码的迁移来源。

用户确认：上述配套代码库整体迁移，再按 BSC 新协议清理无关或废弃内容。

用户确认代码库分层：第一层 `core` 独立维护底层治理框架、发射基础设施、`MemberNFT` 和 `LOVE20Phase`；第二层与第三层按业务框架拆分代码库。当前只建设社群行动业务，因此由 `action` 统一维护 `proposalTarget` 的 `LOVE20Action` 框架和常用行动执行合约。子币发射后的分发及配套合约归入独立的 `launch` 代码库。发射资格与 `LOVE20LaunchNFT` 属于 `core`，不放入 `launch`。

用户确认：当前不为第二层和第三层分别建立代码库；`action` 同时维护社群行动框架和常用行动执行合约。未来出现并列业务框架时，再按业务框架拆分新的代码库。

用户确认：旧 `extension`、`extension-group`、`extension-lp` 均归并到 `action`，按新的 `LOVE20Action` 框架和行动执行模型重写，不保留独立的 `extension` 系列代码库。

用户确认：`periphery`、`script`、`interface-test`、`love20-anvil`、`docs` 继续保持独立代码库，不并入 `core` 或 `action`。

用户确认：`group-chat` 保持独立代码库，只依赖新的 `core` 身份接口和部署地址，不并入 `action`。

用户确认：`batch-transfer` 作为相对独立的工具代码库单独迁移，不并入 `core`、`launch` 或 `action`。

用户确认：`interface` 与 `interface-test` 都迁移到新组织，但日常只修改 `interface-test`；验收后手动同步到 `interface` 正式发布，两者不合并。

用户确认：新建独立 `launch` 代码库，维护子币发射后的分发及配套合约；旧 `burn` 不迁移，旧 `core` 的发射资格、`LOVE20LaunchNFT` 和发射流程继续归入新 `core`。

用户确认：`v2-periphery` 不迁移；它没有 `thinkium70001_public` 部署地址，且来源为 Uniswap 官方仓库，继续作为外部依赖。PancakeSwap V2 与 Uniswap V2 的兼容性留到实现 LP/发射相关代码时，以接口、字节码和实际调用验证。

用户确认：旧网络虽已部署，但被 BSC 新协议明确删除或替代的 `SL/ST`、`Verify`、`Random`、旧 `Join` 等合约不迁移；`core` 只保留并重写新的 `Stake`、`Submit`、`Vote`、`Mint`、发射、`MemberNFT` 和 `Phase`。
