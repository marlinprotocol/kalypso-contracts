// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

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

    EnumerableSet.AddressSet private tokenSet;
    EnumerableSet.AddressSet private operatorSet;

    mapping(address operator => mapping(address token => uint256 amount)) public selfStakes;
    mapping(address operator => mapping(address token => uint256 amount)) public stakes;

    mapping(bytes4 sig => bool isSupported) private supportedSignatures;
    

    modifier onlySupportedToken(address _token) {
        require(tokenSet.contains(_token), "Token not supported");
        _;
    }

    modifier onlySupportedSignature(bytes4 sig) {
        require(supportedSignatures[sig], "Function not supported");
        _;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // Returns the amount of a token staked by the operator
    function stakeOf(address _operator, address _token) external view onlySupportedToken(_token) returns (uint256) {
        return stakes[_operator][_token];
    }

    //  Returns the list of tokenSet staked by the operator and the amounts
    function stakesOf(address _operator) external view returns (address[] memory _tokens, uint256[] memory _amounts) {
        uint256 len = tokenSet.length();

        for (uint256 i = 0; i < len; i++) {
            _tokens[i] = tokenSet.at(i);
            _amounts[i] = stakes[_operator][tokenSet.at(i)];
        }
    }

    // Staker should be able to choose an Operator they want to stake into
    // This should update StakingManger's state
    function stake(address _operator, address _token, uint256 _amount) external onlySupportedSignature(msg.sig) onlySupportedToken(_token) nonReentrant {
        stakes[_operator][_token] += _amount;

        emit Staked(msg.sender, _operator, _token, _amount, block.timestamp);
    }

    // Operators need to self stake tokenSet to be able to receive jobs (jobs will be restricted based on self stake amount)
    // This should update StakingManger's state
    function operatorSelfStake(address _operator, address _token, uint256 _amount) external onlySupportedSignature(msg.sig) onlySupportedToken(_token) nonReentrant {
        stakes[_operator][_token] += _amount;

        emit SelfStaked(_operator, _token, _amount, block.timestamp);
    }

    // This should update StakingManger's state
    function unstake(address operator, address token, uint256 amount) external nonReentrant {
        
    }

    /*======================================== Getters ========================================*/

    // stake of an account for a specific operator
    function getStake(address account, address operator, address token) external view returns (uint256) {
        // TODO
    }

    // stake of an account for all operators
    function getStakes(address account, address token) external view returns (uint256) {
        // TODO
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
}
