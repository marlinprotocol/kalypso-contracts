// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IGeneratorRegistry {
    event RegisteredGenerator(address indexed generator, bytes32 indexed marketId);
    event DeregisteredGenerator(address indexed generator, bytes32 indexed marketId);
    event AddExtraStash(address indexed generator, uint256 amount);

    function register(Generator calldata generator, bytes32 marketId) external;

    function deregister(bytes32 marketId) external;

    function getGeneratorDetails(
        address generator,
        bytes32 marketId
    ) external view returns (GeneratorState, uint256, address);

    function slashGenerator(address generator, bytes32 marketId, address rewardAddress) external returns (uint256);

    function completeGeneratorTask(address generator, bytes32 marketId) external;

    function assignGeneratorTask(address generator, bytes32 marketId) external;

    enum GeneratorState {
        NULL,
        JOINED, /// INACTIVE
        LOW_STAKE,
        WIP, /// BUSY
        REQUESTED_FOR_EXIT
    }

    /// TODO: Confirm with V and K
    /// what is to be added to generator data
    /// list of markets which generator wants to participate
    /// generator's time limit promise
    /// generator minimum fee
    /// compute allocation allocation per market
    struct Generator {
        address rewardAddress;
        uint256 amountLocked;
        uint256 minReward;
        bytes generatorData;
    }

    struct GeneratorWithState {
        GeneratorState state;
        Generator generator;
    }
}
