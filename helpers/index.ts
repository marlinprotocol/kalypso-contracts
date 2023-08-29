import { randomBytes } from "crypto";
import * as fs from "fs";

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
}

export interface GeneratorData {
  name: string; // some field for him to be identified on chain
  time: number; // in millisecond
  generatorOysterPubKey: string; // should be a hex string here
  computeAllocation: number;
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
