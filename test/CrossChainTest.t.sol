// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { RebaseToken } from "src/RebaseToken.sol";
import { IRebaseToken } from "src/interfaces/IRebaseToken.sol";
import { RebaseTokenPool } from "src/RebaseTokenPool.sol";
import { Vault } from "src/Vault.sol";
import { IERC20 } from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import { CCIPLocalSimulatorFork, Register } from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import { RegistryModuleOwnerCustom } from
    "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import { TokenAdminRegistry } from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import { TokenPool } from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import { RateLimiter } from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbitrumSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    Vault vault;
    RebaseTokenPool sepoliaPool;
    Register.NetworkDetails sepoliaNetworkDetails;

    RebaseToken arbitrumSepoliaToken;
    RebaseTokenPool arbitrumSepoliaPool;
    Register.NetworkDetails arbitrumSepoliaNetworkDetails;

    address OWNER = makeAddr("OWNER");
    address USER = makeAddr("USER");

    string public constant FOUNDRY_TOML_SEPOLIA_ETH_KEY = "sepolia-eth";
    string public constant FOUNDRY_TOML_ARBITRUM_SEPOLIA_KEY = "arbitrum-sepolia";

    function setUp() public {
        sepoliaFork = vm.createSelectFork(FOUNDRY_TOML_SEPOLIA_ETH_KEY); // We select this chain first
        arbitrumSepoliaFork = vm.createFork(FOUNDRY_TOML_ARBITRUM_SEPOLIA_KEY);

        // https://docs.chain.link/chainlink-local/build/ccip/foundry/local-simulator-fork
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // Persists it in both chain
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Docs: https://docs.chain.link/ccip/tutorials/cross-chain-tokens/register-from-eoa-burn-mint-foundry
        // Sepolia ETH
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // Sepolia ETH is selected
        vm.startPrank(OWNER);
        sepoliaToken = new RebaseToken();
        // We only want to allow users to deposit and redeem in Sepolia ETH chain.
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );

        vm.stopPrank();

        // Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);
        arbitrumSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbitrumSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbitrumSepoliaToken)),
            new address[](0),
            arbitrumSepoliaNetworkDetails.rmnProxyAddress,
            arbitrumSepoliaNetworkDetails.routerAddress
        );
        vm.startPrank(OWNER);
        sepoliaToken.grantMintAndBurnRole(address(arbitrumSepoliaPool));
        RegistryModuleOwnerCustom(arbitrumSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbitrumSepoliaToken)
        );
        TokenAdminRegistry(arbitrumSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(
            address(arbitrumSepoliaToken)
        );
        TokenAdminRegistry(arbitrumSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbitrumSepoliaToken), address(arbitrumSepoliaPool)
        );
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbitrumSepoliaNetworkDetails.chainSelector,
            address(arbitrumSepoliaPool),
            address(arbitrumSepoliaToken)
        );
        configureTokenPool(
            arbitrumSepoliaFork,
            address(arbitrumSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    )
        public
    {
        vm.selectFork(fork);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({ isEnabled: false, capacity: 0, rate: 0 }),
            inboundRateLimiterConfig: RateLimiter.Config({ isEnabled: false, capacity: 0, rate: 0 })
        });
        vm.prank(OWNER);
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    )
        public
    {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({ token: address(localToken), amount: amountToBridge });
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(USER), // Sending it to itself assuming the address is the same in both chains
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress, // We pay fees in LINK
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: 0 }))
        });
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(USER, fee);

        vm.startPrank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(USER);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        vm.stopPrank();

        assertEq(localToken.balanceOf(USER), localBalanceBefore - amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(USER);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes); // Wait for the messages to propagate
        uint256 remoteBalanceBefore = remoteToken.balanceOf(USER);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork); // Propagates message and sends it across chain

        assertEq(remoteToken.balanceOf(USER), remoteBalanceBefore + amountToBridge);
        uint256 remoteUserInterestRate = localToken.getUserInterestRate(USER);
        assertEq(remoteUserInterestRate, localUserInterestRate);
    }
}
