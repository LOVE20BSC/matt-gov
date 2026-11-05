# `group-chat/managers/ManagerBase.sol` 错误赋值与发送专项 Review

> 基线：`group-chat@72d7226`（2026-11-03），行号按该提交；`ManagerMintCostChanged` 已按 E-MB-01 方案 A 删除声明与比较（`mint` 返回的实付直接丢弃）。
> 判据：`matt-gov/docs/error-standards.md`；行为口径：`matt-gov/docs/specs/group-chat/06-manager.md`、`07-events-errors.md`。
> 范围：`src/managers/ManagerBase.sol`（185 行）+ `src/interfaces/managers/IManagerBase.sol` 的 `IManagerBaseErrors`。`IManagerBaseErrors` 由 6 个 Manager 合约共享。
> 全局口径：本卷组共 31 条 = Low 3 / Info 28（含已由 api-auth / state 卷关闭的 5 条；口径修正见 README「计数差异说明」）；本文件计 6 条（1 Low / 5 Info）。

## 1. 结论

- 4 个错误声明 / 3 个本站点 + 1 个派生站点；实现零声明，无裸 `require`/`revert`。
- 本站点覆盖：回调拒绝、重复托管、名称空间耗尽；铸造费用一致性移到测试（真实 MemberNFT 路径断言实扣 == `calculateMintCost` 报价）。`TokenNotLOVE20` 为「1 个声明 / 0 个本站点 / 1 个派生站点」。
- 1 条 Low：`ManagerMintCostChanged` 在协议内生产不可达，已按方案 A 删除声明与比较；实付与报价一致由 `testT161` 对真实 MemberNFT 断言，链上不再断言。
- 5 条 Info：回调错误缺 `msg.sender`、名称耗尽无载荷、名称算术下溢为 Panic、MemberNFT 名称/ERC721 错误未登记透传、`AlreadyManaged` 的 0 哨兵依赖未写。

| 指标 | 值 |
| --- | --- |
| 错误声明 | 4 |
| revert 站点（本文件） | 3 |
| 派生站点（TokenManagerBase） | 1 |
| 未声明 revert | 0 |
| 无站点声明 | 0（全仓口径；`TokenNotLOVE20` 为 1 个声明 / 0 个本站点 / 1 个派生站点） |
| Low / Info | 1 / 5 |

## 2. 错误清单

| 错误 | 签名 | selector | 站点 | 判定 |
| --- | --- | --- | --- | --- |
| `AlreadyManaged` | `AlreadyManaged(uint256)` | `0xcd0d3eb5` | 1 | 保留 |
| `ManagerGroupNameUnavailable` | `ManagerGroupNameUnavailable()` | `0x4a6464df` | 1 | 保留 |
| `TokenNotLOVE20` | `TokenNotLOVE20(address)` | `0x518fd31e` | 0 本站点 / 1 派生 | 声明在 `IManagerBaseErrors`，站点在 `TokenManagerBase.sol:36` |
| `UnexpectedManagerERC721Received` | `UnexpectedManagerERC721Received(address,address,uint256)` | `0x4cf3a76b` | 1 | 保留（载荷见 E-MB-02） |
| ~~`ManagerMintCostChanged`~~ | ~~`ManagerMintCostChanged(uint256,uint256)`~~ | ~~`0xeb6a25aa`~~ | 0 | 已删除（E-MB-01 方案 A） |

> `TokenNotLOVE20` 的声明归 `IManagerBaseErrors`，但唯一站点在派生合约 `TokenManagerBase`；本报告只登记声明，明细见 [TokenManagerBase.md](TokenManagerBase.md)。

## 3. 逐错误明细

### 3.1 主表

| # | 错误 | 位置 | 函数 | 判据 | 实参赋值 | 入口传播 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `UnexpectedManagerERC721Received(operator, from, tokenId)` | `:64` | `onERC721Received` | `msg.sender != GROUP_ADDRESS \|\| from != address(0)` | `operator ← 回调入参`；`from ← 回调入参`；`tokenId ← 回调入参` | ERC721 `safeTransferFrom` / `_safeMint` 回调 |
| 2 | `AlreadyManaged(groupId)` | `:97` | `_checkNotManaged` | `managedGroupId != 0` | `groupId ← _groupIdByTokenAddress[tokenAddress]` 或 `_groupIdByActionId[tokenAddress][actionId]` | 四个 Manager 的 `activate` |
| 3 | `ManagerGroupNameUnavailable()` | `:138` | `_nextGroupName` | 8 次尝试全部 `isNameUsed` 为 true（for 循环耗尽） | — | 四个 Manager 的 `activate` |
| 4 | `TokenNotLOVE20(tokenAddress)` | `TokenManagerBase.sol:36` | `_checkLOVE20Token` | `tokenAddress.code.length == 0 \|\| !ILaunch(LAUNCH_ADDRESS).isLOVE20Token(tokenAddress)` | `tokenAddress ← 入参` | `TokenMainManager`、`TokenGovManager` 的创建入口 |

