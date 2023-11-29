module.exports = {
  configureYulOptimizer: true,
  skipFiles: [
    "../contracts/verifiers/plonk_vk.sol",
    "../contracts/verifiers/transfer_verifier.sol",
    "../contracts/verifiers/verifier_xor2.sol",
    "../contracts/verifiers/zkb_verifier.sol",
  ],
};
