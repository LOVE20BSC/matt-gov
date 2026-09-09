// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IProposalTarget {
    function onProposalCreated(
        address tokenAddress,
        uint256 proposalId,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external;
    function onProposalSubmitted(
        address tokenAddress,
        uint256 proposalId,
        uint256 submitterId,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external;
    function onProposalVoted(
        address tokenAddress,
        uint256 proposalId,
        uint256 voterId,
        uint256 votes,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external;
}
