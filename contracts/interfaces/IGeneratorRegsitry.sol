// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IGeneratorRegistry {
    event RegisteredGenerator(address indexed generator);
    event DeregisteredGenerator(address indexed generator);

    event JoinedMarketPlace(address indexed generator, bytes32 indexed marketId);
    event RequestExitMarketPlace(address indexed generator, bytes32 indexed marketId);
    event LeftMarketplace(address indexed generator, bytes32 indexed marketId);

    event AddedStash(address indexed generator, uint256 amount);

    enum GeneratorState {
        NULL,
        JOINED,
        LOW_STAKE,
        WIP,
        REQUESTED_FOR_EXIT
    }

    struct Generator {
        address rewardAddress;
        uint256 numberOfSupportedMarkets;
        uint256 totalStake;
        bytes generatorData;
    }

    struct GeneratorInfoPerMarket {
        GeneratorState state;
        uint256 proofGenerationCost;
        uint256 proposedTime;
        uint256 maxParallelRequestsSupported;
        uint256 currentActiveRequest;
    }

    function register(address rewardAddress, bytes memory generatorData) external;

    function deregister(address refundAddress) external;

    function stake(address generator, uint256 amount) external;

    function joinMarketPlace(
        bytes32 marketId,
        uint256 proofGenerationCost,
        uint256 proposedTime,
        uint256 maxParallelRequestsSupported
    ) external;

    function leaveMarketPlaces(bytes32[] calldata marketIds) external;

    function leaveMarketPlace(bytes32 marketId) external;

    // return the state of the generator for a given market, and number of parallel calls available
    function getGeneratorState(
        address generatorAddress,
        bytes32 marketId
    ) external view returns (GeneratorState, uint256);

    function slashGenerator(
        address generatorAddress,
        bytes32 marketId,
        address rewardAddress
    ) external returns (uint256);

    function assignGeneratorTask(address generatorAddress, bytes32 marketId) external;

    function completeGeneratorTask(address generatorAddress, bytes32 marketId) external;

    function getGeneratorAssignmentDetails(
        address generatorAddress,
        bytes32 marketId
    ) external view returns (uint256, uint256);

    function getGeneratorRewardDetails(
        address generatorAddress,
        bytes32 marketId
    ) external view returns (address, uint256);
}
