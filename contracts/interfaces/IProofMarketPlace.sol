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

    struct Ask {
        bytes32 marketId;
        bytes proverData;
        uint256 reward;
        // the block number by which the ask should be assigned by matching engine
        uint256 expiry;
        // TODO: try to remove one the variable below
        uint256 timeTakenForProofGeneration;
        uint256 deadline;
    }

    struct AskWithState {
        Ask ask;
        AskState state;
    }

    struct Task {
        uint256 askId;
        address generator;
    }

    event PaymentTokenChanged(IERC20Upgradeable indexed oldToken, IERC20Upgradeable indexed newToken);
    event MarketCreationCostChanged(uint256 indexed oldCost, uint256 indexed newCost);
    event TreasuryAddressChanged(address indexed oldAddress, address indexed newAddress);
    event GeneratorRegistryChanged(address indexed oldAddress, address indexed newAddress);
    event AskCreated(uint256 indexed askId);
    event TaskCreated(uint256 indexed askId, uint256 indexed taskId);
    event ProofCreated(uint256 indexed taskId);

    event MarketPlaceCreated(bytes32 indexed marketId);

    function createMarketPlace(bytes calldata marketmetadata, address verifier) external;

    function createAsk(Ask calldata ask) external;

    function getMarketVerifier(bytes32 marketId) external view returns (address);
}
