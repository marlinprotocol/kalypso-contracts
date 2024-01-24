module.exports = {
  configureYulOptimizer: true,
  skipFiles: [
    "../contracts/verifiers/plonk_vk.sol",
    "../contracts/verifiers/transfer_verifier.sol",
    "../contracts/verifiers/verifier_xor2.sol",
    "../contracts/verifiers/zkb_verifier.sol",
    "../contracts/verifierWrappers/plonk_vk_wrapper.sol",
    "../contracts/verifierWrappers/transfer_verifier_wrapper.sol",
    "../contracts/verifierWrappers/xor2_verifier_wrapper.sol",
    "../contracts/mock/MockToken.sol",
    "../contracts/mock/MockVerifier.sol",
    "../contracts/mock/MockAttestationVerifier.sol",
    "../contracts/periphery/InputAndProofFormatRegistry.sol",
    "../contracts/periphery/AttestationVerifier.sol",
    "../contracts/periphery/interfaces/IVerifier.sol",
    "../contracts/periphery/PriorityLog.sol",
  ],
};
