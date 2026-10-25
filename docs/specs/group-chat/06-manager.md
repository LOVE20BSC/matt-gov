# Manager 与群组 Chat

## 四类 Manager

保留 TokenMainManager、TokenGovManager、TokenActionMainManager、TokenActionGovManager；每个 Manager 可以管理多个 Chat，不为每个 Chat 部署新 Manager。四个 Manager 同时实现 `IBanVoteWeightSource`，为托管群提供封禁权重；`GovVotedBanSource` 从群 NFT 的持有者解析权重源，因此托管是治理加权封禁成立的前提（见 [类型与资格](05-chat-types.md)）。

同一个 token（token Manager）或 token + actionId（action Manager）只能在同一 Manager 中激活一次，重复激活回 `AlreadyManaged(groupId)`（`groupId` 为已存在的托管群）。保留 tokenOfGroup/groupIdOfToken、actionOfGroup/groupIdOfAction 及批量、分页查询；行动定位使用已有 `actionOfGroup(groupId)` 返回 token 和 actionId，不另加重复的 getActionId。行动不存在或 actionId 为 0 回 `ActionNotExist(tokenAddress, actionId)`；`RECENT_ROUNDS` 必须 >0，由部署脚本在广播前校验，合约为 0 时该 Manager 的治理资格恒为 false。

