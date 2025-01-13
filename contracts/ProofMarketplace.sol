// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {EntityKeyRegistry} from "./EntityKeyRegistry.sol";
import {ProverManager} from "./ProverManager.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProofMarketplace} from "./interfaces/IProofMarketplace.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using HELPER for bytes;
    using HELPER for bytes32;
    using HELPER for uint256;

    using SafeERC20 for IERC20;

    //-------------------------------- Constants and Immutable start --------------------------------//

    bytes32 public constant UPDATER_ROLE = 0x73e573f9566d61418a34d5de3ff49360f9c51fec37f7486551670290f6285dab; // keccak256("UPDATER_ROLE")
    bytes32 public constant MATCHING_ENGINE_ROLE = 0x080f5ea84ed1de4c8edb58be651c25581c355a0011b0f9360de5082becd64640; // keccak256("MATCHING_ENGINE_ROLE")
    bytes32 public constant STAKING_MANAGER_ROLE = 0xa6b5d83d32632203555cb9b2c2f68a8d94da48cadd9266ac0d17babedb52ea5b; // keccak256("STAKING_MANAGER_ROLE")
    bytes32 public constant SYMBIOTIC_STAKING_ROLE = 0x10a5972a598c4264843f7322e2775a07694fac8a54ef3e471a9e82ed2af9bb58; // keccak256("SYMBIOTIC_STAKING_ROLE")
    bytes32 public constant SYMBIOTIC_STAKING_REWARD_ROLE =
        0x930acf1b2ff2678c6844aead593a589f81500db101decf9eb8acd3e9ed204beb; // keccak256("SYMBIOTIC_STAKING_REWARD_ROLE")

    uint256 public constant MIN_PROVING_TIME = 1 seconds; // 1 second
    uint256 public constant MAX_PROVING_TIME = 1 days; // 1 day
    uint256 public constant MAX_MATCHING_TIME = 1 days; // 1 day

    //-------------------------------- Constants and Immutable end --------------------------------//

    //-------------------------------- State variables start --------------------------------//

    Struct.Market[] public marketData;
    Struct.BidWithState[] public listOfBid;

    uint256 public marketCreationCost;
    address public paymentToken;
    address public treasury;
    address public proverManager;
    address public entityKeyRegistry;

    mapping(Enum.SecretType => uint256) public costPerInputBytes; // cost for inputs in payment token
    mapping(Enum.SecretType => uint256) public minProvingTime; // min proving time for each secret type.
    mapping(address => uint256) public proverClaimableFeeReward;
    mapping(address => uint256) public transmitterClaimableFeeReward;

    uint256[500] private __gap;

    // TODO: Add mapping for `stakePerjob` later

    //-------------------------------- State variables end --------------------------------//

    //-------------------------------- Init start --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // TODO: add stake per job
    function initialize(
        address _admin,
        address _paymentToken,
        address _treasury,
        address _proverManager,
        address _entityKeyRegistry,
        uint256 _marketCreationCost
    ) external initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(UPDATER_ROLE, DEFAULT_ADMIN_ROLE);

        paymentToken = _paymentToken;
        emit PaymentTokenSet(_paymentToken);

        treasury = _treasury;
        emit TreasurySet(_treasury);

        proverManager = _proverManager;
        emit ProverManagerSet(_proverManager);

        entityKeyRegistry = _entityKeyRegistry;
        emit EntityKeyRegistrySet(_entityKeyRegistry);

        marketCreationCost = _marketCreationCost;
        emit MarketCreationCostSet(_marketCreationCost);

        // push empty data for market id 0 so that first market id starts with 1
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

        IERC20(paymentToken).safeTransferFrom(msgSender, treasury, marketCreationCost);

        uint256 marketId = marketData.length;

        // Helps skip whitelisting for public provers
        if (_proverPcrs.GET_IMAGE_ID_FROM_PCRS().IS_ENCLAVE()) {
            EntityKeyRegistry(entityKeyRegistry).whitelistImageUsingPcrs(marketId.PROVER_FAMILY_ID(), _proverPcrs);
        }

        // ivs is always enclave, will revert if a non enclave instance is stated as an ivs
        EntityKeyRegistry(entityKeyRegistry).whitelistImageUsingPcrs(marketId.IVS_FAMILY_ID(), _ivsPcrs);

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
    function addExtraImages(uint256 _marketId, bytes[] calldata _proverPcrs, bytes[] calldata _ivsPcrs) external {
        Struct.Market memory market = marketData[_marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());
        require(_msgSender() == market.creator, Error.OnlyMarketCreator());

        if (_proverPcrs.length != 0) {
            require(market.proverImageId.IS_ENCLAVE(), Error.CannotModifyImagesForPublicMarkets());

            for (uint256 index = 0; index < _proverPcrs.length; index++) {
                bytes32 familyId = _marketId.PROVER_FAMILY_ID();
                bytes32 proverImageId = _proverPcrs[index].GET_IMAGE_ID_FROM_PCRS();

                if (EntityKeyRegistry(entityKeyRegistry).isImageInFamily(proverImageId, familyId)) {
                    revert Error.ImageAlreadyInFamily(proverImageId, familyId);
                }

                EntityKeyRegistry(entityKeyRegistry).whitelistImageUsingPcrs(familyId, _proverPcrs[index]);
                emit AddExtraProverImage(_marketId, proverImageId);
            }
        }

        for (uint256 index = 0; index < _ivsPcrs.length; index++) {
            bytes32 familyId = _marketId.IVS_FAMILY_ID();
            bytes32 ivsImageId = _ivsPcrs[index].GET_IMAGE_ID_FROM_PCRS();

            if (EntityKeyRegistry(entityKeyRegistry).isImageInFamily(ivsImageId, familyId)) {
                revert Error.ImageAlreadyInFamily(ivsImageId, familyId);
            }

            EntityKeyRegistry(entityKeyRegistry).whitelistImageUsingPcrs(familyId, _ivsPcrs[index]);
            emit AddExtraIVSImage(_marketId, ivsImageId);
        }
    }

    /**
     * @notice Feature for market creator to remove extra provers
     */
    function removeExtraImages(uint256 _marketId, bytes[] calldata _proverPcrs, bytes[] calldata _ivsPcrs) external {
        Struct.Market memory market = marketData[_marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());
        require(_msgSender() == market.creator, Error.OnlyMarketCreator());
        if (_proverPcrs.length != 0) {
            require(market.proverImageId.IS_ENCLAVE(), Error.CannotModifyImagesForPublicMarkets());

            for (uint256 index = 0; index < _proverPcrs.length; index++) {
                bytes32 imageId = _proverPcrs[index].GET_IMAGE_ID_FROM_PCRS();

                if (imageId == market.proverImageId) {
                    revert Error.CannotRemoveDefaultImageFromMarket(_marketId, imageId);
                }

                EntityKeyRegistry(entityKeyRegistry).removeEnclaveImageFromFamily(imageId, _marketId.PROVER_FAMILY_ID());
                emit RemoveExtraProverImage(_marketId, imageId);
            }
        }

        for (uint256 index = 0; index < _ivsPcrs.length; index++) {
            bytes32 imageId = _ivsPcrs[index].GET_IMAGE_ID_FROM_PCRS();

            if (imageId == market.ivsImageId) {
                revert Error.CannotRemoveDefaultImageFromMarket(_marketId, imageId);
            }

            EntityKeyRegistry(entityKeyRegistry).removeEnclaveImageFromFamily(imageId, _marketId.IVS_FAMILY_ID());
            emit RemoveExtraIVSImage(_marketId, imageId);
        }
    }

    /**
     * @notice Once called new images can't be added to market
     */
    function freezeMarket(uint256 _marketId) external {
        Struct.Market memory market = marketData[_marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());
        require(_msgSender() == market.creator, Error.OnlyMarketCreator());
        delete marketData[_marketId].creator;
    }

    function updateMarketMetadata(uint256 _marketId, bytes calldata _metadata) external {
        require(_msgSender() == marketData[_marketId].creator, Error.OnlyMarketCreator());

        marketData[_marketId].marketmetadata = _metadata;

        emit MarketMetadataUpdated(_marketId, _metadata);
    }

    //-------------------------------- Market end --------------------------------//

    //-------------------------------- Bid Start --------------------------------//

    /**
     * @notice Create requests. Can be paused to prevent temporary escrowing of unwanted amount
     * @param _bid: Details of the BID request
     * @param _secretType: 0 for purely calldata based secret (1 for Celestia etc, 2 ipfs etc)
     * @param _privateInputs: Private Inputs to the circuit.
     * @param _acl: If the private inputs are mean't to be confidential, provide acl using the ME keys
     */
    function createBid(
        Struct.Bid calldata _bid,
        Enum.SecretType _secretType,
        bytes calldata _privateInputs,
        bytes calldata _acl,
        bytes calldata _extraData
    ) external whenNotPaused nonReentrant {
        _createBid(_bid, _msgSender(), _secretType, _privateInputs, _acl, _extraData);
    }

    function _createBid(
        Struct.Bid calldata _bid,
        address _payFrom,
        Enum.SecretType _secretType,
        bytes calldata _privateInputs,
        bytes calldata _acl,
        bytes calldata _extraData
    ) internal {
        require(_bid.reward > 0 && _bid.proverData.length > 0, Error.CannotBeZero());

        require(_bid.expiry > block.timestamp + minProvingTime[_secretType], Error.CannotAssignExpiredTasks());
        require(_bid.expiry <= block.timestamp + MAX_MATCHING_TIME, Error.ExceedsMaximumMatchtime());
        require(
            _bid.timeForProofGeneration >= MIN_PROVING_TIME && _bid.timeForProofGeneration <= MAX_PROVING_TIME,
            Error.InvalidTimeForProofGeneration()
        );

        // ensures that the cipher used is small enough
        require(_acl.length <= 130, Error.InvalidECIESACL());

        Struct.Market memory market = marketData[_bid.marketId];
        require(market.marketmetadata.length > 0, Error.InvalidMarket());

        uint256 platformFee = getPlatformFee(_secretType, _bid, _privateInputs, _acl);

        IERC20(paymentToken).safeTransferFrom(_payFrom, address(this), _bid.reward + platformFee);
        IERC20(paymentToken).safeTransfer(treasury, platformFee);

        uint256 bidId = listOfBid.length;
        Struct.BidWithState memory bidRequest =
            Struct.BidWithState(_bid, Enum.BidState.CREATED, _msgSender(), address(0));
        listOfBid.push(bidRequest);

        IVerifier inputVerifier = IVerifier(market.verifier);
        require(inputVerifier.verifyInputs(_bid.proverData), Error.InvalidInputs());

        if (market.proverImageId.IS_ENCLAVE()) {
            // ACL is emitted if private
            emit BidCreated(bidId, true, _privateInputs, _acl, _extraData);
        } else {
            // ACL is not emitted if not private
            emit BidCreated(bidId, false, "", "", _extraData);
        }
    }

    /**
     * @notice Cancel the unassigned request. Refunds the proof fee back to the requestor
     */
    function cancelBid(uint256 _bidId) external nonReentrant {
        // Only unassigned tasks can be cancelled.
        require(getBidState(_bidId) == Enum.BidState.UNASSIGNED, Error.OnlyExpiredBidsCanBeCancelled(_bidId));

        Struct.BidWithState storage bidWithState = listOfBid[_bidId];
        bidWithState.state = Enum.BidState.COMPLETED;

        IERC20(paymentToken).safeTransfer(bidWithState.bid.refundAddress, bidWithState.bid.reward);

        emit BidCancelled(_bidId);
    }

    //-------------------------------- Bid end --------------------------------//

    //-------------------------------- Prover start --------------------------------//

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 _bidId, bytes calldata _proof) external nonReentrant {
        _submitProof(_bidId, _proof);
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] memory _taskIds, bytes[] calldata _proofs) external nonReentrant {
        require(_taskIds.length == _proofs.length, Error.ArityMismatch());

        for (uint256 index = 0; index < _taskIds.length; index++) {
            _submitProof(_taskIds[index], _proofs[index]);
        }
    }

    function _submitProof(uint256 _bidId, bytes calldata _proof) internal {
        Struct.BidWithState memory bidWithState = listOfBid[_bidId];

        uint256 marketId = bidWithState.bid.marketId;

        (address proverRewardAddress, uint256 minRewardForProver) =
            ProverManager(proverManager).getProverRewardDetails(bidWithState.prover, bidWithState.bid.marketId);

        require(proverRewardAddress != address(0), Error.CannotBeZero());
        require(getBidState(_bidId) == Enum.BidState.ASSIGNED, Error.OnlyAssignedBidsCanBeProved(_bidId));

        // check what needs to be encoded from proof, bid and task for proof to be verified

        bytes memory inputAndProof = abi.encode(bidWithState.bid.proverData, _proof);

        // Verify input and _proof against verifier
        require(IVerifier(marketData[marketId].verifier).verify(inputAndProof), Error.InvalidProof(_bidId));

        listOfBid[_bidId].state = Enum.BidState.COMPLETED;

        uint256 toBackToRequestor = bidWithState.bid.reward - minRewardForProver;

        // reward to prover
        uint256 feeRewardRemaining = _distributeProverFeeReward(marketId, proverRewardAddress, minRewardForProver);

        // fraction of amount back to requestor
        IERC20(paymentToken).safeTransfer(bidWithState.bid.refundAddress, toBackToRequestor);

        ProverManager(proverManager).completeProverTask(_bidId, bidWithState.prover, marketId, feeRewardRemaining);
        emit ProofCreated(_bidId, _proof);
    }

    /**
     * @notice Submit Attestation/Proof from the IVS signer that the given inputs are invalid
     */
    function submitProofForInvalidInputs(uint256 _bidId, bytes calldata _invalidProofSignature) external nonReentrant {
        Struct.BidWithState memory bidWithState = listOfBid[_bidId];
        uint256 marketId = bidWithState.bid.marketId;

        (uint256 minRewardForProver, address proverRewardAddress) = _verifyAndGetData(_bidId, bidWithState);

        require(
            _checkDisputeUsingSignature(
                _bidId, bidWithState.bid.proverData, _invalidProofSignature, marketId.IVS_FAMILY_ID()
            ),
            Error.CannotSlashUsingValidInputs(_bidId)
        );

        _completeProofForInvalidRequests(_bidId, bidWithState, minRewardForProver, proverRewardAddress, marketId);
    }

    function _verifyAndGetData(uint256 _bidId, Struct.BidWithState memory _bidWithState)
        internal
        view
        returns (uint256, address)
    {
        (address proverRewardAddress, uint256 minRewardForProver) =
            ProverManager(proverManager).getProverRewardDetails(_bidWithState.prover, _bidWithState.bid.marketId);

        require(proverRewardAddress != address(0), Error.CannotBeZero());
        require(getBidState(_bidId) == Enum.BidState.ASSIGNED, Error.OnlyAssignedBidsCanBeProved(_bidId));

        return (minRewardForProver, proverRewardAddress);
    }

    function _checkDisputeUsingSignature(
        uint256 _bidId,
        bytes memory _proverData,
        bytes memory _invalidProofSignature,
        bytes32 _familyId
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(_bidId, _proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSA.recover(ethSignedMessageHash, _invalidProofSignature);
        require(signer != address(0), Error.InvalidEnclaveSignature(signer));

        EntityKeyRegistry(entityKeyRegistry).allowOnlyVerifiedFamily(_familyId, signer);
        return true;
    }

    function _completeProofForInvalidRequests(
        uint256 _bidId,
        Struct.BidWithState memory _bidWithState,
        uint256 _minRewardForProver,
        address _proverRewardAddress,
        uint256 _marketId
    ) internal {
        // Only assigned requests can be proved
        require(getBidState(_bidId) == Enum.BidState.ASSIGNED, Error.OnlyAssignedBidsCanBeProved(_bidId));
        listOfBid[_bidId].state = Enum.BidState.COMPLETED;

        // tokens related to incorrect request will be sen't to treasury
        uint256 toTreasury = _bidWithState.bid.reward - _minRewardForProver;

        // transfer the reward to prover
        uint256 feeRewardRemaining = _distributeProverFeeReward(_marketId, _proverRewardAddress, _minRewardForProver);

        // transfer the amount to treasury collection
        IERC20(paymentToken).safeTransfer(treasury, toTreasury);

        ProverManager(proverManager).completeProverTask(_bidId, _bidWithState.prover, _marketId, feeRewardRemaining);
        emit InvalidInputsDetected(_bidId);
    }

    function _distributeProverFeeReward(uint256 _marketId, address _prover, uint256 _feePaid)
        internal
        returns (uint256 feeRewardRemaining)
    {
        // calculate prover fee reward
        uint256 proverCommission = ProverManager(proverManager).getProverCommission(_marketId, _prover);
        uint256 proverFeeReward = Math.mulDiv(_feePaid, proverCommission, 1e18);
        feeRewardRemaining = _feePaid - proverFeeReward;

        // update prover fee reward
        proverClaimableFeeReward[_prover] += proverFeeReward;

        emit ProverFeeRewardAdded(_prover, proverFeeReward);
    }

    /**
     * @notice Prover can discard assigned request if he choses to. This will however result in slashing
     */
    function discardRequest(uint256 _bidId) external nonReentrant {
        Struct.BidWithState memory bidWithState = listOfBid[_bidId];
        require(getBidState(_bidId) == Enum.BidState.ASSIGNED, Error.ShouldBeInAssignedState(_bidId));
        require(bidWithState.prover == _msgSender(), Error.OnlyProverCanDiscardRequest(_bidId));
        _refundFee(_bidId);
    }

    //-------------------------------- Prover end --------------------------------//

    //-------------------------------- Slashing start --------------------------------//

    /**
     * @notice Slash Prover for deadline crossed requests
     */
    function refundFees(uint256[] calldata _bidIds) external {
        for (uint256 i = 0; i < _bidIds.length; i++) {
            Enum.BidState bidState = getBidState(_bidIds[i]);

            if (bidState == Enum.BidState.DEADLINE_CROSSED) {
                // if `refundFee` hasn't been called
                _refundFee(_bidIds[i]);
            } else if (bidState == Enum.BidState.COMPLETED) {
                // actual slashing be done by StakingManager
                continue;
            } else {
                revert Error.NotSlashableBidId(_bidIds[i]);
            }
        }
    }

    function _refundFee(uint256 _bidId) internal {
        Struct.BidWithState storage bidWithState = listOfBid[_bidId];

        bidWithState.state = Enum.BidState.COMPLETED;
        uint256 marketId = bidWithState.bid.marketId;

        // Locked Stake will be unlocked when SlashResult is submitted to SymbioticStaking
        if (bidWithState.bid.reward != 0) {
            // refund fee to requestor
            IERC20(paymentToken).safeTransfer(bidWithState.bid.refundAddress, bidWithState.bid.reward);
            bidWithState.bid.reward = 0;

            ProverManager(proverManager).releaseProverCompute(bidWithState.prover, marketId);
            emit ProofNotGenerated(_bidId);
        }
    }

    //-------------------------------- Slashing end --------------------------------//

    //-------------------------------- Matching Engine start --------------------------------//

    /**
     * @notice Assign Tasks for Provers directly if ME signer has the gas
     */
    function assignTask(uint256 _bidId, address _prover, bytes calldata _new_acl) external nonReentrant {
        EntityKeyRegistry(entityKeyRegistry).allowOnlyVerifiedFamily(
            MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), _msgSender()
        );
        _assignTask(_bidId, _prover, _new_acl);
    }

    function _assignTask(uint256 _bidId, address _prover, bytes memory _new_acl) internal {
        // Only tasks in CREATE state can be assigned
        require(getBidState(_bidId) == Enum.BidState.CREATED, Error.ShouldBeInCreateState());

        Struct.BidWithState storage bidWithState = listOfBid[_bidId];
        (uint256 proofGenerationCost, uint256 proverProposedTime) =
            ProverManager(proverManager).getProverAssignmentDetails(_prover, bidWithState.bid.marketId);

        // Can not assign task if price mismatch happens
        if (bidWithState.bid.reward < proofGenerationCost) {
            revert Error.ProofPriceMismatch(_bidId);
        }

        // Can not assign task if time mismatch happens
        if (bidWithState.bid.timeForProofGeneration < proverProposedTime) {
            revert Error.ProofTimeMismatch(_bidId);
        }

        bidWithState.state = Enum.BidState.ASSIGNED;
        bidWithState.bid.deadline = block.timestamp + bidWithState.bid.timeForProofGeneration;
        bidWithState.prover = _prover;

        ProverManager(proverManager).assignProverTask(_bidId, _prover, bidWithState.bid.marketId);
        emit TaskCreated(_bidId, _prover, _new_acl);
    }

    /**
     * @notice Assign Tasks for Provers. Only Matching Engine Image can call
     */
    function relayBatchAssignTasks(
        uint256[] calldata _bidIds,
        address[] calldata _provers,
        bytes[] calldata _newAcls,
        bytes calldata _signature
    ) external nonReentrant {
        require((_bidIds.length == _provers.length) && (_provers.length == _newAcls.length), Error.ArityMismatch());

        bytes32 messageHash = keccak256(abi.encode(_bidIds, _provers, _newAcls));
        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSA.recover(ethSignedMessageHash, _signature);

        EntityKeyRegistry(entityKeyRegistry).allowOnlyVerifiedFamily(
            MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), signer
        );

        for (uint256 index = 0; index < _bidIds.length; index++) {
            _assignTask(_bidIds[index], _provers[index], _newAcls[index]);
        }
    }

    //-------------------------------- Matching Engine end --------------------------------//

    //-------------------------------- Reward Claim start --------------------------------//

    function claimProverFeeReward() external {
        uint256 amount = proverClaimableFeeReward[_msgSender()];
        require(amount > 0, Error.NoRewardToClaim());
        IERC20(paymentToken).safeTransfer(_msgSender(), amount);
        delete proverClaimableFeeReward[_msgSender()];
    }

    function claimTransmitterFeeReward() external {
        uint256 amount = transmitterClaimableFeeReward[_msgSender()];
        require(amount > 0, Error.NoRewardToClaim());

        IERC20(paymentToken).safeTransfer(_msgSender(), amount);
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
        IERC20(paymentToken).safeTransfer(_recipient, _amount);
    }

    //-------------------------------- SYMBIOTIC_STAKING_REWARD end --------------------------------//

    //-------------------------------- UPDATER_ROLE start --------------------------------//

    /**
     * @notice Enforces PMP to use only one matching engine image
     */
    function setMatchingEngineImage(bytes calldata _pcrs) external onlyRole(UPDATER_ROLE) {
        EntityKeyRegistry(entityKeyRegistry).whitelistImageUsingPcrs(
            MATCHING_ENGINE_ROLE.MATCHING_ENGINE_FAMILY_ID(), _pcrs
        );
    }

    /**
     * @notice Verifies the matching engine and its' keys. Can be verified only by UPDATE_ROLE till multi matching engine key sharing is enabled
     */
    function verifyMatchingEngine(bytes calldata _attestationData, bytes calldata _meSignature)
        external
        onlyRole(UPDATER_ROLE)
    {
        address _thisAddress = address(this);

        // confirms that admin has access to enclave
        _attestationData.VERIFY_ENCLAVE_SIGNATURE(_meSignature, _thisAddress);

        // checks attestation and updates the key
        EntityKeyRegistry(entityKeyRegistry).updatePubkey(
            _thisAddress, 0, _attestationData.GET_PUBKEY(), _attestationData
        );
    }

    /**
     * @notice Update Cost for inputs
     */
    function updateCostPerBytes(Enum.SecretType _secretType, uint256 _costPerByte) external onlyRole(UPDATER_ROLE) {
        costPerInputBytes[_secretType] = _costPerByte;

        emit UpdateCostPerBytes(_secretType, _costPerByte);
    }

    /**
     * @notice Update Min Proving Time
     */
    function updateMinProvingTime(Enum.SecretType _secretType, uint256 _newProvingTime)
        external
        onlyRole(UPDATER_ROLE)
    {
        minProvingTime[_secretType] = _newProvingTime;

        emit UpdateMinProvingTime(_secretType, _newProvingTime);
    }

    function pause() external onlyRole(UPDATER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UPDATER_ROLE) {
        _unpause();
    }

    function setMarketCreationCost(uint256 _marketCreationCost) external onlyRole(UPDATER_ROLE) {
        marketCreationCost = _marketCreationCost;
        emit MarketCreationCostSet(_marketCreationCost);
    }

    function setPaymentToken(address _paymentToken) external onlyRole(UPDATER_ROLE) {
        paymentToken = _paymentToken;
        emit PaymentTokenSet(_paymentToken);
    }

    function setTreasury(address _treasury) external onlyRole(UPDATER_ROLE) {
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function setProverManager(address _proverManager) external onlyRole(UPDATER_ROLE) {
        proverManager = _proverManager;
        emit ProverManagerSet(_proverManager);
    }

    function setEntityKeyRegistry(address _entityKeyRegistry) external onlyRole(UPDATER_ROLE) {
        entityKeyRegistry = _entityKeyRegistry;
        emit EntityKeyRegistrySet(_entityKeyRegistry);
    }

    //-------------------------------- UPDATER_ROLE end --------------------------------//

    //-------------------------------- Getter start --------------------------------//

    /**
     * @notice Different secret might have different fee. Hence fee is different
     * @param _secretType: Secret Type
     * @param _bid: Details of the bid
     * @param _privateInputs: Private Inputs to the circuit
     * @param _acl: Access control Data
     */
    function getPlatformFee(
        Enum.SecretType _secretType,
        Struct.Bid calldata _bid,
        bytes calldata _privateInputs,
        bytes calldata _acl
    ) public view returns (uint256) {
        uint256 costperByte = costPerInputBytes[_secretType];
        if (costperByte != 0) {
            return (_bid.proverData.length + _privateInputs.length + _acl.length) * costperByte;
        }
        return 0;
    }

    /**
     * @notice Possible States: NULL, CREATE, UNASSIGNED, ASSIGNED, COMPLETE, DEADLINE_CROSSED
     */
    function getBidState(uint256 _bidId) public view returns (Enum.BidState) {
        Struct.BidWithState memory bidWithState = listOfBid[_bidId];

        // time before which matching engine should assign the task to prover
        if (bidWithState.state == Enum.BidState.CREATED) {
            if (bidWithState.bid.expiry > block.timestamp) {
                return bidWithState.state;
            }

            return Enum.BidState.UNASSIGNED;
        }

        // time before which prover should submit the proof
        if (bidWithState.state == Enum.BidState.ASSIGNED) {
            if (bidWithState.bid.deadline < block.timestamp) {
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

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    // for further increase
    uint256[50] private __gap1_0;
}
