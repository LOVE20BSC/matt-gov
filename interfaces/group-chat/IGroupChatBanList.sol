// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupChatBanListEvents {
    event SetSenderIdBan(uint256 indexed groupId, address indexed operatorAddress,
        uint256 indexed targetSenderId, uint256 operatorId, bool listed);
}

interface IGroupChatBanList is IGroupChatBanListEvents {
    function GROUP_ADMIN_ADDRESS() external view returns (address);
    function banBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds) external;
    function unbanBySenderIds(uint256 groupId, uint256 operatorId, uint256[] calldata senderIds) external;
    function senderIdBanListCount(uint256 groupId) external view returns (uint256);
    function senderIdBanList(uint256 groupId, uint256 offset, uint256 limit)
        external view returns (uint256[] memory senderIds, address[] memory operatorAddresses, uint256[] memory operatorIds);
    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool);
    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external view returns (bool[] memory banned);
    function senderIdBanDetails(uint256 groupId, uint256[] calldata senderIds)
        external view returns (bool[] memory banned, address[] memory operatorAddresses,
            uint256[] memory operatorIds);

    error TargetSenderIdZero();
    error GroupBanListAddressHasNoCode();
    error UnauthorizedGroupBanListManager();
}
