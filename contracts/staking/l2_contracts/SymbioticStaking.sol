// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Contracts */
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {JobManager} from "./JobManager.sol";

/* Interfaces */
// import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../interfaces/staking/ISymbioticStakingReward.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* Libraries */
import {Struct} from "../../lib/staking/Struct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


contract SymbioticStaking is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ISymbioticStaking
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 public constant STAKE_SNAPSHOT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 public constant SLASH_RESULT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 public constant COMPLETE_MASK = 0x0000000000000000000000000000000000000000000000000000000000000011;

    bytes32 public constant STAKE_SNAPSHOT_TYPE = keccak256("STAKE_SNAPSHOT_TYPE");
    bytes32 public constant SLASH_RESULT_TYPE = keccak256("SLASH_RESULT_TYPE");

    /*===================================================================================================================*/
    /*================================================ state variable ===================================================*/
    /*===================================================================================================================*/

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    /* Config */
    uint256 public submissionCooldown; // 18 decimal (in seconds)
    uint256 public baseTransmitterComissionRate; // 18 decimal (in percentage)

    /* Stake Token */
    EnumerableSet.AddressSet stakeTokenSet;
    uint256 public stakeTokenSelectionWeightSum;

    /* Contracts */
    address public stakingManager;
    address public jobManager;
    address public rewardDistributor;

    /* RewardToken */
    address public feeRewardToken;

    Struct.ConfirmedTimestamp[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    /*===================================================================================================================*/
    /*==================================================== mapping ======================================================*/
    /*===================================================================================================================*/

    /* Config */
    mapping(address stakeToken => uint256 amount) public amountToLock;
    mapping(address stakeToken => uint256 weight) public stakeTokenSelectionWeight;

    /* Symbiotic Snapshot */
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(bytes32 submissionType => Struct.SnapshotTxCountInfo snapshot)) public
        txCountInfo;
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => bytes32 status)) public submissionStatus;

    // staked amount for each operator
    mapping(uint256 captureTimestamp => mapping(address stakeToken => mapping(address operator => uint256 stakeAmount)))
        operatorStakeAmounts;
    // staked amount for each vault
    mapping(
        uint256 captureTimestamp
            => mapping(address stakeToken => mapping(address vault => mapping(address operator => uint256 stakeAmount)))
    ) vaultStakeAmounts;

    mapping(uint256 jobId => Struct.SymbioticStakingLock lockInfo) public lockInfo; // note: this does not actually affect L1 Symbiotic stake
    mapping(address stakeToken => mapping(address operator => uint256 locked)) public operatorLockedAmounts;

    mapping(uint256 captureTimestamp => address transmitter) public registeredTransmitters; // only one transmitter can submit the snapshot for the same capturetimestamp

    /*===================================================================================================================*/
    /*=================================================== modifier ======================================================*/
    /*===================================================================================================================*/

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    /*===================================================================================================================*/
    /*================================================== initializer ====================================================*/
    /*===================================================================================================================*/

    function initialize(
        address _admin,
        address _jobManager,
        address _stakingManager,
        address _rewardDistributor,
        address _feeRewardToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_stakingManager != address(0), "SymbioticStaking: stakingManager is zero");
        stakingManager = _stakingManager;
        emit StakingManagerSet(_stakingManager);

        require(_jobManager != address(0), "SymbioticStaking: jobManager is zero");
        jobManager = _jobManager;
        emit JobManagerSet(_jobManager);
        require(_rewardDistributor != address(0), "SymbioticStaking: rewardDistributor is zero");
        rewardDistributor = _rewardDistributor;
        emit RewardDistributorSet(_rewardDistributor);

        require(_feeRewardToken != address(0), "SymbioticStaking: feeRewardToken is zero");
        feeRewardToken = _feeRewardToken;
        emit FeeRewardTokenSet(_feeRewardToken);
    }

    /*===================================================================================================================*/
    /*==================================================== external =====================================================*/
    /*===================================================================================================================*/

    /*------------------------------ L1 to L2 submission -----------------------------*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes calldata _vaultSnapshotData,
        bytes calldata _signature
    ) external {
        Struct.VaultSnapshot[] memory _vaultSnapshots = abi.decode(_vaultSnapshotData, (Struct.VaultSnapshot[]));

        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, STAKE_SNAPSHOT_TYPE);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _vaultSnapshotData, _signature);

        // update Vault and Operator stake amount
        // update rewardPerToken for each vault and operator in SymbioticStakingReward
        _submitVaultSnapshot(_captureTimestamp, _vaultSnapshots);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, STAKE_SNAPSHOT_TYPE);

        // when all chunks of VaultSnapshots are submitted
        if (_index == _numOfTxs - 1) {
            submissionStatus[_captureTimestamp][msg.sender] |= STAKE_SNAPSHOT_MASK;
        }

        emit VaultSnapshotSubmitted(msg.sender, _index, _numOfTxs, _vaultSnapshotData, _signature);
    }

    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _SlashResultData,
        bytes memory _signature
    ) external {
        Struct.JobSlashed[] memory _jobSlashed = abi.decode(_SlashResultData, (Struct.JobSlashed[]));

        // Vault Snapshot should be submitted before Slash Result
        require(
            submissionStatus[_captureTimestamp][msg.sender] & STAKE_SNAPSHOT_MASK == STAKE_SNAPSHOT_MASK,
            "Vault Snapshot not submitted"
        );

        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, SLASH_RESULT_TYPE);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _SlashResultData, _signature);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, SLASH_RESULT_TYPE);

        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][STAKE_SNAPSHOT_TYPE];

        // there could be no operator slashed
        if (_jobSlashed.length > 0) IStakingManager(stakingManager).onSlashResult(_jobSlashed);

        // TODO: unlock the selfStake and reward it to the transmitter
        emit SlashResultSubmitted(msg.sender, _index, _numOfTxs, _SlashResultData, _signature);

        // when all chunks of Snapshots are submitted
        if (_index == _numOfTxs - 1) {
            submissionStatus[_captureTimestamp][msg.sender] |= STAKE_SNAPSHOT_MASK;
            _completeSubmission(_captureTimestamp);
        }
    }

    /*--------------------------- stake lock/unlock for job --------------------------*/

    function lockStake(uint256 _jobId, address _operator) external onlyStakingManager {
        address _stakeToken = _selectStakeToken(_operator);
        uint256 _amountToLock = amountToLock[_stakeToken];
        require(getOperatorActiveStakeAmount(_stakeToken, _operator) >= _amountToLock, "Insufficient stake amount");

        lockInfo[_jobId] = Struct.SymbioticStakingLock(_stakeToken, _amountToLock);
        operatorLockedAmounts[_stakeToken][_operator] += _amountToLock;

        emit StakeLocked(_jobId, _operator, _stakeToken, _amountToLock);
    }

    function onJobCompletion(uint256 _jobId, address _operator, uint256 _feeRewardAmount) external onlyStakingManager {
        Struct.SymbioticStakingLock memory lock = lockInfo[_jobId];

        // distribute fee reward
        if (_feeRewardAmount > 0) {
            uint256 currentTimestampIdx = latestConfirmedTimestampIdx();
            uint256 transmitterComission =
                Math.mulDiv(_feeRewardAmount, confirmedTimestamps[currentTimestampIdx].transmitterComissionRate, 1e18);
            uint256 feeRewardRemaining = _feeRewardAmount - transmitterComission;

            // reward the transmitter who created the latestConfirmedTimestamp at the time of job creation
            JobManager(jobManager).distributeTransmitterFeeReward(
                confirmedTimestamps[currentTimestampIdx].transmitter, transmitterComission
            );

            // distribute the remaining fee reward
            _distributeFeeReward(lock.stakeToken, _operator, feeRewardRemaining);

            ISymbioticStakingReward(rewardDistributor).updateFeeReward(lock.stakeToken, _operator, feeRewardRemaining);
        }

        // unlock the stake locked during job creation
        delete lockInfo[_jobId];
        operatorLockedAmounts[lock.stakeToken][_operator] -= amountToLock[lock.stakeToken];

        emit StakeUnlocked(_jobId, _operator, lock.stakeToken, amountToLock[lock.stakeToken]);
    }

    /*------------------------------------- slash ------------------------------------*/

    // TODO: later
    function slash(Struct.JobSlashed[] calldata _slashedJobs) external onlyStakingManager {
        uint256 len = _slashedJobs.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.SymbioticStakingLock memory lock = lockInfo[_slashedJobs[i].jobId];

            uint256 lockedAmount = lock.amount;

            // unlock the stake locked during job creation
            operatorLockedAmounts[lock.stakeToken][_slashedJobs[i].operator] -= lockedAmount;
            delete lockInfo[_slashedJobs[i].jobId];

            emit JobSlashed(_slashedJobs[i].jobId, _slashedJobs[i].operator, lock.stakeToken, lockedAmount);
        }
    }

    /*===================================================================================================================*/
    /*===================================================== internal ====================================================*/
    /*===================================================================================================================*/

    /*------------------------------- Snapshot Submission ----------------------------*/

    function _checkTransmitterRegistration(uint256 _captureTimestamp) internal {
        if (registeredTransmitters[_captureTimestamp] == address(0)) {
            // once transmitter is registered, other transmitters cannot submit the snapshot for the same capturetimestamp
            registeredTransmitters[_captureTimestamp] = msg.sender;
        } else {
            require(registeredTransmitters[_captureTimestamp] == msg.sender, "Not registered transmitter");
        }
    }

    function _updateTxCountInfo(uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal {
        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][_type];

        // update length if 0
        if (_snapshot.numOfTxs == 0) {
            txCountInfo[_captureTimestamp][_type].numOfTxs = _numOfTxs;
        }

        // increase count by 1
        txCountInfo[_captureTimestamp][_type].idxToSubmit += 1;
    }

    function _submitVaultSnapshot(uint256 _captureTimestamp, Struct.VaultSnapshot[] memory _vaultSnapshots) internal {
        for (uint256 i = 0; i < _vaultSnapshots.length; i++) {
            Struct.VaultSnapshot memory _vaultSnapshot = _vaultSnapshots[i];

            // update vault staked amount
            vaultStakeAmounts[_captureTimestamp][_vaultSnapshot.stakeToken][_vaultSnapshot.vault][_vaultSnapshot
                .operator] = _vaultSnapshot.stakeAmount;

            // update operator staked amount
            operatorStakeAmounts[_captureTimestamp][_vaultSnapshot.stakeToken][_vaultSnapshot.operator] +=
                _vaultSnapshot.stakeAmount;

            ISymbioticStakingReward(rewardDistributor).onSnapshotSubmission(
                _vaultSnapshot.vault, _vaultSnapshot.operator
            );
        }
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        uint256 transmitterComission = _calcTransmitterComissionRate(_captureTimestamp);

        Struct.ConfirmedTimestamp memory confirmedTimestamp =
            Struct.ConfirmedTimestamp(_captureTimestamp, msg.sender, transmitterComission);
        confirmedTimestamps.push(confirmedTimestamp);

        emit SnapshotConfirmed(msg.sender, _captureTimestamp);
    }

    /*------------------------------ Reward Distribution -----------------------------*/

    function _distributeFeeReward(address _stakeToken, address _operator, uint256 _amount) internal {}

    /*===================================================================================================================*/
    /*================================================== external view ==================================================*/
    /*===================================================================================================================*/

    function latestConfirmedTimestamp() public view returns (uint256) {
        uint256 len = confirmedTimestamps.length;
        return len > 0 ? confirmedTimestamps[len - 1].captureTimestamp : 0;
    }

    function latestConfirmedTimestampInfo() external view returns (Struct.ConfirmedTimestamp memory) {
        return confirmedTimestamps[latestConfirmedTimestampIdx()];
    }

    function confirmedTimestampInfo(uint256 _idx) public view returns (Struct.ConfirmedTimestamp memory) {
        return confirmedTimestamps[_idx];
    }

    function latestConfirmedTimestampIdx() public view returns (uint256) {
        uint256 len = confirmedTimestamps.length;
        return len > 0 ? len - 1 : 0;
    }

    function getOperatorStakeAmount(address _stakeToken, address _operator) public view returns (uint256) {
        return operatorStakeAmounts[latestConfirmedTimestamp()][_stakeToken][_operator];
    }

    function getOperatorActiveStakeAmount(address _stakeToken, address _operator) public view returns (uint256) {
        uint256 operatorStakeAmount = getOperatorStakeAmount(_stakeToken, _operator);
        uint256 operatorLockedAmount = operatorLockedAmounts[_stakeToken][_operator];
        return operatorStakeAmount > operatorLockedAmount ? operatorStakeAmount - operatorLockedAmount : 0;
    }

    function getStakeAmount(address _stakeToken, address _vault, address _operator) external view returns (uint256) {
        return vaultStakeAmounts[latestConfirmedTimestamp()][_stakeToken][_vault][_operator];
    }

    function getStakeTokenList() external view returns (address[] memory) {
        return stakeTokenSet.values();
    }

    function getStakeTokenWeights() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory weights = new uint256[](stakeTokenSet.length());
        for (uint256 i = 0; i < stakeTokenSet.length(); i++) {
            weights[i] = stakeTokenSelectionWeight[stakeTokenSet.at(i)];
        }
        return (stakeTokenSet.values(), weights);
    }

    function isSupportedStakeToken(address _stakeToken) public view returns (bool) {
        return stakeTokenSet.contains(_stakeToken);
    }

    function getSubmissionStatus(uint256 _captureTimestamp, address _transmitter) external view returns (bytes32) {
        return submissionStatus[_captureTimestamp][_transmitter];
    }

    /*===================================================================================================================*/
    /*================================================== internal view ==================================================*/
    /*===================================================================================================================*/

    /*------------------------------ Snapshot Submission -----------------------------*/

    function _checkValidity(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type)
        internal
        view
    {
        require(_numOfTxs > 0, "Invalid length");

        // snapshot cannot be submitted before the cooldown period from the last confirmed timestamp (completed snapshot submission)
        require(_captureTimestamp >= (latestConfirmedTimestamp() + submissionCooldown), "Cooldown period not passed");
        require(_captureTimestamp <= block.timestamp, "Invalid timestamp");

        Struct.SnapshotTxCountInfo memory snapshot = txCountInfo[_captureTimestamp][_type];
        require(_index == snapshot.idxToSubmit, "Invalid index");
        require(_index < _numOfTxs, "Invalid index"); // here we assume enclave submis the correct data

        bytes32 mask;
        if (_type == STAKE_SNAPSHOT_TYPE) mask = STAKE_SNAPSHOT_MASK;
        else if (_type == SLASH_RESULT_TYPE) mask = SLASH_RESULT_MASK;
        require(submissionStatus[_captureTimestamp][msg.sender] & mask == 0, "Already submitted");

    }

    function _verifySignature(
        uint256 _index,
        uint256 _numOfTxs,
        uint256 _captureTimestamp,
        bytes memory _data,
        bytes memory _signature
    ) internal {
        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image
    }

    function _isCompleteStatus(uint256 _captureTimestamp) internal view returns (bool) {
        return submissionStatus[_captureTimestamp][msg.sender] == COMPLETE_MASK;
    }

    function _calcTransmitterComissionRate(uint256 _confirmedTimestamp) internal view returns (uint256) {
        // TODO: (block.timestamp - _lastConfirmedTimestamp) * X
        return baseTransmitterComissionRate;
    }

    function _currentTransmitter() internal view returns (address) {
        return confirmedTimestamps[latestConfirmedTimestampIdx()].transmitter;
    }

    /*-------------------------------------- Job -------------------------------------*/

    function _selectStakeToken(address _operator) internal view returns (address) {
        require(stakeTokenSelectionWeightSum > 0, "Total weight must be greater than zero");
        require(stakeTokenSet.length() > 0, "No tokens available");

        address[] memory tokens = new address[](stakeTokenSet.length());
        uint256[] memory weights = new uint256[](stakeTokenSet.length());

        uint256 weightSum = stakeTokenSelectionWeightSum;

        uint256 idx = 0;
        uint256 len = stakeTokenSet.length();
        for (uint256 i = 0; i < len; i++) {
            address token = stakeTokenSet.at(i);
            uint256 weight = stakeTokenSelectionWeight[token];
            // ignore if weight is 0
            if (weight > 0) {
                tokens[idx] = token;
                weights[idx] = weight;
                idx++;
            }
        }

        // repeat until a valid token is selected
        while (true) {
            require(idx > 0, "No stakeToken available to lock");

            // random number in range [0, weightSum - 1]
            uint256 random = uint256(
                keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), msg.sender))
            ) % weightSum;

            uint256 cumulativeWeight = 0;
            address selectedToken;

            uint256 i;
            // select token based on weight
            for (i = 0; i < idx; i++) {
                cumulativeWeight += weights[i];
                if (random < cumulativeWeight) {
                    selectedToken = tokens[i];
                    break;
                }
            }

            // check if the selected token has enough active stake amount
            if (getOperatorActiveStakeAmount(selectedToken, _operator) >= amountToLock[selectedToken]) {
                return selectedToken;
            }

            weightSum -= weights[i];
            tokens[i] = tokens[idx - 1];
            weights[i] = weights[idx - 1];
            idx--; // 배열 크기를 줄임
        }

        // this should be returned
        return address(0);
    }

    function _getActiveStakeAmount(address _stakeToken) internal view returns (uint256) {
        // TODO
    }

    function _transmitterComissionRate(uint256 _lastConfirmedTimestamp) internal view returns (uint256) {
        // TODO: implement logic
        return baseTransmitterComissionRate;
    }

    /*------------------------------------ Reward ------------------------------------*/

    /*===================================================================================================================*/
    /*===================================================== admin =======================================================*/
    /*===================================================================================================================*/

    function addStakeToken(address _stakeToken, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.add(_stakeToken), "Token already exists");

        stakeTokenSelectionWeightSum += _weight;
        stakeTokenSelectionWeight[_stakeToken] = _weight;

        emit StakeTokenAdded(_stakeToken, _weight);
    }

    function removeStakeToken(address _stakeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.remove(_stakeToken), "Token does not exist");

        stakeTokenSelectionWeightSum -= stakeTokenSelectionWeight[_stakeToken];
        delete stakeTokenSelectionWeight[_stakeToken];

        emit StakeTokenRemoved(_stakeToken);
    }

    function setAmountToLock(address _stakeToken, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        amountToLock[_stakeToken] = _amount;

        emit AmountToLockSet(_stakeToken, _amount);
    }

    function setStakeTokenSelectionWeight(address _stakeToken, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakeTokenSelectionWeightSum -= stakeTokenSelectionWeight[_stakeToken];
        stakeTokenSelectionWeight[_stakeToken] = _weight;
        stakeTokenSelectionWeightSum += _weight;

        emit StakeTokenSelectionWeightSet(_stakeToken, _weight);
    }

    function setSubmissionCooldown(uint256 _submissionCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        submissionCooldown = _submissionCooldown;

        emit SubmissionCooldownSet(_submissionCooldown);
    }

    /// @dev base transmitter comission rate is in range [0, 1e18)
    function setBaseTransmitterComissionRate(uint256 _baseTransmitterComission) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_baseTransmitterComission < 1e18, "Invalid comission rate");

        baseTransmitterComissionRate = _baseTransmitterComission;

        emit BaseTransmitterComissionRateSet(_baseTransmitterComission);
    }

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        emit StakingManagerSet(_stakingManager);
    }

    function setJobManager(address _jobManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        jobManager = _jobManager;

        emit JobManagerSet(_jobManager);
    }

    function setRewardDistributor(address _rewardDistributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardDistributor = _rewardDistributor;

        emit RewardDistributorSet(_rewardDistributor);
    }

    function setFeeRewardToken(address _feeRewardToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeRewardToken = _feeRewardToken;

        emit FeeRewardTokenSet(_feeRewardToken);
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
