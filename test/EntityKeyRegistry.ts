import { expect } from 'chai';
import { Signer } from 'ethers';
import {
  ethers,
  upgrades,
} from 'hardhat';

import {
  MockEnclave,
  MockProverPCRS,
  proverFamilyId,
} from '../helpers';
import {
  EntityKeyRegistry,
  EntityKeyRegistry__factory,
  Error,
  Error__factory,
  MockAttestationVerifier,
  MockAttestationVerifier__factory,
} from '../typechain-types';

describe("Entity key registry tests", () => {
  let signers: Signer[];
  let admin: Signer;
  let randomUser: Signer;

  let entityKeyRegistry: EntityKeyRegistry;
  let errorLibrary: Error;
  let attestationVerifier: MockAttestationVerifier;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];
    randomUser = signers[5];

    errorLibrary = await new Error__factory(admin).deploy();

    attestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
    const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
    const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
      kind: "uups",
      constructorArgs: [await attestationVerifier.getAddress()],
    });
    entityKeyRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

    const register_role = await entityKeyRegistry.KEY_REGISTER_ROLE();
    await entityKeyRegistry.grantRole(register_role, await admin.getAddress());
    // console.log({ entityKeyRegistry: await entityKeyRegistry.getAddress() });
  });

  it("Update key should revert for address without key_register_role", async () => {
    await expect(entityKeyRegistry.connect(randomUser).updatePubkey(randomUser.getAddress(), 0, "0x", "0x")).to.be.reverted;
  });

  it("Updating with invalid key should revert", async () => {
    await expect(entityKeyRegistry.updatePubkey(randomUser.getAddress(), 1, "0x", "0x")).to.be.revertedWithCustomError(
      entityKeyRegistry,
      "InvalidEnclaveKey",
    );
  });

  it("Update key", async () => {
    const prover_enclave = new MockEnclave(MockProverPCRS);
    await entityKeyRegistry.connect(admin).whitelistImageUsingPcrs(proverFamilyId(1), prover_enclave.getPcrRlp());
    await expect(
      entityKeyRegistry.updatePubkey(
        randomUser.getAddress(),
        0,
        prover_enclave.getUncompressedPubkey(),
        await prover_enclave.getVerifiedAttestation(prover_enclave),
      ),
    )
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await randomUser.getAddress(), 0);
  });

  it("Remove key", async () => {
    // Adding key to registry
    const prover_enclave = new MockEnclave(MockProverPCRS);
    await entityKeyRegistry.connect(admin).whitelistImageUsingPcrs(proverFamilyId(1), prover_enclave.getPcrRlp());
    await expect(
      entityKeyRegistry.updatePubkey(
        randomUser.getAddress(),
        8,
        prover_enclave.getUncompressedPubkey(),
        await prover_enclave.getVerifiedAttestation(prover_enclave),
      ),
    )
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await randomUser.getAddress(), 8);

    // Checking key in registry
    const pub_key = await entityKeyRegistry.pub_key(randomUser.getAddress(), 8);
    expect(pub_key).to.eq(prover_enclave.getUncompressedPubkey());

    // Removing key from registry
    await expect(entityKeyRegistry.removePubkey(randomUser.getAddress(), 9))
      .to.emit(entityKeyRegistry, "RemoveKey")
      .withArgs(await randomUser.getAddress(), 9);
  });

  it("Test Attestation to pubkey and address", async () => {
    let abiCoder = new ethers.AbiCoder();
    let signerToUser = admin;
    //actually it is. 04 has been removed to support keccak hash in contracts
    // 046af9fff439e147a2dfc1e5cf83d63389a74a8cddeb1c18ecc21cb83aca9ed5fa222f055073e4c8c81d3c7a9cf8f2fa2944855b43e6c84ab8e16177d45698c843
    const knownPubkey =
      "0x6af9fff439e147a2dfc1e5cf83d63389a74a8cddeb1c18ecc21cb83aca9ed5fa222f055073e4c8c81d3c7a9cf8f2fa2944855b43e6c84ab8e16177d45698c843";
    const expectedAddress = "0xe511c2c747Fa2F46e8786cbF4d66b015d1FCfaC1";

    let inputBytes = abiCoder.encode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256"],
      ["0x00", knownPubkey, "0x00", "0x00", "0x00", new Date().valueOf()],
    );

    const info = MockEnclave.getPubKeyAndAddressFromAttestation(inputBytes);
    expect(info.uncompressedPublicKey).to.eq(knownPubkey);
    expect(info.address.toLowerCase()).to.eq(expectedAddress.toLowerCase());
  });
});
