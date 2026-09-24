// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IProposalTarget} from "../core/IProposalTarget.sol";

interface IActionExecutor is IProposalTarget {
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);

    error RoundNotStarted();
}
