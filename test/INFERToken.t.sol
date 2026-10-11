// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {INFERToken} from "../src/INFERToken.sol";

/// @dev Local deployment harness, not a launch application contract.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (INFERToken) {
        return new INFERToken{salt: salt}();
    }

    function move(INFERToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract INFERTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    INFERToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new INFERToken();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Inference Backed Endogenous Financial Re");
        assertEq(token.symbol(), "INFER");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        INFERToken fresh = new INFERToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_DirectDeploymentMintsToImmediateCaller() public {
        vm.prank(alice, bob);
        INFERToken fresh = new INFERToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_Create2FactoryReceivesSupplyAndCanDistributeExactly() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("INFER launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(INFERToken).creationCode))
                    )
                )
            )
        );
        vm.prank(alice, bob);
        INFERToken launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(bob), 0);

        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainder = makeAddr("remainder recipient");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        assertTrue(factory.move(launched, distributor, swarm));
        assertTrue(factory.move(launched, poolManager, pool));
        assertTrue(factory.move(launched, remainder, SUPPLY - swarm - pool));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarm));
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, 1 ether));
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, 1 ether));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarm);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 7 ether);
        assertTrue(token.transfer(alice, 7 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether);
        assertEq(token.balanceOf(alice), 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRejectsInsufficientBalanceWithoutChangingState() public {
        assertTrue(token.transfer(alice, 5));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(alice);
        token.transfer(bob, 6);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_TransferRejectsZeroRecipientIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 40));
        assertEq(token.allowance(address(this), spender), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromExhaustsAllowance() public {
        assertTrue(token.approve(spender, 5));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 5);
    }

    function test_MaxAllowanceIsNotDecreased() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_RevocationPreventsFurtherSpending() public {
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromRejectsInsufficientAllowanceAndPreservesState() public {
        assertTrue(token.approve(spender, 3));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3, 4));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromRejectsInsufficientBalanceAndRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        vm.prank(spender);
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromRejectsZeroRecipientAndRollsBackAllowance() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromRejectsZeroSenderEvenForZeroAmount() public {
        // transferFrom validates the allowance owner before reaching the transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferFromConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_FormerDeployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(alice, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_NoMintBurnFreezeOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(alice, 100));
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("initialize(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool fromDeployer,) = address(token).call(calls[i]);
            assertFalse(fromDeployer);
            vm.prank(bob);
            (bool fromStranger,) = address(token).call(calls[i]);
            assertFalse(fromStranger);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool accepted,) = address(token).call{value: 1 ether}("");
        assertFalse(accepted);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    function testFuzz_TransferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferAboveBalanceReverts(uint256 excess) public {
        excess = bound(excess, 1, type(uint256).max - SUPPLY);
        uint256 amount = SUPPLY + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_DelegatedTransfersRespectAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, approved));
        if (amount > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
            vm.prank(spender);
            token.transferFrom(address(this), alice, amount);
            assertEq(token.allowance(address(this), spender), approved);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            vm.prank(spender);
            assertTrue(token.transferFrom(address(this), alice, amount));
            assertEq(
                token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount
            );
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
