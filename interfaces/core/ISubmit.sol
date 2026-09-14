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
    bytes[] targetData;
}

struct ProposalSubmitInfo {
    uint256 submitter;
    uint256 proposalId;
}

interface ISubmitErrors {
    error AlreadyInitialized();
    error InvalidAddress();
    error InvalidTargetMode();
    error NotMemberOwner(uint256 memberId);
    error EmptyString(string parameter);
    error ZeroAmount(string parameter);
    error InvalidAmount();
    error RoundNotStarted();
    error ProposalNotFound(uint256 proposalId);
    error IndexOutOfBounds(uint256 index);
    error CannotSubmitAction();
    error AlreadySubmitted();
    error OnlyOneSubmitPerRound();
}

interface ISubmitEvents {
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
}

interface ISubmit is ISubmitErrors, ISubmitEvents {
    function stakeAddress() external view returns (address);
    function phaseAddress() external view returns (address);
    function memberNFTAddress() external view returns (address);
    function SUBMIT_MIN_PER_THOUSAND() external view returns (uint256);
    function initialized() external view returns (bool);
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
    function submit(address tokenAddress, uint256 memberId, uint256 proposalId) external;
    function currentRound() external view returns (uint256);
    function canSubmit(address tokenAddress, uint256 memberId) external view returns (bool);
    function isSubmitted(address tokenAddress, uint256 round, uint256 proposalId)
        external view returns (bool);
    function proposal(address tokenAddress, uint256 proposalId)
        external view returns (
            ProposalHead memory head,
            ProposalBody memory body,
            address target,
            TargetMode targetMode,
            bytes[] memory targetData
        );

    /// @notice Paginated query for all proposals in a community
    /// @param tokenAddress The community token address
    /// @param offset Starting offset (0-based)
    /// @param limit Maximum number of proposals to return
    /// @return proposalIds Array of proposal IDs
    /// @return totalCount Total number of proposals in the community
    function proposals(
        address tokenAddress,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory proposalIds, uint256 totalCount);

    function submissionsCount(address tokenAddress, uint256 round) external view returns (uint256);
    function submissionAtIndex(address tokenAddress, uint256 round, uint256 index)
        external view returns (uint256 proposalId, uint256 submitterId);

    /// @notice Query the submitter of a specific proposal in a round
    /// @dev Corresponding to old code: submitInfo[token][round][actionId]
    /// @param tokenAddress The stake token address
    /// @param round The round number
    /// @param proposalId The proposal ID
    /// @return submitterId The member ID of the submitter (0 if not submitted)
    function submitInfo(address tokenAddress, uint256 round, uint256 proposalId)
        external view returns (uint256 submitterId);

    /// @notice Query whether a member has submitted in a round
    /// @dev Corresponding to old code: submitInfoBySubmitter[token][round][submitter]
    /// @param tokenAddress The stake token address
    /// @param round The round number
    /// @param memberId The member ID
    /// @return proposalId The proposal ID submitted by the member (0 if not submitted)
    function submitInfoBySubmitter(address tokenAddress, uint256 round, uint256 memberId)
        external view returns (uint256 proposalId);

    /// @notice Paginated query for proposals created by an author
    /// @param tokenAddress The community token address
    /// @param author The author's member ID
    /// @param offset Starting offset (0-based)
    /// @param limit Maximum number of proposals to return
    /// @return proposalIds Array of proposal IDs
    /// @return totalCount Total number of proposals by this author
    function proposalsByAuthor(
        address tokenAddress,
        uint256 author,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory proposalIds, uint256 totalCount);
}
