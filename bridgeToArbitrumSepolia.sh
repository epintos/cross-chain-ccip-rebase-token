#!/bin/bash

# Script that deploys contracts to Sepolia and Arbitrum Sepolia and bridges funds between them

# Define constants 
AMOUNT=100000

# https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia
SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM="0x62e731218d0D47305aba2BE3751E7EE9E5520790"
SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"
SEPOLIA_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"
SEPOLIA_RNM_PROXY_ADDRESS="0xba3f6251de62dED61Ff98590cB2fDf6871FbB991"
SEPOLIA_CHAIN_SELECTOR="16015286601757825753"
SEPOLIA_LINK_ADDRESS="0x779877A7B0D9E8603169DdbD7836e478b4624789"

# https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia-arbitrum-1
ARBITRUM_REGISTRY_MODULE_OWNER_CUSTOM="0xE625f0b8b0Ac86946035a7729Aba124c8A64cf69"
ARBITRUM_TOKEN_ADMIN_REGISTRY="0x8126bE56454B628a88C17849B9ED99dd5a11Bd2f"
ARBITRUM_ROUTER="0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165"
ARBITRUM_RNM_PROXY_ADDRESS="0x9527E2d01A3064ef6b50c1Da1C0cC523803BCFF2"
ARBITRUM_SEPOLIA_CHAIN_SELECTOR="3478487238524512106"
ARBITRUM_LINK_ADDRESS="0xb1D4538B4571d411F07960EF2838Ce337FE1E80E"


# Compile and deploy the Rebase Token contract
source .env
ACCOUNT=${SEPOLIA_ACCOUNT}
forge build 

# 1. Arbitrum Sepolia setup
echo "Running the script to deploy the contracts on Arbitrum..."
output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast)
echo "Contracts deployed on Arbitrum"

# Extract the addresses from the output
ARBITRUM_SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
ARBITRUM_SEPOLIA_POOL_ADDRESS=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Arbitrum rebase token address: $ARBITRUM_SEPOLIA_REBASE_TOKEN_ADDRESS"
echo "Arbitrum pool address: $ARBITRUM_SEPOLIA_POOL_ADDRESS"

# echo "Setting the permissiona dn CCIP admin on Arbitrum Sepolia..."
forge script ./script/Deployer.s.sol:SetPermissions --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "grantRole(address,address)" ${ARBITRUM_SEPOLIA_REBASE_TOKEN_ADDRESS} ${ARBITRUM_SEPOLIA_POOL_ADDRESS}
forge script ./script/Deployer.s.sol:SetPermissions --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "setAdmin(address,address)" ${ARBITRUM_SEPOLIA_REBASE_TOKEN_ADDRESS} ${ARBITRUM_SEPOLIA_POOL_ADDRESS}

# Configure the pool on Arbitrum
echo "Configuring the pool on Arbitrum..."
# uint64 remoteChainSelector,
#         address remotePoolAddress, /
#         address remoteTokenAddress, /
#         bool outboundRateLimiterIsEnabled, false 
#         uint128 outboundRateLimiterCapacity, 0
#         uint128 outboundRateLimiterRate, 0
#         bool inboundRateLimiterIsEnabled, false 
#         uint128 inboundRateLimiterCapacity, 0 
#         uint128 inboundRateLimiterRate 0 
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" ${ARBITRUM_SEPOLIA_POOL_ADDRESS} ${ARBITRUM_SEPOLIA_CHAIN_SELECTOR} ${ARBITRUM_SEPOLIA_POOL_ADDRESS} ${ARBITRUM_SEPOLIA_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0

# 2. Sepolia ETH setup

echo "Running the script to deploy the contracts on Sepolia..."
output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY})
echo "Contracts deployed on Sepolia"

# Extract the addresses from the output
SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
SEPOLIA_POOL_ADDRESS=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Sepolia rebase token address: $SEPOLIA_REBASE_TOKEN_ADDRESS"
echo "Sepolia pool address: $SEPOLIA_POOL_ADDRESS"

# echo "Setting the permissiona on CCIP admin on Sepolia..."
forge script ./script/Deployer.s.sol:SetPermissions --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "grantRole(address,address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${SEPOLIA_POOL_ADDRESS}
forge script ./script/Deployer.s.sol:SetPermissions --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "setAdmin(address,address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${SEPOLIA_POOL_ADDRESS}

# Deploy the vault 
echo "Deploying the vault on Sepolia..."
VAULT_ADDRESS=$(forge script ./script/Deployer.s.sol:VaultDeployer --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "run(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} | grep 'vault: contract Vault' | awk '{print $NF}')
echo "Vault address: $VAULT_ADDRESS"

# Configure the pool on Sepolia
echo "Configuring the pool on Sepolia..."
# uint64 remoteChainSelector,
#         address remotePoolAddress, /
#         address remoteTokenAddress, /
#         bool outboundRateLimiterIsEnabled, false 
#         uint128 outboundRateLimiterCapacity, 0
#         uint128 outboundRateLimiterRate, 0
#         bool inboundRateLimiterIsEnabled, false 
#         uint128 inboundRateLimiterCapacity, 0 
#         uint128 inboundRateLimiterRate 0 
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" ${SEPOLIA_POOL_ADDRESS} ${ARBITRUM_SEPOLIA_CHAIN_SELECTOR} ${ARBITRUM_SEPOLIA_POOL_ADDRESS} ${ARBITRUM_SEPOLIA_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0

# Deposit funds to the vault
echo "Depositing funds to the vault on Sepolia..."
cast send ${VAULT_ADDRESS} --value ${AMOUNT} --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} "deposit()"

# Wait a beat for some interest to accrue

# Bridge the funds using the script to Arbitrum Sepolia 
echo "Bridging the funds using the script to Arbitrum Sepolia..."
WALLET_ADDRESS=$(cast wallet address --account ${ACCOUNT})
SEPOLIA_BALANCE_BEFORE=$(cast balance ${WALLET_ADDRESS} --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance before bridging: $SEPOLIA_BALANCE_BEFORE"
# address receiverAddress,
# uint64 destinationChainSelector,
# address tokenToSendAddress,
# uint256 amountToSend,
# address linkTokenAddress,
# address routerAddress
forge script ./script/BridgeTokens.s.sol:BridgeTokensScript --rpc-url ${SEPOLIA_RPC_URL} --account ${ACCOUNT} --broadcast --sig "run(address,uint64,address,uint256,address,address)" ${WALLET_ADDRESS} ${ARBITRUM_SEPOLIA_CHAIN_SELECTOR} ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${AMOUNT} ${SEPOLIA_LINK_ADDRESS} ${SEPOLIA_ROUTER}
# Check transaction in CCIP exporer: https://ccip.chain.link/
echo "Funds bridged to Arbitrum Sepolia"

SEPOLIA_BALANCE_AFTER=$(cast balance ${WALLET_ADDRESS} --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance after bridging: $SEPOLIA_BALANCE_AFTER"



