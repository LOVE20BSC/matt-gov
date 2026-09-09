// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ITokenManager {
    function GROUP_CHAT_ADDRESS() external view returns (address);
    function GROUP_ADDRESS() external view returns (address);
    function BAN_SOURCE_ADDRESS() external view returns (address);
    function BEFORE_POST_PLUGIN_ADDRESS() external view returns (address);
    function AFTER_POST_PLUGIN_ADDRESS() external view returns (address);
    function canPost(uint256 groupId, uint256 senderId) external view returns (bool);
    function voteWeightOf(uint256 groupId, uint256 voterId) external view returns (uint256);
    function totalVoteWeight(uint256 groupId) external view returns (uint256);
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external returns (bytes4);
    function RECENT_ROUNDS() external view returns (uint256);
    function activate(address token) external returns (uint256 groupId);
    function tokenOfGroup(uint256 groupId) external view returns (address);
    function groupIdOfToken(address token) external view returns (uint256);
    function tokensCount() external view returns (uint256);
    function tokens(uint256 offset, uint256 limit, bool reverse)
        external view returns (address[] memory tokenList, uint256[] memory groupIds);

    event Activate(address indexed token, uint256 indexed groupId, address indexed operator);

    error ManagerAddressHasNoCode();
    error AlreadyManaged();
    error RecentRoundsZero();
    error ManagerGroupNameUnavailable();
    error ManagerMintCostChanged();
    error ManagerPaymentFailed();
    error ManagerApprovalFailed();
    error TokenNotLOVE20();
    error UnexpectedManagerERC721Received();
}
