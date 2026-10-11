// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {INFERToken} from "../src/INFERToken.sol";

/// @notice Properties that complement the deployment and ERC-20 examples in INFERToken.t.sol.
/// forge-config: default.fuzz.runs = 1000
contract INFERTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    INFERToken private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        holder = makeAddr("property holder");
        recipient = makeAddr("property recipient");
        spender = makeAddr("property spender");
        otherSpender = makeAddr("other property spender");
        token = new INFERToken();
        assertTrue(token.transfer(holder, SUPPLY));
    }

    function test_OneWeiRoundTripRestoresBalances() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintTransferCannotWrapOrBypassBalanceCheck() public {
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max);
        vm.expectRevert(errorData);
        vm.prank(holder);
        token.transfer(recipient, type(uint256).max);
        vm.expectRevert(errorData);
        vm.prank(holder);
        token.transfer(holder, type(uint256).max);

        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintMinusOneApprovalIsFinite() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
    }

    function test_TransferFromByOwnerStillRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.startPrank(holder);
        assertTrue(token.approve(holder, 1));
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.stopPrank();
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_AllowanceBelongsToCallerNotTransactionOrigin() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, 10));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender, spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 10);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender, otherSpender);
        assertTrue(token.transferFrom(holder, recipient, 10));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 10);
        assertEq(token.balanceOf(recipient), 10);
    }

    function test_RevokingUnlimitedApprovalAfterUsePreventsFurtherSpending() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_CompetingSpendersCannotSpendTheSameBalanceTwice() public {
        vm.startPrank(holder);
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.approve(otherSpender, SUPPLY));
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, SUPPLY));
        vm.prank(otherSpender);
        token.transferFrom(holder, otherSpender, SUPPLY);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, otherSpender), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsAreScopedToOwnerAndSpender(uint256 amount, uint256 unrelatedApproval) public {
        amount = bound(amount, 1, SUPPLY / 2);
        vm.startPrank(holder);
        assertTrue(token.transfer(recipient, SUPPLY / 2));
        assertTrue(token.approve(spender, amount));
        assertTrue(token.approve(otherSpender, unrelatedApproval));
        vm.stopPrank();
        vm.prank(recipient);
        assertTrue(token.approve(spender, unrelatedApproval));

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, otherSpender, amount));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, otherSpender), unrelatedApproval);
        assertEq(token.allowance(recipient, spender), unrelatedApproval);
        assertEq(token.allowance(spender, holder), 0);
        assertEq(token.balanceOf(holder), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(recipient), SUPPLY / 2);
        assertEq(token.balanceOf(otherSpender), amount);
        assertEq(token.balanceOf(spender), 0);

        vm.prank(holder);
        assertTrue(token.approve(otherSpender, 0));
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.allowance(recipient, spender), unrelatedApproval);
    }

    function testFuzz_ApprovalSurvivesEmptyBalanceAndCanBeUsedAfterRefill(uint256 amount, bool unlimited) public {
        amount = bound(amount, 1, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.startPrank(holder);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.transfer(recipient, SUPPLY));
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, amount));
        vm.prank(spender);
        token.transferFrom(holder, spender, amount);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, spender, amount));
        assertEq(token.allowance(holder, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), amount);
        assertEq(token.balanceOf(recipient), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersEqualCombinedTransferAndRoundTrip(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        INFERToken combined = new INFERToken();
        assertTrue(combined.transfer(holder, SUPPLY));
        vm.startPrank(holder);
        assertTrue(combined.transfer(recipient, amount));
        assertTrue(token.transfer(recipient, first));
        assertTrue(token.transfer(recipient, amount - first));
        vm.stopPrank();
        assertEq(token.balanceOf(holder), combined.balanceOf(holder));
        assertEq(token.balanceOf(recipient), combined.balanceOf(recipient));
        assertEq(token.balanceOf(recipient), amount);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacingUnlimitedAllowanceEnforcesNewLimit(uint256 limit) public {
        limit = bound(limit, 0, SUPPLY - 1);
        vm.startPrank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, limit));
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, limit, limit + 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, limit + 1);
        assertEq(token.allowance(holder, spender), limit);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, limit));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - limit);
        assertEq(token.balanceOf(recipient), limit);
    }
}
