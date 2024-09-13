// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
/* 
    Unlike common staking contracts, this contract is interacted each time snapshot is submitted to Symbiotic Staking,
    which means the state of each vault address will be updated whenvever snapshot is submitted.
*/

contract SymbioticStakingReward is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // TODO: staking token enability should be pulled from SymbioticStaking contract
    
    // TODO: fee token
    // TODO: reward token

    //? what should be done when stake is locked?
    // -> just update totalStakeAmount and rewardPerToken?
    // -> does this even affect anything?

    mapping(address token => uint256 amount) public poolReward;
    mapping(address token => uint256 rewardPerToken) public rewardPerTokens;
    mapping(uint256 captureTimestamp => mapping(address token => uint256 totalStakeAmount)) public totalStakeAmount;

    // token supported by the vault can be queried in SymbioticStaking contract
    mapping(uint256 captureTimestamp => mapping(address vault => uint256 amount)) public vaultStakeAmount;
    mapping(uint256 captureTimestamp => mapping(address vault => uint256 rewardPerTokenPaid)) public vaultRewardPerTokenPaid;
    mapping(address vault => uint256 reward) public vaultReward;

    address public symbioticStaking;

    // TODO: (array) confirmed timestamp
    // probably read from StakingManager

    // TODO: (function) function that updates confirmed timestamp
    // this should be called by StakingManager contract when partial txs are completed

    // TODO: (function) updates reward per token for each submission


    // TODO: claim

    modifier onlySymbioticStaking() {
        require(_msgSender() == symbioticStaking, "Caller is not the staking manager");
        _;
    }

    //-------------------------------- Init start --------------------------------//

    function initialize(address _admin, address _stakingManager) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        symbioticStaking = _stakingManager;
    }

    //-------------------------------- Init end --------------------------------//


    //-------------------------------- StakingManager start --------------------------------//

    /// @notice updates stake amount of a given vault
    /// @notice valid only if captureTimestamp is pushed into confirmedTimestamp in SymbioticStaking when submission is completed
    /// @dev only can be called by SymbioticStaking contract
    // TODO: check how to get _token address (probably gets pulled from SymbioticStkaing contract)
    function updateVaultStakeAmount(uint256 _captureTimestamp, address _token, address _vault, uint256 _amount) external onlySymbioticStaking {
        _update(_captureTimestamp, _vault, _token, _amount);

        vaultStakeAmount[_captureTimestamp][_vault] = _amount;
        // TODO: emit events?
    }

    function getLatestConfirmedTimestamp() external view returns (uint256) {
        return _getLatestConfirmedTimestamp();
    }

    function _rewardPerToken(address _token) internal view returns (uint256) {
        uint256 _latestConfirmedTimestamp = _getLatestConfirmedTimestamp();
        uint256 _totalStakeAmount = totalStakeAmount[_latestConfirmedTimestamp][_token];
        uint256 _rewardAmount = poolReward[_token];

        // TODO: check
        return _totalStakeAmount == 0 ? rewardPerTokens[_token] : rewardPerTokens[_token] + (_rewardAmount * 1e18) / _totalStakeAmount;
    }

    function _getLatestConfirmedTimestamp() internal view returns (uint256) {
        return ISymbioticStaking(symbioticStaking).lastConfirmedTimestamp();
    }

    //-------------------------------- StakingManager end --------------------------------//

    //-------------------------------- Update start --------------------------------//

    // called 1) when updated by StakingManager 2) 
    function _update(uint256 _captureTimestamp, address _vault, address _token, uint256 _totalStakeAmount) internal {
        // TODO: update logic for add reward

        uint256 currentRewardPerToken = _rewardPerToken(_token);
        rewardPerTokens[_token] = currentRewardPerToken;

        // update reward for each vault
        vaultReward[_vault] += _pendingReward(_vault, _token);
        vaultRewardPerTokenPaid[_captureTimestamp][_vault] = currentRewardPerToken;
    }

    function _pendingReward(address _vault, address _token) internal view returns (uint256) {
        uint256 _latestConfirmedTimestamp = _getLatestConfirmedTimestamp();
        uint256 _rewardPerTokenPaid = vaultRewardPerTokenPaid[_latestConfirmedTimestamp][_vault];
        uint256 _rewardPerToken = _rewardPerToken(_token);

        return (vaultStakeAmount[_latestConfirmedTimestamp][_vault] * (_rewardPerToken - _rewardPerTokenPaid)) / 1e18; // TODO muldiv
    }

    //-------------------------------- Update end --------------------------------//


    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Admin start --------------------------------//
    function setStakingManager(address _stakingManager) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not an admin");

        symbioticStaking = _stakingManager;
        // TODO: emit event
    }

    //-------------------------------- Admin end --------------------------------//


}
