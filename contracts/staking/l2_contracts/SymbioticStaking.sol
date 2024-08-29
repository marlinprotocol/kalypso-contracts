// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract SymbioticStaking {
    // TODO: address Operator => address token => CheckPoints.Trace256 stakeAmount (Question: operators' stake amount is consolidated within same vault?)

    // TODO: set SD
    uint256 SD;

    // TODO: set TC

    // TODO: lastCapturedTimestamp
    uint256 lastCaptureTimestamp;

    //? How to manage Vault lists?

    struct SnapshotTxInfo {
        uint256 count;
        uint256 length;
    }

    struct OperatorSnapshot {
        address operator;
        uint256 stake;
    }

    struct VaultSnapshot {
        address vault;
        uint256 stake;
    }

    mapping(uint256 captureTimestamp => mapping(address account => SnapshotTxInfo snapshot)) submissionInfo;
    
    // TODO: mappings for operator and vault snapshots
    
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
        require(block.timestamp >= lastCaptureTimestamp + SD, "Cooldown period not passed");

        require(_length > 0, "Invalid length");
        
        require(_index < _length, "Invalid index");

        require(submissionInfo[_captureTimestamp][msg.sender].count > 0, "Snapshot fully submitted already");
        submissionInfo[_captureTimestamp][msg.sender].count--;

        require(submissionInfo[_captureTimestamp][msg.sender].length == _length, "Invalid length");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        OperatorSnapshot[] memory operatorSnapshots = abi.decode(_operatorSnapshotData, (OperatorSnapshot[]));
        VaultSnapshot[] memory vaultSnapshots = abi.decode(_VaultSnapshotData, (VaultSnapshot[]));

        // TODO: loop through each snapshots and update the state

        // when the last chunk of the snapshot is received
        if(submissionInfo[_captureTimestamp][msg.sender].count == 0) {
            // TODO: update lastCaptureTimestamp

            // TODO: calculate rewards for the transmitter based on TC
            // TODO: Data transmitter should get TC% of the rewards
            // TODO: "TC" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + SD)"
        }
    }

    function _updateOperatorSnapshot(uint256 _captureTimestamp, OperatorSnapshot[] memory _operatorSnapshots) internal {
        for(uint256 i = 0; i < _operatorSnapshots.length; i++) {
        }
    }

    /*======================================== Getters ========================================*/


}
