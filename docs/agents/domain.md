# Domain docs

正式领域术语写入 [LOVE20BSC 术语表](https://github.com/LOVE20BSC/docs/blob/main/GLOSSARY.md)（本地 `../docs/GLOSSARY.md`）。跨仓库关系查根目录 `CONTEXT.md`。需要解释难以逆转的架构取舍时，写入 `docs/adr/`。

## 探索前

先读取相关的 `CONTEXT.md` 和 `docs/adr/`。文件不存在时静默继续，不为缺失文档提前搭建空目录。

## 术语规则

- 使用正式术语表确认的叫法，尚未收录的术语查 `CONTEXT.md`。
- 发现用户用词与术语表冲突时，先指出冲突并确认含义。
- 发现代码事实与领域描述不一致时，列出证据，不默默选择一方。
- `CONTEXT.md` 只保存领域词汇和关系，不保存实现细节、临时规格或任务清单。
