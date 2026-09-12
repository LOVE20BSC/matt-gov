// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IPostScopeSource} from "./IGroupChatRules.sol";

/// @notice 把群成员名单（IGroupMember）包装为 scope source，供 IGroupChat.setScopeSource 使用。
interface IGroupMemberScope is IPostScopeSource {
    function GROUP_MEMBER_ADDRESS() external view returns (address);

    error GroupMemberScopeAddressHasNoCode();
}
