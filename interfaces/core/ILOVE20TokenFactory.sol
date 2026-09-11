// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILOVE20TokenFactory {
    error AlreadyInitialized();
    error InvalidAddress();
    error EmptyString();
    error InvalidSupply();
    error UnauthorizedCaller();

    event TokenCreated(
        address indexed tokenAddress,
        address indexed parentTokenAddress,
        string name,
        string symbol,
        address distributor
    );

    function init(
        address pairFactoryAddress,
        address launchAddress,
        address mintAddress,
        uint256 initialSupply,
        uint256 maxSupply
    ) external;
    function createToken(
        address parentTokenAddress,
        string calldata name,
        string calldata symbol,
        address distributor
    ) external returns (address tokenAddress);
    function pairFactoryAddress() external view returns (address);
    function launchAddress() external view returns (address);
    function mintAddress() external view returns (address);
    function initialSupply() external view returns (uint256);
    function maxSupply() external view returns (uint256);
}
