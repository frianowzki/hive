// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/agent/HiveAgent.sol";
import "../src/auction/CCAEngine.sol";
import "../src/reputation/HiveReputation.sol";
import "../src/multisig/HiveMultiSig.sol";
import "../src/portfolio/HivePortfolio.sol";
import "../src/referral/HiveReferral.sol";
import "../src/strategy/HiveAutoStrategy.sol";
import "../src/chat/HiveChat.sol";

// ═══ HiveAgent Test ═══

contract HiveAgentTest is Test {
    HiveAgent agent;

    function setUp() public {
        agent = new HiveAgent();
    }

    function test_constructor() public {
        assertEq(agent.owner(), address(this));
        assertFalse(agent.paused());
    }

    function test_setPaused() public {
        agent.setPaused(true);
        assertTrue(agent.paused());
        agent.setPaused(false);
        assertFalse(agent.paused());
    }

    function test_revert_not_owner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("HiveAgent: not owner");
        agent.setPaused(true);
    }
}

// ═══ CCAEngine Test ═══

contract CCAEngineTest is Test {
    CCAEngine cca;
    address creator = address(0x1);
    address buyer1 = address(0x2);
    address tokenAddr = address(0x3);

    function setUp() public {
        cca = new CCAEngine();
    }

    function test_createAuction() public {
        vm.prank(creator);
        uint256 id = cca.createAuction(tokenAddr, 1000e18, 0.001 ether, 0.1 ether, 1 days, 10);

        CCAEngine.Auction memory a = cca.getAuction(id);
        assertEq(a.creator, creator);
        assertEq(a.token, tokenAddr);
        assertEq(a.totalSupply, 1000e18);
        assertEq(a.minPrice, 0.001 ether);
        assertEq(a.maxPrice, 0.1 ether);
        assertEq(uint8(a.state), uint8(CCAEngine.AuctionState.Active));
    }

    function test_placeBid() public {
        vm.prank(creator);
        uint256 id = cca.createAuction(tokenAddr, 1000e18, 0.001 ether, 0.1 ether, 1 days, 10);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        cca.placeBid{value: 0.5 ether}(id, 0.05 ether);

        assertEq(cca.totalBidAmount(id), 0.5 ether);
        assertEq(cca.getBidderCount(id), 1);
    }

    function test_revert_bid_inactive() public {
        vm.prank(creator);
        uint256 id = cca.createAuction(tokenAddr, 1000e18, 0.001 ether, 0.1 ether, 1 days, 10);

        vm.prank(creator);
        cca.cancelAuction(id);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(CCAEngine.AuctionNotActive.selector);
        cca.placeBid{value: 0.5 ether}(id, 0.05 ether);
    }

    function test_cancel_auction() public {
        vm.prank(creator);
        uint256 id = cca.createAuction(tokenAddr, 1000e18, 0.001 ether, 0.1 ether, 1 days, 10);

        vm.prank(creator);
        cca.cancelAuction(id);

        CCAEngine.Auction memory a = cca.getAuction(id);
        assertEq(uint8(a.state), uint8(CCAEngine.AuctionState.Cancelled));
    }

    function test_revert_cancel_with_bids() public {
        vm.prank(creator);
        uint256 id = cca.createAuction(tokenAddr, 1000e18, 0.001 ether, 0.1 ether, 1 days, 10);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        cca.placeBid{value: 0.5 ether}(id, 0.05 ether);

        vm.prank(creator);
        vm.expectRevert("CCA: has bids");
        cca.cancelAuction(id);
    }
}

// ═══ HiveReputation Test ═══

