// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { Vault } from "src/Vault.sol";
import { RebaseToken } from "src/RebaseToken.sol";
import { RebaseTokenPool } from "src/RebaseTokenPool.sol";
import { IRebaseToken } from "src/interfaces/IRebaseToken.sol";
import { IERC20 } from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import { CCIPLocalSimulatorFork, Register } from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import { RegistryModuleOwnerCustom } from
    "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import { TokenAdminRegistry } from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

contract TokenAndPoolDeployer is Script {
    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        // https://docs.chain.link/ccip/tutorials/cross-chain-tokens/register-from-eoa-burn-mint-foundry
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        address[] memory allowlist = new address[](0);

        vm.startBroadcast();
        token = new RebaseToken();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        pool = new RebaseTokenPool(
            IERC20(address(token)), allowlist, networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );

        vm.stopBroadcast();
    }
}

contract SetPermissions is Script {
    function grantRole(address token, address pool) public {
        vm.startBroadcast();
        IRebaseToken(token).grantMintAndBurnRole(address(pool));
        vm.stopBroadcast();
    }

    function setAdmin(address token, address pool) public {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startBroadcast();
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(token), address(pool));
        vm.stopBroadcast();
    }
}

contract VaultDeployer is Script {
    function run(address rebaseToken) public returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(rebaseToken));
        IRebaseToken(rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
    }
}
