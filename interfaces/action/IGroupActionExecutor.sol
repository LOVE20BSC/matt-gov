// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupActionIndexes} from "./IGroupActionIndexes.sol";
import {IProposalTarget} from "../core/IProposalTarget.sol";

struct GroupConfig {
    string description;
    uint256 maxCapacity;
    uint256 minJoinAmount;
    uint256 maxJoinAmount;
    uint256 maxAccounts;
}

struct VerifierApplication {
    uint256 applicationId;
    uint256 memberId;
    string description;
    uint256 ratioForPublicVerifier;
    uint256 votes;
    bool active;
}

interface IGroupActionExecutor is IGroupActionIndexes, IProposalTarget {
    function JOIN_TOKEN_ADDRESS() external view returns (address);
    function ACTIVATION_STAKE_AMOUNT() external view returns (uint256);
    function MAX_JOIN_AMOUNT_RATIO() external view returns (uint256);
    function ACTIVATION_MIN_GOV_RATIO() external view returns (uint256);
    function init(address actionTargetAddress, address memberNFTAddress, address phaseAddress,
        address stakeAddress, address mintAddress, uint256[] calldata splits) external;
    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentVerifyRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
    function activateGroup(address tokenAddress, uint256 actionId, uint256 groupId, GroupConfig calldata config) external;
    function deactivateGroup(address tokenAddress, uint256 actionId, uint256 groupId) external;
    function updateGroupInfo(address tokenAddress, uint256 actionId, uint256 groupId, GroupConfig calldata config) external;
    function groupInfo(address tokenAddress, uint256 actionId, uint256 groupId)
        external view returns (GroupConfig memory config, bool active, uint256 activatedRound, uint256 deactivatedRound);
    function join(address tokenAddress, uint256 actionId, uint256 groupId, uint256 memberId,
        uint256 amount, string[] calldata verificationInfos) external;
    function withdraw(address tokenAddress, uint256 actionId, uint256 memberId, uint256 amount) external;
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function joinInfo(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 joinedRound, uint256 amount, uint256 groupId);
    function groupIds(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (uint256[] memory);
    function memberIdsByGroupId(address tokenAddress, uint256 actionId, uint256 round, uint256 groupId)
        external view returns (uint256[] memory);
    function joinedAmountByMemberId(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256);
    function trialAccountsWaitingAdd(address tokenAddress, uint256 actionId, uint256 groupId,
        uint256 providerMemberId, uint256[] calldata memberIds, uint256[] calldata amounts) external;
    function trialAccountsWaitingRemove(address tokenAddress, uint256 actionId, uint256 groupId,
        uint256 providerMemberId, uint256[] calldata memberIds) external;
    function trialJoin(address tokenAddress, uint256 actionId, uint256 groupId, uint256 memberId,
        uint256 providerMemberId, string[] calldata verificationInfos) external;
    function trialWithdraw(address tokenAddress, uint256 actionId, uint256 memberId,
        uint256 providerMemberId, uint256 amount) external;
    function trialAccountsWaiting(address tokenAddress, uint256 actionId, uint256 groupId, uint256 providerMemberId)
        external view returns (uint256[] memory memberIds, uint256[] memory amounts, uint256[] memory blockNumbers);
    function trialAmount(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId,
        uint256 providerMemberId) external view returns (uint256);
    function applyForVerifier(address tokenAddress, uint256 actionId, uint256 memberId,
        string calldata description, uint256 ratioForPublicVerifier) external returns (uint256 applicationId);
    function cancelVerifierApplication(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function currentApplicationId(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256);
    function verifierApplication(address tokenAddress, uint256 actionId, uint256 round, uint256 applicationId)
        external view returns (VerifierApplication memory);
    function verifierApplicationsCount(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (uint256);
    function verifierApplicationAtIndex(address tokenAddress, uint256 actionId, uint256 round, uint256 index)
        external view returns (VerifierApplication memory);
    function rankedApplicationIds(address tokenAddress, uint256 actionId, uint256 round)
        external view returns (uint256[] memory);
    function submitOriginScores(address tokenAddress, uint256 actionId, uint256 round,
        uint256 verifierMemberId, uint256 groupId, uint256 startIndex, uint256[] calldata originScores) external;
    function verifiedMemberCount(address tokenAddress, uint256 actionId, uint256 round, uint256 groupId)
        external view returns (uint256);
    function lockedVerifierId(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256);
    function isRoundVerified(address tokenAddress, uint256 actionId, uint256 round) external view returns (bool);
    function originScore(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256 score, bool verified);
    function finalScore(address tokenAddress, uint256 actionId, uint256 round, uint256 memberId)
        external view returns (uint256);
    function totalFinalScore(address tokenAddress, uint256 actionId, uint256 round) external view returns (uint256);
    function generatedActionRewardByGroupId(address tokenAddress, uint256 actionId, uint256 round, uint256 groupId)
        external view returns (uint256);
    function generatedActionRewardByVerifier(uint256 verifierMemberId, uint256 round)
        external view returns (uint256);

    event ActionJoined(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
        uint256 round, uint256 amount, bool isExperience, uint256 providerMemberId);
    event ActionWithdrawn(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
        uint256 round, uint256 amount, bool isExperience, uint256 providerMemberId);
    event ActionExited(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
        uint256 round, bool isExperience, uint256 providerMemberId);
    event VerifierApplied(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed memberId,
        uint256 round, uint256 applicationId);
    event VerificationBatchSubmitted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed groupId,
        uint256 round, uint256 batchIndex, uint256[] scores);
    event VerifierLocked(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
        uint256 memberId);
    event ActionRewardMinted(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
        uint256 totalAmount, bytes32 recipientType);
    event RewardBurned(address indexed tokenAddress, uint256 indexed actionId, uint256 indexed round,
        uint256 amount, bytes32 reason);

    error AlreadyInitialized();
    error InvalidKVLength();
    error InvalidParticipationAmount();
    error InvalidCandidate();
    error InvalidSplits();
    error ApplicationNotActive();
    error InvalidExecutor();
    error UnauthorizedCallback();
    error NotMemberOwner(uint256 memberId);
    error ProposalNotVoted(address tokenAddress, uint256 proposalId);
    error InvalidRound(uint256 round);
    error InsufficientExperienceQuota(uint256 providerMemberId, uint256 required, uint256 available);
    error VerifierAlreadyLocked(address tokenAddress, uint256 actionId, uint256 round);
    error BatchIndexMismatch(uint256 expected, uint256 actual);
    error RewardAlreadyMinted(address tokenAddress, uint256 actionId, uint256 memberId, uint256 round);
}
