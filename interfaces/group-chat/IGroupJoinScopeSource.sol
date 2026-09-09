// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostScopeSource} from "./IGroupChatRules.sol";

/// @notice 把行动参与记录包装为 scope source，供 IGroupChat.setScopeSource 使用。
/// @dev 参与判定走 action 层单例 Executor（继承 IGroupActionIndexes 的 g* 索引），
///      因此 GROUP_JOIN_ADDRESS 改为指向 IGroupActionExecutor；旧协议的 core Join 合约已不存在。
///      GROUP_MEMBER_ADDRESS 仍指向群成员名单，与旧版一致保留。
interface IGroupJoinScopeSource is IPostScopeSource {
    function GROUP_MEMBER_ADDRESS() external view returns (address);

    function GROUP_ACTION_EXECUTOR_ADDRESS() external view returns (address);

    error GroupJoinScopeSourceAddressHasNoCode();
}
