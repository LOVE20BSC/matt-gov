// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IMemberNFT {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function totalSupply() external view returns (uint256);
    function tokenByIndex(uint256 index) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function init(address firstTokenAddress) external;
    function mint(string calldata name) external returns (uint256 id, uint256 mintCost);
    function calculateMintCost(string calldata name) external view returns (uint256);
    function normalizedNameOf(string calldata name) external pure returns (string memory);
    function idOf(string calldata name) external view returns (uint256);
    function nameOf(uint256 id) external view returns (string memory);
    function isNameUsed(string calldata name) external view returns (bool);
    function firstTokenAddress() external view returns (address);
    function baseDivisor() external view returns (uint256);
    function bytesThreshold() external view returns (uint256);
    function multiplier() external view returns (uint256);
    function maxNameLength() external view returns (uint256);
    function totalBurnedForMint() external view returns (uint256);
    function holdersCount() external view returns (uint256);
    function holdersAtIndex(uint256 index) external view returns (address);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event Mint(
        uint256 indexed id,
        address indexed owner,
        string name,
        string normalizedName,
        uint256 cost
    );
    event AddHolder(address indexed holder, uint256 totalHolders);
    event RemoveHolder(address indexed holder, uint256 totalHolders);

    error AlreadyInitialized();
    error NameEmpty();
    error NameTooLong(uint256 length, uint256 maxLength);
    error NameInvalidCharacters();
    error NameAlreadyExists(uint256 existingId);
    error HolderIndexOutOfBounds(uint256 length);
}
