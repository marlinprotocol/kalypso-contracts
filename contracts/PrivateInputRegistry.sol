// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ProofMarketPlace.sol";

contract PrivateInputRegistry {
    mapping(uint256 => bytes[]) public privateInputs;
    mapping(uint256 => bool) public complete;
    ProofMarketPlace public immutable proofMarketPlace;

    constructor(ProofMarketPlace _proofMarketPlace) {
        proofMarketPlace = _proofMarketPlace;
    }

    function addPrivateInputs(uint256 askId, bytes calldata privInputs) external {
        require(!complete[askId], "Can't add to completed inputs");
        (, IProofMarketPlace.AskState state) = proofMarketPlace.listOfAsk(askId);

        require(state == IProofMarketPlace.AskState.CREATE, Error.SHOULD_BE_CREATED);
        privateInputs[askId].push(privInputs);
    }

    function completeInputs(uint256 askId) external {
        complete[askId] = true;
    }

    function privateInputLength(uint256 askId) external view returns (uint256) {
        return privateInputs[askId].length;
    }
}
