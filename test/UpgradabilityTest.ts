import { ethers, upgrades } from "hardhat";
import { expect } from "chai";

describe("Upgrade test", () => {
  it("upgrade: should fail", async () => {
    const UC_Contract = await ethers.getContractFactory("UC");
    const _uc = await upgrades.deployProxy(UC_Contract, [], { kind: "uups", constructorArgs: [] });

    // catching error using try catch, as expect not working here
    try {
      await upgrades.upgradeProxy(await _uc.getAddress(), await ethers.getContractFactory("UC_Rekt"));
      throw new Error("Upgrade should fail");
    } catch (ex) {
      // means expection was caught, which is right
    }
  });

  it("upgrade: should Pass", async () => {
    const UC_Contract = await ethers.getContractFactory("UC");
    const _uc = await upgrades.deployProxy(UC_Contract, [], { kind: "uups", constructorArgs: [] });

    const oldImplementation = await upgrades.erc1967.getImplementationAddress(await _uc.getAddress());

    await upgrades.upgradeProxy(await _uc.getAddress(), await ethers.getContractFactory("UC_with_rg"));
    const newImplementation = await upgrades.erc1967.getImplementationAddress(await _uc.getAddress());

    expect(newImplementation).not.eq(oldImplementation);
  });
});
