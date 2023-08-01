// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IGeneratorRegistry {
    event RegisteredGenerator(address indexed generator, bytes32 indexed marketId);
    event DeregisteredGenerator(address indexed generator, bytes32 indexed marketId);
    event AddExtraStash(address indexed generator, uint256 amount);

    function register(Generator calldata generator, bytes32 marketId) external;

    function deregister(bytes32 marketId) external;

    function getGeneratorState(address generator, bytes32 marketId) external view returns (GeneratorState);

    function getGeneratorRewardAddress(address generator, bytes32 marketId) external view returns (address);

    function slashGenerator(address generator, bytes32 marketId, address rewardAddress) external returns (uint256);

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
        bytes generatorData;
        uint256 amountLocked;
    }

    struct GeneratorWithState {
        GeneratorState state;
        Generator generator;
    }
}
