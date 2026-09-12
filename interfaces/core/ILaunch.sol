// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

enum DistributorMode { NoCallback, Callback }

interface ILaunch {
    function init(
        address tokenFactory,
        address mint,
        address memberNFT,
        address rootParentToken,
        address distributor,
        uint256 launchRatio,
        uint256 maxLaunchCount,
        uint256 tokenSymbolLength,
        string calldata name,
        string calldata symbol
    ) external;
    function tokenFactoryAddress() external view returns (address);
    function mintAddress() external view returns (address);
    function memberNFTAddress() external view returns (address);
    function rootParentTokenAddress() external view returns (address);
    function LAUNCH_RATIO() external view returns (uint256);
    function MAX_LAUNCH_COUNT() external view returns (uint256);
    function TOKEN_SYMBOL_LENGTH() external view returns (uint256);
    function launchToken(
        string calldata tokenSymbol,
        address parentTokenAddress,
        uint256 memberId,
        address distributor,
        DistributorMode distributorMode,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external returns (address tokenAddress);
    function mergeLaunchCount(
        address tokenAddress,
        uint256 sourceMemberId,
        uint256 targetMemberId,
        uint256 count
    ) external;
    function addLaunchCount(address tokenAddress, uint256 memberId, uint256 count) external;
    function launchCount(address tokenAddress, uint256 memberId) external view returns (uint256);
    function issuedLaunchCount(address tokenAddress) external view returns (uint256);
    function isLOVE20Token(address tokenAddress) external view returns (bool);

    event LaunchToken(
        address indexed tokenAddress,
        address indexed parentTokenAddress,
        uint256 indexed launcherMemberId,
        address distributor
    );
    event LaunchCountAdded(address indexed tokenAddress, uint256 indexed memberId, uint256 count);
    event LaunchCountMerged(
        address indexed tokenAddress,
        uint256 indexed sourceMemberId,
        uint256 indexed targetMemberId,
        uint256 count
    );
    event LaunchCountConsumed(address indexed tokenAddress, uint256 indexed memberId, uint256 count);

    error AlreadyInitialized();
    error InvalidAddress();
    error InvalidKVLength();
    error InvalidTokenSymbol();
    error InvalidDistributorMode();
    error UnauthorizedCaller();
    error NotMemberOwner(uint256 memberId);
    error NotEnoughLaunchCount();
    error LaunchCountLimitReached();
}
