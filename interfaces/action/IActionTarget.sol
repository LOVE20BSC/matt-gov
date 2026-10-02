// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IProposalTarget} from "core/src/interfaces/IProposalTarget.sol";

interface IActionTargetEvents {
    event ActionCreated(address indexed tokenAddress, uint256 indexed actionId, address indexed executor);
    event Joined(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
    event Exited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
    event ForceExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId);
}

interface IActionTargetErrors {
    error AlreadyInitialized();
    error InvalidExecutor();
    error UnauthorizedCallback();
    error UnauthorizedExecutor(address tokenAddress, uint256 actionId);
    error NotMemberOwner(uint256 memberId);
    error ProposalNotVoted(address tokenAddress, uint256 proposalId);
    error AlreadyMinted(address tokenAddress, uint256 actionId, uint256 round);
}

interface IActionTarget is IProposalTarget, IActionTargetEvents, IActionTargetErrors {
    function memberNFTAddress() external view returns (address);
    function submitAddress() external view returns (address);
    function voteAddress() external view returns (address);
    function mintAddress() external view returns (address);

    function initialized() external view returns (bool);

    function init(address memberNFTAddress, address submitAddress, address voteAddress, address mintAddress) external;

    function registerJoinState(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function clearJoinState(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function forceExit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function mintProposalReward(address tokenAddress, uint256 round, uint256 proposalId)
        external returns (uint256 amount);

    function isJoined(address tokenAddress, uint256 actionId, uint256 memberId) external view returns (bool);
    function isJoinedByRound(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round)
        external view returns (bool);
    function executor(address tokenAddress, uint256 actionId) external view returns (address);
    function mintedProposalReward(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (uint256 amount, bool minted);
    function actionIdsByMemberId(address tokenAddress, uint256 memberId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory actionIds, uint256 total);
    function memberIdsByActionId(address tokenAddress, uint256 actionId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory memberIds, uint256 total);
    function memberIdsByActionIdByRound(address tokenAddress, uint256 actionId, uint256 round, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory memberIds, uint256 total);
    function actionIdsByExecutor(address tokenAddress, uint256 round, address executor_, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory actionIds, uint256 total);
    function actions(address tokenAddress, uint256 round, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory actionIds, address[] memory executors, uint256 total);
}
