// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../interfaces/staking/ISymbioticStakingReward.sol";

import {Struct} from "../../lib/staking/Struct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";

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

    uint256 submissionCooldown; // 18 decimal (in seconds)
    uint256 baseTransmitterComissionRate; // 18 decimal (in percentage)

    /* Job Status */
    bytes32 public constant STAKE_SNAPSHOT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 public constant SLASH_RESULT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 public constant COMPLETE_MASK = 0x0000000000000000000000000000000000000000000000000000000000000011;

    bytes32 public constant STAKE_SNAPSHOT_TYPE = keccak256("STAKE_SNAPSHOT");
    bytes32 public constant SLASH_RESULT_TYPE = keccak256("SLASH_RESULT");

    EnumerableSet.AddressSet stakeTokenSet;

    address public feeRewardToken;
    address public inflationRewardToken;
    address public stakingManager;
    address public rewardDistributor;
    
    /* Config */
    mapping(address token => uint256 amount) public amountToLock;
    mapping(address stakeToken => uint256 share) public inflationRewardShare; // 1e18 = 100%


    /* Symbiotic Snapshot */
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => mapping(bytes32 submissionType => Struct.SnapshotTxCountInfo snapshot))) txCountInfo; 
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => bytes32 status)) submissionStatus; 
    // staked amount for each operator
    mapping(uint256 captureTimestamp => mapping(address operator => mapping(address stakeToken => uint256 stakeAmount))) operatorStakeAmounts;
    // staked amount for each vault
    mapping(uint256 captureTimestamp => mapping(address vault => mapping(address operator => mapping(address stakeToken => uint256 stakeAmount)))) vaultStakeAmounts;

    Struct.ConfirmedTimestamp[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received


    /* Staking */
    mapping(uint256 jobId => Struct.SymbioticStakingLock lockInfo) public lockInfo; // note: this does not actually affect L1 Symbiotic stake
    mapping(address operator => mapping(address stakeToken => uint256 locked)) public operatorLockedAmounts;

    mapping(uint256 captureTimestamp => address transmitter) registeredTransmitters; // only one transmitter can submit the snapshot for the same capturetimestamp

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    function initialize(address _admin, address _stakingManager, address _rewardDistributor) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        stakingManager = _stakingManager;
        rewardDistributor = _rewardDistributor;
    }

    /*===================================================== external ====================================================*/    

    /*------------------------------ L1 to L2 submission -----------------------------*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _vaultSnapshotData,
        bytes memory _signature
    ) external {
        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, STAKE_SNAPSHOT_TYPE);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _vaultSnapshotData, _signature);
        
        Struct.VaultSnapshot[] memory _vaultSnapshots = abi.decode(_vaultSnapshotData, (Struct.VaultSnapshot[]));

        // update Vault and Operator stake amount
        // update rewardPerToken for each vault and operator in SymbioticStakingReward
        _submitVaultSnapshot(_captureTimestamp, _vaultSnapshots);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, STAKE_SNAPSHOT_TYPE);

        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][STAKE_SNAPSHOT_TYPE];
        
        // when all chunks of VaultSnapshots are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= STAKE_SNAPSHOT_MASK;
        }
    }

    // TODO
    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _SlashResultData,
        bytes memory _signature
    ) external {
        // Vault Snapshot should be submitted before Slash Result
        require(submissionStatus[_captureTimestamp][msg.sender] & STAKE_SNAPSHOT_MASK == STAKE_SNAPSHOT_MASK, "Vault Snapshot not submitted");

        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, SLASH_RESULT_TYPE);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _SlashResultData, _signature);

        Struct.JobSlashed[] memory _jobSlashed = abi.decode(_SlashResultData, (Struct.JobSlashed[]));
        // _updateSlashResultDataInfo(_captureTimestamp, _jobSlashed);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, SLASH_RESULT_TYPE);

        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][STAKE_SNAPSHOT_TYPE];
        
        IStakingManager(stakingManager).onSlashResult(_jobSlashed);
        
        // when all chunks of Snapshots are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= STAKE_SNAPSHOT_MASK;
            _completeSubmission(_captureTimestamp);
        }


        // TODO: unlock the selfStake and reward it to the transmitter 
    }

    /*--------------------------- stake lock/unlock for job --------------------------*/

    function lockStake(uint256 _jobId, address _operator) external onlyStakingManager {
        address _token = _selectLockToken();
        require(getOperatorActiveStakeAmount(_operator, _token) >= amountToLock[_token], "Insufficient stake amount");

        // Store transmitter address to reward when job is closed
        uint256 timestampIdx = confirmedTimestamps.length - 1;
        address transmitter = confirmedTimestamps[timestampIdx].transmitter;

        lockInfo[_jobId] = Struct.SymbioticStakingLock(_token, amountToLock[_token], transmitter, confirmedTimestamps[timestampIdx].transmitterComissionRate);
        operatorLockedAmounts[_operator][_token] += amountToLock[_token];

        // TODO: emit event
    }

    function onJobCompletion(uint256 _jobId, address _operator, uint256 _feeRewardAmount, uint256 _inflationRewardAmount) external onlyStakingManager {
        Struct.SymbioticStakingLock memory lock = lockInfo[_jobId];

        uint256 transmitterComissionRate = lock.transmitterComissionRate;
        uint256 transmitterComission = Math.mulDiv(_feeRewardAmount, transmitterComissionRate, 1e18);

        uint256 feeRewardRemaining = _feeRewardAmount - transmitterComission;

        // distribute fee reward
        if(feeRewardRemaining > 0) {
            _distributeFeeReward(lock.stakeToken, _operator, feeRewardRemaining);
        }

        // distribute inflation reward
        if(_inflationRewardAmount > 0) {
            _distributeInflationReward(_operator, _inflationRewardAmount);
        }

        // reward the transmitter who created the latestConfirmedTimestamp at the time of job creation
        IERC20(feeRewardToken).safeTransfer(lock.transmitter, transmitterComission);

        // unlock the stake locked during job creation
        delete lockInfo[_jobId];
        operatorLockedAmounts[_operator][lock.stakeToken] -= amountToLock[lock.stakeToken];

        // TODO: emit event
    }

    /*------------------------------------- slash ------------------------------------*/

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external onlyStakingManager {
        uint256 len = _slashedJobs.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.SymbioticStakingLock memory lock = lockInfo[_slashedJobs[i].jobId];

            uint256 lockedAmount = lock.amount;

            // unlock the stake locked during job creation
            operatorLockedAmounts[_slashedJobs[i].operator][lock.stakeToken] -= lockedAmount;
            delete lockInfo[_slashedJobs[i].jobId];

            // TODO: emit events?
        }
    }

    function distributeInflationReward(address _operator, uint256 _rewardAmount) external onlyStakingManager {
        if(_rewardAmount == 0) return;

        uint256 len = stakeTokenSet.length();
        for(uint256 i = 0; i < len; i++) {
            _distributeInflationReward(_operator, _calcInflationRewardAmount(stakeTokenSet.at(i), _rewardAmount)); // TODO: gas optimization
        }
    }

    /*===================================================== internal ====================================================*/

    /*------------------------------- Snapshot Submission ----------------------------*/

    function _checkTransmitterRegistration(uint256 _captureTimestamp) internal {
        if(registeredTransmitters[_captureTimestamp] == address(0)) {
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
            vaultStakeAmounts[_captureTimestamp][_vaultSnapshot.vault][_vaultSnapshot.operator][_vaultSnapshot.stakeToken] = _vaultSnapshot.stakeAmount;

            // update operator staked amount
            operatorStakeAmounts[_captureTimestamp][_vaultSnapshot.operator][_vaultSnapshot.stakeToken] += _vaultSnapshot.stakeAmount;

            // TODO: emit event for each update?
        }
        
        ISymbioticStakingReward(rewardDistributor).onSnapshotSubmission(_vaultSnapshots);
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        uint256 transmitterComission = _calcTransmitterComissionRate(_captureTimestamp);

        Struct.ConfirmedTimestamp memory confirmedTimestamp = Struct.ConfirmedTimestamp(_captureTimestamp, msg.sender, transmitterComission);
        confirmedTimestamps.push(confirmedTimestamp);

        // TODO: emit event
    }

    /*------------------------------ Reward Distribution -----------------------------*/

    function _distributeFeeReward(address _stakeToken, address _operator, uint256 _amount) internal {
        ISymbioticStakingReward(rewardDistributor).updateFeeReward(_stakeToken, _operator, _amount);
    }


    function _distributeInflationReward(address _operator, uint256 _amount) internal {
        ISymbioticStakingReward(rewardDistributor).updateInflationReward(_operator, _amount);
    }

    /*================================================== external view ==================================================*/


    function lastConfirmedTimestamp() public view returns (uint256) {
        return confirmedTimestamps[confirmedTimestamps.length - 1].captureTimestamp;
    }

    function getOperatorStakeAmount(address _operator, address _token) public view returns (uint256) {
        return operatorStakeAmounts[lastConfirmedTimestamp()][_operator][_token];
    }

    function getOperatorActiveStakeAmount(address _operator, address _token) public view returns (uint256) {
        uint256 operatorStakeAmount = getOperatorStakeAmount(_operator, _token);
        uint256 operatorLockedAmount = operatorLockedAmounts[_operator][_token];
        return operatorStakeAmount > operatorLockedAmount ? operatorStakeAmount - operatorLockedAmount : 0;
    }

    function getStakeAmount(address _vault, address _stakeToken, address _operator) external view returns (uint256) {
        return vaultStakeAmounts[lastConfirmedTimestamp()][_vault][_stakeToken][_operator];
    }

    function getStakeTokenList() external view returns(address[] memory) {
        return stakeTokenSet.values();
    }

    function isSupportedStakeToken(address _token) public view returns (bool) {
        return stakeTokenSet.contains(_token);
    }

    /*================================================== internal view ==================================================*/

    /*------------------------------ Snapshot Submission -----------------------------*/

    function _checkValidity(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal view {
        require(_numOfTxs > 0, "Invalid length");

        // snapshot cannot be submitted before the cooldown period from the last confirmed timestamp (completed snapshot submission)
        require(block.timestamp >= (lastConfirmedTimestamp() + submissionCooldown), "Cooldown period not passed");

        
        Struct.SnapshotTxCountInfo memory snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];
        require(_index == snapshot.idxToSubmit, "Invalid index");
        require(_index < snapshot.numOfTxs, "Invalid index");
        require(snapshot.numOfTxs == _numOfTxs, "Invalid numOfTxs");

        bytes32 mask;
        if (_type == STAKE_SNAPSHOT_TYPE) mask = STAKE_SNAPSHOT_MASK;
        else if (_type == SLASH_RESULT_TYPE) mask = SLASH_RESULT_MASK;

        require(submissionStatus[_captureTimestamp][msg.sender] & mask == 0, "Already submitted");
    }

    function _verifySignature(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes memory _data, bytes memory _signature) internal {
        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image
    }

    function _isCompleteStatus(uint256 _captureTimestamp) internal view returns (bool) {
        return submissionStatus[_captureTimestamp][msg.sender] == COMPLETE_MASK;
    }

    function _calcTransmitterComissionRate(uint256 _confirmedTimestamp) internal view returns(uint256) {
        // TODO: (block.timestamp - _lastConfirmedTimestamp) * X
    }

    /*-------------------------------------- Job -------------------------------------*/

    // TODO: weight based random selection
    function _selectLockToken() internal view returns(address) {
        require(stakeTokenSet.length() > 0, "No supported token");

        uint256 idx;
        if (stakeTokenSet.length() > 1) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))));
            idx = randomNumber % stakeTokenSet.length();
        }
        return stakeTokenSet.at(idx);
    }

    function _transmitterComissionRate(uint256 _lastConfirmedTimestamp) internal view returns (uint256) {
        // TODO: implement logic
    }

    /*------------------------------------ Reward ------------------------------------*/

    function _calcInflationRewardAmount(address _stakeToken, uint256 _inflationRewardAmount) internal view returns(uint256) {
        return Math.mulDiv(_inflationRewardAmount, inflationRewardShare[_stakeToken], 1e18);
    }

    /*====================================================== admin ======================================================*/

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        // TODO: emit event
    }

    function setStakeToken(address _token, bool _isSupported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_isSupported) {
            require(stakeTokenSet.add(_token), "Token already exists");
        } else {
            require(stakeTokenSet.remove(_token), "Token does not exist");
        }
    }

    function setSubmissionCooldown(uint256 _submissionCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        submissionCooldown = _submissionCooldown;

        // TODO: emit event
    }

    function setBaseTransmitterComission(uint256 _baseTransmitterComission) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
