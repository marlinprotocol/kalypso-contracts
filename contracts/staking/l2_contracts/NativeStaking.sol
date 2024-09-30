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

import {Struct} from "../../interfaces/staking/lib/Struct.sol";

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



    EnumerableSet.AddressSet private tokenSet;

    address public rewardDistributor;
    address public stakingManager;
    address public feeRewardToken;

    /* Config */
    mapping(address token => uint256 lockAmount) public amountToLock;

    /* Stake */
    // total staked amounts for each operator
    mapping(address operator => mapping(address token => uint256 stakeAmounts)) public operatorStakedAmounts; 
    // staked amount for each account
    mapping(address account => mapping(address operator => mapping(address token => uint256 amount))) public stakedAmounts;

    /* Locked Stakes */
    mapping(uint256 jobId => Struct.NativeStakingLock lock) public jobLockedAmounts;
    mapping(address operator => mapping(address token => uint256 stakeAmounts)) public operatorLockedAmounts;

    modifier onlySupportedToken(address _token) {
        require(tokenSet.contains(_token), "Token not supported");
        _;
    }

    modifier onlyStakingManager() {
        require(msg.sender == stakingManager, "Only StakingManager");
        _;
    }

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // Staker should be able to choose an Operator they want to stake into
    function stake(address _operator, address _token, uint256 _amount)
        external
        onlySupportedToken(_token)
        nonReentrant
    {
        // this check can be removed in the future to allow delegatedStake
        require(msg.sender == _operator, "Only operator can stake");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        stakedAmounts[msg.sender][_operator][_token] += _amount;
        operatorStakedAmounts[_operator][_token] += _amount;

        // NativeStakingReward contract will read staking amount info from this contract
        // and update reward related states
        INativeStakingReward(rewardDistributor).update(msg.sender, _token, _operator);

        emit Staked(msg.sender, _operator, _token, _amount, block.timestamp);
    }

    // This should update StakingManger's state
    function requestStakeWithdrawal(address _operator, address _token, uint256 _amount) external nonReentrant {
        require(getOperatorActiveStakeAmount(_operator, _token) >= _amount, "Insufficient stake");

        stakedAmounts[msg.sender][_operator][_token] -= _amount;
        operatorStakedAmounts[_operator][_token] -= _amount;

        IERC20(_token).safeTransfer(msg.sender, _amount);

        INativeStakingReward(rewardDistributor).update(msg.sender, _token, _operator);

        emit StakeWithdrawn(msg.sender, _operator, _token, _amount, block.timestamp);
    }

    function withdrawStake(address _operator, address _token) external nonReentrant {
        uint256 _amount = stakedAmounts[msg.sender][_operator][_token];
        require(_amount > 0, "No stake to withdraw");
    }

    /*======================================== Getters ========================================*/

    function getOperatorStakeAmount(address _operator, address _token) public view returns (uint256) {
        return operatorStakedAmounts[_operator][_token];
    }

    function getOperatorActiveStakeAmount(address _operator, address _token) public view returns (uint256) {
        return operatorStakedAmounts[_operator][_token] - operatorLockedAmounts[_operator][_token];
    }

    function isSupportedToken(address _token) external view returns (bool) {
        return tokenSet.contains(_token);
    }


    /*======================================== Admin ========================================*/

    function addToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenSet.add(token), "Token already exists");

        // TODO: emit event
    }

    function removeToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenSet.remove(token), "Token does not exist");

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

    /*======================================== StakingManager ========================================*/
    function lockStake(uint256 _jobId, address _operator) external onlyStakingManager {
        address _token = _selectTokenToLock();
        uint256 _amountToLock = amountToLock[_token];
        require(getOperatorActiveStakeAmount(_operator, _token) >= _amountToLock, "Insufficient stake to lock");

        // lock stake
        jobLockedAmounts[_jobId] = Struct.NativeStakingLock(_token, _amountToLock);
        operatorLockedAmounts[_operator][_token] += _amountToLock;

        // TODO: emit event
    }

    /// @notice unlock stake and distribute reward 
    /// @dev called by StakingManager when job is completed
    function unlockStake(uint256 _jobId, address _operator, uint256 _feeRewardAmount) external onlyStakingManager {
        Struct.NativeStakingLock memory lock = jobLockedAmounts[_jobId];

        if(lock.amount == 0) return;

        _unlockStake(_jobId, _operator, lock.token, lock.amount);
        _distributeReward(lock.token, _operator, feeRewardToken, _feeRewardAmount);

        // TODO: emit event
    }

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external onlyStakingManager {
        uint256 len = _slashedJobs.length;
        for (uint256 i = 0; i < len; i++) {
            Struct.NativeStakingLock memory lock = jobLockedAmounts[_slashedJobs[i].jobId];

            uint256 lockedAmount = lock.amount;
            if(lockedAmount == 0) continue; // if already slashed

            _unlockStake(_slashedJobs[i].jobId, _slashedJobs[i].operator, lock.token, lockedAmount);
            IERC20(lock.token).safeTransfer(_slashedJobs[i].rewardAddress, lockedAmount);

            // TODO: emit event
        }
    }

    function _unlockStake(uint256 _jobId, address _operator, address _stakeToken, uint256 _amount) internal {
        operatorLockedAmounts[_operator][_stakeToken] -= _amount;
        delete jobLockedAmounts[_jobId];
    }

    function _distributeReward(address _stakeToken, address _operator, address _rewardToken, uint256 _amount) internal {
        IERC20(_rewardToken).safeTransfer(rewardDistributor, _amount);
        IRewardDistributor(rewardDistributor).addReward(_stakeToken, _operator, _rewardToken, _amount);
    }


    function _selectTokenToLock() internal view returns(address) {
        require(tokenSet.length() > 0, "No supported token");
        
        uint256 idx;
        if (tokenSet.length() > 1) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))));
            idx = randomNumber % tokenSet.length();
        }
        return tokenSet.at(idx);
    }

    /*======================================== Overrides ========================================*/

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
