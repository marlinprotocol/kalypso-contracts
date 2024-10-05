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
import {IJobManager} from "../../interfaces/staking/IJobManager.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Struct} from "../../lib/staking/Struct.sol";

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

    address public jobManager;
    address public symbioticStaking;

    address public feeRewardToken;
    address public inflationRewardToken;

    /* 
        rewardToken: Fee Reward, Inflation Reward
        stakeToken: staking token
    */

    // reward accrued per operator
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 amount))) rewards; // TODO: check if needed

    // rewardTokens amount per stakeToken
    mapping(address stakeToken => mapping(address operator => mapping(address rewardToken => uint256 rewardPerToken)))
        rewardPerTokenStored;

    mapping(
        address vault
            => mapping(
                address stakeToken
                    => mapping(address operator => mapping(address rewardToken => uint256 rewardPerTokenPaid))
            )
    ) rewardPerTokenPaids;

    // reward accrued that the vault can claim
    mapping(address vault => mapping(address rewardToken => uint256 amount)) public rewardAccrued;


    modifier onlySymbioticStaking() {
        require(_msgSender() == symbioticStaking, "Caller is not the staking manager");
        _;
    }

    /*============================================= init =============================================*/
    function initialize(
        address _admin,
        address _jobManager,
        address _symbioticStaking,
        address _feeRewardToken,
        address _inflationRewardToken
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        jobManager = _jobManager;
        symbioticStaking = _symbioticStaking;

        feeRewardToken = _feeRewardToken;
        inflationRewardToken = _inflationRewardToken;
    }

    /*============================================= external functions =============================================*/

    /* ------------------------- reward update ------------------------- */

    /// @notice called when fee reward is generated
    /// @dev triggered from JobManager when job is completed
    function updateFeeReward(address _stakeToken, address _operator, uint256 _rewardAmount)
        external
        onlySymbioticStaking
    {
        rewardPerTokenStored[_stakeToken][_operator][feeRewardToken] +=
            _rewardAmount.mulDiv(1e18, _getOperatorStakeAmount(_operator, _stakeToken));
    }

    /// @notice called when inflation reward is generated
    function updateInflationReward(address _operator, uint256 _rewardAmount) external onlySymbioticStaking {
        address[] memory stakeTokenLost = _getStakeTokenList();
        for (uint256 i = 0; i < stakeTokenLost.length; i++) {
            rewardPerTokenStored[stakeTokenLost[i]][_operator][inflationRewardToken] +=
                _rewardAmount.mulDiv(1e18, _getOperatorStakeAmount(_operator, stakeTokenLost[i]));
        }
    }

    /* ------------------------- symbiotic staking ------------------------- */

    /// @notice update rewardPerToken and rewardAccrued for each vault
    /// @dev called when snapshot is submitted
    function onSnapshotSubmission(Struct.VaultSnapshot[] calldata _vaultSnapshots) external onlySymbioticStaking {
        // TODO: this can be called redundantly as each snapshots can have same operator address
        // update inlfationReward info of each vault
        address[] memory stakeTokenList = _getStakeTokenList();

        for (uint256 i = 0; i < _vaultSnapshots.length; i++) {
            _updatePendingInflationReward(_vaultSnapshots[i].operator);

            _updateVaultInflationReward(stakeTokenList, _vaultSnapshots[i].vault, _vaultSnapshots[i].operator);
        }
    }

    /* ------------------------- reward claim ------------------------- */

    /// @notice vault can claim reward calling this function
    function claimReward(address _operator) external nonReentrant {
        _updatePendingInflationReward(_operator);

        _updateVaultInflationReward(_getStakeTokenList(), _msgSender(), _operator);

        // TODO: check transfer logic
        IERC20(feeRewardToken).safeTransfer(_msgSender(), rewardAccrued[_msgSender()][feeRewardToken]);
        rewardAccrued[_msgSender()][feeRewardToken] = 0;

        IERC20(inflationRewardToken).safeTransfer(_msgSender(), rewardAccrued[_msgSender()][inflationRewardToken]);
        rewardAccrued[_msgSender()][inflationRewardToken] = 0;
    }

    /*============================================= external view functions =============================================*/

    function getVaultRewardAccrued(address _vault) external view returns (uint256 feeReward, uint256 inflationReward) {
        // TODO: this does not include pending inflation reward as it requires states update in JobManager
        return (rewardAccrued[_vault][feeRewardToken], rewardAccrued[_vault][inflationRewardToken]);
    }

    /*============================================= internal functions =============================================*/

    /// @dev update pending inflation reward and update rewardPerTokenStored of the operator
    function _updatePendingInflationReward(address _operator) internal {
        IJobManager(jobManager).updateInflationReward(_operator);
    }

    /// @dev update rewardPerToken and rewardAccrued for each vault
    function _updateVaultInflationReward(address[] memory _stakeTokenList, address _vault, address _operator)
        internal
    {
        for (uint256 i = 0; i < _stakeTokenList.length; i++) {
            address stakeToken = _stakeTokenList[i];
            uint256 operatorRewardPerTokenStored = rewardPerTokenStored[stakeToken][_operator][inflationRewardToken];
            uint256 vaultRewardPerTokenPaid = rewardPerTokenPaids[_vault][stakeToken][_operator][inflationRewardToken];

            rewardAccrued[_vault][inflationRewardToken] += _getVaultStakeAmount(_vault, stakeToken, _operator).mulDiv(
                operatorRewardPerTokenStored - vaultRewardPerTokenPaid, 1e18
            );
            rewardPerTokenPaids[_vault][stakeToken][_operator][inflationRewardToken] = operatorRewardPerTokenStored;
        }
    }

    /*============================================= internal view functions =============================================*/

    function _getStakeTokenList() internal view returns (address[] memory) {
        return ISymbioticStaking(symbioticStaking).getStakeTokenList();
    }

    function _getOperatorStakeAmount(address _operator, address _stakeToken) internal view returns (uint256) {
        return ISymbioticStaking(symbioticStaking).getOperatorStakeAmount(_operator, _stakeToken);
    }

    function _getVaultStakeAmount(address _vault, address _stakeToken, address _operator) internal view returns (uint256) {
        return ISymbioticStaking(symbioticStaking).getStakeAmount(_vault, _stakeToken, _operator);
    }

    /*============================================= internal pure functions =============================================*/

    /*======================================== admin functions ========================================*/

    function setStakingPool(address _symbioticStaking) public onlyRole(DEFAULT_ADMIN_ROLE) {
        symbioticStaking = _symbioticStaking;
    }

    function setJobManager(address _jobManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        jobManager = _jobManager;
    }

    function setFeeRewardToken(address _feeRewardToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        feeRewardToken = _feeRewardToken;
    }

    function setInflationRewardToken(address _inflationRewardToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        inflationRewardToken = _inflationRewardToken;
    }

    /*======================================== overrides ========================================*/

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
