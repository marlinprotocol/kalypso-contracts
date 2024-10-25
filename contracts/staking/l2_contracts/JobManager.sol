// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Contracts */
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {StakingManager} from "./StakingManager.sol";

/* Interfaces */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IJobManager} from "../../interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";

/* Libraries */
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Struct} from "../../lib/staking/Struct.sol";

contract JobManager is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IJobManager
{
    using SafeERC20 for IERC20;

    /*===================================================================================================================*/
    /*================================================ state variable ===================================================*/
    /*===================================================================================================================*/

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    address public stakingManager;
    address public symbioticStaking;
    address public symbioticStakingReward;
    address public feeToken;
    // address public inflationRewardManager;

    uint256 public jobDuration;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    /*===================================================================================================================*/
    /*==================================================== mapping ======================================================*/
    /*===================================================================================================================*/

    mapping(uint256 jobId => Struct.JobInfo jobInfo) public jobs;
    // operator deducts comission from inflation reward
    mapping(address operator => uint256 rewardShare) public operatorRewardShares; // 1e18 == 100%

    mapping(address operator => uint256 feeReward) public operatorFeeRewards;

    mapping(address transmitter => uint256 feeReward) public transmitterFeeRewards;

    /*===================================================================================================================*/
    /*=================================================== modifier ======================================================*/
    /*===================================================================================================================*/

    modifier onlySymbioticStaking() {
        require(
            msg.sender == symbioticStaking || msg.sender == symbioticStakingReward,
            "JobManager: caller is not the SymbioticStaking"
        );
        _;
    }

    /*===================================================================================================================*/
    /*================================================== initializer ====================================================*/
    /*===================================================================================================================*/

    function initialize(
        address _admin,
        address _stakingManager,
        address _symbioticStaking,
        address _symbioticStakingReward,
        address _feeToken,
        uint256 _jobDuration
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_stakingManager != address(0), "JobManager: Invalid StakingManager");
        stakingManager = _stakingManager;
        emit StakingManagerSet(_stakingManager);

        require(_symbioticStaking != address(0), "JobManager: Invalid SymbioticStaking");
        symbioticStaking = _symbioticStaking;
        emit SymbioticStakingSet(_symbioticStaking);

        require(_symbioticStakingReward != address(0), "JobManager: Invalid SymbioticStakingReward");
        symbioticStakingReward = _symbioticStakingReward;
        emit SymbioticStakingRewardSet(_symbioticStakingReward);

        require(_feeToken != address(0), "JobManager: Invalid Fee Token");
        feeToken = _feeToken;
        emit FeeTokenSet(_feeToken);

        require(_jobDuration > 0, "JobManager: Invalid Job Duration");
        jobDuration = _jobDuration;
        emit JobDurationSet(_jobDuration);
    }

    /*===================================================================================================================*/
    /*==================================================== external =====================================================*/
    /*===================================================================================================================*/

    /*----------------------------------------------------- Job ---------------------------------------------------------*/
    
 
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

        StakingManager(stakingManager).onJobCreation(_jobId, _operator);

        emit JobCreated(_jobId, _requester, _operator, _feeAmount);
    }


    /// @notice Submit a proof and complete the job
    function submitProof(uint256 _jobId, bytes calldata _proof) public nonReentrant {
        require(jobs[_jobId].deadline > 0, "Job not created");
        require(block.timestamp <= jobs[_jobId].deadline, "Job Expired");

        _verifyProof(_jobId, _proof);

        address operator = jobs[_jobId].operator;

        // distribute fee reward and calculate remaining fee reward
        uint256 feeRewardRemaining = _distributeOperatorFeeReward(operator, jobs[_jobId].feePaid);

        // inflation reward will be distributed here
        StakingManager(stakingManager).onJobCompletion(_jobId, operator, feeRewardRemaining);
        emit JobCompleted(_jobId, operator, feeRewardRemaining);
    }

    /// @notice Submit proofs of multiple jobs
    function submitProofs(uint256[] calldata _jobIds, bytes[] calldata _proofs) external nonReentrant {
        require(_jobIds.length == _proofs.length, "Invalid Length");

        uint256 len = _jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            uint256 jobId = _jobIds[idx];
            submitProof(jobId, _proofs[idx]);
        }
    }

    /// @notice Refund fee to the job requester
    /// @dev Can be called by the requester if the job is not completed by the deadline.
    /// @dev or when the job is slashed and the slash result is submitted in SymbioticStaking contract
    function slashGenerator(uint256 _jobId) external nonReentrant {
        if (jobs[_jobId].feePaid > 0) {
            require(block.timestamp > jobs[_jobId].deadline, "Job not Expired");

            IERC20(feeToken).safeTransfer(jobs[_jobId].requester, jobs[_jobId].feePaid);
            jobs[_jobId].feePaid = 0;

            emit FeeRefunded(_jobId, jobs[_jobId].requester, jobs[_jobId].feePaid);
        }
    }

    function claimOperatorFeeReward() external nonReentrant {
        uint256 feeReward = operatorFeeRewards[msg.sender];
        require(feeReward > 0, "No fee reward to claim");

        operatorFeeRewards[msg.sender] = 0;
        IERC20(feeToken).safeTransfer(msg.sender, feeReward);

        emit OperatorFeeRewardClaimed(msg.sender, feeReward);
    }

    function claimTransmitterFeeReward() external nonReentrant {
        uint256 feeReward = transmitterFeeRewards[msg.sender];
        require(feeReward > 0, "No fee reward to claim");

        transmitterFeeRewards[msg.sender] = 0;
        IERC20(feeToken).safeTransfer(msg.sender, feeReward);

        emit TransmitterFeeRewardClaimed(msg.sender, feeReward);
    }

    /*===================================================================================================================*/
    /*===================================================== internal ====================================================*/
    /*===================================================================================================================*/

    function _verifyProof(uint256 _jobId, bytes calldata _proof) internal {
        // TODO: verify proof

        // TODO: emit event
    }

    function _distributeOperatorFeeReward(address _operator, uint256 _feePaid) internal returns (uint256 feeRewardRemaining) {
        // calculate operator fee reward
        uint256 operatorFeeReward = Math.mulDiv(_feePaid, operatorRewardShares[_operator], 1e18);
        feeRewardRemaining = _feePaid - operatorFeeReward;

        // update operator fee reward
        operatorFeeRewards[_operator] += operatorFeeReward;

        emit OperatorFeeRewardAdded(_operator, operatorFeeReward);
    }

    /*===================================================================================================================*/
    /*=============================================== Symbiotic Staking =================================================*/
    /*===================================================================================================================*/

    /// @dev Only SymbioticStaking and SymbioticStakingReward can call this function
    function transferFeeToken(address _recipient, uint256 _amount) external onlySymbioticStaking {
        IERC20(feeToken).safeTransfer(_recipient, _amount);
    }

    /// @dev updated by SymbioticStaking contract when job is completed
    function distributeTransmitterFeeReward(address _transmitter, uint256 _feeRewardAmount) external onlySymbioticStaking {
        transmitterFeeRewards[_transmitter] += _feeRewardAmount;
        emit TransmitterFeeRewardAdded(_transmitter, _feeRewardAmount);
    }

    /*===================================================================================================================*/
    /*===================================================== admin =======================================================*/
    /*===================================================================================================================*/

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;
        emit StakingManagerSet(_stakingManager);
    }

    function setSymbioticStaking(address _symbioticStaking) external onlyRole(DEFAULT_ADMIN_ROLE) {
        symbioticStaking = _symbioticStaking;
        emit SymbioticStakingSet(_symbioticStaking);
    }

    function setSymbioticStakingReward(address _symbioticStakingReward) external onlyRole(DEFAULT_ADMIN_ROLE) {
        symbioticStakingReward = _symbioticStakingReward;
        emit SymbioticStakingRewardSet(_symbioticStakingReward);
    }

    function setFeeToken(address _feeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeToken = _feeToken;
        emit FeeTokenSet(_feeToken);
    }

    function setJobDuration(uint256 _jobDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        jobDuration = _jobDuration;
        emit JobDurationSet(_jobDuration);
    }

    function setOperatorRewardShare(address _operator, uint256 _rewardShare) external onlyRole(DEFAULT_ADMIN_ROLE) {
        operatorRewardShares[_operator] = _rewardShare;
        emit OperatorRewardShareSet(_operator, _rewardShare);
    }

    function emergencyWithdraw(address _token, address _to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "zero token address");
        require(_to != address(0), "zero to address");

        IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
    }

    /*===================================================================================================================*/
    /*==================================================== override =====================================================*/
    /*===================================================================================================================*/

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
