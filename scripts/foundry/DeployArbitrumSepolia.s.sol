// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Foundry */
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

/* Contracts */
import {USDC} from "./mocks/USDC.sol";
import {POND} from "./mocks/POND.sol";
import {WETH} from "./mocks/WETH.sol";

import {AttestationVerifier} from "../../contracts/periphery/AttestationVerifier.sol";
import {ProofMarketplace} from "../../contracts/ProofMarketplace.sol";
import {EntityKeyRegistry} from "../../contracts/EntityKeyRegistry.sol";
import {ProverManager} from "../../contracts/ProverManager.sol";
import {StakingManager} from "../../contracts/staking/l2_contracts/StakingManager.sol";
import {NativeStaking} from "../../contracts/staking/l2_contracts/NativeStaking.sol";
import {SymbioticStaking} from "../../contracts/staking/l2_contracts/SymbioticStaking.sol";
import {SymbioticStakingReward} from "../../contracts/staking/l2_contracts/SymbioticStakingReward.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/* Interfaces */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployArbitrumSepolia is Script {
    uint256 public constant INFLATION_REWARD_EPOCH_SIZE = 1 hours; // 60*60 seconds
    uint256 public constant INFLATION_REWARD_PER_EPOCH = 100 ether; // 100 POND
    uint256 public constant SUBMISSION_COOLDOWN = 5 minutes; // snapshot submission cooldown delay
    address public constant ATTESTATION_VERIFIER = 0x63EEf1576b477Aa60Bfd7300B2C85b887639Ac1b;

    uint256 constant public FIFTEEN_PERCENT = 15;
    uint256 constant public TWENTY_PERCENT = 20;
    uint256 constant public THIRTY_PERCENT = 30;
    uint256 constant public FORTY_PERCENT = 40;
    uint256 constant public FIFTY_PERCENT = 50;
    uint256 constant public SIXTY_PERCENT = 60;
    uint256 constant public HUNDRED_PERCENT = 100;

    uint256 admin_key = vm.envUint("ARBITRUM_SEPOLIA_ADMIN_KEY");

    /* Tokens */
    address usdc;
    address pond;
    address weth;

    /* Contract Implementations */
    // address attestationVerifierImpl;
    address proofMarketplaceImpl;
    address entityKeyRegistryImpl;
    address proverManagerImpl;
    address stakingManagerImpl;
    address nativeStakingImpl;
    address symbioticStakingImpl;
    address symbioticStakingRewardImpl;

    /* Proxies */
    // address attestationVerifier;
    address proofMarketplace;
    address entityKeyRegistry;
    address proverManager;
    address stakingManager;
    address nativeStaking;
    address symbioticStaking;
    address symbioticStakingReward;

    // TODO: config for each contracts
    function run() public {
        address admin = 0x7C046645E21B811780Cf420021E6701A9E66935C;
        /* God Enclave PCRS */
        // AttestationVerifier.EnclaveImage[] memory GOD_ENCLAVE = new AttestationVerifier.EnclaveImage[](1);
        // GOD_ENCLAVE[0] = AttestationVerifier.EnclaveImage({
        //     PCR0: bytes(hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000065"),
        //     PCR1: bytes(hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036"),
        //     PCR2: bytes(hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000093")
        // });

        // bytes[] memory GOD_ENCLAVE_KEYS = new bytes[](1);
        // GOD_ENCLAVE_KEYS[0] = bytes(hex"6bf5eaebfb44393f4b39351e8dd7bf49e2adfe0c6b639126783132b871bf164d049b27ad2d0ba4206a0e82be1c4bdfe38f853a99b13361cf7b42b68a4dd4530f");

        vm.startBroadcast(admin_key);

        /* deploy tokens */
        usdc = address(new USDC(admin));
        pond = address(new POND(admin));
        weth = address(new WETH(admin));

        address feeToken = usdc;
        // address inflationRewardToken = pond;

        /* Impls */
        stakingManagerImpl = address(new StakingManager());
        nativeStakingImpl = address(new NativeStaking());
        symbioticStakingImpl = address(new SymbioticStaking());
        symbioticStakingRewardImpl = address(new SymbioticStakingReward());

        /* Proxies  */
        stakingManager = address(new ERC1967Proxy(stakingManagerImpl, ""));
        nativeStaking = address(new ERC1967Proxy(nativeStakingImpl, ""));
        symbioticStaking = address(new ERC1967Proxy(symbioticStakingImpl, ""));
        symbioticStakingReward = address(new ERC1967Proxy(symbioticStakingRewardImpl, ""));

        // AttestationVerifier
        // attestationVerifierImpl = address(new AttestationVerifier());
        // attestationVerifier = address(new ERC1967Proxy(attestationVerifierImpl, ""));

        // EntityKeyRegistry
        entityKeyRegistryImpl = address(new EntityKeyRegistry(AttestationVerifier(ATTESTATION_VERIFIER)));
        entityKeyRegistry = address(new ERC1967Proxy(entityKeyRegistryImpl, ""));

        // ProverManager
        proverManagerImpl = address(new ProverManager(EntityKeyRegistry(entityKeyRegistry)));
        proverManager = address(new ERC1967Proxy(proverManagerImpl, ""));

        // ProofMarketplace
        proofMarketplaceImpl = address(
            new ProofMarketplace(
                IERC20(usdc),
                100 ether,
                admin,
                ProverManager(proverManager),
                EntityKeyRegistry(entityKeyRegistry)
            )
        );
        proofMarketplace = address(new ERC1967Proxy(proofMarketplaceImpl, ""));

        /* initialize */

        // ProofMarketplace
        ProofMarketplace(address(proofMarketplace)).initialize(admin);

        // ATTESTATION_VERIFIER
        // AttestationVerifier(address(attestationVerifier)).initialize(GOD_ENCLAVE, GOD_ENCLAVE_KEYS, admin);

        // EntityKeyRegistry
        EntityKeyRegistry.EnclaveImage[] memory initWhitelistImages;
        EntityKeyRegistry(address(entityKeyRegistry)).initialize(admin, initWhitelistImages);

        // ProverManager
        ProverManager(address(proverManager)).initialize(admin, proofMarketplace, stakingManager);

        // StakingManager
        StakingManager(address(stakingManager)).initialize(
            admin, address(proofMarketplace), address(symbioticStaking), address(feeToken)
        );

        // NativeStaking
        NativeStaking(address(nativeStaking)).initialize(
            admin,
            address(stakingManager),
            2 days, // withdrawalDuration
            address(feeToken)
        );

        // SymbioticStaking
        // SymbioticStaking(address(symbioticStaking)).initialize(
        //     admin, address(proofMarketplace), address(symbioticStaking), address(symbioticStakingReward), feeToken
        // );

        // SymbioticStakingReward
        SymbioticStakingReward(address(symbioticStakingReward)).initialize(
            admin, address(proofMarketplace), address(symbioticStaking), feeToken
        );

        // Grant `PROVER_MANAGER_ROLE` to StakingManager
        StakingManager(address(stakingManager)).grantRole(
            StakingManager(address(stakingManager)).PROVER_MANAGER_ROLE(), address(proverManager)
        );

        // Grant `KEY_REGISTER_ROLE` to ProverManager, ProofMarketplace
        bytes32 register_role = EntityKeyRegistry(address(entityKeyRegistry)).KEY_REGISTER_ROLE();
        EntityKeyRegistry(address(entityKeyRegistry)).grantRole(register_role, address(proverManager));
        EntityKeyRegistry(address(entityKeyRegistry)).grantRole(register_role, address(proofMarketplace));

        // Grant `UPDATER_ROLE` to admin
        ProofMarketplace(address(proofMarketplace)).grantRole(ProofMarketplace(address(proofMarketplace)).UPDATER_ROLE(), admin);


        /*==================== Config & Setup ====================*/

        /*-------------------------------- StakingManager Config --------------------------------*/
        // Add NativeStaking, SymbioticStaking
        StakingManager(stakingManager).addStakingPool(nativeStaking);
        StakingManager(stakingManager).addStakingPool(symbioticStaking);

        // Set reward shares
        address[] memory pools = new address[](2);
        pools[0] = nativeStaking;
        pools[1] = symbioticStaking;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 0;
        shares[1] = _calculatePercent(HUNDRED_PERCENT);
        StakingManager(stakingManager).setPoolRewardShare(pools, shares);

        // Enable pools 
        StakingManager(stakingManager).setEnabledPool(nativeStaking, true);
        StakingManager(stakingManager).setEnabledPool(symbioticStaking, true);

        /*-------------------------------- NativeStaking Config --------------------------------*/
        NativeStaking(nativeStaking).addStakeToken(pond, _calculatePercent(HUNDRED_PERCENT));
        NativeStaking(nativeStaking).setAmountToLock(pond, 1 ether);
        console.log("Native Staking: AmountToLock per job: 1 POND");
        console.log("");

        /*-------------------------------- SymbioticStaking Config --------------------------------*/
        SymbioticStaking(symbioticStaking).addStakeToken(pond, _calculatePercent(SIXTY_PERCENT));
        console.log("Symbiotic Staking: POND selection weight: 60%");
        SymbioticStaking(symbioticStaking).addStakeToken(weth, _calculatePercent(FORTY_PERCENT));
        console.log("Symbiotic Staking: WETH selection weight: 40%");
        /* amount to lock */
        SymbioticStaking(symbioticStaking).setAmountToLock(pond, 2 ether);
        console.log("Symbiotic Staking: POND amount to lock (per job): 2 POND");
        SymbioticStaking(symbioticStaking).setAmountToLock(weth, 2 ether);
        console.log("Symbiotic Staking: WETH amount to lock (per job): 2 WETH");
        SymbioticStaking(symbioticStaking).setBaseTransmitterComissionRate(_calculatePercent(TWENTY_PERCENT));
        console.log("Symbiotic Staking: Base Transmitter Comission Rate: 20%");    
        SymbioticStaking(symbioticStaking).setSubmissionCooldown(SUBMISSION_COOLDOWN);
        console.log("Symbiotic Staking: Submission Cooldown: 5 minutes");
        console.log("");

        vm.stopBroadcast();

        console.log("admin: \t\t\t", admin);
        console.log("ATTESTATION_VERIFIER: \t", ATTESTATION_VERIFIER);
        console.log("");

        console.log("< Impls Deployed >\n");
        // console.log("attestationVerifierImpl: \t", address(attestationVerifierImpl));
        console.log("entityKeyRegistryImpl: \t", address(entityKeyRegistryImpl));
        console.log("proverManagerImpl: \t", address(proverManagerImpl));
        console.log("stakingManagerImpl: \t\t", address(stakingManagerImpl));
        console.log("nativeStakingImpl: \t\t", address(nativeStakingImpl));
        console.log("symbioticStakingImpl: \t", address(symbioticStakingImpl));
        console.log("symbioticStakingRewardImpl: \t", address(symbioticStakingRewardImpl));
        console.log("");

        console.log("< Proxies Deployed >\n");

        console.log("proofMarketplace: \t\t", address(proofMarketplace));
        // console.log("attestationVerifier: \t\t", address(attestationVerifier));
        console.log("entityKeyRegistry: \t\t", address(entityKeyRegistry));
        console.log("proverManager: \t\t", address(proverManager));
        console.log("stakingManager: \t\t", address(stakingManager));
        console.log("nativeStaking: \t\t", address(nativeStaking));
        console.log("symbioticStaking: \t\t", address(symbioticStaking));
        console.log("symbioticStakingReward: \t", address(symbioticStakingReward));
        console.log("");

        console.log("< Tokens >\n");

        console.log("USDC (feeToken): \t\t", usdc);
        console.log("POND: \t\t\t", pond);
        console.log("WETH: \t\t\t", weth);
    }

    function _calculatePercent(uint256 percent) internal pure returns (uint256) {
        return Math.mulDiv(percent, 1e18, 100);
    }
}
