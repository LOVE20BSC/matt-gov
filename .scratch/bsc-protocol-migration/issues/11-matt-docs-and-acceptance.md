# Matt 文档与组织验收标准

Type: grilling
Status: claimed
Blocked by: 09

## Question

定义每个 LOVE20BSC 仓库必须具备的 README、Agent 规则、CONTEXT、ADR、Issue tracker 和测试说明；组织级仓库清单/依赖/发布状态放在哪里；如何验证新人能启动和测试、AI 能定位核心模块、文档与代码同步、没有旧组织遗留，以及用一个真实小任务验证协作闭环。

## Comments

用户确认各业务仓库采用条件式最低文档标准：`README.md`、`AGENTS.md` 必须存在；只有存在独立领域术语时才维护 `CONTEXT.md`；只有不可逆架构取舍才创建 `docs/adr/` 中的 ADR；只有需要跨任务协作或 Wayfinder 时才启用 `.scratch` tracker；测试启动和验证命令直接写入 `README.md`，不重复建立测试说明文档。

用户确认组织级仓库清单、依赖关系和发布状态统一维护在 `matt-gov/docs/repositories.md`；各业务仓库只维护自己的 `README.md`，Wayfinder 地图只记录决策，不承担长期状态清单。

用户确认跨仓库验收标准统一维护在 `matt-gov/docs/acceptance.md`；各业务仓库只在自己的 `README.md` 保留启动和测试命令，避免重复维护。

用户修正：协作闭环不把 Claude 或其他外部 reviewer 设为前置条件；由当前负责 agent 完成第二遍自审，外部 review 仅作为可选协作。
