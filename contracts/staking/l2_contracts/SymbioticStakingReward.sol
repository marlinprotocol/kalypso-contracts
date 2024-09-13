// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/* 
    Unlike common staking contracts, this contract is interacted each time snapshot is submitted to Symbiotic Staking,
    which means the state of each vault address will be updated whenvever snapshot is submitted.
*/

contract SymbioticStakingReward is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    // TODO: staking token enability should be pulled from SymbioticStaking contract

    EnumerableSet.AddressSet private _rewardTokenSet;

    //? what should be done when stake is locked?
    // -> just update totalStakeAmount and rewardPerToken?
    // -> does this even affect anything?

    /* 
        rewardToken: Fee Reward, Inflation Reward
        stakeToken: staking token
    */

    // total amount staked for each stakeToken
    // notice: the total amount can be reduced when a job is created and the stake is locked
    mapping(uint256 captureTimestamp => mapping(address stakeToken => uint256 totalStakeAmount)) public
        totalStakeAmounts;
    // reward remaining for each stakeToken
    mapping(address rewardToken => mapping(address stakeToken => uint256 amount)) public rewards;
    // rewardTokens per stakeToken
    mapping(address stakeToken => mapping(address rewardToken => uint256 amount)) public rewardPerTokens;

    // stakeToken supported by each vault should be queried in SymbioticStaking contract
    mapping(uint256 captureTimestamp => mapping(address vault => uint256 amount)) public vaultStakeAmounts;
    // rewardPerToken to store when update
    mapping(uint256 captureTimestamp => mapping(address vault => uint256 rewardPerTokenPaid)) public
        vaultRewardPerTokenPaid;
    // reward accrued that the vault can claim
    mapping(address vault => uint256 rewardAmount) public claimableRewards;

    address public symbioticStaking;

    // TODO: (array) confirmed timestamp
    // probably read from StakingManager

    // TODO: (function) function that updates confirmed timestamp
    // this should be called by StakingManager contract when partial txs are completed

    // TODO: (function) updates reward per token for each submission

    // TODO: claim

    modifier onlySymbioticStaking() {
        require(_msgSender() == symbioticStaking, "Caller is not the staking manager");
        _;
    }

    //-------------------------------- Init start --------------------------------//

    function initialize(address _admin, address _stakingManager) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        symbioticStaking = _stakingManager;
    }

    //-------------------------------- Init end --------------------------------//

    //-------------------------------- StakingManager start --------------------------------//

    /// @notice updates stake amount of a given vault
    /// @notice valid only if the captureTimestamp is pushed into confirmedTimestamp in SymbioticStaking contract when submission is completed
    /// @dev only can be called by SymbioticStaking contract
    // TODO: check how to get _token address (probably gets pulled from SymbioticStkaing contract)
    function updateVaultStakeAmount(uint256 _captureTimestamp, address _token, address _vault, uint256 _amount)
        external
        onlySymbioticStaking
    {
        // TODO: update both of rewardTokens
        // _update(_captureTimestamp, _vault, _token, _amount);

        vaultStakeAmounts[_captureTimestamp][_vault] = _amount;

        // TODO: emit events?
    }

    function getLatestConfirmedTimestamp() external view returns (uint256) {
        return _getLatestConfirmedTimestamp();
    }

    /// @notice returns stakeToken address of a given vault
    function getVaultStakeToken(address _vault) external view returns (address) {
        // TODO: pull from Symbioticstaking contract
    }

    function lockStake(address _stakeToken, uint256 amount) external onlySymbioticStaking {
        // TODO: set function for locking stake
    }

    /// @notice rewardToken amount per stakeToken
    function _rewardPerToken(address _stakeToken, address _rewardToken) internal view returns (uint256) {
        uint256 _latestConfirmedTimestamp = _getLatestConfirmedTimestamp();
        uint256 _totalStakeAmount = totalStakeAmounts[_latestConfirmedTimestamp][_stakeToken];
        uint256 _rewardAmount = rewards[_rewardToken][_stakeToken];

        // TODO: muldiv
        return _totalStakeAmount == 0
            ? rewardPerTokens[_stakeToken][_rewardToken]
            : rewardPerTokens[_stakeToken][_rewardToken] + _rewardAmount.mulDiv(1e18, _totalStakeAmount);
    }

    function _getLatestConfirmedTimestamp() internal view returns (uint256) {
        return ISymbioticStaking(symbioticStaking).lastConfirmedTimestamp();
    }

    //-------------------------------- StakingManager end --------------------------------//

    //-------------------------------- Update start --------------------------------//

    function _update(
        uint256 _captureTimestamp,
        address _vault,
        address _stakeToken,
        address _rewardToken
    ) internal {
        uint256 currentRewardPerToken = _rewardPerToken(_stakeToken, _rewardToken);
        rewardPerTokens[_stakeToken][_rewardToken] = currentRewardPerToken;

        // update reward for each vault
        claimableRewards[_vault] += _pendingReward(_vault, _stakeToken, _rewardToken);
        vaultRewardPerTokenPaid[_captureTimestamp][_vault] = currentRewardPerToken;
    }

    function _pendingReward(address _vault, address _stakeToken, address _rewardToken)
        internal
        view
        returns (uint256)
    {
        uint256 latestConfirmedTimestamp = _getLatestConfirmedTimestamp();
        uint256 rewardPerTokenPaid = vaultRewardPerTokenPaid[latestConfirmedTimestamp][_vault];
        uint256 rewardPerToken = _rewardPerToken(_stakeToken, _rewardToken);

        return (vaultStakeAmounts[latestConfirmedTimestamp][_vault].mulDiv((rewardPerToken - rewardPerTokenPaid), 1e18));
    }

    //-------------------------------- Update end --------------------------------//

    //-------------------------------- Overrides start --------------------------------//

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

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Admin start --------------------------------//
    function setStakingManager(address _stakingManager) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not an admin");

        _setStakingManager(_stakingManager);
        // TODO: emit event
    }

    function _setStakingManager(address _stakingManager) internal {
        symbioticStaking = _stakingManager;
    }

    function _addRewardToken(address _rewardToken) internal {
        _rewardTokenSet.add(_rewardToken);
    }

    function _removeRewardToken(address _rewardToken) internal {
        _rewardTokenSet.remove(_rewardToken);
    }

    //-------------------------------- Admin end --------------------------------//

    //-------------------------------- Getter start --------------------------------//

    function getRewardTokens() external view returns (address[] memory) {
        address[] memory _rewardTokens = new address[](_rewardTokenSet.length());
        for (uint256 i = 0; i < _rewardTokenSet.length(); i++) {
            _rewardTokens[i] = _rewardTokenSet.at(i);
        }
        return _rewardTokens;
    }

    function isSupportedRewardToken(address _rewardToken) public view returns (bool) {
        return _rewardTokenSet.contains(_rewardToken);
    }

    //-------------------------------- Getter end --------------------------------//

    //-------------------------------- JobManager start --------------------------------//

    /// @notice JobManager adds reward to the pool
    function addReward(address _stakeToken, address _rewardToken, uint256 _amount) external {
        // TODO: Only JobManager

        require(_stakeToken != address(0) || _rewardToken != address(0), "zero address");
        require(_amount > 0, "zero amount");

        IERC20(_rewardToken).safeTransferFrom(_msgSender(), address(this), _amount);

        uint256 currentRewardPerToken = _rewardPerToken(_stakeToken, _rewardToken);
        rewardPerTokens[_stakeToken][_rewardToken] = currentRewardPerToken;
    }

    //-------------------------------- JobManager end --------------------------------//
}
