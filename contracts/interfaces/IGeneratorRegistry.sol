// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract IGeneratorRegistry {
    //-------------------------------- Events end --------------------------------//

    event RegisteredGenerator(address indexed generator, uint256 initialCompute);
    event DeregisteredGenerator(address indexed generator);

    event ChangedGeneratorRewardAddress(address indexed generator, address newRewardAddress);

    event JoinedMarketplace(address indexed generator, uint256 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketplace(address indexed generator, uint256 indexed marketId);
    event LeftMarketplace(address indexed generator, uint256 indexed marketId);

    event AddIvsKey(uint256 indexed marketId, address indexed signer);

    event IncreasedCompute(address indexed generator, uint256 compute);
    event RequestComputeDecrease(address indexed generator, uint256 intendedUtilization);
    event DecreaseCompute(address indexed generator, uint256 compute);

    event ComputeLockImposed(address indexed generator, uint256 compute);

    event ComputeLockReleased(address indexed generator, uint256 compute);

    //-------------------------------- Events end --------------------------------//
}
