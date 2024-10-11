// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
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
    // operator deducts comission from inflation reward
    mapping(address operator => uint256 rewardShare) public operatorRewardShares; // 1e18 == 100%

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    address public stakingManager;
    address public feeToken;
    address public inflationRewardManager;

    uint256 public jobDuration;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    /*======================================== Init ========================================*/

    function initialize(address _admin, address _stakingManager, address _feeToken, address _inflationRewardManager, uint256 _jobDuration)
        public
        initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_stakingManager != address(0), "JobManager: Invalid StakingManager");
        stakingManager = _stakingManager;

        require(_feeToken != address(0), "JobManager: Invalid Fee Token");
        feeToken = _feeToken;

        require(_inflationRewardManager != address(0), "JobManager: Invalid InflationRewardManager");
        inflationRewardManager = _inflationRewardManager;

        require(_jobDuration > 0, "JobManager: Invalid Job Duration");
        jobDuration = _jobDuration;
    }

    /*======================================== Job ========================================*/

    // TODO: check paramter for job details
    function createJob(uint256 _jobId, address _requester, address _operator, uint256 _feeAmount)
        external
        nonReentrant
    {   
        // TODO: this should be removed
        IERC20(feeToken).safeTransferFrom(_requester, address(this), _feeAmount);

        // stakeToken and lockAmount will be decided in each pool
        jobs[_jobId] = Struct.JobInfo({
            requester: _requester,
            operator: _operator,
            feePaid: _feeAmount,
            deadline: block.timestamp + jobDuration
        });

        IStakingManager(stakingManager).onJobCreation(_jobId, _operator);

        // TODO: emit event
    }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 _jobId, bytes calldata _proof) public nonReentrant {
        require(block.timestamp <= jobs[_jobId].deadline, "Job Expired");

        _verifyProof(_jobId, _proof);
        
        address operator = jobs[_jobId].operator;   

        // distribute fee reward
        uint256 feeRewardRemaining = _distributeFeeReward(operator, jobs[_jobId].feePaid);

        // inflation reward will be distributed here
        IStakingManager(stakingManager).onJobCompletion(_jobId, operator, feeRewardRemaining);
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] calldata _jobIds, bytes[] calldata _proofs) external nonReentrant {
        require(_jobIds.length == _proofs.length, "Invalid Length");

        uint256 len = _jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            uint256 jobId = _jobIds[idx];
            submitProof(jobId, _proofs[idx]);
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

            IERC20(feeToken).safeTransfer(jobs[_jobId].requester, jobs[_jobId].feePaid);

            // TODO: emit event
        }
    }

    /*======================================== Internal functions ========================================*/

    function _verifyProof(uint256 _jobId, bytes calldata _proof) internal {
        // TODO: verify proof

        // TODO: emit event
    }

    function _distributeFeeReward(address _operator, uint256 _feePaid) internal returns(uint256 feeRewardRemaining) {
        uint256 operatorFeeReward = Math.mulDiv(_feePaid, operatorRewardShares[_operator], 1e18);
        IERC20(feeToken).safeTransfer(_operator, operatorFeeReward);
        feeRewardRemaining = _feePaid - operatorFeeReward;
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

    function setOperatorRewardShare(address _operator, uint256 _rewardShare) external onlyRole(DEFAULT_ADMIN_ROLE) {
        operatorRewardShares[_operator] = _rewardShare;
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
