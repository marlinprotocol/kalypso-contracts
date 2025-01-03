// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

contract IProverManager {
    //-------------------------------- Events end --------------------------------//

    event ProverRegistered(address indexed prover, uint256 initialCompute);
    event ProverDeregistered(address indexed prover);

    event ProverRewardAddressChanged(address indexed prover, address indexed newRewardAddress);

    event ProverJoinedMarketplace(address indexed prover, uint256 indexed marketId, uint256 computeAllocation, uint256 commission);
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
