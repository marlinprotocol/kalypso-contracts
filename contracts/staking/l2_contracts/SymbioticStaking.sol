// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// TODO: vault => token info should be updated by the admin

contract SymbioticStaking is ISymbioticStaking {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 submissionCooldown; // 18 decimal (in seconds)
    uint256 transmitterComission; // 18 decimal (in percentage)

    bytes32 public constant OPERATOR_SNAPSHOT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 public constant VAULT_SNAPSHOT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 public constant SLASH_RESULT_MASK = 0x0000000000000000000000000000000000000000000000000000000000000100;
    bytes32 public constant COMPLETE_MASK = 0x0000000000000000000000000000000000000000000000000000000000000111;

    bytes32 public constant OPERATOR_SNAPSHOT = keccak256("OPERATOR_SNAPSHOT");
    bytes32 public constant VAULT_SNAPSHOT = keccak256("VAULT_SNAPSHOT");
    bytes32 public constant SLASH_RESULT = keccak256("SLASH_RESULT");

    /*======================================== Config ========================================*/
    mapping(address token => uint256 amount) public minStakeAmount;
    mapping(address token => uint256 amount) public amountToLock;

    // TODO: redundant to L1 Data
    EnumerableSet.AddressSet tokenSet;
    // mapping(address vault => address token) public vaultToToken;
    // mapping(address token => uint256 numVaults) public tokenToNumVaults; // number of vaults that support the token

    /* Symbiotic Data Transmission */
    mapping(uint256 captureTimestamp => mapping(address account => mapping(bytes32 submissionType => SnapshotTxCountInfo snapshot))) txCountInfo; // to check if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => bytes32 status)) submissionStatus; // to check if all partial txs are received

    // staked amount for each operator
    mapping(uint256 captureTimestamp => mapping(address operator => mapping(address token => uint256 stakeAmount))) operatorStakedAmounts;
    // staked amount for each vault
    mapping(uint256 captureTimestamp => mapping(address vault => mapping(address token => uint256 stakeAmount))) vaultStakedAmounts;
    // slash result for each job
    mapping(uint256 captureTimestamp  => mapping(uint256 jobId => SlashResult slashResult)) slashResults;

    ConfirmedTimestamp[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received

    struct SymbioticStakingLock {
        address token;
        uint256 amount;
        address transmitter;
    }

    /* Staking */
    mapping(uint256 jobId => SymbioticStakingLock lockInfo) public lockInfo; // note: this does not actually affect L1 Symbiotic stake

    /*======================================== L1 to L2 Transmission ========================================*/
    // Transmitter submits staking data snapshot
    // This should update StakingManger's state

    // TODO: consolidate with submitVaultSnapshot
    function submitOperatorSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _operatorSnapshotData,
        bytes memory _signature
    ) external {
        _checkValidity(_index, _numOfTxs, _captureTimestamp, OPERATOR_SNAPSHOT);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _operatorSnapshotData, _signature);

        // main update logic
        // TODO: consolidate this into VaultSnapshot[]
        OperatorSnapshot[] memory _operatorSnapshots = abi.decode(_operatorSnapshotData, (OperatorSnapshot[]));
        _updateOperatorSnapshotInfo(_captureTimestamp, _operatorSnapshots);

        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][OPERATOR_SNAPSHOT];

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, OPERATOR_SNAPSHOT);

        // when all chunks of OperatorSnapshot are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= OPERATOR_SNAPSHOT_MASK;
        }

        if (_isCompleteStatus(_captureTimestamp)) {
            _completeSubmission(_captureTimestamp);
        }
    }

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _vaultSnapshotData,
        bytes memory _signature
    ) external {
        _checkValidity(_index, _numOfTxs, _captureTimestamp, VAULT_SNAPSHOT);

        _verifySignature(_index, _numOfTxs, _captureTimestamp, _vaultSnapshotData, _signature);

        // main update logic
        VaultSnapshot[] memory _vaultSnapshots = abi.decode(_vaultSnapshotData, (VaultSnapshot[]));
        _updateVaultSnapshotInfo(_captureTimestamp, _vaultSnapshots);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, VAULT_SNAPSHOT);

        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][OPERATOR_SNAPSHOT];
        // when all chunks of OperatorSnapshot are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= OPERATOR_SNAPSHOT_MASK;
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

        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][OPERATOR_SNAPSHOT];
        // when all chunks of OperatorSnapshot are submitted
        if (_snapshot.idxToSubmit == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= OPERATOR_SNAPSHOT_MASK;
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
        require(stakedAmount >= minStakeAmount[_token], "Insufficient stake amount");

        // Store transmitter address to reward when job is closed
        address transmitter = confirmedTimestamps[confirmedTimestamps.length - 1].transmitter;
        lockInfo[_jobId] = SymbioticStakingLock(_token, amountToLock[_token], transmitter);

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

    // TODO: check if delegatedStake also gets unlocked
    function unlockStake(uint256 _jobId) external {
        // TODO: only staking manager
        lockInfo[_jobId].amount = 0;

        // TODO: emit event
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
        if (_type == OPERATOR_SNAPSHOT) mask = OPERATOR_SNAPSHOT_MASK;
        else if (_type == VAULT_SNAPSHOT) mask = VAULT_SNAPSHOT_MASK;
        else if (_type == SLASH_RESULT) mask = SLASH_RESULT_MASK;

        require(submissionStatus[_captureTimestamp][msg.sender] & mask == 0, "Snapshot fully submitted already");
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

    function _updateOperatorSnapshotInfo(uint256 _captureTimestamp, OperatorSnapshot[] memory _operatorSnapshots)
        internal
    {
        for (uint256 i = 0; i < _operatorSnapshots.length; i++) {
            OperatorSnapshot memory _operatorSnapshot = _operatorSnapshots[i];

            operatorStakedAmounts[_captureTimestamp][_operatorSnapshot.operator][_operatorSnapshot.token] =
                _operatorSnapshot.stake;

            // TODO: emit event for each update?
        }
    }
    function _updateVaultSnapshotInfo(uint256 _captureTimestamp, VaultSnapshot[] memory _vaultSnapshots) internal {
        for (uint256 i = 0; i < _vaultSnapshots.length; i++) {
            VaultSnapshot memory _vaultSnapshot = _vaultSnapshots[i];

            vaultStakedAmounts[_captureTimestamp][_vaultSnapshot.vault][_vaultSnapshot.token] = _vaultSnapshot.stake;

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
        // TODO: calc `transmitterComission` based on last submission
        ConfirmedTimestamp memory confirmedTimestamp = ConfirmedTimestamp(_captureTimestamp, block.timestamp, msg.sender);
        confirmedTimestamps.push(confirmedTimestamp);

        // TODO: calculate rewards for the transmitter based on transmitterComission
        // TODO: Data transmitter should get transmitterComission% of the rewards
        // TODO: "transmitterComission" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + submissionCooldown)"

        // TODO: emit SubmissionCompleted
    }

    /*======================================== Getters ========================================*/
    
    function lastConfirmedTimestamp() public view returns (uint256) {
        return confirmedTimestamps[confirmedTimestamps.length - 1].capturedTimestamp;
    }

    function isSupportedToken(address _token) public view returns (bool) {
        // TODO
    }

    function isSupportedVault(address _vault) public view returns (bool) {
        // TODO
    }

    /*======================================== Admin ========================================*/ 
    function setSupportedToken(address _token, bool _isSupported) external {
        // TODO
    }
}
