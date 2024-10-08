// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {INativeStaking} from "../../interfaces/staking/INativeStaking.sol";
import {INativeStakingReward} from "../../interfaces/staking/INativeStakingReward.sol";
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Struct} from "../../lib/staking/Struct.sol";

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

    EnumerableSet.AddressSet private stakeTokenSet;

    address public rewardDistributor;
    address public stakingManager;
    address public feeRewardToken;
    address public inflationRewardToken;

    /* Config */
    uint256 public withdrawalDuration;
    mapping(address stakeToken => uint256 lockAmount) public amountToLock; // amount of token to lock for each job creation
    mapping(address stakeToken => uint256 share) public inflationRewardShare; // 1e18 = 100%

    /* Stake */
    // total staked amounts for each operator
    mapping(address operator => mapping(address stakeToken => uint256 stakeAmounts)) public operatorstakeAmounts;
    // staked amount for each account
    mapping(address account => mapping(address operator => mapping(address stakeToken => uint256 amount))) public
        stakeAmounts;

    mapping(address account => mapping(address operator => Struct.WithdrawalRequest[] withdrawalRequest)) public
        withdrawalRequests;

    /* Locked Stakes */
    mapping(uint256 jobId => Struct.NativeStakingLock lock) public lockInfo;
    mapping(address operator => mapping(address token => uint256 stakeAmounts)) public operatorLockedAmounts;

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
    function stake(address _operator, address _stakeToken, uint256 _amount)
        external
        onlySupportedToken(_stakeToken)
        nonReentrant
    {
        // this check can be removed in the future to allow delegatedStake
        require(msg.sender == _operator, "Only operator can stake");

        IERC20(_stakeToken).safeTransferFrom(msg.sender, address(this), _amount);

        stakeAmounts[msg.sender][_operator][_stakeToken] += _amount;
        operatorstakeAmounts[_operator][_stakeToken] += _amount;

        // INativeStakingReward(rewardDistributor).onStakeUpdate(msg.sender, _stakeToken, _operator);

        emit Staked(msg.sender, _operator, _stakeToken, _amount, block.timestamp);
    }

    // This should update StakingManger's state
    // TODO
    function requestStakeWithdrawal(address _operator, address _stakeToken, uint256 _amount) external nonReentrant {
        require(_getOperatorActiveStakeAmount(_operator, _stakeToken) >= _amount, "Insufficient stake");

        stakeAmounts[msg.sender][_operator][_stakeToken] -= _amount;
        operatorstakeAmounts[_operator][_stakeToken] -= _amount;

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
        address _token = _selectTokenToLock();
        uint256 _amountToLock = amountToLock[_token];
        require(_getOperatorActiveStakeAmount(_operator, _token) >= _amountToLock, "Insufficient stake to lock");

        // lock stake
        lockInfo[_jobId] = Struct.NativeStakingLock(_token, _amountToLock);
        operatorLockedAmounts[_operator][_token] += _amountToLock;

        // TODO: emit event
    }

    /// @notice unlock stake and distribute reward
    /// @dev called by StakingManager when job is completed
    function onJobCompletion(
        uint256 _jobId,
        address _operator,
        uint256 _feeRewardAmount,
        uint256 _inflationRewardAmount
    ) external onlyStakingManager {
        Struct.NativeStakingLock memory lock = lockInfo[_jobId];

        if (lock.amount == 0) return;

        _unlockStake(_jobId, _operator, lock.token, lock.amount);

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

            _unlockStake(_slashedJobs[i].jobId, _slashedJobs[i].operator, lock.token, lockedAmount);
            IERC20(lock.token).safeTransfer(_slashedJobs[i].rewardAddress, lockedAmount);

            // INativeStakingReward(rewardDistributor).onStakeUpdate(msg.sender, lock.token, _slashedJobs[i].operator);
        }
        // TODO: emit event
    }

    function distributeInflationReward(address _operator, uint256 _rewardAmount) external onlyStakingManager {
        if (_rewardAmount == 0) return;

        // _distributeInflationReward(_operator, _rewardAmount);
    }

    /*================================================== external view ==================================================*/

    function getStakeTokenList() external view returns (address[] memory) {
        return stakeTokenSet.values();
    }

    function getStakeAmount(address _account, address _operator, address _stakeToken) external view returns (uint256) {
        return stakeAmounts[_account][_operator][_stakeToken];
    }

    function getOperatorStakeAmount(address _operator, address _token) external view returns (uint256) {
        return _getOperatorStakeAmount(_operator, _token);
    }

    function getOperatorActiveStakeAmount(address _operator, address _token) external view returns (uint256) {
        return _getOperatorActiveStakeAmount(_operator, _token);
    }

    function isSupportedToken(address _token) external view returns (bool) {
        return stakeTokenSet.contains(_token);
    }

    /*===================================================== internal ====================================================*/

    // function _distributeFeeReward(address _stakeToken, address _operator, uint256 _amount) internal {
    //     IERC20(feeRewardToken).safeTransfer(rewardDistributor, _amount);
    //     IRewardDistributor(rewardDistributor).addFeeReward(_stakeToken, _operator, _amount);
    // }

    // function _distributeInflationReward(address _operator, uint256 _rewardAmount) internal {
    //     uint256 len = stakeTokenSet.length();
    //     address[] memory stakeTokens = stakeTokenSet.values();
    //     uint256[] memory rewardAmounts = new uint256[](len);
    //     uint256 inflationRewardAmount;
    //     for (uint256 i = 0; i < len; i++) {
    //         rewardAmounts[i] = _calcInflationRewardAmount(stakeTokens[i], _rewardAmount);
    //         inflationRewardAmount += rewardAmounts[i];
    //     }

    //     IERC20(inflationRewardToken).safeTransfer(rewardDistributor, inflationRewardAmount);
    //     IRewardDistributor(rewardDistributor).addInflationReward(_operator, stakeTokens, rewardAmounts);
    // }

    function _unlockStake(uint256 _jobId, address _operator, address _stakeToken, uint256 _amount) internal {
        operatorLockedAmounts[_operator][_stakeToken] -= _amount;
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

    function _selectTokenToLock() internal view returns (address) {
        require(stakeTokenSet.length() > 0, "No supported token");

        uint256 idx;
        if (stakeTokenSet.length() > 1) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))));
            idx = randomNumber % stakeTokenSet.length();
        }
        return stakeTokenSet.at(idx);
    }

    function _getOperatorStakeAmount(address _operator, address _token) internal view returns (uint256) {
        return operatorstakeAmounts[_operator][_token];
    }

    function _getOperatorActiveStakeAmount(address _operator, address _token) internal view returns (uint256) {
        return operatorstakeAmounts[_operator][_token] - operatorLockedAmounts[_operator][_token];
    }

    /*====================================================== admin ======================================================*/

    function setStakeToken(address _token, bool _isSupported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_isSupported) {
            stakeTokenSet.add(_token);
        } else {
            stakeTokenSet.remove(_token);
        }

        // TODO: emit event
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
