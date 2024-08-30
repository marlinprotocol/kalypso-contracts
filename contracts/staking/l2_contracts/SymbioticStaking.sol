// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

contract SymbioticStaking is ISymbioticStaking {
    // TODO: address Operator => address token => CheckPoints.Trace256 stakeAmount (Question: operators' stake amount is consolidated within same vault?)

    // TODO: set SD
    uint256 SD;

    // TODO: set TC
    uint256 TC;

    //? How to manage Vault lists?

    bytes4 public constant OPERATOR_SNAPSHOT_MASK = 0x00000001;
    bytes4 public constant VAULT_SNAPSHOT_MASK = 0x00000010;
    bytes4 public constant SLASH_RESULT_MASK = 0x00000100;
    bytes4 public constant COMPLETE_MASK = 0x00000111;

    bytes32 public constant OPERATOR_SNAPSHOT = keccak256("OPERATOR_SNAPSHOT");
    bytes32 public constant VAULT_SNAPSHOT = keccak256("VAULT_SNAPSHOT");
    bytes32 public constant SLASH_RESULT = keccak256("SLASH_RESULT");

    mapping(uint256 captureTimestamp => mapping(address account => mapping(bytes32 submissionType => SnapshotTxCountInfo snapshot))) txCountInfo; // to check if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => bytes4 status)) submissionStatus; // to check if all partial txs are received

    mapping(address operator => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake)))operatorSnapshots;
    mapping(address vault => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake)))vaultSnapshots;
    mapping(uint256 jobId => mapping(uint256 captureTimestamp => SlashResult SlashResultData)) SlashResultDatas; // TODO: need to check actual slashing timestamp?

    uint256[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received

    // Transmitter submits staking data snapshot
    // This should update StakingManger's state
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
        OperatorSnapshot[] memory _operatorSnapshots = abi.decode(_operatorSnapshotData, (OperatorSnapshot[]));
        _updateOperatorSnapshotInfo(_captureTimestamp, _operatorSnapshots);

        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][OPERATOR_SNAPSHOT];

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, OPERATOR_SNAPSHOT);

        // when all chunks of OperatorSnapshot are submitted
        if (_snapshot.count == _snapshot.numOfTxs) {
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
        if (_snapshot.count == _snapshot.numOfTxs) {
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
        if (_snapshot.count == _snapshot.numOfTxs) {
            submissionStatus[_captureTimestamp][msg.sender] |= OPERATOR_SNAPSHOT_MASK;
        }

        if (_isCompleteStatus(_captureTimestamp)) {
            _completeSubmission(_captureTimestamp);
        }
    }

    /*======================================== Helpers ========================================*/
    function _checkValidity(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal view {
        require(block.timestamp >= lastConfirmedTimestamp() + SD, "Cooldown period not passed");

        require(_numOfTxs > 0, "Invalid length");
        require(_index < _numOfTxs, "Invalid index");

        SnapshotTxCountInfo memory snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];
        require(snapshot.count < snapshot.numOfTxs, "Snapshot fully submitted already");
        require(snapshot.numOfTxs == _numOfTxs, "Invalid length");

        bytes4 mask;
        if (_type == OPERATOR_SNAPSHOT) mask = OPERATOR_SNAPSHOT_MASK;
        else if (_type == VAULT_SNAPSHOT) mask = VAULT_SNAPSHOT_MASK;
        else if (_type == SLASH_RESULT) mask = SLASH_RESULT_MASK;

        require(submissionStatus[_captureTimestamp][msg.sender] & mask == 0, "Snapshot fully submitted already");
    }

    function _updateTxCountInfo(uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal {
        SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][msg.sender][_type];

        // increase count by 1
        txCountInfo[_captureTimestamp][msg.sender][_type].count += 1;

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

            operatorSnapshots[_operatorSnapshot.operator][_operatorSnapshot.token][_captureTimestamp] =
                _operatorSnapshot.stake;

            // TODO: emit event for each update?
        }
    }


    function _updateVaultSnapshotInfo(uint256 _captureTimestamp, VaultSnapshot[] memory _vaultSnapshots) internal {
        for (uint256 i = 0; i < _vaultSnapshots.length; i++) {
            VaultSnapshot memory _vaultSnapshot = _vaultSnapshots[i];

            vaultSnapshots[_vaultSnapshot.vault][_vaultSnapshot.token][_captureTimestamp] = _vaultSnapshot.stake;

            // TODO: emit event for each update?
        }
    }

    function _updateSlashResultDataInfo(uint256 _captureTimestamp, SlashResultData[] memory _SlashResultDatas)
        internal
    {
        for (uint256 i = 0; i < _SlashResultDatas.length; i++) {
            SlashResultData memory _slashResultData = _SlashResultDatas[i];

            SlashResultDatas[_slashResultData.jobId][_captureTimestamp] = _slashResultData.slashResult;

            // TODO: emit event for each update?
        }
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        confirmedTimestamps.push(_captureTimestamp);

        // TODO: calculate rewards for the transmitter based on TC
        // TODO: Data transmitter should get TC% of the rewards
        // TODO: "TC" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + SD)"

        // TODO: emit SubmissionCompleted
    }

    /*======================================== Getters ========================================*/
    function lastConfirmedTimestamp() public view returns (uint256) {
        return confirmedTimestamps[confirmedTimestamps.length - 1];
    }
}
