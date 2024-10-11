// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";

/* mocks */
import {USDC} from "./mocks/USDC.sol";
import {POND} from "./mocks/POND.sol";
import {WETH} from "./mocks/WETH.sol";

/* contracts */
import {JobManager} from "../../contracts/staking/l2_contracts/JobManager.sol";
import {StakingManager} from "../../contracts/staking/l2_contracts/StakingManager.sol";
import {NativeStaking} from "../../contracts/staking/l2_contracts/NativeStaking.sol";
import {SymbioticStaking} from "../../contracts/staking/l2_contracts/SymbioticStaking.sol";
import {SymbioticStakingReward} from "../../contracts/staking/l2_contracts/SymbioticStakingReward.sol";
import {InflationRewardManager} from "../../contracts/staking/l2_contracts/InflationRewardManger.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* interfaces */
import {IJobManager} from "../../contracts/interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../contracts/interfaces/staking/IStakingManager.sol";
import {IInflationRewardManager} from "../../contracts/interfaces/staking/IInflationRewardManager.sol";
import {INativeStaking} from "../../contracts/interfaces/staking/INativeStaking.sol";
import {ISymbioticStaking} from "../../contracts/interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../contracts/interfaces/staking/ISymbioticStakingReward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* libraries */
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestSetup is Test {
    uint256 constant TWENTY_PERCENT = 20;
    uint256 constant THIRTY_PERCENT = 30;
    uint256 constant FORTY_PERCENT = 40;
    uint256 constant FIFTY_PERCENT = 50;
    uint256 constant SIXTY_PERCENT = 60;
    uint256 constant HUNDRED_PERCENT = 100;
    
    uint256 constant FUND_FOR_GAS = 10 ether; // 10 ether
    uint256 constant FUND_FOR_FEE = 10_000 ether; // 10,000 USDC
    uint256 constant FUND_FOR_INFLATION_REWARD = 100_000 ether; // 100,000 POND

    uint256 constant INFLATION_REWARD_EPOCH_SIZE = 30 minutes; // 30 minutes
    uint256 constant INFLATION_REWARD_PER_EPOCH = 1000 ether; // 1,000 POND


    /* contracts */
    address public jobManager;
    address public inflationRewardManager;

    address public stakingManager;
    address public nativeStaking;
    address public symbioticStaking;
    address public symbioticStakingReward;

    /* reward tokens */
    address public feeToken;
    address public inflationRewardToken;

    /* stake tokens */
    address public usdc;
    address public pond;
    address public weth;

    /* admin */
    address public deployer;
    address public admin;
    address public vault; // holds inflation reward tokens

    /* operators */
    address public operatorA;
    address public operatorB;
    address public operatorC;

    /* stakers */
    address public stakerA;
    address public stakerB;
    address public stakerC;

    /* job requesters */
    address public jobRequesterA;
    address public jobRequesterB;
    address public jobRequesterC;
    

    function _setupAddr() internal {
        /* set address */
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        vault = makeAddr("vault");

        stakerA = makeAddr("stakerA");
        stakerB = makeAddr("stakerB");
        stakerC = makeAddr("stakerC");

        operatorA = makeAddr("operatorA");
        operatorB = makeAddr("operatorB");
        operatorC = makeAddr("operatorC");

        jobRequesterA = makeAddr("jobRequesterA");
        jobRequesterB = makeAddr("jobRequesterB");
        jobRequesterC = makeAddr("jobRequesterC");

        /* fund gas */
        vm.deal(deployer, FUND_FOR_GAS);
        vm.deal(admin, FUND_FOR_GAS);
        vm.deal(vault, FUND_FOR_GAS);

        vm.deal(operatorA, FUND_FOR_GAS);
        vm.deal(operatorB, FUND_FOR_GAS);
        vm.deal(operatorC, FUND_FOR_GAS);

        vm.deal(stakerA, FUND_FOR_GAS);
        vm.deal(stakerB, FUND_FOR_GAS);
        vm.deal(stakerC, FUND_FOR_GAS);

        vm.deal(jobRequesterA, FUND_FOR_GAS);
        vm.deal(jobRequesterB, FUND_FOR_GAS);
        vm.deal(jobRequesterC, FUND_FOR_GAS);

        /* label */
        vm.label(deployer, "deployer");
        vm.label(admin, "admin");

        vm.label(operatorA, "operatorA");
        vm.label(operatorB, "operatorB");
        vm.label(operatorC, "operatorC");

        vm.label(stakerA, "stakerA");
        vm.label(stakerB, "stakerB");
        vm.label(stakerC, "stakerC");

        vm.label(jobRequesterA, "jobRequesterA");
        vm.label(jobRequesterB, "jobRequesterB");
        vm.label(jobRequesterC, "jobRequesterC");
    }

    /*======================================== internal ========================================*/

    function _setupContracts() internal {
        _deployContracts();
        _initializeContracts();
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // FeeToken
        feeToken = address(new USDC(admin));

        // InflationRewardToken
        inflationRewardToken = address(new POND(admin));

        // stakeToken
        weth = address(new WETH(admin));
        pond = inflationRewardToken;

        // contract implementations
        address jobManagerImpl = address(new JobManager());
        address stakingManagerImpl = address(new StakingManager());
        address nativeStakingImpl = address(new NativeStaking());
        address symbioticStakingImpl = address(new SymbioticStaking());
        address symbioticStakingRewardImpl = address(new SymbioticStakingReward());
        address inflationRewardManagerImpl = address(new InflationRewardManager());

        // deploy proxies   
        jobManager = address(new ERC1967Proxy(jobManagerImpl, ""));
        stakingManager = address(new ERC1967Proxy(stakingManagerImpl, ""));
        nativeStaking = address(new ERC1967Proxy(nativeStakingImpl, ""));
        symbioticStaking = address(new ERC1967Proxy(symbioticStakingImpl, ""));
        symbioticStakingReward = address(new ERC1967Proxy(symbioticStakingRewardImpl, ""));
        inflationRewardManager = address(new ERC1967Proxy(inflationRewardManagerImpl, ""));
        vm.stopPrank();

        /* label */
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
        assertEq(JobManager(jobManager).hasRole(JobManager(jobManager).DEFAULT_ADMIN_ROLE(), admin), true); 

        // StakingManager
        StakingManager(address(stakingManager)).initialize(
            admin,
            address(jobManager),
            address(inflationRewardManager),
            address(feeToken),
            address(inflationRewardToken)
        );
        assertEq(StakingManager(stakingManager).hasRole(StakingManager(stakingManager).DEFAULT_ADMIN_ROLE(), admin), true); 

        // NativeStaking
        NativeStaking(address(nativeStaking)).initialize(
            admin,
            address(stakingManager),
            address(0), // rewardDistributor (not set)
            2 days, // withdrawalDuration
            address(feeToken),
            address(inflationRewardToken)
        );
        assertEq(NativeStaking(nativeStaking).hasRole(NativeStaking(nativeStaking).DEFAULT_ADMIN_ROLE(), admin), true); 
    
        // SymbioticStaking
        SymbioticStaking(address(symbioticStaking)).initialize(
            admin,
            address(stakingManager),
            address(symbioticStakingReward),
            address(inflationRewardManager),
            address(feeToken),
            address(inflationRewardToken)
        );
        assertEq(SymbioticStaking(symbioticStaking).hasRole(SymbioticStaking(symbioticStaking).DEFAULT_ADMIN_ROLE(), admin), true); 
        // SymbioticStakingReward
        SymbioticStakingReward(address(symbioticStakingReward)).initialize(
            admin,
            address(inflationRewardManager),
            address(jobManager),
            address(symbioticStaking),
            address(feeToken),
            address(inflationRewardToken)
        );
        assertEq(SymbioticStakingReward(symbioticStakingReward).hasRole(SymbioticStakingReward(symbioticStakingReward).DEFAULT_ADMIN_ROLE(), admin), true); 

        // InflationRewardManager
        InflationRewardManager(address(inflationRewardManager)).initialize(
            admin,
            block.timestamp,
            address(jobManager),
            address(stakingManager),
            address(inflationRewardToken),
            INFLATION_REWARD_EPOCH_SIZE, // inflationRewardEpochSize
            INFLATION_REWARD_PER_EPOCH // inflationRewardPerEpoch
        );
        assertEq(InflationRewardManager(inflationRewardManager).hasRole(InflationRewardManager(inflationRewardManager).DEFAULT_ADMIN_ROLE(), admin), true); 
        vm.stopPrank();
    }

        function _setJobManagerConfig() internal {
        vm.startPrank(admin);
        // operatorA: 30% of the reward as comission
        JobManager(jobManager).setOperatorRewardShare(operatorA, _calcShareAmount(THIRTY_PERCENT));
        // operatorB: 50% of the reward as comission
        JobManager(jobManager).setOperatorRewardShare(operatorB, _calcShareAmount(FIFTY_PERCENT));
        vm.stopPrank();
    }

    function _setStakingManagerConfig() internal {
        address[] memory pools = new address[](2);
        pools[0] = nativeStaking;
        pools[1] = symbioticStaking;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 0;
        shares[1] = _calcShareAmount(HUNDRED_PERCENT);

        vm.startPrank(admin);
        StakingManager(stakingManager).addStakingPool(nativeStaking);
        StakingManager(stakingManager).addStakingPool(symbioticStaking);

        StakingManager(stakingManager).setPoolRewardShare(pools, shares);

        StakingManager(stakingManager).setEnabledPool(nativeStaking, true);
        StakingManager(stakingManager).setEnabledPool(symbioticStaking, true);
        vm.stopPrank();

        assertEq(IStakingManager(stakingManager).getPoolConfig(nativeStaking).share, 0);
        assertEq(IStakingManager(stakingManager).getPoolConfig(symbioticStaking).share, _calcShareAmount(HUNDRED_PERCENT));
    }

    function _setNativeStakingConfig() internal {
        vm.startPrank(admin);
        NativeStaking(nativeStaking).setStakeToken(pond, true);
        vm.stopPrank();
    }

    function _setSymbioticStakingConfig() internal {
        vm.startPrank(admin);

        /* stake tokens and weights */
        SymbioticStaking(symbioticStaking).addStakeToken(pond, _calcShareAmount(SIXTY_PERCENT));
        SymbioticStaking(symbioticStaking).addStakeToken(weth, _calcShareAmount(FORTY_PERCENT));

        /* base transmitter comission rate and submission cooldown */
        SymbioticStaking(symbioticStaking).setBaseTransmitterComissionRate(_calcShareAmount(TWENTY_PERCENT));
        SymbioticStaking(symbioticStaking).setSubmissionCooldown(12 hours);
        vm.stopPrank();

        assertEq(SymbioticStaking(symbioticStaking).baseTransmitterComissionRate(), _calcShareAmount(TWENTY_PERCENT));
        assertEq(SymbioticStaking(symbioticStaking).submissionCooldown(), 12 hours);
    }


    /*===================================== internal pure ======================================*/

    /// @notice convert 100% -> 1e18 (i.e. 50 -> 50e17)
    function _calcShareAmount(uint256 _shareIntPercentage) internal pure returns (uint256) {
        return Math.mulDiv(_shareIntPercentage, 1e18, 100);
    }
}
