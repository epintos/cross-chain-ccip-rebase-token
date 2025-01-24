-include .env

.PHONY: all test deploy

build :; forge build

test :; forge test

install :
	forge install foundry-rs/forge-std@v1.9.5 --no-commit && \
	forge install smartcontractkit/ccip@v2.17.0-ccip1.5.16 --no-commit && \
	forge install openzeppelin/openzeppelin-contracts@v5.2.0 --no-commit && \
	forge install smartcontractkit/chainlink-local@7d8b2f888e1f10c8841ccd9e0f4af0f5baf11dab --no-commit

deploy-and-bridge-sepolia-zksync:
	chmod +x ./bridgeToZkSync.sh && \
	./bridgeToZksync.sh

deploy-and-bridge-sepolia-arbitrum:
	chmod +x ./bridgeToArbitrumSepolia.sh && \
	./bridgeToArbitrumSepolia.sh
