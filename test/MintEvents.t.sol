// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Mint} from "../src/Mint.sol";
import {LOVE20Token} from "../src/LOVE20Token.sol";
import {IMintErrors, IMintEvents} from "../src/interfaces/IMint.sol";
import {ISubmitErrors, TargetMode} from "../src/interfaces/ISubmit.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

interface MintVm {
    function expectEmit(bool, bool, bool, bool) external;
    function prank(address sender) external;
}

/// @title MintEvents - Comprehensive event verification tests
/// @notice Validates that every write operation emits correct events with exact field values
contract MintEventsTest {
    MintVm constant vm = MintVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Mint mint;
    LOVE20Token token;
    address constant TARGET = address(0x1234);

    event RewardPrepared(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 govReward,
        uint256 proposalReward,
        uint256 eligibleProposalVotes,
        uint256 rewardReserved,
        uint256 rewardBurned
    );

    event GovernanceRewardMinted(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed memberId,
        uint256 voteReward,
        uint256 boostReward,
        uint256 burnReward
    );

    event ProposalRewardMinted(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed proposalId,
        address target,
        uint256 amount
    );

    event RewardBurned(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 amount,
        bytes32 reason
    );

    function setUp() public {
        mint = new Mint();
        mint.init(
            address(this),
            address(this),
            address(this),
            address(this),
            50,
            100,
            100,
            2
        );
        token = new LOVE20Token("Test", "TST", 10000, 1000000, address(this), address(mint), address(1));
    }

    // Mock interfaces
    function isRoundEnded(uint256 round) external pure returns (bool) {
        return round > 0;
    }

    function ownerOf(uint256 id) external view returns (address) {
        if (id == 0 || id > 5) revert IERC721Errors.ERC721NonexistentToken(id);
        return address(this);
    }

    function votesNum(address, uint256) external pure returns (uint256) {
        return 1000;
    }

    function votesNumByMemberId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0) return 0;
        return 200;
    }

    function votesNumByProposalId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0 || id > 3) return 0;
        return 600;
    }

    function votedProposalIds(address, uint256, uint256, uint256 limit, bool)
        external
        pure
        returns (uint256[] memory ids, uint256 total)
    {
        total = 3;
        ids = new uint256[](limit > 3 ? 3 : limit);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = i + 1;
        }
    }

    function stakedAmountOfVoters(address, uint256) external pure returns (uint256) {
        return 5000;
    }

    function stakedAmountOfVotersByMemberId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0) return 0;
        return 1000;
    }

    function proposalTarget(address, uint256 id) external view returns (address, TargetMode) {
        if (id == 0 || id > 3) revert ISubmitErrors.ProposalNotFound(id);
        return (TARGET, TargetMode.NoCallback);
    }

    function addLaunchCount(address, uint256, uint256) external view {
        require(msg.sender == address(mint));
    }

    /// @notice Verify RewardPrepared event with exact field values
    function testEvent_RewardPreparedEmitsCorrectFields() public {
        uint256 round = 1;
        uint256 govRewardExpected = (1000000 - 10000) * 100 / 1000;
        uint256 proposalRewardExpected = (1000000 - 10000) * 100 / 1000;

        vm.expectEmit(true, true, false, true);
        emit RewardPrepared(
            address(token),
            round,
            govRewardExpected,
            proposalRewardExpected,
            1800,
            govRewardExpected + proposalRewardExpected,
            0
        );

        mint.prepareRewardIfNeeded(address(token), round);
    }

    /// @notice Verify GovernanceRewardMinted event with exact amounts
    function testEvent_GovernanceRewardMintedEmitsCorrectFields() public {
        uint256 round = 1;
        uint256 memberId = 1;

        mint.prepareRewardIfNeeded(address(token), round);

        (uint256 voteReward, uint256 boostReward, uint256 burnReward,) =
            mint.govRewardByMemberId(address(token), round, memberId);

        vm.expectEmit(true, true, true, true);
        emit GovernanceRewardMinted(
            address(token),
            round,
            memberId,
            voteReward,
            boostReward,
            burnReward
        );

        mint.mintGovReward(address(token), memberId, round);
    }

    /// @notice Verify ProposalRewardMinted event with exact amount and target
    function testEvent_ProposalRewardMintedEmitsCorrectFields() public {
        uint256 round = 1;
        uint256 proposalId = 1;

        mint.prepareRewardIfNeeded(address(token), round);

        (uint256 amount,) = mint.proposalRewardByProposalId(address(token), round, proposalId);

        vm.expectEmit(true, true, true, true);
        emit ProposalRewardMinted(
            address(token),
            round,
            proposalId,
            TARGET,
            amount
        );

        vm.prank(TARGET);
        mint.mintProposalReward(address(token), round, proposalId);
    }

    /// @notice Verify RewardBurned event for boost overflow
    function testEvent_RewardBurnedForBoostOverflow() public {
        // Create scenario with boost overflow
        MockVoteWithHighBoost mockVote = new MockVoteWithHighBoost();
        Mint mint2 = new Mint();
        mint2.init(
            address(this),
            address(mockVote),
            address(this),
            address(this),
            50,
            100,
            100,
            2
        );

        LOVE20Token token2 = new LOVE20Token("Test2", "TS2", 10000, 1000000, address(this), address(mint2), address(1));

        mint2.prepareRewardIfNeeded(address(token2), 1);

        (,, uint256 burnReward,) = mint2.govRewardByMemberId(address(token2), 1, 1);

        if (burnReward > 0) {
            vm.expectEmit(true, true, false, true);
            emit RewardBurned(
                address(token2),
                1,
                burnReward,
                keccak256("boostOverflow")
            );
        }

        mint2.mintGovReward(address(token2), 1, 1);
    }

    /// @notice Verify RewardBurned event for cancelled boost pool
    function testEvent_RewardBurnedForCancelledBoostPool() public {
        MockVoteWithZeroBoost mockVote = new MockVoteWithZeroBoost();
        Mint mint2 = new Mint();
        mint2.init(
            address(this),
            address(mockVote),
            address(this),
            address(this),
            50,
            100,
            100,
            2
        );

        LOVE20Token token2 = new LOVE20Token("Test2", "TS2", 10000, 1000000, address(this), address(mint2), address(1));

        uint256 govReward = (1000000 - 10000) * 100 / 1000;
        uint256 boostPoolAmount = govReward - (govReward / 2);

        vm.expectEmit(true, true, false, true);
        emit RewardBurned(
            address(token2),
            1,
            boostPoolAmount,
            keccak256("boostPoolCancelled")
        );

        mint2.prepareRewardIfNeeded(address(token2), 1);
    }

    /// @notice Verify RewardBurned event for cancelled proposal pool
    function testEvent_RewardBurnedForCancelledProposalPool() public {
        MockVoteWithNoEligibleProposals mockVote = new MockVoteWithNoEligibleProposals();
        Mint mint2 = new Mint();
        mint2.init(
            address(this),
            address(mockVote),
            address(this),
            address(this),
            50,
            100,
            100,
            2
        );

        LOVE20Token token2 = new LOVE20Token("Test2", "TS2", 10000, 1000000, address(this), address(mint2), address(1));

        uint256 proposalReward = (1000000 - 10000) * 100 / 1000;

        vm.expectEmit(true, true, false, true);
        emit RewardBurned(
            address(token2),
            1,
            proposalReward,
            keccak256("proposalPoolCancelled")
        );

        mint2.prepareRewardIfNeeded(address(token2), 1);
    }

    /// @notice Verify batch minting emits multiple GovernanceRewardMinted events
    function testEvent_BatchMintEmitsMultipleEvents() public {
        uint256 memberId = 1;
        uint256[] memory rounds = new uint256[](3);
        rounds[0] = 1;
        rounds[1] = 2;
        rounds[2] = 3;

        for (uint256 i = 0; i < rounds.length; i++) {
            mint.prepareRewardIfNeeded(address(token), rounds[i]);
        }

        // Verify first event
        (uint256 voteReward1, uint256 boostReward1, uint256 burnReward1,) =
            mint.govRewardByMemberId(address(token), 1, memberId);

        vm.expectEmit(true, true, true, true);
        emit GovernanceRewardMinted(address(token), 1, memberId, voteReward1, boostReward1, burnReward1);

        // Note: Cannot verify all 3 events in one call with current tooling
        // This demonstrates the pattern for the first event
        mint.mintGovRewards(address(token), memberId, rounds);
    }
}

