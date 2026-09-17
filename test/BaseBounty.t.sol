// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseBounty} from "../src/BaseBounty.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract BaseBountyTest is Test {
    BaseBounty internal bounty;
    MockUSDC internal usdc;

    address internal treasury = makeAddr("treasury");
    address internal poster = makeAddr("poster");
    address internal agent = makeAddr("agent");
    address internal other = makeAddr("other");

    uint256 internal constant ESCROW = 10e6; // 10 USDC
    uint256 internal constant FEE = 0.1e6;

    function setUp() public {
        usdc = new MockUSDC();
        bounty = new BaseBounty(address(usdc), treasury);

        usdc.mint(poster, 1_000e6);
        usdc.mint(agent, 100e6);
        vm.prank(poster);
        usdc.approve(address(bounty), type(uint256).max);
    }

    function _post(uint256 escrow, uint256 timeout) internal returns (uint256 id) {
        vm.prank(poster);
        id = bounty.post("Fix bug", "Details here", escrow, timeout);
    }

    function test_PostFeeMath_FeeToTreasuryEscrowLocked() public {
        uint256 posterBefore = usdc.balanceOf(poster);
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        uint256 id = _post(ESCROW, 1 days);

        assertEq(usdc.balanceOf(poster), posterBefore - FEE - ESCROW);
        assertEq(usdc.balanceOf(treasury), treasuryBefore + FEE);
        assertEq(usdc.balanceOf(address(bounty)), ESCROW);

        (,, uint256 escrow,, BaseBounty.Status status,,,) = bounty.getBounty(id);
        assertEq(escrow, ESCROW);
        assertEq(uint8(status), uint8(BaseBounty.Status.Open));
        assertEq(bounty.POST_FEE(), FEE);
    }

    function test_SettleSplit_5Percent() public view {
        (uint256 toAgent, uint256 toTreasury) = bounty.settleSplit(ESCROW);
        assertEq(toTreasury, 0.5e6); // 5% of 10
        assertEq(toAgent, 9.5e6);
    }

    function test_Release_CutsTreasuryPaysAgent() public {
        uint256 id = _post(ESCROW, 1 days);

        vm.prank(agent);
        bounty.bid(id);

        vm.prank(agent);
        bounty.submitDelivery(id, "ipfs://QmDelivery");

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 agentBefore = usdc.balanceOf(agent);

        vm.prank(poster);
        bounty.release(id);

        assertEq(usdc.balanceOf(treasury), treasuryBefore + 0.5e6);
        assertEq(usdc.balanceOf(agent), agentBefore + 9.5e6);
        assertEq(usdc.balanceOf(address(bounty)), 0);

        (,,,, BaseBounty.Status status,,,) = bounty.getBounty(id);
        assertEq(uint8(status), uint8(BaseBounty.Status.Released));
    }

    function test_Release_FromBidWithoutSubmit() public {
        uint256 id = _post(ESCROW, 1 days);
        vm.prank(agent);
        bounty.bid(id);

        vm.prank(poster);
        bounty.release(id);

        assertEq(usdc.balanceOf(agent), 100e6 + 9.5e6);
    }

    function test_Refund_AfterTimeout_FullEscrowToPoster_FeeKept() public {
        uint256 id = _post(ESCROW, 1 hours);
        uint256 treasuryAfterPost = usdc.balanceOf(treasury);
        assertEq(treasuryAfterPost, FEE);

        uint256 posterBefore = usdc.balanceOf(poster);
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(other);
        bounty.refund(id);

        assertEq(usdc.balanceOf(poster), posterBefore + ESCROW);
        assertEq(usdc.balanceOf(treasury), FEE); // fee non-refundable
        assertEq(usdc.balanceOf(address(bounty)), 0);

        (,,,, BaseBounty.Status status,,,) = bounty.getBounty(id);
        assertEq(uint8(status), uint8(BaseBounty.Status.Refunded));
    }

    function test_Refund_RevertsBeforeDeadline() public {
        uint256 id = _post(ESCROW, 1 days);
        vm.expectRevert(BaseBounty.DeadlineNotPassed.selector);
        bounty.refund(id);
    }

    function test_BidIsFree() public {
        uint256 id = _post(ESCROW, 1 days);
        uint256 agentBefore = usdc.balanceOf(agent);
        vm.prank(agent);
        bounty.bid(id);
        assertEq(usdc.balanceOf(agent), agentBefore);

        (, address a,,, BaseBounty.Status status,,,) = bounty.getBounty(id);
        assertEq(a, agent);
        assertEq(uint8(status), uint8(BaseBounty.Status.Bid));
    }

    function test_PosterCannotBidOwn() public {
        uint256 id = _post(ESCROW, 1 days);
        vm.prank(poster);
        vm.expectRevert(BaseBounty.InvalidAddress.selector);
        bounty.bid(id);
    }

    function test_OnlyAgentSubmits() public {
        uint256 id = _post(ESCROW, 1 days);
        vm.prank(agent);
        bounty.bid(id);
        vm.prank(other);
        vm.expectRevert(BaseBounty.NotAgent.selector);
        bounty.submitDelivery(id, "ipfs://x");
    }

    function test_OnlyPosterReleases() public {
        uint256 id = _post(ESCROW, 1 days);
        vm.prank(agent);
        bounty.bid(id);
        vm.prank(agent);
        vm.expectRevert(BaseBounty.NotPoster.selector);
        bounty.release(id);
    }

    function test_CannotPostZeroEscrow() public {
        vm.prank(poster);
        vm.expectRevert(BaseBounty.InvalidAmount.selector);
        bounty.post("t", "d", 0, 1 days);
    }

    function test_FeeNotRefundedOnTimeoutWithBid() public {
        uint256 id = _post(ESCROW, 30 minutes);
        vm.prank(agent);
        bounty.bid(id);
        vm.prank(agent);
        bounty.submitDelivery(id, "https://gist.github.com/example");

        vm.warp(block.timestamp + 31 minutes);
        uint256 posterBal = usdc.balanceOf(poster);
        bounty.refund(id);
        assertEq(usdc.balanceOf(poster), posterBal + ESCROW);
        assertEq(usdc.balanceOf(treasury), FEE);
    }
}
