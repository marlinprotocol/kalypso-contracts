// SPDX-License-Identifier: MIT

import {Struct} from "../../lib/staking/Struct.sol";

pragma solidity ^0.8.26;

interface ISymbioticStakingReward {
    function updateFeeReward(address _stakeToken, address _operator, uint256 _amount) external;

    function updateInflationReward(address _operator, uint256 _rewardAmount) external;

    function onSnapshotSubmission(Struct.VaultSnapshot[] calldata _vaultSnapshots) external;
}