# TokenGovManager · 状态变量变更审查

> `group-chat/src/managers/TokenGovManager.sol`，32 行，基线 `group-chat@e982df8`。
> 本合约没有自有状态变量；它是 `TokenScopeManagerBase` 的 `tg` 类型实例，只覆盖类型码、激活入口与资格谓词。
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

本合约**没有新增** storage 变量；所有写入都发生在基类 `_activateToken`。

## 2. 逐变量变更逻辑

### 2.1 本合约新增写入：无

`TokenGovManager` 没有自己的状态赋值、`push`、`delete` 或计数器。`activate(address)`（`:25-27`）是纯转发：

```solidity
function activate(address tokenAddress) external returns (uint256 groupId) {
    return _activateToken(tokenAddress);
}
```

`_activateToken` 的完整写入顺序见 `07-token-scope-manager-base.md` §2.1：

```text
_checkLOVE20Token -> _checkNotManaged -> 名称计算 -> _mintManagedGroup
  -> _tokenAddressByGroupId[groupId] = tokenAddress
  -> _groupIdByTokenAddress[tokenAddress] = groupId
  -> _tokens.push(tokenAddress)
  -> GroupChat.activateChat(groupId, ...)
  -> TokenGroupActivated
```

`_typeCode()`（`:21-23`）返回 `"tg"`，只影响名称 stem 与 `TYPE_CODE()` 查询，不写 storage。

### 2.2 资格谓词

`isSenderAllowed(groupId, senderId)`（`:29-31`）返回 `voteWeight(groupId, senderId) != 0`：

- `voteWeight` 来自 `TokenScopeManagerBase:56-58`，读 `_tokenAddressByGroupId[groupId]`；未托管返回 0；
- 已托管时调 `IStake.validGovVotes(tokenAddress, currentPhase(), voterId)`；
- 只读，不缓存结果、不惰性写入。

## 3. 写入顺序与不可分割性

本合约没有新增写入；继承路径的写入顺序、外部调用与回滚边界完全由 `TokenScopeManagerBase` 决定。`activate` 没有 `nonReentrant`，但外部状态变更调用只到受信 MemberNFT/LOVE20/GroupChat，且映射写入在 mint 之后、activateChat 之前，失败整笔回滚。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `TGM-01` | Info | 资格只看 `validGovVotes != 0`，不看持币/行动参与；这是“代币治理群”的定义，不是缺项 | E1 |
| `TGM-02` | Info | 本合约无自有状态；托管状态与 `TokenMainManager` 等实例互不共享，同一 token 可在不同 Manager 各建一个群 | E1 |

逐条说明：

- **`TGM-01`**：`isSenderAllowed` 只调用 `voteWeight`；`voteWeight` 使用 `Stake.validGovVotes(token, currentPhase(), voterId)`。持币但不质押、或参与行动但没有治理票的成员不满足资格。规格 `05-chat-types.md` 的“代币治理”行与此一致。
- **`TGM-02`**：所有 storage 来自 `TokenScopeManagerBase`；每个 Manager 实例独立。`tg` 群与 `tm` 群可以指向同一 token，但 groupId、映射和 GroupChat 配置互不影响。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 激活者是否获得群管理权 | 不获得；Manager 持有群 NFT，`activate` 只是付款入口，`testT101` / `testT102` 覆盖 |
| `voteWeight` 为 0 是否等于“不是成员” | 是资格谓词为 false，不是成员名单状态；群成员名单在 `GroupMember`，两者独立 |
| 同一 token 重复激活 | 同一 Manager 内回 `AlreadyManaged`；不同 Manager 允许，见 `TSM-01` |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| TG1 | 本合约不新增 storage | ✅ | 文件内无状态变量声明 |
| TG2 | `TYPE_CODE()` 恒为 `"tg"` | ✅ | `:21-23` 常量返回 |
| TG3 | `isSenderAllowed` 与 `voteWeight != 0` 严格等价 | ✅ | `:29-31` 直接返回比较结果 |
| TG4 | 继承的三本托管状态满足 `07-token-scope-manager-base.md` TS1–TS4 | ✅ | 由基类唯一写入点保证 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 本合约无独立状态 | 无需额外状态测试；激活/资格由 `TypedManagers.t.sol` 的 `testT111` 覆盖 |
| 跨轮票权变化 | 由 Stake/Vote 的轮次语义覆盖，不在本合约 |

### 4.5 结论

未发现 Critical / High / Medium。本合约是纯类型化外观：没有自有状态，`activate` 转发到 `_activateToken`，`isSenderAllowed` 只读 Stake 当前轮有效治理票。2 条 Info 均为资格定义与实例隔离说明。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `TGM-01` | 登记：`tg` 只读有效治理票（既有文本已覆盖） | `05-chat-types.md` 类型表 |
| `TGM-02` | 登记：实例之间不共享托管状态 | `06-manager.md`「四类 Manager」 |
