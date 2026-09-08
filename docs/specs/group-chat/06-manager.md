# Manager 与群组 Chat

## 四类 Manager

保留 TokenMainManager、TokenGovManager、TokenActionMainManager、TokenActionGovManager；每个 Manager 可以管理多个 Chat，不为每个 Chat 部署新 Manager。

同一个 token（token Manager）或 token + actionId（action Manager）只能在同一 Manager 中激活一次。保留 tokenOfGroup/groupIdOfToken、actionOfGroup/groupIdOfAction 及批量、分页查询；行动定位使用已有 `actionOfGroup(groupId)` 返回 token 和 actionId，不另加重复的 getActionId。

```solidity
function activate(address token) external returns (uint256 groupId);
function tokenOfGroup(uint256 groupId) external view returns (address);
function groupIdOfToken(address token) external view returns (uint256);
function tokensCount() external view returns (uint256);
function tokens(uint256 offset, uint256 limit, bool reverse)
    external view returns (address[] memory tokenList, uint256[] memory groupIds);
function RECENT_ROUNDS() external view returns (uint256);
function activate(address token, uint256 actionId) external returns (uint256 groupId);
function actionOfGroup(uint256 groupId) external view returns (address token, uint256 actionId);
function groupIdOfAction(address token, uint256 actionId) external view returns (uint256);
function groupIdsOfActions(address token, uint256[] calldata actionIds)
    external view returns (uint256[] memory groupIds);
function actionsOfGroups(uint256[] calldata groupIds)
    external view returns (address[] memory tokens, uint256[] memory actionIds);
function actionsByTokenCount(address token) external view returns (uint256);
function actionsByToken(address token, uint256 offset, uint256 limit, bool reverse)
    external view returns (uint256[] memory actionIds, uint256[] memory groupIds);
```

## NFT 付款与持有

保留旧 BaseManager 的激活交易：

1. 校验 LOVE20 token、存在的 Proposal 及未重复激活，生成唯一名称；保留名称前缀、ASCII 清理/截断、12 位十六进制后缀和最多 8 次重试，长度读取 MemberNFT 配置。
2. Manager 计算铸造费用，从激活者 msg.sender 转入首币并按需授权 MemberNFT；零费用不转账。付款/授权失败或实际费用与报价不一致则回滚。
3. Manager 铸造并持有 NFT，以其 memberId 为 groupId 记录业务映射；scope 使用 Manager 自身，其他槽位使用构造时固定的模块，然后激活同一个 GroupChat 合约。
4. 任一步失败整体回滚，付款、NFT、映射和激活不能半完成；激活者只是付费者，不因付费获得 Chat 管理权。

BSC MemberNFT 的返回值/费用查询 ABI 与旧 group 不完全相同，迁移时适配接口并保留付款金额校验，不新增补贴、退款账户或代付凭证。

## 转移与失效

旧 Manager 没有 NFT 转出、NFT approve、配置重配、升级或恢复入口，BSC 也不新增。onERC721Received 只接受来自协议 NFT 合约、from 为零的铸造回调；普通安全转入被拒绝，这不代表能阻止 ERC721 的非安全 transferFrom 强行转入。

Manager 无私钥，不存在自然人“丢失 Manager 私钥”；若依赖业务故障，按旧路径失败，不向激活付款者赋予接管权，也不自动替换映射。普通 owner Chat 的 NFT 可转移，委托/admin 有效性依旧按快照处理，不能与 managed NFT 混淆。

## owner 管理型群组 Chat

群组直接用 owner 持有的 MemberNFT 激活，不走 Manager；owner/有效 delegate 可更新四个槽位。GroupMemberScope 和组合归属源行为见 [类型与资格](05-chat-types.md)，后者只把旧 GroupJoin 地址关系查询替换为 BSC 标准 GroupAction Executor 的 memberId 查询。

核对来源：旧 `LOVE20TKM/group-chat/src/managers/BaseManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenScopeManager.sol`、`LOVE20TKM/group-chat/src/managers/BaseTokenActionScopeManager.sol`，提交见 [入口](README.md#已核对来源)。
