// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

contract SymbioticStaking is ISymbioticStaking{
    // TODO: address Operator => address token => CheckPoints.Trace256 stakeAmount (Question: operators' stake amount is consolidated within same vault?)

    // TODO: set SD
    uint256 SD;

    // TODO: set TC

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
    
    mapping(address operator => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake))) operatorSnapshot;
    mapping(address vault => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake))) vaultSnapshot;
    mapping(uint256 captureTimestamp => mapping(uint256 jobId => SlashResult slashResult)) slashResults; // TODO: need to check actual slashing timestamp?

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
        require(block.timestamp >= lastCaptureTimestamp() + SD, "Cooldown period not passed");

        require(_numOfTxs > 0, "Invalid length");

        require(_index < _numOfTxs, "Invalid index");

        
        SnapshotTxCountInfo storage snapshot = txCountInfo[_captureTimestamp][msg.sender][OPERATOR_SNAPSHOT];
        require(snapshot.count < snapshot.length, "Snapshot fully submitted already");
        require(snapshot.length == _numOfTxs, "Invalid length");
        require(submissionStatus[_captureTimestamp][msg.sender] & OPERATOR_SNAPSHOT_MASK == 0, "Snapshot fully submitted already");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        // main update logic
        OperatorSnapshot[] memory operatorSnapshots = abi.decode(_operatorSnapshotData, (OperatorSnapshot[]));
        _updateOperatorSnapshotInfo(_captureTimestamp, operatorSnapshots);
        
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
        }

    }

    function submitVaultSnapshot() external {
        // TODO
    }

    function submitSlashResult() external {
        // TODO
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
            // TODO
        }
    }

    function _updateVaultSnapshotInfo(uint256 _captureTimestamp, VaultSnapshot[] memory _vaultSnapshots) internal {
        for(uint256 i = 0; i < _vaultSnapshots.length; i++) {
            // TODO
        }
    }

    function _updateSlashResultInfo(uint256 _captureTimestamp, address[] memory _operators, uint256[] memory _slashAmounts) internal {
        for(uint256 i = 0; i < _operators.length; i++) {
            // TODO
        }
    }

    /*======================================== Getters ========================================*/
    function lastCaptureTimestamp() public view returns(uint256) {
        return confirmedTimestamps[confirmedTimestamps.length - 1];
    }

}
