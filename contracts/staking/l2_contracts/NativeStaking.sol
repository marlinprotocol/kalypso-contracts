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
    EnumerableSet.AddressSet private operatorSet;

    mapping(address operator => mapping(address token => OperatorStakeInfo stakeInfo)) public operatorStakeInfo; // stakeAmount, selfStakeAmount
    mapping(address account => mapping(address operator => mapping(address token => uint256 stake))) public
        userStakeInfo;

    mapping(bytes4 sig => bool isSupported) private supportedSignatures;

    modifier onlySupportedToken(address _token) {
        require(tokenSet.contains(_token), "Token not supported");
        _;
    }

    modifier onlySupportedSignature(bytes4 sig) {
        require(supportedSignatures[sig], "Function not supported");
        _;
    }

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

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // Staker should be able to choose an Operator they want to stake into
    // This should update StakingManger's state
    function stake(address _account, address _operator, address _token, uint256 _amount)
        external
        onlySupportedSignature(msg.sig)
        onlySupportedToken(_token)
        nonReentrant
    {
        IERC20(_token).safeTransferFrom(_account, address(this), _amount);

        userStakeInfo[_account][_operator][_token] += _amount;
        operatorStakeInfo[_operator][_token].delegatedStake += _amount;

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

        operatorStakeInfo[_operator][_token].selfStake += _amount;

        emit SelfStaked(_operator, _token, _amount, block.timestamp);
    }

    // This should update StakingManger's state
    function withdrawStake(address operator, address token, uint256 amount) external nonReentrant {
        require(userStakeInfo[msg.sender][operator][token] >= amount, "Insufficient stake");

        // TODO: check locked time

        // TODO: read from staking manager and calculate withdrawable amount

        IERC20(token).safeTransfer(msg.sender, amount);

        userStakeInfo[msg.sender][operator][token] -= amount;
        operatorStakeInfo[operator][token].delegatedStake -= amount;

        emit StakeWithdrawn(msg.sender, operator, token, amount, block.timestamp);
    }

    function withdrawSelfStake(address operator, address token, uint256 amount) external nonReentrant {
        require(operatorStakeInfo[operator][token].selfStake >= amount, "Insufficient selfstake");

        IERC20(token).safeTransfer(operator, amount);

        operatorStakeInfo[operator][token].selfStake -= amount;

        emit SelfStakeWithdrawn(operator, token, amount, block.timestamp);
    }

    /*======================================== Getters ========================================*/

    function getStakeAmount(address _operator, address _token) external view returns (uint256) {}

    function getStakeAmountList(address _operator) external view returns (address[] memory _operators, uint256[] memory _amounts) {}

    function isSupportedToken(address _token) external view returns (bool) {}

    function getDelegatedStake(address _operator, address _token)
        external
        view
        onlySupportedToken(_token)
        returns (uint256)
    {
        return operatorStakeInfo[_operator][_token].delegatedStake;
    }

    //  Returns the list of tokenSet staked by the operator and the amounts
    function getDelegatedStakes(address _operator)
        external
        view
        returns (address[] memory _tokens, uint256[] memory _amounts)
    {
        uint256 len = tokenSet.length();

        for (uint256 i = 0; i < len; i++) {
            _tokens[i] = tokenSet.at(i);
            _amounts[i] = operatorStakeInfo[_operator][_tokens[i]].delegatedStake;
        }
    }

    function getSelfStake(address _operator, address _token)
        external
        view
        onlySupportedToken(_token)
        returns (uint256)
    {
        return operatorStakeInfo[_operator][_token].selfStake;
    }

    function getSelfStakes(address _operator)
        external
        view
        returns (address[] memory _tokens, uint256[] memory _amounts)
    {
        uint256 len = tokenSet.length();

        for (uint256 i = 0; i < len; i++) {
            _tokens[i] = tokenSet.at(i);
            _amounts[i] = operatorStakeInfo[_operator][_tokens[i]].selfStake;
        }
    }

    function getOperatorTotalStake(address _operator, address _token)
        external
        view
        onlySupportedToken(_token)
        returns (uint256)
    {
        OperatorStakeInfo memory _stakeInfo = operatorStakeInfo[_operator][_token];
        return _stakeInfo.delegatedStake + _stakeInfo.selfStake;
    }

    function getOperatorTotalStakes(address _operator)
        external
        view
        returns (address[] memory _tokens, uint256[] memory _amounts)
    {
        uint256 len = tokenSet.length();

        for (uint256 i = 0; i < len; i++) {
            OperatorStakeInfo memory _stakeInfo = operatorStakeInfo[_operator][tokenSet.at(i)];
            _tokens[i] = tokenSet.at(i);
            _amounts[i] = _stakeInfo.delegatedStake + _stakeInfo.selfStake;
        }
    }

    function getTokenTotalStake(address _token) external view onlySupportedToken(_token) returns (uint256) {
        uint256 len = operatorSet.length();
        uint256 totalStake;

        for (uint256 i = 0; i < len; i++) {
            totalStake += operatorStakeInfo[operatorSet.at(i)][_token].delegatedStake
                + operatorStakeInfo[operatorSet.at(i)][_token].selfStake;
        }

        return totalStake;
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

    // TODO: set staking manager
}
