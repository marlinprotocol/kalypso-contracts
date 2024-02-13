// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IVerifier.sol";

import "./EntityKeyRegistry.sol";
import "./GeneratorRegistry.sol";
import "./lib/Error.sol";

contract ProofMarketplace is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IERC20Upgradeable _paymentToken,
        uint256 _marketCreationCost,
        address _treasury,
        GeneratorRegistry _generatorRegistry,
        EntityKeyRegistry _entityRegistry
    ) initializer {
        PAYMENT_TOKEN = _paymentToken;
        MARKET_CREATION_COST = _marketCreationCost;
        TREASURY = _treasury;
        GENERATOR_REGISTRY = _generatorRegistry;
        ENTITY_KEY_REGISTRY = _entityRegistry;
    }

    using HELPER for bytes;
    using HELPER for bytes32;

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

    /**
     @notice Enforces PMP to use only one matching engine image
     */
    function setMatchingEngineImage(bytes calldata pcrs) external onlyRole(UPDATER_ROLE) {
        matchingEngineImageId = pcrs.GET_IMAGE_ID_FROM_PCRS();
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(pcrs);
    }

    /**
     * @notice Verifies the matching engine and its' keys.
     */
    function verifyMatchingEngine(
        bytes memory attestationData,
        bytes calldata meSignature
    ) external onlyRole(UPDATER_ROLE) {
        address _thisAddress = address(this);

        // check proof of ownership of enclave
        attestationData.VERIFY_ENCLAVE_SIGNATURE(meSignature, _thisAddress);

        (bytes memory pubkey, ) = attestationData.GET_PUBKEY_AND_ADDRESS();

        // checks attestation and updates the key
        ENTITY_KEY_REGISTRY.updatePubkey(_thisAddress, 0, pubkey, attestationData);
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
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

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

    uint256 public constant MARKET_ACTIVATION_DELAY = 100; // in blocks

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    uint256 public marketCounter;
    mapping(uint256 => Market) public marketData;

    AskWithState[] public listOfAsk;

    mapping(SecretType => uint256) public costPerInputBytes;

    uint256 public treasuryCollection;

    bytes32 public matchingEngineImageId;

    struct Market {
        IVerifier verifier; // verifier address for the market place
        bytes32 proverImageId; // use bytes32(0) for public market
        uint256 slashingPenalty;
        uint256 activationBlock;
        bytes32 ivsImageId;
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
        __AccessControlEnumerable_init_unchained();
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(UPDATER_ROLE, DEFAULT_ADMIN_ROLE);
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
        require(_penalty != 0, Error.CANNOT_BE_ZERO); // this also the amount, which will be locked for a generator when task is assigned
        require(_marketmetadata.length != 0, Error.CANNOT_BE_ZERO);

        address _msgSender = _msgSender();

        Market storage market = marketData[marketCounter];
        require(market.marketmetadata.length == 0, Error.MARKET_ALREADY_EXISTS);
        require(address(_verifier) != address(0), Error.CANNOT_BE_ZERO);
        require(_verifier.checkSampleInputsAndProof(), Error.INVALID_INPUTS);

        market.verifier = _verifier;
        market.slashingPenalty = _penalty;
        market.marketmetadata = _marketmetadata;
        market.proverImageId = _proverPcrs.GET_IMAGE_ID_FROM_PCRS();
        market.ivsImageId = _ivsPcrs.GET_IMAGE_ID_FROM_PCRS();
        market.activationBlock = block.number + MARKET_ACTIVATION_DELAY;

        // White list image if is not
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(_proverPcrs);
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(_ivsPcrs);
        PAYMENT_TOKEN.safeTransferFrom(_msgSender, TREASURY, MARKET_CREATION_COST);

        emit MarketplaceCreated(marketCounter);
        marketCounter++;
    }

    /**
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
    ) external nonReentrant {
        _createAsk(ask, msg.sender, secretType, privateInputs, acl);
    }

    function _createAsk(
        Ask calldata ask,
        address payFrom,
        SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl
    ) internal {
        require(ask.reward != 0, Error.CANNOT_BE_ZERO);
        require(ask.proverData.length != 0, Error.CANNOT_BE_ZERO);
        require(ask.expiry > block.number, Error.CAN_NOT_ASSIGN_EXPIRED_TASKS);
        require(acl.length <= 130, Error.INVALID_ECIES_ACL);

        Market memory market = marketData[ask.marketId];
        require(block.number > market.activationBlock, Error.INACTIVE_MARKET);

        uint256 platformFee = getPlatformFee(secretType, ask, privateInputs, acl);

        PAYMENT_TOKEN.safeTransferFrom(payFrom, address(this), ask.reward + platformFee);
        treasuryCollection += platformFee;

        require(market.marketmetadata.length != 0, Error.INVALID_MARKET);

        uint256 askId = listOfAsk.length;
        AskWithState memory askRequest = AskWithState(ask, AskState.CREATE, msg.sender, address(0));
        listOfAsk.push(askRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);
        require(inputVerifier.verifyInputs(ask.proverData), Error.INVALID_INPUTS);

        if (market.proverImageId.IS_ENCLAVE()) {
            // ACL is emitted if private
            emit AskCreated(askId, true, privateInputs, acl);
        } else {
            // ACL is not emitted if not private
            emit AskCreated(askId, false, privateInputs, "");
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
        require(askIds.length == generators.length, Error.ARITY_MISMATCH);
        require(askIds.length == newAcls.length, Error.ARITY_MISMATCH);

        bytes32 messageHash = keccak256(abi.encode(askIds, generators, newAcls));
        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);
        require(
            ENTITY_KEY_REGISTRY.allowOnlyVerified(signer, matchingEngineImageId),
            Error.ONLY_MATCHING_ENGINE_CAN_ASSIGN
        );

        for (uint256 index = 0; index < askIds.length; index++) {
            _assignTask(askIds[index], generators[index], newAcls[index]);
        }
    }

    /**
     * @notice Assign Tasks for Generators directly if ME signer has the gas
     */
    function assignTask(uint256 askId, address generator, bytes calldata new_acl) external nonReentrant {
        require(
            ENTITY_KEY_REGISTRY.allowOnlyVerified(_msgSender(), matchingEngineImageId),
            Error.ONLY_MATCHING_ENGINE_CAN_ASSIGN
        );
        _assignTask(askId, generator, new_acl);
    }

    function _assignTask(uint256 askId, address generator, bytes memory new_acl) internal {
        // Only tasks in CREATE state can be assigned
        require(getAskState(askId) == AskState.CREATE, Error.SHOULD_BE_IN_CREATE_STATE);

        AskWithState storage askWithState = listOfAsk[askId];
        (uint256 proofGenerationCost, uint256 generatorProposedTime) = GENERATOR_REGISTRY.getGeneratorAssignmentDetails(
            generator,
            askWithState.ask.marketId
        );

        // Can not assign task if price mismatch happens
        require(askWithState.ask.reward >= proofGenerationCost, Error.PROOF_PRICE_MISMATCH);

        // Can not assign task if time mismatch happens
        require(askWithState.ask.timeTakenForProofGeneration >= generatorProposedTime, Error.PROOF_TIME_MISMATCH);

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
        require(getAskState(askId) == AskState.UNASSIGNED, Error.ONLY_EXPIRED_ASKS_CAN_BE_CANCELLED);
        AskWithState storage askWithState = listOfAsk[askId];
        askWithState.state = AskState.COMPLETE;

        PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, askWithState.ask.reward);

        emit AskCancelled(askId);
    }

    function _verifyAndGetData(
        uint256 askId,
        AskWithState memory askWithState
    ) internal view returns (uint256, address) {
        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            askWithState.generator,
            askWithState.ask.marketId
        );

        require(generatorRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(getAskState(askId) == AskState.ASSIGNED, Error.ONLY_ASSIGNED_ASKS_CAN_BE_PROVED);

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
        require(getAskState(askId) == AskState.ASSIGNED, Error.ONLY_ASSIGNED_ASKS_CAN_BE_PROVED);
        listOfAsk[askId].state = AskState.COMPLETE;

        // tokens related to incorrect request will be sen't to treasury
        uint256 toTreasury = askWithState.ask.reward - minRewardForGenerator;

        if (minRewardForGenerator != 0) {
            PAYMENT_TOKEN.safeTransfer(generatorRewardAddress, minRewardForGenerator);
        }

        // transfer the amount to treasury collection
        treasuryCollection += toTreasury;

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

        require(
            _checkDisputeUsingSignature(
                askId,
                askWithState.ask.proverData,
                invalidProofSignature,
                currentMarket.ivsImageId
            ),
            Error.CAN_NOT_SLASH_USING_VALID_INPUTS
        );

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
        require(taskIds.length == proofs.length, Error.ARITY_MISMATCH);
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

        require(generatorRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(getAskState(askId) == AskState.ASSIGNED, Error.ONLY_ASSIGNED_ASKS_CAN_BE_PROVED);
        // check what needs to be encoded from proof, ask and task for proof to be verified

        bytes memory inputAndProof = abi.encode(askWithState.ask.proverData, proof);

        // Verify input and proof against verifier
        require(marketData[marketId].verifier.verify(inputAndProof), Error.INVALID_PROOF);
        listOfAsk[askId].state = AskState.COMPLETE;

        uint256 toBackToProver = askWithState.ask.reward - minRewardForGenerator;

        if (minRewardForGenerator != 0) {
            PAYMENT_TOKEN.safeTransfer(generatorRewardAddress, minRewardForGenerator);
        }

        if (toBackToProver != 0) {
            PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, toBackToProver);
        }

        uint256 generatorAmountToRelease = _slashingPenalty(marketId);
        GENERATOR_REGISTRY.completeGeneratorTask(askWithState.generator, marketId, generatorAmountToRelease);
        emit ProofCreated(askId, proof);
    }

    /**
     * @notice Slash Generator for deadline crossed requests
     */
    function slashGenerator(uint256 askId, address rewardAddress) external nonReentrant returns (uint256) {
        require(getAskState(askId) == AskState.DEADLINE_CROSSED, Error.SHOULD_BE_IN_CROSSED_DEADLINE_STATE);
        return _slashGenerator(askId, rewardAddress);
    }

    /**
     * @notice Generator can discard assigned request if he choses to. This will however result in slashing
     */
    function discardRequest(uint256 askId) external nonReentrant returns (uint256) {
        AskWithState memory askWithState = listOfAsk[askId];
        require(getAskState(askId) == AskState.ASSIGNED, Error.SHOULD_BE_IN_ASSIGNED_STATE);
        require(askWithState.generator == msg.sender, Error.ONLY_GENERATOR_CAN_DISCARD_REQUEST);
        return _slashGenerator(askId, TREASURY);
    }

    function _slashGenerator(uint256 askId, address rewardAddress) internal returns (uint256) {
        AskWithState storage askWithState = listOfAsk[askId];

        askWithState.state = AskState.COMPLETE;
        uint256 marketId = askWithState.ask.marketId;

        PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, askWithState.ask.reward);
        emit ProofNotGenerated(askId);
        return
            GENERATOR_REGISTRY.slashGenerator(
                askWithState.generator,
                marketId,
                _slashingPenalty(marketId),
                rewardAddress
            );
    }

    function _slashingPenalty(uint256 marketId) internal view returns (uint256) {
        return marketData[marketId].slashingPenalty;
    }

    function flushToTreasury() public {
        if (treasuryCollection != 0) {
            PAYMENT_TOKEN.safeTransfer(TREASURY, treasuryCollection);
            treasuryCollection = 0;
        }
    }

    function _checkDisputeUsingSignature(
        uint256 askId,
        bytes memory proverData,
        bytes memory invalidProofSignature,
        bytes32 expectedImageId
    ) internal view returns (bool) {
        bytes32 messageHash;

        // when public inputs, sign both ask id and prover data
        if (expectedImageId == bytes32(0) || expectedImageId == HELPER.NO_ENCLAVE_ID) {
            messageHash = keccak256(abi.encode(askId, proverData));
        } else {
            messageHash = keccak256(abi.encode(askId));
        }

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, invalidProofSignature);
        require(signer != address(0), Error.CANNOT_BE_ZERO);

        require(ENTITY_KEY_REGISTRY.allowOnlyVerified(signer, expectedImageId), Error.INVALID_ENCLAVE_KEY);
        return true;
    }

    function askCounter() public view returns (uint256) {
        return listOfAsk.length;
    }

    // for further increase
    uint256[50] private __gap1_0;
}
