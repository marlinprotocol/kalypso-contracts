// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract IProverRegistry {
    //-------------------------------- Events end --------------------------------//

    event RegisteredProver(address indexed prover, uint256 initialCompute);
    event DeregisteredProver(address indexed prover);

    event ChangedProverRewardAddress(address indexed prover, address newRewardAddress);

    event JoinedMarketplace(address indexed prover, uint256 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketplace(address indexed prover, uint256 indexed marketId);
    event LeftMarketplace(address indexed prover, uint256 indexed marketId);

    event AddIvsKey(uint256 indexed marketId, address indexed signer);

    event IncreasedCompute(address indexed prover, uint256 compute);
    event RequestComputeDecrease(address indexed prover, uint256 intendedUtilization);
    event DecreaseCompute(address indexed prover, uint256 compute);

    event ComputeLocked(address indexed prover, uint256 compute);
    event ComputeReleased(address indexed prover, uint256 compute);

    //-------------------------------- Events end --------------------------------//
}
