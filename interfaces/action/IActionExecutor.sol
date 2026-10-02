// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IProposalTarget} from "core/src/interfaces/IProposalTarget.sol";

interface IActionExecutorErrors {
    error RoundNotStarted();
}

interface IActionExecutor is IProposalTarget, IActionExecutorErrors {
    function actionTarget() external view returns (address);

    function initialized() external view returns (bool);

    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;

    function currentVoteRound() external view returns (uint256);
    function currentJoinRound() external view returns (uint256);
    function currentMintRound() external view returns (uint256);
}
