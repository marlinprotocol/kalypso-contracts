// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ProofMarketPlace.sol";
import "./lib/Error.sol";

contract PrivateInputRegistry {
    mapping(uint256 => bytes) public privateInputs;
    ProofMarketPlace public immutable proofMarketPlace;

    constructor(ProofMarketPlace _proofMarketPlace) {
        proofMarketPlace = _proofMarketPlace;
    }

    event AddPrivateInputs(uint256 askId);

    function addPrivateInputs(uint256 askId, bytes calldata privInputs) external {
        require(privateInputs[askId].length == 0, Error.ALREADY_EXISTS);
        (, IProofMarketPlace.AskState state) = proofMarketPlace.listOfAsk(askId);

        require(state == IProofMarketPlace.AskState.CREATE, Error.SHOULD_BE_CREATED);

        // TODO: we are not storing the sender atm, hence anyone can update pricate inputs
        privateInputs[askId] = privInputs;
        emit AddPrivateInputs(askId);
    }
}
