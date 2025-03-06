// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

interface IAffiliateVerifier {
    /// @notice Gets the multiplier for an affiliate address
    /// @param affiliate The address to verify
    /// @return multiplier The multiplier for this affiliate in basis points (10000 = 1.0)
    ///                   Returns 0 if the address is not a valid affiliate
    function getMultiplier(address affiliate) external view returns (uint256 multiplier);
}