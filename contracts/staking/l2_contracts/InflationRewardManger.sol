// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
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

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    /* config */
    uint256 public startTime;

    /* contract addresses */
    address public jobManager;
    address public stakingManager;
    address public symbioticStaking;

    /* reward config */
    address public inflationRewardToken;
    uint256 public inflationRewardEpochSize;
    uint256 public inflationRewardPerEpoch;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    // last epoch when operator completed a job
    mapping(address operator => uint256 lastJobCompletionEpoch) lastJobCompletionEpochs;

    // TODO: temporary
    mapping(address operator => uint256 comissionRate) operatorInflationRewardComissionRate; // 1e18 == 100%

    // count of jobs done by operator in an epoch
    mapping(uint256 epoch => mapping(address operator => uint256 count)) operatorJobCountsPerEpoch;
    // total count of jobs done in an epoch
    mapping(uint256 epoch => uint256 totalCount) totalJobCountsPerEpoch;
    // timestampIdx of the latestConfirmedTimestamp at the time of job completion or snapshot submission
    mapping(uint256 epoch => uint256 timestampIdx) epochTimestampIdx;

    modifier onlyJobManager() {
        require(msg.sender == jobManager, "InflationRewardManager: Only JobManager");
        _;
    }

    modifier onlySymbioticStaking() {
        require(msg.sender == symbioticStaking, "InflationRewardManager: Only SymbioticStaking");
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
    function updatePendingInflationReward(address _operator) external returns (uint256 timestampIdx, uint256 pendingInflationReward) {
        uint256 currentEpoch = (block.timestamp - startTime) / inflationRewardEpochSize;
        uint256 operatorLastEpoch = lastJobCompletionEpochs[_operator];

        // no need to update and distribute pending inflation reward
        if (operatorLastEpoch == currentEpoch) {
            // return address(0) as the transmitter value will not be used
            return (0, 0);
        }

        // when job is completed, increase job count
        if(msg.sender == stakingManager) {
            _increaseJobCount(_operator, currentEpoch);
        }

        uint256 operatorLastEpochJobCount = operatorJobCountsPerEpoch[operatorLastEpoch][_operator];
        uint256 operatorCurrentEpochJobCount = operatorJobCountsPerEpoch[currentEpoch][_operator];

        // if operator has not completed any job
        if(operatorLastEpochJobCount == 0 && operatorCurrentEpochJobCount == 0) {
            // return address(0) as the transmitter value will not be used
            return (0, 0);
        }

        timestampIdx = epochTimestampIdx[operatorLastEpoch];

        // when operator has done job in last epoch, distribute inflation reward
        // if 0, it means pendingInflationReward was updated and no job has been done
        if(operatorLastEpochJobCount > 0) {
            uint256 lastEpochTotalJobCount = totalJobCountsPerEpoch[operatorLastEpoch];
            
            pendingInflationReward = Math.mulDiv(
                inflationRewardPerEpoch, operatorLastEpochJobCount, lastEpochTotalJobCount
            );

            // operator deducts comission from inflation reward
            uint256 operatorComission  = Math.mulDiv(
                pendingInflationReward, IJobManager(jobManager).operatorRewardShares(_operator), 1e18
            );

            IERC20(inflationRewardToken).safeTransfer(_operator, operatorComission);

            pendingInflationReward -= operatorComission;
        }

        // when job is completed, inflation reward with distributed by JobManager along with fee reward
        if(msg.sender != stakingManager && pendingInflationReward > 0) {
            // staking manager will distribute inflation reward based on each pool's share
            IStakingManager(stakingManager).distributeInflationReward(_operator, pendingInflationReward, timestampIdx);
        }

        lastJobCompletionEpochs[_operator] = currentEpoch;
    }

    /// @notice update when snapshot submission is completed, or when a job is completed
    function updateEpochTimestampIdx() external onlySymbioticStaking {
        // latest confirmed timestampIdx
        uint256 currentTimestampIdx = ISymbioticStaking(symbioticStaking).latestConfirmedTimestampIdx();

        if(epochTimestampIdx[_getCurrentEpoch()] != currentTimestampIdx) {
            epochTimestampIdx[_getCurrentEpoch()] = currentTimestampIdx;
        }
    }

    /*===================================================== internal ====================================================*/

    function _increaseJobCount(address _operator, uint256 _epoch) internal {
        operatorJobCountsPerEpoch[_epoch][_operator]++;
        totalJobCountsPerEpoch[_epoch]++;
    }

    /*=================================================== external view =================================================*/

    function getEpochTimestampIdx(uint256 _epoch) external view returns (uint256) {
        return epochTimestampIdx[_epoch];
    }

    /*=================================================== internal view =================================================*/

    function _getCurrentEpoch() internal view returns (uint256) {
        return (block.timestamp - startTime) / inflationRewardEpochSize;
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
