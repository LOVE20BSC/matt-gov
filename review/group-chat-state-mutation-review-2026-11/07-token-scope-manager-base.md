# TokenScopeManagerBase · 状态变量变更审查

> `group-chat/src/managers/TokenScopeManagerBase.sol`，95 行，基线 `group-chat@e982df8`。
> 代币类 Manager 的托管映射：token 与 groupId 双向绑定，另有一份按激活顺序的 token 列表。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `_tokenAddressByGroupId` | `mapping(uint256 => address)` | groupId → 托管 token；0 表示未托管 | `_activateToken:84` |
| 2 | `_groupIdByTokenAddress` | `mapping(address => uint256)` | token → groupId；0 表示未托管 | `_activateToken:86` |
| 3 | `_tokens` | `address[]` | 已托管 token，按激活顺序 | `_activateToken:87`（push） |

三个状态都在同一个函数内写入，没有删除、没有覆盖（重复激活在写入前被拒绝）。

## 2. 逐变量变更逻辑

### 2.1 `_activateToken`（`:75-94`）

| 顺序 | 位置 | 语句 | 守卫 / 说明 |
| --- | --- | --- | --- |
| 1 | `:76` | `_checkLOVE20Token(tokenAddress)` | 有代码且 `Launch.isLOVE20Token` 为 true |
| 2 | `:77` | `_checkNotManaged(_groupIdByTokenAddress[tokenAddress])` | 已托管回 `AlreadyManaged(已有 groupId)` |
| 3 | `:79-81` | 计算 Test 前缀与名称 stem | 读取 LOVE20 symbol / token symbol / MemberNFT 名称上限 |
| 4 | `:82` | `_mintManagedGroup(stem, randomHexLength, requiresTestPrefix)` | 付款、mint、费用校验；详见 `05-manager-base.md` |
| 5 | `:84` | `_tokenAddressByGroupId[groupId] = tokenAddress` | groupId 来自新 mint 的 NFT |
| 6 | `:86` | `_groupIdByTokenAddress[tokenAddress] = groupId` | 与上一步同笔 |
| 7 | `:87` | `_tokens.push(tokenAddress)` | 与上两步同笔 |
| 8 | `:88` | `_activateManagedGroup(groupId)` | 调 GroupChat.activateChat；失败整笔回滚 |
| 9 | `:89-93` | `TokenGroupActivated` 事件 | 在激活之后 |

关键点：

- **双向映射在同一笔交易内写入**，不存在“token 已映射但 groupId 未映射”的对外中间态；任一步失败全部回滚，包括 NFT 铸造与付款。
- `_checkNotManaged` 使用 `_groupIdByTokenAddress[tokenAddress] != 0` 作为“已托管”判据；`groupId` 从 MemberNFT 的 `_nextTokenId` 起从 1 递增，所以 0 可以作为安全的哨兵。
- `_tokens` 与 `_groupIdByTokenAddress` 一一对应；`tokens` 分页时用 `_groupIdByTokenAddress[token]` 回填 groupId，二者不会漂移。
- 同一 token 可以在**不同 Manager 实例/类型**中各自托管一次（例如 TokenMainManager 与 TokenGovManager 各建一个群）；本合约只保证“本实例内一次”，这是规格 `06-manager.md` 的四类 Chat 设计。

### 2.2 查询入口

| 函数 | 位置 | 行为 |
| --- | --- | --- |
| `tokenAddressByGroupId` | `:17-19` | 直接返回映射；未托管返回 0 |
| `groupIdByTokenAddress` | `:21-23` | 直接返回映射；未托管返回 0 |
| `tokens` | `:39-54` | 分页 `_tokens`，用 `_groupIdByTokenAddress` 回填 groupId |
| `voteWeight` / `totalVoteWeight` | `:56-66` | 先读 `_tokenAddressByGroupId`，为 0 返回 0；否则调 Stake |

查询全部只读，不修复、不惰性写入。

## 3. 写入顺序与不可分割性

```text
_checkLOVE20Token
  -> _checkNotManaged
  -> 名称计算
  -> _mintManagedGroup（付款 + mint + 费用校验）
  -> 双向映射 + _tokens.push
  -> GroupChat.activateChat
  -> 事件
```

