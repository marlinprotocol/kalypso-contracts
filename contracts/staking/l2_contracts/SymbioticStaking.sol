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
import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";
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

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    /* Job Status */
    bytes32 public constant STAKE_SNAPSHOT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 public constant SLASH_RESULT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 public constant COMPLETE_MASK = 0x0000000000000000000000000000000000000000000000000000000000000011;

    bytes32 public constant STAKE_SNAPSHOT_TYPE = keccak256("STAKE_SNAPSHOT_TYPE");
    bytes32 public constant SLASH_RESULT_TYPE = keccak256("SLASH_RESULT_TYPE");

    uint256 public submissionCooldown; // 18 decimal (in seconds)
    uint256 public baseTransmitterComissionRate; // 18 decimal (in percentage)

    EnumerableSet.AddressSet stakeTokenSet;

    address public stakingManager;
    address public jobManager;
    address public rewardDistributor;
    address public inflationRewardManager;

    address public feeRewardToken;
    address public inflationRewardToken;

    uint256 public tokenSelectionWeightSum;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    /* Config */
    mapping(address stakeToken => uint256 amount) public amountToLock;
    mapping(address stakeToken => uint256 weight) public tokenSelectionWeight;
    mapping(address stakeToken => uint256 share) public inflationRewardShare; // 1e18 = 100%

    /* Symbiotic Snapshot */
    // to track if all partial txs are received
    mapping(
        uint256 captureTimestamp
            => mapping(address account => mapping(bytes32 submissionType => Struct.SnapshotTxCountInfo snapshot))
    ) txCountInfo;
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => bytes32 status)) submissionStatus;

    // staked amount for each operator
    mapping(uint256 captureTimestamp => mapping(address stakeToken => mapping(address operator => uint256 stakeAmount)))
        operatorStakeAmounts;
    // staked amount for each vault
    mapping(
        uint256 captureTimestamp
            => mapping(address stakeToken => mapping(address vault => mapping(address operator => uint256 stakeAmount)))
    ) vaultStakeAmounts;

    Struct.ConfirmedTimestamp[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received

    /* Staking */
    mapping(uint256 jobId => Struct.SymbioticStakingLock lockInfo) public lockInfo; // note: this does not actually affect L1 Symbiotic stake
    mapping(address stakeToken => mapping(address operator => uint256 locked)) public operatorLockedAmounts;

    mapping(uint256 captureTimestamp => address transmitter) registeredTransmitters; // only one transmitter can submit the snapshot for the same capturetimestamp

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    function initialize(
        address _admin,
        address _jobManager,
        address _stakingManager,
        address _rewardDistributor,
        address _inflationRewardManager,
        address _feeRewardToken,
        address _inflationRewardToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_stakingManager != address(0), "SymbioticStaking: stakingManager is zero");
        stakingManager = _stakingManager;

        require(_jobManager != address(0), "SymbioticStaking: jobManager is zero");
        jobManager = _jobManager;

        require(_rewardDistributor != address(0), "SymbioticStaking: rewardDistributor is zero");
        rewardDistributor = _rewardDistributor;

        require(_inflationRewardManager != address(0), "SymbioticStaking: inflationRewardManager is zero");
        inflationRewardManager = _inflationRewardManager;

        require(_feeRewardToken != address(0), "SymbioticStaking: feeRewardToken is zero");
        feeRewardToken = _feeRewardToken;

        require(_inflationRewardToken != address(0), "SymbioticStaking: inflationRewardToken is zero");
        inflationRewardToken = _inflationRewardToken;
    }

    /*===================================================== external ====================================================*/

    /*------------------------------ L1 to L2 submission -----------------------------*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        bytes calldata _vaultSnapshotData,
        bytes calldata _signature
    ) external {
        (uint256 captureTimestamp, Struct.VaultSnapshot[] memory _vaultSnapshots) =
            abi.decode(_vaultSnapshotData, (uint256, Struct.VaultSnapshot[]));

        _checkTransmitterRegistration(captureTimestamp);

        _checkValidity(_index, _numOfTxs, captureTimestamp, STAKE_SNAPSHOT_TYPE);

        _verifySignature(_index, _numOfTxs, captureTimestamp, _vaultSnapshotData, _signature);

        // update Vault and Operator stake amount
        // update rewardPerToken for each vault and operator in SymbioticStakingReward
        _submitVaultSnapshot(captureTimestamp, _vaultSnapshots);

        _updateTxCountInfo(_numOfTxs, captureTimestamp, STAKE_SNAPSHOT_TYPE);

        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[captureTimestamp][msg.sender][STAKE_SNAPSHOT_TYPE];

        // when all chunks of VaultSnapshots are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[captureTimestamp][msg.sender] |= STAKE_SNAPSHOT_MASK;
        }
    }

    // TODO
    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        bytes memory _SlashResultData,
        bytes memory _signature
    ) external {
        (uint256 captureTimestamp, Struct.JobSlashed[] memory _jobSlashed) =
            abi.decode(_SlashResultData, (uint256, Struct.JobSlashed[]));

        // Vault Snapshot should be submitted before Slash Result
        require(
            submissionStatus[captureTimestamp][msg.sender] & STAKE_SNAPSHOT_MASK == STAKE_SNAPSHOT_MASK,
            "Vault Snapshot not submitted"
        );

        _checkTransmitterRegistration(captureTimestamp);

        _checkValidity(_index, _numOfTxs, captureTimestamp, SLASH_RESULT_TYPE);

        _verifySignature(_index, _numOfTxs, captureTimestamp, _SlashResultData, _signature);

        _updateTxCountInfo(_numOfTxs, captureTimestamp, SLASH_RESULT_TYPE);

        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[captureTimestamp][msg.sender][STAKE_SNAPSHOT_TYPE];

        // there could be no operator slashed
        if (_jobSlashed.length > 0) IStakingManager(stakingManager).onSlashResult(_jobSlashed);

        // when all chunks of Snapshots are submitted
        uint256 numOfTxsStored = _snapshot.numOfTxs;
        if (numOfTxsStored > 0 && _snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[captureTimestamp][msg.sender] |= STAKE_SNAPSHOT_MASK;
            _completeSubmission(captureTimestamp);
        }

        // TODO: unlock the selfStake and reward it to the transmitter
    }

    /*--------------------------- stake lock/unlock for job --------------------------*/

    function lockStake(uint256 _jobId, address _operator) external onlyStakingManager {
        address _stakeToken = _selectStakeToken(_operator);
        uint256 _amountToLock = amountToLock[_stakeToken];
        require(getOperatorActiveStakeAmount(_stakeToken, _operator) >= _amountToLock, "Insufficient stake amount");

        lockInfo[_jobId] = Struct.SymbioticStakingLock(_stakeToken, _amountToLock);
        operatorLockedAmounts[_stakeToken][_operator] += _amountToLock;

        // TODO: emit event
    }

    function onJobCompletion(
        uint256 _jobId,
        address _operator,
        uint256 _feeRewardAmount,
        uint256 _inflationRewardAmount,
        uint256 _inflationRewardTimestampIdx
    ) external onlyStakingManager {
        Struct.SymbioticStakingLock memory lock = lockInfo[_jobId];

        // currentEpoch => currentTimestampIdx
        IInflationRewardManager(inflationRewardManager).updateEpochTimestampIdx();

        // distribute fee reward
        if (_feeRewardAmount > 0) {
            uint256 currentTimestampIdx = latestConfirmedTimestampIdx();
            uint256 transmitterComission =
                Math.mulDiv(_feeRewardAmount, confirmedTimestamps[currentTimestampIdx].transmitterComissionRate, 1e18);
            uint256 feeRewardRemaining = _feeRewardAmount - transmitterComission;

            // reward the transmitter who created the latestConfirmedTimestamp at the time of job creation
            JobManager(jobManager).transferFeeToken(confirmedTimestamps[currentTimestampIdx].transmitter, transmitterComission);

            // distribute the remaining fee reward
            _distributeFeeReward(lock.stakeToken, _operator, feeRewardRemaining);

            ISymbioticStakingReward(rewardDistributor).updateFeeReward(lock.stakeToken, _operator, feeRewardRemaining);
        }

        // distribute inflation reward
        if (_inflationRewardAmount > 0) {
            uint256 transmitterComission = Math.mulDiv(
                _inflationRewardAmount, confirmedTimestamps[_inflationRewardTimestampIdx].transmitterComissionRate, 1e18
            );
            uint256 inflationRewardRemaining = _inflationRewardAmount - transmitterComission;

            // reward the transmitter who created the latestConfirmedTimestamp at the time of job creation
            IInflationRewardManager(inflationRewardManager).transferInflationRewardToken(
                confirmedTimestamps[_inflationRewardTimestampIdx].transmitter, transmitterComission
            );

            // distribute the remaining inflation reward
            _distributeInflationReward(_operator, inflationRewardRemaining);

            ISymbioticStakingReward(rewardDistributor).updateInflationReward(_operator, inflationRewardRemaining);
        }

        // unlock the stake locked during job creation
        delete lockInfo[_jobId];
        operatorLockedAmounts[lock.stakeToken][_operator] -= amountToLock[lock.stakeToken];

        // TODO: emit event
    }

    /*------------------------------------- slash ------------------------------------*/

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external onlyStakingManager {
        uint256 len = _slashedJobs.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.SymbioticStakingLock memory lock = lockInfo[_slashedJobs[i].jobId];

            uint256 lockedAmount = lock.amount;

            // unlock the stake locked during job creation
            operatorLockedAmounts[lock.stakeToken][_slashedJobs[i].operator] -= lockedAmount;
            delete lockInfo[_slashedJobs[i].jobId];

            // TODO: emit events?
        }
    }

    /// @notice called when pending inflation reward is updated
    function distributeInflationReward(address _operator, uint256 _rewardAmount, uint256 _timestampIdx)
        external
        onlyStakingManager
    {
        if (_rewardAmount == 0) return;

        uint256 transmitterComission =
            Math.mulDiv(_rewardAmount, confirmedTimestamps[_timestampIdx].transmitterComissionRate, 1e18);
        uint256 inflationRewardRemaining = _rewardAmount - transmitterComission;

        // reward the transmitter who created the latestConfirmedTimestamp at the time of job creation
        IERC20(inflationRewardToken).safeTransfer(confirmedTimestamps[_timestampIdx].transmitter, transmitterComission);

        uint256 len = stakeTokenSet.length();
        for (uint256 i = 0; i < len; i++) {
            _distributeInflationReward(
                _operator, _calcInflationRewardAmount(stakeTokenSet.at(i), inflationRewardRemaining)
            ); // TODO: gas optimization
        }
    }

    /*===================================================== internal ====================================================*/

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
        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];

        // update length if 0
        if (_snapshot.numOfTxs == 0) {
            txCountInfo[_captureTimestamp][msg.sender][_type].numOfTxs = _numOfTxs;
        }

        // increase count by 1
        txCountInfo[_captureTimestamp][msg.sender][_type].idxToSubmit += 1;
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

            // TODO: emit event for each update?
        }
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        uint256 transmitterComission = _calcTransmitterComissionRate(_captureTimestamp);

        Struct.ConfirmedTimestamp memory confirmedTimestamp =
            Struct.ConfirmedTimestamp(_captureTimestamp, msg.sender, transmitterComission);
        confirmedTimestamps.push(confirmedTimestamp);

        IInflationRewardManager(inflationRewardManager).updateEpochTimestampIdx();
        // TODO: emit event
    }

    /*------------------------------ Reward Distribution -----------------------------*/

    function _distributeFeeReward(address _stakeToken, address _operator, uint256 _amount) internal {}

    function _distributeInflationReward(address _operator, uint256 _amount) internal {
        ISymbioticStakingReward(rewardDistributor).updateInflationReward(_operator, _amount);
    }

    /*================================================== external view ==================================================*/

    function latestConfirmedTimestamp() public view returns (uint256) {
        uint256 len = confirmedTimestamps.length;
        return len > 0 ? confirmedTimestamps[len - 1].captureTimestamp : 0;
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
            weights[i] = tokenSelectionWeight[stakeTokenSet.at(i)];
        }
        return (stakeTokenSet.values(), weights);
    }

    function isSupportedStakeToken(address _stakeToken) public view returns (bool) {
        return stakeTokenSet.contains(_stakeToken);
    }

    function getTxCountInfo(uint256 _captureTimestamp, address _transmitter, bytes32 _type)
        external
        view
        returns (Struct.SnapshotTxCountInfo memory)
    {
        return txCountInfo[_captureTimestamp][_transmitter][_type];
    }

    function getSubmissionStatus(uint256 _captureTimestamp, address _transmitter) external view returns (bytes32) {
        return submissionStatus[_captureTimestamp][_transmitter];
    }

    /*================================================== internal view ==================================================*/

    /*------------------------------ Snapshot Submission -----------------------------*/

    function _checkValidity(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type)
        internal
        view
    {
        require(_numOfTxs > 0, "Invalid length");

        // snapshot cannot be submitted before the cooldown period from the last confirmed timestamp (completed snapshot submission)
        require(_captureTimestamp >= (latestConfirmedTimestamp() + submissionCooldown), "Cooldown period not passed");
        require(_captureTimestamp <= block.timestamp, "Invalid timestamp");

        Struct.SnapshotTxCountInfo memory snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];
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
        require(tokenSelectionWeightSum > 0, "Total weight must be greater than zero");
        require(stakeTokenSet.length() > 0, "No tokens available");

        address[] memory tokens = new address[](stakeTokenSet.length());
        uint256[] memory weights = new uint256[](stakeTokenSet.length());

        uint256 weightSum = tokenSelectionWeightSum;

        uint256 idx = 0;
        uint256 len = stakeTokenSet.length();
        for (uint256 i = 0; i < len; i++) {
            address token = stakeTokenSet.at(i);
            uint256 weight = tokenSelectionWeight[token];
            // ignore if weight is 0
            if (weight > 0) {
                tokens[idx] = token;
                weights[idx] = weight;
                idx++;
            }
        }

        // repeat until a valid token is selected
        while (true) {
            require(idx > 0, "No stakeToken available");

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

    function _calcInflationRewardAmount(address _stakeToken, uint256 _inflationRewardAmount)
        internal
        view
        returns (uint256)
    {
        return Math.mulDiv(_inflationRewardAmount, inflationRewardShare[_stakeToken], 1e18);
    }

    /*====================================================== admin ======================================================*/

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        // TODO: emit event
    }

    function addStakeToken(address _stakeToken, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.add(_stakeToken), "Token already exists");

        tokenSelectionWeightSum += _weight;
        tokenSelectionWeight[_stakeToken] = _weight;
    }

    function setAmountToLock(address _stakeToken, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        amountToLock[_stakeToken] = _amount;
    }

    function removeStakeToken(address _stakeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.remove(_stakeToken), "Token does not exist");

        tokenSelectionWeightSum -= tokenSelectionWeight[_stakeToken];
        delete tokenSelectionWeight[_stakeToken];
    }

    function setStakeTokenWeight(address _stakeToken, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenSelectionWeightSum -= tokenSelectionWeight[_stakeToken];
        tokenSelectionWeight[_stakeToken] = _weight;
        tokenSelectionWeightSum += _weight;
    }

    function setSubmissionCooldown(uint256 _submissionCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        submissionCooldown = _submissionCooldown;

        // TODO: emit event
    }

    /// @dev base transmitter comission rate is in range [0, 1e18)
    function setBaseTransmitterComissionRate(uint256 _baseTransmitterComission) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_baseTransmitterComission < 1e18, "Invalid comission rate");

        baseTransmitterComissionRate = _baseTransmitterComission;

        // TODO: emit event
    }

    /*==================================================== overrides ====================================================*/

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
