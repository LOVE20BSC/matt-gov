// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostBanSource} from "./IGroupChatRules.sol";

/// @notice 把人工黑名单（IGroupChatBanList）包装为 ban source，供 IGroupChat.setBanSource 使用。
interface IAdminBanSource is IPostBanSource {
    function GROUP_BAN_LIST_ADDRESS() external view returns (address);

    error AdminBanSourceAddressHasNoCode();
}
