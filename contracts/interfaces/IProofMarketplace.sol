// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IProofMarketplace {

    function slashGenerator(uint256 askId) external;

    enum SecretType {
        NULL,
        CALLDATA,
        EXTERNAL
    }

    //-------------------------------- Events start --------------------------------//

    event AskCreated(uint256 indexed askId, bool indexed hasPrivateInputs, bytes secret_data, bytes acl);
    event TaskCreated(uint256 indexed askId, address indexed generator, bytes new_acl);
    // TODO: add ask ID also
    event ProofCreated(uint256 indexed askId, bytes proof);
    event ProofNotGenerated(uint256 indexed askId);

    event InvalidInputsDetected(uint256 indexed askId);

    event MarketplaceCreated(uint256 indexed marketId);

    event AskCancelled(uint256 indexed askId);

    event UpdateCostPerBytes(SecretType indexed secretType, uint256 costPerInputBytes);
    event UpdateMinProvingTime(SecretType indexed secretType, uint256 newProvingTime);
    event AddExtraProverImage(uint256 indexed marketId, bytes32 indexed imageId);
    event AddExtraIVSImage(uint256 indexed marketId, bytes32 indexed imageId);
    event RemoveExtraProverImage(uint256 indexed marketId, bytes32 indexed imageId);
    event RemoveExtraIVSImage(uint256 indexed marketId, bytes32 indexed imageId);

    event OperatorRewardShareSet(address indexed operator, uint256 rewardShare);
    event OperatorFeeRewardAdded(address indexed operator, uint256 feeRewardAmount);

    event TransmitterFeeRewardAdded(address indexed transmitter, uint256 feeRewardAmount);

    //-------------------------------- Events end --------------------------------//
}
