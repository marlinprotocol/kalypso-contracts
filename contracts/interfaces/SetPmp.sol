// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ProofMarketplace.sol";

abstract contract SetPmp {
    ProofMarketplace public proofMarketplace;

    function setProofMarketplaceContract(ProofMarketplace _proofMarketplace) external {
        require(address(proofMarketplace) == address(0), "Already Set");
        proofMarketplace = _proofMarketplace;
    }
}
