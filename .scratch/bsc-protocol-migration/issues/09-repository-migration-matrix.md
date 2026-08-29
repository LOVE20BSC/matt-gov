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