### 3.2 赋值与发送逻辑

#### `_mintManagedGroup` 的费用路径

```text
groupName = _nextGroupName(stem, randomHexLength, requiresTestPrefix)   // 名称唯一性在这里闭合
expected  = memberNFT.calculateMintCost(groupName)
if (expected != 0) {
    love20.safeTransferFrom(msg.sender, address(this), expected)       // 失败 → SafeERC20FailedOperation(love20)
    love20.forceApprove(GROUP_ADDRESS, expected)                       // 失败 → SafeERC20FailedOperation(love20)
}
(groupId, ) = memberNFT.mint(groupName)                                // 失败 → MemberNFT 自身错误；实付丢弃
```

- 方案 A 后不再有 `ManagerMintCostChanged` 声明，也不再比较实付与报价；一致性由 `testT161` 保障。
- 费用依赖 `MAX_SUPPLY - totalSupply`（core `MemberNFT.calculateMintCost`），同一交易内 `mint` 会在转账前重算；`mint` 内部 `_addTestPrefixIfNeeded` 对已带 `Test` 前缀的名称不再改写，Manager 的 `_canonicalizeGroupName` 用的是同一判定（LOVE20 symbol 前 4 字节是否为 `Test`），因此两次计算同源。
- 任一步失败整体回滚：付款、授权、NFT、映射、激活不会半完成（06-manager:18）。
- 该不变量已移到测试：协议内 MemberNFT 不可升级、定价确定性由 `testT161` 覆盖；误配非协议 MemberNFT 属部署期风险，由部署脚本的 MemberNFT 一致性校验（`DeployGroupChat.s.sol:117/:123-125/:131-133/:311`）拦截。

#### `_nextGroupName` 的重试

```text
for (i = 0; i < 8; i++) {
    randomHex = _randomHex(randomHexLength, _mintNonce)
    groupName = _canonicalizeGroupName(stem + "_" + randomHex, requiresTestPrefix)
    _mintNonce++
    if (!memberNFT.isNameUsed(groupName)) return groupName
}
revert ManagerGroupNameUnavailable()
```

- 4 位十六进制后缀的空间为 65,536（06-manager:33）；8 次仍冲突即回 `ManagerGroupNameUnavailable()`。错误无载荷，尝试过的 `groupName`/nonce 区间只能靠链下重放（E-MB-03）。

#### `_checkNotManaged`

- 以 `0` 为“未托管”哨兵，依赖 `groupId >= 1`（core `MemberNFT._nextTokenId = 1`）。若未来 MemberNFT 允许 id 0，重复检测会失效（E-MB-06）；06-manager:7 已写明该前提。

### 3.3 已核对项

- `onERC721Received` 声明为 `external view`：只读 immutables，不写状态；`msg.sender == GROUP_ADDRESS && from == address(0)` 时返回 selector，正好覆盖 `MemberNFT.mint` 的 `_safeMint` 回调。
- 普通安全转入（`from != 0`）被拒绝，非安全 `transferFrom` 仍可强行转入，但不会产生托管映射；06-manager:54 已写明这一边界。
- `_checkNotManaged` 只在同一 Manager 内去重；同一 token 可在不同 Manager 各激活一次，06-manager:7 明确“只能在同一 Manager 中激活一次”。
- 测试：`test/Manager.t.sol` 断言 `UnexpectedManagerERC721Received`；`test/ManagerEdgeErrors.t.sol` 断言 `ManagerGroupNameUnavailable`（`testT160`），并以真实 `MemberNFT` 断言实扣 == `calculateMintCost` 报价（`testT161`）；`test/TypedManagers.t.sol` 断言 `AlreadyManaged`。
- 声明 / 站点闭合：4 个声明全部有站点（含 1 个派生站点），`check_errors.py --check` 0 违规。

## 4. Review 结果

### 4.1 发现

