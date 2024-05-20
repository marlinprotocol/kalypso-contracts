// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20 as IERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import "./interfaces/IVerifier.sol";

import "./EntityKeyRegistry.sol";
import "./GeneratorRegistry.sol";
import "./TeeVerifier.sol";
import "./lib/Error.sol";

contract ProofMarketplace is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IERC20Upgradeable _paymentToken,
        uint256 _marketCreationCost,
        address _treasury,
        GeneratorRegistry _generatorRegistry,
        EntityKeyRegistry _entityRegistry,
        TeeVerifier _teeVerifier
    ) initializer {
        PAYMENT_TOKEN = _paymentToken;
        MARKET_CREATION_COST = _marketCreationCost;
        TREASURY = _treasury;
        GENERATOR_REGISTRY = _generatorRegistry;
        ENTITY_KEY_REGISTRY = _entityRegistry;
        TEE_VERIFIER = _teeVerifier;
    }

    using HELPER for bytes;
    using HELPER for bytes32;
    using HELPER for uint256;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     @notice Enforces PMP to use only one matching engine image
     */
    function setMatchingEngineImage(bytes calldata pcrs) external onlyRole(UPDATER_ROLE) {
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), pcrs);
    }

    /**
     * @notice Verifies the matching engine and its' keys. Can be verified only by UPDATE_ROLE till multi matching engine key sharing is enabled
     */
    function verifyMatchingEngine(bytes memory attestationData, bytes calldata meSignature) external onlyRole(UPDATER_ROLE) {
        address _thisAddress = address(this);

        // confirms that admin has access to enclave
        attestationData.VERIFY_ENCLAVE_SIGNATURE(meSignature, _thisAddress);

        // checks attestation and updates the key
        ENTITY_KEY_REGISTRY.updatePubkey(_thisAddress, 0, attestationData.GET_PUBKEY(), attestationData);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Constants and Immutable start --------------------------------//
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint256 public constant MARKET_ACTIVATION_DELAY = 100; // in blocks

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable PAYMENT_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable MARKET_CREATION_COST;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable TREASURY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    GeneratorRegistry public immutable GENERATOR_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    TeeVerifier public immutable TEE_VERIFIER;

    bytes32 public constant MATCHING_ENGINE_ROLE = keccak256("MATCHING_ENGINE_ROLE");

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    Market[] public marketData;

    AskWithState[] public listOfAsk;

    mapping(SecretType => uint256) public costPerInputBytes;

    mapping(address => uint256) public claimableAmount;

    struct Market {
        IVerifier verifier; // verifier address for the market place
        bytes32 proverImageId; // use bytes32(0) for public market
        uint256 slashingPenalty;
        uint256 activationBlock;
        bytes32 ivsImageId;
        address creator;
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

    event MarketplaceCreated(uint256 indexed marketId);

    event AskCancelled(uint256 indexed askId);

    event UpdateCostPerBytes(SecretType indexed secretType, uint256 costPerInputBytes);

    //-------------------------------- Events end --------------------------------//

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(UPDATER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function pause() external onlyRole(UPDATER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UPDATER_ROLE) {
        _unpause();
    }

    /**
     * @notice Create a new market.
     */
    function createMarketplace(
        bytes calldata _marketmetadata,
        IVerifier _verifier,
        uint256 _penalty,
        bytes calldata _proverPcrs,
        bytes calldata _ivsPcrs
    ) external nonReentrant {
        address _msgSender = _msgSender();
        if (_penalty == 0 || _marketmetadata.length == 0 || address(_verifier) == address(0)) {
            revert Error.CannotBeZero();
        }

        if (!_verifier.checkSampleInputsAndProof()) {
            revert Error.InvalidInputs();
        }
        PAYMENT_TOKEN.safeTransferFrom(_msgSender, TREASURY, MARKET_CREATION_COST);

        uint256 marketId = marketData.length;

        // Helps skip whitelisting for public provers
        if (_proverPcrs.GET_IMAGE_ID_FROM_PCRS().IS_ENCLAVE()) {
            ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.GENERATOR_FAMILY_ID(), _proverPcrs);
        }

        // ivs is always enclave, will revert if a non enclave instance is stated as an ivs
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.IVS_FAMILY_ID(), _ivsPcrs);

        marketData.push(
            Market(
                _verifier,
                _proverPcrs.GET_IMAGE_ID_FROM_PCRS(),
                _penalty,
                block.number + MARKET_ACTIVATION_DELAY,
                _ivsPcrs.GET_IMAGE_ID_FROM_PCRS(),
                _msgSender,
                _marketmetadata
            )
        );
        emit MarketplaceCreated(marketId);
    }

    /**
     * @notice Feature for market creator to list new prover images and ivs images
     */
    function addExtraImages(uint256 marketId, bytes[] calldata _proverPcrs, bytes[] calldata _ivsPcrs) external {
        Market memory market = marketData[marketId];
        if (market.marketmetadata.length == 0) {
            revert Error.InvalidMarket();
        }

        if (_msgSender() != market.creator) {
            revert Error.OnlyMarketCreator();
        }

        if (_proverPcrs.length != 0) {
            if (!market.proverImageId.IS_ENCLAVE()) {
                revert Error.CannotModifyImagesForPublicMarkets();
            }

            for (uint256 index = 0; index < _proverPcrs.length; index++) {
                ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.GENERATOR_FAMILY_ID(), _proverPcrs[index]);
            }
        }

        for (uint256 index = 0; index < _ivsPcrs.length; index++) {
            ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.IVS_FAMILY_ID(), _ivsPcrs[index]);
        }
    }

    /**
     * @notice Feature for market creator to remove extra provers
     */
    function removeExtraImages(uint256 marketId, bytes[] calldata _proverPcrs, bytes[] calldata _ivsPcrs) external {
        Market memory market = marketData[marketId];
        if (market.marketmetadata.length == 0) {
            revert Error.InvalidMarket();
        }

        if (_msgSender() != market.creator) {
            revert Error.OnlyMarketCreator();
        }

        if (_proverPcrs.length != 0) {
            if (!market.proverImageId.IS_ENCLAVE()) {
                revert Error.CannotModifyImagesForPublicMarkets();
            }

            for (uint256 index = 0; index < _proverPcrs.length; index++) {
                bytes32 imageId = _proverPcrs[index].GET_IMAGE_ID_FROM_PCRS();
                if (imageId == market.proverImageId) {
                    revert Error.CannotRemoveDefaultImageFromMarket(marketId, imageId);
                }
                ENTITY_KEY_REGISTRY.removeEnclaveImageFromFamily(imageId, marketId.GENERATOR_FAMILY_ID());
            }
        }

        for (uint256 index = 0; index < _ivsPcrs.length; index++) {
            bytes32 imageId = _ivsPcrs[index].GET_IMAGE_ID_FROM_PCRS();
            if (imageId == market.ivsImageId) {
                revert Error.CannotRemoveDefaultImageFromMarket(marketId, imageId);
            }
            ENTITY_KEY_REGISTRY.removeEnclaveImageFromFamily(imageId, marketId.IVS_FAMILY_ID());
        }
    }

    /**
     * @notice Once called new images can't be added to market
     */
    function freezeMarket(uint256 marketId) external {
        Market memory market = marketData[marketId];
        if (market.marketmetadata.length == 0) {
            revert Error.InvalidMarket();
        }

        if (_msgSender() != market.creator) {
            revert Error.OnlyMarketCreator();
        }

        delete marketData[marketId].creator;
    }

    /**
     * @notice Create requests. Can be paused to prevent temporary escrowing of unwanted amount
     * @param ask: Details of the ASK request
     * @param secretType: 0 for purely calldata based secret (1 for Celestia etc, 2 ipfs etc)
     * @param privateInputs: Private Inputs to the circuit.
     * @param acl: If the private inputs are mean't to be confidential, provide acl using the ME keys
     */
    function createAsk(
        Ask calldata ask,
        // TODO: Check if this needs to be removed during review
        SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl
    ) external whenNotPaused nonReentrant {
        _createAsk(ask, msg.sender, secretType, privateInputs, acl);
    }

    function _createAsk(
        Ask calldata ask,
        address payFrom,
        SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl
    ) internal {
        if (ask.reward == 0 || ask.proverData.length == 0) {
            revert Error.CannotBeZero();
        }
        if (ask.expiry <= block.number) {
            revert Error.CannotAssignExpiredTasks();
        }
        // ensures that the cipher used is small enough
        if (acl.length > 130) {
            revert Error.InvalidECIESACL();
        }

        Market memory market = marketData[ask.marketId];
        if (block.number < market.activationBlock) {
            revert Error.InactiveMarket();
        }

        uint256 platformFee = getPlatformFee(secretType, ask, privateInputs, acl);

        PAYMENT_TOKEN.safeTransferFrom(payFrom, address(this), ask.reward + platformFee);
        _increaseClaimableAmount(TREASURY, platformFee);

        if (market.marketmetadata.length == 0) {
            revert Error.InvalidMarket();
        }

        uint256 askId = listOfAsk.length;
        AskWithState memory askRequest = AskWithState(ask, AskState.CREATE, msg.sender, address(0));
        listOfAsk.push(askRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);

        if (!inputVerifier.verifyInputs(ask.proverData)) {
            revert Error.InvalidInputs();
        }

        if (market.proverImageId.IS_ENCLAVE()) {
            // ACL is emitted if private
            emit AskCreated(askId, true, privateInputs, acl);
        } else {
            // ACL is not emitted if not private
            emit AskCreated(askId, false, "", "");
        }
    }

    /**
     * @notice Different secret might have different fee. Hence fee is different
     * @param secretType: Secret Type
     * @param ask: Details of the ask
     * @param privateInputs: Private Inputs to the circuit
     * @param acl: Access control Data
     */
    function getPlatformFee(
        SecretType secretType,
        Ask calldata ask,
        bytes calldata privateInputs,
        bytes calldata acl
    ) public view returns (uint256) {
        uint256 costperByte = costPerInputBytes[secretType];
        if (costperByte != 0) {
            return (ask.proverData.length + privateInputs.length + acl.length) * costperByte;
        }
        return 0;
    }

    /**
     * @notice Update Cost for inputs
     */
    function updateCostPerBytes(SecretType secretType, uint256 costPerByte) public onlyRole(UPDATER_ROLE) {
        costPerInputBytes[secretType] = costPerByte;

        emit UpdateCostPerBytes(secretType, costPerByte);
    }

    /**
     @notice Possible States: NULL, CREATE, UNASSIGNED, ASSIGNED, COMPLETE, DEADLINE_CROSSED
     */
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

    /**
     * @notice Assign Tasks for Generators. Only Matching Engine Image can call
     */
    function relayBatchAssignTasks(
        uint256[] memory askIds,
        address[] memory generators,
        bytes[] calldata newAcls,
        bytes calldata signature
    ) external nonReentrant {
        if (askIds.length != generators.length || generators.length != newAcls.length) {
            revert Error.ArityMismatch();
        }

        bytes32 messageHash = keccak256(abi.encode(askIds, generators, newAcls));
        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), signer);

        for (uint256 index = 0; index < askIds.length; index++) {
            _assignTask(askIds[index], generators[index], newAcls[index]);
        }
    }

    /**
     * @notice Assign Tasks for Generators directly if ME signer has the gas
     */
    function assignTask(uint256 askId, address generator, bytes calldata new_acl) external nonReentrant {
        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), _msgSender());
        _assignTask(askId, generator, new_acl);
    }

    function _assignTask(uint256 askId, address generator, bytes memory new_acl) internal {
        // Only tasks in CREATE state can be assigned
        if (getAskState(askId) != AskState.CREATE) {
            revert Error.ShouldBeInCreateState();
        }

        AskWithState storage askWithState = listOfAsk[askId];
        (uint256 proofGenerationCost, uint256 generatorProposedTime) = GENERATOR_REGISTRY.getGeneratorAssignmentDetails(
            generator,
            askWithState.ask.marketId
        );

        // Can not assign task if price mismatch happens
        if (askWithState.ask.reward < proofGenerationCost) {
            revert Error.ProofPriceMismatch(askId);
        }

        // Can not assign task if time mismatch happens
        if (askWithState.ask.timeTakenForProofGeneration < generatorProposedTime) {
            revert Error.ProofTimeMismatch(askId);
        }

        askWithState.state = AskState.ASSIGNED;
        askWithState.ask.deadline = block.number + askWithState.ask.timeTakenForProofGeneration;
        askWithState.generator = generator;

        uint256 generatorAmountToLock = _slashingPenalty(askWithState.ask.marketId);
        GENERATOR_REGISTRY.assignGeneratorTask(generator, askWithState.ask.marketId, generatorAmountToLock);
        emit TaskCreated(askId, generator, new_acl);
    }

    /**
     * @notice Cancel the unassigned request. Refunds the proof fee back to the requestor
     */
    function cancelAsk(uint256 askId) external nonReentrant {
        // Only unassigned tasks can be cancelled.
        if (getAskState(askId) != AskState.UNASSIGNED) {
            revert Error.OnlyExpiredAsksCanBeCancelled(askId);
        }
        AskWithState storage askWithState = listOfAsk[askId];
        askWithState.state = AskState.COMPLETE;

        _increaseClaimableAmount(askWithState.ask.refundAddress, askWithState.ask.reward);

        emit AskCancelled(askId);
    }

    function _verifyAndGetData(uint256 askId, AskWithState memory askWithState) internal view returns (uint256, address) {
        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            askWithState.generator,
            askWithState.ask.marketId
        );

        if (generatorRewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        if (getAskState(askId) != AskState.ASSIGNED) {
            revert Error.OnlyAssignedAsksCanBeProved(askId);
        }

        return (minRewardForGenerator, generatorRewardAddress);
    }

    function _completeProofForInvalidRequests(
        uint256 askId,
        AskWithState memory askWithState,
        uint256 minRewardForGenerator,
        address generatorRewardAddress,
        uint256 marketId,
        uint256 _penalty
    ) internal {
        // Only assigned requests can be proved
        if (getAskState(askId) != AskState.ASSIGNED) {
            revert Error.OnlyAssignedAsksCanBeProved(askId);
        }
        listOfAsk[askId].state = AskState.COMPLETE;

        // tokens related to incorrect request will be sen't to treasury
        uint256 toTreasury = askWithState.ask.reward - minRewardForGenerator;

        // transfer the reward to generator
        _increaseClaimableAmount(generatorRewardAddress, minRewardForGenerator);
        // transfer the amount to treasury collection
        _increaseClaimableAmount(TREASURY, toTreasury);

        GENERATOR_REGISTRY.completeGeneratorTask(askWithState.generator, marketId, _penalty);
        emit InvalidInputsDetected(askId);
    }

    /**
     * @notice Submit Attestation/Proof from the IVS signer that the given inputs are invalid
     */
    function submitProofForInvalidInputs(uint256 askId, bytes calldata invalidProofSignature) external nonReentrant {
        AskWithState memory askWithState = listOfAsk[askId];
        uint256 marketId = askWithState.ask.marketId;
        Market memory currentMarket = marketData[marketId];

        (uint256 minRewardForGenerator, address generatorRewardAddress) = _verifyAndGetData(askId, askWithState);

        if (!_checkDisputeUsingSignature(askId, askWithState.ask.proverData, invalidProofSignature, marketId.IVS_FAMILY_ID())) {
            revert Error.CannotSlashUsingValidInputs(askId);
        }

        _completeProofForInvalidRequests(
            askId,
            askWithState,
            minRewardForGenerator,
            generatorRewardAddress,
            marketId,
            currentMarket.slashingPenalty
        );
    }

    function submitProofForValidTeeProof(uint256 askId, bytes calldata validTeeProofSignature) external nonReentrant {
        AskWithState memory askWithState = listOfAsk[askId];

        uint256 marketId = askWithState.ask.marketId;

        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            askWithState.generator,
            askWithState.ask.marketId
        );

        if (generatorRewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        if (getAskState(askId) != AskState.ASSIGNED) {
            revert Error.OnlyAssignedAsksCanBeProved(askId);
        }

        // Verify input and proof against verifier
        if (!TEE_VERIFIER.verifyProofForTeeVerifier(askId, askWithState.ask.proverData , validTeeProofSignature, marketId.GENERATOR_FAMILY_ID())) {
            revert Error.InvalidProof(askId);
        }
        listOfAsk[askId].state = AskState.COMPLETE;

        uint256 toBackToRequestor = askWithState.ask.reward - minRewardForGenerator;

        // reward to generator
        _increaseClaimableAmount(generatorRewardAddress, minRewardForGenerator);
        // fraction of amount back to requestor
        _increaseClaimableAmount(askWithState.ask.refundAddress, toBackToRequestor);

        uint256 generatorAmountToRelease = _slashingPenalty(marketId);
        GENERATOR_REGISTRY.completeGeneratorTask(askWithState.generator, marketId, generatorAmountToRelease);
        emit ProofCreated(askId, proof);
    }

    function submitProofForInvalidTeeProof(uint256 askId, bytes calldata invalidTeeProofSignature) external nonReentrant {
        AskWithState memory askWithState = listOfAsk[askId];
        uint256 marketId = askWithState.ask.marketId;
        Market memory currentMarket = marketData[marketId];

        (uint256 minRewardForGenerator, address generatorRewardAddress) = _verifyAndGetData(askId, askWithState);

        if (!TEE_VERIFIER.verifyProofForTeeVerifier(askId, askWithState.ask.proverData, invalidTeeProofSignature, marketId.GENERATOR_FAMILY_ID())) {
            revert Error.CannotSlashUsingValidInputs(askId);
        }

        _completeProofForInvalidRequests(
            askId,
            askWithState,
            minRewardForGenerator,
            generatorRewardAddress,
            marketId,
            currentMarket.slashingPenalty
        );
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] memory taskIds, bytes[] calldata proofs) external nonReentrant {
        if (taskIds.length != proofs.length) {
            revert Error.ArityMismatch();
        }
        for (uint256 index = 0; index < taskIds.length; index++) {
            _submitProof(taskIds[index], proofs[index]);
        }
    }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 askId, bytes calldata proof) public nonReentrant {
        _submitProof(askId, proof);
    }

    function _submitProof(uint256 askId, bytes calldata proof) internal {
        AskWithState memory askWithState = listOfAsk[askId];

        uint256 marketId = askWithState.ask.marketId;

        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            askWithState.generator,
            askWithState.ask.marketId
        );

        if (generatorRewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        if (getAskState(askId) != AskState.ASSIGNED) {
            revert Error.OnlyAssignedAsksCanBeProved(askId);
        }
        // check what needs to be encoded from proof, ask and task for proof to be verified

        bytes memory inputAndProof = abi.encode(askWithState.ask.proverData, proof);

        // Verify input and proof against verifier
        if (!marketData[marketId].verifier.verify(inputAndProof)) {
            revert Error.InvalidProof(askId);
        }
        listOfAsk[askId].state = AskState.COMPLETE;

        uint256 toBackToRequestor = askWithState.ask.reward - minRewardForGenerator;

        // reward to generator
        _increaseClaimableAmount(generatorRewardAddress, minRewardForGenerator);
        // fraction of amount back to requestor
        _increaseClaimableAmount(askWithState.ask.refundAddress, toBackToRequestor);

        uint256 generatorAmountToRelease = _slashingPenalty(marketId);
        GENERATOR_REGISTRY.completeGeneratorTask(askWithState.generator, marketId, generatorAmountToRelease);
        emit ProofCreated(askId, proof);
    }

    /**
     * @notice Slash Generator for deadline crossed requests
     */
    function slashGenerator(uint256 askId, address rewardAddress) external nonReentrant returns (uint256) {
        if (getAskState(askId) != AskState.DEADLINE_CROSSED) {
            revert Error.ShouldBeInCrossedDeadlineState(askId);
        }
        return _slashGenerator(askId, rewardAddress);
    }

    /**
     * @notice Generator can discard assigned request if he choses to. This will however result in slashing
     */
    function discardRequest(uint256 askId) external nonReentrant returns (uint256) {
        AskWithState memory askWithState = listOfAsk[askId];
        if (getAskState(askId) != AskState.ASSIGNED) {
            revert Error.ShouldBeInAssignedState(askId);
        }
        if (askWithState.generator != _msgSender()) {
            revert Error.OnlyGeneratorCanDiscardRequest(askId);
        }
        return _slashGenerator(askId, TREASURY);
    }

    function _slashGenerator(uint256 askId, address rewardAddress) internal returns (uint256) {
        AskWithState storage askWithState = listOfAsk[askId];

        askWithState.state = AskState.COMPLETE;
        uint256 marketId = askWithState.ask.marketId;

        _increaseClaimableAmount(askWithState.ask.refundAddress, askWithState.ask.reward);
        emit ProofNotGenerated(askId);
        return GENERATOR_REGISTRY.slashGenerator(askWithState.generator, marketId, _slashingPenalty(marketId), rewardAddress);
    }

    function _slashingPenalty(uint256 marketId) internal view returns (uint256) {
        return marketData[marketId].slashingPenalty;
    }

    function flush(address _address) public {
        uint256 amount = claimableAmount[_address];
        if (amount != 0) {
            PAYMENT_TOKEN.safeTransfer(_address, amount);
            delete claimableAmount[_address];
        }
    }

    function _increaseClaimableAmount(address _address, uint256 _amount) internal {
        if (_amount != 0) {
            claimableAmount[_address] += _amount;
        }
    }

    function _checkDisputeUsingSignature(
        uint256 askId,
        bytes memory proverData,
        bytes memory invalidProofSignature,
        bytes32 familyId
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(askId, proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, invalidProofSignature);
        if (signer == address(0)) {
            revert Error.InvalidEnclaveSignature(signer);
        }

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(familyId, signer);
        return true;
    }

    function askCounter() public view returns (uint256) {
        return listOfAsk.length;
    }

    function marketCounter() public view returns (uint256) {
        return marketData.length;
    }

    // for further increase
    uint256[50] private __gap1_0;
}
