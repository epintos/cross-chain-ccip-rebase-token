// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Esteban Pintos
 * @notice This contract is a cross-chain rebase token that incentivises users to deposit into a vault and gain
 * interest.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will own interest rate that is the global interest rate at the time of depositing.
 * @notice Known issue: Total supply is the total amount of tokens minted in the contract, without considering interests
 * accrued.
 */
contract RebaseToken is ERC20, AccessControl {
    /// ERRORS ///
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    /// STATE VARIABLES ///
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 5e10 -> 0.000005% per second
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 timestamp) private s_userLastInterestUpdatedTimestamp;

    /// EVENTS ///
    event InterestRateSet(uint256 indexed newInterestRate);

    /// FUNCTIONS ///

    // CONSTRUCTOR
    constructor() ERC20("Rebase Token", "RBT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Grant the mint and burn role to an account
     * @notice Known issue: The owner of the contract can give the access to itself, which will make this contract a bit
     * centralized on the owner.
     * @param account The account to grant the mint and burn role
     */
    function grantMintAndBurnRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINT_AND_BURN_ROLE, account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param newInterestRate The new interest rate
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 newInterestRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, newInterestRate);
        }
        s_interestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @notice Mints any pending interest accrued since the last update
     * @notice Updates the user's interest rate to the current interest rate, which will be lower. This avoids users
     * minting a very small amount at the beginning to take advantage of the high interest rate.
     * @param to The user to mint the tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(to);
        s_userInterestRate[to] = s_interestRate;
        _mint(to, amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param from The user to burn the tokens from
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(from);
        _burn(from, amount);
    }

    // PUBLIC FUNCTIONS

    /**
     * Calculate the balance of the user including the interest accrued since the last update (principle balance +
     * interest)
     * @param user The user address to calculate the balance for
     * @return The balance of the user including the interest accrued since the last update
     */
    function balanceOf(address user) public view override returns (uint256) {
        return (super.balanceOf(user) * _calculateUserAccruedInterestSinceLastUpdate(user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from the sender to the recipient by minting the accrued interest for both users
     * @param recipient The recipient of the tokens.
     * @param amount The amount of tokens to transfer. If the amount is the maximum uint256, it will transfer the entire
     * balance.
     * @return True if the transfer was successful.
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        amount = _accrueInterestBeforeTransferAndUpdatesInterestRate(msg.sender, recipient, amount);
        return super.transfer(recipient, amount);
    }

    /**
     * @notice Transfer tokens from the sender to the recipient by minting the accrued interest for both users
     * @param recipient The recipient of the tokens.
     * @param amount The amount of tokens to transfer. If the amount is the maximum uint256, it will transfer the entire
     * balance.
     * @return True if the transfer was successful.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        amount = _accrueInterestBeforeTransferAndUpdatesInterestRate(sender, recipient, amount);
        return super.transferFrom(sender, recipient, amount);
    }

    // PRIVATE & INTERNAL VIEW FUNCTIONS

    /**
     * @notice Accrues the interest for the sender and recipient before transferring the tokens.
     * @notice If the recipient has no balance, it will inherit the sender's interest rate.
     * @notice Konwn issue: A user owning two wallets can get lower interest rates by transferring the tokens to the
     * wallet with highest interest rate. This would allow the user to mint a low amount of tokens at the beginning and
     * then transfer them to the wallet with the highest interest rate. A possible solution is to set the current
     * interest rate of the contract.
     * @param sender The sender of the tokens.
     * @param recipient The recipient of the tokens.
     * @param amount The amount of tokens to transfer.
     * @return amount The amount of tokens to transfer. If the amount is the maximum uint256, it will return the entire
     * balance.
     */
    function _accrueInterestBeforeTransferAndUpdatesInterestRate(
        address sender,
        address recipient,
        uint256 amount
    )
        private
        returns (uint256)
    {
        _mintAccruedInterest(sender);
        _mintAccruedInterest(recipient);
        if (amount == type(uint256).max) {
            amount = balanceOf(sender);
        }
        if (balanceOf(recipient) == 0) {
            s_userInterestRate[recipient] = s_userInterestRate[sender];
        }
        return amount;
    }

    /**
     * @notice Calculate the interest accrued for the user since the last update
     * @notice Known issue: If the user interactrs with the contract multiple times, the interest might turn into a
     * compounding interest.
     * @param user The user address to calculate the interest for
     * @return linearInterest The interest accrued for the user since the last update
     */
    function _calculateUserAccruedInterestSinceLastUpdate(address user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastInterestUpdatedTimestamp[user];
        // 1 + interestRate * timeElapsed
        // The 1 would the balance of the user since it is getting multipled in the balanceOf function
        linearInterest = PRECISION_FACTOR + s_userInterestRate[user] * timeElapsed;
    }

    /**
     * @notice Mint the acrrued interest for the user since the last time they interacted with the protocol (e.g. burn,
     * mint or transfer).
     * @param user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(user);
        uint256 currentBalance = balanceOf(user);
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        s_userLastInterestUpdatedTimestamp[user] = block.timestamp;
        _mint(user, balanceIncrease);
    }

    // PUBLIC & EXTERNAL VIEW FUNCTIONS

    /**
     * @notice Get the interest rate for the user
     * @param user The user address
     * @return The interest rate for the user
     */
    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }

    /**
     * @notice Get the minted balance of the user. This balance does not include any pending interest accrued since the
     * last update.
     * @param user The user address to calculate the balance for
     */
    function getPrincipleBalanceOf(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice Get the interest rate that is currently set for the contract. Any future depositers will receive this
     * interest rate
     * @return The interest rate in the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
