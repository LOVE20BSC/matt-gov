# BSC 规格文档说明

本目录包含 BSC 版协议的规格文档。

## 文档结构

每个代码库有两个文档：

1. **CHANGES-{name}.md**：迁移变更清单
   - 列出相对于旧协议的所有变更
   - 保留/修改/新增/删除矩阵
   - 引用旧代码位置，避免重复描述

2. **{name}-new.md**：精简规格
   - 只描述新的和变化的部分
   - 保留的逻辑直接引用旧代码位置
   - 专注于接口、状态模型、不变量

## 迁移状态

| 代码库 | 变更清单 | 精简规格 | 旧规格（待替换） |
|--------|----------|----------|------------------|
| core | CHANGES-core.md | core-new.md | core.md |
| action | CHANGES-action.md | action-new.md | action.md |
| group-chat | CHANGES-group-chat.md | group-chat-new.md | group-chat.md |

## 使用建议

**首次了解迁移**：
1. 先读 `CHANGES-{name}.md` 了解变更全貌
2. 再读 `{name}-new.md` 了解新设计细节

**实现时查阅**：
- 查看 `CHANGES-{name}.md` 的"实现检查清单"
- 对照 `{name}-new.md` 的接口和状态模型
- 保留逻辑直接参考引用的旧代码位置

**验收时核对**：
- 使用 `CHANGES-{name}.md` 的"验收边界"
- 对照 `{name}-new.md` 第 9/10 节的验收场景

## 文档对比

### Core
- 旧规格：465 行（包含大量重复的旧逻辑描述）
- 变更清单：265 行（清晰列出所有变更）
- 新规格：443 行（专注于新的和变化的）

### Action
- 旧规格：390 行
- 变更清单：285 行
- 新规格：340 行

### Group Chat
- 旧规格：276 行
- 变更清单：216 行
- 新规格：394 行

## 下一步

待代码库创建后：
1. 将 `{name}-new.md` 复制到 `{repo}/SPEC.md`
2. 在本仓库将 `{name}-new.md` 重命名为 `{name}-new.md.migrated`
3. 添加迁移记录：目标提交、迁移日期
