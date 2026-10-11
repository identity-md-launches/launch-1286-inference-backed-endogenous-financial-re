// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {INFERToken} from "../src/INFERToken.sol";

/// @dev Keeps all transfers within a finite actor set so conservation is independently observable.
contract TokenHandler is Test {
    INFERToken private immutable token;
    address[4] private actors;

    constructor(INFERToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, unlimited ? type(uint256).max : amount));
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        uint256 allowed = token.allowance(from, spender);
        amount = bound(amount, 0, balance < allowed ? balance : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
    }
}

contract INFERTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    INFERToken private token;
    address[4] private actors;

    function setUp() public {
        token = new INFERToken();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        assertTrue(token.transfer(actors[0], SUPPLY));
        TokenHandler handler = new TokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndAllBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
