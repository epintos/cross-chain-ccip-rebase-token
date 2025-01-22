// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

contract Vault {
    /// ERRORS ///

    /// STATE VARIABLES ///
    address private immutable i_rebaseToken;

    /// EVENTS ///

    /// FUNCTIONS ///

    // CONSTRUCTOR
    constructor(address rebaseToken) {
        i_rebaseToken = rebaseToken;
    }

    // EXTERNAL FUNCTIONS

    // PUBLIC FUNCTIONS

    // PRIVATE & INTERNAL VIEW FUNCTIONS

    // PUBLIC & EXTERNAL VIEW FUNCTIONS
    function getRebaseTokenAddress() external view returns (address) {
        return i_rebaseToken;
    }
}
