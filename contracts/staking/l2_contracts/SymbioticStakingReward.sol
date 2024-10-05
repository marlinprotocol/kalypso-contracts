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

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Struct} from "../../lib/staking/Struct.sol";

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
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    address public jobManager;
    address public stakingPool;

    address public feeRewardToken;
    address public inflationRewardToken;

    /* 
        rewardToken: Fee Reward, Inflation Reward
        stakeToken: staking token
    */

    // total amount staked for each stakeToken
    // notice: the total amount can be reduced when a job is created and the stake is locked
    mapping(uint256 captureTimestamp => mapping(address stakeToken => uint256 amount)) public totalStakeAmounts;

    // locked amount for each stakeToken upon job creation
    mapping(uint256 captureTimestamp => mapping(address stakeToken => uint256 amount)) public lockedStakeAmounts;

    // reward accrued per operator
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 amount))) rewards;

    // rewardTokens amount per stakeToken
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 rewardPerToken)))
        rewardPerTokenStored;

    mapping(
        address vault
            => mapping(
                address stakeToken
                    => mapping(address operator => mapping(address rewardToken => uint256 rewardPerTokenPaid))
            )
    ) rewardPerTokenPaids;

    // reward accrued that the vault can claim
    mapping(address vault => mapping(address rewardToken => uint256 amount)) public rewardAccrued;

    address public symbioticStaking;

    // TODO: vault => claimAddress
    modifier onlySymbioticStaking() {
        require(_msgSender() == symbioticStaking, "Caller is not the staking manager");
        _;
    }

    /*============================================= init =============================================*/
    // TODO: initialize contract addresses
    function initialize(address _admin, address _stakingManager) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        _setStakingManager(_stakingManager);
    }

    /*============================================= external functions =============================================*/

    /* ------------------------- reward update ------------------------- */

    /// @notice called when fee reward is generated
    function updateFeeReward(address _stakeToken, address _operator, uint256 _rewardAmount) external onlySymbioticStaking {
        rewards[_stakeToken][_operator][feeRewardToken] += _rewardAmount;
        rewardPerTokenStored[_stakeToken][_operator][feeRewardToken] += _rewardAmount.mulDiv(1e18, _getOperatorStakeAmount(_operator, _stakeToken));
    }

    /// @notice called when inflation reward is generated
    function updateInflationReward(address _operator, uint256 _rewardAmount) external onlySymbioticStaking {
        address[] memory stakeTokenLost = _getStakeTokenList();
        for(uint256 i = 0; i < stakeTokenLost.length; i++) {
            rewards[stakeTokenLost[i]][_operator][inflationRewardToken] += _rewardAmount;
            rewardPerTokenStored[stakeTokenLost[i]][_operator][inflationRewardToken] += _rewardAmount.mulDiv(1e18, _getOperatorStakeAmount(_operator, stakeTokenLost[i]));
        }
    }

    /* ------------------------- symbiotic staking ------------------------- */

    function onSnapshotSubmission(Struct.VaultSnapshot calldata _vaultSnapshots) external onlySymbioticStaking {
        // TODO: update rewardPerToken for each stakeToken
    }

    /*============================================= external view functions =============================================*/
        
    // TODO: needed?
    // function getLatestConfirmedTimestamp() external view returns (uint256) {
    //     return _latestConfirmedTimestamp();
    // }

    // function getRewardTokens() external view returns (address[] memory) {
    //     address[] memory _rewardTokens = new address[](_rewardTokenSet.length());
    //     uint256 len = _rewardTokenSet.length();
    //     for (uint256 i = 0; i < len; i++) {
    //         _rewardTokens[i] = _rewardTokenSet.at(i);
    //     }
    //     return _rewardTokens;
    // }

    // /// @notice rewardToken amount per stakeToken
    // function _rewardPerToken(address _stakeToken, address _rewardToken, address _operator)
    //     internal
    //     view
    //     returns (uint256)
    // {
    //     uint256 operatorStakeAmount = _getOperatorStakeAmount(_operator, _stakeToken);
    //     uint256 rewardAmount = rewards[_rewardToken][_stakeToken];

    //     return operatorStakeAmount == 0
    //         ? rewardPerTokenStored[_stakeToken][_operator][_rewardToken]
    //         : rewardPerTokenStored[_stakeToken][_operator][_rewardToken]
    //             + totalRewardAmount.mulDiv(1e18, operatorStakeAmount);
    // }

    // function _getOperatorStakeAmount(address _operator, address _stakeToken) internal view returns (uint256) {
    //     return ISymbioticStaking(symbioticStaking).getOperatorStakeAmount(_operator, _stakeToken);
    // }

    // function _latestConfirmedTimestamp() internal view returns (uint256) {
    //     return ISymbioticStaking(symbioticStaking).lastConfirmedTimestamp();
    // }

    /*============================================= internal functions =============================================*/

    /*============================================= internal view functions =============================================*/

    function _getStakeTokenList() internal view returns(address[] memory) {
        return ISymbioticStaking(symbioticStaking).getStakeTokenList();
    }

    function _getOperatorStakeAmount(address _operator, address _stakeToken) internal view returns (uint256) {
        return ISymbioticStaking(symbioticStaking).getOperatorStakeAmount(_operator, _stakeToken);
    }

    /*============================================= internal pure functions =============================================*/



    // function _update(uint256 _captureTimestamp, address _vault, address _stakeToken, address _rewardToken) internal {
    //     // update rewardPerToken
    //     uint256 currentRewardPerToken = _rewardPerToken(_stakeToken, _rewardToken);
    //     rewardPerTokens[_stakeToken][_rewardToken] = currentRewardPerToken;

    //     // update reward for each vault
    //     claimableRewards[_vault] += _pendingReward(_vault, _stakeToken, _rewardToken);
    //     vaultRewardPerTokenPaid[_captureTimestamp][_vault] = currentRewardPerToken;
    // }

    // function _updateRewardPerTokens(address _stakeToken) internal {
    //     uint256 len = _rewardTokenSet.length();
    //     for (uint256 i = 0; i < len; i++) {
    //         address rewardToken = _rewardTokenSet.at(i);
    //         rewardPerTokens[_stakeToken][rewardToken] = _rewardPerToken(_stakeToken, rewardToken);
    //     }
    // }

    // function _pendingReward(address _vault, address _stakeToken, address _rewardToken)
    //     internal
    //     view
    //     returns (uint256)
    // {
    //     uint256 latestConfirmedTimestamp = _latestConfirmedTimestamp();
    //     uint256 rewardPerTokenPaid = vaultRewardPerTokenPaid[latestConfirmedTimestamp][_vault];
    //     uint256 rewardPerToken = _rewardPerToken(_stakeToken, _rewardToken);

    //     return (vaultStakeAmounts[latestConfirmedTimestamp][_vault].mulDiv((rewardPerToken - rewardPerTokenPaid), 1e18));
    // }

    /*======================================== internal functions ========================================*/

    /*======================================== internal view functions ========================================*/


    /*======================================== admin functions ========================================*/

    function setStakingManager(address _stakingManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setStakingManager(_stakingManager);
    }

    function _setStakingManager(address _stakingManager) internal {
        symbioticStaking = _stakingManager;
        // TODO: emit event
    }

    /*======================================== overrides ========================================*/

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
