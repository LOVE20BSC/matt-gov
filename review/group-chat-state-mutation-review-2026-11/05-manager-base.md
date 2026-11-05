# ManagerBase · 状态变量变更审查

> `group-chat/src/managers/ManagerBase.sol`，185 行，基线 `group-chat@e982df8`。
> 这是四个 typed Manager 的公共基类；唯一可变状态是名称随机数 `_mintNonce`，其余全是 immutable。
> 证据分级：E3 测试 / E2 算术 / E1 静态。

## 1. 状态布局

| # | 变量 | 类型 | 语义 | 写入点 |
| --- | --- | --- | --- | --- |
| 1 | `GROUP_CHAT_ADDRESS` | `address immutable` | GroupChat 地址 | 构造 `:44` |
| 2 | `GROUP_ADDRESS` | `address immutable` | MemberNFT 地址，从 GroupChat 派生 | 构造 `:42,45` |
| 3 | `MAX_NAME_LENGTH` | `uint256 immutable` | MemberNFT 名称上限 | 构造 `:46` |
| 4 | `BAN_SOURCE_ADDRESS` | `address immutable` | 托管群固定 banSource | 构造 `:47` |
| 5 | `BEFORE_POST_PLUGIN_ADDRESS` | `address immutable` | 托管群固定 before 插件 | 构造 `:48` |
| 6 | `AFTER_POST_PLUGIN_ADDRESS` | `address immutable` | 托管群固定 after 插件 | 构造 `:49` |
| 7 | `ACTION_TARGET_ADDRESS` | `address immutable` | ActionTarget 地址 | 构造 `:50` |
| 8 | `VOTE_ADDRESS` | `address immutable` | Vote 地址，从 ActionTarget 派生 | 构造 `:43,51` |
| 9 | `_mintNonce` | `uint256` | 命名重试计数，参与随机 hex 生成 | `_nextGroupName:134`（`++`） |

常量 `TEST_PREFIX` / `HEX_SYMBOLS` / 三个名称布局常量只在编译期存在。

## 2. 逐变量变更逻辑

### 2.1 `_mintNonce`

唯一写入点 `_nextGroupName`（`:123-141`）：

```solidity
for (uint256 i = 0; i < 8; i++) {
    string memory randomHex = _randomHex(randomHexLength, _mintNonce);
    string memory groupName = _canonicalizeGroupName(
        string(abi.encodePacked(groupNameStem, "_", randomHex)), requiresTestPrefix
    );
    unchecked { _mintNonce++; }
    if (!IMemberNFT(GROUP_ADDRESS).isNameUsed(groupName)) {
        return groupName;
    }
}
revert ManagerGroupNameUnavailable();
```

| 顺序 | 位置 | 说明 |
| --- | --- | --- |
| 1 | `:129` | 用当前 nonce 生成随机 hex |
| 2 | `:130-132` | 拼 `stem_hex`，按 Test 前缀规则规范化 |
| 3 | `:133-135` | nonce 自增（`unchecked`；实际不可能溢出） |
| 4 | `:136-138` | `isNameUsed` 为 false 则返回；这是 view 外部调用（STATICCALL） |
| 5 | `:140` | 8 次仍冲突回 `ManagerGroupNameUnavailable` |

- nonce 在一次激活内最多前进 8；若最终 revert，整笔交易回滚，nonce 回到进入前的值。
- nonce 不区分调用者；不同调用者通过 `_randomHex` 里的 `msg.sender` 参与哈希，仍然得到不同名称。
- nonce 没有 getter，也不影响除命名外的任何状态。

### 2.2 immutables

全部只在构造期写入，没有 setter、没有治理入口：

