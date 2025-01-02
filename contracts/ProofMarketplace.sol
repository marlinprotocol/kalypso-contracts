// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProofMarketplace} from "./interfaces/IProofMarketplace.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";

import {EntityKeyRegistry} from "./EntityKeyRegistry.sol";
import {ProverRegistry} from "./ProverRegistry.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Error} from "./lib/Error.sol";
import {HELPER} from "./lib/Helper.sol";
import {Struct} from "./lib/Struct.sol";
import {Enum} from "./lib/Enum.sol";

contract ProofMarketplace is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IProofMarketplace
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    using HELPER for bytes;
    using HELPER for bytes32;
    using HELPER for uint256;

    using SafeERC20 for IERC20;

    //-------------------------------- Constants and Immutable start --------------------------------//

    uint256 public constant MARKET_ACTIVATION_DELAY = 100; // in blocks
    bytes32 public constant UPDATER_ROLE = 0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab; // keccak256("UPDATER_ROLE")
    bytes32 public constant MATCHING_ENGINE_ROLE = 0x080f5ea84ed1de4c8edb58be651c25581c355a0011b0f9360de5082becd64640; // keccak256("MATCHING_ENGINE_ROLE")
    bytes32 public constant STAKING_MANAGER_ROLE = 0xa6b5d83d32632203555cb9b2c2f68a8d94da48cadd9266ac0d17babedb52ea5b; // keccak256("STAKING_MANAGER_ROLE")
    bytes32 public constant SYMBIOTIC_STAKING_ROLE = 0x10a5972a598c4264843f7322e2775a07694fac8a54ef3e471a9e82ed2af9bb58; // keccak256("SYMBIOTIC_STAKING_ROLE")
    bytes32 public constant SYMBIOTIC_STAKING_REWARD_ROLE =
        0x930acf1b2ff2678c6844aead593a589f81500db101decf9eb8acd3e9ed204beb; // keccak256("SYMBIOTIC_STAKING_REWARD_ROLE")

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20 public immutable PAYMENT_TOKEN;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable MARKET_CREATION_COST;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable TREASURY;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ProverRegistry public immutable PROVER_REGISTRY;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    //-------------------------------- Constants and Immutable end --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    Struct.Market[] public marketData;
    Struct.BidWithState[] public listOfBid;

    // cost for inputs in payment token
    mapping(Enum.SecretType => uint256) public costPerInputBytes;
    // min proving time (in blocks) for each secret type.
    mapping(Enum.SecretType => uint256) public minProvingTime;
    mapping(address => uint256) public proverClaimableFeeReward;
    mapping(address => uint256) public transmitterClaimableFeeReward;

    //-------------------------------- State variables end --------------------------------//

    //-------------------------------- Init start --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IERC20 _paymentToken,
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

    function initialize(address _admin) external initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(UPDATER_ROLE, DEFAULT_ADMIN_ROLE);

        // push empty data for market id 0 so first market id starts with 1
        marketData.push(Struct.Market(address(0), bytes32(0), 0, address(0), bytes("")));
    }

    //-------------------------------- Init end --------------------------------//

    //-------------------------------- Market start --------------------------------//

    /**
     * @notice Create a new market.
     */
    function createMarket(
        bytes calldata _marketmetadata,
        address _verifier,
        bytes calldata _proverPcrs,
        bytes calldata _ivsPcrs
    ) external nonReentrant {
        address msgSender = _msgSender();
        // Note: StakeToken to be locked per task will be set in NativeStaking and SymbioticStaking as of now
        if (_marketmetadata.length == 0 || address(_verifier) == address(0)) {
            revert Error.CannotBeZero();
        }

        if (!IVerifier(_verifier).checkSampleInputsAndProof()) {
            revert Error.InvalidInputs();
        }
        PAYMENT_TOKEN.safeTransferFrom(msgSender, TREASURY, MARKET_CREATION_COST);

        uint256 marketId = marketData.length;

        // Helps skip whitelisting for public provers
        if (_proverPcrs.GET_IMAGE_ID_FROM_PCRS().IS_ENCLAVE()) {
            ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.PROVER_FAMILY_ID(), _proverPcrs);
        }

        // ivs is always enclave, will revert if a non enclave instance is stated as an ivs
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(marketId.IVS_FAMILY_ID(), _ivsPcrs);

        marketData.push(
            Struct.Market(
                _verifier,
                _proverPcrs.GET_IMAGE_ID_FROM_PCRS(),
                _ivsPcrs.GET_IMAGE_ID_FROM_PCRS(),
                msgSender,
                _marketmetadata
            )
        );
        emit MarketplaceCreated(marketId);
    }

    /**
     * @notice Feature for market creator to list new prover images and ivs images
     */
    function addExtraImages(uint256 marketId, bytes[] calldata _proverPcrs, bytes[] calldata _ivsPcrs) external {
        Struct.Market memory market = marketData[marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());
        require(_msgSender() == market.creator, Error.OnlyMarketCreator());

        if (_proverPcrs.length != 0) {
            require(market.proverImageId.IS_ENCLAVE(), Error.CannotModifyImagesForPublicMarkets());

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
        Struct.Market memory market = marketData[marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());
        require(_msgSender() == market.creator, Error.OnlyMarketCreator());
        if (_proverPcrs.length != 0) {
            require(market.proverImageId.IS_ENCLAVE(), Error.CannotModifyImagesForPublicMarkets());

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
    // TODO: change the name
    function freezeMarket(uint256 marketId) external {
        Struct.Market memory market = marketData[marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());
        require(_msgSender() == market.creator, Error.OnlyMarketCreator());
        delete marketData[marketId].creator;
    }

    function updateMarketMetadata(uint256 marketId, bytes memory metadata) external {
        require(_msgSender() == marketData[marketId].creator, Error.OnlyMarketCreator());

        marketData[marketId].marketmetadata = metadata;

        emit MarketMetadataUpdated(marketId, metadata);
    }

    //-------------------------------- Market end --------------------------------//

    //-------------------------------- Bid Start --------------------------------//

    /**
     * @notice Create requests. Can be paused to prevent temporary escrowing of unwanted amount
     * @param bid: Details of the BID request
     * @param secretType: 0 for purely calldata based secret (1 for Celestia etc, 2 ipfs etc)
     * @param privateInputs: Private Inputs to the circuit.
     * @param acl: If the private inputs are mean't to be confidential, provide acl using the ME keys
     */
    function createBid(
        Struct.Bid calldata bid,
        Enum.SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl,
        bytes calldata extraData
    ) external whenNotPaused nonReentrant {
        _createBid(bid, _msgSender(), secretType, privateInputs, acl, extraData);
    }

    function _createBid(
        Struct.Bid calldata bid,
        address payFrom,
        Enum.SecretType secretType,
        bytes calldata privateInputs,
        bytes calldata acl,
        bytes calldata extraData
    ) internal {
        require (bid.reward != 0 && bid.proverData.length != 0, Error.CannotBeZero());

        require (bid.expiry > block.number + minProvingTime[secretType], Error.CannotAssignExpiredTasks());

        // ensures that the cipher used is small enough
        require (acl.length <= 130, Error.InvalidECIESACL());

        Struct.Market memory market = marketData[bid.marketId];
        require (market.marketmetadata.length > 0, Error.InvalidMarket());

        uint256 platformFee = getPlatformFee(secretType, bid, privateInputs, acl);

        PAYMENT_TOKEN.safeTransferFrom(payFrom, address(this), bid.reward + platformFee);
        PAYMENT_TOKEN.safeTransfer(TREASURY, platformFee);


        uint256 bidId = listOfBid.length;
        Struct.BidWithState memory bidRequest = Struct.BidWithState(bid, Enum.BidState.CREATED, _msgSender(), address(0));
        listOfBid.push(bidRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);
        require (inputVerifier.verifyInputs(bid.proverData), Error.InvalidInputs());

        if (market.proverImageId.IS_ENCLAVE()) {
            // ACL is emitted if private
            emit BidCreated(bidId, true, privateInputs, acl, extraData);
        } else {
            // ACL is not emitted if not private
            emit BidCreated(bidId, false, "", "", extraData);
        }
    }

    /**
     * @notice Cancel the unassigned request. Refunds the proof fee back to the requestor
     */
    function cancelBid(uint256 bidId) external nonReentrant {
        // Only unassigned tasks can be cancelled.
        require(getBidState(bidId) == Enum.BidState.UNASSIGNED, Error.OnlyExpiredBidsCanBeCancelled(bidId));

        Struct.BidWithState storage bidWithState = listOfBid[bidId];
        bidWithState.state = Enum.BidState.COMPLETED;

        PAYMENT_TOKEN.safeTransfer(bidWithState.bid.refundAddress, bidWithState.bid.reward);

        emit BidCancelled(bidId);
    }

    //-------------------------------- Bid end --------------------------------//

    //-------------------------------- Prover start --------------------------------//

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 bidId, bytes calldata proof) external nonReentrant {
        _submitProof(bidId, proof);
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] memory taskIds, bytes[] calldata proofs) external nonReentrant {
        require (taskIds.length == proofs.length, Error.ArityMismatch());

        for (uint256 index = 0; index < taskIds.length; index++) {
            _submitProof(taskIds[index], proofs[index]);
        }
    }

    function _submitProof(uint256 bidId, bytes calldata proof) internal {
        Struct.BidWithState memory bidWithState = listOfBid[bidId];

        uint256 marketId = bidWithState.bid.marketId;

        (address proverRewardAddress, uint256 minRewardForProver) =
            PROVER_REGISTRY.getProverRewardDetails(bidWithState.prover, bidWithState.bid.marketId);

        require(proverRewardAddress != address(0), Error.CannotBeZero());
        require(getBidState(bidId) == Enum.BidState.ASSIGNED, Error.OnlyAssignedBidsCanBeProved(bidId));

        // check what needs to be encoded from proof, bid and task for proof to be verified

        bytes memory inputAndProof = abi.encode(bidWithState.bid.proverData, proof);

        // Verify input and proof against verifier
        require(IVerifier(marketData[marketId].verifier).verify(inputAndProof), Error.InvalidProof(bidId));

        listOfBid[bidId].state = Enum.BidState.COMPLETED;

        uint256 toBackToRequestor = bidWithState.bid.reward - minRewardForProver;

        // reward to prover
        uint256 feeRewardRemaining = _distributeProverFeeReward(marketId, proverRewardAddress, minRewardForProver);

        // fraction of amount back to requestor
        PAYMENT_TOKEN.safeTransfer(bidWithState.bid.refundAddress, toBackToRequestor);

        PROVER_REGISTRY.completeProverTask(bidId, bidWithState.prover, marketId, feeRewardRemaining);
        emit ProofCreated(bidId, proof);
    }

    /**
     * @notice Submit Attestation/Proof from the IVS signer that the given inputs are invalid
     */
    function submitProofForInvalidInputs(uint256 bidId, bytes calldata invalidProofSignature) external nonReentrant {
        Struct.BidWithState memory bidWithState = listOfBid[bidId];
        uint256 marketId = bidWithState.bid.marketId;

        (uint256 minRewardForProver, address proverRewardAddress) = _verifyAndGetData(bidId, bidWithState);

        require(
            _checkDisputeUsingSignature(
                bidId, bidWithState.bid.proverData, invalidProofSignature, marketId.IVS_FAMILY_ID()
            ),
            Error.CannotSlashUsingValidInputs(bidId)
        );

        _completeProofForInvalidRequests(bidId, bidWithState, minRewardForProver, proverRewardAddress, marketId);
    }

    function _verifyAndGetData(uint256 bidId, Struct.BidWithState memory bidWithState)
        internal
        view
        returns (uint256, address)
    {
        (address proverRewardAddress, uint256 minRewardForProver) =
            PROVER_REGISTRY.getProverRewardDetails(bidWithState.prover, bidWithState.bid.marketId);

        require(proverRewardAddress != address(0), Error.CannotBeZero());
        require(getBidState(bidId) == Enum.BidState.ASSIGNED, Error.OnlyAssignedBidsCanBeProved(bidId));

        return (minRewardForProver, proverRewardAddress);
    }

    function _checkDisputeUsingSignature(
        uint256 bidId,
        bytes memory proverData,
        bytes memory invalidProofSignature,
        bytes32 familyId
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(bidId, proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSA.recover(ethSignedMessageHash, invalidProofSignature);
        require(signer != address(0), Error.InvalidEnclaveSignature(signer));

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(familyId, signer);
        return true;
    }

    function _completeProofForInvalidRequests(
        uint256 bidId,
        Struct.BidWithState memory bidWithState,
        uint256 minRewardForProver,
        address proverRewardAddress,
        uint256 marketId
    ) internal {
        // Only assigned requests can be proved
        require(getBidState(bidId) == Enum.BidState.ASSIGNED, Error.OnlyAssignedBidsCanBeProved(bidId));
        listOfBid[bidId].state = Enum.BidState.COMPLETED;

        // tokens related to incorrect request will be sen't to treasury
        uint256 toTreasury = bidWithState.bid.reward - minRewardForProver;

        // transfer the reward to prover
        uint256 feeRewardRemaining = _distributeProverFeeReward(marketId, proverRewardAddress, minRewardForProver);

        // transfer the amount to treasury collection
        PAYMENT_TOKEN.safeTransfer(TREASURY, toTreasury);

        PROVER_REGISTRY.completeProverTask(bidId, bidWithState.prover, marketId, feeRewardRemaining);
        emit InvalidInputsDetected(bidId);
    }

    function _distributeProverFeeReward(uint256 _marketId, address _prover, uint256 _feePaid)
        internal
        returns (uint256 feeRewardRemaining)
    {
        // calculate prover fee reward
        uint256 proverCommission = PROVER_REGISTRY.getProverCommission(_marketId, _prover);
        uint256 proverFeeReward = Math.mulDiv(_feePaid, proverCommission, 1e18);
        feeRewardRemaining = _feePaid - proverFeeReward;

        // update prover fee reward
        proverClaimableFeeReward[_prover] += proverFeeReward;

        emit ProverFeeRewardAdded(_prover, proverFeeReward);
    }

    /**
     * @notice Prover can discard assigned request if he choses to. This will however result in slashing
     */
    function discardRequest(uint256 bidId) external nonReentrant {
        Struct.BidWithState memory bidWithState = listOfBid[bidId];
        require(getBidState(bidId) == Enum.BidState.ASSIGNED, Error.ShouldBeInAssignedState(bidId));
        require(bidWithState.prover == _msgSender(), Error.OnlyProverCanDiscardRequest(bidId));
        _refundFee(bidId);
    }

    //-------------------------------- Prover end --------------------------------//

    //-------------------------------- Slashing start --------------------------------//

    /**
     * @notice Slash Prover for deadline crossed requests
     */
    function refundFees(uint256[] calldata bidIds) external {
        for (uint256 i = 0; i < bidIds.length; i++) {
            Enum.BidState bidState = getBidState(bidIds[i]);

            if(bidState == Enum.BidState.DEADLINE_CROSSED) {
                // if `refundFee` hasn't been called
                _refundFee(bidIds[i]);
            } else if (bidState == Enum.BidState.COMPLETED) {
                // actual slashing be done by StakingManager
                continue;
            } else {
                revert Error.NotSlashableBidId(bidIds[i]);  
            }
        }
    }

    function _refundFee(uint256 bidId) internal {
        Struct.BidWithState storage bidWithState = listOfBid[bidId];

        bidWithState.state = Enum.BidState.COMPLETED;
        uint256 marketId = bidWithState.bid.marketId;

        // Locked Stake will be unlocked when SlashResult is submitted to SymbioticStaking
        if (bidWithState.bid.reward != 0) {
            // refund fee to requestor
            PAYMENT_TOKEN.safeTransfer(bidWithState.bid.refundAddress, bidWithState.bid.reward);
            bidWithState.bid.reward = 0;

            PROVER_REGISTRY.releaseProverCompute(bidWithState.prover, marketId);
            emit ProofNotGenerated(bidId);
        }
    }

    //-------------------------------- Slashing end --------------------------------//

    //-------------------------------- Matching Engine start --------------------------------//

    /**
     * @notice Assign Tasks for Provers directly if ME signer has the gas
     */
    function assignTask(uint256 bidId, address prover, bytes calldata new_acl) external nonReentrant {
        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), _msgSender());
        _assignTask(bidId, prover, new_acl);
    }

    function _assignTask(uint256 bidId, address prover, bytes memory new_acl) internal {
        // Only tasks in CREATE state can be assigned
        require(getBidState(bidId) == Enum.BidState.CREATED, Error.ShouldBeInCreateState());

        Struct.BidWithState storage bidWithState = listOfBid[bidId];
        (uint256 proofGenerationCost, uint256 proverProposedTime) =
            PROVER_REGISTRY.getProverAssignmentDetails(prover, bidWithState.bid.marketId);

        // Can not assign task if price mismatch happens
        if (bidWithState.bid.reward < proofGenerationCost) {
            revert Error.ProofPriceMismatch(bidId);
        }

        // Can not assign task if time mismatch happens
        if (bidWithState.bid.timeTakenForProofGeneration < proverProposedTime) {
            revert Error.ProofTimeMismatch(bidId);
        }

        bidWithState.state = Enum.BidState.ASSIGNED;
        bidWithState.bid.deadline = block.number + bidWithState.bid.timeTakenForProofGeneration;
        bidWithState.prover = prover;

        PROVER_REGISTRY.assignProverTask(bidId, prover, bidWithState.bid.marketId);
        emit TaskCreated(bidId, prover, new_acl);
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
        require ((bidIds.length == provers.length) && (provers.length == newAcls.length), Error.ArityMismatch());

        bytes32 messageHash = keccak256(abi.encode(bidIds, provers, newAcls));
        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSA.recover(ethSignedMessageHash, signature);

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), signer);

        for (uint256 index = 0; index < bidIds.length; index++) {
            _assignTask(bidIds[index], provers[index], newAcls[index]);
        }
    }

    //-------------------------------- Matching Engine end --------------------------------//

    //-------------------------------- Reward Claim start --------------------------------//

    function claimProverFeeReward() external {
        uint256 amount = proverClaimableFeeReward[_msgSender()];
        require(amount > 0, Error.NoRewardToClaim());
        PAYMENT_TOKEN.safeTransfer(_msgSender(), amount);
        delete proverClaimableFeeReward[_msgSender()];
    }

    function claimTransmitterFeeReward() external {
        uint256 amount = transmitterClaimableFeeReward[_msgSender()];
        require(amount > 0, Error.NoRewardToClaim());

        PAYMENT_TOKEN.safeTransfer(_msgSender(), amount);
        delete transmitterClaimableFeeReward[_msgSender()];
    }

    //-------------------------------- Reward Claim start --------------------------------//

    //-------------------------------- SYMBIOTIC_STAKING_REWARD start --------------------------------//

    /// @notice Called when SymbioticStaking reward distributes fee rewards
    function distributeTransmitterFeeReward(address _transmitter, uint256 _feeRewardAmount)
        external
        onlyRole(SYMBIOTIC_STAKING_ROLE)
    {
        transmitterClaimableFeeReward[_transmitter] += _feeRewardAmount;
        emit TransmitterFeeRewardAdded(_transmitter, _feeRewardAmount);
    }

    function transferFeeToken(address _recipient, uint256 _amount) external onlyRole(SYMBIOTIC_STAKING_REWARD_ROLE) {
        IERC20(PAYMENT_TOKEN).safeTransfer(_recipient, _amount);
    }

    //-------------------------------- SYMBIOTIC_STAKING_REWARD end --------------------------------//

    //-------------------------------- UPDATER_ROLE start --------------------------------//

    /**
     * @notice Enforces PMP to use only one matching engine image
     */
    function setMatchingEngineImage(bytes calldata pcrs) external onlyRole(UPDATER_ROLE) {
        ENTITY_KEY_REGISTRY.whitelistImageUsingPcrs(MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), pcrs);
    }

    /**
     * @notice Verifies the matching engine and its' keys. Can be verified only by UPDATE_ROLE till multi matching engine key sharing is enabled
     */
    function verifyMatchingEngine(bytes memory attestationData, bytes calldata meSignature)
        external
        onlyRole(UPDATER_ROLE)
    {
        address _thisAddress = address(this);

        // confirms that admin has access to enclave
        attestationData.VERIFY_ENCLAVE_SIGNATURE(meSignature, _thisAddress);

        // checks attestation and updates the key
        ENTITY_KEY_REGISTRY.updatePubkey(_thisAddress, 0, attestationData.GET_PUBKEY(), attestationData);
    }

    /**
     * @notice Update Cost for inputs
     */
    function updateCostPerBytes(Enum.SecretType secretType, uint256 costPerByte) external onlyRole(UPDATER_ROLE) {
        costPerInputBytes[secretType] = costPerByte;

        emit UpdateCostPerBytes(secretType, costPerByte);
    }

    /**
     * @notice Update Min Proving Time
     */
    function updateMinProvingTime(Enum.SecretType secretType, uint256 newProvingTime) external onlyRole(UPDATER_ROLE) {
        minProvingTime[secretType] = newProvingTime;

        emit UpdateMinProvingTime(secretType, newProvingTime);
    }

    function pause() external onlyRole(UPDATER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UPDATER_ROLE) {
        _unpause();
    }

    //-------------------------------- UPDATER_ROLE end --------------------------------//

    //-------------------------------- Getter start --------------------------------//

    /**
     * @notice Different secret might have different fee. Hence fee is different
     * @param secretType: Secret Type
     * @param bid: Details of the bid
     * @param privateInputs: Private Inputs to the circuit
     * @param acl: Access control Data
     */
    function getPlatformFee(
        Enum.SecretType secretType,
        Struct.Bid calldata bid,
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
     * @notice Possible States: NULL, CREATE, UNASSIGNED, ASSIGNED, COMPLETE, DEADLINE_CROSSED
     */
    function getBidState(uint256 bidId) public view returns (Enum.BidState) {
        Struct.BidWithState memory bidWithState = listOfBid[bidId];

        // time before which matching engine should assign the task to prover
        if (bidWithState.state == Enum.BidState.CREATED) {
            if (bidWithState.bid.expiry > block.number) {
                return bidWithState.state;
            }

            return Enum.BidState.UNASSIGNED;
        }

        // time before which prover should submit the proof
        if (bidWithState.state == Enum.BidState.ASSIGNED) {
            if (bidWithState.bid.deadline < block.number) {
                return Enum.BidState.DEADLINE_CROSSED;
            }

            return Enum.BidState.ASSIGNED;
        }

        return bidWithState.state;
    }

    function bidCounter() external view returns (uint256) {
        return listOfBid.length;
    }

    function marketCounter() external view returns (uint256) {
        return marketData.length;
    }

    //-------------------------------- Getter end --------------------------------//

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    // for further increase
    uint256[50] private __gap1_0;
}
