// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/* Contracts */
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProofMarketplace} from "../../ProofMarketplace.sol";

/* Interfaces */
import {ISymbioticStaking} from "../../interfaces/staking/ISymbioticStaking.sol";
import {ISymbioticStakingReward} from "../../interfaces/staking/ISymbioticStakingReward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* Libraries */
import {Struct} from "../../lib/Struct.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Error} from "../../lib/Error.sol";

contract SymbioticStakingReward is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ISymbioticStakingReward
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    //---------------------------------------- Constant start ----------------------------------------//

    bytes32 public constant SYMBIOTIC_STAKING_ROLE = keccak256("SYMBIOTIC_STAKING_ROLE");

    //---------------------------------------- Constant end ----------------------------------------//

    //---------------------------------------- State Variable start ----------------------------------------//

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    address public proofMarketplace;
    address public symbioticStaking;

    address public feeRewardToken;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1;

    //---------------------------------------- State Variable end ----------------------------------------//

    //---------------------------------------- Mapping start ----------------------------------------//

    // rewardTokens amount per stakeToken
    mapping(address stakeToken => mapping(address rewardToken => mapping(address prover => uint256 rewardPerToken)))
        public rewardPerTokenStored;

    mapping(
        address stakeToken
            => mapping(
                address rewardToken => mapping(address vault => mapping(address prover => uint256 rewardPerTokenPaid))
            )
    ) public rewardPerTokenPaid;

    // reward accrued that the vault can claim
    mapping(address rewardToken => mapping(address vault => uint256 amount)) public rewardAccrued;

    //---------------------------------------- Mapping end ----------------------------------------//

    //---------------------------------------- Init start ----------------------------------------//

    function initialize(address _admin, address _proofMarketplace, address _symbioticStaking, address _feeRewardToken)
        public
        initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ReentrancyGuard_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_proofMarketplace != address(0), Error.ZeroProofMarketplaceAddress());
        proofMarketplace = _proofMarketplace;
        emit ProofMarketplaceSet(_proofMarketplace);

        require(_symbioticStaking != address(0), Error.ZeroSymbioticStakingAddress());
        symbioticStaking = _symbioticStaking;
        emit SymbioticStakingSet(_symbioticStaking);

        require(_feeRewardToken != address(0), Error.ZeroTokenAddress());
        feeRewardToken = _feeRewardToken;
        emit FeeRewardTokenSet(_feeRewardToken);
    }

    //---------------------------------------- Init end ----------------------------------------//

    //---------------------------------------- Reward Claim start ----------------------------------------//
    
    // TODO: Vault -> Claimer address
    /// @notice vault can claim reward calling this function
    function claimReward(address _prover) external nonReentrant {
        address[] memory stakeTokenList = _getStakeTokenList();

        // update rewardPerTokenPaid and rewardAccrued for each vault
        _updateVaultReward(stakeTokenList, _msgSender(), _prover);

        for (uint256 i = 0; i < stakeTokenList.length; i++) {}
        // transfer fee reward to the vault
        uint256 feeRewardAmount = rewardAccrued[feeRewardToken][_msgSender()];
        if (feeRewardAmount > 0) {
            ProofMarketplace(proofMarketplace).transferFeeToken(_msgSender(), feeRewardAmount);
            rewardAccrued[feeRewardToken][_msgSender()] = 0;
        }

        emit RewardClaimed(_prover, feeRewardAmount);
    }

    function _getStakeTokenList() internal view returns (address[] memory) {
        return ISymbioticStaking(symbioticStaking).getStakeTokenList();
    }

    //---------------------------------------- Reward Claim end ----------------------------------------//

    //---------------------------------------- SYMBIOTIC_STAKING_ROLE start ----------------------------------------//

    /// @notice called when fee reward is generated
    /// @dev called by ProofMarketplace when task is completed
    function updateFeeReward(address _stakeToken, address _prover, uint256 _rewardAmount)
        external
        onlyRole(SYMBIOTIC_STAKING_ROLE)
    {
        uint256 proverStakeAmount = _getProverStakeAmount(_stakeToken, _prover);
        if (proverStakeAmount > 0) {
            uint256 rewardPerTokenAdded = Math.mulDiv(_rewardAmount, 1e18, proverStakeAmount);
            rewardPerTokenStored[_stakeToken][feeRewardToken][_prover] += rewardPerTokenAdded;

            emit RewardDistributed(_stakeToken, _prover, _rewardAmount);

            emit RewardPerTokenUpdated(
                _stakeToken,
                feeRewardToken,
                _prover,
                rewardPerTokenStored[_stakeToken][feeRewardToken][_prover]
            );
        }
    }

    function onSnapshotSubmission(address _vault, address _prover) external onlyRole(SYMBIOTIC_STAKING_ROLE) {
        _updateVaultReward(_getStakeTokenList(), _vault, _prover);
    }

    function _getProverStakeAmount(address _stakeToken, address _prover) internal view returns (uint256) {
        return ISymbioticStaking(symbioticStaking).getProverStakeAmount(_stakeToken, _prover);
    }

    /// @dev update rewardPerToken and rewardAccrued for each vault
    function _updateVaultReward(address[] memory _stakeTokenList, address _vault, address _prover) internal {
        uint256 rewardToAdd;
        for (uint256 i = 0; i < _stakeTokenList.length; i++) {
            address stakeToken = _stakeTokenList[i];

            /* fee reward */
            uint256 proverRewardPerTokenStored = rewardPerTokenStored[stakeToken][feeRewardToken][_prover];
            uint256 vaultRewardPerTokenPaid = rewardPerTokenPaid[stakeToken][feeRewardToken][_vault][_prover];

            // update reward accrued for the vault
            rewardToAdd += Math.mulDiv(
                _getVaultStakeAmount(stakeToken, _vault, _prover),
                proverRewardPerTokenStored - vaultRewardPerTokenPaid,
                1e18
            );

            // update rewardPerTokenPaid of the vault
            rewardPerTokenPaid[stakeToken][feeRewardToken][_vault][_prover] = proverRewardPerTokenStored;
        }

        if (rewardToAdd > 0) {
            rewardAccrued[feeRewardToken][_vault] += rewardToAdd;
            emit RewardAccrued(feeRewardToken, _vault, rewardToAdd);
        }
    }

    function _getVaultStakeAmount(address _stakeToken, address _vault, address _prover)
        internal
        view
        returns (uint256)
    {
        return ISymbioticStaking(symbioticStaking).getStakeAmount(_stakeToken, _vault, _prover);
    }

    //---------------------------------------- SYMBIOTIC_STAKING_ROLE end ----------------------------------------//

    //---------------------------------------- Getter start ----------------------------------------//

    function getFeeRewardAccrued(address _vault) external view returns (uint256) {
        return rewardAccrued[feeRewardToken][_vault];
    }

    //---------------------------------------- Getter end ----------------------------------------//

    //---------------------------------------- DEFAULT_ADMIN_ROLE start ----------------------------------------//

    function setProofMarketplace(address _proofMarketplace) public onlyRole(DEFAULT_ADMIN_ROLE) {
        proofMarketplace = _proofMarketplace;
        emit ProofMarketplaceSet(_proofMarketplace);
    }

    function setSymbioticStaking(address _symbioticStaking) public onlyRole(DEFAULT_ADMIN_ROLE) {
        symbioticStaking = _symbioticStaking;
        emit SymbioticStakingSet(_symbioticStaking);
    }

    function setStakingPool(address _symbioticStaking) public onlyRole(DEFAULT_ADMIN_ROLE) {
        symbioticStaking = _symbioticStaking;
        emit StakingPoolSet(_symbioticStaking);
    }

    function setFeeRewardToken(address _feeRewardToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        feeRewardToken = _feeRewardToken;
        emit FeeRewardTokenSet(_feeRewardToken);
    }

    function emergencyWithdraw(address _token, address _to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), Error.ZeroTokenAddress());
        require(_to != address(0), Error.ZeroToAddress());

        IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
    }

    //---------------------------------------- DEFAULT_ADMIN_ROLE end ----------------------------------------//


    //---------------------------------------- override start ----------------------------------------//

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //---------------------------------------- override end ----------------------------------------//
}
