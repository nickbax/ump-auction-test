//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Core errors
error Unauthorized();
error InvalidState();
error InvalidAddress();
error InvalidParameters();

contract AffiliateEscrow {
    using SafeERC20 for IERC20;

    // Escrow parties
    address public payee;
    address public payer;
    address public arbiter;
    address public storefront;
    address public affiliate;
    
    // State variables  
    address public escapeAddress;
    bool public isDisputed;
    bool public isSettled;
    uint256 public settleTime;
    bool private initialized;
    address public proposedArbiter;

    // Affiliate configuration
    uint16 public affiliateShare; // 0-10000 representing basis points

    // Events
    event Settled(address indexed to, address indexed affiliate, address token, uint256 amount, uint256 affiliateAmount);
    event Refunded(address indexed to, address token, uint256 amount);
    event Disputed(address indexed disputeInitiator);
    event DisputeRemoved(address indexed disputeRemover);
    event DisputeResolved(address indexed resolver, bool settled);
    event EscapeAddressSet(address indexed escapeAddress);
    event Escaped(address indexed to, address token, uint256 amount);
    event PayerSet(address indexed payer, uint256 settleDeadline);
    event ArbiterChangeProposed(address indexed oldArbiter, address indexed proposedArbiter);
    event ArbiterChangeApproved(address indexed oldArbiter, address indexed newArbiter, address indexed approver);

    modifier onlyArbiter() {
        if (msg.sender != arbiter) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyPayer() {
        if (msg.sender != payer) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyPayee() {
        if (msg.sender != payee) {
            revert Unauthorized();
        }
        _;
    }

    function initialize(
        address _payee,
        address _storefront,
        address _arbiter
    ) external {
        if (initialized) {
            revert InvalidState();
        }
        if (_payee == address(0) || _storefront == address(0) || _arbiter == address(0)) {
            revert InvalidAddress();
        }

        payee = _payee;
        storefront = _storefront;
        arbiter = _arbiter;
        initialized = true;
    }

    receive() external payable {}

    function setPayer(address _payer, uint256 settleDeadline) external {
        if (msg.sender != storefront) {
            revert Unauthorized();
        }
        if (payer != address(0)) {
            revert InvalidState();
        }
        payer = _payer;
        settleTime = block.timestamp + settleDeadline;
        emit PayerSet(_payer, settleTime);
    }

    function setAffiliate(address _affiliate, uint16 _affiliateShare) external {
        if (msg.sender != storefront) {
            revert Unauthorized();
        }
        if (affiliate != address(0)) {
            revert InvalidState(); // Affiliate already set
        }
        // Only validate affiliate share if there is an affiliate
        if (_affiliate != address(0) && _affiliateShare > 10000) {
            revert InvalidParameters();
        }
        affiliate = _affiliate;
        affiliateShare = _affiliate != address(0) ? _affiliateShare : 0;
    }

    function settle(address token, uint256 amount) external {
        if (isDisputed) {
            revert InvalidState();
        }
        if (msg.sender != payer && msg.sender != payee) {
            revert Unauthorized();
        }
        
        if (msg.sender == payee && !(isSettled || block.timestamp >= settleTime)) {
            revert InvalidState();
        }

        if (msg.sender == payer) {
            isSettled = true;
        }

        // Only split payment if there is an affiliate
        if (affiliate != address(0) && affiliateShare > 0) {
            uint256 affiliateAmount = (amount * affiliateShare) / 10000;
            uint256 payeeAmount = amount - affiliateAmount;
            
            _transferPayment(payee, token, payeeAmount);
            _transferPayment(affiliate, token, affiliateAmount);
            
            emit Settled(payee, affiliate, token, payeeAmount, affiliateAmount);
        } else {
            // If no affiliate, send everything to payee
            _transferPayment(payee, token, amount);
            emit Settled(payee, address(0), token, amount, 0);
        }
    }

    function refund(address token, uint256 amount) external onlyPayee {
        _transferPayment(payer, token, amount);
        emit Refunded(payer, token, amount);
    }

    function dispute() external onlyPayer {
        if (isSettled) {
            revert InvalidState();
        }
        isDisputed = true;
        emit Disputed(payer);
    }

    function removeDispute() external onlyPayer {
        if (!isDisputed) {
            revert InvalidState();
        }
        isDisputed = false;
        emit DisputeRemoved(payer);
    }

    function resolveDispute(bool shouldSettle, address token, uint256 amount) external onlyArbiter {
        if (!isDisputed) {
            revert InvalidState();
        }
        
        if (shouldSettle) {
            if (affiliate != address(0) && affiliateShare > 0) {
                uint256 affiliateAmount = (amount * affiliateShare) / 10000;
                uint256 payeeAmount = amount - affiliateAmount;
                
                _transferPayment(payee, token, payeeAmount);
                _transferPayment(affiliate, token, affiliateAmount);
                
                emit Settled(payee, affiliate, token, payeeAmount, affiliateAmount);
            } else {
                _transferPayment(payee, token, amount);
                emit Settled(payee, address(0), token, amount, 0);
            }
        } else {
            _transferPayment(payer, token, amount);
            emit Refunded(payer, token, amount);
        }
        
        emit DisputeResolved(msg.sender, shouldSettle);
    }

    function setEscapeAddress(address _escapeAddress) external onlyArbiter {
        if (_escapeAddress == address(0)) {
            revert InvalidAddress();
        }
        escapeAddress = _escapeAddress;
        emit EscapeAddressSet(_escapeAddress);
    }

    function changeArbiter(address _proposedArbiter) external onlyPayee {
        if (_proposedArbiter == address(0)) {
            revert InvalidAddress();
        }
        proposedArbiter = _proposedArbiter;
        emit ArbiterChangeProposed(arbiter, _proposedArbiter);
    }

    function approveArbiter(address _proposedArbiter) external onlyPayer {
        if (proposedArbiter == address(0) || _proposedArbiter != proposedArbiter) {
            revert InvalidParameters();
        }

        address oldArbiter = arbiter;
        arbiter = _proposedArbiter;
        proposedArbiter = address(0);

        emit ArbiterChangeApproved(oldArbiter, arbiter, msg.sender);
    }

    function escape(address token, uint256 amount, address _escapeAddress) external {
        if (msg.sender != payee && msg.sender != payer) {
            revert Unauthorized();
        }
        if (escapeAddress == address(0) || _escapeAddress != escapeAddress) {
            revert InvalidParameters();
        }

        _transferPayment(_escapeAddress, token, amount);
        emit Escaped(_escapeAddress, token, amount);
    }

    function _transferPayment(address to, address token, uint256 amount) private {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}