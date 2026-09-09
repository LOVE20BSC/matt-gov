// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupChat {
    struct ChatInfo {
        uint256 groupId;
        address owner;
        bool activated;
        bool postingAllowed;
        address scopeSource;
        address banSource;
        address beforePostPlugin;
        address afterPostPlugin;
        address firstActivatedOwner;
        uint256 firstActivatedBlockNumber;
        uint256 firstActivatedTimestamp;
    }
    struct Message {
        uint256 groupId;
        uint256 senderId;
        address senderAddress;
        uint256 round;
        uint256 messageId;
        string content;
        uint256 blockNumber;
        uint256 timestamp;
        uint256[] mentionedSenderIds;
        bool mentionAll;
        uint256 quotedMessageId;
    }
    struct RoundSpan {
        uint256 round;
        uint256 startMessageId;
        uint256 endMessageId;
        uint256 messageCount;
    }

    function GROUP_ADDRESS() external view returns (address);
    function GROUP_ADMIN_ADDRESS() external view returns (address);
    function GROUP_DELEGATE_ADDRESS() external view returns (address);
    function originBlocks() external view returns (uint256);
    function phaseBlocks() external view returns (uint256);
    function MAX_CONTENT_LENGTH() external view returns (uint256);
    function MAX_MENTIONED_SENDER_IDS() external view returns (uint256);
    function activateChat(uint256 groupId, address scopeSource_, address banSource_,
        address beforePostPlugin_, address afterPostPlugin_) external;
    function setPostingAllowed(uint256 groupId, uint256 operatorId, bool postingAllowed_) external;
    function setScopeSource(uint256 groupId, uint256 operatorId, address sourceAddress) external;
    function setBanSource(uint256 groupId, uint256 operatorId, address sourceAddress) external;
    function setBeforePostPlugin(uint256 groupId, uint256 operatorId, address pluginAddress) external;
    function setAfterPostPlugin(uint256 groupId, uint256 operatorId, address pluginAddress) external;
    function post(uint256 groupId, uint256 senderId, string calldata content,
        uint256[] calldata mentionedSenderIds, bool mentionAll, uint256 quotedMessageId) external;
    function chatInfo(uint256 groupId) external view returns (ChatInfo memory);
    function chatInfos(uint256[] calldata groupIds) external view returns (ChatInfo[] memory);
    function postingAllowed(uint256 groupId) external view returns (bool);
    function scopeSource(uint256 groupId) external view returns (address);
    function banSource(uint256 groupId) external view returns (address);
    function beforePostPlugin(uint256 groupId) external view returns (address);
    function afterPostPlugin(uint256 groupId) external view returns (address);
    function canPost(uint256 groupId, uint256 senderId)
        external view returns (bool allowed, bytes4 reasonCode);
    function messagesCount(uint256 groupId) external view returns (uint256);
    function messages(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external view returns (Message[] memory);
    function message(uint256 groupId, uint256 messageId) external view returns (Message memory);
    function messagesByRoundCount(uint256 groupId, uint256 round) external view returns (uint256);
    function messagesByRound(uint256 groupId, uint256 round, uint256 offset, uint256 limit, bool reverse)
        external view returns (Message[] memory);
    function messagesBySenderCount(uint256 groupId, uint256 senderId) external view returns (uint256);
    function messagesBySender(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external view returns (Message[] memory);
    function messageIdsBySender(uint256 groupId, uint256 senderId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory);
    function messagesByMentionCount(uint256 groupId, uint256 mentionedSenderId) external view returns (uint256);
    function messagesByMention(uint256 groupId, uint256 mentionedSenderId, uint256 offset, uint256 limit, bool reverse)
        external view returns (Message[] memory);
    function messageIdsByMention(uint256 groupId, uint256 mentionedSenderId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory);
    function messagesByMentionAllCount(uint256 groupId) external view returns (uint256);
    function messagesByMentionAll(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external view returns (Message[] memory);
    function messageIdsByMentionAll(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory);
    function senderIdsCount(uint256 groupId) external view returns (uint256);
    function senderIds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external view returns (uint256[] memory);
    function groupIdsCount() external view returns (uint256);
    function groupIds(uint256 offset, uint256 limit, bool reverse) external view returns (uint256[] memory);
    function currentRound() external view returns (uint256);
    function roundsCount(uint256 groupId) external view returns (uint256);
    function rounds(uint256 groupId, uint256 offset, uint256 limit, bool reverse)
        external view returns (RoundSpan[] memory);
    function roundInfo(uint256 groupId, uint256 round) external view returns (RoundSpan memory);
    function roundInfos(uint256 groupId, uint256[] calldata rounds)
        external view returns (RoundSpan[] memory);

    event Activate(uint256 indexed groupId, uint256 indexed ownerId, address indexed owner);
    event SetPostingAllowed(uint256 indexed groupId, uint256 indexed operatorId, address indexed operator, bool postingAllowed);
    event SetScopeSource(uint256 indexed groupId, address indexed sourceAddress, uint256 indexed operatorId, address operator, address prevSourceAddress);
    event SetBanSource(uint256 indexed groupId, address indexed sourceAddress, uint256 indexed operatorId, address operator, address prevSourceAddress);
    event SetBeforePostPlugin(uint256 indexed groupId, address indexed pluginAddress, uint256 indexed operatorId, address operator, address prevPluginAddress);
    event SetAfterPostPlugin(uint256 indexed groupId, address indexed pluginAddress, uint256 indexed operatorId, address operator, address prevPluginAddress);
    event PostMessage(uint256 indexed groupId, uint256 indexed senderId, address indexed senderAddress, uint256 round, uint256 messageId);
    event MentionSenderId(uint256 indexed groupId, uint256 indexed mentionedSenderId, uint256 messageId);
    event MentionAll(uint256 indexed groupId, uint256 messageId);
    event FailAfterPostPlugin(uint256 indexed groupId, uint256 indexed messageId, address indexed pluginAddress, uint256 round, bytes errorData);

    error AlreadyInitialized();
    error GroupNotExist();
    error ChatAlreadyActivated();
    error ChatNotActivated();
    error PostingNotAllowed();
    error NotChatOwner();
    error NotChatOwnerOrDelegateIdOwner();
    error SenderNotMemberOwner(uint256 senderId);
    error RoundNotStarted();
    error Reentrant();
    error PhaseBlocksZero();
    error MaxContentLengthZero();
    error SourceAddressHasNoCode();
    error PluginAddressHasNoCode();
    error ContentEmpty();
    error ContentTooLong(uint256 length, uint256 maxLength);
    error TooManyMentionedSenderIds(uint256 length, uint256 maxLength);
    error DuplicateMentionedSenderId();
    error InvalidQuotedMessageId();
    error InvalidMessageId();
    error MentionAllUnauthorized();
    error ScopeRejected();
    error BanRejected();
    error ScopeSourceFailed();
    error BanSourceFailed();
    error InvalidAddress();
}