- `GROUP_CHAT_ADDRESS` / `GROUP_ADDRESS` / `ACTION_TARGET_ADDRESS` 是托管群的身份与依赖绑定；
- `MAX_NAME_LENGTH` 在构造时从 MemberNFT 读取，之后不跟随 MemberNFT 变化（MemberNFT 的该字段本身也是 immutable）；
- `BAN_SOURCE_ADDRESS` / `BEFORE_POST_PLUGIN_ADDRESS` / `AFTER_POST_PLUGIN_ADDRESS` 决定托管群的固定槽位；Manager 不暴露重配入口（`testT102`）。

## 3. 状态写入与外部调用的相对顺序

### 3.1 `_mintManagedGroup`（`:69-89`）

```text
_nextGroupName（写 _mintNonce，调用 isNameUsed view）
  -> calculateMintCost（view）
  -> safeTransferFrom(msg.sender -> manager)（LOVE20 状态变更）
  -> forceApprove(GROUP_ADDRESS, cost)
  -> memberNFT.mint(groupName)（MemberNFT 状态变更 + _safeMint 回调）
  -> 校验 actualMintCost == expectedMintCost
```

- `_mintNonce` 在外部状态变更调用之前写入；但 `isNameUsed` 是 view，`safeTransferFrom` 只作用于 Core LOVE20 token，`memberNFT.mint` 的 ERC721 回调只到本合约的 `onERC721Received`（view，且限制 `msg.sender == GROUP_ADDRESS && from == 0`）。在受信依赖下没有状态重入路径。
- 任一步失败（报价变化、付款/授权失败、mint 失败、费用不一致）整笔回滚，包括 `_mintNonce` 与 token 转账。
- 若 `expectedMintCost == 0`，不转账、不授权；mint 的 `actualMintCost` 必须也为 0。

### 3.2 `_activateManagedGroup`（`:91-95`）

在子类写完业务映射之后调用 `GroupChat.activateChat`。GroupChat 的 `activateChat` 是 `nonReentrant`，且只调用 MemberNFT/GroupAdmin 的 view 与 `code.length` 检查，不会回调 Manager 的写入口。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 一句话 | 证据 |
| --- | --- | --- | --- |
| `MGB-01` | Info | 名称生成是确定性的（chainid + manager + msg.sender + block.number + nonce），可被 mempool 观察并定向抢占；8 次重试只处理“已存在名称”，不处理“本笔提交后名称被抢” | E1 |
| `MGB-02` | Info | 激活无访问控制，首个调用者付款并决定群名/激活时机，但 Manager 持有 NFT、调用者不获得任何管理权 | E1 |
| `MGB-03` | Info | `_managedGroupNameStem` 的随机长度计算依赖部署期不变量 `MAX_NAME_LENGTH ≥ typeCode + 9`；合约本身不做下界检查，误配会在下溢处回滚 | E1 |
| `MGB-04` | Info | `_mintNonce` 是无事件、无 getter 的内部计数器；只影响命名，不影响群身份或权限 | E1 |

逐条说明：

- **`MGB-01`**：`_randomHex` 的熵来自公开字段，攻击者能在交易打包前算出目标名称并抢先 mint。Manager 的名称循环只在 `isNameUsed` 当前为 false 时返回；如果抢注发生在本笔之前，`memberNFT.mint` 会在 `NameAlreadyExists` 处回滚，Manager 不会自动换名重试。规格 `06-manager.md` 已把“定向抢占与后缀长度无关，占满 4 hex 空间需 65,536 次 mint”列为已知取舍；本条只记录状态/重试边界，不重复定性。
- **`MGB-02`**：`activate` 无 `onlyOwner` 或白名单；首个调用者支付铸造费，Manager 铸造并持有群 NFT，随后激活 GroupChat。付款者不获得 owner/admin 角色（`testT101` / `testT102`）。这是规格明确的模式。
- **`MGB-03`**：`_managedGroupNameStem` 在 payload 放不下时计算 `MAX_NAME_LENGTH - typeCode.length - 1 - (testPrefix ? 4 : 0)`。部署脚本按“最长类型码 2 字节 + 9”预检 `MAX_NAME_LENGTH ≥ 11`；若绕过脚本部署了更小的值，这里会下溢回滚。合约侧没有自己的下界断言。
- **`MGB-04`**：`_mintNonce` 在 `_nextGroupName` 内自增，失败回滚；没有外部读取。名称是展示标签，不是身份来源（`06-manager.md`）。

