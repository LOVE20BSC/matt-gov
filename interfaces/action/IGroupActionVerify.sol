// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IVerificationInfo} from "./IVerificationInfo.sol";

struct VerifierApplication {
    uint256 applicationId;
    uint256 memberId;
    string description;
    uint256 ratioForPublicVerifier;
    uint256 votes;
    bool active;
}

interface IGroupActionVerifyEvents {
    event VerificationBatchSubmitted(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed groupId,
        uint256 round,
        uint256 batchIndex,
        uint256[] scores
    );
    event VerifierApplied(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed memberId,
        uint256 round,
        uint256 applicationId
    );
    event VerifierLocked(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 indexed round,
        uint256 memberId
    );
}

interface IGroupActionVerifyErrors {
    error OriginScoresEmpty();
    error InvalidCandidate();
    error ScoreExceedsMax();
    error AlreadyVerified();
    error BatchIndexMismatch(uint256 expected, uint256 actual);
    error ScoresExceedAccountCount();
    error VerifyVotesZero();
    error ApplicationNotActive();
    error VerifierAlreadyLocked(address tokenAddress, uint256 actionId, uint256 round);
}

interface IGroupActionVerify is IVerificationInfo, IGroupActionVerifyEvents, IGroupActionVerifyErrors {
    function submitOriginScores(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 verifierMemberId,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external;

    function originScore(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 memberId
    )
        external
        view
        returns (
            uint256 score,
            bool verified
        );

    function finalScore(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 memberId
    ) external view returns (uint256);

    function totalFinalScore(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    function verifiedMemberCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function isRoundVerified(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (bool);

    function lockedVerifierId(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    function applyForVerifier(
        address tokenAddress,
        uint256 actionId,
        uint256 memberId,
        string calldata description,
        uint256 ratioForPublicVerifier
    ) external returns (uint256 applicationId);

    function cancelVerifierApplication(
        address tokenAddress,
        uint256 actionId,
        uint256 memberId
    ) external;

    function currentApplicationId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 memberId
    ) external view returns (uint256);

    function verifierApplication(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 applicationId
    ) external view returns (VerifierApplication memory);

    function verifierApplicationsCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    function verifierApplicationAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 index
    ) external view returns (VerifierApplication memory);

    function rankedApplicationIds(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256[] memory);
}
