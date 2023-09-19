// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IProofMarketPlace {
    enum AskState {
        NULL,
        CREATE,
        UNASSIGNED,
        ASSIGNED,
        COMPLETE,
        DEADLINE_CROSSED
    }

    enum SecretType {
        NULL,
        CALLDATA,
        EXTERNAL
    }

    struct Ask {
        bytes32 marketId;
        uint256 reward;
        // the block number by which the ask should be assigned by matching engine
        uint256 expiry;
        // TODO: try to remove one the variable below
        uint256 timeTakenForProofGeneration;
        uint256 deadline;
        address refundAddress;
        bytes proverData;
    }

    struct AskWithState {
        Ask ask;
        AskState state;
        address requester; // TODO: remove this field if not used in future
    }

    struct Task {
        uint256 askId;
        address generator;
    }

    event TreasuryAddressChanged(address indexed oldAddress, address indexed newAddress);
    event GeneratorRegistryChanged(address indexed oldAddress, address indexed newAddress);
    event AskCreated(uint256 indexed askId, bool indexed hasPrivateInputs, bytes secret_data, bytes acl);
    event TaskCreated(uint256 indexed askId, uint256 indexed taskId, address indexed generator, bytes new_acl);
    // TODO: add ask ID also
    event ProofCreated(uint256 indexed askId, uint256 indexed taskId);
    event ProofNotGenerated(uint256 indexed askId, uint256 indexed taskId);

    event MarketPlaceCreated(bytes32 indexed marketId);

    event AskCancelled(uint256 indexed askId);

    function createMarketPlace(bytes calldata marketmetadata, address verifier) external;

    function createAsk(
        Ask calldata ask,
        bool hasPrivateInputs,
        SecretType secretType,
        bytes calldata secret,
        bytes calldata acl
    ) external;

    function verifier(bytes32 marketId) external returns (address);
}
