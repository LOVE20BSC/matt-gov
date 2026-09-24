// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IVerificationInfo {
    // Action level: Verification info schema (defined by the creator when submitting a proposal)
    function verificationSchema(
        address tokenAddress,
        uint256 actionId
    )
        external
        view
        returns (string[] memory keys, string[] memory descriptions);

    // Member level: Current value for a single key
    function verificationValue(
        address tokenAddress,
        uint256 actionId,
        uint256 memberId,
        string calldata key
    ) external view returns (string memory value);

    // Member level: Current values for all verification info
    function verificationInfos(
        address tokenAddress,
        uint256 actionId,
        uint256 memberId
    ) external view returns (string[] memory keys, string[] memory values);

    // Member level: Historical snapshot for a specified round
    function verificationInfosByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 memberId,
        uint256 round
    ) external view returns (string[] memory keys, string[] memory values);
}
