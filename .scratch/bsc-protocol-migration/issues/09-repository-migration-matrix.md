# 仓库迁移矩阵与依赖边界

Type: grilling
Status: claimed
Blocked by:

## Question

形成 LOVE20TKM 每个仓库到 LOVE20BSC 的最终矩阵：保留、合并、删除、归档或新建；确定 `core` 合并 Member 身份基础设施后的目录和部署边界，`extension`/`extension-group`/`group-chat`/`periphery`/`script`/`docs`/`chat`/`batch-transfer`/`love20-anvil` 的目标仓库、依赖方向、命名和迁移顺序；确认旧组织只读/归档时机及旧 URL、CI、密钥、webhook 清理标准。

## Comments

用户确认迁移范围规则：只迁移 `LOVE20TKM` 中已经部署到 `thinkium70001_public` 网络的合约代码；未在该网络部署的合约代码不纳入本次 LOVE20BSC 迁移。
