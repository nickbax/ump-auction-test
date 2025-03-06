// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAffiliateVerifier} from "./IAffiliateVerifier.sol";

/**
 * @title AffiliateVerifier
 * @notice A placeholder implementation that validates all non-zero addresses as affiliates with a 1.0 multiplier.
 * This contract is upgradeable and will be enhanced with more complex validation logic in the future.
 */
contract AffiliateVerifier is IAffiliateVerifier, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
    }

    /// @inheritdoc IAffiliateVerifier
    function getMultiplier(address affiliate) external view returns (uint256 multiplier) {
        // Placeholder implementation - returns 1.0 multiplier for any non-zero address
        return affiliate != address(0) ? 10000 : 0; // 10000 basis points = 1.0
    }

    // Required override for UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

contract AffiliateVerifierProxy is ERC1967Proxy {
    constructor(
        address implementation,
        bytes memory _data
    ) ERC1967Proxy(implementation, _data) {}
}