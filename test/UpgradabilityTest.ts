import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";

describe("Upgrade test", () => {
  it("upgrade and check", async () => {
    const UC_Contract = await ethers.getContractFactory("UC");
    const _uc = await upgrades.deployProxy(UC_Contract, [], { kind: "uups", constructorArgs: [] });

    const oldImplementation = await upgrades.erc1967.getImplementationAddress(await _uc.getAddress());

    await upgrades.upgradeProxy(await _uc.getAddress(), await ethers.getContractFactory("UC_Rekt"));
    const newImplementation = await upgrades.erc1967.getImplementationAddress(await _uc.getAddress());

    console.log({ oldImplementation, newImplementation });
  });
});
