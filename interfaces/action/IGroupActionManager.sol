// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

struct GroupConfig {
    string description;
    uint256 maxCapacity;
    uint256 minJoinAmount;
    uint256 maxJoinAmount;
    uint256 maxAccounts;
}

interface IGroupActionManagerEvents {
    event ActivateGroup(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 round,
        uint256 indexed groupId,
        uint256 stakeAmount
    );
    event DeactivateGroup(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 round,
        uint256 indexed groupId,
        uint256 stakeAmount
    );
    event UpdateGroupInfo(
        address indexed tokenAddress,
        uint256 indexed actionId,
        uint256 round,
        uint256 indexed groupId,
        string description,
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount,
        uint256 maxAccounts
    );
}

interface IGroupActionManagerErrors {
    error GroupAlreadyActivated();
    error GroupNotActive();
    error InvalidMinMaxJoinAmount();
    error CannotDeactivateInActivatedRound();
    error OnlyGroupOwner();
    error InsufficientActivationMinGovRatio();
    error NoGovVotes();
}

interface IGroupActionManager is IGroupActionManagerEvents, IGroupActionManagerErrors {
    function activateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        GroupConfig calldata config
    ) external;

    function deactivateGroup(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external;

    function updateGroupInfo(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        GroupConfig calldata config
    ) external;

    function groupInfo(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    )
        external
        view
        returns (
            GroupConfig memory config,
            bool active,
            uint256 activatedRound,
            uint256 deactivatedRound
        );
}