contract HiveReputationTest is Test {
    HiveReputation rep;
    bytes32 userHash = keccak256(bytes("alice"));

    function setUp() public {
        rep = new HiveReputation();
        rep.authorize(address(this));
    }

    function test_record_activity() public {
        rep.recordActivity(userHash, HiveReputation.ActivityType.SaleParticipation, "bought token X");

        HiveReputation.ReputationScore memory score = rep.getScore(userHash);
        assertEq(score.totalScore, 10);
        assertEq(score.saleScore, 10);
        assertEq(score.tier, 0); // Bronze
    }

    function test_tier_upgrade() public {
        // Record enough activities to reach Silver (100 pts)
        for (uint256 i = 0; i < 5; i++) {
            rep.recordActivity(userHash, HiveReputation.ActivityType.Referral, "");
        }

        HiveReputation.ReputationScore memory score = rep.getScore(userHash);
        assertEq(score.totalScore, 250); // 50 * 5
        assertEq(score.tier, 1); // Silver (250 < 500)
    }

    function test_fee_discount() public {
        assertEq(rep.getFeeDiscount(userHash), 0); // Bronze

        // Reach Diamond (10000 pts)
        for (uint256 i = 0; i < 100; i++) {
            rep.recordActivity(userHash, HiveReputation.ActivityType.Referral, "");
        }

        assertEq(rep.getFeeDiscount(userHash), 300); // Platinum: 3%
    }

    function test_governance_weight() public {
        assertEq(rep.getGovernanceWeight(userHash), 100); // Bronze: 1x

        for (uint256 i = 0; i < 200; i++) {
            rep.recordActivity(userHash, HiveReputation.ActivityType.GovernanceVote, "");
        }

        assertEq(rep.getGovernanceWeight(userHash), 150); // Platinum: 1.5x
    }
}

// ═══ HiveMultiSig Test ═══

contract HiveMultiSigTest is Test {
    HiveMultiSig ms;
    address signer1 = address(0x1);
    address signer2 = address(0x2);
    address signer3 = address(0x3);
    address recipient = address(0x4);
    bytes32 hiveHash = keccak256(bytes("team"));

    function setUp() public {
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        ms = new HiveMultiSig(signers, 2, hiveHash); // 2-of-3
        vm.deal(address(ms), 10 ether);
    }

    function test_submit_and_confirm() public {
        vm.prank(signer1);
        uint256 txId = ms.submitTransaction(recipient, 1 ether, "", HiveMultiSig.TxType.Transfer, "pay team");

        vm.prank(signer1);
        ms.confirmTransaction(txId);

        assertTrue(ms.isConfirmed(txId, signer1));
        assertEq(ms.getTransaction(txId).confirmations, 1);
    }

    function test_execute_2of3() public {
        vm.prank(signer1);
        uint256 txId = ms.submitTransaction(recipient, 1 ether, "", HiveMultiSig.TxType.Transfer, "pay");

        vm.prank(signer1);
        ms.confirmTransaction(txId);
        vm.prank(signer2);
        ms.confirmTransaction(txId);

        assertTrue(ms.isReady(txId));

        vm.prank(signer1);
        ms.executeTransaction(txId);

        assertEq(ms.getTransaction(txId).executed, true);
        assertEq(recipient.balance, 1 ether);
    }

    function test_revert_execute_insufficient() public {
        vm.prank(signer1);
        uint256 txId = ms.submitTransaction(recipient, 1 ether, "", HiveMultiSig.TxType.Transfer, "pay");

        vm.prank(signer1);
        ms.confirmTransaction(txId);

        vm.prank(signer1);
        vm.expectRevert(HiveMultiSig.InsufficientConfirmations.selector);
        ms.executeTransaction(txId);
    }

    function test_revoke_confirmation() public {
        vm.prank(signer1);
        uint256 txId = ms.submitTransaction(recipient, 1 ether, "", HiveMultiSig.TxType.Transfer, "pay");

        vm.prank(signer1);
        ms.confirmTransaction(txId);
        vm.prank(signer1);
        ms.revokeConfirmation(txId);

        assertFalse(ms.isConfirmed(txId, signer1));
        assertEq(ms.getTransaction(txId).confirmations, 0);
    }

    function test_signer_count() public {
        assertEq(ms.getSignerCount(), 3);
    }
}

// ═══ HivePortfolio Test ═══

