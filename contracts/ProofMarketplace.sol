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
import "./ProverRegistry.sol";
import "./lib/Error.sol";
import "./interfaces/IProofMarketplace.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ProofMarketplace is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IProofMarketplace
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IERC20Upgradeable _paymentToken,
        uint256 _marketCreationCost,
        address _treasury,
        ProverRegistry _proverRegistry,
        EntityKeyRegistry _entityRegistry
    ) initializer {
        PAYMENT_TOKEN = _paymentToken;
        MARKET_CREATION_COST = _marketCreationCost;
        TREASURY = _treasury;
        PROVER_REGISTRY = _proverRegistry;
        ENTITY_KEY_REGISTRY = _entityRegistry;
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

    bytes32 public constant SYMBIOTIC_STAKING_ROLE = keccak256("SYMBIOTIC_STAKING_ROLE");
    bytes32 public constant SYMBIOTIC_STAKING_REWARD_ROLE = keccak256("SYMBIOTIC_STAKING_REWARD_ROLE");

    uint256 public constant MARKET_ACTIVATION_DELAY = 100; // in blocks

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable PAYMENT_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable MARKET_CREATION_COST;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable TREASURY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ProverRegistry public immutable PROVER_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    bytes32 public constant MATCHING_ENGINE_ROLE = keccak256("MATCHING_ENGINE_ROLE");

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    Market[] public marketData;

    BidWithState[] public listOfBid;

    // cost for inputs
    mapping(SecretType => uint256) public costPerInputBytes;
    // min proving time (in blocks) for each secret type.
    mapping(SecretType => uint256) public minProvingTime;

    mapping(address => uint256) public claimableAmount;

    // operator deducts comission from inflation reward
    mapping(address operator => uint256 rewardShare) public operatorRewardShares; // 1e18 == 100%

    struct Market {
        IVerifier verifier; // verifier address for the market place
        bytes32 proverImageId; // use bytes32(0) for public market
        uint256 slashingPenalty;
        uint256 activationBlock;
        bytes32 ivsImageId;
        address creator;
        bytes marketmetadata;
    }

    enum BidState {
        NULL,
        CREATE,
        UNASSIGNED,
        ASSIGNED,
        COMPLETE,
        DEADLINE_CROSSED
    }

    struct Bid {
        uint256 marketId;
        uint256 reward;
        // the block number by which the bid should be assigned by matching engine
        uint256 expiry;
        uint256 timeTakenForProofGeneration;
        uint256 deadline;
        address refundAddress;
        bytes proverData;
    }

    struct BidWithState {
        Bid bid;
        BidState state;
        address requester;
        address prover;
    }

    //-------------------------------- State variables end --------------------------------//

    function initialize(address _admin) external initializer {
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
        // TODO: understand this logic
        if (_proverPcrs.GET_IMAGE_ID_FROM_PCRS().IS_ENCLAVE()) {
            ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.PROVER_FAMILY_ID(), _proverPcrs);
        }

        // ivs is always enclave, will revert if a non enclave instance is stated as an ivs
        // TODO: understand this logic
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
                bytes32 familyId = marketId.PROVER_FAMILY_ID();
                bytes32 proverImageId = _proverPcrs[index].GET_IMAGE_ID_FROM_PCRS();
                if (ENTITY_KEY_REGISTRY.isImageInFamily(proverImageId, familyId)) {
                    revert Error.ImageAlreadyInFamily(proverImageId, familyId);
                }
                ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(familyId, _proverPcrs[index]);
                emit AddExtraProverImage(marketId, proverImageId);
            }
        }

        for (uint256 index = 0; index < _ivsPcrs.length; index++) {
            bytes32 familyId = marketId.IVS_FAMILY_ID();
            bytes32 ivsImageId = _ivsPcrs[index].GET_IMAGE_ID_FROM_PCRS();
            if (ENTITY_KEY_REGISTRY.isImageInFamily(ivsImageId, familyId)) {
                revert Error.ImageAlreadyInFamily(ivsImageId, familyId);
            }
            ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(familyId, _ivsPcrs[index]);
            emit AddExtraIVSImage(marketId, ivsImageId);
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
                ENTITY_KEY_REGISTRY.removeEnclaveImageFromFamily(imageId, marketId.PROVER_FAMILY_ID());
                emit RemoveExtraProverImage(marketId, imageId);
            }
        }

        for (uint256 index = 0; index < _ivsPcrs.length; index++) {
            bytes32 imageId = _ivsPcrs[index].GET_IMAGE_ID_FROM_PCRS();
            if (imageId == market.ivsImageId) {
                revert Error.CannotRemoveDefaultImageFromMarket(marketId, imageId);
            }
            ENTITY_KEY_REGISTRY.removeEnclaveImageFromFamily(imageId, marketId.IVS_FAMILY_ID());
            emit RemoveExtraIVSImage(marketId, imageId);
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

        // TODO: why doing this way?
        delete marketData[marketId].creator;
    }

    /**
     * @notice Create requests. Can be paused to prevent temporary escrowing of unwanted amount
     * @param bid: Details of the BID request
     * @param secretType: 0 for purely calldata based secret (1 for Celestia etc, 2 ipfs etc)
     * @param privateInputs: Private Inputs to the circuit.
     * @param acl: If the private inputs are mean't to be confidential, provide acl using the ME keys
     */
        // TODO: Check if this needs to be removed during review
    function createBid(
        Bid calldata bid,
        SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl
    ) external whenNotPaused nonReentrant {
        _createBid(bid, msg.sender, secretType, privateInputs, acl);
    }

    function _createBid(
        Bid calldata bid,
        address payFrom,
        SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl
    ) internal {
        if (bid.reward == 0 || bid.proverData.length == 0) {
            revert Error.CannotBeZero();
        }
        if (bid.expiry <= block.number + minProvingTime[secretType]) {
            revert Error.CannotAssignExpiredTasks();
        }

        // ensures that the cipher used is small enough
        if (acl.length > 130) {
            revert Error.InvalidECIESACL();
        }

        Market memory market = marketData[bid.marketId];
        if (block.number < market.activationBlock) {
            revert Error.InactiveMarket();
        }

        uint256 platformFee = getPlatformFee(secretType, bid, privateInputs, acl);

        PAYMENT_TOKEN.safeTransferFrom(payFrom, address(this), bid.reward + platformFee);
        PAYMENT_TOKEN.safeTransfer(TREASURY, platformFee);

        if (market.marketmetadata.length == 0) {
            revert Error.InvalidMarket();
        }

        uint256 bidId = listOfBid.length;
        BidWithState memory bidRequest = BidWithState(bid, BidState.CREATE, msg.sender, address(0));
        listOfBid.push(bidRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);

        if (!inputVerifier.verifyInputs(bid.proverData)) {
            revert Error.InvalidInputs();
        }

        if (market.proverImageId.IS_ENCLAVE()) {
            // ACL is emitted if private
            emit BidCreated(bidId, true, privateInputs, acl);
        } else {
            // ACL is not emitted if not private
            emit BidCreated(bidId, false, "", "");
        }
    }

    /**
     * @notice Different secret might have different fee. Hence fee is different
     * @param secretType: Secret Type
     * @param bid: Details of the bid
     * @param privateInputs: Private Inputs to the circuit
     * @param acl: Access control Data
     */
    function getPlatformFee(
        SecretType secretType,
        Bid calldata bid,
        bytes calldata privateInputs,
        bytes calldata acl
    ) public view returns (uint256) {
        uint256 costperByte = costPerInputBytes[secretType];
        if (costperByte != 0) {
            return (bid.proverData.length + privateInputs.length + acl.length) * costperByte;
        }
        return 0;
    }

    /**
     * @notice Update Cost for inputs
     */
    function updateCostPerBytes(SecretType secretType, uint256 costPerByte) external onlyRole(UPDATER_ROLE) {
        costPerInputBytes[secretType] = costPerByte;

        emit UpdateCostPerBytes(secretType, costPerByte);
    }

    /**
     * @notice Update Min Proving Time
     */
    function updateMinProvingTime(SecretType secretType, uint256 newProvingTime) external onlyRole(UPDATER_ROLE) {
        minProvingTime[secretType] = newProvingTime;

        emit UpdateMinProvingTime(secretType, newProvingTime);
    }

    /**
     @notice Possible States: NULL, CREATE, UNASSIGNED, ASSIGNED, COMPLETE, DEADLINE_CROSSED
     */
    function getBidState(uint256 bidId) public view returns (BidState) {
        BidWithState memory bidWithState = listOfBid[bidId];

        // time before which matching engine should assign the task to prover
        if (bidWithState.state == BidState.CREATE) {
            if (bidWithState.bid.expiry > block.number) {
                return bidWithState.state;
            }

            return BidState.UNASSIGNED;
        }

        // time before which prover should submit the proof
        if (bidWithState.state == BidState.ASSIGNED) {
            if (bidWithState.bid.deadline < block.number) {
                return BidState.DEADLINE_CROSSED;
            }

            return BidState.ASSIGNED;
        }

        return bidWithState.state;
    }

    /**
     * @notice Assign Tasks for Provers. Only Matching Engine Image can call
     */
    function relayBatchAssignTasks(
        uint256[] memory bidIds,
        address[] memory provers,
        bytes[] calldata newAcls,
        bytes calldata signature
    ) external nonReentrant {
        if (bidIds.length != provers.length || provers.length != newAcls.length) {
            revert Error.ArityMismatch();
        }

        bytes32 messageHash = keccak256(abi.encode(bidIds, provers, newAcls));
        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, signature);

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), signer);

        for (uint256 index = 0; index < bidIds.length; index++) {
            _assignTask(bidIds[index], provers[index], newAcls[index]);
        }
    }

    /**
     * @notice Assign Tasks for Provers directly if ME signer has the gas
     */
    // TODO: add this function back(commented due to size)
    // function assignTask(uint256 askId, address prover, bytes calldata new_acl) external nonReentrant {
    //     ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), _msgSender());
    //     _assignTask(askId, prover, new_acl);
    // }

    function _assignTask(uint256 bidId, address prover, bytes memory new_acl) internal {
        // Only tasks in CREATE state can be assigned
        if (getBidState(bidId) != BidState.CREATE) {
            revert Error.ShouldBeInCreateState();
        }

        BidWithState storage bidWithState = listOfBid[bidId];
        (uint256 proofGenerationCost, uint256 proverProposedTime) = PROVER_REGISTRY.getProverAssignmentDetails(
            prover,
            bidWithState.bid.marketId
        );

        // Can not assign task if price mismatch happens
        if (bidWithState.bid.reward < proofGenerationCost) {
            revert Error.ProofPriceMismatch(bidId);
        }

        // Can not assign task if time mismatch happens
        if (bidWithState.bid.timeTakenForProofGeneration < proverProposedTime) {
            revert Error.ProofTimeMismatch(bidId);
        }

        bidWithState.state = BidState.ASSIGNED;
        bidWithState.bid.deadline = block.number + bidWithState.bid.timeTakenForProofGeneration;
        bidWithState.prover = prover;

        PROVER_REGISTRY.assignProverTask(bidId, prover, bidWithState.bid.marketId);
        emit TaskCreated(bidId, prover, new_acl);
    }

    /**
     * @notice Cancel the unassigned request. Refunds the proof fee back to the requestor
     */
    function cancelBid(uint256 bidId) external nonReentrant {
        // Only unassigned tasks can be cancelled.
        if (getBidState(bidId) != BidState.UNASSIGNED) {
            revert Error.OnlyExpiredBidsCanBeCancelled(bidId);
        }
        BidWithState storage bidWithState = listOfBid[bidId];
        bidWithState.state = BidState.COMPLETE;

        PAYMENT_TOKEN.safeTransfer(bidWithState.bid.refundAddress, bidWithState.bid.reward);

        emit BidCancelled(bidId);
    }

    function _verifyAndGetData(uint256 bidId, BidWithState memory bidWithState) internal view returns (uint256, address) {
        (address proverRewardAddress, uint256 minRewardForProver) = PROVER_REGISTRY.getProverRewardDetails(
            bidWithState.prover,
            bidWithState.bid.marketId
        );

        if (proverRewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        if (getBidState(bidId) != BidState.ASSIGNED) {
            revert Error.OnlyAssignedBidsCanBeProved(bidId);
        }

        return (minRewardForProver, proverRewardAddress);
    }

    function _completeProofForInvalidRequests(
        uint256 bidId,
        BidWithState memory bidWithState,
        uint256 minRewardForProver,
        address proverRewardAddress,
        uint256 marketId
    ) internal {
        // Only assigned requests can be proved
        if (getBidState(bidId) != BidState.ASSIGNED) {
            revert Error.OnlyAssignedBidsCanBeProved(bidId);
        }
        listOfBid[bidId].state = BidState.COMPLETE;

        // tokens related to incorrect request will be sen't to treasury
        uint256 toTreasury = bidWithState.bid.reward - minRewardForProver;

        // transfer the reward to prover
        uint256 feeRewardRemaining = _distributeOperatorFeeReward(proverRewardAddress, minRewardForProver);

        // transfer the amount to treasury collection
        PAYMENT_TOKEN.safeTransfer(TREASURY, toTreasury);

        PROVER_REGISTRY.completeProverTask(bidId, bidWithState.prover, marketId, feeRewardRemaining);
        emit InvalidInputsDetected(bidId);
    }

    /**
     * @notice Submit Attestation/Proof from the IVS signer that the given inputs are invalid
     */
    function submitProofForInvalidInputs(uint256 bidId, bytes calldata invalidProofSignature) external nonReentrant {
        BidWithState memory bidWithState = listOfBid[bidId];
        uint256 marketId = bidWithState.bid.marketId;

        (uint256 minRewardForProver, address proverRewardAddress) = _verifyAndGetData(bidId, bidWithState);

        if (!_checkDisputeUsingSignature(bidId, bidWithState.bid.proverData, invalidProofSignature, marketId.IVS_FAMILY_ID())) {
            revert Error.CannotSlashUsingValidInputs(bidId);
        }

        _completeProofForInvalidRequests(
            bidId,
            bidWithState,
            minRewardForProver,
            proverRewardAddress,
            marketId
        );
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    // TODO: add this function back(commented due to size)
    // function submitProofs(uint256[] memory taskIds, bytes[] calldata proofs) external nonReentrant {
    //     if (taskIds.length != proofs.length) {
    //         revert Error.ArityMismatch();
    //     }
    //     for (uint256 index = 0; index < taskIds.length; index++) {
    //         _submitProof(taskIds[index], proofs[index]);
    //     }
    // }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 bidId, bytes calldata proof) external nonReentrant {
        _submitProof(bidId, proof);
    }

    function _submitProof(uint256 bidId, bytes calldata proof) internal {
        BidWithState memory bidWithState = listOfBid[bidId];

        uint256 marketId = bidWithState.bid.marketId;

        (address proverRewardAddress, uint256 minRewardForProver) = PROVER_REGISTRY.getProverRewardDetails(
            bidWithState.prover,
            bidWithState.bid.marketId
        );

        if (proverRewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        if (getBidState(bidId) != BidState.ASSIGNED) {
            revert Error.OnlyAssignedBidsCanBeProved(bidId);
        }
        // check what needs to be encoded from proof, bid and task for proof to be verified

        bytes memory inputAndProof = abi.encode(bidWithState.bid.proverData, proof);

        // Verify input and proof against verifier
        if (!marketData[marketId].verifier.verify(inputAndProof)) {
            revert Error.InvalidProof(bidId);
        }
        listOfBid[bidId].state = BidState.COMPLETE;

        uint256 toBackToRequestor = bidWithState.bid.reward - minRewardForProver;

        // reward to prover
        uint256 feeRewardRemaining = _distributeOperatorFeeReward(proverRewardAddress, minRewardForProver);

        // fraction of amount back to requestor
        PAYMENT_TOKEN.safeTransfer(bidWithState.bid.refundAddress, toBackToRequestor);

        // TODO: consider setting slashingPenalty per market
        // uint256 proverAmountToRelease = _slashingPenalty(marketId);
        PROVER_REGISTRY.completeProverTask(bidId, bidWithState.prover, marketId, feeRewardRemaining);
        emit ProofCreated(bidId, proof);
    }

    /**
     * @notice Slash Prover for deadline crossed requests
     */
    // TODO: fix logic of this function
    function slashProver(uint256 bidId) external nonReentrant {
        if (getBidState(bidId) != BidState.DEADLINE_CROSSED) {
            revert Error.ShouldBeInCrossedDeadlineState(bidId);
        }
        _slashProver(bidId);
    }

    /**
     * @notice Prover can discard assigned request if he choses to. This will however result in slashing
     */
    // TODO: what's this?
    function discardRequest(uint256 bidId) external nonReentrant {
        BidWithState memory bidWithState = listOfBid[bidId];
        if (getBidState(bidId) != BidState.ASSIGNED) {
            revert Error.ShouldBeInAssignedState(bidId);
        }
        if (bidWithState.prover != _msgSender()) {
            revert Error.OnlyProverCanDiscardRequest(bidId);
        }
        _slashProver(bidId);
    }

    function _slashProver(uint256 bidId) internal {
        BidWithState storage bidWithState = listOfBid[bidId];

        bidWithState.state = BidState.COMPLETE;
        uint256 marketId = bidWithState.bid.marketId;

        if(bidWithState.bid.reward != 0) {
            PAYMENT_TOKEN.safeTransfer(bidWithState.bid.refundAddress, bidWithState.bid.reward);
            bidWithState.bid.reward = 0;
            emit ProofNotGenerated(bidId);
            PROVER_REGISTRY.releaseProverResources(bidWithState.prover, marketId);
        }
    }

    function _slashingPenalty(uint256 marketId) internal view returns (uint256) {
        return marketData[marketId].slashingPenalty;
    }

    // TODO: change name to "claimRewards" (operator / prover)
    function flush(address _address) external {
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
        uint256 bidId,
        bytes memory proverData,
        bytes memory invalidProofSignature,
        bytes32 familyId
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(bidId, proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, invalidProofSignature);
        if (signer == address(0)) {
            revert Error.InvalidEnclaveSignature(signer);
        }

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(familyId, signer);
        return true;
    }

    // TODO: add this function back(commented due to size)
    // function bidCounter() external view returns (uint256) {
    //     return listOfBid.length;
    // }

    // TODO: add this function back(commented due to size)
    // function marketCounter() external view returns (uint256) {
    //     return marketData.length;
    // }

    // TODO: Access Control
    function setOperatorRewardShare(address _operator, uint256 _rewardShare) external {
        operatorRewardShares[_operator] = _rewardShare;
        emit OperatorRewardShareSet(_operator, _rewardShare);
    }

    function _distributeOperatorFeeReward(address _operator, uint256 _feePaid) internal returns (uint256 feeRewardRemaining) {
        // calculate operator fee reward
        uint256 operatorFeeReward = Math.mulDiv(_feePaid, operatorRewardShares[_operator], 1e18);
        feeRewardRemaining = _feePaid - operatorFeeReward;

        // update operator fee reward
        _increaseClaimableAmount(_operator, operatorFeeReward);

        emit OperatorFeeRewardAdded(_operator, operatorFeeReward);
    }

    /// @dev updated by SymbioticStaking contract when job is completed
    function distributeTransmitterFeeReward(address _transmitter, uint256 _feeRewardAmount) external onlyRole(SYMBIOTIC_STAKING_ROLE) {
        _increaseClaimableAmount(_transmitter, _feeRewardAmount);
        emit TransmitterFeeRewardAdded(_transmitter, _feeRewardAmount);
    }

    /// @dev Only SymbioticStakingReward can call this function
    function transferFeeToken(address _recipient, uint256 _amount) external onlyRole(SYMBIOTIC_STAKING_REWARD_ROLE) {
        IERC20(PAYMENT_TOKEN).safeTransfer(_recipient, _amount);
    }

    // for further increase
    uint256[50] private __gap1_0;
}
