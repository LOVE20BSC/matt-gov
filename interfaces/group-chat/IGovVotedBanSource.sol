// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPostBanSource} from "./IGroupChatRules.sol";

interface IGovVotedBanSource is IPostBanSource {
    function GROUP_ADDRESS() external view returns (address);
    function PRECISION() external view returns (uint256);
    function MIN_SUPPORT_TO_OPPOSE_RATIO() external view returns (uint256);
    function BAN_THRESHOLD_RATIO() external view returns (uint256);

    function voteBySenderId(uint256 groupId, uint256 targetSenderId, uint256 voterId, bool supportBan) external;
    function clearVoteBySenderId(uint256 groupId, uint256 targetSenderId, uint256 voterId) external;
    function refreshVoteBySenderId(uint256 groupId, uint256 targetSenderId, uint256 voterId) external;
    function voteWeightsBySenderIdsByVoter(uint256 groupId, uint256[] calldata senderIds, uint256 voterId)
        external view returns (uint256[] memory supportWeights, uint256[] memory opposeWeights);
    function voteStatusBySenderId(uint256 groupId, uint256 senderId)
        external view returns (bool banned, uint256 supportWeight, uint256 opposeWeight);
    function voteStatusBySenderIds(uint256 groupId, uint256[] calldata senderIds)
        external view returns (bool[] memory banned, uint256[] memory supportWeights, uint256[] memory opposeWeights);
    function isSenderIdBanned(uint256 groupId, uint256 senderId) external view returns (bool);
    function isSenderIdBannedBatch(uint256 groupId, uint256[] calldata senderIds)
        external view returns (bool[] memory banned);
    function votedSenderIdsCount(uint256 groupId) external view returns (uint256);
    function votedSenderIds(uint256 groupId, uint256 offset, uint256 limit)
        external view returns (uint256[] memory senderIds, uint256[] memory supportWeights,
            uint256[] memory opposeWeights, uint256[] memory voterCounts);
    function votersBySenderIdCount(uint256 groupId, uint256 senderId) external view returns (uint256);
    function votersBySenderId(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit)
        external view returns (uint256[] memory voters, uint256[] memory supportWeights,
            uint256[] memory opposeWeights);
    function stateVersion(uint256 groupId) external view returns (uint256);

    event SetSenderIdBanVote(uint256 indexed groupId, uint256 indexed targetSenderId, uint256 indexed voterId,
        bool supportBan, uint256 settledWeight, uint256 supportWeight, uint256 opposeWeight, uint256 stateVersion);
    event SetSenderIdBan(uint256 indexed groupId, uint256 indexed targetSenderId,
        bool listed, uint256 stateVersion);
    event ChangeStateVersion(uint256 indexed groupId, uint256 stateVersion);

    error GovVotedBanSourceAddressHasNoCode();
    error BanVoteWeightSourceUnavailable();
    error TargetSenderIdZero();
    error VoteWeightZero();
    error VoteUnchanged();
    error VoteNotFound();
    error BanThresholdTooHigh();
    error MinSupportToOpposeRatioZero();
    error SenderNotMemberOwner(uint256 senderId);
}
