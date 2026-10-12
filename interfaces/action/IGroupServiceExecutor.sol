// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IActionExecutor} from "./IActionExecutor.sol";

interface IGroupServiceExecutorEvents {
    event Joined(
        address indexed serviceTokenAddress,
        uint256 indexed serviceActionId,
        uint256 indexed memberId,
        uint256 round
    );
    event Exited(
        address indexed serviceTokenAddress,
        uint256 indexed serviceActionId,
        uint256 indexed memberId,
        uint256 round
    );
    event ServiceRewardDistributed(address indexed serviceTokenAddress, uint256 indexed serviceActionId,
        address indexed actionTokenAddress, uint256 memberId, uint256 verifierReward, uint256 ownerReward,
        uint256 ownerBurned, uint256 round);
    event SecondaryDistributionConfigured(address indexed sourceTokenAddress, uint256 indexed sourceActionId,
        uint256 indexed groupId, uint256 round, uint256[] recipientIds, uint256[] ratios);
    event SecondaryRewardDistributed(address indexed serviceTokenAddress, uint256 indexed serviceActionId,
        uint256 indexed groupId, uint256 sourceActionId, uint256 recipientId, uint256 amount, uint256 round);
}

interface IGroupServiceExecutorErrors {
    error DistributionOverflow(uint256 configured, uint256 available);
    error InvalidAddress();
    error InvalidTargetDataLength();
    error InvalidParentToken();
    error InvalidRatio();
    error NoActiveGroups();
    error NotJoined();
    error AlreadyJoined();
    error TooManyRecipients();
    error ZeroRatio();
    error ArrayLengthMismatch();
    error DuplicateRecipient(uint256 memberId);
    error RecipientCannotBeSelf();
}

interface IGroupServiceExecutor is IActionExecutor, IGroupServiceExecutorEvents, IGroupServiceExecutorErrors {
    function init(address actionTargetAddress, address stakeAddress, address groupActionExecutorAddress) external;
    function currentVerifyRound() external view returns (uint256);
    function totalGroupActionReward(address actionTokenAddress, uint256 round)
        external view returns (uint256 reward, bool cached);
    function join(address serviceTokenAddress, uint256 serviceActionId, uint256 memberId) external;
    function joinInfo(address serviceTokenAddress, uint256 serviceActionId, uint256 round, uint256 memberId)
        external view returns (bool joined);
    function ACTION_TOKEN_ADDRESS(address serviceTokenAddress, uint256 serviceActionId)
        external view returns (address);
    function RATIO_FOR_PUBLIC_VERIFIER(address serviceTokenAddress, uint256 serviceActionId)
        external view returns (uint256);
    function GOV_RATIO_MULTIPLIER(address serviceTokenAddress, uint256 serviceActionId)
        external view returns (uint256);
    function serviceRewardByMember(address serviceTokenAddress, uint256 serviceActionId, uint256 round,
        uint256 memberId) external view returns (uint256 verifierReward, uint256 ownerReward,
        uint256 ownerBurned, bool claimed);
    function setRecipients(address sourceTokenAddress, uint256 sourceActionId, uint256 groupId,
        uint256[] calldata recipientIds, uint256[] calldata ratios, string[] calldata remarks) external;
    function recipients(address sourceTokenAddress, uint256 sourceActionId, uint256 groupId, uint256 round)
        external view returns (uint256[] memory recipientIds, uint256[] memory ratios, string[] memory remarks);
    function rewardDistribution(address serviceTokenAddress, uint256 serviceActionId, uint256 round,
        uint256 sourceActionId, uint256 groupId) external view returns (uint256[] memory recipientIds,
        uint256[] memory ratios, uint256[] memory amounts, uint256 ownerAmount);
}
