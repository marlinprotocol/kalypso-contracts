// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {INativeStaking} from "../../interfaces/staking/INativeStaking.sol";

contract NativeStakingReward is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    address public nativeStaking;
    address public feeRewardToken;
    address public inflationRewardToken;

    // reward is accrued per operator
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 rewardAmount))) rewards;
    // rewardTokens amount per stakeToken
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 rewardPerToken))) rewardPerTokens;

    mapping(address account => mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 rewardPerTokenPaid)))) userRewardPerTokenPaid;
    mapping(address account => mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 amount)))) claimableRewards;

    // TODO: (function) stake

    // TODO: (function) unstake

    // TODO: (function) claim reward

    // TODO: (function) update

    // TODO: (function) addReward

    //-------------------------------- Init start --------------------------------//

    function initialize(address _admin, address _nativeStaking) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setNativeStaking(_nativeStaking);
    }
    //-------------------------------- Init end --------------------------------//

    //-------------------------------- NativeStaking start --------------------------------//



    function claimReward(address token) public {
        
    }

    function addReward(address _stakeToken, address _operator, address _rewardToken, uint256 _amount) public {
        // TODO: only native staking

        rewards[_stakeToken][_operator][_rewardToken] += _amount;
        _update(address(0), _stakeToken, _operator, _rewardToken);
    }
    
    /// @notice pulls stake amount info from NativeStaking and updates
    /// @notice stake amount will be tracked in NativeStaking
    function update(address account, address _stakeToken, address _operator) public {
        // TODO: only native staking
        _update(account, _stakeToken, _operator, feeRewardToken);
        _update(account, _stakeToken, _operator, inflationRewardToken);
    }

    function _update(address account, address _stakeToken, address _operator, address _rewardToken) internal {
        uint256 currentRewardPerToken = _rewardPerToken(_stakeToken, _operator, _rewardToken);
        rewardPerTokens[_stakeToken][_operator][_rewardToken] = currentRewardPerToken;

        claimableRewards[account][_stakeToken][_operator][_rewardToken] += _pendingReward(account, _stakeToken, _operator, _rewardToken);
        userRewardPerTokenPaid[account][_stakeToken][_operator][_rewardToken] = currentRewardPerToken;
    }

    function _pendingReward(address account, address _stakeToken, address operator, address _rewardToken) internal view returns (uint256) {
        uint256 rewardPerTokenPaid = userRewardPerTokenPaid[account][_stakeToken][operator][_rewardToken];
        uint256 rewardPerToken = _rewardPerToken(_stakeToken, operator, _rewardToken);
        uint256 userStakeAmount = _getUserStakeAmount(account, _stakeToken, operator);

        return userStakeAmount.mulDiv(rewardPerToken - rewardPerTokenPaid, 1e18);
    }

    function _rewardPerToken(address _stakeToken, address _operator, address _rewardToken) internal view returns (uint256) {
        uint256 totalStakeAmount = _getTotalStakeAmountActive(_stakeToken, _operator);
        uint256 totalRewardAmount = rewards[_stakeToken][_operator][_rewardToken];

        // TODO: make sure decimal is 18
        return totalStakeAmount == 0
            ? rewardPerTokens[_stakeToken][_operator][_rewardToken]
            : rewardPerTokens[_stakeToken][_operator][_rewardToken] + totalRewardAmount.mulDiv(1e18, totalStakeAmount);
    }

    function _getTotalStakeAmountActive(address token, address operator) internal view returns (uint256) {
        // return INativeStaking(nativeStaking).getTotalStakeAmountActive(token, operator);
    }

    function _getUserStakeAmount(address account, address token, address operator) internal view returns (uint256) {
        // return INativeStaking(nativeStaking).getUserStakeAmount(account, token, operator);
    }

    function _getDelegatedStakeActive(address account, address token, address operator)
        internal
        view
        returns (uint256)
    {
        // return INativeStaking(nativeStaking).getDelegatedStakeActive(account, token, operator);
    }

    //-------------------------------- NativeStaking end --------------------------------//

    //-------------------------------- Overrides start --------------------------------//
    function setNativeStaking(address _nativeStaking) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setNativeStaking(_nativeStaking);
    }

    function _setNativeStaking(address _nativeStaking) internal {
        nativeStaking = _nativeStaking;
        // TODO: emit event
    }

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//
}