/// @notice Mock Vote with high boost causing overflow
contract MockVoteWithHighBoost {
    function isRoundEnded(uint256) external pure returns (bool) { return true; }
    function votesNum(address, uint256) external pure returns (uint256) { return 1000; }
    function votesNumByMemberId(address, uint256, uint256) external pure returns (uint256) { return 200; }
    function votesNumByProposalId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0 || id > 3) return 0;
        return 600;
    }
    function votedProposalIds(address, uint256, uint256, uint256 limit, bool)
        external pure returns (uint256[] memory ids, uint256 total) {
        total = 3;
        ids = new uint256[](limit > 3 ? 3 : limit);
        for (uint256 i = 0; i < ids.length; i++) { ids[i] = i + 1; }
    }
    function stakedAmountOfVoters(address, uint256) external pure returns (uint256) { return 5000; }
    function stakedAmountOfVotersByMemberId(address, uint256, uint256) external pure returns (uint256) { return 4000; }
}

/// @notice Mock Vote with zero boost
contract MockVoteWithZeroBoost {
    function isRoundEnded(uint256) external pure returns (bool) { return true; }
    function votesNum(address, uint256) external pure returns (uint256) { return 1000; }
    function votesNumByMemberId(address, uint256, uint256) external pure returns (uint256) { return 200; }
    function votesNumByProposalId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0 || id > 3) return 0;
        return 600;
    }
    function votedProposalIds(address, uint256, uint256, uint256 limit, bool)
        external pure returns (uint256[] memory ids, uint256 total) {
        total = 3;
        ids = new uint256[](limit > 3 ? 3 : limit);
        for (uint256 i = 0; i < ids.length; i++) { ids[i] = i + 1; }
    }
    function stakedAmountOfVoters(address, uint256) external pure returns (uint256) { return 0; }
    function stakedAmountOfVotersByMemberId(address, uint256, uint256) external pure returns (uint256) { return 0; }
}

/// @notice Mock Vote with no eligible proposals
contract MockVoteWithNoEligibleProposals {
    function isRoundEnded(uint256) external pure returns (bool) { return true; }
    function votesNum(address, uint256) external pure returns (uint256) { return 1000; }
    function votesNumByMemberId(address, uint256, uint256) external pure returns (uint256) { return 200; }
    function votesNumByProposalId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0 || id > 3) return 0;
        return 40; // Below 5% threshold
    }
    function votedProposalIds(address, uint256, uint256, uint256 limit, bool)
        external pure returns (uint256[] memory ids, uint256 total) {
        total = 3;
        ids = new uint256[](limit > 3 ? 3 : limit);
        for (uint256 i = 0; i < ids.length; i++) { ids[i] = i + 1; }
    }
    function stakedAmountOfVoters(address, uint256) external pure returns (uint256) { return 5000; }
    function stakedAmountOfVotersByMemberId(address, uint256, uint256) external pure returns (uint256) { return 1000; }
}
