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

export * as setup from "./setup";
