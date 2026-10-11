// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Inference Backed Endogenous Financial Re (INFER)
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract INFERToken is ERC20 {
    /// @notice One billion tokens, expressed in the smallest unit (10^18 units per token).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer (the factory on launch).
    constructor() ERC20("Inference Backed Endogenous Financial Re", "INFER") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
