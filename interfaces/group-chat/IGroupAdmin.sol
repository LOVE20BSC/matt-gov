// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IGroupAdmin {
    function GROUP_ADDRESS() external view returns (address);
    function GROUP_DELEGATE_ADDRESS() external view returns (address);
    function MAX_ADMIN_IDS() external view returns (uint256);
    function addAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIds) external;
    function removeAdmins(uint256 groupId, uint256 operatorId, uint256[] calldata adminIds) external;
    function isAdminId(uint256 groupId, uint256 adminId) external view returns (bool);
    function adminIds(uint256 groupId) external view returns (uint256[] memory ids, bool[] memory isEffective);

    event SetAdmin(uint256 indexed groupId, address indexed operator, uint256 indexed adminId,
        uint256 operatorId, bool listed);
    event SetAdminSnapshot(uint256 indexed groupId, address indexed operator, uint256 indexed adminId,
        uint256 operatorId, address groupOwnerSnapshot, address adminOwnerSnapshot);

    error DuplicateAdminId();
    error AdminIdsLimitExceeded();
    error GroupAdminAddressHasNoCode();
    error UnauthorizedGroupAdminManager();
    error MaxAdminIdsZero();
    error GroupDelegateGroupMismatch();
    error GroupNotExist();
}
