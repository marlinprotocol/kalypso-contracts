// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";

import {USDC} from "./mocks/USDC.sol";
import {POND} from "./mocks/POND.sol";

import {JobManager} from "../../contracts/staking/l2_contracts/JobManager.sol";
import {StakingManager} from "../../contracts/staking/l2_contracts/StakingManager.sol";
import {NativeStaking} from "../../contracts/staking/l2_contracts/NativeStaking.sol";
import {SymbioticStaking} from "../../contracts/staking/l2_contracts/SymbioticStaking.sol";
import {SymbioticStakingReward} from "../../contracts/staking/l2_contracts/SymbioticStakingReward.sol";
import {InflationRewardManager} from "../../contracts/staking/l2_contracts/InflationRewardManger.sol";

import {IJobManager} from "../../contracts/interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../contracts/interfaces/staking/IStakingManager.sol";
import {IInflationRewardManager} from "../../contracts/interfaces/staking/IInflationRewardManager.sol";
import {INativeStaking} from "../../contracts/interfaces/staking/INativeStaking.sol";
import {ISymbioticStaking} from "../../contracts/interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../contracts/interfaces/staking/ISymbioticStakingReward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestSetup is Test {
    uint256 constant FUND_FOR_GAS = 10 * 1e18; // 10 ether

    address public jobManager;
    address public stakingManager;
    address public inflationRewardManager;
    address public feeToken;
    address public inflationRewardToken;

    address public nativeStaking;
    address public symbioticStaking;
    address public symbioticStakingReward;

    address public deployer;
    address public admin;

    address public operatorA;
    address public operatorB;
    address public operatorC;

    address public userA;
    address public userB;
    address public userC;

    function _setupAddr() internal {
        /* set address */
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");

        operatorA = makeAddr("operatorA");
        operatorB = makeAddr("operatorB");
        operatorC = makeAddr("operatorC");

        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");

        /* fund gas */
        vm.deal(deployer, FUND_FOR_GAS);
        vm.deal(admin, FUND_FOR_GAS);

        vm.deal(operatorA, FUND_FOR_GAS);
        vm.deal(operatorB, FUND_FOR_GAS);
        vm.deal(operatorC, FUND_FOR_GAS);

        vm.deal(userA, FUND_FOR_GAS);
        vm.deal(userB, FUND_FOR_GAS);
        vm.deal(userC, FUND_FOR_GAS);

        /* label */
        vm.label(deployer, "deployer");
        vm.label(admin, "admin");

        vm.label(operatorA, "operatorA");
        vm.label(operatorB, "operatorB");
        vm.label(operatorC, "operatorC");

        vm.label(userA, "userA");
        vm.label(userB, "userB");
        vm.label(userC, "userC");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // FeeToken
        feeToken = address(new USDC(admin));

        // InflationRewardToken
        inflationRewardToken = address(new POND(admin));

        address jobManagerImpl = address(new JobManager());
        address stakingManagerImpl = address(new StakingManager());
        address nativeStakingImpl = address(new NativeStaking());
        address symbioticStakingImpl = address(new SymbioticStaking());
        address symbioticStakingRewardImpl = address(new SymbioticStakingReward());
        address inflationRewardManagerImpl = address(new InflationRewardManager());

        jobManager = address(new ERC1967Proxy(jobManagerImpl, ""));
        stakingManager = address(new ERC1967Proxy(stakingManagerImpl, ""));
        nativeStaking = address(new ERC1967Proxy(nativeStakingImpl, ""));
        symbioticStaking = address(new ERC1967Proxy(symbioticStakingImpl, ""));
        symbioticStakingReward = address(new ERC1967Proxy(symbioticStakingRewardImpl, ""));
        inflationRewardManager = address(new ERC1967Proxy(inflationRewardManagerImpl, ""));
        vm.stopPrank();

        vm.label(address(jobManager), "JobManager");
        vm.label(address(stakingManager), "StakingManager");
        vm.label(address(nativeStaking), "NativeStaking");
        vm.label(address(symbioticStaking), "SymbioticStaking");
        vm.label(address(symbioticStakingReward), "SymbioticStakingReward");
        vm.label(address(inflationRewardManager), "InflationRewardManager");
    }

    function _initializeContracts() internal {
        vm.startPrank(admin);   

        // JobManager
        JobManager(address(jobManager)).initialize(
            admin, address(stakingManager), address(feeToken), address(inflationRewardManager), 1 hours
        );

        // StakingManager
        StakingManager(address(stakingManager)).initialize(
            admin,
            address(jobManager),
            address(inflationRewardManager),
            address(feeToken),
            address(inflationRewardToken)
        );

        // NativeStaking
        NativeStaking(address(nativeStaking)).initialize(
            admin,
            address(stakingManager),
            address(0), // rewardDistributor (not set)
            2 days, // withdrawalDuration
            address(feeToken),
            address(inflationRewardToken)
        );

        // SymbioticStaking
        SymbioticStaking(address(symbioticStaking)).initialize(
            admin,
            address(stakingManager),
            address(symbioticStakingReward),
            address(inflationRewardManager),
            address(feeToken),
            address(inflationRewardToken)
        );

        // SymbioticStakingReward
        SymbioticStakingReward(address(symbioticStakingReward)).initialize(
            admin,
            address(inflationRewardManager),
            address(jobManager),
            address(symbioticStaking),
            address(feeToken),
            address(inflationRewardToken)
        );

        // InflationRewardManager
        InflationRewardManager(address(inflationRewardManager)).initialize(
            admin,
            block.timestamp,
            address(jobManager),
            address(stakingManager),
            address(inflationRewardToken),
            30 minutes, // inflationRewardEpochSize
            1000 ether // inflationRewardPerEpoch
        );

        vm.stopPrank();
    }
}
