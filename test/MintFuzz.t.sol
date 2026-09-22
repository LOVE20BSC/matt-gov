// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Mint} from "../src/Mint.sol";
import {LOVE20Token} from "../src/LOVE20Token.sol";
import {IMintErrors} from "../src/interfaces/IMint.sol";
import {ISubmitErrors, TargetMode} from "../src/interfaces/ISubmit.sol";
import {IERC721Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

interface MintVm {
    function assume(bool condition) external pure;
    function bound(uint256 x, uint256 min, uint256 max) external pure returns (uint256);
    function expectRevert(bytes calldata data) external;
    function prank(address sender) external;
}

/// @title MintFuzz - Fuzzing tests for Mint contract
/// @notice Industry-standard fuzz testing covering random supply, votes, and stake amounts
contract MintFuzzTest {
    MintVm constant vm = MintVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Mint mint;
    LOVE20Token token;
    address constant TARGET = address(0x1234);

    function setupMint(uint256 supply, uint256 maxSupply) internal {
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
        token = new LOVE20Token("Test", "TST", supply, maxSupply, address(this), address(mint), address(1));
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
        if (id == 0 || id > 5) return 0;
        return 200;
    }

    function votesNumByProposalId(address, uint256, uint256 id) external pure returns (uint256) {
        if (id == 0 || id > 3) return 0;
        return 100;
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
        if (id == 0 || id > 5) return 0;
        return 1000;
    }

    function proposalTarget(address, uint256 id) external view returns (address, TargetMode) {
        if (id == 0 || id > 3) revert ISubmitErrors.ProposalNotFound(id);
        return (TARGET, TargetMode.NoCallback);
    }

    function addLaunchCount(address, uint256, uint256) external view {
        require(msg.sender == address(mint));
    }

    /// @notice Fuzz: prepare with random supply combinations
    function testFuzz_PrepareWithRandomSupply(uint96 supply, uint96 maxSupply) public {
        supply = uint96(vm.bound(supply, 1000, type(uint96).max / 2));
        maxSupply = uint96(vm.bound(maxSupply, supply + 1, type(uint96).max));

        setupMint(supply, maxSupply);
        mint.prepareRewardIfNeeded(address(token), 1);

        uint256 govReward = mint.govReward(address(token), 1);
        uint256 proposalReward = mint.proposalReward(address(token), 1);
        uint256 reserved = mint.rewardReserved(address(token));

        // Invariant: reserved equals sum of prepared rewards
        assertEq(reserved, govReward + proposalReward, "reserved mismatch");
    }

    /// @notice Fuzz: governance settlement with random vote distribution
    function testFuzz_GovSettlementWithRandomVotes(uint8 memberIdRaw, uint96 memberVotesRaw, uint96 totalVotesRaw) public {
        uint256 memberId = vm.bound(memberIdRaw, 1, 5);
        uint256 memberVotes = vm.bound(memberVotesRaw, 1, 10000);
        uint256 totalVotes = vm.bound(totalVotesRaw, memberVotes, 100000);

        setupMint(10000, 1000000);

        // Mock with fuzzed values
        MockVoteForFuzz mockVote = new MockVoteForFuzz(totalVotes, memberVotes);
        mint.init(
            address(this),
            address(mockVote),
            address(this),
            address(this),
            50,
            100,
            100,
            2
        );

        mint.prepareRewardIfNeeded(address(token), 1);

        uint256 govReward = mint.govReward(address(token), 1);
        if (govReward == 0) return;

        (uint256 voteReward, uint256 boostReward, uint256 burnReward,) =
            mint.govRewardByMemberId(address(token), 1, memberId);

        // Invariant: sum never exceeds available gov pool
        assertLe(voteReward + boostReward, govReward, "exceeds gov pool");
    }

    /// @notice Fuzz: proposal reward calculation with random votes
    function testFuzz_ProposalRewardWithRandomVotes(uint96 proposalVotesRaw, uint96 totalVotesRaw) public {
        uint256 proposalVotes = vm.bound(proposalVotesRaw, 1, 10000);
        uint256 totalVotes = vm.bound(totalVotesRaw, proposalVotes, 100000);

        setupMint(10000, 1000000);

        MockVoteForFuzz mockVote = new MockVoteForFuzz(totalVotes, 0);
        mockVote.setProposalVotes(proposalVotes);
        mint.init(
            address(this),
            address(mockVote),
            address(this),
            address(this),
            50,
            100,
            100,
            2
        );

        mint.prepareRewardIfNeeded(address(token), 1);

        uint256 proposalReward = mint.proposalReward(address(token), 1);
        if (proposalReward == 0) return;

        (uint256 amount,) = mint.proposalRewardByProposalId(address(token), 1, 1);

        // Invariant: individual reward never exceeds pool
        assertLe(amount, proposalReward, "exceeds proposal pool");
    }

    /// @notice Fuzz: multiple prepare calls should be idempotent
    function testFuzz_PrepareIdempotency(uint8 callCount) public {
        callCount = uint8(vm.bound(callCount, 2, 10));
        setupMint(10000, 1000000);

        for (uint256 i = 0; i < callCount; i++) {
            mint.prepareRewardIfNeeded(address(token), 1);
        }

        uint256 govReward = mint.govReward(address(token), 1);
        uint256 proposalReward = mint.proposalReward(address(token), 1);

        // Another prepare should not change rewards
        mint.prepareRewardIfNeeded(address(token), 1);

        assertEq(mint.govReward(address(token), 1), govReward, "gov changed");
        assertEq(mint.proposalReward(address(token), 1), proposalReward, "proposal changed");
    }

    /// @notice Fuzz: available supply calculation
    function testFuzz_AvailableSupplyCalculation(uint96 supply, uint96 maxSupply, uint8 prepareCount) public {
        supply = uint96(vm.bound(supply, 1000, type(uint96).max / 4));
        maxSupply = uint96(vm.bound(maxSupply, supply * 2, type(uint96).max / 2));
        prepareCount = uint8(vm.bound(prepareCount, 1, 5));

        setupMint(supply, maxSupply);

        uint256 initialAvailable = mint.rewardAvailable(address(token));
        assertEq(initialAvailable, maxSupply - supply, "initial available mismatch");

        for (uint256 i = 1; i <= prepareCount; i++) {
            mint.prepareRewardIfNeeded(address(token), i);
        }

        uint256 reserved = mint.rewardReserved(address(token));
        uint256 finalAvailable = mint.rewardAvailable(address(token));

        // Invariant: available + reserved + supply = maxSupply
        assertEq(finalAvailable + reserved + supply, maxSupply, "supply accounting broken");
    }
}

/// @notice Mock Vote contract for fuzzing with configurable values
contract MockVoteForFuzz {
    uint256 public immutable _totalVotes;
    uint256 public immutable _memberVotes;
    uint256 public _proposalVotes;

    constructor(uint256 totalVotes_, uint256 memberVotes_) {
        _totalVotes = totalVotes_;
        _memberVotes = memberVotes_;
        _proposalVotes = 100;
    }

    function setProposalVotes(uint256 votes) external {
        _proposalVotes = votes;
    }

    function isRoundEnded(uint256 round) external pure returns (bool) {
        return round > 0;
    }

    function votesNum(address, uint256) external view returns (uint256) {
        return _totalVotes;
    }

    function votesNumByMemberId(address, uint256, uint256) external view returns (uint256) {
        return _memberVotes;
    }

    function votesNumByProposalId(address, uint256, uint256 id) external view returns (uint256) {
        if (id == 0 || id > 3) return 0;
        return _proposalVotes;
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

    function stakedAmountOfVotersByMemberId(address, uint256, uint256) external pure returns (uint256) {
        return 1000;
    }
}
