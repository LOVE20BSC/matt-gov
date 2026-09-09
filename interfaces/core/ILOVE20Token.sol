// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface ILOVE20Token {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function maxSupply() external view returns (uint256);
    function minter() external view returns (address);
    function parentTokenAddress() external view returns (address);
    function parentPool() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnForParentToken(uint256 amount)
        external returns (uint256 parentTokenAmount);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokenMint(address indexed to, uint256 amount);
    event TokenBurn(address indexed from, uint256 amount);
    event BurnForParentToken(
        address indexed burner,
        uint256 burnAmount,
        uint256 parentTokenAmount
    );

    error InvalidAddress();
    error NotMinter();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidSupply();
}
