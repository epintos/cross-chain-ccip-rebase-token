// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { IRebaseToken } from "./interfaces/IRebaseToken.sol";

contract Vault {
    /// ERRORS ///
    error Vault__RedeemFailed();

    /// STATE VARIABLES ///
    IRebaseToken private immutable i_rebaseToken;

    /// EVENTS ///
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    /// FUNCTIONS ///

    // CONSTRUCTOR
    constructor(IRebaseToken rebaseToken) {
        i_rebaseToken = rebaseToken;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Allows the contract to reveive ETH.
     */
    receive() external payable { }

    /**
     * @notice Allows user to deposit ETH into the vault and mint rebase tokens in return.
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows user to redeem rebase tokens for ETH.
     * @param amount The amount of rebase tokens to redeem.
     */
    function redeem(uint256 amount) external {
        // TODO: Does burn need to return the amount for the type(uint256).max case?
        i_rebaseToken.burn(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, amount);
    }

    // PUBLIC FUNCTIONS

    // PRIVATE & INTERNAL VIEW FUNCTIONS

    // PUBLIC & EXTERNAL VIEW FUNCTIONS

    /**
     * @notice Get the rebase token address
     * @return The rebase token address
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
