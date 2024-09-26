// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

contract SymbioticStaking is 
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ISymbioticStaking 
    {
    using EnumerableSet for EnumerableSet.AddressSet;
    struct SymbioticStakingLock {
        address token;
        uint256 amount;
        // transmitter who submitted with confirmedTimestamp used when job is created
        address transmitter; 
    }

    uint256 submissionCooldown; // 18 decimal (in seconds)
    uint256 baseTransmitterComissionRate; // 18 decimal (in percentage)

    /* Job Status */
    bytes32 public constant VAULT_SNAPSHOT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 public constant SLASH_RESULT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 public constant COMPLETE_MASK = 0x0000000000000000000000000000000000000000000000000000000000000011;

    bytes32 public constant VAULT_SNAPSHOT = keccak256("VAULT_SNAPSHOT");
    bytes32 public constant SLASH_RESULT = keccak256("SLASH_RESULT");

    EnumerableSet.AddressSet tokenSet;

    address public stakingManager;
    
    /* Config */
    mapping(address token => uint256 amount) public amountToLock;

    /* Symbiotic Snapshot */
    mapping(uint256 captureTimestamp => mapping(address account => mapping(bytes32 submissionType => SnapshotTxCountInfo snapshot))) txCountInfo; // to check if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => bytes32 status)) submissionStatus; // to check if all partial txs are received
    // staked amount for each operator
    mapping(uint256 captureTimestamp => mapping(address operator => mapping(address token => uint256 stakeAmount))) operatorStakedAmounts;
    // staked amount for each vault
    mapping(uint256 captureTimestamp => mapping(address vault => mapping(address token => uint256 stakeAmount))) vaultStakedAmounts;
    // slash result for each job
    mapping(uint256 captureTimestamp  => mapping(uint256 jobId => SlashResult slashResult)) slashResults;

    ConfirmedTimestamp[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received


    /* Staking */
    mapping(uint256 jobId => SymbioticStakingLock lockInfo) public lockInfo; // note: this does not actually affect L1 Symbiotic stake

    mapping(uint256 captureTimestamp => address transmitter) registeredTransmitters;

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    function initialize(address _admin, address _stakingManager) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        stakingManager = _stakingManager;
    }

    /*======================================== L1 to L2 Transmission ========================================*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _vaultSnapshotData,
        bytes memory _signature
    ) external {
        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, VAULT_SNAPSHOT);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _vaultSnapshotData, _signature);

        // main update logic
        VaultSnapshot[] memory _vaultSnapshots = abi.decode(_vaultSnapshotData, (VaultSnapshot[]));
        _updateSnapshotInfo(_captureTimestamp, _vaultSnapshots);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, VAULT_SNAPSHOT);

        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][VAULT_SNAPSHOT];
        // when all chunks of OperatorSnapshot are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= VAULT_SNAPSHOT_MASK;
        }

        if (_isCompleteStatus(_captureTimestamp)) {
            _completeSubmission(_captureTimestamp);
        }
    }

    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _SlashResultData,
        bytes memory _signature
    ) external {
        _checkValidity(_index, _numOfTxs, _captureTimestamp, SLASH_RESULT);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _SlashResultData, _signature);

        SlashResultData[] memory _SlashResultDatas = abi.decode(_SlashResultData, (SlashResultData[]));
        _updateSlashResultDataInfo(_captureTimestamp, _SlashResultDatas);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, SLASH_RESULT);

        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][VAULT_SNAPSHOT];
        // when all chunks of OperatorSnapshot are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= VAULT_SNAPSHOT;
        }

        if (_isCompleteStatus(_captureTimestamp)) {
            _completeSubmission(_captureTimestamp);
        }

        // TODO: unlock the selfStake and reward it to the transmitter 
    }

    /*======================================== Job Creation ========================================*/
    // TODO: check if delegatedStake also gets locked
    function lockStake(uint256 _jobId, address _operator) external {
        address _token = _selectLockToken();
        uint256 stakedAmount = getOperatorStake(_operator, _token);
        require(stakedAmount >= amountToLock[_token], "Insufficient stake amount");

        // Store transmitter address to reward when job is closed
        address transmitter = confirmedTimestamps[confirmedTimestamps.length - 1].transmitter;
        lockInfo[_jobId] = SymbioticStakingLock(_token, amountToLock[_token], transmitter);

        // TODO: emit event
    }

    // TODO: check if delegatedStake also gets unlocked
    function unlockStake(uint256 _jobId) external {
        // TODO: consider the case when new pool is added during job

        // TODO: only staking manager
        lockInfo[_jobId].amount = 0;

        // TODO: emit event
    }

    function _selectLockToken() internal view returns(address) {
        require(tokenSet.length() > 0, "No supported token");

        uint256 idx;
        if (tokenSet.length() > 1) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))));
            idx = randomNumber % tokenSet.length();
        }
        return tokenSet.at(idx);
    }

    function getOperatorStake(address _operator, address _token) public view returns (uint256) {
        return operatorStakedAmounts[lastConfirmedTimestamp()][_operator][_token];
   }

    /*======================================== Helpers ========================================*/
    function _checkValidity(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal view {
        require(_numOfTxs > 0, "Invalid length");

        // snapshot cannot be submitted before the cooldown period from the last confirmed timestamp (completed snapshot submission)
        require(block.timestamp >= (lastConfirmedTimestamp() + submissionCooldown), "Cooldown period not passed");

        
        SnapshotTxCountInfo memory snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];
        require(_index == snapshot.idxToSubmit, "Invalid index");
        require(snapshot.idxToSubmit < snapshot.numOfTxs, "Snapshot fully submitted already");
        require(snapshot.numOfTxs == _numOfTxs, "Invalid length");

        bytes32 mask;
        if (_type == VAULT_SNAPSHOT) mask = VAULT_SNAPSHOT_MASK;
        else if (_type == SLASH_RESULT) mask = SLASH_RESULT_MASK;

        require(submissionStatus[_captureTimestamp][msg.sender] & mask == 0, "Snapshot fully submitted already");
    }

    function _checkTransmitterRegistration(uint256 _captureTimestamp) internal {
        if(registeredTransmitters[_captureTimestamp] == address(0)) {
            // once transmitter is registered, other transmitters cannot submit the snapshot for the same capturetimestamp
            registeredTransmitters[_captureTimestamp] = msg.sender;
        } else {
            require(registeredTransmitters[_captureTimestamp] == msg.sender, "Not registered transmitter");
        }
    }

    function _updateTxCountInfo(uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal {
        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];

        // increase count by 1
        txCountInfo[_captureTimestamp][msg.sender][_type].idxToSubmit += 1;

        // update length if 0
        if (_snapshot.numOfTxs == 0) {
            txCountInfo[_captureTimestamp][msg.sender][_type].numOfTxs = _numOfTxs;
        }
    }

    function _verifySignature(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes memory _data, bytes memory _signature) internal {
        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image
    }
    
    function _isCompleteStatus(uint256 _captureTimestamp) internal view returns (bool) {
        return submissionStatus[_captureTimestamp][msg.sender] == COMPLETE_MASK;
    }


    function _updateSnapshotInfo(uint256 _captureTimestamp, VaultSnapshot[] memory _vaultSnapshots) internal {
        for (uint256 i = 0; i < _vaultSnapshots.length; i++) {
            VaultSnapshot memory _vaultSnapshot = _vaultSnapshots[i];

            // update vault staked amount
            vaultStakedAmounts[_captureTimestamp][_vaultSnapshot.vault][_vaultSnapshot.token] = _vaultSnapshot.stake;

            // update operator staked amount
            operatorStakedAmounts[_captureTimestamp][_vaultSnapshot.operator][_vaultSnapshot.token] += _vaultSnapshot.stake;

            // TODO: emit event for each update?
        }
    }

    function _updateSlashResultDataInfo(uint256 _captureTimestamp, SlashResultData[] memory _SlashResultDatas)
        internal
    {
        for (uint256 i = 0; i < _SlashResultDatas.length; i++) {
            SlashResultData memory _slashResultData = _SlashResultDatas[i];

            slashResults[_slashResultData.jobId][_captureTimestamp] = _slashResultData.slashResult;

            // TODO: emit event for each update?
        }
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        uint256 transmitterComission = _calcTransmitterComissionRate(lastConfirmedTimestamp());

        ConfirmedTimestamp memory confirmedTimestamp = ConfirmedTimestamp(_captureTimestamp, msg.sender, transmitterComission);
        confirmedTimestamps.push(confirmedTimestamp);

        // TODO: emit event
    }

    function _calcTransmitterComissionRate(uint256 _lastConfirmedTimestamp) internal view returns (uint256) {
        // TODO: implement logic
    }

    /*======================================== Getters ========================================*/
    
    function lastConfirmedTimestamp() public view returns (uint256) {
        return confirmedTimestamps[confirmedTimestamps.length - 1].captureTimestamp;
    }

    function isSupportedToken(address _token) public view returns (bool) {
        return tokenSet.contains(_token);
    }

    /*======================================== Admin ========================================*/ 
    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        // TODO: emit event
    }

    function setSupportedToken(address _token, bool _isSupported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_isSupported) {
            require(tokenSet.add(_token), "Token already exists");
        } else {
            require(tokenSet.remove(_token), "Token does not exist");
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
