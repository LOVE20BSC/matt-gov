// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

enum TargetMode { NoCallback, Callback }

struct ProposalHead {
    uint256 id;
    uint256 author;
    uint256 createAtBlock;
}

struct ProposalBody {
    string title;
    string details;
}

struct ProposalParams {
    string title;
    string details;
    address target;
    TargetMode targetMode;
    bytes32[] keys;
    bytes[] values;
}

interface ISubmit {
    function stakeAddress() external view returns (address);
    function SUBMIT_MIN_PER_THOUSAND() external view returns (uint256);
    function MAX_VERIFICATION_KEY_LENGTH() external view returns (uint256);
    function init(
        address phaseAddress,
        address stakeAddress,
        address memberNFTAddress,
        uint256 submitMinPerThousand
    ) external;
    function createProposal(
        address tokenAddress,
        uint256 memberId,
        ProposalParams calldata params
    ) external returns (uint256 proposalId);
    function proposal(address tokenAddress, uint256 proposalId)
        external view returns (
            ProposalHead memory head,
            ProposalBody memory body,
            address target,
            TargetMode targetMode,
            bytes32[] memory keys,
            bytes[] memory values
        );
    function proposalsCount(address tokenAddress) external view returns (uint256);
    function proposalsAtIndex(address tokenAddress, uint256 index)
        external view returns (uint256 proposalId);
    function currentRound() external view returns (uint256);
    function canSubmit(address tokenAddress, uint256 memberId) external view returns (bool);
    function submit(address tokenAddress, uint256 memberId, uint256 proposalId) external;
    function isSubmitted(address tokenAddress, uint256 round, uint256 proposalId)
        external view returns (bool);
    function submissionsCount(address tokenAddress, uint256 round) external view returns (uint256);
    function submissionAtIndex(address tokenAddress, uint256 round, uint256 index)
        external view returns (uint256 proposalId, uint256 submitterId);

    event ProposalCreated(
        address indexed tokenAddress,
        uint256 indexed proposalId,
        uint256 indexed author,
        string title,
        string details,
        address target,
        TargetMode targetMode
    );
    event ProposalSubmitted(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed submitterId,
        uint256 indexed proposalId
    );

    error AlreadyInitialized();
    error InvalidKVLength();
    error ProposalNotFound(uint256 proposalId);
    error IndexOutOfBounds(uint256 length);
    error CannotSubmitAction();
    error AlreadySubmitted();
    error OnlyOneSubmitPerRound();
}