Token Manager 与 Action Manager 的接口分别见 [`ITokenScopeManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/ITokenScopeManagerBase.sol) 和 [`ITokenActionScopeManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/ITokenActionScopeManagerBase.sol)，两者共享的槽位 getter、`TYPE_CODE()` 与错误在 [`IManagerBase.sol`](https://github.com/LOVE20BSC/group-chat/blob/main/src/interfaces/managers/IManagerBase.sol)。两类接口不合并，避免单个 Manager 实现另一类 Manager 的无关方法。

## NFT 付款与持有

保留旧 BaseManager 的激活交易：

1. 校验 LOVE20 token、存在的 Proposal 及未重复激活，生成唯一名称；名称规则见下节，最多 8 次重试，长度读取 MemberNFT 配置。名称空间下限 `MAX_NAME_LENGTH ≥ bytes(TYPE_CODE()).length + 9` 字节（类型码 + 1 字节分隔符 + 4 位十六进制随机后缀 + 4 字节 Test 前缀；当前四类 2 字节类型码即 11）是部署期不变量。广播前 Manager 尚未部署，部署脚本按「当前最长类型码 2 字节」预检 `MAX_NAME_LENGTH ≥ 11`，该假设由 `testT181` 对四个已部署 Manager 的实际 `TYPE_CODE()` 反向锁定（不一致即测试失败）；`21_check.sh` 部署后按每个 Manager 的 `TYPE_CODE()` 独立复核。8 次重试仍取不到可用名称回 `ManagerGroupNameUnavailable()`。
2. Manager 计算铸造费用，从激活者 msg.sender 转入首币并按需授权 MemberNFT；零费用不转账。付款/授权失败由 `SafeERC20` 回滚 `SafeERC20FailedOperation(token)`，实际费用与报价不一致回 `ManagerMintCostChanged(expected, actual)`；非 LOVE20 token 回 `TokenNotLOVE20(token)`。
3. Manager 铸造并持有 NFT，以其 memberId 为 groupId 记录业务映射；scope 使用 Manager 自身，其他槽位使用构造时固定的模块，然后激活同一个 GroupChat 合约。
4. 任一步失败整体回滚，付款、NFT、映射和激活不能半完成；激活者只是付费者，不因付费获得 Chat 管理权。

## 托管群名称

名称只是展示标签，不是身份来源；token/actionId 从 `Activate` 事件与 `tokenOfGroup` / `actionOfGroup` 读取。

`ManagerBase` 只提供通用命名机制，不维护类型清单，也不决定 payload 内容；类型码与 payload 由各 Manager 自己定义，不设集中清单。`ManagerBase` 不接收 type code 构造参数，具体 Manager 实现 `_typeCode()`，并由 `IManagerBase.TYPE_CODE()` 暴露。四类 Manager 的 `_typeCode()` 必须非空且互异（源码/测试不变量，`testT180` 锁定）。当前四类为 `tm`（TokenMainManager）、`tg`（TokenGovManager）、`am`（TokenActionMainManager）、`ag`（TokenActionGovManager），各 2 字节。沿用同一命名格式时，新增托管类型只需新 Manager 实现自己的 `_typeCode()` 与 payload，不改 `ManagerBase`，也不需要在脚本里维护 Manager 清单；只有类型码比当前最长（2 字节）更长时，才需抬高部署脚本的预检常量，并把新 Manager 加入 `testT181` 的类型码核对——漏改时预检偏低，由 `21_check.sh` 部署后拦下。若需要不同的命名格式，仍需单独扩展命名机制。

格式为 `type[_payload]_random`：

- `type`：Manager 自己的类型码（当前四类见上）。
- `payload`：token 类为清洗后的 `symbol()`；action 类为 `symbol()_actionId`，`symbol()` 清洗后为空时只用 actionId。`symbol()` 先清洗为 ASCII 字母数字与 CJK（U+4E00-U+9FFF），其他字符丢弃；清洗后为空且无 action 时没有 payload。
- 整段 payload 连同 4 位十六进制随机后缀放得下时：`type_payload_<4 位 hex>`，payload 原样保留。
- 放不下时：payload 整段丢弃（不哈希、不截断），名称为 `type_<随机串>`，随机串填满剩余字节。
- 随机后缀：有 payload 时固定 4 位十六进制；无 payload 时填满 `MAX_NAME_LENGTH - typeCode.length - 1 - testPrefix` 位。
- 4 位 hex 后缀只用于同 stem 消歧；定向抢占与后缀长度无关，占满 4 hex 空间需 65,536 次 mint，这是已知取舍。

32 字节、6 位 actionId 下 payload 最大长度：

| Manager | 正常 | Test 模式 |
| --- | --- | --- |
| token 类 | 24 字节 symbol | 20 字节 symbol |
| action 类 | 17 字节 symbol + 6 位 actionId | 13 字节 symbol + 6 位 actionId |

示例：`tm_ABCD_1a2b`、`am_ABCD_42_1a2b`；symbol 超长时 `tm_<29 位 hex>`、`am_<29 位 hex>`；Test 模式超长时 `Testtm_<25 位 hex>`。中文 symbol 整段放得下时保留，放不下时整段丢弃，不切 UTF-8。

部署建议把 `MAX_NAME_LENGTH` 保持在 32–64；payload 丢弃时的随机串长度随 `MAX_NAME_LENGTH` 线性增长。

名称的 Test 前缀按 MemberNFT 的 `LOVE20_TOKEN_ADDRESS` 符号判定；该地址由部署 check 保证已初始化，Manager 不判断其是否为零地址或无代码。

构造期依赖代码、参数与地址关系的静态校验由部署脚本在广播前完成（dev-standards §5.7）。`onERC721Received` 收到非协议 NFT 合约或非零 `from` 时回 `UnexpectedManagerERC721Received(operator, from, tokenId)`。

BSC MemberNFT 的返回值/费用查询 ABI 与旧 group 不完全相同，迁移时适配接口并保留付款金额校验，不新增补贴、退款账户或代付凭证。

## 转移与失效

旧 Manager 没有 NFT 转出、NFT approve、配置重配、升级或恢复入口，BSC 也不新增。onERC721Received 只接受来自协议 NFT 合约、from 为零的铸造回调；普通安全转入被拒绝，这不代表能阻止 ERC721 的非安全 transferFrom 强行转入。

Manager 无私钥，不存在自然人“丢失 Manager 私钥”；若依赖业务故障，按旧路径失败，不向激活付款者赋予接管权，也不自动替换映射。普通 owner Chat 的 NFT 可转移，委托/admin 有效性依旧按快照处理，不能与 managed NFT 混淆。

## owner 管理型群组 Chat

群组直接用 owner 持有的 MemberNFT 激活，不走 Manager；owner/有效 delegate 可更新四个槽位。GroupMemberScope 和组合归属源行为见 [类型与资格](05-chat-types.md)，后者只把旧 GroupJoin 地址关系查询替换为 BSC 标准 GroupAction Executor 的 memberId 查询。

核对来源：旧 `LOVE20TKM/group-chat/src/managers/BaseManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenScopeManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenActionScopeManager.sol`，提交见 [入口](README.md#已核对来源)。
