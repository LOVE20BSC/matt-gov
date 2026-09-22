// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IProposalTarget} from "../core/IProposalTarget.sol";

interface IActionExecutor is IProposalTarget {
    function exit(address tokenAddress, uint256 actionId, uint256 memberId) external;
}
