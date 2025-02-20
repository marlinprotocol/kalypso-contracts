import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import {
  Middleware,
  Middleware__factory,
  VaultMock,
  VaultMock__factory,
  InstantSlasherMock,
  InstantSlasherMock__factory,
  VetoSlasherMock,
  VetoSlasherMock__factory,
  MockAttestationVerifier,
  MockAttestationVerifier__factory,
} from "../typechain-types";
import { HDNodeWallet, Signer, SigningKey } from "ethers";
import { BytesLike } from "ethers";
import exp from "constants";

enum SlasherType {
  UNDEFINED = 0,
  NO_SLASH = 1,
  INSTANT_SLASH = 2,
  VETO_SLASH = 3,
}

describe("Middleware Contract Tests", function () {
  let middleware: Middleware;
  let middlewareFactory: Middleware__factory;
  let defaultAddress: Signer;
  let owner: Signer;
  let admin: Signer;
  let otherAccount: Signer;
  let attestationVerifier: MockAttestationVerifier;
  const networkId = ethers.keccak256(ethers.toUtf8Bytes("KalypsoTest"));

  beforeEach(async function () {
    [defaultAddress, owner, admin, otherAccount] = await ethers.getSigners();

    const attestationVerifierFactory = (await ethers.getContractFactory(
      "MockAttestationVerifier",
      owner,
    )) as MockAttestationVerifier__factory;
    attestationVerifier = await (await attestationVerifierFactory.deploy()).waitForDeployment();

    // Deploy Middleware implementation contract
    middlewareFactory = (await ethers.getContractFactory("Middleware", owner)) as Middleware__factory;
    // Deploy proxy without type assertion
    const proxy = await upgrades.deployProxy(
      middlewareFactory.connect(otherAccount),
      [networkId, await attestationVerifier.getAddress(), await admin.getAddress()],
      { initializer: "initialize" },
    );
    await proxy.waitForDeployment();

    // Get the typed contract instance
    middleware = Middleware__factory.connect(await proxy.getAddress(), admin);
  });

  describe("Contract Deployment and Initialization", function () {
    it("Should set the correct admin and network ID upon initialization", async function () {
      expect(await middleware.networkId()).to.equal(networkId);
      expect(await middleware.hasRole(await middleware.DEFAULT_ADMIN_ROLE(), await admin.getAddress())).to.be.true;
      expect(await middleware.getRoleMemberCount(await middleware.DEFAULT_ADMIN_ROLE())).to.equal(1);
      expect(await middleware.getRoleMember(await middleware.DEFAULT_ADMIN_ROLE(), 0)).to.equal(await admin.getAddress());
      expect(await middleware.getNoOfVaults()).to.equal(0);
      expect(await middleware.isSlashingEnabled()).to.equal(false);
    });

    it("Should prevent re-initialization", async function () {
      await expect(
        middleware.initialize(networkId, await attestationVerifier.getAddress(), await admin.getAddress()),
      ).to.be.revertedWithCustomError(middleware, "InvalidInitialization");
    });

    it("Should prevent initialization with zero admin address", async function () {
      const middlewareFactory = (await ethers.getContractFactory("Middleware", owner)) as Middleware__factory;
      await expect(
        upgrades.deployProxy(middlewareFactory, [networkId, await attestationVerifier.getAddress(), ethers.ZeroAddress], {
          initializer: "initialize",
        }),
      ).to.be.revertedWith("M:I-At least one admin necessary");
    });

    it("Should prevent initialization with zero attestation verifier address", async function () {
      const middlewareFactory = (await ethers.getContractFactory("Middleware", owner)) as Middleware__factory;
      await expect(
        upgrades.deployProxy(middlewareFactory, [networkId, ethers.ZeroAddress, await admin.getAddress()], {
          initializer: "initialize",
        }),
      ).to.be.revertedWith("M:I-Attestation verifier cannot be zero address");
    });

    it("Should prevent initialization with zero network ID", async function () {
      const middlewareFactory = (await ethers.getContractFactory("Middleware", owner)) as Middleware__factory;
      await expect(
        upgrades.deployProxy(middlewareFactory, [ethers.ZeroHash, await attestationVerifier.getAddress(), await admin.getAddress()], {
          initializer: "initialize",
        }),
      ).to.be.revertedWith("M:I-Network id cannot be zero");
    });

    it("Deployer should not have admin role", async function () {
      expect(await middleware.hasRole(await middleware.DEFAULT_ADMIN_ROLE(), await defaultAddress.getAddress())).to.be.false;
    });
  });

  describe("Access Control and Role Management", function () {
    it("Only admin can grant roles", async function () {
      const VAULT_CONFIG_SET_ROLE = await middleware.VAULT_CONFIG_SET_ROLE();
      const DEFAULT_ADMIN_ROLE = await middleware.DEFAULT_ADMIN_ROLE();

      await expect(middleware.connect(otherAccount).grantRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress()))
        .to.be.revertedWithCustomError(middleware, "AccessControlUnauthorizedAccount")
        .withArgs(await otherAccount.getAddress(), DEFAULT_ADMIN_ROLE);

      await middleware.connect(admin).grantRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress());
      expect(await middleware.hasRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress())).to.be.true;
    });

    it("Admin cannot be removed if it's the last one", async function () {
      await expect(
        middleware.connect(admin).revokeRole(await middleware.DEFAULT_ADMIN_ROLE(), await admin.getAddress()),
      ).to.be.revertedWith("M:RR-All admins cant be removed");
    });

    it("Admin can grant and revoke roles", async function () {
      await middleware.connect(admin).grantRole(await middleware.DEFAULT_ADMIN_ROLE(), await otherAccount.getAddress());
      expect(await middleware.hasRole(await middleware.DEFAULT_ADMIN_ROLE(), await otherAccount.getAddress())).to.be.true;

      await middleware.connect(admin).revokeRole(await middleware.DEFAULT_ADMIN_ROLE(), await otherAccount.getAddress());
      expect(await middleware.hasRole(await middleware.DEFAULT_ADMIN_ROLE(), await otherAccount.getAddress())).to.be.false;
    });

    it("Admin can grant and revoke multiple roles", async function () {
      const VAULT_CONFIG_SET_ROLE = await middleware.VAULT_CONFIG_SET_ROLE();
      const MIDDLEWARE_CONFIG_SET_ROLE = await middleware.MIDDLEWARE_CONFIG_SET_ROLE();

      await middleware.connect(admin).grantRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress());
      await middleware.connect(admin).grantRole(MIDDLEWARE_CONFIG_SET_ROLE, await otherAccount.getAddress());

      expect(await middleware.hasRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress())).to.be.true;
      expect(await middleware.hasRole(MIDDLEWARE_CONFIG_SET_ROLE, await otherAccount.getAddress())).to.be.true;

      await middleware.connect(admin).revokeRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress());
      await middleware.connect(admin).revokeRole(MIDDLEWARE_CONFIG_SET_ROLE, await otherAccount.getAddress());

      expect(await middleware.hasRole(VAULT_CONFIG_SET_ROLE, await otherAccount.getAddress())).to.be.false;
      expect(await middleware.hasRole(MIDDLEWARE_CONFIG_SET_ROLE, await otherAccount.getAddress())).to.be.false;
    });
  });

  describe("Vault Configuration", function () {
    let vaultAddress: string;
    let slasherAddress: string;
    let collateralAddress: string;

    beforeEach(async function () {
      // Mock Vault
      const VaultMockFactory = (await ethers.getContractFactory("VaultMock", owner)) as VaultMock__factory;
      slasherAddress = ethers.Wallet.createRandom().address;
      collateralAddress = ethers.Wallet.createRandom().address;

      const vault = await VaultMockFactory.deploy(collateralAddress);
      await vault.waitForDeployment();
      await vault.setSlasher(slasherAddress);
      vaultAddress = await vault.getAddress();

      // Grant VAULT_CONFIG_SET_ROLE to admin
      const VAULT_CONFIG_SET_ROLE = await middleware.VAULT_CONFIG_SET_ROLE();
      await middleware.connect(admin).grantRole(VAULT_CONFIG_SET_ROLE, await admin.getAddress());
    });

    it("Should allow admin to enable slashing", async function () {
      expect(await middleware.isSlashingEnabled()).to.equal(false);
      await middleware.connect(admin).setSlashingEnabled(true);
      expect(await middleware.isSlashingEnabled()).to.equal(true);
    });

    it("Should prevent non-admin from enabling slashing", async function () {
      await expect(middleware.connect(otherAccount).setSlashingEnabled(true)).to.be.revertedWith("only admin");
    });

    it("Should allow admin to configure a vault", async function () {
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.INSTANT_SLASH); // SlasherType.INSTANT_SLASH

      const vaultInfo = await middleware.vaultInfo(vaultAddress);
      expect(vaultInfo.slasherType).to.equal(SlasherType.INSTANT_SLASH);
      expect(vaultInfo.collateral).to.equal(collateralAddress);
      expect(vaultInfo.slasher).to.equal(slasherAddress);
      expect(await middleware.vaults(0)).to.equal(vaultAddress);
      expect(await middleware.getNoOfVaults()).to.equal(1);
    });

    it("Should prevent configuring a vault with zero address", async function () {
      await expect(middleware.connect(admin).configureVault(ethers.ZeroAddress, 1)).to.be.revertedWith("M:CV-Vault cannot be zero address");
    });

    it("Should prevent configuring a vault with undefined slasher type", async function () {
      await expect(middleware.connect(admin).configureVault(vaultAddress, 0)).to.be.revertedWith("M:CV-Invalid slasher type");

      await expect(middleware.connect(admin).configureVault(vaultAddress, 4)).to.be.reverted;
    });

    it("Should prevent non-admin from configuring a vault", async function () {
      const VAULT_CONFIG_SET_ROLE = await middleware.VAULT_CONFIG_SET_ROLE();
      await expect(middleware.connect(otherAccount).configureVault(vaultAddress, 1))
        .to.be.revertedWithCustomError(middleware, "AccessControlUnauthorizedAccount")
        .withArgs(await otherAccount.getAddress(), VAULT_CONFIG_SET_ROLE);
    });

    it("Should configure a vault with no slasher", async function () {
      const vault = VaultMock__factory.connect(vaultAddress, owner);
      await vault.setSlasher(ethers.ZeroAddress);
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.NO_SLASH);
      const vaultInfo = await middleware.vaultInfo(vaultAddress);
      expect(vaultInfo.slasherType).to.equal(SlasherType.NO_SLASH);
    });

    it("Should be possible to reconfigure a vault", async function () {
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.INSTANT_SLASH); // SlasherType.INSTANT_SLASH
      let vaultInfo = await middleware.vaultInfo(vaultAddress);
      expect(vaultInfo.slasherType).to.equal(SlasherType.INSTANT_SLASH);

      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.VETO_SLASH); // SlasherType.VETO_SLASH

      vaultInfo = await middleware.vaultInfo(vaultAddress);
      expect(vaultInfo.slasherType).to.equal(SlasherType.VETO_SLASH);
    });
  });

  describe("Network Configuration", function () {
    beforeEach(async function () {
      // Grant MIDDLEWARE_CONFIG_SET_ROLE to admin
      const MIDDLEWARE_CONFIG_SET_ROLE = await middleware.MIDDLEWARE_CONFIG_SET_ROLE();
      await middleware.connect(admin).grantRole(MIDDLEWARE_CONFIG_SET_ROLE, await admin.getAddress());
    });

    it("Should allow admin to update network ID", async function () {
      const newNetworkId = ethers.keccak256(ethers.toUtf8Bytes("KalypsoTest2"));
      await middleware.connect(admin).updateNetworkId(newNetworkId);

      expect(await middleware.networkId()).to.equal(newNetworkId);
    });

    it("Should prevent non-admin from updating network ID", async function () {
      const MIDDLEWARE_CONFIG_SET_ROLE = await middleware.MIDDLEWARE_CONFIG_SET_ROLE();
      await expect(middleware.connect(otherAccount).updateNetworkId(ethers.keccak256(ethers.toUtf8Bytes("KalypsoTest2"))))
        .to.be.revertedWithCustomError(middleware, "AccessControlUnauthorizedAccount")
        .withArgs(await otherAccount.getAddress(), MIDDLEWARE_CONFIG_SET_ROLE);
    });

    it("Should prevent updating network ID with zero value", async function () {
      await expect(middleware.connect(admin).updateNetworkId(ethers.ZeroHash)).to.be.revertedWith("M:UN-Network id cannot be zero");
    });
  });

  describe("Instant Slashing Functions", function () {
    let vaultAddress: string;
    let slasherAddress: string;
    let collateralAddress: string;
    let operatorAddress: string;
    let jobId = 1;
    let amount = ethers.parseEther("100");
    let captureTimestamp = Math.floor(Date.now() / 1000);
    let hints: BytesLike = ethers.keccak256(ethers.toUtf8Bytes("Hints"));
    let enclaveKey: HDNodeWallet = ethers.Wallet.createRandom();
    let proof: BytesLike;

    beforeEach(async function () {
      // Mock Vault
      const VaultMockFactory = (await ethers.getContractFactory("VaultMock", owner)) as VaultMock__factory;
      collateralAddress = ethers.Wallet.createRandom().address;

      const vault = await VaultMockFactory.deploy(collateralAddress);
      await vault.waitForDeployment();
      vaultAddress = await vault.getAddress();

      // Mock Instant Slasher
      const InstantSlasherMockFactory = (await ethers.getContractFactory("InstantSlasherMock", owner)) as InstantSlasherMock__factory;
      const instantSlasher: InstantSlasherMock = await InstantSlasherMockFactory.deploy(vaultAddress);
      await instantSlasher.waitForDeployment();
      slasherAddress = await instantSlasher.getAddress();

      // Link the Vault and Slasher
      await vault.setSlasher(slasherAddress);

      // Operator address
      operatorAddress = ethers.Wallet.createRandom().address;

      // Grant VAULT_CONFIG_SET_ROLE to admin
      const VAULT_CONFIG_SET_ROLE = await middleware.VAULT_CONFIG_SET_ROLE();
      await middleware.connect(admin).grantRole(VAULT_CONFIG_SET_ROLE, await admin.getAddress());

      // Configure Vault in Middleware
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.INSTANT_SLASH); // SlasherType.INSTANT_SLASH

      await middleware.connect(admin).setSlashingEnabled(true);

      // generate proof
      const abiEncoder = new ethers.AbiCoder();
      const slashData = abiEncoder.encode(
        ["uint256", "address", "address", "address", "uint256", "uint256"],
        [jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp],
      );
      const enclaveKeySig = await enclaveKey.signMessage(ethers.getBytes(ethers.keccak256(slashData)));
      const attestationData = abiEncoder.encode(
        ["bytes", "(bytes,bytes,bytes,bytes,uint256)"],
        [
          enclaveKeySig,
          [
            SigningKey.computePublicKey(enclaveKey.publicKey, false).replace("0x04", "0x"),
            "0x12312313",
            "0x12312312312342",
            "0x32145213",
            Date.now(),
          ],
        ],
      );
      proof = abiEncoder.encode(["bytes", "bytes"], [enclaveKeySig, attestationData]);
    });

    it("Should perform instant slash successfully", async function () {
      const instantSlasher = InstantSlasherMock__factory.connect(slasherAddress, owner);

      await expect(
        middleware
          .connect(otherAccount)
          .slash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp, hints, proof),
      )
        .to.emit(instantSlasher, "InstantSlashExecuted")
        .withArgs(networkId, operatorAddress, amount, captureTimestamp, hints);

      const slashInfo = await middleware.slashInfo(vaultAddress, jobId);
      expect(slashInfo.operator).to.equal(operatorAddress);
      expect(slashInfo.amount).to.equal(amount);
    });

    it("Should prevent slashing with invalid slasher type", async function () {
      // Re-configure vault with VETO_SLASH
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.VETO_SLASH); // SlasherType.VETO_SLASH

      await expect(
        middleware
          .connect(otherAccount)
          .slash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp, hints, proof),
      ).to.be.revertedWith("M:S-Invalid slasher type");
    });

    it("Should prevent slashing with zero amount", async function () {
      await expect(
        middleware
          .connect(otherAccount)
          .slash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, 0, captureTimestamp, hints, proof),
      ).to.be.revertedWith("M:S-Invalid amount");
    });

    it("Should prevent double slashing of the same job ID", async function () {
      // Assuming proof verification passes

      await middleware
        .connect(otherAccount)
        .slash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp, hints, proof);

      await expect(
        middleware
          .connect(otherAccount)
          .slash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp, hints, proof),
      ).to.be.revertedWith("M:S-Already slashed");
    });
  });

  describe("Veto Slashing Functions", function () {
    let vaultAddress: string;
    let slasherAddress: string;
    let collateralAddress: string;
    let operatorAddress: string;
    let jobId = 1;
    let amount = ethers.parseEther("100");
    let captureTimestamp = Math.floor(Date.now() / 1000);
    let hints: BytesLike = ethers.keccak256(ethers.toUtf8Bytes("Hints"));
    let enclaveKey: HDNodeWallet = ethers.Wallet.createRandom();
    let proof: BytesLike;

    beforeEach(async function () {
      // Mock Vault
      const VaultMockFactory = (await ethers.getContractFactory("VaultMock", owner)) as VaultMock__factory;
      collateralAddress = ethers.Wallet.createRandom().address;

      const vault = await VaultMockFactory.deploy(collateralAddress);
      await vault.waitForDeployment();
      vaultAddress = await vault.getAddress();

      // Mock Veto Slasher
      const VetoSlasherMockFactory = (await ethers.getContractFactory("VetoSlasherMock", owner)) as VetoSlasherMock__factory;
      const vetoSlasher: VetoSlasherMock = await VetoSlasherMockFactory.deploy();
      await vetoSlasher.waitForDeployment();
      slasherAddress = await vetoSlasher.getAddress();

      // Link the Vault and Slasher
      await vault.setSlasher(slasherAddress);

      // Operator address
      operatorAddress = ethers.Wallet.createRandom().address;

      // Grant VAULT_CONFIG_SET_ROLE to admin
      const VAULT_CONFIG_SET_ROLE = await middleware.VAULT_CONFIG_SET_ROLE();
      await middleware.connect(admin).grantRole(VAULT_CONFIG_SET_ROLE, await admin.getAddress());

      // Configure Vault in Middleware
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.VETO_SLASH); // SlasherType.VETO_SLASH
      await middleware.connect(admin).setSlashingEnabled(true);

      // generate proof
      const abiEncoder = new ethers.AbiCoder();
      const slashData = abiEncoder.encode(
        ["uint256", "address", "address", "address", "uint256", "uint256"],
        [jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp],
      );
      const enclaveKeySig = await enclaveKey.signMessage(ethers.getBytes(ethers.keccak256(slashData)));
      const attestationData = abiEncoder.encode(
        ["bytes", "(bytes,bytes,bytes,bytes,uint256)"],
        [
          enclaveKeySig,
          [
            SigningKey.computePublicKey(enclaveKey.publicKey, false).replace("0x04", "0x"),
            "0x12312313",
            "0x12312312312342",
            "0x32145213",
            Date.now(),
          ],
        ],
      );
      proof = abiEncoder.encode(["bytes", "bytes"], [enclaveKeySig, attestationData]);
    });

    it("Should perform veto slash successfully", async function () {
      const vetoSlasher = VetoSlasherMock__factory.connect(slasherAddress, owner);

      await expect(
        middleware
          .connect(otherAccount)
          .requestSlash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp, hints, proof),
      )
        .to.emit(vetoSlasher, "VetoSlashRequestPlaced")
        .withArgs(networkId, operatorAddress, amount, captureTimestamp, hints);

      const slashInfo = await middleware.slashInfo(vaultAddress, jobId);
      expect(slashInfo.operator).to.equal(operatorAddress);
      expect(slashInfo.amount).to.equal(amount);
    });

    it("Should prevent slashing with invalid slasher type", async function () {
      // Re-configure vault with INSTANT_SLASH
      await middleware.connect(admin).configureVault(vaultAddress, SlasherType.INSTANT_SLASH); // SlasherType.INSTANT_SLASH

      await expect(
        middleware
          .connect(otherAccount)
          .requestSlash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, amount, captureTimestamp, hints, proof),
      ).to.be.revertedWith("M:RS-Invalid slasher type");
    });

    it("Should prevent slashing with zero amount", async function () {
      await expect(
        middleware
          .connect(otherAccount)
          .requestSlash(jobId, await otherAccount.getAddress(), vaultAddress, operatorAddress, 0, captureTimestamp, hints, proof),
      ).to.be.revertedWith("M:RS-Invalid amount");
    });
  });

  describe("Delegates", function () {
    let delegateAddress: string;
    let operator: Signer;

    beforeEach(async function () {
      let delegate: Signer;
      [, , , , , , delegate, operator] = await ethers.getSigners();
      delegateAddress = await delegate.getAddress();
    });

    it("If no delegate is set, operator is the delegate", async function () {
      const operatorAddress = await operator.getAddress();
      expect(await middleware.getDelegate(operatorAddress)).to.equal(operatorAddress);
    });

    it("Anyone can add a delegate", async function () {
      await middleware.connect(operator).setDelegate(delegateAddress);
      const operatorAddress = await operator.getAddress();

      expect(await middleware.getDelegate(operatorAddress)).to.equal(delegateAddress);
    });

    it("Should be possible to update delegate", async function () {
      await middleware.connect(operator).setDelegate(delegateAddress);
      const operatorAddress = await operator.getAddress();

      await middleware.connect(operator).setDelegate(ethers.Wallet.createRandom().address);
      expect(await middleware.getDelegate(operatorAddress)).to.not.equal(delegateAddress);
    });

    it("Should be possible to set delegate to operator address", async function () {
      await middleware.connect(operator).setDelegate(delegateAddress);
      const operatorAddress = await operator.getAddress();

      await middleware.connect(operator).setDelegate(operatorAddress);
      expect(await middleware.getDelegate(operatorAddress)).to.equal(operatorAddress);
    });

    it("Should prevent adding zero address as delegate", async function () {
      await expect(middleware.connect(admin).setDelegate(ethers.ZeroAddress)).to.be.revertedWith("M:SD-Delegate cannot be zero address");
    });
  });
});
