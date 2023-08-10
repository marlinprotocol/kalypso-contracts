// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IProofMarketPlace.sol";
import "./interfaces/IGeneratorRegsitry.sol";
import "./interfaces/IVerifier.sol";

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

    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, "Cannot be adminless");
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

    uint256 public constant costPerInputBytes = 10e15;
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    address public treasury;

    mapping(bytes32 => bytes) public marketmetadata;
    mapping(bytes32 => address) public verifier; // verifier address for the market place

    uint256 public askCounter;
    mapping(uint256 => AskWithState) public listOfAsk;

    uint256 public taskCounter;
    mapping(uint256 => Task) public listOfTask;

    IGeneratorRegistry public generatorRegistry;

    //-------------------------------- State variables end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _paymentToken, IERC20Upgradeable _platformToken, uint256 _marketCreationCost) {
        paymentToken = _paymentToken;
        platformToken = _platformToken;
        marketCreationCost = _marketCreationCost;
    }

    function initialize(address _admin, address _treasury, IGeneratorRegistry _generatorRegistry) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(MATCHING_ENGINE_ROLE, DEFAULT_ADMIN_ROLE);

        treasury = _treasury;
        generatorRegistry = _generatorRegistry;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), Error.ONLY_ADMIN_CAN_CALL);
        _;
    }

    // function changeTreasuryAddressChanged(address _newAddress) public onlyRole(UPDATER_ROLE) {
    //     require(_newAddress != treasury, Error.ALREADY_EXISTS);
    //     address _oldAddress = treasury;
    //     treasury = _newAddress;
    //     emit TreasuryAddressChanged(_oldAddress, _newAddress);
    // }

    function changeGeneratorRegsitry(address _newAddress) public onlyRole(UPDATER_ROLE) {
        require(_newAddress != address(generatorRegistry), Error.ALREADY_EXISTS);
        IGeneratorRegistry _oldAddress = generatorRegistry;
        generatorRegistry = IGeneratorRegistry(_newAddress);
        emit GeneratorRegistryChanged(address(_oldAddress), _newAddress);
    }

    /// TODO: Confirm with V and K
    /// inside marketmetadata store the following
    /// - github link for the generator code
    /// - public and private input formats
    /// - minimum computation requirement for the proof to be generated for this circuit
    function createMarketPlace(bytes calldata _marketmetadata, address _verifier) external override {
        paymentToken.safeTransferFrom(_msgSender(), treasury, marketCreationCost);

        bytes32 marketId = keccak256(_marketmetadata);
        require(marketmetadata[marketId].length == 0, Error.ALREADY_EXISTS);
        require(_verifier != address(0), Error.CANNOT_BE_ZERO);
        marketmetadata[marketId] = _marketmetadata;
        verifier[marketId] = _verifier;

        emit MarketPlaceCreated(marketId);
    }

    function getMarketVerifier(bytes32 marketId) public view returns (address) {
        return verifier[marketId];
    }

    function createAsk(Ask calldata ask) external override {
        require(ask.reward != 0, Error.CANNOT_BE_ZERO);
        require(ask.proverData.length != 0, Error.CANNOT_BE_ZERO);

        address _msgSender = _msgSender();
        uint256 platformFee = ask.proverData.length * costPerInputBytes;

        paymentToken.safeTransferFrom(_msgSender, address(this), ask.reward);
        platformToken.safeTransferFrom(_msgSender, treasury, platformFee);

        require(marketmetadata[ask.marketId].length != 0, Error.DOES_NOT_EXISTS);
        listOfAsk[askCounter] = AskWithState(ask, AskState.CREATE);

        IVerifier inputVerifier = IVerifier(verifier[ask.marketId]);
        require(inputVerifier.verifyInputs(ask.proverData), Error.INVALID_INPUTS);

        emit AskCreated(askCounter);
        askCounter++;
    }

    // Todo: Optimise the function
    function getAskState(uint256 askId) public view returns (AskState) {
        AskWithState memory askWithState = listOfAsk[askId];

        if (askWithState.state == AskState.CREATE) {
            if (askWithState.ask.expiry > block.number) {
                return AskState.CREATE;
            }

            return AskState.UNASSIGNED;
        }

        if (askWithState.state == AskState.ASSIGNED) {
            if (askWithState.ask.deadline < block.number) {
                return AskState.DEADLINE_CROSSED;
            }

            return AskState.ASSIGNED;
        }

        return AskState.NULL;
    }

    // Todo: Optimise the function
    function assignTask(uint256 askId, address generator) external onlyRole(MATCHING_ENGINE_ROLE) {
        require(getAskState(askId) == AskState.CREATE, Error.SHOULD_BE_IN_CREATE_STATE);

        AskWithState storage askWithState = listOfAsk[askId];
        (, uint256 minRewardForGenerator, ) = generatorRegistry.getGeneratorDetails(
            generator,
            askWithState.ask.marketId
        );

        require(askWithState.ask.reward > minRewardForGenerator, Error.INSUFFICIENT_REWARD);
        askWithState.state = AskState.ASSIGNED;
        askWithState.ask.deadline = block.number + askWithState.ask.timeTakenForProofGeneration;

        listOfTask[taskCounter] = Task(askId, generator);

        generatorRegistry.assignGeneratorTask(generator, askWithState.ask.marketId);
        emit TaskCreated(askId, taskCounter);

        taskCounter++;
    }

    function cancelAsk(uint256 askId) external {
        require(getAskState(askId) == AskState.UNASSIGNED, Error.SHOULD_BE_IN_EXPIRED_STATE);
        AskWithState storage askWithState = listOfAsk[askId];
        askWithState.state = AskState.COMPLETE;

        paymentToken.safeTransfer(askWithState.ask.proverRefundAddress, askWithState.ask.reward);

        emit AskCancelled(askId);
    }

    function submitProof(uint256 taskId, bytes calldata proof) external {
        Task memory task = listOfTask[taskId];
        AskWithState memory askWithState = listOfAsk[task.askId];

        bytes32 marketId = askWithState.ask.marketId;
        IVerifier proofVerifier = IVerifier(verifier[marketId]);

        (, uint256 minRewardForGenerator, address generatorRewardAddress) = generatorRegistry.getGeneratorDetails(
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

        paymentToken.safeTransfer(generatorRewardAddress, minRewardForGenerator);

        if (toBackToProver != 0) {
            paymentToken.safeTransfer(askWithState.ask.proverRefundAddress, toBackToProver);
        }

        generatorRegistry.completeGeneratorTask(task.generator, marketId);
        emit ProofCreated(taskId);
    }

    function slashGenerator(uint256 taskId, address rewardAddress) external returns (uint256) {
        Task memory task = listOfTask[taskId];

        require(getAskState(task.askId) == AskState.DEADLINE_CROSSED, Error.SHOULD_BE_IN_CROSSED_DEADLINE_STATE);
        listOfAsk[task.askId].state = AskState.COMPLETE;
        bytes32 marketId = listOfAsk[task.askId].ask.marketId;

        emit ProofNotGenerated(taskId);
        return generatorRegistry.slashGenerator(task.generator, marketId, rewardAddress);
    }
}
