// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { TokenPool } from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 token,
        address[] memory allowList,
        address rnmProxy,
        address router
    )
        TokenPool(token, 18, allowList, rnmProxy, router)
    { }
}
