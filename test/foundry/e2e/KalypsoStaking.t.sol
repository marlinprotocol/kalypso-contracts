// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

/* contracts */
import {JobManager} from "../../../contracts/staking/l2_contracts/JobManager.sol";
import {StakingManager} from "../../../contracts/staking/l2_contracts/StakingManager.sol";
import {SymbioticStaking} from "../../../contracts/staking/l2_contracts/SymbioticStaking.sol";

/* interfaces */
import {IJobManager} from "../../../contracts/interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../../contracts/interfaces/staking/IStakingManager.sol";
import {INativeStaking} from "../../../contracts/interfaces/staking/INativeStaking.sol";
import {ISymbioticStaking} from "../../../contracts/interfaces/staking/ISymbioticStaking.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* libraries */
import {Struct} from "../../../contracts/lib/staking/Struct.sol";

contract KalypsoStakingTest is Test, TestSetup {

    uint256 constant OPERATORA_SELF_STAKE_AMOUNT = 1000 ether;
    uint256 constant OPERATORB_SELF_STAKE_AMOUNT = 2000 ether;

    function setUp() public {
        _setupAddr();
        _setupContracts();
        _fund_tokens();

        /*-------------------- Config --------------------*/
        /* JobManager */
        _setJobManagerConfig();

        /* StakingManager */
        _setStakingManagerConfig();

        /* NativeStaking */
        _setNativeStakingConfig();
        
        /* SymbioticStaking */
        _setSymbioticStakingConfig();
        
    }

    /// @notice test full lifecycle of kalypso staking
    function test_kalypso_staking() public {
        /*-------------------- Native Staking Stake --------------------*/

        _operator_self_stake();

        // _symbiotic_staking_snapshot_transmission();
    }

    function _operator_self_stake() internal {
        // Operator A self stakes into 1_000 POND
        vm.startPrank(operatorA);
        {
            IERC20(weth).approve(nativeStaking, type(uint256).max);
            IERC20(pond).approve(nativeStaking, type(uint256).max);

            // weth is not supported in NativeStaking
            vm.expectRevert("Token not supported");
            INativeStaking(nativeStaking).stake(operatorA, weth, OPERATORA_SELF_STAKE_AMOUNT);

            // only operator can stake
            vm.expectRevert("Only operator can stake");
            INativeStaking(nativeStaking).stake(operatorB, pond, OPERATORA_SELF_STAKE_AMOUNT);
            
            // stake 1000 POND
            INativeStaking(nativeStaking).stake(operatorA, pond, OPERATORA_SELF_STAKE_AMOUNT);
        }
        vm.stopPrank();
        assertEq(INativeStaking(nativeStaking).getOperatorStakeAmount(operatorA, pond), OPERATORA_SELF_STAKE_AMOUNT);
        assertEq(INativeStaking(nativeStaking).getOperatorActiveStakeAmount(operatorA, pond), OPERATORA_SELF_STAKE_AMOUNT);

        vm.startPrank(operatorB);
        {
            IERC20(pond).approve(nativeStaking, type(uint256).max);
            
            INativeStaking(nativeStaking).stake(operatorB, pond, OPERATORB_SELF_STAKE_AMOUNT);

        }
        vm.stopPrank();
        assertEq(INativeStaking(nativeStaking).getOperatorStakeAmount(operatorB, pond), OPERATORB_SELF_STAKE_AMOUNT);
        assertEq(INativeStaking(nativeStaking).getOperatorActiveStakeAmount(operatorB, pond), OPERATORB_SELF_STAKE_AMOUNT);
    }

    function _symbiotic_staking_snapshot_submission() internal {

    }
}
