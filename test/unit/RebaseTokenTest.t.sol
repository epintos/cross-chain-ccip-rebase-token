// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { RebaseToken } from "src/RebaseToken.sol";
import { Vault } from "src/Vault.sol";
import { IRebaseToken } from "src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");
    uint256 public constant INITIAL_VAULT_BALANCE = 1 ether;

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{ value: INITIAL_VAULT_BALANCE }("");
        vm.assertEq(success, true);
        vm.stopPrank();
    }
}
