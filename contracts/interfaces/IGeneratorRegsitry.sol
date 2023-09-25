// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IGeneratorRegistry {
    event RegisteredGenerator(address indexed generator, bytes32 indexed marketId);
    event DeregisteredGenerator(address indexed generator, bytes32 indexed marketId);
    event AddExtraStash(address indexed generator, bytes32 indexed marketId, uint256 amount);

    function register(Generator calldata generator, bytes32 marketId) external;

    function deregister(bytes32 marketId) external;

    function getGeneratorDetails(
        address generator,
        bytes32 marketId
    ) external view returns (GeneratorState, uint256, address, uint256);

    function slashGenerator(address generator, bytes32 marketId, address rewardAddress) external returns (uint256);

    function completeGeneratorTask(address generator, bytes32 marketId) external;

    function assignGeneratorTask(address generator, bytes32 marketId) external;

    function getGeneratorRewardDetails(address _generator, bytes32 marketId) external view returns (address, uint256);

    function getGeneratorAssignmentDetails(
        address _generator,
        bytes32 marketId
    ) external view returns (uint256, uint256);

    enum GeneratorState {
        NULL,
        JOINED, /// INACTIVE
        LOW_STAKE,
        WIP, /// BUSY
        REQUESTED_FOR_EXIT
    }

    struct Generator {
        // Address on which generator will receive reward
        address rewardAddress;
        // Total Amount Staked
        uint256 amountLocked;
        // number of tokens charged for generating a proof
        uint256 proofGenerationCost;
        // proposed time in which generator is ready to generator proofs for everyone (in blocks)
        uint256 proposedTime;
        // generator meta data
        bytes generatorData;
    }

    struct GeneratorWithState {
        GeneratorState state;
        Generator generator;
    }
}
