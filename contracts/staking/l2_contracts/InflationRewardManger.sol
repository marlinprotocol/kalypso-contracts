// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
import {IJobManager} from "../../interfaces/staking/IJobManager.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InflationRewardManager is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IInflationRewardManager
{
    using SafeERC20 for IERC20;

    uint256 public startTime;

    address public jobManager;
    address public stakingManager;

    address public inflationRewardToken;

    uint256 public inflationRewardEpochSize;
    uint256 public inflationRewardPerEpoch;

    // operator deducts comission from inflation reward
    mapping(address operator => uint256 rewardShare) operatorRewardShare; // 1e18 == 100%

    // last epoch when operator completed a job
    mapping(address operator => uint256 lastJobCompletionEpoch) rewardEpoch;

    // TODO: temporary
    mapping(address operator => uint256 comissionRate) operatorInflationRewardComissionRate; // 1e18 == 100%

    // count of jobs done by operator in an epoch
    mapping(uint256 epoch => mapping(address operator => uint256 count)) operatorJobCountsPerEpoch;

    // total count of jobs done in an epoch
    mapping(uint256 epoch => uint256 totalCount) totalJobCountsPerEpoch;

    modifier onlyJobManager() {
        require(msg.sender == jobManager, "InflationRewardManager: Only JobManager");
        _;
    }

    /*==================================================== initialize ===================================================*/

    function initialize(
        address _admin,
        uint256 _startTime,
        address _jobManager,
        address _stakingManager,
        address _inflationRewardToken,
        uint256 _inflationRewardEpochSize,
        uint256 _inflationRewardPerEpoch
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_jobManager != address(0), "InflationRewardManager: jobManager address is zero");
        jobManager = _jobManager;

        require(_stakingManager != address(0), "InflationRewardManager: stakingManager address is zero");
        stakingManager = _stakingManager;

        require(_startTime > 0, "InflationRewardManager: startTime is zero");
        startTime = _startTime;

        require(_inflationRewardToken != address(0), "InflationRewardManager: inflationRewardToken address is zero");
        inflationRewardToken = _inflationRewardToken;

        require(_inflationRewardEpochSize > 0, "InflationRewardManager: inflationRewardEpochSize is zero");
        inflationRewardEpochSize = _inflationRewardEpochSize;

        require(_inflationRewardPerEpoch > 0, "InflationRewardManager: inflationRewardPerEpoch is zero");
        inflationRewardPerEpoch = _inflationRewardPerEpoch;
    }

    /*===================================================== external ====================================================*/

    /// @notice update pending inflation reward for given operator
    /// @dev called by JobManager when job is completed or by RewardDistributor when operator is slashed
    function updatePendingInflationReward(address _operator) external returns (uint256 pendingInflationReward) {
        uint256 currentEpoch = (block.timestamp - startTime) / inflationRewardEpochSize;
        uint256 operatorLastEpoch = rewardEpoch[_operator];

        if (operatorLastEpoch == currentEpoch) {
            return 0;
        }

        if(msg.sender == jobManager) {
            _increaseJobCount(_operator, currentEpoch);
        }

        uint256 operatorLastEpochJobCount = operatorJobCountsPerEpoch[operatorLastEpoch][_operator];
        uint256 operatorCurrentEpochJobCount = operatorJobCountsPerEpoch[currentEpoch][_operator];

        // when there is no job done by operator both in last epoch and current epoch don't update anything
        if(operatorLastEpochJobCount * operatorCurrentEpochJobCount == 0) {
            return 0;
        }

        // when operator has done job in last epoch, distribute inflation reward
        // if 0, it means pendingInflationReward was updated and no job has been done
        if(operatorLastEpochJobCount > 0) {
            uint256 totalJobCount = totalJobCountsPerEpoch[operatorLastEpoch];
            
            pendingInflationReward = Math.mulDiv(
                inflationRewardPerEpoch, operatorLastEpochJobCount, totalJobCount
            );

            // operator deducts comission from inflation reward
            uint256 operatorComission  = Math.mulDiv(
                pendingInflationReward, operatorRewardShare[_operator], 1e18
            );
            IERC20(inflationRewardToken).safeTransfer(_operator, pendingInflationReward - operatorComission);

            pendingInflationReward -= operatorComission;
        }

        // when job is completed, inflation reward with distributed by JobManager along with fee reward
        if(msg.sender != jobManager && pendingInflationReward > 0) {
            // staking manager will distribute inflation reward based on each pool's share
            IStakingManager(stakingManager).distributeInflationReward(_operator, pendingInflationReward);
        }

        rewardEpoch[_operator] = currentEpoch;
    }

    /*===================================================== internal ====================================================*/

    function _increaseJobCount(address _operator, uint256 _epoch) internal {
        operatorJobCountsPerEpoch[_epoch][_operator]++;
        totalJobCountsPerEpoch[_epoch]++;
    }

    /*======================================== Admin ========================================*/

    function setJobManager(address _jobManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_jobManager != address(0), "InflationRewardManager: jobManager address is zero");
        jobManager = _jobManager;
    }

    function setStakingManager(address _stakingManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_stakingManager != address(0), "InflationRewardManager: stakingManager address is zero");
        stakingManager = _stakingManager;
    }

    function setInflationRewardPerEpoch(uint256 _inflationRewardPerEpoch) public onlyRole(DEFAULT_ADMIN_ROLE) {
        inflationRewardPerEpoch = _inflationRewardPerEpoch;
    }

    function setInflationRewardEpochSize(uint256 _inflationRewardEpochSize) public onlyRole(DEFAULT_ADMIN_ROLE) {
        inflationRewardEpochSize = _inflationRewardEpochSize;
    }

    /*======================================== Overrides ========================================*/

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
}
