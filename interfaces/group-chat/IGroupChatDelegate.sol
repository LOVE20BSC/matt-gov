// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupChatDelegateEvents {
    event SetDelegateId(uint256 indexed groupId, address indexed owner,
        uint256 indexed delegateId, uint256 prevDelegateId);
    event ClearDelegatedGroupId(uint256 indexed groupId, uint256 indexed delegateId,
        address indexed delegateOwner);
    event SetDelegatorWhitelistEnabled(uint256 indexed delegateId, address indexed delegateOwner, bool enabled);
    event SetAllowedDelegatorGroupId(uint256 indexed delegateId, uint256 indexed groupId,
        address indexed delegateOwner, bool allowed);
}

interface IGroupChatDelegate is IGroupChatDelegateEvents {
    function GROUP_ADDRESS() external view returns (address);
    function ownerOrDelegateIdOf(uint256 groupId, address account) external view returns (uint256);
    function setDelegateId(uint256 groupId, uint256 delegateId) external;
    function clearDelegatedGroupIds(uint256 delegateId, uint256[] calldata groupIds) external;
    function setDelegatorWhitelistEnabled(uint256 delegateId, bool enabled) external;
    function setAllowedDelegatorGroupIds(uint256 delegateId, uint256[] calldata groupIds, bool allowed) external;
    function isDelegatorWhitelistEnabled(uint256 delegateId) external view returns (bool);
    function canSetDelegateTo(uint256 groupId, uint256 delegateId) external view returns (bool);
    function allowedDelegatorGroupIds(uint256 delegateId, uint256 offset, uint256 limit)
        external view returns (uint256[] memory groupIds, uint256 total);
    function allowedDelegatorGroupIdsCount(uint256 delegateId) external view returns (uint256);
    function delegateIdOf(uint256 groupId) external view returns (uint256);
    function delegateIdsOf(uint256[] calldata groupIds)
        external view returns (uint256[] memory delegateIds);
    function delegatedGroupIds(uint256 delegateId, uint256 offset, uint256 limit)
        external view returns (uint256[] memory groupIds, bool[] memory isEffective, uint256 total);
    function delegatedGroupIdsCount(uint256 delegateId) external view returns (uint256);

    error GroupNotExist();
    error SenderNotGroupOwner();
    error SenderNotDelegateOwner();
    error DelegatorGroupIdNotAllowed();
    error DelegateIdCannotBeGroupId();
}
