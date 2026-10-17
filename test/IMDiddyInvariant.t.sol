// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDiddyToken} from "../src/IMDiddyToken.sol";

/// @dev Exercises sequences of transfers, approvals and both valid/invalid delegated spending.
contract TokenHandler is Test {
    IMDiddyToken public immutable token;
    address[4] public actors;

    constructor(IMDiddyToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
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
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, token.INITIAL_SUPPLY());
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowed = token.allowance(owner, spender);
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, token.INITIAL_SUPPLY() + 1);
        bool shouldSucceed = amount <= ownerBefore && amount <= allowed;
        vm.prank(spender);
        (bool ok, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(ok, shouldSucceed);
        if (ok) {
            assertTrue(abi.decode(result, (bool)));
            assertEq(
                token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount
            );
            assertEq(token.balanceOf(owner), owner == to ? ownerBefore : ownerBefore - amount);
            assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
        } else {
            assertEq(token.allowance(owner, spender), allowed);
            assertEq(token.balanceOf(owner), ownerBefore);
            assertEq(token.balanceOf(to), toBefore);
        }
    }
}

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
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
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
    }
}