### 4.2 判定为“不是缺陷”的疑点

| 疑点 | 结论 |
| --- | --- |
| `_mintNonce` 在 `isNameUsed` 之前自增，是否会产生“用了 nonce 但名称未用”的不一致 | 不返回的名称对应一次失败尝试；成功返回的名称确实使用了自增前的 nonce；整笔失败则回滚 nonce |
| Manager 收到普通 `safeTransferFrom` 的 NFT 是否会被误认为托管群 | `onERC721Received` 要求 `msg.sender == GROUP_ADDRESS` 且 `from == 0`，普通安全转入直接回 `UnexpectedManagerERC721Received` |
| Manager 是否能把群 NFT 转出 | 没有转出/approve/通用调用入口；`onERC721Received` 也不接收二次转入 |
| 付款后 mint 失败是否会让用户损失 | 不会；`safeTransferFrom`、`forceApprove`、`mint` 在同一笔交易，任一步失败全部回滚 |
| 实际费用与报价不一致是否可能吞掉差额 | 不会；`ManagerMintCostChanged` 在 mint 之后检查，不一致整笔回滚 |

### 4.3 不变式

| # | 不变式 | 是否成立 | 依据 |
| --- | --- | --- | --- |
| N1 | 每个 Manager 实例的 immutables 构造后不变 | ✅ | 全部 `immutable`，无 setter |
| N2 | `_mintNonce` 单调递增，除非整笔回滚 | ✅ | `:134` 唯一写入 |
| N3 | 一次 `_mintManagedGroup` 要么完成付款/mint/费用校验，要么全部回滚 | ✅ | 同一笔交易，无 try/catch |
| N4 | Manager 只在 `from == 0` 且来源为 MemberNFT 时接受 ERC721 | ✅ | `onERC721Received:58-67` |
| N5 | 托管群槽位在 Manager 生命周期内固定 | ✅ | 三个 immutable + 无配置转发入口 |

### 4.4 覆盖缺口

| 缺口 | 说明 |
| --- | --- |
| 名称被抢后的重试 | 测试覆盖 8 次冲突，不覆盖“提交后、打包前被抢注”的实际 mempool 场景 |
| `MAX_NAME_LENGTH` 小于下界 | 部署脚本预检覆盖，合约侧无测试（因为正常部署不会构造出来） |
| Core token / MemberNFT 恶意实现 | 信任模型按部署期绑定，未做对抗性依赖测试 |

### 4.5 结论

未发现 Critical / High / Medium。唯一可变状态 `_mintNonce` 只影响命名，写入与失败回滚边界清楚；所有资金/NFT/映射写入都在同一笔交易内完成，外部状态变更调用只指向受信 Core 合约。4 条 Info 均为命名可预测性、无许可激活、部署不变量与内部计数器语义。

### 4.6 处置与落点（2026-11-05）

| ID | 处置 | 落点 |
| --- | --- | --- |
| `MGB-01` | 登记：打包前抢注不在 8 次重试覆盖范围 | `06-manager.md`「托管群名称」 |
| `MGB-02` | 登记：activate 无许可，付款者不获管理权（既有文本已覆盖） | `06-manager.md`「NFT 付款与持有」 |
| `MGB-03` | 既有覆盖：`MAX_NAME_LENGTH` 下界为部署不变量，规格已写 | `06-manager.md`「NFT 付款与持有」（L15） |
| `MGB-04` | 登记：`_mintNonce` 无 getter/事件，仅影响命名 | `06-manager.md`「托管群名称」 |
