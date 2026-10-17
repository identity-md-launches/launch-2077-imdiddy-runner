// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMDiddy Runner (IMDIDDY)
/// @notice A fixed-supply, 18-decimal ERC-20 with no administrative powers or transfer tax.
/// @dev The constructor caller receives the entire supply. During the IdentityMD launch,
///      that caller is the factory, which performs the launch allocations itself.
contract IMDiddyToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("IMDiddy Runner", "IMDIDDY") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
