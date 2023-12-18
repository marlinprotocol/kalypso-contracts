import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";

import * as fs from "fs";
import { utf8ToHex } from "../helpers";
import {
  Error,
  Error__factory,
  EntityKeyRegistry,
  EntityKeyRegistry__factory,
  MockAttestationVerifier__factory,
  MockAttestationVerifier,
} from "../typechain-types";

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
    entityKeyRegistry = await new EntityKeyRegistry__factory(admin).deploy(
      await attestationVerifier.getAddress(),
      await admin.getAddress(),
    );

    const register_role = await entityKeyRegistry.KEY_REGISTER_ROLE();
    await entityKeyRegistry.grantRole(register_role, await admin.getAddress());
    // console.log({ entityKeyRegistry: await entityKeyRegistry.getAddress() });
  });

  it("Update key should revert for invalid admin", async () => {
    await expect(entityKeyRegistry.connect(randomUser).updatePubkey(randomUser.getAddress(), "0x", "0x")).to.be
      .reverted;
  });

  it("Updating with invalid key should revert", async () => {
    await expect(entityKeyRegistry.updatePubkey(randomUser.getAddress(), "0x", "0x")).to.be.revertedWith(
      await errorLibrary.INVALID_ENCLAVE_KEY(),
    );
  });

  // Function always returns true (deployMockContract)
  // it("Should revert for invalid attestation data", async () => {
  //     const generator_publickey = fs.readFileSync("./data/demo_generator/public_key.pem", "utf-8");
  //     const pubBytes = utf8ToHex(generator_publickey);

  //     await expect(entityKeyRegistry.updatePubkey(randomUser.getAddress(), "0x" + pubBytes, "0x"))
  //         .to.be.revertedWith(await errorLibrary.ENCLAVE_KEY_NOT_VERIFIED());
  // });

  it("Update key", async () => {
    const generator_publickey = fs.readFileSync("./data/demo_generator/public_key.pem", "utf-8");
    const pubBytes = utf8ToHex(generator_publickey);
    await expect(entityKeyRegistry.updatePubkey(randomUser.getAddress(), "0x" + pubBytes, "0x"))
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await randomUser.getAddress());
  });

  it("Remove key", async () => {
    // Adding key to registry
    const generator_publickey = fs.readFileSync("./data/demo_generator/public_key.pem", "utf-8");
    const pubBytes = utf8ToHex(generator_publickey);
    await expect(entityKeyRegistry.updatePubkey(randomUser.getAddress(), "0x" + pubBytes, "0x"))
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await randomUser.getAddress());

    // Checking key in registry
    const pub_key = await entityKeyRegistry.pub_key(randomUser.getAddress());
    // console.log({ pub_key: pub_key });
    // console.log({pubBytes: pubBytes });
    expect(pub_key).to.eq("0x" + pubBytes);

    // Removing key from registry
    await expect(entityKeyRegistry.removePubkey(randomUser.getAddress()))
      .to.emit(entityKeyRegistry, "RemoveKey")
      .withArgs(await randomUser.getAddress());
  });
});
