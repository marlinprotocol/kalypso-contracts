// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract SymbioticStaking {
    // TODO: address Operator => address token => CheckPoints.Trace256 stakeAmount (Question: operators' stake amount is consolidated within same vault?)

    // TODO: set SD

    // TODO: set TC

    // TODO: lastCapturedTimestamp

    //? How to manage Vault lists?
    
    // Transmitter submits staking data snapshot
    // This should update StakingManger's state
    function submitSnapshot(
        uint256 txIndex,
        uint256 noOfTxs,
        uint256 captureTimestamp,
        bytes memory stakeData,
        bytes memory signature
    ) external {
        // TODO: check) captureTimestamp >= lastCaptureTimestamp + SD
        
        // TODO: Check) noOfTxs txIndex

        // TODO: Check) noOfTxs should be consistent across all the partial snapshots
        
        // TODO: Data transmitter should get TC% of the rewards

        // TODO: "signature" should be from the enclave key that is verified against the PCR values of the bridge enclave image

        // TODO: stakeData should be of the correct format which has key value pairs of operators and stakeDelta

        // TODO: "TC" should reflect incentivization mechanism based on "captureTimestamp - (lastCaptureTimestamp + SD)"

        // TODO: Should update the latest complete snapshot information once the last chunk of staking snapshot is received (Updates TC based on the delay)
    }

    /*======================================== Getters ========================================*/

    function getLatestStakingAmount() external view returns (address[] memory tokens, uint256[] memory amounts) {
        // TODO
    }

    function getStakingAmountAt(uint256 timestamp) external view returns (uint256 amount) {
        // TODO
    }
    
    function getLatestStakingAmount(address token) external view returns (uint256 amount) {
        // TODO
    }

    function getStakingAmountAt(address token, uint256 timestamp) external view returns (uint256 amount) {
        // TODO
    }

    // returns latest stake amount of an Operator for all tokens
    function getLatestOperatorStakingAmount(address operator) external view returns (address[] memory tokens, uint256[] memory amounts) {
        // TODO
    }
    
    // returns latest stake amount of an Operator for a specific token
    function getLatestOperatorStakingAmount(address operator, address token) external view returns (uint256 amount) {
        // TODO
    }

    // returns stake amounts of an Operator for all tokens at a specific timestamp
    function getOperatorStakingAmountAt(address operator, uint256 timestamp) external view returns (address[] memory tokens, uint256[] memory amounts ) {
        // TODO
    }

    // returns stake amount of an Operator for a specific token at a specific timestamp
    function getOperatorStakingAmountAt(address operator, address token, uint256 timestamp) external view returns (uint256 amount) {
        // TODO
    }
    
    function slashSymbioticVault(address operator, address vault, uint256 captureTimestamp, uint256 amount, address rewardAddress) external {
        // TODO only slashingManager
    }
}