- 外部状态变更调用发生在映射写入**之前**（mint/付款）和**之后**（activateChat）。mint 是受信 MemberNFT，且 `onERC721Received` 只回调 Manager 的 view；activateChat 是受信 GroupChat，且 `nonReentrant` 不会回调 Manager 的写入口。
- 映射写入与 activateChat 之间没有 try/catch；activateChat 失败会回滚映射、mint 与付款。
- 没有删除入口，所以 `_tokens` 长度只增；重复激活在写入前被拒。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `TSM-01` | Info | “同一 token 只能托管一次”是本 Manager 实例内的约束；不同 Manager 类型/实例可各自为同一 token 建群，这是四类 Chat 的设计，不是重复 | E1 |
| `TSM-02` | Info | 映射写入在 `memberNFT.mint` 之后；受信依赖下无重入，但若部署时把 MemberNFT 指向恶意实现（协议内 MemberNFT 不可升级，正常运行不会替换），mint 回调期间映射尚未写入，可能产生重复托管 | E1 |
| `TSM-03` | Info | `_tokens` 与双向映射没有删除路径；token 托管后永久保留，即使 GroupChat 配置或源后续失效 | E1 |

逐条说明：

- **`TSM-01`**：`_checkNotManaged` 只看本合约的 `_groupIdByTokenAddress`。TokenMainManager、TokenGovManager、TokenActionMainManager、TokenActionGovManager 是四个独立实例，允许同一 token / action 在不同类型下各有一个群。规格明确“同一个 token（token Manager）或 token + actionId（action Manager）只能在同一 Manager 中激活一次”。
- **`TSM-02`**：`_mintManagedGroup` 在映射写入前调用 `memberNFT.mint`。正常路径下 MemberNFT 是 Core 合约，`_safeMint` 的回调只到 Manager 的 `onERC721Received`（view，且校验 `from == 0`），不会重入 `activate`。若部署时把 MemberNFT 指向恶意实现（协议内 MemberNFT 不可升级），mint 回调可以重入 `activate`，此时 `_groupIdByTokenAddress` 仍为 0，可能铸出两个群并让后写覆盖前写；这是依赖信任边界，不是当前实现的正常路径。
- **`TSM-03`**：没有 `removeToken` / 迁移 / 重新绑定入口。token 一旦托管，`_tokenAddressByGroupId` 与 `_groupIdByTokenAddress` 永久存在；GroupChat 的配置也不能由 Manager 重配。规格 `06-manager.md` 的“不转出、不重配、不恢复”一致。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| 双向映射是否会只写一半 | 不会；写入在 `_activateToken` 内连续三行，任一步失败整笔回滚 |
| `_tokens` 是否会包含重复 token | 不会；`_checkNotManaged` 在 push 前拒绝 |
| 同一 token 在不同 Manager 建群是否算状态冲突 | 不算；每个 Manager 有独立映射与独立群 NFT，四类 Chat 设计允许 |
| `tokens` 的 groupId 是否会与 `_tokenAddressByGroupId` 不一致 | 不会；两份映射同笔写入，且无覆盖路径 |
| GroupChat 激活失败是否留下已付款/已 mint 的群 | 不会；activateChat 在映射写入后，失败整笔回滚 |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| TS1 | 对本实例，`_tokenAddressByGroupId[g] = t != 0` ⟺ `_groupIdByTokenAddress[t] = g != 0` | ✅ | 同笔写入，无其他写入/删除 |
| TS2 | `_tokens` 无重复，且每个元素的双向映射都指向自身 | ✅ | `_checkNotManaged` + 同笔 push |
| TS3 | 每个 groupId 都有对应的已 mint MemberNFT，且 GroupChat 已激活 | ✅ | mint 成功后才写映射；activateChat 失败回滚 |
| TS4 | 未托管 token 的 `voteWeight` / `totalVoteWeight` 返回 0 | ✅ | `_tokenAddressByGroupId` 零值分支 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 跨 Manager 类型重复托管 | 由设计允许，测试覆盖四类 Manager 各自激活；未做“同一 token 在四个 Manager 各建群”的组合测试 |
| 恶意 MemberNFT 重入 | 不在信任模型内；未做对抗测试 |
| 删除/迁移 | 合约没有入口，无需覆盖 |

### 4.5 结论

未发现 Critical / High / Medium。三本状态（双向映射 + 列表）在同一函数内成组写入，重复检查在写入前，失败整笔回滚；查询对未托管 key 安全返回 0。3 条 Info 均为“实例内唯一”“依赖信任”“永久保留”的边界说明。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `TSM-01` | 登记：唯一性仅在单实例内，跨 Manager 可各自托管 | `06-manager.md`「四类 Manager」 |
| `TSM-02` | 信任边界说明；已按 MemberNFT 不可升级修正表述 | 本节正文、`06-manager.md`「构造期依赖」 |
| `TSM-03` | 登记：托管无删除/迁移（既有文本已覆盖） | `06-manager.md`「转移与失效」 |
