import { randomBytes } from "crypto";
import * as fs from "fs";
import { ethers } from "hardhat";
import { PrivateKey } from "eciesjs";
import { BytesLike } from "ethers";
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

export const BYTES32_ZERO = "0x0000000000000000000000000000000000000000000000000000000000000000";
export const BYTES32_ONE = "0x0000000000000000000000000000000000000000000000000000000000000001";
export const NO_ENCLAVE_ID = "0x99FF0D9125E1FC9531A11262E15AEB2C60509A078C4CC4C64CEFDFB06FF68647";

function getTimestampMs(delay: number = 0): number {
  return new BigNumber(new BigNumber(new Date().valueOf()).plus(delay).toFixed(0)).toNumber();
}

export class MockEnclave {
  public wallet: WalletInfo;
  public pcrs: [BytesLike, BytesLike, BytesLike];

  constructor(pcrs?: [BytesLike, BytesLike, BytesLike]) {
    this.wallet = this.generateWalletInfo();
    if (pcrs) {
      this.pcrs = pcrs;
    } else {
      this.pcrs = ["0x00", "0x00", "0x00"];
    }
  }

  public getMockUnverifiedAttestation(timestamp: number = getTimestampMs()): BytesLike {
    let abiCoder = new ethers.AbiCoder();

    let attestationBytes = abiCoder.encode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256", "uint256"],
      ["0x00", this.wallet.uncompressedPublicKey, this.pcrs[0], this.pcrs[1], this.pcrs[2], "0x00", "0x00", timestamp],
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

  public async signMessage(ethHash: BytesLike): Promise<string> {
    let generateEnclaveSigner = new ethers.Wallet(this.wallet.privateKey);
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
    return MockEnclave.getImageIdFromAttestation(this.getMockUnverifiedAttestation());
  }

  public static getImageIdFromAttestation(attesationData: BytesLike): BytesLike {
    let abicode = new ethers.AbiCoder();

    let decoded = abicode.decode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256", "uint256"],
      attesationData,
    );
    let encoded = ethers.solidityPacked(["bytes", "bytes", "bytes"], [decoded[2], decoded[3], decoded[4]]);
    let digest = ethers.keccak256(encoded);
    return digest;
  }

  public static getPubKeyAndAddressFromAttestation(attesationData: BytesLike): PubkeyAndAddress {
    let abicode = new ethers.AbiCoder();

    let decoded = abicode.decode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256", "uint256"],
      attesationData,
    );
    let pubkey = decoded[1];
    let hash = ethers.keccak256(pubkey);

    const address = "0x" + hash.slice(-40);

    return {
      uncompressedPublicKey: pubkey,
      address,
    };
  }
}

export const MockIVSPCRS: [BytesLike, BytesLike, BytesLike] = ["0x01", "0x02", "0x03"];
export const MockMEPCRS: [BytesLike, BytesLike, BytesLike] = ["0x11", "0x12", "0x13"];
export const MockGeneratorPCRS: [BytesLike, BytesLike, BytesLike] = ["0x21", "0x32", "0x43"];
