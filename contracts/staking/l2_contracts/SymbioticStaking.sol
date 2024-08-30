// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

contract SymbioticStaking is ISymbioticStaking{
    // TODO: address Operator => address token => CheckPoints.Trace256 stakeAmount (Question: operators' stake amount is consolidated within same vault?)

    // TODO: set SD
    uint256 SD;

    // TODO: set TC

    //? How to manage Vault lists?


    mapping(uint256 captureTimestamp => mapping(address account => SnapshotTxInfo snapshot)) submissionInfo; // to check if all partial txs are received
    
    mapping(address operator => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake))) operatorSnapshot;
    mapping(address vault => mapping(address token => mapping(uint256 captureTimestamp => uint256 stake))) vaultSnapshot;
    mapping(uint256 captureTimestamp => mapping(uint256 jobId => SlashResult slashREsult)) slashResults; // TODO: need to check slash timestamp?

    uint256[] public confirmedTimestamps;
    
    // Transmitter submits staking data snapshot
    // This should update StakingManger's state
    function submitSnapshot(
        uint256 _index,
        uint256 _length, // number of total transactions
        uint256 _captureTimestamp,
        bytes memory _operatorSnapshotData,
        bytes memory _VaultSnapshotData,
        bytes memory _signature
    ) external {
        require(block.timestamp >= lastCaptureTimestamp() + SD, "Cooldown period not passed");

        require(_length > 0, "Invalid length");
        
        require(_index < _length, "Invalid index");

        require(submissionInfo[_captureTimestamp][msg.sender].count > 0, "Snapshot fully submitted already");
        submissionInfo[_captureTimestamp][msg.sender].count--;

        require(submissionInfo[_captureTimestamp][msg.sender].length == _length, "Invalid length");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        OperatorSnapshot[] memory operatorSnapshots = abi.decode(_operatorSnapshotData, (OperatorSnapshot[]));
        _updateOperatorSnapshotInfo(_captureTimestamp, operatorSnapshots);
        
        VaultSnapshot[] memory vaultSnapshots = abi.decode(_VaultSnapshotData, (VaultSnapshot[]));
        _updateVaultSnapshotInfo(_captureTimestamp, vaultSnapshots);

        // when the last chunk of the snapshot is received
        if(submissionInfo[_captureTimestamp][msg.sender].count == 0) {
            // TODO: update lastCaptureTimestamp


            // TODO: calculate rewards for the transmitter based on TC
            // TODO: Data transmitter should get TC% of the rewards
            // TODO: "TC" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + SD)"
        }
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
