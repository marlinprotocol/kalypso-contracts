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

    struct JobInfo {
        address requester;
        address operator;
        uint256 feePaid;
        uint256 deadline;
    }

    mapping(uint256 jobId => JobInfo jobInfo) public jobs;

    address public stakingManager;
    address public feeToken;

    uint256 public jobDuration;
    uint256 public totalFeeStored; // TODO: check if needed

    function initialize(address _admin, address _stakingManager, address _feeToken, uint256 _jobDuration) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        stakingManager = _stakingManager;
        feeToken = _feeToken;
        jobDuration = _jobDuration;
    }

    // TODO: check paramter for job details
    function createJob(uint256 _jobId, address _requester, address _operator, uint256 _feeAmount) external nonReentrant {
        IERC20(feeToken).safeTransferFrom(_requester, address(this), _feeAmount);
        
        // stakeToken and lockAmount will be decided in each pool
        jobs[_jobId] = JobInfo({
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

        IStakingManager(stakingManager).onJobCompletion(_jobId); // unlock stake
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] calldata _jobIds, bytes[] calldata _proofs) external nonReentrant {
        require(_jobIds.length == _proofs.length, "Invalid Length");

        // TODO: close job and distribute rewards

        uint256 len = _jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            uint256 jobId = _jobIds[idx];
            require(block.timestamp <= jobs[jobId].deadline, "Job Expired");
            
            _verifyProof(jobId, _proofs[idx]);

            // TODO: let onJobCompletion also accept array of jobIds
            IStakingManager(stakingManager).onJobCompletion(jobId); // unlock stake
        }

    }

    function refundFee(uint256 _jobId) external nonReentrant {
        require(block.timestamp > jobs[_jobId].deadline, "Job not Expired");
        require(jobs[_jobId].requester == msg.sender, "Not Requester");

        // TODO: refund fee
        jobs[_jobId].feePaid = 0;
        totalFeeStored -= jobs[_jobId].feePaid;

        IERC20(feeToken).safeTransfer(jobs[_jobId].requester, jobs[_jobId].feePaid);
        
        // TODO: emit event
    }

    function _verifyProof(uint256 _jobId, bytes calldata _proof) internal {
        // TODO: verify proof

        // TODO: emit event
    }

    /*======================================== Admin ========================================*/

    function setStakingManager(address _stakingManager) external {
        stakingManager = _stakingManager;
    }

    function setFeeToken(address _feeToken) external {
        feeToken = _feeToken;
    }

    function setJobDuration(uint256 _jobDuration) external {
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