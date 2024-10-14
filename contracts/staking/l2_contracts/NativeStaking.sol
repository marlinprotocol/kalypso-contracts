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
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* Libraries */
import {Struct} from "../../lib/staking/Struct.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


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

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    EnumerableSet.AddressSet private stakeTokenSet;

    address public rewardDistributor;
    address public stakingManager;
    address public feeRewardToken;
    address public inflationRewardToken;

    // gaps in case we new vars in same file

    /* Config */
    uint256 public withdrawalDuration;
    uint256 public tokenSelectionWeightSum;

    mapping(address stakeToken => uint256 lockAmount) public amountToLock; // amount of token to lock for each job creation
    mapping(address stakeToken => uint256 weight) public tokenSelectionWeight;
    mapping(address stakeToken => uint256 share) public inflationRewardShare; // 1e18 = 100%

    /* Stake */
    // staked amount for each account
    mapping(address stakeToken => mapping(address account => mapping(address operator => uint256 amount))) public
        stakeAmounts;
    // total staked amounts for each operator
    mapping(address stakeToken => mapping(address operator => uint256 amount)) public operatorstakeAmounts;

    mapping(address account => mapping(address operator => Struct.WithdrawalRequest[] withdrawalRequest)) public
        withdrawalRequests;

    uint256[500] private __gap_1;
    /* Locked Stakes */
    mapping(uint256 jobId => Struct.NativeStakingLock lock) public lockInfo;
    mapping(address stakeToken => mapping(address operator => uint256 amount)) public operatorLockedAmounts;

    modifier onlySupportedToken(address _stakeToken) {
        require(stakeTokenSet.contains(_stakeToken), "Token not supported");
        _;
    }

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    /*=================================================== initialize ====================================================*/

    function initialize(
        address _admin,
        address _stakingManager,
        address _rewardDistributor,
        uint256 _withdrawalDuration,
        address _feeToken,
        address _inflationRewardToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        stakingManager = _stakingManager;
        rewardDistributor = _rewardDistributor;
        withdrawalDuration = _withdrawalDuration;
        feeRewardToken = _feeToken;
        inflationRewardToken = _inflationRewardToken;
    }

    /*==================================================== external =====================================================*/

    /*-------------------------------- Native Staking --------------------------------*/

    // Staker should be able to choose an Operator they want to stake into
    function stake(address _stakeToken, address _operator, uint256 _amount)
        external
        onlySupportedToken(_stakeToken)
        nonReentrant
    {
        // this check can be removed in the future to allow delegatedStake
        require(msg.sender == _operator, "Only operator can stake");

        IERC20(_stakeToken).safeTransferFrom(msg.sender, address(this), _amount);

        stakeAmounts[_stakeToken][msg.sender][_operator] += _amount;
        operatorstakeAmounts[_stakeToken][_operator] += _amount;

        // INativeStakingReward(rewardDistributor).onStakeUpdate(msg.sender, _stakeToken, _operator);

        emit Staked(msg.sender, _operator, _stakeToken, _amount, block.timestamp);
    }

    // TODO
    function requestStakeWithdrawal(address _operator, address _stakeToken, uint256 _amount) external nonReentrant {
        require(getOperatorActiveStakeAmount(_stakeToken, _operator) >= _amount, "Insufficient stake");

        stakeAmounts[_stakeToken][msg.sender][_operator] -= _amount;
        operatorstakeAmounts[_stakeToken][_operator] -= _amount;

        withdrawalRequests[msg.sender][_operator].push(
            Struct.WithdrawalRequest(_stakeToken, _amount, block.timestamp + withdrawalDuration)
        );

        // INativeStakingReward(rewardDistributor).onStakeUpdate(msg.sender, _stakeToken, _operator);

        emit StakeWithdrawn(msg.sender, _operator, _stakeToken, _amount, block.timestamp);
    }

    function withdrawStake(address _operator, uint256[] calldata _index) external nonReentrant {
        require(msg.sender == _operator, "Only operator can withdraw stake");

        _withdrawStake(_operator, _index);
        // TODO
    }

    /*-------------------------------- Satking Manager -------------------------------*/

    function lockStake(uint256 _jobId, address _operator) external onlyStakingManager {
        address _stakeToken = _selectStakeToken(_operator);
        uint256 _amountToLock = amountToLock[_stakeToken];
        require(getOperatorActiveStakeAmount(_stakeToken, _operator) >= _amountToLock, "Insufficient stake to lock");

        // lock stake
        lockInfo[_jobId] = Struct.NativeStakingLock(_stakeToken, _amountToLock);
        operatorLockedAmounts[_stakeToken][_operator] += _amountToLock;

        // TODO: emit event
    }

    /// @notice unlock stake and distribute reward
    /// @dev called by StakingManager when job is completed
    function onJobCompletion(
        uint256 _jobId,
        address _operator,
        uint256 _feeRewardAmount,
        uint256 _inflationRewardAmount,
        uint256 /* _inflationRewardTimestampIdx */
    ) external onlyStakingManager {
        Struct.NativeStakingLock memory lock = lockInfo[_jobId];

        if (lock.amount == 0) return;

        _unlockStake(_jobId, lock.token, _operator, lock.amount);

        // distribute fee reward
        // if (_feeRewardAmount > 0) {
        //     _distributeFeeReward(lock.token, _operator, _feeRewardAmount);
        // }

        // if (_inflationRewardAmount > 0) {
        //     _distributeInflationReward(_operator, _inflationRewardAmount);
        // }

        // TODO: emit event
    }

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external onlyStakingManager {
        uint256 len = _slashedJobs.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.NativeStakingLock memory lock = lockInfo[_slashedJobs[i].jobId];

            uint256 lockedAmount = lock.amount;
            if (lockedAmount == 0) continue; // if already slashed

            _unlockStake(_slashedJobs[i].jobId, lock.token, _slashedJobs[i].operator, lockedAmount);
            IERC20(lock.token).safeTransfer(_slashedJobs[i].rewardAddress, lockedAmount);

            // INativeStakingReward(rewardDistributor).onStakeUpdate(msg.sender, lock.token, _slashedJobs[i].operator);
        }
        // TODO: emit event
    }

    function distributeInflationReward(address _operator, uint256 _rewardAmount, uint256 /* _timestampIdx */) external onlyStakingManager {
        if (_rewardAmount == 0) return;

        // _distributeInflationReward(_operator, _rewardAmount);
    }

    /*==================================================== public view ==================================================*/

    function getOperatorStakeAmount(address _stakeToken, address _operator) public view returns (uint256) {
        return operatorstakeAmounts[_stakeToken][_operator];
    }

    function getOperatorActiveStakeAmount(address _stakeToken, address _operator) public view returns (uint256) {
        return getOperatorStakeAmount(_stakeToken, _operator) - getOperatorLockedAmount(_stakeToken, _operator);
    }

    function getOperatorLockedAmount(address _stakeToken, address _operator) public view returns (uint256) {
        return operatorLockedAmounts[_stakeToken][_operator];
    }

    /*================================================== external view ==================================================*/

    function getStakeTokenList() external view returns (address[] memory) {
        return stakeTokenSet.values();
    }

    function getStakeTokenWeights() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory weights = new uint256[](stakeTokenSet.length());
        for (uint256 i = 0; i < stakeTokenSet.length(); i++) {
            weights[i] = tokenSelectionWeight[stakeTokenSet.at(i)];
        }
        return (stakeTokenSet.values(), weights);
    }

    function getStakeAmount(address _stakeToken, address _account, address _operator) external view returns (uint256) {
        return stakeAmounts[_stakeToken][_account][_operator];
    }

    function isSupportedStakeToken(address _stakeToken) public view returns (bool) {
        return stakeTokenSet.contains(_stakeToken);
    }

    /*===================================================== internal ====================================================*/

    function _unlockStake(uint256 _jobId, address _stakeToken, address _operator, uint256 _amount) internal {
        operatorLockedAmounts[_stakeToken][_operator] -= _amount;
        delete lockInfo[_jobId];
    }

    function _withdrawStake(address _operator, uint256[] calldata _index) internal {
        for (uint256 i = 0; i < _index.length; i++) {
            Struct.WithdrawalRequest memory request = withdrawalRequests[msg.sender][_operator][_index[i]];

            require(request.withdrawalTime <= block.timestamp, "Withdrawal time not reached");

            require(request.amount > 0, "Invalid withdrawal request");

            withdrawalRequests[msg.sender][_operator][_index[i]].amount = 0;

            IERC20(request.stakeToken).safeTransfer(msg.sender, request.amount);
        }
    }

    /*============================================== internal view =============================================*/

    function _calcInflationRewardAmount(address _stakeToken, uint256 _inflationRewardAmount)
        internal
        view
        returns (uint256)
    {
        return Math.mulDiv(_inflationRewardAmount, inflationRewardShare[_stakeToken], 1e18);
    }

    function _selectStakeToken(address _operator) internal view returns(address) {
        require(tokenSelectionWeightSum > 0, "Total weight must be greater than zero");
        require(stakeTokenSet.length() > 0, "No tokens available");

        address[] memory tokens = new address[](stakeTokenSet.length());
        uint256[] memory weights = new uint256[](stakeTokenSet.length());

        uint256 weightSum = tokenSelectionWeightSum;
        uint256 idx = 0;
        uint256 len = stakeTokenSet.length();
        for (uint256 i = 0; i < len; i++) {
            address token = stakeTokenSet.at(i);
            uint256 weight = tokenSelectionWeight[token];
            // ignore if weight is 0
            if (weight > 0) {
                tokens[idx] = token;
                weights[idx] = weight;
                idx++;
            }
        }

        // repeat until a valid token is selected
        while (true) {
            require(idx > 0, "No stakeToken available");

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
            if (getOperatorActiveStakeAmount(selectedToken, _operator) >= amountToLock[selectedToken]) {
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

    /*====================================================== admin ======================================================*/

    function addStakeToken(address _token, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.add(_token), "Token already exists");
        
        tokenSelectionWeight[_token] = _weight;
        tokenSelectionWeightSum += _weight;
    }

    function removeStakeToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakeTokenSet.remove(_token), "Token does not exist");
        
        tokenSelectionWeightSum -= inflationRewardShare[_token];
        delete tokenSelectionWeight[_token];
    }

    function setStakeTokenWeight(address _token, uint256 _weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenSelectionWeightSum -= tokenSelectionWeight[_token];
        tokenSelectionWeight[_token] = _weight;
        tokenSelectionWeightSum += _weight;
    }

    function setNativeStakingReward(address _nativeStakingReward) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardDistributor = _nativeStakingReward;

        // TODO: emit event
    }

    function setStakingManager(address _stakingManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingManager = _stakingManager;

        // TODO: emit event
    }

    function setAmountToLock(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        amountToLock[_token] = _amount;

        // TODO: emit event
    }
    /*==================================================== overrides ====================================================*/

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
