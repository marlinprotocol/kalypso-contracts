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

contract KalypsoStakingTest is Test, TestSetup {
    uint256 constant OPERATORA_SELF_STAKE_AMOUNT = 1000 ether;
    uint256 constant OPERATORB_SELF_STAKE_AMOUNT = 2000 ether;
    uint256 constant VAULT_A_INTO_OPERATOR_A = 1000 ether;
    uint256 constant VAULT_B_INTO_OPERATOR_A = 2000 ether;
    uint256 constant VAULT_B_INTO_OPERATOR_B = 3000 ether;

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

        // symbiotic staking snapshot submitted
        _symbiotic_staking_snapshot_submission();

        // jobId1 created
        _create_job_1();

        vm.warp(block.timestamp + 10 minutes);

        // proof submitted
        _submit_proof_job_1();

        // symbioticVaultA claims fee reward (no inflation reward from job1 generated yet)
        _vault_claim_reward_from_job_1();

        // jobId2 created
        vm.warp(block.timestamp + INFLATION_REWARD_EPOCH_SIZE); // inflation reward for job1 should be generated
        _create_job_2();

        // jobId2 completed
        _submit_proof_job_2(); // TODO: inflation reward generated

        // fee reward and inflation reward distributed

        // job created
        _create_job_3();

        // job slashed in Symbiotic Staking and result submitted
        vm.warp(block.timestamp + SUBMISSION_COOLDOWN);
        _slash_result_submission_job_3();
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

        vm.startPrank(operatorB);
        {   
            // OperatorB self stakes 2000 POND

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
    }

    function _symbiotic_staking_snapshot_submission() internal {
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
        _vaultSnapshots1[0].stakeAmount = VAULT_A_INTO_OPERATOR_A;

        // Partial Tx 2
        Struct.VaultSnapshot[] memory _vaultSnapshots2 = new Struct.VaultSnapshot[](2);

        /* Vault B */

        // VaultA(2000 weth) -> OperatorB
        _vaultSnapshots2[0].operator = operatorB;
        _vaultSnapshots2[0].vault = symbioticVaultA;
        _vaultSnapshots2[0].stakeToken = weth;
        _vaultSnapshots2[0].stakeAmount = VAULT_B_INTO_OPERATOR_A;

        // VaultB(3000 POND) -> OperatorB
        _vaultSnapshots2[1].operator = operatorB;
        _vaultSnapshots2[1].vault = symbioticVaultB;
        _vaultSnapshots2[1].stakeToken = pond;
        _vaultSnapshots2[1].stakeAmount = VAULT_B_INTO_OPERATOR_B;

        /* Snapshot Submission */
        vm.startPrank(transmitterA);
        {
            vm.expectRevert("Invalid index");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                3, 2, abi.encode(block.timestamp - 5, _vaultSnapshots1), ""
            );

            vm.expectRevert("Invalid index");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                2, 2, abi.encode(block.timestamp - 5, _vaultSnapshots1), ""
            );

            vm.expectRevert("Invalid timestamp");
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                1, 2, abi.encode(block.timestamp + 1, _vaultSnapshots1), ""
            );

            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                0, 2, abi.encode(block.timestamp - 5, _vaultSnapshots1), ""
            );
        }
        vm.stopPrank();
        Struct.SnapshotTxCountInfo memory _txCountInfo = ISymbioticStaking(symbioticStaking).getTxCountInfo(
            block.timestamp - 5, transmitterA, keccak256("STAKE_SNAPSHOT_TYPE")
        );

        assertEq(_txCountInfo.idxToSubmit, 1, "_symbiotic_staking_snapshot_submission: Tx count info mismatch");
        assertEq(_txCountInfo.numOfTxs, 2, "_symbiotic_staking_snapshot_submission: Tx count info mismatch");
        assertEq(
            ISymbioticStaking(symbioticStaking).getSubmissionStatus(block.timestamp - 5, transmitterA),
            0x0,
            "_symbiotic_staking_snapshot_submission: Submission status mismatch"
        );

        vm.startPrank(transmitterA);
        {
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                1, 2, abi.encode(block.timestamp - 5, _vaultSnapshots2), ""
            );
        }
        vm.stopPrank();

        _txCountInfo = ISymbioticStaking(symbioticStaking).getTxCountInfo(
            block.timestamp - 5, transmitterA, keccak256("STAKE_SNAPSHOT_TYPE")
        );
        assertEq(_txCountInfo.idxToSubmit, 2);
        assertEq(_txCountInfo.numOfTxs, 2);
        assertEq(
            ISymbioticStaking(symbioticStaking).getSubmissionStatus(block.timestamp - 5, transmitterA),
            0x0000000000000000000000000000000000000000000000000000000000000001,
            "Submission status mismatch"
        );

        /* Slash Result Submission */
        vm.prank(transmitterA);
        ISymbioticStaking(symbioticStaking).submitSlashResult(0, 1, abi.encode(block.timestamp - 5, ""), "");
    }

    function _create_job_1() internal {
        // requesterA creates a job
        vm.startPrank(jobRequesterA);
        {
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            uint256 jobmanagerBalanceBefore = IERC20(feeToken).balanceOf(jobManager);

            vm.expectRevert("No stakeToken available");
            IJobManager(jobManager).createJob(1, jobRequesterA, operatorC, 1 ether); // should revert as operatorC didn't stake any token to NativeStaking

            // pay 1 usdc as fee
            IJobManager(jobManager).createJob(1, jobRequesterA, operatorA, 1 ether);
            assertEq(IERC20(feeToken).balanceOf(jobManager) - jobmanagerBalanceBefore, 1 ether);
        }
        vm.stopPrank();
    }

    function _submit_proof_job_1() internal {
        Struct.ConfirmedTimestamp memory _confirmedTimestampInfo =
            ISymbioticStaking(symbioticStaking).confirmedTimestampInfo(0);

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
        assertEq(IERC20(feeToken).balanceOf(operatorA), 0.3 ether, "OperatorA fee reward mismatch");
        assertEq(IERC20(feeToken).balanceOf(transmitterA), 0.14 ether, "TransmitterA fee reward mismatch");
    }

    function _vault_claim_reward_from_job_1() internal {
        /* 
            Vault A claim fee reward
            Inflation reward still in pending
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

        assertEq(IERC20(feeToken).balanceOf(symbioticVaultA), 0.56 ether, "SymbioticVaultA fee reward mismatch");
    }

    function _create_job_2() internal {
        // requesterB creates a job
        vm.startPrank(jobRequesterB);
        {
            // approve jobRequesterB -> feeToken
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            uint256 jobmanagerBalanceBefore = IERC20(feeToken).balanceOf(jobManager);

            // pay 0.5 usdc as fee
            IJobManager(jobManager).createJob(2, jobRequesterA, operatorA, 0.5 ether);
            assertEq(IERC20(feeToken).balanceOf(jobManager) - jobmanagerBalanceBefore, 0.5 ether);
        }
        vm.stopPrank();
    }

    // inflation reward generated
    function _submit_proof_job_2() internal {
        vm.startPrank(operatorA);
        {
            IJobManager(jobManager).submitProof(2, "");
        }
        vm.stopPrank();

        /* 
            Inflation reward generated: 100 POND (1 job don by operator)

            OperatorA comission: 20%
            => 100 * 0.3 = 30 POND

            TransmitterA comission: 20%
            => 100 * 0.7(after operatorA comission) * 0.2(transmitter comission) = 14 POND

            SymbioticVaultA 
         */

        // TODO: check inflation reward logic
    }

    // job gets slashed
    function _create_job_3() internal {
        // requesterC creates a job
        vm.startPrank(jobRequesterC);
        {
            IERC20(feeToken).approve(jobManager, type(uint256).max);
            uint256 jobmanagerBalanceBefore = IERC20(feeToken).balanceOf(jobManager);

            // pay 2 usdc as fee
            IJobManager(jobManager).createJob(3, jobRequesterC, operatorB, 2 ether);
            assertEq(IERC20(feeToken).balanceOf(jobManager) - jobmanagerBalanceBefore, 2 ether);
        }
        vm.stopPrank();

        // TODO: check job completion logic
    }

    function _slash_result_submission_job_3() internal {
        uint256 jobRequesterCBalanceBefore = IERC20(feeToken).balanceOf(jobRequesterC);

        // Partial Tx 1
        Struct.VaultSnapshot[] memory _vaultSnapshot = new Struct.VaultSnapshot[](3);
        /* Vault A */
        // VaultA(1000 WETH) -> OperatorA
        _vaultSnapshot[0].operator = operatorA;
        _vaultSnapshot[0].vault = symbioticVaultA;
        _vaultSnapshot[0].stakeToken = weth;
        _vaultSnapshot[0].stakeAmount = VAULT_A_INTO_OPERATOR_A;

        /* Vault B */
        // VaultA(2000 weth) -> OperatorB
        _vaultSnapshot[1].operator = operatorB;
        _vaultSnapshot[1].vault = symbioticVaultA;
        _vaultSnapshot[1].stakeToken = weth;
        _vaultSnapshot[1].stakeAmount = VAULT_B_INTO_OPERATOR_A;
        // VaultB(3000 POND) -> OperatorB
        _vaultSnapshot[2].operator = operatorB;
        _vaultSnapshot[2].vault = symbioticVaultB;
        _vaultSnapshot[2].stakeToken = pond;
        _vaultSnapshot[2].stakeAmount = VAULT_B_INTO_OPERATOR_B;

        Struct.JobSlashed[] memory _jobSlashed = new Struct.JobSlashed[](1);

        _jobSlashed[0].jobId = 3;
        _jobSlashed[0].operator = operatorB;
        _jobSlashed[0].rewardAddress = slasher;

        vm.startPrank(transmitterB);
        {
            // submit vault snapshot
            ISymbioticStaking(symbioticStaking).submitVaultSnapshot(
                0, 1, abi.encode(block.timestamp, _vaultSnapshot), ""
            );

            // submit slash result
            ISymbioticStaking(symbioticStaking).submitSlashResult(0, 1, abi.encode(block.timestamp, _jobSlashed), "");
        }
        vm.stopPrank();

        // check if fee is refunded
        assertEq(
            IERC20(feeToken).balanceOf(jobRequesterC) - jobRequesterCBalanceBefore,
            2 ether,
            "JobRequesterC fee refund mismatch"
        );
    }
}
