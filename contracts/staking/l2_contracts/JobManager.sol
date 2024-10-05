// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IJobManager} from "../../interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {Struct} from "../../lib/staking/Struct.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/* 
    JobManager contract is responsible for creating and managing jobs.
    Staking Manager contract is responsible for locking/unlocking tokens and distributing rewards.
 */
contract JobManager is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IJobManager
{
    using SafeERC20 for IERC20;

    mapping(uint256 jobId => Struct.JobInfo jobInfo) public jobs;

    address public stakingManager;
    address public feeToken;
    address public inflationRewardToken;

    uint256 public jobDuration;
    uint256 public totalFeeStored; // TODO: check if needed

    uint256 inflationRewardEpochSize;
    uint256 inflationRewardPerEpoch;

    // epochs in which operator has done jobs
    mapping(address operator => uint256[] epochs) operatorJobCompletionEpochs; 
    // idx of operatorJobCompletionEpochs, inflationReward distribution should be reflected from this idx
    mapping(address operator => uint256 idx) inflationRewardEpochBeginIdx;

    // count of jobs done by operator in an epoch
    mapping(uint256 epoch => mapping(address operator => uint256 count)) operatorJobCount; 
    // total count of jobs done in an epoch
    mapping(uint256 epoch => uint256 totalCount) totalJobCount; 

    /*======================================== Init ========================================*/

    function initialize(address _admin, address _stakingManager, address _feeToken, uint256 _jobDuration)
        public
        initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        stakingManager = _stakingManager;
        feeToken = _feeToken;
        jobDuration = _jobDuration;
    }

    /*======================================== Job ========================================*/

    // TODO: check paramter for job details
    function createJob(uint256 _jobId, address _requester, address _operator, uint256 _feeAmount)
        external
        nonReentrant
    {
        IERC20(feeToken).safeTransferFrom(_requester, address(this), _feeAmount);

        // stakeToken and lockAmount will be decided in each pool
        jobs[_jobId] = Struct.JobInfo({
            requester: _requester,
            operator: _operator,
            feePaid: _feeAmount,
            deadline: block.timestamp + jobDuration
        });

        IStakingManager(stakingManager).onJobCreation(_jobId, _operator);

        totalFeeStored += _feeAmount;

        // TODO: emit event
    }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 _jobId, bytes calldata _proof) public nonReentrant {
        require(block.timestamp <= jobs[_jobId].deadline, "Job Expired");

        _verifyProof(_jobId, _proof);

        uint256 feePaid = jobs[_jobId].feePaid;
        uint256 pendingInflationReward = _updateInflationReward(jobs[_jobId].operator);

        // send fee and unlock stake
        // TODO: consider where the fund comes from
        IERC20(feeToken).safeTransfer(stakingManager, feePaid); // TODO: make RewardDistributor pull fee from JobManager
        IERC20(inflationRewardToken).safeTransfer(stakingManager, pendingInflationReward);
        IStakingManager(stakingManager).onJobCompletion(_jobId, jobs[_jobId].operator, feePaid, pendingInflationReward);

        _updateJobCompletionEpoch(_jobId); // TODO
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] calldata _jobIds, bytes[] calldata _proofs) external nonReentrant {
        require(_jobIds.length == _proofs.length, "Invalid Length");

        uint256 len = _jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            uint256 jobId = _jobIds[idx];
            submitProof(jobId, _proofs[idx]); // TODO: optimize

            _updateJobCompletionEpoch(jobId);
        }
    }

    function _updateJobCompletionEpoch(uint256 _jobId) internal {
        uint256 currentEpoch = block.timestamp / inflationRewardEpochSize;
        uint256 len = operatorJobCompletionEpochs[jobs[_jobId].operator].length;
        
        if(len > 0 && operatorJobCompletionEpochs[jobs[_jobId].operator][len - 1] != currentEpoch) {
            operatorJobCompletionEpochs[jobs[_jobId].operator].push(currentEpoch);
        }
    }

    /*======================================== Fee Reward ========================================*/

    /// @notice refund fee to the job requester
    /// @dev most likely called by the requester when job is not completed
    /// @dev or when the job is slashed and the slash result is submitted in SymbioticStaking contract
    function refundFee(uint256 _jobId) external nonReentrant {
        if (jobs[_jobId].feePaid > 0) {
            require(block.timestamp > jobs[_jobId].deadline, "Job not Expired");

            jobs[_jobId].feePaid = 0;
            totalFeeStored -= jobs[_jobId].feePaid;

            IERC20(feeToken).safeTransfer(jobs[_jobId].requester, jobs[_jobId].feePaid);

            // TODO: emit event
        }
    }

    /*======================================== Inflation Reward ========================================*/

    /// @notice update inflation reward for operator
    /// @dev can be called by anyone, but most likely when proof is submitted(when job is completed) by operator
    /// @dev or inflation reward is claimed in a RewardDistributor
    function updateInflationReward(address _operator) external {
        uint256 pendingInflationReward = _updateInflationReward(_operator);

        if(pendingInflationReward > 0) {
            // send reward to StakingManager
            IERC20(inflationRewardToken).safeTransfer(stakingManager, pendingInflationReward);
            // and distribute
            IStakingManager(stakingManager).distributeInflationReward(_operator, pendingInflationReward);
        }
    }

    function getPendingInflationReward(address _operator) external view returns(uint256) {
        return _getPendingInflationReward(_operator);
    }

    /*======================================== Internal functions ========================================*/

    function _verifyProof(uint256 _jobId, bytes calldata _proof) internal {
        // TODO: verify proof

        // TODO: emit event
    }

    /// @notice update pending inflation reward for operator
    function _updateInflationReward(address _operator) internal returns(uint256 pendingInflationReward) {
        // check if operator has completed any job
        if (operatorJobCompletionEpochs[_operator].length == 0) return 0;
        
        // list of epochs in which operator has completed jobs
        uint256[] storage completedEpochs = operatorJobCompletionEpochs[_operator];

        // first epoch which the reward has not been distributed
        uint256 beginIdx = inflationRewardEpochBeginIdx[_operator];

        // no job completed since last update
        if(beginIdx > completedEpochs.length) return 0;

        uint256 beginEpoch = completedEpochs[beginIdx];
        uint256 currentEpoch = block.timestamp / inflationRewardEpochSize;

        // no pending reward if operator has already claimed reward until latest epoch
        if(beginEpoch == currentEpoch) return 0;

        // update pending reward
        uint256 rewardPerEpoch = inflationRewardPerEpoch; // cache
        uint256 len = completedEpochs.length;

        for(uint256 idx = beginIdx; idx < len; idx++) {
            uint256 epoch = completedEpochs[idx];

            // for last epoch in epoch array
            if(idx == len - 1) {
                // idx can be greater than actual length of epoch array by 1
                inflationRewardEpochBeginIdx[_operator] = epoch == currentEpoch ? idx : idx + 1;
            }

            pendingInflationReward += Math.mulDiv(rewardPerEpoch, operatorJobCount[epoch][_operator], totalJobCount[epoch]);
        }

        return pendingInflationReward;
    }

    function _getPendingInflationReward(address _operator) internal view returns(uint256 pendingInflationReward) {
        // check if operator has completed any job
        if (operatorJobCompletionEpochs[_operator].length == 0) return 0;
        
        // list of epochs in which operator has completed jobs
        uint256[] storage completedEpochs = operatorJobCompletionEpochs[_operator];

        // first epoch which the reward has not been distributed
        uint256 beginIdx = inflationRewardEpochBeginIdx[_operator];

        // no job completed since last update
        if(beginIdx > completedEpochs.length) return 0;

        uint256 beginEpoch = completedEpochs[beginIdx];
        uint256 currentEpoch = block.timestamp / inflationRewardEpochSize;

        // no pending reward if operator has already claimed reward until latest epoch
        if(beginEpoch == currentEpoch) return 0;

        // update pending reward
        uint256 rewardPerEpoch = inflationRewardPerEpoch; // cache
        uint256 len = completedEpochs.length;

        for(uint256 idx = beginIdx; idx < len; idx++) {
            uint256 epoch = completedEpochs[idx];

            pendingInflationReward += Math.mulDiv(rewardPerEpoch, operatorJobCount[epoch][_operator], totalJobCount[epoch]);
        }

        return pendingInflationReward;
    }

    /*======================================== Admin ========================================*/

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;
    }

    function setFeeToken(address _feeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeToken = _feeToken;
    }

    function setJobDuration(uint256 _jobDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        jobDuration = _jobDuration;
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
