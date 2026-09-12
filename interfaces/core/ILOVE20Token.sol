// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

/// @dev The target contract inherits OpenZeppelin's ERC20.

interface ILOVE20TokenEvents {
    event TokenMint(address indexed to, uint256 amount);
    event TokenBurn(address indexed from, uint256 amount);
    event BurnForParentToken(
        address indexed burner,
        uint256 burnAmount,
        uint256 parentTokenAmount
    );
}

interface ILOVE20TokenErrors {
    error InvalidAddress();
    error NotMinter();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidSupply();
}

interface ILOVE20Token is
    ILOVE20TokenEvents,
    ILOVE20TokenErrors
{
    function maxSupply() external view returns (uint256);

    function minter() external view returns (address);

    function parentTokenAddress() external view returns (address);

    function parentPool() external view returns (uint256);

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnForParentToken(
        uint256 amount
    ) external returns (uint256 parentTokenAmount);
}
