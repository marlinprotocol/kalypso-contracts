// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Contracts */
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/* Interfaces */
import {INativeStaking} from "../../interfaces/staking/INativeStaking.sol";
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* Libraries */
import {Struct} from "../../lib/staking/Struct.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../interfaces/IProverCallbacks.sol";

contract NativeStaking is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    INativeStaking
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    
    IProverCallbacks public immutable I_PROVER_CALLBACK;
    constructor(IProverCallbacks _prover_callback) {
        I_PROVER_CALLBACK = _prover_callback;
    }

    /*===================================================================================================================*/
    /*================================================ state variable ===================================================*/
    /*===================================================================================================================*/

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    EnumerableSet.AddressSet private stakeTokenSet;

    address public stakingManager;
    address public rewardDistributor;

    address public feeRewardToken;

    // gaps in case we new vars in same file

    /* Config */
    uint256 public withdrawalDuration;
    uint256 public stakeTokenSelectionWeightSum;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    /*===================================================================================================================*/
    /*==================================================== mapping ======================================================*/
    /*===================================================================================================================*/

    mapping(address stakeToken => uint256 lockAmount) public amountToLock; // amount of token to lock for each job creation
    mapping(address stakeToken => uint256 weight) public stakeTokenSelectionWeight;

    /* Stake */
    // staked amount for each account
    mapping(address stakeToken => mapping(address account => mapping(address prover => uint256 amount))) public
        stakeAmounts;
    // total staked amounts for each prover
    mapping(address stakeToken => mapping(address prover => uint256 amount)) public proverstakeAmounts;

    mapping(address account => mapping(address prover => Struct.WithdrawalRequest[] withdrawalRequest)) public
        withdrawalRequests;

    /* Locked Stakes */
    mapping(uint256 jobId => Struct.NativeStakingLock lock) public lockInfo;
    mapping(address stakeToken => mapping(address prover => uint256 amount)) public proverLockedAmounts;

    /*===================================================================================================================*/
    /*=================================================== modifier ======================================================*/
    /*===================================================================================================================*/

    modifier onlySupportedToken(address _stakeToken) {
        require(stakeTokenSet.contains(_stakeToken), "Token not supported");
        _;
    }

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    /*===================================================================================================================*/
    /*================================================== initializer ====================================================*/
    /*===================================================================================================================*/

    function initialize(
        address _admin,
        address _stakingManager,
        uint256 _withdrawalDuration,
        address _feeToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_stakingManager != address(0), "NativeStaking: Invalid StakingManager");
        stakingManager = _stakingManager;
        emit StakingManagerSet(_stakingManager);

        withdrawalDuration = _withdrawalDuration;

        require(_feeToken != address(0), "NativeStaking: Invalid Fee Token");
        feeRewardToken = _feeToken;
    }

    /*===================================================================================================================*/
    /*==================================================== external =====================================================*/
    /*===================================================================================================================*/

    /*------------------------------------------------ Native Staking ---------------------------------------------------*/

    // Staker should be able to choose an Prover they want to stake into
    function stake(address _stakeToken, address _prover, uint256 _amount)
        external
        onlySupportedToken(_stakeToken)
        nonReentrant
    {
        // this check can be removed in the future to allow delegatedStake
        require(msg.sender == _prover, "Only prover can stake");

        IERC20(_stakeToken).safeTransferFrom(msg.sender, address(this), _amount);

        stakeAmounts[_stakeToken][msg.sender][_prover] += _amount;
        proverstakeAmounts[_stakeToken][_prover] += _amount;

        emit Staked(msg.sender, _prover, _stakeToken, _amount);

        I_PROVER_CALLBACK.addStakeCallback(_prover, _stakeToken, _amount);
    }

    // TODO
    function requestStakeWithdrawal(address _prover, address _stakeToken, uint256 _amount) external nonReentrant {
        require(getProverActiveStakeAmount(_stakeToken, _prover) >= _amount, "Insufficient stake");

        stakeAmounts[_stakeToken][msg.sender][_prover] -= _amount;
        proverstakeAmounts[_stakeToken][_prover] -= _amount;

        withdrawalRequests[msg.sender][_prover].push(
            Struct.WithdrawalRequest(_stakeToken, _amount, block.timestamp + withdrawalDuration)
        );

        uint256 index = withdrawalRequests[msg.sender][_prover].length - 1;

        emit StakeWithdrawalRequested(msg.sender, _prover, _stakeToken, index, _amount);

        I_PROVER_CALLBACK.intendToReduceStakeCallback(_prover, _stakeToken, _amount);
    }

    function withdrawStake(address _prover, uint256[] calldata _index) external nonReentrant {
        require(msg.sender == _prover, "Only prover can withdraw stake");
        require(_index.length > 0, "Invalid index length");

        for (uint256 i = 0; i < _index.length; i++) {
            Struct.WithdrawalRequest memory request = withdrawalRequests[msg.sender][_prover][_index[i]];

            require(request.withdrawalTime <= block.timestamp, "Withdrawal time not reached");

            require(request.amount > 0, "Invalid withdrawal request");

            withdrawalRequests[msg.sender][_prover][_index[i]].amount = 0;

            IERC20(request.stakeToken).safeTransfer(msg.sender, request.amount);

            emit StakeWithdrawn(msg.sender, _prover, request.stakeToken, _index[i], request.amount);

            I_PROVER_CALLBACK.removeStakeCallback(_prover, request.stakeToken, request.amount);
        }
    }

    /*----------------------------------------------- Staking Manager ---------------------------------------------------*/

    function lockStake(uint256 _jobId, address _prover) external onlyStakingManager {
        address _stakeToken = _selectStakeToken(_prover);
        uint256 _amountToLock = amountToLock[_stakeToken];
        require(getProverActiveStakeAmount(_stakeToken, _prover) >= _amountToLock, "Insufficient stake to lock");

        // lock stake
        lockInfo[_jobId] = Struct.NativeStakingLock(_stakeToken, _amountToLock);
        proverLockedAmounts[_stakeToken][_prover] += _amountToLock;

        emit StakeLocked(_jobId, _prover, _stakeToken, _amountToLock);

        I_PROVER_CALLBACK.stakeLockImposedCallback(_prover, _stakeToken, _amountToLock);
    }

    /// @notice unlock stake and distribute reward
    /// @dev called by StakingManager when job is completed
    function onJobCompletion(
        uint256 _jobId,
        address _prover,
        uint256 /* _feeRewardAmount */
    ) external onlyStakingManager {
        Struct.NativeStakingLock memory lock = lockInfo[_jobId];

        if (lock.amount == 0) return;

        _unlockStake(_jobId, lock.token, _prover, lock.amount);

        emit StakeUnlocked(_jobId, _prover, lock.token, lock.amount);

        I_PROVER_CALLBACK.stakeLockReleasedCallback(_prover, lock.token, lock.amount);
    }

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external onlyStakingManager {
        uint256 len = _slashedJobs.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.NativeStakingLock memory lock = lockInfo[_slashedJobs[i].jobId];

            uint256 lockedAmount = lock.amount;
            if (lockedAmount == 0) continue; // if already slashed

            _unlockStake(_slashedJobs[i].jobId, lock.token, _slashedJobs[i].prover, lockedAmount);
            IERC20(lock.token).safeTransfer(_slashedJobs[i].rewardAddress, lockedAmount);
        
            emit JobSlashed(_slashedJobs[i].jobId, _slashedJobs[i].prover, lock.token, lockedAmount);

            I_PROVER_CALLBACK.stakeSlashedCallback(_slashedJobs[i].prover, lock.token, lockedAmount);
        }
    }

    /*===================================================================================================================*/
    /*===================================================== internal ====================================================*/
    /*===================================================================================================================*/

    function _unlockStake(uint256 _jobId, address _stakeToken, address _prover, uint256 _amount) internal {
        proverLockedAmounts[_stakeToken][_prover] -= _amount;
        delete lockInfo[_jobId];
    }

    /*===================================================================================================================*/
    /*=================================================== public view ===================================================*/
    /*===================================================================================================================*/

    function getProverStakeAmount(address _stakeToken, address _prover) public view returns (uint256) {
        return proverstakeAmounts[_stakeToken][_prover];
    }

    function getProverLockedAmount(address _stakeToken, address _prover) public view returns (uint256) {
        return proverLockedAmounts[_stakeToken][_prover];
    }

    function getProverActiveStakeAmount(address _stakeToken, address _prover) public view returns (uint256) {
        return getProverStakeAmount(_stakeToken, _prover) - getProverLockedAmount(_stakeToken, _prover);
    }

    /*===================================================================================================================*/
    /*================================================== external view ==================================================*/
    /*===================================================================================================================*/

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

    function getStakeAmount(address _stakeToken, address _account, address _prover) external view returns (uint256) {
        return stakeAmounts[_stakeToken][_account][_prover];
    }

    function isSupportedStakeToken(address _stakeToken) public view returns (bool) {
        return stakeTokenSet.contains(_stakeToken);
    }


    /*===================================================================================================================*/
    /*================================================== internal view ==================================================*/
    /*===================================================================================================================*/

    function _selectStakeToken(address _prover) internal view returns(address) {
        require(stakeTokenSelectionWeightSum > 0, "Total weight must be greater than zero");
        require(stakeTokenSet.length() > 0, "No tokens available");

        uint256 len = stakeTokenSet.length();
        address[] memory tokens = new address[](len);
        uint256[] memory weights = new uint256[](len);

        uint256 weightSum = stakeTokenSelectionWeightSum;
        uint256 idx = 0;
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
            uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), msg.sender))) % weightSum;

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
            idx--;  // 배열 크기를 줄임
        }

        // this should be returned
        return address(0);  
    }

    /*===================================================================================================================*/
    /*===================================================== admin =======================================================*/
    /*===================================================================================================================*/

    function addStakeToken(address _token, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.add(_token), "Token already exists");
        
        stakeTokenSelectionWeight[_token] = _weight;
        stakeTokenSelectionWeightSum += _weight;

        emit StakeTokenAdded(_token, _weight);
    }

    function removeStakeToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.remove(_token), "Token does not exist");
        
        delete stakeTokenSelectionWeight[_token];

        emit StakeTokenRemoved(_token);
    }

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        emit StakingManagerSet(_stakingManager);
    }

    function setFeeRewardToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeRewardToken = _token;

        emit FeeRewardTokenSet(_token);
    }

    function setWithdrawalDuration(uint256 _duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawalDuration = _duration;

        emit WithdrawalDurationSet(_duration);
    }

    function setStakeTokenSelectionWeight(address _token, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakeTokenSelectionWeightSum -= stakeTokenSelectionWeight[_token];
        stakeTokenSelectionWeight[_token] = _weight;
        stakeTokenSelectionWeightSum += _weight;

        emit StakeTokenSelectionWeightSet(_token, _weight);
    }

    function setAmountToLock(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        amountToLock[_token] = _amount;

        emit AmountToLockSet(_token, _amount);
    }

    function emergencyWithdraw(address _token, address _to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "zero token address");
        require(_to != address(0), "zero to address");

        IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
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
