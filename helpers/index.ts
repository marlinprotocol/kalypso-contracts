import { randomBytes } from "crypto";

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
  let buffer = Buffer.from(hexString, "hex");
  const data = buffer.toString("utf-8");

  return JSON.parse(data) as MarketData;
}

export function generatorDataToBytes(generatorData: GeneratorData): string {
  const data = JSON.stringify(generatorData);
  let buffer = Buffer.from(data, "utf-8");
  return "0x" + bytesToHexString(buffer);
}

export function hexStringToGeneratorData(hexString: string): GeneratorData {
  let buffer = Buffer.from(hexString, "hex");
  const data = buffer.toString("utf-8");

  return JSON.parse(data) as GeneratorData;
}

export * as setup from "./setup";
