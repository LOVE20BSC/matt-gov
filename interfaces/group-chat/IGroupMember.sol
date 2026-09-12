// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupMemberEvents {
    event SetMemberId(uint256 indexed groupId, address indexed operator, uint256 indexed memberId,
        uint256 operatorId, bool listed);
}

interface IGroupMember is IGroupMemberEvents {
    function GROUP_ADDRESS() external view returns (address);
    function GROUP_ADMIN_ADDRESS() external view returns (address);
    function addMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds) external;
    function removeMemberIds(uint256 groupId, uint256 operatorId, uint256[] calldata memberIds) external;
    function isMemberId(uint256 groupId, uint256 memberId) external view returns (bool);
    function isMemberIdBatch(uint256 groupId, uint256[] calldata memberIds)
        external view returns (bool[] memory listed);
    function memberIdsCount(uint256 groupId) external view returns (uint256);
    function memberIds(uint256 groupId, uint256 offset, uint256 limit)
        external view returns (uint256[] memory);

    error TargetMemberIdZero();
    error GroupMemberAddressHasNoCode();
    error UnauthorizedGroupMemberManager();
    error GroupNotExist();
}
