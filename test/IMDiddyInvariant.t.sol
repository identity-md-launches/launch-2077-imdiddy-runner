// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDiddyToken} from "../src/IMDiddyToken.sol";

/// @dev Exercises sequences of transfers, approvals and both valid/invalid delegated spending.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    IMDiddyToken public immutable token;
    address[4] public actors;
    // Seeded from the fixture allocation, then updated only from requested operations.
    // Never resynchronize these ledgers with the token's balance/allowance getters.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public positiveTransfers;
    uint256 public positiveSpends;
    uint256 public rejectedCalls;

    constructor(IMDiddyToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        uint256 amount = bound(rawAmount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
        if (amount > 0 && from != to) ++positiveTransfers;
        if (from != to) {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        } else {
            assertEq(token.balanceOf(from), fromBefore);
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool unlimited) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        // Include approvals above total supply and near uint256.max as well as spendable approvals.
        uint256 amount = unlimited ? type(uint256).max : rawAmount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        _spend(owner, spender, to, bound(rawAmount, 0, SUPPLY + 1));
    }

    function spendAvailable(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount)
        external
    {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 limit = expectedBalance[owner];
        if (expectedAllowance[owner][spender] < limit) limit = expectedAllowance[owner][spender];
        _spend(owner, spender, actors[toSeed % 4], bound(rawAmount, 0, limit));
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        uint256 held = expectedBalance[from];
        uint256 amount = bound(rawAmount, held + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
        );
        vm.prank(from);
        token.transfer(actors[toSeed % 4], amount);
        ++rejectedCalls;
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
        ++rejectedCalls;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 4]);
        token.approve(address(0), amount);
        ++rejectedCalls;
    }

    function spendToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 limit = expectedBalance[owner];
        if (expectedAllowance[owner][spender] < limit) limit = expectedAllowance[owner][spender];
        uint256 amount = bound(rawAmount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
        ++rejectedCalls;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 ownerBefore = expectedBalance[owner];
        uint256 toBefore = expectedBalance[to];
        bool shouldSucceed = amount <= ownerBefore && amount <= allowed;
        vm.prank(spender);
        (bool ok, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(ok, shouldSucceed);
        if (ok) {
            assertTrue(abi.decode(result, (bool)));
            if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
            _move(owner, to, amount);
            if (amount > 0) ++positiveSpends;
            assertEq(
                token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount
            );
            assertEq(token.balanceOf(owner), owner == to ? ownerBefore : ownerBefore - amount);
            assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
        } else {
            bytes memory expectedError = allowed < amount
                ? abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount
                )
                : abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, owner, ownerBefore, amount
                );
            assertEq(result, expectedError, "rejected spending must report the ERC20 error, not a panic");
            ++rejectedCalls;
            assertEq(token.allowance(owner, spender), allowed);
            assertEq(token.balanceOf(owner), ownerBefore);
            assertEq(token.balanceOf(to), toBefore);
        }
    }

    function _move(address from, address to, uint256 amount) private {
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDiddyInvariantTest is Test {
    IMDiddyToken internal token;
    TokenHandler internal handler;
    address[4] internal actors;
    uint256 internal constant SUPPLY = 1_000_000_000e18;

    function setUp() public {
        token = new IMDiddyToken();
        actors = [makeAddr("runner 1"), makeAddr("runner 2"), makeAddr("runner 3"), makeAddr("runner 4")];
        handler = new TokenHandler(token, actors);
        for (uint256 i; i < actors.length; ++i) {
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        selectors[3] = TokenHandler.spendAvailable.selector;
        selectors[4] = TokenHandler.revoke.selector;
        selectors[5] = TokenHandler.transferTooMuch.selector;
        selectors[6] = TokenHandler.transferToZero.selector;
        selectors[7] = TokenHandler.approveZeroSpender.selector;
        selectors[8] = TokenHandler.spendToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_eachHolderKeepsExactlyTheirTokens() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "holder ledger mismatch");
        }
    }

    function invariant_allowancesStayScopedAndMatchEveryApprovalAndSpend() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance ledger mismatch"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            assertEq(token.allowance(actors[i], address(this)), 0);
            assertEq(token.allowance(actors[i], address(handler)), 0);
        }
    }

    // This deterministic sequence proves the generator can exercise positive transfers,
    // finite/infinite delegated spending, revocation, and each rejected-call branch.
    function test_handlerSequenceExercisesAllActions() public {
        handler.transfer(0, 1, 10);
        _checkModel();
        handler.approve(1, 2, 8, false);
        handler.spendAvailable(1, 2, 3, 3);
        _checkModel();
        handler.spend(1, 2, 1, 2); // Self-transfer spends allowance but keeps the holder's balance.
        _checkModel();
        handler.spendToZero(1, 2, 3); // Finite allowance must survive the receiver rejection.
        _checkModel();
        handler.revoke(1, 2);
        handler.spend(1, 2, 3, 1);
        _checkModel();
        handler.approve(0, 2, 0, true);
        handler.spendAvailable(0, 2, 3, 1);
        handler.spend(0, 2, 3, SUPPLY + 1); // Sufficient allowance, insufficient balance.
        _checkModel();
        handler.transferTooMuch(0, 0, type(uint256).max);
        handler.transferToZero(0, 0);
        handler.approveZeroSpender(0, type(uint256).max);
        _checkModel();
        assertEq(handler.positiveTransfers(), 1);
        assertEq(handler.positiveSpends(), 3);
        assertEq(handler.rejectedCalls(), 6);
    }

    function _checkModel() private view {
        invariant_supplyAndBalancesAreConserved();
        invariant_eachHolderKeepsExactlyTheirTokens();
        invariant_allowancesStayScopedAndMatchEveryApprovalAndSpend();
    }
}
