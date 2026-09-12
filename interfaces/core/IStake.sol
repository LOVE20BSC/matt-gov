// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

struct StakeData {
    uint256 lpShares;
    uint256 boostShares;
    uint256 promisedWaitingPhases;
    uint256 unlockRequestPhase;
}

struct TokenStakeGlobals {
    uint256 totalLpShares;
    uint256 withdrawableLp;
    uint256 feeLp;
    uint256 sqrtKOfLp;
    uint256 totalBoostShares;
}

interface IStake {
    function init(
        address phaseAddress,
        address memberNFTAddress,
        address voteAddress,
        address routerAddress,
        address pairFactoryAddress,
        uint256 promisedWaitingPhasesMin,
        uint256 promisedWaitingPhasesMax
    ) external;
    function stakeLiquidity(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 parentTokenAmount,
        uint256 promisedWaitingPhases,
        uint256 memberId
    ) external returns (uint256 govVotesAdded, uint256 lpSharesAdded);
    function stakeToken(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 promisedWaitingPhases,
        uint256 memberId
    ) external returns (uint256 govVotesAdded);
    function unstake(address tokenAddress, uint256 memberId) external;
    function withdraw(address tokenAddress, uint256 memberId) external;
    function mergeStake(address tokenAddress, uint256 sourceMemberId, uint256 targetMemberId) external;

    function PROMISED_WAITING_PHASES_MIN() external view returns (uint256);
    function PROMISED_WAITING_PHASES_MAX() external view returns (uint256);
    function govVotesNum(address tokenAddress) external view returns (uint256);
    function accountStakeStatus(address tokenAddress, uint256 memberId)
        external view returns (StakeData memory);
    function validGovVotes(address tokenAddress, uint256 memberId) external view returns (uint256);
    function tokenStakeGlobals(address tokenAddress)
        external view returns (TokenStakeGlobals memory);
    function canWithdraw(address tokenAddress, uint256 memberId) external view returns (bool);
    function cumulatedTokenAmountByAccount(
        address tokenAddress,
        uint256 round,
        uint256 memberId
    ) external view returns (uint256);
    function stakeTokenUpdatedRoundsCount(address tokenAddress)
        external view returns (uint256);
    function stakeTokenUpdatedRoundsAtIndex(address tokenAddress, uint256 index)
        external view returns (uint256);
    function stakeTokenUpdatedRoundsByAccountCount(
        address tokenAddress,
        uint256 memberId
    ) external view returns (uint256);
    function stakeTokenUpdatedRoundsByAccountAtIndex(
        address tokenAddress,
        uint256 memberId,
        uint256 index
    ) external view returns (uint256);

    event StakeLiquidity(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed memberId,
        uint256 tokenAmountForLP,
        uint256 parentTokenAmountForLP,
        uint256 promisedWaitingPhases,
        uint256 govVotesAdded,
        uint256 govVotes,
        uint256 lpSharesAdded,
        uint256 lpShares
    );
    event StakeToken(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed memberId,
        uint256 tokenAmount,
        uint256 promisedWaitingPhases,
        uint256 govVotesAdded,
        uint256 govVotes,
        uint256 boostSharesAdded,
        uint256 boostShares
    );
    event Unstake(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed memberId,
        uint256 promisedWaitingPhases,
        uint256 govVotes,
        uint256 lpShares,
        uint256 boostShares
    );
    event Withdraw(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed memberId,
        uint256 promisedWaitingPhases,
        uint256 lpShares,
        uint256 tokenAmountForLP,
        uint256 parentTokenAmountForLP,
        uint256 boostShares
    );

    error AlreadyInitialized();
    error NotAllowedToStakeAtRoundZero();
    error StakeAmountMustBeSet();
    error UnstakeAlreadyRequested();
    error UnstakeNotRequested();
    error PromisedWaitingPhasesOutOfRange();
    error PromisedWaitingPhasesMustBeGreaterOrEqualThanBefore();
    error NoStakedLiquidity();
    error NotEnoughWaitingBlocks();
    error RoundHasNotStartedYet();
}
