import { randomBytes } from "crypto";
import * as fs from "fs";
import { ethers } from "hardhat";
import { PrivateKey } from "eciesjs";
import { AddressLike, BigNumberish, BytesLike, Signer, SigningKey } from "ethers";
import BigNumber from "bignumber.js";

export * as secret_operations from "./secretInputOperation";

export function generateRandomBytes(length: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    randomBytes(length, (err, buf) => {
      if (err) {
        reject(err);
      } else {
        resolve(buf);
      }
    });
  });
}

export function bytesToHexString(bytes: Buffer): string {
  return bytes.toString("hex");
}

export interface MarketData {
  zkAppName: string;
  proverCode: string;
  verifierCode: string;
  proverOysterImage: string;
  setupCeremonyData: string[];
  inputOuputVerifierUrl: string;
}

// TODO: Update Generator Data
export interface GeneratorData {
  name: string; // some field for him to be identified on chain
}

export function marketDataToBytes(marketData: MarketData): string {
  const data = JSON.stringify(marketData);
  let buffer = Buffer.from(data, "utf-8");
  return "0x" + bytesToHexString(buffer);
}

export function hexStringToMarketData(hexString: string): MarketData {
  let buffer = Buffer.from(hexString.split("x")[1], "hex");
  const data = buffer.toString("utf-8");

  return JSON.parse(data) as MarketData;
}

export function generatorDataToBytes(generatorData: GeneratorData): string {
  return jsonToBytes(generatorData);
}

export function hexStringToGeneratorData(hexString: string): GeneratorData {
  return hexStringToJson(hexString);
}

export function hexStringToJson<M>(hexString: string): M {
  let buffer = Buffer.from(hexString, "hex");
  const data = buffer.toString("utf-8");

  return JSON.parse(data) as M;
}

export function jsonToBytes<M>(json: M): string {
  const data = JSON.stringify(json);
  let buffer = Buffer.from(data, "utf-8");
  return "0x" + bytesToHexString(buffer);
}

export * as setup from "./setup";

// Function to check if a file exists at the given path
export function checkFileExists(filePath: string): boolean {
  try {
    fs.accessSync(filePath, fs.constants.F_OK);
    return true;
  } catch (err) {
    return false;
  }
}

// Function to create a file at the given path if it doesn't exist
export function createFileIfNotExists(filePath: string): void {
  if (!checkFileExists(filePath)) {
    try {
      fs.writeFileSync(filePath, JSON.stringify({ proxy: {}, implementation: {} }, null, 4), "utf-8");
      console.log(`File created at path: ${filePath}`);
    } catch (err) {
      console.error(`Error creating file: ${err}`);
    }
  } else {
    console.log(`File already exists at path: ${filePath}`);
  }
}

export function splitHexString(hexString: string, n: number): string[] {
  if (n <= 0) {
    throw new Error("The value of n should be a positive integer.");
  }

  // Remove any "0x" prefix
  const cleanHexString = hexString.startsWith("0x") ? hexString.slice(2) : hexString;

  // Check if the hexString is valid
  if (!/^([a-fA-F0-9]+)$/.test(cleanHexString)) {
    throw new Error("Invalid hex string.");
  }

  const buffer = Buffer.from(cleanHexString, "hex");
  const chunkSize = Math.ceil(buffer.length / n);

  const chunks: string[] = [];
  for (let i = 0; i < buffer.length; i += chunkSize) {
    // Slice the buffer and convert it back to a hex string with "0x" prefix
    chunks.push("0x" + buffer.slice(i, i + chunkSize).toString("hex"));
  }

  return chunks;
}

export function combineHexStrings(hexStrings: string[]): string {
  // Convert each hex string in the array to a buffer
  const buffers = hexStrings.map((hexString) => {
    const cleanHexString = hexString.startsWith("0x") ? hexString.slice(2) : hexString;

    // Check if each string in the array is a valid hex string
    if (!/^([a-fA-F0-9]+)$/.test(cleanHexString)) {
      throw new Error("Invalid hex string in the array.");
    }

    return Buffer.from(cleanHexString, "hex");
  });

  // Concatenate all the buffers
  const combinedBuffer = Buffer.concat(buffers);

  // Convert the buffer back to a hex string with "0x" prefix
  return "0x" + combinedBuffer.toString("hex");
}

// TODO: if possible find inbuilt functions for this
export function utf8ToHex(str: string): string {
  let hex = "";
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    const n = code.toString(16);
    hex += n.length < 2 ? "0" + n : n;
  }
  return hex;
}

// TODO: if possible find inbuilt functions for this
export function hexToUtf8(hex: string): string {
  let str = "";
  for (let i = 0; i < hex.length; i += 2) {
    const code = parseInt(hex.substr(i, 2), 16);
    str += String.fromCharCode(code);
  }
  return str;
}

export async function skipBlocks(ethersVar: typeof ethers, n: number) {
  await Promise.all([...Array(n)].map(async (x) => await ethersVar.provider.send("evm_mine", [])));
}

