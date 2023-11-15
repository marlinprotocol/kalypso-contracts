// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IProofMarketPlace {
    struct Market {
        address verifier; // verifier address for the market place
        uint256 slashingPenalty;
        bytes marketmetadata;
    }

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
        uint256 marketId;
        uint256 reward;
        // the block number by which the ask should be assigned by matching engine
        uint256 expiry;
        uint256 timeTakenForProofGeneration;
        uint256 deadline;
        address refundAddress;
        bytes proverData;
    }

    struct AskWithState {
        Ask ask;
        AskState state;
        address requester;
    }

    struct Task {
        uint256 askId;
        address generator;
    }

    event AskCreated(uint256 indexed askId, bool indexed hasPrivateInputs, bytes secret_data, bytes acl);
    event TaskCreated(uint256 indexed askId, uint256 indexed taskId, address indexed generator, bytes new_acl);
    // TODO: add ask ID also
    event ProofCreated(uint256 indexed askId, uint256 indexed taskId, bytes proof);
    event ProofNotGenerated(uint256 indexed askId, uint256 indexed taskId);

    event MarketPlaceCreated(uint256 indexed marketId);

    event AskCancelled(uint256 indexed askId);

    function createMarketPlace(bytes calldata marketmetadata, address verifier, uint256 _slashingPenalty) external;

    function createAsk(
        Ask calldata ask,
        bool hasPrivateInputs,
        SecretType secretType,
        bytes calldata secret,
        bytes calldata acl
    ) external;

    function createAskFor(
        Ask calldata ask,
        bool hasPrivateInputs,
        address payFrom,
        SecretType secretType,
        bytes calldata secret,
        bytes calldata acl
    ) external;

    function verifier(uint256 marketId) external view returns (address);

    function slashingPenalty(uint256 marketId) external view returns (uint256);
}
