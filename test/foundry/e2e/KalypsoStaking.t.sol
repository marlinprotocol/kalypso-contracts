// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

/* contracts */
import {JobManager} from "../../../contracts/staking/l2_contracts/JobManager.sol";
import {StakingManager} from "../../../contracts/staking/l2_contracts/StakingManager.sol";
import {SymbioticStaking} from "../../../contracts/staking/l2_contracts/SymbioticStaking.sol";
import {SymbioticStakingReward} from "../../../contracts/staking/l2_contracts/SymbioticStakingReward.sol";

/* interfaces */
import {IJobManager} from "../../../contracts/interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../../contracts/interfaces/staking/IStakingManager.sol";
import {INativeStaking} from "../../../contracts/interfaces/staking/INativeStaking.sol";
import {ISymbioticStaking} from "../../../contracts/interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../../contracts/interfaces/staking/ISymbioticStakingReward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* libraries */
import {Struct} from "../../../contracts/lib/staking/Struct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract KalypsoStakingTest is Test, TestSetup {
    uint256 constant OPERATORA_SELF_STAKE_AMOUNT = 1000 ether;
    uint256 constant OPERATORB_SELF_STAKE_AMOUNT = 2000 ether;
    uint256 constant OPERATORC_SELF_STAKE_AMOUNT = 1500 ether;

    uint256 operatorAFeeReward;
    uint256 operatorBFeeReward;
    uint256 operatorCFeeReward;

    uint256 transmitterAFeeReward;
    uint256 transmitterBFeeReward;
    uint256 transmitterCFeeReward;

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
        /* current timestamp: 50_001 */
        vm.warp(block.timestamp + 50_000);
        assertEq(block.timestamp, 50_001);

        // operators self stake
        _operator_self_stake();

        /*============================== Snapshot 1 ==============================*/
        // Snapshot 1 submitted
        _symbiotic_staking_snapshot_submission_1();

        /* jobId1 created (jobRequesterA -> OperatorA, 1 USDC) */
        _create_job_1();

        // proof submitted
        vm.warp(block.timestamp + 10 minutes);
        _submit_proof_job_1();

        // symbioticVaultA claims fee reward
        _vault_claims_reward_from_job_1();

        /* jobId2 created (jobRequesterB -> OperatorB, 0.5 USDC) */
        vm.warp(block.timestamp + SUBMISSION_COOLDOWN); // POND locked
        _create_job_2();

        // jobId2 completed
        _submit_proof_job_2();

        /*============================== Snapshot 2 ==============================*/
        // Snapshot 2 submitted
        // here, the reward for jobId2 should be accrued for the symbioticVaultB (for staking 3000 POND to OperatorB)
        vm.warp(block.timestamp + SUBMISSION_COOLDOWN);
        _symbiotic_staking_snapshot_submission_2();

        _create_job_3();

        _submit_proof_job_3();

        _vaultA_claims_reward_from_job_3();

        /*============================== Snapshot 3 ==============================*/
        // Snapshot 3 submitted
        vm.warp(block.timestamp + SUBMISSION_COOLDOWN);
        _symbiotic_staking_snapshot_submission_3();

        _create_job_4();

        _submit_proof_job_4();

        _vaultA_claims_reward_from_job_4();

        _vaultC_claims_reward_from_job_4();

        _vaultD_claims_reward_from_job_4();

        _operators_and_transmitters_claim_fee_reward();
    }

    /*===================================================== internal ====================================================*/

    function _operator_self_stake() internal {
        // Operator A self stakes 1000 WETH and 1000 POND
        vm.startPrank(operatorA);
        {
            IERC20(weth).approve(nativeStaking, type(uint256).max);
            IERC20(pond).approve(nativeStaking, type(uint256).max);

            // weth is not supported in NativeStaking
            vm.expectRevert("Token not supported");
            INativeStaking(nativeStaking).stake(weth, operatorA, OPERATORA_SELF_STAKE_AMOUNT);

            // only operator can stake
            vm.expectRevert("Only operator can stake");
            INativeStaking(nativeStaking).stake(pond, operatorB, OPERATORA_SELF_STAKE_AMOUNT);

            // stake 1000 POND
            INativeStaking(nativeStaking).stake(pond, operatorA, OPERATORA_SELF_STAKE_AMOUNT);
        }
        vm.stopPrank();
        assertEq(
            INativeStaking(nativeStaking).getOperatorStakeAmount(pond, operatorA),
            OPERATORA_SELF_STAKE_AMOUNT,
            "_operator_self_stake: OperatorA stake amount mismatch"
        );
        assertEq(
            INativeStaking(nativeStaking).getOperatorActiveStakeAmount(pond, operatorA),
            OPERATORA_SELF_STAKE_AMOUNT,
            "_operator_self_stake: OperatorA active stake amount mismatch"
        );

        // OperatorB self stakes 2000 POND
        vm.startPrank(operatorB);
        {
            IERC20(pond).approve(nativeStaking, type(uint256).max);

            INativeStaking(nativeStaking).stake(pond, operatorB, OPERATORB_SELF_STAKE_AMOUNT);
        }
        vm.stopPrank();
        assertEq(
            INativeStaking(nativeStaking).getOperatorStakeAmount(pond, operatorB),
            OPERATORB_SELF_STAKE_AMOUNT,
            "_operator_self_stake: OperatorB stake amount mismatch"
        );
        assertEq(
            INativeStaking(nativeStaking).getOperatorActiveStakeAmount(pond, operatorB),
            OPERATORB_SELF_STAKE_AMOUNT,
            "_operator_self_stake: OperatorB active stake amount mismatch"
        );

        vm.startPrank(operatorC);
        {
            IERC20(pond).approve(nativeStaking, type(uint256).max);
            INativeStaking(nativeStaking).stake(pond, operatorC, OPERATORC_SELF_STAKE_AMOUNT);
        }
        vm.stopPrank();
    }

    function _symbiotic_staking_snapshot_submission_1() internal {
        /*  
            < TransmitterA Transmits >
            OperatorA: opted-into symbioticVaultA (weth) - 1000 weth, 
            OperatorB: opted-into symbioticVaultA (weth) - 2000 weth, symbioticVaultB (pond) - 3000 pond
        */

        // Partial Tx 1
        Struct.VaultSnapshot[] memory _vaultSnapshots1 = new Struct.VaultSnapshot[](1);
        /* Vault A */
        // VaultA(1000 WETH) -> OperatorA
        _vaultSnapshots1[0].operator = operatorA;
        _vaultSnapshots1[0].vault = symbioticVaultA;
        _vaultSnapshots1[0].stakeToken = weth;
        _vaultSnapshots1[0].stakeAmount = 1000 ether;

        // Partial Tx 2
        Struct.VaultSnapshot[] memory _vaultSnapshots2 = new Struct.VaultSnapshot[](2);

        /* Vault B */

        // VaultA(2000 weth) -> OperatorB
        _vaultSnapshots2[0].operator = operatorB;
        _vaultSnapshots2[0].vault = symbioticVaultA;
        _vaultSnapshots2[0].stakeToken = weth;
        _vaultSnapshots2[0].stakeAmount = 2000 ether;

        // VaultB(3000 POND) -> OperatorB
        _vaultSnapshots2[1].operator = operatorB;
        _vaultSnapshots2[1].vault = symbioticVaultB;
        _vaultSnapshots2[1].stakeToken = pond;
        _vaultSnapshots2[1].stakeAmount = 3000 ether;

        /* Snapshot Submission */
        vm.startPrank(transmitterA);
        {
            vm.expectRevert("Invalid index");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                3, 2, block.timestamp - 5, abi.encode(_vaultSnapshots1), ""
            );

            vm.expectRevert("Invalid index");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                2, 2, block.timestamp - 5, abi.encode(_vaultSnapshots1), ""
            );

            vm.expectRevert("Invalid timestamp");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                1, 2, block.timestamp + 1, abi.encode(_vaultSnapshots1), ""
            );

            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                0, 2, block.timestamp - 5, abi.encode(_vaultSnapshots1), ""
            );
        }
        vm.stopPrank();
        (uint256 _idxToSubmit, uint256 _numOfTxs) =
            ISymbioticStaking(symbioticStaking).txCountInfo(block.timestamp - 5, keccak256("STAKE_SNAPSHOT_TYPE"));

        assertEq(_idxToSubmit, 1, "_symbiotic_staking_snapshot_submission_1: Tx count info mismatch");
        assertEq(_numOfTxs, 2, "_symbiotic_staking_snapshot_submission_1: Tx count info mismatch");
        assertEq(
            ISymbioticStaking(symbioticStaking).getSubmissionStatus(block.timestamp - 5, transmitterA),
            0x0,
            "_symbiotic_staking_snapshot_submission_1: Submission status mismatch"
        );

        vm.startPrank(transmitterA);
        {
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                1, 2, block.timestamp - 5, abi.encode(_vaultSnapshots2), ""
            );
        }
        vm.stopPrank();

        assertEq(
            ISymbioticStaking(symbioticStaking).registeredTransmitters(block.timestamp - 5),
            transmitterA,
            "_symbiotic_staking_snapshot_submission_1: Registered transmitter mismatch"
        );

        (_idxToSubmit, _numOfTxs) =
            ISymbioticStaking(symbioticStaking).txCountInfo(block.timestamp - 5, keccak256("STAKE_SNAPSHOT_TYPE"));
        assertEq(_idxToSubmit, 2);
        assertEq(_numOfTxs, 2);
        assertEq(
            ISymbioticStaking(symbioticStaking).getSubmissionStatus(block.timestamp - 5, transmitterA),
            0x0000000000000000000000000000000000000000000000000000000000000001,
            "Submission status mismatch"
        );

        /* Slash Result Submission */
        vm.prank(transmitterA);
        ISymbioticStaking(symbioticStaking).submitSlashResult(0, 1, block.timestamp - 5, abi.encode(""), "");
    }

    function _create_job_1() internal {
        // requesterA creates a job
        vm.startPrank(jobRequesterA);
        {
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            uint256 jobmanagerBalanceBefore = IERC20(feeToken).balanceOf(jobManager);

            vm.expectRevert("No stakeToken available to lock");
            IJobManager(jobManager).createJob(1, jobRequesterA, operatorC, 1 * USDC_DECIMALS); // should revert as operatorC didn't stake any token to NativeStaking

            // pay 1 usdc as fee
            IJobManager(jobManager).createJob(1, jobRequesterA, operatorA, 1 * USDC_DECIMALS);
            assertEq(IERC20(feeToken).balanceOf(jobManager) - jobmanagerBalanceBefore, 1 * USDC_DECIMALS);
        }
        vm.stopPrank();
    }

    function _submit_proof_job_1() internal {
        // locked stake token for jobId 1
        uint256 jobId = 1;
        (address lockedStakeToken,) = ISymbioticStaking(symbioticStaking).lockInfo(jobId);
        assertEq(lockedStakeToken, weth, "_submit_proof_job_1: Locked stake token mismatch");

        // OperatorA and TransmitterA fee reward before
        uint256 operatorAFeeRewardBefore = IJobManager(jobManager).operatorFeeRewards(operatorA);
        uint256 transmitterAFeeRewardBefore = IJobManager(jobManager).transmitterFeeRewards(transmitterA);

        // rewardPerTokenStored before for operatorA
        uint256 rewardPerTokenStoredBefore =
            ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(lockedStakeToken, feeToken, operatorA);
        assertEq(rewardPerTokenStoredBefore, 0, "_submit_proof_job_1: RewardPerTokenStored mismatch");

        // staked weth amount for operatorA
        uint256 stakedWethAmount = ISymbioticStaking(symbioticStaking).getOperatorStakeAmount(weth, operatorA);
        assertEq(stakedWethAmount, 1000 ether, "_submit_proof_job_1: Staked weth amount mismatch");

        // expected rewardPerTokenStored after job completion
        uint256 rewardPerTokenIncreased = Math.mulDiv(1 * USDC_DECIMALS * 70 / 100 * 80 / 100, 1e18, stakedWethAmount);

        vm.startPrank(operatorA);
        {
            // reverts if submitted after deadline
            vm.warp(block.timestamp + 12 hours);
            vm.expectRevert("Job Expired");
            IJobManager(jobManager).submitProof(1, "");

            vm.warp(block.timestamp - 12 hours);
            IJobManager(jobManager).submitProof(1, "");
        }
        vm.stopPrank();

        /* 
            <expected fee reward>
            fee paid: 1 usdc
            
            operator reward share: 30%
            => 1 * 0.3 = 0.3 usdc

            transmitter comission rate: 20%
            => 1 * 0.7 * 0.2 = 0.14 usdc
         */

        // OperatorA and TransmitterA fee reward after
        uint256 operatorAFeeRewardAfter = IJobManager(jobManager).operatorFeeRewards(operatorA);
        uint256 transmitterAFeeRewardAfter = IJobManager(jobManager).transmitterFeeRewards(transmitterA);

        assertEq(operatorAFeeRewardAfter - operatorAFeeRewardBefore, 3 * USDC_DECIMALS / 10, "OperatorA fee reward mismatch");
        operatorAFeeReward += operatorAFeeRewardAfter - operatorAFeeRewardBefore;

        assertEq(transmitterAFeeRewardAfter - transmitterAFeeRewardBefore, 14 * USDC_DECIMALS / 100, "TransmitterA fee reward mismatch");
        transmitterAFeeReward += transmitterAFeeRewardAfter - transmitterAFeeRewardBefore;

        // rewardPerTokenStored after for operatorA
        uint256 rewardPerTokenStoredAfter =
            ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(lockedStakeToken, feeToken, operatorA);
        assertEq(
            rewardPerTokenStoredAfter,
            rewardPerTokenStoredBefore + rewardPerTokenIncreased,
            "_submit_proof_job_1: RewardPerTokenStored mismatch"
        );
    }

    function _vault_claims_reward_from_job_1() internal {
        /* 
            Vault A claim fee reward
         */
        vm.startPrank(symbioticVaultA);
        ISymbioticStakingReward(symbioticStakingReward).claimReward(operatorA);
        vm.stopPrank();

        /* 
            current status of staking:
            operatorA: opted-into symbioticVaultA (weth) - 1000 weth, 
            operatorB: opted-into symbioticVaultA (weth) - 2000 weth, symbioticVaultB (pond) - 3000 pond

            operatorA has 100% reward share

            1 USDC * 0.7(after operatorA commision 30%) * 0.8(after transmitter commision 20%) = 0.56 USDC
         */

        assertEq(
            IERC20(feeToken).balanceOf(symbioticVaultA), 56 * USDC_DECIMALS / 100, "SymbioticVaultA fee reward mismatch"
        );
    }

    // when multiple stakeTokens are staked to OperatorB
    function _create_job_2() internal {
        // requesterB creates a job
        vm.startPrank(jobRequesterB);
        {
            // approve feeToken for jobManager
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            uint256 jobmanagerBalanceBefore = IERC20(feeToken).balanceOf(jobManager);

            // requesterB pays 0.5 usdc as fee
            IJobManager(jobManager).createJob(2, jobRequesterA, operatorB, 5 * USDC_DECIMALS / 10);
            assertEq(IERC20(feeToken).balanceOf(jobManager) - jobmanagerBalanceBefore, 5 * USDC_DECIMALS / 10);
        }
        vm.stopPrank();
    }

    function _submit_proof_job_2() internal {
        uint256 jobId = 2;
        (address lockedStakeToken,) = ISymbioticStaking(symbioticStaking).lockInfo(jobId);

        // OperatorB and TransmitterA fee reward before
        uint256 operatorBFeeRewardBefore = IJobManager(jobManager).operatorFeeRewards(operatorB);
        uint256 transmitterAFeeRewardBefore = IJobManager(jobManager).transmitterFeeRewards(transmitterA);

        // rewardPerTokenStored before for operatorA
        uint256 rewardPerTokenStoredBefore =
            ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(lockedStakeToken, feeToken, operatorB);
        assertEq(rewardPerTokenStoredBefore, 0, "_submit_proof_job_2: RewardPerTokenStored mismatch");

        // staked weth amount for operatorA
        uint256 stakeTokenAmount =
            ISymbioticStaking(symbioticStaking).getOperatorStakeAmount(lockedStakeToken, operatorB);

        // expected rewardPerTokenStored after job completion
        uint256 rewardPerTokenToIncrease =
            Math.mulDiv(1 * USDC_DECIMALS * (50 * 50 * 80) / (100 * 100 * 100), 1e18, stakeTokenAmount);

        vm.startPrank(operatorB);
        {
            IJobManager(jobManager).submitProof(2, "");
        }
        vm.stopPrank();

        // OperatorB and TransmitterA fee reward after
        uint256 operatorBFeeRewardAfter = IJobManager(jobManager).operatorFeeRewards(operatorB);
        uint256 transmitterAFeeRewardAfter = IJobManager(jobManager).transmitterFeeRewards(transmitterA);

        /* 
            <expected fee reward>
            fee paid: 0.5 usdc
            
            operator reward share: 50%
            => 0.5 * 0.5 = 0.25 usdc

            transmitter comission rate: 20%
            => 0.5 * 0.5 * 0.2 = 0.05 usdc

            reward distributed
            => 0.5 * 0.5 * 0.8 = 0.2 usdc
         */

        assertEq(operatorBFeeRewardAfter - operatorBFeeRewardBefore, 25 * USDC_DECIMALS / 100, "_submit_proof_job_2: OperatorB fee reward mismatch");
        operatorBFeeReward += operatorBFeeRewardAfter - operatorBFeeRewardBefore;

        assertEq(transmitterAFeeRewardAfter - transmitterAFeeRewardBefore, 5 * USDC_DECIMALS / 100, "_submit_proof_job_2: TransmitterA fee reward mismatch");
        transmitterAFeeReward += transmitterAFeeRewardAfter - transmitterAFeeRewardBefore;

        // rewardPerTokenStored after for operatorB
        uint256 rewardPerTokenStoredAfter =
            ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(lockedStakeToken, feeToken, operatorB);

        assertEq(
            rewardPerTokenStoredAfter,
            rewardPerTokenStoredBefore + rewardPerTokenToIncrease,
            "_submit_proof_job_2: RewardPerTokenStored mismatch"
        );
    }

    // Reward from Job2 not claimed by vaultB
    function _symbiotic_staking_snapshot_submission_2() internal {
        uint256 vaultBRewardPerTokenPaidBefore = ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenPaid(
            pond, feeToken, symbioticVaultB, operatorB
        );

        // same snapshot as in _symbiotic_staking_snapshot_submission_1
        Struct.VaultSnapshot[] memory originalSnapshotData = new Struct.VaultSnapshot[](3);
        // VaultA -> OperatorA (1000 weth)
        originalSnapshotData[0].operator = operatorA;
        originalSnapshotData[0].vault = symbioticVaultA;
        originalSnapshotData[0].stakeToken = weth;
        originalSnapshotData[0].stakeAmount = 1000 ether;

        // VaultA -> OperatorB (2000 weth)
        originalSnapshotData[1].operator = operatorB;
        originalSnapshotData[1].vault = symbioticVaultA;
        originalSnapshotData[1].stakeToken = weth;
        originalSnapshotData[1].stakeAmount = 2000 ether;

        // VaultB -> OperatorB (3000 pond)
        originalSnapshotData[2].operator = operatorB;
        originalSnapshotData[2].vault = symbioticVaultB;
        originalSnapshotData[2].stakeToken = pond;
        originalSnapshotData[2].stakeAmount = 3000 ether;

        Struct.VaultSnapshot[] memory newSnapshotData = new Struct.VaultSnapshot[](5);

        // VaultE -> OperatorB (1500 POND)
        newSnapshotData[0].operator = operatorB;
        newSnapshotData[0].vault = symbioticVaultE;
        newSnapshotData[0].stakeToken = pond;
        newSnapshotData[0].stakeAmount = 1500 ether;

        // VaultA -> OperatorC (1500 WETH)
        newSnapshotData[1].operator = operatorC;
        newSnapshotData[1].vault = symbioticVaultA;
        newSnapshotData[1].stakeToken = weth;
        newSnapshotData[1].stakeAmount = 1500 ether;

        // VaultC -> OperatorC (2300 WETH)
        newSnapshotData[2].operator = operatorC;
        newSnapshotData[2].vault = symbioticVaultC;
        newSnapshotData[2].stakeToken = weth;
        newSnapshotData[2].stakeAmount = 2300 ether;

        // VaultD -> OperatorC (3000 WETH)
        newSnapshotData[3].operator = operatorC;
        newSnapshotData[3].vault = symbioticVaultD;
        newSnapshotData[3].stakeToken = weth;
        newSnapshotData[3].stakeAmount = 3000 ether;

        // VaultE -> OperatorC (4000 POND)
        newSnapshotData[4].operator = operatorC;
        newSnapshotData[4].vault = symbioticVaultE;
        newSnapshotData[4].stakeToken = pond;
        newSnapshotData[4].stakeAmount = 4000 ether;

        vm.startPrank(transmitterB);
        {
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                0, 2, block.timestamp - 5, abi.encode(originalSnapshotData), ""
            );
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                1, 2, block.timestamp - 5, abi.encode(newSnapshotData), ""
            );
            ISymbioticStaking(symbioticStaking).submitSlashResult(0, 1, block.timestamp - 5, abi.encode(""), "");
        }
        vm.stopPrank();

        assertEq(ISymbioticStaking(symbioticStaking).confirmedTimestampInfo(1).transmitter, transmitterB, "_symbiotic_staking_snapshot_submission_2: transmitter mismatch");

        // check if reward distributed for JobId2 is reflected to symbioticVaultB during snapshot submission
        {
            // rewardPerTokenPaid for symbioticVaultB should be updated
            // VaultB staked 3000 POND to OperatorB, and 0.2 USDC was distributed to OperatorB
            uint256 vaultBStake = 3000 ether;
            uint256 rewardPerTokenIncreased = Math.mulDiv(1 * USDC_DECIMALS * 20 / 100, 1e18, vaultBStake);
            uint256 rewardPerTokenPaidAfter = ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenPaid(
                pond, feeToken, symbioticVaultB, operatorB
            );

            assertEq(
                rewardPerTokenPaidAfter - vaultBRewardPerTokenPaidBefore,
                rewardPerTokenIncreased,
                "_symbiotic_staking_snapshot_submission_2: RewardPerTokenPaid mismatch"
            );
            uint256 rewardAccruedForVaultB =
                ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultB);
            assertEq(
                rewardAccruedForVaultB,
                Math.mulDiv(rewardPerTokenIncreased, vaultBStake, 1e18),
                "_symbiotic_staking_snapshot_submission_2: RewardAccrued mismatch"
            );
        }
    }


    // when multiple stakeTokens are staked to OperatorB
    function _create_job_3() internal {
        // requesterB creates a job
        vm.startPrank(jobRequesterB);
        {
            // approve feeToken for jobManager
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            uint256 jobmanagerBalanceBefore = IERC20(feeToken).balanceOf(jobManager);

            // requesterB pays 0.7 usdc as fee
            IJobManager(jobManager).createJob(3, jobRequesterA, operatorC, 7 * USDC_DECIMALS / 10);
            assertEq(IERC20(feeToken).balanceOf(jobManager) - jobmanagerBalanceBefore, 7 * USDC_DECIMALS / 10);
        }
        vm.stopPrank();
    }

    function _submit_proof_job_3() internal {
        (address lockedStakeToken,) = ISymbioticStaking(symbioticStaking).lockInfo(3);

        // OperatorC and TransmitterB fee reward before
        uint256 operatorCFeeRewardBefore = IJobManager(jobManager).operatorFeeRewards(operatorC);
        uint256 transmitterBFeeRewardBefore = IJobManager(jobManager).transmitterFeeRewards(transmitterB);
        
        uint256 rewardPerTokenStoredBefore = ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(
            lockedStakeToken, feeToken, operatorC
        );

        /* 
            < expected fee reward >
            fee paid: 0.7 usdc

            OperatorC has 15% reward share
            => 0.7 * 0.15 = 0.105 usdc

            Transmitter comission rate: 20%
            => 0.7 * 0.85 * 0.2 = 0.119 usdc

            reward distributed
            => 0.7 * 0.85 * 0.8 = 0.476 usdc
         */
        
        // TransmitterA submits proof for JobId3
        vm.startPrank(transmitterA);
        {
            IJobManager(jobManager).submitProof(3, "");
        }
        vm.stopPrank();

        // OperatorC and TransmitterB fee reward after
        uint256 operatorCFeeRewardAfter = IJobManager(jobManager).operatorFeeRewards(operatorC);
        uint256 transmitterBFeeRewardAfter = IJobManager(jobManager).transmitterFeeRewards(transmitterB);

        assertEq(operatorCFeeRewardAfter - operatorCFeeRewardBefore, 105 * USDC_DECIMALS / 1000, "_submit_proof_job_3: OperatorC fee reward mismatch");
        operatorCFeeReward += operatorCFeeRewardAfter - operatorCFeeRewardBefore;
        
        assertEq(transmitterBFeeRewardAfter - transmitterBFeeRewardBefore, 119 * USDC_DECIMALS / 1000, "_submit_proof_job_3: TransmitterB fee reward mismatch");
        transmitterBFeeReward += transmitterBFeeRewardAfter - transmitterBFeeRewardBefore;

        // rewardPerTokenStored for operatorC after
        uint256 rewardPerTokenStoredAfter = ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(
            lockedStakeToken, feeToken, operatorC
        );
        // WETH locked, 0.476 usdc distributed, 6800 WETH staked to OperatorC
        assertEq(rewardPerTokenStoredAfter - rewardPerTokenStoredBefore, Math.mulDiv(476 * USDC_DECIMALS / 1000, 1e18, 6800e18), "_submit_proof_job_3: RewardPerTokenStored mismatch");
    }

    function _vaultA_claims_reward_from_job_3() internal {
        // 0.476 usdc distributed to OperatorC
        uint256 rewardDistributed = 476 * USDC_DECIMALS / 1000;
        // out of 6800 WETH staked to OperatorC, 1500 WETH is staked by SymbioticVaultA
        uint256 rewardForVaultAExpected = Math.mulDiv(rewardDistributed, 1500e18, 6800e18);

        uint256 vaultAUSDCBalanceBefore = IERC20(feeToken).balanceOf(symbioticVaultA);

        vm.startPrank(symbioticVaultA);
        {
            ISymbioticStakingReward(symbioticStakingReward).claimReward(operatorC);
        }
        vm.stopPrank();

        uint256 vaultAUSDCBalanceAfter = IERC20(feeToken).balanceOf(symbioticVaultA);
        assertEq(vaultAUSDCBalanceAfter - vaultAUSDCBalanceBefore, rewardForVaultAExpected, "_vaultA_claims_reward_from_job_3: VaultA fee reward mismatch");
    }

    function _symbiotic_staking_snapshot_submission_3() internal {
        // Vaults that staked to OperatorC during JobId3
        uint256 job3RewardDistributed = 476 * USDC_DECIMALS / 1000;

        uint256 vaultARewardAccruedBefore = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultA);
        uint256 vaultARewardExpected = 0;

        // VaultC staked 2300 WETH to OperatorC
        uint256 vaultCRewardAccruedBefore = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultC);
        uint256 vaultCRewardExpected = Math.mulDiv(job3RewardDistributed, 2300e18, 6800e18);

        // VaultD staked 3000 WETH to OperatorC
        uint256 vaultDRewardAccruedBefore = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultD);
        uint256 vaultDRewardExpected = Math.mulDiv(job3RewardDistributed, 3000e18, 6800e18);

        // VaultE staked 1500 POND to OperatorC, WETH was selected so no reward accrued
        uint256 vaultERewardAccruedBefore = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultE);
        uint256 vaultERewardExpected = 0;
        
        // everything else is same as Snapshot2, except that VaultC and VaultE unstaked from OperatorC

        // same snapshot as in _symbiotic_staking_snapshot_submission_1
        Struct.VaultSnapshot[] memory snapshotData = new Struct.VaultSnapshot[](6);
        // VaultA -> OperatorA (1000 weth)
        snapshotData[0].operator = operatorA;
        snapshotData[0].vault = symbioticVaultA;
        snapshotData[0].stakeToken = weth;
        snapshotData[0].stakeAmount = 1000 ether;

        // VaultA -> OperatorB (2000 weth)
        snapshotData[1].operator = operatorB;
        snapshotData[1].vault = symbioticVaultA;
        snapshotData[1].stakeToken = weth;
        snapshotData[1].stakeAmount = 2000 ether;

        // VaultB -> OperatorB (3000 pond)
        snapshotData[2].operator = operatorB;
        snapshotData[2].vault = symbioticVaultB;
        snapshotData[2].stakeToken = pond;
        snapshotData[2].stakeAmount = 3000 ether;

        // VaultE -> OperatorB (1500 POND)
        snapshotData[3].operator = operatorB;
        snapshotData[3].vault = symbioticVaultE;
        snapshotData[3].stakeToken = pond;
        snapshotData[3].stakeAmount = 1500 ether;

        // VaultA -> OperatorC (1500 WETH)
        snapshotData[4].operator = operatorC;
        snapshotData[4].vault = symbioticVaultA;
        snapshotData[4].stakeToken = weth;
        snapshotData[4].stakeAmount = 1500 ether;

        // VaultD -> OperatorC (3000 WETH)
        snapshotData[5].operator = operatorC;
        snapshotData[5].vault = symbioticVaultD;
        snapshotData[5].stakeToken = weth;
        snapshotData[5].stakeAmount = 3000 ether;

        Struct.VaultSnapshot[] memory unstakedSnapshotData = new Struct.VaultSnapshot[](5);
        
        // VaultC -> OperatorC (0 WETH) [Unstaked]
        unstakedSnapshotData[0].operator = operatorC;
        unstakedSnapshotData[0].vault = symbioticVaultC;
        unstakedSnapshotData[0].stakeToken = weth;
        unstakedSnapshotData[0].stakeAmount = 0 ether;

        // VaultE -> OperatorC (0 POND) [Unstaked]
        unstakedSnapshotData[1].operator = operatorC;
        unstakedSnapshotData[1].vault = symbioticVaultE;
        unstakedSnapshotData[1].stakeToken = pond;
        unstakedSnapshotData[1].stakeAmount = 0 ether;

        vm.startPrank(transmitterC);
        {
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(0, 2, block.timestamp - 5, abi.encode(snapshotData), "");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(1, 2, block.timestamp - 5, abi.encode(unstakedSnapshotData), "");
            ISymbioticStaking(symbioticStaking).submitSlashResult(0, 1, block.timestamp - 5, abi.encode(""), "");
        }
        vm.stopPrank();
        assertEq(ISymbioticStaking(symbioticStaking).latestConfirmedTimestampInfo().transmitter, transmitterC, "_symbiotic_staking_snapshot_submission_3: transmitter mismatch");

        // check if reward accrued for Vaults are updated
        uint256 vaultARewardAccruedAfter = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultA);
        uint256 vaultCRewardAccruedAfter = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultC);
        uint256 vaultDRewardAccruedAfter = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultD);
        uint256 vaultERewardAccruedAfter = ISymbioticStakingReward(symbioticStakingReward).rewardAccrued(feeToken, symbioticVaultE);

        assertEq(vaultARewardAccruedAfter - vaultARewardAccruedBefore, vaultARewardExpected, "_symbiotic_staking_snapshot_submission_3: VaultA reward accrued mismatch");
        assertEq(vaultCRewardAccruedAfter - vaultCRewardAccruedBefore, vaultCRewardExpected, "_symbiotic_staking_snapshot_submission_3: VaultC reward accrued mismatch");
        assertEq(vaultDRewardAccruedAfter - vaultDRewardAccruedBefore, vaultDRewardExpected, "_symbiotic_staking_snapshot_submission_3: VaultD reward accrued mismatch");
        assertEq(vaultERewardAccruedAfter - vaultERewardAccruedBefore, vaultERewardExpected, "_symbiotic_staking_snapshot_submission_3: VaultE reward accrued mismatch");
    }

    function _create_job_4() internal {
        // requesterB creates a job
        vm.startPrank(jobRequesterB);
        {
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            IJobManager(jobManager).createJob(4, jobRequesterA, operatorC, 97 * USDC_DECIMALS / 100);
        }
        vm.stopPrank();
    }

    /* 
        < expected fee reward >

        OperatorC has 15% reward share
        => 0.97 * 0.15 = 0.1455 usdc

        Transmitter comission rate: 20%
        => 0.97 * 0.85 * 0.2 = 0.1649 usdc

        reward distributed
        => 0.97 * 0.85 * 0.8 = 0.6596 usdc

    */
    function _submit_proof_job_4() internal {
        (address lockedStakeToken,) = ISymbioticStaking(symbioticStaking).lockInfo(4);

        // OperatorC and TransmitterB fee reward before
        uint256 operatorCFeeRewardBefore = IJobManager(jobManager).operatorFeeRewards(operatorC);
        uint256 transmitterCFeeRewardBefore = IJobManager(jobManager).transmitterFeeRewards(transmitterC);
        
        // RewardDistrobutor
        uint256 rewardPerTokenStoredBefore = ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(
            lockedStakeToken, feeToken, operatorC
        );
        uint256 rewardPertokenToIncrease = Math.mulDiv(6596 * USDC_DECIMALS / 10000, 1e18, 4500e18); // 4500 WETH staked to OperatorC

        // TransmitterC submits proof for JobId4
        vm.startPrank(transmitterC);
        {
            IJobManager(jobManager).submitProof(4, "");
        }
        vm.stopPrank();

        // OperatorC and TransmitterB fee reward after
        uint256 operatorCFeeRewardAfter = IJobManager(jobManager).operatorFeeRewards(operatorC);
        uint256 transmitterCFeeRewardAfter = IJobManager(jobManager).transmitterFeeRewards(transmitterC);

        assertEq(operatorCFeeRewardAfter - operatorCFeeRewardBefore, 1455 * USDC_DECIMALS / 10000, "_submit_proof_job_4: OperatorC fee reward mismatch");
        operatorCFeeReward += operatorCFeeRewardAfter - operatorCFeeRewardBefore;
        
        assertEq(transmitterCFeeRewardAfter - transmitterCFeeRewardBefore, 1649 * USDC_DECIMALS / 10000, "_submit_proof_job_4: TransmitterC fee reward mismatch");
        transmitterCFeeReward += transmitterCFeeRewardAfter - transmitterCFeeRewardBefore;

        // check if reward distributed for JobId4 is reflected to symbioticVaultA during snapshot submission
        uint256 rewardPerTokenStoredAfter = ISymbioticStakingReward(symbioticStakingReward).rewardPerTokenStored(
            lockedStakeToken, feeToken, operatorC
        );
        assertEq(rewardPerTokenStoredAfter - rewardPerTokenStoredBefore, rewardPertokenToIncrease, "_submit_proof_job_4: RewardPerTokenStored mismatch");
    }

    function _vaultA_claims_reward_from_job_4() internal {
        // 0.6596 usdc distributed to OperatorC for JobId4
        uint256 rewardDistributed = 6596 * USDC_DECIMALS / 10000;
        uint256 operatorCStake = 4500e18;
        uint256 rewardPerTokenAdded = Math.mulDiv(rewardDistributed, 1e18, operatorCStake);

        // out of 4500 WETH staked to OperatorC, 1500 WETH is staked by SymbioticVaultA
        uint256 vaultARewardExpected = Math.mulDiv(rewardPerTokenAdded, 1500e18, 1e18);

        uint256 vaultAUSDCBalanceBefore = IERC20(feeToken).balanceOf(symbioticVaultA);

        vm.startPrank(symbioticVaultA);
        {
            ISymbioticStakingReward(symbioticStakingReward).claimReward(operatorC);
        }
        vm.stopPrank();

        uint256 vaultAUSDCBalanceAfter = IERC20(feeToken).balanceOf(symbioticVaultA);
        assertEq(vaultAUSDCBalanceAfter - vaultAUSDCBalanceBefore, vaultARewardExpected, "_vaultA_claims_reward_from_job_4: VaultA fee reward mismatch");
    }

    // VaultC unstaked after Job3, and hasn't claimed the reward accrued
    function _vaultC_claims_reward_from_job_4() internal {
        // 0.476 usdc distributed to OperatorC for JobId3
        uint256 job3RewardDistributed = 476 * USDC_DECIMALS / 1000;
        uint256 job3OperatorCStake = 6800e18;
        uint256 job3RewardPerTokenAdded = Math.mulDiv(job3RewardDistributed, 1e18, job3OperatorCStake);
        uint256 vaultCRewardExpected = Math.mulDiv(job3RewardPerTokenAdded, 2300e18, 1e18);

        uint256 vaultCUSDCBalanceBefore = IERC20(feeToken).balanceOf(symbioticVaultC);

        vm.startPrank(symbioticVaultC);
        {
            ISymbioticStakingReward(symbioticStakingReward).claimReward(operatorC);
        }
        vm.stopPrank();

        uint256 vaultCUSDCBalanceAfter = IERC20(feeToken).balanceOf(symbioticVaultC);
        assertEq(vaultCUSDCBalanceAfter - vaultCUSDCBalanceBefore, vaultCRewardExpected, "_vaultC_claims_reward_from_job_4: VaultC fee reward mismatch");
    }

    function _vaultD_claims_reward_from_job_4() internal {
        uint256 vaultDRewardExpected;

        // 0.476 usdc distributed to OperatorC for JobId3
        uint256 job3RewardDistributed = 476 * USDC_DECIMALS / 1000;
        uint256 job3OperatorCStake = 6800e18;
        uint256 job3RewardPerTokenAdded = Math.mulDiv(job3RewardDistributed, 1e18, job3OperatorCStake);
        vaultDRewardExpected += Math.mulDiv(job3RewardPerTokenAdded, 3000e18, 1e18);

        // 0.6596 usdc distributed to OperatorC for JobId4
        uint256 job4RewardDistributed = 6596 * USDC_DECIMALS / 10000;
        uint256 job4OperatorCStake = 4500e18;
        uint256 job4RewardPerTokenAdded = Math.mulDiv(job4RewardDistributed, 1e18, job4OperatorCStake);
        vaultDRewardExpected += Math.mulDiv(job4RewardPerTokenAdded, 3000e18, 1e18);

        uint256 vaultDUSDCBalanceBefore = IERC20(feeToken).balanceOf(symbioticVaultD);

        vm.startPrank(symbioticVaultD);
        {
            ISymbioticStakingReward(symbioticStakingReward).claimReward(operatorC);
        }
        vm.stopPrank();

        uint256 vaultDUSDCBalanceAfter = IERC20(feeToken).balanceOf(symbioticVaultD);
        assertEq(vaultDUSDCBalanceAfter - vaultDUSDCBalanceBefore, vaultDRewardExpected, "_vaultD_claims_reward_from_job_4: VaultD fee reward mismatch");
    }

    function _operators_and_transmitters_claim_fee_reward() internal {
        uint256 operatorAFeeTokenBalanceBefore = IERC20(feeToken).balanceOf(operatorA);
        uint256 operatorBFeeTokenBalanceBefore = IERC20(feeToken).balanceOf(operatorB);
        uint256 operatorCFeeTokenBalanceBefore = IERC20(feeToken).balanceOf(operatorC);

        uint256 transmitterAFeeTokenBalanceBefore = IERC20(feeToken).balanceOf(transmitterA);
        uint256 transmitterBFeeTokenBalanceBefore = IERC20(feeToken).balanceOf(transmitterB);
        uint256 transmitterCFeeTokenBalanceBefore = IERC20(feeToken).balanceOf(transmitterC);

        vm.prank(operatorA);
        IJobManager(jobManager).claimOperatorFeeReward(operatorA);

        vm.prank(operatorB);
        IJobManager(jobManager).claimOperatorFeeReward(operatorB);  

        vm.prank(operatorC);
        IJobManager(jobManager).claimOperatorFeeReward(operatorC);

        vm.prank(transmitterA);
        IJobManager(jobManager).claimTransmitterFeeReward(transmitterA);

        vm.prank(transmitterB);
        IJobManager(jobManager).claimTransmitterFeeReward(transmitterB);

        vm.prank(transmitterC);
        IJobManager(jobManager).claimTransmitterFeeReward(transmitterC);

        uint256 operatorAFeeTokenBalanceAfter = IERC20(feeToken).balanceOf(operatorA);
        uint256 operatorBFeeTokenBalanceAfter = IERC20(feeToken).balanceOf(operatorB);
        uint256 operatorCFeeTokenBalanceAfter = IERC20(feeToken).balanceOf(operatorC);

        uint256 transmitterAFeeTokenBalanceAfter = IERC20(feeToken).balanceOf(transmitterA);
        uint256 transmitterBFeeTokenBalanceAfter = IERC20(feeToken).balanceOf(transmitterB);
        uint256 transmitterCFeeTokenBalanceAfter = IERC20(feeToken).balanceOf(transmitterC);

        assertEq(operatorAFeeTokenBalanceAfter - operatorAFeeTokenBalanceBefore, operatorAFeeReward, "_operators_and_transmitters_claim_fee_reward: OperatorA fee token balance mismatch");
        assertEq(operatorBFeeTokenBalanceAfter - operatorBFeeTokenBalanceBefore, operatorBFeeReward, "_operators_and_transmitters_claim_fee_reward: OperatorB fee token balance mismatch");
        assertEq(operatorCFeeTokenBalanceAfter - operatorCFeeTokenBalanceBefore, operatorCFeeReward, "_operators_and_transmitters_claim_fee_reward: OperatorC fee token balance mismatch");

        assertEq(transmitterAFeeTokenBalanceAfter - transmitterAFeeTokenBalanceBefore, transmitterAFeeReward, "_operators_and_transmitters_claim_fee_reward: TransmitterA fee token balance mismatch");
        assertEq(transmitterBFeeTokenBalanceAfter - transmitterBFeeTokenBalanceBefore, transmitterBFeeReward, "_operators_and_transmitters_claim_fee_reward: TransmitterB fee token balance mismatch");
        assertEq(transmitterCFeeTokenBalanceAfter - transmitterCFeeTokenBalanceBefore, transmitterCFeeReward, "_operators_and_transmitters_claim_fee_reward: TransmitterC fee token balance mismatch");
    }
}
