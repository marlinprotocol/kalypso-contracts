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
import "./interfaces/IRsaRegistry.sol";

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
        if (role == DEFAULT_ADMIN_ROLE) {
            // this does not need attestation
            super._grantRole(role, account);
        } else {
            // TODO: use the actual data
            bytes memory data = abi.encode(account, attestation_data);
            require(rsaRegistry.attestationVerifier().verify(data), Error.ENCLAVE_KEY_NOT_VERIFIED);
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

    function _authorizeUpgrade(address /*account*/) internal view override onlyAdmin {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Constants and Immutable start --------------------------------//
    bytes32 public constant UPDATER_ROLE = bytes32(uint256(keccak256("updater")) - 1);
    bytes32 public constant MATCHING_ENGINE_ROLE = bytes32(uint256(keccak256("matching engine")) - 1);

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable paymentToken;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable platformToken;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable marketCreationCost;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable treasury;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IGeneratorRegistry public immutable generatorRegistry;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRsaRegistry public immutable rsaRegistry;

    uint256 public constant costPerInputBytes = 10e15;

    uint256 private constant MIN_STAKE_FOR_PARTICIPATING = 1e18;
    uint256 private constant EXPONENT = 1e18;

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(bytes32 => bytes) public marketmetadata;
    mapping(bytes32 => address) public override verifier; // verifier address for the market place
    mapping(bytes32 => uint256) public override minStakeToJoin;
    mapping(bytes32 => uint256) public slashingPenalty;

    uint256 public askCounter;
    mapping(uint256 => AskWithState) public listOfAsk;

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
        IRsaRegistry _rsaRegistry
    ) {
        paymentToken = _paymentToken;
        platformToken = _platformToken;
        marketCreationCost = _marketCreationCost;
        treasury = _treasury;
        generatorRegistry = _generatorRegistry;
        rsaRegistry = _rsaRegistry;
    }

    function initialize(address _admin) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(MATCHING_ENGINE_ROLE, DEFAULT_ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), Error.ONLY_ADMIN_CAN_CALL);
        _;
    }

    function createMarketPlace(
        bytes calldata _marketmetadata,
        address _verifier,
        uint256 _minStake,
        uint256 _slashingPenalty
    ) external override {
        require(_minStake >= MIN_STAKE_FOR_PARTICIPATING, Error.INSUFFICIENT_STAKE);
        require(_slashingPenalty <= EXPONENT, Error.SHOULD_BE_LESS_THAN_OR_EQUAL); // 1e18 means 100% stake will be slashed

        paymentToken.safeTransferFrom(_msgSender(), treasury, marketCreationCost);

        bytes32 marketId = keccak256(_marketmetadata);
        require(marketmetadata[marketId].length == 0, Error.ALREADY_EXISTS);
        require(_verifier != address(0), Error.CANNOT_BE_ZERO);

        marketmetadata[marketId] = _marketmetadata;
        verifier[marketId] = _verifier;
        minStakeToJoin[marketId] = _minStake;
        slashingPenalty[marketId] = _slashingPenalty;

        emit MarketPlaceCreated(marketId);
    }

    function createAsk(
        Ask calldata ask,
        bool hasPrivateInputs,
        SecretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) external override {
        require(ask.reward != 0, Error.CANNOT_BE_ZERO);
        require(ask.proverData.length != 0, Error.CANNOT_BE_ZERO);
        require(ask.expiry > block.number, Error.CANT_BE_IN_PAST);

        address _msgSender = _msgSender();
        uint256 platformFee = ask.proverData.length * costPerInputBytes;

        paymentToken.safeTransferFrom(_msgSender, address(this), ask.reward);
        platformToken.safeTransferFrom(_msgSender, treasury, platformFee);

        require(marketmetadata[ask.marketId].length != 0, Error.DOES_NOT_EXISTS);
        listOfAsk[askCounter] = AskWithState(ask, AskState.CREATE, _msgSender);

        IVerifier inputVerifier = IVerifier(verifier[ask.marketId]);
        require(inputVerifier.verifyInputs(ask.proverData), Error.INVALID_INPUTS);

        emit AskCreated(askCounter, hasPrivateInputs, secret_inputs, acl);
        askCounter++;
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
        bytes memory rsa_pub,
        bytes memory attestation_data
    ) external onlyRole(MATCHING_ENGINE_ROLE) {
        rsaRegistry.updatePubkey(rsa_pub, attestation_data);
    }

    function relayBatchAssignTasks(
        uint256[] memory askIds,
        uint256[] memory newTaskIds,
        address[] memory generators,
        bytes[] memory new_acls,
        bytes calldata signature
    ) public {
        require(askIds.length == newTaskIds.length, Error.ARITY_MISMATCH);
        require(askIds.length == generators.length, Error.ARITY_MISMATCH);
        require(askIds.length == new_acls.length, Error.ARITY_MISMATCH);

        bytes32 messageHash = keccak256(abi.encode(askIds, newTaskIds, generators, new_acls));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        require(hasRole(MATCHING_ENGINE_ROLE, signer), Error.INVAlID_SENDER);
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

        require(hasRole(MATCHING_ENGINE_ROLE, signer), Error.INVAlID_SENDER);
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
        require(newTaskId == taskCounter, Error.SHOULD_BE_SAME); //protection against replay
        require(getAskState(askId) == AskState.CREATE, Error.SHOULD_BE_IN_CREATE_STATE);

        AskWithState storage askWithState = listOfAsk[askId];
        (uint256 minRewardForGenerator, uint256 generatorProposedTime) = generatorRegistry
            .getGeneratorAssignmentDetails(generator, askWithState.ask.marketId);

        require(askWithState.ask.reward > minRewardForGenerator, Error.INSUFFICIENT_REWARD);
        require(
            askWithState.ask.timeTakenForProofGeneration >= generatorProposedTime,
            Error.PROOF_REQUESTED_IN_LESS_TIME
        );
        askWithState.state = AskState.ASSIGNED;
        askWithState.ask.deadline = block.number + askWithState.ask.timeTakenForProofGeneration;

        listOfTask[taskCounter] = Task(askId, generator);

        generatorRegistry.assignGeneratorTask(generator, askWithState.ask.marketId);
        emit TaskCreated(askId, taskCounter, generator, new_acl);

        taskCounter++;
    }

    function cancelAsk(uint256 askId) external {
        require(getAskState(askId) == AskState.UNASSIGNED, Error.SHOULD_BE_IN_EXPIRED_STATE);
        AskWithState storage askWithState = listOfAsk[askId];
        askWithState.state = AskState.COMPLETE;

        paymentToken.safeTransfer(askWithState.ask.refundAddress, askWithState.ask.reward);

        emit AskCancelled(askId);
    }

    function submitProofs(uint256[] memory taskIds, bytes[] calldata proofs) external {
        require(taskIds.length == proofs.length, Error.ARITY_MISMATCH);
        for (uint256 index = 0; index < taskIds.length; index++) {
            submitProof(taskIds[index], proofs[index]);
        }
    }

    function submitProof(uint256 taskId, bytes calldata proof) public {
        Task memory task = listOfTask[taskId];
        AskWithState memory askWithState = listOfAsk[task.askId];

        bytes32 marketId = askWithState.ask.marketId;
        IVerifier proofVerifier = IVerifier(verifier[marketId]);

        (address generatorRewardAddress, uint256 minRewardForGenerator) = generatorRegistry.getGeneratorRewardDetails(
            task.generator,
            askWithState.ask.marketId
        );

        require(generatorRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(getAskState(task.askId) == AskState.ASSIGNED, Error.SHOULD_BE_IN_ASSIGNED_STATE);
        // check what needs to be encoded from proof, ask and task for proof to be verified

        bytes memory inputAndProof = abi.encode(askWithState.ask.proverData, proof);
        require(proofVerifier.verify(inputAndProof), Error.INVALID_PROOF);
        listOfAsk[task.askId].state = AskState.COMPLETE;

        uint256 toBackToProver = askWithState.ask.reward - minRewardForGenerator;

        if (minRewardForGenerator != 0) {
            paymentToken.safeTransfer(generatorRewardAddress, minRewardForGenerator);
        }

        if (toBackToProver != 0) {
            paymentToken.safeTransfer(askWithState.ask.refundAddress, toBackToProver);
        }

        generatorRegistry.completeGeneratorTask(task.generator, marketId);
        emit ProofCreated(task.askId, taskId);
    }

    function slashGenerator(uint256 taskId, address rewardAddress) external returns (uint256) {
        Task memory task = listOfTask[taskId];

        require(getAskState(task.askId) == AskState.DEADLINE_CROSSED, Error.SHOULD_BE_IN_CROSSED_DEADLINE_STATE);
        return _slashGenerator(taskId, task, rewardAddress);
    }

    function discardRequest(uint256 taskId) external returns (uint256) {
        Task memory task = listOfTask[taskId];
        require(getAskState(task.askId) == AskState.ASSIGNED, Error.SHOULD_BE_IN_ASSIGNED_STATE);
        require(task.generator == msg.sender, Error.ONLY_TASKS_GENERATOR);
        return _slashGenerator(taskId, task, treasury);
    }

    function _slashGenerator(uint256 taskId, Task memory task, address rewardAddress) internal returns (uint256) {
        listOfAsk[task.askId].state = AskState.COMPLETE;
        bytes32 marketId = listOfAsk[task.askId].ask.marketId;

        emit ProofNotGenerated(task.askId, taskId);
        return generatorRegistry.slashGenerator(task.generator, marketId, rewardAddress);
    }
}
