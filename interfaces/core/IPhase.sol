// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPhase {
    function originBlocks() external view returns (uint256);
    function originPhaseBlocks() external view returns (uint256);
    function targetSeconds() external view returns (uint256);
    function adjustThreshold() external view returns (uint256);
    function currentPhaseBlocks() external view returns (uint256);
    function currentPhase() external view returns (uint256);
    function phaseInfo(uint256 phaseNumber)
        external view returns (uint256 startBlock, uint256 phaseBlocks_);
    function phaseAtBlock(uint256 blockNumber) external view returns (uint256);
    function syncObservationsCount() external view returns (uint256);
    function syncObservation(uint256 observationId)
        external view returns (uint256 blockNumber, uint256 blockTimestamp);
    function sync() external returns (bool adjusted, uint256 newPhaseBlocks);

    event PhaseSynchronized(
        uint256 indexed phase,
        uint256 blockNumber,
        uint256 timestamp,
        bool adjusted,
        uint256 phaseBlocks
    );
    event PhaseAdjusted(
        uint256 indexed effectivePhase,
        uint256 oldPhaseBlocks,
        uint256 newPhaseBlocks
    );

    error InvalidPhase(uint256 phaseNumber);
    error ObservationNotFound(uint256 observationId);
}
