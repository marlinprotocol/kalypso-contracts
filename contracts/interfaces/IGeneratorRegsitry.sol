// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IGeneratorRegistry {
    event RegisteredGenerator(address indexed generator);
    event DeregisteredGenerator(address indexed generator);

    event JoinedMarketPlace(address indexed generator, uint256 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketPlace(address indexed generator, uint256 indexed marketId);
    event LeftMarketplace(address indexed generator, uint256 indexed marketId);

    event AddedStash(address indexed generator, uint256 amount);
    event RemovedStash(address indexed generator, uint256);

    enum GeneratorState {
        NULL,
        JOINED,
        NO_COMPUTE_AVAILABLE,
        WIP,
        REQUESTED_FOR_EXIT
    }

    struct Generator {
        address rewardAddress;
        uint256 totalStake;
        uint256 totalCompute;
        uint256 computeConsumed;
        uint256 stakeLocked;
        uint256 activeMarketPlaces;
        uint256 declaredCompute;
        bytes generatorData;
    }

    struct GeneratorInfoPerMarket {
        GeneratorState state;
        uint256 computeAllocation;
        uint256 proofGenerationCost;
        uint256 proposedTime;
        uint256 activeRequests;
    }

    function register(address rewardAddress, uint256 declaredCompute, bytes memory generatorData) external;

    function deregister(address refundAddress) external;

    function stake(address generator, uint256 amount) external returns (uint256);

    function unstake(address recepient, uint256 amount) external returns (uint256);

    function joinMarketPlace(
        uint256 marketId,
        uint256 computeAllocation,
        uint256 proofGenerationCost,
        uint256 proposedTime
    ) external;

    function leaveMarketPlaces(uint256[] calldata marketIds) external;

    function leaveMarketPlace(uint256 marketId) external;

    function requestForExitMarketPlaces(uint256[] calldata marketIds) external;

    function requestForExitMarketPlace(uint256 marketId) external;

    // return the state of the generator for a given market, and number of idle compute available
    function getGeneratorState(
        address generatorAddress,
        uint256 marketId
    ) external view returns (GeneratorState, uint256);

    // returns total stake of the generator after staking
    function slashGenerator(
        address generatorAddress,
        uint256 marketId,
        uint256 slashingAmount,
        address rewardAddress
    ) external returns (uint256);

    function assignGeneratorTask(address generatorAddress, uint256 marketId, uint256 amountToLock) external;

    function completeGeneratorTask(address generatorAddress, uint256 marketId, uint256 amountToRelease) external;

    function getGeneratorAssignmentDetails(
        address generatorAddress,
        uint256 marketId
    ) external view returns (uint256, uint256);

    function getGeneratorRewardDetails(
        address generatorAddress,
        uint256 marketId
    ) external view returns (address, uint256);
}
