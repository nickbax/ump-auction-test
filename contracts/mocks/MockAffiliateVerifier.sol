// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {IAffiliateVerifier} from "../../contracts/IAffiliateVerifier.sol";

contract MockAffiliateVerifier is IAffiliateVerifier {
    uint256 private multiplier = 10000; // Default 1.0 multiplier (10000 basis points)

    function setMultiplier(uint256 _multiplier) external {
        multiplier = _multiplier;
    }

    function getMultiplier(address) external view override returns (uint256) {
        return multiplier;
    }
}
