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

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* interfaces */
import {IJobManager} from "../../contracts/interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../contracts/interfaces/staking/IStakingManager.sol";
import {INativeStaking} from "../../contracts/interfaces/staking/INativeStaking.sol";
import {ISymbioticStaking} from "../../contracts/interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../contracts/interfaces/staking/ISymbioticStakingReward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* libraries */
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestSetup is Test {
    uint256 constant public FIFTEEN_PERCENT = 15;
    uint256 constant public TWENTY_PERCENT = 20;
    uint256 constant public THIRTY_PERCENT = 30;
    uint256 constant public FORTY_PERCENT = 40;
    uint256 constant public FIFTY_PERCENT = 50;
    uint256 constant public SIXTY_PERCENT = 60;
    uint256 constant public HUNDRED_PERCENT = 100;

    uint256 constant public FUND_FOR_GAS = 10 ether; // 10 ether
    uint256 constant public FUND_FOR_FEE = 10_000 ether; // 10,000 USDC
    uint256 constant public FUND_FOR_SELF_STAKE = 1000_000 ether; // 10,000 POND
    uint256 constant public FUND_FOR_INFLATION_REWARD = 100_000 ether; // 100,000 POND

    // uint256 constant public INFLATION_REWARD_EPOCH_SIZE = 30 minutes; // 30 minutes
    // uint256 constant public INFLATION_REWARD_PER_EPOCH = 100 ether; // 1,000 POND

    uint256 constant public SUBMISSION_COOLDOWN = 12 hours;

    uint256 constant public USDC_DECIMALS = 1e6;


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
    address public inflationRewardVault; // holds inflation reward tokens

    /* operators */
    address public operatorA;
    address public operatorB;
    address public operatorC;

    /* symbiotic vaults */
    address public symbioticVaultA;
    address public symbioticVaultB; 
    address public symbioticVaultC;
    address public symbioticVaultD;
    address public symbioticVaultE;

    /* transmitters */
    address public transmitterA;
    address public transmitterB;
    address public transmitterC;

    /* stakers */
    address public stakerA;
    address public stakerB;
    address public stakerC;

    /* slasher */
    address public slasher;

    /* job requesters */
    address public jobRequesterA;
    address public jobRequesterB;
    address public jobRequesterC;
    

    function _setupAddr() internal {
        /* set address */
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        inflationRewardVault = makeAddr("inflationRewardVault");
        
        slasher = makeAddr("slasher");

        stakerA = makeAddr("stakerA");
        stakerB = makeAddr("stakerB");
        stakerC = makeAddr("stakerC");

        operatorA = makeAddr("operatorA");
        operatorB = makeAddr("operatorB");
        operatorC = makeAddr("operatorC");

        symbioticVaultA = makeAddr("symbioticVaultA");
        symbioticVaultB = makeAddr("symbioticVaultB");
        symbioticVaultC = makeAddr("symbioticVaultC");
        symbioticVaultD = makeAddr("symbioticVaultD");
        symbioticVaultE = makeAddr("symbioticVaultE");

        transmitterA = makeAddr("transmitterA");
        transmitterB = makeAddr("transmitterB");
        transmitterC = makeAddr("transmitterC");

        jobRequesterA = makeAddr("jobRequesterA");
        jobRequesterB = makeAddr("jobRequesterB");
        jobRequesterC = makeAddr("jobRequesterC");

        /* fund gas */
        vm.deal(deployer, FUND_FOR_GAS);
        vm.deal(admin, FUND_FOR_GAS);
        vm.deal(inflationRewardVault, FUND_FOR_GAS);

        vm.deal(operatorA, FUND_FOR_GAS);
        vm.deal(operatorB, FUND_FOR_GAS);
        vm.deal(operatorC, FUND_FOR_GAS);
        vm.deal(slasher, FUND_FOR_GAS);

        vm.deal(stakerA, FUND_FOR_GAS);
        vm.deal(stakerB, FUND_FOR_GAS);
        vm.deal(stakerC, FUND_FOR_GAS);

        vm.deal(transmitterA, FUND_FOR_GAS);
        vm.deal(transmitterB, FUND_FOR_GAS);
        vm.deal(transmitterC, FUND_FOR_GAS);

        vm.deal(jobRequesterA, FUND_FOR_GAS);
        vm.deal(jobRequesterB, FUND_FOR_GAS);
        vm.deal(jobRequesterC, FUND_FOR_GAS);

        /* label */
        vm.label(deployer, "deployer");
        vm.label(admin, "admin");
        vm.label(slasher, "slasher");

        vm.label(operatorA, "operatorA");
        vm.label(operatorB, "operatorB");
        vm.label(operatorC, "operatorC");

        vm.label(stakerA, "stakerA");
        vm.label(stakerB, "stakerB");
        vm.label(stakerC, "stakerC");

        vm.label(symbioticVaultA, "symbioticVaultA");
        vm.label(symbioticVaultB, "symbioticVaultB");
        vm.label(symbioticVaultC, "symbioticVaultC");
        vm.label(symbioticVaultD, "symbioticVaultD");
        vm.label(symbioticVaultE, "symbioticVaultE");

        vm.label(jobRequesterA, "jobRequesterA");
        vm.label(jobRequesterB, "jobRequesterB");
        vm.label(jobRequesterC, "jobRequesterC");

        vm.label(transmitterA, "transmitterA");
        vm.label(transmitterB, "transmitterB");
        vm.label(transmitterC, "transmitterC");
    }

    /*======================================== internal ========================================*/

    function _setupContracts() internal {
        _deployContracts();
        _initializeContracts();
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // FeeToken
        usdc = address(new USDC(admin));
        feeToken = usdc;

        // InflationRewardToken
        pond = address(new POND(admin));
        inflationRewardToken = pond;

        // stakeToken
        weth = address(new WETH(admin));
        pond = inflationRewardToken;

        // contract implementations
        address jobManagerImpl = address(new JobManager());
        address stakingManagerImpl = address(new StakingManager());
        address nativeStakingImpl = address(new NativeStaking());
        address symbioticStakingImpl = address(new SymbioticStaking());
        address symbioticStakingRewardImpl = address(new SymbioticStakingReward());

        // deploy proxies   
        jobManager = address(new ERC1967Proxy(jobManagerImpl, ""));
        stakingManager = address(new ERC1967Proxy(stakingManagerImpl, ""));
        nativeStaking = address(new ERC1967Proxy(nativeStakingImpl, ""));
        symbioticStaking = address(new ERC1967Proxy(symbioticStakingImpl, ""));
        symbioticStakingReward = address(new ERC1967Proxy(symbioticStakingRewardImpl, ""));
        // inflationRewardManager = address(new ERC1967Proxy(inflationRewardManagerImpl, ""));
        vm.stopPrank();

        /* label */
        vm.label(address(jobManager), "JobManager");
        vm.label(address(stakingManager), "StakingManager");
        vm.label(address(nativeStaking), "NativeStaking");
        vm.label(address(symbioticStaking), "SymbioticStaking");
        vm.label(address(symbioticStakingReward), "SymbioticStakingReward");
        // vm.label(address(inflationRewardManager), "InflationRewardManager");
    }

    function _initializeContracts() internal {
        vm.startPrank(admin);   

        // JobManager
        JobManager(address(jobManager)).initialize(
            admin, address(stakingManager), address(symbioticStaking), address(symbioticStakingReward), address(feeToken),  1 hours
        );
        assertEq(JobManager(jobManager).hasRole(JobManager(jobManager).DEFAULT_ADMIN_ROLE(), admin), true); 

        // StakingManager
        StakingManager(address(stakingManager)).initialize(
            admin,
            address(jobManager),
            address(symbioticStaking),
            address(feeToken)
        );
        assertEq(StakingManager(stakingManager).hasRole(StakingManager(stakingManager).DEFAULT_ADMIN_ROLE(), admin), true); 

        // NativeStaking
        NativeStaking(address(nativeStaking)).initialize(
            admin,
            address(stakingManager),
            2 days, // withdrawalDuration
            address(feeToken)
        );
        assertEq(NativeStaking(nativeStaking).hasRole(NativeStaking(nativeStaking).DEFAULT_ADMIN_ROLE(), admin), true); 
    
        // SymbioticStaking
        SymbioticStaking(address(symbioticStaking)).initialize(
            admin,
            jobManager,
            stakingManager,
            symbioticStakingReward,
            feeToken
        );
        assertEq(SymbioticStaking(symbioticStaking).hasRole(SymbioticStaking(symbioticStaking).DEFAULT_ADMIN_ROLE(), admin), true); 
        // SymbioticStakingReward
        SymbioticStakingReward(address(symbioticStakingReward)).initialize(
            admin,
            jobManager,
            symbioticStaking,
            feeToken
        );
        assertEq(SymbioticStakingReward(symbioticStakingReward).hasRole(SymbioticStakingReward(symbioticStakingReward).DEFAULT_ADMIN_ROLE(), admin), true); 

        // InflationRewardManager
        // InflationRewardManager(address(inflationRewardManager)).initialize(
        //     admin,
        //     block.timestamp,
        //     jobManager,
        //     stakingManager,
        //     symbioticStaking,
        //     symbioticStakingReward,
        //     inflationRewardToken,
        //     INFLATION_REWARD_EPOCH_SIZE, // inflationRewardEpochSize
        //     INFLATION_REWARD_PER_EPOCH // inflationRewardPerEpoch
        // );
        // assertEq(InflationRewardManager(inflationRewardManager).hasRole(InflationRewardManager(inflationRewardManager).DEFAULT_ADMIN_ROLE(), admin), true); 
        vm.stopPrank();
    }

    function _setJobManagerConfig() internal {
        vm.startPrank(admin);
        // operatorA: 30% of the reward as comission
        JobManager(jobManager).setOperatorRewardShare(operatorA, _calcShareAmount(THIRTY_PERCENT));
        // operatorB: 50% of the reward as comission
        JobManager(jobManager).setOperatorRewardShare(operatorB, _calcShareAmount(FIFTY_PERCENT));
        // operatorB: 15% of the reward as comission
        JobManager(jobManager).setOperatorRewardShare(operatorC, _calcShareAmount(FIFTEEN_PERCENT));
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
        NativeStaking(nativeStaking).addStakeToken(pond, _calcShareAmount(HUNDRED_PERCENT));
        NativeStaking(nativeStaking).setAmountToLock(pond, 1 ether);
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

        /* amount to lock */
        SymbioticStaking(symbioticStaking).setAmountToLock(pond, 0.2 ether);
        SymbioticStaking(symbioticStaking).setAmountToLock(weth, 0.2 ether);

        vm.stopPrank();

        assertEq(SymbioticStaking(symbioticStaking).baseTransmitterComissionRate(), _calcShareAmount(TWENTY_PERCENT));
        assertEq(SymbioticStaking(symbioticStaking).submissionCooldown(), SUBMISSION_COOLDOWN);
    }

    function _fund_tokens() internal {
        deal(pond, operatorA, FUND_FOR_SELF_STAKE);
        deal(pond, operatorB, FUND_FOR_SELF_STAKE);
        deal(pond, operatorC, FUND_FOR_SELF_STAKE);

        deal(usdc, jobRequesterA, FUND_FOR_FEE);
        deal(usdc, jobRequesterB, FUND_FOR_FEE);
        deal(usdc, jobRequesterC, FUND_FOR_FEE);

        deal(inflationRewardToken, inflationRewardManager, FUND_FOR_INFLATION_REWARD);
    }


    /*===================================== internal pure ======================================*/

    /// @notice convert 100% -> 1e18 (i.e. 50 -> 50e17)
    function _calcShareAmount(uint256 _shareIntPercentage) internal pure returns (uint256) {
        return Math.mulDiv(_shareIntPercentage, 1e18, 100);
    }
}
