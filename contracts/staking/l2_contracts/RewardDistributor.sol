// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakingPool} from "../../interfaces/staking/IStakingPool.sol";
import {IJobManager} from "../../interfaces/staking/IJobManager.sol";
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Struct} from "../../lib/staking/Struct.sol";

abstract contract RewardDistributor is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IRewardDistributor
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    address public jobManager;
    address public stakingPool;

    address public feeRewardToken;
    address public inflationRewardToken;

    // mapping(address stakeToken => uint256 share) public inflationRewardShare; // 1e18 = 100%

    // reward is accrued per operator
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 rewardAmount)))
        rewards;
    // rewardTokens amount per stakeToken
    mapping(
        address stakeToken
            => mapping(address operator => mapping(address rewardToken => uint256 rewardPerToken))
    ) rewardPerTokenStored;

    mapping(
        address account
            => mapping(
                address stakeToken
                    => mapping(address operator => mapping(address rewardToken => uint256 rewardPerTokenPaid))
            )
    ) rewardPerTokenPaids;

    mapping(address account => mapping(address rewardToken => uint256 amount)) rewardAccrued;

    modifier onlyStakingPool() {
        require(msg.sender == stakingPool, "Only StakingPool");
        _;
    }

    function initialize(
        address _admin,
        address _jobManager,
        address _stakingPool,
        address _feeRewardToken,
        address _inflationRewardToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_admin != address(0), "Invalid Admin");
        require(_jobManager != address(0), "Invalid JobManager");
        require(_stakingPool != address(0), "Invalid StakingPool");
        require(_feeRewardToken != address(0), "Invalid FeeRewardToken");

        jobManager = _jobManager;
        stakingPool = _stakingPool;
        feeRewardToken = _feeRewardToken;
        inflationRewardToken = _inflationRewardToken;
    }

    function addFeeReward(address _stakeToken, address _operator, uint256 _amount) external onlyStakingPool {
        rewards[_stakeToken][_operator][feeRewardToken] += _amount;

        rewardPerTokenStored[_stakeToken][_operator][feeRewardToken] = _rewardPerTokenStored(_stakeToken, _operator, feeRewardToken);
    }

    /// @notice distribute inflation reward to all stakeTokens
    /// @dev StakingPool should pass the list of stakeTokens and rewardAmount for each stakeToken
    function addInflationReward(address _operator, address[] calldata stakeTokens, uint256[] calldata rewardAmounts) external onlyStakingPool {
        address _inflationRewardToken = inflationRewardToken; // cache
        for (uint256 i = 0; i < stakeTokens.length; i++) {
            // distribute inflation reward to each stakeToken
            rewards[stakeTokens[i]][_operator][_inflationRewardToken] += rewardAmounts[i];

            // update rewardPerTokenStored for each stakeToken
            rewardPerTokenStored[stakeTokens[i]][_operator][_inflationRewardToken] = _rewardPerTokenStored(stakeTokens[i], _operator, _inflationRewardToken);
        }
        // TODO: emit event
    }

    /// @dev called when stake amount is updated in StakingPool
    function onStakeUpdate(address _account, address _stakeToken, address _operator) external onlyStakingPool {
        // update fee reward
        rewardPerTokenStored[_stakeToken][_operator][feeRewardToken] = _rewardPerTokenStored(_stakeToken, _operator, feeRewardToken);

        // update inflation reward
        // TODO: check if there is any problem by not updating rewardPerTokenStored during Tx
        _requestInflationRewardUpdate(_operator);

        uint256 rewardPerTokenStoredCurrent = rewardPerTokenStored[_stakeToken][_operator][inflationRewardToken];
        address[] memory stakeTokenList = IStakingPool(stakingPool).getStakeTokenList();
        
        for(uint256 i = 0; i < stakeTokenList.length; i++) {
            uint256 rewardPerTokenPaid = rewardPerTokenPaids[_account][stakeTokenList[i]][_operator][inflationRewardToken];
            uint256 accountStakeAmount = _getStakeAmount(_account, stakeTokenList[i], _operator);
            uint256 pendingReward = accountStakeAmount.mulDiv(rewardPerTokenStoredCurrent - rewardPerTokenPaid, 1e18);

            // update account's reward info
            rewardAccrued[_account][inflationRewardToken] += pendingReward;
            rewardPerTokenPaids[_account][stakeTokenList[i]][_operator][inflationRewardToken] = rewardPerTokenStoredCurrent;

            // update global rewardPerTokenStored
            uint256 operatorStakeAmount = _getOperatorStakeAmount(_operator, stakeTokenList[i]);
            rewardPerTokenStored[_stakeToken][_operator][inflationRewardToken] += rewards[stakeTokenList[i]][_operator][inflationRewardToken].mulDiv(1e18, operatorStakeAmount);
        }
    }

    function onClaimReward(address _account, address _operator) external onlyStakingPool {
        IERC20(feeRewardToken).safeTransfer(_account, rewardAccrued[_account][feeRewardToken]);
        IERC20(inflationRewardToken).safeTransfer(_account, rewardAccrued[_account][inflationRewardToken]);

        rewardAccrued[_account][feeRewardToken] = 0;
        rewardAccrued[_account][inflationRewardToken] = 0;

        address[] memory stakeTokenList = IStakingPool(stakingPool).getStakeTokenList();
        for(uint256 i = 0; i < stakeTokenList.length; i++) {
            rewardPerTokenPaids[_account][stakeTokenList[i]][_operator][feeRewardToken] = rewardPerTokenStored[stakeTokenList[i]][_operator][feeRewardToken];
            rewardPerTokenPaids[_account][stakeTokenList[i]][_operator][inflationRewardToken] = rewardPerTokenStored[stakeTokenList[i]][_operator][inflationRewardToken];
        }
    }

    function onSlash() external onlyStakingPool {
        // TODO
    }

    function _requestInflationRewardUpdate(address _operator) internal {
        // JobManager.updateInflationReward 
        // -> StakingManager.distributeInflationReward 
        // -> StakingPool.distributeInflationReward 
        // -> RewardDistributor.addInflationReward
        IJobManager(jobManager).updateInflationReward(_operator);
    }


    /* Modification for _update */
    function _rewardPerTokenStored(address _stakeToken, address _operator, address _rewardToken)
        internal
        view
        returns (uint256)
    {
        uint256 operatorStakeAmount = _getOperatorStakeAmount(_operator, _stakeToken);
        uint256 totalRewardAmount = rewards[_stakeToken][_operator][_rewardToken];

        // TODO: make sure decimal is 18
        return operatorStakeAmount == 0
            ? rewardPerTokenStored[_stakeToken][_operator][_rewardToken]
            : rewardPerTokenStored[_stakeToken][_operator][_rewardToken]
                + totalRewardAmount.mulDiv(1e18, operatorStakeAmount);
    }

    function _getOperatorStakeAmount(address _operator, address _stakeToken) internal view returns (uint256) {
        return IStakingPool(stakingPool).getOperatorStakeAmount(_operator, _stakeToken);
    }
    
    function _getStakeTokenList() internal view returns (address[] memory) {
        return IStakingPool(stakingPool).getStakeTokenList();
    }

    function _getStakeAmount(address account, address _stakeToken, address _operator) internal view returns (uint256) {
        return IStakingPool(stakingPool).getStakeAmount(account, _stakeToken, _operator);
    }

    //-------------------------------- Admin start --------------------------------//

    function setStakingPool(address _stakingPool) public onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPool = _stakingPool;

        // TODO: emit event
    }

    //-------------------------------- Admin end --------------------------------//

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
