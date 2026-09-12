// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IPostScopeSource {
    function canPost(uint256 groupId, uint256 senderId) external view returns (bool);
}

interface IPostBanSource {
    function isBanned(uint256 groupId, uint256 senderId) external view returns (bool);
}

interface IBeforePostPlugin {
    function beforePost(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId
    ) external;
}

interface IAfterPostPlugin {
    function afterPost(
        uint256 groupId,
        uint256 senderId,
        string calldata content,
        uint256[] calldata mentionedSenderIds,
        bool mentionAll,
        uint256 quotedMessageId,
        uint256 messageId,
        uint256 blockNumber,
        uint256 timestamp
    ) external;
}
