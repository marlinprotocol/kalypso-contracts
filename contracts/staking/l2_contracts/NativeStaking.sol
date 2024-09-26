// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INativeStaking} from "../../interfaces/staking/INativeStaking.sol";
import {INativeStakingReward} from "../../interfaces/staking/INativeStakingReward.sol";

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

    address public nativeStakingReward;
    address public stakingManager;

    /*======================================== Config ========================================*/
    
    /* Config */
    mapping(address token => uint256 minStakeamount) public minStakeAmount;
    mapping(address token => uint256 lockAmount) public amountToLock;
    mapping(bytes4 sig => bool isSupported) private supportedSignatures;

    /* Stake */
    // total staked amounts for each operator, includes selfStake and delegatedStake amount
    mapping(address operator => mapping(address token => uint256 stakeAmounts)) public operatorStakedAmounts; 
    // selfstake if account == operator
    mapping(address account => mapping(address operator => mapping(address token => uint256 amount))) public stakedAmounts;
    // total staked amount for each token
    mapping(address token => uint256 amount) public totalStakedAmounts;

    /* Locked Stakes */
    mapping(uint256 jobId => NativeStakingLock) public jobLockedAmounts;
    mapping(address operator => mapping(address token => uint256 stakeAmounts)) public operatorLockedAmounts; // includes selfStake and delegatedStake amount
    // mapping(address token => uint256 amount) public totalLockedAmounts; // TODO: delete

    struct NativeStakingLock {
        address token;
        uint256 amount;
    }

    modifier onlySupportedToken(address _token) {
        require(tokenSet.contains(_token), "Token not supported");
        _;
    }

    modifier onlySupportedSignature(bytes4 sig) {
        require(supportedSignatures[sig], "Function not supported");
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
    function stake(address _account, address _operator, address _token, uint256 _amount)
        external
        onlySupportedSignature(msg.sig)
        onlySupportedToken(_token)
        nonReentrant
    {
        IERC20(_token).safeTransferFrom(_account, address(this), _amount);

        stakedAmounts[_account][_operator][_token] += _amount;
        operatorStakedAmounts[_operator][_token] += _amount;

        // NativeStakingReward contract will read staking amount info from this contract
        // and update reward related states
        INativeStakingReward(nativeStakingReward).update(_account, _token, _operator);

        emit Staked(msg.sender, _operator, _token, _amount, block.timestamp);
    }

    // Operators need to self stake tokenSet to be able to receive jobs (jobs will be restricted based on self stake amount)
    // This should update StakingManger's state
    function operatorSelfStake(address _operator, address _token, uint256 _amount)
        external
        onlySupportedSignature(msg.sig)
        onlySupportedToken(_token)
        nonReentrant
    {
        IERC20(_token).safeTransferFrom(_operator, address(this), _amount);

        operatorStakedAmounts[_operator][_token] += _amount;

        emit SelfStaked(_operator, _token, _amount, block.timestamp);
    }

    // This should update StakingManger's state
    function withdrawStake(address _account, address _operator, address _token, uint256 _amount) external nonReentrant {
        require(stakedAmounts[msg.sender][_operator][_token] >= _amount, "Insufficient stake");

        // TODO: check locked time

        // TODO: read from staking manager and calculate withdrawable amount

        IERC20(_token).safeTransfer(msg.sender, _amount);

        stakedAmounts[msg.sender][_operator][_token] -= _amount;
        operatorStakedAmounts[_operator][_token] -= _amount;

        INativeStakingReward(nativeStakingReward).update(_account, _token, _operator);

        emit StakeWithdrawn(msg.sender, _operator, _token, _amount, block.timestamp);
    }

    function withdrawSelfStake(address operator, address token, uint256 amount) external nonReentrant {
        require(operatorStakedAmounts[operator][token] >= amount, "Insufficient selfstake");

        IERC20(token).safeTransfer(operator, amount);

        operatorStakedAmounts[operator][token] -= amount;

        emit SelfStakeWithdrawn(operator, token, amount, block.timestamp);
    }

    /*======================================== Getters ========================================*/

    function getStakeAmount(address _token) external view returns (uint256) {
        return totalStakedAmounts[_token];
    }

    // TODO: check if needed
    // function getActiveStakeAmount(address _token) public view returns (uint256) {
    //     return totalStakedAmounts[_token] - totalLockedAmounts[_token];
    // }

    function getOperatorActiveStakeAmount(address _operator, address _token) public view returns (uint256) {
        return operatorStakedAmounts[_operator][_token] - operatorLockedAmounts[_operator][_token];
    }

    function isSupportedToken(address _token) external view returns (bool) {
        return tokenSet.contains(_token);
    }

    function isSupportedSignature(bytes4 sig) external view returns (bool) {
        return supportedSignatures[sig];
    }

    /*======================================== Admin ========================================*/

    function addToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenSet.add(token), "Token already exists");
    }

    function removeToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenSet.remove(token), "Token does not exist");
    }

    function setSupportedSignature(bytes4 sig, bool isSupported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedSignatures[sig] = isSupported;
    }

    /*======================================== StakingManager ========================================*/
    function lockStake(uint256 _jobId, address _operator) external onlyStakingManager {
        address _token = _selectLockToken();
        uint256 _amountToLock = amountToLock[_token];
        require(getOperatorActiveStakeAmount(_operator, _token) >= _amountToLock, "Insufficient stake to lock");

        // lock stake
        jobLockedAmounts[_jobId] = NativeStakingLock(_token, _amountToLock);
        operatorLockedAmounts[_operator][_token] += _amountToLock;
        // totalLockedAmounts[_token] += _amountToLock; // TODO: delete

        // TODO: emit event
    }

    function _selectLockToken() internal view returns(address) {
        require(tokenSet.length() > 0, "No supported token");
        
        uint256 idx;
        if (tokenSet.length() > 1) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))));
            idx = randomNumber % tokenSet.length();
        }
        return tokenSet.at(idx);
    }

    function unlockStake(uint256 _jobId) external onlyStakingManager {
        // TODO: consider the case when new pool is added during job

        jobLockedAmounts[_jobId] = NativeStakingLock(address(0), 0);
        // TODO: should "jobId => operator" data be pulled from JobManager to update operatorLockedAmounts?

        // TODO: distribute reward
                

        // TODO: emit event
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
