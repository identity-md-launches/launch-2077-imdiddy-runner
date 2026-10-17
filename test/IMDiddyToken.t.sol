// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDiddyToken} from "../src/IMDiddyToken.sol";

/// @dev Local factory model only; never deployed as part of the launch.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (IMDiddyToken) {
        return new IMDiddyToken{salt: salt}();
    }

    function move(IMDiddyToken token, address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }
}

contract RejectingReceiver {
    fallback() external {
        revert("ERC20 transfers must not call recipients");
    }
}

contract IMDiddyTokenTest is Test {
    IMDiddyToken internal token;
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new IMDiddyToken();
    }

    function test_metadataAndExactSupply() public view {
        assertEq(token.name(), "IMDiddy Runner");
        assertEq(token.symbol(), "IMDIDDY");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsSingleMint() public {
        vm.recordLogs();
        IMDiddyToken fresh = new IMDiddyToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2FactoryReceivesEverythingThenDistributesExactAmounts() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("local launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(IMDiddyToken).creationCode)
                        )
                    )
                )
            )
        );
        IMDiddyToken launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        address distributor = makeAddr("local distributor");
        address pool = makeAddr("local pool settlement account");
        address remainder = makeAddr("local remainder recipient");
        factory.move(launched, distributor, SUPPLY * 10 / 100);
        factory.move(launched, pool, SUPPLY * 88 / 100);
        factory.move(launched, remainder, SUPPLY * 2 / 100);
        assertEq(launched.balanceOf(distributor), 100_000_000e18);
        assertEq(launched.balanceOf(pool), 880_000_000e18);
        assertEq(launched.balanceOf(remainder), 20_000_000e18);
        assertEq(launched.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, 100_000_000e18));
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 1_000e18));
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 1_000e18));
        assertEq(launched.balanceOf(alice), 100_000_000e18);
        assertEq(launched.balanceOf(pool), 880_000_000e18);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 15e18);
        assertTrue(token.transfer(alice, 15e18));
        assertEq(token.balanceOf(alice), 15e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 15e18);
    }

    function test_zeroTransferFromEmptyAccountEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferToContractDoesNotCallReceiver() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1e18));
        assertEq(token.balanceOf(address(receiver)), 1e18);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsAndCanReplaceOrRevokeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 42e18);
        assertTrue(token.approve(spender, 42e18));
        assertEq(token.allowance(address(this), spender), 42e18);
        assertTrue(token.approve(spender, 10e18));
        assertEq(token.allowance(address(this), spender), 10e18);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromUsesAllowanceAndEmits() public {
        token.approve(spender, 50e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20e18));
        assertEq(token.allowance(address(this), spender), 30e18);
        assertEq(token.balanceOf(alice), 20e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20e18);
    }

    function test_infiniteAllowanceDoesNotDecrease() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowanceButRejectsZeroSender() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        // _spendAllowance validates the approver before _transfer validates the sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowance() public {
        token.approve(spender, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10e18);
        assertEq(token.allowance(address(this), spender), 10e18);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 5e18);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 5e18)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 5e18);
        assertEq(token.allowance(alice, spender), 5e18);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_revokedAllowanceCannotBeSpent() public {
        token.approve(spender, 1e18);
        token.approve(spender, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_deployerCannotSpendHolderFundsWithoutApproval() public {
        token.transfer(alice, 7e18);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 7e18);
    }

    function test_noMintBurnAdminOrUpgradeEntrypoints() public {
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, 1e18);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1e18);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1e18);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1e18);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[11] = abi.encodeWithSignature("initialize(address)", alice);
        calls[12] = abi.encodeWithSignature("setMinter(address)", alice);
        calls[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[14] = abi.encodeWithSignature("owner()");
        token.transfer(alice, 2e18);
        for (uint256 i; i < calls.length; ++i) {
            (bool byDeployer,) = address(token).call(calls[i]);
            assertFalse(byDeployer);
            vm.prank(bob);
            (bool byStranger,) = address(token).call(calls[i]);
            assertFalse(byStranger);
        }
        assertEq(token.balanceOf(alice), 2e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 2e18));
        assertEq(token.balanceOf(bob), 2e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noPayableOrFallbackEntrypoint() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1 ether}("");
        assertFalse(paid);
        assertEq(address(token).balance, 0);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
    }

    function test_runtimeSizeAndForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            }
        }
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount
            )
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_transferFromCannotExceedAllowance(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY - 1);
        uint256 amount = approved + bound(excess, 1, SUPPLY - approved);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_transferFromSpendsExactly(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
