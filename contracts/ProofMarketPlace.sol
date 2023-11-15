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

import "./interfaces/IProofMarketPlace.sol";
import "./interfaces/IGeneratorRegsitry.sol";
import "./interfaces/IVerifier.sol";
import "./interfaces/IEntityKeyRegistry.sol";

import "./lib/Error.sol";

// import "hardhat/console.sol";

contract ProofMarketPlace is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable,
    IProofMarketPlace
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

    function grantRole(bytes32, address) public virtual override(AccessControlUpgradeable, IAccessControlUpgradeable) {
        revert(Error.CAN_NOT_GRANT_ROLE_WITHOUT_ATTESTATION);
    }

    function grantRole(bytes32 role, address account, bytes memory attestation_data) public {
        if (role == MATCHING_ENGINE_ROLE) {
            bytes memory data = abi.encode(account, attestation_data);
            require(ENTITY_KEY_REGISTRY.attestationVerifier().verify(data), Error.ENCLAVE_KEY_NOT_VERIFIED);
            super._grantRole(role, account);
        } else {
            super._grantRole(role, account);
        }
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
    bytes32 public constant MATCHING_ENGINE_ROLE = bytes32(uint256(keccak256("MATCHING_ENGINE_ROLE")) - 1);

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable PAYMENT_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable PLATFORM_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable MARKET_CREATION_COST;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable TREASURY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IGeneratorRegistry public immutable GENERATOR_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IEntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    uint256 public constant costPerInputBytes = 10e15;

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(bytes32 => Market) marketData;

    AskWithState[] public listOfAsk;

    uint256 public taskCounter; // taskCounter also acts as nonce for matching engine.
    mapping(uint256 => Task) public listOfTask;

    //-------------------------------- State variables end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IERC20Upgradeable _paymentToken,
        IERC20Upgradeable _platformToken,
        uint256 _marketCreationCost,
        address _treasury,
        IGeneratorRegistry _generatorRegistry,
        IEntityKeyRegistry _entityRegistry
    ) {
        PAYMENT_TOKEN = _paymentToken;
        PLATFORM_TOKEN = _platformToken;
        MARKET_CREATION_COST = _marketCreationCost;
        TREASURY = _treasury;
        GENERATOR_REGISTRY = _generatorRegistry;
        ENTITY_KEY_REGISTRY = _entityRegistry;
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
    }

    function createMarketPlace(
        bytes calldata _marketmetadata,
        address _verifier,
        uint256 _slashingPenalty
    ) external override {
        require(_slashingPenalty != 0, Error.CANNOT_BE_ZERO); // this also the amount, which will be locked for a generator when task is assigned
        require(_marketmetadata.length != 0, Error.CANNOT_BE_ZERO);

        bytes32 marketId = keccak256(_marketmetadata);
        Market storage market = marketData[marketId];
        require(market.marketmetadata.length == 0, Error.MARKET_ALREADY_EXISTS);
        require(_verifier != address(0), Error.CANNOT_BE_ZERO);

        market.verifier = _verifier;
        market.slashingPenalty = _slashingPenalty;
        market.marketmetadata = _marketmetadata;

        PAYMENT_TOKEN.safeTransferFrom(_msgSender(), TREASURY, MARKET_CREATION_COST);

        emit MarketPlaceCreated(marketId);
    }

    function createAsk(
        Ask calldata ask,
        bool hasPrivateInputs,
        // TODO: Check if this needs to be removed during review
        SecretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) external override {
        _createAsk(ask, hasPrivateInputs, msg.sender, secret_inputs, acl);
    }

    function createAskFor(
        Ask calldata ask,
        bool hasPrivateInputs,
        address payFrom,
        // TODO: Check if this needs to be removed during review
        SecretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) external override {
        _createAsk(ask, hasPrivateInputs, payFrom, secret_inputs, acl);
    }

    function _createAsk(
        Ask calldata ask,
        bool hasPrivateInputs,
        address payFrom,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) internal {
        require(ask.reward != 0, Error.CANNOT_BE_ZERO);
        require(ask.proverData.length != 0, Error.CANNOT_BE_ZERO);
        require(ask.expiry > block.number, Error.CAN_NOT_ASSIGN_EXPIRED_TASKS);

        uint256 platformFee = getPlatformFee(ask, secret_inputs, acl);
        if (platformFee != 0) {
            PLATFORM_TOKEN.safeTransferFrom(payFrom, TREASURY, platformFee);
        }

        PAYMENT_TOKEN.safeTransferFrom(payFrom, address(this), ask.reward);

        Market memory market = marketData[ask.marketId];
        require(market.marketmetadata.length != 0, Error.INVALID_MARKET);

        uint256 askId = listOfAsk.length;
        AskWithState memory askRequest = AskWithState(ask, AskState.CREATE, msg.sender);
        listOfAsk.push(askRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);
        require(inputVerifier.verifyInputs(ask.proverData), Error.INVALID_INPUTS);

        emit AskCreated(askId, hasPrivateInputs, secret_inputs, acl);
    }

    function getPlatformFee(
        Ask calldata ask,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) public pure returns (uint256) {
        if (costPerInputBytes != 0) {
            return (ask.proverData.length + secret_inputs.length + acl.length) * costPerInputBytes;
        }
        return 0;
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

    function updateEncryptionKey(
        bytes memory pubkey,
        bytes memory attestation_data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ENTITY_KEY_REGISTRY.updatePubkey(pubkey, attestation_data);
    }

    function removeEncryptionKey() external onlyRole(DEFAULT_ADMIN_ROLE) {
        ENTITY_KEY_REGISTRY.removePubkey();
    }

    function relayBatchAssignTasks(
        uint256[] memory askIds,
        uint256[] memory newTaskIds,
        address[] memory generators,
        bytes[] calldata new_acls,
        bytes calldata signature
    ) public {
        require(askIds.length == newTaskIds.length, Error.ARITY_MISMATCH);
        require(askIds.length == generators.length, Error.ARITY_MISMATCH);
        require(askIds.length == new_acls.length, Error.ARITY_MISMATCH);

        bytes32 messageHash = keccak256(abi.encode(askIds, newTaskIds, generators, new_acls));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        require(hasRole(MATCHING_ENGINE_ROLE, signer), Error.ONLY_MATCHING_ENGINE_CAN_ASSIGN);
        for (uint256 index = 0; index < askIds.length; index++) {
            _assignTask(askIds[index], newTaskIds[index], generators[index], new_acls[index]);
        }
    }

    function relayAssignTask(
        uint256 askId,
        uint256 newTaskId,
        address generator,
        bytes calldata new_acl,
        bytes calldata signature
    ) public {
        bytes32 messageHash = keccak256(abi.encode(askId, newTaskId, generator, new_acl));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        require(hasRole(MATCHING_ENGINE_ROLE, signer), Error.ONLY_MATCHING_ENGINE_CAN_ASSIGN);
        _assignTask(askId, newTaskId, generator, new_acl);
    }

    function assignTask(
        uint256 askId,
        uint256 newTaskId,
        address generator,
        bytes calldata new_acl
    ) external onlyRole(MATCHING_ENGINE_ROLE) {
        _assignTask(askId, newTaskId, generator, new_acl);
    }

    function _assignTask(
        uint256 askId,
        uint256 newTaskId, // acts as nonce,
        address generator,
        bytes memory new_acl
    ) internal {
        require(newTaskId == taskCounter, Error.INVALID_TASK_ID); //protection against replay
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

        listOfTask[taskCounter] = Task(askId, generator);

        uint256 generatorAmountToLock = marketData[askWithState.ask.marketId].slashingPenalty;
        GENERATOR_REGISTRY.assignGeneratorTask(generator, askWithState.ask.marketId, generatorAmountToLock);
        emit TaskCreated(askId, taskCounter, generator, new_acl);

        taskCounter++;
    }

    function cancelAsk(uint256 askId) external {
        require(getAskState(askId) == AskState.UNASSIGNED, Error.ONLY_EXPIRED_ASKS_CAN_BE_CANCELLED);
        AskWithState storage askWithState = listOfAsk[askId];
        askWithState.state = AskState.COMPLETE;

        PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, askWithState.ask.reward);

        emit AskCancelled(askId);
    }

    function submitProofs(uint256[] memory taskIds, bytes[] calldata proofs) public {
        require(taskIds.length == proofs.length, Error.ARITY_MISMATCH);
        for (uint256 index = 0; index < taskIds.length; index++) {
            submitProof(taskIds[index], proofs[index]);
        }
    }

    function submitProof(uint256 taskId, bytes calldata proof) public {
        Task memory task = listOfTask[taskId];
        AskWithState memory askWithState = listOfAsk[task.askId];

        bytes32 marketId = askWithState.ask.marketId;
        IVerifier proofVerifier = IVerifier(marketData[marketId].verifier);

        (address generatorRewardAddress, uint256 minRewardForGenerator) = GENERATOR_REGISTRY.getGeneratorRewardDetails(
            task.generator,
            askWithState.ask.marketId
        );

        require(generatorRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(getAskState(task.askId) == AskState.ASSIGNED, Error.ONLY_ASSIGNED_ASKS_CAN_BE_PROVED);
        // check what needs to be encoded from proof, ask and task for proof to be verified

        bytes memory inputAndProof = abi.encode(askWithState.ask.proverData, proof);
        require(proofVerifier.verify(inputAndProof), Error.INVALID_PROOF);
        listOfAsk[task.askId].state = AskState.COMPLETE;

        uint256 toBackToProver = askWithState.ask.reward - minRewardForGenerator;

        if (minRewardForGenerator != 0) {
            PAYMENT_TOKEN.safeTransfer(generatorRewardAddress, minRewardForGenerator);
        }

        if (toBackToProver != 0) {
            PAYMENT_TOKEN.safeTransfer(askWithState.ask.refundAddress, toBackToProver);
        }

        uint256 generatorAmountToRelease = marketData[marketId].slashingPenalty;
        GENERATOR_REGISTRY.completeGeneratorTask(task.generator, marketId, generatorAmountToRelease);
        emit ProofCreated(task.askId, taskId, proof);
    }

    function slashGenerator(uint256 taskId, address rewardAddress) external returns (uint256) {
        Task memory task = listOfTask[taskId];

        require(getAskState(task.askId) == AskState.DEADLINE_CROSSED, Error.SHOULD_BE_IN_CROSSED_DEADLINE_STATE);
        return _slashGenerator(taskId, task, rewardAddress);
    }

    function discardRequest(uint256 taskId) external returns (uint256) {
        Task memory task = listOfTask[taskId];
        require(getAskState(task.askId) == AskState.ASSIGNED, Error.SHOULD_BE_IN_ASSIGNED_STATE);
        require(task.generator == msg.sender, Error.ONLY_GENERATOR_CAN_DISCARD_REQUEST);
        return _slashGenerator(taskId, task, TREASURY);
    }

    function _slashGenerator(uint256 taskId, Task memory task, address rewardAddress) internal returns (uint256) {
        listOfAsk[task.askId].state = AskState.COMPLETE;
        bytes32 marketId = listOfAsk[task.askId].ask.marketId;

        emit ProofNotGenerated(task.askId, taskId);
        return
            GENERATOR_REGISTRY.slashGenerator(
                task.generator,
                marketId,
                marketData[marketId].slashingPenalty,
                rewardAddress
            );
    }

    function slashingPenalty(bytes32 marketId) public view returns (uint256) {
        return marketData[marketId].slashingPenalty;
    }

    function verifier(bytes32 marketId) public view returns (address) {
        return marketData[marketId].verifier;
    }

    function askCounter() public view returns (uint256) {
        return listOfAsk.length;
    }
}
