// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Contracts */
import {ProofMarketplace} from "../../ProofMarketplace.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/* Interfaces */
// import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../interfaces/staking/ISymbioticStakingReward.sol";
import {IAttestationVerifier} from "../../periphery/interfaces/IAttestationVerifier.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* Libraries */
import {Struct} from "../../lib/Struct.sol";
import {Enum} from "../../lib/Enum.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../interfaces/IProverCallbacks.sol";

import {console} from "hardhat/console.sol";

contract SymbioticStaking is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ISymbioticStaking
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IProverCallbacks public immutable I_PROVER_CALLBACK;

    bytes32 public constant STAKE_SNAPSHOT_TYPE = keccak256("STAKE_SNAPSHOT_TYPE");
    bytes32 public constant SLASH_RESULT_TYPE = keccak256("SLASH_RESULT_TYPE");

    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant BRIDGE_ENCLAVE_UPDATES_ROLE = keccak256("BRIDGE_ENCLAVE_UPDATES_ROLE");

    uint256 public constant SIGNATURE_LENGTH = 65;

    /*===================================================================================================================*/
    /*================================================ state variable ===================================================*/
    /*===================================================================================================================*/

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    /* Config */
    uint256 public submissionCooldown; // 18 decimal (in seconds)
    uint256 public baseTransmitterComissionRate; // 18 decimal (in percentage)

    /* Stake Token */
    EnumerableSet.AddressSet stakeTokenSet;
    uint256 public stakeTokenSelectionWeightSum;

    /* Contracts */
    address public stakingManager;
    address public proofMarketplace;
    address public rewardDistributor;
    address public attestationVerifier;

    /* RewardToken */
    address public feeRewardToken;

    Struct.ConfirmedTimestamp[] public confirmedTimestamps; // timestamp is added once all types of partial txs are received

    /*===================================================================================================================*/
    /*==================================================== mapping ======================================================*/
    /*===================================================================================================================*/

    /* Config */
    mapping(address stakeToken => uint256 amount) public amountToLock;
    mapping(address stakeToken => uint256 weight) public stakeTokenSelectionWeight;

    /* Symbiotic Snapshot */
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(bytes32 submissionType => Struct.SnapshotTxCountInfo snapshot)) public
        txCountInfo;
    // to track if all partial txs are received
    mapping(uint256 captureTimestamp => mapping(address account => Enum.SubmissionStatus status)) public submissionStatus;

    // staked amount for each prover
    mapping(uint256 captureTimestamp => mapping(address stakeToken => mapping(address prover => uint256 stakeAmount)))
        proverStakeAmounts;
    // staked amount for each vault
    mapping(
        uint256 captureTimestamp
            => mapping(address stakeToken => mapping(address vault => mapping(address prover => uint256 stakeAmount)))
    ) vaultStakeAmounts;

    mapping(uint256 bidId => Struct.SymbioticStakingLock lockInfo) public lockInfo; // note: this does not actually affect L1 Symbiotic stake
    mapping(address stakeToken => mapping(address prover => uint256 locked)) public proverLockedAmounts;

    mapping(uint256 captureTimestamp => address transmitter) public registeredTransmitters; // only one transmitter can submit the snapshot for the same capturetimestamp

    mapping(bytes32 imageId => Struct.EnclaveImage) public enclaveImages;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    /*===================================================================================================================*/
    /*================================================== initializer ====================================================*/
    /*===================================================================================================================*/

    /// @custom:oz-upgrades-unsafe-allow constructor    
    constructor(IProverCallbacks _prover_callback) {
        I_PROVER_CALLBACK = _prover_callback;
    }

    function initialize(
        address _admin,
        address _attestationVerifier,
        address _proofMarketplace,
        address _stakingManager,
        address _rewardDistributor,
        address _feeRewardToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_attestationVerifier != address(0), "SymbioticStaking: attestationVerifier is zero");
        attestationVerifier = _attestationVerifier;
        emit AttestationVerifierSet(_attestationVerifier);

        require(_stakingManager != address(0), "SymbioticStaking: stakingManager is zero");
        stakingManager = _stakingManager;
        emit StakingManagerSet(_stakingManager);

        require(_proofMarketplace != address(0), "SymbioticStaking: proofMarketplace is zero");
        proofMarketplace = _proofMarketplace;
        emit ProofMarketplaceSet(_proofMarketplace);

        require(_rewardDistributor != address(0), "SymbioticStaking: rewardDistributor is zero");
        rewardDistributor = _rewardDistributor;
        emit RewardDistributorSet(_rewardDistributor);

        require(_feeRewardToken != address(0), "SymbioticStaking: feeRewardToken is zero");
        feeRewardToken = _feeRewardToken;
        emit FeeRewardTokenSet(_feeRewardToken);
    }

    /*===================================================================================================================*/
    /*==================================================== external =====================================================*/
    /*===================================================================================================================*/

    /*------------------------------ L1 to L2 submission -----------------------------*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes32 _imageId,
        bytes calldata _vaultSnapshotData,
        bytes calldata _proof
    ) external {
        Struct.VaultSnapshot[] memory _vaultSnapshots = abi.decode(_vaultSnapshotData, (Struct.VaultSnapshot[]));

        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, STAKE_SNAPSHOT_TYPE);

        _verifyProof(_imageId, STAKE_SNAPSHOT_TYPE, _index, _numOfTxs, _captureTimestamp, _vaultSnapshotData, _proof);

        // update Vault and Prover stake amount
        // update rewardPerToken for each vault and prover in SymbioticStakingReward
        _submitVaultSnapshot(_captureTimestamp, _vaultSnapshots);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, STAKE_SNAPSHOT_TYPE);

        // when all chunks of VaultSnapshots are submitted
        if (_index == _numOfTxs - 1) {
            submissionStatus[_captureTimestamp][msg.sender] = Enum.SubmissionStatus.STAKE_SNAPSHOT_DONE;
        }

        emit VaultSnapshotSubmitted(msg.sender, _index, _numOfTxs, _imageId, _vaultSnapshotData, _proof);
    }

    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes32 _imageId,
        bytes memory _slashResultData,
        bytes memory _proof
    ) external {
        Struct.TaskSlashed[] memory _taskSlashed;
        if (_slashResultData.length > 0) {
            _taskSlashed = abi.decode(_slashResultData, (Struct.TaskSlashed[]));
        }

        // Vault Snapshot should be submitted before Slash Result
        require(
            submissionStatus[_captureTimestamp][msg.sender] ==  Enum.SubmissionStatus.STAKE_SNAPSHOT_DONE,
            "Vault Snapshot not submitted"
        );

        _checkTransmitterRegistration(_captureTimestamp);

        _checkValidity(_index, _numOfTxs, _captureTimestamp, SLASH_RESULT_TYPE);

        _verifyProof(_imageId, SLASH_RESULT_TYPE, _index, _numOfTxs, _captureTimestamp, _slashResultData, _proof);

        _updateTxCountInfo(_numOfTxs, _captureTimestamp, SLASH_RESULT_TYPE);

        // there could be no prover slashed
        if (_taskSlashed.length > 0) IStakingManager(stakingManager).onSlashResultSubmission(_taskSlashed);

        // when all chunks of Snapshots are submitted
        if (_index == _numOfTxs - 1) {
            _completeSubmission(_captureTimestamp);
        }

        emit SlashResultSubmitted(msg.sender, _index, _numOfTxs, _imageId, _slashResultData, _proof);
    }

    /*--------------------------- stake lock/unlock start --------------------------*/

    function lockStake(uint256 _bidId, address _prover) external onlyRole(STAKING_MANAGER_ROLE) {
        address _stakeToken = _selectStakeToken(_prover);
        uint256 _amountToLock = amountToLock[_stakeToken];
        require(getProverActiveStakeAmount(_stakeToken, _prover) >= _amountToLock, "Insufficient stake amount");

        lockInfo[_bidId] = Struct.SymbioticStakingLock(_stakeToken, _amountToLock);
        proverLockedAmounts[_stakeToken][_prover] += _amountToLock;

        emit StakeLocked(_bidId, _prover, _stakeToken, _amountToLock);    
        
        I_PROVER_CALLBACK.stakeLockImposedCallback(_prover, _stakeToken, _amountToLock);
    }

    function onTaskCompletion(uint256 _bidId, address _prover, uint256 _feeRewardAmount) external onlyRole(STAKING_MANAGER_ROLE) {
        Struct.SymbioticStakingLock memory lock = lockInfo[_bidId];

        // distribute fee reward
        if (_feeRewardAmount > 0) {
            uint256 currentTimestampIdx = latestConfirmedTimestampIdx();
            uint256 transmitterComission =
                Math.mulDiv(_feeRewardAmount, confirmedTimestamps[currentTimestampIdx].transmitterComissionRate, 1e18);
            uint256 feeRewardRemaining = _feeRewardAmount - transmitterComission;

            // reward the transmitter who created the latestConfirmedTimestamp at the time of task assignment
            ProofMarketplace(proofMarketplace).distributeTransmitterFeeReward(
                confirmedTimestamps[currentTimestampIdx].transmitter, transmitterComission
            );

            // distribute the remaining fee reward
            ISymbioticStakingReward(rewardDistributor).updateFeeReward(lock.stakeToken, _prover, feeRewardRemaining);
        }

        // unlock the stake locked during task assignment
        delete lockInfo[_bidId];
        proverLockedAmounts[lock.stakeToken][_prover] -= amountToLock[lock.stakeToken];

        emit StakeUnlocked(_bidId, _prover, lock.stakeToken, amountToLock[lock.stakeToken]);

        I_PROVER_CALLBACK.stakeLockReleasedCallback(_prover, lock.stakeToken, amountToLock[lock.stakeToken]);
    }

    /*--------------------------- stake lock/unlock end --------------------------*/

    /*------------------------------------- slash ------------------------------------*/

    function slash(Struct.TaskSlashed[] calldata _slashedTasks) external onlyRole(STAKING_MANAGER_ROLE) {
        uint256 len = _slashedTasks.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.SymbioticStakingLock memory lock = lockInfo[_slashedTasks[i].bidId];

            uint256 lockedAmount = lock.amount;

            // unlock the stake locked during task assignment
            proverLockedAmounts[lock.stakeToken][_slashedTasks[i].prover] -= lockedAmount;
            delete lockInfo[_slashedTasks[i].bidId];

            emit TaskSlashed(_slashedTasks[i].bidId, _slashedTasks[i].prover, lock.stakeToken, lockedAmount);

            I_PROVER_CALLBACK.stakeSlashedCallback(_slashedTasks[i].prover, lock.stakeToken, lockedAmount);
        }
    }

    /*===================================================================================================================*/
    /*===================================================== internal ====================================================*/
    /*===================================================================================================================*/

    /*------------------------------- Snapshot Submission ----------------------------*/

    function _checkTransmitterRegistration(uint256 _captureTimestamp) internal {
        if (registeredTransmitters[_captureTimestamp] == address(0)) {
            // once transmitter is registered, other transmitters cannot submit the snapshot for the same capturetimestamp
            registeredTransmitters[_captureTimestamp] = msg.sender;
        } else {
            require(registeredTransmitters[_captureTimestamp] == msg.sender, "Not registered transmitter");
        }
    }

    function _updateTxCountInfo(uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type) internal {
        Struct.SnapshotTxCountInfo memory _snapshot = txCountInfo[_captureTimestamp][_type];

        // update length if 0
        if (_snapshot.numOfTxs == 0) {
            txCountInfo[_captureTimestamp][_type].numOfTxs = _numOfTxs;
        }

        // increase count by 1
        txCountInfo[_captureTimestamp][_type].idxToSubmit += 1;
    }

    function _submitVaultSnapshot(uint256 _captureTimestamp, Struct.VaultSnapshot[] memory _vaultSnapshots) internal {
        for (uint256 i = 0; i < _vaultSnapshots.length; i++) {
            Struct.VaultSnapshot memory _vaultSnapshot = _vaultSnapshots[i];

            // update vault staked amount
            vaultStakeAmounts[_captureTimestamp][_vaultSnapshot.stakeToken][_vaultSnapshot.vault][_vaultSnapshot
                .prover] = _vaultSnapshot.stakeAmount;

            // update prover staked amount
            proverStakeAmounts[_captureTimestamp][_vaultSnapshot.stakeToken][_vaultSnapshot.prover] +=
                _vaultSnapshot.stakeAmount;

            ISymbioticStakingReward(rewardDistributor).onSnapshotSubmission(
                _vaultSnapshot.vault, _vaultSnapshot.prover
            );
        }
    }

    function _completeSubmission(uint256 _captureTimestamp) internal {
        uint256 transmitterComission = _calcTransmitterComissionRate(_captureTimestamp);

        Struct.ConfirmedTimestamp memory confirmedTimestamp =
            Struct.ConfirmedTimestamp(_captureTimestamp, msg.sender, transmitterComission);
        confirmedTimestamps.push(confirmedTimestamp);

        submissionStatus[_captureTimestamp][msg.sender] = Enum.SubmissionStatus.COMPLETE;

        emit SnapshotConfirmed(msg.sender, _captureTimestamp);

        I_PROVER_CALLBACK.symbioticCompleteSnapshotCallback(_captureTimestamp);
    }

    /*===================================================================================================================*/
    /*================================================== external view ==================================================*/
    /*===================================================================================================================*/

    function latestConfirmedTimestamp() public view returns (uint256) {
        uint256 len = confirmedTimestamps.length;
        return len > 0 ? confirmedTimestamps[len - 1].captureTimestamp : 0;
    }

    function latestConfirmedTimestampInfo() external view returns (Struct.ConfirmedTimestamp memory) {
        return confirmedTimestamps[latestConfirmedTimestampIdx()];
    }

    function confirmedTimestampInfo(uint256 _idx) public view returns (Struct.ConfirmedTimestamp memory) {
        return confirmedTimestamps[_idx];
    }

    function latestConfirmedTimestampIdx() public view returns (uint256) {
        uint256 len = confirmedTimestamps.length;
        return len > 0 ? len - 1 : 0;
    }

    function getProverStakeAmount(address _stakeToken, address prover) public view returns (uint256) {
        return proverStakeAmounts[latestConfirmedTimestamp()][_stakeToken][prover];
    }

    /// @notice this can return 0 if nothing was submitted at the timestamp
    function getProverStakeAmountAt(uint256 _captureTimestamp, address _stakeToken, address prover) public view returns (uint256) {
        return proverStakeAmounts[_captureTimestamp][_stakeToken][prover];
    }

    function getProverActiveStakeAmount(address _stakeToken, address prover) public view returns (uint256) {
        uint256 proverStakeAmount = getProverStakeAmount(_stakeToken, prover);
        uint256 proverLockedAmount = proverLockedAmounts[_stakeToken][prover];
        return proverStakeAmount > proverLockedAmount ? proverStakeAmount - proverLockedAmount : 0;
    }

    function getStakeAmount(address _stakeToken, address _vault, address prover) external view returns (uint256) {
        return vaultStakeAmounts[latestConfirmedTimestamp()][_stakeToken][_vault][prover];
    }

    function getStakeTokenList() external view returns (address[] memory) {
        return stakeTokenSet.values();
    }

    function getStakeTokenWeights() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory weights = new uint256[](stakeTokenSet.length());
        for (uint256 i = 0; i < stakeTokenSet.length(); i++) {
            weights[i] = stakeTokenSelectionWeight[stakeTokenSet.at(i)];
        }
        return (stakeTokenSet.values(), weights);
    }

    function isSupportedStakeToken(address _stakeToken) public view returns (bool) {
        return stakeTokenSet.contains(_stakeToken);
    }

    function getSubmissionStatus(uint256 _captureTimestamp, address _transmitter) external view returns (Enum.SubmissionStatus) {
        return submissionStatus[_captureTimestamp][_transmitter];
    }

    /*===================================================================================================================*/
    /*================================================== internal view ==================================================*/
    /*===================================================================================================================*/

    /*------------------------------ Snapshot Submission -----------------------------*/

    function _checkValidity(uint256 _index, uint256 _numOfTxs, uint256 _captureTimestamp, bytes32 _type)
        internal
        view
    {
        require(submissionStatus[_captureTimestamp][msg.sender] != Enum.SubmissionStatus.COMPLETE, "Completed Submission");

        require(_index < _numOfTxs, "Invalid index"); // here we assume enclave submis the correct data
        require(_numOfTxs > 0, "Invalid length");

        // snapshot cannot be submitted before the cooldown period from the last confirmed timestamp (completed snapshot submission)
        require(_captureTimestamp >= (latestConfirmedTimestamp() + submissionCooldown), "Cooldown period not passed");
        require(_captureTimestamp <= block.timestamp, "Invalid timestamp");

        require(_index == txCountInfo[_captureTimestamp][_type].idxToSubmit, "Not idxToSubmit");
    }

    /**
    * @dev Internal function to verify the proof.
    * The function performs the following steps:
    * - Decodes the proof into the signature and attestation data.
    * - Verifies the signature over the provided data using the enclave key.
    * - Verifies the attestation to ensure the enclave key is valid.
    * - Ensures the enclave key used to sign the data matches the one in the attestation.
    * @param _data The parameters used for slashing.
    * @param _proof  The proof that contains the signature on the parameters used for slashing and 
        attestation data which proves that the key used for signing is securely generated within the enclave.
    */
    function _verifyProof(
        bytes32 _imageId,
        bytes32 _type,
        uint256 _index,
        uint256 _numOfTxs,
        uint256 _captureTimestamp,
        bytes memory _data,
        bytes memory _proof
    ) internal view {
        require(enclaveImages[_imageId].PCR0.length != 0, "Image not found");
        bytes memory dataToSign = abi.encode(_type, _index, _numOfTxs, _captureTimestamp, _data);
        (bytes memory _signature, bytes memory _attestationData) = abi.decode(_proof, (bytes, bytes));
        require(_signature.length == SIGNATURE_LENGTH, "M:VP-Signature length mismatch");
        address _enclaveKey = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(keccak256(dataToSign)), _signature);

        (bytes memory attestationSig, IAttestationVerifier.Attestation memory attestation) = abi.decode(
            _attestationData, 
            (bytes, IAttestationVerifier.Attestation)
        );
        IAttestationVerifier(attestationVerifier).verify(attestationSig, attestation);

        address _verifiedKey = _pubKeyToAddress(attestation.enclavePubKey);
        require(_verifiedKey == _enclaveKey, "M:VP-Enclave key mismatch");
        require(getImageId(attestation.PCR0, attestation.PCR1, attestation.PCR2) == _imageId, "M:VP-Invalid image");
    }

    function _pubKeyToAddress(bytes memory _pubKey) internal pure returns (address) {
        require(_pubKey.length == 64, "M:VP-Invalid public key length");
        return address(uint160(uint256(keccak256(_pubKey))));
    }

    function _addEnclaveImage(bytes memory _PCRs) internal {
        (bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) = abi.decode(_PCRs, (bytes, bytes, bytes));
        bytes32 imageId = getImageId(PCR0, PCR1, PCR2);
        require(enclaveImages[imageId].PCR0.length == 0, "Image already exists");

        require(PCR0.length == 48, "Invalid PCR0 length");
        require(PCR1.length == 48, "Invalid PCR1 length");
        require(PCR2.length == 48, "Invalid PCR2 length");

        Struct.EnclaveImage memory enclaveImage = Struct.EnclaveImage(PCR0, PCR1, PCR2);
        enclaveImages[imageId] = enclaveImage;

        emit EnclaveImageAdded(imageId, PCR0, PCR1, PCR2);
    }

    function _removeEnclaveImage(bytes32 _imageId) internal {
        delete enclaveImages[_imageId];

        emit EnclaveImageRemoved(_imageId);
    }

    function _setAttestationVerifier(address _attestationVerifier) internal {
        attestationVerifier = _attestationVerifier;
        emit AttestationVerifierSet(_attestationVerifier);
    }

    function getImageId(bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) public pure returns (bytes32) {
        return keccak256(abi.encode(PCR0, PCR1, PCR2));
    }


    function _calcTransmitterComissionRate(uint256 /* _confirmedTimestamp */) internal view returns (uint256) {
        // TODO: (block.timestamp - _lastConfirmedTimestamp) * X
        return baseTransmitterComissionRate;
    }

    function _currentTransmitter() internal view returns (address) {
        return confirmedTimestamps[latestConfirmedTimestampIdx()].transmitter;
    }

    /*-------------------------------------- Task -------------------------------------*/

    function _selectStakeToken(address _prover) internal view returns (address) {
        require(stakeTokenSelectionWeightSum > 0, "Total weight must be greater than zero");
        require(stakeTokenSet.length() > 0, "No tokens available");

        address[] memory tokens = new address[](stakeTokenSet.length());
        uint256[] memory weights = new uint256[](stakeTokenSet.length());

        uint256 weightSum = stakeTokenSelectionWeightSum;

        uint256 idx = 0;
        uint256 len = stakeTokenSet.length();
        for (uint256 i = 0; i < len; i++) {
            address token = stakeTokenSet.at(i);
            uint256 weight = stakeTokenSelectionWeight[token];
            // ignore if weight is 0
            if (weight > 0) {
                tokens[idx] = token;
                weights[idx] = weight;
                idx++;
            }
        }

        // repeat until a valid token is selected
        while (true) {
            require(idx > 0, "No stakeToken available to lock");

            // random number in range [0, weightSum - 1]
            uint256 random = uint256(
                keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), msg.sender))
            ) % weightSum;

            uint256 cumulativeWeight = 0;
            address selectedToken;

            uint256 i;
            // select token based on weight
            for (i = 0; i < idx; i++) {
                cumulativeWeight += weights[i];
                if (random < cumulativeWeight) {
                    selectedToken = tokens[i];
                    break;
                }
            }

            // check if the selected token has enough active stake amount
            if (getProverActiveStakeAmount(selectedToken, _prover) >= amountToLock[selectedToken]) {
                return selectedToken;
            }

            weightSum -= weights[i];
            tokens[i] = tokens[idx - 1];
            weights[i] = weights[idx - 1];
            idx--; // 배열 크기를 줄임
        }

        // this should be returned
        return address(0);
    }

    function _transmitterComissionRate(uint256 /* _lastConfirmedTimestamp */) internal view returns (uint256) {
        // TODO: implement logic
        return baseTransmitterComissionRate;
    }

    /*------------------------------------ Reward ------------------------------------*/

    /*===================================================================================================================*/
    /*===================================================== admin =======================================================*/
    /*===================================================================================================================*/

    function addStakeToken(address _stakeToken, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.add(_stakeToken), "Token already exists");

        stakeTokenSelectionWeightSum += _weight;
        stakeTokenSelectionWeight[_stakeToken] = _weight;

        emit StakeTokenAdded(_stakeToken, _weight);
    }

    function removeStakeToken(address _stakeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.remove(_stakeToken), "Token does not exist");

        stakeTokenSelectionWeightSum -= stakeTokenSelectionWeight[_stakeToken];
        delete stakeTokenSelectionWeight[_stakeToken];

        emit StakeTokenRemoved(_stakeToken);
    }

    function setAmountToLock(address _stakeToken, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        amountToLock[_stakeToken] = _amount;

        emit AmountToLockSet(_stakeToken, _amount);
    }

    function setStakeTokenSelectionWeight(address _stakeToken, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakeTokenSelectionWeightSum -= stakeTokenSelectionWeight[_stakeToken];
        stakeTokenSelectionWeight[_stakeToken] = _weight;
        stakeTokenSelectionWeightSum += _weight;

        emit StakeTokenSelectionWeightSet(_stakeToken, _weight);
    }

    function setSubmissionCooldown(uint256 _submissionCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        submissionCooldown = _submissionCooldown;

        emit SubmissionCooldownSet(_submissionCooldown);
    }

    /// @dev base transmitter comission rate is in range [0, 1e18)
    function setBaseTransmitterComissionRate(uint256 _baseTransmitterComission) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_baseTransmitterComission < 1e18, "Invalid comission rate");

        baseTransmitterComissionRate = _baseTransmitterComission;

        emit BaseTransmitterComissionRateSet(_baseTransmitterComission);
    }

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        emit StakingManagerSet(_stakingManager);
    }

    function setProofMarketplace(address _proofMarketplace) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proofMarketplace = _proofMarketplace;

        emit ProofMarketplaceSet(_proofMarketplace);
    }

    function setRewardDistributor(address _rewardDistributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardDistributor = _rewardDistributor;

        emit RewardDistributorSet(_rewardDistributor);
    }

    function setFeeRewardToken(address _feeRewardToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeRewardToken = _feeRewardToken;

        emit FeeRewardTokenSet(_feeRewardToken);
    }

    function emergencyWithdraw(address _token, address _to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "zero token address");
        require(_to != address(0), "zero to address");

        IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
    }

    /*===================================================================================================================*/
    /*========================================= BRIDGE ENCLAVE UPDATES ==================================================*/
    /*===================================================================================================================*/

    function addEnclaveImage(bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) external onlyRole(BRIDGE_ENCLAVE_UPDATES_ROLE) {
        _addEnclaveImage(abi.encode(PCR0, PCR1, PCR2));
    }

    function addEnclaveImage(bytes memory PCRs) external onlyRole(BRIDGE_ENCLAVE_UPDATES_ROLE) {
        _addEnclaveImage(PCRs);
    }

    function removeEnclaveImage(bytes32 _imageId) external onlyRole(BRIDGE_ENCLAVE_UPDATES_ROLE) {
        _removeEnclaveImage(_imageId);
    }

    function setAttestationVerifier(address _attestationVerifier) external onlyRole(BRIDGE_ENCLAVE_UPDATES_ROLE) {
        _setAttestationVerifier(_attestationVerifier);
    }

    /*===================================================================================================================*/
    /*==================================================== override =====================================================*/
    /*===================================================================================================================*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