| ID | 级别 | 位置 | 问题 | 依据 | 处置 |
| --- | --- | --- | --- | --- | --- |
| E-MB-01 | Low | `src/managers/ManagerBase.sol:77-88` | `ManagerMintCostChanged` 在协议内不可达：①报价与 `mint` 在同一交易内对同一名称、同一 `MAX_SUPPLY - totalSupply` 重算，`MemberNFT.mint` 的 `_addTestPrefixIfNeeded` 与 Manager 的 `_canonicalizeGroupName` 用同一判定，`actual == expected`；②若 `actual > expected`，`mint` 的 `safeTransferFrom` 会因授权只有 `expected` 先回 `SafeERC20FailedOperation`；③若 `actual < expected`，`mint` 成功后才触发本错误，但这需要 MemberNFT 定价与报价分歧。测试 `testT161` 用 `MockManagerMemberNFT(false, 1)` 强制分歧，不能证明生产可达。 | §8（不保留不可达错误；不可达不变量用 `assert`） | **已按方案 A 落地**：删除 `ManagerMintCostChanged` 声明与 `actual == expected` 比较，`mint` 返回值直接丢弃；`testT161` 改为走真实 `MemberNFT` 路径断言 LOVE20 实扣 == `calculateMintCost` 报价。定为 A 而非 B 的理由：不变量在协议内不可达，误配属部署期风险（部署脚本已校验 MemberNFT 一致性），测试覆盖比链上断言更合适且省字节 |
| E-MB-02 | Info | `src/managers/ManagerBase.sol:58-67` | 拒绝回调的 payload 是 `operator / from / tokenId`，不含真正失败的调用者 `msg.sender`（NFT 合约地址）。对“非协议 NFT 合约发起的安全转入”，三字段无法直接定位来源，只能从交易 trace 反查。 | §4（主体键在前；只允许定长标量） | 已登记：06-manager「payload 不含 msg.sender，实际调用地址可从 tx 读取」；不改 ABI |
| E-MB-03 | Info | `src/managers/ManagerBase.sol:121-139` | `ManagerGroupNameUnavailable()` 无载荷；8 次尝试的 `groupName` 与 `_mintNonce` 区间不可从错误定位，只能链下重放。 | §4（没有行动价值时省略载荷） | 已登记：06-manager「无载荷；nonce 已推进，重试换候选名」 |
| E-MB-04 | Info | `src/managers/ManagerBase.sol:103-119` | `_managedGroupNameStem` 在 `MAX_NAME_LENGTH < bytes(typeCode) + 1 + testPrefix` 时整数下溢，以 Panic 0x11 失败，不是错误目录成员。部署脚本按 `MAX_NAME_LENGTH ≥ 11` 预检，`21_check.sh` 按实际 `TYPE_CODE()` 复核（06-manager:15），生产不可达。 | §8（不可达不变量用 Panic） | 已登记：06-manager「违反时表现为 Panic(0x11)，不映射为自定义错误」 |
| E-MB-05 | Info | `src/managers/ManagerBase.sol:85` | Manager 调 `MemberNFT.mint`，理论上可透传 `NameAlreadyExists` / `NameEmpty` / `NameTooLong` / `NameInvalidCharacters` 与 ERC721 错误；正常路径下名称由 Manager 生成并经 `isNameUsed` 去重，同交易内无插入点，实际不可达。06-manager 未登记这些透传。 | §1（每个模块一张透传来源表） | 已登记：07-events-errors「按模块登记透传面」段 + 06-manager 透传说明 |
| E-MB-06 | Info | `src/managers/ManagerBase.sol:95-99` | `AlreadyManaged` 以 `0` 表示未托管，依赖 `groupId >= 1`。该前提来自 core `MemberNFT._nextTokenId = 1`，group-chat 规格未写。 | §5（隐式不变量应写明） | 已登记：06-manager:7「groupId 从 1 起分配，0 为未托管哨兵」 |

### 4.2 透传错误面

| 来源 | 错误 | 触发入口 | 登记位置 |
| --- | --- | --- | --- |
| `SafeERC20`（LOVE20） | `SafeERC20FailedOperation(address token)` | `_mintManagedGroup` 的 `safeTransferFrom` / `forceApprove` | 07-events-errors:23；06-manager:16 |
| `MemberNFT.mint` | `NameAlreadyExists` / `NameEmpty` / `NameTooLong` / `NameInvalidCharacters`、ERC721 错误 | `_mintManagedGroup` | 07-events-errors:25（按模块透传表；正常路径不可达） |
| `MemberNFT.calculateMintCost` | 幂溢出 Panic（core 配置越界） | `_mintManagedGroup` | 07-events-errors:25（部署门禁闭合） |
| `IERC20Metadata.symbol()` | 无自身错误，token 回滚原样冒泡 | `_tokenNamePayload`、`_love20TokenRequiresTestPrefix` | 07-events-errors:25 |
| `ILaunch.isLOVE20Token` | 无自身错误，core 回滚原样冒泡 | `TokenManagerBase._checkLOVE20Token` | 07-events-errors:25 |
| `GroupChat.activateChat` | `GroupNotExist` / `ChatAlreadyActivated` / `NotGroupOwner` / `SourceNotContract` / `PluginNotContract` | `_activateManagedGroup` | 07-events-errors:25；正常路径不可达（新群由 Manager 持有） |
| `IPhase.currentPhase` | 无（返回 0） | `currentPhase` | 06-manager |

## 5. 证据与复现

```sh
export PATH="$HOME/.foundry/bin:$PATH"
cd group-chat
env -u PYTHONPATH python3 ../matt-gov/script/check_errors.py --check
env -u PYTHONPATH python3 ../matt-gov/script/check_error_tests.py group-chat
forge test --match-path test/Manager.t.sol
forge test --match-path test/ManagerEdgeErrors.t.sol
```

> 扫描口径同 [GroupChat.md](GroupChat.md)；声明行号取 `src/interfaces/managers/IManagerBase.sol`。
