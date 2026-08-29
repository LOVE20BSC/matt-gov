# Matt 文档与组织验收标准

Type: grilling
Status: resolved
Blocked by: 09

## Question

定义每个 LOVE20BSC 仓库必须具备的 README、Agent 规则、CONTEXT、ADR、Issue tracker 和测试说明；组织级仓库清单/依赖/发布状态放在哪里；如何验证新人能启动和测试、AI 能定位核心模块、文档与代码同步、没有旧组织遗留，以及用一个真实小任务验证协作闭环。

## Comments

用户确认各业务仓库采用条件式最低文档标准：`README.md`、`AGENTS.md` 必须存在；只有存在独立领域术语时才维护 `CONTEXT.md`；只有不可逆架构取舍才创建 `docs/adr/` 中的 ADR；只有需要跨任务协作或 Wayfinder 时才启用 `.scratch` tracker；测试启动和验证命令直接写入 `README.md`，不重复建立测试说明文档。

用户确认组织级仓库清单、依赖关系和发布状态统一维护在 `matt-gov/docs/repositories.md`；各业务仓库只维护自己的 `README.md`，Wayfinder 地图只记录决策，不承担长期状态清单。

用户确认跨仓库验收标准统一维护在 `matt-gov/docs/acceptance.md`；各业务仓库只在自己的 `README.md` 保留启动和测试命令，避免重复维护。

用户修正：协作闭环不把 Claude 或其他外部 reviewer 设为前置条件；由当前负责 agent 完成第二遍自审，外部 review 仅作为可选协作。

## Answer

LOVE20BSC 各业务仓库采用条件式最低文档标准：

- `README.md`、`AGENTS.md` 必须存在；README 提供启动、测试和核心入口。
- 只有存在独立领域术语时才维护 `CONTEXT.md`。
- 只有不可逆架构取舍才创建 `docs/adr/` 中的 ADR。
- 只有需要跨任务协作或 Wayfinder 时才启用 `.scratch` tracker。

组织级长期状态统一维护在 `docs/repositories.md`，记录仓库边界、依赖和发布状态；Wayfinder 地图只记录决策。跨仓库验收标准统一维护在 `docs/acceptance.md`，各业务仓库不重复建立验收文档。

验收至少覆盖：按 README 在干净工作区启动、从 README/`AGENTS.md`/`CONTEXT.md` 定位模块、使用 `love20-anvil` 完成最小集成路径、确认地址/ABI/网络配置和 `interface-test` 到 `interface` 的发布边界、检查已删除组件无旧组织遗留，并保存命令、提交、日志或截图等证据。提交前由负责 agent 做第二遍自审，外部 reviewer 不是通过条件。

迁移完成后，用首个 `core` 的真实低风险小任务验证协作闭环：从文档定位、实现和 focused test，到 agent 自审、Anvil smoke 和验收证据记录；不另造演示项目。
