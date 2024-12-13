// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

contract IProverRegistry {
    //-------------------------------- Events end --------------------------------//

    event ProverRegistered(address indexed prover, uint256 initialCompute);
    event ProverDeregistered(address indexed prover);

    event ProverRewardAddressChanged(address indexed prover, address newRewardAddress);

    event ProverJoinedMarketplace(address indexed prover, uint256 indexed marketId, uint256 computeAllocation);
    event ProverRequestedMarketplaceExit(address indexed prover, uint256 indexed marketId);
    event ProverLeftMarketplace(address indexed prover, uint256 indexed marketId);

    event IvKeyAdded(uint256 indexed marketId, address indexed signer);

    event ComputeIncreased(address indexed prover, uint256 compute);
    event ComputeDecreaseRequested(address indexed prover, uint256 intendedUtilization);
    event ComputeDecreased(address indexed prover, uint256 compute);

    event ComputeLocked(address indexed prover, uint256 compute);
    event ComputeReleased(address indexed prover, uint256 compute);

    //-------------------------------- Events end --------------------------------//
}
