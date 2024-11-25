// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IProofMarketplace {

    function slashProver(uint256 bidId) external;

    enum SecretType {
        NULL,
        CALLDATA,
        EXTERNAL
    }

    //-------------------------------- Events start --------------------------------//

    event BidCreated(uint256 indexed bidId, bool indexed hasPrivateInputs, bytes secret_data, bytes acl);
    event TaskCreated(uint256 indexed bidId, address indexed prover, bytes new_acl);
    event ProofCreated(uint256 indexed bidId, bytes proof);
    event ProofNotGenerated(uint256 indexed bidId);

    event InvalidInputsDetected(uint256 indexed bidId);

    event MarketplaceCreated(uint256 indexed marketId);

    event BidCancelled(uint256 indexed bidId);

    event UpdateCostPerBytes(SecretType indexed secretType, uint256 costPerInputBytes);
    event UpdateMinProvingTime(SecretType indexed secretType, uint256 newProvingTime);
    event AddExtraProverImage(uint256 indexed marketId, bytes32 indexed imageId);
    event AddExtraIVSImage(uint256 indexed marketId, bytes32 indexed imageId);
    event RemoveExtraProverImage(uint256 indexed marketId, bytes32 indexed imageId);
    event RemoveExtraIVSImage(uint256 indexed marketId, bytes32 indexed imageId);

    event ProverRewardShareSet(address indexed prover, uint256 rewardShare);
    event ProverFeeRewardAdded(address indexed prover, uint256 feeRewardAmount);

    event TransmitterFeeRewardAdded(address indexed transmitter, uint256 feeRewardAmount);

    //-------------------------------- Events end --------------------------------//
}
