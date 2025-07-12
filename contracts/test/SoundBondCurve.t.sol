// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SoundBondCurve} from "../src/SoundBondCurve.sol";

contract SoundBondCurveTest is Test {
    SoundBondCurve public curve;
    address public owner;
    address public clubTreasury;
    address public noiseRouter;
    address public buyer;
    address public seller;
    
    // Test constants
    string constant NAME = "PSG Sound Token";
    string constant SYMBOL = "PSG-SND";
    uint256 constant ALPHA = 1e15; // 0.001 CHZ per token
    uint256 constant BETA = 5e16; // 0.05 CHZ base price
    uint256 constant EXIT_FEE_BPS = 200; // 2%
    uint256 constant SCALE_FACTOR = 1e18;
    
    event TokensPurchased(
        address indexed buyer,
        uint256 chzAmount,
        uint256 tokensReceived,
        uint256 newPrice
    );
    
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 chzReceived,
        uint256 exitFee,
        uint256 newPrice
    );
    
    event SlopeUpdated(uint256 oldAlpha, uint256 newAlpha, address indexed updatedBy);
    
    event BonusTokensMinted(uint256 amount, address indexed recipient);
    
    function setUp() public {
        owner = makeAddr("owner");
        clubTreasury = makeAddr("clubTreasury");
        noiseRouter = makeAddr("noiseRouter");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        
        // Deploy curve
        curve = new SoundBondCurve(
            NAME,
            SYMBOL,
            ALPHA,
            BETA,
            EXIT_FEE_BPS,
            clubTreasury,
            owner
        );
        
        // Set noise router
        vm.prank(owner);
        curve.setNoiseRouter(noiseRouter);
        
        // Give test accounts some CHZ
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 100 ether);
    }
    
    function testConstructor() public {
        assertEq(curve.name(), NAME);
        assertEq(curve.symbol(), SYMBOL);
        assertEq(curve.alpha(), ALPHA);
        assertEq(curve.beta(), BETA);
        assertEq(curve.exitFeeBps(), EXIT_FEE_BPS);
        assertEq(curve.clubTreasury(), clubTreasury);
        assertEq(curve.owner(), owner);
        assertEq(curve.vaultBalance(), 0);
        assertEq(curve.totalBonusTokens(), 0);
    }
    
    function testConstructorInvalidParams() public {
        // Zero alpha
        vm.expectRevert(SoundBondCurve.InvalidParameters.selector);
        new SoundBondCurve(NAME, SYMBOL, 0, BETA, EXIT_FEE_BPS, clubTreasury, owner);
        
        // Exit fee too high
        vm.expectRevert(SoundBondCurve.InvalidParameters.selector);
        new SoundBondCurve(NAME, SYMBOL, ALPHA, BETA, 600, clubTreasury, owner);
        
        // Zero club treasury
        vm.expectRevert(SoundBondCurve.ZeroAddress.selector);
        new SoundBondCurve(NAME, SYMBOL, ALPHA, BETA, EXIT_FEE_BPS, address(0), owner);
    }
    
    function testCalculatePrice() public {
        // Price at 0 supply should be beta
        assertEq(curve.calculatePrice(0), BETA);
        
        // Price at 1000 tokens: alpha * 1000 + beta
        uint256 expectedPrice = (ALPHA * 1000 * SCALE_FACTOR) / SCALE_FACTOR + BETA;
        assertEq(curve.calculatePrice(1000 * SCALE_FACTOR), expectedPrice);
    }
    
    function testBuyTokens() public {
        uint256 chzAmount = 1 ether;
        
        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit TokensPurchased(buyer, chzAmount, 0, 0); // We'll check actual values separately
        
        uint256 tokensReceived = curve.buy{value: chzAmount}();
        
        assertGt(tokensReceived, 0);
        assertEq(curve.balanceOf(buyer), tokensReceived);
        assertEq(curve.vaultBalance(), chzAmount);
        assertEq(curve.totalSupply(), tokensReceived);
    }
    
    function testBuyZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(SoundBondCurve.ZeroAmount.selector);
        curve.buy{value: 0}();
    }
    
    function testSellTokens() public {
        // First buy some tokens
        uint256 chzAmount = 1 ether;
        vm.prank(buyer);
        uint256 tokensReceived = curve.buy{value: chzAmount}();
        
        // Now sell half
        uint256 tokensToSell = tokensReceived / 2;
        
        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit TokensSold(buyer, tokensToSell, 0, 0, 0); // We'll check actual values separately
        
        uint256 chzReceived = curve.sell(tokensToSell);
        
        assertGt(chzReceived, 0);
        assertEq(curve.balanceOf(buyer), tokensReceived - tokensToSell);
        assertLt(curve.vaultBalance(), chzAmount); // Should be less due to CHZ withdrawal
    }
    
    function testSellZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(SoundBondCurve.ZeroAmount.selector);
        curve.sell(0);
    }
    
    function testSellInsufficientTokens() public {
        vm.prank(buyer);
        vm.expectRevert(SoundBondCurve.InsufficientTokens.selector);
        curve.sell(1000);
    }
    
    function testUpdateSlope() public {
        uint256 deltaAlpha = 1e14; // 0.0001 CHZ
        uint256 oldAlpha = curve.alpha();
        
        vm.prank(noiseRouter);
        vm.expectEmit(false, false, false, true);
        emit SlopeUpdated(oldAlpha, oldAlpha + deltaAlpha, noiseRouter);
        
        curve.updateSlope(deltaAlpha);
        
        assertEq(curve.alpha(), oldAlpha + deltaAlpha);
    }
    
    function testUpdateSlopeUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert(SoundBondCurve.Unauthorized.selector);
        curve.updateSlope(1e14);
    }
    
    function testUpdateSlopeZeroAmount() public {
        vm.prank(noiseRouter);
        vm.expectRevert(SoundBondCurve.ZeroAmount.selector);
        curve.updateSlope(0);
    }
    
    function testBonusMint() public {
        uint256 bonusAmount = 1000 * SCALE_FACTOR;
        
        vm.prank(noiseRouter);
        vm.expectEmit(false, false, true, true);
        emit BonusTokensMinted(bonusAmount, clubTreasury);
        
        curve.bonusMint(bonusAmount);
        
        assertEq(curve.balanceOf(clubTreasury), bonusAmount);
        assertEq(curve.totalBonusTokens(), bonusAmount);
    }
    
    function testBonusMintUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert(SoundBondCurve.Unauthorized.selector);
        curve.bonusMint(1000);
    }
    
    function testBonusMintZeroAmount() public {
        vm.prank(noiseRouter);
        vm.expectRevert(SoundBondCurve.ZeroAmount.selector);
        curve.bonusMint(0);
    }
    
    function testCalculateBuyCost() public {
        uint256 tokenAmount = 1000 * SCALE_FACTOR;
        uint256 cost = curve.calculateBuyCost(tokenAmount);
        
        assertGt(cost, 0);
        
        // Cost should be approximately (alpha * tokenAmount^2 / 2) + (beta * tokenAmount)
        uint256 expectedCost = ((ALPHA * tokenAmount * tokenAmount) / (2 * SCALE_FACTOR)) + (BETA * tokenAmount) / SCALE_FACTOR;
        assertApproxEqRel(cost, expectedCost, 1e16); // 1% tolerance
    }
    
    function testCalculateBuyCostZero() public {
        assertEq(curve.calculateBuyCost(0), 0);
    }
    
    function testCalculateSellReturn() public {
        // First buy some tokens
        uint256 chzAmount = 1 ether;
        vm.prank(buyer);
        uint256 tokensReceived = curve.buy{value: chzAmount}();
        
        // Calculate sell return
        uint256 sellReturn = curve.calculateSellReturn(tokensReceived);
        
        // Should be less than original purchase due to exit fee
        assertLt(sellReturn, chzAmount);
        
        // Should be approximately (1 - exitFee) * original amount
        uint256 expectedReturn = (chzAmount * (curve.BPS_DENOMINATOR() - EXIT_FEE_BPS)) / curve.BPS_DENOMINATOR();
        assertApproxEqRel(sellReturn, expectedReturn, 1e17); // 10% tolerance for curve math
    }
    
    function testCalculateSellReturnZero() public {
        assertEq(curve.calculateSellReturn(0), 0);
    }
    
    function testExitFeeDistribution() public {
        // Buy tokens
        uint256 chzAmount = 1 ether;
        vm.prank(buyer);
        uint256 tokensReceived = curve.buy{value: chzAmount}();
        
        // Record balances
        uint256 treasuryBalanceBefore = clubTreasury.balance;
        uint256 buyerBalanceBefore = buyer.balance;
        
        // Sell tokens
        vm.prank(buyer);
        uint256 chzReceived = curve.sell(tokensReceived);
        
        // Check that treasury received exit fee
        uint256 treasuryBalanceAfter = clubTreasury.balance;
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore);
        
        // Check that buyer received CHZ minus exit fee
        uint256 buyerBalanceAfter = buyer.balance;
        assertEq(buyerBalanceAfter, buyerBalanceBefore + chzReceived);
    }
    
    function testSetNoiseRouter() public {
        address newRouter = makeAddr("newRouter");
        
        vm.prank(owner);
        curve.setNoiseRouter(newRouter);
        
        assertEq(curve.noiseRouter(), newRouter);
    }
    
    function testSetNoiseRouterUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert();
        curve.setNoiseRouter(makeAddr("newRouter"));
    }
    
    function testSetNoiseRouterZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SoundBondCurve.ZeroAddress.selector);
        curve.setNoiseRouter(address(0));
    }
    
    function testSetClubTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        
        vm.prank(owner);
        curve.setClubTreasury(newTreasury);
        
        assertEq(curve.clubTreasury(), newTreasury);
    }
    
    function testSetClubTreasuryUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert();
        curve.setClubTreasury(makeAddr("newTreasury"));
    }
    
    function testSetClubTreasuryZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SoundBondCurve.ZeroAddress.selector);
        curve.setClubTreasury(address(0));
    }
    
    function testSetExitFee() public {
        uint256 newExitFee = 300; // 3%
        
        vm.prank(owner);
        curve.setExitFee(newExitFee);
        
        assertEq(curve.exitFeeBps(), newExitFee);
    }
    
    function testSetExitFeeUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert();
        curve.setExitFee(300);
    }
    
    function testSetExitFeeTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(SoundBondCurve.InvalidParameters.selector);
        curve.setExitFee(600); // 6% > 5% max
    }
    
    function testEmergencyWithdraw() public {
        // First, add some CHZ to vault
        vm.prank(buyer);
        curve.buy{value: 1 ether}();
        
        uint256 withdrawAmount = 0.5 ether;
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.prank(owner);
        curve.emergencyWithdraw(withdrawAmount);
        
        assertEq(owner.balance, ownerBalanceBefore + withdrawAmount);
        assertEq(curve.vaultBalance(), 1 ether - withdrawAmount);
    }
    
    function testEmergencyWithdrawUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert();
        curve.emergencyWithdraw(1 ether);
    }
    
    function testEmergencyWithdrawInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(SoundBondCurve.InsufficientVaultBalance.selector);
        curve.emergencyWithdraw(1 ether);
    }
    
    function testReceiveFunction() public {
        uint256 amount = 1 ether;
        uint256 vaultBefore = curve.vaultBalance();
        
        (bool success, ) = address(curve).call{value: amount}("");
        assertTrue(success);
        
        assertEq(curve.vaultBalance(), vaultBefore + amount);
    }
    
    function testBuyGasUsage() public {
        vm.prank(buyer);
        uint256 gasBefore = gasleft();
        curve.buy{value: 1 ether}();
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for buy:", gasUsed);
        assertLt(gasUsed, 50000, "Buy gas usage should be less than 50k");
    }
    
    function testSellGasUsage() public {
        // First buy tokens
        vm.prank(buyer);
        uint256 tokensReceived = curve.buy{value: 1 ether}();
        
        // Then sell
        vm.prank(buyer);
        uint256 gasBefore = gasleft();
        curve.sell(tokensReceived);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for sell:", gasUsed);
        assertLt(gasUsed, 50000, "Sell gas usage should be less than 50k");
    }
    
    function testBonusMintGasUsage() public {
        vm.prank(noiseRouter);
        uint256 gasBefore = gasleft();
        curve.bonusMint(1000 * SCALE_FACTOR);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for bonus mint:", gasUsed);
        assertLt(gasUsed, 38000, "Bonus mint gas usage should be less than 38k");
    }
    
    function testSqrtFunction() public {
        // Test the internal sqrt function indirectly through buy operations
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 0.1 ether;
        testAmounts[1] = 0.5 ether;
        testAmounts[2] = 1 ether;
        testAmounts[3] = 2 ether;
        testAmounts[4] = 5 ether;
        
        for (uint256 i = 0; i < testAmounts.length; i++) {
            vm.prank(buyer);
            uint256 tokens = curve.buy{value: testAmounts[i]}();
            assertGt(tokens, 0, "Should receive tokens for any positive CHZ amount");
        }
    }
    
    function testFuzzBuyAndSell(uint256 chzAmount) public {
        vm.assume(chzAmount > 0.01 ether && chzAmount < 10 ether);
        
        // Buy tokens
        vm.deal(buyer, chzAmount);
        vm.prank(buyer);
        uint256 tokensReceived = curve.buy{value: chzAmount}();
        
        assertGt(tokensReceived, 0);
        assertEq(curve.balanceOf(buyer), tokensReceived);
        
        // Sell tokens
        vm.prank(buyer);
        uint256 chzReceived = curve.sell(tokensReceived);
        
        assertGt(chzReceived, 0);
        assertLt(chzReceived, chzAmount); // Should be less due to exit fee
        assertEq(curve.balanceOf(buyer), 0);
    }
    
    function testMultipleBuysAndSells() public {
        address[] memory buyers = new address[](3);
        buyers[0] = makeAddr("buyer1");
        buyers[1] = makeAddr("buyer2");
        buyers[2] = makeAddr("buyer3");
        
        uint256[] memory tokenAmounts = new uint256[](3);
        
        // Multiple buyers purchase tokens
        for (uint256 i = 0; i < buyers.length; i++) {
            vm.deal(buyers[i], 1 ether);
            vm.prank(buyers[i]);
            tokenAmounts[i] = curve.buy{value: 1 ether}();
            assertGt(tokenAmounts[i], 0);
        }
        
        // Check total supply
        uint256 expectedTotalSupply = tokenAmounts[0] + tokenAmounts[1] + tokenAmounts[2];
        assertEq(curve.totalSupply(), expectedTotalSupply);
        
        // First buyer sells all tokens
        vm.prank(buyers[0]);
        uint256 chzReceived = curve.sell(tokenAmounts[0]);
        assertGt(chzReceived, 0);
        
        // Check supply decreased
        assertEq(curve.totalSupply(), expectedTotalSupply - tokenAmounts[0]);
    }
} 