contract HivePortfolioTest is Test {
    HivePortfolio portfolio;
    bytes32 userHash = keccak256(bytes("alice"));
    address tokenA = address(0xA);

    function setUp() public {
        portfolio = new HivePortfolio();
    }

    function test_record_acquisition() public {
        portfolio.recordAcquisition(userHash, tokenA, 100e18, 0.01 ether);

        HivePortfolio.Holding memory h = portfolio.getHolding(userHash, tokenA);
        assertEq(h.amount, 100e18);
        assertEq(h.avgEntryPrice, 0.01 ether);
    }

    function test_weighted_avg_entry() public {
        portfolio.recordAcquisition(userHash, tokenA, 100e18, 0.01 ether);
        portfolio.recordAcquisition(userHash, tokenA, 100e18, 0.02 ether);

        HivePortfolio.Holding memory h = portfolio.getHolding(userHash, tokenA);
        assertEq(h.amount, 200e18);
        assertEq(h.avgEntryPrice, 0.015 ether); // weighted avg
    }

    function test_record_disposal() public {
        portfolio.recordAcquisition(userHash, tokenA, 100e18, 0.01 ether);
        portfolio.recordDisposal(userHash, tokenA, 50e18, 0.02 ether);

        HivePortfolio.Holding memory h = portfolio.getHolding(userHash, tokenA);
        assertEq(h.amount, 50e18);
    }

    function test_get_holding_tokens() public {
        portfolio.recordAcquisition(userHash, tokenA, 100e18, 0.01 ether);

        address[] memory tokens = portfolio.getHoldingTokens(userHash);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenA);
    }

    function test_trade_history() public {
        portfolio.recordAcquisition(userHash, tokenA, 100e18, 0.01 ether);
        portfolio.recordDisposal(userHash, tokenA, 50e18, 0.02 ether);

        HivePortfolio.Trade[] memory trades = portfolio.getTrades(userHash);
        assertEq(trades.length, 2);
        assertTrue(trades[0].isBuy);
        assertFalse(trades[1].isBuy);
    }
}

// ═══ HiveReferral Test ═══

contract HiveReferralTest is Test {
    HiveReferral referral;
    bytes32 referrerHash = keccak256(bytes("alice"));
    bytes32 refereeHash = keccak256(bytes("bob"));

    function setUp() public {
        referral = new HiveReferral();
    }

    function test_create_referral_code() public {
        bytes32 code = referral.createReferralCode(referrerHash);
        assertEq(referral.getReferralCode(referrerHash), code);
    }

    function test_register_referral() public {
        bytes32 code = referral.createReferralCode(referrerHash);

        referral.registerReferral(refereeHash, code);

        assertEq(referral.getReferrer(refereeHash), referrerHash);
        HiveReferral.ReferrerStats memory stats = referral.getStats(referrerHash);
        assertEq(stats.totalReferrals, 1);
    }

    function test_revert_self_referral() public {
        bytes32 code = referral.createReferralCode(referrerHash);

        vm.expectRevert("Referral: self-referral");
        referral.registerReferral(referrerHash, code);
    }

    function test_claim_rewards() public {
        bytes32 code = referral.createReferralCode(referrerHash);
        referral.registerReferral(refereeHash, code);

        uint256 claimable = referral.getClaimable(referrerHash);
        assertGt(claimable, 0);

        vm.deal(address(referral), 1 ether);
        // Can't actually claim without a real address, but check claimable
    }

    function test_tier_progression() public {
        bytes32 code = referral.createReferralCode(referrerHash);

        // 5 referrals = tier 1 (Promoter)
        for (uint256 i = 0; i < 5; i++) {
            bytes32 ref = keccak256(abi.encodePacked(i));
            referral.registerReferral(ref, code);
        }

        HiveReferral.ReferrerStats memory stats = referral.getStats(referrerHash);
        assertEq(stats.totalReferrals, 5);
        assertEq(stats.tier, 1);
    }
}

// ═══ HiveAutoStrategy Test ═══

