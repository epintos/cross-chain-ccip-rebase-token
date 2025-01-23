// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TokenPool } from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import { Pool } from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import { IERC20 } from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import { IRebaseToken } from "src/interfaces/IRebaseToken.sol";

/**
 * @title RebaseTokenPool
 * @author Esteban Pintos
 * @notice This contract is a custom token pool that allows users to send tokens cross-chain using Chailink CCIP.
 * @notice It uses a lock/burn and release/mint mechanism to send tokens from one chain to another.
 * @notice This contract needs to be deployed in the origin and destination chain.
 *
 * @notice More info: https://docs.chain.link/ccip/concepts/cross-chain-tokens#custom-token-pools
 */
contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 token,
        address[] memory allowList,
        address rnmProxy,
        address router
    )
        TokenPool(token, allowList, rnmProxy, router)
    { }

    /**
     * @notice This function is called by CCIP when we want to send tokens from the chain this contract is deployed to,
     * to another chain.
     * @notice It sends the original sender current interest rate that will be used to update the interest rate in the
     * destination chain.
     * @param lockOrBurnIn The input data for the lock or burn operation. Includes the originalSender and the amount.
     * @return lockOrBurnOut The output data for the lock or burn operation, including the destination token address
     * and the interest rate of the originalSender.
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        // Makes validations
        _validateLockOrBurn(lockOrBurnIn);
        // i_token is the token address in the source chain
        uint256 userInterest = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);

        // 1. Sender makes a token approval and sends tokens to CCIP
        // 2. CCIP sends tokens to the pool, that's why we use address(this)
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector), // token address in the destination
                // chain
            destPoolData: abi.encode(userInterest)
        });
    }

    /**
     * @notice This function is called by CCIP when this contract is receiving tokens from another chain.
     * @param releaseOrMintIn The input data for the release or mint operation, including the receiver, the amount
     * and the interest rate in the source chain.
     * @return releaseOrMintOut The output data for the release or mint operation, including the amount of tokens
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);

        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({ destinationAmount: releaseOrMintIn.amount });
    }
}
