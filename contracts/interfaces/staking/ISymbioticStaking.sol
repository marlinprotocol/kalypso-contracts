// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "./IStakingPool.sol";

interface ISymbioticStaking is IStakingPool {
    // function stakeOf(address _operator, address _token) external view returns (uint256);



    // event OperatorSnapshotSubmitted

    // event VaultSnapshotSubmitted

    // event SlashResultSubmitted

    // event SubmissionCompleted

    /// @notice Returns the captureTimestamp of latest completed snapshot submission
    function lastConfirmedTimestamp() external view returns (uint256);
}
