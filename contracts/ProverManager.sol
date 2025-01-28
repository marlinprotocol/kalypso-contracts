// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EntityKeyRegistry} from "./EntityKeyRegistry.sol";
import {Error} from "./lib/Error.sol";
import {Struct} from "./lib/Struct.sol";
import {Enum} from "./lib/Enum.sol";
import {HELPER} from "./lib/Helper.sol";
import {ProofMarketplace} from "./ProofMarketplace.sol";
import {IStakingManager} from "./interfaces/staking/IStakingManager.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IProverManager} from "./interfaces/IProverManager.sol";

contract ProverManager is AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IProverManager {
    using HELPER for bytes;
    using HELPER for bytes32;
    using HELPER for uint256;
    using SafeERC20 for IERC20;

    //-------------------------------- Constants and Immutable start --------------------------------//

    bytes32 public constant PROOF_MARKET_PLACE_ROLE = keccak256("PROOF_MARKET_PLACE_ROLE"); // 0xc79b502a8525f583d129c14570e17ce9bca26110a5c41ab7e2556f95e081fec5

    uint256 internal constant EXPONENT = 10 ** 18;

    uint256 public constant PARALLEL_REQUESTS_UPPER_LIMIT = 100;
    uint256 internal constant REDUCTION_REQUEST_DELAY = 100 seconds; // in seconds
    uint256 public constant MIN_PROVING_TIME = 1 seconds; // 1 second
    uint256 public constant MAX_PROVING_TIME = 1 days; // 1 day

    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//

    uint256[500] private __gap_0;

    address public proofMarketplace;
    address public stakingManager;
    address public entityKeyRegistry;

    mapping(address => Struct.Prover) public proverRegistry;
    mapping(address prover => mapping(uint256 marketId => Struct.ProverInfoPerMarket)) public proverInfoPerMarket;
    mapping(address prover => uint256 timestamp) public reduceComputeRequestTimestamp;

    uint256[500] private __gap_1;

    //-------------------------------- State variables end --------------------------------//

    //-------------------------------- Init start --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _proofMarketplace, address _stakingManager, address _entityKeyRegistry)
        public
        initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROOF_MARKET_PLACE_ROLE, _proofMarketplace);

        proofMarketplace = _proofMarketplace;
        stakingManager = _stakingManager;
        entityKeyRegistry = _entityKeyRegistry;
    }

    //-------------------------------- Init end --------------------------------//

    //-------------------------------- Prover Info start --------------------------------//

    /**
     * @notice Register Prover
     */
    function register(address _rewardAddress, uint256 _declaredCompute, bytes calldata _proverData)
        external
        nonReentrant
    {
        address _proverAddress = _msgSender();
        Struct.Prover memory prover = proverRegistry[_proverAddress];

        require(_proverData.length > 0 && _rewardAddress > address(0) && _declaredCompute > 0, Error.CannotBeZero());

        // prevents registering multiple times, unless deregistered
        require(prover.rewardAddress == address(0), Error.ProverAlreadyExists());

        proverRegistry[_proverAddress] = Struct.Prover(_rewardAddress, 0, 0, 0, _declaredCompute, EXPONENT, _proverData);

        emit ProverRegistered(_proverAddress, _declaredCompute, _proverData);
    }

    /**
     * @notice Deregister the prover
     */
    function deregister() external nonReentrant {
        address _proverAddress = _msgSender();
        Struct.Prover memory prover = proverRegistry[_proverAddress];

        require(prover.sumOfComputeAllocations == 0, Error.CannotLeaveWithActiveMarket());

        delete proverRegistry[_proverAddress];

        emit ProverDeregistered(_proverAddress);
    }

    /**
     * @notice Change Prover's reward address
     */
    function updateProverRewardAddress(address _newRewardAddress) external {
        require(_newRewardAddress != address(0), Error.ZeroNewRewardAddress());

        address _proverAddress = _msgSender();
        Struct.Prover storage prover = proverRegistry[_proverAddress];
        require(prover.rewardAddress != address(0), Error.ProverNotRegistered());

        prover.rewardAddress = _newRewardAddress;

        emit ProverRewardAddressChanged(_proverAddress, _newRewardAddress);
    }

    /**
     * @notice Increase prover's compute
     */
    function increaseDeclaredCompute(uint256 _computeToIncrease) external {
        require(_computeToIncrease > 0, Error.ZeroComputeToIncrease());

        address _proverAddress = _msgSender();
        Struct.Prover storage prover = proverRegistry[_proverAddress];
        require(prover.rewardAddress != address(0) && prover.proverData.length != 0, Error.ProverNotRegistered());

        prover.declaredCompute += _computeToIncrease;

        emit ComputeIncreased(_proverAddress, _computeToIncrease);
    }

    /**
     * @notice Notify matching engine about compute reduction. This will stop matching engine from assigning new tasks till the compute is down
     * @param _computeToReduce Compute To Reduce
     */
    function intendToReduceCompute(uint256 _computeToReduce) external {
        require(_computeToReduce != 0, Error.ZeroComputeToReduce());

        address _proverAddress = _msgSender();
        Struct.Prover storage prover = proverRegistry[_proverAddress];

        require(prover.rewardAddress != address(0) && prover.proverData.length > 0, Error.ProverNotRegistered());

        // if request is already in place, this will ICU will be less than EXP (as per design)
        require(prover.intendedComputeUtilization == EXPONENT, Error.RequestAlreadyInPlace());

        // new utilization after update
        uint256 newTotalCompute = prover.declaredCompute - _computeToReduce;

        // this is min compute requires for atleast 1 request from each supported market
        require(newTotalCompute > prover.sumOfComputeAllocations, Error.ExceedsAcceptableRange());

        uint256 newUtilization = (newTotalCompute * EXPONENT) / prover.declaredCompute;
        // new utilization should be always less than EXP
        require(newUtilization < EXPONENT, Error.ExceedsAcceptableRange());

        // temporary value to store the new utilization
        prover.intendedComputeUtilization = newUtilization;

        // block number after which this intent which execute
        reduceComputeRequestTimestamp[_proverAddress] = block.timestamp + REDUCTION_REQUEST_DELAY;
        emit ComputeDecreaseRequested(_proverAddress, newUtilization);
    }

    /**
     * @notice Free up the unused compute. intendToReduceCompute must have been called before this function
     */
    function decreaseDeclaredCompute() external {
        address _proverAddress = _msgSender();

        Struct.Prover storage prover = proverRegistry[_proverAddress];

        require(prover.proverData.length != 0 && prover.rewardAddress != address(0), Error.InvalidProver());

        if (prover.intendedComputeUtilization == EXPONENT) {
            revert Error.ReduceComputeRequestNotInPlace();
        }

        uint256 newTotalCompute = (prover.intendedComputeUtilization * prover.declaredCompute) / EXPONENT;
        uint256 computeToRelease = prover.declaredCompute - newTotalCompute;

        if (newTotalCompute < prover.computeConsumed) {
            revert Error.InsufficientProverComputeAvailable();
        }

        if (newTotalCompute < prover.sumOfComputeAllocations) {
            revert Error.InsufficientProverComputeAvailable();
        }

        prover.declaredCompute = newTotalCompute;
        prover.intendedComputeUtilization = EXPONENT;

        if (
            !(
                block.timestamp >= reduceComputeRequestTimestamp[_proverAddress]
                    && reduceComputeRequestTimestamp[_proverAddress] != 0
            )
        ) {
            revert Error.ReductionRequestNotValid();
        }

        delete reduceComputeRequestTimestamp[_proverAddress];
        emit ComputeDecreased(_proverAddress, computeToRelease);
    }

    function updateProverData(bytes calldata _proverData) external nonReentrant {
        require(_proverData.length > 0, Error.ZeroProverDataLength());

        address _proverAddress = _msgSender();
        Struct.Prover storage prover = proverRegistry[_proverAddress];
        require(prover.rewardAddress != address(0), Error.ProverNotRegistered());

        prover.proverData = _proverData;

        emit ProverDataUpdated(_proverAddress, _proverData);
    }

    //-------------------------------- Prover Info end --------------------------------//

    //-------------------------------- Prover-Marketplace start --------------------------------//

    function joinMarketplace(
        uint256 _marketId,
        uint256 _computePerRequestRequired,
        uint256 _proofGenerationCost,
        uint256 _proposedTime,
        uint256 _commission,
        bool _updateMarketDedicatedKey, // false if not a private market
        bytes memory _attestationData, // verification ignored if updateMarketDedicatedKey==false
        bytes calldata _enclaveSignature // ignored if updateMarketDedicatedKey==false
    ) external {
        address proverAddress = _msgSender();

        Struct.Prover storage prover = proverRegistry[proverAddress];
        Struct.ProverInfoPerMarket memory info = proverInfoPerMarket[proverAddress][_marketId];

        // proof generation time can't be zero.
        // compute required per proof can't be zero
        if (prover.rewardAddress == address(0) || _computePerRequestRequired == 0) {
            revert Error.CannotBeZero();
        }

        require(
            _proposedTime >= MIN_PROVING_TIME && _proposedTime <= MAX_PROVING_TIME, Error.InvalidProverProposedTime()
        );

        // commission can't be more than 1e18 (100%)
        if (_commission > 1e18) {
            revert Error.InvalidProverCommission();
        }

        // only for checking if any market id valid or not
        (address marketVerifierContractAddress,) = _readMarketData(_marketId);
        if (marketVerifierContractAddress == address(0)) {
            revert Error.InvalidMarket();
        }

        // prevents re-joining
        require(info.state == Enum.ProverState.NULL, Error.AlreadyJoinedMarket());

        // sum of compute allocation of all supported markets
        prover.sumOfComputeAllocations += _computePerRequestRequired;

        // ensures that prover will support atleast 1 request for every market
        require(prover.sumOfComputeAllocations <= prover.declaredCompute, Error.CannotBeMoreThanDeclaredCompute());

        // increment the number of active market places supported
        prover.activeMarketplaces++;

        // update market specific info for the prover
        proverInfoPerMarket[proverAddress][_marketId] = Struct.ProverInfoPerMarket(
            Enum.ProverState.JOINED, _computePerRequestRequired, _commission, _proofGenerationCost, _proposedTime, 0
        );

        if (_updateMarketDedicatedKey) {
            _updateEncryptionKey(proverAddress, _marketId, _attestationData, _enclaveSignature);
        }

        emit ProverJoinedMarketplace(proverAddress, _marketId, _computePerRequestRequired, _commission);
    }

    // TODO: Add methods to update prover commission for a market

    function _readMarketData(uint256 _marketId) internal view returns (address, bytes32) {
        (address _verifier, bytes32 proverImageId,,,) = ProofMarketplace(proofMarketplace).marketData(_marketId);

        return (_verifier, proverImageId);
    }

    function leaveMarketplaces(uint256[] calldata marketIds) external {
        for (uint256 index = 0; index < marketIds.length; index++) {
            // proverAddress = _msgSender();
            _leaveMarketplace(_msgSender(), marketIds[index]);
        }
    }

    function leaveMarketplace(uint256 _marketId) external {
        // proverAddress = _msgSender();
        _leaveMarketplace(_msgSender(), _marketId);
    }

    function getProverCommission(uint256 _marketId, address _proverAddress) public view returns (uint256) {
        return proverInfoPerMarket[_proverAddress][_marketId].commission;
    }

    function _leaveMarketplace(address _proverAddress, uint256 _marketId) internal {
        (address marketVerifier,,,,) = ProofMarketplace(proofMarketplace).marketData(_marketId);

        require(marketVerifier != address(0), Error.InvalidMarket());

        Struct.ProverInfoPerMarket memory info = proverInfoPerMarket[_proverAddress][_marketId];

        require(info.state != Enum.ProverState.NULL, Error.InvalidProverStatePerMarket());

        // check if there is any active requests
        require(info.activeRequests == 0, Error.CannotLeaveMarketWithActiveRequest());

        Struct.Prover storage prover = proverRegistry[_proverAddress];

        prover.sumOfComputeAllocations -= info.computePerRequestRequired;
        prover.activeMarketplaces -= 1;

        delete proverInfoPerMarket[_proverAddress][_marketId];
        emit ProverLeftMarketplace(_proverAddress, _marketId);
    }

    function requestForExitMarketplace(uint256 _marketId) external {
        _requestForExitMarketplace(_msgSender(), _marketId);
    }

    function requestForExitMarketplaces(uint256[] calldata _marketIds) external {
        for (uint256 index = 0; index < _marketIds.length; index++) {
            _requestForExitMarketplace(_msgSender(), _marketIds[index]);
        }
    }

    function _requestForExitMarketplace(address _proverAddress, uint256 _marketId) internal {
        (Enum.ProverState state,) = getProverState(_proverAddress, _marketId);

        // only valid provers can exit the market
        if (!(state != Enum.ProverState.NULL && state != Enum.ProverState.REQUESTED_FOR_EXIT)) {
            revert Error.OnlyValidProversCanRequestExit();
        }
        Struct.ProverInfoPerMarket storage info = proverInfoPerMarket[_proverAddress][_marketId];

        info.state = Enum.ProverState.REQUESTED_FOR_EXIT;

        // alerts matching engine to stop assinging the requests of given market
        emit ProverRequestedMarketplaceExit(_proverAddress, _marketId);

        // if there are no active requests, proceed to leave market plaes
        if (info.activeRequests == 0) {
            _leaveMarketplace(_proverAddress, _marketId);
        }
    }

    /**
     * @notice update the encryption key
     */
    function updateEncryptionKey(uint256 _marketId, bytes memory _attestationData, bytes calldata _enclaveSignature)
        external
    {
        // msg.sender is prover
        _updateEncryptionKey(_msgSender(), _marketId, _attestationData, _enclaveSignature);
    }

    function _updateEncryptionKey(
        address _proverAddress,
        uint256 _marketId,
        bytes memory _attestationData,
        bytes calldata _enclaveSignature
    ) internal {
        Struct.Prover memory prover = proverRegistry[_proverAddress];

        // just an extra check to prevent spam
        require(prover.rewardAddress != address(0), Error.CannotBeZero());

        // only for knowing if the given market is private or public
        (, bytes32 proverImageId) = _readMarketData(_marketId);

        require(proverImageId.IS_ENCLAVE(), Error.PublicMarketsDontNeedKey());

        require(
            EntityKeyRegistry(entityKeyRegistry).isImageInFamily(
                _attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), _marketId.PROVER_FAMILY_ID()
            ),
            Error.IncorrectImageId()
        );

        bytes memory pubkey = _attestationData.GET_PUBKEY();

        _attestationData.VERIFY_ENCLAVE_SIGNATURE(_enclaveSignature, _proverAddress);

        // don't whitelist, because same imageId must be used to update the key
        EntityKeyRegistry(entityKeyRegistry).updatePubkey(_proverAddress, _marketId, pubkey, _attestationData);
    }

    /**
     * @notice Add IVS key for a given market
     */
    function addIvsKey(uint256 _marketId, bytes memory _attestationData, bytes calldata _enclaveSignature) external {
        // ensure only right image is used
        require(
            EntityKeyRegistry(entityKeyRegistry).isImageInFamily(
                _attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), _marketId.IVS_FAMILY_ID()
            ),
            Error.IncorrectImageId()
        );

        // confirms that _msgSender() has access to enclave
        _attestationData.VERIFY_ENCLAVE_SIGNATURE(_enclaveSignature, _msgSender());

        // only whitelist key, after verifying the attestation
        EntityKeyRegistry(entityKeyRegistry).verifyKey(_attestationData);
        emit IvKeyAdded(_marketId, _attestationData.GET_ADDRESS());
    }

    /**
     * @notice Remove prover's encryption key
     */
    function removeEncryptionKey(uint256 _marketId) external {
        // msg.sender is prover
        EntityKeyRegistry(entityKeyRegistry).removePubkey(_msgSender(), _marketId);
    }

    //-------------------------------- Prover-Marketplace end --------------------------------//

    //-------------------------------- PROOF_MARKET_PLACE_ROLE start --------------------------------//

    function assignProverTask(uint256 _bidId, address _proverAddress, uint256 _marketId)
        external
        nonReentrant
        onlyRole(PROOF_MARKET_PLACE_ROLE)
    {
        (Enum.ProverState state, uint256 idleCapacity) = getProverState(_proverAddress, _marketId);

        if (!(state == Enum.ProverState.JOINED || state == Enum.ProverState.WIP)) {
            revert Error.AssignOnlyToIdleProvers();
        }

        Struct.Prover storage prover = proverRegistry[_proverAddress];
        Struct.ProverInfoPerMarket storage info = proverInfoPerMarket[_proverAddress][_marketId];

        require(info.computePerRequestRequired <= idleCapacity, Error.InsufficientProverComputeAvailable());
        require(info.activeRequests <= PARALLEL_REQUESTS_UPPER_LIMIT, Error.MaxParallelRequestsPerMarketExceeded());

        uint256 computeConsumed = info.computePerRequestRequired;
        prover.computeConsumed += computeConsumed;

        IStakingManager(stakingManager).onTaskAssignment(_bidId, _proverAddress);

        info.activeRequests++;
        emit ComputeLocked(_proverAddress, computeConsumed);
    }

    function completeProverTask(uint256 _bidId, address _proverAddress, uint256 _marketId, uint256 _feeReward)
        external
        onlyRole(PROOF_MARKET_PLACE_ROLE)
    {
        _releaseProverCompute(_proverAddress, _marketId);

        IStakingManager(stakingManager).onTaskCompletion(_bidId, _proverAddress, _feeReward);
    }

    /**
     * @notice Should be called by proof market place only, PMP is assigned SLASHER_ROLE, called when provers is about to be slashed
     */
    function releaseProverCompute(address _proverAddress, uint256 _marketId)
        external
        onlyRole(PROOF_MARKET_PLACE_ROLE)
    {
        _releaseProverCompute(_proverAddress, _marketId);
    }

    function _releaseProverCompute(address _proverAddress, uint256 _marketId) internal {
        (Enum.ProverState state,) = getProverState(_proverAddress, _marketId);

        // All states = NULL,JOINED,NO_COMPUTE_AVAILABLE,WIP,REQUESTED_FOR_EXIT
        // only provers in WIP, REQUESTED_FOR_EXIT, NO_COMPUTE_AVAILABLE can submit the request, NULL and JOINED can't
        if (state == Enum.ProverState.NULL || state == Enum.ProverState.JOINED) {
            revert Error.OnlyWorkingProvers();
        }

        Struct.Prover storage prover = proverRegistry[_proverAddress];
        Struct.ProverInfoPerMarket storage info = proverInfoPerMarket[_proverAddress][_marketId];

        uint256 computeReleased = info.computePerRequestRequired;
        prover.computeConsumed -= computeReleased;

        info.activeRequests--;
        emit ComputeReleased(_proverAddress, computeReleased);
    }

    //-------------------------------- PROOF_MARKET_PLACE_ROLE end --------------------------------//

    //-------------------------------- Getters start --------------------------------//

    function getProverState(address _proverAddress, uint256 _marketId)
        public
        view
        returns (Enum.ProverState, uint256)
    {
        Struct.ProverInfoPerMarket memory info = proverInfoPerMarket[_proverAddress][_marketId];
        Struct.Prover memory prover = proverRegistry[_proverAddress];

        if (info.state == Enum.ProverState.NULL) {
            return (Enum.ProverState.NULL, 0);
        }

        if (info.state == Enum.ProverState.REQUESTED_FOR_EXIT) {
            return (Enum.ProverState.REQUESTED_FOR_EXIT, 0);
        }

        uint256 idleCapacity = _maxReducableCompute(_proverAddress);

        if (info.state != Enum.ProverState.NULL && idleCapacity == 0) {
            return (Enum.ProverState.NO_COMPUTE_AVAILABLE, 0);
        }

        if (idleCapacity == prover.declaredCompute) {
            return (Enum.ProverState.JOINED, idleCapacity);
        }

        if (idleCapacity != 0 && idleCapacity < prover.declaredCompute) {
            return (Enum.ProverState.WIP, idleCapacity);
        }
        return (Enum.ProverState.NULL, 0);
    }

    function _maxReducableCompute(address _proverAddress) internal view returns (uint256) {
        Struct.Prover memory prover = proverRegistry[_proverAddress];

        uint256 maxUsableCompute = (prover.declaredCompute * prover.intendedComputeUtilization) / EXPONENT;

        if (maxUsableCompute < prover.computeConsumed) {
            return 0;
        }

        return maxUsableCompute - prover.computeConsumed;
    }

    function getProverAssignmentDetails(address _proverAddress, uint256 _marketId)
        external
        view
        returns (uint256, uint256)
    {
        Struct.ProverInfoPerMarket memory info = proverInfoPerMarket[_proverAddress][_marketId];

        return (info.proofGenerationCost, info.proposedTime);
    }

    function getProverRewardDetails(address _proverAddress, uint256 _marketId)
        external
        view
        returns (address, uint256)
    {
        Struct.ProverInfoPerMarket memory info = proverInfoPerMarket[_proverAddress][_marketId];
        Struct.Prover memory prover = proverRegistry[_proverAddress];

        return (prover.rewardAddress, info.proofGenerationCost);
    }

    //-------------------------------- Getters end --------------------------------//

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//
}