export async function skipTime(ethersVar: typeof ethers, t: number) {
  await ethersVar.provider.send("evm_increaseTime", [t]);
  await skipBlocks(ethersVar, 1);
}

export interface PubkeyAndAddress {
  address: string;
  uncompressedPublicKey: string;
}
export interface WalletInfo extends PubkeyAndAddress {
  privateKey: string;
}

// export const BYTES32_ZERO = "0x0000000000000000000000000000000000000000000000000000000000000000";
// export const BYTES32_ONE = "0x0000000000000000000000000000000000000000000000000000000000000001";

export const BYTES48_ZERO =
  "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

export const NO_ENCLAVE_ID = "0xcd2e66bf0b91eeedc6c648ae9335a78d7c9a4ab0ef33612a824d91cdc68a4f21";
// console.log("No enclave id", new MockEnclave().getImageId());

function getTimestampMs(delay: number = 0): number {
  return new BigNumber(new BigNumber(new Date().valueOf()).plus(delay).toFixed(0)).toNumber();
}
export class MockEnclave {
  public wallet: WalletInfo;
  public pcrs: [BytesLike, BytesLike, BytesLike];

  constructor(pcrs?: [BytesLike, BytesLike, BytesLike]) {
    this.wallet = this.generateWalletInfo();
    if (pcrs) {
      pcrs.forEach((pcr, index) => {
        // Assuming BytesLike can be represented as a string in hexadecimal
        // This check assumes pcr.length gives the byte length; if pcr is a string, you may need to adjust the logic
        // For hexadecimal strings, each byte is represented by 2 characters, hence 48 bytes * 2 characters per byte = 96 characters + 2 for the '0x' prefix
        if (pcr.length !== 98) {
          // Adjusted to check for 98 characters including '0x'
          throw new Error(`PCR at index ${index} is not 48 bytes`);
        }
      });
      this.pcrs = pcrs;
    } else {
      this.pcrs = [BYTES48_ZERO, BYTES48_ZERO, BYTES48_ZERO];
    }
  }

  public async getMockUnverifiedAttestation(timestamp: number = getTimestampMs()): Promise<BytesLike> {
    throw new Error("mockUnverified attestation is not supported now");
    let abiCoder = new ethers.AbiCoder();

    let attestationBytes = abiCoder.encode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256"],
      ["0x00", this.wallet.uncompressedPublicKey, this.pcrs[0], this.pcrs[1], this.pcrs[2], timestamp],
    );

