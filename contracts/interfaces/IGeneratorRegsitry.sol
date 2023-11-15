// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IGeneratorRegistry {
    event RegisteredGenerator(address indexed generator);
    event DeregisteredGenerator(address indexed generator);

    event JoinedMarketPlace(address indexed generator, bytes32 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketPlace(address indexed generator, bytes32 indexed marketId);
    event LeftMarketplace(address indexed generator, bytes32 indexed marketId);

    event AddedStake(address indexed generator, uint256 amount);
    event RemovedStake(address indexed generator, uint256);

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
        bytes32 marketId,
        uint256 computeAllocation,
        uint256 proofGenerationCost,
        uint256 proposedTime
    ) external;

    function leaveMarketPlaces(bytes32[] calldata marketIds) external;

    function leaveMarketPlace(bytes32 marketId) external;

    function requestForExitMarketPlaces(bytes32[] calldata marketIds) external;

    function requestForExitMarketPlace(bytes32 marketId) external;

    // return the state of the generator for a given market, and number of idle compute available
    function getGeneratorState(
        address generatorAddress,
        bytes32 marketId
    ) external view returns (GeneratorState, uint256);

    // returns total stake of the generator after staking
    function slashGenerator(
        address generatorAddress,
        bytes32 marketId,
        uint256 slashingAmount,
        address rewardAddress
    ) external returns (uint256);

    function assignGeneratorTask(address generatorAddress, bytes32 marketId, uint256 amountToLock) external;

    function completeGeneratorTask(address generatorAddress, bytes32 marketId, uint256 amountToRelease) external;

    function getGeneratorAssignmentDetails(
        address generatorAddress,
        bytes32 marketId
    ) external view returns (uint256, uint256);

    function getGeneratorRewardDetails(
        address generatorAddress,
        bytes32 marketId
    ) external view returns (address, uint256);
}
