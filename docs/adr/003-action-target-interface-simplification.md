# ADR-003: ActionTarget 接口简化设计

## 状态

已接受 (2026-09-22)

## 背景

在 ActionTarget 迁移规格与接口 Review 中，发现原接口设计存在以下问题：

1. **事件字段不匹配**：草稿事件包含 `amount, isExperience, providerMemberId` 字段，但 `join/exit` 函数签名没有这些参数
2. **集合读取重复**：`actionIdsByMemberId` 既提供全量数组，又提供 Count/AtIndex 分页，违反[集合设计原则](../../migration-standards.md#集合读取函数的设计原则)
3. **职责边界模糊**：ActionTarget 定位是"通用加入登记"，但草稿事件字段包含了具体业务细节
4. **命名一致性**：`isAccountJoined` 使用 Account 前缀但参数是 memberId；事件名带 Action 前缀冗余
5. **无界集合未分页**：某轮某 executor 的行动列表、某轮总行动列表由外部创建决定，属无界集合

## 决策

### 1. 简化 join/exit 签名和事件

**采用方案 A**：ActionTarget 只记录加入布尔状态，不传递业务字段

```solidity
// 函数签名保持简洁
function join(address tokenAddress, uint256 actionId, uint256 memberId) external;
function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;

// 事件简化为只包含通用字段
event Joined(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round);
event Exited(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId, uint256 round);
event ForceExited(address indexed tokenAddress, uint256 indexed actionId, 
    uint256 indexed memberId);
```

**理由**：
- 符合"ActionTarget 不保存 Executor 的资产、验证或群归属"的职责定位
- 各 Executor（LpExecutor、GroupActionExecutor）在自己的合约发出包含完整业务字段的同名事件
- 事件分层清晰：ActionTarget 层记录通用加入状态，Executor 层记录业务细节
- 参考旧设计：ExtensionCenter 的 `AddAccount` 事件也只包含通用字段（`round, accountCount`）
- withdraw 不改变加入状态，ActionTarget 不发出 `Withdrawn` 事件

### 2. 采用标准分页设计

采用迁移标准规定的分页签名 `(offset, limit, reverse) → (列表, 总数)`：

```solidity
function actionIdsByMemberId(
    address tokenAddress, 
    uint256 memberId, 
    uint256 offset, 
    uint256 limit, 
    bool reverse
) external view returns (uint256[] memory actionIds, uint256 total);

function actionIdsByExecutor(
    address tokenAddress,
    uint256 round,
    address executor_,
    uint256 offset,
    uint256 limit,
    bool reverse
) external view returns (uint256[] memory actionIds, uint256 total);

function actions(
    address tokenAddress,
    uint256 round,
    uint256 offset,
    uint256 limit,
    bool reverse
) external view returns (uint256[] memory actionIds, address[] memory executors, uint256 total);
```

**理由**：
- 成员行动列表、某轮某 executor 行动列表、某轮总行动列表均为无界集合
- 符合迁移规范："只有有界集合才提供全量读取...由外部输入决定一律按无界处理，只给分页"
- 标准分页签名：越界返回空数组与真实总数、不回滚；`limit` 超剩余按剩余返回；`reverse` 从新到旧；只取总数传 `limit = 0`
- 避免未来规模变大后调用方 gas 耗尽

### 3. 统一命名规范

- `isAccountJoined` → `isJoined`（参数已是 memberId，Account 前缀无意义）
- `ProposalLinked` → `ActionCreated`（Action 层视角是创建行动）
- `ActionJoined/ActionExited` → `Joined/Exited`（接口上下文已明确，去冗余前缀）

## 后果

### 正面影响

1. **职责清晰**：ActionTarget 专注于"是否加入"的布尔状态，不关心金额、体验等业务细节
2. **接口一致**：函数签名与事件字段匹配，不存在"事件有字段但函数没参数"的矛盾
3. **符合规范**：集合读取遵循迁移标准，避免未来维护问题
4. **事件分层**：各层级发出各自关心的事件，聚合点清晰
5. **命名简洁**：去除冗余前缀，提高可读性

### 负面影响

1. **事件监听**：需要监听 ActionTarget 和各 Executor 的事件才能获得完整信息（但这是分层设计的必然结果）
2. **历史兼容**：与草稿接口不同，需要更新下游 Executor 接口（LpExecutor、GroupActionExecutor）

## 相关文档

- [迁移标准：集合读取函数的设计原则](../../migration-standards.md#集合读取函数的设计原则)
- [ActionTarget 规格](../specs/action/01-action-target.md)
- [接口对账：ActionTarget](../../.scratch/interface-diff/action.md#1-iactiontarget-vs-iextensioncenter--iextension)
