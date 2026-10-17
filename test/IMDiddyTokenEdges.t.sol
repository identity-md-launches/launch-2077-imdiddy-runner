// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDiddyToken} from "src/IMDiddyToken.sol";

/// @dev Regression cases for allowance boundaries, address aliasing and atomic rejection.
/// forge-config: default.fuzz.runs = 1024
contract IMDiddyTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    IMDiddyToken internal token;
    address internal alice = makeAddr("edge holder");
    address internal bob = makeAddr("edge recipient");
    address internal spender = makeAddr("edge spender");

    function setUp() public {
        token = new IMDiddyToken();
        assertTrue(token.transfer(alice, SUPPLY));
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        _approve(alice, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY - 1));
        assertEq(token.allowance(alice, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_infiniteApprovalCanBeReducedThenRevoked() public {
        _approve(alice, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        _approve(alice, spender, 2);
        _expectAllowanceFailure(spender, alice, bob, 2, 3);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 1);
        _approve(alice, spender, 0);
        _expectAllowanceFailure(spender, alice, bob, 0, 1);
        assertEq(token.balanceOf(alice), SUPPLY - 2);
        assertEq(token.balanceOf(bob), 2);
    }

    function test_exhaustedApprovalCannotBeReplayedAfterTokensReturn() public {
        _approve(alice, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.allowance(alice, spender), 0);
        vm.prank(bob);
        assertTrue(token.transfer(alice, SUPPLY));
        // Restoring the owner's balance must not restore the authorization already spent.
        _expectAllowanceFailure(spender, alice, bob, 0, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ownerNeedsSelfApprovalForTransferFrom() public {
        _expectAllowanceFailure(alice, alice, bob, 0, 1);
        _approve(alice, alice, 1);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);
        _expectAllowanceFailure(alice, alice, bob, 0, 1);
        assertEq(token.balanceOf(alice), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_allowanceIsNotSharedBetweenSpendersOrOwners() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 7));
        _approve(alice, spender, 5);
        _approve(alice, bob, 2);
        _approve(bob, spender, 3);
        _expectAllowanceFailure(bob, alice, bob, 2, 3);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 4));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.allowance(alice, bob), 2);
        assertEq(token.allowance(bob, spender), 3);
        _expectAllowanceFailure(spender, bob, alice, 3, 4);
        vm.prank(spender);
        assertTrue(token.transferFrom(bob, alice, 3));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.allowance(alice, bob), 2);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), SUPPLY - 8);
        assertEq(token.balanceOf(bob), 8);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        _expectBalanceFailure(alice, alice, SUPPLY, SUPPLY + 1);
        _expectBalanceFailure(alice, alice, SUPPLY, type(uint256).max);
        _expectBalanceFailure(bob, bob, 0, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceCannotAuthorizeMoreThanTheBalance() public {
        _approve(alice, spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, type(uint256).max);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferAboveBalanceRollsBackFiniteAllowance() public {
        _approve(alice, spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, alice, SUPPLY + 1);
        assertEq(token.allowance(alice, spender), SUPPLY + 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAmountCannotBypassAddressValidation() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, address(0)), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferPreservesExistingAllowance() public {
        _approve(alice, spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 0));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_spenderCanBeRecipientAndSpendTheFullBalance() public {
        _approve(alice, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_tokenContractCanReceiveTokensWithoutBurningThem() public {
        vm.prank(alice);
        assertTrue(token.transfer(address(token), 1));
        _approve(alice, spender, SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
        _expectAllowanceFailure(address(this), address(token), bob, 0, 1);
        assertEq(token.balanceOf(address(token)), SUPPLY);
    }

    function test_erc20EntrypointsRejectAttachedEtherWithoutChangingState() public {
        _approve(alice, spender, 1);
        vm.deal(alice, 1 ether);
        vm.deal(spender, 1 ether);
        vm.prank(alice);
        (bool transferred,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (bob, 1)));
        assertFalse(transferred);
        vm.prank(alice);
        (bool approved,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (spender, 2)));
        assertFalse(approved);
        vm.prank(spender);
        (bool spent,) = address(token).call{value: 1}(abi.encodeCall(token.transferFrom, (alice, bob, 1)));
        assertFalse(spent);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
        assertEq(spender.balance, 1 ether);
    }

    function test_roundTripsAtZeroOneWeiAndFullSupply() public {
        _splitAndReturn(0, 0);
        _splitAndReturn(1, 1);
        _splitAndReturn(SUPPLY, 1);
    }

    function testFuzz_splitTransfersAndRoundTripDoNotChargeFees(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 0, SUPPLY);
        _splitAndReturn(amount, bound(firstPart, 0, amount));
    }

    function testFuzz_approvalReplacementIsIdempotentAndIndependentOfBalance(uint256 first, uint256 second)
        public
    {
        // Bob has no tokens. Approval is a spending limit, not a transfer or a reserve of funds.
        _approve(bob, spender, first);
        assertEq(token.allowance(bob, spender), first);
        _approve(bob, spender, second);
        _approve(bob, spender, second);
        assertEq(token.allowance(bob, spender), second);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferFromChangesOnlyFiniteAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        _approve(alice, spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - amount
        );
    }

    function testFuzz_reducedApprovalTakesEffectImmediately(uint256 first, uint256 reduced) public {
        first = bound(first, 1, SUPPLY);
        reduced = bound(reduced, 0, first - 1);
        _approve(alice, spender, first);
        _approve(alice, spender, reduced);
        _expectAllowanceFailure(spender, alice, bob, reduced, reduced + 1);
        assertEq(token.allowance(alice, spender), reduced);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, reduced));
        _expectAllowanceFailure(spender, alice, bob, 0, 1);
        assertEq(token.balanceOf(alice), SUPPLY - reduced);
        assertEq(token.balanceOf(bob), reduced);
    }

    function testFuzz_balanceFailurePreservesLargeFiniteAllowance(
        uint256 held,
        uint256 approved,
        uint256 amount
    ) public {
        held = bound(held, 0, SUPPLY - 1);
        approved = bound(approved, held + 1, type(uint256).max - 1);
        amount = bound(amount, held + 1, approved);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY - held));
        _approve(alice, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _splitAndReturn(uint256 amount, uint256 firstPart) private {
        _approve(alice, spender, type(uint256).max);
        vm.prank(alice);
        assertTrue(token.transfer(bob, firstPart));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount - firstPart));
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), SUPPLY - amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address approvedSpender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(approvedSpender, amount));
    }

    function _expectAllowanceFailure(
        address caller,
        address owner,
        address to,
        uint256 allowed,
        uint256 amount
    ) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, allowed, amount)
        );
        vm.prank(caller);
        token.transferFrom(owner, to, amount);
    }

    function _expectBalanceFailure(address from, address to, uint256 held, uint256 amount) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
        );
        vm.prank(from);
        token.transfer(to, amount);
    }
}
