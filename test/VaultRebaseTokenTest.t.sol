// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { RebaseToken } from "src/RebaseToken.sol";
import { Vault } from "src/Vault.sol";
import { IRebaseToken } from "src/interfaces/IRebaseToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract VaultRebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");
    uint256 public constant INITIAL_VAULT_BALANCE = 1 ether;
    uint256 public constant INITIAL_OWNER_BALANCE = 10 ether;
    uint256 public constant LOWER_DEPOSIT = 1e5;
    uint256 public constant HIGHER_DEPOSIT = type(uint96).max;
    uint256 public constant HIGHER_TIME = type(uint32).max;

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.deal(OWNER, INITIAL_OWNER_BALANCE);
        addRewardsToVault(INITIAL_VAULT_BALANCE);
        vm.stopPrank();
    }

    // Helper function
    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{ value: rewardAmount }("");
        assertEq(success, true);
    }

    // constructor
    function testConstructorAssignsAdminRole() public view {
        vm.assertEq(rebaseToken.hasRole(rebaseToken.DEFAULT_ADMIN_ROLE(), OWNER), true);
    }

    // deposit
    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, LOWER_DEPOSIT, HIGHER_DEPOSIT);
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{ value: amount }();
        uint256 startBalance = rebaseToken.balanceOf(USER);
        assertEq(startBalance, amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(USER);
        assert(middleBalance > startBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(USER);
        assert(endBalance > middleBalance);

        // Interest is linear
        // We use assertApproxEqAbs to avoid precision error
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    // redeem
    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, LOWER_DEPOSIT, HIGHER_DEPOSIT);
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{ value: amount }();
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(address(USER).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAafterTimePassed(uint256 amount, uint256 time) public {
        time = bound(time, 1000, HIGHER_TIME); // in seconds
        amount = bound(amount, LOWER_DEPOSIT, HIGHER_DEPOSIT);
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{ value: amount }();

        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(USER);

        // We need to make sure there is enought ETH for rewards
        vm.deal(OWNER, balanceAfterSomeTime - amount);
        vm.prank(OWNER);
        addRewardsToVault(balanceAfterSomeTime - amount);

        vm.prank(USER);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(USER).balance;
        assertEq(balanceAfterSomeTime, ethBalance);
        assert(ethBalance > amount);
    }

    // transfer
    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, LOWER_DEPOSIT * 2, HIGHER_DEPOSIT);
        amountToSend = bound(amountToSend, LOWER_DEPOSIT, amount - LOWER_DEPOSIT);

        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{ value: amount }();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(USER);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        vm.prank(USER);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(USER);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        // check the interest rate has been inherited
        assertEq(rebaseToken.getUserInterestRate(USER), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    // setInterestRate
    function testCannotSetInterestRateIfNotAdmin(uint256 interestRate) public {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER, rebaseToken.DEFAULT_ADMIN_ROLE()
            )
        );
        rebaseToken.setInterestRate(interestRate);
        vm.stopPrank();
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, initialInterestRate, newInterestRate
            )
        );
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    // mint
    function testCannotCallMintIfNotAuthorized() public {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER, rebaseToken.MINT_AND_BURN_ROLE()
            )
        );
        rebaseToken.mint(USER, 100);
        vm.stopPrank();
    }

    // burn
    function testCannotCallBurnIfNotAuthorized() public {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER, rebaseToken.MINT_AND_BURN_ROLE()
            )
        );
        rebaseToken.burn(USER, 100);
        vm.stopPrank();
    }

    // getPrincipleBalanceOf
    function testGetPrincipleBalanceOf(uint256 amount) public {
        amount = bound(amount, LOWER_DEPOSIT, HIGHER_DEPOSIT);
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{ value: amount }();
        assertEq(rebaseToken.getPrincipleBalanceOf(USER), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.getPrincipleBalanceOf(USER), amount);
    }

    // getRebaseTokenAddress
    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }
}
