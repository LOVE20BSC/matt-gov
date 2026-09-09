# Matt Governance 工作规则

- 本仓库只维护 LOVE20BSC 的组织级迁移、协作规范和跨仓库决策；允许存放可直接迁移到目标仓库的纯 Solidity 接口声明，不存放实现、测试或部署脚本。
- `interfaces/` 下的 `.sol` 文件是 ABI 唯一来源；规格正文解释行为并链接接口，不重复维护函数、事件和错误签名。
- 文档、地图、票据、ADR 和讨论结论默认使用中文；合约、函数、接口、仓库、路径、命令和专有名词保留原文。
- 密码、Token 和私钥只能通过弹窗或本地安全输入，不写入仓库或聊天。
- 组织根目录 `LOVE20BSC` 只是工作区；本仓库自身使用 Git 维护。
- 各业务仓库的实现细节和单仓库问题留在对应仓库；这里仅记录跨仓库决策。
- `LOVE20TKM` 在整个迁移期间只读：只能读取源码、提交历史和链上部署证据，不得编辑、格式化、更新依赖、提交、推送或删除其中任何代码库；所有迁移和 BSC 改造只能在 `LOVE20BSC` 新仓库完成。

## Agent skills

### Issue tracker

Issues and specs live under `.scratch/<feature>/` using the local Markdown tracker.
See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default labels: `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. Use root `CONTEXT.md` and `docs/adr/`.
See `docs/agents/domain.md`.
