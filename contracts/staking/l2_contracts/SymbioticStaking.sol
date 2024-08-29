// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract SymbioticStaking {
    // TODO: address Operator => address token => CheckPoints.Trace256 stakeAmount (Question: operators' stake amount is consolidated within same vault?)

    // TODO: set SD
    uint256 SD;

    // TODO: set TC

    // TODO: lastCapturedTimestamp
    uint256 lastCapturedTimestamp;

    //? How to manage Vault lists?

    struct SnapshotInfo {
        uint256 count;
        uint256 length;
    }

    mapping(uint256 captureTimestamp => mapping(address account => SnapshotInfo snapshot)) snapshotInfo;
    
    // Transmitter submits staking data snapshot
    // This should update StakingManger's state
    function submitSnapshot(
        uint256 index,
        uint256 length, // number of total transactions
        uint256 captureTimestamp,
        bytes memory stakeData,
        bytes memory signature
    ) external {
        require(block.timestamp >= lastCapturedTimestamp + SD, "Cooldown period not passed");

        require(length > 0, "Invalid length");
        
        require(index < length, "Invalid index");

        require(snapshotInfo[captureTimestamp][msg.sender].count > 0, "Snapshot fully submitted already");
        snapshotInfo[captureTimestamp][msg.sender].count--;

        require(snapshotInfo[captureTimestamp][msg.sender].length == length, "Invalid length");

        // TODO: Verify the signature
        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        // TODO: Data transmitter should get TC% of the rewards

        // TODO: stakeData should be of the correct format which has key value pairs of operators and stakeDelta (?)

        // TODO: "TC" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + SD)"

        // TODO: Should update the latest complete snapshot information once the last chunk of staking snapshot is received (Updates TC based on the delay)
    }


    /*======================================== Getters ========================================*/


}