    return attestationBytes;
  }

  public async getVerifiedAttestation(
    attestationVerifierEnclave: MockEnclave,
    timestamp: number = getTimestampMs(),
  ): Promise<BytesLike> {
    let abiCoder = new ethers.AbiCoder();

    const EIP712Domain = ethers.keccak256(ethers.toUtf8Bytes("EIP712Domain(string name,string version)"));
    const nameHash = ethers.keccak256(ethers.toUtf8Bytes("marlin.oyster.AttestationVerifier"));
    const versionHash = ethers.keccak256(ethers.toUtf8Bytes("1"));

    const DOMAIN_SEPARATOR = ethers.keccak256(
      abiCoder.encode(["bytes32", "bytes32", "bytes32"], [EIP712Domain, nameHash, versionHash]),
    );

    const ATTESTATION_TYPEHASH = ethers.keccak256(
      ethers.toUtf8Bytes(
        "Attestation(bytes enclavePubKey,bytes PCR0,bytes PCR1,bytes PCR2,uint256 timestampInMilliseconds)",
      ),
    );

    // Encode and hash the attestation structure
    const hashStruct = ethers.keccak256(
      abiCoder.encode(
        ["bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "uint256"],
        [
          ATTESTATION_TYPEHASH,
          ethers.keccak256(ethers.getBytes(this.wallet.uncompressedPublicKey)),
          ethers.keccak256(ethers.getBytes(this.pcrs[0])),
          ethers.keccak256(ethers.getBytes(this.pcrs[1])),
          ethers.keccak256(ethers.getBytes(this.pcrs[2])),
          timestamp,
        ],
      ),
    );

    // Create the digest
    const digest = ethers.keccak256(
      ethers.solidityPacked(["bytes", "bytes32", "bytes32"], ["0x1901", DOMAIN_SEPARATOR, hashStruct]),
    );

    let firstStageSignature = await attestationVerifierEnclave.signMessageWithoutPrefix(ethers.getBytes(digest));

    let attestationBytes = abiCoder.encode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256"],
      [firstStageSignature, this.wallet.uncompressedPublicKey, this.pcrs[0], this.pcrs[1], this.pcrs[2], timestamp],
    );

    return attestationBytes;
  }

  private generateWalletInfo(): WalletInfo {
    // Create a new wallet
    const wallet = ethers.Wallet.createRandom();

    // Extract the private key
    const privateKey = wallet.privateKey;

    // Extract the address
    const address = wallet.address;

    let secret_key: PrivateKey = PrivateKey.fromHex(privateKey);
    let pub_key = "0x" + secret_key.publicKey.uncompressed.toString("hex").substring(2);

    return {
      privateKey,
      address,
      uncompressedPublicKey: pub_key,
    };
  }

  public getPrivateKey(supressWarning = false): string {
    if (!supressWarning) {
      console.warn(
        "Accessing enclave private key is not possible in enclaves. This is mock enclave. You should know why you are accessing key during testing",
      );
    }
    return this.wallet.privateKey;
  }

  public async signMessageWithoutPrefix(ethHash: BytesLike): Promise<string> {
    const generatorEnclaveSigningKey = new SigningKey(this.getPrivateKey(true));
    const signature = generatorEnclaveSigningKey.sign(ethHash).serialized;
    return signature;
  }

  public async signMessage(ethHash: BytesLike): Promise<string> {
    let generateEnclaveSigner = new ethers.Wallet(this.getPrivateKey(true));
    let signature = await generateEnclaveSigner.signMessage(ethHash);

    return signature;
  }

  public getUncompressedPubkey(): string {
    return this.wallet.uncompressedPublicKey;
  }

  public getAddress(): string {
    return this.wallet.address;
  }

  public getImageId(): BytesLike {
    return MockEnclave.getImageId(this.pcrs);
  }

  public getPcrRlp(): BytesLike {
    let abicode = new ethers.AbiCoder();

    let encoded = abicode.encode(["bytes", "bytes", "bytes"], [this.pcrs[0], this.pcrs[1], this.pcrs[2]]);

    return encoded;
  }

  public static getImageIdFromAttestation(attesationData: BytesLike): BytesLike {
    let abicode = new ethers.AbiCoder();

    let decoded = abicode.decode(["bytes", "bytes", "bytes", "bytes", "bytes", "uint256"], attesationData);
    let encoded = ethers.solidityPacked(["bytes", "bytes", "bytes"], [decoded[2], decoded[3], decoded[4]]);
    let digest = ethers.keccak256(encoded);
    return digest;
  }

  public static getImageId(pcrs: [BytesLike, BytesLike, BytesLike]): BytesLike {
    let encoded = ethers.solidityPacked(["bytes", "bytes", "bytes"], [pcrs[0], pcrs[1], pcrs[2]]);
    let digest = ethers.keccak256(encoded);
    return digest;
  }

  public static getPubKeyAndAddressFromAttestation(attesationData: BytesLike): PubkeyAndAddress {
    let abicode = new ethers.AbiCoder();

    let decoded = abicode.decode(["bytes", "bytes", "bytes", "bytes", "bytes", "uint256"], attesationData);
    let pubkey = decoded[1];
    let hash = ethers.keccak256(pubkey);

    const address = "0x" + hash.slice(-40);

    return {
      uncompressedPublicKey: pubkey,
      address,
    };
  }

  public static pubkeyToAddress(pubkey: BytesLike): AddressLike {
    let hash = ethers.keccak256(ethers.getBytes(pubkey));

    const address = "0x" + hash.slice(-40);

    return address;
  }
}

export const MockIVSPCRS: [BytesLike, BytesLike, BytesLike] = [
  "0x" + "00".repeat(47) + "01",
  "0x" + "00".repeat(47) + "02",
  "0x" + "00".repeat(47) + "03",
];
export const MockMEPCRS: [BytesLike, BytesLike, BytesLike] = [
  "0x" + "00".repeat(47) + "11",
  "0x" + "00".repeat(47) + "12",
  "0x" + "00".repeat(47) + "13",
];
export const MockGeneratorPCRS: [BytesLike, BytesLike, BytesLike] = [
  "0x" + "00".repeat(47) + "21",
  "0x" + "00".repeat(47) + "32",
  "0x" + "00".repeat(47) + "43",
];

export const GodEnclavePCRS: [BytesLike, BytesLike, BytesLike] = [
  "0x" + "00".repeat(47) + "65",
  "0x" + "00".repeat(47) + "36",
  "0x" + "00".repeat(47) + "93",
];

export function generatorFamilyId(marketId: BigNumberish): BytesLike {
  let abicode = new ethers.AbiCoder();
  let encoded = abicode.encode(["string", "uint256"], ["gen", marketId]);
  let digest = ethers.keccak256(encoded);
  return digest;
}

export function ivsFamilyId(marketId: BigNumberish): BytesLike {
  let abicode = new ethers.AbiCoder();
  let encoded = abicode.encode(["string", "uint256"], ["ivs", marketId]);
  let digest = ethers.keccak256(encoded);
  return digest;
}

export function matchingEngineFamilyId(meRole: BytesLike): BytesLike {
  let abicode = new ethers.AbiCoder();
  let encoded = abicode.encode(["bytes32"], [meRole]);
  let digest = ethers.keccak256(encoded);
  return digest;
}
