// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IActionExecutor} from "./IActionExecutor.sol";

interface ILpExecutorEvents {
    event Joined(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed memberId,
        uint256 round,
        uint256 amount
    );
    event Withdrawn(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed memberId,
        uint256 round,
        uint256 amount
    );
    event Exited(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed memberId,
        uint256 round
    );
    event ActionRewardMinted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
        uint256 totalAmount, bytes32 recipientType);
    event RewardBurned(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
        uint256 amount, bytes32 reason);
}

interface ILpExecutor is IActionExecutor, ILpExecutorEvents {
    function join(address tokenAddress, uint256 actionId, uint256 memberId, uint256 amount,
        string[] calldata verificationInfos) external;
    function withdraw(address tokenAddress, uint256 actionId, uint256 memberId, uint256 amount) external;
    function GOV_RATIO_MULTIPLIER(address tokenAddress, uint256 actionId) external view returns (uint256);
    function MIN_GOV_RATIO(address tokenAddress, uint256 actionId) external view returns (uint256);
    function init(address actionTargetAddress, address memberNFTAddress, address phaseAddress,
        address stakeAddress, address mintAddress, address pairFactoryAddress) external;
    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
    function joinedAmount(address tokenAddress, uint256 actionId) external view returns (uint256);
    function joinedAmountByMemberId(address tokenAddress, uint256 actionId, uint256 memberId)
        external view returns (uint256);
    function joinedAmountByRound(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (uint256);
    function joinedAmountByMemberIdByRound(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round)
        external view returns (uint256);
    function deduction(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 amount, uint256[] memory joinBlocks, uint256[] memory joinAmounts);
    function totalDeduction(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (uint256);
    function govRatio(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 ratio, bool claimed);

    error AlreadyInitialized();
    error InvalidKVLength();
    error UnauthorizedCallback();
    error InvalidParticipationAmount();
    error InvalidRound(uint256 round);
    error RoundNotStarted();
    error NotMemberOwner(uint256 memberId);
    error ProposalNotVoted(address tokenAddress, uint256 proposalId);
    error InsufficientGovRatio();
    error RewardAlreadyMinted(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round);
}