contract HiveAutoStrategyTest is Test {
    HiveAutoStrategy strategy;
    address user = address(0x1);
    address tokenIn = address(0xA);
    address tokenOut = address(0xB);

    function setUp() public {
        strategy = new HiveAutoStrategy();
        strategy.updatePrice(tokenIn, 0.01 ether);
    }

    function test_create_dca() public {
        vm.prank(user);
        uint256 sid = strategy.createDCA(tokenIn, tokenOut, 0.1 ether, 1 ether, 100, 10, 1 days);

        HiveAutoStrategy.Strategy memory s = strategy.getStrategy(sid);
        assertEq(s.owner, user);
        assertEq(uint8(s.strategyType), uint8(HiveAutoStrategy.StrategyType.DCA));
        assertEq(uint8(s.state), uint8(HiveAutoStrategy.StrategyState.Active));
    }

    function test_create_take_profit() public {
        vm.prank(user);
        uint256 sid = strategy.createPriceTrigger(
            HiveAutoStrategy.StrategyType.TakeProfit,
            tokenIn, tokenOut, 100e18, 0.05 ether, 1 days
        );

        HiveAutoStrategy.Strategy memory s = strategy.getStrategy(sid);
        assertEq(s.targetPrice, 0.05 ether);
    }

    function test_create_stop_loss() public {
        vm.prank(user);
        uint256 sid = strategy.createPriceTrigger(
            HiveAutoStrategy.StrategyType.StopLoss,
            tokenIn, tokenOut, 100e18, 0.005 ether, 1 days
        );

        HiveAutoStrategy.Strategy memory s = strategy.getStrategy(sid);
        assertEq(s.targetPrice, 0.005 ether);
    }

    function test_create_trailing_stop() public {
        vm.prank(user);
        uint256 sid = strategy.createTrailingStop(tokenIn, tokenOut, 100e18, 500, 1 days);

        HiveAutoStrategy.Strategy memory s = strategy.getStrategy(sid);
        assertEq(s.trailingPercentBps, 500);
    }

    function test_cancel_strategy() public {
        vm.deal(address(strategy), 1 ether);

        vm.prank(user);
        uint256 sid = strategy.createDCA(tokenIn, tokenOut, 0.1 ether, 1 ether, 100, 10, 1 days);

        uint256 balBefore = user.balance;
        vm.prank(user);
        strategy.cancelStrategy(sid);

        assertEq(user.balance, balBefore + 1 ether);
    }

    function test_isActive() public {
        vm.prank(user);
        uint256 sid = strategy.createDCA(tokenIn, tokenOut, 0.1 ether, 1 ether, 100, 10, 1 days);

        assertTrue(strategy.isActive(sid));
    }
}

// ═══ HiveChat Test ═══

contract HiveChatTest is Test {
    HiveChat chat;
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        chat = new HiveChat();

        // Map identities
        chat.setIdentityMapping(user1, keccak256(bytes("alice")));
        chat.setIdentityMapping(user2, keccak256(bytes("bob")));
    }

    function test_register_public_key() public {
        vm.prank(user1);
        chat.registerPublicKey(bytes("pubkey-alice-65bytes"));
        assertTrue(chat.hasPublicKey(keccak256(bytes("alice"))));
    }

    function test_start_conversation() public {
        vm.prank(user1);
        bytes32 convId = chat.startConversation(keccak256(bytes("bob")));

        assertTrue(convId != bytes32(0));
        assertEq(chat.getConversation(convId).messageCount, 0);
    }

    function test_send_message() public {
        vm.prank(user1);
        bytes32 convId = chat.startConversation(keccak256(bytes("bob")));

        vm.prank(user1);
        chat.sendMessage(keccak256(bytes("bob")), bytes("encrypted-hello"));

        assertEq(chat.getConversation(convId).messageCount, 1);
        assertEq(chat.getUnreadCount(keccak256(bytes("bob")), convId), 1);
    }

    function test_mark_read() public {
        vm.prank(user1);
        bytes32 convId = chat.startConversation(keccak256(bytes("bob")));

        vm.prank(user1);
        chat.sendMessage(keccak256(bytes("bob")), bytes("hello"));

        vm.prank(user2);
        chat.markRead(convId);

        assertEq(chat.getUnreadCount(keccak256(bytes("bob")), convId), 0);
    }

    function test_get_messages() public {
        vm.prank(user1);
        chat.startConversation(keccak256(bytes("bob")));

        vm.prank(user1);
        chat.sendMessage(keccak256(bytes("bob")), bytes("msg1"));
        vm.prank(user2);
        chat.sendMessage(keccak256(bytes("alice")), bytes("msg2"));

        bytes32 convId = chat.conversationLookup(keccak256(bytes("alice")), keccak256(bytes("bob")));
        HiveChat.Message[] memory msgs = chat.getMessages(convId, 0, 10);
        assertEq(msgs.length, 2);
    }

    function test_get_total_unread() public {
        vm.prank(user1);
        chat.startConversation(keccak256(bytes("bob")));
        vm.prank(user1);
        chat.sendMessage(keccak256(bytes("bob")), bytes("hello"));

        assertEq(chat.getTotalUnread(keccak256(bytes("bob"))), 1);
    }
}
