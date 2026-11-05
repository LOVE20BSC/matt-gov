# TokenMainManager · 状态变量变更审查

> `group-chat/src/managers/TokenMainManager.sol`，50 行，基线 `group-chat@e982df8`。
> 本合约没有自有状态变量；它是 `TokenScopeManagerBase` 的 `tm` 类型实例，资格由“持币 / 治理票 / 当前行动参与”三选一组成。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 来源 | 语义 |
| --- | --- | --- | --- |
| 1 | `GROUP_CHAT_ADDRESS` / `GROUP_ADDRESS` / `MAX_NAME_LENGTH` | `ManagerBase` | 托管群依赖与名称上限 |
| 2 | `BAN_SOURCE_ADDRESS` / `BEFORE_POST_PLUGIN_ADDRESS` / `AFTER_POST_PLUGIN_ADDRESS` | `ManagerBase` | 托管群固定槽位 |
| 3 | `ACTION_TARGET_ADDRESS` / `VOTE_ADDRESS` | `ManagerBase` | ActionTarget / Vote |
| 4 | `_mintNonce` | `ManagerBase` | 名称重试计数 |
| 5 | `STAKE_ADDRESS` / `LAUNCH_ADDRESS` / `PHASE_ADDRESS` | `TokenManagerBase` | Stake / Launch / Phase |
| 6 | `_tokenAddressByGroupId` / `_groupIdByTokenAddress` / `_tokens` | `TokenScopeManagerBase` | 代币托管双向映射与列表 |

本合约**没有新增** storage；所有写入都发生在基类 `_activateToken`。

## 2. 逐变量变更逻辑

### 2.1 本合约新增写入：无

`activate(address)`（`:28-30`）转发到 `_activateToken`；`_typeCode()`（`:24-26`）返回 `"tm"`。写入顺序、守卫与回滚边界见 `07-token-scope-manager-base.md` §2.1。

### 2.2 资格谓词

`isSenderAllowed(groupId, senderId)`（`:32-39`）：

```solidity
address tokenAddress = _tokenAddressByGroupId[groupId];
return tokenAddress != address(0)
    && (
        _hasTokenBalance(tokenAddress, senderId) || _voteWeight(tokenAddress, senderId) != 0
            || _hasTokenActionParticipation(tokenAddress, senderId)
    );
```

| 分支 | 位置 | 读取 | 语义 |
| --- | --- | --- | --- |
| 持币 | `_hasTokenBalance:41-43` | `IERC20(tokenAddress).balanceOf(MemberOwner.ownerOrZero(GROUP_ADDRESS, memberId)) > 0` | 任一最小单位即满足 |
| 治理票 | `_voteWeight:56-58`（基类） | `Stake.validGovVotes(token, currentPhase(), memberId)` | 当前轮有效治理票 |
| 行动参与 | `_hasTokenActionParticipation:45-49` | `ActionTarget.actionIdsByMemberId(token, memberId, 0, 1, false).total` | 当前参与该社区至少一个行动 |

三个分支都是 view；没有缓存、没有惰性写入。`tokenAddress == 0` 时直接 false，不调用外部。

### 2.3 持币分支的地址解析

`_hasTokenBalance` 用 `MemberOwner.ownerOrZero(GROUP_ADDRESS, memberId)` 把 memberId 解析为当前 NFT 持有人，再读 ERC20 余额。若 memberId 不存在，`ownerOrZero` 返回 `address(0)`，`balanceOf(0)` 按标准 ERC20 返回 0；不会把“不存在”误判为有资格。若 token 的 `balanceOf(0)` 非标准 revert，异常会冒泡到 GroupChat 的 source try/catch，最终表现为 `ScopeSourceFailed`（除非出现 `GCH-03` 的解码边界）。

### 2.4 行动参与分支

`ActionTarget.actionIdsByMemberId(token, memberId, 0, 1, false)` 只取第一页（offset 0, limit 1），用返回的 `total` 判断“是否至少参与一个行动”。它不关心 actionId 是什么；只要该 token 下存在成员参与记录即满足，符合规格“当前参与该社区行动”。

## 3. 写入顺序与不可分割性

本合约没有新增写入；继承路径的写入顺序与回滚边界由 `TokenScopeManagerBase` 决定。资格查询不写状态。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `TMM-01` | Info | 持币判断是“任一最小单位”，不是“大于 1 个代币”；这是 2026-10-19 的明确决策，不是精度问题 | E1 |
| `TMM-02` | Info | 持币/行动参与分支读取的是查询时状态，不冻结在激活时；成员买卖 token、退出行动会立即改变资格 | E1 |
| `TMM-03` | Info | `_hasTokenActionParticipation` 只取 `limit=1` 的第一页并用 total 判断，不枚举全部行动；语义是“存在参与”而非“参与特定行动” | E1 |

逐条说明：

- **`TMM-01`**：`_hasTokenBalance` 是 `balanceOf(...) > 0`；规格 `05-chat-types.md` 明确“余额 > 0（任一最小单位）”，CHANGES 也记录了旧实现严格大于 1 个最小单位的修正。
- **`TMM-02`**：`isSenderAllowed` 是实时谓词：token 余额、治理票、行动参与都按当前状态读取。GroupChat 每次发言重新调用 source，不做成员资格快照；这是“资格”而非“名单”的设计。
- **`TMM-03`**：`actionIdsByMemberId` 的 `limit=1` 只用于取 `total`；如果实现返回的 `total` 正确，是否枚举不影响结果。该调用不写状态。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 持币为 0 但治理票 > 0 是否可发言 | 可以；三个分支是“或” |
| 参与行动但已退出（forceClearJoinState）是否仍有资格 | 若 `actionIdsByMemberId` 不再返回该行动，则分支 false；其他分支仍可独立成立 |
| memberId 不存在是否会被 `balanceOf(0)` 误判 | 标准 ERC20 返回 0；不会 true |
| 同一 token 在不同 Manager 的资格是否共享 | 不共享；各自读同一 Core 状态，但群与映射独立 |
| 激活者是否获得管理权 | 不获得；Manager 持有 NFT |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| TM1 | 本合约不新增 storage | ✅ | 文件内无状态变量声明 |
| TM2 | `TYPE_CODE()` 恒为 `"tm"` | ✅ | `:24-26` |
| TM3 | 未托管 group 的 `isSenderAllowed` 恒 false | ✅ | `tokenAddress == 0` 短路 |
| TM4 | 资格三分支均为实时 view，不写状态 | ✅ | 三个 helper 只读外部 view |
| TM5 | 继承的三本托管状态满足 `07-token-scope-manager-base.md` TS1–TS4 | ✅ | 基类唯一写入点 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 三分支组合 | `testT110` 覆盖存储/资格组合；未穷举三分支同时 true/false 的所有组合（逻辑是短路或，风险低） |
| 非标准 ERC20 的 `balanceOf(0)` | 依赖 Core token 标准实现；未做对抗测试 |

### 4.5 结论

未发现 Critical / High / Medium。本合约无自有状态；资格三分支全部是实时 view，未托管 key 安全短路。3 条 Info 分别为持币阈值、实时资格与行动参与查询语义。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `TMM-01` | 登记：>0 最小单位（既有文本已覆盖） | `05-chat-types.md`「资格数据」 |
| `TMM-02` | 登记：实时状态，不使用快照 | `05-chat-types.md`「资格数据」 |
| `TMM-03` | 登记：行动参与只取 `limit = 1` 第一页并以 `total` 判断 | `05-chat-types.md`「资格数据」 |
