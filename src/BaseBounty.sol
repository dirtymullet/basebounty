// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BaseBounty — thin USDC escrow for agent bounties on Base
/// @notice Post fee 0.10 USDC (non-refundable). Settle cut 5% of escrow to treasury.
contract BaseBounty is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant POST_FEE = 0.1e6; // 0.10 USDC (6 decimals)
    uint256 public constant SETTLE_BPS = 500; // 5%
    uint256 public constant BPS_DENOM = 10_000;
    uint256 public constant DEFAULT_TIMEOUT = 7 days;

    IERC20 public immutable usdc;
    address public immutable treasury;

    enum Status {
        None,
        Open,
        Bid,
        Submitted,
        Released,
        Refunded
    }

    struct Bounty {
        address poster;
        address agent;
        uint256 escrow;
        uint64 deadline;
        Status status;
        string title;
        string description;
        string deliveryUri;
    }

    uint256 public nextId = 1;
    mapping(uint256 => Bounty) public bounties;

    event BountyPosted(
        uint256 indexed id,
        address indexed poster,
        uint256 escrow,
        uint64 deadline,
        string title
    );
    event BidPlaced(uint256 indexed id, address indexed agent);
    event DeliverySubmitted(uint256 indexed id, address indexed agent, string deliveryUri);
    event Released(uint256 indexed id, address indexed agent, uint256 agentAmount, uint256 treasuryCut);
    event Refunded(uint256 indexed id, address indexed poster, uint256 amount);

    error InvalidAmount();
    error InvalidAddress();
    error BadStatus();
    error NotPoster();
    error NotAgent();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error EmptyString();

    constructor(address usdc_, address treasury_) {
        if (usdc_ == address(0) || treasury_ == address(0)) revert InvalidAddress();
        usdc = IERC20(usdc_);
        treasury = treasury_;
    }

    /// @notice Pay POST_FEE (to treasury) + lock `escrow` USDC. Fee is non-refundable.
    function post(
        string calldata title,
        string calldata description,
        uint256 escrow,
        uint256 timeoutSeconds
    ) external nonReentrant returns (uint256 id) {
        if (escrow == 0) revert InvalidAmount();
        if (bytes(title).length == 0) revert EmptyString();
        uint256 timeout = timeoutSeconds == 0 ? DEFAULT_TIMEOUT : timeoutSeconds;
        uint256 total = POST_FEE + escrow;
        usdc.safeTransferFrom(msg.sender, address(this), total);
        usdc.safeTransfer(treasury, POST_FEE);

        id = nextId++;
        uint64 deadline = uint64(block.timestamp + timeout);
        bounties[id] = Bounty({
            poster: msg.sender,
            agent: address(0),
            escrow: escrow,
            deadline: deadline,
            status: Status.Open,
            title: title,
            description: description,
            deliveryUri: ""
        });
        emit BountyPosted(id, msg.sender, escrow, deadline, title);
    }

    /// @notice Agent bid is free (no USDC).
    function bid(uint256 id) external nonReentrant {
        Bounty storage b = bounties[id];
        if (b.status != Status.Open) revert BadStatus();
        if (block.timestamp > b.deadline) revert DeadlinePassed();
        if (msg.sender == b.poster) revert InvalidAddress();
        b.agent = msg.sender;
        b.status = Status.Bid;
        emit BidPlaced(id, msg.sender);
    }

    function submitDelivery(uint256 id, string calldata deliveryUri) external nonReentrant {
        Bounty storage b = bounties[id];
        if (b.status != Status.Bid && b.status != Status.Submitted) revert BadStatus();
        if (msg.sender != b.agent) revert NotAgent();
        if (block.timestamp > b.deadline) revert DeadlinePassed();
        if (bytes(deliveryUri).length == 0) revert EmptyString();
        b.deliveryUri = deliveryUri;
        b.status = Status.Submitted;
        emit DeliverySubmitted(id, msg.sender, deliveryUri);
    }

    /// @notice Poster releases escrow: 5% treasury, 95% agent.
    function release(uint256 id) external nonReentrant {
        Bounty storage b = bounties[id];
        if (b.status != Status.Submitted && b.status != Status.Bid) revert BadStatus();
        if (msg.sender != b.poster) revert NotPoster();
        if (b.agent == address(0)) revert InvalidAddress();

        uint256 escrow = b.escrow;
        uint256 cut = (escrow * SETTLE_BPS) / BPS_DENOM;
        uint256 toAgent = escrow - cut;
        b.escrow = 0;
        b.status = Status.Released;

        if (cut > 0) usdc.safeTransfer(treasury, cut);
        usdc.safeTransfer(b.agent, toAgent);
        emit Released(id, b.agent, toAgent, cut);
    }

    /// @notice After deadline, poster (or anyone) refunds full escrow to poster. Fee stays with treasury.
    function refund(uint256 id) external nonReentrant {
        Bounty storage b = bounties[id];
        if (
            b.status != Status.Open && b.status != Status.Bid && b.status != Status.Submitted
        ) revert BadStatus();
        if (block.timestamp <= b.deadline) revert DeadlineNotPassed();

        uint256 amount = b.escrow;
        address poster = b.poster;
        b.escrow = 0;
        b.status = Status.Refunded;
        usdc.safeTransfer(poster, amount);
        emit Refunded(id, poster, amount);
    }

    function getBounty(uint256 id)
        external
        view
        returns (
            address poster,
            address agent,
            uint256 escrow,
            uint64 deadline,
            Status status,
            string memory title,
            string memory description,
            string memory deliveryUri
        )
    {
        Bounty storage b = bounties[id];
        return (
            b.poster,
            b.agent,
            b.escrow,
            b.deadline,
            b.status,
            b.title,
            b.description,
            b.deliveryUri
        );
    }

    function settleSplit(uint256 escrow) external pure returns (uint256 toAgent, uint256 toTreasury) {
        toTreasury = (escrow * SETTLE_BPS) / BPS_DENOM;
        toAgent = escrow - toTreasury;
    }
}
