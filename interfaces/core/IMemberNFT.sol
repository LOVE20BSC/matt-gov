// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

/// @dev The target contract also inherits OpenZeppelin's ERC721Enumerable,
/// which supplies the standard ERC721 and enumerable API.
interface IMemberNFT {
    event Mint(
        uint256 indexed id,
        address indexed owner,
        string name,
        string normalizedName,
        uint256 cost
    );

    event AddHolder(address indexed holder, uint256 totalHolders);

    event RemoveHolder(address indexed holder, uint256 totalHolders);

    error NameAlreadyExists(uint256 existingId);
    error NameEmpty();
    error NameTooLong(uint256 length, uint256 maxLength);
    error NameInvalidCharacters();
    error HolderIndexOutOfBounds(uint256 length);

    error AlreadyInitialized();

    function LOVE20_TOKEN_ADDRESS() external view returns (address);

    function BASE_DIVISOR() external view returns (uint256);

    function BYTES_THRESHOLD() external view returns (uint256);

    function MULTIPLIER() external view returns (uint256);

    function MAX_NAME_LENGTH() external view returns (uint256);

    function initialized() external view returns (bool);

    function init(address firstTokenAddress) external;

    function mint(
        string calldata name
    ) external returns (uint256 id, uint256 mintCost);

    function calculateMintCost(
        string calldata name
    ) external view returns (uint256);

    function nameOf(uint256 id) external view returns (string memory);

    function isNameUsed(
        string calldata name
    ) external view returns (bool);

    function idOf(
        string calldata name
    ) external view returns (uint256);

    function normalizedNameOf(
        string calldata name
    ) external pure returns (string memory);

    function totalBurnedForMint() external view returns (uint256);

    function holdersCount() external view returns (uint256);

    function holdersAtIndex(uint256 index) external view returns (address);
}
