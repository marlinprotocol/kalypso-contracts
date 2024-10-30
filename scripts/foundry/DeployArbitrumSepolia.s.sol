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
import {GeneratorRegistry} from "../../contracts/GeneratorRegistry.sol";
import {StakingManager} from "../../contracts/staking/l2_contracts/StakingManager.sol";
import {NativeStaking} from "../../contracts/staking/l2_contracts/NativeStaking.sol";
import {SymbioticStaking} from "../../contracts/staking/l2_contracts/SymbioticStaking.sol";
import {SymbioticStakingReward} from "../../contracts/staking/l2_contracts/SymbioticStakingReward.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* Interfaces */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployArbitrumSepolia is Script {
    uint256 public constant INFLATION_REWARD_EPOCH_SIZE = 1 hours; // 60*60 seconds
    uint256 public constant INFLATION_REWARD_PER_EPOCH = 100 ether; // 100 POND
    uint256 public constant SUBMISSION_COOLDOWN = 12 hours; // snapshot submission cooldown delay

    uint256 admin_key = vm.envUint("ARBITRUM_SEPOLIA_ADMIN_KEY");

    /* Tokens */
    address usdc;
    address pond;
    address weth;

    /* Contract Implementations */
    address attestationVerifierImpl;
    address proofMarketplaceImpl;
    address entityKeyRegistryImpl;
    address generatorRegistryImpl;
    address stakingManagerImpl;
    address nativeStakingImpl;
    address symbioticStakingImpl;
    address symbioticStakingRewardImpl;

    /* Proxies */
    address attestationVerifier;
    address proofMarketplace;
    address entityKeyRegistry;
    address generatorRegistry;
    address stakingManager;
    address nativeStaking;
    address symbioticStaking;
    address symbioticStakingReward;

    // TODO: config for each contracts
    function run() public {
        address admin = 0x7C046645E21B811780Cf420021E6701A9E66935C;
        /* God Enclave PCRS */
        AttestationVerifier.EnclaveImage[] memory GOD_ENCLAVE = new AttestationVerifier.EnclaveImage[](1);
        GOD_ENCLAVE[0] = AttestationVerifier.EnclaveImage({
            PCR0: bytes(hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000065"),
            PCR1: bytes(hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036"),
            PCR2: bytes(hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000093")
        });

        bytes[] memory GOD_ENCLAVE_KEYS = new bytes[](1);
        GOD_ENCLAVE_KEYS[0] = bytes(hex"6bf5eaebfb44393f4b39351e8dd7bf49e2adfe0c6b639126783132b871bf164d049b27ad2d0ba4206a0e82be1c4bdfe38f853a99b13361cf7b42b68a4dd4530f");

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
        attestationVerifierImpl = address(new AttestationVerifier());
        attestationVerifier = address(new ERC1967Proxy(attestationVerifierImpl, ""));

        // EntityKeyRegistry
        entityKeyRegistryImpl = address(new EntityKeyRegistry(AttestationVerifier(attestationVerifier)));
        entityKeyRegistry = address(new ERC1967Proxy(entityKeyRegistryImpl, ""));

        // GeneratorRegistry
        generatorRegistryImpl = address(new GeneratorRegistry(EntityKeyRegistry(entityKeyRegistry)));
        generatorRegistry = address(new ERC1967Proxy(generatorRegistryImpl, ""));

        // ProofMarketplace
        proofMarketplaceImpl = address(
            new ProofMarketplace(
                IERC20(usdc),
                100 ether,
                admin,
                GeneratorRegistry(generatorRegistry),
                EntityKeyRegistry(entityKeyRegistry)
            )
        );
        proofMarketplace = address(new ERC1967Proxy(proofMarketplaceImpl, ""));

        /* initialize */

        // ProofMarketplace
        ProofMarketplace(address(proofMarketplace)).initialize(admin);

        // AttestationVerifier
        AttestationVerifier(address(attestationVerifier)).initialize(GOD_ENCLAVE, GOD_ENCLAVE_KEYS, admin);

        // EntityKeyRegistry
        EntityKeyRegistry.EnclaveImage[] memory initWhitelistImages;
        EntityKeyRegistry(address(entityKeyRegistry)).initialize(admin, initWhitelistImages);

        // GeneratorRegistry
        GeneratorRegistry(address(generatorRegistry)).initialize(admin, proofMarketplace, stakingManager);

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
        SymbioticStaking(address(symbioticStaking)).initialize(
            admin, address(proofMarketplace), address(symbioticStaking), address(symbioticStakingReward), feeToken
        );

        // SymbioticStakingReward
        SymbioticStakingReward(address(symbioticStakingReward)).initialize(
            admin, address(proofMarketplace), address(symbioticStaking), feeToken
        );

        // Grant `GENERATOR_REGISTRY_ROLE` to StakingManager
        StakingManager(address(stakingManager)).grantRole(
            StakingManager(address(stakingManager)).GENERATOR_REGISTRY_ROLE(), address(generatorRegistry)
        );

        // Grant `KEY_REGISTER_ROLE` to GeneratorRegistry, ProofMarketplace
        bytes32 register_role = EntityKeyRegistry(address(entityKeyRegistry)).KEY_REGISTER_ROLE();
        EntityKeyRegistry(address(entityKeyRegistry)).grantRole(register_role, address(generatorRegistry));
        EntityKeyRegistry(address(entityKeyRegistry)).grantRole(register_role, address(proofMarketplace));

        // Grant `UPDATER_ROLE` to admin
        ProofMarketplace(address(proofMarketplace)).grantRole(ProofMarketplace(address(proofMarketplace)).UPDATER_ROLE(), admin);
        vm.stopBroadcast();

        console.log("admin: ", admin);
        console.log("");

        console.log("< Impls Deployed >\n");
        console.log("attestationVerifierImpl: \t", address(attestationVerifierImpl));
        console.log("entityKeyRegistryImpl: \t", address(entityKeyRegistryImpl));
        console.log("generatorRegistryImpl: \t", address(generatorRegistryImpl));
        console.log("stakingManagerImpl: \t\t", address(stakingManagerImpl));
        console.log("nativeStakingImpl: \t\t", address(nativeStakingImpl));
        console.log("symbioticStakingImpl: \t", address(symbioticStakingImpl));
        console.log("symbioticStakingRewardImpl: \t", address(symbioticStakingRewardImpl));
        console.log("");

        console.log("< Proxies Deployed >\n");

        console.log("proofMarketplace: \t\t", address(proofMarketplace));
        console.log("attestationVerifier: \t\t", address(attestationVerifier));
        console.log("entityKeyRegistry: \t\t", address(entityKeyRegistry));
        console.log("generatorRegistry: \t\t", address(generatorRegistry));
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
}
