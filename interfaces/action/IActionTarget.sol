// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IProposalTarget} from "../core/IProposalTarget.sol";

interface IActionTargetEvents {
    event ProposalLinked(address indexed tokenAddress, uint256 indexed proposalId, address indexed executor);
    event ActionJoined(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
    event ActionWithdrawn(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
    event ActionExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId, uint256 round);
    event ForceExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId);
}

interface IActionTargetErrors {
    error AlreadyInitialized();
    error InvalidKVLength();
    error InvalidExecutor();
    error UnauthorizedCallback();
    error NotMemberOwner(uint256 memberId);
    error ProposalNotVoted(address tokenAddress, uint256 proposalId);
    error InvalidRound(uint256 round);
    error RewardAlreadyMinted(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round);
    error IndexOutOfBounds(uint256 length);
}

interface IActionTarget is IProposalTarget, IActionTargetEvents, IActionTargetErrors {
    function init(address memberNFTAddress, address submitAddress, address voteAddress, address mintAddress) external;
    function isAccountJoined(address tokenAddress, uint256 actionId, uint256 memberId) external view returns (bool);
    function actionIdsByMemberId(address tokenAddress, uint256 memberId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory actionIds, uint256 total);
    function join(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function forceExit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function executor(address tokenAddress, uint256 proposalId) external view returns (address);
    function mintProposalReward(address tokenAddress, uint256 round, uint256 proposalId)
        external returns (uint256 amount);
    function proposalIdsByExecutor(address tokenAddress, uint256 round, address executor_)
        external view returns (uint256[] memory proposalIds);
    function proposals(address tokenAddress, uint256 round)
        external view returns (uint256[] memory proposalIds, address[] memory executors);
}
