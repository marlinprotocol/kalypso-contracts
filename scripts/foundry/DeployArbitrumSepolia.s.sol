// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Foundry */
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

/* Contracts */
import {USDC} from "./mocks/USDC.sol";
import {POND} from "./mocks/POND.sol";
import {WETH} from "./mocks/WETH.sol";
import {JobManager} from "../../contracts/staking/l2_contracts/JobManager.sol";
import {StakingManager} from "../../contracts/staking/l2_contracts/StakingManager.sol";
import {NativeStaking} from "../../contracts/staking/l2_contracts/NativeStaking.sol";
import {SymbioticStaking} from "../../contracts/staking/l2_contracts/SymbioticStaking.sol";
import {SymbioticStakingReward} from "../../contracts/staking/l2_contracts/SymbioticStakingReward.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* Interfaces */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployArbitrumSepolia is Script {

    uint256 constant public INFLATION_REWARD_EPOCH_SIZE = 1 hours; // 60*60 seconds
    uint256 constant public INFLATION_REWARD_PER_EPOCH = 100 ether; // 100 POND
    uint256 constant public SUBMISSION_COOLDOWN = 12 hours; // snapshot submission cooldown delay
    
    uint256 admin_key = vm.envUint("ARBITRUM_SEPOLIA_ADMIN_KEY");

    function run() public {
        address admin = 0x7C046645E21B811780Cf420021E6701A9E66935C;

        vm.startBroadcast(admin_key);

        /* deploy tokens */
        address usdc = address(new USDC(admin));
        address pond = address(new POND(admin));
        address weth = address(new WETH(admin));

        address feeToken = usdc;
        address inflationRewardToken = pond;
        
        /* contract implementations */
        address jobManager = address(new JobManager());
        address stakingManager = address(new StakingManager());
        address nativeStaking = address(new NativeStaking());
        address symbioticStaking = address(new SymbioticStaking());
        address symbioticStakingReward = address(new SymbioticStakingReward());

        /* deploy proxies  */
        jobManager = address(new ERC1967Proxy(jobManager, ""));
        stakingManager = address(new ERC1967Proxy(stakingManager, ""));
        nativeStaking = address(new ERC1967Proxy(nativeStaking, ""));
        symbioticStaking = address(new ERC1967Proxy(symbioticStaking, ""));
        symbioticStakingReward = address(new ERC1967Proxy(symbioticStakingReward, ""));

        /* initialize contracts */
        
        // JobManager
        JobManager(address(jobManager)).initialize(
            admin, address(stakingManager), address(symbioticStaking), address(symbioticStakingReward), address(feeToken), 1 hours
        );

        // StakingManager
        StakingManager(address(stakingManager)).initialize(
            admin,
            address(jobManager),
            address(symbioticStaking),
            address(feeToken)
        );

        // NativeStaking
        NativeStaking(address(nativeStaking)).initialize(
            admin,
            address(stakingManager),
            2 days, // withdrawalDuration
            address(feeToken)
        );
    
        // SymbioticStaking
        SymbioticStaking(address(symbioticStaking)).initialize(
            admin,
            jobManager,
            stakingManager,
            symbioticStakingReward,
            feeToken
        );

        // SymbioticStakingReward
        SymbioticStakingReward(address(symbioticStakingReward)).initialize(
            admin,
            jobManager,
            symbioticStaking,
            feeToken
        );

        vm.stopBroadcast();

        console.log("admin: ", admin);
        console.log("");

        console.log("< Proxies Deployed >\n");

        console.log("jobManager: \t\t\t", address(jobManager));
        console.log("stakingManager: \t\t", address(stakingManager));
        console.log("nativeStaking: \t\t", address(nativeStaking));
        console.log("symbioticStaking: \t\t", address(symbioticStaking));
        console.log("symbioticStakingReward: \t", address(symbioticStakingReward));
        console.log("");

        console.log("USDC (feeToken): \t\t", usdc);
        console.log("POND (inflationRewardToken): \t", pond);
        console.log("WETH: \t\t\t", weth);
    }
}