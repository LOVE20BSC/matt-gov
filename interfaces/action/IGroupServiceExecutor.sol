// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IProposalTarget} from "../core/IProposalTarget.sol";

interface IGroupServiceExecutor is IProposalTarget {
    function init(address actionTargetAddress, address memberNFTAddress, address phaseAddress,
        address stakeAddress, address mintAddress, address groupActionExecutorAddress) external;
    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentVerifyRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
    function totalGroupActionReward(address actionTokenAddress, uint256 round)
        external view returns (uint256 reward, bool cached);
    function join(address serviceTokenAddress, uint256 serviceProposalId, uint256 memberId,
        string[] calldata verificationInfos) external;
    function exit(address serviceTokenAddress, uint256 serviceProposalId, uint256 memberId) external;
    function joinInfo(address serviceTokenAddress, uint256 serviceProposalId, uint256 round, uint256 memberId)
        external view returns (bool joined);
    function actionTokenAddress(address serviceTokenAddress, uint256 serviceProposalId)
        external view returns (address);
    function serviceRewardByMember(address serviceTokenAddress, uint256 serviceProposalId, uint256 round,
        uint256 memberId) external view returns (uint256 verifierReward, uint256 ownerReward,
        uint256 ownerBurned, bool claimed);
    function burnRewardIfNeeded(uint256 round) external;
    function setRecipients(address sourceTokenAddress, uint256 sourceActionId, uint256 groupId,
        uint256[] calldata recipientIds, uint256[] calldata ratios, string[] calldata remarks) external;
    function recipients(address sourceTokenAddress, uint256 sourceActionId, uint256 groupId, uint256 round)
        external view returns (uint256[] memory recipientIds, uint256[] memory ratios, string[] memory remarks);
    function rewardDistribution(address serviceTokenAddress, uint256 serviceProposalId, uint256 round,
        uint256 sourceActionId, uint256 groupId) external view returns (uint256[] memory recipientIds,
        uint256[] memory ratios, uint256[] memory amounts, uint256 ownerAmount);

    event ServiceRewardDistributed(address indexed serviceTokenAddress, uint256 indexed serviceProposalId,
        address indexed actionTokenAddress, uint256 memberId, uint256 verifierReward, uint256 ownerReward,
        uint256 ownerBurned, uint256 round);
    event SecondaryDistributionConfigured(address indexed sourceTokenAddress, uint256 indexed sourceActionId,
        uint256 indexed groupId, uint256 round, uint256[] recipientIds, uint256[] ratios);
    event RewardBurned(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
        uint256 amount, bytes32 reason);

    error AlreadyInitialized();
    error InvalidKVLength();
    error InvalidRound(uint256 round);
    error NotMemberOwner(uint256 memberId);
    error ProposalNotVoted(address tokenAddress, uint256 proposalId);
    error UnauthorizedCallback();
    error RewardAlreadyMinted(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round);
    error DistributionOverflow(uint256 configured, uint256 available);
}
