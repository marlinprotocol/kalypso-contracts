// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./GeneratorRegistry.sol";
import "./EntityKeyRegistry.sol";
import "./interfaces/IVerifier.sol";
import "./interfaces/IAttestationVerifier.sol";

import "./lib/Error.sol";
import "./lib/Helper.sol";

contract ProofMarketPlace is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable,
    HELPER
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, AccessControlUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._grantRole(role, account);
    }

    function grantRole(
        bytes32 role,
        address account
    ) public virtual override(AccessControlUpgradeable, IAccessControlUpgradeable) {
        require(role != MATCHING_ENGINE_ROLE, Error.CANNOT_USE_MATCHING_ENGINE_ROLE);
        _grantRole(role, account);
    }

    function updateMatchingEngineEncryptionKeyAndSigner(bytes memory attestationData) public {
        (bytes memory pubkey, address meSigner) = HELPER.getPubkeyAndAddress(attestationData);
        _grantRole(MATCHING_ENGINE_ROLE, meSigner);
        ENTITY_KEY_REGISTRY.updatePubkey(address(this), pubkey, attestationData);
    }

    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, Error.CANNOT_BE_ADMIN_LESS);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Constants and Immutable start --------------------------------//
    bytes32 public constant MATCHING_ENGINE_ROLE = keccak256("MATCHING_ENGINE_ROLE");

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable PAYMENT_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable PLATFORM_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable MARKET_CREATION_COST;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable TREASURY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    GeneratorRegistry public immutable GENERATOR_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IAttestationVerifier public immutable ATTESTATION_VERIFIER;

    uint256 public constant MARKET_ACTIVATION_DELAY = 100; // in blocks

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    uint256 public marketCounter;
    mapping(uint256 => Market) public marketData;

    AskWithState[] public listOfAsk;

    mapping(SecretType => uint256) public costPerInputBytes;

    struct Market {
        address verifier; // verifier address for the market place
        bool isEnclaveRequired;
        uint256 slashingPenalty;
        uint256 activationBlock;
        address ivsSigner;
        bytes ivsUrl;
        bytes marketmetadata;
    }

    enum AskState {
        NULL,
        CREATE,
        UNASSIGNED,
        ASSIGNED,
        COMPLETE,
        DEADLINE_CROSSED
    }

    enum SecretType {
        NULL,
        CALLDATA,
        EXTERNAL
    }

    struct Ask {
        uint256 marketId;
        uint256 reward;
        // the block number by which the ask should be assigned by matching engine
        uint256 expiry;
        uint256 timeTakenForProofGeneration;
        uint256 deadline;
        address refundAddress;
        bytes proverData;
    }

    struct AskWithState {
        Ask ask;
        AskState state;
        address requester;
        address generator;
    }

    //-------------------------------- State variables end --------------------------------//

    //-------------------------------- Events start --------------------------------//

    event AskCreated(uint256 indexed askId, bool indexed hasPrivateInputs, bytes secret_data, bytes acl);
    event TaskCreated(uint256 indexed askId, address indexed generator, bytes new_acl);
    // TODO: add ask ID also
    event ProofCreated(uint256 indexed askId, bytes proof);
    event ProofNotGenerated(uint256 indexed askId);

    event InvalidInputsDetected(uint256 indexed askId);

    event MarketPlaceCreated(uint256 indexed marketId);

    event AskCancelled(uint256 indexed askId);

    event UpdateCostPerBytes(SecretType indexed secretType, uint256 costPerInputBytes);

    //-------------------------------- Events end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IERC20Upgradeable _paymentToken,
        IERC20Upgradeable _platformToken,
        uint256 _marketCreationCost,
        address _treasury,
        GeneratorRegistry _generatorRegistry,
        EntityKeyRegistry _entityRegistry,
        IAttestationVerifier _attestationVerifier
    ) {
        PAYMENT_TOKEN = _paymentToken;
        PLATFORM_TOKEN = _platformToken;
        MARKET_CREATION_COST = _marketCreationCost;
        TREASURY = _treasury;
        GENERATOR_REGISTRY = _generatorRegistry;
        ENTITY_KEY_REGISTRY = _entityRegistry;
        ATTESTATION_VERIFIER = _attestationVerifier;
    }

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(MATCHING_ENGINE_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(UPDATER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function createMarketPlace(
        bytes calldata _marketmetadata,
        address _verifier,
        uint256 _slashingPenalty,
        bool isEnclaveRequired,
        bytes calldata ivsAttestationBytes,
        bytes calldata ivsUrl
    ) external {
        require(_slashingPenalty != 0, Error.CANNOT_BE_ZERO); // this also the amount, which will be locked for a generator when task is assigned
        require(_marketmetadata.length != 0, Error.CANNOT_BE_ZERO);

        Market storage market = marketData[marketCounter];
        require(market.marketmetadata.length == 0, Error.MARKET_ALREADY_EXISTS);
        require(_verifier != address(0), Error.CANNOT_BE_ZERO);
        require(IVerifier(_verifier).checkSampleInputsAndProof(), Error.INVALID_INPUTS);
        require(ATTESTATION_VERIFIER.verify(ivsAttestationBytes), Error.ENCLAVE_KEY_NOT_VERIFIED);

        (bytes memory ivsPubkey, address ivsSigner) = HELPER.getPubkeyAndAddress(ivsAttestationBytes);

        market.verifier = _verifier;
        market.slashingPenalty = _slashingPenalty;
        market.marketmetadata = _marketmetadata;
        market.isEnclaveRequired = isEnclaveRequired;
        market.activationBlock = block.number + MARKET_ACTIVATION_DELAY;
        market.ivsUrl = ivsUrl;
        market.ivsSigner = ivsSigner;

        ENTITY_KEY_REGISTRY.updatePubkey(ivsSigner, ivsPubkey, ivsAttestationBytes);
        PAYMENT_TOKEN.safeTransferFrom(_msgSender(), TREASURY, MARKET_CREATION_COST);

        emit MarketPlaceCreated(marketCounter);
        marketCounter++;
    }

    function createAsk(
        Ask calldata ask,
        // TODO: Check if this needs to be removed during review
        SecretType secretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) external {
        _createAsk(ask, msg.sender, secretType, secret_inputs, acl);
    }

    function _createAsk(
        Ask calldata ask,
        address payFrom,
        SecretType secretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) internal {
        require(ask.reward != 0, Error.CANNOT_BE_ZERO);
        require(ask.proverData.length != 0, Error.CANNOT_BE_ZERO);
        require(ask.expiry > block.number, Error.CAN_NOT_ASSIGN_EXPIRED_TASKS);

        Market memory market = marketData[ask.marketId];
        require(block.number > market.activationBlock, Error.INACTIVE_MARKET);

        uint256 platformFee = getPlatformFee(secretType, ask, secret_inputs, acl);
        if (platformFee != 0) {
            PLATFORM_TOKEN.safeTransferFrom(payFrom, TREASURY, platformFee);
        }

        PAYMENT_TOKEN.safeTransferFrom(payFrom, address(this), ask.reward);

        require(market.marketmetadata.length != 0, Error.INVALID_MARKET);

        uint256 askId = listOfAsk.length;
        AskWithState memory askRequest = AskWithState(ask, AskState.CREATE, msg.sender, address(0));
        listOfAsk.push(askRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);
        require(inputVerifier.verifyInputs(ask.proverData), Error.INVALID_INPUTS);

        emit AskCreated(askId, market.isEnclaveRequired, secret_inputs, acl);
    }

    function getPlatformFee(
        SecretType secretType,
        Ask calldata ask,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) public view returns (uint256) {
        uint256 costperByte = costPerInputBytes[secretType];
        if (costperByte != 0) {
            return (ask.proverData.length + secret_inputs.length + acl.length) * costperByte;
        }
        return 0;
    }

    function updateCostPerBytes(SecretType secretType, uint256 costPerByte) public onlyRole(UPDATER_ROLE) {
        costPerInputBytes[secretType] = costPerByte;

        emit UpdateCostPerBytes(secretType, costPerByte);
    }

    // Todo: Optimise the function
    function getAskState(uint256 askId) public view returns (AskState) {
        AskWithState memory askWithState = listOfAsk[askId];

        // time before which matching engine should assign the task to generator
        if (askWithState.state == AskState.CREATE) {
            if (askWithState.ask.expiry > block.number) {
                return askWithState.state;
            }

            return AskState.UNASSIGNED;
        }

        // time before which generator should submit the proof
        if (askWithState.state == AskState.ASSIGNED) {
            if (askWithState.ask.deadline < block.number) {
                return AskState.DEADLINE_CROSSED;
            }

            return AskState.ASSIGNED;
        }

        return askWithState.state;
    }

    function relayBatchAssignTasks(
        uint256[] memory askIds,
        address[] memory generators,
        bytes[] calldata new_acls,
        bytes calldata signature
    ) external {
        require(askIds.length == generators.length, Error.ARITY_MISMATCH);
        require(askIds.length == new_acls.length, Error.ARITY_MISMATCH);

        bytes32 messageHash = keccak256(abi.encode(askIds, generators, new_acls));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        require(hasRole(MATCHING_ENGINE_ROLE, signer), Error.ONLY_MATCHING_ENGINE_CAN_ASSIGN);
        for (uint256 index = 0; index < askIds.length; index++) {
            _assignTask(askIds[index], generators[index], new_acls[index]);
        }
    }

    function relayAssignTask(
        uint256 askId,
        address generator,
        bytes calldata new_acl,
        bytes calldata signature
    ) external {
        bytes32 messageHash = keccak256(abi.encode(askId, generator, new_acl));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        require(hasRole(MATCHING_ENGINE_ROLE, signer), Error.ONLY_MATCHING_ENGINE_CAN_ASSIGN);
        _assignTask(askId, generator, new_acl);
    }

    function assignTask(
        uint256 askId,
        address generator,
        bytes calldata new_acl
    ) external onlyRole(MATCHING_ENGINE_ROLE) {
        _assignTask(askId, generator, new_acl);
    }

    function _assignTask(uint256 askId, address generator, bytes memory new_acl) internal {
        require(getAskState(askId) == AskState.CREATE, Error.SHOULD_BE_IN_CREATE_STATE);

        AskWithState storage askWithState = listOfAsk[askId];
        (uint256 proofGenerationCost, uint256 generatorProposedTime) = GENERATOR_REGISTRY.getGeneratorAssignmentDetails(
            generator,
            askWithState.ask.marketId
        );

        require(askWithState.ask.reward >= proofGenerationCost, Error.PROOF_PRICE_MISMATCH);
        require(askWithState.ask.timeTakenForProofGeneration >= generatorProposedTime, Error.PROOF_TIME_MISMATCH);
        askWithState.state = AskState.ASSIGNED;
        askWithState.ask.deadline = block.number + askWithState.ask.timeTakenForProofGeneration;
        askWithState.generator = generator;

        uint256 generatorAmountToLock = slashingPenalty(askWithState.ask.marketId);
        GENERATOR_REGISTRY.assignGeneratorTask(generator, askWithState.ask.marketId, generatorAmountToLock);
        emit TaskCreated(askId, generator, new_acl);
    }

    function cancelAsk(uint256 askId) external {
        require(getAskState(askId) == AskState.UNASSIGNED, Error.ONLY_EXPIRED_ASKS_CAN_BE_CANCELLED);
        AskWithState storage askWithState = listOfAsk[askId];
        askWithState.state = AskState.COMPLETE;

        PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, askWithState.ask.reward);

        emit AskCancelled(askId);
    }

    function submitProofForInvalidInputs(uint256 askId, bytes calldata invalidProofSignature) external {
        AskWithState memory askWithState = listOfAsk[askId];

        uint256 marketId = askWithState.ask.marketId;

        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            askWithState.generator,
            askWithState.ask.marketId
        );

        require(generatorRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(getAskState(askId) == AskState.ASSIGNED, Error.ONLY_ASSIGNED_ASKS_CAN_BE_PROVED);

        Market memory currentMarket = marketData[marketId];
        bytes32 messageHash;
        // if market needs enclave based, only sign only request id
        if (currentMarket.isEnclaveRequired) {
            //only askId must be signed
            messageHash = keccak256(abi.encode(askId));
        }
        // if market is not enclave based, sign request||inputdata
        else {
            //askId and proverData both must be signed
            messageHash = keccak256(abi.encode(askId, askWithState.ask.proverData));
        }

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, invalidProofSignature);
        require(signer == currentMarket.ivsSigner, Error.INVALID_ENCLAVE_KEY);

        listOfAsk[askId].state = AskState.COMPLETE;

        // token related to incorrect request will be sen't to treasury
        uint256 toTreasury = askWithState.ask.reward - minRewardForGenerator;

        if (minRewardForGenerator != 0) {
            PAYMENT_TOKEN.safeTransfer(generatorRewardAddress, minRewardForGenerator);
        }

        if (toTreasury != 0) {
            PAYMENT_TOKEN.safeTransfer(TREASURY, toTreasury);
        }

        uint256 generatorAmountToRelease = currentMarket.slashingPenalty;
        GENERATOR_REGISTRY.completeGeneratorTask(askWithState.generator, marketId, generatorAmountToRelease);
        emit InvalidInputsDetected(askId);
    }

    function submitProofs(uint256[] memory taskIds, bytes[] calldata proofs) external {
        require(taskIds.length == proofs.length, Error.ARITY_MISMATCH);
        for (uint256 index = 0; index < taskIds.length; index++) {
            submitProof(taskIds[index], proofs[index]);
        }
    }

    function submitProof(uint256 askId, bytes calldata proof) public {
        AskWithState memory askWithState = listOfAsk[askId];

        uint256 marketId = askWithState.ask.marketId;
        IVerifier proofVerifier = IVerifier(marketData[marketId].verifier);

        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            askWithState.generator,
            askWithState.ask.marketId
        );

        require(generatorRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(getAskState(askId) == AskState.ASSIGNED, Error.ONLY_ASSIGNED_ASKS_CAN_BE_PROVED);
        // check what needs to be encoded from proof, ask and task for proof to be verified

        bytes memory inputAndProof = abi.encode(askWithState.ask.proverData, proof);
        require(proofVerifier.verify(inputAndProof), Error.INVALID_PROOF);
        listOfAsk[askId].state = AskState.COMPLETE;

        uint256 toBackToProver = askWithState.ask.reward - minRewardForGenerator;

        if (minRewardForGenerator != 0) {
            PAYMENT_TOKEN.safeTransfer(generatorRewardAddress, minRewardForGenerator);
        }

        if (toBackToProver != 0) {
            PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, toBackToProver);
        }

        uint256 generatorAmountToRelease = slashingPenalty(marketId);
        GENERATOR_REGISTRY.completeGeneratorTask(askWithState.generator, marketId, generatorAmountToRelease);
        emit ProofCreated(askId, proof);
    }

    function slashGenerator(
        uint256 askId,
        address rewardAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        require(getAskState(askId) == AskState.DEADLINE_CROSSED, Error.SHOULD_BE_IN_CROSSED_DEADLINE_STATE);
        return _slashGenerator(askId, rewardAddress);
    }

    function discardRequest(uint256 askId) external returns (uint256) {
        AskWithState memory askWithState = listOfAsk[askId];
        require(getAskState(askId) == AskState.ASSIGNED, Error.SHOULD_BE_IN_ASSIGNED_STATE);
        require(askWithState.generator == msg.sender, Error.ONLY_GENERATOR_CAN_DISCARD_REQUEST);
        return _slashGenerator(askId, TREASURY);
    }

    function _slashGenerator(uint256 askId, address rewardAddress) internal returns (uint256) {
        AskWithState storage askWithState = listOfAsk[askId];

        askWithState.state = AskState.COMPLETE;
        uint256 marketId = askWithState.ask.marketId;

        emit ProofNotGenerated(askId);
        return
            GENERATOR_REGISTRY.slashGenerator(
                askWithState.generator,
                marketId,
                slashingPenalty(marketId),
                rewardAddress
            );
    }

    function slashingPenalty(uint256 marketId) public view returns (uint256) {
        return marketData[marketId].slashingPenalty;
    }

    function verifier(uint256 marketId) public view returns (address) {
        return marketData[marketId].verifier;
    }

    function askCounter() public view returns (uint256) {
        return listOfAsk.length;
    }
}
