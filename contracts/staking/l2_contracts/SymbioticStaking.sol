// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

contract SymbioticStaking is ISymbioticStaking{
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
    
    mapping(address operator => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake))) operatorSnapshots;
    mapping(address vault => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake))) vaultSnapshots;
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
        require(block.timestamp >= lastConfirmedTimestamp() + SD, "Cooldown period not passed");

        require(_numOfTxs > 0, "Invalid length");
        require(_index < _numOfTxs, "Invalid index");
        
        SnapshotTxCountInfo storage snapshot = txCountInfo[_captureTimestamp][msg.sender][OPERATOR_SNAPSHOT];
        
        require(snapshot.count < snapshot.length, "Snapshot fully submitted already");
        require(snapshot.length == _numOfTxs, "Invalid length");

        require(submissionStatus[_captureTimestamp][msg.sender] & OPERATOR_SNAPSHOT_MASK == 0, "Snapshot fully submitted already");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        // main update logic
        OperatorSnapshot[] memory _operatorSnapshots = abi.decode(_operatorSnapshotData, (OperatorSnapshot[]));
        _updateOperatorSnapshotInfo(_captureTimestamp, _operatorSnapshots);
        
        // increase count by 1
        snapshot.count += 1;

        // update length if 0
        if(snapshot.length == 0) {
            snapshot.length = _numOfTxs;
        }

        // when all chunks of OperatorSnapshot are submitted
        if(snapshot.count == snapshot.length) {
            submissionStatus[_captureTimestamp][msg.sender] |= OPERATOR_SNAPSHOT_MASK;
        }

        if(_isCompleteStatus(_captureTimestamp)) {
            _completeSubmission(_captureTimestamp);
            // TODO: emit SubmissionCompleted
        }
    }

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _vaultSnapshotData,
        bytes memory _signature
    ) external {
        require(block.timestamp >= lastConfirmedTimestamp() + SD, "Cooldown period not passed");

        require(_numOfTxs > 0, "Invalid length");
        require(_index < _numOfTxs, "Invalid index");
        
        SnapshotTxCountInfo storage snapshot = txCountInfo[_captureTimestamp][msg.sender][VAULT_SNAPSHOT];
        
        require(snapshot.count < snapshot.length, "Snapshot fully submitted already");
        require(snapshot.length == _numOfTxs, "Invalid length");

        require(submissionStatus[_captureTimestamp][msg.sender] & VAULT_SNAPSHOT_MASK == 0, "Snapshot fully submitted already");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        // main update logic
        VaultSnapshot[] memory _vaultSnapshots = abi.decode(_vaultSnapshotData, (VaultSnapshot[]));
        _updateVaultSnapshotInfo(_captureTimestamp, _vaultSnapshots);
        
        // increase count by 1
        snapshot.count += 1;

        // update length if 0
        if(snapshot.length == 0) {
            snapshot.length = _numOfTxs;
        }

        // when all chunks of OperatorSnapshot are submitted
        if(snapshot.count == snapshot.length) {
            submissionStatus[_captureTimestamp][msg.sender] |= OPERATOR_SNAPSHOT_MASK;
        }

        if(_isCompleteStatus(_captureTimestamp)) {
            _completeSubmission(_captureTimestamp);
            // TODO: emit SubmissionCompleted
        }
    }

    function submitSlashResultData(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _SlashResultDataData,
        bytes memory _signature
    ) external {
        require(block.timestamp >= lastConfirmedTimestamp() + SD, "Cooldown period not passed");

        require(_numOfTxs > 0, "Invalid length");
        require(_index < _numOfTxs, "Invalid index");
        
        SnapshotTxCountInfo storage snapshot = txCountInfo[_captureTimestamp][msg.sender][SLASH_RESULT];
        
        require(snapshot.count < snapshot.length, "Snapshot fully submitted already");
        require(snapshot.length == _numOfTxs, "Invalid length");

        require(submissionStatus[_captureTimestamp][msg.sender] & SLASH_RESULT_MASK == 0, "Snapshot fully submitted already");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image
    }

    /*======================================== Helpers ========================================*/
    function _isCompleteStatus(uint256 _captureTimestamp) internal view returns(bool) {
        return submissionStatus[_captureTimestamp][msg.sender] == COMPLETE_MASK;
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        confirmedTimestamps.push(_captureTimestamp);

        // TODO: calculate rewards for the transmitter based on TC
        // TODO: Data transmitter should get TC% of the rewards
        // TODO: "TC" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + SD)"

    }

    function _updateOperatorSnapshotInfo(uint256 _captureTimestamp, OperatorSnapshot[] memory _operatorSnapshots) internal {
        for(uint256 i = 0; i < _operatorSnapshots.length; i++) {
            OperatorSnapshot memory _operatorSnapshot = _operatorSnapshots[i];

            operatorSnapshots[_operatorSnapshot.operator][_operatorSnapshot.token][_captureTimestamp] = _operatorSnapshot.stake;

            // TODO: emit event for each update?
        }
    }

    function _updateVaultSnapshotInfo(uint256 _captureTimestamp, VaultSnapshot[] memory _vaultSnapshots) internal {
        for(uint256 i = 0; i < _vaultSnapshots.length; i++) {
            VaultSnapshot memory _vaultSnapshot = _vaultSnapshots[i];

            vaultSnapshots[_vaultSnapshot.vault][_vaultSnapshot.token][_captureTimestamp] = _vaultSnapshot.stake;

            // TODO: emit event for each update?
        }
    }

    function _updateSlashResultDataInfo(uint256 _captureTimestamp, SlashResultData[] memory _SlashResultDatas) internal {
        for(uint256 i = 0; i < _SlashResultDatas.length; i++) {
            SlashResultData memory _slashResultData = _SlashResultDatas[i];

            SlashResultDatas[_slashResultData.jobId][_captureTimestamp] = _slashResultData.slashResult;
            
            // TODO: emit event for each update?
        }

    }

    function _verifySignature(bytes memory _data, bytes memory _signature) internal {
        // TODO
    }

    /*======================================== Getters ========================================*/
    function lastConfirmedTimestamp() public view returns(uint256) {
        return confirmedTimestamps[confirmedTimestamps.length - 1];
    }

}
