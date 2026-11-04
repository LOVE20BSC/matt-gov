# 权限卷执行任务（决策版）

> 规格来源：本目录 `README.md` 与 `01`～`10` 各分卷。基线 `action@8478619`（`src/` 相对 `e849e36` 无实质变化，行号未位移）。

## 裁决落地

| 裁决 | 落点（action） | 落点（matt-gov） |
| --- | --- | --- |
| A-1 `AT-01` / `G-01` | `script/deploy/DeployAction.s.sol`：在 `new ActionTarget()` 后断言未初始化 → `init` → 断言已初始化（同批广播，`init` 紧接部署），并回读 5 个绑定；`script/deploy/21_check.sh`：5 个绑定逐项核对（已有，补显式说明） | `specs/action/01-action-target.md`：`init` 段写明「必须部署后第一笔交易」、5 个派生值是鉴权根、信任根在部署脚本（与 core `DEP-01` 同口径，不加 caller 限制） |
| A-2 `AT-02` | 不改合约源码（源码不新增注释） | `specs/action/01-action-target.md` + `07-minting.md`：可结算窗口由 Executor 负责，引用 core `MNT-01` 边界，不重开 |
| A-3 `G-02` / `GAE-01` | （脚本在 matt-gov）`matt-gov/script/check_caller_auth.py`：显式覆盖库文件并新增「库内 `only*` 必须被本文件至少一个入口使用」规则；报改动前后 `violations` | `dev-standards.md` §5.5：实现体进库时 modifier 可定义在库，但模块规格必须列「入口 → 鉴权主体」映射；`05-group-action-executor.md` / `06-service-executor.md` 补映射表 |

## B 类 35 条落点

| 编号 | 落点 |
| --- | --- |
| AT-03 | `01-action-target.md` 创建回调段：Executor 实现来源不在校验范围，风险由提案投票承担 |
| AT-04 | `07-minting.md` 错误表 `UnauthorizedExecutor`：同时表示未绑定与调用者不匹配 |
| AT-05 | `01-action-target.md` + `06-service-executor.md`：`votedActions` 上界 = 本轮有推举资格成员数（每人每轮至多推举一个，core `05-submit.md`） |
| EB-01 | `00-executor-interface.md`：`mintMemberReward` 可收窄 `external`，ABI 不变，登记为可选接口面整理 |
| EB-02 | `07-minting.md` 事件段：`onProposalSubmitted` 无事件为例外并写明理由 |
| LP-01 | `04-lp-executor.md` 错误表：`ActionNotCreated` 限定「仅结算路径」；新增 `join` 未创建行动报 `UnauthorizedExecutor` |
| LP-02 | `04-lp-executor.md` 退出段：`clearJoinState` → `Phase.currentPhase()` 是资金出口的可用性依赖 |
| LP-03 | `04-lp-executor.md` `join` 段：非首次加入不重复校验行动归属，依赖首次 `registerJoinState` |
| LP-04 | `04-lp-executor.md` 配置段：配置写入唯一性由 ActionTarget `AlreadyCreated` 保证 |
| GAE-02 | `05-group-action-executor.md` 部署期不变量：`activationStakeAmountByActionId` 单写，由 ActionTarget `AlreadyCreated` 保证；DeployAction 断言 ActionTarget 实现 |
| GAE-03 | `05-group-action-executor.md`：`submitOriginScores` / `setGroupConfig` 只调只读外部依赖，不设锁（G-05 裁决：只写规格） |
| GAE-04 | `05-group-action-executor.md` 群管理段：激活质押取回权属 `groupId` 当前持有人，随 NFT 转移 |
| GAE-05 | `05-group-action-executor.md` 实现约束：库内 modifier 的 `self` 形参未使用，登记为已接受的形状（不改代码） |
| GAJ-01 | `03-participation.md` 额度接口：`groupId`/`memberId` 是记录定位键，权限主体只有 `providerId` |
| GAJ-02 | `03-participation.md` 错误落点：`join` 在行动未创建时表现为 `GroupNotActive` |
| GAJ-03 | `05-group-action-executor.md` 实现约束：`exit`/`withdraw` 清理被退款切开，但 `nonReentrant` 使顺序不承重，只登记 |
| GAV-01 | `05-group-action-executor.md`：登记当前顺序为「资格 → 参数 → 存在性」，与 §5.2.2 的偏离交错误卷 `E-GAV-02` 重排；本卷不改 `_checkApplicationSubmission` |
| GAV-02 | `05-group-action-executor.md` 库表：`onProposalVoted` 库内不判调用者，调用方必须判 |
| GAV-03 | `05-group-action-executor.md`：同一库并存 `voteRound` / `verifyRound` 两个轮次空间 |
| GAV-04 | `05-group-action-executor.md`：`verifierApplications` 一页最坏 `limit × 1024` 字节 |
| GAM-01 | `05-group-action-executor.md`：创建回调唯一性由 ActionTarget `AlreadyCreated` + 编译器库守卫，DeployAction 断言实现 |
| GAM-02 | `05-group-action-executor.md` 实现约束：同 GAE-05 |
| GAM-03 | `05-group-action-executor.md` 群管理段：同轮不可停用的作用是「质押至少锁定一个加入轮」 |
| GAM-05 | `05-group-action-executor.md` 索引表：`hasActiveGroups` 第二参数实为群主体（`groupId`） |
| GSE-01 | `06-service-executor.md`：协议常量默认不进 ABI；`PRECISION` / `DEFAULT_MAX_RECIPIENTS` 的 `public` 暴露登记为口径偏差 |
| GSE-02 | `06-service-executor.md` 构造函数段：群 owner 判定留在本合约（无对应业务库） |
| GSE-03 | `06-service-executor.md`：`setRecipients` 只调只读外部依赖，不设锁 |
| GSE-04 | `06-service-executor.md` 二次分配：付款对象是结算时 NFT 持有人 |
| GSE-05 | `06-service-executor.md`：`join` 资格判定 O(votedActions)，上界同 AT-05 |
| GSE-06 | `06-service-executor.md` 加入/退出：同轮退出使该轮结算资格失效 |
| GRC-02 | `06-service-executor.md`：`setRecipients` 顺序为存在性先于参数，登记 |
| GRC-03 | `06-service-executor.md`：轮次由调用方保证是当前验证轮，库不校验 |
| GRC-04 | `06-service-executor.md` 库表：`GroupRecipients` 鉴权位置 = 调用方 |
| SUP-01 | `05-group-action-executor.md`：`ownerOrZero` 只吞 `ERC721NonexistentToken`，其余 rethrow |
| SUP-02 | `02-phase-model.md`：`joinRound` 三份同式实现登记为已接受重复 |

## 验证

`forge build --deny warnings`、`forge lint`、`forge test --summary`、`check_caller_auth.py`（前后计数）、`check_errors.py --check`、`check_error_tests.py action`、`test/deploy_scripts_test.py`（部署脚本改动后）。

## 交付

action / matt-gov 各一个提交，只描述最终态，不推送。
